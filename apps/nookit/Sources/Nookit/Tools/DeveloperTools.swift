import SwiftUI
import AppKit
import CryptoKit
import Foundation

// MARK: - JSON

struct JSONFormatterTool: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case pretty = "Format"
        case minify = "Minify"
        case validate = "Validate"
        var id: String { rawValue }
    }

    @State private var input = #"{"name":"Nookit","private":true,"tools":[1,2,3]}"#
    @State private var mode: Mode = .pretty
    @State private var sortKeys = true

    private var result: (output: String, error: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", nil) }
        do {
            let object = try JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed])
            if mode == .validate {
                return ("Valid JSON.\n\n\(describe(object))", nil)
            }
            guard JSONSerialization.isValidJSONObject(object) else {
                return ("", "This is valid JSON but not an object or array, so it can’t be re-serialised.")
            }
            var options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
            if mode == .pretty { options.insert(.prettyPrinted) }
            if sortKeys { options.insert(.sortedKeys) }
            let data = try JSONSerialization.data(withJSONObject: object, options: options)
            return (String(decoding: data, as: UTF8.self), nil)
        } catch {
            return ("", readable(error))
        }
    }

    private func describe(_ value: Any) -> String {
        if let array = value as? [Any] { return "Top level: array with \(array.count) item\(array.count == 1 ? "" : "s")." }
        if let dict = value as? [String: Any] { return "Top level: object with \(dict.count) key\(dict.count == 1 ? "" : "s")." }
        return "Top level: \(type(of: value))."
    }

    private func readable(_ error: Error) -> String {
        let ns = error as NSError
        if let debug = ns.userInfo[NSDebugDescriptionErrorKey] as? String { return debug }
        return error.localizedDescription
    }

    var body: some View {
        ToolPage(symbol: "curlybraces", title: "JSON Formatter", subtitle: "Format, minify and validate JSON without sending it anywhere.") {
            HStack(spacing: 14) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                Toggle("Sort keys", isOn: $sortKeys)
                    .toggleStyle(.checkbox)
                    .font(Theme.body)
                Spacer()
            }

            HStack(alignment: .top, spacing: Theme.Space.m) {
                ToolCard(title: "JSON", subtitle: "Paste or type. Everything is parsed on this Mac.") {
                    CodeEditor(text: $input, height: 280, placeholder: "Paste JSON here…")
                }
                TextOutputCard(
                    toolName: "JSON Formatter",
                    text: result.output,
                    title: result.error == nil ? (mode == .validate ? "Check" : "Result") : "Problem",
                    filename: mode == .minify ? "minified.json" : "formatted.json",
                    footnote: result.error == nil ? nil : "Fix the highlighted issue and try again."
                )
            }

            if let error = result.error {
                InlineError(message: error)
            }
        }
    }
}

// MARK: - Base64

struct Base64Tool: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case encode = "Text → Base64"
        case decode = "Base64 → Text"
        var id: String { rawValue }
    }

    @State private var input = "Nookit keeps this on your Mac."
    @State private var mode: Mode = .encode
    @State private var urlSafe = false

    private var result: (String, String?) {
        switch mode {
        case .encode:
            return (DeveloperLogic.base64Encode(input, urlSafe: urlSafe), nil)
        case .decode:
            return DeveloperLogic.base64Decode(input)
        }
    }

    var body: some View {
        ToolPage(symbol: "textformat.abc.dottedunderline", title: "Base64", subtitle: "Encode or decode text. URL-safe mode drops padding and swaps + / for - _.") {
            HStack(spacing: 14) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)
                Toggle("URL-safe", isOn: $urlSafe)
                    .toggleStyle(.checkbox)
                    .font(Theme.body)
                Spacer()
            }

            HStack(alignment: .top, spacing: Theme.Space.m) {
                ToolCard(title: mode == .encode ? "Plain text" : "Base64") {
                    CodeEditor(text: $input, height: 240, placeholder: "Type here…")
                }
                TextOutputCard(
                    toolName: "Base64",
                    text: result.0,
                    title: mode == .encode ? "Encoded" : "Decoded",
                    filename: mode == .encode ? "base64.txt" : "decoded.txt"
                )
            }

            if let error = result.1 { InlineError(message: error) }
        }
    }
}

// MARK: - Hash

struct HashGeneratorTool: View {
    private enum Algorithm: String, CaseIterable, Identifiable {
        case md5 = "MD5"
        case sha1 = "SHA-1"
        case sha256 = "SHA-256"
        case sha512 = "SHA-512"
        var id: String { rawValue }
    }

    @State private var input = "Nookit"
    @State private var algorithm: Algorithm = .sha256

