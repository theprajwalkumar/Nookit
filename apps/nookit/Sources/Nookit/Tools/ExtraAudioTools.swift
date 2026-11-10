import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Audio format helpers

enum AudioExport {
    enum Format: String, CaseIterable, Identifiable {
        case m4a = "M4A"
        case mp3 = "MP3"
        case wav = "WAV"
        case flac = "FLAC"
        case aiff = "AIFF"
        var id: String { rawValue }
        var ext: String { rawValue.lowercased() }
        var codec: String {
            switch self {
            case .m4a: return "aac"
            case .mp3: return "libmp3lame"
            case .wav: return "pcm_s16le"
            case .flac: return "flac"
            case .aiff: return "pcm_s16be"
            }
        }
        var lossy: Bool { self == .m4a || self == .mp3 }
        var type: UTType {
            switch self {
            case .m4a: return .mpeg4Audio
            case .mp3: return .mp3
            case .wav: return .wav
            case .flac: return UTType("org.xiph.flac") ?? .audio
            case .aiff: return .aiff
            }
        }
    }

    static func arguments(format: Format, bitrate: Int, sampleRate: Int?) -> [String] {
        var args = ["-c:a", format.codec]
        if format.lossy {
            args += ["-b:a", "\(bitrate)k"]
        }
        if let sampleRate {
            args += ["-ar", "\(sampleRate)"]
        }
        return args
    }
}

// MARK: - Clean up audio

