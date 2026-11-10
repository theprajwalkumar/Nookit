import Foundation
import AppKit
import UniformTypeIdentifiers

final class ResultStore: ObservableObject {
    static let shared = ResultStore()

    @Published var outputRoot: URL
    @Published var revealOnSave: Bool = true

    private let keyRoot = "NookitOutputRoot"
    private let keyReveal = "NookitRevealOnSave"

    init() {
        if let saved = UserDefaults.standard.string(forKey: keyRoot), let url = URL(string: saved) {
            // If it exists or can be created, use it; otherwise fall back to Downloads/Nookit.
            self.outputRoot = url
        } else {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            self.outputRoot = downloads.appendingPathComponent("Nookit", isDirectory: true)
        }
        self.revealOnSave = UserDefaults.standard.object(forKey: keyReveal) as? Bool ?? true
        try? FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
    }

    func setRoot(_ url: URL) {
        outputRoot = url
        UserDefaults.standard.set(url.absoluteString, forKey: keyRoot)
    }

    func setReveal(_ value: Bool) {
        revealOnSave = value
        UserDefaults.standard.set(value, forKey: keyReveal)
    }

    /// Returns a new dated folder for a tool run: `~/Downloads/Nookit/<yyyy-MM-dd> <Tool Name>/`
    func datedFolder(for toolName: String) -> URL {
        let day = Fmt.stamp.string(from: Date())
        let name = Fmt.safeFilename("\(day) \(toolName)")
        let folder = outputRoot.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes data to a unique file in the folder, returns the URL. Never overwrites existing files.
    func write(data: Data, to folder: URL, filename: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder.appendingPathComponent(Fmt.safeFilename(filename))
        if FileManager.default.fileExists(atPath: url.path) {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            var attempt = 0
            while FileManager.default.fileExists(atPath: url.path) && attempt < 50 {
                attempt += 1
                let candidate = "\(base) \(attempt)"
                url = ext.isEmpty ? folder.appendingPathComponent(candidate) : folder.appendingPathComponent("\(candidate).\(ext)")
            }
        }
        try data.write(to: url, options: .atomic)
        if revealOnSave {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        return url
    }

    func write(string: String, to folder: URL, filename: String, encoding: String.Encoding = .utf8) throws -> URL {
        guard let data = string.data(using: encoding) else {
            throw NSError(domain: "Nookit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn’t encode text."])
        }
        return try write(data: data, to: folder, filename: filename)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
