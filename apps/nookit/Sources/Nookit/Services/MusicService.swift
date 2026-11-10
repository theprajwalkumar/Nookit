import SwiftUI
import AppKit

struct NowPlaying: Equatable {
    var app: String = ""
    var playing: Bool = false
    var track: String = ""
    var artist: String = ""
    var available: Bool = false
    var unauthorized: Bool = false

    var summary: String? {
        guard available else { return nil }
        if track.isEmpty { return playing ? "\(app) playing" : "\(app) paused" }
        return "\(track) — \(artist)"
    }
}

@MainActor
final class MusicService: ObservableObject {
    static let shared = MusicService()

    @Published private(set) var now = NowPlaying()
    @Published private(set) var busy = false

    private var timer: Timer?
    private var refreshing = false

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        Task { await refresh() }
    }

    private func isRunning(_ bundle: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundle }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let musicRunning = isRunning("com.apple.Music")
        let spotifyRunning = isRunning("com.spotify.client")

        var candidate: NowPlaying?
        if musicRunning, let state = await query(app: "Music") {
            candidate = state
        }
        if (candidate == nil || candidate?.playing == false), spotifyRunning, let spotify = await query(app: "Spotify") {
            if spotify.playing || candidate == nil { candidate = spotify }
        }

        if let candidate {
            now = candidate
        } else {
            now = NowPlaying()
        }
    }

    private func query(app: String) async -> NowPlaying? {
        let script = """
        tell application "\(app)"
            try
                set st to (player state as string)
                set nm to ""
                set ar to ""
                if st is not "stopped" then
                    set nm to name of current track
                    set ar to artist of current track
                end if
                return st & "\t" & nm & "\t" & ar
            on error errMsg
                return "error\t" & errMsg & "\t"
            end try
        end tell
        """
        do {
            let output = try await Shell.checked("/usr/bin/osascript", ["-e", script], timeout: 5)
            let parts = output.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
            if parts.first == "error" {
                return NowPlaying(available: false, unauthorized: true)
            }
            let state = parts.first?.lowercased() ?? "stopped"
            let track = parts.count > 1 ? parts[1] : ""
            let artist = parts.count > 2 ? parts[2] : ""
            return NowPlaying(
                app: app,
                playing: state.contains("playing"),
                track: track,
                artist: artist,
                available: true
            )
        } catch {
            return NowPlaying(available: false, unauthorized: true)
        }
    }

    func playPause() {
        control("playpause")
    }

    func next() {
        control("next track")
    }

    func previous() {
        control("previous track")
    }

    private func control(_ command: String) {
        let app = now.app.isEmpty ? (isRunning("com.apple.Music") ? "Music" : "Spotify") : now.app
        guard !app.isEmpty else { return }
        busy = true
        Task {
            _ = try? await Shell.run("/usr/bin/osascript", ["-e", "tell application \"\(app)\" to \(command)"], timeout: 5)
            try? await Task.sleep(for: .milliseconds(350))
            busy = false
            await refresh()
        }
    }
}
