import SwiftUI
import AppKit
import PDFKit
import Vision
import UniformTypeIdentifiers

// MARK: - PDF helpers

enum PDFWork {
    static func open(_ url: URL) -> PDFDocument? {
        PDFDocument(url: url)
    }

    static func save(_ document: PDFDocument, folder: URL, name: String, store: ResultStore) throws -> URL {
        guard let data = document.dataRepresentation() else {
            throw ToolError.message("The PDF couldn’t be written.")
        }
        return try store.write(data: data, to: folder, filename: name)
    }

    static func displaySize(_ page: PDFPage) -> CGSize {
        let bounds = page.bounds(for: .mediaBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        if rotation == 90 || rotation == 270 {
            return CGSize(width: bounds.height, height: bounds.width)
        }
        return bounds.size
    }

    /// Renders a page to an image at the requested scale. PDFKit handles the
    /// page rotation, so the result is what the reader sees.
    static func image(_ page: PDFPage, scale: CGFloat = 2) -> CGImage? {
        let size = displaySize(page)
        guard size.width > 0, size.height > 0 else { return nil }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let thumbnail = page.thumbnail(of: target, for: .mediaBox)
        var rect = CGRect(origin: .zero, size: thumbnail.size)
        return thumbnail.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func rasterizedPage(_ page: PDFPage, scale: CGFloat = 2) -> PDFPage? {
        guard let image = image(page, scale: scale) else { return nil }
        let size = displaySize(page)
        let ns = NSImage(cgImage: image, size: size)
        guard let copy = PDFPage(image: ns) else { return nil }
        copy.setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
        copy.rotation = 0
        return copy
    }

    static func flatten(_ document: PDFDocument) -> PDFDocument {
        let result = PDFDocument()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let copy = rasterizedPage(page) else { continue }
            result.insert(copy, at: result.pageCount)
        }
        return result
    }

    /// Fits an image on a printable page without stretching it.
    static func imagePage(_ image: CGImage, size: CGSize) -> PDFPage? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        context.draw(image, in: CGRect(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        ))
        context.endPDFPage()
        context.closePDF()
        return PDFDocument(data: data as Data)?.page(at: 0)
    }

    /// Returns a copy of `document` with the given zero-based pages removed.
    static func removing(_ document: PDFDocument, pages: Set<Int>) -> PDFDocument {
        let result = PDFDocument()
        for index in 0..<document.pageCount where !pages.contains(index) {
            if let page = document.page(at: index)?.copy() as? PDFPage {
                result.insert(page, at: result.pageCount)
            }
        }
        return result
    }

    /// Builds a document from pages in the supplied order, applying an
    /// additional rotation on top of each page’s existing rotation.
    static func assemble(_ pages: [(page: PDFPage, rotation: Int)]) -> PDFDocument {
        let result = PDFDocument()
        for entry in pages {
            guard let page = entry.page.copy() as? PDFPage else { continue }
            page.rotation = ((page.rotation + entry.rotation) % 360 + 360) % 360
            result.insert(page, at: result.pageCount)
        }
        return result
    }

