import Foundation
import SwiftUI

/// Shared execution state for a tool screen.
@MainActor
final class ToolContext: ObservableObject {
    @Published var isWorking = false
    @Published var progress: Double? = nil
    @Published var status: String = ""
    @Published var error: String? = nil
    @Published var results: [ResultFile] = []

    func begin(_ status: String = "Working…") {
        isWorking = true
        progress = nil
        error = nil
        self.status = status
    }

    func update(_ status: String, progress: Double? = nil) {
        self.status = status
        if let progress { self.progress = progress }
    }

    func finish(_ urls: [URL]) {
        isWorking = false
        progress = nil
        status = ""
        results.append(contentsOf: urls.map { ResultFile(url: $0) })
    }

    func add(_ url: URL) {
        results.append(ResultFile(url: url))
    }

    /// Errors are shown in plain English; the underlying message is appended when useful.
    func fail(_ error: Error, prefix: String = "Something went wrong.") {
        isWorking = false
        progress = nil
        status = ""
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if detail.isEmpty || detail == "The operation couldn’t be completed." {
            self.error = prefix
        } else {
            self.error = "\(prefix) \(detail)"
        }
    }

    func fail(_ message: String) {
        isWorking = false
        progress = nil
        status = ""
        self.error = message
    }

    func reset() {
        isWorking = false
        progress = nil
        status = ""
        error = nil
    }

    func clearResults() {
        results = []
    }
}

struct ResultFile: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var size: Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }
}
