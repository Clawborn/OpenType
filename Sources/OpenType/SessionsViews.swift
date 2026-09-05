import SwiftUI

/// The redesigned 会话 screen: the merged Q&A + Agent list, and the thread
/// beside it (2026-08 handoff, sections 01 and 02).
///
/// Two tabs became one because they were never two places. A user who asks a
/// question and then gives a task should not have to remember which tab it
/// landed in — the data shape was already identical (a `conversationId` and a
/// message list; only the toolset differs), so the split was an artifact of
/// there having been two fetches. One list, and a 5pt dot carries the
/// distinction.
///
/// Everything here is measured from the handoff, and where the mockup and a
/// token disagree the **mockup wins** — 稿子优先, the owner's ruling of
/// 2026-08-15. An earlier pass rounded the markup's 11.5pt chips to 12, its 8pt
/// inner block to 10, its 5pt tag to 6 and its six border alphas to one, on the
/// theory that a closed scale is worth a point here and there. Across six
/// screens that stopped being a rounding convention and became the
/// implementation overruling the design, so the literals are back and
/// `DesignTokens.swift` carries a step for each of them.

// MARK: - List column

/// The 334pt middle column: header, filter chips, the pinned 进行中 card, and
/// the date-grouped history.
///
/// The list is grouped into **one card per day holding N rows**, not one card
/// per row. A card per row spends a border, a shadow and 8pt of gutter on
/// every entry to say something the rows already say by being adjacent; at
/// twelve conversations it reads as twelve objects rather than one list.
struct SessionsListColumn: View {
    @ObservedObject var model: AppModel
    /// Only changes the content gutter (12 → 14). Row and card metrics are
    /// identical in both layouts, so nothing has to be re-learned on resize.
    var narrow: Bool = false

    @State private var searching = false
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if searching { searchField }
            filterChips
            list
        }
        .background(DS.Colour.canvas)
        .task {
            await model.refreshAskConversations()
            await model.refreshAgentConversations()
        }
    }

    // MARK: Header

    private var header: some View {
        // Deliberately not `ColumnHeader(narrow:)`: that component hardcodes the
        // page gutter (24 wide / 14 narrow) and the handoff gives this column 16
        // in *both* layouts — only the scrolling content below tightens to 14.
        // Passing `narrow` would move the title relative to the chips it heads.
        SessionColumnHeader(leading: DS.Space.content, trailing: DS.Space.content, spacing: 10) {
            Text(OpenTypeL10n.text("会话", english: "Sessions"))
                .font(DS.Text.title())
                .tracking(DS.Tracking.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            SessionIconButton(
                symbol: "magnifyingglass",
                filled: false,
                help: OpenTypeL10n.text("搜索会话", english: "Search sessions")
            ) {
                searching.toggle()
                if !searching { query = "" }
            }

            SessionIconButton(
                symbol: "plus",
                filled: true,
                help: OpenTypeL10n.text("新对话", english: "New conversation")
            ) {
                startNewConversation()
            }
        }
    }

    /// The magnifying glass has to do something, and the handoff draws the
    /// button without drawing a results screen — so it filters what is already
    /// rendered, exactly like the chips, rather than opening a search mode with
    /// its own state.
    private var searchField: some View {
        // Undrawn, so it borrows 3A's search box wholesale rather than
        // inventing a fourth header-control spec: 26pt, r7, 11pt gutter, a .09
        // edge and the control lift.
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(DS.Text.size(15))
                .foregroundStyle(DS.Colour.ink(0.5))
            TextField(
                "",
                text: $query,
                prompt: Text(OpenTypeL10n.text("搜索会话", english: "Search conversations"))
                    .font(DS.Text.caption())
                    .foregroundColor(DS.Colour.ink(0.4))
            )
            .textFieldStyle(.plain)
            .font(DS.Text.caption())
        }
        .padding(.horizontal, 11)
        .frame(height: DS.Size.headerControl)
        .modifier(SessionHeaderControlChrome())
        .padding(.horizontal, DS.Space.content)
        .padding(.bottom, 8)
    }

    private var filterChips: some View {
        HStack(spacing: 5) {
            ForEach(SessionFilter.allCases) { filter in
                SessionFilterChip(
                    filter: filter,
                    selected: model.sessionFilter == filter
                ) {
                    model.sessionFilter = filter
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.content)
        .padding(.bottom, 10)
    }

    // MARK: Body

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !runningRuns.isEmpty {
                    runningGroup
                }
                ForEach(SessionDay.grouped(visibleConversations)) { day in
                    dayGroup(day)
                }
                if runningRuns.isEmpty, visibleConversations.isEmpty {
                    empty
                }
            }
            .padding(.horizontal, narrow ? DS.Space.pageNarrow : 12)
            .padding(.bottom, narrow ? DS.Space.pageNarrow : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    /// The mockup does not draw the empty case, but the tabs this screen
    /// replaces each had one, and a blank column reads as broken rather than
    /// as new.
    private var empty: some View {
        Text(emptyMessage)
            .font(DS.Text.caption())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
            .padding(.horizontal, 16)
    }

    /// §I's partial-search honesty, carried through to what the empty state
    /// actually says. `SessionSearchOutcome` keeps "no sessions at all
    /// (nothing to search)", "searched everything on screen, nothing
    /// matched" and "matched nothing among what was actually loaded" as three
    /// distinct claims — collapsing them to `visibleConversations.isEmpty`
    /// plus `query.isEmpty` would make the third one lie about the archive
    /// having been searched.
    private var emptyMessage: String {
        switch searchOutcome {
        case .matches:
            // Only reachable as `.matches([])` here (`empty` only renders
            // when `visibleConversations` is empty) — a blank query over an
            // empty (or chip-filtered-to-empty) list, not a failed search.
            return OpenTypeL10n.text(
                "还没有会话。按住快捷键说一句，就有了。",
                english: "No sessions yet. Hold the shortcut and say something."
            )
        case .noMatches:
            return OpenTypeL10n.text("没有匹配的会话", english: "No matching sessions")
        case .noMatchesInLoadedSubset(let bodiesSearched, let total):
            return OpenTypeL10n.text(
                "没有匹配的会话（只搜索了已加载的 \(bodiesSearched)/\(total) 个会话正文）",
                english: "No matches — only searched the body of \(bodiesSearched) of \(total) loaded conversations"
            )
        }
    }

    private var runningGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                SessionPulseDot()
                SessionGroupLabel(OpenTypeL10n.text("进行中", english: "In progress"))
            }
            .padding(.horizontal, DS.Space.labelInset)

            ForEach(runningRuns) { run in
                SessionRunningCard(run: run) {
                    model.cancelAgentRun(run.id)
                }
            }
        }
    }

    private func dayGroup(_ day: SessionDay) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SessionGroupLabel(day.title)
                .padding(.horizontal, DS.Space.labelInset)

            VStack(spacing: 0) {
                ForEach(Array(day.conversations.enumerated()), id: \.element.id) { index, conversation in
                    SessionRow(
                        conversation: conversation,
                        selected: model.focusedConversation?.id == conversation.id,
                        firstInCard: index == 0
                    ) {
                        open(conversation)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .dsCard()
        }
    }

    // MARK: Data

    private var runningRuns: [AgentRunRecord] {
        model.agentRuns.filter { $0.status.isRunning }
    }

    /// Chips and search narrow what is drawn, never what was fetched — so
    /// switching either costs no refetch and can never lose a row.
    private var visibleConversations: [ConversationSummary] {
        searchOutcome.conversations
    }

    /// The chip-filtered list, run through `SessionSearch` — see `empty`
    /// above for why the outcome (not just its conversations) matters.
    private var searchOutcome: SessionSearchOutcome {
        let byChip = SessionList.filtered(model.sessionConversations, by: model.sessionFilter)
        return SessionSearch.search(byChip, query: query, loadedDetails: loadedDetails)
    }

    /// The bodies actually held in memory right now — at most the ask and
    /// agent threads the user has opened (`AppModel.askConversationDetail` /
    /// `agentConversationDetail`), never the full archive, which lives in the
    /// sidecar. This is the "loaded" half of §I's partial-search honesty.
    private var loadedDetails: [Int: ConversationDetail] {
        var details: [Int: ConversationDetail] = [:]
        if let ask = model.askConversationDetail { details[ask.id] = ask }
        if let agent = model.agentConversationDetail { details[agent.id] = agent }
        return details
    }

    private func open(_ conversation: ConversationSummary) {
        // A conversation written by a newer sidecar has a `kind` this build
        // cannot route. It stays listed rather than silently impersonating an
        // ask thread, which would send its next turn to the wrong endpoint.
        guard let kind = conversation.sessionKind else { return }
        model.focusedConversation = FocusedConversation(id: conversation.id, kind: kind)
        switch kind {
        case .ask: model.openAskConversation(conversation.id)
        case .agent: model.openAgentConversation(conversation.id)
        }
    }

    private func startNewConversation() {
        model.focusedConversation = nil
        model.startNewAskConversation()
        model.startNewAgentConversation()
    }
}

