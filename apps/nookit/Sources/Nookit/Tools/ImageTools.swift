import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

// MARK: - Engine

enum ImageEngine {
    static func source(_ url: URL) -> CGImage? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return image
    }

    static func encode(_ image: CGImage, type: UTType, quality: Double = 0.85, metadata: [CFString: Any]? = nil) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var properties: [CFString: Any] = metadata ?? [:]
        if type == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        } else if type == .heic {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func resized(_ image: CGImage, maxPixel: CGFloat) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longest = max(width, height)
        guard longest > maxPixel, maxPixel > 0 else { return image }
        let scale = maxPixel / longest
        let target = CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
        return draw(size: target) { context in
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(origin: .zero, size: target))
        } ?? image
    }

    static func rotated(_ image: CGImage, degrees: Int, flip: Bool) -> CGImage {
        let radians = CGFloat(degrees) * .pi / 180
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let rotatedBounds = bounds.applying(CGAffineTransform(rotationAngle: radians))
        let target = CGSize(width: abs(rotatedBounds.width), height: abs(rotatedBounds.height))
        return draw(size: target) { context in
            context.translateBy(x: target.width / 2, y: target.height / 2)
            context.rotate(by: radians)
            if flip { context.scaleBy(x: -1, y: 1) }
            context.draw(image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        } ?? image
    }

    static func beautified(_ image: CGImage, padding: CGFloat, corner: CGFloat, dark: Bool) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let pad = padding
        let target = CGSize(width: width + pad * 2, height: height + pad * 2)
        return draw(size: target) { context in
            let colors = dark
                ? [NSColor(hex: 0x0A0B0E).cgColor, NSColor(hex: 0x1C2028).cgColor]
                : [NSColor(hex: 0xF6F3EC).cgColor, NSColor(hex: 0xE7DFD0).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: target.height),
                    end: CGPoint(x: target.width, y: 0),
                    options: []
                )
            }
            let rect = CGRect(x: pad, y: pad, width: width, height: height)
            let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
            context.addPath(path)
            context.clip()
            context.draw(image, in: rect)
        } ?? image
    }

    static func draw(size: CGSize, _ body: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: max(1, Int(size.width)),
            height: max(1, Int(size.height)),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        body(context)
        return context.makeImage()
    }
}

// MARK: - Batch screen

struct ImageBatchTool: View {
    enum Operation: String {
        case convert
        case resize
        case compress
        case rotate
        case strip
        case beautify

        var symbol: String {
            switch self {
            case .convert: return "arrow.triangle.2.circlepath"
            case .resize: return "arrow.up.left.and.arrow.down.right"
            case .compress: return "arrow.down.right.and.arrow.up.left"
            case .rotate: return "rotate.right"
            case .strip: return "eye.slash"
            case .beautify: return "sparkles"
            }
        }

        var title: String {
            switch self {
            case .convert: return "Convert Images"
            case .resize: return "Resize Images"
            case .compress: return "Compress Images"
            case .rotate: return "Rotate Images"
            case .strip: return "Remove Metadata"
            case .beautify: return "Beautify Screenshot"
            }
        }

        var subtitle: String {
            switch self {
            case .convert: return "Move a batch of images between PNG, JPEG, HEIC and TIFF."
            case .resize: return "Scale images down to a maximum edge length without stretching them."
            case .compress: return "Shrink photos and screenshots with a quality you choose."
            case .rotate: return "Turn images in quarter steps, optionally mirroring them."
            case .strip: return "Re-encode images without EXIF, GPS or camera metadata."
            case .beautify: return "Put a screenshot on a soft backdrop with rounded corners."
            }
        }

        var defaultFormat: UTType {
            switch self {
            case .convert: return .jpeg
            case .beautify: return .png
            case .strip: return .png
            default: return .png
            }
        }
    }

    let operation: Operation

    @State private var files: [URL] = []
    @State private var format: Format = .jpeg
    @State private var quality = 0.8
    @State private var maxDimension = 1600.0
    @State private var degrees = 90
    @State private var flip = false
    @State private var padding = 64.0
    @State private var corner = 18.0
    @State private var darkBackdrop = true
    @State private var working = false
    @State private var results: [URL] = []
    @State private var error: String?
    @State private var status = ""
    @EnvironmentObject private var store: ResultStore

    private enum Format: String, CaseIterable, Identifiable {
        case jpeg = "JPEG"
        case png = "PNG"
        case heic = "HEIC"
        case tiff = "TIFF"
        var id: String { rawValue }
        var type: UTType {
            switch self { case .jpeg: return .jpeg; case .png: return .png; case .heic: return .heic; case .tiff: return .tiff }
        }
        var ext: String {
            switch self { case .jpeg: return "jpg"; case .png: return "png"; case .heic: return "heic"; case .tiff: return "tiff" }
        }
    }

