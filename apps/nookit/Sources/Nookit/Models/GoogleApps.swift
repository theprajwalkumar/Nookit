import SwiftUI
import UniformTypeIdentifiers

/// The Google Workspace apps Nookit can draft for. Deep links use Google's
/// `*.new` shortcuts, which open a fresh document in the signed-in browser.
enum GoogleApp: String, CaseIterable, Identifiable {
    case docs
    case sheets
    case slides
    case gmail
    case calendar
    case meet
    case drive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .docs: return "Docs"
        case .sheets: return "Sheets"
        case .slides: return "Slides"
        case .gmail: return "Gmail"
        case .calendar: return "Calendar"
        case .meet: return "Meet"
        case .drive: return "Drive"
        }
    }

    var fullName: String {
        switch self {
        case .docs: return "Google Docs"
        case .sheets: return "Google Sheets"
        case .slides: return "Google Slides"
        case .gmail: return "Gmail"
        case .calendar: return "Google Calendar"
        case .meet: return "Google Meet"
        case .drive: return "Google Drive"
        }
    }

    var symbol: String {
        switch self {
        case .docs: return "doc.text.fill"
        case .sheets: return "tablecells.fill"
        case .slides: return "rectangle.on.rectangle.angled"
        case .gmail: return "envelope.fill"
        case .calendar: return "calendar"
        case .meet: return "video.fill"
        case .drive: return "externaldrive.fill"
        }
    }

    var tint: Color {
        switch self {
        case .docs: return Color(hex: 0x4285F4)
        case .sheets: return Color(hex: 0x34A853)
        case .slides: return Color(hex: 0xF9AB00)
        case .gmail: return Color(hex: 0xEA4335)
        case .calendar: return Color(hex: 0x4285F4)
        case .meet: return Color(hex: 0x00AC47)
        case .drive: return Color(hex: 0xFBBC04)
        }
    }

    var blurb: String {
        switch self {
        case .docs: return "Briefs, proposals and polished copy."
        case .sheets: return "CSV tables, budgets and trackers."
        case .slides: return "Pitch outlines and deck structure."
        case .gmail: return "Subject and body, ready to send."
        case .calendar: return "Agendas that become invites."
        case .meet: return "A running order for the call."
        case .drive: return "Folder and naming conventions."
        }
    }

    var outputFormat: AppOutputFormat {
        switch self {
        case .sheets: return .csv
        case .gmail: return .email
        case .calendar, .meet: return .agenda
        case .slides: return .outline
        case .docs, .drive: return .prose
        }
    }

    var systemPrompt: String {
        let base = """
        You are Nookit, an expert assistant inside a Mac app. Produce work that can be pasted straight into \(fullName) without cleanup. No preamble, no apologies, no meta commentary. Use plain text and markdown only where it helps.
        """

        switch outputFormat {
        case .csv:
            return base + """

            Return only valid CSV. The first row must be column headers. Quote every field that contains a comma or quote. Do not wrap the CSV in markdown fences. Keep it to at most 40 rows unless the request needs more.
            """
        case .email:
            return base + """

            Return an email. The first line must be exactly `Subject: <subject>`, then one blank line, then the body. Keep the body friendly, specific and under 220 words. Sign off as the sender without inventing a full name.
            """
        case .agenda:
            return base + """

            Return a practical meeting agenda. Start with a title line, then `Duration: …`, then a short objective, then timed agenda bullets, then a prep checklist. Keep it tight and actionable.
            """
        case .outline:
            return base + """

            Return a slide outline. Use `Slide 1 — Title` style headings, then 2–4 short bullets per slide. Include speaker notes only when they add real value.
            """
        case .prose:
            return base + """

            Return clean, well-structured prose with short headings and scannable bullets where useful. Match a confident, human tone.
            """
        }
    }

    var createURL: URL? {
        switch self {
        case .docs: return URL(string: "https://docs.new")
        case .sheets: return URL(string: "https://sheets.new")
        case .slides: return URL(string: "https://slides.new")
        case .gmail: return URL(string: "https://mail.google.com/mail/u/0/#inbox?compose=new")
        case .calendar: return URL(string: "https://calendar.google.com/calendar/r/eventedit")
        case .meet: return URL(string: "https://meet.google.com/new")
        case .drive: return URL(string: "https://drive.google.com/drive/my-drive")
        }
    }

    var starterPrompts: [String] {
        switch self {
        case .docs:
            return [
                "Draft a one-page project brief for launching a neighbourhood coffee subscription.",
                "Turn these rough notes into a polished client proposal: …",
                "Write a concise how-to guide for setting up a home office on a budget."
            ]
        case .sheets:
            return [
                "Build a monthly budget table for a freelancer with categories, estimates and actuals.",
                "Create a product launch checklist with owner, status and due date columns.",
                "Make a simple CRM table for tracking 15 leads and next follow-up dates."
            ]
        case .slides:
            return [
                "Outline a six-slide pitch for an AI-powered study planner.",
                "Create a 10-slide onboarding deck for a new design hire.",
                "Turn this product update into a five-slide team presentation: …"
            ]
        case .gmail:
            return [
                "Write a friendly follow-up to a client who hasn't replied in a week.",
                "Draft a polite email declining a meeting while offering an async update.",
                "Write a short launch announcement for a new feature to existing customers."
            ]
        case .calendar:
            return [
                "Plan a 45-minute project kickoff with agenda and prep notes.",
                "Create a weekly review agenda for a small product team.",
                "Plan a 30-minute one-on-one focused on career growth."
            ]
        case .meet:
            return [
                "Create a 25-minute standup agenda with blockers and owners.",
                "Plan a remote design critique that keeps feedback specific.",
                "Write a running order for a 20-minute customer demo."
            ]
        case .drive:
            return [
                "Draft a file naming and folder structure guide for a small design team.",
                "Create a shared-drive cleanup plan with owners and deadlines.",
                "Write a simple handover checklist for project files."
            ]
        }
    }

    var fileExtension: String {
        switch outputFormat {
        case .csv: return "csv"
        case .email, .agenda: return "txt"
        case .outline, .prose: return "md"
        }
    }

    var contentType: UTType {
        switch outputFormat {
        case .csv: return .commaSeparatedText
        case .email, .agenda: return .plainText
        case .outline, .prose: return .plainText
        }
    }

    var openLabel: String {
        switch self {
        case .docs: return "Create in Docs"
        case .sheets: return "Create in Sheets"
        case .slides: return "Create in Slides"
        case .gmail: return "Save Gmail draft"
        case .calendar: return "Add to Calendar"
        case .meet: return "Create Meet event"
        case .drive: return "Create in Drive"
        }
    }

    /// Copy shown before the user has connected Google.
    var connectLabel: String { "Connect Google" }

    var fallbackLabel: String {
        switch self {
        case .gmail: return "Open Gmail"
        case .calendar: return "Open Calendar"
        case .meet: return "Open Meet"
        default: return "Open \(title)"
        }
    }

    var workspaceNoun: String {
        switch self {
        case .docs, .drive: return "document"
        case .sheets: return "spreadsheet"
        case .slides: return "presentation"
        case .gmail: return "draft"
        case .calendar, .meet: return "calendar event"
        }
    }
}