// MARK: - Thread column

/// The detail column: one conversation, its step log, and a composer that
/// continues it.
///
/// Two decisions from the handoff carry most of the weight here. **Assistant
/// turns get no bubble** — a bubble frames a remark, and an Agent's answer is
/// a document with headings, tables and paths in it; boxing it at 78% width
/// and centring the reader's eye on a chat rhythm fights what it is. The user's
/// own turn keeps its bubble precisely because it *is* a remark. And **the
/// composer continues `conversationId`** rather than starting a fresh
/// conversation, so a thread you are reading is a thread you can talk to.
struct SessionThreadColumn: View {
    @ObservedObject var model: AppModel
    var narrow: Bool = false
    /// Sends a typed turn into `conversation`, continuing it.
    ///
    /// A closure rather than a call into `AppModel` because no entry point for
    /// a *typed* turn exists yet — every dispatch today starts from a
    /// recording (`dispatchAskRun`/`dispatchAgentRun` are private and take a
    /// transcript). Left required, not defaulted, so wiring it is a decision
    /// someone makes rather than a no-op they inherit.
    var onSubmit: (String, FocusedConversation) -> Void

    @State private var draft = ""
    /// §I's remaining gap: same confirm-before-destroy pattern the dictation
    /// row's delete uses (`DictationViews.swift`'s `showingDeleteConfirmation`,
    /// `509d3f4`) rather than a second convention for the same kind of action.
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Group {
            if let focused = model.focusedConversation {
                thread(focused)
            } else {
                placeholder
            }
        }
        .background(DS.Colour.card)
    }

    private func thread(_ focused: FocusedConversation) -> some View {
        VStack(spacing: 0) {
            header(focused)
            if let detail = detail(for: focused) {
                messages(detail, focused: focused)
            } else {
                loading
            }
            composer(focused)
        }
        // This destroys data and there is no undo — matching the dictation
        // row's own delete confirmation rather than a second convention for
        // the same kind of action.
        .confirmationDialog(
            OpenTypeL10n.text("删除这条会话？", english: "Delete this conversation?"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(OpenTypeL10n.text("确认删除", english: "Delete"), role: .destructive) {
                deleteConversation(focused)
            }
        } message: {
            Text(OpenTypeL10n.text("删除后无法恢复。", english: "This cannot be undone."))
        }
    }

    // MARK: Header

    private func header(_ focused: FocusedConversation) -> some View {
        // The handoff gives this header its own gutters — 20 on both sides wide,
        // and 10/14 narrow so the back chevron sits closer to the edge than the
        // ellipsis does. `ColumnHeader`'s fixed 24/14 would put the type tag a
        // step out from the content under it.
        SessionColumnHeader(
            leading: narrow ? 10 : 20,
            trailing: narrow ? DS.Space.pageNarrow : 20,
            spacing: narrow ? 8 : 10
        ) {
            if narrow {
                // Narrow pushes the thread over the list, so the only way
                // back is here. Wide keeps the list visible beside it.
                Button(action: clearFocus) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(DS.Colour.accent)
                }
                .buttonStyle(.plain)
                .help(OpenTypeL10n.text("返回列表", english: "Back to list"))
            }

            SessionKindTag(kind: focused.kind)

            Text(detail(for: focused)?.title ?? OpenTypeL10n.text("对话", english: "Conversation"))
                // 14/600 — a heading for one conversation, deliberately a step
                // under the 15/600 that heads a section of a page.
                .font(DS.Text.size(14, .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Narrow drops the copy button and keeps only 「更多」: the back
            // chevron has already taken a slot, and the same action is one row
            // down the menu. The handoff draws it exactly this way.
            if !narrow {
                Button {
                    copyTranscript(focused)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(DS.Text.size(17))
                        .foregroundStyle(DS.Colour.ink(0.45))
                }
                .buttonStyle(.plain)
                .help(OpenTypeL10n.text("复制全文", english: "Copy transcript"))
            }

            Menu {
                Button(OpenTypeL10n.text("新对话", english: "New conversation")) {
                    clearFocus()
                }
                Button(OpenTypeL10n.text("复制全文", english: "Copy transcript")) {
                    copyTranscript(focused)
                }
                if detail(for: focused) != nil {
                    Divider()
                    Button(OpenTypeL10n.text("导出为 Markdown", english: "Export as Markdown")) {
                        exportConversation(focused, as: .markdown)
                    }
                    Button(OpenTypeL10n.text("导出为 JSON", english: "Export as JSON")) {
                        exportConversation(focused, as: .json)
                    }
                }
                Divider()
                // §I: the other half of single-entry deletion — the dictation
                // history row already got its right-click 删除; this is the
                // conversation side, behind the same confirmation.
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label(OpenTypeL10n.text("删除会话", english: "Delete conversation"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(DS.Text.size(17))
                    .foregroundStyle(DS.Colour.ink(0.45))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .modifier(SessionEdgeBorder(edge: .bottom))
    }

    // MARK: Messages

    private func messages(_ detail: ConversationDetail, focused: FocusedConversation) -> some View {
        GeometryReader { proxy in
            let gutter = narrow ? 18.0 : 28.0
            let available = max(proxy.size.width - gutter * 2, 1)

            ScrollViewReader { scroller in
                ScrollView {
                    // Computed once per render, not once per message: the
                    // anchor is an `O(n)` scan over the thread, and the 5-arg
                    // `SessionStepLogResolver.steps` overload below exists
                    // specifically so a loop over every message doesn't
                    // re-run it `O(n)` times.
                    let live = liveRun(for: focused)
                    let anchor = stepLogAnchor(in: detail)
                    LazyVStack(alignment: .leading, spacing: narrow ? 18 : 20) {
                        ForEach(Array(detail.messages.enumerated()), id: \.element.id) { index, message in
                            // The log and the answer it produced are one turn at
                            // 12pt, not two messages at 20 — they are the same
                            // reply, seen from two distances.
                            VStack(alignment: .leading, spacing: 12) {
                                // Every message gets a chance to render its own
                                // step log now, not just the anchor: a
                                // historical (already-persisted) thread has no
                                // in-flight run at all, so the ONLY way its
                                // steps ever show is each message asking for
                                // its own persisted value here. The resolver is
                                // what still makes an ACTIVELY running turn win
                                // at the anchor over that same message's own
                                // (stale-by-comparison) persisted content — see
                                // `SessionStepLogResolver`'s doc comment.
                                if let steps = SessionStepLogResolver.steps(
                                    forMessageAt: index,
                                    in: detail.messages,
                                    conversationId: focused.id,
                                    liveRun: live,
                                    anchorIndex: anchor
                                ) {
                                    // Only the in-flight run's own log opens
                                    // expanded — a historical/persisted log
                                    // (including a just-finished, no-longer-
                                    // running trailing one) starts collapsed,
                                    // since a thread reopened after a fresh
                                    // launch showing every past run's steps
                                    // already unfurled would bury the actual
                                    // conversation under old step tables.
                                    StepLog(
                                        steps: steps,
                                        initiallyExpanded: index == anchor && live?.isActivelyRunning == true
                                    )
                                }
                                // 78% wide, 80% narrow: the same bubble reads as
                                // narrower when the column is, so the handoff
                                // gives the tighter layout the looser cap.
                                SessionTurn(message: message, maxBubbleWidth: available * (narrow ? 0.80 : 0.78))
                                // §H: the detail page's copy of the result
                                // card's 「交给助理去做」 — same decision
                                // (`AssistantEscalation.offered(forAssistantMessage:in:)`),
                                // so an ask thread offers it here exactly when
                                // the floating card would have offered it too.
                                if let escalation = AssistantEscalation.offered(
                                    forAssistantMessage: message, in: detail
                                ) {
                                    escalateRow(escalation)
                                }
                            }
                            .id(message.id)
                        }
                        if isWorking(focused) {
                            SessionWorkingRow()
                                .id(Self.workingRowID)
                        }
                    }
                    .padding(.horizontal, gutter)
                    .padding(.vertical, narrow ? 20 : DS.Space.pageWide)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .onAppear { scroller.scrollTo(bottomAnchor(detail, focused: focused), anchor: .bottom) }
                .onChange(of: detail.messages.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        scroller.scrollTo(bottomAnchor(detail, focused: focused), anchor: .bottom)
                    }
                }
            }
        }
    }

    private static let workingRowID = "session.working"

    private func bottomAnchor(_ detail: ConversationDetail, focused: FocusedConversation) -> AnyHashable {
        isWorking(focused)
            ? AnyHashable(Self.workingRowID)
            : AnyHashable(detail.messages.last?.id ?? 0)
    }

    /// Where the step log goes: immediately before the answer it produced, so
    /// the reading order is task → what it did → what it found.
    ///
    /// Delegates to `SessionStepLogResolver.anchorIndex` so the "last
    /// non-user message" rule has exactly one definition. `messages(_:focused:)`
    /// calls this exactly ONCE per render (not once per message) and threads
    /// the result into the 5-arg `SessionStepLogResolver.steps(...:anchorIndex:)`
    /// overload for every message in the loop — computing the anchor is an
    /// `O(n)` scan over the thread, so re-deriving it per message would make
    /// rendering an `O(n²)` thread scan instead of `O(n)`.
    private func stepLogAnchor(in detail: ConversationDetail) -> Int? {
        SessionStepLogResolver.anchorIndex(in: detail.messages)
    }

    /// The in-flight run state for `focused`'s conversation, if any —
    /// what `SessionStepLogResolver.LiveRun` is built from.
    ///
    /// Since the 2026-08-28 skill/agent-UI batch, steps ARE persisted with
    /// the conversation (`ConversationMessageSummary.steps`, written by the
    /// sidecar alongside the assistant message a run produced), so a
    /// historical thread — including one reopened after a fresh launch —
    /// has its own log to show without this at all; see
    /// `SessionStepLogResolver`'s doc comment for the full precedence. This
    /// method supplies only the OTHER half: the current run's live,
    /// not-yet-persisted (or just-settled) state, matched through the voice
    /// surface's `agentPanelState`, which is the only place a run's
    /// conversation id is known while `isActivelyRunning`.
    ///
    /// Only Agent threads have a live source at all: `AskPanelState` (Ask's
    /// equivalent surface state) carries no step feed of its own — Ask's web
    /// tool calls complete inside the one blocking `/oneshot/ask` call, with
    /// no async polling ticker the way Agent's `/agent/run` has. An Ask
    /// thread's steps, when it has any, are therefore always read from its
    /// own persisted value, never from a live record here.
    private func liveRun(for focused: FocusedConversation) -> SessionStepLogResolver.LiveRun? {
        guard focused.kind == .agent,
              let panel = model.agentPanelState,
              panel.conversationId == focused.id
        else { return nil }
        return SessionStepLogResolver.LiveRun(
            conversationId: focused.id,
            steps: panel.steps.map(\.asStepSummary),
            isActivelyRunning: panel.phase == .running
        )
    }

    /// §H's button, styled to match the unified voice surface's result-card
    /// action row (`OverlayController.swift`'s `VoiceSurfaceCard.footer`) —
    /// the same feature reached from a second surface should look like the
    /// same button, not grow a second convention.
    private func escalateRow(_ escalation: AssistantEscalation) -> some View {
        HStack {
            Spacer(minLength: 0)
            Button(OpenTypeL10n.text("交给助理去做", english: "Hand off to the assistant")) {
                model.escalateToAgent(escalation)
            }
            .buttonStyle(.plain)
            .font(DS.Text.size(11.5))
            .foregroundStyle(DS.Colour.ink(0.6))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                DS.Colour.control,
                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            )
        }
    }

    private func isWorking(_ focused: FocusedConversation) -> Bool {
        if let panel = model.agentPanelState,
           panel.conversationId == focused.id,
           panel.phase == .running {
            return true
        }
        if let ask = model.askPanelState,
           ask.conversationId == focused.id,
           ask.answer == nil {
            return true
        }
        return false
    }

    private var loading: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(OpenTypeL10n.text("正在加载对话…", english: "Loading conversation…"))
                .font(DS.Text.caption())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 22))
                .foregroundStyle(.quaternary)
            Text(OpenTypeL10n.text("选一条会话，或按住快捷键说话", english: "Pick a session, or hold the shortcut and speak"))
                .font(DS.Text.caption())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Composer

    private func composer(_ focused: FocusedConversation) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text(ConversationRecordingTarget(conversation: focused).placeholder)
                            .font(DS.Text.body())
                            .foregroundStyle(DS.Colour.ink(0.35))
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(DS.Text.body())
                        .lineLimit(1...6)
                        .onSubmit { send(focused) }
                }
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)

                SessionComposerButton(
                    symbol: model.isRecording(in: focused) ? "stop.fill" : "mic.fill",
                    filled: model.isRecording(in: focused),
                    help: model.isRecording(in: focused)
                        ? OpenTypeL10n.text("结束录音", english: "Finish recording")
                        : OpenTypeL10n.text("用语音继续本次会话", english: "Continue this conversation by voice")
                ) {
                    model.toggleConversationRecording(in: focused)
                }
                SessionComposerButton(symbol: "arrow.up", filled: true, help: OpenTypeL10n.text("发送", english: "Send")) {
                    send(focused)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            .background(DS.Colour.canvas, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                // .08, a step heavier than a card's own edge: the composer is
                // the same colour as the page behind it, so its own edge is the
                // only thing that says where it starts.
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.Colour.borderStrong, lineWidth: 0.75)
            )
        }
        .padding(.horizontal, narrow ? DS.Space.content : 20)
        .padding(.top, narrow ? 12 : 14)
        .padding(.bottom, narrow ? DS.Space.content : 18)
        .modifier(SessionEdgeBorder(edge: .top))
    }

    private func send(_ focused: FocusedConversation) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        onSubmit(text, focused)
    }

    // MARK: Actions

    private func detail(for focused: FocusedConversation) -> ConversationDetail? {
        let candidate = focused.kind == .agent
            ? model.agentConversationDetail
            : model.askConversationDetail
        // The two details are fetched independently, so a stale one from the
        // previously-open thread can still be sitting in the other slot.
        return candidate?.id == focused.id ? candidate : nil
    }

    private func copyTranscript(_ focused: FocusedConversation) {
        guard let detail = detail(for: focused) else { return }
        model.copy(detail.messages.map(\.content).joined(separator: "\n\n"))
    }

    private func clearFocus() {
        model.focusedConversation = nil
        model.startNewAskConversation()
        model.startNewAgentConversation()
    }

    /// §I: deletes the conversation currently open in this column.
    /// `AppModel.deleteConversation(_:)` also resolves `focusedConversation`
    /// (to `nil`, since this is always the focused thread), which is what
    /// leaves this column showing `placeholder` afterwards rather than a
    /// detail view for a conversation that no longer exists.
    private func deleteConversation(_ focused: FocusedConversation) {
        Task { await model.deleteConversation(focused) }
    }

    /// §I: a single conversation, exported to Markdown or JSON. Placed in the
    /// same `…` menu as 「新对话」/「复制全文」 rather than a second entry
    /// point, matching where the spec puts it.
    private func exportConversation(_ focused: FocusedConversation, as format: HistoryExportPanel.Format) {
        guard let detail = detail(for: focused) else { return }
        let content: String
        switch format {
        case .markdown: content = HistoryExport.markdown(conversation: detail, exportedAt: Date())
        case .json: content = HistoryExport.json(conversation: detail, exportedAt: Date())
        }
        let suggestedName = detail.title.isEmpty ? "OpenType-Conversation-\(detail.id)" : "OpenType-\(detail.title)"
        HistoryExportPanel.save(content, suggestedName: suggestedName, format: format)
    }
}

