import SwiftUI
import AppKit
import Vision
import CoreImage
import CoreVideo
import UniformTypeIdentifiers

// MARK: - Shared image drawing

enum MarkStyle: String, CaseIterable, Identifiable {
    case arrow = "Arrow"
    case box = "Box"
    case label = "Label"
    case number = "Step number"
    var id: String { rawValue }
}

struct MarkColor: Identifiable {
    let id: Int
    let name: String
    let color: NSColor
    static let all: [MarkColor] = [
        MarkColor(id: 0, name: "Ember", color: NSColor(hex: 0xFF5A1F)),
        MarkColor(id: 1, name: "Red", color: NSColor(hex: 0xE23B3B)),
        MarkColor(id: 2, name: "Yellow", color: NSColor(hex: 0xFFC857)),
        MarkColor(id: 3, name: "Mint", color: NSColor(hex: 0x2BC48A)),
        MarkColor(id: 4, name: "White", color: .white),
        MarkColor(id: 5, name: "Ink", color: NSColor(hex: 0x0A0B0E))
    ]
    static func color(_ id: Int) -> NSColor { all.first { $0.id == id }?.color ?? all[0].color }
}

struct Mark: Identifiable {
    let id = UUID()
    var style: MarkStyle
    var start: CGPoint
    var end: CGPoint
    var text: String
    var colorID: Int
    var number: Int
}

enum ImageMarkRenderer {
    /// Draws marks onto a copy of the image. Coordinates are normalised with a
    /// top-left origin so they are independent of the preview size.
    static func render(_ image: CGImage, marks: [Mark], lineWidth: CGFloat = 4, redact: Bool = false) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let size = CGSize(width: width, height: height)
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw into a bitmap at the source's pixel size. Going through
        // NSImage.lockFocus() would use the screen's backing scale (so a
        // 400×300 image would export at 800×600) and asking for its CGImage
        // before unlocking returns nil.
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))

        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = previousContext }

        for mark in marks {
            let color = MarkColor.color(mark.colorID)
            let a = CGPoint(x: mark.start.x * width, y: (1 - mark.start.y) * height)
            let b = CGPoint(x: mark.end.x * width, y: (1 - mark.end.y) * height)
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))

            switch mark.style {
            case .box:
                if redact {
                    color.setFill()
                    rect.fill()
                } else {
                    color.setStroke()
                    let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                    path.lineWidth = lineWidth
                    path.stroke()
                }
            case .arrow:
                drawArrow(from: a, to: b, color: color, lineWidth: lineWidth)
            case .label:
                drawLabel(mark.text.isEmpty ? "Note" : mark.text, at: a, color: color, lineWidth: lineWidth)
            case .number:
                drawNumber(mark.number, at: a, color: color, lineWidth: lineWidth)
            }
        }

        return context.makeImage()
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.move(to: from)
        path.line(to: to)
        color.setStroke()
        path.stroke()

        let angle = atan2(to.y - from.y, to.x - from.x)
        let head = max(10, lineWidth * 4)
        let left = CGPoint(x: to.x - head * cos(angle - .pi / 7), y: to.y - head * sin(angle - .pi / 7))
        let right = CGPoint(x: to.x - head * cos(angle + .pi / 7), y: to.y - head * sin(angle + .pi / 7))
        let headPath = NSBezierPath()
        headPath.move(to: to)
        headPath.line(to: left)
        headPath.line(to: right)
        headPath.close()
        color.setFill()
        headPath.fill()
    }

    private static func drawLabel(_ text: String, at point: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: color
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let pad: CGFloat = 5
        let box = CGRect(x: point.x, y: point.y, width: size.width + pad * 2, height: size.height + pad * 2)
        NSColor(hex: 0x0A0B0E).withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        string.draw(at: CGPoint(x: point.x + pad, y: point.y + pad))
    }

    private static func drawNumber(_ number: Int, at point: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let radius: CGFloat = 15
        let circle = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        color.setFill()
        NSBezierPath(ovalIn: circle).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let string = NSAttributedString(string: "\(number)", attributes: attributes)
        let size = string.size()
        string.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }
}

