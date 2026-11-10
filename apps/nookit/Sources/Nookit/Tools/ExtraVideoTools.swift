import SwiftUI
import AppKit
import AVFoundation
import Speech
import UniformTypeIdentifiers

// MARK: - Download video

struct DownloadVideoTool: View {
    @StateObject private var job = JobState()
    @State private var link = ""
    @State private var quality: Quality = .best
    @State private var cookies: CookieSource = .none
    @State private var enginePath: String?
    @State private var engineVersion: String?
    @State private var jsRuntime: String?
    @State private var installingEngine = false
    @State private var engineError: String?
    @EnvironmentObject private var store: ResultStore

    enum Quality: String, CaseIterable, Identifiable {
        case best = "Best available"
        case p1080 = "1080p"
        case p720 = "720p"
        case p480 = "480p"
        var id: String { rawValue }
        var format: String {
            switch self {
            case .best: return "bv*+ba/b"
            case .p1080: return "bv*[height<=1080]+ba/b[height<=1080]"
            case .p720: return "bv*[height<=720]+ba/b[height<=720]"
            case .p480: return "bv*[height<=480]+ba/b[height<=480]"
            }
        }

        /// YouTube's compatible client usually exposes one combined stream, so
        /// ask for the best muxed format rather than separate video + audio.
        var combinedFormat: String {
            switch self {
            case .best: return "b"
            case .p1080: return "b[height<=1080]"
            case .p720: return "b[height<=720]"
            case .p480: return "b[height<=480]"
            }
        }
    }

