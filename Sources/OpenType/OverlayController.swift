import AppKit
import SwiftUI

@MainActor
private final class OverlayPresentation: ObservableObject {
    @Published var state: ProcessingState = .idle
    @Published var mode: InputMode = InputMode.visibleModes[0]
    @Published var liveTranscript = ""
    @Published var audioLevel = 0.0
    /// The unified ask/agent surface. `.hidden` hands the panel back to the
    /// legacy transcribe HUD / toast content below.
    @Published var surface: VoiceSurfaceState = .hidden
    /// Non-nil while the toast on screen *is* the correction-window affordance
    /// (P0-3) rather than a plain success toast.
    @Published var correctionHint: CorrectionHint?
    /// The §H escalation the current `surface` offers, or `nil` when it must
    /// not be drawn — computed by whichever caller has the panel state
    /// (`AppModel.presentVoiceSurface()`) and stored here alongside `surface`
    /// rather than re-derived from it, since `ResultCard` itself carries no
    /// `conversationId` (see `AssistantEscalation`'s own doc comment).
    @Published var escalation: AssistantEscalation?
    /// Non-nil while the pre-dispatch confirmation window is open (P1-6). It
    /// preempts everything below — surface included — because for its 1.5
    /// seconds it is the only thing on this panel worth reading.
    @Published var pendingDispatch: PendingDispatch?
    /// The `m:ss` readout on the listening pill (P2-10), non-nil for exactly as
    /// long as a recording is being timed. `AppModel`'s recording tick is the
    /// only writer — the controller never reads a clock of its own.
    @Published var elapsedText: String?
    /// What the listening pill's trailing hint says, and whether tapping it
    /// ends the recording — pushed by `apply(...)` on every recording, and
    /// read together by `listeningContent` so the two can never disagree
    /// (see `RecordingClock.StopAffordance`'s doc comment).
    @Published var stopAffordance = RecordingClock.stopAffordance(startedByClick: false)
    /// The speech model's load state, so a transcription queued behind the
    /// first-launch download can say what it is waiting for.
    @Published var whisperStatus: WhisperStatusSnapshot?
    /// The two-minute warning's sentence, shown for a few seconds in place of
    /// the caption. Separate from the flag below because the sentence is
    /// transient and the fact that it fired is not.
    @Published var recordingWarning: String?
    /// Sticks for the rest of the recording once the warning has fired, so the
    /// elapsed readout stays tinted after the sentence has gone: the user is
    /// still in the stretch that ends by itself.
    @Published var pastWarningThreshold = false

    // MARK: - Redesign additions (2026-08-14 handoff §04)

    /// When the current processing/working episode began, so the pill can say
    /// 「…· 42s」. Timed here rather than pushed because it is the panel's own
    /// question — how long has the user been looking at this — and the states
    /// it spans (`.processing` → `.working`) are exactly the ones this
    /// controller already sees the boundaries of.
    @Published var workingStartedAt: Date?
    /// How many distinct agent steps have arrived during that episode. The
    /// wire gives us the *last* step's text, not an index, so 「第 6 步」 is
    /// counted from the changes we observe. Total-step estimates do not exist
    /// upstream, so the readout deliberately shows the current number alone
    /// rather than inventing a denominator.
    @Published var stepCount = 0
    /// The finished episode's duration, frozen at the moment the card
    /// appeared. A card that kept counting would be timing the user reading
    /// it, not the run.
    @Published var finishedElapsed: TimeInterval?
    /// The last live caption of the recording that led into this episode —
    /// what the user said, kept so the working pill and the result card can
    /// show the task rather than a generic 「请稍候…」.
    @Published var lastCaption = ""
    /// Where the last delivery landed, for 「已写入 <App>」. Set by `AppModel`
    /// alongside `correctionWindowArmed`; `nil` falls back to naming the field
    /// rather than the app.
    @Published var deliveryTargetApp: String?
    /// What was delivered, shown under that headline.
    @Published var deliveredText: String?
    /// Whether the installed hotkey preset actually supports Tab-to-switch
    /// (`HotKeyPreset.modeSwitchHint != nil`). The Space-chord presets do not,
    /// and a pill that advertises a key that does nothing is worse than one
    /// that stays quiet.
    @Published var modeSwitchHintAvailable = true

    /// Mirrors `AppConfiguration.interfaceLanguageToken` (§F). This panel is
    /// not `@ObservedObject` on `AppConfiguration` the way `RootView`/
    /// `MenuBarPopoverView` are — `AppModel.changeInterfaceLanguage` pushes it
    /// explicitly — so `.id(languageToken)` on `OverlayView.body` is the only
    /// way this panel learns a live language switch happened while it wasn't
    /// necessarily on screen at the time.
    @Published var languageToken = 0

    // MARK: - The learning loop, made visible (2026-08-15 §D)

    /// What the entity dictionary rewrote in the text this toast is about
    /// (D-1), in text order. Empty for a delivery it left alone, which is the
    /// common case and shows nothing at all.
    @Published var aliasReplacements: [AliasReplacement] = []
    /// Whether the list under 「自动修正 N 处」 is open. Lives here rather than as
    /// the view's `@State` because the panel is fixed-height: the controller has
    /// to resize it when the list opens, and it cannot see a `@State` toggle.
    @Published var aliasReplacementsExpanded = false
    /// One sentence about what the loop just did — 「已记住：呸泡 → PayPal」
    /// (D-2), or how an undo turned out (D-1).
    @Published var learningNote: LearningNote?

    /// Whether the note is the panel's whole content right now, rather than a
    /// row on a delivery toast. Set only by `presentNote()`.
    @Published var learningNoteOwnsPanel = false

    /// What the delivery toast shows under its headline: what `AppModel` says
    /// it delivered, or failing that the caption of the recording that
    /// produced it. Derived from two `@Published` values, so the layout
    /// decision (`VoiceSurfacePanelMetrics.delivery`) and the view can read
    /// the same answer instead of each deciding "is there text" separately.
    var deliveryBody: String {
        let text = deliveredText ?? lastCaption
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The visible half of an armed correction window.
    struct CorrectionHint: Equatable {
        let text: String
        let seconds: TimeInterval
        /// Identity for the progress bar: a re-armed window is a *new* bar
        /// that starts full again, not the old one continuing.
        let startedAt: Date
    }

    /// The visible half of a pre-dispatch confirmation (P1-6): the transcript
    /// about to be handed to `/agent/run`, and how long is left to take it
    /// back.
    struct PendingDispatch: Equatable {
        let transcript: String
        let seconds: TimeInterval
        /// Identity for the countdown bar, same as `CorrectionHint.startedAt`.
        let startedAt: Date
    }
}

/// One sentence the voice surface shows about the learning loop (§D): 「已记
/// 住：呸泡 → PayPal」 after a correction taught the dictionary something, or how
/// an 「撤销并删除该词条」 click turned out.
///
/// File-scope rather than nested in the private presentation object because
/// `AppModel` builds these — it owns the decisions (`LearnedTermNotice`,
/// `AliasUndo`) and the controller only draws them, the same non-self-deciding
/// contract every other thing on this panel has.
struct LearningNote: Equatable {
    let text: String
    /// The canonical spelling of the term to reveal on the 记忆 page, or `nil`
    /// for a note with nowhere to go — an undo's outcome, whose term has just
    /// been deleted.
    let term: String?
}

/// How `OverlayController.show(...)` should treat the HUD panel for a given
/// `ProcessingState`, factored out of the inline `switch` so the per-state
/// timing decision is pure and unit-testable (see `OverlayHideBehaviorTests`).
enum OverlayHideBehavior: Equatable {
    /// Hide the panel right away (e.g. `.idle` — there is nothing to show).
    case hideImmediately
    /// Leave it up for `after` seconds, then hide (transient toast states).
    case scheduleHide(after: TimeInterval)
    /// Leave it up for `after` seconds carrying the correction-window
    /// affordance (`CorrectionWindow.hintText` plus a bar that empties as the
    /// window does) instead of the bare success copy — P0-3. Distinct from
    /// `.scheduleHide` because what changes is *what the toast says*, not only
    /// how long it stays: a longer-lived 「完成」 would teach nobody that the
    /// hotkey has temporarily changed meaning.
    case scheduleHideWithCorrectionHint(after: TimeInterval)
    /// Keep it on screen with no scheduled hide (active in-flight states).
    case keepVisible
}

extension OverlayHideBehavior {
    /// How long the panel stays up, for the two cases that schedule a hide.
    ///
    /// Exists so that consumers which only care about the *timing* ask once
    /// here rather than pattern-matching a single case and silently ignoring
    /// the other — the trap the spec calls out for `presentToast`, where an
    /// unhandled case does not fail to compile, it just stops restoring the
    /// preempted voice surface forever.
    var scheduledHideDelay: TimeInterval? {
        switch self {
        case .scheduleHide(let seconds),
             .scheduleHideWithCorrectionHint(let seconds):
            return seconds
        case .hideImmediately, .keepVisible:
            return nil
        }
    }
}

/// The panel's two widths, and the heights that go with them.
///
/// The redesign's single biggest change to this surface: **420 or 640, and
/// nothing else.** The panel used to be 300 / 388 / 392 / 460 / 480 / 620
/// depending on what it happened to be showing, so every morph slid it
/// sideways under the user's eyes — five states that are one panel read as
/// five panels taking turns. Everything except the result card is 420; the
/// card is 640×520 (handoff §04).
///
/// This is the **only** table. `VoiceSurfacePanelLayout.size(for:)`
/// (`Models.swift`) forwards to it rather than carrying its own numbers —
/// there used to be two copies, each locally reasonable, and they drifting
/// apart one state at a time is how the panel ended up with six widths.
/// Positioning still comes from `VoiceSurfacePanelLayout.frame` — the
/// bottom-anchored geometry is unchanged, and that is what keeps the morph
/// reading as growth rather than as a new window.
enum VoiceSurfacePanelMetrics {
    /// Every pre-result state. One size for all of them, so the panel holds
    /// still from the first word until it becomes the card.
    static let pill = NSSize(width: 420, height: 132)
    static let card = NSSize(width: 640, height: 520)
    /// Toasts with a single headline row (mode changed, failed, cancelled).
    static let compactToast = NSSize(width: 420, height: 66)
    static let pendingDispatch = NSSize(width: 420, height: 96)

    /// A delivery toast: the headline, optionally what was delivered, the
    /// learning loop's own rows (§D), and — while a correction window is open —
    /// the merged countdown/hint row.
    ///
    /// Sized from what it will actually contain rather than to a worst case,
    /// because the panel is fixed-height and an absent row would otherwise
    /// leave a strip of blank material under the text.
    static func delivery(
        hasText: Bool,
        hasHint: Bool,
        hasNote: Bool = false,
        replacementCount: Int = 0,
        replacementsExpanded: Bool = false
    ) -> NSSize {
        var height: CGFloat = 66
        if hasText { height += 42 }
        if hasNote { height += 26 }
        if replacementCount > 0 { height += 26 }
        if replacementsExpanded {
            // Capped at the same six rows the question card caps its options
            // at: past that the toast is taller than the thing it is describing,
            // and a delivery that hit seven aliases has a dictionary problem the
            // 记忆 page is the place to look at.
            height += CGFloat(min(replacementCount, maxExpandedReplacements)) * 30
        }
        if hasHint { height += 33 }
        return NSSize(width: 420, height: height)
    }

    /// How many rewrite rows the expanded list draws before it stops growing.
    static let maxExpandedReplacements = 6

    /// A standalone learning-loop note (§D), wide enough for one sentence that
    /// may wrap once.
    static let note = NSSize(width: 420, height: 78)

    /// The question card grows with its options and stays 420 wide. A prompt,
    /// not a document — it never reaches the card's 640.
    static func asking(optionCount: Int) -> NSSize {
        // Header + question + the mic/answer row + padding, plus one 36pt row
        // per option inside a bordered list.
        let base: CGFloat = 160
        let rows = CGFloat(min(max(optionCount, 0), 6)) * 36
        return NSSize(width: 420, height: base + rows)
    }

