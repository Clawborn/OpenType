import AppKit
import SwiftUI

private enum OpenTypeTheme {
    static let surface = Color.primary.opacity(0.045)
    static let elevatedSurface = Color.primary.opacity(0.065)
    static let border = Color.primary.opacity(0.075)
    static let subtleText = Color.secondary.opacity(0.88)
}

private extension View {
    func openTypeSurface(
        cornerRadius: CGFloat = 16,
        selected: Bool = false
    ) -> some View {
        self
            .background(
                selected
                    ? Color.accentColor.opacity(0.11)
                    : OpenTypeTheme.surface,
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    selected
                        ? Color.accentColor.opacity(0.24)
                        : OpenTypeTheme.border,
                    lineWidth: 0.75
                )
            )
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var configuration: AppConfiguration

    init(model: AppModel) {
        self.model = model
        self.configuration = model.configuration
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model, configuration: model.configuration)

            Group {
                switch model.selectedTab {
                case .home:
                    HomeView(model: model, configuration: model.configuration)
                case .history:
                    HistoryView(model: model)
                case .prompts:
                    PromptStudioView(
                        model: model,
                        configuration: model.configuration,
                        agentMemory: model.agentMemory
                    )
                case .settings:
                    SettingsView(
                        model: model,
                        configuration: model.configuration,
                        agentMemory: model.agentMemory
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(model: model)
        }
        .frame(width: 424, height: 568)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        configuration.colorTheme.accent.opacity(0.045),
                        configuration.colorTheme.secondaryAccent.opacity(0.018),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
        }
        .tint(configuration.colorTheme.accent)
        .environment(\.locale, configuration.interfaceLanguage.locale)
    }
}

private struct HeaderView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var configuration: AppConfiguration

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                configuration.colorTheme.accent,
                                configuration.colorTheme.secondaryAccent
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .shadow(
                color: Color.accentColor.opacity(0.22),
                radius: 7,
                y: 3
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("OpenType")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                    Text(configuration.selectedMode.title)
                        .font(.system(size: 10.5, weight: .medium))
                    Text("·")
                    Text(configuration.selectedMode.shortTitle)
                        .font(.system(size: 10.5))
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.quit()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 27, height: 27)
                    .background(
                        OpenTypeTheme.surface,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .help("退出 OpenType")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OpenTypeTheme.border)
                .frame(height: 0.5)
        }
    }
}