// MARK: - Step log

/// The Agent's step-by-step log, as one collapsible monospaced block.
///
/// Extracted rather than inlined because the thread and the result card both
/// show it, and they showed *different* logs before: the overlay had a live
/// ticker, the run row had its own list, and a finished conversation had none
/// at all. Three renderings of one thing is three places for it to drift.
///
/// The three columns are a table on purpose — index, tool, detail — because
/// what a reader does with a step log is scan for the one tool call that
/// explains the result, and a ragged left edge makes that a read instead of a
/// scan.
struct StepLog: View {
    private let entries: [StepLogEntry]
    private let elapsed: String?
    @State private var expanded: Bool

    /// From either a message's persisted step log (`ConversationMessageSummary.steps`
    /// / `AgentRunRecord.steps`) or the live progress feed
    /// (`AgentProgressPanelState.steps`, mapped through
    /// `AgentProgressStep.asStepSummary`) — `SessionStepLogResolver` picks
    /// which source applies per message before either ever reaches this
    /// view, so there is only one initializer to reconcile them in.
    init(steps: [AgentStepSummary], elapsed: String? = nil, initiallyExpanded: Bool = true) {
        self.entries = steps.map(StepLogEntry.init(step:))
        self.elapsed = elapsed
        self._expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(DS.Text.size(14))
                        .foregroundStyle(DS.Colour.ink(0.45))
                    Text(OpenTypeL10n.text("执行了 \(entries.count) 步", english: "\(entries.count) steps"))
                        .font(DS.Text.caption())
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.Colour.ink(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let elapsed {
                        Text(elapsed)
                            .font(DS.Text.mono())
                            .foregroundStyle(DS.Colour.ink(0.4))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(SessionConditionalHairline(active: expanded, edge: .bottom))

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text(String(format: "%02d", index + 1))
                                .font(DS.Text.mono(10.5))
                                .foregroundStyle(DS.Colour.ink(0.3))
                                .frame(width: 16, alignment: .leading)
                            Text(entry.label)
                                .font(DS.Text.mono(10.5))
                                .foregroundStyle(entry.tint)
                                .lineLimit(1)
                                .frame(width: 64, alignment: .leading)
                            Text(entry.detail)
                                .font(DS.Text.mono())
                                .foregroundStyle(DS.Colour.ink(0.6))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
        }
        .background(DS.Colour.insetSurface, in: RoundedRectangle(cornerRadius: DS.Radius.inset, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.inset, style: .continuous)
                .strokeBorder(DS.Colour.border, lineWidth: 0.75)
        )
    }
}

/// Resolves which step log (if any) one message in a thread should render —
/// the merge seam between a message's own PERSISTED steps
/// (`ConversationMessageSummary.steps`, since the 2026-08-28 skill/agent-UI
/// batch) and a conversation's LIVE, in-flight run state, neither of which
/// alone is enough: persisted-only misses the run that is still going and
/// has not been written down yet, live-only misses every historical thread
/// from before this session (or before this app launch).
///
/// **Pinned precedence** (docs/superpowers/specs/2026-08-28-skill-agent-ui-and-step-log-persistence.md
/// §2; see `ConversationStepLogPersistenceTests.swift`'s header for the full
/// worked-through rationale, including the case the first draft of that
/// spec got backwards):
/// - A message's own persisted `steps`, when present and non-empty, is what
///   it shows at every **non-anchor** index — a live run anywhere else in
///   the conversation never reaches back and changes an already-settled
///   turn's own log.
/// - At the **anchor** (the last non-user message — where a run-in-progress
///   attaches, since its own assistant message does not exist yet), a
///   matching, **actively running** live record wins unconditionally, even
///   over that anchor's own non-empty persisted steps: a follow-up run's
///   live feed must keep showing for its whole duration, not just for one
///   race-y instant.
/// - Once a matching live record is **not** actively running (the run
///   already finished, and this is a trailing, not-yet-torn-down record),
///   the anchor's own persisted value preempts it — persisted first if
///   present, the live record only as a fallback when the anchor genuinely
///   has no persisted value yet.
/// - `[]` (persisted or live) normalises to "no steps" throughout, never a
///   zero-row collapsible block.
/// - A live record for a **different** conversation never applies.
enum SessionStepLogResolver {
    /// The state of an in-flight (or just-finished) run, if one exists for
    /// the conversation currently being rendered. The caller
    /// (`SessionThreadColumn.liveRun(for:)`) builds this from
    /// `AppModel.agentPanelState`.
    struct LiveRun: Equatable {
        var conversationId: Int
        var steps: [AgentStepSummary]
        /// Mirrors `AgentProgressPanelState.phase == .running` — the same
        /// condition `isWorking(_:)` already tests. Distinguishes "this run
        /// has not finished yet" (live wins unconditionally at the anchor)
        /// from "this is a leftover record for a run that already completed
        /// or failed" (persisted wins, live is only a fallback).
        var isActivelyRunning: Bool
    }