    static func size(for state: VoiceSurfaceState) -> NSSize {
        switch state {
        case .hidden:
            return .zero
        case .listening, .processing, .working:
            return pill
        case .asking(let detail):
            return asking(optionCount: detail.question.options?.count ?? 0)
        case .result, .failed:
            return card
        }
    }
}

/// The app's single floating bottom-center panel. It plays two roles:
///
/// 1. The legacy transient HUD — transcribe mode's live-caption pill and every
///    mode's toast states (`show(state:mode:)`), unchanged.
/// 2. The **unified voice surface** (`apply(_:state:mode:)`): the whole
///    ask/agent lifecycle, from the same pill through breathing-dots
///    "processing"/"working" to a result card the panel *morphs into* by
///    animating its frame upward from a fixed bottom edge (spec:
///    `docs/superpowers/specs/2026-08-13-hud-morph-result-surface-design.md` §1).
///    This replaced both the center-screen Ask popup (`AskPanelController`) and
///    the top-right Agent progress panel (`AgentProgressPanelController`);
///    neither exists anymore.
///
/// `AppModel` owns all the state: it reduces its own
/// `(mode, ProcessingState, askPanelState, agentPanelState)` into a
/// `VoiceSurfaceState` and pushes it here. The controller decides nothing
/// except geometry and animation, and reports user intent back through
/// `onRequestDismiss` / `onCopyResult` / `onOpenMainWindow` rather than
/// mutating anything itself (same non-self-closing contract the old panels
/// had, which is what keeps show/hide from feedback-looping).
@MainActor
final class OverlayController {
    private let presentation = OverlayPresentation()
    private var panel: NSPanel?
    private var draggingPanel = false
    private let positionPreference = "OpenType.overlayPosition.v1"
    private var dismissWorkItem: DispatchWorkItem?
    /// The surface state currently on screen (or, while a transient toast has
    /// preempted it, the one that comes back when the toast is done). While
    /// this is non-`.hidden` the surface owns the panel.
    private var surfaceState: VoiceSurfaceState = .hidden
    /// The last `(state, mode)` pushed *with* a surface, so a toast that
    /// preempted the surface can restore it with the right content. Only
    /// `apply(...)`/`applyWithToast(...)` update these: a bare `show(...)`
    /// toast carries a mode of its own (the newly selected one) that must not
    /// stick to the surface underneath it.
    private var lastState: ProcessingState = .idle
    private var lastMode: InputMode = InputMode.visibleModes[0]
    /// Non-nil while a transient toast has preempted the unified surface: the
    /// work item that puts the surface back when the toast's time is up. See
    /// `presentToast(state:mode:)`.
    private var toastOverride: DispatchWorkItem?
    /// What the legacy path last put on the panel, and only for as long as it
    /// is actually up. A live agent run re-applies the surface on every ~0.7s
    /// poll tick, so an unchanged `.hidden` push is common — replaying the
    /// legacy path for it would restart the visible toast's dismiss timer.
    /// Cleared the moment that content leaves the panel, so a genuinely new
    /// toast still shows even when it is identical to one that already came
    /// and went.
    private var legacyOnScreen: (state: ProcessingState, mode: InputMode)?
    private var clickOutsideMonitor: Any?
    /// The Esc watchers installed for the length of a pre-dispatch
    /// confirmation (P1-6), and only for that length.
    private var pendingDispatchKeyMonitors: [Any] = []
    /// The digit watchers installed for the length of an agent question, and
    /// only for that length — see `installQuestionKeyMonitors(for:)`.
    private var questionKeyMonitors: [Any] = []
    /// Takes the two-minute warning's sentence back off the pill (P2-10).
    private var recordingWarningWorkItem: DispatchWorkItem?
    /// How long that sentence stays up.
    private let recordingWarningSeconds: TimeInterval = 4.5
    /// The agent step whose text the pill is currently showing, so a poll tick
    /// that repeats it does not count as a new step.
    private var lastStepSignature: String?

    /// Whether a post-delivery correction window is open right now (P0-3).
    /// `AppModel` sets it *before* pushing the delivery state, since it is
    /// what turns that push's success toast into the window's affordance.
    /// A plain flag rather than the `CorrectionWindow.State` itself: the
    /// controller decides presentation, never policy.
    var correctionWindowArmed = false

    /// Where the last delivery landed (`AppModel.lastApplication`), so the
    /// toast can say 「已写入 Notes」 instead of 「已复制」. Set before pushing
    /// the delivery state, same contract as `correctionWindowArmed`.
    var deliveryTargetApp: String? {
        get { presentation.deliveryTargetApp }
        set { presentation.deliveryTargetApp = newValue }
    }

    /// What was delivered, shown beneath that headline.
    var deliveredText: String? {
        get { presentation.deliveredText }
        set { presentation.deliveredText = newValue }
    }

    /// Whether the installed hotkey preset supports Tab-to-switch. Drives the
    /// listening pill's bottom row; see the presentation property.
    var modeSwitchHintAvailable: Bool {
        get { presentation.modeSwitchHintAvailable }
        set { presentation.modeSwitchHintAvailable = newValue }
    }

    /// §F live language switch — see `OverlayPresentation.languageToken`.
    var languageToken: Int {
        get { presentation.languageToken }
        set { presentation.languageToken = newValue }
    }

    /// What the dictionary rewrote in the delivery this toast is about (D-1).
    /// Set alongside `correctionWindowArmed`, and for the same reason: the undo
    /// it offers is live for exactly as long as that window is.
    var aliasReplacements: [AliasReplacement] {
        get { presentation.aliasReplacements }
        set {
            let previous = presentation.aliasReplacements
            presentation.aliasReplacements = newValue
            // A *new* report opens collapsed: the summary line is what a
            // delivery that went right needs, and a list inherited open from the
            // previous delivery would be a panel that opens itself. A list that
            // only lost rows is the same list mid-undo, and collapsing it under
            // the user's pointer after one click would make undoing a second
            // rewrite cost an extra one.
            let shrank = !newValue.isEmpty
                && newValue.allSatisfy { previous.contains($0) }
            if !shrank {
                presentation.aliasReplacementsExpanded = false
            }
        }
    }

    /// The 「已记住」 / undo-outcome sentence riding under the delivery headline.
    /// Plain property, so a delivery push that follows it renders it as part of
    /// the same toast rather than replacing it — see `showLearningNote(_:)` for
    /// the case where no such push is coming.
    var learningNote: LearningNote? {
        get { presentation.learningNote }
        set { presentation.learningNote = newValue }
    }

    /// A note with nothing pushing a toast behind it — the outcome of an undo,
    /// which happens while the panel may already be on its way out.
    ///
    /// Refreshes the delivery toast in place when one is up (it is the toast
    /// this note is about, and preempting it would tear down the correction
    /// window's own affordance), and otherwise takes the panel for a couple of
    /// seconds on its own.
    func showLearningNote(_ note: LearningNote) {
        presentation.learningNote = note
        if let legacyOnScreen,
           legacyOnScreen.state == .success || legacyOnScreen.state == .copied {
            resizeLegacyPanel(for: legacyOnScreen.state)
            return
        }
        presentNote()
    }

    /// The disclosure control on 「自动修正 N 处」. Handled here rather than as
    /// view state because opening the list changes the panel's height, and the
    /// panel's height is the controller's to set.
    func toggleAliasReplacements() {
        presentation.aliasReplacementsExpanded.toggle()
        guard let legacyOnScreen else { return }
        resizeLegacyPanel(for: legacyOnScreen.state)
    }

    /// Escape, the 关闭 button, or a click outside a finished card.
    var onRequestDismiss: (() -> Void)?
    /// The 复制 button, with the card's Markdown body.
    var onCopyResult: ((String) -> Void)?
    /// The 打开主窗口 button.
    var onOpenMainWindow: (() -> Void)?
    /// The 停止 control shown while a stoppable agent run is on screen (T1).
    var onStopAgentRun: (() -> Void)?
    /// The user's answer to an agent question (T5): run id plus the answer.
    var onAnswerAgentQuestion: ((String, AgentQuestionAnswerItem) -> Void)?
    /// 「撤销并删除该词条」 on one rewrite row (D-1). Reported rather than acted
    /// on, same contract as everything else here: whether the delivered text may
    /// still be touched is `AliasUndo`'s decision and `AppModel`'s to make.
    var onUndoAliasReplacement: ((AliasReplacement) -> Void)?
    /// A click on 「已记住：呸泡 → PayPal」 (D-2), carrying the canonical spelling
    /// the 记忆 page should reveal.
    var onOpenLearnedTerm: ((String) -> Void)?
    /// Esc while the pre-dispatch confirmation is on screen (P1-6). Reported
    /// rather than acted on, same non-self-closing contract as everything
    /// above: `AppModel` owns the window and decides what a keypress at this
    /// instant means (`DispatchConfirmation.decision`).
    var onCancelPendingDispatch: (() -> Void)?

    /// A follow-up typed (or picked from the card's action row) while a result
    /// card is on screen: **the card's way out of being a dead end.**
    ///
    /// Before this, following up on an answer you were looking at meant
    /// dismissing the card, opening the main window, finding the thread and
    /// speaking again. The caller is expected to dispatch the text against the
    /// card's own `conversationId` (`VoiceFollowUp.conversationId`) and push
    /// the surface back to `.working`, so the follow-up continues the
    /// conversation instead of starting a parallel one.
    var onFollowUp: ((String) -> Void)?
    /// The card composer's mic button — the same intent as holding the hotkey,
    /// reported rather than performed because starting a recording is
    /// `AppModel`'s job.
    var onFollowUpByVoice: (() -> Void)?
    /// 「交给助理去做」 (§H): the ask result card's one-way exit into the full
    /// toolset. Reported rather than performed, same non-self-closing
    /// contract as everything above — `AppModel` owns the dispatch
    /// (`escalateToAgent(_:)`), this controller only ever forwards the
    /// `AssistantEscalation` the card was built to offer.
    var onEscalate: ((AssistantEscalation) -> Void)?

    private lazy var hostingView = OverlayHostingView(
        rootView: OverlayView(
            presentation: presentation,
            onClose: { [weak self] in self?.onRequestDismiss?() },
            onCopy: { [weak self] text in self?.onCopyResult?(text) },
            onOpenMainWindow: { [weak self] in self?.onOpenMainWindow?() },
            onStop: { [weak self] in self?.onStopAgentRun?() },
            onAnswer: { [weak self] runId, answer in
                self?.onAnswerAgentQuestion?(runId, answer)
            },
            onFollowUp: { [weak self] text in self?.onFollowUp?(text) },
            onFollowUpByVoice: { [weak self] in self?.onFollowUpByVoice?() },
            onToggleReplacements: { [weak self] in self?.toggleAliasReplacements() },
            onUndoReplacement: { [weak self] replacement in
                self?.onUndoAliasReplacement?(replacement)
            },
            onOpenLearnedTerm: { [weak self] term in self?.onOpenLearnedTerm?(term) },
            onEscalate: { [weak self] escalation in self?.onEscalate?(escalation) }
        )
    )

    /// Legacy transient HUD for a state that does not itself change the
    /// surface — today only the mode-changed toast. One window, two owners:
    /// rather than being swallowed while the surface owns the panel, the
    /// toast *preempts* it for its usual duration and the surface comes back
    /// afterwards (`presentToast`).
    func show(state: ProcessingState, mode: InputMode) {
        presentToast(state: state, mode: mode)
    }