    private var digest: String {
        let data = Data(input.utf8)
        switch algorithm {
        case .md5: return Fmt.hex(Data(Insecure.MD5.hash(data: data)))
        case .sha1: return Fmt.hex(Data(Insecure.SHA1.hash(data: data)))
        case .sha256: return Fmt.hex(Data(SHA256.hash(data: data)))
        case .sha512: return Fmt.hex(Data(SHA512.hash(data: data)))
        }
    }

    var body: some View {
        ToolPage(symbol: "number", title: "Hash Generator", subtitle: "MD5, SHA-1, SHA-256 and SHA-512 digests for text, computed locally.") {
            ToolCard(title: "Input") {
                CodeEditor(text: $input, height: 180, placeholder: "Text to hash…")
                OptionPicker(label: "Algorithm", options: Algorithm.allCases.map { ($0.rawValue, $0) }, selection: $algorithm)
                Text("MD5 and SHA-1 are for checksums only. Use SHA-256 or SHA-512 for anything security-related.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            TextOutputCard(
                toolName: "Hash Generator",
                text: digest,
                title: "\(algorithm.rawValue) digest",
                filename: "hash-\(algorithm.rawValue.lowercased()).txt",
                footnote: "\(digest.count / 2) bytes · lowercase hex"
            )
        }
    }
}

// MARK: - UUID

struct UUIDGeneratorTool: View {
    @State private var count = 5
    @State private var uppercase = false
    @State private var hyphenated = true
    @State private var values: [String] = []

