import SwiftUI
import AppKit

// MARK: - Job state for the additional tools

/// Small observable used by the extra tool screens. It mirrors `ToolContext`
/// but keeps the per-tool state local and simple.
@MainActor
final class JobState: ObservableObject {
    @Published var working = false
    @Published var status = ""
    @Published var error: String?
    @Published var results: [URL] = []

    func begin(_ text: String) {
        working = true
        status = text
        error = nil
        results = []
    }

    func note(_ text: String) {
        status = text
    }

    func finish(_ urls: [URL], _ text: String = "Done.") {
        working = false
        status = text
        results = urls
    }

    func fail(_ error: Error) {
        working = false
        status = ""
        self.error = MediaExport.readable(error)
    }

    func fail(_ message: String) {
        working = false
        status = ""
        error = message
    }

    func clear() {
        error = nil
        results = []
        status = ""
    }
}

// MARK: - Output list

/// Shared result list with Reveal and Open actions. Tools append to
/// `ResultStore`'s dated folder, so every file here is already saved.
struct OutputFilesCard: View {
    let title: String
    let urls: [URL]
    var symbol: String = "doc"
    var openTitle: String = "Open"
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        if !urls.isEmpty {
            ToolCard(title: title) {
                VStack(spacing: 1) {
                    ForEach(urls, id: \.path) { url in
                        HStack(spacing: 10) {
                            Image(systemName: symbol)
                                .foregroundStyle(Theme.ember)
                                .frame(width: 22)
                            Text(url.lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                            Text(Fmt.bytes((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textTertiary)
                            Button(openTitle) { store.open(url) }
                                .buttonStyle(QuietButtonStyle())
                            Button("Reveal") { store.reveal(url) }
                                .buttonStyle(QuietButtonStyle())
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.raised.opacity(0.4))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

// MARK: - Small fields

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var width: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(width: width)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.lineStrong, lineWidth: 1)
                )
        }
    }
}

struct RunBar: View {
    let title: String
    @ObservedObject var job: JobState
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(job.working ? "Working…" : title, action: action)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(disabled || job.working)
            if job.working {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(job.status.isEmpty ? "Working…" : job.status)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if !job.status.isEmpty {
                Text(job.status)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let error = job.error {
                InlineError(message: error)
            }
        }
    }
}

// MARK: - Time parsing

enum TimeText {
    /// Accepts `12`, `1:30`, `01:02:03` or `1:02:03.5`.
    static func seconds(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":")
        var values: [Double] = []
        for part in parts {
            guard let value = Double(part), value >= 0 else { return nil }
            values.append(value)
        }
        switch values.count {
        case 1: return values[0]
        case 2: return values[0] * 60 + values[1]
        case 3: return values[0] * 3600 + values[1] * 60 + values[2]
        default: return nil
        }
    }

    static func string(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = total - Double(Int(total) / 60 * 60)
        if h > 0 { return String(format: "%d:%02d:%05.2f", h, m, s) }
        return String(format: "%d:%05.2f", m, s)
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - File helpers

enum ExtraFiles {
    static func unique(_ folder: URL, _ name: String) -> URL {
        var url = folder.appendingPathComponent(Fmt.safeFilename(name))
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var attempt = 1
        while FileManager.default.fileExists(atPath: url.path), attempt < 1000 {
            let candidate = "\(base) \(attempt)"
            url = ext.isEmpty ? folder.appendingPathComponent(candidate) : folder.appendingPathComponent("\(candidate).\(ext)")
            attempt += 1
        }
        return url
    }

    static func files(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))?
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    static func size(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    static func text(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func image(_ url: URL) -> NSImage? {
        NSImage(contentsOf: url)
    }
}

// MARK: - Preview helpers

/// Renders a CGImage into a SwiftUI preview with a checkerboard behind it,
/// which makes transparency obvious.
struct CheckerImage: View {
    let image: CGImage

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .background(
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    Canvas { context, size in
                        let step: CGFloat = 10
                        for row in stride(from: 0, to: size.height, by: step) {
                            for col in stride(from: 0, to: size.width, by: step) {
                                if (Int(row / step) + Int(col / step)) % 2 == 0 {
                                    context.fill(Path(CGRect(x: col, y: row, width: step, height: step)), with: .color(.gray.opacity(0.18)))
                                }
                            }
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}
