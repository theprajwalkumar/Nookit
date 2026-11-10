import Foundation

// MARK: - Result

struct WorkspaceResult {
    let app: GoogleApp
    let url: URL
    let title: String
    let detail: String?
}

// MARK: - CSV

enum GoogleCSV {
    /// Parses RFC 4180-ish CSV, tolerating markdown fences and a trailing newline.
    static func parse(_ text: String) -> [[String]] {
        var source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.hasPrefix("```") {
            if let firstNewline = source.firstIndex(of: "\n") {
                source = String(source[source.index(after: firstNewline)...])
            }
            if let fence = source.range(of: "```", options: .backwards) {
                source = String(source[..<fence.lowerBound])
            }
        }

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]

            if inQuotes {
                if character == "\"" {
                    let next = source.index(after: index)
                    if next < source.endIndex, source[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    break
                default:
                    field.append(character)
                }
            }

            index = source.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        while let last = rows.last, last.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            rows.removeLast()
        }
        return rows
    }
}

// MARK: - Slide outline

enum GoogleSlidesOutline {
    struct Slide {
        let title: String
        let body: String
    }

    /// Turns a generated outline into slide title/body pairs. Recognises
    /// markdown headings and `Slide 1 — Title` lines, then falls back to
    /// paragraph chunks so even a plain draft becomes a usable deck.
    static func parse(_ draft: String) -> [Slide] {
        let lines = draft.components(separatedBy: .newlines)
        var slides: [Slide] = []
        var currentTitle: String?
        var body: [String] = []

        func flush() {
            guard let title = currentTitle else { return }
            let text = body
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            slides.append(Slide(title: title, body: text))
            currentTitle = nil
            body = []
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if let title = headingTitle(line) {
                flush()
                currentTitle = title
            } else if currentTitle == nil {
                currentTitle = String(line.replacingOccurrences(of: "#", with: "").prefix(120))
            } else {
                body.append(stripBullet(line))
            }
        }
        flush()

        if slides.isEmpty {
            let paragraphs = draft
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for paragraph in paragraphs.prefix(20) {
                let title = paragraph.components(separatedBy: .newlines).first ?? paragraph
                slides.append(Slide(
                    title: String(title.prefix(120)),
                    body: String(paragraph.dropFirst(title.count).trimmingCharacters(in: .whitespacesAndNewlines).prefix(1500))
                ))
            }
        }

        if slides.isEmpty {
            slides = [Slide(title: "Nookit draft", body: String(draft.prefix(1500)))]
        }
        return Array(slides.prefix(20))
    }

    private static func headingTitle(_ line: String) -> String? {
        if line.hasPrefix("#") {
            let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : String(title.prefix(120))
        }

        let lowered = line.lowercased()
        if lowered.hasPrefix("slide ") {
            // Slide 1 — Title / Slide 1 - Title / Slide 1: Title
            if let separator = line.firstIndex(where: { $0 == "—" || $0 == "-" || $0 == ":" }) {
                let candidate = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty { return String(candidate.prefix(120)) }
            }
        }
        return nil
    }

    private static func stripBullet(_ line: String) -> String {
        var value = line
        for prefix in ["- ", "* ", "• ", "– "] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
            break
        }
        if let dot = value.firstIndex(of: "."),
           value[..<dot].allSatisfy({ $0.isNumber }),
           value.distance(from: value.startIndex, to: dot) <= 2 {
            value = String(value[value.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        }
        return value
    }
}

// MARK: - Workspace API

/// Performs real Google Workspace actions with the OAuth token from
/// `GoogleAuthService`. Every method returns the live document/event URL so the
/// UI can open the thing that was actually created.
@MainActor
final class GoogleWorkspaceService {
    static let shared = GoogleWorkspaceService()