    /// Rasterises only the pages that carry redaction marks, so marked words
    /// are genuinely gone while untouched pages keep their text layer.
    static func redact(_ document: PDFDocument, marks: [Int: [Mark]]) -> PDFDocument {
        let result = PDFDocument()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let pageMarks = marks[index] ?? []
            if pageMarks.isEmpty {
                if let copy = page.copy() as? PDFPage {
                    result.insert(copy, at: result.pageCount)
                }
            } else if let image = image(page, scale: 2),
                      let redacted = ImageMarkRenderer.render(image, marks: pageMarks, redact: true) {
                let size = displaySize(page)
                let ns = NSImage(cgImage: redacted, size: size)
                if let copy = PDFPage(image: ns) {
                    copy.setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
                    copy.rotation = 0
                    result.insert(copy, at: result.pageCount)
                }
            }
        }
        return result
    }

    /// PDF access-permission bits. High-quality printing implies low-quality
    /// printing, so only the higher bit is set.
    static func permissions(allowPrinting: Bool, allowCopying: Bool) -> UInt {
        var value: UInt = 0
        if allowPrinting { value |= 1 << 1 }
        if allowCopying { value |= 1 << 4 }
        return value
    }

    static func encrypt(
        _ document: PDFDocument,
        to url: URL,
        userPassword: String,
        allowPrinting: Bool,
        allowCopying: Bool
    ) throws {
        let options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: Fmt.randomToken(24),
            .userPasswordOption: userPassword,
            .accessPermissionsOption: NSNumber(value: permissions(allowPrinting: allowPrinting, allowCopying: allowCopying))
        ]
        guard document.write(to: url, withOptions: options) else {
            throw ToolError.message("The encrypted PDF couldn’t be written.")
        }
    }

    /// Rebuilds pages as images with an invisible OCR text layer, so scans stay
    /// searchable without uploading anything.
    static func searchable(pages: [(image: CGImage, size: CGSize)], title: String = "") -> PDFDocument {
        let document = PDFDocument()
        for (index, entry) in pages.enumerated() {
            let pageSize = entry.size
            let data = NSMutableData()
            guard let consumer = CGDataConsumer(data: data) else { continue }
            var mediaBox = CGRect(origin: .zero, size: pageSize)
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { continue }
            context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(mediaBox)

            let imageSize = CGSize(width: entry.image.width, height: entry.image.height)
            let scale = min(pageSize.width / imageSize.width, pageSize.height / imageSize.height)
            let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let drawRect = CGRect(
                x: (pageSize.width - drawSize.width) / 2,
                y: (pageSize.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            context.draw(entry.image, in: drawRect)

            let observations = (try? VisionText.recognize(entry.image)) ?? []
            context.setTextDrawingMode(.fill)
            for (text, box) in observations where !text.isEmpty {
                let height = max(4, box.height * drawRect.height * 0.92)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: height),
                    .foregroundColor: NSColor(white: 0, alpha: 0.01)
                ]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
                context.textPosition = CGPoint(
                    x: drawRect.minX + box.minX * drawRect.width,
                    y: drawRect.minY + box.minY * drawRect.height
                )
                CTLineDraw(line, context)
            }

            context.endPDFPage()
            context.closePDF()
            if let page = PDFDocument(data: data as Data)?.page(at: 0) {
                document.insert(page, at: index)
            }
        }
        return document
    }

    static func parseRanges(_ text: String, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return Array(0..<count) }
        var result: [Int] = []
        for part in cleaned.split(separator: ",") {
            let token = part.trimmingCharacters(in: .whitespaces)
            if token.contains("-") {
                let sides = token.split(separator: "-", omittingEmptySubsequences: false)
                guard sides.count == 2,
                      let start = Int(sides[0].trimmingCharacters(in: .whitespaces)),
                      let end = Int(sides[1].trimmingCharacters(in: .whitespaces)) else { continue }
                let low = max(1, min(start, end))
                let high = min(count, max(start, end))
                if low <= high {
                    for page in low...high where !result.contains(page - 1) {
                        result.append(page - 1)
                    }
                }
            } else if let page = Int(token), page >= 1, page <= count, !result.contains(page - 1) {
                result.append(page - 1)
            }
        }
        return result
    }

    /// Draws an overlay image onto a rendered page and returns a new page.
    static func page(_ page: PDFPage, with overlay: CGImage?, rect: CGRect) -> PDFPage? {
        guard let base = image(page, scale: 2) else { return nil }
        let size = displaySize(page)
        let result = NSImage(size: size)
        result.lockFocus()
        NSImage(cgImage: base, size: size).draw(in: CGRect(origin: .zero, size: size))
        if let overlay {
            NSImage(cgImage: overlay, size: rect.size).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        result.unlockFocus()
        var proposed = CGRect(origin: .zero, size: size)
        guard let cg = result.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let copy = PDFPage(image: NSImage(cgImage: cg, size: size)) else { return nil }
        copy.setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
        copy.rotation = 0
        return copy
    }
}

// MARK: - Interactive forms

enum PDFForms {
    static func fieldNames(in document: PDFDocument) -> [String] {
        var names: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                guard let name = annotation.fieldName, !name.isEmpty, !names.contains(name) else { continue }
                names.append(name)
            }
        }
        return names
    }

    static func currentValues(in document: PDFDocument) -> [String: String] {
        var values: [String: String] = [:]
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                guard let name = annotation.fieldName, !name.isEmpty, values[name] == nil else { continue }
                if let value = annotation.widgetStringValue, !value.isEmpty {
                    values[name] = value
                }
            }
        }
        return values
    }

    /// Writes the supplied values into every matching widget. Buttons accept
    /// `on`/`yes`/`true`/`1` (case-insensitive); everything else is treated as
    /// text. Returns the number of widgets updated.
    @discardableResult
    static func apply(_ values: [String: String], to document: PDFDocument) -> Int {
        var updated = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                guard let name = annotation.fieldName, let value = values[name] else { continue }
                if annotation.widgetFieldType == .button {
                    let on = ["on", "yes", "true", "1", "checked"].contains(
                        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    )
                    annotation.buttonWidgetState = on ? .onState : .offState
                } else {
                    annotation.widgetStringValue = value
                }
                updated += 1
            }
        }
        return updated
    }
}

// MARK: - Scan document

