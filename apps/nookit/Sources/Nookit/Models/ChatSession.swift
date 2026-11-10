import Foundation

/// A saved Nookit AI conversation. Sessions live in Application Support as a
/// single JSON file so switching chats is instant and survives relaunches.
struct ChatSession: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String? = nil,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title ?? ChatSession.makeTitle(from: messages)
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static let defaultTitle = "New chat"

    var isEmpty: Bool {
        messages.allSatisfy { $0.text.isEmpty && $0.attachments.isEmpty && $0.reasoning.isEmpty }
    }

    /// One-line hint shown under the title in the sidebar.
    var preview: String {
        guard let message = messages.last(where: { !$0.text.isEmpty }) else {
            return isEmpty ? "Empty conversation" : "Attachment"
        }
        let text = message.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Attachment" }
        return String(text.prefix(72))
    }

    var messageCount: Int {
        messages.filter { !$0.text.isEmpty || !$0.attachments.isEmpty }.count
    }

    /// Derives a compact, human-readable title from the first user turn.
    static func makeTitle(from messages: [ChatMessage]) -> String {
        if let message = messages.first(where: { $0.role == .user && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let cleaned = message.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned.count <= 46 ? cleaned : String(cleaned.prefix(45)).trimmingCharacters(in: .whitespaces) + "…"
            }
        }
        if let attachment = messages.first(where: { !$0.attachments.isEmpty })?.attachments.first {
            return attachment.filename
        }
        return defaultTitle
    }

    /// Copy with a refreshed timestamp. Used whenever a turn is persisted.
    func touched() -> ChatSession {
        var copy = self
        copy.updatedAt = Date()
        copy.title = ChatSession.makeTitle(from: messages)
        return copy
    }
}
