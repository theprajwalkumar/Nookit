import SwiftUI
import AppKit
import PDFKit
import NaturalLanguage
import Translation
import UniformTypeIdentifiers

// MARK: - Text extraction

enum TextExtract {
    /// Returns page-numbered text. PDFs keep their page numbers; text files are
    /// split on blank lines into virtual pages so citations still mean something.
    static func pages(_ url: URL) -> [(page: Int, text: String)] {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else { return [] }
            return (0..<document.pageCount).compactMap { index in
                guard let page = document.page(at: index) else { return nil }
                let text = page.string ?? ""
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : (index + 1, text)
            }
        }
        if ext == "srt" || ext == "vtt" {
            let text = SubtitleFile.parse(contentsOf: url).map(\.text).joined(separator: "\n")
            return [(1, text)]
        }
        if ext == "rtf" || ext == "rtfd" || ext == "doc" || ext == "docx" || ext == "odt" || ext == "html" || ext == "htm" {
            if let converted = convertWithTextutil(url), !converted.isEmpty {
                return split(converted)
            }
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return split(text)
        }
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .isoLatin1) {
            return split(text)
        }
        return []
    }

    static func plain(_ url: URL) -> String {
        pages(url).map(\.text).joined(separator: "\n\n")
    }

    private static func split(_ text: String) -> [(Int, String)] {
        let blocks = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if blocks.isEmpty { return [(1, text)] }
        return blocks.enumerated().map { ($0.offset + 1, $0.element) }
    }

    private static func convertWithTextutil(_ url: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - Sentence ranking

enum TextRank {
    static func sentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 2 { sentences.append(sentence) }
            return true
        }
        if sentences.isEmpty {
            return text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return sentences
    }

    static func words(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var words: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let word = String(text[range]).lowercased()
            if word.count > 2, tag == .noun || tag == .verb || tag == .adjective || tag == .otherWord || tag == .personalName || tag == .placeName {
                words.append(word)
            }
            return true
        }
        return words
    }

    static func summarize(_ text: String, sentences target: Int) -> [String] {
        let all = sentences(text)
        guard all.count > target, target > 0 else { return all }

        var frequency: [String: Int] = [:]
        for sentence in all {
            for word in words(sentence) where !stopwords.contains(word) {
                frequency[word, default: 0] += 1
            }
        }
        guard let maximum = frequency.values.max(), maximum > 0 else {
            return Array(all.prefix(target))
        }
        let normalised = frequency.mapValues { Double($0) / Double(maximum) }

        let scored = all.enumerated().map { index, sentence -> (Int, Double) in
            let tokens = words(sentence).filter { !stopwords.contains($0) }
            guard !tokens.isEmpty else { return (index, 0) }
            let sum = tokens.reduce(0.0) { $0 + (normalised[$1] ?? 0) }
            let density = sum / sqrt(Double(tokens.count))
            let position = index < all.count / 5 ? 0.12 : 0
            let lengthPenalty = sentence.count > 320 ? 0.7 : 1
            return (index, (density + position) * lengthPenalty)
        }
        let chosen = Set(scored.sorted { $0.1 > $1.1 }.prefix(target).map(\.0))
        return all.enumerated().filter { chosen.contains($0.offset) }.map(\.element)
    }
}

let stopwords: Set<String> = [
    "the", "and", "for", "that", "with", "this", "from", "have", "has", "had", "are", "was", "were",
    "you", "your", "our", "their", "they", "them", "his", "her", "she", "him", "its", "it’s", "it's",
    "but", "not", "can", "could", "would", "should", "will", "just", "about", "into", "than", "then",
    "there", "here", "what", "when", "where", "which", "who", "how", "why", "all", "any", "more",
    "most", "some", "such", "only", "also", "very", "much", "many", "one", "two", "may", "might",
    "been", "being", "does", "did", "doing", "done", "get", "got", "make", "made", "like", "over",
    "under", "again", "further", "once", "these", "those", "each", "other", "same", "own", "both",
    "few", "nor", "too", "use", "used", "using", "because", "while", "after", "before", "between"
]

// MARK: - Summarize

struct SummarizeTool: View {
    @StateObject private var job = JobState()
    @State private var text = ""
    @State private var sourceName = "Pasted text"
    @State private var ratio = 0.25
    @State private var output = ""
    @State private var inputMode: InputMode = .paste
    @EnvironmentObject private var store: ResultStore

