import Foundation

@MainActor
final class AppConfiguration: ObservableObject {
    @Published var selectedMode: InputMode {
        didSet { defaults.set(selectedMode.rawValue, forKey: Keys.selectedMode) }
    }

    @Published var xReplyStyle: XReplyStyle {
        didSet { defaults.set(xReplyStyle.rawValue, forKey: Keys.xReplyStyle) }
    }

    @Published var hotKeyPreset: HotKeyPreset {
        didSet { defaults.set(hotKeyPreset.rawValue, forKey: Keys.hotKeyPreset) }
    }

    @Published var colorTheme: AppColorTheme {
        didSet { defaults.set(colorTheme.rawValue, forKey: Keys.colorTheme) }
    }

    @Published var interfaceLanguage: InterfaceLanguage {
        didSet {
            defaults.set(interfaceLanguage.rawValue, forKey: Keys.interfaceLanguage)
            OpenTypeL10n.language = interfaceLanguage
        }
    }

    @Published var speechProvider: AIProvider {
        didSet { defaults.set(speechProvider.rawValue, forKey: Keys.speechProvider) }
    }

    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet {
            defaults.set(
                transcriptionLanguage.rawValue,
                forKey: Keys.transcriptionLanguage
            )
        }
    }

    @Published var textProvider: AIProvider {
        didSet { defaults.set(textProvider.rawValue, forKey: Keys.textProvider) }
    }

    @Published private(set) var speechModels: [String: String] {
        didSet { defaults.set(speechModels, forKey: Keys.speechModels) }
    }

    @Published private(set) var textModels: [String: String] {
        didSet { defaults.set(textModels, forKey: Keys.textModels) }
    }

    @Published var automaticallyInsert: Bool {
        didSet { defaults.set(automaticallyInsert, forKey: Keys.automaticallyInsert) }
    }

    @Published var keepHistory: Bool {
        didSet { defaults.set(keepHistory, forKey: Keys.keepHistory) }
    }

    @Published var agentMemoryEnabled: Bool {
        didSet { defaults.set(agentMemoryEnabled, forKey: Keys.agentMemoryEnabled) }
    }

    @Published var automaticOwnerProfileUpdates: Bool {
        didSet {
            defaults.set(
                automaticOwnerProfileUpdates,
                forKey: Keys.automaticOwnerProfileUpdates
            )
        }
    }

    @Published var pressEnterCommand: Bool {
        didSet { defaults.set(pressEnterCommand, forKey: Keys.pressEnterCommand) }
    }

    @Published var playFeedbackSounds: Bool {
        didSet { defaults.set(playFeedbackSounds, forKey: Keys.playFeedbackSounds) }
    }

    @Published var liveCaptionsEnabled: Bool {
        didSet { defaults.set(liveCaptionsEnabled, forKey: Keys.liveCaptionsEnabled) }
    }

    @Published var personalDictionaryText: String {
        didSet { defaults.set(personalDictionaryText, forKey: Keys.personalDictionaryText) }
    }

    @Published private(set) var promptOverrides: [String: String] {
        didSet { defaults.set(promptOverrides, forKey: Keys.promptOverrides) }
    }

    private let defaults: UserDefaults

    var personalDictionary: [String] {
        personalDictionaryText
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isMuted: Bool {
        get { !playFeedbackSounds }
        set { playFeedbackSounds = !newValue }
    }

    var serviceSelection: AIServiceSelection {
        AIServiceSelection(
            speechProvider: speechProvider,
            speechModel: speechModel(for: speechProvider),
            transcriptionLanguage: transcriptionLanguage,
            textProvider: textProvider,
            textModel: textModel(for: textProvider)
        )
    }

    func speechModel(for provider: AIProvider) -> String {
        speechModels[provider.rawValue]
            ?? provider.defaultSpeechModel
            ?? ""
    }

    func textModel(for provider: AIProvider) -> String {
        textModels[provider.rawValue]
            ?? provider.defaultTextModel
            ?? ""
    }

    func updateSpeechModel(_ model: String, for provider: AIProvider) {
        var updated = speechModels
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == provider.defaultSpeechModel {
            updated.removeValue(forKey: provider.rawValue)
        } else {
            updated[provider.rawValue] = model
        }
        speechModels = updated
    }

    func updateTextModel(_ model: String, for provider: AIProvider) {
        var updated = textModels
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == provider.defaultTextModel {
            updated.removeValue(forKey: provider.rawValue)
        } else {
            updated[provider.rawValue] = model
        }
        textModels = updated
    }

    func promptOverride(for mode: InputMode) -> String? {
        promptOverrides[mode.rawValue]
    }

    func promptText(for mode: InputMode) -> String {
        promptOverride(for: mode) ?? PromptBuilder.defaultModePrompt(for: mode)
    }

    func hasCustomPrompt(for mode: InputMode) -> Bool {
        promptOverride(for: mode) != nil
    }

    func updatePrompt(_ text: String, for mode: InputMode) {
        guard mode.supportsCustomPrompt else { return }
        var updated = promptOverrides
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultText = PromptBuilder.defaultModePrompt(for: mode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == defaultText {
            updated.removeValue(forKey: mode.rawValue)
        } else {
            updated[mode.rawValue] = text
        }
        promptOverrides = updated
    }

    func resetPrompt(for mode: InputMode) {
        var updated = promptOverrides
        updated.removeValue(forKey: mode.rawValue)
        promptOverrides = updated
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedMode = InputMode(
            rawValue: defaults.string(forKey: Keys.selectedMode) ?? ""
        ) ?? .clean
        selectedMode = savedMode == .command ? .clean : savedMode
        xReplyStyle = XReplyStyle(
            rawValue: defaults.string(forKey: Keys.xReplyStyle) ?? ""
        ) ?? .adaptive
        hotKeyPreset = HotKeyPreset(
            rawValue: defaults.string(forKey: Keys.hotKeyPreset) ?? ""
        ) ?? .leftOption
        colorTheme = AppColorTheme(
            rawValue: defaults.string(forKey: Keys.colorTheme) ?? ""
        ) ?? .ocean
        interfaceLanguage = InterfaceLanguage(
            rawValue: defaults.string(forKey: Keys.interfaceLanguage) ?? ""
        ) ?? .chinese
        speechProvider = AIProvider(
            rawValue: defaults.string(forKey: Keys.speechProvider) ?? ""
        ).flatMap { $0.supportsSpeechRecognition ? $0 : nil } ?? .dashScope
        transcriptionLanguage = TranscriptionLanguage(
            rawValue: defaults.string(forKey: Keys.transcriptionLanguage) ?? ""
        ) ?? .automatic
        textProvider = AIProvider(
            rawValue: defaults.string(forKey: Keys.textProvider) ?? ""
        ).flatMap { $0.supportsTextGeneration ? $0 : nil } ?? .dashScope
        speechModels = defaults.dictionary(forKey: Keys.speechModels)
            as? [String: String] ?? [:]
        var savedTextModels = defaults.dictionary(forKey: Keys.textModels)
            as? [String: String] ?? [:]
        if savedTextModels[AIProvider.dashScope.rawValue] == nil,
           let legacyModel = defaults.string(forKey: Keys.textModel),
           !legacyModel.isEmpty {
            savedTextModels[AIProvider.dashScope.rawValue] = legacyModel
        }
        textModels = savedTextModels
        automaticallyInsert = defaults.object(forKey: Keys.automaticallyInsert) as? Bool ?? true
        keepHistory = defaults.object(forKey: Keys.keepHistory) as? Bool ?? true
        agentMemoryEnabled = defaults.object(forKey: Keys.agentMemoryEnabled) as? Bool ?? true
        automaticOwnerProfileUpdates = defaults.object(
            forKey: Keys.automaticOwnerProfileUpdates
        ) as? Bool ?? true
        pressEnterCommand = defaults.object(forKey: Keys.pressEnterCommand) as? Bool ?? false
        playFeedbackSounds = defaults.object(forKey: Keys.playFeedbackSounds) as? Bool ?? true
        liveCaptionsEnabled = defaults.object(forKey: Keys.liveCaptionsEnabled) as? Bool ?? true
        personalDictionaryText = defaults.string(forKey: Keys.personalDictionaryText)
            ?? "Rain, OpenType, OpenClaw, Mingle, Clawborn"
        promptOverrides = defaults.dictionary(forKey: Keys.promptOverrides)
            as? [String: String] ?? [:]
        OpenTypeL10n.language = interfaceLanguage
    }

    private enum Keys {
        static let selectedMode = "selectedMode"
        static let xReplyStyle = "xReplyStyle"
        static let hotKeyPreset = "hotKeyPreset"
        static let colorTheme = "colorTheme"
        static let interfaceLanguage = "interfaceLanguage"
        static let textModel = "textModel"
        static let speechProvider = "speechProvider"
        static let transcriptionLanguage = "transcriptionLanguage"
        static let textProvider = "textProvider"
        static let speechModels = "speechModels"
        static let textModels = "textModels"
        static let automaticallyInsert = "automaticallyInsert"
        static let keepHistory = "keepHistory"
        static let agentMemoryEnabled = "agentMemoryEnabled"
        static let automaticOwnerProfileUpdates = "automaticOwnerProfileUpdates"
        static let pressEnterCommand = "pressEnterCommand"
        static let playFeedbackSounds = "playFeedbackSounds"
        static let liveCaptionsEnabled = "liveCaptionsEnabled"
        static let personalDictionaryText = "personalDictionaryText"
        static let promptOverrides = "promptOverrides"
    }
}
