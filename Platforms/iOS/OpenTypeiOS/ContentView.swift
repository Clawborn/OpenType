import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            HomeView(model: model, settings: model.settings, speech: model.speech)
                .tabItem { Label(tab("输入", "Compose"), systemImage: "waveform") }
            HistoryView(history: model.history, settings: model.settings)
                .tabItem { Label(tab("历史", "History"), systemImage: "clock.arrow.circlepath") }
            SettingsView(settings: model.settings)
                .tabItem { Label(tab("设置", "Settings"), systemImage: "slider.horizontal.3") }
        }
    }

    private func tab(_ chinese: String, _ english: String) -> String {
        L10n.text(chinese, english, language: model.settings.language)
    }
}

private struct HomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var speech: SpeechRecognizer
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    introCard
                    modeGrid
                    if model.selectedMode.supportsContext { contextCard }
                    recordingCard
                    if case .failed(let message) = model.state { messageCard(message, warning: true) }
                    if case .cancelled(let message) = model.state { messageCard(message, warning: false) }
                    if !model.result.isEmpty { resultCard }
                    keyboardFlowCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("OpenType")
            .toolbar {
                if !speech.transcript.isEmpty || !model.result.isEmpty || !model.context.isEmpty {
                    Button(L10n.text("新对话", "New", language: settings.language)) {
                        model.startNewDraft()
                    }
                }
            }
        }
    }

    private var introCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selectedMode.title(settings.language)).font(.headline)
                Text(model.selectedMode.subtitle(settings.language))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private var modeGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("模式", "MODE", language: settings.language))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(InputMode.allCases) { mode in
                    Button {
                        model.selectedMode = mode
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.symbol)
                                .frame(width: 34, height: 34)
                                .background(model.selectedMode == mode ? Color.blue.opacity(0.14) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title(settings.language)).font(.subheadline.weight(.semibold))
                                Text(mode.subtitle(settings.language)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 66)
                        .background(model.selectedMode == mode ? Color.blue.opacity(0.09) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(model.selectedMode == mode ? Color.blue.opacity(0.45) : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.state.isBusy)
                }
            }
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(contextTitle).font(.subheadline.weight(.semibold))
            TextEditor(text: $model.context)
                .frame(minHeight: 88)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            Text(contextHint).font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var recordingCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stateTitle).font(.headline)
                    if speech.isRecording && settings.preferOnDeviceRecognition {
                        Text(speech.usingOnDeviceRecognition
                             ? L10n.text("正在使用设备端识别", "On-device recognition", language: settings.language)
                             : L10n.text("系统已自动使用在线识别", "System online recognition fallback", language: settings.language))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                WaveformView(level: speech.isRecording ? speech.level : 0.12, active: speech.isRecording)
                    .frame(width: 76, height: 28)
            }

            ZStack(alignment: .topLeading) {
                if speech.transcript.isEmpty {
                    Text(L10n.text("实时字幕会显示在这里，也可以直接输入文字。", "Live transcript appears here. You can also type.", language: settings.language))
                        .foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 8)
                }
                TextEditor(text: $speech.transcript)
                    .frame(minHeight: 112)
                    .scrollContentBackground(.hidden)
            }
            .padding(8)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 12) {
                Button(action: model.toggleRecording) {
                    Label(
                        speech.isRecording
                            ? L10n.text("停止并处理", "Stop & process", language: settings.language)
                            : L10n.text("开始说话", "Start speaking", language: settings.language),
                        systemImage: speech.isRecording ? "stop.fill" : "mic.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.state.isBusy && !speech.isRecording)

                if !speech.isRecording {
                    Button(L10n.text("生成", "Generate", language: settings.language)) {
                        Task { await model.generate() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!model.canGenerate || model.state.isBusy)
                }
            }
        }
        .cardStyle()
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("结果", "RESULT", language: settings.language), systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    model.copyResult()
                } label: {
                    Label(L10n.text("复制", "Copy", language: settings.language), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            Text(model.result).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Label(
                L10n.text("已复制，并同步到 OpenType 键盘", "Copied and synced to the OpenType keyboard", language: settings.language),
                systemImage: "circle.fill"
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var keyboardFlowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("在其他 App 中输入", "TYPE IN OTHER APPS", language: settings.language))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            flowRow(number: "1", title: L10n.text("在 OpenType 里说话并生成", "Record and generate in OpenType", language: settings.language))
            flowRow(number: "2", title: L10n.text("回到目标 App，切换到 OpenType 键盘", "Return to the target app and switch keyboards", language: settings.language))
            flowRow(number: "3", title: L10n.text("点“一键插入最近结果”", "Tap “Insert latest result”", language: settings.language))
            Text(L10n.text(
                "iOS 不允许第三方键盘使用麦克风。密码框或禁用第三方键盘的 App 请直接粘贴剪贴板结果。",
                "iOS does not allow microphone access inside third-party keyboards. Use clipboard paste in password fields or apps that block custom keyboards.",
                language: settings.language
            ))
            .font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func flowRow(number: String, title: String) -> some View {
        HStack(spacing: 10) {
            Text(number).font(.caption.bold()).foregroundStyle(.blue)
                .frame(width: 24, height: 24).background(Color.blue.opacity(0.12), in: Circle())
            Text(title).font(.subheadline)
        }
    }

    private func messageCard(_ message: String, warning: Bool) -> some View {
        Label(message, systemImage: warning ? "exclamationmark.triangle" : "info.circle")
            .font(.subheadline)
            .foregroundStyle(warning ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background((warning ? Color.red : Color.gray).opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var contextTitle: String {
        switch model.selectedMode {
        case .xReply: return L10n.text("原推文", "Original post", language: settings.language)
        case .smartEdit: return L10n.text("可选：要修改的原文", "Optional: source text to edit", language: settings.language)
        default: return L10n.text("可选参考内容", "Optional reference", language: settings.language)
        }
    }

    private var contextHint: String {
        if model.selectedMode == .smartEdit {
            return L10n.text("填入原文后，必须明确说出修改指令，否则不会处理。", "With source text, an explicit edit instruction is required.", language: settings.language)
        }
        return L10n.text("从其他 App 复制后粘贴到这里。", "Copy from another app and paste it here.", language: settings.language)
    }

    private var stateTitle: String {
        switch model.state {
        case .idle: return L10n.text("准备好了", "Ready", language: settings.language)
        case .requestingPermission: return L10n.text("正在请求权限…", "Requesting permission…", language: settings.language)
        case .listening: return L10n.text("正在听…", "Listening…", language: settings.language)
        case .recognizing: return L10n.text("正在完成识别…", "Finishing recognition…", language: settings.language)
        case .processing: return L10n.text("正在生成…", "Generating…", language: settings.language)
        case .completed: return L10n.text("完成，结果已复制", "Done and copied", language: settings.language)
        case .cancelled: return L10n.text("没有执行", "Not run", language: settings.language)
        case .failed: return L10n.text("出现问题", "Something went wrong", language: settings.language)
        }
    }
}

private struct WaveformView: View {
    let level: Double
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !active)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    let pulse = (sin(phase * 8 + Double(index) * 0.9) + 1) / 2
                    Capsule()
                        .fill(active ? Color.blue : Color.secondary.opacity(0.35))
                        .frame(width: 5, height: 7 + 19 * max(0.12, level) * pulse)
                        .animation(.easeOut(duration: 0.1), value: level)
                }
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}
