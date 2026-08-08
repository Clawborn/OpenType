import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let schemaVersion: Int
    let id: UUID
    let requestId: UUID
    let createdAt: Date
    let platform: String
    let outcome: String
    let mode: String
    let originalTranscript: String
    let context: String
    let result: String
    let error: String?
    let provider: String
    let model: String
    let effectiveInput: String?
    let supersedesEventId: UUID?

    init(
        schemaVersion: Int = 1,
        id: UUID,
        requestId: UUID = UUID(),
        createdAt: Date,
        platform: String,
        outcome: String,
        mode: String,
        originalTranscript: String,
        context: String,
        result: String,
        error: String?,
        provider: String,
        model: String,
        effectiveInput: String? = nil,
        supersedesEventId: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.requestId = requestId
        self.createdAt = createdAt
        self.platform = platform
        self.outcome = outcome
        self.mode = mode
        self.originalTranscript = originalTranscript
        self.context = context
        self.result = result
        self.error = error
        self.provider = provider
        self.model = model
        self.effectiveInput = effectiveInput ?? originalTranscript
        self.supersedesEventId = supersedesEventId
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id = "eventId"
        case requestId
        case createdAt
        case platform
        case outcome = "status"
        case mode
        case originalTranscript = "rawTranscript"
        case effectiveInput
        case context = "selectedContext"
        case result
        case error
        case provider
        case model
        case supersedesEventId
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    let logURL: URL
    private let visibleEntryLimit: Int

    init(logURL customLogURL: URL? = nil, visibleEntryLimit: Int = 500) {
        self.visibleEntryLimit = max(1, visibleEntryLimit)
        let defaultDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenType", isDirectory: true)
        let resolvedLogURL = customLogURL ?? defaultDirectory.appendingPathComponent("audit-events.jsonl")
        let directory = resolvedLogURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = resolvedLogURL
        if !FileManager.default.fileExists(atPath: logURL.path) {
            _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: logURL.path
            )
        }
        loadRecent()
    }

    func append(
        requestId: UUID = UUID(),
        mode: InputMode,
        effectiveMode: String? = nil,
        transcript: String,
        context: String,
        result: String,
        outcome: String,
        error: String?,
        provider: String,
        model: String
    ) -> Bool {
        let entry = HistoryEntry(
            id: UUID(),
            requestId: requestId,
            createdAt: Date(),
            platform: "iOS",
            outcome: outcome,
            mode: effectiveMode ?? mode.rawValue,
            originalTranscript: transcript,
            context: context,
            result: result,
            error: error,
            provider: provider,
            model: model
        )
        guard appendLine(entry) else { return false }
        if outcome != "recognized" {
            entries.removeAll { $0.requestId == requestId }
            entries.insert(entry, at: 0)
        }
        if entries.count > visibleEntryLimit {
            entries.removeLast(entries.count - visibleEntryLimit)
        }
        return true
    }

    private func appendLine(_ entry: HistoryEntry) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(entry) else { return false }
        data.append(0x0A)
        do {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            return true
        } catch {
            return false
        }
    }

    private func loadRecent() {
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let recentLines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(visibleEntryLimit * 4)
        var seenRequests = Set<UUID>()
        var visible: [HistoryEntry] = []
        for line in recentLines.reversed() {
            guard let entry = try? decoder.decode(HistoryEntry.self, from: Data(line.utf8)),
                  entry.outcome != "recognized",
                  seenRequests.insert(entry.requestId).inserted else { continue }
            visible.append(entry)
            if visible.count == visibleEntryLimit { break }
        }
        entries = visible
    }
}