/// Aspect-fit image view that reports normalised drag coordinates.
struct MarkCanvas: View {
    let image: CGImage
    @Binding var marks: [Mark]
    let tool: MarkStyle
    let colorID: Int
    let text: String
    let lineWidth: CGFloat
    var onMark: (() -> Void)? = nil

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let rect = ImageFit.rect(image: image, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                Canvas { context, _ in
                    for mark in marks {
                        draw(mark, in: context, rect: rect)
                    }
                    if let start = dragStart, let current = dragCurrent {
                        let preview = Mark(style: tool, start: start, end: current, text: text, colorID: colorID, number: marks.filter { $0.style == .number }.count + 1)
                        draw(preview, in: context, rect: rect)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let start = ImageFit.normalise(value.startLocation, rect: rect)
                            let current = ImageFit.normalise(value.location, rect: rect)
                            if dragStart == nil { dragStart = start }
                            dragCurrent = current
                        }
                        .onEnded { value in
                            let start = ImageFit.normalise(value.startLocation, rect: rect)
                            let end = ImageFit.normalise(value.location, rect: rect)
                            if distance(start, end) > 0.005 {
                                marks.append(Mark(
                                    style: tool,
                                    start: tool == .number || tool == .label ? start : start,
                                    end: end,
                                    text: text,
                                    colorID: colorID,
                                    number: marks.filter { $0.style == .number }.count + 1
                                ))
                                onMark?()
                            }
                            dragStart = nil
                            dragCurrent = nil
                        }
                )
                .onTapGesture { location in
                    guard tool == .number || tool == .label else { return }
                    let point = ImageFit.normalise(location, rect: rect)
                    marks.append(Mark(
                        style: tool,
                        start: point,
                        end: point,
                        text: text,
                        colorID: colorID,
                        number: marks.filter { $0.style == .number }.count + 1
                    ))
                    onMark?()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 280)
        .background(Theme.raised.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func draw(_ mark: Mark, in context: GraphicsContext, rect: CGRect) {
        let a = ImageFit.point(mark.start, rect: rect)
        let b = ImageFit.point(mark.end, rect: rect)
        let color = Color(nsColor: MarkColor.color(mark.colorID))
        let box = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        switch mark.style {
        case .box:
            context.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(color), lineWidth: lineWidth)
        case .arrow:
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            let angle = atan2(b.y - a.y, b.x - a.x)
            let head = max(10, lineWidth * 4)
            var headPath = Path()
            headPath.move(to: b)
            headPath.addLine(to: CGPoint(x: b.x - head * cos(angle - .pi / 7), y: b.y - head * sin(angle - .pi / 7)))
            headPath.addLine(to: CGPoint(x: b.x - head * cos(angle + .pi / 7), y: b.y - head * sin(angle + .pi / 7)))
            headPath.closeSubpath()
            context.fill(headPath, with: .color(color))
        case .label:
            let label = Text(mark.text.isEmpty ? "Note" : mark.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            context.draw(label, at: CGPoint(x: a.x + 6, y: a.y + 6), anchor: .topLeading)
        case .number:
            let circle = CGRect(x: a.x - 14, y: a.y - 14, width: 28, height: 28)
            context.fill(Path(ellipseIn: circle), with: .color(color))
            context.draw(
                Text("\(mark.number)").font(.system(size: 13, weight: .bold)).foregroundColor(.white),
                at: a,
                anchor: .center
            )
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

enum ImageFit {
    static func rect(image: CGImage, in size: CGSize) -> CGRect {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0 else { return .zero }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let target = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (size.width - target.width) / 2, y: (size.height - target.height) / 2, width: target.width, height: target.height)
    }

    static func normalise(_ point: CGPoint, rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(
            x: min(1, max(0, (point.x - rect.minX) / rect.width)),
            y: min(1, max(0, (point.y - rect.minY) / rect.height))
        )
    }

    static func point(_ normalised: CGPoint, rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + normalised.x * rect.width, y: rect.minY + normalised.y * rect.height)
    }

    static func pixelRect(_ normalised: CGRect, image: CGImage) -> CGRect {
        CGRect(
            x: normalised.minX * CGFloat(image.width),
            y: (1 - normalised.maxY) * CGFloat(image.height),
            width: normalised.width * CGFloat(image.width),
            height: normalised.height * CGFloat(image.height)
        )
    }
}

// MARK: - Blur faces

struct BlurFacesTool: View {
    @StateObject private var job = JobState()
    @State private var files: [URL] = []
    @State private var mode: Cover = .blur
    @State private var strength = 18.0
    @State private var preview: CGImage?
    @State private var faceCount = 0
    @EnvironmentObject private var store: ResultStore

    enum Cover: String, CaseIterable, Identifiable {
        case blur = "Blur"
        case pixelate = "Pixelate"
        case black = "Solid black"
        var id: String { rawValue }
    }

    var body: some View {
        ToolPage(symbol: "face.dashed", title: "Blur Faces", subtitle: "Vision finds every face, then Nookit hides each one. Review the first result before saving the batch.") {
            DropZone(title: "Choose photos", subtitle: "JPEG, PNG or HEIC. Drop one or many.", allowsMultiple: true, types: [.image]) { urls in
                files = urls
                job.clear()
                faceCount = 0
                preview = nil
                if let first = urls.first, let image = ImageEngine.source(first) {
                    preview = image
                }
            }
            if !files.isEmpty {
                HStack(spacing: 6) {
                    ForEach(files.prefix(5), id: \.path) { url in FileChip(url: url) }
                    if files.count > 5 { Text("+\(files.count - 5) more").font(Theme.caption).foregroundStyle(Theme.textTertiary) }
                    Spacer()
                    Button("Clear") { files = []; preview = nil }.buttonStyle(QuietButtonStyle())
                }
            }
            ToolCard(title: "Cover") {
                OptionPicker(label: "Style", options: Cover.allCases.map { ($0.rawValue, $0) }, selection: $mode)
                HStack(spacing: 12) {
                    Text("Strength").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    Slider(value: $strength, in: 6...40, step: 1).frame(maxWidth: 220)
                    Text("\(Int(strength))").font(Theme.mono)
                }
                if faceCount > 0 {
                    Text("\(faceCount) face\(faceCount == 1 ? "" : "s") found in the preview.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                RunBar(title: "Blur faces", job: job, disabled: files.isEmpty) { run() }
            }
            if let preview {
                ToolCard(title: "Preview") {
                    CheckerImage(image: preview)
                        .frame(maxHeight: 360)
                }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "photo")
        }
    }

    private func run() {
        let sources = files
        let mode = self.mode
        let strength = self.strength
        job.begin("Finding faces…")
        Task {
            do {
                let folder = store.datedFolder(for: "Blur Faces")
                var outputs: [URL] = []
                var totalFaces = 0
                var firstPreview: CGImage?
                for (index, source) in sources.enumerated() {
                    job.note("Photo \(index + 1) of \(sources.count)…")
                    guard let image = ImageEngine.source(source) else {
                        throw ToolError.message("\(source.lastPathComponent) couldn’t be read.")
                    }
                    let faces = try ImageToolsFaces.detect(in: image)
                    totalFaces += faces.count
                    let result = try ImageToolsFaces.cover(image, faces: faces, mode: mode, strength: strength)
                    let type: UTType = ["jpg", "jpeg"].contains(source.pathExtension.lowercased()) ? .jpeg : .png
                    let data = ImageEngine.encode(result, type: type, quality: 0.92)
                    guard let data else { throw ToolError.message("Couldn’t encode \(source.lastPathComponent).") }
                    let base = source.deletingPathExtension().lastPathComponent
                    let target = try store.write(data: data, to: folder, filename: "\(base)-faces.\(type == .jpeg ? "jpg" : "png")")
                    outputs.append(target)
                    if firstPreview == nil { firstPreview = result }
                }
                await MainActor.run { preview = firstPreview; faceCount = totalFaces }
                job.finish(outputs, "Saved \(outputs.count) photo\(outputs.count == 1 ? "" : "s"); \(totalFaces) face\(totalFaces == 1 ? "" : "s") covered.")
            } catch {
                job.fail(error)
            }
        }
    }
}

enum ImageToolsFaces {
    static func detect(in image: CGImage) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.map { observation in
            let box = observation.boundingBox
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            let rect = CGRect(x: box.minX * width, y: box.minY * height, width: box.width * width, height: box.height * height)
            return rect.insetBy(dx: -rect.width * 0.18, dy: -rect.height * 0.18)
        }
    }

    static func cover(_ image: CGImage, faces: [CGRect], mode: BlurFacesTool.Cover, strength: Double) throws -> CGImage {
        guard !faces.isEmpty else { return image }
        let input = CIImage(cgImage: image)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        var output = input

        let filtered: CIImage
        switch mode {
        case .blur:
            filtered = input.clampedToExtent()
                .applyingGaussianBlur(sigma: strength)
                .cropped(to: input.extent)
        case .pixelate:
            filtered = input.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: max(8, strength),
                kCIInputCenterKey: CIVector(x: input.extent.midX, y: input.extent.midY)
            ])
        case .black:
            filtered = CIImage(color: CIColor.black).cropped(to: input.extent)
        }

        for face in faces {
            let rect = face.intersection(input.extent)
            guard !rect.isNull, rect.width > 1, rect.height > 1 else { continue }
            let patch = filtered.cropped(to: rect).composited(over: output)
            output = patch
        }

        guard let cg = context.createCGImage(output, from: input.extent) else {
            throw ToolError.message("The blurred image couldn’t be rendered.")
        }
        return cg
    }
}

// MARK: - Remove background

struct RemoveBackgroundTool: View {
    @StateObject private var job = JobState()
    @State private var files: [URL] = []
    @State private var preview: CGImage?
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "person.crop.rectangle", title: "Remove Background", subtitle: "Apple’s on-device segmentation lifts the subject out and leaves a transparent PNG.") {
            DropZone(title: "Choose photos", subtitle: "One subject works best. Drop a folder’s worth and walk away.", allowsMultiple: true, types: [.image]) { urls in
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
            ToolCard(title: "Output") {
                Text("The subject is kept, the background becomes transparent, and the result is a PNG at the original pixel size. Photos with one clear subject work best.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                RunBar(title: "Remove background", job: job, disabled: files.isEmpty) { run() }
            }
            if let preview {
                ToolCard(title: "Preview") {
                    CheckerImage(image: preview).frame(maxHeight: 360)
                }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "photo")
        }
    }

    private func run() {
        let sources = files
        job.begin("Finding the subject…")
        Task {
            do {
                let folder = store.datedFolder(for: "Remove Background")
                var outputs: [URL] = []
                var firstPreview: CGImage?
                for (index, source) in sources.enumerated() {
                    job.note("Photo \(index + 1) of \(sources.count)…")
                    guard let image = ImageEngine.source(source) else {
                        throw ToolError.message("\(source.lastPathComponent) couldn’t be read.")
                    }
                    let cutout = try BackgroundCutout.remove(from: image)
                    let data = ImageEngine.encode(cutout, type: .png)
                    guard let data else { throw ToolError.message("Couldn’t encode the cutout.") }
                    let base = source.deletingPathExtension().lastPathComponent
                    let target = try store.write(data: data, to: folder, filename: "\(base)-cutout.png")
                    outputs.append(target)
                    if firstPreview == nil { firstPreview = cutout }
                }
                await MainActor.run { preview = firstPreview }
                job.finish(outputs, "Saved \(outputs.count) cutout\(outputs.count == 1 ? "" : "s").")
            } catch {
                job.fail(error)
            }
        }
    }
}

enum BackgroundCutout {
    static func remove(from image: CGImage) throws -> CGImage {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let mask: CVPixelBuffer
        if #available(macOS 14.0, *) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else {
                throw ToolError.message("No clear subject was found. Try a photo with one person or object against a simple background.")
            }
            mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        } else {
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            try handler.perform([request])
            guard let result = request.results?.first else {
                throw ToolError.message("No person was found in that photo.")
            }
            mask = result.pixelBuffer
        }

        let input = CIImage(cgImage: image)
        var maskImage = CIImage(cvPixelBuffer: mask)
        if maskImage.extent.width > 0, maskImage.extent.height > 0 {
            maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: input.extent.width / maskImage.extent.width, y: input.extent.height / maskImage.extent.height))
        }
        let clear = CIImage(color: .clear).cropped(to: input.extent)
        let output = input.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: maskImage
        ])
        let context = CIContext()
        guard let cg = context.createCGImage(output, from: input.extent) else {
            throw ToolError.message("The cutout couldn’t be rendered.")
        }
        return cg
    }
}

