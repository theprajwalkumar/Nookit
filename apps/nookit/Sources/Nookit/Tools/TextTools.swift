import SwiftUI
import AppKit
import PDFKit
import Speech
import AVFoundation

// MARK: - Word counter

struct WordCounterTool: View {
    @State private var text = "Nookit is a private toolkit for the Mac. Drop in a document, clean it up, and get a new file back — the original is never touched."

    private var stats: TextLogic.WordStats { TextLogic.stats(text) }

    private var words: [String] { stats.words }

    private var sentences: Int { stats.sentences }

    private var paragraphs: Int { stats.paragraphs }

    private var readingSeconds: Int { stats.readingSeconds }

    private var topWords: [(String, Int)] { stats.topWords }

    var body: some View {
        ToolPage(symbol: "text.word.spacing", title: "Word Counter", subtitle: "Count words, characters and reading time as you type.") {
            StatRow(items: [
                ("Words", "\(words.count)"),
                ("Characters", "\(text.count)"),
                ("Sentences", "\(sentences)"),
                ("Read time", Fmt.duration(Double(readingSeconds)))
            ])
            HStack(alignment: .top, spacing: Theme.Space.m) {
                ToolCard(title: "Text") {
                    CodeEditor(text: $text, height: 280, placeholder: "Paste or write here…")
                }
                ToolCard(title: "Most used words", subtitle: "Words longer than two characters, case-insensitive.") {
                    if topWords.isEmpty {
                        Text("Not enough text yet.").font(Theme.body).foregroundStyle(Theme.textTertiary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(topWords, id: \.0) { pair in
                                HStack(spacing: 8) {
                                    Text(pair.0)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(pair.1)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Theme.ember)
                                }
                            }
                        }
                    }
                    Divider().padding(.vertical, 4)
                    Text("\(paragraphs) paragraph\(paragraphs == 1 ? "" : "s") · \(text.utf8.count) UTF-8 bytes")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

// MARK: - Case converter

struct CaseConverterTool: View {
    private typealias Style = TextLogic.CaseStyle

    @State private var input = "the quick brown fox jumps over the lazy dog"
    @State private var style: Style = .title

    private var output: String {
        TextLogic.convert(input, to: style)
    }

    var body: some View {
        ToolPage(symbol: "textformat.size", title: "Case Converter", subtitle: "Switch between sentence, title, code and URL-friendly casing.") {
            Picker("Style", selection: $style) {
                ForEach(Style.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: Theme.Space.m) {
                ToolCard(title: "Input") {
                    CodeEditor(text: $input, height: 200)
                }
                TextOutputCard(toolName: "Case Converter", text: output, title: "Converted", filename: "converted.txt")
            }
        }
    }
}

// MARK: - Extract text

struct ExtractTextTool: View {
    @State private var file: URL?
    @State private var output = ""
    @State private var error: String?
    @State private var working = false
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "doc.text.magnifyingglass", title: "Extract Text", subtitle: "Pull readable text out of PDFs, RTF, HTML and plain documents.") {
            DropZone(title: "Choose a document", subtitle: "PDF, RTF, HTML, TXT, Markdown, CSV or JSON.", allowsMultiple: false) { urls in
                guard let url = urls.first else { return }
                file = url
                extract(url)
            }

            if let file {
                HStack(spacing: 8) {
                    FileChip(url: file) { self.file = nil; output = "" }
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                }
            }

            if let error { InlineError(message: error) }

            TextOutputCard(
                toolName: "Extract Text",
                text: output,
                title: "Extracted text",
                filename: (file?.deletingPathExtension().lastPathComponent ?? "document") + ".txt",
                footnote: output.isEmpty ? nil : "\(output.split(whereSeparator: \.isWhitespace).count) words"
            )
        }
    }

    private func extract(_ url: URL) {
        error = nil
        output = ""
        working = true
        Task {
            defer { working = false }
            do {
                let text = try Extractor.text(from: url)
                await MainActor.run {
                    output = text
                    if text.isEmpty { error = "No selectable text was found. Scanned PDFs need OCR." }
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
    }
}

enum Extractor {
    static func text(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else {
                throw ToolError.message("This PDF couldn’t be opened.")
            }
            return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
        }
        if ["txt", "md", "markdown", "csv", "json", "xml", "swift", "js", "ts", "css", "html", "htm", "log", "yml", "yaml"].contains(ext) {
            if let utf8 = try? String(contentsOf: url, encoding: .utf8) { return utf8 }
            return try String(contentsOf: url, encoding: .isoLatin1)
        }
        let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        return attributed.string
    }
}

// MARK: - Text to speech

struct TextToSpeechTool: View {
    @State private var text = "This is Nookit. Everything you hear was generated on this Mac."
    @State private var voice = "Samantha"
    @State private var rate = 175.0
    @State private var saved: URL?
    @State private var error: String?
    @State private var working = false
    @EnvironmentObject private var store: ResultStore

    private var voices: [String] {
        let all = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map(\.name)
        let unique = Array(Set(all)).sorted()
        return unique.isEmpty ? ["Samantha"] : unique
    }

    var body: some View {
        ToolPage(symbol: "waveform.badge.mic", title: "Text to Speech", subtitle: "Turn text into an audio file using the voices already installed on this Mac.") {
            ToolCard(title: "Script") {
                CodeEditor(text: $text, height: 200, placeholder: "Type what should be spoken…", monospaced: false)
                HStack(spacing: 16) {
                    OptionPicker(label: "Voice", options: voices.map { ($0, $0) }, selection: $voice)
                    HStack(spacing: 8) {
                        Text("Rate").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        Slider(value: $rate, in: 120...260)
                            .frame(width: 140)
                        Text("\(Int(rate)) wpm").font(Theme.caption).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Button(working ? "Rendering…" : "Render audio") { render() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(working || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    CopyButton(value: text)
                }
                if let error { InlineError(message: error) }
                if let saved {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform").foregroundStyle(Theme.mint)
                        Text(saved.lastPathComponent).font(Theme.body)
                        Spacer()
                        Button("Play") { store.open(saved) }.buttonStyle(QuietButtonStyle())
                        Button("Reveal") { store.reveal(saved) }.buttonStyle(QuietButtonStyle())
                    }
                    .padding(10)
                    .background(Theme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
            Text("Uses the macOS `say` voice engine. Audio is written once, into a dated folder, and never uploaded.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func render() {
        working = true
        error = nil
        saved = nil
        let folder = store.datedFolder(for: "Text to Speech")
        let name = Fmt.safeFilename("speech-\(Fmt.randomToken()).aiff")
        let url = folder.appendingPathComponent(name)
        Task {
            defer { working = false }
            do {
                let result = try await Shell.run(
                    "/usr/bin/say",
                    ["-v", voice, "-r", String(Int(rate)), "-o", url.path, text],
                    timeout: 180
                )
                if result.succeeded, ExtraFiles.size(url) > 0 {
                    await MainActor.run { saved = url }
                } else if result.succeeded {
                    await MainActor.run { error = "The speech engine finished without writing audio." }
                } else {
                    let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    await MainActor.run {
                        error = detail.isEmpty
                            ? "The speech engine exited with code \(result.status)."
                            : detail
                    }
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
    }
}

// MARK: - Transcribe

struct TranscribeTool: View {
    @State private var file: URL?
    @State private var transcript = ""
    @State private var status = ""
    @State private var error: String?
    @State private var working = false
    @State private var task: SFSpeechRecognitionTask?
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "waveform.and.mic", title: "Transcribe", subtitle: "Turn a recording into plain text with on-device speech recognition.") {
            DropZone(title: "Choose an audio or video file", subtitle: "M4A, MP3, WAV, AIFF, MOV or MP4.", allowsMultiple: false) { urls in
                guard let url = urls.first else { return }
                file = url
                start(url)
            }

            if let file {
                HStack(spacing: 8) {
                    FileChip(url: file) { cancel(); self.file = nil }
                    Spacer()
                    if working {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { cancel() }.buttonStyle(QuietButtonStyle())
                    }
                }
                if !status.isEmpty {
                    Text(status).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }

            if let error { InlineError(message: error) }

            TextOutputCard(
                toolName: "Transcribe",
                text: transcript,
                title: "Transcript",
                filename: (file?.deletingPathExtension().lastPathComponent ?? "transcript") + ".txt"
            )

            Text("Transcription runs on this Mac. If the offline speech model is missing, Nookit stops rather than uploading your recording.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func start(_ url: URL) {
        cancel()
        transcript = ""
        error = nil
        working = true
        status = "Preparing…"
        Task {
            let allowed = await Permissions.speech()
            guard allowed else {
                await MainActor.run {
                    working = false
                    status = ""
                    error = "Speech recognition isn’t allowed. Enable it in System Settings → Privacy & Security → Speech Recognition."
                }
                return
            }
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
                await MainActor.run {
                    working = false
                    status = ""
                    error = "No speech recogniser is available for English (US) on this Mac."
                }
                return
            }
            guard recognizer.supportsOnDeviceRecognition else {
                await MainActor.run {
                    working = false
                    status = ""
                    error = "This Mac has no on-device English (US) speech model. Nookit stopped instead of uploading your recording."
                }
                return
            }
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            await MainActor.run {
                status = "Transcribing on-device…"
            }
            let task = recognizer.recognitionTask(with: request) { result, taskError in
                Task { @MainActor in
                    if let result {
                        transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            working = false
                            status = "Finished. \(transcript.split(whereSeparator: \.isWhitespace).count) words."
                        }
                    }
                    if let taskError {
                        let ns = taskError as NSError
                        if ns.code != 216 || transcript.isEmpty { // 216 = cancelled
                            error = taskError.localizedDescription
                        }
                        working = false
                        status = ""
                    }
                }
            }
            await MainActor.run { self.task = task }
        }
    }

    private func cancel() {
        task?.cancel()
        task = nil
        working = false
        status = ""
    }
}