private struct HomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var configuration: AppConfiguration

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !model.setupReady {
                    SetupCard(model: model)
                }

                ShortcutHero(
                    state: model.state,
                    behavior: model.shortcutBehavior
                )

                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("模式")

                    ModeGrid(model: model, configuration: configuration)
                }

                if !model.lastResult.isEmpty {
                    LastResultCard(model: model)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ShortcutHero: View {
    let state: ProcessingState
    let behavior: HotKeyBehavior

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(stateColor.opacity(0.12))
                Image(systemName: state.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(stateColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(cardTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(stateSubtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(OpenTypeTheme.subtleText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .openTypeSurface(cornerRadius: 15)
    }

    private var cardTitle: String {
        switch state {
        case .idle, .modeChanged, .success, .copied, .cancelled:
            return OpenTypeL10n.text("开始语音输入", english: "Start voice input")
        case .listening:
            return OpenTypeL10n.text("正在听", english: "Listening")
        default:
            return state.title
        }
    }

    private var stateSubtitle: String {
        switch state {
        case .idle, .modeChanged, .success:
            return gestureHint
        case .copied:
            return OpenTypeL10n.text("已复制到剪贴板，按 ⌘V 即可粘贴", english: "Copied. Press ⌘V to paste")
        case .cancelled(let message):
            return message
        case .listening:
            return stopHint
        case .transcribing:
            return OpenTypeL10n.text("正在识别语音", english: "Transcribing speech")
        case .transforming:
            return OpenTypeL10n.text("正在整理表达", english: "Refining your words")
        case .inserting:
            return OpenTypeL10n.text("正在写入当前应用", english: "Inserting into the current app")
        case .failure(let message):
            return message
        }
    }

    private var gestureHint: String {
        switch behavior {
        case .optionHybrid:
            return OpenTypeL10n.text("按住说话，或双击后连续录音", english: "Hold to talk, or double-tap for continuous recording")
        case .doubleTapThenAnyKey:
            return OpenTypeL10n.text("双击开始，完成时按任意键", english: "Double-tap to start; press any key to finish")
        case .pressThenAnyKey:
            return OpenTypeL10n.text("按一下开始，完成时按任意键", english: "Press once to start; press any key to finish")
        case .holdToTalk:
            return OpenTypeL10n.text("按住说话，松开完成", english: "Hold to talk; release to finish")
        }
    }

    private var stopHint: String {
        behavior == .holdToTalk
            ? OpenTypeL10n.text("松开完成", english: "Release to finish")
            : OpenTypeL10n.text("完成时按任意键", english: "Press any key to finish")
    }

    private var stateColor: Color {
        switch state {
        case .failure: return .red
        case .success, .copied: return Color.accentColor
        case .listening: return .red
        default: return Color.accentColor
        }
    }
}

private struct ModeGrid: View {
    @ObservedObject var model: AppModel
    @ObservedObject var configuration: AppConfiguration

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                modeCard(.clean)
                modeCard(.english)
            }
            GridRow {
                modeCard(.instruction)
                modeCard(.xReply)
            }
            GridRow {
                modeCard(.raw)
                    .gridCellColumns(2)
            }
        }
    }

    private func modeCard(_ mode: InputMode) -> some View {
        ModeCard(
            mode: mode,
            isSelected: configuration.selectedMode == mode
        ) {
            model.selectMode(mode)
        }
    }
}

private struct ModeCard: View {
    let mode: InputMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.14)
                                : Color.primary.opacity(0.045)
                        )
                    Image(systemName: mode.symbol)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? Color.accentColor : Color.secondary
                        )
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(mode.shortTitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Circle()
                        .fill(Color.accentColor.opacity(0.72))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
            .openTypeSurface(cornerRadius: 13, selected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

private struct SetupCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(OpenTypeTheme.elevatedSurface, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: setupProgress)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(completedStepCount)/\(totalStepCount)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(setupTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(setupDetail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(primaryActionTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            HStack(spacing: 6) {
                SetupStatusPill(
                    title: "云端",
                    status: model.cloudConnected ? .granted : .denied
                )
                SetupStatusPill(
                    title: "麦克风",
                    status: model.microphonePermission
                )
                SetupStatusPill(
                    title: "辅助功能",
                    status: model.accessibilityGranted ? .granted : .notDetermined
                )
                if model.configuration.liveCaptionsEnabled {
                    SetupStatusPill(
                        title: "实时字幕",
                        status: model.speechRecognitionPermission
                    )
                }

                Spacer(minLength: 0)

                if model.setupReady {
                    Button {
                        model.togglePracticeDictation()
                    } label: {
                        Label(practiceButtonTitle, systemImage: "mic")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(!model.canTogglePractice)
                }
            }
        }
        .padding(14)
        .openTypeSurface(cornerRadius: 17)
    }

    private var completedStepCount: Int {
        var checks = [
            model.cloudConnected,
            model.microphonePermission == .granted,
            model.accessibilityGranted
        ]
        if model.configuration.liveCaptionsEnabled {
            checks.append(model.speechRecognitionPermission == .granted)
        }
        return checks.filter { $0 }.count
    }

    private var totalStepCount: Int {
        model.configuration.liveCaptionsEnabled ? 4 : 3
    }

    private var setupProgress: CGFloat {
        CGFloat(completedStepCount) / CGFloat(totalStepCount)
    }

    private var setupTitle: String {
        let remaining = totalStepCount - completedStepCount
        switch remaining {
        case 0: return OpenTypeL10n.text("OpenType 已准备就绪", english: "OpenType is ready")
        case 1: return OpenTypeL10n.text("还差最后一步", english: "One step left")
        default: return OpenTypeL10n.text("再完成 \(remaining) 步", english: "\(remaining) steps left")
        }
    }

    private var setupDetail: String {
        if !model.cloudConnected {
            return OpenTypeL10n.text("先连接你的 DashScope 云端模型", english: "Connect your DashScope model first")
        }
        if model.microphonePermission != .granted {
            return OpenTypeL10n.text("允许麦克风后，就可以开始说话", english: "Allow microphone access to start speaking")
        }
        if !model.accessibilityGranted {
            return OpenTypeL10n.text("开启辅助功能后，自动启用你在设置中选择的快捷键", english: "Enable Accessibility to activate your chosen shortcut")
        }
        if model.configuration.liveCaptionsEnabled,
           model.speechRecognitionPermission != .granted {
            return OpenTypeL10n.text("允许语音识别后，说话时会显示实时字幕", english: "Allow Speech Recognition to show live captions")
        }
        return OpenTypeL10n.text("正在注册你选择的全局快捷键", english: "Registering your global shortcut")
    }

    private var primaryActionTitle: String {
        if !model.cloudConnected { return OpenTypeL10n.text("查看连接", english: "View connection") }
        if model.microphonePermission == .denied { return OpenTypeL10n.text("打开麦克风设置", english: "Open Microphone Settings") }
        if model.microphonePermission != .granted { return OpenTypeL10n.text("允许麦克风", english: "Allow Microphone") }
        if !model.accessibilityGranted { return OpenTypeL10n.text("开启辅助功能", english: "Enable Accessibility") }
        if model.configuration.liveCaptionsEnabled,
           model.speechRecognitionPermission == .denied {
            return OpenTypeL10n.text("打开字幕权限", english: "Open Caption Settings")
        }
        if model.configuration.liveCaptionsEnabled,
           model.speechRecognitionPermission != .granted {
            return OpenTypeL10n.text("允许实时字幕", english: "Allow Live Captions")
        }
        return OpenTypeL10n.text("重试", english: "Retry")
    }

    private var primaryAction: () -> Void {
        if !model.cloudConnected {
            return { model.selectedTab = .settings }
        }
        if model.microphonePermission != .granted {
            return model.requestMicrophonePermission
        }
        if !model.accessibilityGranted {
            return model.requestAccessibility
        }
        if model.configuration.liveCaptionsEnabled,
           model.speechRecognitionPermission != .granted {
            return model.requestSpeechRecognitionPermission
        }
        return model.refreshPermissionStatus
    }

    private var practiceButtonTitle: String {
        if model.isPracticeSession, model.state == .listening {
            return OpenTypeL10n.text("结束并查看", english: "Stop & review")
        }
        return model.lastResultWasPractice
            ? OpenTypeL10n.text("再试一次", english: "Try again")
            : OpenTypeL10n.text("开始试用", english: "Try it")
    }
}

private struct SetupStatusPill: View {
    let title: String
    let status: PermissionStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(statusColor)
            Text(LocalizedStringKey(title))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(OpenTypeTheme.surface, in: Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .notDetermined: return .orange
        case .granted: return .secondary
        case .denied: return .red
        }
    }
}

private struct LastResultCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionLabel(model.lastResultWasPractice ? "试用结果" : "刚刚写下")
                Spacer()
                if !model.lastApplication.isEmpty {
                    Text(model.lastApplication)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(model.lastResult)
                .font(.system(size: 12))
                .lineLimit(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button {
                    model.copyLastResult()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .controlSize(.small)

                Button {
                    model.undo()
                } label: {
                    Label("撤销写入", systemImage: "arrow.uturn.backward")
                }
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(14)
        .openTypeSurface(cornerRadius: 15)
    }
}

private struct HistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.history.entries.isEmpty {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(OpenTypeTheme.surface)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 48, height: 48)
                    Text("还没有输入历史")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("完成一次语音输入后会出现在这里")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(model.history.entries.count) 条本地记录")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 5)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.history.entries) { entry in
                            HistoryRow(model: model, entry: entry)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct HistoryRow: View {
    @ObservedObject var model: AppModel
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(entry.mode.title, systemImage: entry.mode.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(entry.createdAt, style: .relative)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            Text(entry.result)
                .font(.system(size: 12))
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            HStack {
                Text(entry.applicationName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("复制") {
                    model.copy(entry.result)
                }
                .buttonStyle(.borderless)
                Button("重新使用") {
                    model.reuse(entry)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(13)
        .openTypeSurface(cornerRadius: 14)
    }
}

private enum PromptStudioPanel: String, CaseIterable, Identifiable {
    case edit
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit: return OpenTypeL10n.text("编辑", english: "Edit")
        case .preview: return OpenTypeL10n.text("完整预览", english: "Full preview")
        }
    }
}

private struct PromptStudioView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var configuration: AppConfiguration
    @ObservedObject var agentMemory: AgentMemoryStore
    @State private var selectedMode: InputMode = .clean
    @State private var smartEditPromptBranch: InputMode = .clean
    @State private var panel: PromptStudioPanel = .edit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                introCard
                modePicker

                editorCard
                if !usesDedicatedDashScopeTranslation {
                    injectionCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
    }

    private var introCard: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Prompt Studio")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("修改模式行为；上下文与安全规则仍由系统自动注入")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .openTypeSurface(cornerRadius: 15)
    }

    private var modePicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(InputMode.visibleModes) { mode in
                    Button {
                        selectedMode = mode
                        if mode == .clean {
                            smartEditPromptBranch = .clean
                        }
                        panel = .edit
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 9.5, weight: .semibold))
                            Text(mode.title)
                                .font(.system(size: 9.5, weight: .semibold))
                            if hasCustomPromptIndicator(for: mode) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .foregroundStyle(
                            selectedMode == mode
                                ? Color.accentColor
                                : Color.secondary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            selectedMode == mode
                                ? Color.accentColor.opacity(0.11)
                                : OpenTypeTheme.surface,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    selectedMode == mode
                                        ? Color.accentColor.opacity(0.22)
                                        : OpenTypeTheme.border,
                                    lineWidth: 0.75
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(selectedMode.title)
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(editorStatusTitle)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(
                            usesDedicatedDashScopeTranslation
                                || configuration.hasCustomPrompt(for: effectivePromptMode)
                                ? Color.accentColor
                                : Color.secondary
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(OpenTypeTheme.surface, in: Capsule())
                    }
                    Text(editorScopeDescription)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !usesDedicatedDashScopeTranslation {
                    Picker("", selection: $panel) {
                        ForEach(PromptStudioPanel.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 142)
                }
            }

            if selectedMode == .clean {
                Picker("智能编辑分支", selection: $smartEditPromptBranch) {
                    Text("口述整理").tag(InputMode.clean)
                    Text("选中修改").tag(InputMode.command)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if usesDedicatedDashScopeTranslation {
                dedicatedTranslationCard
            } else if panel == .edit {
                TextEditor(text: promptBinding)
                    .font(.system(size: 10.5, design: .monospaced))
                    .frame(height: 205)
                    .padding(9)
                    .scrollContentBackground(.hidden)
                    .background(
                        Color(nsColor: .textBackgroundColor).opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(OpenTypeTheme.border, lineWidth: 0.75)
                    )
            } else {
                ScrollView {
                    Text(fullPromptPreview)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 223)
                .background(
                    Color(nsColor: .textBackgroundColor).opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(OpenTypeTheme.border, lineWidth: 0.75)
                )
            }

            HStack {
                if usesDedicatedDashScopeTranslation {
                    Text("qwen-mt-flash  ·  必要时 qwen-mt-plus")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(configuration.promptText(for: effectivePromptMode).count) 字符")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !usesDedicatedDashScopeTranslation {
                    Button("恢复默认") {
                        configuration.resetPrompt(for: effectivePromptMode)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!configuration.hasCustomPrompt(for: effectivePromptMode))

                    Button {
                        copyFullPrompt()
                    } label: {
                        Label("复制完整 Prompt", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(13)
        .openTypeSurface(cornerRadius: 15)
    }

    private var dedicatedTranslationCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 5) {
                Text(OpenTypeL10n.text("专用翻译模式", english: "Dedicated translation mode"))
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    OpenTypeL10n.text(
                        "原话会作为待翻译文本直接交给 Qwen-MT，不会作为指令执行，也不会读取聊天 Prompt。",
                        english: "Your words are sent to Qwen-MT as inert source text, never executed as an instruction and never passed through a chat prompt."
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Label(
                    OpenTypeL10n.text("自动识别源语言  →  English", english: "Auto-detect source  →  English"),
                    systemImage: "arrow.right.circle"
                )
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .padding(16)
        .background(
            Color.accentColor.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 0.75)
        )
    }

    private var injectionCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionLabel("系统自动附加")
                Spacer()
                Image(systemName: "lock.shield")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Text(injectionDescription)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .openTypeSurface(cornerRadius: 14)
    }

    private var promptBinding: Binding<String> {
        Binding(
            get: { configuration.promptText(for: effectivePromptMode) },
            set: { configuration.updatePrompt($0, for: effectivePromptMode) }
        )
    }

    private var effectivePromptMode: InputMode {
        selectedMode == .clean ? smartEditPromptBranch : selectedMode
    }

    private var usesDedicatedDashScopeTranslation: Bool {
        selectedMode == .english && configuration.textProvider == .dashScope
    }

    private var editorStatusTitle: String {
        if usesDedicatedDashScopeTranslation {
            return OpenTypeL10n.text("专用翻译", english: "Translation API")
        }
        return configuration.hasCustomPrompt(for: effectivePromptMode)
            ? OpenTypeL10n.text("已自定义", english: "Customized")
            : OpenTypeL10n.text("默认", english: "Default")
    }

    private var editorScopeDescription: String {
        if usesDedicatedDashScopeTranslation {
            return OpenTypeL10n.text(
                "原文是数据，不是指令",
                english: "Source text is data, not an instruction"
            )
        }
        guard selectedMode == .clean else {
            return OpenTypeL10n.text("自动保存，仅影响这个模式", english: "Saved automatically · Only affects this mode")
        }
        return effectivePromptMode == .command
            ? OpenTypeL10n.text("有选中文字时使用", english: "Used when text is selected")
            : OpenTypeL10n.text("没有选中文字时使用", english: "Used when no text is selected")
    }

    private func hasCustomPromptIndicator(for mode: InputMode) -> Bool {
        if mode == .clean {
            return configuration.hasCustomPrompt(for: .clean)
                || configuration.hasCustomPrompt(for: .command)
        }
        return configuration.hasCustomPrompt(for: mode)
    }

    private var fullPromptPreview: String {
        let request = TransformRequest(
            transcript: "[你的语音内容]",
            mode: effectivePromptMode,
            context: CapturedContext(
                selectedText: effectivePromptMode.requiresSelection
                    || effectivePromptMode == .instruction
                    ? "[你选中的原文]"
                    : nil,
                applicationName: "[当前应用]",
                bundleIdentifier: nil
            ),
            personalDictionary: configuration.personalDictionary,
            xReplyStyle: configuration.xReplyStyle,
            modePromptOverride: configuration.promptOverride(for: effectivePromptMode),
            agentMemory: effectivePromptMode == .instruction
                && configuration.agentMemoryEnabled
                ? agentMemory.memoriesForPrompt(
                    query: "[你的语音内容]",
                    selectedContext: "[你选中的原文]",
                    applicationName: "[当前应用]"
                )
                : [],
            memoryProfile: configuration.agentMemoryEnabled
                ? agentMemory.profileContextForPrompt()
                : .empty
        )
        return """
        SYSTEM PROMPT
        ─────────────
        \(PromptBuilder.systemPrompt(for: request))

        USER PROMPT
        ───────────
        \(PromptBuilder.userPrompt(for: request))
        """
    }

    private var injectionDescription: String {
        switch effectivePromptMode {
        case .instruction:
            return OpenTypeL10n.text("全局真实性规则、当前应用、个人词典、当前任务、存在时的选中参考文本，以及本机检索的相关记忆与最近记录。", english: "Global truthfulness rules, current app, personal dictionary, current task, selected reference text when present, and relevant local memories and recent records.")
        case .xReply:
            return OpenTypeL10n.text("全局真实性规则、当前应用、个人词典、X Reply 风格，以及选中的原推文和你的语音观点。", english: "Global truthfulness rules, current app, personal dictionary, X Reply style, selected post, and your spoken take.")
        case .command:
            return OpenTypeL10n.text("全局真实性规则、当前应用、个人词典，以及选中的原文和你的语音修改要求。", english: "Global truthfulness rules, current app, personal dictionary, selected text, and your spoken editing instruction.")
        default:
            return OpenTypeL10n.text("全局真实性规则、当前应用、个人词典，以及本次语音识别结果。", english: "Global truthfulness rules, current app, personal dictionary, and this transcription.")
        }
    }

    private func copyFullPrompt() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fullPromptPreview, forType: .string)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var configuration: AppConfiguration
    @ObservedObject var agentMemory: AgentMemoryStore
    @State private var editingProvider: AIProvider?
    @State private var tokenDraft = ""
    @State private var providerMessage = ""
    @State private var providerPendingDeletion: AIProvider?
    @State private var appearanceExpanded = false
    @State private var ownerProfileExpanded = true
    @State private var dataManagementExpanded = false
    @State private var showingHistoryResetConfirmation = false
    @State private var showingAgentMemoryResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection("外观") {
                    DisclosureGroup(isExpanded: $appearanceExpanded) {
                        VStack(alignment: .leading, spacing: 11) {
                            Picker(
                                "界面语言",
                                selection: Binding(
                                    get: { configuration.interfaceLanguage },
                                    set: { model.changeInterfaceLanguage($0) }
                                )
                            ) {
                                ForEach(InterfaceLanguage.allCases) { language in
                                    Text(language.title).tag(language)
                                }
                            }
                            .pickerStyle(.segmented)

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ],
                                spacing: 8
                            ) {
                                ForEach(AppColorTheme.allCases) { theme in
                                    colorThemeButton(theme)
                                }
                            }

                            Text("切换后立即生效，并同步应用到导航、模式选中态、语音悬浮窗和菜单栏图标。")
                                .font(.system(size: 8.8))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 10)
                    } label: {
                        HStack(spacing: 9) {
                            ZStack {
                                Circle()
                                    .fill(configuration.colorTheme.secondaryAccent)
                                    .frame(width: 15, height: 15)
                                    .offset(x: 4, y: -2)
                                Circle()
                                    .fill(configuration.colorTheme.accent)
                                    .frame(width: 17, height: 17)
                            }
                            .frame(width: 25, height: 22)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(configuration.colorTheme.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text(configuration.interfaceLanguage.title)
                                    .font(.system(size: 8.8))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(appearanceExpanded
                                ? OpenTypeL10n.text("收起", english: "Collapse")
                                : OpenTypeL10n.text("更改", english: "Change"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .contentShape(Rectangle())
                    }
                    .tint(.secondary)
                }

                SettingsSection("快捷键") {
                    Picker(
                        "启动快捷键",
                        selection: Binding(
                            get: { configuration.hotKeyPreset },
                            set: { model.changeHotKey($0) }
                        )
                    ) {
                        ForEach(HotKeyPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(configuration.hotKeyPreset.note)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)

                    Label(
                        model.shortcutStatus,
                        systemImage: shortcutStatusSymbol
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(shortcutStatusColor)
                    .fixedSize(horizontal: false, vertical: true)

                    if !model.accessibilityGranted {
                        HStack {
                            Text("开启辅助功能后，可使用双击键，并由任意键结束。")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("打开设置") {
                                model.requestAccessibility()
                            }
                            .controlSize(.small)
                        }
                    }
                }

                SettingsSection("输入体验") {
                    Toggle(
                        "完成后自动写入当前输入框",
                        isOn: $configuration.automaticallyInsert
                    )
                    Toggle(
                        "保留本地输入历史",
                        isOn: $configuration.keepHistory
                    )
                    Toggle(
                        isOn: Binding(
                            get: { configuration.isMuted },
                            set: { model.changeMuted($0) }
                        )
                    ) {
                        Label(
                            "静音",
                            systemImage: configuration.isMuted
                                ? "speaker.slash.fill"
                                : "speaker.wave.2.fill"
                        )
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("OpenType Air")
                                .font(.system(size: 10.5, weight: .medium))
                            Text("开始、结束、完成和问题使用一组低响度提示音")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Menu("试听") {
                            ForEach(FeedbackSoundCue.allCases) { cue in
                                Button(cue.title) {
                                    model.previewFeedbackSound(cue)
                                }
                            }
                        }
                        .controlSize(.small)
                        .disabled(configuration.isMuted)
                    }
                    Toggle(
                        "录音时显示实时字幕",
                        isOn: $configuration.liveCaptionsEnabled
                    )
                    if configuration.liveCaptionsEnabled,
                       model.speechRecognitionPermission != .granted {
                        HStack {
                            Text("实时字幕需要 macOS 语音识别权限")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(
                                model.speechRecognitionPermission == .denied
                                    ? "打开设置"
                                    : "授权"
                            ) {
                                model.requestSpeechRecognitionPermission()
                            }
                            .controlSize(.small)
                        }
                    }
                    Toggle(
                        "识别“发送 / press enter”命令",
                        isOn: $configuration.pressEnterCommand
                    )
                    Text("X Reply 始终复制到剪贴板，由你手动粘贴和发布。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                SettingsSection("记忆与偏好") {
                    Toggle(
                        "启用本地长期记忆与个性化",
                        isOn: $configuration.agentMemoryEnabled
                    )

                    Text("正式文字任务会追加保存原始转写、实际指令、上下文和结果。“关于我”只保存你确认的信息；系统推断的偏好会单独存放。不保存原始录音。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Label(
                            "\(agentMemory.eventCount) 条本地记录",
                            systemImage: agentMemory.databaseReady
                                ? "cylinder.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(
                            agentMemory.databaseReady ? Color.secondary : Color.orange
                        )

                        Spacer()

                        Button("显示数据库") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [agentMemory.databaseURL]
                            )
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(!agentMemory.databaseReady)
                    }

                    DisclosureGroup(
                        isExpanded: $ownerProfileExpanded
                    ) {
                        VStack(alignment: .leading, spacing: 11) {
                            Toggle(
                                "每 100 条更新“已学到的偏好”",
                                isOn: Binding(
                                    get: {
                                        configuration.automaticOwnerProfileUpdates
                                    },
                                    set: {
                                        model.changeAutomaticOwnerProfileUpdates($0)
                                    }
                                )
                            )
                            .disabled(!configuration.agentMemoryEnabled)

                            Text(automaticProfileUpdateDescription)
                                .font(.system(size: 8.8))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            profileEditor(
                                title: "我的职业与工作",
                                hint: "例如：我在做 AI Agent 产品，平时需要写产品方案和社交媒体内容。只填写确认的事实。",
                                text: ownerProfileBinding(for: .identityAndWork)
                            )
                            VStack(alignment: .leading, spacing: 5) {
                                Text("默认输出语言")
                                    .font(.system(size: 9.5, weight: .semibold))
                                Picker(
                                    "默认输出语言",
                                    selection: preferredLanguageBinding
                                ) {
                                    ForEach(ProfileLanguagePreference.allCases) { language in
                                        Text(language.title).tag(language)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                Text("只在当前指令和模式都没有指定语言时使用。“中转英”等模式规则始终优先。")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            profileEditor(
                                title: "我喜欢的表达方式",
                                hint: "例如：简洁、直接、口语化，避免公关腔和明显的 AI 味。语言选择请使用上方单独设置。",
                                text: ownerProfileBinding(for: .communicationStyle)
                            )
                            profileEditor(
                                title: "重要术语与正确拼写",
                                hint: "例如：OpenType、OpenClaw、Mingle、Clawborn。",
                                text: ownerProfileBinding(for: .importantTerms),
                                height: 54
                            )
                        }
                        .padding(.top, 9)
                    } label: {
                        Label("关于我", systemImage: "person.text.rectangle")
                            .font(.system(size: 10.5, weight: .semibold))
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label("已学到的偏好", systemImage: "sparkles")
                                .font(.system(size: 10.5, weight: .semibold))
                            Spacer()
                            Text("自动归纳 · 只作参考")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }

                        if agentMemory.learnedPreferences.isEmpty {
                            Text("每完成 100 条正式输入，OpenType 会在本机归纳一次术语、任务和表达偏好。这些推断不会改写“关于我”。")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        } else {
                            memoryInsightRow(
                                "常用术语",
                                values: agentMemory.learnedPreferences.commonTerms
                            )
                            memoryInsightRow(
                                "常见任务",
                                values: agentMemory.learnedPreferences.taskDomains
                            )
                            memoryInsightRow(
                                "语言习惯",
                                values: agentMemory.learnedPreferences.languagePattern.map { [$0] } ?? []
                            )
                            memoryInsightRow(
                                "表达偏好",
                                values: agentMemory.learnedPreferences.stylePreferences
                            )
                        }
                    }

                    Text("当前明确指令 > 当前模式 > 关于我 > 已学到的偏好。系统只会把与当前任务相关的最少信息发送给你选择的文字模型。")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !agentMemory.entries.isEmpty {
                        Divider()
                        Text("最近 Agent 任务")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(agentMemory.entries.prefix(3)) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.request)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1)
                                Text(entry.outcome)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(
                                Color.primary.opacity(0.028),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        }
                    }
                }

                SettingsSection("AI 服务") {
                    Picker(
                        "转写语言",
                        selection: Binding(
                            get: { configuration.transcriptionLanguage },
                            set: { model.changeTranscriptionLanguage($0) }
                        )
                    ) {
                        ForEach(TranscriptionLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("中英夹杂或一段音频包含多种语言时，请使用“自动识别”；单一语言可明确选择，以提高识别准确率。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker(
                        "语音识别",
                        selection: Binding(
                            get: { configuration.speechProvider },
                            set: { model.changeSpeechProvider($0) }
                        )
                    ) {
                        ForEach(AIProvider.speechProviders) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField(
                        "语音模型 ID",
                        text: Binding(
                            get: {
                                configuration.speechModel(
                                    for: configuration.speechProvider
                                )
                            },
                            set: { model.updateSpeechModel($0) }
                        )
                    )

                    Picker(
                        "文字生成",
                        selection: Binding(
                            get: { configuration.textProvider },
                            set: { model.changeTextProvider($0) }
                        )
                    ) {
                        ForEach(AIProvider.textProviders) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField(
                        "文字模型 ID",
                        text: Binding(
                            get: {
                                configuration.textModel(
                                    for: configuration.textProvider
                                )
                            },
                            set: { model.updateTextModel($0) }
                        )
                    )

                    Divider()

                    HStack {
                        Text("Provider Vault")
                            .font(.system(size: 10.5, weight: .semibold))
                        Spacer()
                        Label("本地加密", systemImage: "lock.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(AIProvider.allCases) { provider in
                        ProviderCredentialRow(
                            provider: provider,
                            configured: model.providerIsConfigured(provider),
                            expanded: editingProvider == provider,
                            tokenDraft: $tokenDraft,
                            message: editingProvider == provider
                                ? providerMessage
                                : "",
                            onToggle: {
                                if editingProvider == provider {
                                    editingProvider = nil
                                } else {
                                    editingProvider = provider
                                    tokenDraft = ""
                                    providerMessage = ""
                                }
                            },
                            onSave: {
                                guard !tokenDraft
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty else {
                                    providerMessage = "请输入 API Key 或 Token"
                                    return
                                }
                                if let error = model.saveProviderToken(
                                    tokenDraft,
                                    for: provider
                                ) {
                                    providerMessage = error
                                } else {
                                    tokenDraft = ""
                                    providerMessage = "已保存到 OpenType 本地加密凭据库"
                                }
                            },
                            onDelete: {
                                providerPendingDeletion = provider
                            }
                        )
                    }
                }

                SettingsSection("X Reply") {
                    Picker(
                        "X Reply 风格",
                        selection: $configuration.xReplyStyle
                    ) {
                        ForEach(XReplyStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }

                SettingsSection("个人词典") {
                    Text("用逗号或换行分隔。OpenType 会保留这些词的拼写。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $configuration.personalDictionaryText)
                        .font(.system(size: 11))
                        .frame(height: 76)
                        .padding(7)
                        .scrollContentBackground(.hidden)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(.primary.opacity(0.1))
                        )
                }

                SettingsSection("连接与权限") {
                    Label(
                        model.credentialStatus,
                        systemImage: model.cloudConnected
                            ? "circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(
                        model.cloudConnected
                            ? Color.secondary
                            : Color.orange
                    )

                    HStack {
                        Label(
                            "麦克风\(model.microphonePermission.title)",
                            systemImage: model.microphonePermission.symbol
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(
                            model.microphonePermission == .granted
                                ? Color.secondary
                                : Color.orange
                        )
                        Spacer()
                        if model.microphonePermission != .granted {
                            Button(
                                model.microphonePermission == .denied
                                    ? "打开设置"
                                    : "授权"
                            ) {
                                model.requestMicrophonePermission()
                            }
                            .controlSize(.small)
                        }
                    }

                    HStack {
                        Label(
                            model.accessibilityGranted
                                ? "辅助功能已授权"
                                : "辅助功能未授权",
                            systemImage: model.accessibilityGranted
                                ? "circle.fill"
                                : "circle"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(
                            model.accessibilityGranted
                                ? Color.secondary
                                : Color.orange
                        )
                        Spacer()
                        if !model.accessibilityGranted {
                            Button("授权") {
                                model.requestAccessibility()
                            }
                            .controlSize(.small)
                        }
                    }

                    HStack {
                        Label(
                            "实时字幕\(model.speechRecognitionPermission.title)",
                            systemImage: model.speechRecognitionPermission.symbol
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(
                            model.speechRecognitionPermission == .granted
                                ? Color.secondary
                                : Color.orange
                        )
                        Spacer()
                        if model.speechRecognitionPermission != .granted {
                            Button(
                                model.speechRecognitionPermission == .denied
                                    ? "打开设置"
                                    : "授权"
                            ) {
                                model.requestSpeechRecognitionPermission()
                            }
                            .controlSize(.small)
                        }
                    }
                }

                SettingsSection("隐私与数据") {
                    DisclosureGroup(
                        isExpanded: $dataManagementExpanded
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider()

                            dataManagementRow(
                                title: "输入历史",
                                detail: "\(model.history.entries.count) 条本地记录",
                                actionTitle: "重置输入历史",
                                disabled: model.history.entries.isEmpty
                            ) {
                                showingHistoryResetConfirmation = true
                            }

                            Divider()

                            dataManagementRow(
                                title: "长期记忆",
                                detail: "\(agentMemory.eventCount) 条学习记录",
                                actionTitle: "重新学习偏好",
                                disabled: agentMemory.eventCount == 0
                            ) {
                                showingAgentMemoryResetConfirmation = true
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("本地数据管理", systemImage: "externaldrive")
                            .font(.system(size: 10.5, weight: .semibold))
                    }

                    Text("高风险操作默认收起，需要时再展开。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                Text("实时字幕优先使用 Apple 本机识别，仅作为录音预览；最终音频与文字只发送给你在上方选择的服务。API Key 保存在 OpenType 本地加密凭据库，不写入设置、日志或历史。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
        .alert(item: $providerPendingDeletion) { provider in
            Alert(
                title: Text("移除 \(provider.title) Token？"),
                message: Text("将从 OpenType 本地加密凭据库移除；需要时可以重新添加。"),
                primaryButton: .destructive(Text("移除")) {
                    if let error = model.deleteProviderToken(for: provider) {
                        editingProvider = provider
                        providerMessage = error
                    } else {
                        if editingProvider == provider {
                            tokenDraft = ""
                            providerMessage = "Token 已移除"
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .confirmationDialog(
            "重置输入历史？",
            isPresented: $showingHistoryResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认重置", role: .destructive) {
                model.resetHistory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本机保存的输入记录会被移除。此操作不可撤销，建议先保存重要信息。")
        }
        .confirmationDialog(
            "重新学习偏好？",
            isPresented: $showingAgentMemoryResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认重新学习", role: .destructive) {
                model.resetAgentMemory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本地任务记录和系统推断会被移除；你在“关于我”中手动填写的内容会保留。此操作不可撤销，建议先保存重要信息。")
        }
    }

    @ViewBuilder
    private func dataManagementRow(
        title: String,
        detail: String,
        actionTitle: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 10.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: action) {
                Text(LocalizedStringKey(actionTitle))
            }
                .controlSize(.small)
                .disabled(disabled)
        }
    }

    private enum OwnerProfileField {
        case identityAndWork
        case communicationStyle
        case importantTerms
    }

    @ViewBuilder
    private func colorThemeButton(_ theme: AppColorTheme) -> some View {
        let selected = configuration.colorTheme == theme
        Button {
            model.changeColorTheme(theme)
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(theme.secondaryAccent)
                        .frame(width: 18, height: 18)
                        .offset(x: 5, y: -2)
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.52), lineWidth: 0.7)
                        )
                }
                .frame(width: 29, height: 25)

                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.title)
                        .font(.system(size: 10, weight: .semibold))
                    Text(theme.subtitle)
                        .font(.system(size: 8.2))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 2)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                selected ? theme.accent.opacity(0.10) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        selected ? theme.accent.opacity(0.34) : OpenTypeTheme.border,
                        lineWidth: 0.75
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func profileEditor(
        title: String,
        hint: String,
        text: Binding<String>,
        height: CGFloat = 68
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 9.5, weight: .semibold))
            TextEditor(text: text)
                .font(.system(size: 10.5))
                .frame(height: height)
                .padding(6)
                .scrollContentBackground(.hidden)
                .background(
                    Color(nsColor: .textBackgroundColor).opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(OpenTypeTheme.border, lineWidth: 0.75)
                )
            Text(LocalizedStringKey(hint))
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ownerProfileBinding(
        for field: OwnerProfileField
    ) -> Binding<String> {
        Binding(
            get: {
                switch field {
                case .identityAndWork:
                    return agentMemory.ownerProfile.identityAndWork
                case .communicationStyle:
                    return agentMemory.ownerProfile.communicationStyle
                case .importantTerms:
                    return agentMemory.ownerProfile.importantTerms
                }
            },
            set: { value in
                var profile = agentMemory.ownerProfile
                switch field {
                case .identityAndWork:
                    profile.identityAndWork = value
                case .communicationStyle:
                    profile.communicationStyle = value
                case .importantTerms:
                    profile.importantTerms = value
                }
                agentMemory.updateOwnerProfile(profile)
            }
        )
    }

    private var preferredLanguageBinding: Binding<ProfileLanguagePreference> {
        Binding(
            get: { agentMemory.ownerProfile.preferredLanguage },
            set: { language in
                var profile = agentMemory.ownerProfile
                profile.preferredLanguage = language
                agentMemory.updateOwnerProfile(profile)
            }
        )
    }

    private var automaticProfileUpdateDescription: String {
        guard configuration.automaticOwnerProfileUpdates else {
            return OpenTypeL10n.text("已暂停自动更新；已有内容会保留。", english: "Automatic updates are paused; existing content is kept.")
        }
        if agentMemory.automaticProfileUpdateDue {
            return OpenTypeL10n.text("已达到更新条件，下次启动或完成输入时将更新。整个过程在本机完成。", english: "Ready to update on the next launch or completed input. Everything runs locally.")
        }
        return OpenTypeL10n.text(
            "已记录 \(agentMemory.eventCount) 条；到 \(agentMemory.nextAutomaticProfileEventCount) 条时更新已学到的偏好。“关于我”永远不会被自动改写。",
            english: "\(agentMemory.eventCount) recorded; learned preferences update at \(agentMemory.nextAutomaticProfileEventCount). About Me is never rewritten automatically."
        )
    }

    @ViewBuilder
    private func memoryInsightRow(
        _ title: String,
        values: [String]
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(
                values.isEmpty
                    ? OpenTypeL10n.text("仍在学习", english: "Still learning")
                    : values.joined(separator: " · ")
            )
                .font(.system(size: 9.5, weight: values.isEmpty ? .regular : .medium))
                .foregroundStyle(values.isEmpty ? .tertiary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shortcutStatusSymbol: String {
        if !model.shortcutReady {
            return "exclamationmark.triangle.fill"
        }
        return model.preferredShortcutActive
            ? "keyboard.badge.ellipsis"
            : "arrow.triangle.2.circlepath"
    }

    private var shortcutStatusColor: Color {
        model.shortcutReady && model.preferredShortcutActive ? .secondary : .orange
    }
}

private struct ProviderCredentialRow: View {
    let provider: AIProvider
    let configured: Bool
    let expanded: Bool
    @Binding var tokenDraft: String
    let message: String
    let onToggle: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 9) {
                    Image(systemName: provider.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 25, height: 25)
                        .background(Color.primary.opacity(0.045), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        HStack(spacing: 5) {
                            if provider.supportsSpeechRecognition {
                                capabilityPill("语音")
                            }
                            if provider.supportsTextGeneration {
                                capabilityPill("文字")
                            }
                        }
                    }

                    Spacer()

                    Text(
                        configured
                            ? OpenTypeL10n.text("已配置", english: "Configured")
                            : OpenTypeL10n.text("添加", english: "Add")
                    )
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(configured ? Color.secondary : Color.accentColor)

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                SecureField(provider.tokenHint, text: $tokenDraft)
                    .textFieldStyle(.roundedBorder)

                Text(
                    configured
                        ? OpenTypeL10n.text(
                            "Token 已保存；输入新值可覆盖，现有 Token 不会显示。",
                            english: "The token is saved. Enter a new value to replace it; the current token is never displayed."
                        )
                        : OpenTypeL10n.text(
                            "Token 只会写入 OpenType 本地加密凭据库。",
                            english: "The token is stored only in OpenType's local encrypted vault."
                        )
                )
                .font(.system(size: 8.8))
                .foregroundStyle(.secondary)

                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 8.8, weight: .medium))
                        .foregroundStyle(
                            message.contains("已安全") || message.contains("已移除")
                                ? Color.secondary
                                : Color.orange
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    if configured {
                        Button("移除 Token", role: .destructive, action: onDelete)
                            .controlSize(.small)
                    }
                    Spacer()
                    Button(configured ? "更新 Token" : "保存 Token", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(9)
        .background(
            expanded ? Color.accentColor.opacity(0.055) : Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    expanded ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.055),
                    lineWidth: 0.7
                )
        )
    }

    private func capabilityPill(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.045), in: Capsule())
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionLabel(title)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .openTypeSurface(cornerRadius: 14)
        }
    }
}

private struct TabBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    model.selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            model.selectedTab == tab
                                ? Color.accentColor.opacity(0.11)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .foregroundStyle(
                    model.selectedTab == tab ? Color.accentColor : Color.secondary
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OpenTypeTheme.border)
                .frame(height: 0.5)
        }
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
