import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Shared export helper

enum MediaJob {
    case convert
    case trim
    case mute
    case extractAudio
}

enum MediaExport {
    static func export(_ session: AVAssetExportSession, to url: URL) async throws {
        session.outputURL = url
        session.shouldOptimizeForNetworkUse = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: ToolError.message("The export was cancelled."))
                default:
                    continuation.resume(throwing: session.error ?? ToolError.message("The export failed."))
                }
            }
        }
    }

    /// Builds the exporter used by Convert, Trim, Mute and Extract Audio. Kept
    /// separate from the view so the self-test suite can exercise the exact
    /// presets, containers and time ranges the tools ship with.
    static func session(
        for job: MediaJob,
        asset: AVAsset,
        presetName: String,
        fileType: AVFileType,
        start: Double,
        end: Double
    ) async throws -> AVAssetExportSession {
        let session: AVAssetExportSession?
        switch job {
        case .convert:
            session = AVAssetExportSession(asset: asset, presetName: presetName)
            session?.outputFileType = fileType
        case .trim:
            session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
            session?.outputFileType = .mp4
            session?.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )
        case .mute:
            let composition = try await composition(from: asset, mediaTypes: [.video])
            session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
            session?.outputFileType = .mp4
        case .extractAudio:
            let composition = try await composition(from: asset, mediaTypes: [.audio])
            session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
            session?.outputFileType = .m4a
        }

        guard let session else {
            throw ToolError.message("macOS couldn’t create an exporter for this file.")
        }
        if let requested = session.outputFileType, !session.supportedFileTypes.contains(requested) {
            throw ToolError.message("This video can’t be written as \(requested.rawValue) with the chosen quality. Try another format.")
        }
        return session
    }

    static func composition(from asset: AVAsset, mediaTypes: [AVMediaType]) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        for type in mediaTypes {
            let tracks = try await asset.loadTracks(withMediaType: type)
            for track in tracks {
                guard let target = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                let duration = try await asset.load(.duration)
                try target.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
                if type == .video {
                    target.preferredTransform = try await track.load(.preferredTransform)
                }
            }
        }
        return composition
    }

    static func readable(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Media info

enum MediaInspector {
    static func rows(for url: URL) async throws -> [(String, String)] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        var output: [(String, String)] = [
            ("File", url.lastPathComponent),
            ("Size", Fmt.bytes((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)),
            ("Container", url.pathExtension.uppercased()),
            ("Duration", Fmt.duration(duration.seconds)),
            ("Tracks", "\(tracks.count)")
        ]
        for (index, track) in tracks.enumerated() {
            let type = track.mediaType
            let rate = try await track.load(.estimatedDataRate)
            let kinds = try await track.load(.formatDescriptions)
            let codec = kinds.first.map { description -> String in
                fourCC(CMFormatDescriptionGetMediaSubType(description))
            } ?? "—"
            output.append(("Track \(index + 1)", "\(type.rawValue) · \(codec) · \(Int(rate / 1000)) kbps"))
            if type == .video {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let transformed = size.applying(transform)
                output.append(("Resolution", "\(Int(abs(transformed.width))) × \(Int(abs(transformed.height)))"))
                let fps = try await track.load(.nominalFrameRate)
                output.append(("Frame rate", String(format: "%.2f fps", fps)))
            }
        }
        return output
    }

    static func fourCC(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "—"
    }
}

struct MediaInfoTool: View {
    @State private var file: URL?
    @State private var rows: [(String, String)] = []
    @State private var error: String?

    var body: some View {
        ToolPage(symbol: "info.circle", title: "Media Info", subtitle: "Inspect duration, resolution, codecs and bitrate without playing the file.") {
            DropZone(title: "Choose a media file", subtitle: "Video or audio. Read-only.", allowsMultiple: false) { urls in
                guard let url = urls.first else { return }
                file = url
                inspect(url)
            }
            if let file { FileChip(url: file) }
            if let error { InlineError(message: error) }
            if !rows.isEmpty {
                ToolCard(title: "Details") {
                    VStack(spacing: 1) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 12) {
                                Text(row.0)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 150, alignment: .leading)
                                Text(row.1)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.textPrimary)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.raised.opacity(0.4))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func inspect(_ url: URL) {
        error = nil
        rows = []
        Task {
            do {
                let final = try await MediaInspector.rows(for: url)
                await MainActor.run { rows = final }
            } catch {
                await MainActor.run { self.error = MediaExport.readable(error) }
            }
        }
    }
}

// MARK: - Video convert / trim / mute / extract audio

struct VideoTool: View {
    enum Operation {
        case convert
        case trim
        case mute
        case extractAudio

        var slug: String {
            switch self {
            case .convert: return "convert-video"
            case .trim: return "trim-video"
            case .mute: return "mute-video"
            case .extractAudio: return "extract-audio"
            }
        }

        var title: String {
            switch self {
            case .convert: return "Convert Video"
            case .trim: return "Trim Video"
            case .mute: return "Mute Video"
            case .extractAudio: return "Extract Audio"
            }
        }

        var symbol: String {
            switch self {
            case .convert: return "film"
            case .trim: return "scissors"
            case .mute: return "speaker.slash"
            case .extractAudio: return "waveform"
            }
        }

        var subtitle: String {
            switch self {
            case .convert: return "Re-encode a video to MP4 or MOV using the system encoder."
            case .trim: return "Keep a section of a video and save it as a new file."
            case .mute: return "Remove the audio track and export a silent video."
            case .extractAudio: return "Pull the soundtrack out of a video as an M4A file."
            }
        }
    }

    let operation: Operation

    @State private var file: URL?
    @State private var duration: Double = 0
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var preset: Preset = .highest
    @State private var format: OutputFormat = .mp4
    @State private var working = false
    @State private var progress: Double = 0
    @State private var results: [URL] = []
    @State private var error: String?
    @State private var status = ""
    @EnvironmentObject private var store: ResultStore

    private enum Preset: String, CaseIterable, Identifiable {
        case highest = "Best quality"
        case medium = "Balanced"
        case low = "Small file"
        var id: String { rawValue }
        var name: String {
            switch self {
            case .highest: return AVAssetExportPresetHighestQuality
            case .medium: return AVAssetExportPresetMediumQuality
            case .low: return AVAssetExportPresetLowQuality
            }
        }
    }

    private enum OutputFormat: String, CaseIterable, Identifiable {
        case mp4 = "MP4"
        case mov = "MOV"
        var id: String { rawValue }
        var type: AVFileType { self == .mp4 ? .mp4 : .mov }
        var ext: String { self == .mp4 ? "mp4" : "mov" }
    }

    var body: some View {
        ToolPage(symbol: operation.symbol, title: operation.title, subtitle: operation.subtitle) {
            DropZone(title: "Choose a video", subtitle: "MP4, MOV, M4V. Drop it here or click to choose.", allowsMultiple: false, types: [.movie, .video]) { urls in
                guard let url = urls.first else { return }
                file = url
                loadDuration(url)
            }

            if let file {
                HStack(spacing: 8) {
                    FileChip(url: file) { self.file = nil; results = [] }
                    Spacer()
                    Text(Fmt.duration(duration)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }

            ToolCard(title: "Options") {
                switch operation {
                case .convert:
                    HStack(spacing: 16) {
                        OptionPicker(label: "Quality", options: Preset.allCases.map { ($0.rawValue, $0) }, selection: $preset)
                        OptionPicker(label: "Format", options: OutputFormat.allCases.map { ($0.rawValue, $0) }, selection: $format)
                        Spacer()
                    }
                case .trim:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            Text("Start").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                            Slider(value: $start, in: 0...max(0.1, duration - 0.2))
                                .frame(maxWidth: 220)
                            Text(Fmt.duration(start)).font(.system(size: 12, design: .monospaced))
                            Text("End").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                            Slider(value: $end, in: 0.2...max(0.3, duration))
                                .frame(maxWidth: 220)
                            Text(Fmt.duration(end)).font(.system(size: 12, design: .monospaced))
                        }
                        Text("Keeping \(Fmt.duration(max(0, end - start))) of \(Fmt.duration(duration)).")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                case .mute, .extractAudio:
                    Text(operation == .mute ? "The audio track is dropped; the video is re-encoded and saved as a new MP4." : "The audio track is copied into an M4A file.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: 10) {
                    Button(working ? "Exporting…" : "Export") { run() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(file == nil || working || (operation == .trim && end <= start))
                    if let file {
                        Button("Reveal source") { store.reveal(file) }.buttonStyle(QuietButtonStyle())
                    }
                    Spacer()
                }
                if working {
                    ProgressView(value: progress)
                        .tint(Theme.ember)
                }
                if !status.isEmpty { Text(status).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                if let error { InlineError(message: error) }
            }

            if !results.isEmpty {
                ToolCard(title: "Results") {
                    VStack(spacing: 1) {
                        ForEach(results, id: \.path) { url in
                            HStack(spacing: 10) {
                                Image(systemName: "film").foregroundStyle(Theme.ember).frame(width: 22)
                                Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
                                Spacer()
                                Text(Fmt.bytes((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textTertiary)
                                Button("Play") { store.open(url) }.buttonStyle(QuietButtonStyle())
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

    private func loadDuration(_ url: URL) {
        results = []
        error = nil
        Task {
            do {
                let asset = AVURLAsset(url: url)
                let value = try await asset.load(.duration).seconds
                await MainActor.run {
                    duration = max(0.2, value)
                    start = 0
                    end = max(0.2, value)
                }
            } catch {
                await MainActor.run { self.error = MediaExport.readable(error) }
            }
        }
    }

    private func run() {
        guard let file else { return }
        working = true
        error = nil
        results = []
        status = "Preparing export…"
        progress = 0
        let folder = store.datedFolder(for: operation.title)
        let base = file.deletingPathExtension().lastPathComponent
        let op = operation
        let preset = self.preset
        let format = self.format
        let start = self.start
        let end = self.end

        Task {
            do {
                let asset = AVURLAsset(url: file)
                let job: MediaJob
                var filename: String

                switch op {
                case .convert:
                    job = .convert
                    filename = "\(base)-converted.\(format.ext)"
                case .trim:
                    job = .trim
                    filename = "\(base)-trimmed.mp4"
                case .mute:
                    job = .mute
                    filename = "\(base)-muted.mp4"
                case .extractAudio:
                    job = .extractAudio
                    filename = "\(base)-audio.m4a"
                }

                let session = try await MediaExport.session(
                    for: job,
                    asset: asset,
                    presetName: preset.name,
                    fileType: format.type,
                    start: start,
                    end: end
                )
                // Never clobber an earlier export; AVFoundation refuses to write
                // over an existing file anyway.
                let target = ExtraFiles.unique(folder, filename)
                status = "Exporting…"

                let monitor = Task {
                    while !Task.isCancelled {
                        let value = Double(session.progress)
                        await MainActor.run { progress = value }
                        try? await Task.sleep(for: .milliseconds(220))
                    }
                }
                defer { monitor.cancel() }

                try await MediaExport.export(session, to: target)
                await MainActor.run {
                    working = false
                    progress = 1
                    results = [target]
                    status = "Saved \(target.lastPathComponent) · \(Fmt.bytes((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))"
                }
            } catch {
                await MainActor.run {
                    working = false
                    progress = 0
                    status = ""
                    self.error = MediaExport.readable(error)
                }
            }
        }
    }
}

// MARK: - Audio recorder

// MARK: - Record audio

enum AudioRecording {
    /// AAC settings shared by Record Audio and the self-test suite.
    static func settings(sampleRate: Double = 44_100) -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }
}

struct RecordAudioTool: View {
    @State private var recording = false
    @State private var elapsed: TimeInterval = 0
    @State private var recorder: AVAudioRecorder?
    @State private var saved: URL?
    @State private var error: String?
    @State private var ticker: Timer?
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "record.circle", title: "Record Audio", subtitle: "Capture a voice note to your Mac. Nothing is uploaded and no account is needed.") {
            ToolCard(title: "Recorder") {
                HStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(recording ? Theme.danger.opacity(0.15) : Theme.raised)
                            .frame(width: 84, height: 84)
                        Image(systemName: recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(recording ? Theme.danger : Theme.ember)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recording ? "Recording" : "Ready")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text(String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                            .font(.system(size: 34, weight: .semibold, design: .monospaced))
                            .foregroundStyle(recording ? Theme.danger : Theme.textSecondary)
                        Text("M4A · 44.1 kHz · saved to a dated folder when you stop.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Button(recording ? "Stop and save" : "Start recording") {
                        recording ? stop() : start()
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: recording ? Theme.danger : Theme.ember))
                }
            }

            if let saved, !recording {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").foregroundStyle(Theme.mint)
                    Text(saved.lastPathComponent).font(Theme.body)
                    Spacer()
                    Button("Play") { store.open(saved) }.buttonStyle(QuietButtonStyle())
                    Button("Reveal") { store.reveal(saved) }.buttonStyle(QuietButtonStyle())
                }
                .padding(12)
                .nookitCard()
            }

            if let error { InlineError(message: error) }

            Text("The first recording asks for microphone access. Audio stays on this Mac and is never sent anywhere.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        error = nil
        saved = nil
        Task {
            let allowed = await Permissions.microphone()
            guard allowed else {
                await MainActor.run {
                    error = "Microphone access isn’t allowed. Enable it in System Settings → Privacy & Security → Microphone."
                }
                return
            }
            let folder = store.datedFolder(for: "Record Audio")
            let url = folder.appendingPathComponent(Fmt.safeFilename("recording-\(Fmt.stampTime.string(from: Date())).m4a"))
            let settings = AudioRecording.settings()
            do {
                let recorder = try AVAudioRecorder(url: url, settings: settings)
                guard recorder.prepareToRecord(), recorder.record() else {
                    throw ToolError.message("The microphone didn’t start. Check that an input device is connected and not in use by another app.")
                }
                await MainActor.run {
                    self.recorder = recorder
                    self.recording = true
                    self.elapsed = 0
                    self.saved = url
                    startTicker()
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
    }

    private func stop() {
        recorder?.stop()
        recorder = nil
        recording = false
        ticker?.invalidate()
        ticker = nil
        if let saved, FileManager.default.fileExists(atPath: saved.path) {
            if elapsed < 0.4 {
                try? FileManager.default.removeItem(at: saved)
                self.saved = nil
                error = "That recording was too short to keep."
            }
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor in
                if let recorder, recorder.isRecording { elapsed = recorder.currentTime }
            }
        }
    }
}
