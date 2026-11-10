import SwiftUI
import EventKit
import Combine

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    @Published private(set) var loading = false
    @Published var error: String?

    private let store = EKEventStore()
    private var timer: Timer?

    private init() {
        checkStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func checkStatus() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            authorized = true
            denied = false
            refresh()
        case .denied, .restricted, .writeOnly:
            authorized = false
            denied = true
        default:
            authorized = false
            denied = false
        }
    }

    func requestAccess() async {
        loading = true
        error = nil
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorized = granted
            denied = !granted
            if granted { refresh() }
        } catch {
            self.error = "Calendar access failed: \(error.localizedDescription)"
            denied = true
        }
        loading = false
    }

    func refresh() {
        guard authorized else { return }
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-300), end: end, calendars: nil)
        let found = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
        events = Array(found.prefix(3))
    }

    var nextEvent: EKEvent? { events.first }

    var nextEventText: String? {
        guard let next = nextEvent else { return nil }
        let minutes = Int(next.startDate.timeIntervalSinceNow / 60)
        if minutes <= 0 { return "Now · \(next.title ?? "Event")" }
        if minutes < 60 { return "In \(minutes)m · \(next.title ?? "Event")" }
        return "\(Fmt.shortDate(next.startDate)) · \(next.title ?? "Event")"
    }

    func join(_ event: EKEvent) {
        if let url = event.url {
            NSWorkspace.shared.open(url)
        }
    }

    func openInCalendar() {
        if let url = URL(string: "ical://") { NSWorkspace.shared.open(url) }
    }
}
