import Foundation

enum InputMode: String, CaseIterable, Codable, Identifiable {
    case clean
    case english
    case instruction
    case xReply
    case command
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean, .command: return OpenTypeL10n.text("智能编辑", english: "Smart Edit")
        case .english: return OpenTypeL10n.text("中转英", english: "English")
        case .instruction: return OpenTypeL10n.text("Agent 模式", english: "Agent")
        case .xReply: return "X Reply"
        case .raw: return OpenTypeL10n.text("文字转写", english: "Transcribe")
        }
    }

    var shortTitle: String {
        switch self {
        case .clean: return OpenTypeL10n.text("说话整理 · 选中修改", english: "Dictate · Edit selection")
        case .english: return OpenTypeL10n.text("中文 → English", english: "Chinese → English")
        case .instruction: return OpenTypeL10n.text("任务执行 · 长期记忆", english: "Tasks · Long-term memory")
        case .xReply: return OpenTypeL10n.text("有观点就说 · 没有也能回", english: "Join the conversation")
        case .command: return OpenTypeL10n.text("有选区：按指令修改", english: "Selection: edit by instruction")
        case .raw: return OpenTypeL10n.text("去口癖 · 保留原话", english: "Clean filler · Keep your words")
        }
    }

    var symbol: String {
        switch self {
        case .clean, .command: return "wand.and.stars"
        case .english: return "globe.americas.fill"
        case .instruction: return "brain.head.profile"
        case .xReply: return "bubble.left.and.bubble.right.fill"
        case .raw: return "waveform"
        }
    }

    var requiresSelection: Bool {
        self == .xReply || self == .command
    }

    var supportsCustomPrompt: Bool {
        true
    }

    var next: InputMode {
        let modes = Self.visibleModes
        guard let index = modes.firstIndex(of: self) else { return .clean }
        return modes[(index + 1) % modes.count]
    }

    static let visibleModes: [InputMode] = [
        .clean,
        .english,
        .instruction,
        .xReply,
        .raw
    ]

    var explanation: String {
        switch self {
        case .clean:
            return OpenTypeL10n.text("直接说话会自动整理；选中文字后按指令修改", english: "Dictate to clean up; select text to edit it by instruction")
        case .english:
            return OpenTypeL10n.text("中文口述，直接写成地道英文", english: "Speak Chinese and get natural English")
        case .instruction:
            return OpenTypeL10n.text("说出目标，结合最近任务生成可直接使用的结果", english: "Describe a goal and create a ready-to-use result with recent context")
        case .xReply:
            return OpenTypeL10n.text("加入对话；有观点就说，没有也能自动回复", english: "Join the conversation with your take, or let OpenType draft one")
        case .command:
            return OpenTypeL10n.text("智能编辑的选中文字分支", english: "Selected-text branch of Smart Edit")
        case .raw:
            return OpenTypeL10n.text("保留原话，只清理口癖、重复和基础标点", english: "Keep your wording; clean only filler, repetition, and punctuation")
        }
    }

}

enum XReplyStyle: String, CaseIterable, Codable, Identifiable {
    case adaptive
    case concise
    case friendly
    case sharp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adaptive: return OpenTypeL10n.text("自动判断", english: "Adaptive")
        case .concise: return OpenTypeL10n.text("简短直接", english: "Short & direct")
        case .friendly: return OpenTypeL10n.text("友好交流", english: "Friendly")
        case .sharp: return OpenTypeL10n.text("有一点锋芒", english: "A little sharp")
        }
    }

    var promptInstruction: String {
        switch self {
        case .adaptive:
            return "Match the social temperature of the exchange. If the user's thought is casual or rough-edged, keep it that way instead of upgrading it into polished commentary."
        case .concise:
            return "Use the shortest natural wording that carries the user's point. Prefer one sentence and stop as soon as the point lands."
        case .friendly:
            return "Sound open and conversational. Add warmth only through phrasing; do not add praise, agreement, or a question the user did not express."
        case .sharp:
            return "State the user's disagreement or distinction cleanly. Keep the edge in the idea, not in grand phrasing, sarcasm, or performative provocation."
        }
    }
}

