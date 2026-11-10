import SwiftUI
import AppKit
import Combine

struct ClipItem: Codable, Identifiable, Hashable {
    let id: UUID
    let text: String
    let date: Date
    let source: String

    var preview: String {
        text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()

    @Published private(set) var items: [ClipItem] = []

    private let defaults = UserDefaults.standard
    private let storageKey = "NookitClipboardHistory"
    private let limit = 50
    private let blocked = ["1password", "bitwarden", "keychain", "lastpass", "dashlane", "keeper"]

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    private init() {
        load()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() ?? ""
        if blocked.contains(where: { bundle.contains($0) }) { return }

        guard
            let string = pasteboard.string(forType: .string),
            !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            string.count < 40_000
        else { return }

        if items.first?.text == string { return }

        let item = ClipItem(
            id: UUID(),
            text: string,
            date: Date(),
            source: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        )
        items.insert(item, at: 0)
        if items.count > limit { items = Array(items.prefix(limit)) }
        save()
    }

    func copy(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        save()
    }

    func clear() {
        items = []
        save()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
