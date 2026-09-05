import AppKit
import SwiftUI

// The redesigned 设置 screen (2026-08 handoff §5, mockup 03C).
//
// The old Settings tab was nine stacked sections in a 420pt column, and three
// of them — provider setup, MCP, memory — were full configuration surfaces
// inlined into a list. That is why it had a `DisclosureGroup`: there was
// nowhere else to put anything, so everything was on one page and the
// dangerous parts had to be hidden behind a twisty.
//
// This splits it in two. `SettingsColumn` is five groups of short rows, laid
// out in two columns when there is room; anything that needs a form of its own
// becomes a row with a `chevron.right` that pushes a page into the detail
// column (`SettingsDetailColumn`). The two provider rows carry the answer to
// the question people actually open Settings for — *what is it using right
// now?* — in mono on the row itself, so the common case needs no click at all.
//
// Every value here comes from `DS`, and every one of them is the value 03C's
// markup literally sets — 11.5pt subtitles, `rgba(28,28,30,.45)` ink,
// `rgba(0,0,0,.09)` chip borders. An earlier pass rounded those onto the
// README's closed scale (12pt, `.secondary`, one border token); the owner
// reversed that on 2026-08-15 with 稿子优先, so the mockup wins wherever the
// two disagree. The rule that survives is the one that mattered: the value
// lives in `DS` under a name, never as a literal in this file.

// MARK: - The settings list

/// 设置's list column: five groups, two columns when the column is wide
/// enough for them.
///
/// The two-column threshold is measured rather than passed in because this
/// view is used in both shell slots — it reads as one page when it owns the
/// content area (the mockup's 908pt case) and degrades to a single scrolling
/// column when it is the 334pt list beside a pushed sub-page. Neither layout
/// changes a row's own metrics; only the page padding moves, exactly as the
/// handoff specifies for every other screen.
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, voice, intelligence, privacy, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return OpenTypeL10n.text("通用", english: "General")
        case .voice: return OpenTypeL10n.text("语音输入", english: "Voice input")
        case .intelligence: return OpenTypeL10n.text("智能服务", english: "Intelligence")
        case .privacy: return OpenTypeL10n.text("隐私与数据", english: "Privacy & data")
        case .about: return OpenTypeL10n.text("关于", english: "About")
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .voice: return "mic"
        case .intelligence: return "sparkle"
        case .privacy: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

struct SettingsColumn: View {
    @ObservedObject var model: AppModel
    @ObservedObject var configuration: AppConfiguration
    /// Observed directly rather than read through `model`: the login item's
    /// state is the system's, not ours, and this is the object that re-reads
    /// it. See `LaunchAtLogin.swift`.
    @ObservedObject var launchAtLogin: LaunchAtLoginController

    /// Line count of `audit-events.v1.jsonl`, for the 审计记录 row. `nil`
    /// until the first read finishes — the row prints nothing rather than a
    /// wrong `0`, the same rule the stats band uses for missing figures.
    @State private var auditEventCount: Int?
    @AppStorage("OpenType.settingsCategory") private var category: SettingsCategory = .general

    init(model: AppModel) {
        self.model = model
        configuration = model.configuration
        launchAtLogin = model.launchAtLogin
    }

    /// Below this the five groups stack into one column. It is not the
    /// window's narrow breakpoint: two 300pt-ish columns plus the gutter need
    /// more than a 334pt list column can give regardless of how wide the
    /// window is.
    private let twoColumnWidth: CGFloat = 620