    /// The last non-user message in a thread — where the step log goes,
    /// immediately before the answer it produced. Single definition;
    /// `SessionThreadColumn.stepLogAnchor(in:)` delegates here rather than
    /// re-stating the rule.
    static func anchorIndex(in messages: [ConversationMessageSummary]) -> Int? {
        messages.lastIndex { $0.role != "user" }
    }

    /// Which steps (if any) `messages[index]` should render. See this type's
    /// doc comment for the full precedence rule.
    ///
    /// Thin wrapper over the 5-arg overload below, which does the actual
    /// work: computes the anchor once and delegates. Kept exactly as the
    /// pinned, stage-1-tested entry point
    /// (`ConversationStepLogPersistenceTests.swift`) — a render loop calling
    /// this once per message would otherwise recompute `anchorIndex(in:)`
    /// (an `O(n)` scan) once per message too, i.e. `O(n²)` over a thread;
    /// `SessionThreadColumn.messages(_:focused:)` computes the anchor once
    /// per render instead and calls the 5-arg overload directly.
    static func steps(
        forMessageAt index: Int,
        in messages: [ConversationMessageSummary],
        conversationId: Int,
        liveRun: LiveRun?
    ) -> [AgentStepSummary]? {
        steps(
            forMessageAt: index,
            in: messages,
            conversationId: conversationId,
            liveRun: liveRun,
            anchorIndex: anchorIndex(in: messages)
        )
    }

