import SwiftUI

@MainActor
final class HydrationService: ObservableObject {
    static let shared = HydrationService()

    @Published private(set) var glasses: Int = 0
    @Published var goal: Int = 8

    private let defaults = UserDefaults.standard
    private let keyGlasses = "NookitWaterGlasses"
    private let keyGoal = "NookitWaterGoal"
    private let keyDay = "NookitWaterDay"
    private var timer: Timer?

    private init() {
        goal = defaults.object(forKey: keyGoal) as? Int ?? 8
        glasses = defaults.object(forKey: keyGlasses) as? Int ?? 0
        if defaults.string(forKey: keyDay) != Fmt.stamp.string(from: Date()) {
            glasses = 0
            defaults.set(0, forKey: keyGlasses)
            defaults.set(Fmt.stamp.string(from: Date()), forKey: keyDay)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDay() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    var progress: Double {
        goal <= 0 ? 0 : min(1, Double(glasses) / Double(goal))
    }

    func add() {
        checkDay()
        glasses = min(glasses + 1, 30)
        defaults.set(glasses, forKey: keyGlasses)
    }

    func remove() {
        glasses = max(0, glasses - 1)
        defaults.set(glasses, forKey: keyGlasses)
    }

    func setGoal(_ value: Int) {
        goal = min(max(value, 1), 20)
        defaults.set(goal, forKey: keyGoal)
    }

    private func checkDay() {
        let today = Fmt.stamp.string(from: Date())
        if defaults.string(forKey: keyDay) != today {
            glasses = 0
            defaults.set(0, forKey: keyGlasses)
            defaults.set(today, forKey: keyDay)
        }
    }
}
