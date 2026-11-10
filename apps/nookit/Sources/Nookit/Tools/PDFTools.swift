import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

struct PDFTool: View {
    enum Operation: String {
        case merge
        case split
        case extract
        case imagesToPDF
        case toImages
        case compress
        case unlock

        var slug: String {
            switch self {
            case .merge: return "merge-pdfs"
            case .split: return "split-pdf"
            case .extract: return "extract-pdf-pages"
            case .imagesToPDF: return "images-to-pdf"
            case .toImages: return "pdf-to-images"
            case .compress: return "compress-pdf"
            case .unlock: return "remove-pdf-password"
            }
        }

        var symbol: String {
            switch self {
            case .merge: return "doc.on.doc"
            case .split: return "scissors"
            case .extract: return "doc.text"
            case .imagesToPDF: return "photo.on.rectangle"
            case .toImages: return "photo.stack"
            case .compress: return "arrow.down.right.and.arrow.up.left"
            case .unlock: return "lock.open"
            }
        }

        var title: String {
            switch self {
            case .merge: return "Merge PDFs"
            case .split: return "Split PDF"
            case .extract: return "Extract PDF Pages"
            case .imagesToPDF: return "Images to PDF"
            case .toImages: return "PDF to Images"
            case .compress: return "Compress PDF"
            case .unlock: return "Remove PDF Password"
            }
        }

        var subtitle: String {
            switch self {
            case .merge: return "Combine several PDFs into one document, in the order you choose."
            case .split: return "Break a PDF into separate files by page range."
            case .extract: return "Pull selected pages out of a PDF and save them as a new document."
            case .imagesToPDF: return "Turn photos and screenshots into a single PDF."
            case .toImages: return "Render PDF pages as PNG images at the resolution you pick."
            case .compress: return "Rebuild a PDF at a lower resolution. Text-heavy files may not shrink much."
            case .unlock: return "Save a password-free copy of a PDF you can open."
            }
        }

        var acceptsPDF: Bool { self != .imagesToPDF }
        var allowsMultiple: Bool { self == .merge || self == .imagesToPDF }
    }

    let operation: Operation

    @State private var files: [URL] = []
    @State private var ranges = "1-3, 5"
    @State private var eachPage = false
    @State private var password = ""
    @State private var dpi = 144.0
    @State private var imageScale = 2.0
    @State private var preserveText = false
    @State private var working = false
    @State private var results: [URL] = []
    @State private var error: String?
    @State private var status = ""
    @EnvironmentObject private var store: ResultStore

    private var expectedExtension: String { operation == .toImages ? "png" : "pdf" }

