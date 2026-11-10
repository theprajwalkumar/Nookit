import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePicker {
    static func files(title: String = "Choose files", types: [UTType]? = nil, allowsMultiple: Bool = true) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowsMultiple
        panel.canCreateDirectories = false
        if let types { panel.allowedContentTypes = types }
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func file(title: String = "Choose a file", types: [UTType]? = nil) -> URL? {
        files(title: title, types: types, allowsMultiple: false).first
    }

    static func folder(title: String = "Choose a folder", prompt: String = "Choose") -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func save(title: String = "Save", name: String = "Untitled", types: [UTType]? = nil) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = name
        if let types, let first = types.first { panel.allowedContentTypes = [first] }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

enum DropHandler {
    /// Extracts file URLs from a SwiftUI drop provider set.
    static func fileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else if let string = item as? String {
                    url = URL(string: string)
                }
                if let url {
                    lock.lock(); urls.append(url); lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            completion(urls)
        }
    }
}
