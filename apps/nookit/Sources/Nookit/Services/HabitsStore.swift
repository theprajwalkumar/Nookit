import SwiftUI

struct Habit: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var days: Set<String>

    var todayKey: String { Fmt.stamp.string(from: Date()) }
    var doneToday: Bool { days.contains(todayKey) }

    var streak: Int {
        let calendar = Calendar.current
        var streak = 0
        var day = Date()
        let formatter = Fmt.stamp
        // Allow the streak to start yesterday if today isn't checked yet.
        if !days.contains(formatter.string(from: day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        while days.contains(formatter.string(from: day)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            if streak > 3650 { break }
        }
        return streak
    }
}

@MainActor
final class HabitsStore: ObservableObject {
    static let shared = HabitsStore()

    @Published private(set) var habits: [Habit] = []

    private let url = AppPaths.supportFile("habits.json")

    private init() { load() }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        habits.append(Habit(id: UUID(), title: trimmed, days: []))
        save()
    }

    func toggleToday(_ id: UUID) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = Fmt.stamp.string(from: Date())
        if habits[index].days.contains(key) {
            habits[index].days.remove(key)
        } else {
            habits[index].days.insert(key)
        }
        save()
    }

    func delete(_ id: UUID) {
        habits.removeAll { $0.id == id }
        save()
    }

    var bestStreak: Int { habits.map(\.streak).max() ?? 0 }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Habit].self, from: data) else { return }
        habits = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(habits) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