    var body: some View {
        ToolPage(symbol: operation.symbol, title: operation.title, subtitle: operation.subtitle) {
            DropZone(
                title: operation == .imagesToPDF ? "Choose images" : "Choose a PDF",
                subtitle: operation.allowsMultiple ? "Drop files here, in the order you want them." : "Drop a file here, or click to choose.",
                allowsMultiple: operation.allowsMultiple,
                types: operation == .imagesToPDF ? [.image] : [.pdf],
                height: 110
            ) { urls in
                files = operation.allowsMultiple ? urls : Array(urls.prefix(1))
                results = []
                error = nil
            }

            if !files.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(files.enumerated()), id: \.offset) { index, url in
                            FileChip(url: url) { files.remove(at: index) }
                        }
                    }
                }
            }

            ToolCard(title: "Options") {
                options

                HStack(spacing: 10) {
                    Button(working ? "Working…" : "Run") { run() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(files.isEmpty || working)
                    if !files.isEmpty {
                        Button("Choose again…") {
                            let picked = FilePicker.files(
                                title: operation == .imagesToPDF ? "Choose images" : "Choose PDFs",
                                types: operation == .imagesToPDF ? [.image] : [.pdf],
                                allowsMultiple: operation.allowsMultiple
                            )
                            if !picked.isEmpty { files = operation.allowsMultiple ? picked : Array(picked.prefix(1)); results = []; error = nil }
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                    Spacer()
                    if !results.isEmpty {
                        Button("Reveal results") { store.reveal(results[0].deletingLastPathComponent()) }
                            .buttonStyle(QuietButtonStyle())
                    }
                }

                if !status.isEmpty { Text(status).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                if let error { InlineError(message: error) }
            }

            if !results.isEmpty {
                ToolCard(title: "Results", subtitle: "\(results.count) file\(results.count == 1 ? "" : "s") saved") {
                    VStack(spacing: 1) {
                        ForEach(results, id: \.path) { url in
                            HStack(spacing: 10) {
                                Image(systemName: url.pathExtension == "png" ? "photo" : "doc.richtext")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.ember)
                                    .frame(width: 22)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer()
                                Text(Fmt.bytes((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textTertiary)
                                Button("Open") { store.open(url) }.buttonStyle(QuietButtonStyle())
                                Button("Reveal") { store.reveal(url) }.buttonStyle(QuietButtonStyle())
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

    @ViewBuilder
    private var options: some View {
        switch operation {
        case .merge, .imagesToPDF, .toImages:
            EmptyView()
        case .split:
            HStack(spacing: 14) {
                TextField("1-3, 5", text: $ranges)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .fieldStyle()
                    .frame(width: 200)
                    .disabled(eachPage)
                Toggle("One file per page", isOn: $eachPage)
                    .toggleStyle(.checkbox)
                    .font(Theme.body)
                Spacer()
                Text(eachPage ? "Each page becomes its own PDF." : "Comma-separated pages or ranges.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        case .extract:
            HStack(spacing: 12) {
                TextField("1-3, 5", text: $ranges)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .fieldStyle()
                    .frame(width: 200)
                Text("Pages to extract, in the order you list them.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
        case .compress:
            HStack(spacing: 16) {
                Text("Resolution").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                Picker("Resolution", selection: $dpi) {
                    Text("72 dpi").tag(72.0)
                    Text("144 dpi").tag(144.0)
                    Text("200 dpi").tag(200.0)
                }
                .labelsHidden()
                .frame(width: 120)
                Toggle("Keep text selectable (less compression)", isOn: $preserveText)
                    .toggleStyle(.checkbox)
                    .font(Theme.body)
                Spacer()
            }
        case .unlock:
            HStack(spacing: 12) {
                SecureField("PDF password", text: $password)
                    .textFieldStyle(.plain)
                    .fieldStyle()
                    .frame(width: 220)
                Text("The password is used once, on this Mac, and never stored.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
        case .toImages:
            HStack(spacing: 16) {
                OptionPicker(label: "Scale", options: [("1×", 1.0), ("2×", 2.0), ("3×", 3.0)], selection: $imageScale)
                Spacer()
                Text("Each page becomes a PNG in a folder.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func run() {
        guard !files.isEmpty else { return }
        working = true
        error = nil
        results = []
        status = "Working…"
        let folder = store.datedFolder(for: operation.title)
        let files = self.files
        let op = operation
        let ranges = self.ranges
        let eachPage = self.eachPage
        let password = self.password
        let dpi = self.dpi
        let scale = self.imageScale
        let preserveText = self.preserveText

        Task {
            var saved: [URL] = []
            do {
                switch op {
                case .merge:
                    let merged = PDFDocument()
                    var pageIndex = 0
                    for url in files {
                        guard let doc = PDFDocument(url: url) else { throw ToolError.message("\(url.lastPathComponent) couldn’t be opened.") }
                        for index in 0..<doc.pageCount {
                            if let page = doc.page(at: index) {
                                merged.insert(page, at: pageIndex)
                                pageIndex += 1
                            }
                        }
                    }
                    let url = try write(merged, folder: folder, name: "merged.pdf")
                    saved = [url]
                case .split:
                    guard let first = files.first, let doc = PDFDocument(url: first) else {
                        throw ToolError.message("Choose a PDF to split.")
                    }
                    let groups = eachPage ? (0..<doc.pageCount).map { [$0] } : try pages(from: ranges, count: doc.pageCount)
                    for (offset, pages) in groups.enumerated() {
                        let part = PDFDocument()
                        for (pageOffset, index) in pages.enumerated() {
                            if let page = doc.page(at: index) { part.insert(page, at: pageOffset) }
                        }
                        let label = pages.count == 1 ? "page-\(pages[0] + 1)" : "pages-\(pages.first! + 1)-\(pages.last! + 1)"
                        saved.append(try write(part, folder: folder, name: "\(first.deletingPathExtension().lastPathComponent)-\(label)-\(offset + 1).pdf"))
                    }
                case .extract:
                    guard let first = files.first, let doc = PDFDocument(url: first) else {
                        throw ToolError.message("Choose a PDF first.")
                    }
                    let indexes = try pages(from: ranges, count: doc.pageCount).flatMap { $0 }
                    let out = PDFDocument()
                    for (offset, index) in indexes.enumerated() {
                        if let page = doc.page(at: index) { out.insert(page, at: offset) }
                    }
                    saved = [try write(out, folder: folder, name: "\(first.deletingPathExtension().lastPathComponent)-extract.pdf")]
                case .imagesToPDF:
                    let doc = PDFDocument()
                    for url in files {
                        guard let image = ImageEngine.source(url) else {
                            throw ToolError.message("\(url.lastPathComponent) couldn’t be read.")
                        }
                        let portrait = image.height >= image.width
                        let pageSize = portrait
                            ? CGSize(width: 612, height: 792)
                            : CGSize(width: 792, height: 612)
                        if let page = PDFWork.imagePage(image, size: pageSize) {
                            doc.insert(page, at: doc.pageCount)
                        }
                    }
                    guard doc.pageCount > 0 else { throw ToolError.message("No images could be read.") }
                    saved = [try write(doc, folder: folder, name: "images.pdf")]
                case .toImages:
                    guard let first = files.first, let doc = PDFDocument(url: first) else {
                        throw ToolError.message("Choose a PDF first.")
                    }
                    let out = folder.appendingPathComponent(Fmt.safeFilename(first.deletingPathExtension().lastPathComponent), isDirectory: true)
                    for index in 0..<doc.pageCount {
                        guard let page = doc.page(at: index),
                              let image = PDFWork.image(page, scale: scale) else { continue }
                        let rep = NSBitmapImageRep(cgImage: image)
                        guard let png = rep.representation(using: .png, properties: [:]) else { continue }
                        saved.append(try store.write(data: png, to: out, filename: "page-\(String(format: "%03d", index + 1)).png"))
                    }
                case .compress:
                    guard let first = files.first else { throw ToolError.message("Choose a PDF first.") }
                    let output = try compress(first, dpi: dpi, preserveText: preserveText, folder: folder)
                    saved = [output]
                case .unlock:
                    guard let first = files.first, let doc = PDFDocument(url: first) else {
                        throw ToolError.message("Choose a PDF first.")
                    }
                    if doc.isLocked {
                        guard doc.unlock(withPassword: password) else {
                            throw ToolError.message("That password didn’t unlock the document.")
                        }
                    }
                    saved = [try write(doc, folder: folder, name: "\(first.deletingPathExtension().lastPathComponent)-unlocked.pdf")]
                }
                let final = saved
                await MainActor.run {
                    working = false
                    results = final
                    status = "Saved \(final.count) file\(final.count == 1 ? "" : "s")."
                }
            } catch {
                await MainActor.run {
                    working = false
                    self.error = error.localizedDescription
                    status = ""
                }
            }
        }
    }

    private func write(_ document: PDFDocument, folder: URL, name: String) throws -> URL {
        guard let data = document.dataRepresentation() else {
            throw ToolError.message("The PDF couldn’t be written.")
        }
        return try store.write(data: data, to: folder, filename: name)
    }

    /// Parses "1-3, 5" into zero-based page index groups.
    private func pages(from text: String, count: Int) throws -> [[Int]] {
        let pieces = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !pieces.isEmpty else { throw ToolError.message("Enter at least one page or range, for example 1-3, 5.") }
        var groups: [[Int]] = []
        for piece in pieces {
            if piece.contains("-") {
                let parts = piece.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]), start > 0, end >= start else {
                    throw ToolError.message("“\(piece)” isn’t a valid range. Use numbers like 1-3.")
                }
                guard end <= count else { throw ToolError.message("This PDF only has \(count) page\(count == 1 ? "" : "s").") }
                groups.append(Array((start - 1)...(end - 1)))
            } else {
                guard let page = Int(piece), page > 0, page <= count else {
                    throw ToolError.message("Page \(piece) is outside this PDF (1–\(count)).")
                }
                groups.append([page - 1])
            }
        }
        return groups
    }

    private func compress(_ url: URL, dpi: Double, preserveText: Bool, folder: URL) throws -> URL {
        guard let doc = PDFDocument(url: url) else { throw ToolError.message("This PDF couldn’t be opened.") }
        let name = "\(url.deletingPathExtension().lastPathComponent)-compressed.pdf"

        if preserveText {
            guard let data = doc.dataRepresentation() else { throw ToolError.message("The PDF couldn’t be rewritten.") }
            return try store.write(data: data, to: folder, filename: name)
        }

        let output = PDFDocument()
        let zoom = dpi / 72.0
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = NSSize(width: bounds.width * zoom, height: bounds.height * zoom)
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.62]),
                  let compressed = NSImage(data: jpeg),
                  let newPage = PDFPage(image: compressed)
            else { continue }
            output.insert(newPage, at: index)
        }
        guard let data = output.dataRepresentation() else { throw ToolError.message("The compressed PDF couldn’t be written.") }
        return try store.write(data: data, to: folder, filename: name)
    }
}