    /// Same precedence rule as the 4-arg overload above, but takes the
    /// thread's anchor index already computed — the version an
    /// once-per-thread render loop should call.
    static func steps(
        forMessageAt index: Int,
        in messages: [ConversationMessageSummary],
        conversationId: Int,
        liveRun: LiveRun?,
        anchorIndex: Int?
    ) -> [AgentStepSummary]? {
        let persisted = nonEmpty(messages[index].steps)
        let isAnchor = index == anchorIndex
        guard isAnchor, let liveRun, liveRun.conversationId == conversationId else {
            return persisted
        }
        if liveRun.isActivelyRunning {
            return nonEmpty(liveRun.steps)
        }
        return persisted ?? nonEmpty(liveRun.steps)
    }

    /// `[]` and `nil` are equivalent as "nothing to show" throughout this
    /// type — never a `0`-row collapsible block.
    private static func nonEmpty(_ steps: [AgentStepSummary]?) -> [AgentStepSummary]? {
        guard let steps, !steps.isEmpty else { return nil }
        return steps
    }
}

/// The live progress feed's step, expressed in the same `{type, detail}`
/// shape `AgentStepSummary`/the sidecar's persisted `ConversationStepRecord`
/// already use — what lets `SessionThreadColumn.liveRun(for:)` build a
/// `SessionStepLogResolver.LiveRun` (and `StepLog`) from either source
/// without a second table of steps.
private extension AgentProgressStep {
    var asStepSummary: AgentStepSummary {
        let type: String
        switch kind {
        case .thinking: type = "thinking"
        case .toolCall: type = "tool_call"
        case .toolResult: type = "tool_result"
        case .error: type = "error"
        }
        return AgentStepSummary(type: type, detail: detail)
    }
}

/// One row of a `StepLog`, normalised away from whichever of the two step
/// types it came from.
struct StepLogEntry {
    var label: String
    var detail: String
    var tint: Color