    private let auth = GoogleAuthService.shared
    private let baseDocs = "https://docs.googleapis.com/v1"
    private let baseSheets = "https://sheets.googleapis.com/v4"
    private let baseSlides = "https://slides.googleapis.com/v1"
    private let baseGmail = "https://gmail.googleapis.com/gmail/v1"
    private let baseCalendar = "https://www.googleapis.com/calendar/v3"
    private let baseDrive = "https://www.googleapis.com/drive/v3"

    private init() {}

    // MARK: Entry point

    func perform(app: GoogleApp, draft: String) async throws -> WorkspaceResult {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ToolError.message("Draft something first.") }

        let parsed = GoogleLinkBuilder.titleAndDetails(text)
        let title = parsed.title.isEmpty ? "Nookit \(app.title)" : parsed.title

        switch app {
        case .docs:
            let url = try await createDocument(title: title, text: text)
            return WorkspaceResult(app: app, url: url, title: title, detail: "Document created with your draft")

        case .sheets:
            let rows = GoogleCSV.parse(text)
            guard !rows.isEmpty else { throw ToolError.message("The draft did not contain any table rows.") }
            let url = try await createSpreadsheet(title: title, rows: rows)
            return WorkspaceResult(app: app, url: url, title: title, detail: "\(rows.count) rows written to a new sheet")

        case .slides:
            let outline = GoogleSlidesOutline.parse(text)
            let url = try await createPresentation(title: title, slides: outline)
            return WorkspaceResult(app: app, url: url, title: title, detail: "\(outline.count) slides created")

        case .gmail:
            let mail = GoogleLinkBuilder.emailParts(text)
            let url = try await createGmailDraft(subject: mail.subject, body: mail.body)
            return WorkspaceResult(app: app, url: url, title: mail.subject, detail: "Draft saved in Gmail")

        case .calendar:
            let start = AppsService.suggestedStart()
            let url = try await createCalendarEvent(
                title: title,
                details: text,
                start: start,
                minutes: 45,
                withMeet: false
            )
            return WorkspaceResult(app: app, url: url, title: title, detail: "Event added to your primary calendar")

        case .meet:
            let start = AppsService.suggestedStart()
            let result = try await createCalendarEvent(
                title: title,
                details: text,
                start: start,
                minutes: 45,
                withMeet: true
            )
            return WorkspaceResult(app: app, url: result, title: title, detail: "Calendar event created with a Meet link")

        case .drive:
            let folder = try await createFolder(name: title)
            let doc = try await createDocument(title: title, text: text)
            let fileID = Self.documentID(from: doc)
            if let fileID {
                try? await moveFile(fileID: fileID, into: folder.id)
            }
            return WorkspaceResult(
                app: app,
                url: doc,
                title: title,
                detail: folder.id == nil ? "Document created in Drive" : "Document created in a new Drive folder"
            )
        }
    }

    // MARK: Docs

    func createDocument(title: String, text: String) async throws -> URL {
        let created = try await postJSON(
            url: "\(baseDocs)/documents",
            body: ["title": title]
        )
        guard let id = created["documentId"] as? String else {
            throw ToolError.message("Google Docs did not return a document ID.")
        }

        let body: [String: Any] = [
            "requests": [
                [
                    "insertText": [
                        "location": ["index": 1],
                        "text": text
                    ]
                ]
            ]
        ]
        _ = try await postJSON(url: "\(baseDocs)/documents/\(id):batchUpdate", body: body)

        guard let url = URL(string: "https://docs.google.com/document/d/\(id)/edit") else {
            throw ToolError.message("The new document URL could not be built.")
        }
        return url
    }

    // MARK: Sheets

