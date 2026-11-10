import SwiftUI
import AppKit
import AVFoundation
import PDFKit
import Vision
import CoreImage
import CryptoKit
import UniformTypeIdentifiers

// MARK: - FFmpeg

/// Thin wrapper around the system FFmpeg. The app looks for a bundled copy first,
/// then Homebrew/MacPorts, then PATH. Tools that need it explain the dependency
/// instead of silently failing.
enum FFmpeg {
    static var path: String? {
        if let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        return Shell.which("ffmpeg")
    }

    static var available: Bool { path != nil }

    /// Some Homebrew builds are compiled without libass/freetype, so a filter
    /// can be missing from an otherwise working FFmpeg. Tools that use an
    /// optional filter check this and fall back instead of failing.
    static func hasFilter(_ name: String) async -> Bool {
        guard let path else { return false }
        guard let result = try? await Shell.run(path, ["-hide_banner", "-filters"]) else { return false }
        return result.stdout.components(separatedBy: .newlines).contains { line in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            return fields.count > 1 && fields[1] == Substring(name)
        }
    }

    static func run(_ arguments: [String], timeout: TimeInterval? = nil) async throws -> ShellResult {
        guard let path else {
            throw ToolError.message("FFmpeg isn’t installed. Install it with `brew install ffmpeg` (or bundle it with the app) and try again.")
        }
        let result = try await Shell.run(path, ["-hide_banner", "-nostdin", "-loglevel", "error"] + arguments, timeout: timeout)
        guard result.succeeded else {
            throw ToolError.message(result.stderr.isEmpty ? "FFmpeg exited with code \(result.status)." : result.stderr)
        }
        return result
    }

    static func checked(_ arguments: [String], timeout: TimeInterval? = nil) async throws {
        _ = try await run(arguments, timeout: timeout)
    }

    static func hasAudio(_ url: URL) async -> Bool {
        guard let probe = Shell.which("ffprobe") else {
            let asset = AVURLAsset(url: url)
            let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            return !tracks.isEmpty
        }
        let result = try? await Shell.run(probe, ["-v", "error", "-select_streams", "a", "-show_entries", "stream=index", "-of", "csv=p=0", url.path])
        return !(result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func duration(_ url: URL) async -> Double {
        if let probe = Shell.which("ffprobe") {
            let result = try? await Shell.run(probe, ["-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", url.path])
            if let value = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), let seconds = Double(value) {
                return seconds
            }
        }
        let asset = AVURLAsset(url: url)
        return (try? await asset.load(.duration).seconds) ?? 0
    }

    /// Display-oriented size: applies the track’s preferred transform so a
    /// portrait iPhone clip reports 1080 × 1920 even when its stored frame is
    /// 1920 × 1080. Falls back to ffprobe when AVFoundation can’t read it.
    static func videoSize(_ url: URL) async -> CGSize {
        let asset = AVURLAsset(url: url)
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let natural = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform),
           natural.width > 0, natural.height > 0 {
            let displayed = natural.applying(transform)
            return CGSize(width: abs(displayed.width), height: abs(displayed.height))
        }
        if let probe = Shell.which("ffprobe") {
            let result = try? await Shell.run(probe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=s=x:p=0", url.path])
            if let text = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) {
                let parts = text.split(separator: "x").compactMap { Double($0) }
                if parts.count == 2 { return CGSize(width: parts[0], height: parts[1]) }
            }
        }
        return .zero
    }

    /// Escapes a path for use inside an FFmpeg filter argument.
    static func filterEscape(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    static func even(_ value: Double) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded % 2 == 0 ? rounded : rounded + 1
    }

    /// FFmpeg's atempo only accepts 0.5–2.0, so chain several stages for a wider range.
    static func atempo(_ factor: Double) -> String {
        guard factor > 0, factor != 1 else { return "atempo=1" }
        var remaining = factor
        var stages: [Double] = []
        while remaining > 2.0 {
            stages.append(2.0)
            remaining /= 2.0
        }
        while remaining < 0.5 {
            stages.append(0.5)
            remaining /= 0.5
        }
        stages.append(remaining)
        return stages.map { "atempo=\(String(format: "%.4f", $0))" }.joined(separator: ",")
    }
}

// MARK: - PDF composition