    init(step: AgentStepSummary) {
        self.init(type: step.type, detail: step.detail)
    }

    private init(type: String, detail: String) {
        switch type {
        case "tool_call":
            let call = StepLogEntry.parseToolCall(detail)
            label = call.name
            self.detail = call.arguments
            // Colour marks the calls that changed something. A run that only
            // read is a run you do not have to audit, and spending the Agent
            // tint on every row would stop saying which is which.
            tint = StepLogEntry.sideEffecting.contains(call.name)
                ? DS.Colour.agent
                : StepLogEntry.readOnlyTint
        case "error":
            label = OpenTypeL10n.text("错误", english: "error")
            self.detail = detail
            tint = DS.Colour.error
        case "tool_result":
            label = OpenTypeL10n.text("结果", english: "result")
            self.detail = detail
            tint = StepLogEntry.readOnlyTint
        case "done":
            label = OpenTypeL10n.text("完成", english: "done")
            self.detail = detail
            tint = StepLogEntry.readOnlyTint
        default:
            label = type
            self.detail = detail
            tint = StepLogEntry.readOnlyTint
        }
    }

    /// The four tools that can change something, from the handoff's tool
    /// catalogue (`sidecar/src/agent/coreTools.ts`), named without the
    /// `opentype__` prefix the parser has already stripped.
    private static let sideEffecting: Set<String> = ["bash", "python", "open_file", "remember_fact"]

    /// What a read-only step's tool column is set in — the handoff's
    /// `rgba(28,28,30,.45)`, one step lighter than the detail beside it.
    private static let readOnlyTint = DS.Colour.ink(0.45)

    /// Splits `Calling opentype__bash({"command":"…"})` into `bash` and the
    /// argument string.
    ///
    /// The sidecar emits tool calls as one prose-wrapped line
    /// (`loop.ts`), so the tool name and its arguments have to be recovered
    /// here to make the log a table. A line that does not match the shape
    /// falls through as its own label with no arguments rather than being
    /// dropped — an unparsed step is still a step that happened.
    static func parseToolCall(_ detail: String) -> (name: String, arguments: String) {
        var body = detail.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("Calling ") { body.removeFirst("Calling ".count) }

        guard let open = body.firstIndex(of: "(") else {
            return (StepLogEntry.shortName(String(body)), "")
        }
        let name = StepLogEntry.shortName(String(body[body.startIndex..<open]))
        var arguments = String(body[body.index(after: open)...])
        if arguments.hasSuffix(")") { arguments.removeLast() }
        return (name, arguments)
    }

    /// Drops our own `opentype__` prefix; an MCP server's prefix
    /// (`github__create_issue`) stays, because there it identifies which
    /// server the tool came from.
    private static func shortName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("opentype__")
            ? String(trimmed.dropFirst("opentype__".count))
            : trimmed
    }
}

// MARK: - List pieces

