enum TBBreakKind: String, Equatable {
    case short
    case long
}

enum TBBreakStartMode: Equatable {
    case automatic
    case manual
}

enum TBTimerState: Equatable {
    case waitingForWork
    case working
    case waitingForBreak(TBBreakKind)
    case onBreak(TBBreakKind)
}

enum TBTimerEvent: Equatable {
    case startWork
    case stopWork
    case workFinished
    case startBreak
    case skipBreak
    case breakFinished
}

struct TBTimerTransition {
    let event: TBTimerEvent
    let from: TBTimerState
    let to: TBTimerState
}

struct TBTimerFlow {
    private(set) var state: TBTimerState
    private(set) var completedWorkIntervalsInSet: Int

    init(state: TBTimerState = .waitingForWork, completedWorkIntervalsInSet: Int = 0) {
        self.state = state
        self.completedWorkIntervalsInSet = completedWorkIntervalsInSet
    }

    mutating func handle(_ event: TBTimerEvent,
                         workIntervalsInSet: Int,
                         breakStartMode: TBBreakStartMode) -> TBTimerTransition?
    {
        let nextState: TBTimerState

        switch (state, event) {
        case (.waitingForWork, .startWork):
            nextState = .working
        case (.working, .stopWork):
            completedWorkIntervalsInSet = 0
            nextState = .waitingForWork
        case (.working, .workFinished):
            completedWorkIntervalsInSet += 1
            let breakKind: TBBreakKind
            if completedWorkIntervalsInSet >= workIntervalsInSet {
                breakKind = .long
                completedWorkIntervalsInSet = 0
            } else {
                breakKind = .short
            }
            nextState = breakStartMode == .automatic ? .onBreak(breakKind) : .waitingForBreak(breakKind)
        case let (.waitingForBreak(breakKind), .startBreak):
            nextState = .onBreak(breakKind)
        case (.waitingForBreak, .skipBreak), (.onBreak, .skipBreak), (.onBreak, .breakFinished):
            nextState = .waitingForWork
        default:
            return nil
        }

        let transition = TBTimerTransition(event: event, from: state, to: nextState)
        state = nextState
        return transition
    }
}