    func createSpreadsheet(title: String, rows: [[String]]) async throws -> URL {
        let created = try await postJSON(
            url: "\(baseSheets)/spreadsheets",
            body: ["properties": ["title": title]]
        )
        guard let id = created["spreadsheetId"] as? String else {
            throw ToolError.message("Google Sheets did not return a spreadsheet ID.")
        }

        var sheetName = "Sheet1"
        if let sheets = created["sheets"] as? [[String: Any]],
           let properties = sheets.first?["properties"] as? [String: Any],
           let name = properties["title"] as? String,
           !name.isEmpty {
            sheetName = name
        }

        let range = "\(sheetName)!A1"
        guard var components = URLComponents(string: "\(baseSheets)/spreadsheets/\(id)/values/\(range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range)") else {
            throw ToolError.message("The sheet range could not be built.")
        }
        components.queryItems = [URLQueryItem(name: "valueInputOption", value: "RAW")]

        guard let url = components.url else {
            throw ToolError.message("The sheet range could not be built.")
        }
        _ = try await requestJSON(
            url: url,
            method: "PUT",
            body: [
                "majorDimension": "ROWS",
                "values": rows
            ]
        )

        guard let result = URL(string: "https://docs.google.com/spreadsheets/d/\(id)/edit") else {
            throw ToolError.message("The new spreadsheet URL could not be built.")
        }
        return result
    }

    // MARK: Slides

    func createPresentation(title: String, slides: [GoogleSlidesOutline.Slide]) async throws -> URL {
        let created = try await postJSON(
            url: "\(baseSlides)/presentations",
            body: ["title": title]
        )
        guard let id = created["presentationId"] as? String else {
            throw ToolError.message("Google Slides did not return a presentation ID.")
        }

        let existingSlides = (created["slides"] as? [[String: Any]] ?? []).compactMap { $0["objectId"] as? String }

        var firstBatch: [[String: Any]] = existingSlides.map { ["deleteObject": ["objectId": $0]] }
        for (index, _) in slides.enumerated() {
            firstBatch.append([
                "createSlide": [
                    "objectId": "nookit_slide_\(index)",
                    "slideLayoutReference": ["predefinedLayout": "TITLE_AND_BODY"],
                    "placeholderIdMappings": [
                        [
                            "layoutPlaceholder": ["type": "TITLE"],
                            "objectId": "nookit_title_\(index)"
                        ],
                        [
                            "layoutPlaceholder": ["type": "BODY"],
                            "objectId": "nookit_body_\(index)"
                        ]
                    ]
                ]
            ])
        }

        if !firstBatch.isEmpty {
            _ = try await postJSON(
                url: "\(baseSlides)/presentations/\(id):batchUpdate",
                body: ["requests": firstBatch]
            )
        }

        var secondBatch: [[String: Any]] = []
        for (index, slide) in slides.enumerated() {
            secondBatch.append([
                "insertText": [
                    "objectId": "nookit_title_\(index)",
                    "text": slide.title,
                    "insertionIndex": 0
                ]
            ])
            if !slide.body.isEmpty {
                secondBatch.append([
                    "insertText": [
                        "objectId": "nookit_body_\(index)",
                        "text": slide.body,
                        "insertionIndex": 0
                    ]
                ])
            }
        }

        if !secondBatch.isEmpty {
            _ = try await postJSON(
                url: "\(baseSlides)/presentations/\(id):batchUpdate",
                body: ["requests": secondBatch]
            )
        }

        guard let url = URL(string: "https://docs.google.com/presentation/d/\(id)/edit") else {
            throw ToolError.message("The new presentation URL could not be built.")
        }
        return url
    }

    // MARK: Gmail

    func createGmailDraft(subject: String, body: String) async throws -> URL {
        let raw = Self.emailRaw(subject: subject, body: body)
        _ = try await postJSON(
            url: "\(baseGmail)/users/me/drafts",
            body: ["message": ["raw": raw]]
        )
        guard let url = URL(string: "https://mail.google.com/mail/u/0/#drafts") else {
            throw ToolError.message("The Gmail URL could not be built.")
        }
        return url
    }