enum FeedbackSoundCue: String, CaseIterable, Identifiable {
    case ready
    case release
    case done
    case issue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready: return OpenTypeL10n.text("开始说话", english: "Start speaking")
        case .release: return OpenTypeL10n.text("结束录音", english: "Stop recording")
        case .done: return OpenTypeL10n.text("完成写入", english: "Inserted")
        case .issue: return OpenTypeL10n.text("出现问题", english: "Issue")
        }
    }

    var resourceName: String {
        switch self {
        case .ready: return "OpenTypeReady"
        case .release: return "OpenTypeRelease"
        case .done: return "OpenTypeDone"
        case .issue: return "OpenTypeIssue"
        }
    }

    var volume: Float {
        switch self {
        case .ready: return 0.70
        case .release: return 0.64
        case .done: return 0.64
        case .issue: return 0.58
        }
    }

    var fallbackSystemSound: String {
        switch self {
        case .ready: return "Tink"
        case .release: return "Pop"
        case .done: return "Glass"
        case .issue: return "Basso"
        }
    }
}

enum ProcessingState: Equatable {
    case idle
    case modeChanged
    case listening
    case transcribing
    case transforming
    case inserting
    case success
    case copied
    case cancelled(String)
    case failure(String)

    var title: String {
        switch self {
        case .idle: return OpenTypeL10n.text("就绪", english: "Ready")
        case .modeChanged: return OpenTypeL10n.text("已切换模式", english: "Mode changed")
        case .listening: return OpenTypeL10n.text("正在听", english: "Listening")
        case .transcribing: return OpenTypeL10n.text("正在识别", english: "Transcribing")
        case .transforming: return OpenTypeL10n.text("正在整理", english: "Refining")
        case .inserting: return OpenTypeL10n.text("正在写入", english: "Inserting")
        case .success: return OpenTypeL10n.text("完成", english: "Done")
        case .copied: return OpenTypeL10n.text("已复制", english: "Copied")
        case .cancelled: return OpenTypeL10n.text("未执行", english: "Not run")
        case .failure: return OpenTypeL10n.text("出现问题", english: "Something went wrong")
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "waveform"
        case .modeChanged: return "arrow.triangle.2.circlepath"
        case .listening: return "mic.fill"
        case .transcribing: return "waveform.badge.magnifyingglass"
        case .transforming: return "sparkles"
        case .inserting: return "text.cursor"
        case .success: return "circle.fill"
        case .copied: return "doc.on.clipboard.fill"
        case .cancelled: return "circle.slash"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    func overlayDetail(for mode: InputMode) -> String {
        switch self {
        case .cancelled(let message):
            return message
        case .failure(let message):
            return message
        case .copied where mode == .xReply:
            return OpenTypeL10n.text("在 X 回复框按 ⌘V 粘贴", english: "Press ⌘V in the X reply box")
        case .success where mode == .command:
            return OpenTypeL10n.text("已替换 · 结果也已复制", english: "Replaced · Also copied")
        case .copied where mode == .command:
            return OpenTypeL10n.text("结果已复制，可直接粘贴", english: "Copied and ready to paste")
        default:
            return mode.title
        }
    }
}

enum OutputDeliveryStrategy: Equatable {
    case automaticInsert
    case clipboard
}

enum SmartEditRouter {
    static func mode(
        selectedMode: InputMode,
        selectedText: String?
    ) -> InputMode {
        guard selectedMode == .clean else { return selectedMode }
        let hasSelection = selectedText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        return hasSelection ? .command : .clean
    }
}

enum OutputDeliveryPolicy {
    static func strategy(
        for mode: InputMode,
        automaticallyInsert: Bool
    ) -> OutputDeliveryStrategy {
        if mode == .xReply { return .clipboard }
        return automaticallyInsert ? .automaticInsert : .clipboard
    }

    static func retainsClipboardCopy(for mode: InputMode) -> Bool {
        // Clipboard availability is a product-level guarantee. Automatic
        // insertion is an additional delivery action, not a replacement for
        // keeping the generated result available to paste.
        true
    }

    static func permitsAutomaticEnter(for mode: InputMode) -> Bool {
        mode != .xReply && mode != .instruction
    }

}

enum PermissionStatus: Equatable {
    case notDetermined
    case granted
    case denied

    var title: String {
        switch self {
        case .notDetermined: return OpenTypeL10n.text("待授权", english: "Permission needed")
        case .granted: return OpenTypeL10n.text("已就绪", english: "Ready")
        case .denied: return OpenTypeL10n.text("未授权", english: "Not allowed")
        }
    }

    var symbol: String {
        switch self {
        case .notDetermined: return "circle.dashed"
        case .granted: return "circle.fill"
        case .denied: return "exclamationmark.circle.fill"
        }
    }
}

enum HotKeyPreset: String, CaseIterable, Codable, Identifiable {
    case leftOption
    case doubleControl
    case doubleOption
    case doubleShift
    case controlShiftSpace
    case optionSpace
    case controlSpace
    case controlOptionSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftOption: return OpenTypeL10n.text("左 Option", english: "Left Option")
        case .doubleControl: return OpenTypeL10n.text("双击 Ctrl", english: "Double-tap Ctrl")
        case .doubleOption: return OpenTypeL10n.text("双击 Option", english: "Double-tap Option")
        case .doubleShift: return OpenTypeL10n.text("双击 Shift", english: "Double-tap Shift")
        case .controlShiftSpace: return "⌃⇧ Space"
        case .optionSpace: return "⌥ Space"
        case .controlSpace: return "⌃ Space"
        case .controlOptionSpace: return "⌃⌥ Space"
        }
    }