    enum InputMode: String, CaseIterable, Identifiable {
        case paste = "Paste text"
        case file = "Open a document"
        var id: String { rawValue }
    }

    private var summaryCount: Int {
        let total = TextRank.sentences(text).count
        return max(1, Int(Double(total) * ratio))
    }

    var body: some View {
        ToolPage(symbol: "text.redaction", title: "Summarize", subtitle: "Pull the short version out of a document, transcript or pasted note. Everything runs on this Mac; nothing is uploaded.") {
            ToolCard(title: "Source") {
                OptionPicker(label: "Input", options: InputMode.allCases.map { ($0.rawValue, $0) }, selection: $inputMode)
                if inputMode == .paste {
                    TextEditor(text: $text)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 190)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
                } else {
                    DropZone(title: "Choose a document", subtitle: "PDF, TXT, Markdown, RTF, DOCX or subtitles.", allowsMultiple: false) { urls in
                        guard let url = urls.first else { return }
                        let pages = TextExtract.pages(url)
                        text = pages.map(\.text).joined(separator: "\n\n")
                        sourceName = url.lastPathComponent
                        output = ""
                        job.clear()
                    }
                }
                HStack(spacing: 16) {
                    Text("Length").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    Slider(value: $ratio, in: 0.05...0.6, step: 0.05).frame(maxWidth: 240)
                    Text("\(Int(ratio * 100))%").font(Theme.mono).frame(width: 42)
                    Text("about \(summaryCount) sentence\(summaryCount == 1 ? "" : "s")").font(Theme.caption).foregroundStyle(Theme.textTertiary)
                }
                Text("Nookit uses an extractive summariser: it selects the most representative sentences and keeps their original wording. It does not invent new sentences or add facts.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 10) {
                    Button(job.working ? "Summarising…" : "Summarise") { run() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 || job.working)
                    Button("Clear") { text = ""; output = ""; sourceName = "Pasted text"; job.clear() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(text.isEmpty && output.isEmpty)
                    Spacer()
                    if !text.isEmpty {
                        Text("\(TextRank.sentences(text).count) sentences · \(text.split(whereSeparator: \.isWhitespace).count) words")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                if let error = job.error { InlineError(message: error) }
            }

            if !output.isEmpty {
                ToolCard(title: "Summary", subtitle: "\(sourceName) · \(Int(ratio * 100))% of the original", trailing: AnyView(
                    HStack(spacing: 6) {
                        CopyButton(value: output)
                        Button("Save") { save() }.buttonStyle(QuietButtonStyle())
                    }
                )) {
                    ScrollView {
                        Text(output)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 320)
                    .background(Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
    }

    private func run() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.count >= 40 else {
            job.fail("Add a little more text first.")
            return
        }
        let count = summaryCount
        job.begin("Reading the structure…")
        Task {
            let sentences = TextRank.summarize(body, sentences: count)
            let summary = sentences.enumerated()
                .map { "- \($0.element.trimmingCharacters(in: .whitespacesAndNewlines))" }
                .joined(separator: "\n")
            let words = body.split(whereSeparator: \.isWhitespace).count
            await MainActor.run {
                output = summary
                job.finish([], "Kept \(sentences.count) of \(TextRank.sentences(body).count) sentences.")
                _ = words
            }
        }
    }

    private func save() {
        do {
            let folder = store.datedFolder(for: "Summarize")
            let base = (sourceName as NSString).deletingPathExtension
            let name = base == "Pasted text" ? "summary" : "\(base)-summary"
            let target = try store.write(string: output, to: folder, filename: "\(name).md")
            job.finish([target], "Saved \(target.lastPathComponent).")
        } catch {
            job.fail(error)
        }
    }
}

// MARK: - Capture text

struct CaptureTextTool: View {
    @StateObject private var job = JobState()
    @State private var text = ""
    @State private var source = "Screen selection"
    @State private var mode: Capture = .area
    @EnvironmentObject private var store: ResultStore

    enum Capture: String, CaseIterable, Identifiable {
        case area = "Selected area"
        case window = "A window"
        case screen = "The whole screen"
        var id: String { rawValue }
        var args: [String] {
            switch self {
            case .area: return ["-i"]
            case .window: return ["-i", "-W"]
            case .screen: return ["-m"]
            }
        }
    }

    var body: some View {
        ToolPage(symbol: "viewfinder", title: "Capture Text", subtitle: "Select part of the screen and get the words inside it. No screenshot is added to your Desktop unless you ask for one.") {
            ToolCard(title: "Capture") {
                OptionPicker(label: "Source", options: Capture.allCases.map { ($0.rawValue, $0) }, selection: $mode)
                HStack(spacing: 10) {
                    Button(job.working ? "Reading…" : "Select and read") { capture() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(job.working)
                    Button("From clipboard image") { readClipboard() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(job.working)
                    Spacer()
                    if !text.isEmpty {
                        CopyButton(value: text)
                        Button("Save") { save() }.buttonStyle(QuietButtonStyle())
                    }
                }
                Text("Screen recording permission is needed the first time. Press Escape to cancel the selection.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                if let error = job.error { InlineError(message: error) }
                if !job.status.isEmpty && !job.working {
                    Text(job.status).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
            }

            if !text.isEmpty {
                ToolCard(title: "Text", subtitle: "\(source) · \(text.count) characters", trailing: AnyView(
                    Button("Clear") { text = "" }.buttonStyle(QuietButtonStyle())
                )) {
                    TextEditor(text: $text)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 240)
                        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    Text("Recognised with Apple’s Vision framework. You can correct any misread words above before saving.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                ToolCard(title: "Also works with images") {
                    DropZone(title: "Drop a screenshot", subtitle: "PNG, JPEG or HEIC. The image is read locally and never uploaded.", allowsMultiple: false, types: [.image]) { urls in
                        guard let url = urls.first, let image = ImageEngine.source(url) else { return }
                        read(image, name: url.lastPathComponent)
                    }
                }
            }
        }
    }

    private func capture() {
        job.begin("Waiting for the selection…")
        let current = mode
        Task {
            do {
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("nookit-capture-\(UUID().uuidString).png")
                defer { try? FileManager.default.removeItem(at: temp) }
                let result = try await Shell.run("/usr/sbin/screencapture", ["-x"] + current.args + [temp.path], timeout: 300)
                guard result.succeeded, FileManager.default.fileExists(atPath: temp.path),
                      let image = NSImage(contentsOf: temp).flatMap(ImageData.cgImage) else {
                    throw ToolError.message("Nothing was captured. If you cancelled the selection, try again; otherwise allow Nookit in System Settings → Privacy & Security → Screen Recording.")
                }
                let recognised = VisionText.text(image).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !recognised.isEmpty else {
                    throw ToolError.message("The selection had no readable text. Try a tighter selection or a larger area.")
                }
                await MainActor.run {
                    text = recognised
                    source = current.rawValue
                    job.finish([], "Found \(recognised.split(whereSeparator: \.isNewline).count) lines.")
                }
            } catch {
                await MainActor.run { job.fail(error) }
            }
        }
    }

    private func readClipboard() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let cg = ImageData.cgImage(image) else {
            job.fail("The clipboard does not contain an image. Copy a screenshot first.")
            return
        }
        read(cg, name: "Clipboard image")
    }

    private func read(_ image: CGImage, name: String) {
        job.begin("Reading the image…")
        Task {
            let recognised = VisionText.text(image).trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                if recognised.isEmpty {
                    job.fail("No readable text was found in that image.")
                } else {
                    text = recognised
                    source = name
                    job.finish([], "Found \(recognised.split(whereSeparator: \.isNewline).count) lines.")
                }
            }
        }
    }

    private func save() {
        do {
            let folder = store.datedFolder(for: "Capture Text")
            let target = try store.write(string: text, to: folder, filename: "captured-text-\(Fmt.stampTime.string(from: Date())).txt")
            job.finish([target], "Saved \(target.lastPathComponent).")
        } catch {
            job.fail(error)
        }
    }
}

// MARK: - Subtitles

enum SubtitleFile {
    struct Cue {
        var index: Int
        var start: String
        var end: String
        var text: String
    }

    static func parse(contentsOf url: URL) -> [Cue] {
        guard let body = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(body)
    }

    /// Accepts `00:00:01,500`, `00:00:01.500`, `0:00:01.50` (ASS) and
    /// `00:01.500` (WebVTT without an hours field).
    static func seconds(_ stamp: String) -> Double? {
        let parts = stamp
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ":")
            .map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let seconds = Double(parts[parts.count - 1]),
              let minutes = Double(parts[parts.count - 2]) else { return nil }
        let hours = parts.count == 3 ? (Double(parts[0]) ?? 0) : 0
        guard hours >= 0, minutes >= 0, seconds >= 0 else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    static func srtStamp(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let h = Int(total) / 3600
        let m = (Int(total) % 3600) / 60
        let s = Int(total) % 60
        let ms = Int(((total - Double(Int(total))) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, min(ms, 999))
    }

    static func parse(_ body: String) -> [Cue] {
        let normalised = body.replacingOccurrences(of: "\r\n", with: "\n")

        // Advanced SubStation Alpha keeps every cue on a single `Dialogue:`
        // line; convert those to the same cue shape as SRT/VTT.
        let dialogue = normalised.components(separatedBy: "\n").filter { $0.hasPrefix("Dialogue:") }
        if !dialogue.isEmpty {
            return dialogue.enumerated().compactMap { offset, line in
                let fields = line.dropFirst("Dialogue:".count)
                    .split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
                guard fields.count == 10,
                      let start = seconds(String(fields[1])),
                      let end = seconds(String(fields[2]))
                else { return nil }
                var text = String(fields[9])
                    .replacingOccurrences(of: "\\N", with: " ")
                    .replacingOccurrences(of: "\\n", with: " ")
                text = text.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return Cue(index: offset, start: srtStamp(start), end: srtStamp(end), text: text)
            }
        }

        var cues: [Cue] = []
        let blocks = normalised.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = lines[timingIndex].components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
            guard times.count == 2 else { continue }
            // WebVTT allows cue settings after the end timestamp.
            let start = times[0].split(separator: " ").first.map(String.init) ?? times[0]
            let end = times[1].split(separator: " ").first.map(String.init) ?? times[1]
            let text = lines.dropFirst(timingIndex + 1).joined(separator: " ")
            guard !text.isEmpty else { continue }
            cues.append(Cue(index: cues.count, start: start, end: end, text: text))
        }
        return cues
    }

    static func srt(_ cues: [Cue]) -> String {
        cues.map { "\($0.index + 1)\n\($0.start) --> \($0.end)\n\($0.text)\n" }.joined(separator: "\n")
    }
}

// MARK: - Translate

struct TranslateTool: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            TranslateModernTool()
        } else {
            ToolPage(symbol: "character.bubble", title: "Translate", subtitle: "On-device translation needs macOS 15 or later.") {
                ToolCard(title: "Not available") {
                    Text("This Mac runs an older macOS. Update to macOS 15 or later to translate text and subtitles on device.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

@available(macOS 15.0, *)
@MainActor
final class TranslationRunner: ObservableObject {
    @Published var isWorking = false
    @Published var status = ""
    @Published var error: String?
    @Published var output = ""

    var pendingText: String?
    var pendingCues: [SubtitleFile.Cue]?
    var targetCode = "es"

    func perform(_ session: TranslationSession) async {
        isWorking = true
        error = nil
        output = ""
        status = "Preparing the language pack…"
        do {
            try await session.prepareTranslation()
            if let text = pendingText {
                status = "Translating…"
                let response = try await session.translate(text)
                output = response.targetText
                status = "Translated on this Mac."
            } else if let cues = pendingCues {
                status = "Translating \(cues.count) captions…"
                let requests = cues.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.index)) }
                let responses = try await session.translations(from: requests)
                var map: [Int: String] = [:]
                for response in responses {
                    if let id = response.clientIdentifier, let index = Int(id) {
                        map[index] = response.targetText
                    }
                }
                var translated = cues
                for index in translated.indices {
                    if let value = map[index] { translated[index].text = value }
                }
                output = SubtitleFile.srt(translated)
                status = "Translated \(translated.count) captions; timings unchanged."
            }
            pendingText = nil
            pendingCues = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = ""
        }
        isWorking = false
    }
}

@available(macOS 15.0, *)
struct TranslateModernTool: View {
    @StateObject private var runner = TranslationRunner()
    @StateObject private var job = JobState()
    @State private var mode: Mode = .text
    @State private var text = ""
    @State private var subtitle: URL?
    @State private var target = "es"
    @State private var configuration: TranslationSession.Configuration?
    @EnvironmentObject private var store: ResultStore

    enum Mode: String, CaseIterable, Identifiable {
        case text = "Text"
        case subtitles = "Subtitles"
        var id: String { rawValue }
    }

    private let languages: [(String, String)] = [
        ("Spanish", "es"), ("French", "fr"), ("German", "de"), ("Italian", "it"),
        ("Portuguese", "pt"), ("Dutch", "nl"), ("Polish", "pl"), ("Swedish", "sv"),
        ("Danish", "da"), ("Norwegian", "nb"), ("Finnish", "fi"), ("Turkish", "tr"),
        ("Czech", "cs"), ("Greek", "el"), ("Romanian", "ro"), ("Hungarian", "hu"),
        ("Ukrainian", "uk"), ("Russian", "ru"), ("Arabic", "ar"), ("Hebrew", "he"),
        ("Hindi", "hi"), ("Thai", "th"), ("Vietnamese", "vi"), ("Indonesian", "id"),
        ("Japanese", "ja"), ("Korean", "ko"), ("Chinese (Simplified)", "zh-Hans"),
        ("Chinese (Traditional)", "zh-Hant")
    ]

    private var languageName: String {
        languages.first { $0.1 == target }?.0 ?? target
    }

    var body: some View {
        ToolPage(symbol: "character.bubble", title: "Translate", subtitle: "Text and subtitle files, translated by Apple’s on-device models. Nothing leaves the Mac.") {
            ToolCard(title: "What to translate") {
                OptionPicker(label: "Mode", options: Mode.allCases.map { ($0.rawValue, $0) }, selection: $mode)
                OptionPicker(label: "Into", options: languages, selection: $target)
                if mode == .text {
                    TextEditor(text: $text)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 190)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
                } else {
                    DropZone(title: "Choose a subtitle file", subtitle: "SRT or WebVTT. Timings are preserved.", allowsMultiple: false, types: [.item], height: 86) { urls in
                        subtitle = urls.first
                        job.clear()
                    }
                    if let subtitle { FileChip(url: subtitle) { self.subtitle = nil } }
                }
                HStack(spacing: 10) {
                    Button(runner.isWorking ? "Translating…" : "Translate") { run() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(runner.isWorking || !canRun)
                    if !runner.output.isEmpty {
                        CopyButton(value: runner.output)
                        Button("Save") { save() }.buttonStyle(QuietButtonStyle())
                    }
                    Spacer()
                    Text("Apple may ask to download a language the first time.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                if runner.isWorking || !runner.status.isEmpty {
                    HStack(spacing: 8) {
                        if runner.isWorking { ProgressView().controlSize(.small) }
                        Text(runner.status).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                if let error = runner.error { InlineError(message: error) }
            }

            if !runner.output.isEmpty {
                ToolCard(title: mode == .text ? "Translation" : "Translated subtitles", subtitle: "Into \(languageName)") {
                    ScrollView {
                        Text(runner.output)
                            .font(.system(size: mode == .text ? 13 : 11, design: mode == .text ? .default : .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 340)
                    .background(Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .translationTask(configuration) { session in
            await runner.perform(session)
        }
    }

    private var canRun: Bool {
        if mode == .text { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return subtitle != nil
    }

    private func run() {
        runner.pendingText = nil
        runner.pendingCues = nil
        runner.targetCode = target
        if mode == .text {
            runner.pendingText = text
        } else if let subtitle {
            let cues = SubtitleFile.parse(contentsOf: subtitle)
            guard !cues.isEmpty else {
                runner.error = "No subtitle cues were found in that file."
                return
            }
            runner.pendingCues = cues
        }
        let language = Locale.Language(identifier: target)
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: nil, target: language)
        } else {
            configuration?.target = language
            configuration?.invalidate()
        }
    }

    private func save() {
        do {
            let folder = store.datedFolder(for: "Translate")
            let name: String
            if mode == .subtitles, let subtitle {
                name = "\(subtitle.deletingPathExtension().lastPathComponent)-\(target).srt"
            } else {
                name = "translation-\(target)-\(Fmt.stampTime.string(from: Date())).txt"
            }
            let target = try store.write(string: runner.output, to: folder, filename: name)
            job.finish([target], "Saved \(target.lastPathComponent).")
        } catch {
            job.fail(error)
        }
    }
}

// MARK: - Ask a document

struct AskDocumentTool: View {
    @StateObject private var job = JobState()
    @State private var file: URL?
    @State private var pages: [(page: Int, text: String)] = []
    @State private var question = ""
    @State private var answer = ""
    @State private var evidence: [(page: Int, text: String, score: Double)] = []
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "bubble.left.and.text.bubble.right", title: "Ask a Document", subtitle: "Ask a PDF or text file a question and get an answer with the page it came from. Indexing and search stay on this Mac.") {
            ToolCard(title: "Document") {
                DropZone(title: "Choose a PDF or text file", subtitle: "PDF, TXT, Markdown, RTF, DOCX or subtitles.", allowsMultiple: false) { urls in
                    guard let url = urls.first else { return }
                    let extracted = TextExtract.pages(url)
                    guard !extracted.isEmpty else {
                        job.fail("No text was found. Run Make PDF Searchable first if this is a scan.")
                        return
                    }
                    file = url
                    pages = extracted
                    answer = ""
                    evidence = []
                    job.clear()
                }
                if let file {
                    HStack {
                        FileChip(url: file) { self.file = nil; pages = []; answer = ""; evidence = [] }
                        Spacer()
                        Text("\(pages.count) page\(pages.count == 1 ? "" : "s") indexed")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            if !pages.isEmpty {
                ToolCard(title: "Question") {
                    HStack(spacing: 10) {
                        TextField("What does the document say about…", text: $question)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
                            .onSubmit { run() }
                        Button("Ask") { run() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Answers are quoted from the document, not generated, so every sentence can be checked against its page.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if !answer.isEmpty {
                ToolCard(title: "Answer", trailing: AnyView(
                    HStack(spacing: 6) {
                        CopyButton(value: answer)
                        Button("Save") { save() }.buttonStyle(QuietButtonStyle())
                    }
                )) {
                    Text(answer)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !evidence.isEmpty {
                ToolCard(title: "Where it came from") {
                    VStack(spacing: 1) {
                        ForEach(Array(evidence.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("Page \(item.page)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Theme.ember)
                                    Spacer()
                                    Text(String(format: "%.0f%% match", min(99, item.score * 100)))
                                        .font(Theme.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Text(item.text)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(4)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.raised.opacity(0.45))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func run() {
        let query = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let pages = self.pages
        job.begin("Searching the document…")
        Task {
            let terms = Set(TextRank.words(query)).union(query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count > 2 })
            guard !terms.isEmpty else {
                await MainActor.run { job.fail("Use a few more words in the question.") }
                return
            }
            var scored: [(Int, String, Double)] = []
            let allSentences = pages.flatMap { page in TextRank.sentences(page.text).map { (page.page, $0) } }
            let total = max(1, allSentences.count)
            for (page, sentence) in allSentences {
                let lower = sentence.lowercased()
                let words = TextRank.words(sentence)
                guard !words.isEmpty else { continue }
                var hits = 0.0
                for term in terms where lower.contains(term) { hits += 1 }
                guard hits > 0 else { continue }
                let coverage = hits / Double(terms.count)
                let density = hits / sqrt(Double(words.count))
                let score = coverage * 0.7 + density * 0.3 + (1.0 / Double(total))
                scored.append((page, sentence.trimmingCharacters(in: .whitespacesAndNewlines), score))
            }
            let top = scored.sorted { $0.2 > $1.2 }.prefix(4)
            await MainActor.run {
                if top.isEmpty {
                    answer = ""
                    evidence = []
                    job.fail("I couldn’t find that in this document. Try different words, or check whether the page is a scan without a text layer.")
                    return
                }
                let maxScore = top.map(\.2).max() ?? 1
                evidence = top.map { (page: $0.0, text: $0.1, score: $0.2 / maxScore) }
                answer = top.map { "• \($0.1)  [p. \($0.0)]" }.joined(separator: "\n\n")
                job.finish([], "Found \(top.count) relevant passage\(top.count == 1 ? "" : "s").")
            }
        }
    }

    private func save() {
        do {
            let folder = store.datedFolder(for: "Ask a Document")
            let body = "# \(question)\n\n\(answer)\n\n## Sources\n" + evidence.map { "- Page \($0.page): \($0.text)" }.joined(separator: "\n")
            let base = file?.deletingPathExtension().lastPathComponent ?? "answer"
            let target = try store.write(string: body, to: folder, filename: "\(base)-answer.md")
            job.finish([target], "Saved \(target.lastPathComponent).")
        } catch {
            job.fail(error)
        }
    }
}
