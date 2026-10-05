import KeyboardShortcuts
import SwiftUI

class TBTimer: ObservableObject {
    @AppStorage("autoStartBreak") var autoStartBreak = true
    @AppStorage("showTimerInMenuBar") var showTimerInMenuBar = true
    @AppStorage("workIntervalLength") var workIntervalLength = 25
    @AppStorage("shortRestIntervalLength") var shortRestIntervalLength = 5
    @AppStorage("longRestIntervalLength") var longRestIntervalLength = 15
    @AppStorage("workIntervalsInSet") var workIntervalsInSet = 4
    @AppStorage("currentWorkContent") var currentWorkContent = ""
    // This preference is "hidden"
    @AppStorage("overrunTimeLimit") var overrunTimeLimit = -60.0

    private var flow = TBTimerFlow()
    public let player = TBPlayer()
    private var notificationCenter = TBNotificationCenter()
    let workStore = TBWorkStore()
    private var finishTime: Date?
    private var workStartedAt: Date?
    private var lockedWorkContent: String?
    private var lockedWorkDurationMinutes: Int?
    private var workStartCalendar: Calendar?
    private var timerFormatter = DateComponentsFormatter()
    @Published private(set) var state: TBTimerState = .waitingForWork
    @Published var timeLeftString: String = ""
    @Published var timer: DispatchSourceTimer?