struct ScanDocumentTool: View {
    @StateObject private var job = JobState()
    @State private var files: [URL] = []
    @State private var correctEdges = true
    @State private var makeSearchable = true
    @State private var preview: CGImage?
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "doc.viewfinder", title: "Scan Document", subtitle: "Turn photos of paper into a straight, clean PDF. Edges are detected, pages are flattened and the text is searchable.") {
            DropZone(title: "Add page photos", subtitle: "One image per page, in reading order. Use the iPhone camera or a scanner app.", allowsMultiple: true, types: [.image]) { urls in
                files = urls
                job.clear()
                preview = urls.first.flatMap(ImageEngine.source)
            }
            if !files.isEmpty {
                HStack(spacing: 6) {
                    ForEach(files.prefix(5), id: \.path) { url in FileChip(url: url) }
                    if files.count > 5 { Text("+\(files.count - 5) more").font(Theme.caption).foregroundStyle(Theme.textTertiary) }
                    Spacer()
                    Button("Clear") { files = []; preview = nil }.buttonStyle(QuietButtonStyle())
                }
            }
            ToolCard(title: "Scan") {
                Toggle("Detect and straighten page edges", isOn: $correctEdges).toggleStyle(.switch).font(Theme.body)
                Toggle("Add an invisible searchable text layer", isOn: $makeSearchable).toggleStyle(.switch).font(Theme.body)
                Text("On-device only. If a page edge is not detected, the original framing is kept rather than cropping something important.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                RunBar(title: "Build PDF", job: job, disabled: files.isEmpty) { run() }
            }
            if let preview {
                ToolCard(title: "First page") { CheckerImage(image: preview).frame(maxHeight: 300) }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func run() {
        let sources = files
        let correct = correctEdges
        let searchable = makeSearchable
        job.begin("Straightening pages…")
        Task {
            do {
                var pages: [(CGImage, CGSize)] = []
                for (index, source) in sources.enumerated() {
                    job.note("Page \(index + 1) of \(sources.count)…")
                    guard let image = ImageEngine.source(source) else {
                        throw ToolError.message("\(source.lastPathComponent) couldn’t be read.")
                    }
                    let corrected = correct ? DocumentScan.correct(image) : image
                    let pageSize = DocumentScan.pageSize(for: corrected)
                    pages.append((corrected, pageSize))
                }
                let document: PDFDocument
                if searchable {
                    job.note("Adding the searchable text layer…")
                    document = PDFWork.searchable(pages: pages.map { (image: $0.0, size: $0.1) })
                } else {
                    document = PDFDocument()
                    for entry in pages {
                        let ns = NSImage(cgImage: entry.0, size: entry.1)
                        if let page = PDFPage(image: ns) {
                            document.insert(page, at: document.pageCount)
                        }
                    }
                }
                guard document.pageCount > 0 else { throw ToolError.message("No pages could be built.") }
                let folder = store.datedFolder(for: "Scan Document")
                let target = try PDFWork.save(document, folder: folder, name: "scan-\(Fmt.stampTime.string(from: Date())).pdf", store: store)
                await MainActor.run { preview = pages.first?.0 }
                job.finish([target], "Saved \(document.pageCount) page\(document.pageCount == 1 ? "" : "s") · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

enum DocumentScan {
    static func correct(_ image: CGImage) -> CGImage {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.55
        request.quadratureTolerance = 30
        request.minimumSize = 0.25
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let rectangle = request.results?.first else { return image }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let input = CIImage(cgImage: image)
        let filter = CIFilter(name: "CIPerspectiveCorrection")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(x: rectangle.topLeft.x * width, y: rectangle.topLeft.y * height), forKey: "inputTopLeft")
        filter?.setValue(CIVector(x: rectangle.topRight.x * width, y: rectangle.topRight.y * height), forKey: "inputTopRight")
        filter?.setValue(CIVector(x: rectangle.bottomLeft.x * width, y: rectangle.bottomLeft.y * height), forKey: "inputBottomLeft")
        filter?.setValue(CIVector(x: rectangle.bottomRight.x * width, y: rectangle.bottomRight.y * height), forKey: "inputBottomRight")
        guard let output = filter?.outputImage else { return image }
        let context = CIContext()
        return context.createCGImage(output, from: output.extent) ?? image
    }

    static func pageSize(for image: CGImage) -> CGSize {
        let portrait = image.height >= image.width
        return portrait ? CGSize(width: 612, height: 792) : CGSize(width: 792, height: 612)
    }
}

// MARK: - Redact PDF

struct RedactPDFTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @State private var document: PDFDocument?
    @State private var pageIndex = 0
    @State private var pageImage: CGImage?
    @State private var pageSize = CGSize.zero
    @State private var marks: [Int: [Mark]] = [:]
    @EnvironmentObject private var store: ResultStore

    private var currentMarks: [Mark] { marks[pageIndex] ?? [] }

    var body: some View {
        ToolPage(symbol: "rectangle.fill", title: "Redact PDF", subtitle: "Draw over each area that must disappear. The saved page is flattened, so the words underneath are genuinely gone.") {
            DropZone(title: "Choose a PDF", subtitle: "You must own the document or have permission to change it.", allowsMultiple: false, types: [.pdf]) { urls in
                guard let url = urls.first, let doc = PDFWork.open(url) else { return }
                file = url
                document = doc
                pageIndex = 0
                marks = [:]
                job.clear()
                loadPage()
            }
            if let file {
                HStack {
                    FileChip(url: file) { self.file = nil; document = nil; pageImage = nil }
                    Spacer()
                    if let document {
                        Text("\(document.pageCount) pages").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if let document, let pageImage {
                ToolCard(title: "Page \(pageIndex + 1) of \(document.pageCount)") {
                    HStack(spacing: 8) {
                        Button("Previous") { pageIndex = max(0, pageIndex - 1); loadPage() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(pageIndex == 0)
                        Button("Next") { pageIndex = min(document.pageCount - 1, pageIndex + 1); loadPage() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(pageIndex >= document.pageCount - 1)
                        Spacer()
                        Text("\(currentMarks.count) redaction\(currentMarks.count == 1 ? "" : "s") on this page")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Button("Undo") { marks[pageIndex]?.removeLast(); loadPage() }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(currentMarks.isEmpty)
                        Button("Clear page") { marks[pageIndex] = []; loadPage() }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(currentMarks.isEmpty)
                    }
                    MarkCanvas(
                        image: pageImage,
                        marks: Binding(
                            get: { marks[pageIndex] ?? [] },
                            set: { marks[pageIndex] = $0 }
                        ),
                        tool: .box,
                        colorID: 5,
                        text: "",
                        lineWidth: 0
                    )
                    .frame(height: 380)
                    Text("Every marked page is rasterised at 2× and stripped of its text layer. Unmarked pages stay untouched.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                    RunBar(title: "Save redacted copy", job: job, disabled: file == nil || marks.values.allSatisfy { $0.isEmpty }) { run() }
                }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func loadPage() {
        guard let document, let page = document.page(at: pageIndex) else { pageImage = nil; return }
        pageSize = PDFWork.displaySize(page)
        pageImage = PDFWork.image(page, scale: 2)
    }

    private func run() {
        guard let document, let file else { return }
        let marks = self.marks
        job.begin("Flattening redacted pages…")
        Task {
            do {
                let output = PDFWork.redact(document, marks: marks)
                let folder = store.datedFolder(for: "Redact PDF")
                let base = file.deletingPathExtension().lastPathComponent
                let target = try PDFWork.save(output, folder: folder, name: "\(base)-redacted.pdf", store: store)
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - Fill & flatten forms

struct FillPDFFormsTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @State private var document: PDFDocument?
    @State private var fields: [String] = []
    @State private var values: [String: String] = [:]
    @State private var extraText = ""
    @State private var flatten = true
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "list.bullet.rectangle", title: "Fill & Flatten Forms", subtitle: "Fill real form fields where they exist, add a note where they do not, then lock the result.") {
            DropZone(title: "Choose a PDF form", subtitle: "AcroForm fields are detected automatically.", allowsMultiple: false, types: [.pdf]) { urls in
                guard let url = urls.first, let doc = PDFWork.open(url) else { return }
                file = url
                document = doc
                loadFields(doc)
                job.clear()
            }
            if let file { FileChip(url: file) { self.file = nil; document = nil; fields = []; values = [:] } }

            if !fields.isEmpty {
                ToolCard(title: "Fields") {
                    ForEach(fields, id: \.self) { field in
                        LabeledField(label: field, text: Binding(
                            get: { values[field] ?? "" },
                            set: { values[field] = $0 }
                        ), placeholder: "Value", width: 320)
                    }
                }
            }

            ToolCard(title: "Finish") {
                if fields.isEmpty && document != nil {
                    Text("This PDF has no fillable fields. Use the note below to add text to the first page.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                }
                LabeledField(label: "Extra note (optional)", text: $extraText, placeholder: "Added at the foot of page 1", width: 360)
                Toggle("Flatten the answers so they cannot be edited", isOn: $flatten).toggleStyle(.switch).font(Theme.body)
                Text("Flattening rasterises each page at 2×, which keeps the appearance exact and removes the interactive fields.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                RunBar(title: "Save copy", job: job, disabled: file == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func loadFields(_ document: PDFDocument) {
        fields = PDFForms.fieldNames(in: document)
        values = PDFForms.currentValues(in: document)
    }

    private func run() {
        guard let document, let file else { return }
        let values = self.values
        let extra = extraText
        let shouldFlatten = flatten
        job.begin("Filling…")
        Task {
            do {
                PDFForms.apply(values, to: document)
                let output = PDFDocument()
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index) else { continue }
                    let needsNote = index == 0 && !extra.isEmpty
                    if shouldFlatten || needsNote {
                        guard let image = PDFWork.image(page, scale: 2) else { continue }
                        let size = PDFWork.displaySize(page)
                        let canvas = NSImage(size: size)
                        canvas.lockFocus()
                        NSImage(cgImage: image, size: size).draw(in: CGRect(origin: .zero, size: size))
                        if needsNote {
                            let attributes: [NSAttributedString.Key: Any] = [
                                .font: NSFont.systemFont(ofSize: 10),
                                .foregroundColor: NSColor(hex: 0x0A0B0E)
                            ]
                            NSAttributedString(string: extra, attributes: attributes)
                                .draw(in: CGRect(x: 36, y: 30, width: size.width - 72, height: 80))
                        }
                        canvas.unlockFocus()
                        var proposed = CGRect(origin: .zero, size: size)
                        if let cg = canvas.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
                           let copy = PDFPage(image: NSImage(cgImage: cg, size: size)) {
                            copy.setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
                            copy.rotation = 0
                            output.insert(copy, at: output.pageCount)
                        }
                    } else if let copy = page.copy() as? PDFPage {
                        output.insert(copy, at: output.pageCount)
                    }
                }
                let folder = store.datedFolder(for: "Fill & Flatten Forms")
                let base = file.deletingPathExtension().lastPathComponent
                let target = try PDFWork.save(output, folder: folder, name: "\(base)-filled.pdf", store: store)
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - OCR PDF

struct OCRPDFTool: View {
    @StateObject private var job = JobState()
    @State private var files: [URL] = []
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "text.viewfinder", title: "Make PDF Searchable", subtitle: "Add a selectable, searchable text layer to scanned pages using on-device OCR. The page image itself is not changed.") {
            DropZone(title: "Choose scanned PDFs", subtitle: "One or several. Each page is recognised locally.", allowsMultiple: true, types: [.pdf]) { urls in
                files = urls
                job.clear()
            }
            if !files.isEmpty {
                HStack(spacing: 6) {
                    ForEach(files.prefix(5), id: \.path) { url in FileChip(url: url) }
                    Spacer()
                    Button("Clear") { files = [] }.buttonStyle(QuietButtonStyle())
                }
            }
            ToolCard(title: "Recognise") {
                Text("Recognition is done by Apple’s Vision framework on this Mac. Pages that already contain text are kept as they are, with a fresh OCR layer added on top of the rendered page.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                RunBar(title: "Add text layer", job: job, disabled: files.isEmpty) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func run() {
        let sources = files
        job.begin("Reading pages…")
        Task {
            do {
                let folder = store.datedFolder(for: "Make PDF Searchable")
                var outputs: [URL] = []
                for (fileIndex, source) in sources.enumerated() {
                    guard let document = PDFWork.open(source) else {
                        throw ToolError.message("\(source.lastPathComponent) couldn’t be opened.")
                    }
                    var pages: [(CGImage, CGSize)] = []
                    for index in 0..<document.pageCount {
                        job.note("\(source.lastPathComponent) · page \(index + 1) of \(document.pageCount)")
                        guard let page = document.page(at: index),
                              let image = PDFWork.image(page, scale: 2) else { continue }
                        pages.append((image, PDFWork.displaySize(page)))
                    }
                    let searchable = PDFWork.searchable(pages: pages)
                    let base = source.deletingPathExtension().lastPathComponent
                    let target = try PDFWork.save(searchable, folder: folder, name: "\(base)-searchable.pdf", store: store)
                    outputs.append(target)
                    _ = fileIndex
                }
                job.finish(outputs, "Saved \(outputs.count) searchable PDF\(outputs.count == 1 ? "" : "s").")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - PDF to Word

struct PDFToWordTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "doc.text", title: "PDF to Word", subtitle: "Turn a PDF into an editable DOCX with headings, paragraphs and bullet lists.") {
            DropZone(title: "Choose a PDF", subtitle: "Text-based PDFs convert best; scans should be made searchable first.", allowsMultiple: false, types: [.pdf]) { urls in
                file = urls.first
                job.clear()
            }
            if let file { FileChip(url: file) { self.file = nil } }
            ToolCard(title: "Convert") {
                Text("Each page becomes editable paragraphs. A short line in a larger type is treated as a heading; lines that start with a bullet become list items. Tables are reconstructed as text rows.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                RunBar(title: "Make DOCX", job: job, disabled: file == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func run() {
        guard let file else { return }
        job.begin("Reading the PDF…")
        Task {
            do {
                guard let document = PDFWork.open(file) else {
                    throw ToolError.message("That PDF couldn’t be opened.")
                }
                let paragraphs = PDFText.paragraphs(from: document)
                guard !paragraphs.isEmpty else {
                    throw ToolError.message("No text was found. Run Make PDF Searchable first for a scan.")
                }
                let folder = store.datedFolder(for: "PDF to Word")
                let base = file.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base).docx")
                try DocxWriter.make(paragraphs: paragraphs, title: base, to: target)
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

enum PDFText {
    static func paragraphs(from document: PDFDocument) -> [DocxWriter.Paragraph] {
        var result: [DocxWriter.Paragraph] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string ?? ""
            let lines = text.components(separatedBy: .newlines)
            var bodySize: CGFloat = 12
            if let attributed = page.attributedString, attributed.length > 0 {
                var sizes: [CGFloat] = []
                attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                    if let font = value as? NSFont { sizes.append(font.pointSize) }
                }
                if let common = sizes.sorted(by: <).dropFirst(sizes.count / 3).first {
                    bodySize = common
                }
            }
            for raw in lines {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                if line.hasPrefix("•") || line.hasPrefix("- ") || line.hasPrefix("* ") {
                    result.append(DocxWriter.Paragraph(line.trimmingCharacters(in: CharacterSet(charactersIn: "•-* ")), bullet: true))
                    continue
                }
                let looksLikeHeading = line.count < 90
                    && !line.hasSuffix(".")
                    && !line.hasSuffix(",")
                    && (line.uppercased() == line || line.split(separator: " ").count <= 9)
                result.append(DocxWriter.Paragraph(line, heading: looksLikeHeading && line.count < 70 ? (index == 0 ? 1 : 2) : nil))
            }
            if index < document.pageCount - 1 {
                result.append(DocxWriter.Paragraph(""))
            }
        }
        return result
    }
}

// MARK: - Sign PDF

struct SignPDFTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @State private var document: PDFDocument?
    @State private var pageIndex = 0
    @StateObject private var signature = SignaturePadModel()
    @State private var typedName = ""
    @State private var useTyped = false
    @State private var position: SignaturePosition = .bottomRight
    @State private var widthPercent = 24.0
    @State private var preview: NSImage?
    @EnvironmentObject private var store: ResultStore

    enum SignaturePosition: String, CaseIterable, Identifiable {
        case bottomRight = "Bottom right"
        case bottomLeft = "Bottom left"
        case bottomCenter = "Bottom centre"
        case topRight = "Top right"
        case center = "Middle"
        var id: String { rawValue }
    }

    var body: some View {
        ToolPage(symbol: "signature", title: "Sign PDF", subtitle: "Draw a signature with the trackpad or type your name, then place it on any page.") {
            DropZone(title: "Choose a PDF", subtitle: "The original is never changed.", allowsMultiple: false, types: [.pdf]) { urls in
                guard let url = urls.first, let doc = PDFWork.open(url) else { return }
                file = url
                document = doc
                pageIndex = 0
                job.clear()
                renderPreview()
            }
            if let document, let preview {
                ToolCard(title: "Signature") {
                    Picker("Style", selection: $useTyped) {
                        Text("Draw").tag(false)
                        Text("Type").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    if useTyped {
                        LabeledField(label: "Name", text: $typedName, placeholder: "Your name", width: 280)
                        if let image = Signature.preview(typedName) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 60)
                        }
                    } else {
                        SignaturePad(model: signature)
                            .frame(height: 150)
                        HStack {
                            Button("Clear") { signature.clear() }.buttonStyle(QuietButtonStyle())
                            Text("Sign with the trackpad or a mouse.")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textTertiary)
                            Spacer()
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Previous") { pageIndex = max(0, pageIndex - 1); renderPreview() }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(pageIndex == 0)
                        Text("Page \(pageIndex + 1) of \(document.pageCount)")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Button("Next") { pageIndex = min(document.pageCount - 1, pageIndex + 1); renderPreview() }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(pageIndex >= document.pageCount - 1)
                        Spacer()
                    }
                    OptionPicker(label: "Placement", options: SignaturePosition.allCases.map { ($0.rawValue, $0) }, selection: $position)
                    HStack(spacing: 12) {
                        Text("Width").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        Slider(value: $widthPercent, in: 10...55, step: 1).frame(maxWidth: 220)
                        Text("\(Int(widthPercent))%").font(Theme.mono)
                    }
                    Text("The signed copy is flattened, so it looks the same in every reader and cannot be moved by accident.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    RunBar(title: "Sign and save", job: job, disabled: file == nil || (!useTyped && signature.isEmpty) || (useTyped && typedName.trimmingCharacters(in: .whitespaces).isEmpty)) { run() }
                }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func renderPreview() {
        guard let document, let page = document.page(at: pageIndex), let image = PDFWork.image(page, scale: 1.5) else {
            preview = nil
            return
        }
        let size = PDFWork.displaySize(page)
        let signatureImage = currentSignature()
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSImage(cgImage: image, size: size).draw(in: CGRect(origin: .zero, size: size))
        if let signatureImage, let rect = signatureRect(pageSize: size, image: signatureImage) {
            signatureImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        canvas.unlockFocus()
        preview = canvas
    }

    private func currentSignature() -> NSImage? {
        if useTyped { return Signature.image(typedName) }
        return signature.image()
    }

    private func signatureRect(pageSize: CGSize, image: NSImage) -> CGRect? {
        let targetWidth = pageSize.width * CGFloat(widthPercent / 100)
        let ratio = image.size.height / max(1, image.size.width)
        let targetHeight = targetWidth * ratio
        let margin: CGFloat = 36
        let x: CGFloat
        let y: CGFloat
        switch position {
        case .bottomRight: x = pageSize.width - targetWidth - margin; y = margin
        case .bottomLeft: x = margin; y = margin
        case .bottomCenter: x = (pageSize.width - targetWidth) / 2; y = margin
        case .topRight: x = pageSize.width - targetWidth - margin; y = pageSize.height - targetHeight - margin
        case .center: x = (pageSize.width - targetWidth) / 2; y = (pageSize.height - targetHeight) / 2
        }
        return CGRect(x: x, y: y, width: targetWidth, height: targetHeight)
    }

    private func run() {
        guard let document, let file, let signatureImage = currentSignature() else { return }
        let pageIndex = self.pageIndex
        let percent = widthPercent
        let placement = position
        let shouldFlatten = true
        job.begin("Signing…")
        Task {
            do {
                let output = PDFDocument()
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index) else { continue }
                    if index != pageIndex {
                        if let copy = page.copy() as? PDFPage { output.insert(copy, at: output.pageCount) }
                        continue
                    }
                    let size = PDFWork.displaySize(page)
                    let targetWidth = size.width * CGFloat(percent / 100)
                    let ratio = signatureImage.size.height / max(1, signatureImage.size.width)
                    let targetHeight = targetWidth * ratio
                    let margin: CGFloat = 36
                    let x: CGFloat
                    let y: CGFloat
                    switch placement {
                    case .bottomRight: x = size.width - targetWidth - margin; y = margin
                    case .bottomLeft: x = margin; y = margin
                    case .bottomCenter: x = (size.width - targetWidth) / 2; y = margin
                    case .topRight: x = size.width - targetWidth - margin; y = size.height - targetHeight - margin
                    case .center: x = (size.width - targetWidth) / 2; y = (size.height - targetHeight) / 2
                    }
                    let rect = CGRect(x: x, y: y, width: targetWidth, height: targetHeight)

                    if shouldFlatten {
                        guard let image = PDFWork.image(page, scale: 2) else { continue }
                        let canvas = NSImage(size: size)
                        canvas.lockFocus()
                        NSImage(cgImage: image, size: size).draw(in: CGRect(origin: .zero, size: size))
                        signatureImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                        canvas.unlockFocus()
                        var proposed = CGRect(origin: .zero, size: size)
                        if let cg = canvas.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
                           let copy = PDFPage(image: NSImage(cgImage: cg, size: size)) {
                            copy.setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
                            copy.rotation = 0
                            output.insert(copy, at: output.pageCount)
                        }
                    }
                }
                let folder = store.datedFolder(for: "Sign PDF")
                let base = file.deletingPathExtension().lastPathComponent
                let target = try PDFWork.save(output, folder: folder, name: "\(base)-signed.pdf", store: store)
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

@MainActor
final class SignaturePadModel: ObservableObject {
    @Published var strokes: [[CGPoint]] = []
    @Published var current: [CGPoint] = []

    var isEmpty: Bool { strokes.isEmpty && current.isEmpty }
    func clear() { strokes = []; current = [] }
    func image(size: CGSize = CGSize(width: 600, height: 200)) -> NSImage? {
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSColor.clear.setFill()
        CGRect(origin: .zero, size: size).fill()
        NSColor(hex: 0x0A0B0E).setStroke()
        for stroke in strokes {
            guard stroke.count > 1 else { continue }
            let path = NSBezierPath()
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: CGPoint(x: stroke[0].x * size.width, y: (1 - stroke[0].y) * size.height))
            for point in stroke.dropFirst() {
                path.line(to: CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height))
            }
            path.stroke()
        }
        canvas.unlockFocus()
        return canvas
    }
}

struct SignaturePad: View {
    @ObservedObject var model: SignaturePadModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .textBackgroundColor)
                Canvas { context, size in
                    for stroke in model.strokes + [model.current] {
                        guard stroke.count > 1 else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: stroke[0].x * size.width, y: stroke[0].y * size.height))
                        for point in stroke.dropFirst() {
                            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                        }
                        context.stroke(path, with: .color(Theme.textPrimary), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let point = CGPoint(x: value.location.x / max(1, geo.size.width), y: value.location.y / max(1, geo.size.height))
                            model.current.append(point)
                        }
                        .onEnded { _ in
                            if !model.current.isEmpty {
                                model.strokes.append(model.current)
                                model.current = []
                            }
                        }
                )
                if model.isEmpty {
                    Text("Sign here")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
        }
    }
}

enum Signature {
    static func image(_ name: String) -> NSImage? {
        preview(name)
    }

    static func preview(_ name: String) -> NSImage? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let size = CGSize(width: 600, height: 180)
        let result = NSImage(size: size)
        result.lockFocus()
        NSColor.clear.setFill()
        CGRect(origin: .zero, size: size).fill()
        let font = NSFont(name: "Snell Roundhand", size: 72) ?? NSFontManager.shared.convert(NSFont.systemFont(ofSize: 64), toHaveTrait: .italicFontMask)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(hex: 0x0A0B0E)
        ]
        let string = NSAttributedString(string: trimmed, attributes: attributes)
        let textSize = string.size()
        string.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
        result.unlockFocus()
        return result
    }
}

// MARK: - Organize PDF

struct OrganizePDFTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @State private var items: [PageItem] = []
    @EnvironmentObject private var store: ResultStore

    struct PageItem: Identifiable {
        let id = UUID()
        let page: PDFPage
        var rotation: Int
        var thumbnail: NSImage?
    }

    var body: some View {
        ToolPage(symbol: "rectangle.3.group", title: "Organize PDF", subtitle: "Drag pages into a new order, rotate sideways scans and remove what does not belong.") {
            DropZone(title: "Choose a PDF", subtitle: "Nothing is written until you export.", allowsMultiple: false, types: [.pdf]) { urls in
                guard let url = urls.first, let doc = PDFWork.open(url) else { return }
                file = url
                items = (0..<doc.pageCount).compactMap { index in
                    guard let page = doc.page(at: index) else { return nil }
                    let size = page.bounds(for: .mediaBox).size
                    let image = page.thumbnail(of: CGSize(width: 150, height: 150 * size.height / max(1, size.width)), for: .mediaBox)
                    return PageItem(page: page, rotation: 0, thumbnail: image)
                }
                job.clear()
            }
            if let file {
                HStack {
                    FileChip(url: file) { self.file = nil; items = [] }
                    Spacer()
                    Text("\(items.count) pages").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            if !items.isEmpty {
                ToolCard(title: "Pages") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 4) {
                                ZStack(alignment: .topLeading) {
                                    if let thumbnail = item.thumbnail {
                                        Image(nsImage: thumbnail)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 110)
                                            .rotationEffect(.degrees(Double(item.rotation)))
                                            .frame(width: 96, height: 110)
                                            .background(Color.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
                                    }
                                    Text("\(index + 1)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.6), in: Capsule())
                                        .padding(4)
                                }
                                HStack(spacing: 2) {
                                    Button { rotate(index) } label: { Image(systemName: "rotate.right") }.buttonStyle(QuietButtonStyle())
                                    Button { remove(index) } label: { Image(systemName: "trash") }.buttonStyle(QuietButtonStyle())
                                    Button { move(index, -1) } label: { Image(systemName: "arrow.left") }.buttonStyle(QuietButtonStyle()).disabled(index == 0)
                                    Button { move(index, 1) } label: { Image(systemName: "arrow.right") }.buttonStyle(QuietButtonStyle()).disabled(index == items.count - 1)
                                }
                            }
                            .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
                            .onDrop(of: [.text], delegate: PageDropDelegate(target: item.id, items: $items))
                        }
                    }
                    RunBar(title: "Export organized PDF", job: job, disabled: items.isEmpty) { run() }
                }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func rotate(_ index: Int) {
        guard items.indices.contains(index) else { return }
        items[index].rotation = ((items[index].rotation + 90) % 360 + 360) % 360
    }

    private func remove(_ index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    private func move(_ index: Int, _ delta: Int) {
        let destination = index + delta
        guard items.indices.contains(index), items.indices.contains(destination) else { return }
        items.swapAt(index, destination)
    }

    private func run() {
        guard let file else { return }
        let source = items
        job.begin("Building the PDF…")
        Task {
            do {
                let document = PDFWork.assemble(source.map { (page: $0.page, rotation: $0.rotation) })
                let folder = store.datedFolder(for: "Organize PDF")
                let base = file.deletingPathExtension().lastPathComponent
                let target = try PDFWork.save(document, folder: folder, name: "\(base)-organized.pdf", store: store)
                job.finish([target], "Saved \(document.pageCount) pages · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

struct PageDropDelegate: DropDelegate {
    let target: UUID
    @Binding var items: [OrganizePDFTool.PageItem]

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String, let id = UUID(uuidString: string) else { return }
            DispatchQueue.main.async {
                guard let from = items.firstIndex(where: { $0.id == id }),
                      let to = items.firstIndex(where: { $0.id == target }) else { return }
                let item = items.remove(at: from)
                items.insert(item, at: to)
            }
        }
        return true
    }
}

// MARK: - Delete PDF pages

struct DeletePDFPagesTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @State private var document: PDFDocument?
    @State private var selected: Set<Int> = []
    @State private var ranges = ""
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "trash", title: "Delete Pages", subtitle: "Drop pages you do not need and save a clean copy. The original stays where it is.") {
            DropZone(title: "Choose a PDF", subtitle: "Click pages to mark them for removal.", allowsMultiple: false, types: [.pdf]) { urls in
                guard let url = urls.first, let doc = PDFWork.open(url) else { return }
                file = url
                document = doc
                selected = []
                ranges = ""
                job.clear()
            }
            if let file { FileChip(url: file) { self.file = nil; document = nil; selected = [] } }

            if let document {
                ToolCard(title: "Pages") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(0..<document.pageCount, id: \.self) { index in
                            if let page = document.page(at: index) {
                                let size = page.bounds(for: .mediaBox).size
                                Button {
                                    if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        Image(nsImage: page.thumbnail(of: CGSize(width: 140, height: 140 * size.height / max(1, size.width)), for: .mediaBox))
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 88, height: 108)
                                            .background(Color.white)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .strokeBorder(selected.contains(index) ? Theme.danger : Theme.lineStrong, lineWidth: selected.contains(index) ? 3 : 1)
                                            )
                                        if selected.contains(index) {
                                            Image(systemName: "trash.fill")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(5)
                                                .background(Theme.danger, in: Circle())
                                                .padding(4)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Text("Or type ranges to remove:").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        TextField("2-4, 9", text: $ranges)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .fieldStyle()
                            .frame(width: 160)
                        Spacer()
                        Button("Select none") { selected = [] }.buttonStyle(QuietButtonStyle())
                    }
                    RunBar(title: "Save without these pages", job: job, disabled: selected.isEmpty && ranges.trimmingCharacters(in: .whitespaces).isEmpty) { run() }
                }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func run() {
        guard let document, let file else { return }
        var remove = selected
        for index in PDFWork.parseRanges(ranges, count: document.pageCount) where !ranges.trimmingCharacters(in: .whitespaces).isEmpty {
            remove.insert(index)
        }
        guard remove.count < document.pageCount else {
            job.fail("That would remove every page. Keep at least one.")
            return
        }
        job.begin("Building a clean copy…")
        Task {
            do {
                let output = PDFWork.removing(document, pages: remove)
                let folder = store.datedFolder(for: "Delete Pages")
                let base = file.deletingPathExtension().lastPathComponent
                let target = try PDFWork.save(output, folder: folder, name: "\(base)-trimmed.pdf", store: store)
                job.finish([target], "Removed \(remove.count) page\(remove.count == 1 ? "" : "s"); \(output.pageCount) remain.")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - Password protect PDF

struct PasswordProtectPDFTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @State private var password = ""
    @State private var confirm = ""
    @State private var allowPrinting = true
    @State private var allowCopying = false
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "lock.doc", title: "Add Password", subtitle: "Encrypt a PDF you own with AES. Keep the password somewhere safe; Nookit never stores it.") {
            DropZone(title: "Choose a PDF", subtitle: "The original is left unencrypted.", allowsMultiple: false, types: [.pdf]) { urls in
                file = urls.first
                job.clear()
            }
            if let file { FileChip(url: file) { self.file = nil } }
            ToolCard(title: "Password") {
                HStack(spacing: 12) {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .fieldStyle()
                        .frame(width: 220)
                    SecureField("Repeat password", text: $confirm)
                        .textFieldStyle(.plain)
                        .fieldStyle()
                        .frame(width: 220)
                }
                HStack(spacing: 18) {
                    Toggle("Allow printing", isOn: $allowPrinting).toggleStyle(.switch)
                    Toggle("Allow copying text", isOn: $allowCopying).toggleStyle(.switch)
                }
                .font(Theme.body)
                Text("The owner password is generated on this Mac and used to apply the restrictions. Write the user password down; it cannot be recovered.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                RunBar(title: "Encrypt", job: job, disabled: file == nil || password.isEmpty || password != confirm) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func run() {
        guard let file, password == confirm, !password.isEmpty else { return }
        let allowPrinting = self.allowPrinting
        let allowCopying = self.allowCopying
        let needPassword = password
        job.begin("Encrypting…")
        Task {
            do {
                guard let document = PDFWork.open(file) else {
                    throw ToolError.message("That PDF couldn’t be opened.")
                }
                guard !document.isEncrypted else {
                    throw ToolError.message("That PDF is already encrypted. Remove its password first.")
                }
                let folder = store.datedFolder(for: "Add Password")
                let base = file.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base)-protected.pdf")
                try PDFWork.encrypt(
                    document,
                    to: target,
                    userPassword: needPassword,
                    allowPrinting: allowPrinting,
                    allowCopying: allowCopying
                )
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}