enum AppOutputFormat {
    case prose
    case csv
    case email
    case agenda
    case outline
}

// MARK: - Link building

enum GoogleLinkBuilder {
    /// Parses `Subject: …` plus body from a generated email draft.
    static func emailParts(_ draft: String) -> (subject: String, body: String) {
        let lines = draft.components(separatedBy: .newlines)
        guard let first = lines.first,
              first.lowercased().hasPrefix("subject:") else {
            let subject = draft.components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Draft from Nookit"
            return (String(subject.prefix(120)), draft)
        }

        let subject = String(first.dropFirst("subject:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        var body = lines.dropFirst().joined(separator: "\n")
        while body.hasPrefix("\n") { body.removeFirst() }
        return (subject.isEmpty ? "Draft from Nookit" : subject, body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Extracts a title and details from an agenda or outline draft.
    static func titleAndDetails(_ draft: String) -> (title: String, details: String) {
        let lines = draft.components(separatedBy: .newlines)
        let title = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Nookit draft"
        return (String(title.prefix(120)), draft)
    }

    static func gmailURL(subject: String, body: String) -> URL? {
        var components = URLComponents(string: "https://mail.google.com/mail/")
        components?.queryItems = [
            URLQueryItem(name: "view", value: "cm"),
            URLQueryItem(name: "fs", value: "1"),
            URLQueryItem(name: "su", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components?.url
    }

    static func calendarURL(title: String, details: String, start: Date, minutes: Int = 45) -> URL? {
        var components = URLComponents(string: "https://calendar.google.com/calendar/render")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        let end = start.addingTimeInterval(TimeInterval(max(15, minutes) * 60))
        components?.queryItems = [
            URLQueryItem(name: "action", value: "TEMPLATE"),
            URLQueryItem(name: "text", value: title),
            URLQueryItem(name: "details", value: details),
            URLQueryItem(name: "dates", value: "\(formatter.string(from: start))/\(formatter.string(from: end))")
        ]
        return components?.url
    }
}