/// Lays an attributed string out over one or more US Letter pages.
enum PDFComposer {
    static func make(from attributed: NSAttributedString, title: String = "") -> PDFDocument {
        make(from: attributed, pageSize: CGSize(width: 612, height: 792), title: title)
    }

    static func make(from attributed: NSAttributedString, pageSize: CGSize, title: String = "") -> PDFDocument {
        let document = PDFDocument()
        let margin: CGFloat = 54
        let textRect = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var offset = 0
        var pageIndex = 0

        while offset < attributed.length || pageIndex == 0 {
            let data = NSMutableData()
            guard let consumer = CGDataConsumer(data: data) else { break }
            // The media box has to be given to the context as well as the page:
            // PDFKit falls back to US Letter when only the page dictionary
            // carries it.
            var mediaBox = CGRect(origin: .zero, size: pageSize)
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { break }
            context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)

            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(offset, 0), path, nil)
            CTFrameDraw(frame, context)

            // Small document title in the footer.
            if !title.isEmpty {
                let footer = NSAttributedString(string: title, attributes: [
                    .font: NSFont.systemFont(ofSize: 8),
                    .foregroundColor: NSColor(white: 0.55, alpha: 1)
                ])
                let line = CTLineCreateWithAttributedString(footer)
                context.textPosition = CGPoint(x: margin, y: 28)
                CTLineDraw(line, context)
            }
            context.endPDFPage()
            context.closePDF()

            if let page = PDFDocument(data: data as Data)?.page(at: 0) {
                document.insert(page, at: pageIndex)
            }

            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length <= 0 { break }
            offset += visible.length
            pageIndex += 1
            if pageIndex > 400 { break }
        }
        return document
    }

    static func make(text: String, title: String = "") -> PDFDocument {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 8
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1),
            .paragraphStyle: style
        ])
        return make(from: attributed, title: title)
    }
}

// MARK: - Markdown

enum MarkdownRenderer {
    static func attributed(from markdown: String, baseSize: CGFloat = 11.5) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: .newlines)
        var inCode = false

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                inCode.toggle()
                continue
            }

            if inCode {
                append(output, line + "\n", font: .monospacedSystemFont(ofSize: baseSize - 0.5, weight: .regular),
                       color: NSColor(calibratedWhite: 0.18, alpha: 1), spacingAfter: 0)
                continue
            }

            if line.isEmpty {
                append(output, "\n", font: .systemFont(ofSize: baseSize), color: .clear, spacingAfter: 0)
                continue
            }

            if line.hasPrefix("|") {
                // Markdown table row. Separator rows are dropped; cells are padded
                // so the monospaced output keeps its columns readable.
                if line.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }
                let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                let padded = cells.map { cell -> String in
                    cell.count >= 18 ? cell : cell + String(repeating: " ", count: 18 - cell.count)
                }.joined(separator: " ")
                append(output, padded + "\n", font: .monospacedSystemFont(ofSize: baseSize - 0.5, weight: .regular),
                       color: NSColor(calibratedWhite: 0.12, alpha: 1), spacingAfter: 0)
                continue
            }

            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                let size: CGFloat = level == 1 ? baseSize + 12 : level == 2 ? baseSize + 7 : baseSize + 3
                append(output, text + "\n", font: .boldSystemFont(ofSize: size), color: NSColor(calibratedWhite: 0.06, alpha: 1), spacingBefore: level == 1 ? 6 : 10, spacingAfter: 5)
                continue
            }

            if line.hasPrefix("> ") {
                append(output, String(line.dropFirst(2)) + "\n", font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: baseSize), toHaveTrait: .italicFontMask),
                       color: NSColor(calibratedWhite: 0.35, alpha: 1), spacingAfter: 3)
                continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                append(output, "•  " + inline(String(line.dropFirst(2))) + "\n", font: .systemFont(ofSize: baseSize),
                       color: NSColor(calibratedWhite: 0.1, alpha: 1), spacingAfter: 1)
                continue
            }

            if let match = line.range(of: #"^[0-9]+[.)]\s+"#, options: .regularExpression) {
                let number = line[line.startIndex..<match.upperBound]
                let rest = line[match.upperBound...]
                append(output, number + inline(String(rest)) + "\n", font: .systemFont(ofSize: baseSize),
                       color: NSColor(calibratedWhite: 0.1, alpha: 1), spacingAfter: 1)
                continue
            }

            append(output, inline(line) + "\n", font: .systemFont(ofSize: baseSize),
                   color: NSColor(calibratedWhite: 0.1, alpha: 1), spacingAfter: 3)
        }
        return output
    }

    /// Extracts `#` headings so a caller can build a table of contents.
    static func headings(from markdown: String) -> [(level: Int, text: String)] {
        markdown.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#") else { return nil }
            let level = line.prefix(while: { $0 == "#" }).count
            let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : (level, text)
        }
    }

    private static func inline(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
    }

    private static func append(
        _ output: NSMutableAttributedString,
        _ text: String,
        font: NSFont,
        color: NSColor,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 0
    ) {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.lineSpacing = 3
        output.append(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ]))
    }
}