/// A running Agent task, as a whole card.
///
/// It gets a card because it is the only thing on this screen with time
/// pressure: everything else already happened and will still be there in a
/// minute. Current tool, progress, elapsed time and 停止 in one glance is what
/// a row of grey text could not do.
private struct SessionRunningCard: View {
    let run: AgentRunRecord
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(run.task)
                .font(DS.Text.body(.medium))
                // 1.5 line height at 13pt.
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Colour.agent)
                    Text(currentTool)
                        .font(DS.Text.mono())
                        .foregroundStyle(DS.Colour.ink(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SessionIndeterminateBar()

                HStack(spacing: 6) {
                    // A live counter, so "已用" stays true without any state of
                    // its own.
                    TimelineView(.periodic(from: run.dispatchedAt, by: 1)) { context in
                        Text(stepAndElapsed(now: context.date))
                            .font(DS.Text.mono(10))
                            .foregroundStyle(DS.Colour.ink(0.42))
                    }
                    Spacer(minLength: 0)
                    Button(action: onStop) {
                        Text(OpenTypeL10n.text("停止", english: "Stop"))
                            // 11/500, not the 11/600 group-label step: this is
                            // an action sitting beside a 10pt mono line, and
                            // semibold makes it the loudest thing in the card.
                            .font(DS.Text.size(11, .medium))
                            .foregroundStyle(DS.Colour.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DS.Colour.canvas, in: RoundedRectangle(cornerRadius: DS.Radius.block, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SessionRunningCardChrome())
    }

    private var currentTool: String {
        guard let last = run.steps.last(where: { $0.type == "tool_call" }) else {
            return OpenTypeL10n.text("准备中…", english: "starting…")
        }
        let call = StepLogEntry.parseToolCall(last.detail)
        return call.arguments.isEmpty ? call.name : "\(call.name) · \(call.arguments)"
    }

    private func stepAndElapsed(now: Date) -> String {
        // The handoff's "第 6 / ~9 步" needs a total the sidecar never sends,
        // so this shows the step reached and nothing it cannot know.
        let step = run.steps.filter { $0.type == "tool_call" }.count
        let seconds = max(now.timeIntervalSince(run.dispatchedAt), 0)
        return OpenTypeL10n.text(
            "第 \(max(step, 1)) 步 · 已用 \(SessionFormat.duration(seconds))",
            english: "Step \(max(step, 1)) · \(SessionFormat.duration(seconds)) elapsed"
        )
    }
}

/// The accent border and lifted shadow that mark a card as live.
private struct SessionRunningCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        DS.Shadow.running(
            content
                .background(DS.Colour.card, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(DS.Colour.accent.opacity(0.28), lineWidth: 0.75)
                )
        )
    }
}

/// One conversation in the list: a type dot, a title, a time, and a preview.
private struct SessionRow: View {
    let conversation: ConversationSummary
    let selected: Bool
    /// Interior rows carry the hairline; the first does not, or the card would
    /// have a line across its top edge.
    let firstInCard: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(SessionKindStyle.dot(conversation.sessionKind))
                        .frame(width: DS.Size.statusDot, height: DS.Size.statusDot)
                    Text(conversation.title)
                        .font(DS.Text.body(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(SessionFormat.time(millis: conversation.updatedAt))
                        .font(DS.Text.mono())
                        .foregroundStyle(DS.Colour.ink(0.35))
                }
                // The second line: the newest message, whoever wrote it.
                // Without it every row read as an unanswered question, which
                // is the opposite of what a session list is for. Absent for a
                // thread with no messages yet, and the row collapses to one
                // line rather than reserving empty space.
                if let preview = conversation.preview, !preview.isEmpty {
                    Text(preview)
                        .font(DS.Text.caption())
                        .foregroundStyle(DS.Colour.ink(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, DS.Space.rowH)
            .padding(.vertical, DS.Space.rowV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? DS.Colour.accent.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
            .modifier(SessionConditionalHairline(active: !firstInCard, edge: .top))
        }
        .buttonStyle(.plain)
    }
}

private struct SessionFilterChip: View {
    let filter: SessionFilter
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let kind = filter.kind {
                    Circle()
                        .fill(SessionKindStyle.dot(kind))
                        .frame(width: DS.Size.statusDot, height: DS.Size.statusDot)
                }
                Text(filter.title)
                    // 11.5, not the 12pt caption step. A chip 22pt tall with
                    // 10pt of gutter is sized around this half point, and
                    // rounding it up is what made the three chips crowd the
                    // 334pt column.
                    .font(DS.Text.size(11.5, selected ? .medium : .regular))
                    .foregroundStyle(selected ? DS.Colour.card : DS.Colour.ink(0.6))
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                // `labelColor` rather than a literal #1C1C1E: the selected chip
                // has to invert in dark mode, and a fixed near-black there is
                // white text on black in a white-on-dark window.
                selected ? AnyShapeStyle(Color(nsColor: .labelColor)) : AnyShapeStyle(DS.Colour.chipFill),
                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private extension SessionFilter {
    /// The kind whose dot the chip carries. 全部 has none.
    var kind: SessionKind? {
        switch self {
        case .all: return nil
        case .agent: return .agent
        case .ask: return .ask
        }
    }
}

// MARK: - Thread pieces

/// One turn. The user's is a bubble; the assistant's is not.
private struct SessionTurn: View {
    let message: ConversationMessageSummary
    let maxBubbleWidth: CGFloat

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        if isUser {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(message.content)
                    .font(DS.Text.body())
                    // 1.6 line height at 13pt.
                    .lineSpacing(5)
                    .foregroundStyle(DS.Colour.inkBase)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DS.Colour.control, in: SessionBubbleShape())
                    .frame(maxWidth: maxBubbleWidth, alignment: .trailing)
            }
        } else {
            // No bubble, no width cap: a long answer is a document.
            AssistantMarkdownView(markdown: message.content, fontSize: 13.5)
                // 1.75 line height at 13.5pt.
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The bubble's `14 14 4 14` corners.
///
/// Hand-rolled because `UnevenRoundedRectangle` is macOS 14 and this app
/// targets 13.
private struct SessionBubbleShape: Shape {
    var topLeading: CGFloat = DS.Radius.card
    var topTrailing: CGFloat = DS.Radius.card
    var bottomTrailing: CGFloat = 4
    var bottomLeading: CGFloat = DS.Radius.card

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeading, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topTrailing, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topTrailing),
            radius: topTrailing
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomTrailing))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - bottomTrailing, y: rect.maxY),
            radius: bottomTrailing
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomLeading, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeading),
            radius: bottomLeading
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeading))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + topLeading, y: rect.minY),
            radius: topLeading
        )
        path.closeSubpath()
        return path
    }
}

/// The 问答 / Agent tag in the thread header.
private struct SessionKindTag: View {
    let kind: SessionKind

    var body: some View {
        Text(kind.title)
            .font(DS.Text.groupLabel())
            .foregroundStyle(SessionKindStyle.tagText(kind))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                SessionKindStyle.tagFill(kind),
                in: RoundedRectangle(cornerRadius: DS.Radius.tag, style: .continuous)
            )
            .fixedSize()
    }
}

/// "The answer is on its way", inside the thread rather than only on the
/// floating panel — the panel is transient, and a thread the user opened on
/// purpose should say what it is doing.
private struct SessionWorkingRow: View {
    var body: some View {
        HStack(spacing: 7) {
            SessionPulseDot(period: 1.2)
            Text(OpenTypeL10n.text("正在检索…", english: "Working…"))
                .font(DS.Text.mono())
                .foregroundStyle(DS.Colour.ink(0.4))
        }
    }
}

private struct SessionComposerButton: View {
    let symbol: String
    let filled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: SessionMetrics.glyph))
                .foregroundStyle(filled ? AnyShapeStyle(Color.white) : AnyShapeStyle(DS.Colour.accent))
                .frame(width: 30, height: 30)
                .modifier(SessionButtonChrome(filled: filled, radius: DS.Radius.nested))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Shared small parts

private struct SessionIconButton: View {
    let symbol: String
    let filled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: SessionMetrics.glyph))
                .foregroundStyle(filled ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .frame(width: 26, height: 26)
                .modifier(SessionButtonChrome(filled: filled, radius: DS.Radius.smallControl))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Either an accent-filled button with its coloured lift, or a white one with a
/// `.09` edge and the neutral one.
///
/// `.09` rather than the card edge's `.07`: a 26pt white square on a `#F5F5F3`
/// page has almost no value contrast to sit on, so the handoff spends two
/// hundredths of alpha on the outline instead.
private struct SessionButtonChrome: ViewModifier {
    let filled: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        if filled {
            DS.Shadow.accentControl(
                content
                    .background(DS.Colour.accent, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
        } else {
            DS.Shadow.control(
                content
                    .background(DS.Colour.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(DS.Colour.controlBorder, lineWidth: 0.75)
                    )
            )
        }
    }
}

/// The same white pill as an unfilled `SessionButtonChrome`, for the header
/// controls that are a field rather than a button.
private struct SessionHeaderControlChrome: ViewModifier {
    func body(content: Content) -> some View {
        DS.Shadow.control(
            content
                .background(
                    DS.Colour.card,
                    in: RoundedRectangle(cornerRadius: DS.Radius.smallControl, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.smallControl, style: .continuous)
                        .strokeBorder(DS.Colour.controlBorder, lineWidth: 0.75)
                )
        )
    }
}

private struct SessionGroupLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.Text.groupLabel())
            .tracking(DS.Tracking.groupLabel)
            // .42, the α the handoff sets on every group label in the app.
            // `.tertiary` is ≈ .26 and reads as disabled at 11pt.
            .foregroundStyle(DS.Colour.ink(0.42))
    }
}