    var body: some View {
        ToolPage(symbol: "arrow.down.circle", title: "Download Video", subtitle: "Paste a YouTube, Vimeo or direct video link. Nookit installs the download engine automatically, so the file is the original asset — not a screen recording.") {
            ToolCard(title: "Address") {
                LabeledField(label: "Video URL", text: $link, placeholder: "https://www.youtube.com/watch?v=…")
                OptionPicker(label: "Quality", options: Quality.allCases.map { ($0.rawValue, $0) }, selection: $quality)
                OptionPicker(label: "Browser cookies", options: CookieSource.allCases.map { ($0.rawValue, $0) }, selection: $cookies)
                Text("Cookies are only used when a site asks you to sign in. Choose the browser you use for that site; nothing is uploaded.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                if jsRuntime == nil {
                    Text("YouTube needs Node or Deno for full-quality extraction. Without one, Nookit uses YouTube’s compatible client, which may cap the resolution. Install Node with `brew install node` for the best results.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.warning)
                }
                RunBar(title: "Download", job: job, disabled: URL(string: link)?.scheme?.hasPrefix("http") != true) {
                    run()
                }
            }

            ToolCard(title: "Download engine", subtitle: enginePath == nil ? "Needed for YouTube and other streaming pages." : "Ready.") {
                HStack(spacing: 10) {
                    Image(systemName: enginePath == nil ? "arrow.down.circle" : "checkmark.seal.fill")
                        .foregroundStyle(enginePath == nil ? Theme.textTertiary : Theme.mint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(enginePath == nil ? "Not installed" : "yt-dlp \(engineVersion ?? "")")
                            .font(.system(size: 12.5, weight: .medium))
                        Text(enginePath.map { abbreviated($0) } ?? "Nookit can fetch the official standalone binary.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if installingEngine {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(enginePath == nil ? "Install" : "Reinstall") { installEngine() }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                if let engineError { InlineError(message: engineError) }
                Text("The engine is the official yt-dlp macOS binary, about 37 MB. It is stored in Application Support; a Homebrew copy is used when one already exists.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            OutputFilesCard(title: "Results", urls: job.results, symbol: "film")
        }
        .onAppear(perform: refreshEngine)
    }

    private func refreshEngine() {
        enginePath = DownloadEngine.path
        engineVersion = DownloadEngine.version
        jsRuntime = DownloadEngine.javascriptRuntime
    }

    private func abbreviated(_ path: String) -> String {
        path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func installEngine() {
        guard !installingEngine else { return }
        installingEngine = true
        engineError = nil
        Task {
            do {
                _ = try await DownloadEngine.install()
                refreshEngine()
                if enginePath == nil {
                    engineError = "The engine installed but couldn’t be started. Install `yt-dlp` with Homebrew and try again."
                }
            } catch {
                engineError = error.localizedDescription
            }
            installingEngine = false
        }
    }

    private func run() {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            job.fail("Enter a full http:// or https:// address.")
            return
        }
        let quality = self.quality
        let cookies = self.cookies
        job.begin("Preparing download…")
        Task {
            do {
                let folder = store.datedFolder(for: "Download Video")
                var engine = DownloadEngine.path
                let streamingPage = DownloadEngine.needsStreamingEngine(url)

                if engine == nil && streamingPage {
                    job.note("Installing the download engine…")
                    engine = try await DownloadEngine.install()
                    refreshEngine()
                }

                if let engine {
                    job.note("Downloading with yt-dlp…")
                    let before = Set(ExtraFiles.files(in: folder).map(\.lastPathComponent))
                    let youtube = DownloadEngine.isYouTube(url)
                    let runtime = DownloadEngine.javascriptRuntime

                    // YouTube's current bot checks need a JS runtime for full
                    // quality. Without one, use the compatible android client,
                    // which still returns a playable muxed file.
                    var result = try await runEngine(
                        engine,
                        url: url,
                        quality: quality,
                        cookies: cookies,
                        folder: folder,
                        compatible: youtube && runtime == nil
                    )
                    if !result.succeeded, youtube, runtime != nil {
                        job.note("Retrying with YouTube’s compatible client…")
                        result = try await runEngine(
                            engine,
                            url: url,
                            quality: quality,
                            cookies: cookies,
                            folder: folder,
                            compatible: true
                        )
                    }
                    guard result.succeeded else {
                        throw ToolError.message(DownloadErrors.friendly(result.stderr))
                    }
                    let files = ExtraFiles.files(in: folder).filter {
                        !before.contains($0.lastPathComponent)
                            && !$0.pathExtension.isEmpty
                            && $0.pathExtension != "part"
                            && $0.pathExtension != "ytdl"
                    }
                    guard !files.isEmpty else { throw ToolError.message("The download finished but no file appeared.") }
                    job.finish(files, "Saved \(files.count) file\(files.count == 1 ? "" : "s").")
                } else {
                    job.note("Downloading…")
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 60
                    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) Nookit/1.0", forHTTPHeaderField: "User-Agent")
                    let (temp, response) = try await URLSession.shared.download(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        throw ToolError.message("The server answered \(http.statusCode). If this is a video page rather than a direct file, install the download engine above.")
                    }
                    let mime = response.mimeType ?? ""
                    guard mime.hasPrefix("video/") || mime.hasPrefix("audio/") || mime == "application/octet-stream" || url.pathExtension.lowercased() == "mp4" else {
                        throw ToolError.message("That address returned \(mime.isEmpty ? "an unknown file" : mime), not a video. Install the download engine above for streaming pages.")
                    }
                    let suggested = response.suggestedFilename ?? url.lastPathComponent
                    let name = suggested.isEmpty ? "video.mp4" : suggested
                    let target = ExtraFiles.unique(folder, name)
                    try FileManager.default.moveItem(at: temp, to: target)
                    job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
                }
            } catch {
                job.fail(error)
            }
        }
    }

    private func runEngine(
        _ engine: String,
        url: URL,
        quality: Quality,
        cookies: CookieSource,
        folder: URL,
        compatible: Bool
    ) async throws -> ShellResult {
        let template = folder.appendingPathComponent("%(title).120B.%(ext)s").path
        var args = ["--no-playlist", "--restrict-filenames", "--newline", "-o", template]

        if compatible {
            args += ["--extractor-args", "youtube:player_client=android", "-f", quality.combinedFormat]
        } else {
            args += ["-f", quality.format]
            if let runtime = DownloadEngine.javascriptRuntime {
                args += ["--js-runtimes", runtime]
            }
        }

        if let ffmpeg = FFmpeg.path {
            args += ["--ffmpeg-location", URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().path]
        }
        if let source = cookies.ytDlpValue {
            args += ["--cookies-from-browser", source]
        }
        args.append(url.absoluteString)

        return try await Shell.run(engine, args, timeout: 3600)
    }
}

// MARK: - Burn subtitles

struct BurnSubtitlesTool: View {
    @StateObject private var job = JobState()
    @State private var video: URL?
    @State private var subtitles: URL?
    @State private var transcribe = false
    @State private var fontSize = 22.0
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "captions.bubble", title: "Burn In Subtitles", subtitle: "Render captions into the picture so they survive every player, upload and projector.") {
            VStack(alignment: .leading, spacing: 8) {
                DropZone(title: "Choose a video", subtitle: "MP4, MOV or M4V.", allowsMultiple: false, types: [.movie, .video]) { urls in
                    video = urls.first
                    job.clear()
                }
                if let video {
                    FileChip(url: video) { self.video = nil }
                }
            }

            ToolCard(title: "Captions") {
                DropZone(title: "Choose a subtitle file", subtitle: "SRT, VTT or ASS. Optional if you use on-device transcription.", allowsMultiple: false, types: [.item], height: 86) { urls in
                    subtitles = urls.first
                }
                if let subtitles {
                    FileChip(url: subtitles) { self.subtitles = nil }
                }
                Toggle("Transcribe the audio on this Mac instead", isOn: $transcribe)
                    .toggleStyle(.switch)
                    .font(Theme.body)
                HStack(spacing: 12) {
                    Text("Caption size")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Slider(value: $fontSize, in: 14...42, step: 1)
                        .frame(maxWidth: 220)
                    Text("\(Int(fontSize)) pt").font(Theme.mono).foregroundStyle(Theme.textSecondary)
                }
                Text("Transcription uses the on-device speech model and never uploads the recording. It works best on clear speech with little music.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                RunBar(title: "Burn captions", job: job, disabled: video == nil || (subtitles == nil && !transcribe)) {
                    run()
                }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "captions.bubble")
        }
    }

    private func run() {
        guard let video else { return }
        let useTranscribe = transcribe
        let subtitleURL = subtitles
        let size = Int(fontSize)
        job.begin(useTranscribe ? "Transcribing on device…" : "Preparing…")

        Task {
            do {
                let folder = store.datedFolder(for: "Burn In Subtitles")
                let base = video.deletingPathExtension().lastPathComponent
                let srt: URL
                if let subtitleURL {
                    srt = subtitleURL
                } else {
                    if let existing = try? makeSubtitles(from: video, folder: folder, base: base) {
                        srt = existing
                    } else {
                        srt = try await transcribeVideo(video, folder: folder, base: base)
                    }
                }

                let target = ExtraFiles.unique(folder, "\(base)-subtitled.mp4")
                if await FFmpeg.hasFilter("subtitles") {
                    job.note("Rendering captions…")
                    let filter = "subtitles='\(FFmpeg.filterEscape(srt.path))':force_style='FontName=Helvetica,FontSize=\(size),PrimaryColour=&H00FFFFFF,OutlineColour=&H66000000,BorderStyle=1,Outline=1,Shadow=0,MarginV=28'"
                    try await FFmpeg.checked([
                        "-i", video.path,
                        "-vf", filter,
                        "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                        "-c:a", "aac", "-b:a", "160k",
                        "-movflags", "+faststart",
                        target.path
                    ])
                } else {
                    job.note("Rendering captions on this Mac…")
                    let cues = SubtitleFile.parse(contentsOf: srt)
                    try await SubtitleBurner.burn(video: video, cues: cues, fontSize: fontSize, to: target)
                }
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }

    private func makeSubtitles(from video: URL, folder: URL, base: String) throws -> URL? {
        // Placeholder for callers that already have a sidecar subtitle next to the video.
        let candidates = ["srt", "vtt", "ass"].map { video.deletingPathExtension().appendingPathExtension($0) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func transcribeVideo(_ video: URL, folder: URL, base: String) async throws -> URL {
        guard FFmpeg.available else {
            throw ToolError.message("Transcription needs FFmpeg to extract the audio track.")
        }
        let allowed = await Permissions.speech()
        guard allowed else {
            throw ToolError.message("Speech recognition isn’t allowed. Enable it in System Settings → Privacy & Security → Speech Recognition.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.supportsOnDeviceRecognition else {
            throw ToolError.message("No on-device English speech model is installed on this Mac.")
        }

        let wav = folder.appendingPathComponent("audio-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wav) }
        try await FFmpeg.checked(["-y", "-i", video.path, "-vn", "-ac", "1", "-ar", "16000", wav.path])

        let request = SFSpeechURLRecognitionRequest(url: wav)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        let segments: [SFTranscriptionSegment] = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                    return
                }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.segments)
                }
            }
        }
        guard !segments.isEmpty else {
            throw ToolError.message("No speech was recognised in that clip.")
        }

        var srt = ""
        for (index, segment) in segments.enumerated() {
            let start = segment.timestamp
            let end = min(segment.timestamp + max(0.4, segment.duration), start + 7)
            srt += "\(index + 1)\n\(srtTime(start)) --> \(srtTime(end))\n\(segment.substring)\n\n"
        }
        let url = ExtraFiles.unique(folder, "\(base)-transcript.srt")
        try srt.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func srtTime(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = Int(total) % 60
        let ms = Int((total - floor(total)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}

// MARK: - Change speed

struct ChangeSpeedTool: View {
    @StateObject private var job = JobState()
    @State private var video: URL?
    @State private var factor = 1.5
    @State private var keepPitch = true
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "speedometer", title: "Change Speed", subtitle: "Retime a clip without the chipmunk effect. Pitch stays natural when the audio is retimed.") {
            DropZone(title: "Choose a video", subtitle: "MP4, MOV or M4V.", allowsMultiple: false, types: [.movie, .video]) { urls in
                video = urls.first
                job.clear()
            }
            if let video { FileChip(url: video) { self.video = nil } }

            ToolCard(title: "Timing") {
                HStack(spacing: 12) {
                    Text("Speed").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    Slider(value: $factor, in: 0.25...4, step: 0.05)
                        .frame(maxWidth: 300)
                    Text(String(format: "%.2f×", factor)).font(Theme.mono).frame(width: 50)
                }
                Text(factor < 1 ? "Slower. The clip gets longer and the audio is stretched." : "Faster. The clip gets shorter and the audio is compressed.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                if factor > 1 {
                    Text("A \(Fmt.duration(60)) clip becomes about \(Fmt.duration(60 / factor)).")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Toggle("Keep audio (pitch stays natural)", isOn: $keepPitch)
                    .toggleStyle(.switch)
                    .font(Theme.body)
                if !keepPitch {
                    Text("Audio is removed so the picture and sound can’t drift apart.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                RunBar(title: "Export", job: job, disabled: video == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "film")
        }
    }

    private func run() {
        guard let video else { return }
        let speed = factor
        let pitch = keepPitch
        job.begin("Retiming…")
        Task {
            do {
                let folder = store.datedFolder(for: "Change Speed")
                let base = video.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base)-\(String(format: "%.2f", speed))x.mp4")
                var args = ["-i", video.path, "-filter:v", "setpts=PTS/\(String(format: "%.6f", speed))"]
                if pitch {
                    args += ["-filter:a", FFmpeg.atempo(speed)]
                } else {
                    args += ["-an"]
                }
                args += [
                    "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                    "-c:a", "aac", "-b:a", "160k",
                    "-movflags", "+faststart",
                    target.path
                ]
                try await FFmpeg.checked(args)
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - Extract frames

struct ExtractFramesTool: View {
    @StateObject private var job = JobState()
    @State private var video: URL?
    @State private var mode: Mode = .interval
    @State private var interval = 1.0
    @State private var timestamp = "0:02.00"
    @State private var format: FrameFormat = .png
    @State private var maxWidth: Width = .original
    @EnvironmentObject private var store: ResultStore

    enum Mode: String, CaseIterable, Identifiable {
        case interval = "Every N seconds"
        case single = "One frame at a time"
        var id: String { rawValue }
    }

    enum FrameFormat: String, CaseIterable, Identifiable {
        case png = "PNG"
        case jpeg = "JPEG"
        var id: String { rawValue }
        var ext: String { self == .png ? "png" : "jpg" }
    }

    enum Width: String, CaseIterable, Identifiable {
        case original = "Original size"
        case w1920 = "1920 px"
        case w1280 = "1280 px"
        case w640 = "640 px"
        var id: String { rawValue }
        var value: Int? {
            switch self {
            case .original: return nil
            case .w1920: return 1920
            case .w1280: return 1280
            case .w640: return 640
            }
        }
    }

    var body: some View {
        ToolPage(symbol: "photo.stack", title: "Extract Frames", subtitle: "Pull stills out of any clip: a steady interval, every few seconds, or one moment you pick.") {
            DropZone(title: "Choose a video", subtitle: "MP4, MOV or M4V.", allowsMultiple: false, types: [.movie, .video]) { urls in
                video = urls.first
                job.clear()
            }
            if let video { FileChip(url: video) { self.video = nil } }

            ToolCard(title: "Frames") {
                OptionPicker(label: "Mode", options: Mode.allCases.map { ($0.rawValue, $0) }, selection: $mode)
                if mode == .interval {
                    HStack(spacing: 12) {
                        Text("Every").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        Slider(value: $interval, in: 0.25...10, step: 0.25).frame(maxWidth: 260)
                        Text("\(String(format: "%.2f", interval)) s").font(Theme.mono)
                    }
                } else {
                    LabeledField(label: "Timestamp", text: $timestamp, placeholder: "0:02.00")
                }
                HStack(spacing: 16) {
                    OptionPicker(label: "Format", options: FrameFormat.allCases.map { ($0.rawValue, $0) }, selection: $format)
                    OptionPicker(label: "Width", options: Width.allCases.map { ($0.rawValue, $0) }, selection: $maxWidth)
                }
                RunBar(title: "Extract", job: job, disabled: video == nil) { run() }
            }
            OutputFilesCard(title: "Frames", urls: job.results, symbol: "photo", openTitle: "Open")
        }
    }

    private func run() {
        guard let video else { return }
        let mode = self.mode
        let interval = self.interval
        let format = self.format
        let width = maxWidth.value
        let timeText = timestamp
        job.begin("Extracting frames…")
        Task {
            do {
                let folder = store.datedFolder(for: "Extract Frames")
                let base = video.deletingPathExtension().lastPathComponent
                var outputs: [URL] = []
                if mode == .interval {
                    let framesFolder = ExtraFiles.unique(folder, "\(base)-frames")
                    try FileManager.default.createDirectory(at: framesFolder, withIntermediateDirectories: true)
                    let stem = "\(base)-frame"
                    let template = framesFolder.appendingPathComponent("\(stem)-%04d.\(format.ext)").path
                    var filters = ["fps=1/\(String(format: "%.4f", interval))"]
                    if let width { filters.append("scale=\(width):-2") }
                    var args = ["-i", video.path, "-vf", filters.joined(separator: ",")]
                    if format == .jpeg { args += ["-q:v", "2"] }
                    args.append(template)
                    try await FFmpeg.checked(args)
                    outputs = ExtraFiles.files(in: framesFolder).filter { $0.lastPathComponent.hasPrefix(stem) }
                } else {
                    guard let seconds = TimeText.seconds(timeText) else {
                        throw ToolError.message("Use a timestamp such as 12, 0:12 or 1:02:03.")
                    }
                    let target = ExtraFiles.unique(folder, "\(base)-frame.\(format.ext)")
                    var filters: [String] = []
                    if let width { filters.append("scale=\(width):-2") }
                    var args = ["-ss", String(format: "%.3f", seconds), "-i", video.path, "-frames:v", "1"]
                    if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }
                    if format == .jpeg { args += ["-q:v", "2"] }
                    args.append(target.path)
                    try await FFmpeg.checked(args)
                    outputs = [target]
                }
                guard !outputs.isEmpty else { throw ToolError.message("No frames were produced. Try a smaller interval or a different timestamp.") }
                job.finish(outputs, "Saved \(outputs.count) frame\(outputs.count == 1 ? "" : "s").")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - Record screen

enum ScreenRecorder {
    /// Builds the `screencapture` arguments used by Record Screen. Kept pure so
    /// the self-test suite can verify the flags without touching the display.
    static func arguments(
        area: Bool,
        window: Bool,
        systemAudio: Bool,
        microphone: Bool,
        seconds: Double?,
        target: URL
    ) -> [String] {
        var args = ["-v", "-x"]
        if area {
            args.append("-i")
        } else if window {
            args += ["-i", "-W"]
        } else {
            args += ["-D", "1"]
        }
        if systemAudio { args.append("-A") }
        if microphone { args.append("-g") }
        if let seconds, seconds > 0 {
            args.append("-V\(String(format: "%.1f", seconds))")
        }
        args.append(target.path)
        return args
    }
}

struct RecordScreenTool: View {
    @StateObject private var job = JobState()
    @State private var source: Source = .area
    @State private var systemAudio = false
    @State private var microphone = false
    @State private var limit = ""
    @State private var process: Process?
    @State private var recording = false
    @State private var started: Date?
    @State private var ticker: Task<Void, Never>?
    @State private var elapsed = 0.0
    @EnvironmentObject private var store: ResultStore

    enum Source: String, CaseIterable, Identifiable {
        case area = "Choose an area"
        case window = "Choose a window"
        case display = "Main display"
        var id: String { rawValue }
    }

    var body: some View {
        ToolPage(symbol: "record.circle", title: "Record Screen", subtitle: "Record a display, a window or a clean rectangle. Screen recording permission is required the first time.") {
            ToolCard(title: "What to record") {
                OptionPicker(label: "Source", options: Source.allCases.map { ($0.rawValue, $0) }, selection: $source)
                Toggle("Include system audio", isOn: $systemAudio)
                    .toggleStyle(.switch)
                Toggle("Include the microphone", isOn: $microphone)
                    .toggleStyle(.switch)
                LabeledField(label: "Stop after (optional)", text: $limit, placeholder: "1:30", width: 140)
                HStack(spacing: 10) {
                    if recording {
                        Button("Stop recording") { stop() }
                            .buttonStyle(PrimaryButtonStyle(tint: Theme.danger))
                        Text(TimeText.clock(elapsed))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Button("Start recording") { start() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(job.working)
                    }
                    Spacer()
                }
                if recording {
                    Text("Recording. The menu bar icon keeps running while you switch apps; come back here to stop.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let error = job.error { InlineError(message: error) }
                if !job.status.isEmpty && !recording {
                    Text(job.status).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            OutputFilesCard(title: "Recordings", urls: job.results, symbol: "film")
        }
        .onDisappear {
            // Never leave an invisible recording running after the user
            // navigates away; the partial file is finalised by screencapture.
            if recording { stop() }
        }
    }

    private func start() {
        job.clear()
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            job.fail("Screen recording isn’t allowed. Enable Nookit in System Settings → Privacy & Security → Screen Recording, then relaunch.")
            return
        }
        let folder = store.datedFolder(for: "Record Screen")
        let target = ExtraFiles.unique(folder, "Recording \(Fmt.stampTime.string(from: Date())).mov")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ScreenRecorder.arguments(
            area: source == .area,
            window: source == .window,
            systemAudio: systemAudio,
            microphone: microphone,
            seconds: TimeText.seconds(limit),
            target: target
        )

        let finishedURL = target
        process.terminationHandler = { proc in
            DispatchQueue.main.async {
                ticker?.cancel()
                ticker = nil
                recording = false
                self.process = nil
                if FileManager.default.fileExists(atPath: finishedURL.path), ExtraFiles.size(finishedURL) > 0 {
                    job.finish([finishedURL], "Saved \(finishedURL.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(finishedURL))).")
                } else {
                    job.fail("Recording stopped without a file. If you cancelled the selection, nothing was saved.")
                }
            }
        }

        do {
            try process.run()
            self.process = process
            recording = true
            started = Date()
            elapsed = 0
            ticker = Task { @MainActor in
                while recording {
                    elapsed = Date().timeIntervalSince(started ?? Date())
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        } catch {
            job.fail(error)
        }
    }

    private func stop() {
        process?.interrupt()
    }
}

// MARK: - Compress video

struct CompressVideoTool: View {
    @StateObject private var job = JobState()
    @State private var video: URL?
    @State private var mode: Mode = .quality
    @State private var quality: Quality = .balanced
    @State private var targetMB = "25"
    @State private var duration = 0.0
    @EnvironmentObject private var store: ResultStore

    enum Mode: String, CaseIterable, Identifiable {
        case quality = "Quality preset"
        case size = "Target file size"
        var id: String { rawValue }
    }

    enum Quality: String, CaseIterable, Identifiable {
        case small = "Smallest file"
        case balanced = "Balanced"
        case sharp = "Sharper"
        var id: String { rawValue }
        var crf: Int {
            switch self {
            case .small: return 29
            case .balanced: return 24
            case .sharp: return 20
            }
        }
    }

    var body: some View {
        ToolPage(symbol: "arrow.down.right.and.arrow.up.left", title: "Compress Video", subtitle: "Shrink a clip to fit an upload limit, with a projected size before you commit.") {
            DropZone(title: "Choose a video", subtitle: "MP4, MOV or M4V.", allowsMultiple: false, types: [.movie, .video]) { urls in
                video = urls.first
                job.clear()
                if let url = urls.first {
                    Task { duration = await FFmpeg.duration(url) }
                }
            }
            if let video {
                HStack {
                    FileChip(url: video) { self.video = nil }
                    Spacer()
                    Text("\(Fmt.duration(duration)) · \(Fmt.bytes(ExtraFiles.size(video)))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            ToolCard(title: "Target") {
                OptionPicker(label: "Method", options: Mode.allCases.map { ($0.rawValue, $0) }, selection: $mode)
                if mode == .quality {
                    OptionPicker(label: "Quality", options: Quality.allCases.map { ($0.rawValue, $0) }, selection: $quality)
                } else {
                    HStack(spacing: 10) {
                        LabeledField(label: "Target size (MB)", text: $targetMB, placeholder: "25", width: 120)
                        if duration > 0, let mb = Double(targetMB), mb > 0 {
                            Text("About \(Int(mb * 8 * 1024 / duration)) kbps for \(Fmt.duration(duration)).")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                RunBar(title: "Compress", job: job, disabled: video == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "film")
        }
    }

    private func run() {
        guard let video else { return }
        let mode = self.mode
        let quality = self.quality
        let megabytes = Double(targetMB) ?? 0
        job.begin("Compressing…")
        Task {
            do {
                let folder = store.datedFolder(for: "Compress Video")
                let base = video.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base)-compressed.mp4")
                var args = ["-i", video.path, "-c:v", "libx264", "-preset", "medium"]
                if mode == .quality {
                    args += ["-crf", "\(quality.crf)"]
                } else {
                    guard megabytes > 0, duration > 0 else {
                        throw ToolError.message("Enter a target size in MB, and use a clip with a known duration.")
                    }
                    let totalKbps = megabytes * 8 * 1024 / duration
                    let videoKbps = max(180, totalKbps - 128)
                    args += ["-b:v", "\(Int(videoKbps))k", "-maxrate", "\(Int(videoKbps * 1.5))k", "-bufsize", "\(Int(videoKbps * 2))k"]
                }
                args += ["-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", target.path]
                try await FFmpeg.checked(args)
                let before = ExtraFiles.size(video)
                let after = ExtraFiles.size(target)
                let saved = before > 0 ? max(0, 100 - Double(after) / Double(before) * 100) : 0
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(after)) (from \(Fmt.bytes(before)), \(Int(saved))% smaller).")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - Resize video

struct ResizeVideoTool: View {
    @StateObject private var job = JobState()
    @State private var video: URL?
    @State private var width = "1920"
    @State private var height = "1080"
    @State private var mode: Fit = .pad
    @State private var sourceSize = CGSize.zero
    @EnvironmentObject private var store: ResultStore

    enum Fit: String, CaseIterable, Identifiable {
        case pad = "Letterbox"
        case crop = "Crop to fill"
        case stretch = "Stretch"
        var id: String { rawValue }
    }

    var body: some View {
        ToolPage(symbol: "aspectratio", title: "Resize Video", subtitle: "Exact dimensions, with letterboxing, cropping or stretching chosen deliberately.") {
            DropZone(title: "Choose a video", subtitle: "MP4, MOV or M4V.", allowsMultiple: false, types: [.movie, .video]) { urls in
                video = urls.first
                job.clear()
                guard let url = urls.first else { return }
                Task {
                    let size = await FFmpeg.videoSize(url)
                    await MainActor.run {
                        sourceSize = size
                        if size.width > 0 {
                            width = "\(Int(size.width))"
                            height = "\(Int(size.height))"
                        }
                    }
                }
            }
            if let video {
                HStack {
                    FileChip(url: video) { self.video = nil }
                    Spacer()
                    if sourceSize.width > 0 {
                        Text("Source \(Int(sourceSize.width)) × \(Int(sourceSize.height))")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            ToolCard(title: "Dimensions") {
                HStack(spacing: 12) {
                    LabeledField(label: "Width", text: $width, placeholder: "1920", width: 110)
                    LabeledField(label: "Height", text: $height, placeholder: "1080", width: 110)
                }
                OptionPicker(label: "Empty space", options: Fit.allCases.map { ($0.rawValue, $0) }, selection: $mode)
                Text("Even dimensions are enforced because most video codecs require them.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                RunBar(title: "Resize", job: job, disabled: video == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "film")
        }
    }

    private func run() {
        guard let video, let w = Int(width), let h = Int(height), w > 1, h > 1 else {
            job.fail("Enter a width and height in pixels.")
            return
        }
        let targetW = FFmpeg.even(Double(w))
        let targetH = FFmpeg.even(Double(h))
        let mode = self.mode
        job.begin("Resizing…")
        Task {
            do {
                let folder = store.datedFolder(for: "Resize Video")
                let base = video.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base)-\(targetW)x\(targetH).mp4")
                let filter: String
                switch mode {
                case .pad:
                    filter = "scale=\(targetW):\(targetH):force_original_aspect_ratio=decrease,pad=\(targetW):\(targetH):(ow-iw)/2:(oh-ih)/2:color=black"
                case .crop:
                    filter = "scale=\(targetW):\(targetH):force_original_aspect_ratio=increase,crop=\(targetW):\(targetH)"
                case .stretch:
                    filter = "scale=\(targetW):\(targetH)"
                }
                try await FFmpeg.checked([
                    "-i", video.path,
                    "-vf", filter,
                    "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                    "-c:a", "aac", "-b:a", "160k",
                    "-movflags", "+faststart",
                    target.path
                ])
                job.finish([target], "Saved \(targetW) × \(targetH) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - Crop & rotate

struct CropRotateVideoTool: View {
    @StateObject private var job = JobState()
    @State private var video: URL?
    @State private var rotate: Rotation = .none
    @State private var flipH = false
    @State private var flipV = false
    @State private var crop = false
    @State private var x = "0"
    @State private var y = "0"
    @State private var w = "0"
    @State private var h = "0"
    @State private var sourceSize = CGSize.zero
    @EnvironmentObject private var store: ResultStore

    enum Rotation: String, CaseIterable, Identifiable {
        case none = "None"
        case cw = "90° right"
        case ccw = "90° left"
        case half = "180°"
        var id: String { rawValue }
        var filter: String? {
            switch self {
            case .none: return nil
            case .cw: return "transpose=1"
            case .ccw: return "transpose=2"
            case .half: return "transpose=1,transpose=1"
            }
        }
    }

    var body: some View {
        ToolPage(symbol: "crop.rotate", title: "Crop & Rotate Video", subtitle: "Fix phone footage: rotate in 90° steps, flip it, or crop to the part you want.") {
            DropZone(title: "Choose a video", subtitle: "MP4, MOV or M4V.", allowsMultiple: false, types: [.movie, .video]) { urls in
                video = urls.first
                job.clear()
                guard let url = urls.first else { return }
                Task {
                    let size = await FFmpeg.videoSize(url)
                    await MainActor.run {
                        sourceSize = size
                        w = "\(Int(size.width))"
                        h = "\(Int(size.height))"
                    }
                }
            }
            if let video {
                HStack {
                    FileChip(url: video) { self.video = nil }
                    Spacer()
                    if sourceSize.width > 0 {
                        Text("Source \(Int(sourceSize.width)) × \(Int(sourceSize.height))")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            ToolCard(title: "Transform") {
                OptionPicker(label: "Rotation", options: Rotation.allCases.map { ($0.rawValue, $0) }, selection: $rotate)
                HStack(spacing: 16) {
                    Toggle("Flip horizontally", isOn: $flipH).toggleStyle(.switch)
                    Toggle("Flip vertically", isOn: $flipV).toggleStyle(.switch)
                }
                .font(Theme.body)
                Toggle("Crop to a rectangle", isOn: $crop).toggleStyle(.switch).font(Theme.body)
                if crop {
                    HStack(spacing: 10) {
                        LabeledField(label: "X", text: $x, width: 80)
                        LabeledField(label: "Y", text: $y, width: 80)
                        LabeledField(label: "Width", text: $w, width: 90)
                        LabeledField(label: "Height", text: $h, width: 90)
                    }
                }
                RunBar(title: "Export", job: job, disabled: video == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "film")
        }
    }

    private func run() {
        guard let video else { return }
        let rotate = self.rotate
        let flipH = self.flipH
        let flipV = self.flipV
        let crop = self.crop
        let x = Int(self.x) ?? 0
        let y = Int(self.y) ?? 0
        let w = Int(self.w) ?? 0
        let h = Int(self.h) ?? 0
        job.begin("Rendering…")
        Task {
            do {
                var filters: [String] = []
                if let filter = rotate.filter { filters.append(filter) }
                if flipH { filters.append("hflip") }
                if flipV { filters.append("vflip") }
                if crop {
                    guard w > 1, h > 1, x >= 0, y >= 0 else {
                        throw ToolError.message("Enter a crop rectangle with a positive width and height.")
                    }
                    filters.append("crop=\(FFmpeg.even(Double(w))):\(FFmpeg.even(Double(h))):\(x):\(y)")
                }
                guard !filters.isEmpty else {
                    throw ToolError.message("Choose a rotation, a flip or a crop first.")
                }
                let folder = store.datedFolder(for: "Crop & Rotate Video")
                let base = video.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base)-transformed.mp4")
                try await FFmpeg.checked([
                    "-i", video.path,
                    "-vf", filters.joined(separator: ","),
                    "-c:v", "libx264", "-preset", "medium", "-crf", "20",
                    "-c:a", "aac", "-b:a", "160k",
                    "-movflags", "+faststart",
                    target.path
                ])
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - Merge videos

struct MergeVideosTool: View {
    @StateObject private var job = JobState()
    @State private var files: [URL] = []
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "rectangle.stack", title: "Merge Videos", subtitle: "Join clips in the order you choose. Mixed resolutions are scaled and padded to the first clip.") {
            DropZone(title: "Choose clips", subtitle: "Drop several files, then put them in order.", allowsMultiple: true, types: [.movie, .video]) { urls in
                files.append(contentsOf: urls)
                job.clear()
            }
            if !files.isEmpty {
                ToolCard(title: "Sequence") {
                    VStack(spacing: 1) {
                        ForEach(Array(files.enumerated()), id: \.element.path) { index, url in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.ember)
                                    .frame(width: 18)
                                Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
                                Spacer()
                                Text(Fmt.bytes(ExtraFiles.size(url))).font(Theme.caption).foregroundStyle(Theme.textTertiary)
                                Button { move(index, -1) } label: { Image(systemName: "arrow.up") }.buttonStyle(QuietButtonStyle()).disabled(index == 0)
                                Button { move(index, 1) } label: { Image(systemName: "arrow.down") }.buttonStyle(QuietButtonStyle()).disabled(index == files.count - 1)
                                Button { files.remove(at: index) } label: { Image(systemName: "xmark") }.buttonStyle(QuietButtonStyle())
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Theme.raised.opacity(0.4))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    RunBar(title: "Merge", job: job, disabled: files.count < 2) { run() }
                }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "film")
        }
    }

    private func move(_ index: Int, _ delta: Int) {
        let destination = index + delta
        guard files.indices.contains(index), files.indices.contains(destination) else { return }
        files.swapAt(index, destination)
    }

    private func run() {
        guard files.count >= 2 else { return }
        let sources = files
        job.begin("Preparing clips…")
        Task {
            do {
                let folder = store.datedFolder(for: "Merge Videos")
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("nookit-merge-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: temp) }

                let firstSize = await FFmpeg.videoSize(sources[0])
                let width = firstSize.width > 0 ? FFmpeg.even(firstSize.width) : 1920
                let height = firstSize.height > 0 ? FFmpeg.even(firstSize.height) : 1080
                var list = ""

                for (index, source) in sources.enumerated() {
                    job.note("Normalising clip \(index + 1) of \(sources.count)…")
                    let part = temp.appendingPathComponent(String(format: "part-%03d.mp4", index))
                    var args = ["-i", source.path]
                    let hasAudio = await FFmpeg.hasAudio(source)
                    if !hasAudio {
                        args += ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100"]
                    }
                    let filter = "scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps=30"
                    args += ["-vf", filter, "-c:v", "libx264", "-preset", "veryfast", "-crf", "20"]
                    if hasAudio {
                        args += ["-c:a", "aac", "-b:a", "160k", "-ar", "44100", "-ac", "2"]
                    } else {
                        args += ["-map", "0:v:0", "-map", "1:a:0", "-c:a", "aac", "-b:a", "160k", "-shortest"]
                    }
                    args.append(part.path)
                    try await FFmpeg.checked(args)
                    list += "file '\(part.path.replacingOccurrences(of: "'", with: "'\\''"))'\n"
                }

                let listURL = temp.appendingPathComponent("list.txt")
                try list.write(to: listURL, atomically: true, encoding: .utf8)
                job.note("Joining \(sources.count) clips…")
                let target = ExtraFiles.unique(folder, "merged-\(Fmt.stampTime.string(from: Date())).mp4")
                try await FFmpeg.checked(["-f", "concat", "-safe", "0", "-i", listURL.path, "-c", "copy", "-movflags", "+faststart", target.path])
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - Replace audio

struct ReplaceAudioTool: View {
    @StateObject private var job = JobState()
    @State private var video: URL?
    @State private var audio: URL?
    @State private var mode: Mode = .replace
    @State private var newLevel = 1.0
    @State private var originalLevel = 0.35
    @EnvironmentObject private var store: ResultStore

    enum Mode: String, CaseIterable, Identifiable {
        case replace = "Replace the soundtrack"
        case mix = "Mix with the original"
        var id: String { rawValue }
    }

    var body: some View {
        ToolPage(symbol: "music.note", title: "Replace Audio", subtitle: "Put new music or narration under the picture, or mix it with what was already there.") {
            HStack(spacing: 12) {
                DropZone(title: "Choose a video", subtitle: "MP4, MOV or M4V.", allowsMultiple: false, types: [.movie, .video], height: 100) { urls in
                    video = urls.first
                    job.clear()
                }
                DropZone(title: "Choose audio", subtitle: "M4A, MP3, WAV or FLAC.", allowsMultiple: false, types: [.audio], height: 100) { urls in
                    audio = urls.first
                }
            }
            HStack(spacing: 8) {
                if let video { FileChip(url: video) { self.video = nil } }
                if let audio { FileChip(url: audio) { self.audio = nil } }
            }
            ToolCard(title: "Mix") {
                OptionPicker(label: "Method", options: Mode.allCases.map { ($0.rawValue, $0) }, selection: $mode)
                HStack(spacing: 12) {
                    Text("New audio").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    Slider(value: $newLevel, in: 0...2, step: 0.05).frame(maxWidth: 220)
                    Text("\(Int(newLevel * 100))%").font(Theme.mono)
                }
                if mode == .mix {
                    HStack(spacing: 12) {
                        Text("Original").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        Slider(value: $originalLevel, in: 0...2, step: 0.05).frame(maxWidth: 220)
                        Text("\(Int(originalLevel * 100))%").font(Theme.mono)
                    }
                }
                RunBar(title: "Export", job: job, disabled: video == nil || audio == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "film")
        }
    }

    private func run() {
        guard let video, let audio else { return }
        let mode = self.mode
        let newLevel = self.newLevel
        let originalLevel = self.originalLevel
        job.begin("Mixing…")
        Task {
            do {
                let folder = store.datedFolder(for: "Replace Audio")
                let base = video.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base)-new-audio.mp4")
                var args = ["-i", video.path, "-i", audio.path]
                let hasOriginal = await FFmpeg.hasAudio(video)
                if mode == .mix && hasOriginal {
                    let filter = "[0:a]volume=\(String(format: "%.3f", originalLevel))[orig];[1:a]volume=\(String(format: "%.3f", newLevel))[new];[orig][new]amix=inputs=2:duration=first:dropout_transition=0[a]"
                    args += ["-filter_complex", filter, "-map", "0:v:0", "-map", "[a]"]
                } else {
                    args += ["-map", "0:v:0", "-map", "1:a:0", "-filter:a", "volume=\(String(format: "%.3f", newLevel))"]
                }
                args += ["-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", target.path]
                try await FFmpeg.checked(args)
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - Video to GIF

struct VideoToGIFTool: View {
    @StateObject private var job = JobState()
    @State private var video: URL?
    @State private var start = "0:00"
    @State private var end = "0:05"
    @State private var fps = 15.0
    @State private var width: GIFWidth = .medium
    @State private var loop = true
    @EnvironmentObject private var store: ResultStore

    enum GIFWidth: String, CaseIterable, Identifiable {
        case small = "480 px"
        case medium = "640 px"
        case large = "800 px"
        var id: String { rawValue }
        var value: Int {
            switch self {
            case .small: return 480
            case .medium: return 640
            case .large: return 800
            }
        }
    }

    var body: some View {
        ToolPage(symbol: "rectangle.on.rectangle", title: "Video to GIF", subtitle: "Short loops with a proper palette, not the dithered mess of 1996.") {
            DropZone(title: "Choose a video", subtitle: "MP4, MOV or M4V.", allowsMultiple: false, types: [.movie, .video]) { urls in
                video = urls.first
                job.clear()
            }
            if let video { FileChip(url: video) { self.video = nil } }

            ToolCard(title: "Loop") {
                HStack(spacing: 12) {
                    LabeledField(label: "Start", text: $start, placeholder: "0:00", width: 100)
                    LabeledField(label: "End", text: $end, placeholder: "0:05", width: 100)
                }
                HStack(spacing: 12) {
                    Text("Frames per second").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    Slider(value: $fps, in: 5...30, step: 1).frame(maxWidth: 220)
                    Text("\(Int(fps))").font(Theme.mono)
                }
                HStack(spacing: 16) {
                    OptionPicker(label: "Width", options: GIFWidth.allCases.map { ($0.rawValue, $0) }, selection: $width)
                    Toggle("Loop forever", isOn: $loop).toggleStyle(.switch).font(Theme.body)
                }
                Text("Keep it under ten seconds; GIFs get large quickly.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                RunBar(title: "Make GIF", job: job, disabled: video == nil) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "photo")
        }
    }

    private func run() {
        guard let video else { return }
        guard let startSeconds = TimeText.seconds(start), let endSeconds = TimeText.seconds(end), endSeconds > startSeconds else {
            job.fail("Set a start and end time, with the end after the start.")
            return
        }
        let fps = Int(self.fps)
        let width = self.width.value
        let loopForever = loop
        job.begin("Building the palette…")
        Task {
            do {
                let folder = store.datedFolder(for: "Video to GIF")
                let base = video.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base).gif")
                let filter = "fps=\(fps),scale=\(width):-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=256:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle"
                var args = ["-ss", String(format: "%.3f", startSeconds), "-to", String(format: "%.3f", endSeconds), "-i", video.path, "-vf", filter]
                if loopForever {
                    args += ["-loop", "0"]
                }
                args.append(target.path)
                try await FFmpeg.checked(args)
                job.finish([target], "Saved \(target.lastPathComponent) · \(Fmt.bytes(ExtraFiles.size(target))).")
            } catch {
                job.fail(error)
            }
        }
    }
}
