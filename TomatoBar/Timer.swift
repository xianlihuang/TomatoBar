import Combine
import KeyboardShortcuts
import SwiftState
import SwiftUI

/// Keys used by `UserDefaults`. Keeping the original names means existing
/// installations keep their preferences after the redesign.
enum TBPreferences {
    static let stopAfterBreak = "stopAfterBreak"
    static let showTimerInMenuBar = "showTimerInMenuBar"
    static let workIntervalLength = "workIntervalLength"
    static let shortRestIntervalLength = "shortRestIntervalLength"
    static let longRestIntervalLength = "longRestIntervalLength"
    static let workIntervalsInSet = "workIntervalsInSet"
    static let overrunTimeLimit = "overrunTimeLimit"

    static let windupVolume = "windupVolume"
    static let dingVolume = "dingVolume"
    static let tickingVolume = "tickingVolume"
}

final class TBTimer: NSObject, ObservableObject {
    static let workIntervalRange = 1 ... 60
    static let shortRestIntervalRange = 1 ... 60
    static let longRestIntervalRange = 1 ... 60
    static let workIntervalsInSetRange = 1 ... 10

    // MARK: - Preferences

    @Published var stopAfterBreak: Bool {
        didSet {
            defaults.set(stopAfterBreak, forKey: TBPreferences.stopAfterBreak)
        }
    }

    @Published var showTimerInMenuBar: Bool {
        didSet {
            defaults.set(showTimerInMenuBar, forKey: TBPreferences.showTimerInMenuBar)
            updateMenuBarTitle()
        }
    }

    @Published var workIntervalLength: Int {
        didSet {
            defaults.set(workIntervalLength, forKey: TBPreferences.workIntervalLength)
        }
    }

    @Published var shortRestIntervalLength: Int {
        didSet {
            defaults.set(shortRestIntervalLength, forKey: TBPreferences.shortRestIntervalLength)
        }
    }

    @Published var longRestIntervalLength: Int {
        didSet {
            defaults.set(longRestIntervalLength, forKey: TBPreferences.longRestIntervalLength)
        }
    }

    @Published var workIntervalsInSet: Int {
        didSet {
            defaults.set(workIntervalsInSet, forKey: TBPreferences.workIntervalsInSet)
        }
    }

    // MARK: - Published state

    @Published private(set) var phase: TBStateMachineStates = .idle
    @Published private(set) var timeLeft: TimeInterval = 0
    @Published private(set) var totalDuration: TimeInterval = 0
    @Published private(set) var completedWorkIntervals = 0
    @Published private(set) var isLongRest = false

    // MARK: - Dependencies

    let player: TBPlayer

    private let defaults: UserDefaults
    private let stateMachine = TBStateMachine(state: .idle)
    private let notificationCenter = TBNotificationCenter()
    private let overrunTimeLimit: TimeInterval

    // MARK: - Timer

    private var finishTime: Date?
    private var timer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private var lastMenuBarTitle: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        workIntervalLength = Self.clamp(
            defaults.object(forKey: TBPreferences.workIntervalLength) as? Int ?? 25,
            to: Self.workIntervalRange
        )
        shortRestIntervalLength = Self.clamp(
            defaults.object(forKey: TBPreferences.shortRestIntervalLength) as? Int ?? 5,
            to: Self.shortRestIntervalRange
        )
        longRestIntervalLength = Self.clamp(
            defaults.object(forKey: TBPreferences.longRestIntervalLength) as? Int ?? 15,
            to: Self.longRestIntervalRange
        )
        workIntervalsInSet = Self.clamp(
            defaults.object(forKey: TBPreferences.workIntervalsInSet) as? Int ?? 4,
            to: Self.workIntervalsInSetRange
        )
        stopAfterBreak = defaults.object(forKey: TBPreferences.stopAfterBreak) as? Bool ?? false
        showTimerInMenuBar = defaults.object(forKey: TBPreferences.showTimerInMenuBar) as? Bool ?? true
        let overrunLimit = defaults.object(forKey: TBPreferences.overrunTimeLimit) as? Double ?? -60
        overrunTimeLimit = min(overrunLimit, -1)

        player = TBPlayer(defaults: defaults)