    /// Unified voice-surface entry point: the single call `AppModel` makes
    /// after anything that could change what the surface should look like.
    /// A `.hidden` surface falls through to the legacy HUD for `state`, so
    /// transcribe keeps behaving exactly as before.
    ///
    /// - Parameter startedByClick: whether the recording behind this push (if
    ///   any) began from a UI tap rather than the hotkey — forwarded straight
    ///   into `RecordingClock.stopAffordance(startedByClick:)` below. Harmless
    ///   to set even when `state != .listening`: the affordance is pure and
    ///   the listening pill is the only reader of `presentation.stopAffordance`.
    func apply(
        _ surface: VoiceSurfaceState,
        state: ProcessingState,
        mode: InputMode,
        escalation: AssistantEscalation? = nil,
        startedByClick: Bool = false
    ) {
        let previous = surfaceState
        let previousProcessing = presentation.state
        surfaceState = surface
        lastState = state
        lastMode = mode
        trackProgress(from: previous, to: surface)

        // A new recording starts a new thing to say. Keyed on the processing
        // state rather than the surface because transcribe never enters the
        // surface at all, and its delivery toast is the main reader of this —
        // a recording that produces no live caption (captions off, or silence)
        // must not show the previous one's words as what it just delivered.
        if state == .listening, previousProcessing != .listening {
            presentation.lastCaption = ""
            presentation.deliveredText = nil
            // The learning loop's rows belong to the delivery that produced
            // them (§D). A new recording is a new subject, and an undo offer
            // for the previous one would act on text that is about to be
            // superseded.
            presentation.aliasReplacements = []
            presentation.aliasReplacementsExpanded = false
            presentation.learningNote = nil
        }

        // A new recording is a fresh, user-initiated action: it always wins
        // over a toast still sitting on the panel.
        if state == .listening { cancelToastOverride() }

        // A transient toast owns the panel right now and restores the surface
        // — as it stands *then* — itself, so this push is bookkeeping only.
        guard toastOverride == nil else { return }

        // The legacy path is already showing exactly this: replaying it would
        // restart the toast's dismiss timer on every poll tick.
        if surface == .hidden,
           previous == .hidden,
           let legacyOnScreen,
           legacyOnScreen.state == state,
           legacyOnScreen.mode == mode {
            return
        }

        presentation.mode = mode
        presentation.state = state
        presentation.stopAffordance = RecordingClock.stopAffordance(startedByClick: startedByClick)

        guard surface != .hidden else {
            presentation.surface = .hidden
            presentation.escalation = nil
            presentLegacy(state: state, mode: mode)
            return
        }

        dismissWorkItem?.cancel()
        if surface != .listening {
            presentation.liveTranscript = ""
            presentation.audioLevel = 0
        }
        presentation.surface = surface
        presentation.escalation = escalation
        presentSurface(surface, grewFrom: previous)
    }

    /// `AppModel.fail(_:)`'s entry point: push the freshly-reduced `surface`
    /// **and** show `state`'s failure toast *over* it. A pipeline failure that
    /// lands while a previous run still owns the panel (a result card the user
    /// hasn't dismissed, an agent still ticking) must neither be swallowed by
    /// that surface — the user would get no feedback at all that their
    /// recording failed — nor tear it down, since the run it belongs to is
    /// still going. So the toast preempts the surface for its usual duration
    /// and the surface comes back when it expires.
    func applyWithToast(
        _ surface: VoiceSurfaceState,
        state: ProcessingState,
        mode: InputMode
    ) {
        trackProgress(from: surfaceState, to: surface)
        surfaceState = surface
        lastState = state
        lastMode = mode
        presentToast(state: state, mode: mode)
    }

    /// Keeps the pill's 「第 N 步 · 42s」 and the card's frozen duration in step
    /// with the surface, since neither number exists on the wire.
    ///
    /// An *episode* is one uninterrupted stretch of processing/working. It
    /// starts when the surface first enters one of those states and ends when
    /// it leaves them, which is also the moment the card's elapsed is frozen —
    /// a card that kept counting would be timing how long the user takes to
    /// read it.
    private func trackProgress(
        from previous: VoiceSurfaceState,
        to surface: VoiceSurfaceState
    ) {
        let wasBusy = previous.isBusyEpisode
        let isBusy = surface.isBusyEpisode

        if isBusy, !wasBusy {
            presentation.workingStartedAt = Date()
            presentation.stepCount = 0
            presentation.finishedElapsed = nil
            lastStepSignature = nil
        }

        if case .working(let detail) = surface,
           let step = detail.currentStep,
           step != lastStepSignature {
            lastStepSignature = step
            presentation.stepCount += 1
        }

        switch surface {
        case .result, .failed:
            if let started = presentation.workingStartedAt {
                presentation.finishedElapsed = Date().timeIntervalSince(started)
                presentation.workingStartedAt = nil
            }
        case .listening:
            // A new recording is a new task: the finished run's duration is no
            // longer what this panel is about. (The caption is cleared by
            // `apply`, which sees the processing state transcribe never leaves
            // the surface for.)
            presentation.finishedElapsed = nil
        case .hidden, .processing, .working, .asking:
            break
        }
    }

    /// Pure per-state timing decision behind `show(...)`. `.idle` hides
    /// immediately (P1-18: the "ready" HUD must not stick), active in-flight
    /// states stay visible, and the transient toast states keep the exact
    /// durations `show(...)` historically used.
    static func hideBehavior(for state: ProcessingState) -> OverlayHideBehavior {
        switch state {
        case .idle:
            return .hideImmediately
        case .listening, .transcribing, .transforming, .inserting:
            return .keepVisible
        case .modeChanged:
            return .scheduleHide(after: 1.2)
        case .success, .copied:
            return .scheduleHide(after: 0.9)
        case .dispatched:
            // Informational, not an error, but carries a second line of copy
            // ("已下发给 Agent") the user has to actually read, so it needs
            // longer on screen than a bare success toast.
            return .scheduleHide(after: 1.6)
        case .cancelled:
            return .scheduleHide(after: 1.8)
        case .failure:
            return .scheduleHide(after: 2.4)
        }
    }

    /// The same decision, told whether a correction window is open (P0-3).
    ///
    /// Only the two delivery-success toasts change: they *are* the affordance,
    /// so they stay up for exactly the window's length — 0.9s is not enough
    /// time to read a hint, let alone select a word and press a key — and the
    /// duration comes from `CorrectionWindow.windowSeconds` itself so the bar
    /// cannot promise more time than the hotkey actually honors. Errors,
    /// cancellations, mode switches and every in-flight state are not the
    /// affordance and keep the timings above unchanged.
    ///
    /// `OutputDeliveryPolicy` can downgrade an insert to clipboard-only at the
    /// last moment, so `.copied` gets the same treatment as `.success`: which
    /// of the two toasts was chosen says nothing about whether the delivered
    /// text is worth fixing.
    static func hideBehavior(
        for state: ProcessingState,
        correctionWindowArmed: Bool
    ) -> OverlayHideBehavior {
        guard correctionWindowArmed else { return hideBehavior(for: state) }
        switch state {
        case .success, .copied:
            return .scheduleHideWithCorrectionHint(
                after: CorrectionWindow.windowSeconds
            )
        case .idle, .modeChanged, .listening, .transcribing, .transforming,
             .inserting, .dispatched, .cancelled, .failure:
            return hideBehavior(for: state)
        }
    }

    func updateLiveTranscript(_ text: String) {
        guard presentation.state == .listening else { return }
        presentation.liveTranscript = text
        if !text.isEmpty { presentation.lastCaption = text }
    }

    /// How far the speech model has got to loading, pushed by `AppModel`'s
    /// poll. Only ever read while transcribing: a recording taken during the
    /// first-launch download otherwise sits under 「正在识别」 for minutes,
    /// which is the blank screen this feature removes, relabelled.
    func updateWhisperStatus(_ status: WhisperStatusSnapshot?) {
        presentation.whisperStatus = status
    }

    /// The elapsed-time readout, pushed by `AppModel`'s recording tick (P2-10).
    /// Formatting is the tick's job (`RecordingClock.elapsedText(seconds:)`) —
    /// what arrives here is already the string to draw.
    func updateRecordingElapsed(_ text: String) {
        guard presentation.state == .listening else { return }
        presentation.elapsedText = text
    }

