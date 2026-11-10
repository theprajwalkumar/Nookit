import AppKit
import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreLocation
import CryptoKit
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Engine-level functional checks used during development.
///
/// `NOOKIT_TEST=1 ./Nookit` generates fixtures in `/tmp/nookit-selftest`, runs
/// the shared engines that back the tools, and prints one summary line plus a
/// FAIL/SKIP line per problem. It never touches the user's real Downloads
/// folder and does not open Finder windows.
@MainActor
enum FunctionalTests {
    static func run() {
        Task { @MainActor in
            let suite = Suite()
            await suite.execute()
            print("NOOKIT_TEST passed=\(suite.passed) failed=\(suite.failed) skipped=\(suite.skipped)")
            for item in suite.failures { print("FAIL \(item)") }
            for item in suite.skips { print("SKIP \(item)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
        }
    }
}

@MainActor
private final class Suite {
    private let fm = FileManager.default
    private let root = URL(fileURLWithPath: "/tmp/nookit-selftest", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    private var fixtures: URL { root.appendingPathComponent("fixtures", isDirectory: true) }
    private var output: URL { root.appendingPathComponent("output", isDirectory: true) }

    private(set) var passed = 0
    private(set) var failed = 0
    private(set) var skipped = 0
    private(set) var failures: [String] = []
    private(set) var skips: [String] = []

    // MARK: Reporting

    private func check(_ name: String, _ condition: @autoclosure () -> Bool, _ detail: @autoclosure () -> String = "") {
        if condition() {
            passed += 1
        } else {
            failed += 1
            let extra = detail()
            failures.append(extra.isEmpty ? name : "\(name) — \(extra)")
        }
    }

    private func skip(_ name: String, _ reason: String) {
        skipped += 1
        skips.append("\(name) — \(reason)")
    }

    private func checkURL(_ name: String, _ url: URL, minSize: Int = 1) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        check(name, fm.fileExists(atPath: url.path) && size >= minSize, "size=\(size) path=\(url.lastPathComponent)")
    }

    private func shell(_ tool: String, _ arguments: [String], workingDirectory: URL? = nil) async -> ShellResult {
        (try? await Shell.run(tool, arguments, workingDirectory: workingDirectory))
            ?? ShellResult(stdout: "", stderr: "launch failed", status: -1)
    }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func uniqueFile(_ folder: URL, _ name: String) -> URL {
        ExtraFiles.unique(folder, name)
    }

    /// Builds a small ZIP with the same `/usr/bin/zip` path used by DocxWriter
    /// and Office readers, so fixtures match what the tools actually see.
    private func makeZip(_ files: [String: String], at url: URL) async throws {
        let temp = root.appendingPathComponent("zip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        for (path, body) in files {
            let target = temp.appendingPathComponent(path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: target, atomically: true, encoding: .utf8)
        }
        try? fm.removeItem(at: url)
        let result = await shell("/usr/bin/zip", ["-q", "-r", url.path, "."], workingDirectory: temp)
        guard result.succeeded else { throw ToolError.message("zip fixture failed: \(result.stderr)") }
    }

    private func hash(_ data: Data) -> String {
        Fmt.hex(Data(SHA256.hash(data: data)))
    }

    private func imageHash(_ image: CGImage) -> String {
        guard let data = ImageEngine.encode(image, type: .png) else { return "" }
        return hash(data)
    }

    // MARK: Fixtures

    private func gradientImage(width: Int = 400, height: Int = 300, dark: Bool = false) -> CGImage? {
        ImageEngine.draw(size: CGSize(width: width, height: height)) { context in
            let colors = dark
                ? [NSColor(hex: 0x0A0B0E).cgColor, NSColor(hex: 0xFF5A1F).cgColor]
                : [NSColor(hex: 0xF7F4ED).cgColor, NSColor(hex: 0x6FE3B6).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient,
                                           start: CGPoint(x: 0, y: 0),
                                           end: CGPoint(x: CGFloat(width), y: CGFloat(height)),
                                           options: [])
            }
            context.setFillColor(NSColor(hex: 0x0A0B0E).cgColor)
            context.fill(CGRect(x: CGFloat(width) * 0.2, y: CGFloat(height) * 0.2,
                                width: CGFloat(width) * 0.3, height: CGFloat(height) * 0.3))
            context.setFillColor(NSColor(hex: 0xFF5A1F).cgColor)
            context.fillEllipse(in: CGRect(x: CGFloat(width) * 0.58, y: CGFloat(height) * 0.45,
                                           width: CGFloat(width) * 0.25, height: CGFloat(height) * 0.25))
        }
    }

    private func textImage(_ text: String = "NOOKIT TEST 123") -> CGImage? {
        let size = NSSize(width: 760, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 58),
            .foregroundColor: NSColor.black
        ]
        NSString(string: text).draw(at: NSPoint(x: 24, y: 70), withAttributes: attributes)
        image.unlockFocus()
        var rect = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func makePDF(_ text: String, at url: URL, pageSize: CGSize = CGSize(width: 612, height: 792)) -> Bool {
        PDFComposer.make(text: text).write(to: url, withOptions: [:])
        guard fm.fileExists(atPath: url.path) else { return false }
        if pageSize != CGSize(width: 612, height: 792) {
            let document = PDFComposer.make(from: NSAttributedString(string: text), pageSize: pageSize)
            return document.write(to: url, withOptions: [:])
        }
        return true
    }

    // MARK: Entry point

    func execute() async {
        do {
            try fm.createDirectory(at: fixtures, withIntermediateDirectories: true)
            try fm.createDirectory(at: output, withIntermediateDirectories: true)
        } catch {
            failed += 1
            failures.append("fixtures — \(error.localizedDescription)")
            return
        }

        let previousRoot = ResultStore.shared.outputRoot
        let previousReveal = ResultStore.shared.revealOnSave
        ResultStore.shared.outputRoot = output
        ResultStore.shared.revealOnSave = false
        defer {
            ResultStore.shared.outputRoot = previousRoot
            ResultStore.shared.revealOnSave = previousReveal
        }

        runImageTests()
        runPDFTests()
        await runDocumentTests()
        runTextTests()
        await runUtilityTests()
        await runFFmpegTests()
        await runDependencyTests()
        runFeatureTests()
        runDisplayTests()

        // Leave fixtures on disk for inspection but do not accumulate runs.
        let marker = root.appendingPathComponent("SUMMARY.txt")
        let summary = "passed=\(passed) failed=\(failed) skipped=\(skipped)\n"
            + failures.map { "FAIL \($0)" }.joined(separator: "\n")
            + "\n"
            + skips.map { "SKIP \($0)" }.joined(separator: "\n")
        try? summary.write(to: marker, atomically: true, encoding: .utf8)
    }

    // MARK: Images

    private func runImageTests() {
        let pngURL = fixtures.appendingPathComponent("sample.png")
        let source = gradientImage()
        check("ImageEngine.draw", source != nil)
        guard let source else { return }
        if let png = ImageEngine.encode(source, type: .png) {
            check("ImageEngine.encode PNG", (try? png.write(to: pngURL)) != nil)
        } else {
            check("ImageEngine.encode PNG", false, "encoder returned nil")
        }

        check("ImageEngine.source", ImageEngine.source(pngURL)?.width == 400)

        if let jpeg = ImageEngine.encode(source, type: .jpeg, quality: 0.8) {
            let url = fixtures.appendingPathComponent("sample.jpg")
            try? jpeg.write(to: url)
            check("ImageEngine.encode JPEG", ImageEngine.source(url)?.height == 300)
        } else {
            check("ImageEngine.encode JPEG", false, "encoder returned nil")
        }

        if let tiff = ImageEngine.encode(source, type: .tiff) {
            let url = fixtures.appendingPathComponent("sample.tiff")
            try? tiff.write(to: url)
            check("ImageEngine.encode TIFF", ImageEngine.source(url) != nil)
        } else {
            check("ImageEngine.encode TIFF", false, "encoder returned nil")
        }

        if let heic = ImageEngine.encode(source, type: .heic, quality: 0.8) {
            let url = fixtures.appendingPathComponent("sample.heic")
            try? heic.write(to: url)
            check("ImageEngine.encode HEIC", ImageEngine.source(url) != nil)
        } else {
            skip("ImageEngine.encode HEIC", "this Mac's ImageIO has no HEIC encoder")
        }

        let resized = ImageEngine.resized(source, maxPixel: 200)
        check("ImageEngine.resized", resized.width == 200 && resized.height == 150,
              "\(resized.width)x\(resized.height)")

        let untouched = ImageEngine.resized(source, maxPixel: 4000)
        check("ImageEngine.resized does not upscale", untouched.width == 400 && untouched.height == 300)

        let rotated90 = ImageEngine.rotated(source, degrees: 90, flip: false)
        check("ImageEngine.rotated 90", rotated90.width == 300 && rotated90.height == 400,
              "\(rotated90.width)x\(rotated90.height)")

        let rotated180 = ImageEngine.rotated(source, degrees: 180, flip: false)
        check("ImageEngine.rotated 180", rotated180.width == 400 && rotated180.height == 300)

        let flipped = ImageEngine.rotated(source, degrees: 0, flip: true)
        check("ImageEngine.rotated flip", flipped.width == 400 && flipped.height == 300)

        let beautified = ImageEngine.beautified(source, padding: 40, corner: 12, dark: true)
        check("ImageEngine.beautified", beautified.width == 480 && beautified.height == 380,
              "\(beautified.width)x\(beautified.height)")

        // Metadata stripping: add EXIF to a JPEG, then re-encode without it.
        let exifURL = fixtures.appendingPathComponent("exif.jpg")
        if let destination = CGImageDestinationCreateWithURL(exifURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
            let properties: [CFString: Any] = [
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifUserComment: "nookit-test-metadata",
                    kCGImagePropertyExifDateTimeOriginal: "2024:01:02 03:04:05"
                ]
            ]
            CGImageDestinationAddImage(destination, source, properties as CFDictionary)
            CGImageDestinationFinalize(destination)
            let exif = imageProperties(exifURL)?[kCGImagePropertyExifDictionary] as? [CFString: Any]
            check("Image metadata fixture",
                  exif?[kCGImagePropertyExifUserComment] != nil
                  && exif?[kCGImagePropertyExifDateTimeOriginal] != nil)
            if let stripped = ImageEngine.encode(ImageEngine.source(exifURL) ?? source, type: .jpeg, quality: 0.9) {
                let strippedURL = fixtures.appendingPathComponent("stripped.jpg")
                try? stripped.write(to: strippedURL)
                // ImageIO keeps a minimal EXIF block with pixel dimensions;
                // what has to disappear is the camera/author metadata.
                let remaining = (imageProperties(strippedURL)?[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
                let keys = remaining.keys.map { $0 as String }.sorted()
                check("Remove metadata strips EXIF",
                      remaining[kCGImagePropertyExifUserComment] == nil
                      && remaining[kCGImagePropertyExifDateTimeOriginal] == nil,
                      "remaining=\(keys)")
            } else {
                check("Remove metadata strips EXIF", false, "encode failed")
            }
        } else {
            check("Image metadata fixture", false, "could not create JPEG destination")
        }

        let marks: [Mark] = [
            Mark(style: .box, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.4), text: "", colorID: 0, number: 1),
            Mark(style: .arrow, start: CGPoint(x: 0.2, y: 0.7), end: CGPoint(x: 0.6, y: 0.5), text: "", colorID: 3, number: 2),
            Mark(style: .label, start: CGPoint(x: 0.5, y: 0.2), end: CGPoint(x: 0.8, y: 0.3), text: "Look here", colorID: 2, number: 3),
            Mark(style: .number, start: CGPoint(x: 0.7, y: 0.7), end: CGPoint(x: 0.7, y: 0.7), text: "", colorID: 2, number: 4)
        ]
        let marked = ImageMarkRenderer.render(source, marks: marks)
        check("ImageMarkRenderer.render", marked != nil)
        if let marked {
            check("ImageMarkRenderer changes pixels", imageHash(marked) != imageHash(source))
        }

        if let pixelated = try? Redaction.pixelate(source, marks: [marks[0]]) {
            check("Redaction.pixelate", imageHash(pixelated) != imageHash(source))
        } else {
            check("Redaction.pixelate", false, "threw")
        }

        let fitRect = ImageFit.rect(image: source, in: CGSize(width: 200, height: 200))
        check("ImageFit.rect", fitRect == CGRect(x: 0, y: 25, width: 200, height: 150),
              "\(fitRect)")

        let normalised = ImageFit.normalise(CGPoint(x: 100, y: 80), rect: fitRect)
        let roundTrip = ImageFit.point(normalised, rect: fitRect)
        check("ImageFit normalise/point round-trip",
              abs(roundTrip.x - 100) < 0.001 && abs(roundTrip.y - 80) < 0.001)

        let pixelRect = ImageFit.pixelRect(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), image: source)
        check("ImageFit.pixelRect", pixelRect == CGRect(x: 100, y: 75, width: 200, height: 150),
              "\(pixelRect)")

        if let text = textImage() {
            let png = ImageEngine.encode(text, type: .png)
            if let png {
                try? png.write(to: fixtures.appendingPathComponent("ocr.png"))
            }
            let recognised = VisionText.text(text)
            check("VisionText.recognize", recognised.uppercased().contains("NOOKIT"),
                  "recognised=\(recognised.prefix(80))")

            let faces = (try? ImageToolsFaces.detect(in: text)) ?? []
            check("ImageToolsFaces.detect handles no faces", faces.isEmpty)

            if let covered = try? ImageToolsFaces.cover(source, faces: [CGRect(x: 100, y: 100, width: 80, height: 80)],
                                                       mode: .blur, strength: 18) {
                check("ImageToolsFaces.cover", imageHash(covered) != imageHash(source))
            } else {
                check("ImageToolsFaces.cover", false, "threw")
            }

            if let scan = try? BackgroundCutout.remove(from: text) {
                check("BackgroundCutout.remove", scan.width > 0)
            } else {
                skip("BackgroundCutout.remove", "no foreground subject in the synthetic image")
            }

            let corrected = DocumentScan.correct(text)
            check("DocumentScan.correct", corrected.width > 0 && corrected.height > 0)
        } else {
            check("OCR fixture", false, "could not render text image")
        }

        check("DocumentScan.pageSize landscape", DocumentScan.pageSize(for: source) == CGSize(width: 792, height: 612))
        check("DocumentScan.pageSize portrait", DocumentScan.pageSize(for: ImageEngine.rotated(source, degrees: 90, flip: false)) == CGSize(width: 612, height: 792))
    }