    var keys: [String] {
        switch self {
        case .leftOption: return ["左 Option"]
        case .doubleControl: return ["Ctrl × 2"]
        case .doubleOption: return ["Option × 2"]
        case .doubleShift: return ["Shift × 2"]
        case .controlShiftSpace: return ["⌃", "⇧", "Space"]
        case .optionSpace: return ["⌥", "Space"]
        case .controlSpace: return ["⌃", "Space"]
        case .controlOptionSpace: return ["⌃", "⌥", "Space"]
        }
    }

    var usesDoubleModifierTap: Bool {
        switch self {
        case .doubleControl, .doubleOption, .doubleShift: return true
        default: return false
        }
    }

    var usesModifierOnlyEventTap: Bool {
        self == .leftOption || usesDoubleModifierTap
    }

    var usesOptionHybridGesture: Bool {
        self == .leftOption
    }

    var note: String {
        switch self {
        case .leftOption:
            return OpenTypeL10n.text("长按说话、松开完成；双击开始，再按任意普通键结束。右 Option 保持空闲。", english: "Hold to talk and release to finish; double-tap to start and press any regular key to stop. Right Option stays free.")
        case .doubleControl:
            return OpenTypeL10n.text("推荐。两次轻点任意一侧 Ctrl。", english: "Recommended. Tap either Ctrl key twice.")
        case .doubleOption:
            return OpenTypeL10n.text("可能与部分输入法的 Option 快捷键冲突。", english: "May conflict with Option shortcuts in some input methods.")
        case .doubleShift:
            return OpenTypeL10n.text("适合不常连续使用 Shift 的键盘习惯。", english: "Useful if you rarely tap Shift twice in succession.")
        case .controlShiftSpace:
            return OpenTypeL10n.text("不占用 Option；没有辅助功能权限时可按住说话。", english: "Keeps Option free; hold to talk without Accessibility permission.")
        case .optionSpace, .controlSpace, .controlOptionSpace:
            return OpenTypeL10n.text("按一次开始；授权辅助功能后，按任意普通键结束。", english: "Press once to start; with Accessibility permission, press any regular key to stop.")
        }
    }
}

