import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

// MARK: - QR code

struct QRCodeTool: View {
    private enum Correction: String, CaseIterable, Identifiable {
        case low = "L — 7%"
        case medium = "M — 15%"
        case quartile = "Q — 25%"
        case high = "H — 30%"
        var id: String { rawValue }
        var level: String {
            switch self { case .low: return "L"; case .medium: return "M"; case .quartile: return "Q"; case .high: return "H" }
        }
    }

    @State private var text = "https://nookit.app"
    @State private var correction: Correction = .medium
    @State private var size = 512.0
    @State private var preview: NSImage?
    @State private var saved: URL?
    @State private var error: String?
    @State private var decodeInput: URL?
    @State private var decoded = ""
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "qrcode", title: "QR Code", subtitle: "Generate a QR code as a PNG, or read one from an image. Everything stays local.") {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                ToolCard(title: "Create") {
                    CodeEditor(text: $text, height: 100, placeholder: "URL or text…", monospaced: false)
                    OptionPicker(label: "Correction", options: Correction.allCases.map { ($0.rawValue, $0) }, selection: $correction)
                    HStack(spacing: 8) {
                        Text("Size").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        Slider(value: $size, in: 128...1024, step: 64)
                        Text("\(Int(size)) px").font(Theme.caption).foregroundStyle(Theme.textTertiary).frame(width: 52, alignment: .trailing)
                    }
                    HStack(spacing: 10) {
                        Button("Generate") { generate() }.buttonStyle(PrimaryButtonStyle())
                        if let saved {
                            Button("Save a copy") { saveCopy() }.buttonStyle(SecondaryButtonStyle())
                            Button("Reveal") { store.reveal(saved) }.buttonStyle(QuietButtonStyle())
                        }
                    }
                    if let error { InlineError(message: error) }
                }

                ToolCard(title: "Preview") {
                    if let preview {
                        Image(nsImage: preview)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(maxWidth: 260, maxHeight: 260)
                            .padding(14)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Your QR code appears here.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
            }

            ToolCard(title: "Read a QR code", subtitle: "Choose an image that contains a code.") {
                HStack(spacing: 10) {
                    Button("Choose image…") {
                        if let url = FilePicker.file(title: "Choose an image", types: [.image]) {
                            decodeInput = url
                            decode(url)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if let decodeInput { FileChip(url: decodeInput) { self.decodeInput = nil; decoded = "" } }
                    Spacer()
                }
                if !decoded.isEmpty {
                    HStack {
                        Text(decoded)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        CopyButton(value: decoded)
                    }
                    .padding(10)
                    .background(Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .onAppear { if preview == nil { generate() } }
    }

    private func makeImage() -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correction.level
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }

    private func generate() {
        error = nil
        preview = makeImage()
        guard let preview, let png = pngData(preview) else {
            error = "That text couldn’t be turned into a QR code."
            return
        }
        do {
            saved = try store.write(data: png, to: store.datedFolder(for: "QR Code"), filename: "qr-code.png")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveCopy() {
        guard let preview, let png = pngData(preview) else { return }
        if let url = FilePicker.save(title: "Save QR code", name: "qr-code.png", types: [.png]) {
            try? png.write(to: url)
        }
    }

    private func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func decode(_ url: URL) {
        decoded = ""
        guard let image = CIImage(contentsOf: url) else {
            error = "That image couldn’t be opened."
            return
        }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: image) ?? []
        let values = features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        if values.isEmpty {
            error = "No QR code was found in that image."
        } else {
            decoded = values.joined(separator: "\n")
        }
    }
}

// MARK: - Batch rename

struct BatchRenameTool: View {
    private struct RenameItem: Identifiable {
        let id = UUID()
        let source: URL
        let newName: String
    }

    @State private var folder: URL?
    @State private var files: [URL] = []
    @State private var pattern = "{name}-{n}"
    @State private var start = 1
    @State private var preview: [RenameItem] = []
    @State private var done: [URL] = []
    @State private var error: String?
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "character.cursor.ibeam", title: "Batch Rename", subtitle: "Rename a folder of files in one pass. The copies go to a dated folder; originals stay untouched.") {
            ToolCard(title: "Folder") {
                HStack(spacing: 10) {
                    Button("Choose folder…") {
                        if let url = FilePicker.folder(title: "Choose a folder of files") {
                            folder = url
                            load(url)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if let folder {
                        Text(folder.path).font(Theme.caption).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if !files.isEmpty { Badge(text: "\(files.count) files") }
                }
            }

            if !files.isEmpty {
                ToolCard(title: "Pattern", subtitle: "Tokens: {name} {n} {ext} {date}") {
                    HStack(spacing: 12) {
                        TextField("{name}-{n}", text: $pattern)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .fieldStyle()
                            .onChange(of: pattern) { _, _ in rebuild() }
                        Stepper("Start at \(start)", value: $start, in: 1...9999)
                            .font(Theme.body)
                            .onChange(of: start) { _, _ in rebuild() }
                        Button("Preview") { rebuild() }.buttonStyle(QuietButtonStyle())
                    }
                }

                ToolCard(title: "Preview", subtitle: "\(preview.count) files will be copied with new names.") {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(preview) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: "doc")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.textTertiary)
                                    Text(item.source.lastPathComponent)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Theme.textTertiary)
                                    Text(item.newName)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Theme.raised.opacity(0.4))
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack {
                        Button("Apply names") { apply() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(preview.isEmpty)
                        if !done.isEmpty {
                            Button("Reveal results") { store.reveal(done[0].deletingLastPathComponent()) }
                                .buttonStyle(QuietButtonStyle())
                        }
                        Spacer()
                        if !done.isEmpty { Text("\(done.count) files copied").font(Theme.caption).foregroundStyle(Theme.mint) }
                    }
                    if let error { InlineError(message: error) }
                }
            }
        }
    }

    private func load(_ url: URL) {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        files = contents.filter { (try? $0.resourceValues(forKeys: Set(keys)).isRegularFile) == true }
        rebuild()
    }

    private func rebuild() {
        done = []
        error = nil
        let date = Fmt.stamp.string(from: Date())
        preview = files.enumerated().map { index, url in
            let name = TextLogic.renamed(
                pattern: pattern,
                base: url.deletingPathExtension().lastPathComponent,
                ext: url.pathExtension,
                index: index,
                start: start,
                date: date
            )
            return RenameItem(source: url, newName: name)
        }
    }

    private func apply() {
        error = nil
        let output = store.datedFolder(for: "Batch Rename").appendingPathComponent("renamed", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var saved: [URL] = []
        do {
            for item in preview {
                let target = try store.write(data: Data(contentsOf: item.source), to: output, filename: item.newName)
                saved.append(target)
            }
            done = saved
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Zip / unzip

struct ZipUnzipTool: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case compress = "Create ZIP"
        case extract = "Extract ZIP"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .compress
    @State private var items: [URL] = []
    @State private var archive: URL?
    @State private var results: [URL] = []
    @State private var status = ""
    @State private var error: String?
    @State private var working = false
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "archivebox", title: "Zip & Unzip", subtitle: "Pack files into a ZIP or unpack one, using the archive tools built into macOS.") {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            .onChange(of: mode) { _, _ in items = []; results = []; archive = nil; error = nil }

            if mode == .compress {
                ToolCard(title: "Files to compress") {
                    HStack(spacing: 10) {
                        Button("Add files…") { items.append(contentsOf: FilePicker.files(title: "Choose files to zip")) }
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Add folder…") {
                            if let folder = FilePicker.folder(title: "Choose a folder to zip") { items.append(folder) }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Spacer()
                        if !items.isEmpty { Button("Clear") { items = [] }.buttonStyle(QuietButtonStyle()) }
                    }
                    if !items.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(Array(items.enumerated()), id: \.offset) { index, url in
                                    FileChip(url: url) { items.remove(at: index) }
                                }
                            }
                        }
                    }
                    HStack {
                        Button(working ? "Zipping…" : "Create ZIP") { compress() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(items.isEmpty || working)
                        Spacer()
                    }
                }
            } else {
                ToolCard(title: "Choose an archive") {
                    HStack(spacing: 10) {
                        Button("Choose .zip…") {
                            if let url = FilePicker.file(title: "Choose a ZIP", types: [.zip]) {
                                archive = url
                                extract(url)
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        if let archive { FileChip(url: archive) }
                        Spacer()
                        if working { ProgressView().controlSize(.small) }
                    }
                }
            }

            if !status.isEmpty { Text(status).font(Theme.body).foregroundStyle(Theme.textSecondary) }
            if let error { InlineError(message: error) }

            if !results.isEmpty {
                ResultsPanel(context: contextForResults())
            }
        }
    }

    private func contextForResults() -> ToolContext {
        let context = ToolContext()
        context.results = results.map { ResultFile(url: $0) }
        return context
    }

    private func compress() {
        guard !items.isEmpty else { return }
        working = true
        error = nil
        results = []
        status = "Preparing…"
        let folder = store.datedFolder(for: "Zip & Unzip")
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("nookit-zip-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        Task {
            defer { working = false }
            do {
                for item in items {
                    try FileManager.default.copyItem(at: item, to: staging.appendingPathComponent(item.lastPathComponent))
                }
                let name = "Archive \(Fmt.stampTime.string(from: Date())).zip"
                let target = folder.appendingPathComponent(Fmt.safeFilename(name))
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", staging.path, target.path]
                try process.run()
                process.waitUntilExit()
                try? FileManager.default.removeItem(at: staging)
                if process.terminationStatus == 0 {
                    await MainActor.run {
                        results = [target]
                        status = "Created \(target.lastPathComponent) · \(Fmt.bytes((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))"
                    }
                } else {
                    await MainActor.run { error = "ditto exited with code \(process.terminationStatus)." }
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
                try? FileManager.default.removeItem(at: staging)
            }
        }
    }

    private func extract(_ url: URL) {
        working = true
        error = nil
        results = []
        status = "Extracting…"
        let folder = store.datedFolder(for: "Zip & Unzip")
            .appendingPathComponent(Fmt.safeFilename(url.deletingPathExtension().lastPathComponent), isDirectory: true)
        Task {
            defer { working = false }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", url.path, folder.path]
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                    await MainActor.run {
                        results = contents
                        status = "Extracted \(contents.count) item\(contents.count == 1 ? "" : "s") to \(folder.lastPathComponent)."
                    }
                } else {
                    await MainActor.run { error = "The archive couldn’t be extracted (ditto \(process.terminationStatus))." }
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
    }
}
