import SwiftUI

/// The menubar `NSPopover`'s content.
///
/// It used to be a mode switcher and nothing else: three 56pt cards with
/// subtitles, filling two thirds of the popover to answer a question — "which
/// mode will the hotkey use next" — that the three mode names already answer.
/// The redesign compresses that into one row of three cells and spends the
/// space it frees on **what is happening right now**: the shortcut's status, a
/// live 进行中 block for a running agent task, and the two most recent
/// sessions.
///
/// The reason is the app's shape. `RootView` runs as `.accessory` and is
/// usually closed, so between dictating something and getting a result there
/// is often no OpenType window on screen at all. The menu bar is then the only
/// place to look, and "which mode is next" is not what anyone is looking for.
struct MenuBarPopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var configuration: AppConfiguration
    var onOpenMainWindow: () -> Void

    init(model: AppModel, onOpenMainWindow: @escaping () -> Void) {
        self.model = model
        self.configuration = model.configuration
        self.onOpenMainWindow = onOpenMainWindow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            modeRow
            if let whisper = model.whisperStatus, whisper.backend == .local {
                whisperPreparingRow(whisper)
            }
            if model.needsLLMForSelectedMode {
                llmSetupNudge
            }
            statusRow
            if let run = runningRun {
                runningSection(run)
            }
            if !recentSessions.isEmpty {
                recentSection
            }
            if let version = announcedVersion {
                updateRow(version)
            }
            openWindowRow
            quitRow
        }
        // The handoff's 300pt. `configurePopover()` in `OpenTypeApp.swift`
        // sets the matching `NSPopover.contentSize`.
        .frame(width: 300)
        // The handoff's `rgba(250,250,248,.94)` — a warm off-white, not the
        // system's `.windowBackgroundColor` (#ECECEC in light mode), which is
        // a full step greyer than every other surface in the redesign.
        .background(DS.Colour.insetSurface)
        .tint(DS.Colour.accent)
        .environment(\.locale, OpenTypeL10n.locale)
        // §F: see `RootView.body`'s identical seam for why.
        .id(configuration.interfaceLanguageToken)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            AppBrandIcon(size: 26)

            Text("OpenType")
                .font(DS.Text.body(.semibold))

            Spacer(minLength: 8)

            Button(action: onOpenMainWindow) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.Colour.ink(0.4))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(OpenTypeL10n.text(
                "打开 OpenType（会话、听写、记忆、设置）",
                english: "Open OpenType (sessions, dictation, memory, settings)"
            ))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Modes

    /// One row, three cells. The names carry the whole distinction; the
    /// subtitles they used to have are said once in Settings instead of three
    /// times here, every time the popover opens.
    private var modeRow: some View {
        HStack(spacing: 4) {
            ForEach(InputMode.visibleModes) { mode in
                ModeCell(
                    mode: mode,
                    isSelected: configuration.selectedMode == mode
                ) {
                    model.selectMode(mode)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    /// Shown when the user selects Ask/Agent but has no LLM configured (the
    /// case a transcribe-only user reaches after skipping AI setup). Guides
    /// them to configure one rather than silently letting the mode fail —
    /// tapping it opens the main window on the Settings tab's AI-model section.
    private var llmSetupNudge: some View {
        Button {
            onOpenMainWindow()
            model.selectedTab = .settings
            model.settingsRoute = .languageModel
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                VStack(alignment: .leading, spacing: 1) {
                    Text(OpenTypeL10n.text(
                        "该模式需要 AI 模型",
                        english: "This mode needs an AI model"
                    ))
                    .font(DS.Text.caption())
                    .fontWeight(.medium)
                    Text(OpenTypeL10n.text(
                        "点此前往设置配置",
                        english: "Tap to set one up in Settings"
                    ))
                    .font(DS.Text.mono())
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(DS.Colour.warningText)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                DS.Colour.warningFill,
                in: RoundedRectangle(cornerRadius: DS.Radius.inset, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Speech model

    /// What the first launch spends its minutes on, said out loud.
    ///
    /// The popover is the surface that is always one click away, which is why
    /// this lives here rather than only in Settings: the main window is an
    /// accessory and is usually closed, so a download reported only there is a
    /// download nobody sees. Nothing is shown once the model is ready, and a
    /// remote-Whisper user never gets here at all — they have no local model
    /// and must not be shown a bar for a file they will never fetch.
    @ViewBuilder
    private func whisperPreparingRow(_ whisper: WhisperStatusSnapshot) -> some View {
        if WhisperReadinessPolicy.showsPreparingBanner(whisper.state) {
            VStack(alignment: .leading, spacing: 5) {
                Text(OpenTypeL10n.text(
                    "正在准备语音模型…（首次约 460 MB）",
                    english: "Preparing the speech model… (about 460 MB the first time)"
                ))
                .font(DS.Text.mono())
                .foregroundStyle(DS.Colour.ink(0.55))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

                // A determinate bar only when the total is actually known. An
                // unknown total degrades to the indeterminate one rather than
                // to a bar sitting at 0%, which reads as stuck — the blank
                // screen this row exists to remove, wearing a progress
                // indicator.
                if let fraction = whisper.fractionComplete {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(DS.Colour.accent)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(DS.Colour.accent)
                }

                Text(OpenTypeL10n.text(
                    "现在就可以按快捷键说话，说完的内容会等模型好了再转写。",
                    english: "You can talk now — what you say is transcribed once it is ready."
                ))
                .font(DS.Text.mono())
                .foregroundStyle(DS.Colour.ink(0.4))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        } else if whisper.state == .failed {
            VStack(alignment: .leading, spacing: 6) {
                Text(OpenTypeL10n.text(
                    "语音模型没能准备好",
                    english: "The speech model could not be prepared"
                ))
                .font(DS.Text.caption())
                .fontWeight(.medium)
                // The real message, not a generic one: 「No space left on
                // device」 tells the user what to fix and which of the two
                // exits below is theirs.
                if let error = whisper.error {
                    Text(error)
                        .font(DS.Text.mono())
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    Button {
                        model.retryWhisperModel()
                    } label: {
                        Text(OpenTypeL10n.text("重试", english: "Retry"))
                            .font(DS.Text.caption())
                            .foregroundStyle(DS.Colour.accent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onOpenMainWindow()
                        model.selectedTab = .settings
                    } label: {
                        Text(OpenTypeL10n.text(
                            "改用远程识别",
                            english: "Use remote recognition"
                        ))
                        .font(DS.Text.caption())
                        .foregroundStyle(DS.Colour.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(DS.Colour.warningText)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                DS.Colour.warningFill,
                in: RoundedRectangle(cornerRadius: DS.Radius.inset, style: .continuous)
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Status

    /// One line for "is this thing working": the gesture on the left, a 5pt
    /// dot on the right. It replaces four stacked `Label`s that each said
    /// something slightly different about the same answer.
    private var statusRow: some View {
        HStack(spacing: 8) {
            if model.sidecarNeedsAttention {
                Text(model.sidecarStatusText)
                    .font(DS.Text.mono())
                    .foregroundStyle(DS.Colour.warningText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    model.restartSidecarManually()
                } label: {
                    Text(OpenTypeL10n.text("重启服务", english: "Restart"))
                        .font(DS.Text.caption())
                        .foregroundStyle(DS.Colour.accent)
                }
                .buttonStyle(.plain)
            } else {
                Text(shortcutLine)
                    .font(DS.Text.mono())
                    .foregroundStyle(DS.Colour.ink(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Circle()
                .fill(model.sidecarNeedsAttention ? DS.Colour.warning : DS.Colour.ok)
                .frame(width: DS.Size.statusDot, height: DS.Size.statusDot)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .dsHairline(.top, color: DS.Colour.border)
    }

    /// The gesture, named from the installed preset rather than hardcoded —
    /// telling an `fn` user to hold ⌥ is the copy-side version of the bug the
    /// Tab gate used to have.
    private var shortcutLine: String {
        guard model.preferredShortcutActive,
              let hint = configuration.hotKeyPreset.modeSwitchHint
        else { return model.shortcutStatus }
        return hint
    }

    // MARK: - 进行中

    private var runningRun: AgentRunRecord? {
        model.agentRuns.first { $0.status.isRunning }
    }

    /// The block the whole redesign of this popover is for: a task that is
    /// still going, what it is doing, and how long it has been at it.
    private func runningSection(_ run: AgentRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                MenuBarBreathingDot(colour: DS.Colour.accent)

                Text(OpenTypeL10n.text("进行中", english: "Running"))
                    .font(DS.Text.groupLabel())
                    .tracking(DS.Tracking.groupLabel)
                    .foregroundStyle(DS.Colour.ink(0.45))

                Spacer(minLength: 4)

                TimelineView(.periodic(from: run.dispatchedAt, by: 1)) { context in
                    Text(OverlayElapsed.short(
                        max(0, context.date.timeIntervalSince(run.dispatchedAt))
                    ))
                    .font(DS.Text.mono(10.5))
                    .foregroundStyle(DS.Colour.ink(0.4))
                }
            }

            Text(run.task)
                .font(DS.Text.size(12.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(toolLine(for: run))
                .font(DS.Text.mono(10.5))
                .foregroundStyle(DS.Colour.ink(0.45))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.Colour.accent.opacity(0.05))
        .dsHairline(.top, color: DS.Colour.border)
    }

    /// The tool the run is on, parsed out of the last progress line the same
    /// way the overlay's working pill does it.
    private func toolLine(for run: AgentRunRecord) -> String {
        guard let last = run.steps.last else {
            return OpenTypeL10n.text("正在准备…", english: "Starting up…")
        }
        guard let parsed = AgentToolLine.parse(last.detail) else {
            return last.detail
        }
        return parsed.summary.isEmpty ? parsed.tool : "\(parsed.tool) · \(parsed.summary)"
    }

    // MARK: - 最近

    private var recentSessions: [ConversationSummary] {
        Array(model.sessionConversations.prefix(2))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(OpenTypeL10n.text("最近", english: "Recent"))
                .font(DS.Text.groupLabel())
                .tracking(DS.Tracking.groupLabel)
                .foregroundStyle(DS.Colour.ink(0.42))
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            ForEach(recentSessions) { conversation in
                Button {
                    open(conversation)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(dotColour(for: conversation))
                            .frame(width: DS.Size.statusDot, height: DS.Size.statusDot)

                        Text(conversation.title)
                            .font(DS.Text.size(12.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(MenuBarSessionTime.text(forMilliseconds: conversation.updatedAt))
                            .font(DS.Text.mono(10.5))
                            .foregroundStyle(DS.Colour.ink(0.35))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .dsHairline(.top, color: DS.Colour.border)
    }

    private func dotColour(for conversation: ConversationSummary) -> Color {
        conversation.sessionKind == .agent ? DS.Colour.agent : DS.Colour.accent
    }

    /// Opening a session from here is the same act as opening it in the list,
    /// so it goes through the same state rather than a menubar-only path.
    private func open(_ conversation: ConversationSummary) {
        guard let kind = conversation.sessionKind else { return }
        onOpenMainWindow()
        model.selectedTab = .sessions
        model.focusedConversation = FocusedConversation(id: conversation.id, kind: kind)
    }

    // MARK: - 有新版本

    /// The version this row just copied the command for. Kept for a beat after
    /// the press so the button can say 「已复制」: acknowledging the update is
    /// what hides the row, and a row that disappears out from under the cursor
    /// leaves no evidence that anything was copied.
    @State private var copiedVersion: String?

    /// `nil` unless there is something to say — see
    /// `AppModel.announcedUpdateVersion`, which is where 「同一个版本只提示
    /// 一次」 is decided.
    private var announcedVersion: String? {
        model.announcedUpdateVersion ?? copiedVersion
    }

    /// §B's second surface, and the one that matters: this window is
    /// `.accessory` and usually closed, so an update notice that only 设置
    /// carries is one nobody ever sees. Not a modal, not a download — one row
    /// and the command that does it.
    private func updateRow(_ version: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Colour.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(OpenTypeL10n.text(
                    "有新版本 \(version)",
                    english: "Version \(version) available"
                ))
                .font(DS.Text.size(12.5))

                Text(OpenTypeL10n.text(
                    "复制命令，在终端里跑一次就更新好了",
                    english: "Copy the command and run it once in a terminal"
                ))
                .font(DS.Text.mono(10.5))
                .foregroundStyle(DS.Colour.ink(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.copyUpdateInstallCommand()
                copiedVersion = version
                Task {
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    copiedVersion = nil
                }
            } label: {
                Text(
                    copiedVersion == version
                        ? OpenTypeL10n.text("已复制", english: "Copied")
                        : OpenTypeL10n.text("复制安装命令", english: "Copy command")
                )
                .font(DS.Text.caption())
                .foregroundStyle(DS.Colour.accent)
            }
            .buttonStyle(.plain)
            .disabled(copiedVersion == version)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // The same accent wash 进行中 uses: this row wants attention without
        // being a warning, and the app has exactly one colour for that.
        .background(DS.Colour.accent.opacity(0.05))
        .dsHairline(.top, color: DS.Colour.border)
    }

    // MARK: - Footer

    private var openWindowRow: some View {
        Button(action: onOpenMainWindow) {
            HStack(spacing: 8) {
                Text(OpenTypeL10n.text("打开主窗口", english: "Open main window"))
                    .font(DS.Text.size(12.5))
                Spacer(minLength: 0)
                Text("⌘O")
                    .font(DS.Text.mono())
            }
            // The handoff puts the ink on the row, not on each run: the label
            // and the shortcut are both `rgba(28,28,30,.5)`.
            .foregroundStyle(DS.Colour.ink(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("o", modifiers: .command)
        .dsHairline(.top, color: DS.Colour.border)
    }

    /// The menu bar is the only surface that's always reachable — the app is
    /// `.accessory` whenever the main window is closed, so there's no Dock
    /// icon and no app menu to quit from. Spelled out with a label rather
    /// than an icon so it doesn't read as "close the popover".
    private var quitRow: some View {
        Button {
            model.quit()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
                Text(OpenTypeL10n.text("退出 OpenType", english: "Quit OpenType"))
                    .font(DS.Text.size(12.5))
                Spacer(minLength: 0)
            }
            // Not in the handoff, so it takes the treatment of the row it sits
            // under rather than inventing one.
            .foregroundStyle(DS.Colour.ink(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHairline(.top, color: DS.Colour.border)
    }
}

/// One of the three mode cells: icon over label, 52pt tall, and accent-filled
/// when it is the one the hotkey will use.
private struct ModeCell: View {
    let mode: InputMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 17, weight: .medium))
                Text(mode.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.white : DS.Colour.ink(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isSelected ? DS.Colour.accent : DS.Colour.codeFill,
                in: RoundedRectangle(cornerRadius: DS.Radius.nested, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.shortTitle)
    }
}

/// The same 1.4s breath the overlay's running states use, so "still going"
/// looks the same wherever it is said.
private struct MenuBarBreathingDot: View {
    let colour: Color
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: DS.Size.statusDot, height: DS.Size.statusDot)
            .opacity(dim ? 0.35 : 1)
            .scaleEffect(dim ? 0.82 : 1)
            .animation(
                .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                value: dim
            )
            .onAppear { dim = true }
    }
}

/// `13:20` for today, `昨天`, then a date. Short enough to sit at the right
/// edge of a 300pt popover without pushing the title out.
enum MenuBarSessionTime {
    static func text(forMilliseconds milliseconds: Int) -> String {
        text(for: Date(timeIntervalSince1970: Double(milliseconds) / 1000))
    }

    static func text(for date: Date, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = OpenTypeL10n.locale
        if calendar.isDate(date, inSameDayAs: now) {
            return timeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return OpenTypeL10n.text("昨天", english: "Yesterday")
        }
        return dayFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = OpenTypeL10n.locale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = OpenTypeL10n.locale
        formatter.dateFormat = "MM-dd"
        return formatter
    }()
}