enum HotKeyBehavior: Equatable {
    case optionHybrid
    case doubleTapThenAnyKey
    case pressThenAnyKey
    case holdToTalk
}

struct CapturedContext {
    var selectedText: String?
    var applicationName: String
    var bundleIdentifier: String?
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let mode: InputMode
    let applicationName: String
    let transcript: String
    let result: String
    let contextPreview: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        mode: InputMode,
        applicationName: String,
        transcript: String,
        result: String,
        contextPreview: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.applicationName = applicationName
        self.transcript = transcript
        self.result = result
        self.contextPreview = contextPreview
    }
}

struct AgentTaskMemory: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let request: String
    let outcome: String
    let applicationName: String
    let referencePreview: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        request: String,
        outcome: String,
        applicationName: String,
        referencePreview: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.request = request
        self.outcome = outcome
        self.applicationName = applicationName
        self.referencePreview = referencePreview
    }

    var estimatedPromptCharacters: Int {
        min(request.count, 900)
            + min(outcome.count, 2_400)
            + min(referencePreview?.count ?? 0, 600)
            + applicationName.count
            + 120
    }
}

struct MemoryEvent: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let mode: InputMode
    let applicationName: String
    let bundleIdentifier: String?
    let rawTranscript: String
    let effectiveInput: String
    let selectedContext: String?
    let result: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        mode: InputMode,
        applicationName: String,
        bundleIdentifier: String?,
        rawTranscript: String,
        effectiveInput: String,
        selectedContext: String?,
        result: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.rawTranscript = rawTranscript
        self.effectiveInput = effectiveInput
        self.selectedContext = selectedContext
        self.result = result
    }
}

enum ProfileLanguagePreference: String, CaseIterable, Codable, Identifiable {
    case followInput
    case chinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followInput:
            return OpenTypeL10n.text(
                "跟随当前模式与输入",
                english: "Follow the current mode and input"
            )
        case .chinese:
            return OpenTypeL10n.text(
                "中文（仅在未指定时）",
                english: "Chinese (only when unspecified)"
            )
        case .english:
            return OpenTypeL10n.text(
                "English（仅在未指定时）",
                english: "English (only when unspecified)"
            )
        }
    }
}

struct OwnerProfile: Codable, Equatable {
    var identityAndWork: String
    var communicationStyle: String
    var importantTerms: String
    var preferredLanguage: ProfileLanguagePreference
    var updatedAt: Date?

    init(
        identityAndWork: String,
        communicationStyle: String,
        importantTerms: String,
        preferredLanguage: ProfileLanguagePreference = .followInput,
        updatedAt: Date? = nil
    ) {
        self.identityAndWork = identityAndWork
        self.communicationStyle = communicationStyle
        self.importantTerms = importantTerms
        self.preferredLanguage = preferredLanguage
        self.updatedAt = updatedAt
    }

    static let empty = OwnerProfile(
        identityAndWork: "",
        communicationStyle: "",
        importantTerms: "",
        preferredLanguage: .followInput,
        updatedAt: nil
    )

    var isEmpty: Bool {
        let textFieldsAreEmpty = [
            identityAndWork,
            communicationStyle,
            importantTerms
        ].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return textFieldsAreEmpty && preferredLanguage == .followInput
    }
}

struct MemoryInsights: Codable, Equatable {
    let observedTaskCount: Int
    let commonTerms: [String]
    let taskDomains: [String]
    let languagePattern: String?
    let stylePreferences: [String]
    let updatedAt: Date

    static let empty = MemoryInsights(
        observedTaskCount: 0,
        commonTerms: [],
        taskDomains: [],
        languagePattern: nil,
        stylePreferences: [],
        updatedAt: .distantPast
    )