struct CleanUpAudioTool: View {
    @StateObject private var job = JobState()
    @State private var files: [URL] = []
    @State private var strength = 12.0
    @State private var removeHum = true
    @State private var normalize = true
    @State private var format: AudioExport.Format = .m4a
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "waveform.badge.minus", title: "Clean Up Audio", subtitle: "Reduce steady hum, fan noise and hiss while keeping the voice intact. Everything runs locally.") {
            DropZone(title: "Choose recordings", subtitle: "M4A, MP3, WAV, FLAC or AIFF. Drop one or a folder’s worth.", allowsMultiple: true, types: [.audio]) { urls in
                files = urls
                job.clear()
            }
            if !files.isEmpty {
                HStack(spacing: 6) {
                    ForEach(files.prefix(6), id: \.path) { url in
                        FileChip(url: url)
                    }
                    if files.count > 6 {
                        Text("+\(files.count - 6) more").font(Theme.caption).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Button("Clear") { files = [] }.buttonStyle(QuietButtonStyle())
                }
            }
            ToolCard(title: "Cleanup") {
                HStack(spacing: 12) {
                    Text("Noise reduction").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    Slider(value: $strength, in: 4...24, step: 2).frame(maxWidth: 240)
                    Text("\(Int(strength)) dB").font(Theme.mono).frame(width: 54)
                }
                HStack(spacing: 18) {
                    Toggle("Remove low hum", isOn: $removeHum).toggleStyle(.switch)
                    Toggle("Normalise loudness", isOn: $normalize).toggleStyle(.switch)
                }
                .font(Theme.body)
                OptionPicker(label: "Output", options: AudioExport.Format.allCases.map { ($0.rawValue, $0) }, selection: $format)
                Text("Noise reduction works best on a steady hiss or fan. It cannot remove a conversation, traffic or wind gust without damaging the voice.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                RunBar(title: "Clean \(files.count) file\(files.count == 1 ? "" : "s")", job: job, disabled: files.isEmpty) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "waveform")
        }
    }

    private func run() {
        let sources = files
        let strength = Int(self.strength)
        let removeHum = self.removeHum
        let normalize = self.normalize
        let format = self.format
        job.begin("Cleaning…")
        Task {
            do {
                let folder = store.datedFolder(for: "Clean Up Audio")
                var outputs: [URL] = []
                for (index, source) in sources.enumerated() {
                    job.note("Cleaning \(index + 1) of \(sources.count)…")
                    var filters = ["afftdn=nf=-25:nr=\(strength)"]
                    if removeHum {
                        filters.append("highpass=f=80")
                        filters.append("lowpass=f=14000")
                    }
                    if normalize {
                        filters.append("loudnorm=I=-16:TP=-1.5:LRA=11")
                    }
                    let base = source.deletingPathExtension().lastPathComponent
                    let target = ExtraFiles.unique(folder, "\(base)-clean.\(format.ext)")
                    var args = ["-i", source.path, "-af", filters.joined(separator: ",")]
                    args += AudioExport.arguments(format: format, bitrate: 192, sampleRate: nil)
                    args.append(target.path)
                    try await FFmpeg.checked(args)
                    outputs.append(target)
                }
                job.finish(outputs, "Cleaned \(outputs.count) file\(outputs.count == 1 ? "" : "s").")
            } catch {
                job.fail(error)
            }
        }
    }
}

// MARK: - Trim audio

struct TrimAudioTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @State private var duration = 0.0
    @State private var start = "0:00"
    @State private var end = "0:00"
    @State private var lossless = true
    @State private var player: AVAudioPlayer?
    @EnvironmentObject private var store: ResultStore

    private var startSeconds: Double? { TimeText.seconds(start) }
    private var endSeconds: Double? { TimeText.seconds(end) }

    var body: some View {
        ToolPage(symbol: "waveform.path", title: "Trim Audio", subtitle: "Cut a recording to the part you need. Lossless mode keeps the original encoding.") {
            DropZone(title: "Choose a recording", subtitle: "M4A, MP3, WAV, FLAC or AIFF.", allowsMultiple: false, types: [.audio]) { urls in
                guard let url = urls.first else { return }
                file = url
                job.clear()
                stopPreview()
                Task {
                    let value = await FFmpeg.duration(url)
                    await MainActor.run {
                        duration = value
                        start = "0:00"
                        end = TimeText.string(value)
                    }
                }
            }
            if let file {
                HStack {
                    FileChip(url: file) { self.file = nil; stopPreview() }
                    Spacer()
                    Text(Fmt.duration(duration)).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    Button(player?.isPlaying == true ? "Stop" : "Preview") { preview() }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            ToolCard(title: "Range") {
                HStack(spacing: 12) {
                    LabeledField(label: "Start", text: $start, placeholder: "0:00", width: 110)
                    LabeledField(label: "End", text: $end, placeholder: "0:30", width: 110)
                    if let startSeconds, let endSeconds, endSeconds > startSeconds {
                        Text("Keeping \(Fmt.duration(endSeconds - startSeconds))").font(Theme.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
                Toggle("Lossless copy (no re-encoding)", isOn: $lossless)
                    .toggleStyle(.switch)
                    .font(Theme.body)
                RunBar(title: "Trim", job: job, disabled: file == nil || startSeconds == nil || endSeconds == nil || (endSeconds ?? 0) <= (startSeconds ?? 0)) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "waveform")
        }
    }

    private func preview() {
        guard let file else { return }
        if player?.isPlaying == true {
            stopPreview()
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: file)
            player.currentTime = startSeconds ?? 0
            player.play()
            self.player = player
        } catch {
            job.fail("This file can’t be previewed natively. The trim will still work.")
        }
    }

    private func stopPreview() {
        player?.stop()
        player = nil
    }

    private func run() {
        guard let file, let startSeconds, let endSeconds, endSeconds > startSeconds else { return }
        let lossless = self.lossless
        job.begin("Trimming…")
        Task {
            do {
                let folder = store.datedFolder(for: "Trim Audio")
                let ext = file.pathExtension.lowercased()
                let base = file.deletingPathExtension().lastPathComponent
                let target = ExtraFiles.unique(folder, "\(base)-trimmed.\(ext.isEmpty ? "m4a" : ext)")
                var args = ["-ss", String(format: "%.3f", startSeconds), "-to", String(format: "%.3f", endSeconds), "-i", file.path]
                if lossless {
                    args += ["-c", "copy"]
                } else {
                    args += ["-c:a", "aac", "-b:a", "192k"]
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

// MARK: - Convert audio

struct ConvertAudioTool: View {
    @StateObject private var job = JobState()
    @State private var files: [URL] = []
    @State private var format: AudioExport.Format = .mp3
    @State private var bitrate = 192
    @State private var sampleRate = 0
    @EnvironmentObject private var store: ResultStore

    private let bitrates = [96, 128, 192, 256, 320]
    private let sampleRates: [(String, Int)] = [("Original", 0), ("44.1 kHz", 44100), ("48 kHz", 48000), ("22.05 kHz", 22050)]

    var body: some View {
        ToolPage(symbol: "arrow.left.arrow.right", title: "Convert Audio", subtitle: "Batch convert between MP3, M4A, WAV, FLAC and AIFF, with bitrate and sample rate in plain sight.") {
            DropZone(title: "Choose recordings", subtitle: "Drop as many as you like.", allowsMultiple: true, types: [.audio]) { urls in
                files = urls
                job.clear()
            }
            if !files.isEmpty {
                HStack(spacing: 6) {
                    ForEach(files.prefix(6), id: \.path) { url in
                        FileChip(url: url) { files.removeAll { $0 == url } }
                    }
                    if files.count > 6 {
                        Text("+\(files.count - 6) more").font(Theme.caption).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Button("Clear") { files = [] }.buttonStyle(QuietButtonStyle())
                }
            }
            ToolCard(title: "Output") {
                OptionPicker(label: "Format", options: AudioExport.Format.allCases.map { ($0.rawValue, $0) }, selection: $format)
                if format.lossy {
                    OptionPicker(label: "Bitrate", options: bitrates.map { ("\($0) kbps", $0) }, selection: $bitrate)
                }
                OptionPicker(label: "Sample rate", options: sampleRates, selection: $sampleRate)
                RunBar(title: "Convert \(files.count) file\(files.count == 1 ? "" : "s")", job: job, disabled: files.isEmpty) { run() }
            }
            OutputFilesCard(title: "Results", urls: job.results, symbol: "waveform")
        }
    }

    private func run() {
        let sources = files
        let format = self.format
        let bitrate = self.bitrate
        let sampleRate = sampleRate == 0 ? nil : self.sampleRate
        job.begin("Converting…")
        Task {
            do {
                let folder = store.datedFolder(for: "Convert Audio")
                var outputs: [URL] = []
                for (index, source) in sources.enumerated() {
                    job.note("Converting \(index + 1) of \(sources.count)…")
                    let base = source.deletingPathExtension().lastPathComponent
                    let target = ExtraFiles.unique(folder, "\(base).\(format.ext)")
                    var args = ["-i", source.path]
                    args += AudioExport.arguments(format: format, bitrate: bitrate, sampleRate: sampleRate)
                    args.append(target.path)
                    try await FFmpeg.checked(args)
                    outputs.append(target)
                }
                job.finish(outputs, "Converted \(outputs.count) file\(outputs.count == 1 ? "" : "s") to \(format.rawValue).")
            } catch {
                job.fail(error)
            }
        }
    }
}