    var body: some View {
        ToolPage(symbol: operation.symbol, title: operation.title, subtitle: operation.subtitle) {
            DropZone(title: "Choose images", subtitle: "PNG, JPEG, HEIC, TIFF, GIF or WebP. Drop them here.", height: 110) { urls in
                files = urls
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
                switch operation {
                case .convert:
                    formatRow
                case .compress:
                    HStack(spacing: 16) {
                        qualityRow
                        Spacer()
                    }
                    dimensionRow
                case .resize:
                    dimensionRow
                case .rotate:
                    HStack(spacing: 16) {
                        OptionPicker(
                            label: "Rotation",
                            options: [("90° right", 90), ("180°", 180), ("90° left", 270)],
                            selection: $degrees
                        )
                        Toggle("Mirror horizontally", isOn: $flip).toggleStyle(.checkbox).font(Theme.body)
                        Spacer()
                    }
                case .beautify:
                    HStack(spacing: 16) {
                        sliderRow("Padding", value: $padding, range: 0...160, suffix: "px")
                        sliderRow("Corner", value: $corner, range: 0...60, suffix: "px")
                        Toggle("Dark backdrop", isOn: $darkBackdrop).toggleStyle(.checkbox).font(Theme.body)
                        Spacer()
                    }
                case .strip:
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(Theme.mint)
                        Text("Re-encoding removes EXIF, GPS, camera and software tags. Colour profiles are kept.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                HStack(spacing: 10) {
                    Button(working ? "Working…" : "Run") { run() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(files.isEmpty || working)
                    if !files.isEmpty {
                        Button("Choose different files…") {
                            let picked = FilePicker.files(title: "Choose images", types: [.image])
                            if !picked.isEmpty { files = picked; results = []; error = nil }
                        }
                        .buttonStyle(QuietButtonStyle())
                        Text("\(files.count) file\(files.count == 1 ? "" : "s") queued")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                    } else {
                        Spacer()
                    }
                    if !results.isEmpty {
                        Button("Reveal results") { store.reveal(results[0].deletingLastPathComponent()) }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                if !status.isEmpty { Text(status).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                if let error { InlineError(message: error) }
            }

            if !results.isEmpty {
                ImageResultGrid(results: results)
            }
        }
    }

    private var formatRow: some View {
        HStack(spacing: 12) {
            OptionPicker(label: "Format", options: Format.allCases.map { ($0.rawValue, $0) }, selection: $format)
            if format == .jpeg || format == .heic { qualityRow }
            Spacer()
        }
    }

    private var qualityRow: some View {
        sliderRow("Quality", value: $quality, range: 0.2...1.0, suffix: "%", scale: 100)
    }

    private var dimensionRow: some View {
        HStack(spacing: 12) {
            Text("Longest edge").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Slider(value: $maxDimension, in: 320...4096, step: 160)
                .frame(maxWidth: 220)
            Text("\(Int(maxDimension)) px").font(Theme.caption).foregroundStyle(Theme.textTertiary)
            Button("Original") { maxDimension = 4096 }.buttonStyle(QuietButtonStyle())
            Spacer()
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String, scale: Double = 1) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Slider(value: value, in: range)
                .frame(width: 120)
            Text("\(Int(value.wrappedValue * scale))\(suffix)").font(Theme.caption).foregroundStyle(Theme.textTertiary)
        }
    }

    private func run() {
        guard !files.isEmpty else { return }
        working = true
        error = nil
        results = []
        status = "Processing \(files.count) image\(files.count == 1 ? "" : "s")…"
        let folder = store.datedFolder(for: operation.title)
        let snapshot = (files, format, quality, maxDimension, degrees, flip, padding, corner, darkBackdrop)
        let op = operation

        Task {
            var saved: [URL] = []
            var failures = 0
            for (index, url) in snapshot.0.enumerated() {
                guard let source = ImageEngine.source(url) else { failures += 1; continue }
                var image = source
                var type = snapshot.1.type
                var ext = snapshot.1.ext
                switch op {
                case .convert:
                    break
                case .resize:
                    image = ImageEngine.resized(image, maxPixel: snapshot.3)
                    type = url.pathExtension.lowercased() == "png" ? .png : (url.pathExtension.lowercased() == "heic" ? .heic : .jpeg)
                    ext = type == .png ? "png" : (type == .heic ? "heic" : "jpg")
                case .compress:
                    image = ImageEngine.resized(image, maxPixel: snapshot.3)
                    type = .jpeg
                    ext = "jpg"
                case .rotate:
                    image = ImageEngine.rotated(image, degrees: snapshot.4, flip: snapshot.5)
                    type = url.pathExtension.lowercased() == "png" ? .png : .jpeg
                    ext = type == .png ? "png" : "jpg"
                case .strip:
                    type = url.pathExtension.lowercased() == "png" ? .png : .jpeg
                    ext = type == .png ? "png" : "jpg"
                case .beautify:
                    image = ImageEngine.beautified(image, padding: snapshot.6, corner: snapshot.7, dark: snapshot.8)
                    type = .png
                    ext = "png"
                }
                guard let data = ImageEngine.encode(image, type: type, quality: snapshot.2),
                      let target = try? store.write(data: data, to: folder.appendingPathComponent(Fmt.safeFilename(op.title), isDirectory: true), filename: "\(url.deletingPathExtension().lastPathComponent)-\(index + 1).\(ext)")
                else {
                    failures += 1
                    continue
                }
                saved.append(target)
            }
            let final = saved
            let failureCount = failures
            await MainActor.run {
                working = false
                results = final
                status = "Saved \(final.count) image\(final.count == 1 ? "" : "s") · \(Fmt.bytes(final.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }))"
                if failureCount > 0 { error = "\(failureCount) file\(failureCount == 1 ? "" : "s") couldn’t be read or written." }
            }
        }
    }
}

// MARK: - Result grid

struct ImageResultGrid: View {
    let results: [URL]
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolCard(title: "Results", subtitle: "\(results.count) images saved") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(results, id: \.path) { url in
                    VStack(spacing: 6) {
                        if let image = NSImage(contentsOf: url) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 90)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.raised)
                                .frame(height: 90)
                        }
                        Text(url.lastPathComponent)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Button("Open") { store.open(url) }.buttonStyle(QuietButtonStyle())
                            Button("Reveal") { store.reveal(url) }.buttonStyle(QuietButtonStyle())
                        }
                    }
                }
            }
        }
    }
}
