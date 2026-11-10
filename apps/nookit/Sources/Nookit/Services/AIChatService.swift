import SwiftUI
import UniformTypeIdentifiers
import PDFKit
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AttachedFile: Identifiable, Hashable, Codable {
    let id: UUID
    let data: Data
    let filename: String
    let mimeType: String
    let isImage: Bool

    init(data: Data, filename: String) {
        self.id = UUID()
        self.data = data
        self.filename = filename
        let ext = (filename as NSString).pathExtension.lowercased()
        let imageExts = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "avif"]
        self.isImage = imageExts.contains(ext)

        switch ext {
        case "png": self.mimeType = "image/png"
        case "jpg", "jpeg": self.mimeType = "image/jpeg"
        case "gif": self.mimeType = "image/gif"
        case "webp": self.mimeType = "image/webp"
        case "heic", "heif": self.mimeType = "image/heic"
        case "tiff", "tif": self.mimeType = "image/tiff"
        case "bmp": self.mimeType = "image/bmp"
        case "pdf": self.mimeType = "application/pdf"
        case "txt", "md", "swift", "js", "ts", "py", "json", "yaml", "yml", "xml", "html", "css", "sql", "sh", "rb", "go", "rs": self.mimeType = "text/plain"
        default: self.mimeType = "application/octet-stream"
        }
    }

    var nsImage: NSImage? {
        guard isImage else { return nil }
        return NSImage(data: data)
    }
}

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    var role: Role
    var text: String
    var attachments: [AttachedFile] = []
    /// Internal model reasoning. Kept separate from `text` so the bubble only
    /// ever shows the final answer, while the UI can still indicate progress.
    var reasoning: String = ""

    init(id: UUID = UUID(), role: Role, text: String, attachments: [AttachedFile] = [], reasoning: String = "") {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.reasoning = reasoning
    }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case automatic
    case apple
    case nookitAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .apple: return "Apple Intelligence"
        case .nookitAI: return "Nookit AI"
        }
    }
}

/// The Nookit assistant. It can use Apple Intelligence when the Mac supports
/// it, or NVIDIA models via Nookit AI with your API key.
@MainActor
final class AIChatService: ObservableObject {
    static let shared = AIChatService()

    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var busy = false
    @Published var error: String?
    @Published var availabilityNote: String?
    @Published var checking = false

    // Saved conversations. `currentSessionID` is nil until the first message of
    // a fresh chat is sent, so empty sessions never clutter the sidebar.
    @Published private(set) var sessions: [ChatSession] = []
    @Published private(set) var currentSessionID: UUID?

    private let sessionsURL = AppPaths.supportFile("chat-history.json")
    private let maxSessions = 40

    // Cancellation support
    private var currentTask: Task<Void, Never>?
    private var isCancelled = false

    // Persisted provider settings. Changing the provider re-checks what is
    // available, so the notch reflects a model you just pulled.
    @Published var provider: AIProvider {
        didSet {
            defaults.set(provider.rawValue, forKey: Keys.provider)
            Task { await refresh() }
        }
    }
    @Published var nookitAIURL: String {
        didSet { defaults.set(nookitAIURL, forKey: Keys.nookitAIURL) }
    }
    @Published var nookitAIModel: String {
        didSet { defaults.set(nookitAIModel, forKey: Keys.nookitAIModel) }
    }
    @Published var nookitAIKey: String {
        didSet { defaults.set(nookitAIKey, forKey: Keys.nookitAIKey) }
    }

