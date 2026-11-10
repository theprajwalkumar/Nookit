import SwiftUI
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeService: ObservableObject {
    static let shared = KeepAwakeService()

    @Published private(set) var active = false
    @Published private(set) var remaining: Int = 0
    @Published private(set) var indefinite = false
    @Published var lastError: String?

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?
    private var endDate: Date?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    var statusText: String {
        if !active { return "Off" }
        if indefinite { return "On until you stop it" }
        return "On · \(Fmt.clock(remaining)) left"
    }

    func toggle(minutes: Int? = 30) {
        if active {
            stop()
        } else {
            start(minutes: minutes)
        }
    }

    func start(minutes: Int? = 30) {
        stop()
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Nookit is keeping this Mac awake" as CFString,
            &assertionID
        )
        guard status == kIOReturnSuccess else {
            lastError = "Couldn’t create the power assertion. This Mac may not allow it."
            return
        }
        active = true
        lastError = nil
        if let minutes {
            indefinite = false
            endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
            remaining = minutes * 60
        } else {
            indefinite = true
            endDate = nil
            remaining = 0
        }
    }

    func stop() {
        if active {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        active = false
        indefinite = false
        endDate = nil
        remaining = 0
    }

    private func tick() {
        guard active, let endDate else { return }
        remaining = max(0, Int(endDate.timeIntervalSinceNow))
        if remaining <= 0 { stop() }
    }
}