// MARK: - DOCX

enum DocxWriter {
    struct Paragraph {
        var text: String
        var heading: Int?
        var bullet: Bool

        init(_ text: String, heading: Int? = nil, bullet: Bool = false) {
            self.text = text
            self.heading = heading
            self.bullet = bullet
        }
    }

    static func make(paragraphs: [String], title: String, to url: URL) throws {
        try make(paragraphs: paragraphs.map { Paragraph($0) }, title: title, to: url)
    }

    static func make(paragraphs: [Paragraph], title: String, to url: URL) throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("nookit-docx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        func write(_ path: String, _ contents: String) throws {
            let target = temp.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.data(using: .utf8)?.write(to: target)
        }

        try write("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """)

        try write("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """)

        let body = paragraphs.map { paragraph -> String in
            let text = paragraph.bullet ? "•  " + paragraph.text : paragraph.text
            let safe = escape(text)
            if let heading = paragraph.heading {
                let level = min(3, max(1, heading))
                let size = level == 1 ? 32 : level == 2 ? 28 : 24
                return "<w:p><w:pPr><w:pStyle w:val=\"Heading\(level)\"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val=\"\(size)\"/></w:rPr><w:t xml:space=\"preserve\">\(safe)</w:t></w:r></w:p>"
            }
            if paragraph.bullet {
                return "<w:p><w:r><w:rPr><w:sz w:val=\"22\"/></w:rPr><w:t xml:space=\"preserve\">\(safe)</w:t></w:r></w:p>"
            }
            return "<w:p><w:r><w:t xml:space=\"preserve\">\(safe)</w:t></w:r></w:p>"
        }.joined()

        try write("word/document.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="36"/></w:rPr><w:t xml:space="preserve">\(escape(title))</w:t></w:r></w:p>
            \(body)
            <w:sectPr/>
          </w:body>
        </w:document>
        """)

        let zip = temp.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).docx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = temp
        process.arguments = ["-q", "-r", zip.path, "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ToolError.message("The DOCX package couldn’t be written.")
        }
        defer { try? FileManager.default.removeItem(at: zip) }
        try FileManager.default.copyItem(at: zip, to: url)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - OCR

enum VisionText {
    static func recognize(_ image: CGImage, languages: [String] = ["en-US"]) throws -> [(String, CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (candidate.string, observation.boundingBox)
        }
    }

    static func text(_ image: CGImage) -> String {
        (try? recognize(image))?.map(\.0).joined(separator: "\n") ?? ""
    }
}

// MARK: - Image helpers

enum ImageData {
    static func png(_ image: CGImage) -> Data? {
        ImageEngine.encode(image, type: .png)
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.9) -> Data? {
        ImageEngine.encode(image, type: .jpeg, quality: quality)
    }

    static func cgImage(_ image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func draw(size: CGSize, _ body: (CGContext) -> Void) -> CGImage? {
        ImageEngine.draw(size: size, body)
    }
}

// MARK: - Shell conveniences

enum ExtraShell {
    @discardableResult
    static func quiet(_ tool: String, _ arguments: [String]) async -> String {
        (try? await Shell.run(tool, arguments))?.output ?? ""
    }

    static func defaultsRead(_ domain: String, _ key: String) async -> String? {
        let result = try? await Shell.run("/usr/bin/defaults", ["read", domain, key])
        guard let result, result.succeeded else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func defaultsWrite(_ domain: String, _ key: String, _ value: String) async {
        _ = try? await Shell.run("/usr/bin/defaults", ["write", domain, key, value])
    }
}
