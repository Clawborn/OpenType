import XCTest
@testable import OpenType

final class InteractionPolishTests: XCTestCase {
    func testConversationRecordingKeepsItsOwnModeAndID() {
        let ask = ConversationRecordingTarget(conversation: .init(id: 17, kind: .ask))
        let agent = ConversationRecordingTarget(conversation: .init(id: 28, kind: .agent))
        XCTAssertEqual(ask.mode, .ask)
        XCTAssertEqual(ask.conversationID, 17)
        XCTAssertEqual(agent.mode, .agent)
        XCTAssertEqual(agent.conversationID, 28)
        XCTAssertFalse(ask.placeholder.contains("⌥"))
        XCTAssertEqual(ask.route("  执行任务：打开一个文件  "),
                       RoutedTranscript(mode: .ask, text: "执行任务：打开一个文件"))
        XCTAssertEqual(agent.route("问答：这个词什么意思"),
                       RoutedTranscript(mode: .agent, text: "问答：这个词什么意思"))
    }

    func testDictationScopeExcludesAnswersWithoutDeletingSharedHistory() {
        let entries = [entry(1, .ask), entry(2, .transcribe), entry(3, .agent), entry(4, .transcribe)]
        XCTAssertEqual(DictationHistory.entries(in: entries).map(\.id), [2, 4])
        XCTAssertEqual(entries.count, 4)
        XCTAssertTrue(DictationHistory.isConfirmedEmpty(.loaded([entry(1, .ask)])))
        XCTAssertFalse(DictationHistory.isConfirmedEmpty(.unavailable(lastKnown: [])))
        XCTAssertFalse(DictationHistory.isConfirmedEmpty(.notYetLoaded))
    }

    func testRoutineDeliveryRetiresEarlyButInteractiveUndoKeepsItsTime() {
        XCTAssertEqual(DeliveryFeedback.visibleSeconds(correctionSeconds: 8, hasActions: false), 2)
        XCTAssertEqual(DeliveryFeedback.visibleSeconds(correctionSeconds: 8, hasActions: true), 8)
        XCTAssertEqual(DeliveryFeedback.visibleSeconds(correctionSeconds: 1, hasActions: false), 1)
    }

    private func entry(_ id: Int, _ mode: InputMode) -> HistoryEntry {
        HistoryEntry(id: id, createdAt: Date(), mode: mode, applicationName: "Test",
                     transcript: "原话", result: "结果", contextPreview: nil)
    }
}
