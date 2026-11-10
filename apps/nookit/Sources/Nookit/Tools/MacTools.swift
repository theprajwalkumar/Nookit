import SwiftUI
import AppKit
import Foundation

// MARK: - Keep awake

struct KeepAwakeTool: View {
    @ObservedObject private var service = KeepAwakeService.shared

    var body: some View {
        ToolPage(symbol: "cup.and.saucer", title: "Keep Awake", subtitle: "Stop the display from sleeping while a render, download or call finishes.") {
            ToolCard(title: "Status") {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(service.active ? Theme.mint.opacity(0.18) : Theme.raised)
                            .frame(width: 64, height: 64)
                        Image(systemName: service.active ? "cup.and.saucer.fill" : "cup.and.saucer")
                            .font(.system(size: 24))
                            .foregroundStyle(service.active ? Theme.mint : Theme.textTertiary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(service.active ? "Keeping this Mac awake" : "Sleep is allowed")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text(service.active ? service.statusText : "Choose a duration to start a power assertion.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if service.active {
                        Button("Stop") { service.stop() }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                if let lastError = service.lastError { InlineError(message: lastError) }
            }

            ToolCard(title: "Start") {
                HStack(spacing: 10) {
                    ForEach([30, 60, 120], id: \.self) { minutes in
                        Button("\(minutes) min") { service.start(minutes: minutes) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button("Until I stop it") { service.start(minutes: nil) }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                }
                Text("Uses the same IOKit assertion as apps like Caffeine. It doesn’t change your Energy Saver settings.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

// MARK: - Eject disks

struct EjectDisksTool: View {
    private struct Volume: Identifiable {
        let id: String
        let name: String
        let url: URL
        let capacity: Int64?
        let available: Int64?
        let removable: Bool
    }

    @State private var volumes: [Volume] = []
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        ToolPage(symbol: "eject", title: "Eject All Disks", subtitle: "Safely eject external drives and disk images before unplugging them.") {
            ToolCard(title: "Mounted volumes") {
                if volumes.isEmpty {
                    Text("No ejectable volumes are mounted.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 1) {
                        ForEach(volumes) { volume in
                            HStack(spacing: 10) {
                                Image(systemName: volume.removable ? "externaldrive" : "internaldrive")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.ember)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(volume.name).font(.system(size: 12.5, weight: .medium))
                                    if let capacity = volume.capacity, let available = volume.available {
                                        Text("\(Fmt.bytes(available)) free of \(Fmt.bytes(capacity))")
                                            .font(Theme.caption)
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                }
                                Spacer()
                                Button("Eject") { eject(volume) }.buttonStyle(QuietButtonStyle())
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Theme.raised.opacity(0.4))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                HStack {
                    Button("Refresh") { load() }.buttonStyle(QuietButtonStyle())
                    Spacer()
                    if !volumes.isEmpty {
                        ConfirmButton(
                            title: "Eject all",
                            confirmTitle: "Eject \(volumes.count) volumes?",
                            detail: "Save any open files first. Ejecting can interrupt a copy in progress.",
                            action: { volumes.forEach(eject) }
                        )
                    }
                }
                if let message { Text(message).font(Theme.caption).foregroundStyle(Theme.mint) }
                if let error { InlineError(message: error) }
            }
        }
        .onAppear { load() }
    }

    private func load() {
        message = nil
        error = nil
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        volumes = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let internalVolume = values.volumeIsInternal ?? true
            if internalVolume && url.path == "/" { return nil }
            return Volume(
                id: url.path,
                name: values.volumeName ?? url.lastPathComponent,
                url: url,
                capacity: values.volumeTotalCapacity.map(Int64.init),
                available: values.volumeAvailableCapacity.map(Int64.init),
                removable: values.volumeIsRemovable ?? false
            )
        }
        .filter { $0.url.path != "/" }
    }

    private func eject(_ volume: Volume) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            message = "Ejected \(volume.name)."
            volumes.removeAll { $0.id == volume.id }
        } catch {
            self.error = "Couldn’t eject \(volume.name). \(error.localizedDescription)"
        }
    }
}

// MARK: - Battery health

enum BatteryInfo {
    static func rows(pmset: String, ioreg: String, host: String) -> [(String, String)] {
        var output: [(String, String)] = []
        if let percent = pmset.firstMatch(of: #/(\d+)%/#).map({ String($0.1) }) {
            output.append(("Charge", "\(percent)%"))
        }
        if pmset.contains("AC Power") { output.append(("Power source", "Power adapter")) }
        if pmset.contains("Battery Power") { output.append(("Power source", "Battery")) }
        if pmset.contains("charging") { output.append(("State", "Charging")) }
        if pmset.contains("discharging") { output.append(("State", "Discharging")) }
        if pmset.contains("charged") { output.append(("State", "Fully charged")) }

        let lines = ioreg.components(separatedBy: "\n")
        for key in ["CycleCount", "DesignCapacity", "MaxCapacity", "Temperature", "ExternalConnected", "IsCharging"] {
            let needle = "\"\(key)\" = "
            guard let line = lines.first(where: { $0.contains(needle) }),
                  let range = line.range(of: needle) else { continue }
            let value = line[range.upperBound...]
                .prefix { !$0.isWhitespace && $0 != "}" && $0 != "," }
            output.append((key, String(value)))
        }
        output.append(("Computer", host))
        return output
    }
}

struct BatteryHealthTool: View {
    @State private var rows: [(String, String)] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ToolPage(symbol: "battery.75percent", title: "Battery Health", subtitle: "Read charge, cycle count and power state straight from the controller.") {
            HStack(spacing: 8) {
                Button("Refresh") { load() }.buttonStyle(SecondaryButtonStyle())
                if loading { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let error { InlineError(message: error) }
            if !rows.isEmpty {
                ToolCard(title: "Power") {
                    VStack(spacing: 1) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack {
                                Text(row.0).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(row.1).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.textPrimary).textSelection(.enabled)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.raised.opacity(0.4))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            Text("Health is reported by macOS. Nookit only reads it; it never changes charging behaviour.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .onAppear { load() }
    }

    private func load() {
        loading = true
        error = nil
        Task {
            do {
                let battery = try await Shell.run("/usr/bin/pmset", ["-g", "batt"])
                let ioreg = try await Shell.run("/usr/sbin/ioreg", ["-l", "-w0", "-r", "-c", "AppleSmartBattery"])
                let final = BatteryInfo.rows(
                    pmset: battery.output,
                    ioreg: ioreg.stdout,
                    host: ProcessInfo.processInfo.hostName
                )
                await MainActor.run {
                    rows = final
                    loading = false
                }
            } catch {
                await MainActor.run {
                    loading = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Storage explorer

struct StorageEntry: Identifiable {
    var id: String { url.path }
    let name: String
    let bytes: Int64
    let url: URL
}

enum StorageScan {
    static func scan(_ root: URL) -> (entries: [StorageEntry], total: Int64) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [])) ?? []
        var found: [StorageEntry] = []
        var sum: Int64 = 0
        for child in children {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            var size: Int64 = 0
            if let enumerator = FileManager.default.enumerator(
                at: child,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) {
                for case let file as URL in enumerator {
                    guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isDirectory != true else { continue }
                    size += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                }
            }
            sum += size
            found.append(StorageEntry(name: child.lastPathComponent, bytes: size, url: child))
        }
        found.sort { $0.bytes > $1.bytes }
        return (found, sum)
    }
}

struct StorageExplorerTool: View {
    private typealias Entry = StorageEntry

    @State private var entries: [Entry] = []
    @State private var total: Int64 = 0
    @State private var scanning = false
    @State private var error: String?
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        ToolPage(symbol: "internaldrive", title: "Storage Explorer", subtitle: "See which folders in your home directory are using the most space.") {
            HStack(spacing: 10) {
                Button(scanning ? "Scanning…" : "Scan home folder") { scan() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(scanning)
                if scanning { ProgressView().controlSize(.small) }
                Spacer()
                Button("Open home folder") { store.open(FileManager.default.homeDirectoryForCurrentUser) }
                    .buttonStyle(QuietButtonStyle())
            }

            if let error { InlineError(message: error) }

            if !entries.isEmpty {
                StatRow(items: [
                    ("Home folder", Fmt.bytes(total)),
                    ("Largest", entries.first.map { Fmt.bytes($0.bytes) } ?? "—"),
                    ("Folders", "\(entries.count)")
                ])
                ToolCard(title: "By folder", subtitle: "Hidden folders are included in the total but not listed.") {
                    VStack(spacing: 6) {
                        ForEach(entries.prefix(12)) { entry in
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.ember)
                                    .frame(width: 18)
                                Text(entry.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 150, alignment: .leading)
                                GeometryReader { geo in
                                    let fraction = total > 0 ? CGFloat(entry.bytes) / CGFloat(total) : 0
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Theme.ember.opacity(0.75))
                                        .frame(width: max(4, geo.size.width * fraction))
                                }
                                .frame(height: 10)
                                Text(Fmt.bytes(entry.bytes))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 74, alignment: .trailing)
                                Button("Reveal") { store.reveal(entry.url) }.buttonStyle(QuietButtonStyle())
                            }
                        }
                    }
                }
            } else if !scanning {
                EmptyState(
                    symbol: "internaldrive",
                    title: "Nothing scanned yet",
                    message: "Nookit reads folder sizes locally. A first scan can take a minute on a large home folder.",
                    actionTitle: "Scan now",
                    action: { scan() }
                )
            }
        }
    }

    private func scan() {
        scanning = true
        error = nil
        entries = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task.detached(priority: .userInitiated) {
            let result = StorageScan.scan(home)
            let final = result.entries
            let finalTotal = result.total
            await MainActor.run {
                entries = final
                total = finalTotal
                scanning = false
            }
        }
    }
}

// MARK: - Network speed

enum NetworkSpeed {
    static func megabitsPerSecond(bytes: Int, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(bytes) * 8 / seconds / 1_000_000
    }

    /// Cloudflare sometimes answers a single large request with HTTP 403, so
    /// the test uses a few smaller chunks and retries. Chunked requests also
    /// let the UI show progress instead of freezing on one 15 MB payload.
    static let downloadChunks = [5_000_000, 5_000_000, 5_000_000, 5_000_000]
    static let uploadBytes = 5_000_000
    static let fallbackDownload = "https://proof.ovh.net/files/10Mb.dat"

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func downloadURL(bytes: Int) -> URL? {
        URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)&r=\(UUID().uuidString)")
    }
}

struct NetworkSpeedTestTool: View {
    @State private var testing = false
    @State private var phase = ""
    @State private var latency: Double?
    @State private var download: Double?
    @State private var upload: Double?
    @State private var bytes = 0
    @State private var seconds = 0.0
    @State private var notes: [String] = []
    @State private var error: String?

    var body: some View {
        ToolPage(symbol: "speedometer", title: "Network Speed Test", subtitle: "Measure latency, download and upload against Cloudflare. The download runs in small chunks with retries, so a single rejected request no longer fails the whole test.") {
            ToolCard(title: "Connection test") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(download.map { String(format: "%.1f", $0) } ?? (testing ? "—" : "Not tested"))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ember)
                        Text("Mbps download")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button(testing ? "Testing…" : "Start test") { run() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                }

                StatRow(items: [
                    ("Latency", latency.map { String(format: "%.0f ms", $0) } ?? "—"),
                    ("Download", download.map { String(format: "%.1f Mbps", $0) } ?? "—"),
                    ("Upload", upload.map { String(format: "%.1f Mbps", $0) } ?? "—")
                ])

                if testing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(phase.isEmpty ? "Testing…" : phase)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if bytes > 0 {
                    Text("Downloaded \(Fmt.bytes(bytes)) in \(String(format: "%.1f", seconds)) s.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(notes, id: \.self) { note in
                    Text(note)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                if let error { InlineError(message: error) }
            }
            Text("This test downloads about 20 MB and uploads about 5 MB, so it uses data. Results depend on the server and your connection at that moment.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func run() {
        testing = true
        error = nil
        phase = "Measuring latency…"
        latency = nil
        download = nil
        upload = nil
        bytes = 0
        seconds = 0
        notes = []

        Task {
            let lat = await measureLatency()
            latency = lat
            if lat == nil {
                notes.append("Latency couldn’t be measured; the download test still ran.")
            }

            phase = "Testing download…"
            do {
                let started = Date()
                var received = 0
                for (index, size) in NetworkSpeed.downloadChunks.enumerated() {
                    phase = "Downloading chunk \(index + 1) of \(NetworkSpeed.downloadChunks.count)…"
                    let count = try await Self.downloadChunk(bytes: size)
                    received += count
                    bytes = received
                    seconds = Date().timeIntervalSince(started)
                    download = NetworkSpeed.megabitsPerSecond(bytes: received, seconds: seconds)
                }
            } catch {
                phase = "Trying a fallback server…"
                do {
                    let started = Date()
                    let count = try await Self.downloadFallback()
                    bytes = count
                    seconds = Date().timeIntervalSince(started)
                    download = NetworkSpeed.megabitsPerSecond(bytes: count, seconds: seconds)
                    notes.append("Cloudflare’s speed endpoint refused the request, so a single fallback payload was used.")
                } catch {
                    self.error = "The download test couldn’t run. \(error.localizedDescription)"
                    self.testing = false
                    self.phase = ""
                    return
                }
            }

            phase = "Testing upload…"
            do {
                upload = try await Self.measureUpload(bytes: NetworkSpeed.uploadBytes)
            } catch {
                notes.append("Upload couldn’t be measured. Download results are still valid.")
            }

            phase = ""
            testing = false
        }
    }

    private func measureLatency() async -> Double? {
        var samples: [Double] = []
        for index in 0..<4 {
            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0&r=\(UUID().uuidString)") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let start = Date()
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               index > 0 {
                samples.append(Date().timeIntervalSince(start) * 1000)
            }
        }
        return NetworkSpeed.median(samples)
    }

    private static func downloadChunk(bytes: Int) async throws -> Int {
        var lastMessage = "The speed endpoint refused the request."
        for attempt in 0..<3 {
            guard let url = NetworkSpeed.downloadURL(bytes: bytes) else {
                throw ToolError.message("The speed test address is invalid.")
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 45
            request.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastMessage = "The speed endpoint returned no HTTP response."
                    continue
                }
                guard (200..<300).contains(http.statusCode), data.count > 0 else {
                    lastMessage = "The speed endpoint answered \(http.statusCode)."
                    continue
                }
                return data.count
            } catch {
                lastMessage = error.localizedDescription
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        throw ToolError.message(lastMessage)
    }

    private static func downloadFallback() async throws -> Int {
        guard let url = URL(string: NetworkSpeed.fallbackDownload) else {
            throw ToolError.message("The fallback speed test address is invalid.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 0 else {
            throw ToolError.message("The fallback server didn’t return a test payload.")
        }
        return data.count
    }

    private static func measureUpload(bytes: Int) async throws -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else {
            throw ToolError.message("The upload test address is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let payload = Data(count: bytes)
        let start = Date()
        let (_, response) = try await URLSession.shared.upload(for: request, from: payload)
        let elapsed = Date().timeIntervalSince(start)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ToolError.message("The upload endpoint refused the request.")
        }
        return NetworkSpeed.megabitsPerSecond(bytes: bytes, seconds: elapsed)
    }
}

// MARK: - Wi-Fi password

enum WiFiNetwork {
    static func current(from networksetupOutput: String) -> String? {
        guard let range = networksetupOutput.range(of: "Current Wi-Fi Network: ") else { return nil }
        let name = String(networksetupOutput[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

struct WiFiPasswordTool: View {
    @State private var network = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        ToolPage(symbol: "wifi", title: "Wi-Fi Password", subtitle: "Look up the saved password for the network you’re on, from your login keychain.") {
            ToolCard(title: "Current network") {
                HStack(spacing: 10) {
                    Text(network.isEmpty ? "Not connected" : network)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Button(working ? "Looking up…" : "Show password") { lookup() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(working)
                    if working { ProgressView().controlSize(.small) }
                }
                if !password.isEmpty {
                    HStack(spacing: 10) {
                        Text(password)
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        CopyButton(value: password)
                    }
                    .padding(10)
                    .background(Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                if let error { InlineError(message: error) }
                Text("macOS may ask for keychain access the first time. The password is read once and never stored by Nookit.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .onAppear { loadNetwork() }
    }

    private func loadNetwork() {
        Task {
            let result = try? await Shell.run("/usr/sbin/networksetup", ["-getairportnetwork", "en0"])
            if let name = WiFiNetwork.current(from: result?.output ?? "") {
                await MainActor.run { network = name }
            }
        }
    }

    private func lookup() {
        guard !network.isEmpty else {
            error = "No Wi-Fi network is active."
            return
        }
        working = true
        error = nil
        password = ""
        Task {
            let result = try? await Shell.run(
                "/usr/bin/security",
                ["find-generic-password", "-D", "AirPort network password", "-a", network, "-w"],
                timeout: 20
            )
            await MainActor.run {
                working = false
                if let value = result, value.succeeded {
                    password = value.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    error = "That network’s password isn’t in your login keychain, or keychain access was declined."
                }
            }
        }
    }
}