    /// The one-time two-minute warning (P2-10). The sentence takes the pill's
    /// caption line for a few seconds — long enough to read, short enough that
    /// someone mid-thought gets their live transcript back — while the tint on
    /// the elapsed readout stays for the rest of the recording.
    func showRecordingWarning(_ text: String) {
        guard presentation.state == .listening else { return }
        presentation.pastWarningThreshold = true
        presentation.recordingWarning = text

        recordingWarningWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.recordingWarningWorkItem = nil
            self?.presentation.recordingWarning = nil
        }
        recordingWarningWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + recordingWarningSeconds,
            execute: item
        )
    }

    /// Called when the recording ends, however it ends.
    func clearRecordingElapsed() {
        recordingWarningWorkItem?.cancel()
        recordingWarningWorkItem = nil
        presentation.elapsedText = nil
        presentation.recordingWarning = nil
        presentation.pastWarningThreshold = false
    }

    func updateAudioLevel(_ level: Double) {
        guard presentation.state == .listening else { return }
        presentation.audioLevel = level
    }

    func hide() {
        dismissWorkItem?.cancel()
        cancelToastOverride()
        removeClickOutsideMonitor()
        removePendingDispatchMonitors()
        removeQuestionKeyMonitors()
        clearRecordingElapsed()
        legacyOnScreen = nil
        surfaceState = .hidden
        presentation.surface = .hidden
        presentation.correctionHint = nil
        presentation.pendingDispatch = nil
        presentation.learningNoteOwnsPanel = false
        panel?.orderOut(nil)
    }

    // MARK: - Pre-dispatch confirmation (P1-6)

    /// Shows `transcript` for `seconds` with the Esc affordance, and starts
    /// watching for that key.
    ///
    /// It preempts whatever the panel was showing (during this window the
    /// surface would read 「正在整理…」, which catches nothing) without
    /// disturbing `surfaceState`, so the next push from `AppModel` — the
    /// dispatched run's working pill, or the cancelled toast — lays the panel
    /// out again on its own.
    func showPendingDispatch(transcript: String, seconds: TimeInterval) {
        dismissWorkItem?.cancel()
        cancelToastOverride()
        presentation.pendingDispatch = OverlayPresentation.PendingDispatch(
            transcript: transcript,
            seconds: seconds,
            startedAt: Date()
        )

        let panel = panel ?? makePanel()
        let size = VoiceSurfacePanelMetrics.pendingDispatch
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        position(panel)
        // Never `makeKey`: the user may still be typing into the app they
        // dictated from, and 1.5 seconds is not worth stealing focus for. The
        // global monitor below is what hears Esc from over there.
        panel.orderFrontRegardless()
        self.panel = panel

        installPendingDispatchMonitors()
    }

    /// Takes the window down, however it ended. Layout is left to `AppModel`'s
    /// next push, which follows immediately in the same main-actor turn.
    func hidePendingDispatch() {
        removePendingDispatchMonitors()
        guard presentation.pendingDispatch != nil else { return }
        presentation.pendingDispatch = nil
        legacyOnScreen = nil
    }

    /// Esc's key code. Named here rather than importing Carbon for one number.
    private static let escapeKeyCode: UInt16 = 53

    private func installPendingDispatchMonitors() {
        removePendingDispatchMonitors()
        // Two monitors, because the keypress can land in either place: local
        // if our own window happens to be frontmost, global if the user is
        // still in the app they were dictating into — which is the normal case,
        // since the pill never takes key focus.
        //
        // Two things a global monitor cannot do, both acceptable here. It
        // cannot *consume* the event (only an event tap can), so Esc also
        // reaches the app in front — in practice a no-op or a dismissed popup,
        // and not worth an event tap of our own for 1.5 seconds. And it needs
        // Accessibility trust, which this app already requires for its hotkey
        // and write-back; without it, Esc still works whenever OpenType is
        // frontmost via the local monitor.
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == Self.escapeKeyCode else { return event }
            self.onCancelPendingDispatch?()
            return nil
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == Self.escapeKeyCode else { return }
            self.onCancelPendingDispatch?()
        }
        pendingDispatchKeyMonitors = [local, global].compactMap { $0 }
    }

    private func removePendingDispatchMonitors() {
        for monitor in pendingDispatchKeyMonitors {
            NSEvent.removeMonitor(monitor)
        }
        pendingDispatchKeyMonitors = []
    }

    // MARK: - Answering an agent question by number key

    /// Watches for `1`…`9` while a question is on screen, so a task started
    /// without touching the mouse can be answered without reaching for it.
    ///
    /// **Local only** — see the comment on the monitor itself for why a global
    /// one is not an option here. The monitor is removed the instant an answer
    /// is sent or the question leaves the screen. Modified keypresses (⌘1, ⌃2,
    /// …) are ignored, since those are somebody else's shortcuts.
    private func installQuestionKeyMonitors(for detail: VoiceSurfaceState.AskingDetail) {
        removeQuestionKeyMonitors()
        guard let options = detail.question.options, !options.isEmpty else { return }

        let answer: (NSEvent) -> Bool = { [weak self] event in
            guard let self else { return false }
            let interesting: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            guard event.modifierFlags.intersection(interesting).isEmpty,
                  let characters = event.charactersIgnoringModifiers,
                  let digit = Int(characters),
                  digit >= 1, digit <= options.count
            else { return false }

            self.removeQuestionKeyMonitors()
            self.onAnswerAgentQuestion?(
                detail.runId,
                AgentQuestionAnswerItem(
                    id: detail.question.id,
                    selected: [options[digit - 1].label],
                    custom: nil
                )
            )
            return true
        }

        // Local only, deliberately. A global monitor sees key events on their
        // way to *other* applications, so a bare "1" typed into Slack while a
        // question was open would answer it — and the agent would act on that
        // answer, with tools. The question card takes key focus when it
        // appears (`canBecomeKey` + `makeKeyAndOrderFront`, added for the
        // custom-answer field), so a local monitor covers exactly the moment
        // the user is looking at the card and means to reply, and nothing else.
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            answer(event) ? nil : event
        }
        questionKeyMonitors = [local].compactMap { $0 }
    }

    private func removeQuestionKeyMonitors() {
        for monitor in questionKeyMonitors {
            NSEvent.removeMonitor(monitor)
        }
        questionKeyMonitors = []
    }

    // MARK: - Legacy transient HUD

    private func presentLegacy(state: ProcessingState, mode: InputMode) {
        dismissWorkItem?.cancel()
        removeClickOutsideMonitor()
        removeQuestionKeyMonitors()
        // Whatever is being pushed now owns the panel; a note that had it to
        // itself is back to being a row on this toast, if it belongs on one.
        presentation.learningNoteOwnsPanel = false

        let behavior = Self.hideBehavior(
            for: state,
            correctionWindowArmed: correctionWindowArmed
        )

        presentation.state = state
        presentation.mode = mode
        presentation.surface = .hidden
        if state != .listening {
            presentation.liveTranscript = ""
            presentation.audioLevel = 0
        }
        // The affordance and the timing are the same decision, so they are
        // read off the same answer rather than tested for separately.
        if case .scheduleHideWithCorrectionHint(let seconds) = behavior {
            presentation.correctionHint = OverlayPresentation.CorrectionHint(
                text: CorrectionWindow.hintText,
                seconds: seconds,
                startedAt: Date()
            )
        } else {
            presentation.correctionHint = nil
        }

        let panel = panel ?? makePanel()
        let size = legacySize(for: state)
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel

        switch behavior {
        case .hideImmediately:
            hide()
        case .scheduleHide(let seconds):
            legacyOnScreen = (state, mode)
            dismiss(after: seconds)
        case .scheduleHideWithCorrectionHint(let seconds):
            legacyOnScreen = (state, mode)
            dismiss(after: DeliveryFeedback.visibleSeconds(
                correctionSeconds: seconds,
                hasActions: presentation.learningNote != nil || !presentation.aliasReplacements.isEmpty
            ))
        case .keepVisible:
            legacyOnScreen = (state, mode)
        }
    }

    /// How big the legacy panel has to be to hold `state`'s content, including
    /// the learning-loop rows a delivery may have grown (§D).
    private func legacySize(for state: ProcessingState) -> NSSize {
        switch state {
        case .listening:
            return VoiceSurfacePanelMetrics.pill
        case .success, .copied:
            return VoiceSurfacePanelMetrics.delivery(
                hasText: !presentation.deliveryBody.isEmpty &&
                    (presentation.learningNote != nil || !presentation.aliasReplacements.isEmpty),
                hasHint: presentation.correctionHint != nil,
                hasNote: presentation.learningNote != nil,
                replacementCount: presentation.aliasReplacements.count,
                replacementsExpanded: presentation.aliasReplacementsExpanded
            )
        default:
            return VoiceSurfacePanelMetrics.compactToast
        }
    }

    /// Re-sizes the panel around content that changed while it was up — the
    /// rewrite list opening, an undo's outcome arriving — **without** touching
    /// the dismiss timer. The delivery toast's clock is the correction window's
    /// (P0-3), and re-presenting it to change its height would hand the user
    /// eight fresh seconds of a window that is already half spent.
    private func resizeLegacyPanel(for state: ProcessingState) {
        guard let panel, panel.isVisible else { return }
        let size = legacySize(for: state)
        hostingView.frame = NSRect(origin: .zero, size: size)
        let frame = positionedFrame(size: size, fallback: panel.frame)
        panel.setFrame(frame, display: true, animate: true)
    }

    /// The learning-loop note as a toast of its own, for when there is no
    /// delivery toast to hang it on (§D). Preempts and restores the unified
    /// surface exactly like `presentToast` does, for the same reason: an undo's
    /// outcome must neither be swallowed by a card that is still up nor tear
    /// that card down.
    private func presentNote() {
        cancelToastOverride()
        let preempted = surfaceState

        dismissWorkItem?.cancel()
        removeClickOutsideMonitor()
        removeQuestionKeyMonitors()
        presentation.surface = .hidden
        presentation.correctionHint = nil
        presentation.learningNoteOwnsPanel = true
        legacyOnScreen = nil

        let panel = panel ?? makePanel()
        let size = VoiceSurfacePanelMetrics.note
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
        dismiss(after: Self.learningNoteSeconds)

        guard preempted != .hidden else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.toastOverride = nil
            self.restoreSurfaceAfterToast()
        }
        toastOverride = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.learningNoteSeconds,
            execute: item
        )
    }

    /// Long enough to read one sentence naming a term and what happened to it.
    private static let learningNoteSeconds: TimeInterval = 2.6

    /// Shows a transient legacy toast, preempting the unified surface when it
    /// owns the panel instead of being swallowed by it. The surface is put
    /// back — as it stands *then*, not as it stood now — when the toast's
    /// `hideBehavior` duration is up, so a long agent run's ticker survives a
    /// failure toast and picks up whatever steps arrived meanwhile.
    ///
    /// Nothing to preempt (`surfaceState == .hidden`) means this is exactly
    /// the legacy path, and a state that isn't a scheduled-hide toast (only
    /// `.idle` today, which hides immediately) schedules no restore.
    ///
    /// The restore delay is taken from `scheduledHideDelay` rather than by
    /// matching one case: this `guard` is not exhaustiveness-checked, so a
    /// `case .scheduleHide` that silently failed to match a newer toast case
    /// would return early and leave the preempted surface off screen forever.
    private func presentToast(state: ProcessingState, mode: InputMode) {
        cancelToastOverride()
        let preempted = surfaceState

        presentLegacy(state: state, mode: mode)

        guard preempted != .hidden,
              let seconds = Self.hideBehavior(
                for: state,
                correctionWindowArmed: correctionWindowArmed
              ).scheduledHideDelay
        else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.toastOverride = nil
            self.restoreSurfaceAfterToast()
        }
        toastOverride = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func restoreSurfaceAfterToast() {
        guard surfaceState != .hidden else {
            hide()
            return
        }
        presentation.state = lastState
        presentation.mode = lastMode
        presentation.surface = surfaceState
        // The surface owns the panel again; the toast's hint went with it.
        presentation.correctionHint = nil
        // `grewFrom: .hidden` suppresses the frame animation: coming back from
        // a toast is not the pill-morphs-into-the-card moment, so it snaps.
        presentSurface(surfaceState, grewFrom: .hidden)
    }

    private func cancelToastOverride() {
        toastOverride?.cancel()
        toastOverride = nil
    }

    // MARK: - Unified voice surface

    private func presentSurface(
        _ surface: VoiceSurfaceState,
        grewFrom previous: VoiceSurfaceState
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel
        // The surface owns the panel from here on; no legacy toast is up, and
        // no note has it to itself.
        legacyOnScreen = nil
        presentation.correctionHint = nil
        presentation.learningNoteOwnsPanel = false

        let size = VoiceSurfacePanelMetrics.size(for: surface)
        let frame = positionedFrame(size: size, fallback: panel.frame)
        hostingView.frame = NSRect(origin: .zero, size: size)

        // Animate only a real size change on an already-visible panel: that is
        // the pill-morphs-into-the-card moment. A first appearance just snaps
        // in at the right size.
        let shouldAnimate = panel.isVisible
            && previous != .hidden
            && !NSEqualSizes(panel.frame.size, NSSize(width: size.width, height: size.height))
        panel.setFrame(frame, display: true, animate: shouldAnimate)

        if case .asking(let detail) = surface {
            installQuestionKeyMonitors(for: detail)
        } else {
            removeQuestionKeyMonitors()
        }

        if surface.allowsClickOutsideDismiss {
            // A finished card is interactive (buttons, selectable Markdown,
            // Escape), so it takes key status — but only on the way in, never
            // on a re-render, so it can't keep yanking focus back.
            if !panel.isVisible || previous.allowsClickOutsideDismiss == false {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
            installClickOutsideMonitor()
        } else {
            // Listening/processing/working must never steal key focus from
            // whatever the user is typing into.
            removeClickOutsideMonitor()
            panel.orderFrontRegardless()
        }
    }

    private func installClickOutsideMonitor() {
        guard clickOutsideMonitor == nil else { return }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self,
                  let panel = self.panel,
                  panel.isVisible,
                  self.surfaceState.allowsClickOutsideDismiss
            else { return }
            let clickLocation = NSEvent.mouseLocation
            guard !panel.frame.contains(clickLocation) else { return }
            self.onRequestDismiss?()
        }
    }

    private func removeClickOutsideMonitor() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
        }
        clickOutsideMonitor = nil
    }

    // MARK: - Panel plumbing

    private func makePanel() -> NSPanel {
        let panel = KeyableOverlayPanel(
            contentRect: NSRect(origin: .zero, size: VoiceSurfacePanelMetrics.pill),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // A panel is its own window and does not inherit `NSApp.appearance`,
        // so without this it kept the system's dark palette while the rest of
        // the app was pinned light — the same split that made the menu bar
        // popover draw white text on a white sheet.
        panel.appearance = NSAppearance(named: .aqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        // The handoff's `0 22px 60px rgba(0,0,0,.40)` is a window shadow, not
        // an in-content one: a SwiftUI `.shadow` would be clipped by the
        // hosting view's bounds, which end exactly at the panel's edge. AppKit
        // draws it from the content's alpha instead.
        panel.hasShadow = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = true
        panel.onDragStarted = { [weak self] in self?.draggingPanel = true }
        panel.onDragEnded = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.draggingPanel = false
            guard let screen = panel.screen?.visibleFrame ?? self.visibleFrame() else { return }
            let anchor = OverlayPosition.anchor(for: panel.frame, in: screen)
            UserDefaults.standard.set([Double(anchor.x), Double(anchor.y)], forKey: self.positionPreference)
            panel.setFrame(OverlayPosition.frame(size: panel.frame.size, screen: screen, anchor: anchor), display: true)
        }
        panel.contentView = hostingView
        return panel
    }

    /// The screen the panel is laid out on: whichever display the pointer is on,
    /// falling back to `NSScreen.main` (P2-10 — see `ScreenPlacement`). Called
    /// on every `presentSurface`/`position`, never cached, so an already-open
    /// panel follows the user to another display.
    private func visibleFrame() -> CGRect? {
        ScreenPlacement.currentVisibleFrame()
    }

    private func position(_ panel: NSPanel) {
        panel.setFrameOrigin(positionedFrame(size: panel.frame.size, fallback: panel.frame).origin)
    }

    private func positionedFrame(size: CGSize, fallback: CGRect) -> CGRect {
        let screen = visibleFrame() ?? fallback
        if draggingPanel, let panel {
            return CGRect(x: panel.frame.midX - size.width / 2,
                          y: panel.frame.minY, width: size.width, height: size.height)
        }
        if let saved = UserDefaults.standard.array(forKey: positionPreference) as? [Double],
           saved.count == 2, saved.allSatisfy({ $0.isFinite }) {
            return OverlayPosition.frame(size: size, screen: screen,
                                         anchor: CGPoint(x: saved[0], y: saved[1]))
        }
        return VoiceSurfacePanelLayout.frame(for: size, visibleFrame: screen)
    }

    private func dismiss(after seconds: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in
            self?.legacyOnScreen = nil
            self?.panel?.orderOut(nil)
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
}

private extension VoiceSurfaceState {
    /// Whether this state is part of one "the user is waiting" episode — the
    /// stretch the pill's elapsed readout and step counter measure.
    var isBusyEpisode: Bool {
        switch self {
        case .processing, .working, .asking:
            return true
        case .hidden, .listening, .result, .failed:
            return false
        }
    }
}

/// A `.nonactivatingPanel` normally can't become key, which would swallow the
/// Escape keypress meant for the result card's `onExitCommand`. Overriding
/// `canBecomeKey` lets the panel receive keyboard input while
/// `.nonactivatingPanel` still keeps it from stealing app activation away from
/// whatever the user was typing into. Key status is only ever *taken* for the
/// result/failed card (see `presentSurface`), never for the pill.
private final class KeyableOverlayPanel: NSPanel {
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?
    override var canBecomeKey: Bool { true }
}

/// Only the dedicated handle catches mouse events; text and controls keep theirs.
private struct OverlayDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ nsView: HandleView, context: Context) {}

    final class HandleView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var needsPanelToBecomeKey: Bool { false }
        override var mouseDownCanMoveWindow: Bool { false }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) {
            guard let panel = window as? KeyableOverlayPanel else { return }
            panel.onDragStarted?()
            NSCursor.closedHand.push()
            panel.performDrag(with: event)
            NSCursor.pop()
            panel.onDragEnded?()
        }
    }
}