// MARK: - Color picker

struct ColorPickerTool: View {
    @StateObject private var job = JobState()
    @State private var image: CGImage?
    @State private var picked = NSColor(hex: 0xFF5A1F)
    @State private var history: [NSColor] = []
    @State private var sampler = NSColorSampler()
    @State private var hover: CGPoint?
    @State private var loupe: CGImage?
    @EnvironmentObject private var store: ResultStore

    private var hex: String {
        let rgb = picked.usingColorSpace(.sRGB) ?? picked
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }

    private var rgb: String {
        let c = picked.usingColorSpace(.sRGB) ?? picked
        return "\(Int(c.redComponent * 255)), \(Int(c.greenComponent * 255)), \(Int(c.blueComponent * 255))"
    }

    private var hsl: String {
        let c = picked.usingColorSpace(.sRGB) ?? picked
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        var h: Double = 0
        var s: Double = 0
        if maxV != minV {
            let d = maxV - minV
            s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
            if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) }
            else if maxV == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
        }
        return String(format: "%.0f°, %.0f%%, %.0f%%", h * 360, s * 100, l * 100)
    }

    private var css: String { "color: \(hex);" }
    private var swiftUI: String { "Color(hex: 0x\(hex.dropFirst()))" }

    var body: some View {
        ToolPage(symbol: "eyedropper", title: "Color Picker", subtitle: "Pick a colour anywhere on screen, or click a photo. Copy it as HEX, RGB, HSL, CSS or SwiftUI.") {
            ToolCard(title: "Sample") {
                HStack(spacing: 10) {
                    Button("Pick from screen") {
                        sampler.show { color in
                            guard let color else { return }
                            record(color)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Text("Then click anywhere on any display. Press Escape to cancel.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: picked))
                        .frame(width: 76, height: 76)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 5) {
                        valueRow("HEX", hex)
                        valueRow("RGB", rgb)
                        valueRow("HSL", hsl)
                        valueRow("CSS", css)
                        valueRow("SwiftUI", swiftUI)
                    }
                }
            }

            ToolCard(title: "Or pick from an image") {
                DropZone(title: "Choose an image", subtitle: "Click any pixel to sample it.", allowsMultiple: false, types: [.image], height: 84) { urls in
                    guard let url = urls.first, let source = ImageEngine.source(url) else { return }
                    image = source
                    hover = nil
                    loupe = nil
                }
                if let image {
                    GeometryReader { geo in
                        let rect = ImageFit.rect(image: image, in: geo.size)
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let normalised = ImageFit.normalise(location, rect: rect)
                                    hover = normalised
                                    loupe = crop(image, normalised: normalised)
                                case .ended:
                                    hover = nil
                                    loupe = nil
                                }
                            }
                            .onTapGesture { location in
                                let normalised = ImageFit.normalise(location, rect: rect)
                                if let color = sample(image, normalised: normalised) {
                                    record(color)
                                }
                            }
                    }
                    .frame(height: 320)
                    if let loupe, let hover {
                        HStack(spacing: 12) {
                            Image(decorative: loupe, scale: 1)
                                .resizable()
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
                            Text(String(format: "x %.0f%% · y %.0f%%", hover.x * 100, hover.y * 100))
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }

            if !history.isEmpty {
                ToolCard(title: "History") {
                    HStack(spacing: 8) {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, color in
                            Button {
                                picked = color
                            } label: {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(nsColor: color))
                                    .frame(width: 34, height: 34)
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
            CopyButton(value: value)
        }
    }

    private func record(_ color: NSColor) {
        picked = color
        history.insert(color, at: 0)
        if history.count > 16 { history.removeLast() }
    }

    private func sample(_ image: CGImage, normalised: CGPoint) -> NSColor? {
        let x = Int(normalised.x * CGFloat(image.width))
        let y = Int(normalised.y * CGFloat(image.height))
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1, height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: -CGFloat(x), y: -CGFloat(image.height - 1 - y), width: CGFloat(image.width), height: CGFloat(image.height)))
        return NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }

    private func crop(_ image: CGImage, normalised: CGPoint) -> CGImage? {
        let size = 28
        let centerX = Int(normalised.x * CGFloat(image.width))
        let centerY = Int(normalised.y * CGFloat(image.height))
        let rect = CGRect(x: centerX - size / 2, y: centerY - size / 2, width: size, height: size).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let cropped = image.cropping(to: rect) else { return nil }
        return ImageEngine.resized(cropped, maxPixel: 168)
    }
}

// MARK: - Redact image

struct RedactImageTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @State private var image: CGImage?
    @State private var marks: [Mark] = []
    @State private var style: RedactionStyle = .black
    @EnvironmentObject private var store: ResultStore

    enum RedactionStyle: String, CaseIterable, Identifiable {
        case black = "Solid black"
        case pixelate = "Pixelate"
        var id: String { rawValue }
    }

    var body: some View {
        ToolPage(symbol: "rectangle.slash", title: "Redact Image", subtitle: "Draw over anything private. The export contains the redaction itself, not a layer that can be peeled off.") {
            DropZone(title: "Choose an image", subtitle: "Screenshots, scans or photos.", allowsMultiple: false, types: [.image]) { urls in
                guard let url = urls.first else { return }
                file = url
                image = ImageEngine.source(url)
                marks = []
                job.clear()
            }
            if let image {
                ToolCard(title: "Redact") {
                    OptionPicker(label: "Style", options: RedactionStyle.allCases.map { ($0.rawValue, $0) }, selection: $style)
                    Text("Drag a rectangle over each area to hide. Nothing is written until you press Save.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                    MarkCanvas(
                        image: image,
                        marks: $marks,
                        tool: .box,
                        colorID: 5,
                        text: "",
                        lineWidth: 0
                    )
                    .frame(height: 380)
                    HStack(spacing: 10) {
                        Button("Undo") { _ = marks.popLast() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(marks.isEmpty)
                        Button("Clear") { marks = [] }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(marks.isEmpty)
                        Spacer()
                        Button("Save redacted copy") { save() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(marks.isEmpty || job.working)
                    }
                    if !job.status.isEmpty { Text(job.status).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                    if let error = job.error { InlineError(message: error) }
                }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "photo")
        }
    }

    private func save() {
        guard let image, let file else { return }
        let style = self.style
        let marks = self.marks
        job.begin("Rendering…")
        Task {
            do {
                let output: CGImage?
                if style == .black {
                    output = ImageMarkRenderer.render(image, marks: marks, redact: true)
                } else {
                    output = try Redaction.pixelate(image, marks: marks)
                }
                guard let output else { throw ToolError.message("The redacted image couldn’t be rendered.") }
                let folder = store.datedFolder(for: "Redact Image")
                let base = file.deletingPathExtension().lastPathComponent
                guard let data = ImageEngine.encode(output, type: .png) else {
                    throw ToolError.message("Couldn’t encode the result.")
                }
                let target = try store.write(data: data, to: folder, filename: "\(base)-redacted.png")
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

enum Redaction {
    static func pixelate(_ image: CGImage, marks: [Mark]) throws -> CGImage {
        let input = CIImage(cgImage: image)
        let context = CIContext()
        var output = input
        let pixelated = input.applyingFilter("CIPixellate", parameters: [
            kCIInputScaleKey: 22,
            kCIInputCenterKey: CIVector(x: input.extent.midX, y: input.extent.midY)
        ])
        for mark in marks {
            let normalised = CGRect(
                x: min(mark.start.x, mark.end.x),
                y: min(mark.start.y, mark.end.y),
                width: abs(mark.end.x - mark.start.x),
                height: abs(mark.end.y - mark.start.y)
            )
            let rect = ImageFit.pixelRect(normalised, image: image).intersection(input.extent)
            guard !rect.isNull else { continue }
            output = pixelated.cropped(to: rect).composited(over: output)
        }
        guard let cg = context.createCGImage(output, from: input.extent) else {
            throw ToolError.message("The pixelated image couldn’t be rendered.")
        }
        return cg
    }
}

// MARK: - Annotate screenshot

struct AnnotateScreenshotTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @State private var image: CGImage?
    @State private var marks: [Mark] = []
    @State private var tool: MarkStyle = .arrow
    @State private var colorID = 1
    @State private var text = "Look here"
    @State private var lineWidth = 4.0
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "pencil.tip.crop.circle", title: "Annotate Screenshot", subtitle: "Arrows, boxes, labels and numbered steps. Export a copy that is ready for a bug report or a doc.") {
            DropZone(title: "Choose a screenshot", subtitle: "PNG, JPEG or HEIC.", allowsMultiple: false, types: [.image]) { urls in
                guard let url = urls.first else { return }
                file = url
                image = ImageEngine.source(url)
                marks = []
                job.clear()
            }
            if let image {
                ToolCard(title: "Tools") {
                    HStack(spacing: 14) {
                        OptionPicker(label: "Tool", options: MarkStyle.allCases.map { ($0.rawValue, $0) }, selection: $tool)
                        OptionPicker(label: "Colour", options: MarkColor.all.map { ($0.name, $0.id) }, selection: $colorID)
                        HStack(spacing: 8) {
                            Text("Width").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                            Slider(value: $lineWidth, in: 2...12, step: 1).frame(width: 120)
                            Text("\(Int(lineWidth))").font(Theme.mono)
                        }
                    }
                    if tool == .label {
                        LabeledField(label: "Label text", text: $text, placeholder: "Look here", width: 240)
                    }
                    if tool == .number {
                        Text("Click where the first numbered step belongs. Each new number increments automatically.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    MarkCanvas(
                        image: image,
                        marks: $marks,
                        tool: tool,
                        colorID: colorID,
                        text: text,
                        lineWidth: lineWidth
                    )
                    .frame(height: 400)
                    HStack(spacing: 10) {
                        Button("Undo") { _ = marks.popLast() }.buttonStyle(SecondaryButtonStyle()).disabled(marks.isEmpty)
                        Button("Clear") { marks = [] }.buttonStyle(SecondaryButtonStyle()).disabled(marks.isEmpty)
                        Spacer()
                        Button("Export annotated copy") { save() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(marks.isEmpty || job.working)
                    }
                    if !job.status.isEmpty { Text(job.status).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                    if let error = job.error { InlineError(message: error) }
                }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "photo")
        }
    }

    private func save() {
        guard let image, let file else { return }
        let marks = self.marks
        let width = lineWidth
        job.begin("Rendering…")
        Task {
            do {
                guard let output = ImageMarkRenderer.render(image, marks: marks, lineWidth: width) else {
                    throw ToolError.message("The annotated image couldn’t be rendered.")
                }
                let folder = store.datedFolder(for: "Annotate Screenshot")
                let base = file.deletingPathExtension().lastPathComponent
                guard let data = ImageEngine.encode(output, type: .png) else {
                    throw ToolError.message("Couldn’t encode the result.")
                }
                let target = try store.write(data: data, to: folder, filename: "\(base)-annotated.png")
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}
