import SwiftUI
import UserNotifications

enum NotchTimerMode: String, CaseIterable, Identifiable {
    case countdown
    case pomodoro
    case stopwatch

    var id: String { rawValue }
    var title: String {
        switch self {
        case .countdown: return "Countdown"
        case .pomodoro: return "Pomodoro"
        case .stopwatch: return "Stopwatch"
        }
    }
    var symbol: String {
        switch self {
        case .countdown: return "timer"
        case .pomodoro: return "circle.dotted"
        case .stopwatch: return "stopwatch"
        }
    }
}

@MainActor
final class TimerService: ObservableObject {
    static let shared = TimerService()

    @Published private(set) var mode: NotchTimerMode = .countdown
    @Published private(set) var running = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var pomodoroFocus = true
    @Published var countdownMinutes: Int = 10
    @Published var focusMinutes: Int = 25
    @Published var breakMinutes: Int = 5

    private var endDate: Date?
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0
    private var ticker: Timer?
    private var notificationsRequested = false

    private init() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
    }

    // MARK: - Control

    func startCountdown(minutes: Int? = nil) {
        if let minutes { countdownMinutes = max(1, minutes) }
        mode = .countdown
        total = TimeInterval(max(1, countdownMinutes) * 60)
        remaining = total
        endDate = Date().addingTimeInterval(total)
        running = true
        requestNotificationsIfNeeded()
    }

    func startPomodoro() {
        mode = .pomodoro
        pomodoroFocus = true
        total = TimeInterval(max(1, focusMinutes) * 60)
        remaining = total
        endDate = Date().addingTimeInterval(total)
        running = true
        requestNotificationsIfNeeded()
    }

    func startStopwatch() {
        mode = .stopwatch
        elapsed = 0
        accumulated = 0
        startedAt = Date()
        running = true
    }

    func pauseOrResume() {
        switch mode {
        case .stopwatch:
            if running {
                accumulated = elapsed
                startedAt = nil
                running = false
            } else {
                startedAt = Date()
                running = true
            }
        case .countdown, .pomodoro:
            if running {
                if let endDate { remaining = max(0, endDate.timeIntervalSinceNow) }
                self.endDate = nil
                running = false
            } else {
                guard remaining > 0 else { return }
                endDate = Date().addingTimeInterval(remaining)
                running = true
                requestNotificationsIfNeeded()
            }
        }
    }

    func reset() {
        running = false
        endDate = nil
        startedAt = nil
        accumulated = 0
        elapsed = 0
        remaining = total
        if mode == .stopwatch { elapsed = 0 }
    }

    func stop() {
        running = false
        endDate = nil
        startedAt = nil
    }

    // MARK: - Display

    var display: String {
        switch mode {
        case .stopwatch:
            return Fmt.clock(Int(elapsed))
        case .countdown:
            return Fmt.clock(Int(ceil(max(0, remaining))))
        case .pomodoro:
            return Fmt.clock(Int(ceil(max(0, remaining))))
        }
    }

    var label: String {
        switch mode {
        case .stopwatch: return running ? "Stopwatch" : "Stopwatch paused"
        case .countdown: return running ? "Countdown" : (remaining == 0 ? "Done" : "Countdown paused")
        case .pomodoro: return pomodoroFocus ? "Focus" : "Break"
        }
    }

    var collapsedText: String? {
        if running { return "\(label) · \(display)" }
        if mode == .countdown && remaining == 0 { return "Timer done" }
        return nil
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    // MARK: - Tick

    private func tick() {
        guard running else { return }
        let now = Date()
        switch mode {
        case .stopwatch:
            if let startedAt { elapsed = accumulated + now.timeIntervalSince(startedAt) }
        case .countdown, .pomodoro:
            guard let endDate else { return }
            remaining = max(0, endDate.timeIntervalSince(now))
            if remaining <= 0 {
                completePhase()
            }
        }
    }

    private func completePhase() {
        if mode == .pomodoro {
            if pomodoroFocus {
                notify(title: "Focus done", body: "Take a \(breakMinutes)-minute break.")
                pomodoroFocus = false
                total = TimeInterval(max(1, breakMinutes) * 60)
                remaining = total
                endDate = Date().addingTimeInterval(total)
                running = true
            } else {
                notify(title: "Break over", body: "Ready for another \(focusMinutes)-minute focus block?")
                running = false
                remaining = 0
                endDate = nil
            }
        } else {
            notify(title: "Timer finished", body: "Your \(countdownMinutes)-minute countdown is done.")
            running = false
            remaining = 0
            endDate = nil
        }
    }

    private func requestNotificationsIfNeeded() {
        guard !notificationsRequested else { return }
        notificationsRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        NSSound.beep()
    }
}