        super.init()

        configureStateMachine()

        KeyboardShortcuts.onKeyUp(for: .startStopTimer) { [weak self] in
            self?.startStop()
        }
        notificationCenter.setActionHandler { [weak self] action in
            self?.handleNotificationAction(action)
        }

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // `DispatchSourceTimer` does not fire while the Mac is asleep. Catch up
        // as soon as the machine wakes instead of waiting for the next tick.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onTimerTick()
        }
    }

    deinit {
        timer?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: - Derived values

    var isRunning: Bool {
        phase != .idle
    }

    var progress: Double {
        guard phase != .idle, totalDuration > 0 else {
            return 0
        }
        return min(max(1 - timeLeft / totalDuration, 0), 1)
    }

    var timeString: String {
        let seconds: Int
        switch phase {
        case .idle:
            seconds = workIntervalLength * 60
        case .work, .rest:
            seconds = Int(ceil(max(timeLeft, 0)))
        }
        return Self.format(seconds: seconds)
    }

    var sessionNumber: Int {
        let setLength = max(workIntervalsInSet, 1)
        switch phase {
        case .idle:
            return 0
        case .work:
            return min(completedWorkIntervals + 1, setLength)
        case .rest:
            return min(max(completedWorkIntervals, 1), setLength)
        }
    }

    // MARK: - Public actions

    func startStop() {
        stateMachine <-! .startStop
    }

    func skipRest() {
        stateMachine <-! .skipRest
    }

    func shutdown() {
        stopTimer()
        player.stopAll()
        updateMenuBarTitle()
    }

    // MARK: - URL scheme

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                         withReplyEvent _: NSAppleEventDescriptor)
    {
        guard let urlString = event.forKeyword(AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              url.scheme?.caseInsensitiveCompare("tomatobar") == .orderedSame,
              let command = url.host?.lowercased()
        else {
            print("url handling error: cannot parse url")
            return
        }

        switch command {
        case "startstop":
            startStop()
        case "skiprest":
            skipRest()
        case "show":
            TBStatusItem.shared?.showPopover(nil)
        case "hide":
            TBStatusItem.shared?.closePopover(nil)
        default:
            print("url handling error: unknown command \(command)")
        }
    }

    // MARK: - State machine

    private func configureStateMachine() {
        /*
         * State diagram
         *
         *                 start/stop
         *       +--------------+-------------+
         *       |              |             |
         *       |  start/stop  |  timerFired |
         *       V    |         |    |        |
         * +--------+ |  +--------+  | +--------+
         * | idle   |--->| work   |--->| rest   |
         * +--------+    +--------+    +--------+
         *   A                  A        |    |
         *   |                  |        |    |
         *   |                  +--------+    |
         *   |  timerFired (!stopAfterBreak)  |
         *   |             skipRest           |
         *   |                                |
         *   +--------------------------------+
         *      timerFired (stopAfterBreak)
         *
         */
        stateMachine.addRoutes(event: .startStop, transitions: [
            .idle => .work, .work => .idle, .rest => .idle,
        ])
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .rest])
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .idle]) { [weak self] _ in
            self?.stopAfterBreak ?? false
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .work]) { [weak self] _ in
            !(self?.stopAfterBreak ?? false)
        }
        stateMachine.addRoutes(event: .skipRest, transitions: [.rest => .work])

        /*
         * "Finish" handlers are called when a time interval ends.
         * "End" handlers are called when a time interval ends or is cancelled.
         *
         * Orders are explicit here: the work-finish handler must increment the
         * interval counter before the rest-start handler picks a long break.
         */
        stateMachine.addAnyHandler(.any => .work, order: 1) { [weak self] _ in
            self?.onWorkStart()
        }
        stateMachine.addAnyHandler(.work => .rest, order: 0) { [weak self] _ in
            self?.onWorkFinish()
        }
        stateMachine.addAnyHandler(.work => .any, order: 2) { [weak self] _ in
            self?.onWorkEnd()
        }
        stateMachine.addAnyHandler(.any => .rest, order: 3) { [weak self] _ in
            self?.onRestStart()
        }
        stateMachine.addAnyHandler(.rest => .work, order: 0) { [weak self] context in
            self?.onRestFinish(context: context)
        }
        stateMachine.addAnyHandler(.any => .idle, order: 3) { [weak self] _ in
            self?.onIdleStart()
        }
        stateMachine.addAnyHandler(.any => .any, order: 200) { context in
            logger.append(event: TBLogEventTransition(fromContext: context))
        }

        stateMachine.addErrorHandler { context in
            let event = context.event.map { "\($0)" } ?? "none"
            print("state transition ignored: \(event) (\(context.fromState) -> \(context.toState))")
        }
    }

    private func onWorkStart() {
        if isLongRest {
            completedWorkIntervals = 0
            isLongRest = false
        }

        phase = .work
        TBStatusItem.shared?.setIcon(name: .work)
        player.playWindup()
        player.startTicking()
        startTimer(seconds: max(workIntervalLength, 1) * 60)
    }

    private func onWorkFinish() {
        completedWorkIntervals += 1
        player.playDing()
    }

    private func onWorkEnd() {
        player.stopTicking()
    }

    private func onRestStart() {
        let isLong = completedWorkIntervals >= max(workIntervalsInSet, 1)
        isLongRest = isLong

        let length = isLong ? longRestIntervalLength : shortRestIntervalLength
        let body = NSLocalizedString(
            isLong ? "TBTimer.onRestStart.long.body" : "TBTimer.onRestStart.short.body",
            comment: "Break body"
        )

        phase = .rest
        TBStatusItem.shared?.setIcon(name: isLong ? .longRest : .shortRest)
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title"),
            body: body,
            category: .restStarted
        )
        startTimer(seconds: max(length, 1) * 60)
    }

    private func onRestFinish(context: TBStateMachine.Context) {
        guard context.event != .skipRest else {
            return
        }
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestFinish.title", comment: "Break is over title"),
            body: NSLocalizedString("TBTimer.onRestFinish.body", comment: "Break is over body"),
            category: .restFinished
        )
    }

    private func onIdleStart() {
        phase = .idle
        stopTimer()
        player.stopTicking()
        completedWorkIntervals = 0
        isLongRest = false
        TBStatusItem.shared?.setIcon(name: .idle)
        updateMenuBarTitle()
    }

    private func handleNotificationAction(_ action: TBNotification.Action) {
        guard action == .skipRest, phase == .rest else {
            return
        }
        skipRest()
    }

    // MARK: - Countdown

    private func startTimer(seconds: Int) {
        stopTimer()
        guard seconds > 0 else {
            return
        }

        let duration = TimeInterval(seconds)
        totalDuration = duration
        timeLeft = duration
        finishTime = Date().addingTimeInterval(duration)

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(
            deadline: .now() + .seconds(1),
            repeating: .seconds(1),
            leeway: .milliseconds(80)
        )
        source.setEventHandler { [weak self] in
            self?.onTimerTick()
        }

        timer = source
        source.resume()
        updateMenuBarTitle()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        finishTime = nil
        timeLeft = 0
        totalDuration = 0
    }

    private func onTimerTick() {
        guard let finishTime else {
            return
        }

        let remaining = finishTime.timeIntervalSinceNow
        timeLeft = max(remaining, 0)
        updateMenuBarTitle()

        guard remaining <= 0 else {
            return
        }

        // Cancel before changing state. A new timer is created by the state
        // handler for the next interval; keeping the old source alive would
        // create duplicate ticks (and duplicate transitions).
        stopTimer()

        if remaining < overrunTimeLimit {
            /*
             Ticks can be missed while the Mac sleeps. If an interval has been
             overrun by more than the limit, stop instead of starting a break
             that should have finished long ago.
             */
            stateMachine <-! .startStop
        } else {
            stateMachine <-! .timerFired
        }
    }

    private func updateMenuBarTitle() {
        let title: String? = (phase == .idle || !showTimerInMenuBar) ? nil : timeString
        guard title != lastMenuBarTitle else {
            return
        }
        lastMenuBarTitle = title
        TBStatusItem.shared?.setTitle(title: title)
    }

    // MARK: - Helpers

    static func format(seconds: Int) -> String {
        let value = max(seconds, 0)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