    private func imageProperties(_ url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    // MARK: PDF

    private func runPDFTests() {
        let one = fixtures.appendingPathComponent("one.pdf")
        let two = fixtures.appendingPathComponent("two.pdf")
        let three = fixtures.appendingPathComponent("three.pdf")
        check("PDFComposer.make text", makePDF("Nookit page one", at: one))
        check("PDFComposer.make text 2", makePDF("Nookit page two", at: two))
        check("PDFComposer.make text 3", makePDF("Nookit page three", at: three))

        guard let doc1 = PDFDocument(url: one), let doc2 = PDFDocument(url: two), let doc3 = PDFDocument(url: three) else {
            check("PDFDocument open", false)
            return
        }
        check("PDFComposer page count", doc1.pageCount >= 1 && doc1.page(at: 0)?.string?.contains("Nookit") == true,
              "pages=\(doc1.pageCount)")

        let merged = PDFDocument()
        for (offset, doc) in [doc1, doc2, doc3].enumerated() {
            for index in 0..<doc.pageCount {
                if let page = doc.page(at: index) { merged.insert(page, at: offset) }
            }
        }
        check("PDF merge", merged.pageCount == doc1.pageCount + doc2.pageCount + doc3.pageCount,
              "pages=\(merged.pageCount)")

        let longText = (1...90).map { "Line \($0): Nookit keeps every page on this Mac and writes results to a dated folder." }.joined(separator: "\n")
        let multiURL = fixtures.appendingPathComponent("multi.pdf")
        let multi = PDFComposer.make(text: longText)
        _ = multi.write(to: multiURL, withOptions: [:])
        check("PDFComposer paginates long text", multi.pageCount > 1, "pages=\(multi.pageCount)")

        let ranges = PDFWork.parseRanges("1-2, 4", count: 5)
        check("PDFWork.parseRanges list", ranges == [0, 1, 3], "\(ranges)")
        let reversed = PDFWork.parseRanges("3-1", count: 5)
        check("PDFWork.parseRanges reversed", reversed == [0, 1, 2], "\(reversed)")
        let clamped = PDFWork.parseRanges("4-99", count: 5)
        check("PDFWork.parseRanges clamps", clamped == [3, 4], "\(clamped)")
        let all = PDFWork.parseRanges("", count: 3)
        check("PDFWork.parseRanges empty means all", all == [0, 1, 2], "\(all)")

        if let page = doc1.page(at: 0) {
            let image = PDFWork.image(page, scale: 2)
            check("PDFWork.image", image != nil && (image?.width ?? 0) > 100,
                  "\(image?.width ?? 0)x\(image?.height ?? 0)")

            if let raster = PDFWork.rasterizedPage(page, scale: 1.5) {
                check("PDFWork.rasterizedPage", raster.rotation == 0 && PDFWork.displaySize(raster).width > 100)
            } else {
                check("PDFWork.rasterizedPage", false)
            }

            if let overlay = gradientImage(width: 80, height: 80),
               let stamped = PDFWork.page(page, with: overlay, rect: CGRect(x: 40, y: 40, width: 100, height: 100)) {
                check("PDFWork.page overlay", PDFWork.displaySize(stamped).width > 100)
            } else {
                check("PDFWork.page overlay", false)
            }
        }

        let flattened = PDFWork.flatten(merged)
        check("PDFWork.flatten", flattened.pageCount == merged.pageCount, "pages=\(flattened.pageCount)")

        // Interactive form fields survive a fill + flatten pass.
        let formSize = CGSize(width: 612, height: 792)
        let formImage = NSImage(size: formSize)
        formImage.lockFocus()
        NSColor.white.setFill()
        CGRect(origin: .zero, size: formSize).fill()
        NSAttributedString(string: "Nookit application form", attributes: [
            .font: NSFont.systemFont(ofSize: 20),
            .foregroundColor: NSColor.black
        ]).draw(at: CGPoint(x: 48, y: 700))
        formImage.unlockFocus()
        let formDocument = PDFDocument()
        if let formPage = PDFPage(image: formImage) {
            formDocument.insert(formPage, at: 0)
            let nameField = PDFAnnotation(
                bounds: CGRect(x: 60, y: 600, width: 320, height: 30),
                forType: .widget,
                withProperties: nil
            )
            nameField.widgetFieldType = .text
            nameField.fieldName = "FullName"
            nameField.widgetStringValue = "Ada Lovelace"
            formPage.addAnnotation(nameField)

            let agree = PDFAnnotation(
                bounds: CGRect(x: 60, y: 540, width: 22, height: 22),
                forType: .widget,
                withProperties: nil
            )
            agree.widgetFieldType = .button
            agree.fieldName = "Agree"
            formPage.addAnnotation(agree)
        }
        let formURL = fixtures.appendingPathComponent("form.pdf")
        if let data = formDocument.dataRepresentation() {
            try? data.write(to: formURL)
        }
        if let reopened = PDFDocument(url: formURL) {
            check("PDFForms.fieldNames", PDFForms.fieldNames(in: reopened) == ["FullName", "Agree"],
                  "\(PDFForms.fieldNames(in: reopened))")
            check("PDFForms.currentValues", PDFForms.currentValues(in: reopened)["FullName"] == "Ada Lovelace",
                  "\(PDFForms.currentValues(in: reopened))")
            let updated = PDFForms.apply(["FullName": "Grace Hopper", "Agree": "yes"], to: reopened)
            check("PDFForms.apply", updated == 2, "updated=\(updated)")
            let agreeState = reopened.page(at: 0)?.annotations.first { $0.fieldName == "Agree" }?.buttonWidgetState
            check("PDFForms.apply checkbox", agreeState == .onState, "\(String(describing: agreeState))")

            let flattenedForm = PDFWork.flatten(reopened)
            let formText = flattenedForm.page(at: 0).flatMap { page -> String in
                guard let image = PDFWork.image(page, scale: 2) else { return "" }
                return VisionText.text(image)
            } ?? ""
            check("PDFForms flatten keeps answers", formText.uppercased().contains("GRACE"),
                  "text=\(formText.prefix(120))")
            check("PDFForms flatten drops widgets",
                  flattenedForm.page(at: 0)?.annotations.isEmpty == true,
                  "\(flattenedForm.page(at: 0)?.annotations.count ?? -1)")
        } else {
            check("PDFForms.fieldNames", false, "form fixture did not reopen")
        }

        if let image = gradientImage(width: 400, height: 300) {
            let imagesPDF = PDFDocument()
            if let page = PDFPage(image: NSImage(cgImage: image, size: NSSize(width: 400, height: 300))) {
                imagesPDF.insert(page, at: 0)
            }
            check("Images to PDF", imagesPDF.pageCount == 1)
        }

        if let scanned = textImage() {
            let pageSize = CGSize(width: 612, height: 792)
            let searchable = PDFWork.searchable(pages: [(scanned, pageSize)])
            let text = searchable.page(at: 0)?.string ?? ""
            check("PDFWork.searchable", searchable.pageCount == 1 && text.uppercased().contains("NOOKIT"),
                  "text=\(text.prefix(80))")
            if let page = searchable.page(at: 0) {
                check("PDFWork.searchable page size", PDFWork.displaySize(page) == pageSize,
                      "\(PDFWork.displaySize(page))")
            }
        } else {
            check("PDFWork.searchable", false, "no text fixture")
        }

        let encrypted = fixtures.appendingPathComponent("encrypted.pdf")
        let secret = PDFComposer.make(text: "Nookit secret page")
        let wroteEncrypted = secret.write(to: encrypted, withOptions: [
            PDFDocumentWriteOption.userPasswordOption: "nookit",
            PDFDocumentWriteOption.ownerPasswordOption: "nookit"
        ])
        check("PDF password write", wroteEncrypted)
        if wroteEncrypted, let locked = PDFDocument(url: encrypted) {
            check("PDF password locks document", locked.isLocked)
            check("PDF unlock with password", locked.unlock(withPassword: "nookit"))
            if let data = locked.dataRepresentation() {
                let unlockedURL = output.appendingPathComponent("unlocked.pdf")
                try? data.write(to: unlockedURL)
                check("PDF unlocked copy opens", PDFDocument(url: unlockedURL) != nil)
            }
        }

        let tall = PDFComposer.make(from: NSAttributedString(string: longText), pageSize: CGSize(width: 400, height: 1600))
        if let data = tall.dataRepresentation() {
            let sliced = PDFSlicer.slice(data, pageHeight: 600)
            check("PDFSlicer.slice", sliced.pageCount == 3, "pages=\(sliced.pageCount)")
        } else {
            check("PDFSlicer.slice", false, "no data")
        }

        if let doc = PDFDocument(url: multiURL) {
            let paragraphs = PDFText.paragraphs(from: doc)
            check("PDFText.paragraphs", !paragraphs.isEmpty && paragraphs.contains { $0.text.contains("Nookit") },
                  "paragraphs=\(paragraphs.count)")
        }
    }

    // MARK: Documents

    private func runDocumentTests() async {
        let markdown = """
        # Nookit

        A short paragraph with **bold** and `code`.

        | Tool | Ready |
        | --- | --- |
        | PDF | Yes |
        | Video | Yes |

        1. First step
        2. Second step

        > Keep it local.

        ```swift
        let nookit = true
        ```
        """
        let headings = MarkdownRenderer.headings(from: markdown)
        check("MarkdownRenderer.headings", headings.count == 1 && headings.first?.text == "Nookit",
              "\(headings)")

        let attributed = MarkdownRenderer.attributed(from: markdown)
        check("MarkdownRenderer.attributed", attributed.string.contains("Nookit")
              && attributed.string.contains("First step")
              && attributed.string.contains("let nookit = true")
              && attributed.string.contains("PDF"))

        let markdownPDF = PDFComposer.make(from: attributed, title: "Nookit")
        check("Markdown to PDF", markdownPDF.pageCount >= 1)
        if let url = Optional(output.appendingPathComponent("markdown.pdf")) {
            _ = markdownPDF.write(to: url, withOptions: [:])
            checkURL("Markdown PDF written", url)
        }

        let docxURL = fixtures.appendingPathComponent("report.docx")
        do {
            try DocxWriter.make(paragraphs: [
                DocxWriter.Paragraph("Nookit Report", heading: 1),
                DocxWriter.Paragraph("Body text with <tags> & symbols"),
                DocxWriter.Paragraph("Bullet one", bullet: true)
            ], title: "Nookit Test", to: docxURL)
            check("DocxWriter.make", fm.fileExists(atPath: docxURL.path))
        } catch {
            check("DocxWriter.make", false, error.localizedDescription)
        }

        let pptxURL = fixtures.appendingPathComponent("deck.pptx")
        let xlsxURL = fixtures.appendingPathComponent("sheet.xlsx")
        do {
            try await makeZip([
                "ppt/presentation.xml": #"<?xml version="1.0"?><p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldSz cx="9144000" cy="6858000"/></p:presentation>"#,
                "ppt/slides/slide1.xml": #"<?xml version="1.0"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>Hello slide</a:t></a:r></a:p><a:p><a:r><a:t>Second line</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>"#,
                "ppt/slides/slide2.xml": #"<?xml version="1.0"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>Closing</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>"#
            ], at: pptxURL)
            try await makeZip([
                "xl/sharedStrings.xml": #"<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>Alpha</t></si><si><t>Beta</t></si><si><t>10</t></si></sst>"#,
                "xl/worksheets/sheet1.xml": #"<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row><c t="s"><v>0</v></c><c t="s"><v>1</v></c></row><row><c t="s"><v>2</v></c><c><v>42</v></c></row></sheetData></worksheet>"#
            ], at: xlsxURL)
            checkDeckAndSheet(pptxURL, xlsxURL)
        } catch {
            check("Office fixtures", false, error.localizedDescription)
        }
    }

    private func checkDeckAndSheet(_ pptxURL: URL, _ xlsxURL: URL) {
        do {
            let deck = try OfficeXML.presentation(pptxURL)
            check("OfficeXML.presentation", deck.slides.count == 2
                  && deck.slides.first?.contains("Hello slide") == true
                  && deck.slides.last?.contains("Closing") == true,
                  "slides=\(deck.slides)")
            check("OfficeXML.slideAttributed", OfficeXML.slideAttributed(deck.slides.first ?? []).string.contains("Hello slide"))
            let deckPDF = PDFComposer.make(from: OfficeXML.slideAttributed(deck.slides.first ?? []), pageSize: deck.pageSize)
            check("PowerPoint fallback PDF", deckPDF.pageCount >= 1)
        } catch {
            check("OfficeXML.presentation", false, error.localizedDescription)
        }

        do {
            let sheets = try OfficeXML.spreadsheet(xlsxURL)
            let values = sheets.flatMap { $0.1.flatMap { $0 } }
            check("OfficeXML.spreadsheet", values.contains("Alpha") && values.contains("Beta") && values.contains("42"),
                  "values=\(values)")
            let table = TablePDF.make(sheets: sheets)
            check("TablePDF.make", table.pageCount >= 1, "pages=\(table.pageCount)")
        } catch {
            check("OfficeXML.spreadsheet", false, error.localizedDescription)
        }
    }

    // MARK: Text

    private func runTextTests() {
        let textURL = fixtures.appendingPathComponent("notes.txt")
        try? write("First paragraph.\n\nSecond paragraph.\n\nThird paragraph.", to: textURL)
        let pages = TextExtract.pages(textURL)
        check("TextExtract.pages plain text", pages.count == 3, "pages=\(pages.count)")
        check("TextExtract.plain", TextExtract.plain(textURL).contains("Second paragraph"))

        if let pdf = PDFDocument(url: fixtures.appendingPathComponent("one.pdf")) {
            let extracted = TextExtract.plain(fixtures.appendingPathComponent("one.pdf"))
            check("TextExtract.pages PDF", extracted.contains("Nookit") && pdf.pageCount >= 1,
                  "text=\(extracted.prefix(50))")
        }

        check("Extractor.text plain", (try? Extractor.text(from: textURL))?.contains("Third paragraph") == true)
        check("Extractor.text PDF", (try? Extractor.text(from: fixtures.appendingPathComponent("one.pdf")))?.contains("Nookit") == true)

        let srt = """
        1
        00:00:00,000 --> 00:00:02,500
        Hello from Nookit.

        2
        00:00:02,500 --> 00:00:05,000
        Everything stays local.
        """
        let cues = SubtitleFile.parse(srt)
        check("SubtitleFile.parse", cues.count == 2 && cues[0].text == "Hello from Nookit.",
              "cues=\(cues.count)")
        let roundTrip = SubtitleFile.parse(SubtitleFile.srt(cues))
        check("SubtitleFile.srt round-trip", roundTrip.count == 2 && roundTrip[1].text == "Everything stays local.")

        let srtURL = fixtures.appendingPathComponent("captions.srt")
        try? write(srt, to: srtURL)
        check("SubtitleFile.parse file", SubtitleFile.parse(contentsOf: srtURL).count == 2)

        check("SubtitleFile.seconds SRT", SubtitleFile.seconds("00:01:02,500") == 62.5)
        check("SubtitleFile.seconds ASS", SubtitleFile.seconds("0:00:03.25") == 3.25)
        check("SubtitleFile.seconds VTT short", SubtitleFile.seconds("01:02.500") == 62.5)
        check("SubtitleFile.seconds invalid", SubtitleFile.seconds("later") == nil)

        let ass = """
        [Script Info]
        Title: Nookit

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:00.00,0:00:01.50,Default,,0,0,0,,{\\i1}Hello ASS{\\i0}
        Dialogue: 0,0:00:02.00,0:00:03.00,Default,,0,0,0,,Second\\Nline
        """
        let assCues = SubtitleFile.parse(ass)
        check("SubtitleFile.parse ASS", assCues.count == 2
              && assCues[0].text == "Hello ASS"
              && assCues[1].text == "Second line",
              "cues=\(assCues.map(\.text))")

        let paragraph = "Nookit keeps files on this Mac. It never uploads documents or photos. Results go to a dated folder. Originals are not changed. The notch holds small daily tools."
        let sentences = TextRank.sentences(paragraph)
        check("TextRank.sentences", sentences.count >= 4, "\(sentences.count)")
        let summary = TextRank.summarize(paragraph, sentences: 2)
        check("TextRank.summarize", summary.count <= 2 && !summary.isEmpty, "\(summary.count)")

        check("TimeText.seconds clock", TimeText.seconds("1:02:03.5") == 3723.5)
        check("TimeText.seconds plain", TimeText.seconds("12") == 12)
        check("TimeText.seconds invalid", TimeText.seconds("-2") == nil)
        check("TimeText.string", TimeText.string(65.5) == "1:05.50", TimeText.string(65.5))
        check("TimeText.clock", TimeText.clock(65) == "1:05", TimeText.clock(65))

        check("Fmt.safeFilename slashes", Fmt.safeFilename("a/b:c?d") == "a-b-c-d", Fmt.safeFilename("a/b:c?d"))
        check("Fmt.safeFilename empty", Fmt.safeFilename("   ") == "Untitled")
        check("Fmt.safeFilename length", Fmt.safeFilename(String(repeating: "a", count: 200)).count == 120)

        let md5 = Fmt.hex(Data(Insecure.MD5.hash(data: Data("abc".utf8))))
        let sha256 = Fmt.hex(Data(SHA256.hash(data: Data("abc".utf8))))
        check("Hash MD5 vector", md5 == "900150983cd24fb0d6963f7d28e17f72", md5)
        check("Hash SHA-256 vector", sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", sha256)

        let json = ToolFormat.json(["b": 2, "a": 1])
        check("ToolFormat.json sorted", json.contains("\"a\" : 1") && json.contains("\"b\" : 2") && json.contains("\n"),
              json)
    }

    // MARK: Utilities

    private func runUtilityTests() async {
        let golden = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let dms = CoordinateMath.dms(golden.latitude, latitude: true)
        check("CoordinateMath.dms", dms.contains("37°") && dms.hasSuffix("N"), dms)
        check("CoordinateMath.dms south", CoordinateMath.dms(-33.8688, latitude: true).hasSuffix("S"))
        check("CoordinateMath.ddm", CoordinateMath.ddm(golden.latitude, latitude: true).contains("46."))

        let pair = CoordinateMath.decimalPair(golden)
        check("CoordinateMath.decimalPair", pair == "37.774900, -122.419400", pair)

        let utm = CoordinateMath.utm(golden)
        check("CoordinateMath.utm zone", utm.hasPrefix("10S"), utm)
        check("CoordinateMath.utm values", utm.contains("m E") && utm.contains("m N"), utm)
        check("CoordinateMath.utm polar", CoordinateMath.utm(CLLocationCoordinate2D(latitude: 89, longitude: 0)).contains("Not defined"))

        let losAngeles = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        let distance = CoordinateMath.distance(from: golden, to: losAngeles)
        check("CoordinateMath.distance", distance > 540_000 && distance < 580_000, "\(Int(distance)) m")
        let bearing = CoordinateMath.bearing(from: golden, to: losAngeles)
        check("CoordinateMath.bearing", bearing > 120 && bearing < 160, "\(Int(bearing))°")
        check("CoordinateMath.compass", CoordinateMath.compass(0) == "N 0°", CoordinateMath.compass(0))
        check("CoordinateMath.compass east", CoordinateMath.compass(90) == "E 90°", CoordinateMath.compass(90))
        check("CoordinateMath.compass southwest", CoordinateMath.compass(225) == "SW 225°", CoordinateMath.compass(225))
        check("CoordinateMath.latitudeBand", CoordinateMath.latitudeBand(37.7749) == "S")

        check("FFmpeg.atempo normal", FFmpeg.atempo(1.5) == "atempo=1.5000", FFmpeg.atempo(1.5))
        check("FFmpeg.atempo unity", FFmpeg.atempo(1) == "atempo=1")
        check("FFmpeg.atempo fast chain", FFmpeg.atempo(4) == "atempo=2.0000,atempo=2.0000", FFmpeg.atempo(4))
        check("FFmpeg.atempo slow chain", FFmpeg.atempo(0.25) == "atempo=0.5000,atempo=0.5000", FFmpeg.atempo(0.25))
        check("FFmpeg.even rounds up", FFmpeg.even(3.2) == 4)
        check("FFmpeg.even keeps even", FFmpeg.even(4) == 4)
        check("FFmpeg.even minimum", FFmpeg.even(0) == 2)
        check("FFmpeg.filterEscape", FFmpeg.filterEscape("a:b,c[d]") == "a\\:b\\,c\\[d\\]",
              FFmpeg.filterEscape("a:b,c[d]"))

        let mp3 = AudioExport.arguments(format: .mp3, bitrate: 192, sampleRate: 44100)
        check("AudioExport mp3 args", mp3.contains("libmp3lame") && mp3.contains("192k") && mp3.contains("44100"),
              "\(mp3)")
        let wav = AudioExport.arguments(format: .wav, bitrate: 192, sampleRate: nil)
        check("AudioExport wav args", wav == ["-c:a", "pcm_s16le"], "\(wav)")

        check("TimeText rejects overflow", TimeText.seconds("1:2:3:4") == nil)

        // ResultStore never overwrites: writing the same name twice creates two files.
        let folder = output.appendingPathComponent("store-test", isDirectory: true)
        if let first = try? ResultStore.shared.write(string: "one", to: folder, filename: "same.txt"),
           let second = try? ResultStore.shared.write(string: "two", to: folder, filename: "same.txt") {
            check("ResultStore.write never overwrites",
                  first != second && fm.fileExists(atPath: first.path) && fm.fileExists(atPath: second.path),
                  "\(first.lastPathComponent) vs \(second.lastPathComponent)")
        } else {
            check("ResultStore.write never overwrites", false)
        }

        // Zip through the same ditto path used by the Zip & Unzip tool.
        let zipSource = fixtures.appendingPathComponent("zip-source", isDirectory: true)
        try? fm.createDirectory(at: zipSource, withIntermediateDirectories: true)
        try? write("zipped contents", to: zipSource.appendingPathComponent("inside.txt"))
        let zipURL = fixtures.appendingPathComponent("archive.zip")
        let create = await shell("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", zipSource.path, zipURL.path])
        check("Zip create", create.succeeded && fm.fileExists(atPath: zipURL.path))
        let extractFolder = output.appendingPathComponent("unzipped", isDirectory: true)
        let extract = await shell("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractFolder.path])
        let found = (fm.enumerator(at: extractFolder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .first { $0.lastPathComponent == "inside.txt" })
        check("Zip extract", extract.succeeded && found != nil)
        if let found {
            check("Zip extract contents", (try? String(contentsOf: found, encoding: .utf8)) == "zipped contents")
        }

        // QR generation and detection share the CoreImage path used by the tool.
        let message = "https://nookit.app/test?x=1"
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "H"
        if let output = filter.outputImage {
            let scale = 8.0
            let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let context = CIContext()
            if let cg = context.createCGImage(scaled, from: scaled.extent) {
                check("QR generate", cg.width == Int(output.extent.width * scale), "\(cg.width)")
                let ci = CIImage(cgImage: cg)
                let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                          options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
                let decoded = detector?.features(in: ci)
                    .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
                    .joined() ?? ""
                check("QR decode", decoded == message, decoded)
            } else {
                check("QR generate", false, "no CGImage")
            }
        } else {
            check("QR generate", false, "no output image")
        }

        // Duplicate scanning: identical payloads with different names group together.
        let duplicates = fixtures.appendingPathComponent("duplicates", isDirectory: true)
        try? fm.createDirectory(at: duplicates, withIntermediateDirectories: true)
        let body = String(repeating: "nookit duplicate fixture ", count: 400)
        try? write(body, to: duplicates.appendingPathComponent("a.txt"))
        try? write(body, to: duplicates.appendingPathComponent("b.txt"))
        try? write("different", to: duplicates.appendingPathComponent("c.txt"))
        let groups = DuplicateScanner.find(in: [duplicates], includeSmall: true, status: { _ in })
        check("DuplicateScanner.find", groups.count == 1 && groups.first?.files.count == 2,
              "groups=\(groups.count)")
        let digest = DuplicateScanner.hash(duplicates.appendingPathComponent("a.txt"))
        check("DuplicateScanner.hash", digest == hash(Data(body.utf8)), "digest=\(digest?.prefix(12) ?? "nil")")

        // File helpers used by every tool.
        let uniqueA = uniqueFile(output, "unique.txt")
        try? "x".write(to: uniqueA, atomically: true, encoding: .utf8)
        let uniqueB = uniqueFile(output, "unique.txt")
        check("ExtraFiles.unique", uniqueB != uniqueA && uniqueB.lastPathComponent == "unique 1.txt",
              uniqueB.lastPathComponent)
        check("ExtraFiles.size", ExtraFiles.size(uniqueA) == 1, "\(ExtraFiles.size(uniqueA))")
        let listed = ExtraFiles.files(in: output).map { $0.resolvingSymlinksInPath() }
        check("ExtraFiles.files", listed.contains(uniqueA.resolvingSymlinksInPath()))

        // MARK: Developer tool logic

        let b64Text = "Nookit ✓ — local only"
        let standard = DeveloperLogic.base64Encode(b64Text, urlSafe: false)
        let urlSafe = DeveloperLogic.base64Encode(b64Text, urlSafe: true)
        check("Base64 encode", standard == Data(b64Text.utf8).base64EncodedString(), standard)
        check("Base64 URL-safe", !urlSafe.contains("+") && !urlSafe.contains("/") && !urlSafe.contains("="),
              urlSafe)
        check("Base64 round-trip", DeveloperLogic.base64Decode(standard).text == b64Text)
        check("Base64 URL-safe round-trip", DeveloperLogic.base64Decode(urlSafe).text == b64Text)
        check("Base64 known value", DeveloperLogic.base64Decode("Tm9va2l0").text == "Nookit")
        check("Base64 rejects junk", DeveloperLogic.base64Decode("a").error != nil)

        let header = DeveloperLogic.base64Encode(#"{"alg":"HS256","typ":"JWT"}"#, urlSafe: true)
        let payload = DeveloperLogic.base64Encode(#"{"sub":"nookit","iss":"local","exp":1700000000}"#, urlSafe: true)
        let token = "\(header).\(payload).signature"
        let parts = DeveloperLogic.jwtParts(token)
        check("JWT header", parts.header.contains("HS256") && parts.error == nil, parts.header)
        check("JWT payload", parts.payload.contains("nookit"), parts.payload)
        let claims = DeveloperLogic.jwtClaims(token)
        check("JWT claims", claims.contains { $0.0 == "sub" && $0.1.contains("nookit") },
              "\(claims.map(\.0))")
        check("JWT incomplete", DeveloperLogic.jwtParts("not-a-token").error != nil)

        let diffRows = DeveloperLogic.diff("a\nb\nc", "a\nx\nc")
        check("Diff marks removal", diffRows.contains { $0.0 == .removed && $0.1 == "b" },
              "\(diffRows)")
        check("Diff marks addition", diffRows.contains { $0.0 == .added && $0.1 == "x" })
        check("Diff keeps unchanged", diffRows.filter { $0.0 == .same }.count == 2)

        let caps = DeveloperLogic.regexMatches(
            pattern: #"\b[A-Z]{2,}\b"#,
            text: "Nookit keeps PDF and JSON on-device.",
            caseInsensitive: false,
            multiline: false
        )
        check("Regex matches", caps.map(\.text) == ["PDF", "JSON"], "\(caps.map(\.text))")
        let ignored = DeveloperLogic.regexMatches(
            pattern: "pdfs",
            text: "PDFs",
            caseInsensitive: true,
            multiline: false
        )
        check("Regex ignore case", ignored.count == 1)
        check("Regex reports bad pattern", DeveloperLogic.regexError(pattern: "(", caseInsensitive: false) != nil)

        let dirty = "https://example.com/article?utm_source=news&utm_medium=email&id=42#top"
        let clean = DeveloperLogic.cleanLinks(dirty)
        check("Clean Links strips tracking", !clean.contains("utm_source") && !clean.contains("utm_medium"),
              clean)
        check("Clean Links keeps real parameters", clean.contains("id=42") && clean.hasSuffix("#top"), clean)
        check("Clean Links counts removals", DeveloperLogic.removedLinkParameters(dirty) == 2,
              "\(DeveloperLogic.removedLinkParameters(dirty))")
        let lines = DeveloperLogic.cleanLinks("https://a.test/?fbclid=1&x=1\n\nnot a url")
        check("Clean Links keeps blank lines", lines.contains("\n\n") && lines.contains("not a url"), lines)

        let lorem = DeveloperLogic.lorem(paragraphs: 2, sentences: 3, startClassic: true)
        check("Lorem classic opening", lorem.hasPrefix("Lorem ipsum"))
        check("Lorem paragraphs", lorem.components(separatedBy: "\n\n").count == 2)
        check("Lorem sentences", lorem.components(separatedBy: ". ").count >= 5)

        let hyphenated = DeveloperLogic.uuid(upper: false, hyphens: true)
        let plain = DeveloperLogic.uuid(upper: true, hyphens: false)
        check("UUID hyphenated", hyphenated.count == 36 && hyphenated.contains("-"))
        check("UUID compact uppercase", plain.count == 32 && plain == plain.uppercased() && !plain.contains("-"))

        // MARK: Text tool logic

        let stats = TextLogic.stats("Hello world. Second line!\nNew paragraph.")
        check("WordCounter words", stats.words.count == 6, "\(stats.words)")
        check("WordCounter sentences", stats.sentences == 3, "\(stats.sentences)")
        check("WordCounter paragraphs", stats.paragraphs == 2, "\(stats.paragraphs)")
        check("WordCounter reading time", stats.readingSeconds == 1, "\(stats.readingSeconds)")
        check("WordCounter top words", stats.topWords.first?.0 == "hello", "\(stats.topWords)")

        check("Case sentence", TextLogic.convert("THE QUICK FOX", to: .sentence) == "The quick fox")
        check("Case title", TextLogic.convert("the quick fox", to: .title) == "The Quick Fox")
        check("Case upper", TextLogic.convert("nookit", to: .upper) == "NOOKIT")
        check("Case lower", TextLogic.convert("NOOKIT", to: .lower) == "nookit")
        check("Case camel", TextLogic.convert("hello-world test", to: .camel) == "helloWorldTest")
        check("Case pascal", TextLogic.convert("hello_world test", to: .pascal) == "HelloWorldTest")
        check("Case snake", TextLogic.convert("hello world-test", to: .snake) == "hello_world_test")
        check("Case kebab", TextLogic.convert("hello_world test", to: .kebab) == "hello-world-test")

        check("Batch Rename tokens",
              TextLogic.renamed(pattern: "{name}-{n}.{ext}", base: "photo", ext: "jpg",
                                index: 0, start: 1, date: "2026") == "photo-1.jpg")
        check("Batch Rename adds extension",
              TextLogic.renamed(pattern: "{name}-edit", base: "photo", ext: "jpg",
                                index: 0, start: 1, date: "2026") == "photo-edit.jpg")
        check("Batch Rename keeps extension",
              TextLogic.renamed(pattern: "done.{ext}", base: "photo", ext: "png",
                                index: 0, start: 1, date: "2026") == "done.png")
        check("Batch Rename empty pattern",
              TextLogic.renamed(pattern: "", base: "photo", ext: "jpg",
                                index: 0, start: 1, date: "2026") == "photo.jpg")

        // Text to Speech: `say` must produce a readable AIFF without blocking
        // the caller (the tool awaits Shell.run).
        let speech = output.appendingPathComponent("speech-selftest.aiff")
        do {
            let result = try await Shell.run(
                "/usr/bin/say",
                ["-v", "Samantha", "-r", "180", "-o", speech.path, "Nookit"],
                timeout: 120
            )
            check("Text to Speech renders", result.succeeded && ExtraFiles.size(speech) > 1000,
                  "status=\(result.status) size=\(ExtraFiles.size(speech))")
        } catch {
            check("Text to Speech renders", false, error.localizedDescription)
        }
    }

    // MARK: FFmpeg

    private func runFFmpegTests() async {
        guard FFmpeg.available else {
            skip("FFmpeg suite", "ffmpeg is not installed")
            return
        }

        let wav = fixtures.appendingPathComponent("tone.wav")
        let clip = fixtures.appendingPathComponent("clip.mp4")
        do {
            try await FFmpeg.checked(["-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=1.2",
                                      "-c:a", "pcm_s16le", wav.path])
            checkURL("FFmpeg generate WAV", wav)
            let wavDuration = await FFmpeg.duration(wav)
            check("FFmpeg.duration WAV", abs(wavDuration - 1.2) < 0.2, "\(wavDuration)")
            let wavHasAudio = await FFmpeg.hasAudio(wav)
            check("FFmpeg.hasAudio WAV", wavHasAudio)

            try await FFmpeg.checked(["-y",
                                      "-f", "lavfi", "-i", "testsrc=size=320x240:rate=24",
                                      "-f", "lavfi", "-i", "sine=frequency=330:duration=1.2",
                                      "-t", "1.2", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                                      "-c:a", "aac", "-shortest", clip.path])
            checkURL("FFmpeg generate MP4", clip, minSize: 1000)
            let size = await FFmpeg.videoSize(clip)
            check("FFmpeg.videoSize", Int(size.width) == 320 && Int(size.height) == 240,
                  "\(Int(size.width))x\(Int(size.height))")
            let rotatedMeta = fixtures.appendingPathComponent("rotated-meta.mp4")
            try await FFmpeg.checked(["-y", "-display_rotation", "90", "-i", clip.path, "-c", "copy", rotatedMeta.path])
            let rotatedSize = await FFmpeg.videoSize(rotatedMeta)
            check("FFmpeg.videoSize honours rotation",
                  Int(rotatedSize.width) == 240 && Int(rotatedSize.height) == 320,
                  "\(Int(rotatedSize.width))x\(Int(rotatedSize.height))")
            let videoHasAudio = await FFmpeg.hasAudio(clip)
            check("FFmpeg.hasAudio video", videoHasAudio)
        } catch {
            check("FFmpeg fixtures", false, error.localizedDescription)
            return
        }

        // Audio convert
        let mp3 = output.appendingPathComponent("tone.mp3")
        do {
            var args = ["-y", "-i", wav.path]
            args += AudioExport.arguments(format: .mp3, bitrate: 192, sampleRate: 44100)
            args.append(mp3.path)
            try await FFmpeg.checked(args)
            checkURL("FFmpeg convert WAV→MP3", mp3, minSize: 1000)
            let mp3HasAudio = await FFmpeg.hasAudio(mp3)
            check("FFmpeg MP3 has audio", mp3HasAudio)
        } catch {
            check("FFmpeg convert WAV→MP3", false, error.localizedDescription)
        }

        // Clean-up filter chain used by Clean Up Audio
        let cleaned = output.appendingPathComponent("tone-clean.m4a")
        do {
            try await FFmpeg.checked(["-y", "-i", wav.path,
                                      "-af", "afftdn=nf=-25:nr=12,highpass=f=80,lowpass=f=14000,loudnorm=I=-16:TP=-1.5:LRA=11",
                                      "-c:a", "aac", "-b:a", "192k", cleaned.path])
            checkURL("FFmpeg clean audio", cleaned, minSize: 1000)
        } catch {
            check("FFmpeg clean audio", false, error.localizedDescription)
        }

        // Trim to the middle half
        let trimmed = output.appendingPathComponent("tone-trimmed.m4a")
        do {
            try await FFmpeg.checked(["-y", "-ss", "0.300", "-to", "0.900", "-i", wav.path,
                                      "-c:a", "aac", "-b:a", "192k", trimmed.path])
            let duration = await FFmpeg.duration(trimmed)
            check("FFmpeg trim audio", abs(duration - 0.6) < 0.25, "\(duration)")
        } catch {
            check("FFmpeg trim audio", false, error.localizedDescription)
        }

        // Video mute (Video tool)
        let muted = output.appendingPathComponent("clip-muted.mp4")
        do {
            try await FFmpeg.checked(["-y", "-i", clip.path, "-an", "-c:v", "copy", muted.path])
            checkURL("FFmpeg mute video", muted, minSize: 1000)
            let mutedHasAudio = await FFmpeg.hasAudio(muted)
            check("FFmpeg mute removes audio", !mutedHasAudio)
        } catch {
            check("FFmpeg mute video", false, error.localizedDescription)
        }

        // Extract audio from video
        let extracted = output.appendingPathComponent("clip-audio.m4a")
        do {
            try await FFmpeg.checked(["-y", "-i", clip.path, "-vn", "-c:a", "aac", "-b:a", "160k", extracted.path])
            checkURL("FFmpeg extract audio", extracted, minSize: 1000)
            let extractedHasAudio = await FFmpeg.hasAudio(extracted)
            check("FFmpeg extracted audio track", extractedHasAudio)
        } catch {
            check("FFmpeg extract audio", false, error.localizedDescription)
        }

        // Resize video
        let resized = output.appendingPathComponent("clip-160x120.mp4")
        do {
            try await FFmpeg.checked(["-y", "-i", clip.path,
                                      "-vf", "scale=160:120:force_original_aspect_ratio=decrease,pad=160:120:(ow-iw)/2:(oh-ih)/2:color=black",
                                      "-c:v", "libx264", "-preset", "ultrafast", "-crf", "24",
                                      "-c:a", "aac", "-b:a", "96k", resized.path])
            let size = await FFmpeg.videoSize(resized)
            check("FFmpeg resize video", Int(size.width) == 160 && Int(size.height) == 120,
                  "\(Int(size.width))x\(Int(size.height))")
        } catch {
            check("FFmpeg resize video", false, error.localizedDescription)
        }

        // Rotate video
        let rotated = output.appendingPathComponent("clip-rotated.mp4")
        do {
            try await FFmpeg.checked(["-y", "-i", clip.path, "-vf", "transpose=1",
                                      "-c:v", "libx264", "-preset", "ultrafast", "-crf", "24",
                                      "-c:a", "aac", "-b:a", "96k", rotated.path])
            let size = await FFmpeg.videoSize(rotated)
            check("FFmpeg rotate video", Int(size.width) == 240 && Int(size.height) == 320,
                  "\(Int(size.width))x\(Int(size.height))")
        } catch {
            check("FFmpeg rotate video", false, error.localizedDescription)
        }

        // Speed change with atempo
        let speed = output.appendingPathComponent("clip-2x.mp4")
        do {
            try await FFmpeg.checked(["-y", "-i", clip.path,
                                      "-filter:v", "setpts=PTS/2.000000",
                                      "-filter:a", FFmpeg.atempo(2),
                                      "-c:v", "libx264", "-preset", "ultrafast", "-crf", "24",
                                      "-c:a", "aac", "-b:a", "128k", speed.path])
            let duration = await FFmpeg.duration(speed)
            check("FFmpeg speed 2x", abs(duration - 0.6) < 0.3, "\(duration)")
            let speedHasAudio = await FFmpeg.hasAudio(speed)
            check("FFmpeg speed keeps audio", speedHasAudio)
        } catch {
            check("FFmpeg speed 2x", false, error.localizedDescription)
        }

        // Extract frames at 2 fps
        let frames = output.appendingPathComponent("frames", isDirectory: true)
        try? fm.createDirectory(at: frames, withIntermediateDirectories: true)
        do {
            try await FFmpeg.checked(["-y", "-i", clip.path, "-vf", "fps=2",
                                      frames.appendingPathComponent("frame-%03d.png").path])
            let files = ExtraFiles.files(in: frames)
            check("FFmpeg extract frames", files.count >= 2, "frames=\(files.count)")
        } catch {
            check("FFmpeg extract frames", false, error.localizedDescription)
        }

        // GIF palette chain
        let gif = output.appendingPathComponent("clip.gif")
        do {
            let filter = "fps=10,scale=160:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=256:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle"
            try await FFmpeg.checked(["-y", "-ss", "0", "-to", "0.8", "-i", clip.path,
                                      "-vf", filter, "-loop", "0", gif.path])
            checkURL("FFmpeg GIF", gif, minSize: 1000)
        } catch {
            check("FFmpeg GIF", false, error.localizedDescription)
        }

        // Replace audio, including the mix filter used when original audio exists.
        let replacement = output.appendingPathComponent("clip-new-audio.mp4")
        do {
            try await FFmpeg.checked(["-y", "-i", clip.path, "-i", wav.path,
                                      "-filter_complex", "[0:a]volume=0.350[orig];[1:a]volume=1.000[new];[orig][new]amix=inputs=2:duration=first:dropout_transition=0[a]",
                                      "-map", "0:v:0", "-map", "[a]", "-c:v", "copy", "-c:a", "aac",
                                      "-b:a", "192k", "-shortest", "-movflags", "+faststart", replacement.path])
            checkURL("FFmpeg replace/mix audio", replacement, minSize: 1000)
            let mixedHasAudio = await FFmpeg.hasAudio(replacement)
            check("FFmpeg mix keeps audio", mixedHasAudio)
        } catch {
            check("FFmpeg replace/mix audio", false, error.localizedDescription)
        }

        // Merge two clips.
        let merged = output.appendingPathComponent("clip-merged.mp4")
        let list = root.appendingPathComponent("concat.txt")
        try? "file '\(clip.path)'\nfile '\(clip.path)'\n".write(to: list, atomically: true, encoding: .utf8)
        do {
            try await FFmpeg.checked(["-y", "-f", "concat", "-safe", "0", "-i", list.path,
                                      "-c:v", "libx264", "-preset", "ultrafast", "-crf", "24",
                                      "-c:a", "aac", "-b:a", "128k", merged.path])
            let duration = await FFmpeg.duration(merged)
            check("FFmpeg merge videos", duration > 1.8, "duration=\(duration)")
        } catch {
            check("FFmpeg merge videos", false, error.localizedDescription)
        }

        // Burn subtitles. Use FFmpeg's subtitles filter when this build has
        // libass, otherwise the AVFoundation fallback the tool ships.
        let srt = fixtures.appendingPathComponent("burn.srt")
        try? write("1\n00:00:00,000 --> 00:00:01,000\nNOOKIT\n", to: srt)
        let burned = output.appendingPathComponent("clip-burned.mp4")
        do {
            if await FFmpeg.hasFilter("subtitles") {
                let filter = "subtitles='\(FFmpeg.filterEscape(srt.path))':force_style='FontName=Helvetica,FontSize=32'"
                try await FFmpeg.checked(["-y", "-i", clip.path, "-vf", filter,
                                          "-c:v", "libx264", "-preset", "ultrafast", "-crf", "24",
                                          "-c:a", "aac", "-b:a", "128k", burned.path])
                checkURL("Burn subtitles (FFmpeg)", burned, minSize: 1000)
            } else {
                let cues = SubtitleFile.parse(contentsOf: srt)
                try await SubtitleBurner.burn(video: clip, cues: cues, fontSize: 48, to: burned)
                checkURL("Burn subtitles (native fallback)", burned, minSize: 1000)
            }
            let burnedDuration = await FFmpeg.duration(burned)
            check("Burn subtitles keeps duration", abs(burnedDuration - 1.2) < 0.35, "\(burnedDuration)")

            let frame = output.appendingPathComponent("burned-frame.png")
            try await FFmpeg.checked(["-y", "-ss", "0.4", "-i", burned.path, "-frames:v", "1", frame.path])
            if let image = ImageEngine.source(frame) {
                let recognised = VisionText.text(image)
                check("Burn subtitles renders text", recognised.uppercased().contains("NOOKIT"),
                      "recognised=\(recognised.prefix(60))")
            } else {
                check("Burn subtitles renders text", false, "could not read frame")
            }
        } catch {
            check("Burn subtitles", false, error.localizedDescription)
        }

        // AVFoundation composition/export path used by Media tools.
        let asset = AVURLAsset(url: clip)
        do {
            let composition = try await MediaExport.composition(from: asset, mediaTypes: [.video, .audio])
            check("MediaExport.composition", composition.tracks.count == 2,
                  "tracks=\(composition.tracks.count)")
            if let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) {
                session.outputFileType = .mov
                let target = output.appendingPathComponent("clip-composed.mov")
                try await MediaExport.export(session, to: target)
                checkURL("MediaExport.export", target, minSize: 1000)
            } else {
                check("MediaExport.export", false, "no export session")
            }
        } catch {
            check("MediaExport.composition", false, error.localizedDescription)
        }

        // Media Info reads the same metadata the tool shows.
        do {
            let rows = try await MediaInspector.rows(for: clip)
            let labels = rows.map(\.0)
            check("MediaInspector rows", labels.contains("Duration") && labels.contains("Resolution"),
                  "\(labels)")
            check("MediaInspector codec", rows.contains { $0.0 == "Track 1" && $0.1.contains("avc1") },
                  "\(rows)")
        } catch {
            check("MediaInspector rows", false, error.localizedDescription)
        }

        // Convert Video: every preset and both containers the UI offers.
        let presets: [(String, String)] = [
            (AVAssetExportPresetHighestQuality, "highest"),
            (AVAssetExportPresetMediumQuality, "medium"),
            (AVAssetExportPresetLowQuality, "low")
        ]
        let formats: [(AVFileType, String)] = [(.mp4, "mp4"), (.mov, "mov")]
        for (preset, presetName) in presets {
            for (fileType, ext) in formats {
                let label = "Convert Video \(presetName) \(ext.uppercased())"
                do {
                    let session = try await MediaExport.session(
                        for: .convert,
                        asset: asset,
                        presetName: preset,
                        fileType: fileType,
                        start: 0,
                        end: 0
                    )
                    let target = ExtraFiles.unique(output, "converted-\(presetName).\(ext)")
                    try await MediaExport.export(session, to: target)
                    checkURL(label, target, minSize: 1000)
                } catch {
                    check(label, false, error.localizedDescription)
                }
            }
        }

        // Trim Video keeps only the requested section.
        do {
            let session = try await MediaExport.session(
                for: .trim,
                asset: asset,
                presetName: AVAssetExportPresetHighestQuality,
                fileType: .mp4,
                start: 0.2,
                end: 0.8
            )
            let target = ExtraFiles.unique(output, "trimmed.mp4")
            try await MediaExport.export(session, to: target)
            checkURL("Trim Video export", target, minSize: 1000)
            let trimmed = await FFmpeg.duration(target)
            check("Trim Video duration", abs(trimmed - 0.6) < 0.25, "\(trimmed)")
        } catch {
            check("Trim Video export", false, error.localizedDescription)
        }

        // Mute Video removes the audio track.
        do {
            let session = try await MediaExport.session(
                for: .mute,
                asset: asset,
                presetName: AVAssetExportPresetHighestQuality,
                fileType: .mp4,
                start: 0,
                end: 0
            )
            let target = ExtraFiles.unique(output, "muted.mp4")
            try await MediaExport.export(session, to: target)
            checkURL("Mute Video export", target, minSize: 1000)
            let muted = AVURLAsset(url: target)
            let audio = try await muted.loadTracks(withMediaType: .audio)
            check("Mute Video has no audio", audio.isEmpty, "audio tracks=\(audio.count)")
        } catch {
            check("Mute Video export", false, error.localizedDescription)
        }

        // Extract Audio writes an M4A with a playable audio track.
        do {
            let session = try await MediaExport.session(
                for: .extractAudio,
                asset: asset,
                presetName: AVAssetExportPresetAppleM4A,
                fileType: .m4a,
                start: 0,
                end: 0
            )
            let target = ExtraFiles.unique(output, "extracted.m4a")
            try await MediaExport.export(session, to: target)
            checkURL("Extract Audio export", target, minSize: 1000)
            let extracted = AVURLAsset(url: target)
            let audio = try await extracted.loadTracks(withMediaType: .audio)
            check("Extract Audio track", audio.count == 1, "audio tracks=\(audio.count)")
        } catch {
            check("Extract Audio export", false, error.localizedDescription)
        }
    }

    // MARK: Dependencies / Mac

    private func runDependencyTests() async {
        check("FFmpeg.available", FFmpeg.available)

        // Document conversion: pandoc for Markdown, textutil for Office input.
        let md = fixtures.appendingPathComponent("notes.md")
        try? write("# Nookit\n\n**Local** conversion.", to: md)
        do {
            let html = try await DocumentConvert.prepareInput(md, folder: output)
            checkURL("DocumentConvert.prepareInput Markdown", html)
            check("DocumentConvert HTML output", (try? String(contentsOf: html, encoding: .utf8))?.contains("Nookit") == true)
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("pandoc") {
                skip("DocumentConvert.prepareInput Markdown", "pandoc not installed; the tool reports it clearly")
            } else {
                check("DocumentConvert.prepareInput Markdown", false, error.localizedDescription)
            }
        }

        let htmlURL = fixtures.appendingPathComponent("page.html")
        try? write("<html><body><h1>Title</h1><p>Body text</p></body></html>", to: htmlURL)
        do {
            let html = try await DocumentConvert.htmlString(htmlURL)
            check("DocumentConvert.htmlString", html.lowercased().contains("<html") && html.contains("Title"))
            let attributed = DocumentConvert.attributedHTML(html)
            check("DocumentConvert.attributedHTML", attributed?.string.contains("Title") == true
                  && attributed?.string.contains("Body text") == true)
            if let attributed {
                let pdf = PDFComposer.make(from: attributed, title: "Word to PDF")
                check("Word to PDF fallback", pdf.pageCount >= 1 && (pdf.page(at: 0)?.string?.contains("Title") == true))
            }
        } catch {
            check("DocumentConvert.htmlString", false, error.localizedDescription)
        }

        // Optional tools should be discoverable, not required.
        for tool in ["pandoc", "soffice", "yt-dlp"] {
            let path = Shell.which(tool)
            if let path {
                check("Optional dependency \(tool)", fm.isExecutableFile(atPath: path), path)
            } else {
                skip("Optional dependency \(tool)", "not installed; related tools use their documented fallback")
            }
        }

        // Office fallback works without LibreOffice; if LibreOffice exists we
        // still exercise OfficeXML above, so nothing to do here.

        // The catalog is the source of truth; every tool must have a screen.
        let catalog = CatalogStore.shared
        let registry = ToolRegistry.shared
        check("Catalog tool count", catalog.tools.count == 94, "tools=\(catalog.tools.count)")
        check("Catalog implemented count", catalog.tools.allSatisfy(\.implemented),
              "\(catalog.tools.filter { !$0.implemented }.map(\.slug))")
        check("Catalog unique slugs", Set(catalog.tools.map(\.slug)).count == catalog.tools.count)
        check("Catalog tool copy", catalog.tools.allSatisfy {
            !$0.name.isEmpty && !$0.tagline.isEmpty && !$0.description.isEmpty
        }, "\(catalog.tools.filter { $0.name.isEmpty || $0.tagline.isEmpty || $0.description.isEmpty }.map(\.slug))")
        let missingScreens = catalog.tools.map(\.slug).filter { !registry.has($0) }
        check("ToolRegistry has every tool", missingScreens.isEmpty, "\(missingScreens)")
        check("ToolRegistry ready count", registry.readyCount(in: catalog) == catalog.tools.count,
              "\(registry.readyCount(in: catalog))/\(catalog.tools.count)")
        check("Catalog notch count", catalog.notchModules.count == 24, "notch=\(catalog.notchModules.count)")

        // Read-only Mac helpers.
        let bundle = Bundle.main.bundleURL
        check("AppInfo.size", AppInfo.size(of: bundle) > 0, "\(AppInfo.size(of: bundle))")
        let signature = await AppInfo.signer(for: bundle)
        check("AppInfo.signer", !signature.identifier.isEmpty,
              "id=\(signature.identifier)")
        if signature.authority.isEmpty {
            skip("AppInfo.signer authority", "development build is ad-hoc signed")
        } else {
            check("AppInfo.signer authority", !signature.authority.isEmpty, signature.authority)
        }

        let leftovers = ScanLeftovers.find(url: bundle, bundleID: "app.nookit")
        check("ScanLeftovers.find", leftovers.allSatisfy { $0.url.path.hasPrefix("/") })

        // Battery parsing accepts real pmset/ioreg output shapes.
        let batteryRows = BatteryInfo.rows(
            pmset: "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1234567)\t82%; charged; 0:00 remaining present: true",
            ioreg: """
            "CycleCount" = 214
            "DesignCapacity" = 5103
            "MaxCapacity" = 4788
            "ExternalConnected" = Yes
            "IsCharging" = No
            """,
            host: "Test-Mac"
        )
        check("BatteryInfo charge", batteryRows.contains { $0.0 == "Charge" && $0.1 == "82%" },
              "\(batteryRows)")
        check("BatteryInfo power source", batteryRows.contains { $0.0 == "Power source" && $0.1 == "Power adapter" })
        check("BatteryInfo cycle count", batteryRows.contains { $0.0 == "CycleCount" && $0.1 == "214" },
              "\(batteryRows)")

        check("WiFiNetwork.current",
              WiFiNetwork.current(from: "Current Wi-Fi Network: Nookit-5G\n") == "Nookit-5G")
        check("WiFiNetwork.current off",
              WiFiNetwork.current(from: "You are not associated with an AirPort network.\n") == nil)

        check("NetworkSpeed calculation",
              abs(NetworkSpeed.megabitsPerSecond(bytes: 15_000_000, seconds: 12.5) - 9.6) < 0.001,
              "\(NetworkSpeed.megabitsPerSecond(bytes: 15_000_000, seconds: 12.5))")
        check("NetworkSpeed guards zero", NetworkSpeed.megabitsPerSecond(bytes: 1, seconds: 0) == 0)
        check("NetworkSpeed median", NetworkSpeed.median([10, 2, 6]) == 6.0
              && NetworkSpeed.median([10, 2]) == 6.0,
              "\(String(describing: NetworkSpeed.median([10, 2])))")
        check("NetworkSpeed chunks", NetworkSpeed.downloadChunks.reduce(0, +) >= 10_000_000,
              "\(NetworkSpeed.downloadChunks)")

        check("DownloadEngine streaming detection",
              DownloadEngine.needsStreamingEngine(URL(string: "https://www.youtube.com/watch?v=abc")!)
                  && DownloadEngine.needsStreamingEngine(URL(string: "https://vimeo.com/12345")!)
                  && !DownloadEngine.needsStreamingEngine(URL(string: "https://example.com/clip.mp4")!))
        check("DownloadErrors bot copy",
              DownloadErrors.friendly("Sign in to confirm you're not a bot").lowercased().contains("sign-in"),
              DownloadErrors.friendly("Sign in to confirm you're not a bot"))

        // Storage scan measures nested folders and sorts largest first.
        let storageRoot = fixtures.appendingPathComponent("storage-fixture", isDirectory: true)
        let storageBig = storageRoot.appendingPathComponent("big", isDirectory: true)
        let storageSmall = storageRoot.appendingPathComponent("small", isDirectory: true)
        try? fm.createDirectory(at: storageBig, withIntermediateDirectories: true)
        try? fm.createDirectory(at: storageSmall, withIntermediateDirectories: true)
        try? Data(repeating: 0x41, count: 200_000).write(to: storageBig.appendingPathComponent("payload.bin"))
        try? Data(repeating: 0x42, count: 1_000).write(to: storageSmall.appendingPathComponent("note.txt"))
        try? "not a folder".write(to: storageRoot.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let storage = StorageScan.scan(storageRoot)
        check("StorageScan entries", storage.entries.map(\.name) == ["big", "small"],
              "\(storage.entries.map { "\($0.name):\($0.bytes)" })")
        check("StorageScan total", storage.total >= 201_000, "\(storage.total)")

        // Keep Awake creates and releases a real power assertion.
        let keepAwake = KeepAwakeService.shared
        keepAwake.start(minutes: 1)
        if keepAwake.active {
            check("KeepAwake start", keepAwake.remaining > 0 && keepAwake.statusText.contains("left"),
                  keepAwake.statusText)
            keepAwake.stop()
            check("KeepAwake stop", !keepAwake.active)
        } else {
            skip("KeepAwake assertion", keepAwake.lastError ?? "power assertion unavailable")
        }

        // Recording flags are pure data, so they can be checked without
        // touching the screen or microphone.
        let capture = output.appendingPathComponent("capture.mov")
        let areaArgs = ScreenRecorder.arguments(
            area: true, window: false, systemAudio: true, microphone: false,
            seconds: 90, target: capture
        )
        check("ScreenRecorder area flags",
              areaArgs.contains("-i") && areaArgs.contains("-A") && !areaArgs.contains("-g")
                  && areaArgs.contains("-V90.0") && areaArgs.last == capture.path,
              "\(areaArgs)")
        let windowArgs = ScreenRecorder.arguments(
            area: false, window: true, systemAudio: false, microphone: true,
            seconds: nil, target: capture
        )
        check("ScreenRecorder window flags",
              windowArgs.contains("-W") && windowArgs.contains("-g") && !windowArgs.contains("-A")
                  && !windowArgs.contains { $0.hasPrefix("-V") },
              "\(windowArgs)")
        let displayArgs = ScreenRecorder.arguments(
            area: false, window: false, systemAudio: false, microphone: false,
            seconds: 0, target: capture
        )
        check("ScreenRecorder display flags",
              displayArgs.contains("-D") && displayArgs.contains("1") && !displayArgs.contains("-i"),
              "\(displayArgs)")

        let audioSettings = AudioRecording.settings()
        check("AudioRecording settings",
              audioSettings[AVFormatIDKey] as? Int == Int(kAudioFormatMPEG4AAC)
                  && audioSettings[AVSampleRateKey] as? Double == 44_100
                  && audioSettings[AVNumberOfChannelsKey] as? Int == 1,
              "\(audioSettings.keys.sorted())")

        let ai = AIChatService.shared
        if ai.isSupported {
            skip("AIChatService fallback copy", "a local model or Apple Intelligence is available")
        } else {
            check("AIChatService fallback copy",
                  ai.unavailableReason.lowercased().contains("nvidia")
                      || ai.unavailableReason.lowercased().contains("ai configuration"),
                  ai.unavailableReason)
        }

        // Attachment typing must match what the vision API accepts.
        let png = AttachedFile(data: Data([0x89, 0x50, 0x4E, 0x47]), filename: "shot.png")
        check("AttachedFile png", png.isImage && png.mimeType == "image/png", png.mimeType)
        let webp = AttachedFile(data: Data([0x52, 0x49, 0x46, 0x46]), filename: "shot.webp")
        check("AttachedFile webp", webp.isImage && webp.mimeType == "image/webp", webp.mimeType)
        let pdf = AttachedFile(data: Data([0x25, 0x50, 0x44, 0x46]), filename: "doc.pdf")
        check("AttachedFile pdf", !pdf.isImage && pdf.mimeType == "application/pdf", pdf.mimeType)
        let text = AttachedFile(data: Data("hello".utf8), filename: "note.md")
        check("AttachedFile text", !text.isImage && text.mimeType == "text/plain", text.mimeType)
    }

    // MARK: Chat history, Hype and Apps

    private func runFeatureTests() {
        // Chat sessions persist as JSON, including image attachments.
        let shot = AttachedFile(data: Data([0x89, 0x50, 0x4E, 0x47]), filename: "shot.png")
        let message = ChatMessage(role: .user, text: "Plan a trip to Kyoto", attachments: [shot])
        let session = ChatSession(messages: [message])

        check("ChatSession title", ChatSession.makeTitle(from: [message]) == "Plan a trip to Kyoto",
              ChatSession.makeTitle(from: [message]))
        check("ChatSession default title", ChatSession.makeTitle(from: []) == ChatSession.defaultTitle)

        let long = String(repeating: "a", count: 90)
        let longTitle = ChatSession.makeTitle(from: [ChatMessage(role: .user, text: long)])
        check("ChatSession long title", longTitle.count <= 46 && longTitle.hasSuffix("…"), longTitle)

        if let encoded = try? JSONEncoder().encode(session),
           let decoded = try? JSONDecoder().decode(ChatSession.self, from: encoded) {
            check("ChatSession codable",
                  decoded.title == "Plan a trip to Kyoto"
                    && decoded.messages.count == 1
                    && decoded.messages.first?.attachments.first?.filename == "shot.png"
                    && decoded.messages.first?.attachments.first?.isImage == true,
                  "messages=\(decoded.messages.count)")
        } else {
            check("ChatSession codable", false, "encode/decode failed")
        }
        check("ChatSession preview", !session.preview.isEmpty, session.preview)

        // Hype math and price heuristics.
        let oneDegree = HypeService.distanceMeters(0, 0, 0, 1)
        check("Hype distance", abs(oneDegree - 111_195) < 250, "\(oneDegree)")

        check("Hype tier fast food", HypeService.priceTier(tags: [:], kind: "fast_food") == 1)
        check("Hype tier cafe", HypeService.priceTier(tags: [:], kind: "cafe") == 2)
        check("Hype tier dollars", HypeService.priceTier(tags: ["price": "$$$"], kind: "restaurant") == 3)
        check("Hype tier fine dining", HypeService.priceTier(tags: ["cuisine": "fine_dining"], kind: "restaurant") == 4)
        check("Hype tier numeric", HypeService.priceTier(tags: ["price": "8"], kind: "restaurant") == 1)

        let origin = HypePlace(id: "origin", name: "Test City", displayName: "Test City", latitude: 37.0, longitude: -122.0)
        let overpass = """
        {"elements":[
          {"type":"node","id":1,"lat":37.0002,"lon":-122.0002,"tags":{"name":"Cheap Eats","amenity":"fast_food","addr:housenumber":"12","addr:street":"Main St","website":"example.com"}},
          {"type":"way","id":2,"center":{"lat":37.01,"lon":-122.01},"tags":{"name":"Nice Cafe","amenity":"cafe","cuisine":"coffee_shop"}}
        ]}
        """
        let venues = HypeService.venues(from: Data(overpass.utf8), origin: origin)
        check("Hype venue parsing", venues.count == 2, "count=\(venues.count)")
        check("Hype venue sort", venues.first?.name == "Cheap Eats", venues.first?.name ?? "none")
        check("Hype venue price", venues.first?.priceTier == 1, "\(venues.first?.priceTier ?? -1)")
        check("Hype venue address", venues.first?.address?.contains("Main St") == true, venues.first?.address ?? "nil")
        check("Hype venue website", venues.first?.url != nil)

        // Google app links and draft parsing.
        check("Google apps count", GoogleApp.allCases.count == 7, "\(GoogleApp.allCases.count)")
        check("Google docs link", GoogleApp.docs.createURL?.absoluteString == "https://docs.new")
        check("Google sheets file", GoogleApp.sheets.fileExtension == "csv")
        check("Google email prompt", GoogleApp.gmail.systemPrompt.contains("Subject:"))

        let email = GoogleLinkBuilder.emailParts("Subject: Hello there\n\nBody line\nSecond")
        check("Email subject", email.subject == "Hello there", email.subject)
        check("Email body", email.body == "Body line\nSecond", email.body)

        let fallbackEmail = GoogleLinkBuilder.emailParts("Just a body with no subject")
        check("Email fallback", fallbackEmail.subject == "Just a body with no subject", fallbackEmail.subject)

        let compose = GoogleLinkBuilder.gmailURL(subject: email.subject, body: email.body)
        let composeQuery = compose.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        check("Gmail compose URL", composeQuery?.first(where: { $0.name == "su" })?.value == "Hello there")

        let calendar = GoogleLinkBuilder.calendarURL(
            title: "Kickoff",
            details: "Agenda",
            start: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let calendarQuery = calendar.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        check("Calendar URL", calendarQuery?.first(where: { $0.name == "text" })?.value == "Kickoff"
                && calendarQuery?.first(where: { $0.name == "dates" })?.value?.contains("/") == true)

        let title = GoogleLinkBuilder.titleAndDetails("# Launch plan\n\nDetails")
        check("Draft title", title.title == "Launch plan", title.title)

        check("Apps history codable",
              (try? JSONDecoder().decode([AppsRun].self, from: JSONEncoder().encode([
                AppsRun(id: UUID(), appRaw: GoogleApp.docs.rawValue, title: "Brief", output: "Text", createdAt: Date())
              ])))?.first?.app == .docs)

        runWorkspaceTests()
        runHypeRoutingTests()
    }

    // MARK: Google OAuth + Workspace helpers

    private func runWorkspaceTests() {
        // RFC 7636 appendix B test vector.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = GooglePKCE.challenge(for: verifier)
        check("Google PKCE vector", challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", challenge)

        let authURL = GoogleAuthService.authorizationURL(
            clientID: "client.apps.googleusercontent.com",
            redirectURI: "http://127.0.0.1:12345",
            state: "state123",
            challenge: challenge
        )
        let items = authURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        check("Google auth URL client",
              items?.first(where: { $0.name == "client_id" })?.value == "client.apps.googleusercontent.com")
        check("Google auth URL PKCE",
              items?.first(where: { $0.name == "code_challenge_method" })?.value == "S256"
                && items?.first(where: { $0.name == "redirect_uri" })?.value == "http://127.0.0.1:12345")
        check("Google auth URL offline",
              items?.first(where: { $0.name == "access_type" })?.value == "offline")

        let profile = GoogleAuthService.profile(fromIDToken: Self.testIDToken(email: "ada@example.com", name: "Ada"))
        check("Google ID token email", profile.email == "ada@example.com", profile.email ?? "nil")
        check("Google ID token name", profile.name == "Ada", profile.name ?? "nil")

        let csv = GoogleCSV.parse("Name,Role\n\"Ada, Lovelace\",Engineer\nGrace,Admiral\n")
        check("Google CSV rows", csv.count == 3, "\(csv.count)")
        check("Google CSV quoted comma", csv[1].first == "Ada, Lovelace", csv[1].first ?? "nil")

        let fenced = GoogleCSV.parse("```csv\na,b\n1,2\n```")
        check("Google CSV fences", fenced.count == 2 && fenced[0] == ["a", "b"], "\(fenced)")

        let slides = GoogleSlidesOutline.parse("# Intro\n- one\n- two\n\n# Roadmap\n- three")
        check("Google slides outline", slides.count == 2, "\(slides.count)")
        check("Google slides title", slides.first?.title == "Intro", slides.first?.title ?? "nil")
        check("Google slides body", slides.first?.body.contains("one") == true, slides.first?.body ?? "nil")

        let raw = GoogleWorkspaceService.emailRaw(subject: "Hello", body: "World")
        var padded = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        let mime = Data(base64Encoded: padded).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check("Gmail MIME subject", mime.contains("Subject: Hello"), mime.prefix(60).description)
        check("Gmail MIME body", mime.contains("World"))

        check("Google docs create label", GoogleApp.docs.openLabel == "Create in Docs", GoogleApp.docs.openLabel)
        check("Google meet noun", GoogleApp.meet.workspaceNoun == "calendar event", GoogleApp.meet.workspaceNoun)
    }

    private static func testIDToken(email: String, name: String) -> String {
        let header = Data(#"{"alg":"none","typ":"JWT"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let payloadJSON = #"{"email":"\#(email)","name":"\#(name)"}"#
        let payload = Data(payloadJSON.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(payload).signature"
    }

    // MARK: Hype provider routing

    private func runHypeRoutingTests() {
        let india = HypePlace(
            id: "in",
            name: "Bengaluru",
            displayName: "Bengaluru, Karnataka, India",
            latitude: 12.97,
            longitude: 77.59,
            countryCode: "in"
        )
        let global = HypePlace(
            id: "us",
            name: "San Francisco",
            displayName: "San Francisco, California, United States",
            latitude: 37.77,
            longitude: -122.41,
            countryCode: "us"
        )
        let venue = HypeVenue(
            id: "v1",
            name: "Spice Route",
            kind: "restaurant",
            cuisine: "indian",
            latitude: 12.98,
            longitude: 77.60,
            distance: 420,
            priceTier: 2,
            address: "12 MG Road",
            website: "spiceroute.example",
            phone: "+91 80 1234 5678",
            openingHours: "11:00-23:00"
        )

        check("Hype country India", india.isIndia && !global.isIndia)
        check("Hype India by name",
              HypePlace(id: "fallback", name: "Delhi", displayName: "Delhi, India", latitude: 0, longitude: 0).isIndia)

        check("Hype Swiggy order", HypeRouting.foodOrderURL(venue: venue, place: india)?.host == "www.swiggy.com")
        check("Hype Zomato table", HypeRouting.tableBookingURL(venue: venue, place: india)?.host == "www.zomato.com")
        check("Hype Uber Eats order", HypeRouting.foodOrderURL(venue: venue, place: global)?.host == "www.ubereats.com")
        check("Hype OpenTable table", HypeRouting.tableBookingURL(venue: venue, place: global)?.host == "www.opentable.com")

        let indiaMovies = HypeRouting.moviesURL(place: india)
        check("Hype BookMyShow", indiaMovies?.host == "in.bookmyshow.com"
                && indiaMovies?.absoluteString.contains("bengaluru") == true,
              indiaMovies?.absoluteString ?? "nil")
        check("Hype District events", HypeRouting.eventsURL(place: india)?.host == "www.district.in")
        check("Hype global events", HypeRouting.eventsURL(place: global)?.host == "www.ticketmaster.com")

        let depart = Date(timeIntervalSince1970: 1_800_000_000)
        let ret = depart.addingTimeInterval(3 * 86_400)
        let indiaFlight = HypeRouting.travelURL(
            mode: .flights, from: "New Delhi", to: "Mumbai", depart: depart, ret: ret, travelers: 1, place: india
        )
        let flightQuery = indiaFlight.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        check("Hype travel flights host", indiaFlight?.host == "www.google.com", indiaFlight?.absoluteString ?? "nil")
        check("Hype travel flights query", (indiaFlight.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }?.first(where: { $0.name == "q" })?.value?.contains("DEL") == true),
              indiaFlight?.absoluteString ?? "nil")
        check("Hype travel hotels host",
              HypeRouting.travelURL(mode: .hotels, from: "Delhi", to: "Mumbai", depart: depart, ret: ret, travelers: 2, place: india)?.host == "www.booking.com")
        check("Hype travel trains host",
              HypeRouting.travelURL(mode: .trains, from: "Delhi", to: "Agra", depart: depart, ret: ret, travelers: 1, place: india)?.absoluteString.contains("rome2rio") == true)

        let globalFlight = HypeRouting.travelURL(
            mode: .flights, from: "San Francisco", to: "Tokyo", depart: depart, ret: ret, travelers: 1, place: global
        )
        check("Hype Google Flights", globalFlight?.host == "www.google.com", globalFlight?.host ?? "nil")
        let globalFlightQuery = globalFlight.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        check("Hype Google Flights currency", globalFlightQuery?.first(where: { $0.name == "curr" })?.value == "USD")

        let alternateFlight = HypeRouting.alternateTravelURL(
            mode: .flights, from: "Delhi", to: "Mumbai", depart: depart, ret: ret, travelers: 1, place: india
        )
        let alternateQuery = alternateFlight.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        check("Hype alternate Google Flights", alternateFlight?.host == "www.google.com", alternateFlight?.host ?? "nil")
        check("Hype alternate INR", alternateQuery?.first(where: { $0.name == "curr" })?.value == "INR")
        let alternateQueryText = alternateQuery?.first(where: { $0.name == "q" })?.value ?? ""
        check("Hype alternate IATA query",
              alternateQueryText.contains("DEL") && alternateQueryText.contains("BOM"),
              alternateQueryText)
        check("Hype alternate ISO date",
              alternateQueryText.contains("1800000000") == false && alternateQueryText.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil,
              alternateQueryText)
        check("Hype alternate one way", alternateQueryText.lowercased().contains("one way"), alternateQueryText)
        check("Hype alternate hotels",
              HypeRouting.alternateTravelURL(mode: .hotels, from: "Delhi", to: "Mumbai", depart: depart, ret: ret, travelers: 2, place: india)?.host == "www.booking.com")
        check("Hype alternate hidden globally",
              HypeRouting.alternateTravelURL(mode: .flights, from: "SF", to: "Tokyo", depart: depart, ret: ret, travelers: 1, place: global) == nil)

        check("Hype Booking hotels",
              HypeRouting.travelURL(mode: .hotels, from: "SF", to: "Tokyo", depart: depart, ret: ret, travelers: 2, place: global)?.host == "www.booking.com")
        check("Hype Rome2Rio",
              HypeRouting.travelURL(mode: .trains, from: "Paris", to: "Berlin", depart: depart, ret: ret, travelers: 1, place: global)?.host == "www.rome2rio.com")

        check("Hype airport lookup", HypeRouting.airportCode("New Delhi") == "DEL", HypeRouting.airportCode("New Delhi") ?? "nil")
        check("Hype airport passthrough", HypeRouting.airportCode("BLR") == "BLR", HypeRouting.airportCode("BLR") ?? "nil")
        check("Hype city slug", HypeRouting.citySlug("Bengaluru") == "bengaluru", HypeRouting.citySlug("Bengaluru"))

        check("Hype category cafes", HypeFoodCategory.cafes.matches(venue) == false)
        check("Hype category restaurants", HypeFoodCategory.restaurants.matches(venue))

        let cinemaJSON = """
        {"elements":[
          {"type":"node","id":9,"lat":12.971,"lon":77.595,"tags":{"name":"Cinepolis","amenity":"cinema","addr:street":"MG Road"}}
        ]}
        """
        let cinemas = HypeService.cinemas(from: Data(cinemaJSON.utf8), origin: india)
        check("Hype cinema parsing", cinemas.count == 1 && cinemas.first?.name == "Cinepolis", "\(cinemas.count)")
        check("Hype cinema address", cinemas.first?.address?.contains("MG Road") == true, cinemas.first?.address ?? "nil")

        if let data = try? JSONEncoder().encode(india),
           let decoded = try? JSONDecoder().decode(HypePlace.self, from: data) {
            check("Hype place codable country", decoded.countryCode == "in", decoded.countryCode ?? "nil")
        } else {
            check("Hype place codable country", false, "encode/decode failed")
        }

        // District events ld+json parsing
        let districtEventsHTML = """
        <html><body>
        <script type="application/ld+json">{"@context":"https://schema.org"}</script>
        <script type="application/ld+json">{"@type":"BreadcrumbList","itemListElement":[]}</script>
        <script type="application/ld+json">{
          "@context": "https://schema.org",
          "@type": "ItemList",
          "name": "Events in Delhi",
          "itemListElement": [
            {"@type":"ListItem","position":1,"item":{
              "@type":"Event",
              "name": "Test Comedy Show",
              "url": "https://www.district.in/events/test-comedy-show",
              "startDate": "2026-12-01T19:00:00.000Z",
              "endDate": "2026-12-01T21:00:00.000Z",
              "location": {"@type":"Place","name":"Test Venue","address":{"@type":"PostalAddress","addressLocality":"Delhi","addressCountry":"IN"}},
              "offers": {"@type":"Offer","price":"499","priceCurrency":"INR"},
              "image": ["https://example.com/image.jpg"]
            }},
            {"@type":"ListItem","position":2,"item":{
              "@type":"Event",
              "name": "Test Music Concert",
              "url": "https://www.district.in/events/test-music-concert",
              "startDate": "2026-12-15T20:00:00.000Z",
              "location": {"@type":"Place","name":"Music Hall","address":{"@type":"PostalAddress","addressLocality":"Mumbai","addressCountry":"IN"}},
              "offers": {"@type":"Offer","price":"0","priceCurrency":"INR"}
            }}
          ]
        }</script>
        </body></html>
        """
        let parsedEvents = HypeService.districtEvents(fromHTML: Data(districtEventsHTML.utf8))
        check("District events parsed", parsedEvents.count == 2, "\(parsedEvents.count)")
        check("District event title", parsedEvents.first?.title == "Test Comedy Show", parsedEvents.first?.title ?? "nil")
        check("District event venue", parsedEvents.first?.venue == "Test Venue", parsedEvents.first?.venue ?? "nil")
        check("District event city", parsedEvents.first?.city == "Delhi", parsedEvents.first?.city ?? "nil")
        check("District event price", parsedEvents.first?.priceLabel == "From ₹499", parsedEvents.first?.priceLabel ?? "nil")
        check("District free event", parsedEvents[1].priceLabel == "Free entry", parsedEvents[1].priceLabel)

        // HypeEvent category inference
        check("Event category comedy", HypeService.eventCategory("Jimmy Carr Comedy Show") == "Comedy")
        check("Event category music", HypeService.eventCategory("Arijit Singh Live Concert") == "Music")
        check("Event category theatre", HypeService.eventCategory("Hamlet Theatre Play") == "Theatre")
        check("Event category workshop", HypeService.eventCategory("Photography Workshop") == "Workshop")
        check("Event category sports", HypeService.eventCategory("Marathon 2026") == "Sports")
        check("Event category default", HypeService.eventCategory("Random Event") == "Event")

        // Date parsing
        let date = HypeService.districtDate("2026-12-01T19:00:00.000Z")
        check("District date parse", date != nil, "\(String(describing: date))")
        let dateNoFraction = HypeService.districtDate("2026-12-01T19:00:00Z")
        check("District date parse no fraction", dateNoFraction != nil, "\(String(describing: dateNoFraction))")

        // Price parsing
        check("District price INR", HypeService.districtPrice("499") == "From ₹499")
        check("District price free", HypeService.districtPrice("0") == "Free entry")
        check("District price missing", HypeService.districtPrice(nil) == "See tickets")

        // ld+json block extraction
        let blocks = HypeService.ldJSONBlocks(in: districtEventsHTML)
        check("ld+json blocks count", blocks.count == 3, "\(blocks.count)")

        // City matching must tolerate District's inconsistent locality labels
        // ("Delhi/NCR", neighbourhoods like "Dwarka", historical aliases).
        let delhiAliases = HypeService.cityAliases("New Delhi")
        check("City aliases include delhi", delhiAliases.contains("delhi"), "\(delhiAliases)")
        check("City aliases include ncr", delhiAliases.contains("ncr"), "\(delhiAliases)")
        check("District slug Bengaluru", HypeService.districtCitySlug("Bangalore") == "bengaluru",
              HypeService.districtCitySlug("Bangalore"))
        check("District slug New Delhi", HypeService.districtCitySlug("New Delhi") == "new-delhi",
              HypeService.districtCitySlug("New Delhi"))

        let cityEvents = [
            HypeEvent(id: "a", title: "Shreya Ghoshal | Delhi", venue: "Indira Gandhi Arena", city: "Delhi/NCR",
                      dateLabel: "", startsAt: nil, priceLabel: "", category: "Music", urlString: nil,
                      imageURL: nil, isVenueSuggestion: false),
            HypeEvent(id: "b", title: "Ota Tokyo | Delhi", venue: "Yashobhoomi", city: "Dwarka",
                      dateLabel: "", startsAt: nil, priceLabel: "", category: "Event", urlString: nil,
                      imageURL: nil, isVenueSuggestion: false),
            HypeEvent(id: "c", title: "Home Festival", venue: "Vagator", city: "Goa",
                      dateLabel: "", startsAt: nil, priceLabel: "", category: "Music", urlString: nil,
                      imageURL: nil, isVenueSuggestion: false)
        ]
        let delhiMatched = HypeService.filterEventsByCity(cityEvents, city: "New Delhi")
        check("City filter keeps metro label", delhiMatched.contains { $0.id == "a" }, "\(delhiMatched.map(\.id))")
        check("City filter keeps neighbourhood by title", delhiMatched.contains { $0.id == "b" }, "\(delhiMatched.map(\.id))")
        check("City filter drops other city", !delhiMatched.contains { $0.id == "c" }, "\(delhiMatched.map(\.id))")

        let rohini = HypePlace(id: "r", name: "Rohini", displayName: "Rohini, Delhi, India",
                               latitude: 28.7, longitude: 77.1, countryCode: "in")
        check("districtCity Rohini to Delhi", HypeService.districtCity(rohini) == "Delhi",
              HypeService.districtCity(rohini))
        let dwarka = HypePlace(id: "d", name: "Dwarka", displayName: "Dwarka, New Delhi, India",
                               latitude: 28.6, longitude: 77.0, countryCode: "in")
        check("districtCity Dwarka to Delhi", HypeService.districtCity(dwarka) == "Delhi",
              HypeService.districtCity(dwarka))
        let andheri = HypePlace(id: "a", name: "Andheri", displayName: "Andheri, Mumbai, India",
                                latitude: 19.1, longitude: 72.8, countryCode: "in")
        check("districtCity Andheri to Mumbai", HypeService.districtCity(andheri) == "Mumbai",
              HypeService.districtCity(andheri))
        let whitefield = HypePlace(id: "w", name: "Whitefield", displayName: "Whitefield, Bengaluru, India",
                                   latitude: 13.0, longitude: 77.7, countryCode: "in")
        check("districtCity Whitefield to Bengaluru", HypeService.districtCity(whitefield) == "Bengaluru",
              HypeService.districtCity(whitefield))

        runTravelParsingTests()
    }

    private func runTravelParsingTests() {
        check("Travel duration 17.40", TravelService.minutes(fromRailwayDuration: "17.40") == 1060)
        check("Travel runs daily", TravelService.runsOnLabel("1111111") == "Daily")
        check("Travel runs Friday", TravelService.runsOnLabel("0000100") == "Fri")
        check("Travel classes",
              TravelService.classList("2A:39:28:10:8:::::::|3A:167:278:12:20:::::::|SL:118:96:18:28::6:::::4|") == ["2A", "3A", "SL"])
        check("Travel class list ignores junk", TravelService.classList("ZZ:1:2|SL:3:4") == ["SL"])

        let stations = [("NDLS", "New Delhi"), ("BCT", "Mumbai Central"), ("BSR", "Vasai Road")]
        check("Travel station by code", TravelService.resolveStation("NDLS", in: stations) == "NDLS")
        check("Travel station by city", TravelService.resolveStation("Delhi", in: stations) == "NDLS")
        check("Travel station by name", TravelService.resolveStation("mumbai central", in: stations) == "BCT")
        check("Travel station unknown", TravelService.resolveStation("Atlantis", in: stations) == nil)

        check("Travel flight price", TravelService.price(from: [[nil, 6551], "token"]) == 6551)
        check("Travel flight price direct", TravelService.price(from: 8459) == 8459)
        check("Travel flight time", TravelService.timeString([14, 10]) == "14:10")
        check("Travel flight time short", TravelService.timeString([9, 5]) == "09:05")
        check("Travel flight day offset", TravelService.dayOffset(from: [2026, 11, 20], to: [2026, 11, 21]) == 1)
        check("Travel flight day offset same", TravelService.dayOffset(from: [2026, 11, 20], to: [2026, 11, 20]) == 0)

        let initData = "AF_initDataCallback({key: 'ds:1', hash: '2', data:[[null],[[\"6E\"]]], sideChannel: {}});"
        let parsed = TravelService.extractInitData(from: initData, key: "ds:1") as? [Any]
        check("Travel init data block", parsed?.count == 2, "\(parsed?.count ?? -1)")
        check("Travel init data missing key", TravelService.extractInitData(from: initData, key: "ds:9") == nil)

        let hotelHTML = """
        <div class="uaTTDe x"><a class="PVOOXe" aria-label="Taj Palace &amp; Spa" href="/travel/hotels/entity/abc?x=1"></a>\
        <span aria-label="Prices starting from ₹12,488,"></span>\
        <span aria-label="4.7 out of 5 stars from 35,266 reviews"></span>\
        <img src="https://lh3.googleusercontent.com/abc=s1"><div>Amenities for Taj Palace, a 5-star hotel.</div></div>
        """
        let hotels = TravelService.parseHotels(html: hotelHTML, currency: "INR")
        check("Travel hotel parsed", hotels.count == 1, "\(hotels.count)")
        check("Travel hotel name", hotels.first?.name == "Taj Palace & Spa", hotels.first?.name ?? "nil")
        check("Travel hotel price", hotels.first?.price == 12488, "\(hotels.first?.price ?? -1)")
        check("Travel hotel rating", hotels.first?.rating == 4.7 && hotels.first?.reviewCount == 35266)
        check("Travel hotel photo", hotels.first?.photoURL != nil)
        check("Travel hotel star", hotels.first?.starClass == "5-star hotel", hotels.first?.starClass ?? "nil")
        check("Travel hotel price label", hotels.first?.priceLabel == "₹12,488", hotels.first?.priceLabel ?? "nil")

        var fields = Array(repeating: "", count: 70)
        fields[0] = "12301"
        fields[1] = "RAJDHANI EXP"
        fields[6] = "New Delhi"
        fields[7] = "NDLS"
        fields[8] = "Mumbai Central"
        fields[9] = "BCT"
        fields[10] = "16.55"
        fields[11] = "08.15"
        fields[12] = "15.20"
        fields[13] = "1111111"
        fields[39] = "1384"
        fields[62] = "1A:1:2:3:4|2A:5:6:7:8|3A:9:10:11:12"
        let trainText = "~header~~2026-11-10-1-36-43~~~^" + fields.joined(separator: "~")
        let trains = TravelService.parseTrains(trainText)
        check("Travel train parsed", trains.count == 1, "\(trains.count)")
        check("Travel train number", trains.first?.number == "12301")
        check("Travel train times", trains.first?.departTime == "16:55" && trains.first?.arriveTime == "08:15")
        check("Travel train duration", trains.first?.durationMinutes == 920, "\(trains.first?.durationMinutes ?? -1)")
        check("Travel train classes", trains.first?.classes == ["1A", "2A", "3A"])
        check("Travel train distance", trains.first?.distanceKm == 1384)
    }

    private func runDisplayTests() {
        let before = BuiltInBrightness.read(CGMainDisplayID())
        check("BuiltInBrightness.read", before == nil || (before! >= 0 && before! <= 1),
              "\(String(describing: before))")
        if !BuiltInBrightness.available {
            skip("BuiltInBrightness.available", "DisplayServices symbols unavailable on this macOS build")
        }

        DisplayControlService.shared.refresh()
        check("DisplayControlService.refresh", DisplayControlService.shared.builtinID != nil,
              "builtinID=\(String(describing: DisplayControlService.shared.builtinID))")
        check("DisplayControlService external enumeration",
              DisplayControlService.shared.external.allSatisfy { !$0.name.isEmpty })

        // Notch model should expose only implemented modules and select a real one.
        let settings = NotchSettings.shared
        let modules = Weave.visibleModules(settings: settings)
        check("Notch visible modules", !modules.isEmpty && modules.allSatisfy { NotchModule.allCases.contains($0) },
              "\(modules.count)")
        let model = NotchModel(settings: settings)
        model.normalizeSelection()
        check("Notch selection normalises", model.visibleModules.contains(model.activeModule))

        // Panel geometry must respect the physical notch inset, and the
        // expanded panel must stay on screen.
        if let screen = NSScreen.main {
            let controller = NotchController(settings: settings)
            let inset = screen.safeAreaInsets.top
            let hasNotch = inset > 0 || screen.auxiliaryTopLeftArea != nil || screen.auxiliaryTopRightArea != nil

            controller.model.expanded = false
            let collapsed = controller.targetFrame()
            let expectedTop = hasNotch ? screen.frame.maxY - inset : screen.visibleFrame.maxY - 8
            check("Notch collapsed top clears menu bar", abs(collapsed.maxY - expectedTop) < 1,
                  "top=\(collapsed.maxY) expected=\(expectedTop) inset=\(inset)")
            check("Notch collapsed is centred",
                  abs(collapsed.midX - screen.frame.midX) < 1 && collapsed.width >= 200,
                  "\(collapsed)")

            controller.model.expanded = true
            let expanded = controller.targetFrame()
            check("Notch expanded sits under safe area", expanded.maxY <= expectedTop + 0.5,
                  "top=\(expanded.maxY) safe=\(expectedTop)")
            check("Notch expanded stays on screen",
                  expanded.minY >= screen.frame.minY && expanded.width >= 560 && expanded.width <= 760,
                  "\(expanded) screen=\(screen.frame)")
            check("Notch expanded keeps module content", expanded.height >= 300,
                  "height=\(expanded.height)")
        }

        // Render the two modules that previously lost their top rows to the
        // notch. A blank or missing bitmap would mean the layout collapsed.
        let renderModel = NotchModel(settings: settings)
        renderModel.pinned = true
        renderModel.expanded = true
        for module in [NotchModule.breathe, .ai] {
            renderModel.activeModule = module
            let host = NSHostingView(rootView: NotchView(model: renderModel))
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                check("Notch render \(module.title)", false, "no bitmap")
                continue
            }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                let path = output.appendingPathComponent("notch-\(module.rawValue).png")
                try? data.write(to: path)
                var lit = 0
                var sampled = 0
                for y in stride(from: 0, to: rep.pixelsHigh, by: 6) {
                    for x in stride(from: 0, to: rep.pixelsWide, by: 6) {
                        sampled += 1
                        if let color = rep.colorAt(x: x, y: y), color.brightnessComponent > 0.25 {
                            lit += 1
                        }
                    }
                }
                check("Notch render \(module.title)", data.count > 2_000 && lit > 8,
                      "bytes=\(data.count) lit=\(lit)/\(sampled)")
            } else {
                check("Notch render \(module.title)", false, "no png")
            }
        }
    }
}
