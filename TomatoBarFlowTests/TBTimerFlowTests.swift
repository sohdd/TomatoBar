import XCTest
@testable import TomatoBarFlow

final class TBTimerFlowTests: XCTestCase {
    func testCompletedWorkAutomaticallyStartsDeterminedBreakByDefault() {
        var flow = TBTimerFlow()

        XCTAssertEqual(flow.handle(.startWork, workIntervalsInSet: 4, autoStartBreak: true)?.to, .working)
        XCTAssertEqual(flow.handle(.workFinished, workIntervalsInSet: 4, autoStartBreak: true)?.to,
                       .onBreak(.short))
    }

    func testCompletedWorkCanWaitForTheDeterminedBreak() {
        var flow = TBTimerFlow()

        _ = flow.handle(.startWork, workIntervalsInSet: 4, autoStartBreak: false)

        XCTAssertEqual(flow.handle(.workFinished, workIntervalsInSet: 4, autoStartBreak: false)?.to,
                       .waitingForBreak(.short))
        XCTAssertEqual(flow.handle(.startBreak, workIntervalsInSet: 4, autoStartBreak: false)?.to,
                       .onBreak(.short))
    }

    func testSkippingDeterminedBreakWaitsForWork() {
        var flow = TBTimerFlow()

        _ = flow.handle(.startWork, workIntervalsInSet: 4, autoStartBreak: false)
        _ = flow.handle(.workFinished, workIntervalsInSet: 4, autoStartBreak: false)

        XCTAssertEqual(flow.handle(.skipBreak, workIntervalsInSet: 4, autoStartBreak: false)?.to,
                       .waitingForWork)
    }

    func testFinishingOrSkippingRunningBreakAlwaysWaitsForWork() {
        var finishedFlow = TBTimerFlow()
        _ = finishedFlow.handle(.startWork, workIntervalsInSet: 4, autoStartBreak: true)
        _ = finishedFlow.handle(.workFinished, workIntervalsInSet: 4, autoStartBreak: true)

        XCTAssertEqual(finishedFlow.handle(.breakFinished,
                                           workIntervalsInSet: 4,
                                           autoStartBreak: true)?.to,
                       .waitingForWork)

        var skippedFlow = TBTimerFlow()
        _ = skippedFlow.handle(.startWork, workIntervalsInSet: 4, autoStartBreak: true)
        _ = skippedFlow.handle(.workFinished, workIntervalsInSet: 4, autoStartBreak: true)

        XCTAssertEqual(skippedFlow.handle(.skipBreak,
                                          workIntervalsInSet: 4,
                                          autoStartBreak: true)?.to,
                       .waitingForWork)
    }

    func testLongBreakIsDeterminedWhenWorkSetCompletesAndSurvivesWaiting() {
        var flow = TBTimerFlow(completedWorkIntervalsInSet: 3)

        _ = flow.handle(.startWork, workIntervalsInSet: 4, autoStartBreak: false)

        XCTAssertEqual(flow.handle(.workFinished, workIntervalsInSet: 4, autoStartBreak: false)?.to,
                       .waitingForBreak(.long))
        XCTAssertEqual(flow.handle(.startBreak, workIntervalsInSet: 4, autoStartBreak: false)?.to,
                       .onBreak(.long))
        XCTAssertEqual(flow.completedWorkIntervalsInSet, 0)
    }

    func testStoppedWorkWaitsForWorkAndResetsCurrentSetLikeExistingFlow() {
        var flow = TBTimerFlow(completedWorkIntervalsInSet: 2)

        _ = flow.handle(.startWork, workIntervalsInSet: 4, autoStartBreak: true)

        XCTAssertEqual(flow.handle(.stopWork, workIntervalsInSet: 4, autoStartBreak: true)?.to,
                       .waitingForWork)
        XCTAssertEqual(flow.completedWorkIntervalsInSet, 0)
    }
}
