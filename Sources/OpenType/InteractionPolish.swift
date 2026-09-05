import Foundation

/// Capture at microphone-down, not after ASR: changing the visible thread
/// while recognition runs must never redirect a spoken follow-up.
struct ConversationRecordingTarget: Equatable {
    let conversation: FocusedConversation
    var mode: InputMode { conversation.kind == .ask ? .ask : .agent }
    var conversationID: Int { conversation.id }
    func route(_ transcript: String) -> RoutedTranscript {
        RoutedTranscript(mode: mode, text: transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    var placeholder: String {
        conversation.kind == .ask
            ? OpenTypeL10n.text("继续提问…", english: "Ask a follow-up…")
            : OpenTypeL10n.text("补充要求，或交代下一步…", english: "Add details or describe the next step…")
    }
}

/// A presentation scope only. Keep the shared event store intact for memory
/// and conversations; use the same scope for list, search, export and badge.
enum DictationHistory {
    static func entries(in all: [HistoryEntry]) -> [HistoryEntry] {
        all.filter { $0.mode == .transcribe }
    }

    static func isConfirmedEmpty(_ state: HistoryLoadState) -> Bool {
        guard case .loaded(let all) = state else { return false }
        return entries(in: all).isEmpty
    }
}

enum DeliveryFeedback {
    /// Retiring routine feedback does NOT close the correction window.
    /// Learning/alias undo buttons retain the full interaction interval.
    static func visibleSeconds(correctionSeconds: TimeInterval, hasActions: Bool) -> TimeInterval {
        hasActions ? correctionSeconds : min(2, correctionSeconds)
    }
}
