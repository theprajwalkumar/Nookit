import SwiftUI
import AppKit
import PDFKit
import WebKit
import UniformTypeIdentifiers

// MARK: - Convert documents

struct ConvertDocumentsTool: View {
    @StateObject private var job = JobState()
    @State private var files: [URL] = []
    @State private var target: Target = .docx
    @EnvironmentObject private var store: ResultStore

    enum Target: String, CaseIterable, Identifiable {
        case docx = "DOCX"
        case doc = "DOC"
        case rtf = "RTF"
        case html = "HTML"
        case odt = "ODT"
        case txt = "Plain text"
        case markdown = "Markdown"
        var id: String { rawValue }
        var textutilFormat: String? {
            switch self {
            case .docx: return "docx"
            case .doc: return "doc"
            case .rtf: return "rtf"
            case .html: return "html"
            case .odt: return "odt"
            case .txt: return "txt"
            case .markdown: return nil
            }
        }
        var ext: String {
            switch self {
            case .docx: return "docx"
            case .doc: return "doc"
            case .rtf: return "rtf"
            case .html: return "html"
            case .odt: return "odt"
            case .txt: return "txt"
            case .markdown: return "md"
            }
        }
    }

    var body: some View {
        ToolPage(symbol: "arrow.triangle.2.circlepath.doc", title: "Convert Documents", subtitle: "Word, RTF, HTML, ODT, text and Markdown, without opening a word processor.") {
            DropZone(title: "Choose documents", subtitle: "DOCX, DOC, RTF, ODT, HTML, TXT or Markdown.", allowsMultiple: true) { urls in
                files = urls
                job.clear()
            }
            if !files.isEmpty {
                HStack(spacing: 6) {
                    ForEach(files.prefix(5), id: \.path) { url in FileChip(url: url) }
                    if files.count > 5 { Text("+\(files.count - 5) more").font(Theme.caption).foregroundStyle(Theme.textTertiary) }
                    Spacer()
                    Button("Clear") { files = [] }.buttonStyle(QuietButtonStyle())
                }
            }
            ToolCard(title: "Output format") {
                OptionPicker(label: "Convert to", options: Target.allCases.map { ($0.rawValue, $0) }, selection: $target)
                Text("DOC, DOCX, RTF, HTML, ODT and TXT use the macOS text engine. Markdown output is written directly as plain text with headings and lists preserved.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                RunBar(title: "Convert \(files.count) file\(files.count == 1 ? "" : "s")", job: job, disabled: files.isEmpty) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func run() {
        let sources = files
        let target = self.target
        job.begin("Converting…")
        Task {
            do {
                let folder = store.datedFolder(for: "Convert Documents")
                var outputs: [URL] = []
                for (index, source) in sources.enumerated() {
                    job.note("\(index + 1) of \(sources.count) · \(source.lastPathComponent)")
                    let base = source.deletingPathExtension().lastPathComponent
                    let out = ExtraFiles.unique(folder, "\(base).\(target.ext)")
                    let input = try await DocumentConvert.prepareInput(source, folder: folder)
                    if let format = target.textutilFormat {
                        let result = try await Shell.run("/usr/bin/textutil", ["-convert", format, "-output", out.path, input.path])
                        guard result.succeeded, FileManager.default.fileExists(atPath: out.path) else {
                            throw ToolError.message(result.stderr.isEmpty ? "textutil couldn’t convert \(source.lastPathComponent)." : result.stderr)
                        }
                    } else {
                        let text = ExtraFiles.text(input)
                        try text.write(to: out, atomically: true, encoding: .utf8)
                    }
                    if input != source { try? FileManager.default.removeItem(at: input) }
                    outputs.append(out)
                }
                job.finish(outputs, "Converted \(outputs.count) file\(outputs.count == 1 ? "" : "s") to \(target.rawValue).")
            } catch {
                job.fail(error)
            }
        }
    }
}

enum DocumentConvert {
    static func prepareInput(_ source: URL, folder: URL) async throws -> URL {
        let ext = source.pathExtension.lowercased()
        guard ext == "md" || ext == "markdown" else { return source }
        guard let pandoc = Shell.which("pandoc") else {
            throw ToolError.message("Markdown input needs pandoc. Install it with `brew install pandoc`, or convert the Markdown to HTML first.")
        }
        let html = ExtraFiles.unique(folder, "\(source.deletingPathExtension().lastPathComponent)-source.html")
        let result = try await Shell.run(pandoc, ["-f", "markdown", "-t", "html", "-o", html.path, source.path])
        guard result.succeeded else {
            throw ToolError.message(result.stderr.isEmpty ? "pandoc couldn’t read that Markdown file." : result.stderr)
        }
        return html
    }

    static func htmlString(_ url: URL) async throws -> String {
        let result = try await Shell.run("/usr/bin/textutil", ["-convert", "html", "-stdout", url.path])
        guard result.succeeded, !result.stdout.isEmpty else {
            throw ToolError.message(result.stderr.isEmpty ? "That document couldn’t be read." : result.stderr)
        }
        return result.stdout
    }

    static func attributedHTML(_ html: String) -> NSAttributedString? {
        guard let data = html.data(using: .utf8) else { return nil }
        return try? NSAttributedString(data: data, options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ], documentAttributes: nil)
    }
}

// MARK: - Word to PDF

struct WordToPDFTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "doc.richtext", title: "Word to PDF", subtitle: "Render DOCX, RTF, ODT and text into a PDF with the layout engine macOS already ships.") {
            DropZone(title: "Choose a document", subtitle: "DOCX, DOC, RTF, ODT, HTML or TXT.", allowsMultiple: false) { urls in
                file = urls.first
                job.clear()
            }
            if let file { FileChip(url: file) { self.file = nil } }
            ToolCard(title: "Render") {
                Text("Formatting, headings and inline styling are kept. Complex layouts with floating images may reflow, because this is the system text engine rather than Microsoft Word.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                RunBar(title: "Make PDF", job: job, disabled: file == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func run() {
        guard let file else { return }
        job.begin("Laying out the document…")
        Task {
            do {
                let folder = store.datedFolder(for: "Word to PDF")
                let base = file.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base).pdf")
                let ext = file.pathExtension.lowercased()
                let document: PDFDocument
                if ext == "txt" || ext == "text" {
                    document = PDFComposer.make(text: ExtraFiles.text(file), title: base)
                } else {
                    let html = try await DocumentConvert.htmlString(file)
                    guard let attributed = DocumentConvert.attributedHTML(html) else {
                        throw ToolError.message("The document’s formatting couldn’t be read.")
                    }
                    document = PDFComposer.make(from: attributed, title: base)
                }
                guard document.pageCount > 0 else { throw ToolError.message("The PDF came out empty.") }
                guard let data = document.dataRepresentation() else { throw ToolError.message("The PDF couldn’t be written.") }
                try data.write(to: target, options: .atomic)
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - PowerPoint to PDF

struct PowerPointToPDFTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "rectangle.on.rectangle.angled", title: "PowerPoint to PDF", subtitle: "Decks into PDFs. Keynote or LibreOffice gives the closest layout; without them Nookit renders the text of each slide.") {
            DropZone(title: "Choose a deck", subtitle: "PPTX or PPT.", allowsMultiple: false, types: [UTType(filenameExtension: "pptx") ?? .data, .data]) { urls in
                file = urls.first
                job.clear()
            }
            if let file { FileChip(url: file) { self.file = nil } }
            ToolCard(title: "Render") {
                Text("Nookit checks for Keynote or LibreOffice first. If neither is installed, slide text is laid out one slide per page, without images or theme effects.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                RunBar(title: "Make PDF", job: job, disabled: file == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func run() {
        guard let file else { return }
        job.begin("Opening the deck…")
        Task {
            do {
                let folder = store.datedFolder(for: "PowerPoint to PDF")
                let base = file.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base).pdf")

                if let office = OfficeConverter.libreOffice {
                    job.note("Converting through LibreOffice…")
                    if let converted = try await OfficeConverter.pdf(from: file, office: office, folder: folder) {
                        job.finish([converted], "Saved \(converted.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(converted))).")
                        return
                    }
                    // Fall through to the built-in text renderer rather than
                    // leaving the user with no PDF at all.
                }

                job.note("Reading slide text…")
                let deck = try OfficeXML.presentation(file)
                guard !deck.slides.isEmpty else {
                    throw ToolError.message("No slide text was found. Install Keynote or LibreOffice for a full-fidelity conversion.")
                }
                let document = PDFDocument()
                for slide in deck.slides {
                    let page = PDFComposer.make(from: OfficeXML.slideAttributed(slide), pageSize: deck.pageSize, title: "")
                    if let first = page.page(at: 0) {
                        document.insert(first, at: document.pageCount)
                    }
                }
                let data = document.dataRepresentation()
                guard let data else { throw ToolError.message("The PDF couldn’t be written.") }
                try data.write(to: target, options: .atomic)
                job.finish([target], "Saved \(document.pageCount) slides · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - Excel to PDF

struct ExcelToPDFTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "tablecells", title: "Excel to PDF", subtitle: "Spreadsheets without the scrollbars. LibreOffice or Numbers gives the closest layout; otherwise each sheet is rendered as a clean table.") {
            DropZone(title: "Choose a spreadsheet", subtitle: "XLSX or XLS.", allowsMultiple: false, types: [UTType(filenameExtension: "xlsx") ?? .data, .data]) { urls in
                file = urls.first
                job.clear()
            }
            if let file { FileChip(url: file) { self.file = nil } }
            ToolCard(title: "Render") {
                Text("Without a spreadsheet app installed, Nookit reads the first worksheet of an XLSX and lays it out as a paginated table. Formulas appear as their last saved values.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                RunBar(title: "Make PDF", job: job, disabled: file == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func run() {
        guard let file else { return }
        job.begin("Opening the workbook…")
        Task {
            do {
                let folder = store.datedFolder(for: "Excel to PDF")
                let base = file.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base).pdf")

                if let office = OfficeConverter.libreOffice {
                    job.note("Converting through LibreOffice…")
                    if let converted = try await OfficeConverter.pdf(from: file, office: office, folder: folder) {
                        job.finish([converted], "Saved \(converted.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(converted))).")
                        return
                    }
                    // Fall through to the built-in table renderer.
                }

                job.note("Reading cells…")
                let sheets = try OfficeXML.spreadsheet(file)
                guard !sheets.isEmpty else {
                    throw ToolError.message("No worksheet data was found. Install LibreOffice for a full-fidelity conversion.")
                }
                let document = TablePDF.make(sheets: sheets)
                guard let data = document.dataRepresentation() else { throw ToolError.message("The PDF couldn’t be written.") }
                try data.write(to: target, options: .atomic)
                job.finish([target], "Saved \(document.pageCount) page\(document.pageCount == 1 ? "" : "s") · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

enum OfficeConverter {
    /// Converts one document to PDF in a scratch directory, then moves the
    /// result into the dated folder under a unique name. Converting straight
    /// into the dated folder would overwrite a PDF from an earlier run (or
    /// silently keep the old one when LibreOffice refuses to overwrite).
    static func pdf(from file: URL, office: String, folder: URL) async throws -> URL? {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("nookit-office-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let result = try await Shell.run(
            office,
            ["--headless", "--convert-to", "pdf", "--outdir", scratch.path, file.path],
            timeout: 300
        )
        guard result.succeeded else { return nil }

        let base = file.deletingPathExtension().lastPathComponent
        let produced = scratch.appendingPathComponent("\(base).pdf")
        guard FileManager.default.fileExists(atPath: produced.path) else { return nil }

        let target = ExtraFiles.unique(folder, "\(base).pdf")
        do {
            try FileManager.default.moveItem(at: produced, to: target)
        } catch {
            return nil
        }
        return target
    }

    static var libreOffice: String? {
        if let path = Shell.which("soffice") { return path }
        if let path = Shell.which("libreoffice") { return path }
        let candidates = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice",
            "/usr/local/bin/soffice"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var keynote: String? {
        FileManager.default.fileExists(atPath: "/Applications/Keynote.app") ? "/Applications/Keynote.app" : nil
    }
}

// MARK: - Office XML readers

enum OfficeXML {
    struct Deck {
        var slides: [[String]]
        var pageSize: CGSize
    }

    static func presentation(_ url: URL) throws -> Deck {
        let temp = try unzip(url)
        defer { try? FileManager.default.removeItem(at: temp) }

        var pageSize = CGSize(width: 720, height: 540)
        let presentationURL = temp.appendingPathComponent("ppt/presentation.xml")
        if let data = try? Data(contentsOf: presentationURL) {
            let parser = XMLParser(data: data)
            let delegate = SlideSizeDelegate()
            parser.delegate = delegate
            parser.parse()
            if delegate.width > 0, delegate.height > 0 {
                let ratio = delegate.width / delegate.height
                if ratio > 1.5 {
                    pageSize = CGSize(width: 960, height: 540)
                } else if ratio < 1.05 {
                    pageSize = CGSize(width: 540, height: 960)
                } else {
                    pageSize = CGSize(width: 720, height: 540)
                }
            }
        }

        let slideFolder = temp.appendingPathComponent("ppt/slides")
        let files = (try? FileManager.default.contentsOfDirectory(at: slideFolder, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasSuffix(".xml") }
            .sorted { slideNumber($0) < slideNumber($1) } ?? []
        var slides: [[String]] = []
        for file in files {
            guard let data = try? Data(contentsOf: file) else { continue }
            let delegate = ParagraphDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            let paragraphs = delegate.paragraphs.filter { !$0.isEmpty }
            if !paragraphs.isEmpty { slides.append(paragraphs) }
        }
        return Deck(slides: slides, pageSize: pageSize)
    }

    static func slideAttributed(_ lines: [String]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let isTitle = index == 0
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = isTitle ? 16 : 8
            style.lineSpacing = 3
            let font = isTitle ? NSFont.boldSystemFont(ofSize: 26) : NSFont.systemFont(ofSize: 15)
            output.append(NSAttributedString(string: (isTitle ? "" : "•  ") + line + "\n", attributes: [
                .font: font,
                .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1),
                .paragraphStyle: style
            ]))
        }
        return output
    }

    static func spreadsheet(_ url: URL) throws -> [(String, [[String]])] {
        let temp = try unzip(url)
        defer { try? FileManager.default.removeItem(at: temp) }

        var shared: [String] = []
        let sharedURL = temp.appendingPathComponent("xl/sharedStrings.xml")
        if let data = try? Data(contentsOf: sharedURL) {
            let delegate = SharedStringsDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            shared = delegate.strings
        }

        let sheetFolder = temp.appendingPathComponent("xl/worksheets")
        let files = (try? FileManager.default.contentsOfDirectory(at: sheetFolder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "xml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        var sheets: [(String, [[String]])] = []
        for (index, file) in files.prefix(4).enumerated() {
            guard let data = try? Data(contentsOf: file) else { continue }
            let delegate = SheetDelegate(shared: shared)
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            let rows = delegate.rows.filter { !$0.isEmpty }
            if !rows.isEmpty {
                sheets.append(("Sheet \(index + 1)", rows))
            }
        }
        return sheets
    }

    private static func unzip(_ url: URL) throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("nookit-office-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", url.path, "-d", temp.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ToolError.message("That file isn’t a readable Office package.")
        }
        return temp
    }

    private static func slideNumber(_ url: URL) -> Int {
        let digits = url.deletingPathExtension().lastPathComponent.filter { $0.isNumber }
        return Int(digits) ?? 0
    }
}

private final class SlideSizeDelegate: NSObject, XMLParserDelegate {
    var width: CGFloat = 0
    var height: CGFloat = 0
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard local == "sldSz" else { return }
        if let cx = Double(attributeDict["cx"] ?? ""), let cy = Double(attributeDict["cy"] ?? "") {
            width = cx / 12700
            height = cy / 12700
        }
    }
}

private final class ParagraphDelegate: NSObject, XMLParserDelegate {
    var paragraphs: [String] = []
    private var current = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if local == "p" { current = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if local == "p" {
            let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { paragraphs.append(text) }
            current = ""
        }
    }
}

private final class SharedStringsDelegate: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inItem = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if local == "si" { current = ""; inItem = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if local == "si" {
            strings.append(current)
            current = ""
            inItem = false
        }
    }
}

private final class SheetDelegate: NSObject, XMLParserDelegate {
    let shared: [String]
    var rows: [[String]] = []
    private var currentRow: [String] = []
    private var currentCell: String = ""
    private var currentType: String = ""
    private var inCell = false
    private var inValue = false

    init(shared: [String]) {
        self.shared = shared
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if local == "row" { currentRow = [] }
        if local == "c" {
            inCell = true
            currentCell = ""
            currentType = attributeDict["t"] ?? ""
        }
        if local == "v" || local == "t" { inValue = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inCell, inValue { currentCell += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if local == "v" || local == "t" { inValue = false }
        if local == "c" {
            let value: String
            if currentType == "s", let index = Int(currentCell), shared.indices.contains(index) {
                value = shared[index]
            } else {
                value = currentCell
            }
            currentRow.append(value)
            inCell = false
            currentCell = ""
        }
        if local == "row" { rows.append(currentRow) }
    }
}

// MARK: - Table PDF

enum TablePDF {
    static func make(sheets: [(String, [[String]])]) -> PDFDocument {
        let document = PDFDocument()
        let pageSize = CGSize(width: 792, height: 612)
        let margin: CGFloat = 34
        let rowHeight: CGFloat = 18
        let titleHeight: CGFloat = 30
        let tableWidth = pageSize.width - margin * 2

        for (name, rows) in sheets {
            let columnCount = max(1, rows.map(\.count).max() ?? 1)
            let columnWidth = tableWidth / CGFloat(columnCount)
            var rowIndex = 0
            while rowIndex < rows.count {
                let data = NSMutableData()
                guard let consumer = CGDataConsumer(data: data) else { break }
                var mediaBox = CGRect(origin: .zero, size: pageSize)
                guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { break }
                context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
                context.setFillColor(NSColor.white.cgColor)
                context.fill(mediaBox)

                let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = nsContext

                // Sheet title.
                let title = NSAttributedString(string: name, attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 15),
                    .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1)
                ])
                title.draw(at: CGPoint(x: margin, y: pageSize.height - margin - 18))

                let headerY = pageSize.height - margin - titleHeight - rowHeight
                context.setFillColor(NSColor(calibratedWhite: 0.93, alpha: 1).cgColor)
                context.fill(CGRect(x: margin, y: headerY, width: tableWidth, height: rowHeight))

                let rowsPerPage = max(1, Int((headerY - margin) / rowHeight))
                let end = min(rows.count, rowIndex + rowsPerPage)
                for (offset, row) in rows[rowIndex..<end].enumerated() {
                    let y = headerY - CGFloat(offset + 1) * rowHeight
                    for column in 0..<columnCount {
                        let value = column < row.count ? row[column] : ""
                        let cellRect = CGRect(x: margin + CGFloat(column) * columnWidth + 4, y: y + 3, width: columnWidth - 8, height: rowHeight - 5)
                        let font = rowIndex == 0 && offset == 0 ? NSFont.boldSystemFont(ofSize: 9) : NSFont.systemFont(ofSize: 9)
                        let line = NSAttributedString(string: value, attributes: [
                            .font: font,
                            .foregroundColor: NSColor(calibratedWhite: 0.1, alpha: 1)
                        ])
                        line.draw(in: cellRect)
                    }
                }

                // Grid.
                context.setStrokeColor(NSColor(calibratedWhite: 0.78, alpha: 1).cgColor)
                context.setLineWidth(0.5)
                let tableHeight = CGFloat(end - rowIndex + 1) * rowHeight
                for column in 0...columnCount {
                    let x = margin + CGFloat(column) * columnWidth
                    context.move(to: CGPoint(x: x, y: headerY + rowHeight))
                    context.addLine(to: CGPoint(x: x, y: headerY + rowHeight - tableHeight))
                }
                for row in 0...end - rowIndex {
                    let y = headerY + rowHeight - CGFloat(row) * rowHeight
                    context.move(to: CGPoint(x: margin, y: y))
                    context.addLine(to: CGPoint(x: margin + tableWidth, y: y))
                }
                context.strokePath()

                NSGraphicsContext.restoreGraphicsState()
                context.endPDFPage()
                context.closePDF()

                if let page = PDFDocument(data: data as Data)?.page(at: 0) {
                    document.insert(page, at: document.pageCount)
                }
                rowIndex = end
            }
        }
        return document
    }
}

// MARK: - Web page to PDF

struct WebpageToPDFTool: View {
    @StateObject private var job = JobState()
    @State private var address = ""
    @State private var paginate = true
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "globe", title: "Web Page to PDF", subtitle: "Keep the page, lose the tabs. Save a URL as a paginated PDF or one continuous page.") {
            ToolCard(title: "Address") {
                LabeledField(label: "URL", text: $address, placeholder: "https://example.com/article")
                Toggle("Split into A4 pages", isOn: $paginate).toggleStyle(.switch).font(Theme.body)
                Text("The page is rendered by WebKit on this Mac. Pages behind a login will use the session already on this Mac, if one exists.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                RunBar(title: "Save PDF", job: job, disabled: !(address.lowercased().hasPrefix("http://") || address.lowercased().hasPrefix("https://"))) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func run() {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            job.fail("Enter a full http:// or https:// address.")
            return
        }
        let paginate = self.paginate
        job.begin("Loading the page…")
        Task {
            do {
                let loader = WebPageLoader()
                let data = try await loader.pdf(url: url, width: 1000)
                let document: PDFDocument
                if paginate {
                    document = PDFSlicer.slice(data, pageHeight: 1414)
                } else {
                    document = PDFDocument(data: data) ?? PDFDocument()
                }
                guard document.pageCount > 0 else { throw ToolError.message("The page produced an empty PDF.") }
                let folder = store.datedFolder(for: "Web Page to PDF")
                let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "page"
                let target = try PDFWork.save(document, folder: folder, name: "\(host).pdf", store: store)
                job.finish([target], "Saved \(document.pageCount) page\(document.pageCount == 1 ? "" : "s") · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

@MainActor
final class WebPageLoader: NSObject, WKNavigationDelegate {
    private var view: WKWebView?
    private var window: NSWindow?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?

    func pdf(url: URL, width: CGFloat) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 900), configuration: configuration)
        view.navigationDelegate = self
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderOut(nil)
        self.view = view
        self.window = window

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
            timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.finish(.failure(ToolError.message("The page took too long to load.")))
            }
        }

        // Let layout and lazy images settle before capturing.
        try? await Task.sleep(for: .milliseconds(900))
        let reported = try? await view.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)")
        let contentHeight = max(900, CGFloat((reported as? NSNumber)?.doubleValue ?? 900))
        let config = WKPDFConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: contentHeight)
        let data = try await view.pdf(configuration: config)
        self.view = nil
        self.window = nil
        return data
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
}

enum PDFSlicer {
    static func slice(_ data: Data, pageHeight: CGFloat) -> PDFDocument {
        guard let source = PDFDocument(data: data), let page = source.page(at: 0) else {
            return PDFDocument()
        }
        let bounds = page.bounds(for: .mediaBox)
        let result = PDFDocument()
        var remaining = bounds.height
        while remaining > 1 {
            let height = min(pageHeight, remaining)
            let offset = bounds.height - remaining
            let sliceData = NSMutableData()
            guard let consumer = CGDataConsumer(data: sliceData) else { break }
            var mediaBox = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { break }
            context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(mediaBox)
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: bounds.width, height: height))
            context.translateBy(x: 0, y: -(bounds.height - offset - height))
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
            context.endPDFPage()
            context.closePDF()
            if let slice = PDFDocument(data: sliceData as Data)?.page(at: 0) {
                result.insert(slice, at: result.pageCount)
            }
            remaining -= height
        }
        return result
    }
}

// MARK: - Markdown to PDF

struct MarkdownToPDFTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @State private var includeContents = true
    @State private var page: Page = .letter
    @EnvironmentObject private var store: ResultStore

    enum Page: String, CaseIterable, Identifiable {
        case letter = "US Letter"
        case a4 = "A4"
        var id: String { rawValue }
        var size: CGSize { self == .letter ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842) }
    }

    var body: some View {
        ToolPage(symbol: "text.alignleft", title: "Markdown to PDF", subtitle: "Notes and READMEs, typeset with headings, code blocks, tables and an optional table of contents.") {
            DropZone(title: "Choose a Markdown file", subtitle: ".md or .markdown.", allowsMultiple: false) { urls in
                file = urls.first
                job.clear()
            }
            if let file { FileChip(url: file) { self.file = nil } }
            ToolCard(title: "Layout") {
                HStack(spacing: 16) {
                    OptionPicker(label: "Page", options: Page.allCases.map { ($0.rawValue, $0) }, selection: $page)
                    Toggle("Table of contents", isOn: $includeContents).toggleStyle(.switch).font(Theme.body)
                }
                Text("Code is set in a monospaced face, tables keep their columns and long documents flow across pages.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                RunBar(title: "Make PDF", job: job, disabled: file == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "doc")
        }
    }

    private func run() {
        guard let file else { return }
        let includeContents = self.includeContents
        let pageSize = page.size
        job.begin("Typesetting…")
        Task {
            do {
                let markdown = ExtraFiles.text(file)
                guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ToolError.message("That Markdown file is empty.")
                }
                let output = NSMutableAttributedString()
                if includeContents {
                    let headings = MarkdownRenderer.headings(from: markdown)
                    if !headings.isEmpty {
                        output.append(NSAttributedString(string: "Contents\n", attributes: [
                            .font: NSFont.boldSystemFont(ofSize: 20),
                            .foregroundColor: NSColor(calibratedWhite: 0.06, alpha: 1)
                        ]))
                        for heading in headings {
                            let indent = String(repeating: "    ", count: max(0, heading.level - 1))
                            let style = NSMutableParagraphStyle()
                            style.paragraphSpacing = 2
                            output.append(NSAttributedString(string: "\(indent)\(heading.text)\n", attributes: [
                                .font: NSFont.systemFont(ofSize: 11),
                                .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1),
                                .paragraphStyle: style
                            ]))
                        }
                        output.append(NSAttributedString(string: "\n\n"))
                    }
                }
                output.append(MarkdownRenderer.attributed(from: markdown))
                let document = PDFComposer.make(from: output, pageSize: pageSize, title: file.deletingPathExtension().lastPathComponent)
                let folder = store.datedFolder(for: "Markdown to PDF")
                let base = file.deletingPathExtension().lastPathComponent
                let target = try PDFWork.save(document, folder: folder, name: "\(base).pdf", store: store)
                job.finish([target], "Saved \(target.lastPathComponent) · \(document.pageCount) page\(document.pageCount == 1 ? "" : "s").")
            } catch {
                job.fail(error)
            }
        }
    }
}
