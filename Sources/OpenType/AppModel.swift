import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: ProcessingState = .idle
    @Published private(set) var credentialStatus = "正在检查…"
    @Published private(set) var shortcutStatus = "正在注册…"
    @Published private(set) var shortcutKeys = HotKeyPreset.controlShiftSpace.keys
    @Published private(set) var shortcutBehavior: HotKeyBehavior = .holdToTalk
    @Published private(set) var shortcutReady = false
    @Published private(set) var preferredShortcutActive = false
    @Published private(set) var microphonePermission: PermissionStatus = .notDetermined
    @Published private(set) var speechRecognitionPermission: PermissionStatus = .notDetermined
    @Published private(set) var isPracticeSession = false
    @Published private(set) var lastResultWasPractice = false
    @Published private(set) var lastResult = ""
    @Published private(set) var lastTranscript = ""
    @Published private(set) var lastApplication = ""
    @Published private(set) var configuredProviders: Set<AIProvider> = []
    @Published var selectedTab: AppTab = .home

    let configuration: AppConfiguration
    let history: HistoryStore
    let agentMemory: AgentMemoryStore
    let providerVault = ProviderVault()
    private let auditStore = ImmutableAuditStore()

    private let audioRecorder = AudioRecorder()
    private let liveSpeechTranscriber = LiveSpeechTranscriber()
    private let contextBridge = ContextBridge()
    private let hotKey = GlobalHotKey()
    private let overlay = OverlayController()
    private var customSounds: [String: NSSound] = [:]
    private var activeFeedbackSound: NSSound?
    private var client: AIServiceClient?
    private var capturedContext = CapturedContext(
        selectedText: nil,
        applicationName: "Unknown app",
        bundleIdentifier: nil
    )
    private var processingTask: Task<Void, Never>?
    private var accessibilityPollTimer: Timer?
    private var activeMode: InputMode?
    private var didStart = false
    private var isHotKeyHeld = false
    private var isStartingRecording = false

    var accessibilityGranted: Bool {
        contextBridge.accessibilityGranted
    }

    var cloudConnected: Bool {
        client?.isFullyConfigured == true
    }

    var setupReady: Bool {
        cloudConnected
            && microphonePermission == .granted
            && accessibilityGranted
            && (!configuration.liveCaptionsEnabled
                || speechRecognitionPermission == .granted)
            && shortcutReady
            && preferredShortcutActive
    }

    var canTogglePractice: Bool {
        if isPracticeSession, state == .listening { return true }
        return cloudConnected && !isBusy && !isStartingRecording
    }

    var canUndo: Bool {
        !lastResult.isEmpty
    }

    init() {
        self.configuration = AppConfiguration()
        self.history = HistoryStore()
        self.agentMemory = AgentMemoryStore()
        self.agentMemory.importHistoryIfNeeded(self.history.entries)
        self.agentMemory.refreshOwnerProfileIfNeeded(
            enabled: self.configuration.agentMemoryEnabled
                && self.configuration.automaticOwnerProfileUpdates,
            personalDictionary: self.configuration.personalDictionary
        )
        self.overlay.updateColorTheme(self.configuration.colorTheme)
        self.overlay.updateInterfaceLanguage(self.configuration.interfaceLanguage)
        microphonePermission = audioRecorder.permissionStatus
        speechRecognitionPermission = liveSpeechTranscriber.permissionStatus
        liveSpeechTranscriber.onTranscript = { [weak self] text in
            self?.overlay.updateLiveTranscript(text)
        }
        liveSpeechTranscriber.onAudioLevel = { [weak self] level in
            self?.overlay.updateAudioLevel(level)
        }
        loadCredential()
        start()
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        hotKey.onPressed = { [weak self] in
            self?.shortcutBehavior = .holdToTalk
            self?.hotKeyPressed()
        }
        hotKey.onReleased = { [weak self] in
            self?.hotKeyReleased()
        }
        hotKey.onToggle = { [weak self] in
            self?.shortcutBehavior = .pressThenAnyKey
            self?.hotKeyToggled()
        }
        hotKey.onStopRequested = { [weak self] in
            self?.hotKeyReleased()
        }
        hotKey.onCycleMode = { [weak self] in
            self?.cycleMode()
        }
        let installed = hotKey.install(preference: configuration.hotKeyPreset)
        updateShortcutPresentation(
            preference: configuration.hotKeyPreset,
            installed: installed
        )
    }

    func hotKeyPressed() {
        guard state != .listening else { return }
        guard !isBusy, !isStartingRecording else { return }

        let context = contextBridge.capture()
        let selectedMode = configuration.selectedMode
        let mode = SmartEditRouter.mode(
            selectedMode: selectedMode,
            selectedText: context.selectedText
        )
        if mode.requiresSelection, !contextBridge.accessibilityGranted {
            fail(OpenTypeError.accessibilityRequired)
            return
        }
        if mode.requiresSelection,
           context.selectedText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty != false {
            fail(OpenTypeError.selectionRequired(mode))
            return
        }

        isHotKeyHeld = true
        beginRecording(context: context, mode: mode, practice: false)
    }

    func togglePracticeDictation() {
        if isPracticeSession, state == .listening {
            isHotKeyHeld = false
            finishRecording()
            return
        }
        guard canTogglePractice else { return }

        isHotKeyHeld = true
        beginRecording(
            context: CapturedContext(
                selectedText: nil,
                applicationName: "OpenType 试用",
                bundleIdentifier: "ai.rain.opentype"
            ),
            mode: .clean,
            practice: true
        )
    }

    private func beginRecording(
        context: CapturedContext,
        mode: InputMode,
        practice: Bool
    ) {
        isStartingRecording = true
        capturedContext = context
        activeMode = mode
        isPracticeSession = practice
        processingTask?.cancel()
        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.audioRecorder.start()
                self.microphonePermission = self.audioRecorder.permissionStatus
                self.isStartingRecording = false
                self.setState(.listening)
                if self.configuration.liveCaptionsEnabled,
                   self.speechRecognitionPermission == .granted {
                    try? self.liveSpeechTranscriber.start(
                        localeIdentifier: self.configuration
                            .transcriptionLanguage
                            .appleLocaleIdentifier
                    )
                }
                self.playFeedbackSound(.ready)
                if !self.isHotKeyHeld, !self.isPracticeSession {
                    self.finishRecording()
                }
            } catch {
                self.microphonePermission = self.audioRecorder.permissionStatus
                self.isStartingRecording = false
                self.fail(error)
            }
        }
    }

    func hotKeyReleased() {
        isHotKeyHeld = false
        shortcutBehavior = hotKey.behavior
        guard state == .listening else { return }
        finishRecording()
    }

    func hotKeyToggled() {
        if state == .listening {
            hotKeyReleased()
        } else if !isBusy, !isStartingRecording {
            hotKeyPressed()
        } else {
            shortcutBehavior = hotKey.behavior
        }
    }

    func cancel() {
        processingTask?.cancel()
        processingTask = nil
        isHotKeyHeld = false
        isStartingRecording = false
        isPracticeSession = false
        activeMode = nil
        shortcutBehavior = hotKey.behavior
        audioRecorder.cancel()
        liveSpeechTranscriber.stop()
        setState(.idle)
        overlay.hide()
    }

    func selectMode(_ mode: InputMode) {
        configuration.selectedMode = mode
        overlay.show(state: .modeChanged, mode: mode)
    }

    func cycleMode() {
        guard state != .listening, !isBusy, !isStartingRecording else { return }
        selectMode(configuration.selectedMode.next)
    }

    func requestAccessibility() {
        contextBridge.requestAccessibilityPermission()
        contextBridge.openAccessibilitySettings()
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                guard self.contextBridge.accessibilityGranted else { return }
                timer.invalidate()
                self.accessibilityPollTimer = nil
                self.refreshPreferredShortcut()
                self.objectWillChange.send()
            }
        }
        objectWillChange.send()
    }

    func requestMicrophonePermission() {
        if microphonePermission == .denied {
            contextBridge.openMicrophoneSettings()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            _ = await self.audioRecorder.requestPermission()
            self.microphonePermission = self.audioRecorder.permissionStatus
        }
    }

    func requestSpeechRecognitionPermission() {
        if speechRecognitionPermission == .denied {
            liveSpeechTranscriber.openPermissionSettings()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            _ = await self.liveSpeechTranscriber.requestPermission()
            self.speechRecognitionPermission = self.liveSpeechTranscriber.permissionStatus
            self.objectWillChange.send()
        }
    }

    func refreshPermissionStatus() {
        microphonePermission = audioRecorder.permissionStatus
        speechRecognitionPermission = liveSpeechTranscriber.permissionStatus
        if contextBridge.accessibilityGranted,
           (!preferredShortcutActive || shortcutBehavior == .holdToTalk) {
            refreshPreferredShortcut()
        }
        objectWillChange.send()
    }

    func changeHotKey(_ preset: HotKeyPreset) {
        guard state != .listening, !isBusy, !isStartingRecording else {
            shortcutStatus = OpenTypeL10n.text("请先结束当前语音输入，再修改快捷键", english: "Finish the current voice input before changing the shortcut")
            persistShortcutStatus()
            return
        }

        let previous = configuration.hotKeyPreset
        let installed = hotKey.reinstall(preference: preset)
        if installed {
            configuration.hotKeyPreset = preset
            updateShortcutPresentation(preference: preset, installed: true)
            return
        }

        let restored = hotKey.reinstall(preference: previous)
        updateShortcutPresentation(preference: previous, installed: restored)
        shortcutStatus = OpenTypeL10n.text(
            "\(preset.title) 已被系统或其他应用占用，已恢复 \(previous.title)",
            english: "\(preset.title) is used by macOS or another app. Restored \(previous.title)."
        )
        persistShortcutStatus()
    }

    func changeColorTheme(_ theme: AppColorTheme) {
        guard configuration.colorTheme != theme else { return }
        configuration.colorTheme = theme
        overlay.updateColorTheme(theme)
    }

    func changeInterfaceLanguage(_ language: InterfaceLanguage) {
        guard configuration.interfaceLanguage != language else { return }
        configuration.interfaceLanguage = language
        overlay.updateInterfaceLanguage(language)
        refreshAIService()
        updateShortcutPresentation(
            preference: configuration.hotKeyPreset,
            installed: shortcutReady
        )
    }

    func changeSpeechProvider(_ provider: AIProvider) {
        guard provider.supportsSpeechRecognition else { return }
        configuration.speechProvider = provider
        refreshAIService()
    }

    func changeTranscriptionLanguage(_ language: TranscriptionLanguage) {
        configuration.transcriptionLanguage = language
        refreshAIService()
    }

    func changeTextProvider(_ provider: AIProvider) {
        guard provider.supportsTextGeneration else { return }
        configuration.textProvider = provider
        refreshAIService()
    }

    func changeAutomaticOwnerProfileUpdates(_ enabled: Bool) {
        configuration.automaticOwnerProfileUpdates = enabled
        guard enabled, configuration.agentMemoryEnabled else { return }
        agentMemory.refreshOwnerProfileIfNeeded(
            enabled: true,
            personalDictionary: configuration.personalDictionary
        )
    }

    func updateSpeechModel(_ model: String) {
        configuration.updateSpeechModel(model, for: configuration.speechProvider)
        refreshAIService()
    }

    func updateTextModel(_ model: String) {
        configuration.updateTextModel(model, for: configuration.textProvider)
        refreshAIService()
    }

    func providerIsConfigured(_ provider: AIProvider) -> Bool {
        configuredProviders.contains(provider)
    }

    @discardableResult
    func saveProviderToken(_ token: String, for provider: AIProvider) -> String? {
        do {
            try providerVault.save(token, for: provider)
            refreshAIService()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @discardableResult
    func deleteProviderToken(for provider: AIProvider) -> String? {
        do {
            try providerVault.delete(for: provider)
            refreshAIService()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func copyLastResult() {
        guard !lastResult.isEmpty else { return }
        contextBridge.copyToClipboard(lastResult)
    }

    func copy(_ text: String) {
        contextBridge.copyToClipboard(text)
    }

    func previewFeedbackSound(_ cue: FeedbackSoundCue) {
        playFeedbackSound(cue)
    }

    func changeMuted(_ muted: Bool) {
        configuration.isMuted = muted
        if muted {
            activeFeedbackSound?.stop()
            activeFeedbackSound = nil
        }
    }

    func resetHistory() {
        history.clear()
    }

    func resetAgentMemory() {
        agentMemory.clear()
    }

    func reuse(_ entry: HistoryEntry) {
        lastResult = entry.result
        lastTranscript = entry.transcript
        lastApplication = entry.applicationName
        lastResultWasPractice = false
        contextBridge.copyToClipboard(entry.result)
    }

    func undo() {
        do {
            try contextBridge.undoLastChange()
        } catch {
            fail(error)
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private var isBusy: Bool {
        switch state {
        case .transcribing, .transforming, .inserting:
            return true
        default:
            return false
        }
    }

    private func finishRecording() {
        hotKey.setRecordingActive(false)
        liveSpeechTranscriber.stop()
        do {
            let audioURL = try audioRecorder.stop()
            playFeedbackSound(.release)
            processingTask = Task { [weak self] in
                await self?.process(audioURL: audioURL)
            }
        } catch {
            fail(error)
        }
    }

    private func loadCredential() {
        let legacyCredential = try? CredentialProvider().load()
        providerVault.migrateDashScopeIfNeeded(legacyCredential)
        refreshAIService()
    }

    private func refreshAIService() {
        configuredProviders = Set(
            AIProvider.allCases.filter { providerVault.hasToken(for: $0) }
        )
        let service = AIServiceClient(
            selection: configuration.serviceSelection,
            vault: providerVault
        )
        client = service
        credentialStatus = service.isFullyConfigured
            ? OpenTypeL10n.text("AI 服务已配置 · \(service.safeStatusDescription)", english: "AI services ready · \(service.safeStatusDescription)")
            : service.safeStatusDescription
    }

    private func refreshPreferredShortcut() {
        let preference = configuration.hotKeyPreset
        let installed = hotKey.reinstall(preference: preference)
        updateShortcutPresentation(preference: preference, installed: installed)
    }

    private func updateShortcutPresentation(
        preference: HotKeyPreset,
        installed: Bool
    ) {
        shortcutReady = installed
        preferredShortcutActive = installed && hotKey.isUsingPreferred
        shortcutKeys = installed ? hotKey.shortcutKeys : preference.keys
        shortcutBehavior = installed ? hotKey.behavior : .holdToTalk

        if !installed {
            shortcutStatus = OpenTypeL10n.text("\(preference.title) 无法注册，请换一个快捷键", english: "Could not register \(preference.title). Choose another shortcut.")
        } else if hotKey.isUsingPreferred {
            let interaction: String
            switch hotKey.behavior {
            case .optionHybrid:
                interaction = OpenTypeL10n.text("长按说话 / 双击连续录音", english: "Hold to talk / double-tap for continuous recording")
            case .holdToTalk:
                interaction = OpenTypeL10n.text("按住说话", english: "Hold to talk")
            default:
                interaction = OpenTypeL10n.text("按任意键结束", english: "Press any key to finish")
            }
            shortcutStatus = OpenTypeL10n.text("当前生效：\(preference.title) · \(interaction)", english: "Active: \(preference.title) · \(interaction)")
        } else {
            let actual = hotKey.shortcutKeys.joined(separator: " ")
            shortcutStatus = OpenTypeL10n.text("目标：\(preference.title) · 当前回退：\(actual)（等待辅助功能授权）", english: "Target: \(preference.title) · Fallback: \(actual) (waiting for Accessibility permission)")
        }
        persistShortcutStatus()
    }

    private func persistShortcutStatus() {
        UserDefaults.standard.set(
            shortcutStatus,
            forKey: "lastShortcutRegistrationStatus"
        )
    }

    private func process(audioURL: URL) async {
        let startingMode = activeMode ?? configuration.selectedMode
        let practice = isPracticeSession
        let auditRequestID = UUID()
        let serviceSelection = configuration.serviceSelection
        var auditMode = startingMode
        var auditRawTranscript = ""
        var auditEffectiveInput: String?
        var usedTextModel = false
        var effectiveTextModel: String?

        func appendAudit(
            status: AuditEventStatus,
            result: String? = nil,
            error: String? = nil,
            provider: AIProvider? = nil,
            model: String? = nil
        ) {
            try? auditStore.append(
                ImmutableAuditEvent(
                    requestId: auditRequestID,
                    status: status,
                    mode: auditMode,
                    rawTranscript: auditRawTranscript,
                    effectiveInput: auditEffectiveInput,
                    selectedContext: capturedContext.selectedText,
                    result: result,
                    provider: provider?.rawValue,
                    model: model,
                    error: error
                )
            )
        }

        defer {
            try? FileManager.default.removeItem(at: audioURL)
            activeMode = nil
            isPracticeSession = false
        }

        guard let client else {
            fail(OpenTypeError.missingCredential)
            return
        }

        do {
            setState(.transcribing)
            let rawTranscript: String
            do {
                rawTranscript = try await client.transcribe(
                    audioURL: audioURL,
                    personalVocabulary: configuration.personalDictionary
                )
            } catch OpenTypeError.emptyRecording where startingMode == .xReply {
                // Silence is a valid X Reply instruction: generate a useful
                // conversational response from the selected post alone.
                rawTranscript = ""
            } catch OpenTypeError.emptyRecording where startingMode == .command {
                throw OpenTypeError.missingEditInstruction
            }
            try Task.checkCancellation()
            auditRawTranscript = rawTranscript

            let sendCommand = SendCommandParser.parse(
                rawTranscript,
                enabled: configuration.pressEnterCommand
            )
            let routed = startingMode == .command
                ? RoutedTranscript(mode: .command, text: sendCommand.text)
                : VoiceModeRouter.route(
                    sendCommand.text,
                    currentMode: startingMode
                )
            let mode = routed.mode
            let transcript = routed.text
            activeMode = mode
            auditMode = mode
            auditEffectiveInput = transcript
            appendAudit(
                status: .recognized,
                provider: serviceSelection.speechProvider,
                model: serviceSelection.speechModel
            )

            if mode == .command,
               !EditInstructionValidator.isExplicit(transcript) {
                throw OpenTypeError.missingEditInstruction
            }

            if mode.requiresSelection,
               !contextBridge.accessibilityGranted {
                throw OpenTypeError.accessibilityRequired
            }
            if mode.requiresSelection,
               capturedContext.selectedText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty != false {
                throw OpenTypeError.selectionRequired(mode)
            }
            lastTranscript = transcript

            setState(.transforming)
            let result: String
            if mode == .raw,
               !configuration.hasCustomPrompt(for: .raw),
               !LightTranscriptionPolicy.shouldUseModel(for: transcript) {
                result = LightTranscriptionPolicy.localResult(for: transcript)
            } else {
                usedTextModel = true
                effectiveTextModel = client.effectiveTextModel(for: mode)
                let request = TransformRequest(
                    transcript: transcript,
                    mode: mode,
                    context: capturedContext,
                    personalDictionary: configuration.personalDictionary,
                    xReplyStyle: configuration.xReplyStyle,
                    modePromptOverride: configuration.promptOverride(for: mode),
                    agentMemory: mode == .instruction
                        && configuration.agentMemoryEnabled
                        ? agentMemory.memoriesForPrompt(
                            query: transcript,
                            selectedContext: capturedContext.selectedText,
                            applicationName: capturedContext.applicationName
                        )
                        : [],
                    memoryProfile: configuration.agentMemoryEnabled
                        && mode != .raw
                        ? agentMemory.profileContextForPrompt()
                        : .empty
                )
                let transformResult = try await client.transformResult(request)
                effectiveTextModel = transformResult.model
                let transformed = transformResult.text
                result = mode == .raw
                    ? LightTranscriptionPolicy.validatedResult(
                        original: transcript,
                        candidate: transformed
                    )
                    : transformed
            }
            try Task.checkCancellation()

            lastResult = result
            lastApplication = capturedContext.applicationName
            lastResultWasPractice = practice

            if configuration.agentMemoryEnabled, !practice {
                agentMemory.record(
                    MemoryEvent(
                        mode: mode,
                        applicationName: capturedContext.applicationName,
                        bundleIdentifier: capturedContext.bundleIdentifier,
                        rawTranscript: rawTranscript,
                        effectiveInput: transcript,
                        selectedContext: capturedContext.selectedText,
                        result: result
                    )
                )
                agentMemory.refreshOwnerProfileIfNeeded(
                    enabled: configuration.automaticOwnerProfileUpdates,
                    personalDictionary: configuration.personalDictionary
                )
            }

            if configuration.keepHistory, !practice {
                history.add(
                    HistoryEntry(
                        mode: mode,
                        applicationName: capturedContext.applicationName,
                        transcript: transcript,
                        result: result,
                        contextPreview: capturedContext.selectedText.map {
                            String($0.prefix(240))
                        }
                    )
                )
            }

            var completionState: ProcessingState = .success
            let deliveryStrategy = OutputDeliveryPolicy.strategy(
                for: mode,
                automaticallyInsert: configuration.automaticallyInsert
            )
            if practice {
                // The guided first-run test keeps the result inside OpenType so
                // users can verify the whole voice pipeline before granting
                // system-wide insertion access.
            } else if deliveryStrategy == .automaticInsert {
                setState(.inserting)
                do {
                    try await contextBridge.insert(
                        result,
                        pressEnter: sendCommand.pressEnter
                            && OutputDeliveryPolicy.permitsAutomaticEnter(
                                for: mode
                            )
                    )
                } catch {
                    completionState = .copied
                }
            } else if !practice {
                completionState = .copied
            }

            if OutputDeliveryPolicy.retainsClipboardCopy(for: mode) {
                contextBridge.copyToClipboard(result)
            }

            appendAudit(
                status: .completed,
                result: result,
                provider: usedTextModel ? serviceSelection.textProvider : nil,
                model: usedTextModel ? effectiveTextModel : nil
            )

            playFeedbackSound(.done)
            setState(completionState)
            scheduleIdle(after: completionState)
        } catch is CancellationError {
            appendAudit(
                status: .cancelled,
                error: OpenTypeL10n.text(
                    "处理已取消",
                    english: "Processing was cancelled"
                )
            )
            if state != .copied {
                setState(.idle)
            }
        } catch OpenTypeError.missingEditInstruction {
            let message = OpenTypeL10n.text("没有明确修改指令，原文保持不变", english: "No clear editing instruction was detected. The original text was left unchanged.")
            appendAudit(status: .cancelled, error: message)
            let cancelled = ProcessingState.cancelled(message)
            setState(cancelled)
            scheduleIdle(after: cancelled)
        } catch {
            appendAudit(
                status: .failed,
                error: ErrorMessagePresenter.message(for: error),
                provider: auditRawTranscript.isEmpty
                    ? serviceSelection.speechProvider
                    : serviceSelection.textProvider,
                model: auditRawTranscript.isEmpty
                    ? serviceSelection.speechModel
                    : (effectiveTextModel
                        ?? client.effectiveTextModel(for: auditMode))
            )
            fail(error)
        }
    }

    private func scheduleIdle(after completionState: ProcessingState) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, self.state == completionState else { return }
            self.state = .idle
        }
    }

    private func setState(_ newState: ProcessingState) {
        state = newState
        hotKey.setRecordingActive(newState == .listening)
        overlay.show(
            state: newState,
            mode: activeMode ?? configuration.selectedMode
        )
    }

    private func fail(_ error: Error) {
        let message = ErrorMessagePresenter.message(for: error)
        let failedMode = activeMode ?? configuration.selectedMode
        isHotKeyHeld = false
        isStartingRecording = false
        isPracticeSession = false
        activeMode = nil
        shortcutBehavior = hotKey.behavior
        hotKey.setRecordingActive(false)
        liveSpeechTranscriber.stop()
        state = .failure(message)
        overlay.show(
            state: .failure(message),
            mode: failedMode
        )
        playFeedbackSound(.issue)
    }

    private func playFeedbackSound(_ cue: FeedbackSoundCue) {
        guard configuration.playFeedbackSounds else { return }

        activeFeedbackSound?.stop()

        if let sound = customSounds[cue.resourceName] {
            sound.currentTime = 0
            activeFeedbackSound = sound
            sound.play()
            return
        }

        if let url = Bundle.main.url(
            forResource: cue.resourceName,
            withExtension: "wav",
            subdirectory: "Sounds"
        ), let sound = NSSound(contentsOf: url, byReference: true) {
            sound.volume = cue.volume
            customSounds[cue.resourceName] = sound
            activeFeedbackSound = sound
            sound.play()
            return
        }

        NSSound(named: NSSound.Name(cue.fallbackSystemSound))?.play()
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case history
    case prompts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return OpenTypeL10n.text("输入", english: "Input")
        case .history: return OpenTypeL10n.text("历史", english: "History")
        case .prompts: return "Prompt"
        case .settings: return OpenTypeL10n.text("设置", english: "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .home: return "waveform"
        case .history: return "clock.arrow.circlepath"
        case .prompts: return "text.bubble"
        case .settings: return "slider.horizontal.3"
        }
    }
}
