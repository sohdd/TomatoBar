import XCTest
@testable import TomatoBarFlow

final class TBTimerFlowTests: XCTestCase {
    func testCompletedWorkAutomaticallyStartsDeterminedBreakByDefault() {
        var flow = TBTimerFlow()

        XCTAssertEqual(flow.handle(.startWork, workIntervalsInSet: 4, breakStartMode: .automatic)?.to, .working)
        XCTAssertEqual(flow.handle(.workFinished, workIntervalsInSet: 4, breakStartMode: .automatic)?.to,
                       .onBreak(.short))
    }

    func testCompletedWorkCanWaitForTheDeterminedBreak() {
        var flow = TBTimerFlow()

        _ = flow.handle(.startWork, workIntervalsInSet: 4, breakStartMode: .manual)

        XCTAssertEqual(flow.handle(.workFinished, workIntervalsInSet: 4, breakStartMode: .manual)?.to,
                       .waitingForBreak(.short))
        XCTAssertEqual(flow.handle(.startBreak, workIntervalsInSet: 4, breakStartMode: .manual)?.to,
                       .onBreak(.short))
    }

    func testSkippingDeterminedBreakWaitsForWork() {
        var flow = TBTimerFlow()

        _ = flow.handle(.startWork, workIntervalsInSet: 4, breakStartMode: .manual)
        _ = flow.handle(.workFinished, workIntervalsInSet: 4, breakStartMode: .manual)

        XCTAssertEqual(flow.handle(.skipBreak, workIntervalsInSet: 4, breakStartMode: .manual)?.to,
                       .waitingForWork)
    }

    func testFinishingOrSkippingRunningBreakAlwaysWaitsForWork() {
        var finishedFlow = TBTimerFlow()
        _ = finishedFlow.handle(.startWork, workIntervalsInSet: 4, breakStartMode: .automatic)
        _ = finishedFlow.handle(.workFinished, workIntervalsInSet: 4, breakStartMode: .automatic)

        XCTAssertEqual(finishedFlow.handle(.breakFinished,
                                           workIntervalsInSet: 4,
                                           breakStartMode: .automatic)?.to,
                       .waitingForWork)

        var skippedFlow = TBTimerFlow()
        _ = skippedFlow.handle(.startWork, workIntervalsInSet: 4, breakStartMode: .automatic)
        _ = skippedFlow.handle(.workFinished, workIntervalsInSet: 4, breakStartMode: .automatic)

        XCTAssertEqual(skippedFlow.handle(.skipBreak,
                                          workIntervalsInSet: 4,
                                          breakStartMode: .automatic)?.to,
                       .waitingForWork)
    }

    func testLongBreakIsDeterminedWhenWorkSetCompletesAndSurvivesWaiting() {
        var flow = TBTimerFlow(completedWorkIntervalsInSet: 3)

        _ = flow.handle(.startWork, workIntervalsInSet: 4, breakStartMode: .manual)

        XCTAssertEqual(flow.handle(.workFinished, workIntervalsInSet: 4, breakStartMode: .manual)?.to,
                       .waitingForBreak(.long))
        XCTAssertEqual(flow.handle(.startBreak, workIntervalsInSet: 4, breakStartMode: .manual)?.to,
                       .onBreak(.long))
        XCTAssertEqual(flow.completedWorkIntervalsInSet, 0)
    }

    func testStoppedWorkWaitsForWorkAndResetsCurrentSetLikeExistingFlow() {
        var flow = TBTimerFlow(completedWorkIntervalsInSet: 2)

        _ = flow.handle(.startWork, workIntervalsInSet: 4, breakStartMode: .automatic)

        XCTAssertEqual(flow.handle(.stopWork, workIntervalsInSet: 4, breakStartMode: .automatic)?.to,
                       .waitingForWork)
        XCTAssertEqual(flow.completedWorkIntervalsInSet, 0)
    }
}