/// The panel's content view, with one behaviour AppKit does not give by
/// default: a click that arrives while **another** application is frontmost
/// lands on the control it hit, instead of being spent on bringing this window
/// forward.
///
/// Every control on this panel exists to be clicked in exactly that situation —
/// the user is in Notes looking at what was just delivered, and the panel is a
/// `.nonactivatingPanel` precisely so acting on it does not pull them out of
/// their app. Without `acceptsFirstMouse`, 「撤销并删除该词条」 (§D-1) would need
/// two clicks inside an eight-second window, which for a control offered *once*
/// per delivery is the same as not offering it.
private final class OverlayHostingView: NSHostingView<OverlayView> {
    required init(rootView: OverlayView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OverlayHostingView is built in code, never from a nib")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct OverlayView: View {
    @ObservedObject var presentation: OverlayPresentation
    let onClose: () -> Void
    let onCopy: (String) -> Void
    let onOpenMainWindow: () -> Void
    let onStop: () -> Void
    let onAnswer: (String, AgentQuestionAnswerItem) -> Void
    let onFollowUp: (String) -> Void
    let onFollowUpByVoice: () -> Void
    let onToggleReplacements: () -> Void
    let onUndoReplacement: (AliasReplacement) -> Void
    let onOpenLearnedTerm: (String) -> Void
    let onEscalate: (AssistantEscalation) -> Void

    var body: some View {
        Group {
            // The pre-dispatch confirmation (P1-6) preempts everything: for
            // its 1.5 seconds the only thing worth showing is what was heard.
            if let pending = presentation.pendingDispatch {
                pendingDispatchContent(pending)
            } else if presentation.learningNoteOwnsPanel,
                      let note = presentation.learningNote {
                noteContent(note)
            } else {
                surfaceContent
            }
        }
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(.white.opacity(0.45), lineWidth: 0.75)
        )
        .tint(DS.Colour.accent)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 28, height: 3)
                .frame(width: 72, height: 16)
                .overlay(OverlayDragHandle())
                .help(OpenTypeL10n.text("拖动以移动浮层", english: "Drag to move"))
        }
        .environment(\.locale, OpenTypeL10n.locale)
        // §F: tears down and rebuilds the whole subtree on a live language
        // switch, the same seam `RootView`/`MenuBarPopoverView` use via
        // `configuration.interfaceLanguageToken` — this panel has no
        // `configuration` in scope, so `OverlayController.languageToken`
        // mirrors it instead (`AppModel.changeInterfaceLanguage`).
        .id(presentation.languageToken)
        // The content crossfade half of the morph: the panel's frame animates
        // (`setFrame(_:display:animate:)`), the contents fade between states.
        .animation(.easeInOut(duration: 0.2), value: presentation.surface)
    }

    @ViewBuilder
    private var surfaceContent: some View {
        Group {
            switch presentation.surface {
            case .hidden:
                if presentation.state == .listening {
                    listeningContent
                } else if presentation.state == .success || presentation.state == .copied {
                    deliveryContent(hint: presentation.correctionHint)
                } else {
                    compactContent
                }
            case .listening:
                listeningContent
            case .processing:
                WorkingPill(
                    kind: presentation.mode == .agent ? .agent : .ask,
                    task: presentation.lastCaption,
                    toolLine: nil,
                    fallbackLine: OpenTypeL10n.text("正在识别…", english: "Transcribing…"),
                    startedAt: presentation.workingStartedAt,
                    stepCount: 0,
                    onStop: nil
                )
            case .working(let detail):
                WorkingPill(
                    // The badge names the run this pill belongs to, not the
                    // currently-selected mode: a dispatched run outlives the
                    // recording (and the user is free to switch modes while it
                    // is still working), so `presentation.mode` would be able
                    // to label an Agent run "听写".
                    kind: detail.kind,
                    task: presentation.lastCaption,
                    toolLine: detail.currentStep.flatMap(AgentToolLine.parse),
                    fallbackLine: detail.kind == .agent
                        ? OpenTypeL10n.text("正在准备下一步…", english: "Planning the next step…")
                        : OpenTypeL10n.text("正在查资料并作答…", english: "Searching and answering…"),
                    startedAt: presentation.workingStartedAt,
                    stepCount: presentation.stepCount,
                    onStop: presentation.surface.stoppableAgentRun ? onStop : nil
                )
            case .asking(let detail):
                AgentQuestionCard(
                    detail: detail,
                    onAnswer: { answer in onAnswer(detail.runId, answer) },
                    onStop: onStop
                )
            case .result(let card):
                VoiceSurfaceCard(
                    card: card,
                    failed: false,
                    elapsed: presentation.finishedElapsed,
                    escalation: presentation.escalation,
                    onClose: onClose,
                    onCopy: onCopy,
                    onOpenMainWindow: onOpenMainWindow,
                    onFollowUp: onFollowUp,
                    onFollowUpByVoice: onFollowUpByVoice,
                    onEscalate: onEscalate
                )
            case .failed(let card):
                VoiceSurfaceCard(
                    card: card,
                    failed: true,
                    elapsed: presentation.finishedElapsed,
                    escalation: presentation.escalation,
                    onClose: onClose,
                    onCopy: onCopy,
                    onOpenMainWindow: onOpenMainWindow,
                    onFollowUp: onFollowUp,
                    onFollowUpByVoice: onFollowUpByVoice,
                    onEscalate: onEscalate
                )
            }
        }
    }

    /// The pre-dispatch confirmation (P1-6): what was heard, verbatim, with a
    /// bar that empties exactly as the window does and the key that stops it.
    ///
    /// The transcript is the headline rather than a subtitle, because reading
    /// it back is the entire function of this window — a card that led with
    /// 「正在下发…」 would occupy the same 1.5 seconds and catch nothing. The
    /// bar is what lets the user tell at a glance how much of the offer is
    /// left instead of counting.
    private func pendingDispatchContent(
        _ pending: OverlayPresentation.PendingDispatch
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "paperplane")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Colour.accent)

                Text(pending.transcript)
                    .font(DS.Text.body(.medium))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            HStack(spacing: 9) {
                WindowCountdownBar(seconds: pending.seconds)
                    .id(pending.startedAt)
                Text(
                    OpenTypeL10n.text(
                        "即将下发给 Agent · \(DispatchConfirmation.hintText)",
                        english: "Dispatching · \(DispatchConfirmation.hintText)"
                    )
                )
                .font(DS.Text.mono())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(
            width: VoiceSurfacePanelMetrics.pendingDispatch.width,
            height: VoiceSurfacePanelMetrics.pendingDispatch.height,
            alignment: .leading
        )
    }

    /// 4A. The live caption is the reason this panel exists, so it is the
    /// largest thing on it — it used to be 13pt, smaller than a button label.
    private var listeningContent: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                LiveWaveform(level: presentation.audioLevel)

                ModeTag(mode: presentation.mode)

                Spacer(minLength: 4)

                // How long this recording has been running (P2-10). Mono so
                // the pill's contents don't shuffle sideways once a second;
                // tinted for the rest of the recording once the two-minute
                // warning has fired.
                if let elapsed = presentation.elapsedText {
                    Text(elapsed)
                        .font(DS.Text.mono())
                        .foregroundStyle(
                            presentation.pastWarningThreshold
                                ? DS.Colour.warningText
                                : DS.Colour.ink(0.45)
                        )
                }

                // P0's follow-up-recording fix: a hotkey-started recording has
                // no control here (just today's hint, unchanged), but a
                // click-started one — the result card's mic button, which is
                // off screen the instant this pill replaces the card — has no
                // other discoverable way to stop. `presentation.stopAffordance`
                // is one value for both the hint text and whether it is
                // actually clickable, so the two can never disagree (see
                // `RecordingClock.StopAffordance`'s doc comment).
                if presentation.stopAffordance.stopsOnClick {
                    Button(presentation.stopAffordance.hintText, action: onFollowUpByVoice)
                        .buttonStyle(.plain)
                        .font(DS.Text.mono())
                        .foregroundStyle(DS.Colour.accent)
                } else {
                    Text(presentation.stopAffordance.hintText)
                        .font(DS.Text.mono())
                        .foregroundStyle(DS.Colour.ink(0.3))
                }
            }

            Text(captionText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(captionColor)
                .lineLimit(2)
                .truncationMode(.head)
                // Fills whatever the mode-switch row does not use, so the pill
                // reads the same height with the hint and without it.
                .frame(
                    maxWidth: .infinity,
                    minHeight: 38,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .contentTransition(.opacity)
                .animation(
                    .easeOut(duration: 0.16),
                    value: presentation.liveTranscript
                )

            if presentation.modeSwitchHintAvailable {
                modeSwitchRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(
            width: VoiceSurfacePanelMetrics.pill.width,
            height: VoiceSurfacePanelMetrics.pill.height,
            alignment: .topLeading
        )
    }

    /// 「Tab 切换到 [问答] [Agent]」 — the mode switch was previously only
    /// discoverable from Settings, which is not where anyone is while holding
    /// a key down.
    private var modeSwitchRow: some View {
        HStack(spacing: 7) {
            Text(OpenTypeL10n.text("Tab 切换到", english: "Tab switches to"))
                .font(DS.Text.mono())
                .foregroundStyle(DS.Colour.ink(0.35))

            ForEach(InputMode.visibleModes.filter { $0 != presentation.mode }) { mode in
                Text(mode.title)
                    .font(DS.Text.size(11))
                    .foregroundStyle(DS.Colour.ink(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        DS.Colour.control,
                        in: RoundedRectangle(cornerRadius: DS.Radius.tag, style: .continuous)
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 9)
        .dsHairline(.top, color: DS.Colour.border)
    }

    /// Replaces 「正在识别」 while the model is still coming up.
    ///
    /// The recording is already in flight and will be transcribed the moment
    /// the model arrives — nothing is lost. What the user must not be given is
    /// 「正在识别」 for four minutes, which looks exactly like a hang.
    private var whisperPreparingTitle: String? {
        guard
            presentation.state == .transcribing,
            let whisper = presentation.whisperStatus,
            whisper.backend == .local,
            WhisperReadinessPolicy.showsPreparingBanner(whisper.state)
        else { return nil }
        return OpenTypeL10n.text("正在准备语音模型", english: "Preparing the speech model")
    }

    private var whisperPreparingDetail: String? {
        guard
            whisperPreparingTitle != nil,
            let whisper = presentation.whisperStatus
        else { return nil }
        // A percentage only when the total is genuinely known; otherwise the
        // honest sentence, never a figure invented to fill the line.
        if let fraction = whisper.fractionComplete {
            let percent = Int((fraction * 100).rounded())
            return OpenTypeL10n.text(
                "首次约 460 MB · \(percent)% · 说的话会保留",
                english: "About 460 MB the first time · \(percent)% · your words are kept"
            )
        }
        return OpenTypeL10n.text(
            "首次约 460 MB · 说的话会保留",
            english: "About 460 MB the first time · your words are kept"
        )
    }

    private var compactContent: some View {
        HStack(spacing: 11) {
            Image(systemName: presentation.state.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(symbolColour)

            VStack(alignment: .leading, spacing: 2) {
                Text(whisperPreparingTitle ?? presentation.state.title)
                    .font(DS.Text.body(.semibold))
                Text(
                    whisperPreparingDetail
                        ?? presentation.state.overlayDetail(for: presentation.mode)
                )
                .font(DS.Text.caption())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(
            width: VoiceSurfacePanelMetrics.compactToast.width,
            height: VoiceSurfacePanelMetrics.compactToast.height
        )
    }

    /// 4C. Delivery, and — while a correction window is open (P0-3) — the
    /// offer to fix it by voice.
    ///
    /// Two changes from the old toast. It says **where the text landed**
    /// (「已写入 Notes」) rather than 「已复制」, because "copied" was the least
    /// interesting true thing about a delivery that also went into the app the
    /// user was typing in; the clipboard copy is demoted to the mono 「也已复制」
    /// at the right. And the countdown bar and the hint are one row instead of
    /// two stacked blocks — they are one statement, and stacking them made the
    /// panel taller than what it had to say.
    private func deliveryContent(
        hint: OverlayPresentation.CorrectionHint?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                // Neutral, not green and not accent: success is the common
                // case, and colouring it spends attention on the expected
                // outcome (handoff §Design Tokens).
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Colour.ink(0.55))

                Text(deliveryHeadline)
                    .font(DS.Text.body(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if presentation.state == .success {
                    Text(OpenTypeL10n.text("也已复制", english: "Copied too"))
                        .font(DS.Text.mono())
                        .foregroundStyle(DS.Colour.ink(0.35))
                }
            }

            if !presentation.deliveryBody.isEmpty,
               presentation.learningNote != nil || !presentation.aliasReplacements.isEmpty {
                Text(presentation.deliveryBody)
                    .font(DS.Text.size(12.5))
                    // 1.55 line height at 12.5pt.
                    .lineSpacing(4)
                    .foregroundStyle(DS.Colour.ink(0.55))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if let note = presentation.learningNote {
                LearningNoteRow(note: note, onOpen: onOpenLearnedTerm)
            }

            if let summary = AliasReplacementNotice.summary(
                for: presentation.aliasReplacements
            ) {
                replacementsSection(summary: summary)
            }

            Spacer(minLength: 0)

            if let hint {
                HStack(spacing: 9) {
                    WindowCountdownBar(seconds: hint.seconds)
                        // A re-armed window is a new bar starting full again,
                        // not the old one continuing — new identity, fresh
                        // `onAppear`.
                        .id(hint.startedAt)
                    Text(hint.text)
                        .font(DS.Text.mono())
                        .foregroundStyle(DS.Colour.ink(0.45))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .padding(.top, 9)
                .dsHairline(.top, color: DS.Colour.border)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 「自动修正 N 处」, and — once opened — one row per rewrite with the way
    /// out of it (D-1).
    ///
    /// Collapsed by default because the summary is what the user needs to see
    /// on a delivery that went right, and expanded only on purpose because the
    /// list is what they need when it went wrong. The whole affordance is up for
    /// exactly as long as the correction window (`CorrectionWindow.windowSeconds`),
    /// which is also exactly as long as the undo can still put the text back.
    private func replacementsSection(summary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggleReplacements) {
                HStack(spacing: 5) {
                    Image(systemName: "text.badge.checkmark")
                        .font(DS.Text.size(11))
                    Text(summary)
                        .font(DS.Text.size(11, .medium))
                    Image(systemName: presentation.aliasReplacementsExpanded
                          ? "chevron.down" : "chevron.right")
                        .font(DS.Text.size(9, .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DS.Colour.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(OpenTypeL10n.text(
                "展开可以撤销某一处替换，并删除对应的词典记录",
                english: "Open to undo one replacement and delete the dictionary entry behind it"
            ))

            if presentation.aliasReplacementsExpanded {
                ForEach(
                    Array(
                        presentation.aliasReplacements
                            .prefix(VoiceSurfacePanelMetrics.maxExpandedReplacements)
                            .enumerated()
                    ),
                    id: \.offset
                ) { _, replacement in
                    AliasReplacementRow(
                        replacement: replacement,
                        onUndo: { onUndoReplacement(replacement) }
                    )
                }
            }
        }
        .padding(.top, 7)
        .dsHairline(.top, color: DS.Colour.border)
    }

    /// The learning-loop note when it has the panel to itself — an undo's
    /// outcome, which lands after the delivery toast it belongs to may already
    /// have gone.
    private func noteContent(_ note: LearningNote) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "book.closed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Colour.ink(0.55))

            LearningNoteRow(note: note, onOpen: onOpenLearnedTerm, lineLimit: 3)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(
            width: VoiceSurfacePanelMetrics.note.width,
            height: VoiceSurfacePanelMetrics.note.height,
            alignment: .leading
        )
    }

    /// 「已写入 Notes」 when the text went into an app, 「已复制」 when the
    /// clipboard is genuinely all that happened.
    private var deliveryHeadline: String {
        guard presentation.state == .success else {
            return ProcessingState.copied.title
        }
        if let app = presentation.deliveryTargetApp, !app.isEmpty {
            return OpenTypeL10n.text("已写入 \(app)", english: "Written to \(app)")
        }
        return OpenTypeL10n.text("已写入当前输入框", english: "Written to the focused field")
    }

    /// The pill's second line: the two-minute warning while it is up, then the
    /// live transcript, then the mode's own invitation to speak.
    ///
    /// The warning deliberately preempts the live caption rather than being
    /// squeezed in beside it — the pill is two lines tall by design, and a
    /// warning the user has to notice while reading their own words back is a
    /// warning half of them will miss. It hands the line back after a few
    /// seconds (`OverlayController.recordingWarningSeconds`).
    private var captionText: String {
        if let warning = presentation.recordingWarning {
            return warning
        }
        if !presentation.liveTranscript.isEmpty {
            return presentation.liveTranscript
        }
        switch presentation.mode {
        case .transcribe:
            return OpenTypeL10n.text(
                "直接说话，松开后原样转成文字…",
                english: "Just speak — released speech becomes text as-is…"
            )
        case .ask:
            return OpenTypeL10n.text(
                "说出你的问题，松开后直接获得答案…",
                english: "Ask your question — get a direct answer here…"
            )
        case .agent:
            return OpenTypeL10n.text(
                "说出希望 Agent Runtime 完成的任务…",
                english: "Describe the task for the Agent Runtime…"
            )
        }
    }

    private var captionColor: Color {
        if presentation.recordingWarning != nil { return DS.Colour.warningText }
        return presentation.liveTranscript.isEmpty ? .secondary : .primary
    }

    private var symbolColour: Color {
        switch presentation.state {
        case .failure: return DS.Colour.error
        case .cancelled: return .secondary
        default: return DS.Colour.accent
        }
    }
}

/// 「已记住：呸泡 → PayPal」 (D-2), or how an undo turned out (D-1).
///
/// A button when it has somewhere to go and plain text when it does not, rather
/// than a button that sometimes does nothing: the click-through exists so the
/// user can go *check* what was just learned, and an undo's note has had its
/// term deleted by the time it is drawn.
private struct LearningNoteRow: View {
    let note: LearningNote
    let onOpen: (String) -> Void
    var lineLimit = 1

    var body: some View {
        if let term = note.term {
            Button {
                onOpen(term)
            } label: {
                HStack(spacing: 5) {
                    label
                    Image(systemName: "arrow.up.forward")
                        .font(DS.Text.size(9, .semibold))
                        .foregroundStyle(DS.Colour.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(OpenTypeL10n.text(
                "在记忆页查看这个词条",
                english: "Show this entry on the Memory page"
            ))
        } else {
            label
        }
    }

    private var label: some View {
        Text(note.text)
            .font(DS.Text.size(11.5))
            .foregroundStyle(DS.Colour.ink(0.55))
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }
}

/// One rewrite, and the way out of it: 「呸泡 → PayPal · 撤销」.
///
/// The undo is the row's reason for existing, so it is a control rather than a
/// context menu — a wrongly-learned alias is otherwise only reachable by
/// hunting through the 记忆 page, which is where this feature's whole
/// motivation came from (review §1).
private struct AliasReplacementRow: View {
    let replacement: AliasReplacement
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text(replacement.from)
                .font(DS.Text.mono())
                .foregroundStyle(DS.Colour.ink(0.45))
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(DS.Text.size(9))
                .foregroundStyle(DS.Colour.ink(0.3))
            Text(replacement.to)
                .font(DS.Text.mono(11, weight: .medium))
                .foregroundStyle(DS.Colour.ink(0.7))
                .lineLimit(1)

            Spacer(minLength: 6)

            Button(action: onUndo) {
                Text(OpenTypeL10n.text("撤销并删除该词条", english: "Undo and forget"))
                    .font(DS.Text.size(11, .medium))
                    .foregroundStyle(DS.Colour.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 「词条」 rather than 「别名」: `DELETE /memory/terms/:id` takes the
            // whole row, canonical and every alias on it, and there is no
            // endpoint that removes one alias. Saying otherwise would promise
            // a narrower deletion than the click performs.
            .help(OpenTypeL10n.text(
                "把这处替换改回原话，并从词典中删除这条词条",
                english: "Put the original words back and delete this entry from the dictionary"
            ))
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            DS.Colour.OnPanel.fill,
            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        )
    }
}

/// The coloured type tag that replaced the grey capsule: Agent carries its own
/// identity colour, the two speech modes carry the accent. It is the only
/// place on the pill where the mode is named, so it has to be readable at a
/// glance rather than merely present.
/// The fill and the text are separate colours because the handoff darkens the
/// text on the **blue** tag only: 听写/问答 is `#0A5CC8` on 12%-accent, while
/// Agent is `#4B45E8` on 12% of itself, undarkened. One `colour` used for both
/// roles made the blue tag's text a step too light.
private struct ModeTag: View {
    let title: String
    let fill: Color
    let tint: Color

    init(mode: InputMode) {
        title = mode.title
        fill = mode == .agent ? DS.Colour.agent : DS.Colour.accent
        tint = mode == .agent ? DS.Colour.agent : DS.Colour.askTag
    }

    init(kind: AskPanelState.Kind) {
        switch kind {
        case .agent:
            title = InputMode.agent.title
            fill = DS.Colour.agent
            tint = DS.Colour.agent
        case .ask:
            title = InputMode.ask.title
            fill = DS.Colour.accent
            tint = DS.Colour.askTag
        }
    }

    var body: some View {
        Text(title)
            .font(DS.Text.groupLabel())
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                fill.opacity(0.12),
                in: RoundedRectangle(cornerRadius: DS.Radius.tag, style: .continuous)
            )
    }
}

/// A timed window running out, drawn rather than counted: a bar that starts
/// full and reaches zero at the same instant the window closes. Shared by the
/// two windows that have one — the post-delivery correction offer (P0-3) and
/// the pre-dispatch confirmation (P1-6) — so neither can promise more time
/// than its own deadline. Driven by one linear animation over the window's own
/// duration rather than a ticking timer, so it costs nothing while it runs and
/// cannot drift away from what it is drawing.
private struct WindowCountdownBar: View {
    let seconds: TimeInterval

    @State private var remaining: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.Colour.borderStrong)
                Capsule()
                    .fill(DS.Colour.accent)
                    .frame(width: max(0, proxy.size.width * remaining))
            }
        }
        .frame(height: 2)
        .frame(minWidth: 60)
        .onAppear {
            withAnimation(.linear(duration: seconds)) { remaining = 0 }
        }
    }
}

/// 4B. What is actually happening, instead of 「正在思考…」.
///
/// The old pill said the same six characters for the whole run whether that
/// was two seconds or two minutes. The one thing somebody waiting wants to
/// know is what it is doing right now, so the tool call is the content: its
/// name and arguments in mono, under a header that carries the step number and
/// how long this has been going.
private struct WorkingPill: View {
    let kind: AskPanelState.Kind
    /// What the user said, as the live caption caught it. Empty when live
    /// captions are off, in which case the row is dropped rather than filled
    /// with a placeholder.
    let task: String
    let toolLine: AgentToolLine.Line?
    /// What to put on the mono line before any tool has been called.
    let fallbackLine: String
    let startedAt: Date?
    let stepCount: Int
    /// Non-nil only while the surface is showing a stoppable agent run
    /// (`VoiceSurfaceState.stoppableAgentRun`). Separate from the card's
    /// 关闭: closing the panel and stopping the run are different intentions,
    /// and dismissal deliberately never cancels an agent run.
    var onStop: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                BreathingDot(colour: kind == .agent ? DS.Colour.agent : DS.Colour.accent)

                ModeTag(kind: kind)

                Spacer(minLength: 4)

                if let startedAt {
                    ElapsedLabel(startedAt: startedAt, stepCount: stepCount)
                }

                if let onStop {
                    // Plain rather than bordered: a bordered control is ~24pt
                    // tall and forced this whole row taller than the text it
                    // sits beside, which is what made the working pill look
                    // padded and crowded at once. The HUD's register is text,
                    // not chrome.
                    Button(OpenTypeL10n.text("停止", english: "Stop"), action: onStop)
                        .buttonStyle(.plain)
                        .font(DS.Text.size(11.5, .medium))
                        .foregroundStyle(DS.Colour.accent)
                }
            }

            if !task.isEmpty {
                Text(task)
                    .font(DS.Text.body())
                    .foregroundStyle(DS.Colour.ink(0.6))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            // The tool block sits on the pill's bottom edge whether or not
            // there is a task line above it, so it does not slide up and down
            // between a run started with live captions on and one without.
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.Colour.agent)
                    Text(toolLine.map { "\($0.tool) · \($0.summary)" } ?? fallbackLine)
                        .font(DS.Text.mono(11.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                }
                IndeterminateBar()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                DS.Colour.inset,
                in: RoundedRectangle(cornerRadius: DS.Radius.nested, style: .continuous)
            )
            .animation(.easeOut(duration: 0.16), value: toolLine)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(
            width: VoiceSurfacePanelMetrics.pill.width,
            height: VoiceSurfacePanelMetrics.pill.height,
            alignment: .topLeading
        )
    }
}

/// 「第 6 步 · 42s」, ticking once a second.
///
/// The handoff's 「第 6 / ~9 步」 wants a total, and there is none: `/agent/run`
/// reports the steps it has taken, never how many it expects. Rather than
/// invent a denominator the run would then contradict, this prints the step
/// number alone — the handoff's own instruction for exactly this case.
private struct ElapsedLabel: View {
    let startedAt: Date
    let stepCount: Int

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            Text(text(at: context.date))
                .font(DS.Text.mono())
                .foregroundStyle(DS.Colour.ink(0.45))
        }
    }

    private func text(at now: Date) -> String {
        let elapsed = OverlayElapsed.short(max(0, now.timeIntervalSince(startedAt)))
        guard stepCount > 0 else { return elapsed }
        return OpenTypeL10n.text(
            "第 \(stepCount) 步 · \(elapsed)",
            english: "Step \(stepCount) · \(elapsed)"
        )
    }
}

enum OverlayElapsed {
    /// `42s`, `2m14s`. Seconds-only below a minute because that is the range
    /// almost every run finishes in, and `0:42` reads as a timestamp.
    static func short(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        guard total >= 60 else { return "\(total)s" }
        return "\(total / 60)m\(total % 60)s"
    }

    /// The same, with one decimal below a minute: a finished run's duration is
    /// read once and compared, so the tenth is worth the character.
    static func precise(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else {
            return String(format: "%.1fs", max(0, seconds))
        }
        return short(seconds)
    }
}

/// Turns one agent progress line into the tool name and argument the pill
/// shows.
///
/// The sidecar emits `Calling opentype__bash({"command":"pandoc a.md -o a.pdf"})`
/// (`sidecar/src/agent/loop.ts`). Printing that verbatim spends the pill's one
/// mono line on `Calling opentype__` and a JSON envelope, so the parse is what
/// makes the line readable — `bash · pandoc a.md -o a.pdf`. Anything that does
/// not match returns `nil` and the caller falls back to its own copy, rather
/// than showing a half-parsed string.
enum AgentToolLine {
    struct Line: Equatable {
        let tool: String
        let summary: String
    }

    /// The argument keys worth showing, in the order they are preferred.
    /// JSON objects are unordered once decoded, so "the first argument" is not
    /// a thing that exists — this names the ones that identify the call.
    private static let preferredKeys = [
        "command", "code", "path", "file_path", "pattern", "query", "url", "name"
    ]

    static func parse(_ detail: String) -> Line? {
        let prefix = "Calling "
        guard detail.hasPrefix(prefix),
              let open = detail.firstIndex(of: "("),
              detail.hasSuffix(")")
        else { return nil }

        let rawName = String(detail[detail.index(detail.startIndex, offsetBy: prefix.count)..<open])
            .trimmingCharacters(in: .whitespaces)
        guard !rawName.isEmpty else { return nil }
        let tool = rawName.hasPrefix("opentype__")
            ? String(rawName.dropFirst("opentype__".count))
            : rawName

        let argumentsStart = detail.index(after: open)
        let argumentsEnd = detail.index(before: detail.endIndex)
        guard argumentsStart <= argumentsEnd else { return Line(tool: tool, summary: "") }
        let arguments = String(detail[argumentsStart..<argumentsEnd])

        return Line(tool: tool, summary: summarise(arguments))
    }

    private static func summarise(_ arguments: String) -> String {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "{}" else { return "" }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in preferredKeys {
                if let value = object[key] as? String, !value.isEmpty {
                    return collapse(value)
                }
            }
            if let first = object.values.compactMap({ $0 as? String }).first {
                return collapse(first)
            }
        }
        return collapse(trimmed)
    }

    /// One line, however many the argument had: the pill is a single row.
    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// A 5pt dot breathing at the handoff's 1.4s — the one animation that says
/// "still going" without claiming to know how far along it is.
private struct BreathingDot: View {
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

/// A 2pt bar for progress that has no fraction. The run reports steps taken,
/// never steps remaining, so a filled percentage would be a number we made up;
/// a sweep says "moving" and claims nothing else.
private struct IndeterminateBar: View {
    @State private var offset: CGFloat = -0.42

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Colour.borderStrong)
                Capsule()
                    .fill(DS.Colour.accent)
                    .frame(width: proxy.size.width * 0.36)
                    .offset(x: proxy.size.width * offset)
            }
            .clipShape(Capsule())
        }
        .frame(height: 2)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.4).repeatForever(autoreverses: false)
            ) {
                offset = 1.06
            }
        }
    }
}

