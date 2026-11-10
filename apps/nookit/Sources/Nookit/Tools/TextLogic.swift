import Foundation

/// Pure helpers behind the text tools, shared with the self-test suite.
enum TextLogic {
    enum CaseStyle: String, CaseIterable, Identifiable {
        case sentence = "Sentence case"
        case title = "Title Case"
        case upper = "UPPER CASE"
        case lower = "lower case"
        case camel = "camelCase"
        case pascal = "PascalCase"
        case snake = "snake_case"
        case kebab = "kebab-case"
        var id: String { rawValue }
    }

    struct WordStats {
        var words: [String]
        var sentences: Int
        var paragraphs: Int
        var readingSeconds: Int
        var topWords: [(String, Int)]
    }

    static func words(in text: String) -> [String] {
        text.split { $0.isWhitespace || $0.isPunctuation }.map(String.init).filter { !$0.isEmpty }
    }

    static func stats(_ text: String) -> WordStats {
        let words = words(in: text)
        let sentences = text
            .split(whereSeparator: { ".!?".contains($0) })
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        let paragraphs = text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        let readingSeconds = max(1, Int(Double(words.count) / 3.5))

        var counts: [String: Int] = [:]
        for word in words {
            let key = word.lowercased()
            guard key.count > 2 else { continue }
            counts[key, default: 0] += 1
        }
        let top = counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(8)
            .map { ($0.key, $0.value) }

        return WordStats(
            words: words,
            sentences: sentences,
            paragraphs: paragraphs,
            readingSeconds: readingSeconds,
            topWords: top
        )
    }

    static func convert(_ input: String, to style: CaseStyle) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch style {
        case .sentence:
            guard let first = trimmed.first else { return "" }
            return first.uppercased() + trimmed.dropFirst().lowercased()
        case .title:
            return trimmed.split(separator: " ").map { word -> String in
                guard let first = word.first else { return String(word) }
                return first.uppercased() + word.dropFirst()
            }.joined(separator: " ")
        case .upper:
            return trimmed.uppercased()
        case .lower:
            return trimmed.lowercased()
        case .camel, .pascal, .snake, .kebab:
            let parts = trimmed
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .split(whereSeparator: { $0.isWhitespace })
                .map { $0.lowercased() }
            switch style {
            case .camel:
                return parts.enumerated().map { index, part in
                    index == 0 ? part : part.capitalized
                }.joined()
            case .pascal:
                return parts.map(\.capitalized).joined()
            case .snake:
                return parts.joined(separator: "_")
            case .kebab:
                return parts.joined(separator: "-")
            default:
                return trimmed
            }
        }
    }

    /// Expands the Batch Rename pattern for one file. The extension is added
    /// back when the expanded name doesn't already end with it.
    static func renamed(
        pattern: String,
        base: String,
        ext: String,
        index: Int,
        start: Int,
        date: String
    ) -> String {
        var name = pattern
            .replacingOccurrences(of: "{name}", with: base)
            .replacingOccurrences(of: "{n}", with: String(start + index))
            .replacingOccurrences(of: "{ext}", with: ext)
            .replacingOccurrences(of: "{date}", with: date)
        if name.isEmpty { name = base }
        if !name.hasSuffix(".\(ext)") && !ext.isEmpty { name += ".\(ext)" }
        return Fmt.safeFilename(name)
    }
}
