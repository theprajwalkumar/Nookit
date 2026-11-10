import SwiftUI
import AppKit
import Foundation

struct AppsRun: Identifiable, Codable, Hashable {
    let id: UUID
    let appRaw: String
    let title: String
    let output: String
    let createdAt: Date

    var app: GoogleApp? { GoogleApp(rawValue: appRaw) }
}

/// Drives the Apps hub: pick a Google app, describe the work, let Nookit AI
/// draft it, then copy, save, or hand it straight to the right Google surface.
@MainActor
final class AppsService: ObservableObject {
    static let shared = AppsService()

    @Published private(set) var selectedApp: GoogleApp = .docs
    @Published var brief: String = ""
    @Published var output: String = ""
    @Published var running = false
    @Published var error: String?
    @Published var note: String?
    @Published private(set) var lastRun: Date?
    @Published private(set) var history: [AppsRun] = []

    /// Set while a real Google Workspace request is in flight.
    @Published private(set) var creating = false
    /// The live document/event Nookit just created in the user's account.
    @Published private(set) var workspace: WorkspaceResult?
    /// True when the user tried to create something before connecting Google.
    @Published var needsGoogle = false

    private var task: Task<Void, Never>?
    private var drafts: [String: String] = [:]
    private let defaults = UserDefaults.standard
    private let historyURL = AppPaths.supportFile("apps-history.json")
    private let auth = GoogleAuthService.shared
    private let workspaceService = GoogleWorkspaceService.shared

    private enum Keys {
        static let drafts = "NookitAppDrafts"
        static let selected = "NookitAppsSelectedApp"
    }

    private init() {
        if let stored = defaults.string(forKey: Keys.selected).flatMap(GoogleApp.init(rawValue:)) {
            selectedApp = stored
        }
        if let saved = defaults.dictionary(forKey: Keys.drafts) as? [String: String] {
            drafts = saved
        }
        brief = drafts[selectedApp.rawValue] ?? selectedApp.starterPrompts.first ?? ""
        loadHistory()
    }

    // MARK: - Selection

    func select(_ app: GoogleApp) {
        guard app != selectedApp else { return }
        drafts[selectedApp.rawValue] = brief
        saveDrafts()

        if !running { output = "" }
        error = nil
        note = nil
        workspace = nil
        needsGoogle = false
        selectedApp = app
        defaults.set(app.rawValue, forKey: Keys.selected)
        brief = drafts[app.rawValue] ?? app.starterPrompts.first ?? ""
    }

    // MARK: - Google account

    var googleConnected: Bool { auth.isConnected }
    var googleEmail: String? { auth.accountEmail }
    var googleName: String? { auth.accountName }
    var googleConnecting: Bool { auth.connecting }
    var googleClientID: String { auth.clientID }
    var googleClientSecret: String { auth.clientSecret }

    func configureGoogle(clientID: String, clientSecret: String) {
        auth.saveConfiguration(clientID: clientID, clientSecret: clientSecret)
        needsGoogle = false
        error = nil
    }

    func connectGoogle() async {
        error = nil
        await auth.connect()
        if let message = auth.error {
            error = message
        } else if auth.isConnected {
            needsGoogle = false
            note = "Google connected as \(auth.accountEmail ?? "your account")."
        }
    }

    func disconnectGoogle() {
        auth.disconnect()
        workspace = nil
        needsGoogle = false
        note = "Google disconnected."
    }

    func useStarter(_ prompt: String) {
        brief = prompt
        error = nil
    }

    private func saveDrafts() {
        drafts[selectedApp.rawValue] = brief
        defaults.set(drafts, forKey: Keys.drafts)
    }

    // MARK: - Run

    func start() {
        guard !running else { return }
        let request = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            error = "Describe the work you want first."
            return
        }

        saveDrafts()
        let app = selectedApp

        running = true
        error = nil
        note = nil
        workspace = nil
        needsGoogle = false
        output = ""

        task = Task {
            do {
                let prompt = "Create this for \(app.fullName):\n\n\(request)"
                let result = try await AIChatService.shared.complete(prompt: prompt, system: app.systemPrompt)
                try Task.checkCancellation()
                output = result
                lastRun = Date()
                record(app: app, draft: result)
            } catch is CancellationError {
                note = "Stopped."
            } catch let urlError as URLError where urlError.code == .cancelled {
                note = "Stopped."
            } catch {
                self.error = error.localizedDescription
            }
            running = false
            task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        running = false
        note = "Stopped."
    }

    func clearOutput() {
        output = ""
        workspace = nil
        error = nil
        note = nil
        needsGoogle = false
    }

    // MARK: - Real Google actions

    /// Creates the draft in the user's Google account using the Workspace APIs.
    /// When Google is not connected the caller should show the connect sheet;
    /// `needsGoogle` is set so the UI can react without losing the draft.
    func createInGoogle() async {
        guard !creating else { return }
        let draft = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            error = "Draft something first."
            return
        }
        guard auth.isConnected else {
            needsGoogle = true
            error = "Connect your Google account to create this in \(selectedApp.fullName)."
            return
        }

        creating = true
        error = nil
        note = nil
        workspace = nil
        defer { creating = false }

        do {
            let result = try await workspaceService.perform(app: selectedApp, draft: draft)
            workspace = result
            note = result.detail
            lastRun = Date()
        } catch {
            self.error = error.localizedDescription
            if !auth.isConnected { needsGoogle = true }
        }
    }

    func openWorkspaceResult() {
        guard let workspace else { return }
        NSWorkspace.shared.open(workspace.url)
    }

    // MARK: - Fallback handoff

    /// The URL that turns the draft into a real Google action. Gmail and
    /// Calendar are prefilled; everything else opens a fresh document.
    func actionURL(for app: GoogleApp) -> URL? {
        let draft = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return app.createURL }

        switch app {
        case .gmail:
            let parts = GoogleLinkBuilder.emailParts(draft)
            return GoogleLinkBuilder.gmailURL(subject: parts.subject, body: parts.body)
        case .calendar:
            let parts = GoogleLinkBuilder.titleAndDetails(draft)
            return GoogleLinkBuilder.calendarURL(
                title: parts.title,
                details: parts.details,
                start: Self.suggestedStart()
            )
        default:
            return app.createURL
        }
    }

    /// Any draft can be copied before opening a Google surface, so `.new`
    /// documents can be filled with a single paste.
    @discardableResult
    func copyToPasteboard() -> Bool {
        let draft = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(draft, forType: .string)
        return true
    }

    func save(to url: URL) throws {
        let draft = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { throw ToolError.message("There is no draft to save yet.") }
        try draft.write(to: url, atomically: true, encoding: .utf8)
    }

    static func suggestedStart() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    // MARK: - History

    func restore(_ run: AppsRun) {
        guard !running, let app = run.app else { return }
        selectedApp = app
        defaults.set(app.rawValue, forKey: Keys.selected)
        output = run.output
        workspace = nil
        needsGoogle = false
        error = nil
        note = "Restored from \(run.createdAt.formatted(date: .abbreviated, time: .shortened))."
    }

    func deleteRun(_ id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    private func record(app: GoogleApp, draft: String) {
        let title = draft.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "\(app.title) draft"

        let run = AppsRun(
            id: UUID(),
            appRaw: app.rawValue,
            title: String(title.prefix(70)),
            output: draft,
            createdAt: Date()
        )
        history.insert(run, at: 0)
        if history.count > 12 { history = Array(history.prefix(12)) }
        saveHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([AppsRun].self, from: data) else { return }
        history = decoded
        lastRun = decoded.first?.createdAt
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }
}