/// The breathing dot that marks something as live.
///
/// Two periods, both from the handoff: 1.4s for the 进行中 group label, 1.2s for
/// the 正在检索 row in a thread. The faster one is next to a line of text that
/// is itself waiting, and matching them would have made the two read as one
/// object blinking together.
private struct SessionPulseDot: View {
    var period: Double = 1.4

    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(DS.Colour.accent)
            .frame(width: DS.Size.statusDot, height: DS.Size.statusDot)
            .opacity(pulsing ? 0.35 : 1)
            .scaleEffect(pulsing ? 0.82 : 1)
            .animation(.easeInOut(duration: period).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

/// A 2pt bar that shows motion without claiming a percentage.
///
/// The handoff draws a determinate fill, but `/agent/run` never reports a step
/// total — the loop stops when the model stops calling tools. A bar at 58%
/// would be a number we made up; a moving segment says "still going", which is
/// the whole of what is actually known.
private struct SessionIndeterminateBar: View {
    @State private var shifted = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Capsule()
                .fill(DS.Colour.accent)
                .frame(width: max(width * 0.32, 1))
                .offset(x: shifted ? width * 0.68 : 0)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: shifted)
        }
        .frame(height: 2)
        .background(DS.Colour.border)
        .clipShape(Capsule())
        .onAppear { shifted = true }
    }
}

/// The 52pt strip a column starts with, at gutters this screen chooses.
///
/// `ColumnHeader` bakes in the page gutter (24 wide / 14 narrow). Both of this
/// screen's headers want something else — 16/16 for the list, 20/20 then 10/14
/// for the thread — and a header that does not share a left edge with the cards
/// under it is the one misalignment a reader notices without being able to say
/// why. Same height, so headers still line up across all three columns.
private struct SessionColumnHeader<Content: View>: View {
    var leading: CGFloat
    var trailing: CGFloat
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: spacing) {
            content()
        }
        .padding(.leading, leading)
        .padding(.trailing, trailing)
        .frame(height: DS.Size.headerHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A 0.75pt line at the *border* weight rather than the hairline one.
///
/// The design uses two: `border` (0.07) where one region ends and another
/// begins — the thread header, the composer — and `hairline` (0.06) between
/// rows inside a single card. `dsHairline` is the second; this is the first.
private struct SessionEdgeBorder: ViewModifier {
    let edge: Edge

    func body(content: Content) -> some View {
        content.overlay(alignment: edge == .top ? .top : .bottom) {
            Rectangle()
                .fill(DS.Colour.border)
                .frame(height: 0.75)
        }
    }
}

/// `dsHairline` only when a condition holds — SwiftUI has no conditional
/// modifier, and branching on the view itself would give the two branches
/// different identities and re-create their state.
private struct SessionConditionalHairline: ViewModifier {
    let active: Bool
    let edge: Edge

    func body(content: Content) -> some View {
        content.overlay(alignment: edge == .top ? .top : .bottom) {
            Rectangle()
                .fill(active ? DS.Colour.hairline : Color.clear)
                .frame(height: 0.75)
        }
    }
}

// MARK: - Values

private enum SessionMetrics {
    /// The glyph inside a 26 or 30pt button. One value because the handoff uses
    /// one (`font-size:16px` for 搜索 / 新对话 / 口述 / 发送 alike) — the button
    /// grows, the icon in it does not.
    static let glyph: CGFloat = 16
}

private enum SessionKindStyle {
    static func dot(_ kind: SessionKind?) -> Color {
        switch kind {
        case .agent: return DS.Colour.agent
        case .ask: return DS.Colour.accent
        case nil: return Color.secondary
        }
    }

    /// Both at 11%. The README says 12 for the Agent tag; §01's markup says 11
    /// for both, and the markup is what ships.
    static func tagFill(_ kind: SessionKind) -> Color {
        switch kind {
        case .agent: return DS.Colour.agent.opacity(0.11)
        case .ask: return DS.Colour.accent.opacity(0.11)
        }
    }

    /// The 问答 tag darkens its text rather than reusing the accent: 11% accent
    /// behind #0D73FA is a tag you have to look at twice.
    static func tagText(_ kind: SessionKind) -> Color {
        switch kind {
        case .agent: return DS.Colour.agent
        case .ask: return DS.Colour.askTag
        }
    }
}

private enum SessionFormat {
    static func time(millis: Int) -> String {
        timeFormatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }

    /// `42s` / `2m 04s`. Seconds alone stop being readable somewhere around a
    /// minute and a half.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        guard total >= 60 else { return "\(total)s" }
        return String(format: "%dm %02ds", total / 60, total % 60)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = OpenTypeL10n.locale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// One 今天 / 昨天 / dated group of the list.
private struct SessionDay: Identifiable {
    let id: Date
    let title: String
    let conversations: [ConversationSummary]

    /// Buckets an already-sorted list by calendar day, preserving order.
    ///
    /// Grouping happens here rather than in `SessionList` because it is a
    /// rendering concern with a calendar and a locale in it — the merge and the
    /// filter are pure list operations, and mixing "what is in the list" with
    /// "how today is spelled" is how one of them ends up needing the other's
    /// tests.
    static func grouped(_ conversations: [ConversationSummary]) -> [SessionDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = OpenTypeL10n.locale

        var order: [Date] = []
        var buckets: [Date: [ConversationSummary]] = [:]
        for conversation in conversations {
            let date = Date(timeIntervalSince1970: Double(conversation.updatedAt) / 1000)
            let day = calendar.startOfDay(for: date)
            if buckets[day] == nil {
                buckets[day] = []
                order.append(day)
            }
            buckets[day]?.append(conversation)
        }

        return order.map { day in
            SessionDay(id: day, title: title(for: day, calendar: calendar), conversations: buckets[day] ?? [])
        }
    }

    private static func title(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) {
            return OpenTypeL10n.text("今天", english: "Today")
        }
        if calendar.isDateInYesterday(day) {
            return OpenTypeL10n.text("昨天", english: "Yesterday")
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: Date())
        let formatter = sameYear ? monthDayFormatter : fullDateFormatter
        return formatter.string(from: day)
    }

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = OpenTypeL10n.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = OpenTypeL10n.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter
    }()
}