    var body: some View {
        ToolPage(symbol: "number.square", title: "UUID Generator", subtitle: "Random version-4 identifiers, generated on demand.") {
            ToolCard(title: "Options") {
                HStack(spacing: 18) {
                    Stepper("Count: \(count)", value: $count, in: 1...100)
                        .font(Theme.body)
                    Toggle("Uppercase", isOn: $uppercase).toggleStyle(.checkbox)
                    Toggle("Hyphens", isOn: $hyphenated).toggleStyle(.checkbox)
                    Spacer()
                    Button("Generate") { generate() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            TextOutputCard(
                toolName: "UUID Generator",
                text: values.joined(separator: "\n"),
                title: "UUIDs",
                filename: "uuids.txt"
            )
            .onAppear { if values.isEmpty { generate() } }
        }
    }

    private func generate() {
        values = (0..<count).map { _ in
            DeveloperLogic.uuid(upper: uppercase, hyphens: hyphenated)
        }
    }
}

// MARK: - JWT

struct JWTDecoderTool: View {
    @State private var token = ""

    private var parts: (header: String, payload: String, error: String?) {
        DeveloperLogic.jwtParts(token)
    }

    private var claims: [(String, String)] {
        DeveloperLogic.jwtClaims(token)
    }

    var body: some View {
        ToolPage(symbol: "key.horizontal", title: "JWT Decoder", subtitle: "Read a JSON Web Token’s header and claims. The signature is not verified.") {
            ToolCard(title: "Token") {
                CodeEditor(text: $token, height: 120, placeholder: "eyJhbGciOi…")
                Text("Decoding never proves a token is genuine. Verify signatures on your server.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            if let error = parts.error, !error.isEmpty {
                InlineError(message: error)
            } else {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    TextOutputCard(toolName: "JWT Decoder", text: parts.header, title: "Header", filename: "jwt-header.json")
                    TextOutputCard(toolName: "JWT Decoder", text: parts.payload, title: "Payload", filename: "jwt-payload.json")
                }
                if !claims.isEmpty {
                    ToolCard(title: "Registered claims") {
                        VStack(spacing: 1) {
                            ForEach(claims, id: \.0) { claim in
                                HStack {
                                    Text(claim.0)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Theme.ember)
                                        .frame(width: 60, alignment: .leading)
                                    Text(claim.1)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(Theme.textPrimary)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Theme.raised.opacity(0.45))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
        }
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        DeveloperLogic.decodeBase64URL(value)
    }

    private func pretty(_ data: Data) -> String {
        DeveloperLogic.prettyJSON(data)
    }
}

// MARK: - Timestamp

struct TimestampConverterTool: View {
    @State private var epoch = String(Int(Date().timeIntervalSince1970))
    @State private var unit: Unit = .seconds
    @State private var pickedDate = Date()

    private enum Unit: String, CaseIterable, Identifiable {
        case seconds = "Seconds"
        case milliseconds = "Milliseconds"
        var id: String { rawValue }
    }

    private var parsedDate: Date? {
        guard let value = Double(epoch.trimmingCharacters(in: .whitespaces)) else { return nil }
        return Date(timeIntervalSince1970: unit == .seconds ? value : value / 1000)
    }

    var body: some View {
        ToolPage(symbol: "clock.arrow.circlepath", title: "Timestamp Converter", subtitle: "Turn Unix timestamps into local dates, and dates back into timestamps.") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    StatTile(label: "Unix seconds", value: String(Int(context.date.timeIntervalSince1970)))
                    StatTile(label: "Milliseconds", value: String(Int(context.date.timeIntervalSince1970 * 1000)))
                    StatTile(label: "ISO 8601", value: Fmt.iso(context.date))
                }
            }

            HStack(alignment: .top, spacing: Theme.Space.m) {
                ToolCard(title: "Timestamp → date") {
                    TextField("1700000000", text: $epoch)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .fieldStyle()
                    OptionPicker(label: "Unit", options: Unit.allCases.map { ($0.rawValue, $0) }, selection: $unit)
                    if let date = parsedDate {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Fmt.shortDate(date)).font(.system(size: 16, weight: .semibold))
                            Text(Fmt.iso(date)).font(Theme.mono).foregroundStyle(Theme.textSecondary)
                            Text(date.description(with: Locale.current)).font(Theme.caption).foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.top, 4)
                    } else {
                        Text("Enter a number to convert.").font(Theme.body).foregroundStyle(Theme.textTertiary)
                    }
                }
                ToolCard(title: "Date → timestamp") {
                    DatePicker("Pick a moment", selection: $pickedDate)
                        .datePickerStyle(.compact)
                    let seconds = Int(pickedDate.timeIntervalSince1970)
                    HStack {
                        Text(String(seconds)).font(.system(size: 14, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        CopyButton(value: String(seconds))
                    }
                    .padding(10)
                    .background(Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text("Local timezone: \(TimeZone.current.identifier)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

// MARK: - Diff

struct DiffCheckerTool: View {
    private typealias DiffKind = DeveloperLogic.DiffKind

    @State private var left = "The quick brown fox\njumps over the lazy dog.\nNookit stays local."
    @State private var right = "The quick brown fox\njumps over the lazy dog.\nNookit stays on your Mac."

    private var rows: [(DiffKind, String)] { diff(left, right) }

    var body: some View {
        ToolPage(symbol: "plus.forwardslash.minus", title: "Diff Checker", subtitle: "Compare two blocks of text and see exactly which lines changed.") {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                ToolCard(title: "Original") {
                    CodeEditor(text: $left, height: 220)
                }
                ToolCard(title: "Changed") {
                    CodeEditor(text: $right, height: 220)
                }
            }

            ToolCard(title: "Difference", subtitle: "\(rows.filter { $0.0 == .added }.count) added · \(rows.filter { $0.0 == .removed }.count) removed") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 8) {
                                Text(prefix(row.0))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(color(row.0))
                                    .frame(width: 14)
                                Text(row.1.isEmpty ? " " : row.1)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.textPrimary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(background(row.0))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 140, maxHeight: 320)
                .background(Theme.raised.opacity(0.35), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private func prefix(_ kind: DiffKind) -> String {
        switch kind { case .same: return " "; case .added: return "+"; case .removed: return "−" }
    }

    private func color(_ kind: DiffKind) -> Color {
        switch kind { case .same: return Theme.textTertiary; case .added: return Theme.mint; case .removed: return Theme.danger }
    }

    private func background(_ kind: DiffKind) -> Color {
        switch kind {
        case .same: return .clear
        case .added: return Theme.mint.opacity(0.08)
        case .removed: return Theme.danger.opacity(0.08)
        }
    }

    /// Longest-common-subsequence line diff, shared with the self-test suite.
    private func diff(_ a: String, _ b: String) -> [(DiffKind, String)] {
        DeveloperLogic.diff(a, b)
    }
}

// MARK: - Regex

struct RegexTesterTool: View {
    @State private var pattern = #"\b[A-Z]{2,}\b"#
    @State private var text = "Nookit runs on macOS and keeps PDFs, JSON and URLs on-device."
    @State private var caseInsensitive = false
    @State private var multiline = true

    private var matches: [(String, NSRange)] {
        DeveloperLogic.regexMatches(
            pattern: pattern,
            text: text,
            caseInsensitive: caseInsensitive,
            multiline: multiline
        )
    }

    private var regexError: String? {
        DeveloperLogic.regexError(pattern: pattern, caseInsensitive: caseInsensitive)
    }

    var body: some View {
        ToolPage(symbol: "text.magnifyingglass", title: "Regex Tester", subtitle: "Try a regular expression against sample text and inspect every match.") {
            ToolCard(title: "Pattern") {
                TextField(#"\bword\b"#, text: $pattern)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .fieldStyle()
                HStack(spacing: 16) {
                    Toggle("Ignore case", isOn: $caseInsensitive).toggleStyle(.checkbox)
                    Toggle("Multiline anchors", isOn: $multiline).toggleStyle(.checkbox)
                    Spacer()
                    Badge(text: "\(matches.count) match\(matches.count == 1 ? "" : "es")", tint: regexError == nil ? Theme.mint : Theme.danger)
                }
                .font(Theme.body)
            }

            if let regexError {
                InlineError(message: regexError)
            }

            ToolCard(title: "Test text") {
                CodeEditor(text: $text, height: 180)
                if !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
                            HStack(spacing: 8) {
                                Text("#\(index + 1)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(width: 26, alignment: .leading)
                                Text(match.0.isEmpty ? "(empty match)" : match.0)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.textPrimary)
                                    .textSelection(.enabled)
                                Spacer()
                                Text("offset \(match.1.location) · length \(match.1.length)")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Theme.raised.opacity(0.45), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Clean links

struct CleanLinksTool: View {
    @State private var input = "https://example.com/article?utm_source=newsletter&utm_medium=email&id=42#top"

    private var cleaned: String {
        DeveloperLogic.cleanLinks(input)
    }

    private var removedCount: Int {
        DeveloperLogic.removedLinkParameters(input)
    }

    var body: some View {
        ToolPage(symbol: "link.badge.plus", title: "Clean Links", subtitle: "Strip tracking parameters from links before you share them.") {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                ToolCard(title: "Paste links", subtitle: "One per line.") {
                    CodeEditor(text: $input, height: 240)
                }
                TextOutputCard(
                    toolName: "Clean Links",
                    text: cleaned,
                    title: "Cleaned",
                    filename: "clean-links.txt",
                    footnote: removedCount == 0 ? "No tracking parameters found." : "Removed \(removedCount) parameter\(removedCount == 1 ? "" : "s")."
                )
            }
        }
    }
}

// MARK: - Unicode

struct UnicodeInspectorTool: View {
    @State private var input = "Nookit ✓ 🪄 café"

    private var scalars: [(String, String, String, String)] {
        input.unicodeScalars.enumerated().map { index, scalar in
            let utf8 = String(scalar).utf8.map { String(format: "%02X", $0) }.joined(separator: " ")
            let category = String(describing: scalar.properties.generalCategory)
            return ("\(index + 1)", String(scalar), String(format: "U+%04X", scalar.value), "\(utf8)  ·  \(category)")
        }
    }

    var body: some View {
        ToolPage(symbol: "character.book.closed", title: "Unicode Inspector", subtitle: "See the code points and UTF-8 bytes behind any text.") {
            ToolCard(title: "Text") {
                CodeEditor(text: $input, height: 90)
            }
            StatRow(items: [
                ("Characters", "\(input.count)"),
                ("Scalars", "\(input.unicodeScalars.count)"),
                ("UTF-8 bytes", "\(input.utf8.count)"),
                ("UTF-16 units", "\(input.utf16.count)")
            ])
            ToolCard(title: "Code points") {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(scalars.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 10) {
                                Text(row.0).font(Theme.caption).foregroundStyle(Theme.textTertiary).frame(width: 26, alignment: .trailing)
                                Text(row.1).font(.system(size: 16)).frame(width: 34)
                                Text(row.2).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.ember).frame(width: 66, alignment: .leading)
                                Text(row.3).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.raised.opacity(0.4))
                        }
                    }
                }
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

// MARK: - Lorem ipsum

struct LoremIpsumTool: View {
    @State private var paragraphs = 3
    @State private var sentences = 4
    @State private var startClassic = true
    @State private var output = ""

    var body: some View {
        ToolPage(symbol: "text.alignleft", title: "Lorem Ipsum", subtitle: "Placeholder copy in the Nookit voice, generated locally.") {
            ToolCard(title: "Options") {
                HStack(spacing: 20) {
                    Stepper("Paragraphs: \(paragraphs)", value: $paragraphs, in: 1...20)
                    Stepper("Sentences each: \(sentences)", value: $sentences, in: 1...10)
                    Toggle("Open with “Lorem ipsum”", isOn: $startClassic).toggleStyle(.checkbox)
                    Spacer()
                    Button("Generate") { generate() }.buttonStyle(PrimaryButtonStyle())
                    Button("Copy") { copy(output) }.buttonStyle(QuietButtonStyle())
                }
                .font(Theme.body)
            }
            TextOutputCard(toolName: "Lorem Ipsum", text: output, title: "Placeholder", filename: "lorem-ipsum.txt", footnote: "\(output.split(whereSeparator: \.isWhitespace).count) words")
                .onAppear { if output.isEmpty { generate() } }
        }
    }

    private func generate() {
        output = DeveloperLogic.lorem(paragraphs: paragraphs, sentences: sentences, startClassic: startClassic)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
