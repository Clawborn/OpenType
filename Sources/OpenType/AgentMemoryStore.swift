import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)

@MainActor
final class AgentMemoryStore: ObservableObject {
    @Published private(set) var entries: [AgentTaskMemory] = []
    @Published private(set) var eventCount = 0
    @Published private(set) var ownerProfile: OwnerProfile = .empty
    @Published private(set) var insights: MemoryInsights = .empty
    @Published private(set) var learnedPreferences: MemoryInsights = .empty
    @Published private(set) var lastAutomaticProfileEventCount = 0
    @Published private(set) var databaseReady = false
    @Published private(set) var databaseStatus = "正在打开本地记忆库…"

    let databaseURL: URL

    private let maximumEntries: Int
    private let legacyJSONURL: URL?
    private var database: OpaquePointer?

    init(
        fileURL: URL? = nil,
        maximumEntries: Int = 300
    ) {
        self.maximumEntries = maximumEntries

        if let fileURL {
            databaseURL = fileURL
            legacyJSONURL = nil
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            let directory = support.appendingPathComponent(
                "OpenType",
                isDirectory: true
            )
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            databaseURL = directory.appendingPathComponent("memory.sqlite3")
            legacyJSONURL = directory.appendingPathComponent("agent-memory.json")
        }

        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        openDatabase()
        guard databaseReady else { return }
        createSchema()
        migrateLegacyJSONIfNeeded()
        backfillMissingEmbeddings(limit: 200)
        reloadPublishedState()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func record(_ event: MemoryEvent) {
        guard insert(event, source: "voice") else { return }
        refreshAfterEventChanges(writeSnapshot: true)
    }

    func add(_ entry: AgentTaskMemory) {
        record(
            MemoryEvent(
                id: entry.id,
                createdAt: entry.createdAt,
                mode: .instruction,
                applicationName: entry.applicationName,
                bundleIdentifier: nil,
                rawTranscript: entry.request,
                effectiveInput: entry.request,
                selectedContext: entry.referencePreview,
                result: entry.outcome
            )
        )
    }

    func importHistoryIfNeeded(_ historyEntries: [HistoryEntry]) {
        guard databaseReady, metadataValue(for: "history_imported") != "1" else {
            return
        }

        execute("BEGIN IMMEDIATE TRANSACTION;")
        for entry in historyEntries.reversed() {
            let event = MemoryEvent(
                id: entry.id,
                createdAt: entry.createdAt,
                mode: entry.mode,
                applicationName: entry.applicationName,
                bundleIdentifier: nil,
                rawTranscript: entry.transcript,
                effectiveInput: entry.transcript,
                selectedContext: entry.contextPreview,
                result: entry.result
            )
            if !containsEquivalent(event) {
                _ = insert(event, source: "history_migration")
            }
        }
        setMetadata("1", for: "history_imported")
        execute("COMMIT;")
        refreshAfterEventChanges(writeSnapshot: true)
    }

    @discardableResult
    func updateOwnerProfile(_ updated: OwnerProfile) -> Bool {
        guard databaseReady else { return false }
        var profile = updated
        profile.updatedAt = Date()

        let sql = """
        INSERT INTO owner_profile (
            id, identity_and_work, communication_style, important_terms,
            preferred_language, updated_at
        ) VALUES (1, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            identity_and_work = excluded.identity_and_work,
            communication_style = excluded.communication_style,
            important_terms = excluded.important_terms,
            preferred_language = excluded.preferred_language,
            updated_at = excluded.updated_at;
        """
        guard let statement = prepare(sql) else { return false }
        defer { sqlite3_finalize(statement) }
        bind(profile.identityAndWork, at: 1, to: statement)
        bind(profile.communicationStyle, at: 2, to: statement)
        bind(profile.importantTerms, at: 3, to: statement)
        bind(profile.preferredLanguage.rawValue, at: 4, to: statement)
        sqlite3_bind_double(
            statement,
            5,
            profile.updatedAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        )
        guard sqlite3_step(statement) == SQLITE_DONE else {
            reportDatabaseError("Unable to save owner profile")
            return false
        }
        ownerProfile = profile
        return true
    }

    @discardableResult
    func refreshOwnerProfileIfNeeded(
        enabled: Bool,
        personalDictionary: [String]
    ) -> Bool {
        guard enabled, databaseReady else { return false }
        let currentBucket = eventCount / OwnerProfileAutoUpdater.updateInterval
        let savedBucket = Int(
            metadataValue(for: "automatic_owner_profile_bucket") ?? "0"
        ) ?? 0
        guard currentBucket > savedBucket else { return false }

        // Automatic learning is a separate, lower-confidence layer. It must
        // never rewrite the user-confirmed "About Me" fields or become a
        // global output instruction.
        guard persistLearnedPreferences(insights) else { return false }
        learnedPreferences = insights

        setMetadata(
            String(currentBucket),
            for: "automatic_owner_profile_bucket"
        )
        setMetadata(
            String(eventCount),
            for: "automatic_owner_profile_event_count"
        )
        lastAutomaticProfileEventCount = eventCount
        return true
    }

    var automaticProfileUpdateDue: Bool {
        let currentBucket = eventCount / OwnerProfileAutoUpdater.updateInterval
        let savedBucket = Int(
            metadataValue(for: "automatic_owner_profile_bucket") ?? "0"
        ) ?? 0
        return currentBucket > savedBucket
    }

    var nextAutomaticProfileEventCount: Int {
        let nextBucket = eventCount / OwnerProfileAutoUpdater.updateInterval + 1
        return max(OwnerProfileAutoUpdater.updateInterval, nextBucket * OwnerProfileAutoUpdater.updateInterval)
    }

    func clear() {
        guard databaseReady else { return }
        execute("BEGIN IMMEDIATE TRANSACTION;")
        execute("DELETE FROM memory_events;")
        execute("DELETE FROM memory_snapshots;")
        setMetadata("0", for: "automatic_owner_profile_bucket")
        setMetadata("0", for: "automatic_owner_profile_event_count")
        execute("COMMIT;")
        entries = []
        eventCount = 0
        insights = .empty
        learnedPreferences = .empty
        lastAutomaticProfileEventCount = 0
        execute(
            "DELETE FROM memory_metadata WHERE key = 'learned_preferences_v1';"
        )
    }

    func entriesForPrompt(
        maximumEntries: Int = 12,
        maximumCharacters: Int = 14_000
    ) -> [AgentTaskMemory] {
        guard maximumEntries > 0, maximumCharacters > 0 else { return [] }

        var selected: [AgentTaskMemory] = []
        var characterCount = 0

        for entry in entries.prefix(maximumEntries) {
            let nextCount = characterCount + entry.estimatedPromptCharacters
            if !selected.isEmpty, nextCount > maximumCharacters {
                break
            }
            selected.append(entry)
            characterCount = nextCount
        }

        return Array(selected.reversed())
    }

    func memoriesForPrompt(
        query: String,
        selectedContext: String?,
        applicationName: String,
        maximumEntries: Int = 8,
        maximumCharacters: Int = 14_000
    ) -> [AgentTaskMemory] {
        guard maximumEntries > 0, maximumCharacters > 0 else { return [] }

        let retrieved = LocalMemoryRetriever.retrieve(
            from: loadIndexedEvents(limit: 2_000),
            query: query,
            selectedContext: selectedContext,
            applicationName: applicationName,
            maximumEntries: maximumEntries
        )

        var selected: [AgentTaskMemory] = []
        var characterCount = 0
        for event in retrieved {
            let entry = agentTaskMemory(from: event)
            let nextCount = characterCount + entry.estimatedPromptCharacters
            if !selected.isEmpty, nextCount > maximumCharacters { continue }
            selected.append(entry)
            characterCount = nextCount
        }

        return selected.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func profileContextForPrompt() -> MemoryProfileContext {
        MemoryProfileContext(
            ownerProfile: ownerProfile,
            insights: learnedPreferences
        )
    }

    private func openDatabase() {
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(
            databaseURL.path,
            &connection,
            flags,
            nil
        )
        guard result == SQLITE_OK, let connection else {
            if let connection {
                databaseStatus = String(cString: sqlite3_errmsg(connection))
                sqlite3_close(connection)
            } else {
                databaseStatus = "无法创建本地记忆库"
            }
            return
        }

        database = connection
        sqlite3_busy_timeout(connection, 2_000)
        databaseReady = true
        databaseStatus = "本地记忆库已就绪"
    }

    private func createSchema() {
        execute("PRAGMA journal_mode = WAL;")
        execute("PRAGMA synchronous = NORMAL;")
        execute("PRAGMA foreign_keys = ON;")
        execute(
            """
            CREATE TABLE IF NOT EXISTS memory_events (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                id TEXT NOT NULL UNIQUE,
                created_at REAL NOT NULL,
                mode TEXT NOT NULL,
                application_name TEXT NOT NULL,
                bundle_identifier TEXT,
                raw_transcript TEXT NOT NULL,
                effective_input TEXT NOT NULL,
                selected_context TEXT,
                result TEXT NOT NULL,
                source TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS memory_events_created_at
            ON memory_events(created_at DESC);

            CREATE INDEX IF NOT EXISTS memory_events_mode
            ON memory_events(mode, created_at DESC);

            CREATE TABLE IF NOT EXISTS memory_embeddings (
                event_id TEXT PRIMARY KEY,
                model_language TEXT NOT NULL,
                vector_blob BLOB NOT NULL,
                FOREIGN KEY(event_id) REFERENCES memory_events(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS owner_profile (
                id INTEGER PRIMARY KEY CHECK(id = 1),
                identity_and_work TEXT NOT NULL DEFAULT '',
                communication_style TEXT NOT NULL DEFAULT '',
                important_terms TEXT NOT NULL DEFAULT '',
                preferred_language TEXT NOT NULL DEFAULT 'followInput',
                updated_at REAL
            );

            CREATE TABLE IF NOT EXISTS memory_snapshots (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at REAL NOT NULL,
                event_count INTEGER NOT NULL,
                payload_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS memory_metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """
        )
        if !table("owner_profile", hasColumn: "preferred_language") {
            execute(
                "ALTER TABLE owner_profile ADD COLUMN preferred_language "
                    + "TEXT NOT NULL DEFAULT 'followInput';"
            )
        }
        setMetadata("3", for: "schema_version")
    }

    private func migrateLegacyJSONIfNeeded() {
        guard metadataValue(for: "legacy_agent_json_migrated") != "1" else {
            return
        }
        defer { setMetadata("1", for: "legacy_agent_json_migrated") }
        guard
            let legacyJSONURL,
            let data = try? Data(contentsOf: legacyJSONURL),
            let decoded = try? Self.legacyDecoder.decode(
                [AgentTaskMemory].self,
                from: data
            )
        else { return }

        execute("BEGIN IMMEDIATE TRANSACTION;")
        for entry in decoded.reversed() {
            let event = MemoryEvent(
                id: entry.id,
                createdAt: entry.createdAt,
                mode: .instruction,
                applicationName: entry.applicationName,
                bundleIdentifier: nil,
                rawTranscript: entry.request,
                effectiveInput: entry.request,
                selectedContext: entry.referencePreview,
                result: entry.outcome
            )
            if !containsEquivalent(event) {
                _ = insert(event, source: "agent_json_migration")
            }
        }
        execute("COMMIT;")
    }

    private func reloadPublishedState() {
        eventCount = queryEventCount()
        entries = loadRecentAgentTasks()
        ownerProfile = loadOwnerProfile()
        let sanitizedProfile = OwnerProfileAutoUpdater.removingLegacyManagedLines(
            from: ownerProfile
        )
        if sanitizedProfile != ownerProfile {
            _ = updateOwnerProfile(sanitizedProfile)
        }
        lastAutomaticProfileEventCount = Int(
            metadataValue(for: "automatic_owner_profile_event_count") ?? "0"
        ) ?? 0

        if let saved = loadLatestInsights(),
           saved.observedTaskCount == eventCount {
            insights = saved
        } else if eventCount > 0 {
            insights = MemoryInsightsAnalyzer.analyze(loadEvents())
            persistSnapshot(insights)
        } else {
            insights = .empty
        }

        if let savedLearnedPreferences = loadLearnedPreferences() {
            learnedPreferences = savedLearnedPreferences
        } else if lastAutomaticProfileEventCount > 0, !insights.isEmpty {
            // Migrate installations that previously embedded automatic lines
            // directly inside the confirmed profile.
            learnedPreferences = insights
            _ = persistLearnedPreferences(insights)
        } else {
            learnedPreferences = .empty
        }
    }

    private func refreshAfterEventChanges(writeSnapshot: Bool) {
        eventCount = queryEventCount()
        entries = loadRecentAgentTasks()
        insights = eventCount > 0
            ? MemoryInsightsAnalyzer.analyze(loadEvents())
            : .empty
        if writeSnapshot, eventCount > 0 {
            persistSnapshot(insights)
        }
    }

    @discardableResult
    private func insert(_ event: MemoryEvent, source: String) -> Bool {
        guard databaseReady else { return false }
        let sql = """
        INSERT OR IGNORE INTO memory_events (
            id, created_at, mode, application_name, bundle_identifier,
            raw_transcript, effective_input, selected_context, result, source
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let statement = prepare(sql) else { return false }
        defer { sqlite3_finalize(statement) }
        bind(event.id.uuidString, at: 1, to: statement)
        sqlite3_bind_double(statement, 2, event.createdAt.timeIntervalSince1970)
        bind(event.mode.rawValue, at: 3, to: statement)
        bind(event.applicationName, at: 4, to: statement)
        bind(event.bundleIdentifier, at: 5, to: statement)
        bind(event.rawTranscript, at: 6, to: statement)
        bind(event.effectiveInput, at: 7, to: statement)
        bind(event.selectedContext, at: 8, to: statement)
        bind(event.result, at: 9, to: statement)
        bind(source, at: 10, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            reportDatabaseError("Unable to append memory event")
            return false
        }
        let didInsert = sqlite3_changes(database) > 0
        if didInsert {
            persistEmbedding(for: event)
        }
        return didInsert
    }

    private func persistEmbedding(for event: MemoryEvent) {
        guard let vector = LocalMemoryEmbedding.vector(for: event) else { return }
        let sql = """
        INSERT INTO memory_embeddings (event_id, model_language, vector_blob)
        VALUES (?, 'zh-Hans', ?)
        ON CONFLICT(event_id) DO UPDATE SET
            model_language = excluded.model_language,
            vector_blob = excluded.vector_blob;
        """
        guard let statement = prepare(sql) else { return }
        defer { sqlite3_finalize(statement) }
        bind(event.id.uuidString, at: 1, to: statement)
        bind(LocalMemoryEmbedding.encoded(vector), at: 2, to: statement)
        if sqlite3_step(statement) != SQLITE_DONE {
            reportDatabaseError("Unable to save local memory embedding")
        }
    }

    private func backfillMissingEmbeddings(limit: Int) {
        guard limit > 0 else { return }
        let sql = """
        SELECT e.id, e.created_at, e.mode, e.application_name,
               e.bundle_identifier, e.raw_transcript, e.effective_input,
               e.selected_context, e.result
        FROM memory_events e
        LEFT JOIN memory_embeddings x ON x.event_id = e.id
        WHERE x.event_id IS NULL
        ORDER BY e.sequence DESC
        LIMIT ?;
        """
        guard let statement = prepare(sql) else { return }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var events: [MemoryEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            events.append(memoryEvent(from: statement))
        }
        sqlite3_finalize(statement)

        execute("BEGIN IMMEDIATE TRANSACTION;")
        for event in events {
            persistEmbedding(for: event)
        }
        execute("COMMIT;")
    }

    private func loadIndexedEvents(limit: Int) -> [IndexedMemoryEvent] {
        let sql = """
        SELECT e.id, e.created_at, e.mode, e.application_name,
               e.bundle_identifier, e.raw_transcript, e.effective_input,
               e.selected_context, e.result, x.vector_blob
        FROM memory_events e
        LEFT JOIN memory_embeddings x ON x.event_id = e.id
        ORDER BY e.sequence DESC
        LIMIT ?;
        """
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(0, limit)))

        var result: [IndexedMemoryEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let embedding = data(at: 9, from: statement)
                .flatMap(LocalMemoryEmbedding.decoded)
            result.append(
                IndexedMemoryEvent(
                    event: memoryEvent(from: statement),
                    embedding: embedding
                )
            )
        }
        return result
    }

    private func loadEvents() -> [MemoryEvent] {
        let sql = """
        SELECT id, created_at, mode, application_name, bundle_identifier,
               raw_transcript, effective_input, selected_context, result
        FROM memory_events
        ORDER BY created_at ASC, sequence ASC;
        """
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [MemoryEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(memoryEvent(from: statement))
        }
        return result
    }

    private func memoryEvent(from statement: OpaquePointer) -> MemoryEvent {
        MemoryEvent(
            id: UUID(uuidString: text(at: 0, from: statement) ?? "") ?? UUID(),
            createdAt: Date(
                timeIntervalSince1970: sqlite3_column_double(statement, 1)
            ),
            mode: InputMode(rawValue: text(at: 2, from: statement) ?? "") ?? .clean,
            applicationName: text(at: 3, from: statement) ?? "Unknown app",
            bundleIdentifier: text(at: 4, from: statement),
            rawTranscript: text(at: 5, from: statement) ?? "",
            effectiveInput: text(at: 6, from: statement) ?? "",
            selectedContext: text(at: 7, from: statement),
            result: text(at: 8, from: statement) ?? ""
        )
    }

    private func agentTaskMemory(from event: MemoryEvent) -> AgentTaskMemory {
        let effective = event.effectiveInput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return AgentTaskMemory(
            id: event.id,
            createdAt: event.createdAt,
            request: effective.isEmpty ? event.rawTranscript : effective,
            outcome: event.result,
            applicationName: event.applicationName,
            referencePreview: event.selectedContext
        )
    }

    private func loadRecentAgentTasks() -> [AgentTaskMemory] {
        let sql = """
        SELECT id, created_at, effective_input, result,
               application_name, selected_context
        FROM memory_events
        WHERE mode = ?
        ORDER BY created_at DESC, sequence DESC
        LIMIT ?;
        """
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(InputMode.instruction.rawValue, at: 1, to: statement)
        sqlite3_bind_int(statement, 2, Int32(maximumEntries))
        var result: [AgentTaskMemory] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(
                AgentTaskMemory(
                    id: UUID(uuidString: text(at: 0, from: statement) ?? "")
                        ?? UUID(),
                    createdAt: Date(
                        timeIntervalSince1970: sqlite3_column_double(statement, 1)
                    ),
                    request: text(at: 2, from: statement) ?? "",
                    outcome: text(at: 3, from: statement) ?? "",
                    applicationName: text(at: 4, from: statement) ?? "Unknown app",
                    referencePreview: text(at: 5, from: statement).map {
                        String($0.prefix(1_000))
                    }
                )
            )
        }
        return result
    }

    private func loadOwnerProfile() -> OwnerProfile {
        let sql = """
        SELECT identity_and_work, communication_style, important_terms,
               preferred_language, updated_at
        FROM owner_profile WHERE id = 1;
        """
        guard let statement = prepare(sql) else { return .empty }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return .empty }
        let timestamp = sqlite3_column_type(statement, 4) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(statement, 4)
        return OwnerProfile(
            identityAndWork: text(at: 0, from: statement) ?? "",
            communicationStyle: text(at: 1, from: statement) ?? "",
            importantTerms: text(at: 2, from: statement) ?? "",
            preferredLanguage: ProfileLanguagePreference(
                rawValue: text(at: 3, from: statement) ?? ""
            ) ?? .followInput,
            updatedAt: timestamp.map(Date.init(timeIntervalSince1970:))
        )
    }

    private func loadLatestInsights() -> MemoryInsights? {
        let sql = """
        SELECT payload_json FROM memory_snapshots
        ORDER BY sequence DESC LIMIT 1;
        """
        guard let statement = prepare(sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard
            sqlite3_step(statement) == SQLITE_ROW,
            let payload = text(at: 0, from: statement),
            let data = payload.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(MemoryInsights.self, from: data)
    }

    private func persistSnapshot(_ snapshot: MemoryInsights) {
        guard
            let data = try? JSONEncoder().encode(snapshot),
            let payload = String(data: data, encoding: .utf8)
        else { return }
        let sql = """
        INSERT INTO memory_snapshots (created_at, event_count, payload_json)
        VALUES (?, ?, ?);
        """
        guard let statement = prepare(sql) else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(snapshot.observedTaskCount))
        bind(payload, at: 3, to: statement)
        if sqlite3_step(statement) != SQLITE_DONE {
            reportDatabaseError("Unable to save memory snapshot")
        }
    }

    private func loadLearnedPreferences() -> MemoryInsights? {
        guard
            let payload = metadataValue(for: "learned_preferences_v1"),
            let data = payload.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(MemoryInsights.self, from: data)
    }

    @discardableResult
    private func persistLearnedPreferences(_ preferences: MemoryInsights) -> Bool {
        guard
            let data = try? JSONEncoder().encode(preferences),
            let payload = String(data: data, encoding: .utf8)
        else { return false }
        setMetadata(payload, for: "learned_preferences_v1")
        return metadataValue(for: "learned_preferences_v1") == payload
    }

    private func containsEquivalent(_ event: MemoryEvent) -> Bool {
        let sql = """
        SELECT 1 FROM memory_events
        WHERE ABS(created_at - ?) < 1
          AND effective_input = ?
          AND result = ?
        LIMIT 1;
        """
        guard let statement = prepare(sql) else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, event.createdAt.timeIntervalSince1970)
        bind(event.effectiveInput, at: 2, to: statement)
        bind(event.result, at: 3, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func queryEventCount() -> Int {
        guard let statement = prepare("SELECT COUNT(*) FROM memory_events;") else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func metadataValue(for key: String) -> String? {
        guard let statement = prepare(
            "SELECT value FROM memory_metadata WHERE key = ? LIMIT 1;"
        ) else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(key, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(at: 0, from: statement)
    }

    private func table(_ tableName: String, hasColumn columnName: String) -> Bool {
        guard let statement = prepare("PRAGMA table_info(\(tableName));") else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if text(at: 1, from: statement) == columnName { return true }
        }
        return false
    }

    private func setMetadata(_ value: String, for key: String) {
        let sql = """
        INSERT INTO memory_metadata (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        """
        guard let statement = prepare(sql) else { return }
        defer { sqlite3_finalize(statement) }
        bind(key, at: 1, to: statement)
        bind(value, at: 2, to: statement)
        if sqlite3_step(statement) != SQLITE_DONE {
            reportDatabaseError("Unable to save memory metadata")
        }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            reportDatabaseError("Unable to prepare memory query")
            return nil
        }
        return statement
    }

    private func bind(
        _ value: String?,
        at index: Int32,
        to statement: OpaquePointer
    ) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(
        _ value: Data,
        at index: Int32,
        to statement: OpaquePointer
    ) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(
                statement,
                index,
                bytes.baseAddress,
                Int32(bytes.count),
                sqliteTransient
            )
        }
    }

    private func text(
        at index: Int32,
        from statement: OpaquePointer
    ) -> String? {
        guard let raw = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: raw)
    }

    private func data(
        at index: Int32,
        from statement: OpaquePointer
    ) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else {
            return nil
        }
        return Data(bytes: bytes, count: count)
    }

    private func execute(_ sql: String) {
        guard let database else { return }
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &errorMessage) != SQLITE_OK {
            if let errorMessage {
                databaseStatus = String(cString: errorMessage)
                sqlite3_free(errorMessage)
            } else {
                reportDatabaseError("Unable to update memory database")
            }
        }
    }

    private func reportDatabaseError(_ prefix: String) {
        if let database {
            databaseStatus = "\(prefix): \(String(cString: sqlite3_errmsg(database)))"
        } else {
            databaseStatus = prefix
        }
    }

    private static var legacyDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