    @Published private(set) var nookitAIModels: [String] = []
    @Published private(set) var nookitAIVisionModels: [String] = []

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let provider = "NookitAIProvider"
        static let nookitAIURL = "NookitAINookitAIURL"
        static let nookitAIModel = "NookitAINookitAIModel"
        static let nookitAIKey = "NookitAINookitAIKey"
    }

    private init() {
        let storedProvider = defaults.string(forKey: Keys.provider).flatMap(AIProvider.init(rawValue:))
        provider = storedProvider ?? .automatic
        nookitAIURL = defaults.string(forKey: Keys.nookitAIURL) ?? "https://integrate.api.nvidia.com/v1"
        
        // Migrate from old text-only default to vision-capable default
        let storedModel = defaults.string(forKey: Keys.nookitAIModel) ?? ""
        let oldTextOnlyModels = [
            "nvidia/nemotron-3-ultra",
            "nvidia/nemotron-3.5-lightning-30b-a3b",
            "nvidia/nemotron-3.5-bolt-e4b"
        ]
        let newDefault = "nvidia/nemotron-3.5-super-vl-120b-a12b"
        let modelToUse = oldTextOnlyModels.contains(storedModel) ? newDefault : (storedModel.isEmpty ? newDefault : storedModel)
        self.nookitAIModel = modelToUse
        defaults.set(modelToUse, forKey: Keys.nookitAIModel)
        
        nookitAIKey = defaults.string(forKey: Keys.nookitAIKey) ?? ""

        loadHistory()
    }

    // MARK: - History

    var currentSession: ChatSession? {
        guard let currentSessionID else { return nil }
        return sessions.first { $0.id == currentSessionID }
    }

    /// Starts a blank conversation. The previous one is saved first.
    func newChat() {
        if busy { stop() }
        persistCurrentSession()
        currentSessionID = nil
        messages = []
        error = nil
    }

    func openSession(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        if busy { stop() }
        if currentSessionID != id {
            persistCurrentSession()
        }
        currentSessionID = session.id
        messages = session.messages
        error = nil
    }

    func deleteSession(_ id: UUID) {
        if currentSessionID == id {
            if busy { stop() }
            currentSessionID = nil
            messages = []
        }
        sessions.removeAll { $0.id == id }
        saveHistory()
    }

    func clearAllSessions() {
        if busy { stop() }
        sessions = []
        currentSessionID = nil
        messages = []
        error = nil
        saveHistory()
    }

    /// Flushes the active transcript. Called when a turn ends and on quit.
    func persistNow() {
        persistCurrentSession()
    }

    private func ensureSession(for transcript: [ChatMessage]) {
        if let id = currentSessionID, let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].messages = transcript
            sessions[index].title = ChatSession.makeTitle(from: transcript)
            sessions[index].updatedAt = Date()
        } else {
            let session = ChatSession(messages: transcript).touched()
            currentSessionID = session.id
            sessions.insert(session, at: 0)
        }
        sortSessions()
    }

    private func persistCurrentSession() {
        guard let id = currentSessionID,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }

        sessions[index].messages = messages
        sessions[index].title = ChatSession.makeTitle(from: messages)
        sessions[index].updatedAt = Date()

        if sessions[index].isEmpty {
            sessions.remove(at: index)
            currentSessionID = nil
            saveHistory()
            return
        }

        sortSessions()
        saveHistory()
    }

    private func sortSessions() {
        sessions.sort { $0.updatedAt > $1.updatedAt }
        if sessions.count > maxSessions {
            sessions = Array(sessions.prefix(maxSessions))
        }
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: sessionsURL, options: .atomic)
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: sessionsURL),
              let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) else { return }

        sessions = decoded.sorted { $0.updatedAt > $1.updatedAt }
        if let latest = sessions.first(where: { !$0.isEmpty }) {
            currentSessionID = latest.id
            messages = latest.messages
        }
    }

    // MARK: - Availability

    enum Route: Equatable {
        case apple
        case nookitAI(model: String)
    }

    var appleSupported: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    /// The route the next message will take, or nil when nothing is ready.
    var route: Route? {
        switch provider {
        case .apple:
            return appleSupported ? .apple : nil
        case .nookitAI:
            return nookitAIModel.isEmpty || nookitAIKey.isEmpty ? nil : .nookitAI(model: nookitAIModel)
        case .automatic:
            if appleSupported { return .apple }
            if !nookitAIModel.isEmpty && !nookitAIKey.isEmpty { return .nookitAI(model: nookitAIModel) }
            return nil
        }
    }

    var isSupported: Bool { route != nil }

    var subtitle: String? {
        switch provider {
        case .apple:
            return appleSupported ? "Apple Intelligence" : "Apple Intelligence (unavailable)"
        case .nookitAI:
            return nookitAIModel.isEmpty ? "Nookit AI · No model selected" : "Nookit AI"
        case .automatic:
            if appleSupported { return "Apple Intelligence" }
            return nookitAIModel.isEmpty ? "Nookit AI · No model selected" : "Nookit AI"
        }
    }

    var unavailableReason: String {
        if let availabilityNote, !availabilityNote.isEmpty { return availabilityNote }

        switch provider {
        case .apple:
            #if canImport(FoundationModels)
            return "Needs macOS 26 with Apple Intelligence. Choose Nookit AI in Settings → AI Configuration to use NVIDIA models with your API key."
            #else
            return "Apple Intelligence isn't available to this build. Choose Nookit AI in Settings → AI Configuration to use NVIDIA models with your API key."
            #endif
        case .nookitAI:
            return "Enter your NVIDIA API key in Settings → AI Configuration to use Nookit AI with Nemotron and other NVIDIA models. Get a key at build.nvidia.com."
        case .automatic:
            if appleSupported {
                return "No model is ready. Configure Nookit AI in Settings → AI Configuration."
            }
            return "No model is ready yet. Enter your NVIDIA API key in Settings → AI Configuration to use Nemotron and other NVIDIA models."
        }
    }

    // MARK: - Discovery

    func refresh() async {
        guard !checking else { return }
        checking = true
        availabilityNote = nil
        defer { checking = false }

        if provider == .nookitAI || provider == .automatic {
            let (models, visionModels) = await fetchNookitAIModels()
            nookitAIModels = models
            nookitAIVisionModels = visionModels
            if provider == .nookitAI {
                if nookitAIModels.isEmpty {
                    availabilityNote = "Couldn't fetch models from \(nookitAIURL). Check your API key at build.nvidia.com."
                } else if nookitAIModel.isEmpty || !nookitAIModels.contains(nookitAIModel) {
                    // Prefer a vision model as default
                    nookitAIModel = nookitAIVisionModels.first ?? nookitAIModels[0]
                }
            }
        }

        if provider == .automatic, appleSupported {
            availabilityNote = nil
        }
    }

    private func fetchNookitAIModels() async -> (models: [String], visionModels: [String]) {
        guard let base = Self.baseURL(nookitAIURL) else { return ([], []) }
        var request = URLRequest(url: base.appendingPathComponent("models"))
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if !nookitAIKey.isEmpty {
            request.setValue("Bearer \(nookitAIKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return ([], []) }
            struct Response: Decodable {
                struct Model: Decodable { let id: String }
                let data: [Model]
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let allModels = decoded.data.map(\.id).sorted()
            let visionModels = allModels.filter { Self.looksLikeVisionModel($0) }
            return (allModels, visionModels)
        } catch {
            return ([], [])
        }
    }

    // MARK: - Chat

    func send() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !busy else { return }

        if route == nil {
            await refresh()
        }
        guard let route = self.route else {
            error = unavailableReason
            return
        }

        input = ""
        error = nil
        isCancelled = false
        
        let userMessage = ChatMessage(role: .user, text: prompt)
        messages.append(userMessage)
        ensureSession(for: messages)
        busy = true
        
        let history = Self.wireMessages(from: messages)
        let assistant = ChatMessage(role: .assistant, text: "")
        messages.append(assistant)

        currentTask = Task {
            do {
                switch route {
                case .apple:
                    try await sendApple(prompt: prompt, assistantID: assistant.id)
                case .nookitAI(let model):
                    try await streamNookitAI(model: model, messages: history, assistantID: assistant.id)
                }
            } catch is CancellationError {
                // Clean cancellation - just stop
            } catch {
                if let index = messages.firstIndex(where: { $0.id == assistant.id }), messages[index].text.isEmpty {
                    messages.remove(at: index)
                }
                self.error = friendly(error)
            }
            persistCurrentSession()
            busy = false
        }
    }

    func sendWithAttachments(_ prompt: String, files: [AttachedFile]) async {
        guard (!prompt.isEmpty || !files.isEmpty), !busy else { return }

        // Make sure model discovery has run. Without this, a message sent right
        // after launch would not know which models support images.
        if nookitAIModels.isEmpty || nookitAIVisionModels.isEmpty {
            await refresh()
        }

        // Check if any attached files are images
        let hasImages = files.contains { $0.isImage }

        // Pick a vision-capable model whenever an image is attached.
        var modelToUse = nookitAIModel
        if hasImages {
            if !nookitAIVisionModels.contains(modelToUse) {
                if let visionModel = nookitAIVisionModels.first
                    ?? Self.fallbackVisionModel(for: nookitAIModel, available: nookitAIModels) {
                    modelToUse = visionModel
                    nookitAIModel = visionModel
                }
            }
            guard nookitAIVisionModels.contains(modelToUse)
                || Self.looksLikeVisionModel(modelToUse) else {
                error = "No vision-capable model is available on this NVIDIA account. Open AI Configuration and pick a model such as Nemotron Super VL, Llama 3.2 Vision, or Gemma 3."
                return
            }
        }

        guard !modelToUse.isEmpty, !nookitAIKey.isEmpty else {
            error = unavailableReason
            return
        }

        // A scanned PDF has no text layer. Tell the user instead of sending an
        // empty attachment and waiting for a reply that can never come.
        if files.contains(where: { $0.mimeType == "application/pdf" && Self.extractTextFromFile($0) == nil })
            && !hasImages {
            error = "That PDF has no extractable text (it looks scanned). Attach a screenshot or image of the pages instead."
            return
        }

        error = nil
        isCancelled = false
        
        let userMessage = ChatMessage(role: .user, text: prompt, attachments: files)
        messages.append(userMessage)
        ensureSession(for: messages)
        busy = true
        
        let history = Self.wireMessages(from: messages)
        let assistant = ChatMessage(role: .assistant, text: "")
        messages.append(assistant)

        currentTask = Task {
            do {
                try await streamNookitAI(model: modelToUse, messages: history, assistantID: assistant.id)
            } catch is CancellationError {
                // Clean cancellation - just stop
            } catch {
                if let index = messages.firstIndex(where: { $0.id == assistant.id }), messages[index].text.isEmpty {
                    messages.remove(at: index)
                }
                self.error = friendly(error)
            }
            persistCurrentSession()
            busy = false
        }
    }

    func stop() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil
        // Drop a completely empty assistant bubble so stopping before the first
        // token leaves no blank block in the transcript.
        if let last = messages.last, last.role == .assistant, last.text.isEmpty, last.reasoning.isEmpty {
            messages.removeLast()
        }
        persistCurrentSession()
        busy = false
    }

    func clear() {
        newChat()
    }

    // MARK: - One-shot completion

    /// Runs a single prompt without touching the visible transcript. Used by
    /// agentic workflows in the Apps hub to draft documents, emails and plans.
    func complete(prompt: String, system: String) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ToolError.message("There is nothing to generate yet.") }

        if route == nil { await refresh() }
        guard let route = self.route else { throw ToolError.message(unavailableReason) }

        switch route {
        case .apple:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let languageSession = LanguageModelSession(instructions: system)
                let response = try await languageSession.respond(to: trimmed)
                return response.content
            }
            #endif
            throw ToolError.message(unavailableReason)
        case .nookitAI(let model):
            return try await completeNookitAI(model: model, prompt: trimmed, system: system)
        }
    }

    private func completeNookitAI(model: String, prompt: String, system: String) async throws -> String {
        guard let base = Self.baseURL(nookitAIURL) else {
            throw ToolError.message("The NVIDIA API address is invalid.")
        }
        guard !nookitAIKey.isEmpty else { throw ToolError.message(unavailableReason) }

        var request = URLRequest(url: base.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(nookitAIKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 2048,
            "temperature": 0.6,
            "top_p": 0.95
        ]
        if model.lowercased().contains("nemotron") {
            body["chat_template_kwargs"] = ["enable_thinking": false]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ToolError.message("NVIDIA API returned no HTTP response.")
        }

        let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if http.statusCode == 404,
           let fallback = Self.fallbackVisionModel(for: model, available: nookitAIModels),
           fallback != model {
            return try await completeNookitAI(model: fallback, prompt: prompt, system: system)
        }

        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ToolError.message(Self.serverError(text, status: http.statusCode, provider: "NVIDIA API"))
        }

        if let serverError = decoded?["error"] as? [String: Any],
           let message = serverError["message"] as? String {
            throw ToolError.message(message)
        }

        guard let choices = decoded?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw ToolError.message("NVIDIA API finished without returning any text. Try again.")
        }

        if let content = message["content"] as? String,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let reasoning = message["reasoning_content"] as? String,
           !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ToolError.message("The model only returned hidden reasoning. Pick a non-reasoning model in AI Configuration and try again.")
        }

        throw ToolError.message("NVIDIA API finished without returning any text. Try again.")
    }

    // MARK: - Apple Intelligence

    #if canImport(FoundationModels)
    /// Stored as `Any` because `LanguageModelSession` is only available on
    /// macOS 26+, and stored properties cannot carry `@available`.
    private var appleSessionStorage: Any?
    #endif

    private func sendApple(prompt: String, assistantID: UUID) async throws {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session: LanguageModelSession
            if let existing = appleSessionStorage as? LanguageModelSession {
                session = existing
            } else {
                let created = LanguageModelSession(instructions: "You are Nookit's small on-device assistant. Be concise, practical and private. Prefer short answers with concrete steps.")
                appleSessionStorage = created
                session = created
            }
            let response = try await session.respond(to: prompt)
            append(response.content, to: assistantID)
            return
        }
        #endif
        throw ToolError.message(unavailableReason)
    }

    // MARK: - Nookit AI (NVIDIA API)

    private func streamNookitAI(model: String, messages: [[String: Any]], assistantID: UUID) async throws {
        guard let base = Self.baseURL(nookitAIURL) else {
            throw ToolError.message("The NVIDIA API address is invalid.")
        }
        guard !nookitAIKey.isEmpty else {
            throw ToolError.message(unavailableReason)
        }

        var request = URLRequest(url: base.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(nookitAIKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": Self.withSystemPrompt(messages),
            "max_tokens": 4096,
            "temperature": 0.7,
            "top_p": 1.0,
            "frequency_penalty": 0.0,
            "presence_penalty": 0.0
        ]

        // Nemotron reasoning models otherwise spend a long time streaming
        // `reasoning_content` before the first visible token, which made the
        // chat look stuck on "thinking". Ask for the answer directly.
        if model.lowercased().contains("nemotron") {
            body["chat_template_kwargs"] = ["enable_thinking": false]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ToolError.message("NVIDIA API returned no HTTP response.")
        }

        // Handle 404 "Function not found" - model not available for this account/endpoint
        if http.statusCode == 404 {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line + "\n" }
            if let fallbackModel = Self.fallbackVisionModel(for: model, available: nookitAIModels),
               fallbackModel != model {
                return try await streamNookitAI(model: fallbackModel, messages: messages, assistantID: assistantID)
            }
            throw ToolError.message("Model '\(model)' is not available on this NVIDIA account. Select a different model in AI Configuration, or check your API key at build.nvidia.com. \(Self.serverError(errorBody, status: 404, provider: "NVIDIA API"))")
        }

        guard (200..<300).contains(http.statusCode) else {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line + "\n" }
            throw ToolError.message(Self.serverError(errorBody, status: http.statusCode, provider: "NVIDIA API"))
        }

        var received = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if isCancelled { throw CancellationError() }

            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data),
                  let object = raw as? [String: Any] else { continue }

            if let serverError = object["error"] as? [String: Any],
               let message = serverError["message"] as? String {
                throw ToolError.message(message)
            }

            guard let choices = object["choices"] as? [[String: Any]],
                  let choice = choices.first else { continue }
            let delta = choice["delta"] as? [String: Any] ?? [:]

            // Reasoning-capable models stream internal thoughts here. Track the
            // fact so the UI can show progress, but never mix it with the answer.
            if let reasoning = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String),
               !reasoning.isEmpty {
                appendReasoning(reasoning, to: assistantID)
            }

            if let content = delta["content"] as? String, !content.isEmpty {
                append(content, to: assistantID)
                received = true
            }

            if let finish = choice["finish_reason"] as? String, finish == "length", !received {
                throw ToolError.message("The model ran out of answer budget while reasoning. Try a shorter prompt, or choose a non-reasoning vision model in AI Configuration.")
            }
        }

        if !received {
            throw ToolError.message("NVIDIA API finished without returning any text. Try again or select a different model in AI Configuration.")
        }
    }

    private static func looksLikeVisionModel(_ model: String) -> Bool {
        let lower = model.lowercased()
        let visionKeywords = ["vision", "vl-", "vl_", "omni", "vila", "neva", "phi-3-vision", "gemma-3", "gemma-4", "llava", "fuyu", "kosmos"]
        return visionKeywords.contains { lower.contains($0) }
    }

    private static func fallbackVisionModel(for requestedModel: String, available: [String]) -> String? {
        // Priority list of vision models that commonly work on NVIDIA API
        let preferredVisionModels = [
            "nvidia/nemotron-3.5-super-vl-120b-a12b",
            "meta/llama-3.2-90b-vision-instruct",
            "microsoft/phi-3-vision-128k-instruct",
            "google/gemma-3-12b-it",
            "nvidia/neva-22b",
            "nvidia/vila",
            "adept/fuyu-8b",
        ]
        
        // First try: a preferred model that's in the available list
        for model in preferredVisionModels where model != requestedModel {
            if available.contains(model) {
                return model
            }
        }
        // Second try: any available model that looks like a vision model
        for model in available where model != requestedModel {
            if looksLikeVisionModel(model) {
                return model
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func append(_ text: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += text
    }

    private func appendReasoning(_ text: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].reasoning += text
    }

    private func friendly(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
                switch provider {
                case .nookitAI, .automatic:
                    return "Can't reach NVIDIA API at \(nookitAIURL). Check your internet connection and API key."
                case .apple:
                    break
                }
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private static func baseURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }

    private static func extractTextFromFile(_ file: AttachedFile) -> String? {
        if file.mimeType == "text/plain" {
            return String(data: file.data, encoding: .utf8)
        } else if file.mimeType == "application/pdf" {
            guard let pdf = PDFDocument(data: file.data) else { return nil }
            var text = ""
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i), let pageText = page.string {
                    text += pageText + "\n"
                }
            }
            return text.isEmpty ? nil : text
        }
        return nil
    }

    /// NVIDIA vision models reliably accept PNG and JPEG data URLs. Convert
    /// HEIC/WebP/TIFF/BMP files and downscale very large images so requests are
    /// quick and the model actually receives a supported payload.
    private static func apiImage(for file: AttachedFile) -> (mime: String, base64: String) {
        let originalMime = file.mimeType.hasPrefix("image/") ? file.mimeType : "image/jpeg"
        if (originalMime == "image/png" || originalMime == "image/jpeg"), file.data.count <= 3_000_000 {
            return (originalMime, file.data.base64EncodedString())
        }

        guard let image = NSImage(data: file.data) else {
            return (originalMime, file.data.base64EncodedString())
        }

        let source = image.size
        let maxDimension: CGFloat = 1536
        let longest = max(source.width, source.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = NSSize(width: max(1, round(source.width * scale)), height: max(1, round(source.height * scale)))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return (originalMime, file.data.base64EncodedString())
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: target).fill()
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        if let png = rep.representation(using: .png, properties: [:]) {
            return ("image/png", png.base64EncodedString())
        }
        return (originalMime, file.data.base64EncodedString())
    }

    private static func wireMessages(from messages: [ChatMessage]) -> [[String: Any]] {
        // Keep the context small and predictable. Older base64 images are the
        // main cause of slow follow-up turns, so only the most recent image
        // turn is uploaded in full. Earlier attachments stay as short notes.
        let recent = Array(messages.suffix(30))
        let lastImageMessage = recent.last(where: {
            $0.role == .user && $0.attachments.contains(where: \.isImage)
        })?.id
        let lastDocumentMessage = recent.last(where: {
            $0.role == .user && $0.attachments.contains(where: { !$0.isImage })
        })?.id

        var documentBudget = 24_000

        return recent
            .filter { !$0.text.isEmpty || !$0.attachments.isEmpty }
            .map { message in
                var content: [[String: Any]] = []
                var fullText = message.text

                for attachment in message.attachments where !attachment.isImage {
                    guard message.id == lastDocumentMessage,
                          documentBudget > 0,
                          let extracted = extractTextFromFile(attachment) else {
                        fullText = "Earlier attachment: \(attachment.filename) (contents omitted)\n\n\(fullText)"
                        continue
                    }
                    let capped = String(extracted.prefix(min(documentBudget, 12_000)))
                    documentBudget -= capped.count
                    fullText = "File: \(attachment.filename)\n\n\(capped)\n\n---\n\n\(fullText)"
                }

                for attachment in message.attachments where attachment.isImage {
                    if message.id == lastImageMessage {
                        let image = Self.apiImage(for: attachment)
                        content.append([
                            "type": "image_url",
                            "image_url": [
                                "url": "data:\(image.mime);base64,\(image.base64)",
                                "detail": "high"
                            ]
                        ])
                    } else {
                        fullText = "Earlier image: \(attachment.filename) (not resent)\n\n\(fullText)"
                    }
                }

                if !fullText.isEmpty {
                    content.insert(["type": "text", "text": fullText], at: 0)
                }

                return ["role": message.role.rawValue, "content": content]
            }
    }

    private static func withSystemPrompt(_ messages: [[String: Any]]) -> [[String: Any]] {
        [["role": "system", "content": [["type": "text", "text": "You are Nookit, a concise, practical assistant running on the user's Mac. Prefer short answers with concrete steps. You can analyze images and read attached documents when provided."]]]] + messages
    }

    private static func serverError(_ body: String, status: Int, provider: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let raw = try? JSONSerialization.jsonObject(with: data),
           let object = raw as? [String: Any] {
            if let message = object["error"] as? String { return message }
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String { return message }
        }
        let tail = trimmed.split(separator: "\n").suffix(2).joined(separator: " ")
        return tail.isEmpty ? "\(provider) answered \(status)." : "\(provider) answered \(status): \(tail)"
    }

    static func friendlyModelName(_ modelId: String) -> String {
        // Map technical model IDs to friendly names
        let mappings: [String: String] = [
            "nvidia/nemotron-3.5-super-vl-120b-a12b": "Nemotron 3.5 Super VL (120B)",
            "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning": "Nemotron 3 Nano Omni (30B)",
            "nvidia/neva-22b": "NEVA 22B",
            "nvidia/vila": "VILA",
            "meta/llama-3.2-90b-vision-instruct": "Llama 3.2 90B Vision",
            "microsoft/phi-3-vision-128k-instruct": "Phi-3 Vision (128K)",
            "google/gemma-3-12b-it": "Gemma 3 12B",
            "google/gemma-3-4b-it": "Gemma 3 4B",
            "google/gemma-4-31b-it": "Gemma 4 31B",
            "adept/fuyu-8b": "Fuyu 8B",
            "microsoft/kosmos-2": "KOSMOS-2",
            "nvidia/nemotron-3-ultra": "Nemotron 3 Ultra",
            "nvidia/nemotron-3.5-lightning-30b-a3b": "Nemotron 3.5 Lightning (30B)",
        ]
        return mappings[modelId] ?? modelId
    }
}