import AppKit
import AVFoundation
import CoreText
import QuartzCore

/// Burns subtitles into a video with AVFoundation when the installed FFmpeg
/// was built without the `subtitles` filter (Homebrew builds sometimes omit
/// libass). Everything stays on this Mac: frames are composited with Core
/// Animation and re-encoded by the system encoder.
enum SubtitleBurner {
    static func burn(video: URL, cues: [SubtitleFile.Cue], fontSize: Double, to target: URL) async throws {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration)
        guard duration.isValid, duration.seconds > 0 else {
            throw ToolError.message("That video has no measurable duration.")
        }
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            throw ToolError.message("No video track was found in that file.")
        }

        let naturalSize = try await sourceVideo.load(.naturalSize)
        let transform = try await sourceVideo.load(.preferredTransform)
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let renderSize = CGSize(
            width: max(2, abs(transformed.width).rounded()),
            height: max(2, abs(transformed.height).rounded())
        )

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ToolError.message("The video track couldn’t be prepared.")
        }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        videoTrack.preferredTransform = transform

        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioRange = try await sourceAudio.load(.timeRange)
            let insertDuration = CMTimeMinimum(duration, audioRange.duration)
            try? audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: insertDuration),
                                            of: sourceAudio, at: .zero)
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let nominalRate = try await sourceVideo.load(.nominalFrameRate)
        let framesPerSecond = nominalRate > 1 ? nominalRate.rounded() : 30

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = false
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        var captionCount = 0
        for cue in cues {
            guard let start = SubtitleFile.seconds(cue.start),
                  let end = SubtitleFile.seconds(cue.end),
                  end > start,
                  let image = captionImage(cue.text, renderSize: renderSize, fontSize: fontSize)
            else { continue }

            let maximumWidth = renderSize.width * 0.86
            let scale = min(1, maximumWidth / CGFloat(image.width))
            let width = CGFloat(image.width) * scale
            let height = CGFloat(image.height) * scale

            let caption = CALayer()
            caption.contents = image
            caption.contentsScale = 1
            caption.contentsGravity = .resize
            caption.frame = CGRect(
                x: (renderSize.width - width) / 2,
                y: renderSize.height * 0.055,
                width: width,
                height: height
            )
            caption.opacity = 0

            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.beginTime = AVCoreAnimationBeginTimeAtZero + start
            animation.duration = end - start
            animation.values = [0, 1, 1, 0]
            animation.keyTimes = [0, 0.01, 0.99, 1] as [NSNumber]
            animation.isRemovedOnCompletion = false
            animation.fillMode = .both
            caption.add(animation, forKey: "caption")
            parentLayer.addSublayer(caption)
            captionCount += 1
        }

        guard captionCount > 0 else {
            throw ToolError.message("No timed captions were found in that file. Check that it uses SRT, VTT or ASS timings.")
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ToolError.message("The system couldn’t create a video encoder for this clip.")
        }
        session.videoComposition = videoComposition
        session.outputFileType = .mp4
        try await MediaExport.export(session, to: target)
    }

    /// Renders one caption into a transparent bitmap with a soft black plate,
    /// so it stays legible over both bright and dark footage.
    private static func captionImage(_ text: String, renderSize: CGSize, fontSize: Double) -> CGImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let relative = min(renderSize.width / 1280, renderSize.height / 720)
        let pointSize = max(11, CGFloat(fontSize) * max(0.65, relative))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, pointSize, nil)
        let paragraph = paragraphStyle()
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.white.cgColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
        ]
        let attributed = NSAttributedString(string: trimmed, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        let maximumWidth = renderSize.width * 0.78
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: maximumWidth, height: renderSize.height),
            nil
        )
        let padding = pointSize * 0.55
        let width = max(1, ceil(suggested.width + padding * 2))
        let height = max(1, ceil(suggested.height + padding * 1.2))
        let canvas = CGSize(width: width, height: height)

        guard let context = CGContext(
            data: nil,
            width: Int(canvas.width),
            height: Int(canvas.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.clear(CGRect(origin: .zero, size: canvas))
        context.setFillColor(NSColor(white: 0, alpha: 0.58).cgColor)
        let plate = CGRect(origin: .zero, size: canvas)
        context.addPath(CGPath(roundedRect: plate,
                               cornerWidth: padding * 0.7,
                               cornerHeight: padding * 0.7,
                               transform: nil))
        context.fillPath()

        let textRect = CGRect(
            x: padding,
            y: padding * 0.6,
            width: max(1, canvas.width - padding * 2),
            height: max(1, canvas.height - padding * 1.2)
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            CGPath(rect: textRect, transform: nil),
            nil
        )
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        return context.makeImage()
    }

    private static func paragraphStyle() -> CTParagraphStyle {
        var alignment = CTTextAlignment.center
        var wrapping = CTLineBreakMode.byWordWrapping
        let settings: [CTParagraphStyleSetting] = [
            CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: &alignment
            ),
            CTParagraphStyleSetting(
                spec: .lineBreakMode,
                valueSize: MemoryLayout<CTLineBreakMode>.size,
                value: &wrapping
            )
        ]
        return CTParagraphStyleCreate(settings, settings.count)
    }
}
