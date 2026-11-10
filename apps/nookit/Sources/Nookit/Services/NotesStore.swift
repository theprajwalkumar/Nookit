import SwiftUI

struct Note: Identifiable, Hashable {
    let id: UUID
    var content: String
    var modified: Date

    var title: String {
        let first = content.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
        let title = first?.trimmingCharacters(in: .whitespaces) ?? ""
        return title.isEmpty ? "Untitled note" : String(title.prefix(48))
    }

    var preview: String {
        content.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published private(set) var notes: [Note] = []
    @Published var selectedID: UUID?

    private let folder = AppPaths.supportFolder("Notes")
    private let stamp = ISO8601DateFormatter()

    private init() {
        load()
        if selectedID == nil { selectedID = notes.first?.id }
    }

    func load() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var loaded: [Note] = []
        for url in urls where url.pathExtension.lowercased() == "md" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            loaded.append(Note(id: id, content: content, modified: values?.contentModificationDate ?? .distantPast))
        }
        notes = loaded.sorted { $0.modified > $1.modified }
    }

    @discardableResult
    func create() -> Note {
        let note = Note(id: UUID(), content: "", modified: Date())
        notes.insert(note, at: 0)
        selectedID = note.id
        persist(note)
        return note
    }

    func update(_ id: UUID, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].content = content
        notes[index].modified = Date()
        persist(notes[index])
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(id))
        if selectedID == id { selectedID = notes.first?.id }
    }

    func note(_ id: UUID?) -> Note? {
        guard let id else { return nil }
        return notes.first { $0.id == id }
    }

    private func fileURL(_ id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).md")
    }

    private func persist(_ note: Note) {
        try? note.content.write(to: fileURL(note.id), atomically: true, encoding: .utf8)
    }
}
