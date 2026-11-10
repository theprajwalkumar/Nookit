import SwiftUI

struct NotchTask: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var done: Bool
    var createdAt: Date
}

@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    @Published private(set) var tasks: [NotchTask] = []

    private let url = AppPaths.supportFile("tasks.json")

    private init() { load() }

    var openCount: Int { tasks.filter { !$0.done }.count }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.insert(NotchTask(id: UUID(), title: trimmed, done: false, createdAt: Date()), at: 0)
        save()
    }

    func toggle(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].done.toggle()
        save()
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func clearDone() {
        tasks.removeAll { $0.done }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([NotchTask].self, from: data) else { return }
        tasks = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tasks) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