    static func emailRaw(subject: String, body: String) -> String {
        let message = """
        MIME-Version: 1.0\r
        Content-Type: text/plain; charset="UTF-8"\r
        Content-Transfer-Encoding: 8bit\r
        Subject: \(subject)\r
        \r
        \(body)
        """
        return Data(message.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: Calendar + Meet

    func createCalendarEvent(
        title: String,
        details: String,
        start: Date,
        minutes: Int,
        withMeet: Bool
    ) async throws -> URL {
        let end = start.addingTimeInterval(TimeInterval(max(15, minutes) * 60))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var invitation: [String: Any] = [
            "summary": title,
            "description": details,
            "start": [
                "dateTime": formatter.string(from: start),
                "timeZone": TimeZone.current.identifier
            ],
            "end": [
                "dateTime": formatter.string(from: end),
                "timeZone": TimeZone.current.identifier
            ]
        ]

        if withMeet {
            invitation["conferenceData"] = [
                "createRequest": [
                    "requestId": "nookit-\(UUID().uuidString)",
                    "conferenceSolutionKey": ["type": "hangoutsMeet"]
                ]
            ]
        }

        var components = URLComponents(string: "\(baseCalendar)/calendars/primary/events")
        components?.queryItems = [
            URLQueryItem(name: "conferenceDataVersion", value: withMeet ? "1" : "0"),
            URLQueryItem(name: "sendUpdates", value: "none")
        ]
        guard let url = components?.url else {
            throw ToolError.message("The calendar endpoint could not be built.")
        }

        let created = try await postJSON(url: url.absoluteString, body: invitation)

        if withMeet, let meet = created["hangoutLink"] as? String, let meetURL = URL(string: meet) {
            return meetURL
        }
        if let link = created["htmlLink"] as? String, let eventURL = URL(string: link) {
            return eventURL
        }
        guard let fallback = URL(string: "https://calendar.google.com/calendar/r") else {
            throw ToolError.message("The calendar URL could not be built.")
        }
        return fallback
    }

    // MARK: Drive

    func createFolder(name: String) async throws -> (id: String?, url: URL?) {
        let created = try await postJSON(
            url: "\(baseDrive)/files",
            body: [
                "name": name,
                "mimeType": "application/vnd.google-apps.folder"
            ]
        )
        let id = created["id"] as? String
        let url = id.flatMap { URL(string: "https://drive.google.com/drive/folders/\($0)") }
        return (id, url)
    }

    func moveFile(fileID: String, into folderID: String?) async throws {
        guard let folderID else { return }
        var components = URLComponents(string: "\(baseDrive)/files/\(fileID)")
        components?.queryItems = [
            URLQueryItem(name: "addParents", value: folderID),
            URLQueryItem(name: "removeParents", value: "root")
        ]
        guard let url = components?.url else { return }
        _ = try await requestJSON(url: url, method: "PATCH", body: [:])
    }

    static func documentID(from url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "d"), index + 1 < parts.count else { return nil }
        return parts[index + 1]
    }

    // MARK: HTTP

    private func postJSON(url: String, body: [String: Any]) async throws -> [String: Any] {
        guard let endpoint = URL(string: url) else {
            throw ToolError.message("Google API endpoint is invalid.")
        }
        return try await requestJSON(url: endpoint, method: "POST", body: body)
    }

    private func requestJSON(url: URL, method: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await auth.authorizedRequest(request)

        guard (200..<300).contains(http.statusCode) else {
            throw ToolError.message(Self.errorMessage(data: data, status: http.statusCode))
        }

        guard !data.isEmpty else { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    static func errorMessage(data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                if let message = error["message"] as? String, !message.isEmpty {
                    return message
                }
                if let status = error["status"] as? String {
                    return "Google API answered \(status)."
                }
            }
            if let message = json["error_description"] as? String, !message.isEmpty {
                return message
            }
        }
        switch status {
        case 401: return "Google access expired. Reconnect your account."
        case 403: return "Google denied this action. Check that the required API is enabled and the account has access."
        case 404: return "Google could not find that resource."
        case 429: return "Google is rate limiting Nookit. Try again in a moment."
        default: return "Google API answered HTTP \(status)."
        }
    }
}