/// 4D. The agent asking the user something mid-run (T5).
///
/// A task started by voice should be answerable without reaching for the
/// mouse, so every option carries a number and the number keys are live
/// (`OverlayController.installQuestionKeyMonitors`). The bottom row is both
/// the instruction and the escape hatch: type anything else and it goes back
/// as a custom answer.
private struct AgentQuestionCard: View {
    let detail: VoiceSurfaceState.AskingDetail
    let onAnswer: (AgentQuestionAnswerItem) -> Void
    let onStop: () -> Void

    @State private var custom = ""

    private var options: [AgentQuestionOption] { detail.question.options ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ModeTag(kind: .agent)

                Text(OpenTypeL10n.text("需要你选一下", english: "Pick one"))
                    .font(DS.Text.body(.semibold))

                Spacer(minLength: 4)

                Button(OpenTypeL10n.text("停止", english: "Stop"), action: onStop)
                    .buttonStyle(.plain)
                    .font(DS.Text.size(11.5, .medium))
                    .foregroundStyle(DS.Colour.ink(0.45))
            }

            Text(detail.question.question)
                .font(DS.Text.size(13.5))
                // 1.55 line height at 13.5pt.
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)

            if !options.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        optionRow(option, number: index + 1)
                            .overlay(alignment: .top) {
                                if index > 0 {
                                    Rectangle()
                                        .fill(DS.Colour.border)
                                        .frame(height: 0.75)
                                }
                            }
                    }
                }
                .background(
                    DS.Colour.card.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: DS.Radius.inset, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.inset, style: .continuous)
                        .strokeBorder(DS.Colour.controlBorder, lineWidth: 0.75)
                )
            }

            answerRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(
            width: VoiceSurfacePanelMetrics.asking(optionCount: options.count).width,
            alignment: .topLeading
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func optionRow(_ option: AgentQuestionOption, number: Int) -> some View {
        Button {
            onAnswer(
                AgentQuestionAnswerItem(
                    id: detail.question.id,
                    selected: [option.label],
                    custom: nil
                )
            )
        } label: {
            HStack(spacing: 10) {
                Text(option.label)
                    .font(DS.Text.mono(12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let description = option.description, !description.isEmpty {
                    Text(description)
                        .font(DS.Text.mono())
                        .foregroundStyle(DS.Colour.ink(0.4))
                        .lineLimit(1)
                }

                Text("\(number)")
                    .font(DS.Text.mono())
                    .foregroundStyle(DS.Colour.ink(0.3))
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The instruction and the "something else" field are the same row: the
    /// mockup's line reads as a placeholder because that is what it is, which
    /// keeps a custom answer reachable without a second control.
    private var answerRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "mic.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Colour.accent)

            TextField(
                OpenTypeL10n.text(
                    "按数字键，或按住 ⌥ 直接说",
                    english: "Press a number, or hold ⌥ and say it"
                ),
                text: $custom
            )
            .textFieldStyle(.plain)
            .font(DS.Text.size(12.5))
            .onSubmit(submitCustom)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            DS.Colour.inset,
            in: RoundedRectangle(cornerRadius: DS.Radius.inset, style: .continuous)
        )
    }

    private func submitCustom() {
        let text = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onAnswer(
            AgentQuestionAnswerItem(id: detail.question.id, selected: [], custom: text)
        )
    }
}

/// What a finished card offers to do next, chosen by what the result *is*.
///
/// Three generic buttons (复制 / 关闭 / 打开主窗口) answered the question "what
/// can this panel do" rather than "what would you like to do with this". A run
/// that produced a file wants to open it; an answer wants to be pushed on.
enum VoiceResultAction: Equatable {
    /// A file the run produced, openable with its default app.
    case openFile(path: String)
    case copyPath(path: String)
    /// Both of these are follow-ups in the same conversation, not new modes.
    case elaborate
    case rephrase

    var title: String {
        switch self {
        case .openFile(let path):
            let ext = (path as NSString).pathExtension.uppercased()
            guard !ext.isEmpty else {
                return OpenTypeL10n.text("打开文件", english: "Open file")
            }
            return OpenTypeL10n.text("打开 \(ext)", english: "Open \(ext)")
        case .copyPath:
            return OpenTypeL10n.text("复制路径", english: "Copy path")
        case .elaborate:
            return OpenTypeL10n.text("展开说说", english: "Say more")
        case .rephrase:
            return OpenTypeL10n.text("换个说法", english: "Put it differently")
        }
    }
}

enum VoiceResultActions {
    /// Prefers a produced file when the run left one behind, since that is the
    /// thing the user asked for; otherwise the answer's two follow-ups.
    static func actions(for card: VoiceSurfaceState.ResultCard) -> [VoiceResultAction] {
        if let path = producedPath(in: card) {
            return [.openFile(path: path), .copyPath(path: path)]
        }
        return [.elaborate, .rephrase]
    }

    /// A path the run wrote or opened, if the transcript mentions one.
    ///
    /// Reads the steps before the body: `opentype__open_file` naming a path is
    /// direct evidence of a produced file, whereas the answer's prose may just
    /// be quoting an input. Only absolute or `~`-rooted paths with an
    /// extension count, and only ones that **exist** — an answer quoting a URL
    /// path or an example filename would otherwise put a 「打开 PDF」 button on
    /// the card that opens nothing.
    static func producedPath(in card: VoiceSurfaceState.ResultCard) -> String? {
        for step in card.steps.reversed() where step.kind == .toolCall {
            guard let line = AgentToolLine.parse(step.detail),
                  line.tool.contains("open_file") || line.tool.contains("write")
            else { continue }
            if let path = existingPath(in: line.summary) { return path }
        }
        return existingPath(in: card.body)
    }

    private static func existingPath(in text: String) -> String? {
        guard let path = firstPath(in: text) else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return path
    }

    private static let pathPattern = try? NSRegularExpression(
        pattern: "(?:~|/)[^\\s\"'`,、，。()\\[\\]【】]*\\.[A-Za-z0-9]{1,6}"
    )

    private static func firstPath(in text: String) -> String? {
        guard let pathPattern else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        // The last match, not the first: a run that reads one file and writes
        // another mentions the output last.
        let matches = pathPattern.matches(in: text, range: range)
        guard let match = matches.last, let found = Range(match.range, in: text) else {
            return nil
        }
        return String(text[found])
    }
}

/// 4E. The result card the pill morphs into — 640×520, and no longer a dead
/// end.
///
/// The composer at the bottom is the point: following up used to mean
/// dismissing this, opening the main window, finding the thread and speaking
/// again, which is enough friction that people simply did not. Now the next
/// thing said or typed continues the same conversation.
private struct VoiceSurfaceCard: View {
    let card: VoiceSurfaceState.ResultCard
    let failed: Bool
    /// How long the run took, frozen when the card appeared.
    let elapsed: TimeInterval?
    /// §H's 「交给助理去做」 payload, or `nil` when the button must not be
    /// drawn — `AssistantEscalation.offered` already refuses anything but a
    /// finished ask card, so this is `nil` for every `.failed` card and most
    /// `.result` ones.
    let escalation: AssistantEscalation?
    let onClose: () -> Void
    let onCopy: (String) -> Void
    let onOpenMainWindow: () -> Void
    let onFollowUp: (String) -> Void
    let onFollowUpByVoice: () -> Void
    let onEscalate: (AssistantEscalation) -> Void

    @State private var stepsExpanded = false
    @State private var draft = ""

    /// The handoff's `max-width:78%` for the user's bubble, resolved against
    /// the card's own content width — the card is a fixed 640 with 18pt of
    /// padding either side and 4pt reserved for the scroll indicator, so the
    /// percentage has a single answer rather than needing a `GeometryReader`.
    /// Same 78% the session thread uses (`SessionsViews.SessionTurn`).
    private static let bubbleMaxWidth: CGFloat =
        (VoiceSurfacePanelMetrics.card.width - 18 * 2 - 4) * 0.78

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .dsHairline(.bottom, color: DS.Colour.border)

            content
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .dsHairline(.top, color: DS.Colour.border)
        }
        .frame(
            width: VoiceSurfacePanelMetrics.card.width,
            height: VoiceSurfacePanelMetrics.card.height,
            alignment: .topLeading
        )
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ModeTag(kind: card.kind)

            Text(failed
                ? OpenTypeL10n.text("失败", english: "Failed")
                : OpenTypeL10n.text("完成", english: "Done"))
                .font(DS.Text.body(.semibold))
                .foregroundStyle(failed ? DS.Colour.error : Color.primary)

            Spacer(minLength: 8)

            if let summary = runSummary {
                Text(summary)
                    .font(DS.Text.mono())
                    .foregroundStyle(DS.Colour.ink(0.35))
            }

            iconButton("arrow.up.forward.app", help: OpenTypeL10n.text(
                "打开主窗口", english: "Open main window"
            ), action: onOpenMainWindow)

            iconButton("xmark", help: OpenTypeL10n.text(
                "关闭", english: "Close"
            ), action: onClose)
        }
    }

    /// 「9 步 · 24.1s」 — whichever halves exist.
    private var runSummary: String? {
        var parts: [String] = []
        if !card.steps.isEmpty {
            parts.append(OpenTypeL10n.text(
                "\(card.steps.count) 步",
                english: "\(card.steps.count) steps"
            ))
        }
        if let elapsed {
            parts.append(OverlayElapsed.precise(elapsed))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DS.Colour.ink(0.4))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !card.query.isEmpty {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Text(card.query)
                            .font(DS.Text.size(12.5))
                            // 1.55 line height at 12.5pt.
                            .lineSpacing(4)
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .frame(maxWidth: Self.bubbleMaxWidth, alignment: .leading)
                            .background(DS.Colour.accent, in: UserBubbleShape())
                    }
                }

                if !card.steps.isEmpty {
                    stepLog
                }

                AssistantMarkdownView(markdown: card.body, fontSize: 13.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, 4)
        }
        .scrollIndicators(.visible)
    }

    /// The step log is one line until asked otherwise: 「执行了 9 步」 plus the
    /// tools it used. The full list is available and rarely what is wanted —
    /// the summary answers "did it do something reasonable" in a glance, which
    /// is the actual question.
    private var stepLog: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                stepsExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: stepsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.Colour.ink(0.4))
                        .frame(width: 12)
                    Text(OpenTypeL10n.text(
                        "执行了 \(card.steps.count) 步",
                        english: "Ran \(card.steps.count) steps"
                    ))
                    .font(DS.Text.caption())
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Colour.ink(0.55))

                    Spacer(minLength: 8)

                    Text(toolNames)
                        .font(DS.Text.mono())
                        .foregroundStyle(DS.Colour.ink(0.35))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if stepsExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(card.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(format: "%02d", index + 1))
                                .font(DS.Text.mono())
                                .foregroundStyle(.tertiary)
                                .frame(width: 18, alignment: .leading)
                            Text(AgentToolLine.parse(step.detail)?.tool ?? label(for: step.kind))
                                .font(DS.Text.mono())
                                .foregroundStyle(
                                    step.kind == .error ? DS.Colour.error : DS.Colour.agent
                                )
                                .frame(width: 64, alignment: .leading)
                                .lineLimit(1)
                            Text(AgentToolLine.parse(step.detail)?.summary ?? step.detail)
                                .font(DS.Text.mono())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .dsHairline(.top)
            }
        }
        // Translucent white rather than the recessed grey the other inset
        // blocks use: on the card this row sits *above* the answer rather than
        // inside it, and the handoff lifts it off the material accordingly
        // (`rgba(255,255,255,.5)`) — the same treatment the question card's
        // option list gets.
        .background(
            DS.Colour.card.opacity(0.5),
            in: RoundedRectangle(cornerRadius: DS.Radius.nested, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.nested, style: .continuous)
                .strokeBorder(DS.Colour.borderStrong, lineWidth: 0.75)
        )
    }

    private var toolNames: String {
        var seen: [String] = []
        for step in card.steps where step.kind == .toolCall {
            guard let tool = AgentToolLine.parse(step.detail)?.tool else { continue }
            if !seen.contains(tool) { seen.append(tool) }
        }
        return seen.prefix(4).joined(separator: " · ")
    }

    private func label(for kind: AgentProgressStep.Kind) -> String {
        switch kind {
        case .thinking: return "think"
        case .toolCall: return "tool"
        case .toolResult: return "result"
        case .error: return "error"
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.title) { perform(action) }
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

                if let escalation {
                    // §H: the card's exit for "I picked the wrong mode" — same
                    // action-row chrome as `actions` above, offered alongside
                    // rather than replacing them, since 展开说说/换个说法 stay
                    // useful right up to the moment this is pressed.
                    Button(OpenTypeL10n.text("交给助理去做", english: "Hand off to the assistant")) {
                        onEscalate(escalation)
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

                Spacer(minLength: 0)

                Button(OpenTypeL10n.text("复制", english: "Copy")) {
                    onCopy(card.body)
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

            composer
        }
    }

    private var actions: [VoiceResultAction] {
        VoiceResultActions.actions(for: card)
    }

    private func perform(_ action: VoiceResultAction) {
        switch action {
        case .openFile(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        case .copyPath(let path):
            onCopy(path)
        case .elaborate:
            onFollowUp(OpenTypeL10n.text("展开说说", english: "Say more about that"))
        case .rephrase:
            onFollowUp(OpenTypeL10n.text("换个说法", english: "Put that differently"))
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField(
                OpenTypeL10n.text("接着说，或按住 ⌥ 口述…", english: "Keep going, or hold ⌥ to speak…"),
                text: $draft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(DS.Text.body())
            .lineLimit(1...3)
            .onSubmit(submitDraft)
            .padding(.bottom, 5)

            Button(action: onFollowUpByVoice) {
                DS.Shadow.control(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.Colour.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            DS.Colour.card,
                            in: RoundedRectangle(cornerRadius: DS.Radius.block, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.block, style: .continuous)
                                .strokeBorder(DS.Colour.controlBorder, lineWidth: 0.75)
                        )
                )
            }
            .buttonStyle(.plain)
            .help(OpenTypeL10n.text("口述追问", english: "Dictate a follow-up"))

            Button(action: submitDraft) {
                DS.Shadow.accentControl(
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            DS.Colour.accent.opacity(draft.isEmpty ? 0.35 : 1),
                            in: RoundedRectangle(cornerRadius: DS.Radius.block, style: .continuous)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.leading, 13)
        .padding(.trailing, 9)
        .padding(.vertical, 9)
        .background(
            DS.Colour.card.opacity(0.7),
            in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
                .strokeBorder(DS.Colour.controlBorder, lineWidth: 0.75)
        )
    }

    private func submitDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        onFollowUp(text)
    }
}

/// The user's turn: rounded everywhere except the corner nearest the speaker,
/// which is what makes a bubble read as coming *from* somewhere.
///
/// Drawn by hand rather than with `UnevenRoundedRectangle`, which this app's
/// macOS 13 floor cannot rely on.
private struct UserBubbleShape: Shape {
    private let tail: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let radius = min(DS.Radius.sheet, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tail))
        path.addArc(
            center: CGPoint(x: rect.maxX - tail, y: rect.maxY - tail),
            radius: tail,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// Five bars at the handoff's 2.5pt, reacting to level. The pill's only
/// non-textual element, and the one that makes it obvious the mic is live.
///
/// `peaks` are the handoff's literal bar heights (§04 4A), read as the profile
/// at full level rather than as a static picture: the bar the design draws
/// tallest is the one that reaches the container's 16pt, and none of them ever
/// exceeds it. The previous mapping topped out at 27pt, so a loud syllable
/// pushed the waveform out of its own 16pt row and into the tag beside it —
/// `normalizedLevel` maps −55…−10 dBFS onto 0…1, and ordinary speech sits
/// around 0.6, which is well past where the old curve overflowed.
private struct LiveWaveform: View {
    let level: Double
    private let peaks: [CGFloat] = [7, 14, 16, 10, 5]
    /// What the bars settle to in silence — short enough to read as "waiting",
    /// tall enough to still read as five bars.
    private let resting: CGFloat = 4

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(peaks.enumerated()), id: \.offset) { _, peak in
                Capsule()
                    .fill(DS.Colour.accent)
                    .frame(width: 2.5, height: height(for: peak))
            }
        }
        .frame(width: 24.5, height: 16)
        .animation(.interactiveSpring(response: 0.12), value: level)
    }

    private func height(for peak: CGFloat) -> CGFloat {
        let reach = CGFloat(min(max(level, 0.15), 1))
        return resting + (peak - resting) * reach
    }
}