    var isEmpty: Bool {
        commonTerms.isEmpty
            && taskDomains.isEmpty
            && languagePattern == nil
            && stylePreferences.isEmpty
    }
}

struct MemoryProfileContext: Equatable {
    let ownerProfile: OwnerProfile
    let insights: MemoryInsights

    static let empty = MemoryProfileContext(
        ownerProfile: .empty,
        insights: .empty
    )

    var isEmpty: Bool {
        ownerProfile.isEmpty && insights.isEmpty
    }
}

struct TransformRequest {
    let transcript: String
    let mode: InputMode
    let context: CapturedContext
    let personalDictionary: [String]
    let xReplyStyle: XReplyStyle
    let modePromptOverride: String?
    let agentMemory: [AgentTaskMemory]
    let memoryProfile: MemoryProfileContext

    init(
        transcript: String,
        mode: InputMode,
        context: CapturedContext,
        personalDictionary: [String],
        xReplyStyle: XReplyStyle,
        modePromptOverride: String? = nil,
        agentMemory: [AgentTaskMemory] = [],
        memoryProfile: MemoryProfileContext = .empty
    ) {
        self.transcript = transcript
        self.mode = mode
        self.context = context
        self.personalDictionary = personalDictionary
        self.xReplyStyle = xReplyStyle
        self.modePromptOverride = modePromptOverride
        self.agentMemory = agentMemory
        self.memoryProfile = memoryProfile
    }
}

enum OpenTypeError: LocalizedError {
    case missingCredential
    case microphoneDenied
    case recordingFailed(String)
    case emptyRecording
    case invalidResponse
    case service(String)
    case accessibilityRequired
    case selectionRequired(InputMode)
    case missingEditInstruction

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "请先在设置中配置当前选择的语音与文字服务"
        case .microphoneDenied:
            return "需要麦克风权限才能录音"
        case .recordingFailed(let detail):
            return "录音失败：\(detail)"
        case .emptyRecording:
            return "没有听到有效语音"
        case .invalidResponse:
            return "云端返回了无法识别的结果"
        case .service(let detail):
            return detail
        case .accessibilityRequired:
            return "请先开启辅助功能权限，再使用选中文字或自动写入"
        case .selectionRequired(let mode):
            switch mode {
            case .xReply:
                return "请先选中要回复的推文，再开始说话"
            case .command:
                return "请先选中要编辑的文字，再开始说话"
            default:
                return "这个模式需要先选中文字"
            }
        case .missingEditInstruction:
            return "没有听到明确的修改指令，选中文字保持不变"
        }
    }
}

enum ErrorMessagePresenter {
    static func message(for error: Error) -> String {
        if let openTypeError = error as? OpenTypeError {
            switch openTypeError {
            case .service(let detail):
                return serviceMessage(detail)
            default:
                return openTypeError.errorDescription ?? "出现了一个问题，请再试一次"
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "当前没有网络连接，联网后再试一次"
            case .timedOut:
                return "云端处理超时，请再试一次"
            default:
                return "网络连接不稳定，请再试一次"
            }
        }

        return error.localizedDescription
    }

    private static func serviceMessage(_ detail: String) -> String {
        let normalized = detail.lowercased()
        if normalized.contains("invalidparameter")
            || normalized.contains("does not support this input") {
            return "这段语音没有识别成功，请再说一次"
        }
        if normalized.contains("timeout") || normalized.contains("timed out") {
            return "云端处理超时，请再试一次"
        }
        if normalized.contains("rate limit") || normalized.contains("throttl") {
            return "请求太频繁了，稍等几秒再试"
        }
        if normalized.contains("unauthorized")
            || normalized.contains("invalid api-key")
            || normalized.contains("invalid api key") {
            return "DashScope 连接已失效，请检查 API key"
        }
        return detail
    }
}
