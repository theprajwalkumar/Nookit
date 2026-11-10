import Foundation

/// Pure helpers behind the developer tools. Keeping them out of the SwiftUI
/// views means the self-test suite can exercise the same code the UI runs.
enum DeveloperLogic {
    // MARK: Base64

    static func base64Encode(_ text: String, urlSafe: Bool) -> String {
        var encoded = Data(text.utf8).base64EncodedString()
        if urlSafe {
            encoded = encoded
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return encoded
    }

    /// Returns the decoded text plus an optional note. Binary payloads decode
    /// successfully but carry a note instead of text.
    static func base64Decode(_ input: String) -> (text: String, error: String?) {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while cleaned.count % 4 != 0 { cleaned.append("=") }
        guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters) else {
            return ("", "That doesn’t look like valid Base64.")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return ("Decoded \(data.count) bytes, but the result isn’t UTF-8 text.", nil)
        }
        return (text, nil)
    }

    static func decodeBase64URL(_ value: String) -> Data? {
        var cleaned = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while cleaned.count % 4 != 0 { cleaned.append("=") }
        return Data(base64Encoded: cleaned)
    }

    // MARK: JWT

    static func jwtParts(_ token: String) -> (header: String, payload: String, error: String?) {
        let segments = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard segments.count >= 2 else {
            return ("", "", token.isEmpty ? "" : "A JWT has three dot-separated parts. Paste the whole token.")
        }
        guard
            let headerData = decodeBase64URL(String(segments[0])),
            let payloadData = decodeBase64URL(String(segments[1]))
        else {
            return ("", "", "The header or payload isn’t valid Base64URL.")
        }
        let header = prettyJSON(headerData)
        let payload = prettyJSON(payloadData)
        if header.isEmpty || payload.isEmpty {
            return ("", "", "The token contains JSON that couldn’t be read.")
        }
        return (header, payload, nil)
    }

    static func jwtClaims(_ token: String) -> [(String, String)] {
        let segments = token.split(separator: ".")
        guard segments.count >= 2, let data = decodeBase64URL(String(segments[1])),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var rows: [(String, String)] = []
        for key in ["iss", "sub", "aud", "exp", "nbf", "iat", "jti"] {
            guard let value = object[key] else { continue }
            if ["exp", "nbf", "iat"].contains(key), let seconds = value as? Double {
                rows.append((key, "\(Fmt.shortDate(Date(timeIntervalSince1970: seconds))) · \(Int(seconds))"))
            } else {
                rows.append((key, String(describing: value)))
            }
        }
        return rows
    }

    static func prettyJSON(_ data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            JSONSerialization.isValidJSONObject(object),
            let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return "" }
        return String(decoding: pretty, as: UTF8.self)
    }

    // MARK: Diff

    enum DiffKind: Equatable {
        case same, added, removed
    }

    /// Longest-common-subsequence line diff. Capped so huge inputs don't lock
    /// the UI.
    static func diff(_ a: String, _ b: String) -> [(DiffKind, String)] {
        let leftLines = Array(a.components(separatedBy: "\n").prefix(700))
        let rightLines = Array(b.components(separatedBy: "\n").prefix(700))
        let n = leftLines.count, m = rightLines.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = leftLines[i] == rightLines[j]
                        ? table[i + 1][j + 1] + 1
                        : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var out: [(DiffKind, String)] = []
        var i = 0, j = 0
        while i < n && j < m {
            if leftLines[i] == rightLines[j] {
                out.append((.same, leftLines[i])); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                out.append((.removed, leftLines[i])); i += 1
            } else {
                out.append((.added, rightLines[j])); j += 1
            }
        }
        while i < n { out.append((.removed, leftLines[i])); i += 1 }
        while j < m { out.append((.added, rightLines[j])); j += 1 }
        return out
    }

    // MARK: Regex

    static func regexMatches(
        pattern: String,
        text: String,
        caseInsensitive: Bool,
        multiline: Bool
    ) -> [(text: String, range: NSRange)] {
        guard !pattern.isEmpty else { return [] }
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        if multiline { options.insert(.anchorsMatchLines) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).map { match in
            let matched = Range(match.range, in: text).map { String(text[$0]) } ?? ""
            return (matched, match.range)
        }
    }

    static func regexError(pattern: String, caseInsensitive: Bool) -> String? {
        guard !pattern.isEmpty else { return nil }
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        do {
            _ = try NSRegularExpression(pattern: pattern, options: options)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Links

    private static let trackingParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid",
        "ref", "ref_src", "ref_url", "source", "spm", "yclid", "_hsenc", "_hsmi"
    ]

    static func cleanLinks(_ input: String) -> String {
        input.components(separatedBy: .newlines).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  var components = URLComponents(string: trimmed),
                  components.scheme != nil
            else { return line }
            components.queryItems = components.queryItems?.filter { item in
                !trackingParameters.contains(item.name.lowercased())
                    && !item.name.lowercased().hasPrefix("utm_")
            }
            if components.queryItems?.isEmpty == true { components.queryItems = nil }
            return components.string ?? trimmed
        }
        .joined(separator: "\n")
    }

    static func removedLinkParameters(_ input: String) -> Int {
        guard let before = URLComponents(string: input.trimmingCharacters(in: .whitespaces)) else { return 0 }
        guard let after = URLComponents(string: cleanLinks(input).trimmingCharacters(in: .whitespaces)) else { return 0 }
        return max(0, (before.queryItems?.count ?? 0) - (after.queryItems?.count ?? 0))
    }

    // MARK: Lorem

    static let loremBank = [
        "A private toolkit should feel like part of the desk, not another tab.",
        "Nothing leaves the machine, so the work stays yours.",
        "Files land in a dated folder and originals are never touched.",
        "Small utilities add up: a rename here, a conversion there.",
        "The notch keeps the day close without stealing the screen.",
        "Results are new files, which makes every run reversible.",
        "No account, no sync, no dashboard to keep alive.",
        "Keyboard first, because the fastest path is the one you know.",
        "Long jobs show progress and can be stopped.",
        "Good tools explain what they did and where the output went."
    ]

    static func lorem(paragraphs: Int, sentences: Int, startClassic: Bool) -> String {
        let paragraphCount = max(1, paragraphs)
        let sentenceCount = max(1, sentences)
        var blocks: [String] = []
        for p in 0..<paragraphCount {
            var lines: [String] = []
            for s in 0..<sentenceCount {
                if p == 0 && s == 0 && startClassic {
                    lines.append("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore.")
                } else {
                    lines.append(loremBank[(p * sentenceCount + s) % loremBank.count])
                }
            }
            blocks.append(lines.joined(separator: " "))
        }
        return blocks.joined(separator: "\n\n")
    }

    // MARK: UUID

    static func uuid(upper: Bool, hyphens: Bool) -> String {
        var value = UUID().uuidString
        if !hyphens { value = value.replacingOccurrences(of: "-", with: "") }
        return upper ? value.uppercased() : value.lowercased()
    }
}
