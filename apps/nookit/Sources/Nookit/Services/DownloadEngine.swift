import Foundation

/// Resolves and, when needed, provisions the `yt-dlp` download engine.
///
/// The app never assumes Homebrew is present. On first use it can fetch the
/// official standalone mac binary into Application Support, which keeps the
/// Download Video tool working for YouTube and other streaming sites on a
/// clean Mac. A copy on `PATH` (Homebrew, MacPorts, pip) is preferred when it
/// already exists so power users keep their own updates.
enum DownloadEngine {
    static let binaryName = "yt-dlp"
    static let downloadURL = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

    static var installFolder: URL { AppPaths.supportFolder("bin") }
    static var installedURL: URL { installFolder.appendingPathComponent(binaryName) }

    /// A bundled copy wins, then the copy Nookit installed, then `PATH`.
    static var path: String? {
        if let bundled = Bundle.main.url(forResource: binaryName, withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        if FileManager.default.isExecutableFile(atPath: installedURL.path) {
            return installedURL.path
        }
        return Shell.which(binaryName)
    }

    static var isInstalled: Bool { path != nil }

    /// yt-dlp uses a JavaScript runtime to solve YouTube's player challenges.
    /// Prefer Deno (yt-dlp's default) and fall back to Node, which many Macs
    /// with developer tools already have.
    static var javascriptRuntime: String? {
        if let deno = Shell.which("deno") { return "deno:\(deno)" }
        if let node = Shell.which("node") { return "node:\(node)" }
        return nil
    }

    static func isYouTube(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host == "youtu.be" || host.hasSuffix(".youtu.be")
            || host == "youtube.com" || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
    }

    static var version: String? {
        guard let path else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    /// Downloads the official standalone binary, installs it, and verifies that
    /// it runs. Returns the installed path.
    static func install() async throws -> String {
        guard let url = URL(string: downloadURL) else {
            throw ToolError.message("The download engine address is invalid.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        request.setValue("Nookit/1.0", forHTTPHeaderField: "User-Agent")

        let (temporary, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ToolError.message("The download engine server answered \(http.statusCode).")
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: temporary.path))
            .flatMap { ($0[.size] as? NSNumber)?.intValue } ?? 0
        guard size > 1_000_000 else {
            throw ToolError.message("The download engine file looked incomplete. Try again.")
        }

        try FileManager.default.createDirectory(at: installFolder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: installedURL.path) {
            try? FileManager.default.removeItem(at: installedURL)
        }
        try FileManager.default.moveItem(at: temporary, to: installedURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedURL.path)
        // A quarantined helper can be blocked by Gatekeeper when launched.
        _ = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", installedURL.path])

        guard let version = version, !version.isEmpty else {
            try? FileManager.default.removeItem(at: installedURL)
            throw ToolError.message("The download engine couldn’t run after installing. Install it with `brew install yt-dlp` and try again.")
        }

        return installedURL.path
    }

    /// Removes only the copy Nookit installed; a PATH copy is left alone.
    static func uninstall() {
        try? FileManager.default.removeItem(at: installedURL)
    }

    /// The site likely needs yt-dlp rather than a plain HTTP request.
    static func needsStreamingEngine(_ url: URL) -> Bool {
        let direct = ["mp4", "m4v", "mov", "webm", "mkv", "avi", "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]
        if direct.contains(url.pathExtension.lowercased()) { return false }
        let host = (url.host ?? "").lowercased()
        let streamingHosts = [
            "youtube.com", "youtu.be", "youtube-nocookie.com", "vimeo.com", "dailymotion.com",
            "tiktok.com", "instagram.com", "facebook.com", "fb.watch", "twitter.com", "x.com",
            "reddit.com", "redd.it", "twitch.tv", "soundcloud.com", "bilibili.com",
            "b23.tv", "rumble.com", "odysee.com", "streamable.com", "pornhub.com"
        ]
        if streamingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        // Unknown extension: treating it as a page is the safer default.
        return url.pathExtension.isEmpty
    }
}

/// Which browser's cookies yt-dlp may use for sites that want a signed-in
/// session. Opt-in, because macOS may ask for Full Disk Access.
enum CookieSource: String, CaseIterable, Identifiable {
    case none = "None"
    case safari = "Safari"
    case chrome = "Chrome"
    case firefox = "Firefox"
    case edge = "Edge"
    case brave = "Brave"

    var id: String { rawValue }

    var ytDlpValue: String? {
        switch self {
        case .none: return nil
        case .safari: return "safari"
        case .chrome: return "chrome"
        case .firefox: return "firefox"
        case .edge: return "edge"
        case .brave: return "brave"
        }
    }
}

/// Turns yt-dlp's verbose stderr into a short, actionable message.
enum DownloadErrors {
    static func friendly(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return "The download engine couldn’t download that address."
        }
        let lower = text.lowercased()

        if lower.contains("sign in to confirm") || lower.contains("not a bot") || lower.contains("confirm you're not a bot") {
            return "YouTube asked for a sign-in check. Choose a browser under “Browser cookies” (Safari, Chrome, Firefox…) and try again, or install yt-dlp with Homebrew and update it with `brew upgrade yt-dlp`."
        }
        if lower.contains("video unavailable") || lower.contains("private video") {
            return "That video is private, age-restricted, or unavailable in your region."
        }
        if lower.contains("unsupported url") {
            return "That site isn’t supported by the download engine. Try a direct video file link instead."
        }
        if lower.contains("ffmpeg") && (lower.contains("not found") || lower.contains("not installed")) {
            return "The video was downloaded but merging needs FFmpeg. Install it with `brew install ffmpeg` and try again."
        }
        if lower.contains("http error 403") || lower.contains("forbidden") {
            return "The site refused the request (403). If you’re signed in, choose a browser under “Browser cookies”; otherwise try again later."
        }
        if lower.contains("unable to download webpage") || lower.contains("failed to resolve") || lower.contains("could not resolve host") {
            return "Nookit couldn’t reach that address. Check your connection and the link."
        }
        if lower.contains("no space left") {
            return "There isn’t enough free disk space for this download."
        }

        // Keep the useful tail, where yt-dlp puts the actual reason.
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let tail = lines.suffix(4).joined(separator: "\n")
        return tail.isEmpty ? "The download engine couldn’t download that address." : tail
    }
}