    init() {
        timerFormatter.unitsStyle = .positional
        timerFormatter.allowedUnits = [.minute, .second]
        timerFormatter.zeroFormattingBehavior = .pad

        KeyboardShortcuts.onKeyUp(for: .startStopTimer, action: startStop)
        notificationCenter.setActionHandler(handler: onNotificationAction)

        let aem: NSAppleEventManager = NSAppleEventManager.shared()
        aem.setEventHandler(self,
                            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                            forEventClass: AEEventClass(kInternetEventClass),
                            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                 withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.forKeyword(AEKeyword(keyDirectObject))?.stringValue else {
            print("url handling error: cannot get url")
            return
        }
        let url = URL(string: urlString)
        guard url != nil,
              let scheme = url!.scheme,
              let host = url!.host else {
            print("url handling error: cannot parse url")
            return
        }
        guard scheme.caseInsensitiveCompare("tomatobar") == .orderedSame else {
            print("url handling error: unknown scheme \(scheme)")
            return
        }
        switch host.lowercased() {
        case "startstop":
            startStop()
        default:
            print("url handling error: unknown command \(host)")
            return
        }
    }

    func startStop() {
        switch state {
        case .waitingForWork:
            transition(.startWork)
        case .working:
            transition(.stopWork)
        case .waitingForBreak:
            transition(.startBreak)
        case .onBreak:
            transition(.skipBreak)
        }
    }

    func startBreak() {
        transition(.startBreak)
    }

    func skipBreak() {
        transition(.skipBreak)
    }

    func updateTimeLeft() {
        guard let finishTime = finishTime else {
            timeLeftString = ""
            TBStatusItem.shared.setTitle(title: nil)
            return
        }
        timeLeftString = timerFormatter.string(from: Date(), to: finishTime) ?? "00:00"
        if timer != nil, showTimerInMenuBar {
            TBStatusItem.shared.setTitle(title: timeLeftString)
        } else {
            TBStatusItem.shared.setTitle(title: nil)
        }
    }

    private func startTimer(seconds: Int) {
        finishTime = Date().addingTimeInterval(TimeInterval(seconds))

        let queue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer!.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer!.setEventHandler(handler: onTimerTick)
        timer!.setCancelHandler(handler: onTimerCancel)
        timer!.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        finishTime = nil
    }

    private func onTimerTick() {
        /* Cannot publish updates from background thread */
        DispatchQueue.main.async { [self] in
            updateTimeLeft()
            guard let finishTime = finishTime else {
                return
            }
            let timeLeft = finishTime.timeIntervalSince(Date())
            if timeLeft <= 0 {
                /*
                 Ticks can be missed during the machine sleep.
                 Stop the timer if it goes beyond an overrun time limit.
                 */
                if timeLeft < overrunTimeLimit {
                    switch state {
                    case .working:
                        transition(.stopWork)
                    case .onBreak:
                        transition(.skipBreak)
                    default:
                        break
                    }
                } else {
                    switch state {
                    case .working:
                        transition(.workFinished)
                    case .onBreak:
                        transition(.breakFinished)
                    default:
                        break
                    }
                }
            }
        }
    }

    private func onTimerCancel() {
        DispatchQueue.main.async { [self] in
            updateTimeLeft()
        }
    }

    private func onNotificationAction(action: TBNotification.Action) {
        switch action {
        case .skipBreak where state.isBreakRelated:
            skipBreak()
        default:
            break
        }
    }

    private func transition(_ event: TBTimerEvent) {
        guard let transition = flow.handle(event,
                                           workIntervalsInSet: workIntervalsInSet,
                                           breakStartMode: autoStartBreak ? .automatic : .manual) else {
            return
        }

        state = transition.to

        if transition.from.isWaitingForBreak || transition.from == .waitingForWork {
            TBStatusItem.shared.dismissCompletionPrompt()
        }

        if transition.from == .working {
            if transition.event == .workFinished {
                onWorkFinish()
            }
            onWorkEnd()
        }

        switch transition.to {
        case .working:
            onWorkStart()
        case let .waitingForBreak(breakKind):
            onWaitingForBreak(breakKind)
        case let .onBreak(breakKind):
            onBreakStart(breakKind, notify: transition.from == .working)
        case .waitingForWork:
            if transition.from.isOnBreak, transition.event == .breakFinished {
                onBreakFinish()
            }
            onWaitingForWork()
        }

        logger.append(event: TBLogEventTransition(transition: transition))
    }

    private func onWorkStart() {
        let workContent = TBWorkContent.lock(
            currentWorkContent,
            uncategorized: NSLocalizedString("WorkView.uncategorized", comment: "Uncategorized work content")
        )
        currentWorkContent = workContent.current
        lockedWorkContent = workContent.recorded
        workStartedAt = Date()
        lockedWorkDurationMinutes = workIntervalLength
        workStartCalendar = .current

        TBStatusItem.shared.setIcon(name: .work)
        player.playWindup()
        player.startTicking()
        startTimer(seconds: workIntervalLength * 60)
    }

    private func onWorkFinish() {
        if let content = lockedWorkContent,
           let startedAt = workStartedAt,
           let endedAt = finishTime,
           let durationMinutes = lockedWorkDurationMinutes,
           let calendar = workStartCalendar
        {
            workStore.completeWork(
                content: content,
                startedAt: startedAt,
                endedAt: endedAt,
                durationMinutes: durationMinutes,
                calendar: calendar
            )
        }
        player.playDing()
    }

    private func onWorkEnd() {
        player.stopTicking()
        stopTimer()
        lockedWorkContent = nil
        workStartedAt = nil
        lockedWorkDurationMinutes = nil
        workStartCalendar = nil
    }

    private func onWaitingForBreak(_ breakKind: TBBreakKind) {
        let presentation = breakPresentation(for: breakKind)
        TBStatusItem.shared.showBreakPrompt(
            message: presentation.body,
            startBreak: { [weak self] in self?.startBreak() },
            skipBreak: { [weak self] in self?.skipBreak() }
        )
        TBStatusItem.shared.setIcon(name: presentation.icon)
    }

    private func onBreakStart(_ breakKind: TBBreakKind, notify: Bool) {
        let presentation = breakPresentation(for: breakKind)
        if notify {
            notificationCenter.send(
                title: NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title"),
                body: presentation.body,
                category: .breakStarted
            )
        }
        TBStatusItem.shared.setIcon(name: presentation.icon)
        startTimer(seconds: presentation.length * 60)
    }

    private func onBreakFinish() {
        player.playDing()
        TBStatusItem.shared.showWorkPrompt(startWork: { [weak self] in self?.transition(.startWork) })
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestFinish.title", comment: "Break is over title"),
            body: NSLocalizedString("TBTimer.onRestFinish.body", comment: "Break is over body"),
            category: .breakFinished
        )
    }

    private func onWaitingForWork() {
        stopTimer()
        TBStatusItem.shared.setIcon(name: .idle)
    }

    private func breakPresentation(for breakKind: TBBreakKind) -> (body: String, length: Int, icon: NSImage.Name) {
        switch breakKind {
        case .short:
            return (
                NSLocalizedString("TBTimer.onRestStart.short.body", comment: "Short break body"),
                shortRestIntervalLength,
                .shortRest
            )
        case .long:
            return (
                NSLocalizedString("TBTimer.onRestStart.long.body", comment: "Long break body"),
                longRestIntervalLength,
                .longRest
            )
        }
    }
}

private extension TBTimerState {
    var isWaitingForBreak: Bool {
        if case .waitingForBreak = self { return true }
        return false
    }

    var isOnBreak: Bool {
        if case .onBreak = self { return true }
        return false
    }

    var isBreakRelated: Bool {
        isWaitingForBreak || isOnBreak
    }
}