    var body: some View {
        GeometryReader { proxy in
            let twoColumn = proxy.size.width >= twoColumnWidth
            let pagePadding = twoColumn ? DS.Space.pageWide : DS.Space.pageNarrow

            VStack(spacing: 0) {
                ColumnHeader(narrow: !twoColumn) {
                    Text(OpenTypeL10n.text("设置", english: "Settings"))
                        .font(DS.Text.title())
                        .tracking(DS.Tracking.title)
                    Spacer(minLength: 0)
                }

                if twoColumn {
                    HStack(alignment: .top, spacing: 24) {
                        categoryNavigation
                            .frame(width: 150)
                        settingsContent
                    }
                    .padding(.horizontal, pagePadding)
                } else {
                    Picker(OpenTypeL10n.text("设置分类", english: "Settings category"), selection: $category) {
                        ForEach(SettingsCategory.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .padding(.horizontal, pagePadding)
                    .padding(.bottom, 16)
                    settingsContent.padding(.horizontal, pagePadding)
                }
            }
        }
        .background(DS.Colour.canvas)
        .task {
            // Before the awaits: the login item's state is read locally, and
            // it is the one thing on this page that can have changed without
            // the app being involved at all.
            model.refreshLaunchAtLogin()
            auditEventCount = await auditEventCountFromDisk()
            await model.refreshWhisperConfigSummary()
            await model.refreshLLMConfigSummary()
            await model.refreshWhisperModelConfig()
        }
    }

    private var categoryNavigation: some View {
        VStack(spacing: 4) {
            ForEach(SettingsCategory.allCases) { item in
                Button { category = item } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(DS.Text.body(category == item ? .medium : .regular))
                        .foregroundStyle(category == item ? DS.Colour.accent : DS.Colour.ink(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(category == item ? DS.Colour.accent.opacity(0.08) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(category == item ? [.isSelected] : [])
            }
        }
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch category {
                case .general:
                    generalGroup
                case .voice:
                    shortcutGroup
                    dictationOutputGroup
                case .intelligence:
                    engineGroup
                case .privacy:
                    permissionsGroup
                    dataGroup
                case .about:
                    HStack(spacing: 14) {
                        AppBrandIcon(size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OpenType").font(DS.Text.title())
                            Text(OpenTypeL10n.text("听写 · 问答 · Agent", english: "Dictation · Ask · Agent"))
                                .font(DS.Text.caption()).foregroundStyle(.secondary)
                        }
                    }
                    aboutGroup
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 28)
        }
        .id(category)
    }

    // MARK: 通用

    private var generalGroup: some View {
        SettingsGroup(OpenTypeL10n.text("通用", english: "General")) {
            launchAtLoginRow
            interfaceLanguageRow
        }
    }

    /// 界面语言（§F）— 跟随系统 / 中文 / English. A `SegmentedControl`, the same
    /// shape 听写输出's 松开之后 picker uses, because both are "exactly one of a
    /// small closed set" choices that deserve a permanently visible control
    /// rather than a menu that hides the current value behind a click.
    private var interfaceLanguageRow: some View {
        SettingsStackedRow(
            title: OpenTypeL10n.text("界面语言", english: "Interface language")
        ) {
            SegmentedControl(
                options: InterfaceLanguage.allCases,
                selection: configuration.interfaceLanguage,
                title: { $0.title },
                help: { $0.explanation },
                select: { model.changeInterfaceLanguage($0) }
            )
        }
    }

    /// 开机自启, in whichever of its four states the system is in.
    ///
    /// Three renderings rather than one switch with disabled states, because
    /// two of the four are not 「开」 or 「关」 at all. `.requiresApproval` is a
    /// registration macOS is holding back, and the only thing that clears it is
    /// the Login Items pane — so that row trades the switch for the jump, the
    /// same shape the ungranted permission rows below use. `.notSupported` is a
    /// bundle launchd will not register from where it is running — the app's
    /// current ad-hoc, no-TeamIdentifier signing means this is the normal
    /// state for every user of the current distribution, not a bug specific to
    /// a debug build — and a switch there would be one the user can press
    /// forever with nothing to show for it, so the row renders nothing at all
    /// rather than explanatory prose. It reappears on its own once the app
    /// ships Developer ID–signed and notarized.
    @ViewBuilder
    private var launchAtLoginRow: some View {
        let title = OpenTypeL10n.text("开机时自动启动", english: "Launch at login")

        switch launchAtLogin.status {
        case .enabled, .disabled:
            SettingsRow(
                divided: false,
                title: title,
                // Nothing shows in the ordinary case (owner copy rule, §5,
                // removed the standing "lives in the menu bar…" explanation);
                // a refused `register()` is the one thing worth reading here,
                // so it is the only subtitle this row ever prints.
                subtitle: model.launchAtLoginError,
                tinted: model.launchAtLoginError != nil
            ) {
                SettingsSwitch(
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { model.changeLaunchAtLogin($0) }
                    )
                )
                .accessibilityLabel(title)
            }

        case .requiresApproval:
            SettingsRow(
                divided: false,
                title: title,
                subtitle: OpenTypeL10n.text(
                    "已被系统设置拦下。在「登录项与扩展」里允许 OpenType 之后才会生效。",
                    english: "Blocked by System Settings. Allow OpenType under Login Items & Extensions for this to take effect."
                ),
                tinted: true
            ) {
                SmallButton(OpenTypeL10n.text("打开设置", english: "Open Settings")) {
                    model.openLoginItemsSettings()
                }
            }

        case .notSupported:
            // No row at all — not even a shrunk one. This is the normal state
            // for the current ad-hoc-signed distribution (no TeamIdentifier,
            // so `SMAppService.mainApp` refuses to register), and there is no
            // control to offer here. It comes back on its own once the app is
            // Developer ID–signed and notarized.
            EmptyView()
        }
    }

    // MARK: 快捷键

    private var shortcutGroup: some View {
        SettingsGroup(OpenTypeL10n.text("快捷键", english: "Shortcut")) {
            SettingsRow(
                divided: false,
                title: OpenTypeL10n.text("启动方式", english: "Trigger")
            ) {
                Menu {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Button(preset.title) { model.changeHotKey(preset) }
                    }
                } label: {
                    ControlChip(
                        text: configuration.hotKeyPreset.title,
                        mono: true
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            // Only when something is wrong. A permanently-present "it works"
            // line is the kind of reassurance that stops being read, and the
            // handoff reserves colour for things that want an action.
            if !shortcutHealthy {
                SettingsRow(
                    title: model.shortcutStatus,
                    subtitle: model.accessibilityGranted
                        ? nil
                        : OpenTypeL10n.text(
                            "开启辅助功能后可使用双击触发，并用任意键结束。",
                            english: "With Accessibility granted, double-tap triggers work and any key can stop a recording."
                        ),
                    tinted: true
                ) {
                    if !model.accessibilityGranted {
                        SmallButton(OpenTypeL10n.text("授权", english: "Grant")) {
                            model.requestAccessibility()
                        }
                    }
                }
            }

            SettingsRow(
                title: OpenTypeL10n.text("录音中切换模式", english: "Switch mode while recording")
            ) {
                Text(verbatim: "Tab")
                    .font(DS.Text.mono(12))
                    .foregroundStyle(DS.Colour.ink(0.5))
            }
        }
    }

    private var shortcutHealthy: Bool {
        model.shortcutReady && model.preferredShortcutActive
    }

    // MARK: 听写输出

    private var dictationOutputGroup: some View {
        SettingsGroup(OpenTypeL10n.text("听写输出", english: "Dictation output")) {
            // The one row that is a stacked control rather than a trailing
            // one: three named destinations do not fit in a trailing slot, and
            // this is the setting that decides what the app does with your
            // voice, so it gets the width.
            SettingsStackedRow(
                divided: false,
                title: OpenTypeL10n.text("松开之后", english: "On release")
            ) {
                SegmentedControl(
                    options: TranscribeVariant.allCases,
                    selection: configuration.transcribeVariant,
                    title: { $0.releaseTitle },
                    help: { $0.explanation },
                    select: { model.changeTranscribeVariant($0) }
                )
            }

            SettingsRow(
                title: OpenTypeL10n.text("自动写入当前输入框", english: "Insert into the focused field")
            ) {
                SettingsSwitch(isOn: $configuration.automaticallyInsert)
                    .accessibilityLabel(
                        OpenTypeL10n.text("自动写入当前输入框", english: "Insert into the focused field")
                    )
            }

            // Shown even when auto-insert is off, dimmed. The old Settings
            // hid it, which made the row above jump the list around every
            // time it was toggled — and hiding a setting is how a user comes
            // to believe it was removed.
            SettingsRow(
                title: OpenTypeL10n.text("写入后恢复原剪贴板", english: "Restore the clipboard after inserting")
            ) {
                SettingsSwitch(isOn: $configuration.retainClipboardAfterInsert)
                    .accessibilityLabel(
                        OpenTypeL10n.text("写入后恢复原剪贴板", english: "Restore the clipboard after inserting")
                    )
            }
            .disabled(!configuration.automaticallyInsert)

            SettingsRow(
                title: OpenTypeL10n.text("录音时显示实时字幕", english: "Live captions while recording")
            ) {
                SettingsSwitch(isOn: $configuration.liveCaptionsEnabled)
                    .accessibilityLabel(
                        OpenTypeL10n.text("录音时显示实时字幕", english: "Live captions while recording")
                    )
            }

            SettingsRow(
                title: OpenTypeL10n.text("提示音", english: "Sounds"),
                subtitle: "OpenType Air"
            ) {
                Menu {
                    ForEach(FeedbackSoundCue.allCases) { cue in
                        Button(cue.title) { model.previewFeedbackSound(cue) }
                    }
                } label: {
                    ControlChip(
                        text: OpenTypeL10n.text("试听", english: "Preview"),
                        showsIndicator: false,
                        horizontalPadding: 10
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(configuration.isMuted)

                SettingsSwitch(
                    isOn: Binding(
                        get: { !configuration.isMuted },
                        set: { model.changeMuted(!$0) }
                    )
                )
                .accessibilityLabel(OpenTypeL10n.text("提示音", english: "Sounds"))
            }
        }
    }

    // MARK: 引擎

    private var engineGroup: some View {
        SettingsGroup(OpenTypeL10n.text("引擎", english: "Engines")) {
            SettingsRow(
                divided: false,
                title: SettingsRoute.speechRecognition.title,
                mono: whisperSummaryLine,
                statusDot: whisperConfigured ? DS.Colour.ok : DS.Colour.warning,
                pushes: .speechRecognition,
                model: model
            )

            SettingsRow(
                title: SettingsRoute.languageModel.title,
                mono: llmSummaryLine,
                statusDot: llmConfigured ? DS.Colour.ok : DS.Colour.warning,
                pushes: .languageModel,
                model: model
            )

            SettingsRow(
                title: SettingsRoute.agentTools.title,
                subtitle: OpenTypeL10n.text(
                    "内置工具与 MCP 服务器",
                    english: "Built-in tools and MCP servers"
                ),
                pushes: .agentTools,
                model: model
            )

            SettingsRow(
                title: SettingsRoute.skillsAndAgents.title,
                pushes: .skillsAndAgents,
                model: model
            )

            // Renamed from 「转写语言」 in the 2026-08-15 batch (§C), when the
            // setting stopped being a live-caption-only preference and started
            // reaching Whisper — the old name was true of neither recogniser
            // in particular. No explanatory text on the row itself (2026-08-15
            // settings-trim pass): the picker's own value is the setting.
            SettingsRow(
                title: OpenTypeL10n.text("语音识别语言", english: "Speech recognition language")
            ) {
                Menu {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Button(language.title) {
                            model.changeTranscriptionLanguage(language)
                        }
                    }
                } label: {
                    ControlChip(text: configuration.transcriptionLanguage.title)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            // 语音模型 (§E-4). Until this batch the only way to change it was an
            // environment variable a packaged-app user cannot set — while the
            // default model's accuracy on proper nouns is the whole of a new
            // user's first impression.
            if let config = model.whisperModelConfig, !config.presets.isEmpty {
                SettingsRow(
                    title: OpenTypeL10n.text("语音模型", english: "Speech model"),
                    // Only the transient "saved, not yet in effect" status
                    // shows as a subtitle — it is real state the user just
                    // caused, not standing prose about the tradeoff.
                    subtitle: model.whisperModelRestartPending
                        ? OpenTypeL10n.text(
                            "已保存，下次启动生效",
                            english: "Saved — takes effect on next launch"
                        )
                        : nil
                ) {
                    Menu {
                        ForEach(config.presets) { preset in
                            Button("\(whisperModelName(preset.id)) · \(preset.approximateSizeText)") {
                                Task { await model.changeWhisperModel(preset.id) }
                            }
                        }
                    } label: {
                        ControlChip(text: whisperModelName(config.model))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
    }

    /// `mlx-whisper · 本机`, or the remote model and host the user configured.
    private var whisperSummaryLine: String {
        guard let summary = model.whisperConfigSummary, summary.mode == .remote else {
            return OpenTypeL10n.text("mlx-whisper · 本机", english: "mlx-whisper · local")
        }
        return [summary.model, host(of: summary.baseUrl), OpenTypeL10n.text("远程", english: "remote")]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    private var whisperConfigured: Bool {
        model.whisperConfigSummary?.configured
            ?? (model.providerConfigStatus?.whisperConfigured ?? false)
    }

    /// `deepseek-v4-flash · OpenAI 兼容`, or the zero-config fallback's own
    /// label when nothing was ever saved.
    private var llmSummaryLine: String {
        guard let summary = model.llmConfigSummary, summary.configured else {
            return OpenTypeL10n.text("未配置", english: "Not configured")
        }
        return [summary.model, summary.type?.title]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    private var llmConfigured: Bool {
        model.llmConfigSummary?.configured
            ?? (model.providerConfigStatus?.llmConfigured ?? false)
    }

    private func host(of urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString) else { return urlString }
        return url.host ?? urlString
    }

    // MARK: 权限

    private var permissionsGroup: some View {
        SettingsGroup(OpenTypeL10n.text("权限", english: "Permissions")) {
            PermissionRow(
                divided: false,
                title: OpenTypeL10n.text("麦克风", english: "Microphone"),
                status: model.microphonePermission,
                deniedNote: OpenTypeL10n.text(
                    "未授权时无法录音，快捷键不会有反应",
                    english: "Without it nothing can be recorded and the hotkey does nothing"
                ),
                grant: { model.requestMicrophonePermission() }
            )

            PermissionRow(
                title: OpenTypeL10n.text("辅助功能", english: "Accessibility"),
                status: model.accessibilityGranted ? .granted : .denied,
                deniedNote: OpenTypeL10n.text(
                    "未授权时无法写入当前输入框，结果仍会复制到剪贴板",
                    english: "Without it nothing is inserted into the focused field; results are still copied"
                ),
                grant: { model.requestAccessibility() }
            )

            PermissionRow(
                title: OpenTypeL10n.text("语音识别（实时字幕）", english: "Speech recognition (live captions)"),
                status: model.speechRecognitionPermission,
                deniedNote: nil,
                grant: { model.requestSpeechRecognitionPermission() }
            )
        }
    }

    // MARK: 数据

    /// Names the sizes the sidecar deliberately does not name.
    ///
    /// Falls back to the bare repo id, which is what a user who pointed
    /// `OPENTYPE_WHISPER_MODEL` at a fine-tune should see: the picker is a menu,
    /// not an allowlist, and a value it does not recognise is still theirs.
    private func whisperModelName(_ id: String) -> String {
        if id.contains("large") {
            return OpenTypeL10n.text("大", english: "Large")
        }
        if id.contains("medium") {
            return OpenTypeL10n.text("中", english: "Medium")
        }
        if id.contains("small") {
            return OpenTypeL10n.text("小（默认）", english: "Small (default)")
        }
        return id
    }

    private var dataGroup: some View {
        SettingsGroup(OpenTypeL10n.text("数据", english: "Data")) {
            SettingsRow(
                divided: false,
                title: OpenTypeL10n.text("保留本地输入历史", english: "Keep local input history")
            ) {
                SettingsSwitch(isOn: $configuration.keepHistory)
                    .accessibilityLabel(
                        OpenTypeL10n.text("保留本地输入历史", english: "Keep local input history")
                    )
            }

            SettingsRow(
                title: SettingsRoute.auditLog.title,
                mono: auditSummaryLine,
                pushes: .auditLog,
                model: model
            )

            SettingsRow(
                title: OpenTypeL10n.text("清除本地数据…", english: "Clear local data…"),
                destructive: true,
                pushes: .clearLocalData,
                model: model
            )
        }
    }

    private var auditSummaryLine: String {
        guard let auditEventCount else { return "audit-events.v1.jsonl" }
        return OpenTypeL10n.text(
            "audit-events.v1.jsonl · \(auditEventCount.formatted()) 条",
            english: "audit-events.v1.jsonl · \(auditEventCount.formatted()) events"
        )
    }

    // MARK: 关于

    /// Version, what the last update check found, and the switch that governs
    /// whether there is a next one (§B).
    ///
    /// The announcement itself does not live here — the menubar popover carries
    /// it, because this window is `.accessory` and usually closed, and a notice
    /// only Settings shows is one nobody sees. What this group is for is the
    /// other half: the user who came looking, who gets the version, the last
    /// result including a failed one, and a way to check right now.
    private var aboutGroup: some View {
        SettingsGroup(OpenTypeL10n.text("关于", english: "About")) {
            SettingsRow(
                divided: false,
                title: OpenTypeL10n.text("当前版本", english: "Version"),
                subtitle: updateStatusLine,
                mono: AppVersion.displayText.isEmpty ? nil : AppVersion.displayText
            ) {
                SmallButton(
                    model.isCheckingForUpdate
                        ? OpenTypeL10n.text("检查中…", english: "Checking…")
                        : OpenTypeL10n.text("检查更新", english: "Check now")
                ) {
                    model.checkForUpdatesNow()
                }
                .disabled(model.isCheckingForUpdate)
            }

            // Shown whenever an update exists, not only the first time — unlike
            // the popover's row, which is a notification and stops after the
            // user has acted on it. Someone who opened 设置 and scrolled here is
            // asking.
            if let version = availableUpdateVersion {
                SettingsRow(
                    title: OpenTypeL10n.text(
                        "有新版本 \(version)",
                        english: "Version \(version) is available"
                    ),
                    titleHint: OpenTypeL10n.text(
                        "在终端里重新跑一次安装命令就是更新；命令是幂等的，重复执行没有副作用。",
                        english: "Re-running the install command in a terminal is the update — it is idempotent, so running it again is harmless."
                    ),
                    mono: UpdateInstall.command
                ) {
                    SmallButton(OpenTypeL10n.text("复制安装命令", english: "Copy command")) {
                        model.copyUpdateInstallCommand()
                    }
                }
            }

            SettingsRow(
                title: OpenTypeL10n.text("自动检查更新", english: "Check for updates automatically")
            ) {
                SettingsSwitch(
                    isOn: Binding(
                        get: { configuration.updateCheckEnabled },
                        set: { model.changeUpdateCheckEnabled($0) }
                    )
                )
                .accessibilityLabel(
                    OpenTypeL10n.text("自动检查更新", english: "Check for updates automatically")
                )
            }
        }
    }

    private var availableUpdateVersion: String? {
        guard case .updateAvailable(let version, _)? = model.updateCheckOutcome else {
            return nil
        }
        return version
    }

    /// The one line under 当前版本. A `.unknown` is named rather than hidden:
    /// 「查不到」 and 「已是最新」 are different facts, and only one of them is
    /// a reason to stop wondering.
    private var updateStatusLine: String {
        if model.isCheckingForUpdate {
            return OpenTypeL10n.text("正在检查…", english: "Checking…")
        }
        guard let outcome = model.updateCheckOutcome,
              let checkedAt = model.lastUpdateCheckAt
        else {
            return configuration.updateCheckEnabled
                ? OpenTypeL10n.text("还没有检查过", english: "Not checked yet")
                : OpenTypeL10n.text("自动检查已关闭", english: "Automatic checks are off")
        }

        // The app's one clock formatter, already bound to `OpenTypeL10n.locale`
        // — a second one here would be a second thing to localize later.
        let when = MenuBarSessionTime.text(for: checkedAt)
        switch outcome {
        case .upToDate:
            return OpenTypeL10n.text(
                "已是最新版本 · \(when) 检查",
                english: "Up to date · checked \(when)"
            )
        case .updateAvailable(let version, _):
            return OpenTypeL10n.text(
                "有新版本 \(version) · \(when) 检查",
                english: "Version \(version) available · checked \(when)"
            )
        case .unknown:
            return OpenTypeL10n.text(
                "上次没能查到 · \(when)",
                english: "The last check did not get an answer · \(when)"
            )
        }
    }

}

// MARK: - The pushed sub-pages

/// The detail column for 设置: whichever `SettingsRoute` is pushed, or a
/// placeholder when none is.
///
/// The back control clears `model.settingsRoute` rather than owning any
/// navigation state of its own — the route *is* the navigation state, and the
/// narrow layout's push in `SidebarShell` reads the same flag, so one tap can
/// never leave the two disagreeing about which page is on screen.
struct SettingsDetailColumn: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let route = model.settingsRoute {
                ColumnHeader {
                    Button {
                        model.settingsRoute = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(DS.Text.size(15, .semibold))
                            .foregroundStyle(DS.Colour.accent)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(OpenTypeL10n.text("返回", english: "Back"))

                    Text(route.title)
                        .font(DS.Text.title())
                        .tracking(DS.Tracking.title)
                    Spacer(minLength: 0)
                }
                .dsHairline(.bottom)

                page(for: route)
            } else {
                // Matches `SessionThreadColumn`'s own empty state (icon above
                // a caption, both centred) rather than the bare line of text
                // this used to be — bug 2 of the popover-and-window fix batch
                // found that alone read as "nothing here" on first landing on
                // 设置, since it was the one destination whose placeholder
                // carried no icon at all.
                VStack(spacing: 10) {
                    Image(systemName: AppTab.settings.symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(.quaternary)
                    Text(OpenTypeL10n.text(
                        "从左侧选择一项设置",
                        english: "Pick a setting on the left"
                    ))
                    .font(DS.Text.caption())
                    // .4 — 03C's quietest informational step (已授权, the
                    // header's status line). The pushed column is not in the
                    // mockup, so it borrows an alpha the mockup draws instead
                    // of `.tertiary`, which resolves to ≈ .26, lighter than
                    // anything on 03C.
                    .foregroundStyle(DS.Colour.ink(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colour.card)
    }

    @ViewBuilder
    private func page(for route: SettingsRoute) -> some View {
        switch route {
        case .speechRecognition:
            SettingsPageScroll { WhisperSetupContent(model: model) }
        case .languageModel:
            SettingsPageScroll { LLMProviderSetupContent(model: model) }
        case .agentTools:
            AgentToolsPage(model: model)
        case .skillsAndAgents:
            SkillAgentPage(model: model)
        case .auditLog:
            AuditLogPage()
        case .clearLocalData:
            ClearLocalDataPage(model: model)
        }
    }
}

/// The scrolling body every sub-page shares, so a page cannot quietly pick its
/// own page padding.
private struct SettingsPageScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.group) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.pageWide)
            .padding(.vertical, DS.Space.content)
        }
        .scrollIndicators(.hidden)
    }
}

/// 审计记录: what the trail is, where it lives, and how big it is.
///
/// Read-only by construction. `ImmutableAuditStore` has no delete or rewrite
/// API and the 清除本地数据 page deliberately does not touch this file, so the
/// page's job is to make that promise legible rather than to offer actions
/// that would break it.
private struct AuditLogPage: View {
    @State private var eventCount: Int?

    private let fileURL = ImmutableAuditStore().fileURL

    var body: some View {
        SettingsPageScroll {
            Text(OpenTypeL10n.text(
                "每一次识别、纠错、完成、取消与失败都会向这个文件追加一行 JSON。它只增不删，不受「清除本地数据」影响；原始录音不会保存。",
                english: "Every recognition, correction, completion, cancellation and failure appends one JSON line to this file. It is append-only and untouched by Clear local data; raw audio is never kept."
            ))
            .font(DS.Text.caption())
            // .5 — the alpha 03C sets on an explanatory note. The sub-pages are
            // not drawn, so their prose takes the step the drawn prose takes.
            .foregroundStyle(DS.Colour.ink(0.5))
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                SettingsRow(
                    divided: false,
                    title: OpenTypeL10n.text("文件", english: "File"),
                    mono: fileURL.path
                ) {
                    SmallButton(OpenTypeL10n.text("在访达中显示", english: "Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                }

                SettingsRow(
                    title: OpenTypeL10n.text("记录条数", english: "Events")
                ) {
                    Text(eventCount.map { $0.formatted() } ?? "—")
                        .font(DS.Text.mono(12))
                        // The same 12pt mono at .5 that 03C's read-only 「Tab」
                        // trailing value takes.
                        .foregroundStyle(DS.Colour.ink(0.5))
                }
            }
            .dsCard()
        }
        .task { eventCount = await auditEventCountFromDisk() }
    }
}

/// 清除本地数据: the resettable local store, with its own confirmation. Used to
/// list two stores (input history and the now-deleted local long-term
/// `AgentMemoryStore`) — the second one and its "重新学习" reset went with it
/// (Task 8, design §3.7's HistoryStore/AgentMemoryStore removal).
///
/// A page rather than a `DisclosureGroup`. The twisty made a destructive
/// action feel like a detail of the section above it; a page you have to
/// navigate to states the cost up front and gives the confirmation somewhere
/// to live that is not a popover over a settings list.
private struct ClearLocalDataPage: View {
    @ObservedObject var model: AppModel

    @State private var confirmingHistoryReset = false

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        SettingsPageScroll {
            Text(OpenTypeL10n.text(
                "以下操作只影响本机数据，无法撤销。审计记录（audit-events.v1.jsonl）不在其中，它只增不删。",
                english: "These act on local data only and cannot be undone. The audit trail (audit-events.v1.jsonl) is not included — it is append-only."
            ))
            .font(DS.Text.caption())
            .foregroundStyle(DS.Colour.ink(0.5))
            .fixedSize(horizontal: false, vertical: true)

            // Surfaces a failed context-log clear (the sidecar half of
            // `resetHistory()`) right where the button that triggered it
            // lives — same idiom as `MemoryColumn`'s `memoryEditError` row.
            // Without this, a reset that only half-worked would look
            // identical to one that fully did.
            if let error = model.historyResetError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(DS.Text.caption())
                    .foregroundStyle(DS.Colour.warningText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 0) {
                SettingsRow(
                    divided: false,
                    title: OpenTypeL10n.text("输入历史", english: "Input history"),
                    subtitle: OpenTypeL10n.text(
                        "\(model.historyEntries.count) 条本地记录",
                        english: "\(model.historyEntries.count) local records"
                    )
                ) {
                    SmallButton(
                        OpenTypeL10n.text("重置", english: "Reset"),
                        destructive: true
                    ) {
                        confirmingHistoryReset = true
                    }
                    .disabled(model.historyEntries.isEmpty)
                }
            }
            .dsCard()
        }
        .confirmationDialog(
            OpenTypeL10n.text("重置输入历史？", english: "Reset input history?"),
            isPresented: $confirmingHistoryReset,
            titleVisibility: .visible
        ) {
            Button(OpenTypeL10n.text("确认重置", english: "Reset"), role: .destructive) {
                model.resetHistory()
            }
            Button(OpenTypeL10n.text("取消", english: "Cancel"), role: .cancel) {}
        } message: {
            Text(OpenTypeL10n.text(
                "本机保存的输入记录会被移除。此操作不可撤销，建议先保存重要信息。",
                english: "Locally stored input records are removed. This cannot be undone — save anything you need first."
            ))
        }
    }
}

// MARK: - Building blocks

/// A labelled card of rows. The label sits outside the card, 8pt above it, per
/// the handoff's spacing table.
private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.label) {
            Text(title)
                .font(DS.Text.groupLabel())
                .tracking(DS.Tracking.groupLabel)
                .foregroundStyle(DS.Colour.ink(0.42))
                .padding(.horizontal, 4)

            // `overflow:hidden` in the mockup, and not decorative: the
            // ungranted permission row carries a full-bleed warning tint and is
            // the last row of its card, so without the clip its square corners
            // would poke out past the card's 14pt radius.
            VStack(spacing: 0) { content() }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .dsCard()
        }
    }
}

/// A small "?" after a row title that reveals its explanation on hover via
/// the native tooltip, for copy that earns its place without permanently
/// occupying a subtitle line under every row.
private struct InfoHint: View {
    let text: String

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(DS.Text.size(11, .regular))
            .foregroundStyle(DS.Colour.ink(0.35))
            .help(text)
            .accessibilityLabel(OpenTypeL10n.text("说明", english: "Info"))
            .accessibilityHint(text)
    }
}

/// One row of a settings card: a title, an optional second line, and either a
/// trailing control or a `chevron.right` that pushes a page.
///
/// The two are one type on purpose. A row that pushes and a row that toggles
/// have to be the same height, the same padding and the same hairline or the
/// card reads as two lists stacked; keeping them one view means that can't
/// drift.
private struct SettingsRow<Trailing: View>: View {
    var divided = true
    /// 11pt vertical padding instead of 12. The mockup gives the permission
    /// rows — a dot, a name and a word — one point less than every other row,
    /// which is what keeps a three-row card of one-line rows from reading as
    /// taller than the two-row cards beside it.
    var compact = false
    let title: String
    /// Explanation shown on hover via a small **?** next to the title, for
    /// copy that earns its place without permanently occupying a subtitle
    /// line under every row (see `InfoHint`).
    var titleHint: String?
    var subtitle: String?
    /// A machine-produced second line — provider and model, a path, a count.
    var mono: String?
    /// A 5pt dot before the title. Permissions use it; a provider row puts its
    /// dot on the trailing side instead, beside the chevron it belongs to.
    var leadingDot: Color?
    var statusDot: Color?
    /// Red title, for 清除本地数据…
    var destructive = false
    /// Warning-tinted row, for a shortcut that isn't working.
    var tinted = false
    var pushes: SettingsRoute?
    var model: AppModel?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        if let pushes, let model {
            Button {
                model.settingsRoute = pushes
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            if let leadingDot {
                Circle()
                    .fill(leadingDot)
                    .frame(width: DS.Size.statusDot, height: DS.Size.statusDot)
            }

            // 2pt under a prose subtitle, 3pt under a mono one. The mono line
            // sits on a smaller face with tighter leading, so the mockup buys
            // the point back to keep the optical gap equal.
            VStack(alignment: .leading, spacing: mono == nil ? 2 : 3) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(DS.Text.body())
                        .foregroundStyle(destructive ? DS.Colour.error : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let titleHint {
                        InfoHint(text: titleHint)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Text.size(11.5))
                        .foregroundStyle(DS.Colour.ink(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let mono {
                    Text(mono)
                        .font(DS.Text.mono())
                        .foregroundStyle(DS.Colour.ink(0.45))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                trailing()
                if let statusDot {
                    Circle()
                        .fill(statusDot)
                        .frame(width: DS.Size.statusDot, height: DS.Size.statusDot)
                }
                if pushes != nil {
                    // The mockup's `chevron_right` is a 16px Material glyph.
                    // Material sizes the em box; SF Symbols size the cap
                    // height, and a chevron fills about two thirds of a
                    // Material box — so 16px of box is ~13pt of symbol.
                    Image(systemName: "chevron.right")
                        .font(DS.Text.size(13, .semibold))
                        .foregroundStyle(DS.Colour.ink(0.3))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, compact ? 11 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tinted ? DS.Colour.warning.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .modifier(RowDivider(divided: divided))
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(
        divided: Bool = true,
        compact: Bool = false,
        title: String,
        titleHint: String? = nil,
        subtitle: String? = nil,
        mono: String? = nil,
        leadingDot: Color? = nil,
        statusDot: Color? = nil,
        destructive: Bool = false,
        tinted: Bool = false,
        pushes: SettingsRoute? = nil,
        model: AppModel? = nil
    ) {
        self.init(
            divided: divided,
            compact: compact,
            title: title,
            titleHint: titleHint,
            subtitle: subtitle,
            mono: mono,
            leadingDot: leadingDot,
            statusDot: statusDot,
            destructive: destructive,
            tinted: tinted,
            pushes: pushes,
            model: model,
            trailing: { EmptyView() }
        )
    }
}

/// A row whose control sits under the title rather than beside it, for the
/// one control too wide to be trailing.
private struct SettingsStackedRow<Content: View>: View {
    var divided = true
    let title: String
    /// Explanation shown on hover via a small **?** next to the title (see
    /// `InfoHint`).
    var titleHint: String?
    var note: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 4) {
                Text(title)
                    .font(DS.Text.body())
                if let titleHint {
                    InfoHint(text: titleHint)
                }
            }
            content()
            if let note {
                Text(note)
                    .font(DS.Text.size(11.5))
                    .foregroundStyle(DS.Colour.ink(0.5))
                    .lineSpacing(11.5 * 0.55)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(RowDivider(divided: divided))
    }
}

/// One of three uniform permission rows.
///
/// Uniform is the point. The old Settings gave each permission its own
/// phrasing, its own symbol and its own colour rule, so "which of these is a
/// problem" took reading rather than looking. A dot, a name, a status — and
/// colour only on the one that wants something.
private struct PermissionRow: View {
    var divided = true
    let title: String
    let status: PermissionStatus
    /// Shown only when the permission is missing; there is nothing to explain
    /// about one that is granted.
    let deniedNote: String?
    let grant: () -> Void

    var body: some View {
        SettingsRow(
            divided: divided,
            compact: true,
            title: title,
            subtitle: status == .granted ? nil : deniedNote,
            leadingDot: status == .granted ? DS.Colour.ok : DS.Colour.warning,
            tinted: status != .granted
        ) {
            if status == .granted {
                Text(OpenTypeL10n.text("已授权", english: "Granted"))
                    .font(DS.Text.size(11.5))
                    .foregroundStyle(DS.Colour.ink(0.4))
            } else {
                SmallButton(
                    status == .denied
                        ? OpenTypeL10n.text("打开设置", english: "Open Settings")
                        : OpenTypeL10n.text("授权", english: "Grant"),
                    action: grant
                )
            }
        }
    }
}

/// The hairline between rows, as a modifier so both row shapes get exactly
/// one implementation of it.
private struct RowDivider: ViewModifier {
    let divided: Bool

    func body(content: Content) -> some View {
        if divided {
            content.dsHairline(.top)
        } else {
            content
        }
    }
}

// MARK: - Controls

/// Native switches retain macOS keyboard focus and accessibility semantics.
private struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

/// Native segmented choice, sharing the existing model bindings.
private struct SegmentedControl<Option: Identifiable & Equatable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let help: (Option) -> String
    let select: (Option) -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { selection.id },
            set: { id in
                if let option = options.first(where: { $0.id == id }) { select(option) }
            }
        )) {
            ForEach(options) { option in
                Text(title(option)).tag(option.id).help(help(option))
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.regular)
    }
}

/// The 24pt dropdown / chip a `Menu` wears.
private struct ControlChip: View {
    let text: String
    var mono = false
    var showsIndicator = true
    /// 8 with a chevron, 10 without. The mockup pads a bare label wider so the
    /// two shapes end up the same optical size — the chevron already carries
    /// the trailing 2pt of air that a plain word doesn't have.
    var horizontalPadding: CGFloat = 8

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(mono ? DS.Text.mono(12) : DS.Text.caption())
                .foregroundStyle(.primary)
                .lineLimit(1)
            if showsIndicator {
                // `unfold_more` at 14px of Material em box. Two stacked
                // chevrons fill a box more completely than one does, so this
                // maps lower than the 16px `chevron.right` above, not higher.
                Image(systemName: "chevron.up.chevron.down")
                    .font(DS.Text.size(10, .semibold))
                    .foregroundStyle(DS.Colour.ink(0.35))
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: 24)
        .background(
            DS.Colour.canvas,
            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(DS.Colour.controlBorder, lineWidth: 0.75)
        )
        .contentShape(Rectangle())
    }
}

/// The 24pt lifted button: 授权, 试听, 在访达中显示, and the two resets.
private struct SmallButton: View {
    let title: String
    var destructive = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Text.caption())
                .fontWeight(.medium)
                .foregroundStyle(destructive ? DS.Colour.error : Color.primary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background {
                    DS.Shadow.control(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .fill(DS.Colour.card)
                    )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(
                            destructive ? DS.Colour.error.opacity(0.35) : DS.Colour.buttonBorder,
                            lineWidth: 0.75
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Shared bits

/// The mockup's 原样写入 / 轻整理 / 先复核.
///
/// Local rather than a change to `TranscribeVariant.title`, which reads
/// 直接模式 / 轻整理 / 复核模式 and is used elsewhere (the mode menus, the
/// Review panel). The handoff's copy is final for *this* control, where the
/// three sit side by side under 「松开之后」 and name what happens rather than
/// what the setting is called.
private extension TranscribeVariant {
    var releaseTitle: String {
        switch self {
        case .direct: return OpenTypeL10n.text("原样写入", english: "As spoken")
        case .tidy: return OpenTypeL10n.text("轻整理", english: "Tidy")
        case .review: return OpenTypeL10n.text("先复核", english: "Review first")
        }
    }
}

/// Counts the records in `audit-events.v1.jsonl` off the main actor.
///
/// The trail is append-only and never trimmed, so for a heavy user it is the
/// one file in this app big enough that reading it on the main thread would be
/// felt as a hitch when Settings opens — the same reason
/// `AppModel.refreshUsageStats()` reads it detached. Counting `\n` bytes
/// rather than decoding avoids materialising the whole file as a `String`;
/// every append ends in one, so the byte count *is* the record count.
private func auditEventCountFromDisk() async -> Int {
    let url = ImmutableAuditStore().fileURL
    return await Task.detached(priority: .utility) {
        let data = (try? Data(contentsOf: url)) ?? Data()
        return data.reduce(into: 0) { total, byte in
            if byte == 0x0A { total += 1 }
        }
    }.value
}
