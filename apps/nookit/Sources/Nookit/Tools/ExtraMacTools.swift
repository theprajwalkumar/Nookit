import SwiftUI
import AppKit
import IOKit.pwr_mgt
import ApplicationServices
import UniformTypeIdentifiers

// MARK: - App metadata helpers

enum AppInfo {
    static func signer(for url: URL) async -> (authority: String, team: String, identifier: String, verified: Bool, assessment: String) {
        let details = try? await Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", url.path])
        let text = (details?.stderr ?? "") + (details?.stdout ?? "")
        func value(_ prefix: String) -> String {
            text.components(separatedBy: .newlines)
                .first { $0.hasPrefix(prefix) }?
                .replacingOccurrences(of: prefix, with: "")
                .trimmingCharacters(in: .whitespaces) ?? ""
        }
        let verify = try? await Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", url.path])
        let assess = try? await Shell.run("/usr/sbin/spctl", ["-a", "-vvv", "-t", "exec", url.path])
        let assessment = (assess?.stderr ?? "") + (assess?.stdout ?? "")
        return (
            value("Authority="),
            value("TeamIdentifier="),
            value("Identifier="),
            verify?.succeeded ?? false,
            assessment.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func size(of url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            if let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}


enum ScanLeftovers {
    typealias Leftover = UninstallAppTool.Leftover

    static func find(url: URL, bundleID: String) -> [Leftover] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        let name = url.deletingPathExtension().lastPathComponent
        var results: [Leftover] = []

        func add(_ target: URL, _ kind: String, admin: Bool = false) {
            guard FileManager.default.fileExists(atPath: target.path) else { return }
            if results.contains(where: { $0.url == target }) { return }
            results.append(Leftover(url: target, kind: kind, size: AppInfo.size(of: target), adminOnly: admin))
        }

        if !bundleID.isEmpty {
            add(library.appendingPathComponent("Preferences/\(bundleID).plist"), "Preferences")
            add(library.appendingPathComponent("Saved Application State/\(bundleID).savedState"), "Saved state")
            add(library.appendingPathComponent("Caches/\(bundleID)"), "Cache")
            add(library.appendingPathComponent("Application Support/\(bundleID)"), "Application support")
            add(library.appendingPathComponent("Containers/\(bundleID)"), "Container")
            add(library.appendingPathComponent("HTTPStorages/\(bundleID)"), "HTTP storage")
            add(library.appendingPathComponent("WebKit/\(bundleID)"), "WebKit data")
            add(library.appendingPathComponent("Logs/\(bundleID)"), "Logs")
            add(library.appendingPathComponent("Cookies/\(bundleID).binarycookies"), "Cookies")
            add(library.appendingPathComponent("LaunchAgents/\(bundleID).plist"), "Launch agent")
        }
        add(library.appendingPathComponent("Application Support/\(name)"), "Application support")
        add(library.appendingPathComponent("Caches/\(name)"), "Cache")
        add(library.appendingPathComponent("Logs/\(name)"), "Logs")
        add(library.appendingPathComponent("Preferences/\(name).plist"), "Preferences")

        // Group containers are shared; only match the exact bundle identifier.
        if !bundleID.isEmpty {
            let groups = library.appendingPathComponent("Group Containers")
            if let children = try? FileManager.default.contentsOfDirectory(at: groups, includingPropertiesForKeys: nil) {
                for child in children where child.lastPathComponent.contains(bundleID) {
                    add(child, "Group container")
                }
            }
        }

        // User launch agents named after the app.
        let agents = library.appendingPathComponent("LaunchAgents")
        if let children = try? FileManager.default.contentsOfDirectory(at: agents, includingPropertiesForKeys: nil) {
            for child in children where child.pathExtension == "plist" &&
                (child.lastPathComponent.localizedCaseInsensitiveContains(name) || (!bundleID.isEmpty && child.lastPathComponent.contains(bundleID))) {
                add(child, "Launch agent")
            }
        }

        for base in ["/Library/LaunchAgents", "/Library/LaunchDaemons"] {
            let folder = URL(fileURLWithPath: base)
            if let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                for child in children where child.pathExtension == "plist" &&
                    (child.lastPathComponent.localizedCaseInsensitiveContains(name) || (!bundleID.isEmpty && child.lastPathComponent.contains(bundleID))) {
                    add(child, "System launch item", admin: true)
                }
            }
        }

        return results.sorted { $0.size > $1.size }
    }

}

// MARK: - Uninstall app

struct UninstallAppTool: View {
    @StateObject private var job = JobState()
    @State private var app: URL?
    @State private var bundleID = ""
    @State private var version = ""
    @State private var signer = ""
    @State private var leftovers: [Leftover] = []
    @State private var selected: Set<URL> = []
    @State private var confirm = false
    @State private var scanTask: Task<Void, Never>?

    struct Leftover: Identifiable {
        var id: URL { url }
        let url: URL
        let kind: String
        let size: Int64
        let adminOnly: Bool
    }

    var body: some View {
        ToolPage(symbol: "trash.slash", title: "Uninstall App", subtitle: "Take the app and the files it left behind. Everything is reviewed before removal and goes to the Trash, not into the void.") {
            DropZone(title: "Choose an application", subtitle: "Drag an app here, or use the button. Nookit reads the bundle identifier and looks for related files.", allowsMultiple: false, types: [.application]) { urls in
                guard let url = urls.first else { return }
                load(url)
            }
            HStack(spacing: 10) {
                Button("Choose application…") {
                    if let url = FilePicker.files(title: "Choose an application", types: [.application], allowsMultiple: false).first {
                        load(url)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                if let app {
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([app]) }
                        .buttonStyle(QuietButtonStyle())
                    Spacer()
                    Text(app.deletingLastPathComponent().path)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            if let app {
                ToolCard(title: app.deletingPathExtension().lastPathComponent, subtitle: version.isEmpty ? nil : "Version \(version)") {
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bundleID.isEmpty ? "No bundle identifier" : bundleID)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                            Text(signer.isEmpty ? "Signature not readable" : signer)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    if !leftovers.isEmpty {
                        HStack {
                            Text("\(selected.count) of \(leftovers.count) selected · \(Fmt.bytes(selectedSize))")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Button("Select all") { selected = Set(leftovers.filter { !$0.adminOnly }.map(\.url)) }
                                .buttonStyle(QuietButtonStyle())
                            Button("Select none") { selected = [] }
                                .buttonStyle(QuietButtonStyle())
                        }
                        VStack(spacing: 1) {
                            ForEach(leftovers) { item in
                                HStack(spacing: 8) {
                                    Toggle("", isOn: Binding(
                                        get: { selected.contains(item.url) },
                                        set: { if $0 { selected.insert(item.url) } else { selected.remove(item.url) } }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                    .disabled(item.adminOnly)
                                    Image(systemName: icon(item.kind))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Theme.ember)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.url.lastPathComponent)
                                            .font(.system(size: 11.5))
                                            .lineLimit(1)
                                        Text(item.kind + (item.adminOnly ? " · needs administrator" : ""))
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                    Spacer()
                                    Text(Fmt.bytes(item.size))
                                        .font(Theme.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                        .buttonStyle(QuietButtonStyle())
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.raised.opacity(0.38))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else if job.working {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(job.status).font(Theme.caption) }
                    } else {
                        Text("No related preference, cache or support files were found.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    HStack(spacing: 10) {
                        Button("Uninstall and move to Trash") { confirm = true }
                            .buttonStyle(PrimaryButtonStyle(tint: Theme.danger))
                            .disabled(job.working)
                        if let error = job.error { Text(error).font(Theme.caption).foregroundStyle(Theme.danger) }
                        if !job.status.isEmpty && !job.working {
                            Text(job.status).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    Text("The app is quit first. Files go to the Trash so you can put them back; nothing is deleted permanently. Administrator-owned system files are listed but never removed by Nookit.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .alert("Uninstall \(app?.deletingPathExtension().lastPathComponent ?? "this app")?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { uninstall() }
        } message: {
            Text("The app and \(selected.count) related item\(selected.count == 1 ? "" : "s") will be moved to the Trash. You can restore them until the Trash is emptied.")
        }
    }

    private var selectedSize: Int64 {
        leftovers.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    private func icon(_ kind: String) -> String {
        if kind.contains("Preference") { return "slider.horizontal.3" }
        if kind.contains("Cache") { return "internaldrive" }
        if kind.contains("Container") { return "shippingbox" }
        if kind.contains("Launch") { return "bolt" }
        if kind.contains("Log") { return "doc.text" }
        return "folder"
    }

    private func load(_ url: URL) {
        scanTask?.cancel()
        app = url
        bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
        version = Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        signer = ""
        leftovers = []
        selected = []
        job.begin("Reading the app…")
        scanTask = Task {
            let info = await AppInfo.signer(for: url)
            if Task.isCancelled { return }
            await MainActor.run {
                signer = [info.authority, info.team.isEmpty ? "" : "Team \(info.team)"].filter { !$0.isEmpty }.joined(separator: " · ")
                if signer.isEmpty { signer = "Unsigned or signature unreadable" }
            }
            let target = url
            let identifier = bundleID
            let found = await Task.detached(priority: .userInitiated) {
                ScanLeftovers.find(url: target, bundleID: identifier)
            }.value
            if Task.isCancelled { return }
            await MainActor.run {
                leftovers = found
                selected = Set(found.filter { !$0.adminOnly }.map(\.url))
                job.finish([], "Found \(found.count) related item\(found.count == 1 ? "" : "s").")
            }
        }
    }

    private func uninstall() {
        guard let app else { return }
        let bundleID = self.bundleID
        let targets = leftovers.filter { selected.contains($0.url) }
        job.begin("Quitting the app…")
        Task {
            if !bundleID.isEmpty,
               let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                running.terminate()
                for _ in 0..<20 where !running.isTerminated {
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
            var moved = 0
            var failed: [String] = []
            for target in targets {
                do {
                    try FileManager.default.trashItem(at: target.url, resultingItemURL: nil)
                    moved += 1
                } catch {
                    failed.append(target.url.lastPathComponent)
                }
            }
            do {
                try FileManager.default.trashItem(at: app, resultingItemURL: nil)
                moved += 1
            } catch {
                failed.append(app.lastPathComponent)
            }
            await MainActor.run {
                job.finish([], failed.isEmpty
                    ? "Moved \(moved) item\(moved == 1 ? "" : "s") to the Trash."
                    : "Moved \(moved) items. Could not move: \(failed.joined(separator: ", ")).")
                self.app = nil
                leftovers = []
                selected = []
            }
        }
    }
}

// MARK: - Presentation mode

@MainActor
final class PresentationService: ObservableObject {
    static let shared = PresentationService()

    @Published var active = false
    @Published var hideDesktopIcons = true
    @Published var autohideDock = true
    @Published var keepAwake = true
    @Published var status = ""
    @Published var error: String?
    @Published var startedAt: Date?

    private var assertion: IOPMAssertionID = 0
    private var savedDockAutohide: Bool?
    private var savedDesktopIcons: Bool?

    private init() {
        active = false
    }

    private func defaultsRead(_ domain: String, _ key: String) -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", domain, key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text == "1" || text.lowercased() == "true" { return true }
            if text == "0" || text.lowercased() == "false" { return false }
            return nil
        } catch {
            return nil
        }
    }

    private func defaultsWrite(_ domain: String, _ key: String, _ value: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", domain, key, "-bool", value ? "true" : "false"]
        try? process.run()
        process.waitUntilExit()
    }

    private func restart(_ app: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = [app]
        try? process.run()
        process.waitUntilExit()
    }

    func activate() {
        guard !active else { return }
        error = nil
        savedDockAutohide = defaultsRead("com.apple.dock", "autohide")
        savedDesktopIcons = defaultsRead("com.apple.finder", "CreateDesktop")

        if hideDesktopIcons {
            defaultsWrite("com.apple.finder", "CreateDesktop", false)
            restart("Finder")
        }
        if autohideDock {
            defaultsWrite("com.apple.dock", "autohide", true)
            restart("Dock")
        }
        if keepAwake {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Nookit presentation mode" as CFString,
                &id
            )
            if result == kIOReturnSuccess {
                assertion = id
            } else {
                error = "macOS refused the sleep assertion. The display may still sleep."
            }
        }
        startedAt = Date()
        active = true
        status = "Presentation mode is on."
    }

    func restore() {
        guard active else { return }
        if let saved = savedDockAutohide {
            defaultsWrite("com.apple.dock", "autohide", saved)
            restart("Dock")
        }
        if let saved = savedDesktopIcons {
            defaultsWrite("com.apple.finder", "CreateDesktop", saved)
            restart("Finder")
        }
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
        active = false
        startedAt = nil
        status = "Everything is back the way it was."
    }
}

struct PresentationModeTool: View {
    @StateObject private var service = PresentationService.shared
    @State private var tick = Date()

    var body: some View {
        ToolPage(symbol: "person.crop.rectangle.badge.plus", title: "Presentation Mode", subtitle: "One switch before you share: clear the desktop, hide the Dock and stop the display from sleeping. Restore puts it all back.") {
            ToolCard(title: "What to change") {
                Toggle("Hide desktop icons", isOn: $service.hideDesktopIcons)
                    .toggleStyle(.switch)
                Toggle("Auto-hide the Dock", isOn: $service.autohideDock)
                    .toggleStyle(.switch)
                Toggle("Keep the display awake", isOn: $service.keepAwake)
                    .toggleStyle(.switch)
                Text("The current Dock and desktop settings are remembered when you start, then written back exactly when you restore.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 10) {
                    if service.active {
                        Button("Restore everything") { service.restore() }
                            .buttonStyle(PrimaryButtonStyle())
                        Text(elapsedText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Button("Start presentation mode") { service.activate() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Spacer()
                }
                if !service.status.isEmpty {
                    Text(service.status).font(Theme.caption).foregroundStyle(Theme.textSecondary)
                }
                if let error = service.error { InlineError(message: error) }
            }

            ToolCard(title: "Focus") {
                Text("macOS does not give apps a supported way to switch Focus on and off silently. If you make a Shortcut named “Nookit Focus” that sets the Focus you want, Nookit can run it from the notch. Until then, use Control Centre.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                Button("Open Focus settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")!)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in tick = date }
    }

    private var elapsedText: String {
        guard let started = service.startedAt else { return "" }
        let seconds = Int(tick.timeIntervalSince(started))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Clean keyboard

@MainActor
final class KeyboardShield: ObservableObject {
    static let shared = KeyboardShield()

    @Published var active = false
    @Published var remaining = 0
    let total: Int = 60

    private var windows: [NSWindow] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?

    func start(seconds: Int) {
        guard !active else { return }
        guard CGPreflightListenEventAccess() || CGRequestListenEventAccess() else {
            NotificationCenter.default.post(name: .nookitKeyboardShieldDenied, object: nil)
            return
        }
        guard AXIsProcessTrusted() else {
            NotificationCenter.default.post(name: .nookitKeyboardShieldDenied, object: nil)
            return
        }
        active = true
        remaining = seconds
        showOverlays()

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon { Unmanaged<KeyboardShield>.fromOpaque(refcon).takeUnretainedValue().reenable() }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown {
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                if code == 53 && flags.contains([.maskControl, .maskAlternate, .maskCommand]) {
                    DispatchQueue.main.async { KeyboardShield.shared.stop() }
                    return Unmanaged.passUnretained(event)
                }
            }
            return nil
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            active = false
            hideOverlays()
            NotificationCenter.default.post(name: .nookitKeyboardShieldDenied, object: nil)
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.remaining <= 1 {
                    self.stop()
                } else {
                    self.remaining -= 1
                }
            }
        }
    }

    func stop() {
        guard active else { return }
        timer?.invalidate()
        timer = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        active = false
        hideOverlays()
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func showOverlays() {
        hideOverlays()
        for screen in NSScreen.screens {
            let window = ShieldWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = true
            window.backgroundColor = .black
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = false
            let view = NSHostingView(rootView: KeyboardShieldOverlay(shield: self))
            view.frame = CGRect(origin: .zero, size: screen.frame.size)
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSCursor.hide()
    }

    private func hideOverlays() {
        for window in windows { window.orderOut(nil) }
        windows = []
        NSCursor.unhide()
    }
}

extension Notification.Name {
    static let nookitKeyboardShieldDenied = Notification.Name("NookitKeyboardShieldDenied")
}

private final class ShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct KeyboardShieldOverlay: View {
    @ObservedObject var shield: KeyboardShield

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard")
                .font(.system(size: 42, weight: .thin))
                .foregroundStyle(Color.white.opacity(0.55))
            Text("Keyboard paused")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(String(format: "%d:%02d", shield.remaining / 60, shield.remaining % 60))
                .font(.system(size: 54, weight: .light, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
            Text("Wipe the keys and the screen. Click Stop or press ⌃⌥⌘Esc when you are done.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.55))
            Button("Stop") { shield.stop() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.white)
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

struct CleanKeyboardTool: View {
    @StateObject private var shield = KeyboardShield.shared
    @State private var duration = 60
    @State private var denied = false

    var body: some View {
        ToolPage(symbol: "keyboard", title: "Clean Keyboard", subtitle: "Pause every key for a minute so you can wipe the keyboard without typing nonsense into whatever is open.") {
            ToolCard(title: "Pause input") {
                OptionPicker(label: "For", options: [( "30 seconds", 30), ("1 minute", 60), ("2 minutes", 120), ("5 minutes", 300)], selection: $duration)
                Text("Nookit covers every display with black and swallows keyboard events while the timer runs. The mouse keeps working so you can press Stop.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    Button("Start cleaning mode") { shield.start(seconds: duration) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(shield.active)
                    if shield.active {
                        Button("Stop") { shield.stop() }.buttonStyle(SecondaryButtonStyle())
                    }
                    Spacer()
                }
                Text("Input Monitoring and Accessibility permissions are required to intercept keys. Nookit asks the first time.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                if denied {
                    InlineError(message: "Keyboard access isn’t allowed. Enable Nookit in System Settings → Privacy & Security → Input Monitoring and Accessibility, then try again.")
                    Button("Open Privacy settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nookitKeyboardShieldDenied)) { _ in denied = true }
    }
}

// MARK: - Dead pixel test

@MainActor
final class PixelTestController {
    static let shared = PixelTestController()
    private var windows: [NSWindow] = []
    private var monitor: Any?
    private var index = 0
    private let colors: [(String, NSColor)] = [
        ("Red", .systemRed), ("Green", .systemGreen), ("Blue", .systemBlue),
        ("White", .white), ("Black", .black), ("Grey", NSColor(white: 0.5, alpha: 1)),
        ("Cyan", .cyan), ("Magenta", .magenta), ("Yellow", .yellow)
    ]

    func start() {
        guard windows.isEmpty else { return }
        index = 0
        for screen in NSScreen.screens {
            let window = ShieldWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = true
            window.backgroundColor = .black
            let view = PixelView(color: colors[index].1, title: colors[index].0) { [weak self] step in
                self?.advance(step)
            }
            view.frame = CGRect(origin: .zero, size: screen.frame.size)
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.stop()
                return nil
            }
            if event.keyCode == 123 {
                self.advance(-1)
            } else {
                self.advance(1)
            }
            return nil
        }
        NSCursor.hide()
    }

    func advance(_ step: Int) {
        guard !windows.isEmpty else { return }
        index = (index + step + colors.count) % colors.count
        let colour = colors[index]
        for window in windows {
            (window.contentView as? PixelView)?.update(color: colour.1, title: colour.0)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for window in windows { window.orderOut(nil) }
        windows = []
        NSCursor.unhide()
    }
}

final class PixelView: NSView {
    private var color: NSColor
    private var title: String
    private let onStep: (Int) -> Void

    init(color: NSColor, title: String, onStep: @escaping (Int) -> Void) {
        self.color = color
        self.title = title
        self.onStep = onStep
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(color: NSColor, title: String) {
        self.color = color
        self.title = title
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
        let textColor: NSColor = color == .black || color == .systemBlue ? .white : .black
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: textColor.withAlphaComponent(0.65)
        ]
        let text = "\(title) · click to change · Esc to finish"
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: 18, y: bounds.height - size.height - 16), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) { onStep(1) }
    override func rightMouseDown(with event: NSEvent) { onStep(-1) }
}

struct DeadPixelTestTool: View {
    @State private var running = false

    var body: some View {
        ToolPage(symbol: "display", title: "Dead Pixel Test", subtitle: "Fill every display with solid colours to spot dead, stuck or hot pixels, backlight bleed and uneven brightness.") {
            ToolCard(title: "Test") {
                Text("The test appears on every attached display at once. Click or press any key for the next colour, right-click for the previous one, and press Escape to finish.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                Button("Start full-screen test") {
                    running = true
                    PixelTestController.shared.start()
                }
                .buttonStyle(PrimaryButtonStyle())
                Text("Colours: red, green, blue, white, black, grey, cyan, magenta, yellow.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .onDisappear {
            if running { PixelTestController.shared.stop() }
        }
    }
}

// MARK: - Login items

struct LoginEntry: Identifiable {
    var id: String { label + kind.rawValue + path }
    let label: String
    let detail: String
    let path: String
    let developer: String
    let kind: Kind
    let enabled: Bool
    let canToggle: Bool

    enum Kind: String { case loginItem = "Login item", agent = "Launch agent", daemon = "Launch daemon" }
}

enum LoginItemsService {
    static func scan(status: @escaping (String) -> Void) async -> [LoginEntry] {
        var entries: [LoginEntry] = []
        status("Reading launch agents…")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders: [(URL, Bool)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), true),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), false),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), false)
        ]
        for (folder, userOwned) in folders {
            guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: file),
                      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { continue }
                let label = plist["Label"] as? String ?? file.deletingPathExtension().lastPathComponent
                let program = plist["Program"] as? String
                    ?? (plist["ProgramArguments"] as? [String])?.first
                    ?? "No program listed"
                let loaded = await isLoaded(label: label, user: userOwned)
                let developer = await developerName(for: program)
                entries.append(LoginEntry(
                    label: label,
                    detail: program,
                    path: file.path,
                    developer: developer,
                    kind: userOwned ? .agent : .daemon,
                    enabled: loaded,
                    canToggle: userOwned
                ))
            }
        }

        status("Reading login items…")
        let script = "tell application \"System Events\" to get the name of every login item"
        if let result = try? await Shell.run("/usr/bin/osascript", ["-e", script], timeout: 8), result.succeeded {
            let names = result.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for name in names {
                entries.append(LoginEntry(
                    label: name,
                    detail: "Login item managed by System Events",
                    path: "",
                    developer: "",
                    kind: .loginItem,
                    enabled: true,
                    canToggle: true
                ))
            }
        }
        return entries.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    static func isLoaded(label: String, user: Bool) async -> Bool {
        let uid = getuid()
        let target = user ? "gui/\(uid)/\(label)" : "system/\(label)"
        guard let result = try? await Shell.run("/bin/launchctl", ["print", target], timeout: 4) else { return false }
        return result.succeeded
    }

    static func developerName(for program: String) async -> String {
        guard program.hasPrefix("/") else { return "" }
        guard let result = try? await Shell.run("/usr/bin/codesign", ["-dv", "--verbose=2", program], timeout: 6) else { return "" }
        let text = (result.stderr) + (result.stdout)
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("Authority=") {
                return line.replacingOccurrences(of: "Authority=", with: "")
            }
        }
        return ""
    }

    static func set(_ entry: LoginEntry, enabled: Bool) async -> String? {
        if entry.kind == .loginItem {
            let escaped = entry.label.replacingOccurrences(of: "\"", with: "\\\"")
            let command = enabled
                ? "tell application \"System Events\" to make login item at end with properties {name:\"\(escaped)\", path:\"\"}"
                : "tell application \"System Events\" to delete login item \"\(escaped)\""
            guard let result = try? await Shell.run("/usr/bin/osascript", ["-e", command], timeout: 10) else {
                return "The login item couldn’t be changed."
            }
            return result.succeeded ? nil : (result.stderr.isEmpty ? "The login item couldn’t be changed." : result.stderr)
        }
        guard entry.canToggle else { return "System launch items need administrator access." }
        let uid = getuid()
        if enabled {
            let result = try? await Shell.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", entry.path], timeout: 10)
            if result?.succeeded == true { return nil }
            return result?.stderr.isEmpty == false ? result?.stderr : "launchctl could not enable that agent."
        } else {
            let result = try? await Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", entry.path], timeout: 10)
            if result?.succeeded == true { return nil }
            return result?.stderr.isEmpty == false ? result?.stderr : "launchctl could not disable that agent."
        }
    }
}

struct LoginItemsTool: View {
    @StateObject private var job = JobState()
    @State private var entries: [LoginEntry] = []
    @State private var pendingRemoval: LoginEntry?

    var body: some View {
        ToolPage(symbol: "list.bullet.rectangle.portrait", title: "Login & Background Items", subtitle: "See what starts with your Mac: login items, user launch agents and system daemons, with the signer of each program.") {
            ToolCard(title: "Startup items") {
                HStack(spacing: 10) {
                    Button(job.working ? "Reading…" : "Refresh") { load() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(job.working)
                    Button("Open Login Items settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                }
                if job.working {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(job.status).font(Theme.caption) }
                }
                if let error = job.error { InlineError(message: error) }
                if entries.isEmpty && !job.working {
                    Text("Press Refresh to read the startup items. macOS may ask for permission to control System Events for login items.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(spacing: 1) {
                        ForEach(entries) { entry in
                            HStack(spacing: 9) {
                                Image(systemName: entry.kind == .loginItem ? "person.crop.circle" : entry.enabled ? "bolt.fill" : "bolt.slash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(entry.enabled ? Theme.mint : Theme.textTertiary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.label)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .lineLimit(1)
                                    Text([entry.kind.rawValue, entry.developer.isEmpty ? nil : entry.developer].compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(Theme.textTertiary)
                                        .lineLimit(1)
                                    if !entry.detail.isEmpty {
                                        Text(entry.detail)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(Theme.textTertiary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if entry.canToggle {
                                    Toggle("", isOn: Binding(
                                        get: { entry.enabled },
                                        set: { value in
                                            if entry.kind == .loginItem && !value {
                                                pendingRemoval = entry
                                            } else {
                                                update(entry, enabled: value)
                                            }
                                        }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                } else {
                                    Text("Administrator")
                                        .font(Theme.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.raised.opacity(0.38))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text("Turning off a launch agent stops it now and keeps the file, so it can be turned back on. Removing a login item does not delete the app.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .alert("Remove “\(pendingRemoval?.label ?? "")” from login items?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
            Button("Remove", role: .destructive) {
                if let entry = pendingRemoval { update(entry, enabled: false) }
                pendingRemoval = nil
            }
        } message: {
            Text("The app stays installed; it will simply stop opening at login.")
        }
        .task { load() }
    }

    private func load() {
        job.begin("Reading startup items…")
        entries = []
        Task {
            let found = await LoginItemsService.scan { text in
                Task { @MainActor in job.note(text) }
            }
            await MainActor.run {
                entries = found
                job.finish([], found.isEmpty ? "No startup items were found." : "Found \(found.count) startup item\(found.count == 1 ? "" : "s").")
            }
        }
    }

    private func update(_ entry: LoginEntry, enabled: Bool) {
        Task {
            let error = await LoginItemsService.set(entry, enabled: enabled)
            await MainActor.run {
                if let error {
                    job.fail(error)
                } else if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                    let current = entries[index]
                    entries[index] = LoginEntry(label: current.label, detail: current.detail, path: current.path, developer: current.developer, kind: current.kind, enabled: enabled, canToggle: current.canToggle)
                    job.finish([], enabled ? "Turned on \(current.label)." : "Turned off \(current.label).")
                }
            }
        }
    }
}

// MARK: - Fix app damaged

struct FixAppDamagedTool: View {
    @StateObject private var job = JobState()
    @State private var app: URL?
    @State private var authority = ""
    @State private var team = ""
    @State private var verified = false
    @State private var assessment = ""
    @State private var quarantine = ""
    @State private var confirm = false

    var body: some View {
        ToolPage(symbol: "checkmark.shield", title: "Fix “App Is Damaged”", subtitle: "See who signed an app, check its signature, then remove the download quarantine only when you decide it is safe.") {
            DropZone(title: "Choose the app macOS refuses to open", subtitle: "Drag it from Applications.", allowsMultiple: false, types: [.application]) { urls in
                if let url = urls.first { inspect(url) }
            }
            HStack {
                Button("Choose application…") {
                    if let url = FilePicker.files(title: "Choose an application", types: [.application], allowsMultiple: false).first {
                        inspect(url)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                if let app {
                    Spacer()
                    Text(app.path).font(Theme.caption).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
            }

            if let app {
                ToolCard(title: app.deletingPathExtension().lastPathComponent) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authority.isEmpty ? "No signing authority found" : authority)
                                .font(.system(size: 12.5, weight: .medium))
                            Text(team.isEmpty ? "No team identifier" : "Team \(team)")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Text(verified ? "Signature verifies" : "Signature does not verify")
                                .font(Theme.caption)
                                .foregroundStyle(verified ? Theme.mint : Theme.danger)
                        }
                    }
                    if !assessment.isEmpty {
                        Text(assessment)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                    if quarantine.isEmpty {
                        Text("No com.apple.quarantine attribute is set. If the app still won’t open, check Privacy & Security → Security for a blocked-software message.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("Quarantine attributes")
                            .font(.system(size: 11, weight: .semibold))
                        Text(quarantine)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                            .lineLimit(4)
                        Button("Remove quarantine and open permissions") { confirm = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Text("Removing quarantine lowers a macOS protection for this app. Only do it for software you trust and whose signature matches the developer you expect.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                    if let error = job.error { InlineError(message: error) }
                    if !job.status.isEmpty { Text(job.status).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                }
            }
        }
        .alert("Remove the quarantine flag?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { removeQuarantine() }
        } message: {
            Text("Nookit will run xattr -dr com.apple.quarantine on this app only. The signature is not changed.")
        }
    }

    private func inspect(_ url: URL) {
        app = url
        job.begin("Checking the signature…")
        Task {
            let info = await AppInfo.signer(for: url)
            let xattr = try? await Shell.run("/usr/bin/xattr", ["-l", url.path])
            await MainActor.run {
                authority = info.authority
                team = info.team
                verified = info.verified
                assessment = info.assessment
                quarantine = (xattr?.stdout ?? "").components(separatedBy: .newlines)
                    .filter { $0.contains("quarantine") }
                    .joined(separator: "\n")
                job.finish([], "")
            }
        }
    }

    private func removeQuarantine() {
        guard let app else { return }
        job.begin("Removing quarantine…")
        Task {
            let result = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
            let check = try? await Shell.run("/usr/bin/xattr", ["-l", app.path])
            await MainActor.run {
                if result?.succeeded == true {
                    quarantine = (check?.stdout ?? "").components(separatedBy: .newlines).filter { $0.contains("quarantine") }.joined(separator: "\n")
                    job.finish([], "Quarantine removed. Try opening the app now.")
                } else {
                    job.fail("Couldn’t remove the attribute. If the app lives in /Applications, macOS may require administrator rights. You can copy the command and run it in Terminal:\nsudo xattr -dr com.apple.quarantine \"\(app.path)\"")
                }
            }
        }
    }
}

// MARK: - Reset permissions

struct ResetPermissionsTool: View {
    @StateObject private var job = JobState()
    @State private var app: URL?
    @State private var bundleID = ""
    @State private var service: Service = .screen
    @State private var pending: Service?

    struct Service: Identifiable, Hashable {
        let label: String
        let id: String
        let detail: String
        static let all: [Service] = [
            Service(label: "Screen Recording", id: "ScreenCapture", detail: "Needed to record the screen or capture text."),
            Service(label: "Microphone", id: "Microphone", detail: "Needed for recording audio and dictation."),
            Service(label: "Camera", id: "Camera", detail: "Needed for the mirror preview."),
            Service(label: "Accessibility", id: "Accessibility", detail: "Needed to control other apps and intercept keys."),
            Service(label: "Input Monitoring", id: "ListenEvent", detail: "Needed to watch for global shortcuts and keyboard cleaning."),
            Service(label: "Full Disk Access", id: "SystemPolicyAllFiles", detail: "Needed to read protected folders."),
            Service(label: "Contacts", id: "AddressBook", detail: "Needed when a tool reads contacts."),
            Service(label: "Calendars", id: "Calendar", detail: "Needed for the calendar module."),
            Service(label: "Reminders", id: "Reminders", detail: "Needed for the reminders module."),
            Service(label: "Photos", id: "Photos", detail: "Needed when saving into the Photos library."),
            Service(label: "Automation (all apps)", id: "AppleEvents", detail: "Resets automation grants for every target app.")
        ]
        static let screen = all[0]
    }

    var body: some View {
        ToolPage(symbol: "hand.raised", title: "Reset Permissions", subtitle: "Make macOS ask again for one app’s privacy access. Useful after a denied prompt or a confusing first run.") {
            ToolCard(title: "Which app?") {
                HStack(spacing: 10) {
                    Button("Choose application…") {
                        if let url = FilePicker.files(title: "Choose an application", types: [.application], allowsMultiple: false).first {
                            app = url
                            bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
                            job.clear()
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if let app { FileChip(url: app) }
                    Spacer()
                }
                if !bundleID.isEmpty {
                    Text(bundleID).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
                OptionPicker(label: "Permission", options: Service.all.map { ($0.label, $0) }, selection: $service)
                Text(service.detail).font(Theme.caption).foregroundStyle(Theme.textTertiary)
                HStack(spacing: 10) {
                    Button("Reset \(service.label)") { pending = service }
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.danger))
                        .disabled(bundleID.isEmpty)
                    Button("Open Privacy settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                }
                Text("Resetting a grant makes the next request show the system prompt again. Quit and reopen the app afterwards so it asks cleanly.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                if let error = job.error { InlineError(message: error) }
                if !job.status.isEmpty { Text(job.status).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
            }
        }
        .alert("Reset \(pending?.label ?? "") for \(bundleID)?", isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        )) {
            Button("Cancel", role: .cancel) { pending = nil }
            Button("Reset", role: .destructive) {
                if let pending { reset(pending) }
                pending = nil
            }
        } message: {
            Text("This does not revoke access for other apps. The chosen app may need to be quit and reopened.")
        }
    }

    private func reset(_ service: Service) {
        guard !bundleID.isEmpty else { return }
        job.begin("Asking macOS to forget the grant…")
        Task {
            let result = try? await Shell.run("/usr/bin/tccutil", ["reset", service.id, bundleID], timeout: 20)
            await MainActor.run {
                if result?.succeeded == true {
                    job.finish([], "Reset \(service.label) for \(bundleID). Quit and reopen that app.")
                } else {
                    let message = (result?.stdout ?? "") + (result?.stderr ?? "")
                    job.fail(message.isEmpty ? "macOS did not reset that permission. Some permissions can only be changed in System Settings." : message)
                }
            }
        }
    }
}

// MARK: - Hidden settings

struct HiddenSettingsTool: View {
    @StateObject private var job = JobState()
    @State private var values: [String: Bool] = [:]
    @State private var screenshotFolder = ""
    @State private var pendingReset = false

    struct Row: Identifiable {
        let id: String
        let title: String
        let detail: String
        let domain: String
        let key: String
        let defaultValue: Bool
        let group: String
        let restart: String?
    }

    private let rows: [Row] = [
        Row(id: "finder-hidden", title: "Show hidden files", detail: "Makes dotfiles and ~/Library visible in Finder. Useful, and easy to turn back off.", domain: "com.apple.finder", key: "AppleShowAllFiles", defaultValue: false, group: "Finder", restart: "Finder"),
        Row(id: "finder-path", title: "Show the path bar", detail: "Adds the breadcrumb path at the bottom of Finder windows.", domain: "com.apple.finder", key: "ShowPathbar", defaultValue: false, group: "Finder", restart: "Finder"),
        Row(id: "finder-status", title: "Show the status bar", detail: "Shows item counts and free space at the bottom of Finder windows.", domain: "com.apple.finder", key: "ShowStatusBar", defaultValue: false, group: "Finder", restart: "Finder"),
        Row(id: "finder-ext", title: "Show all filename extensions", detail: "Makes .pdf, .jpg and friends visible everywhere, not just in Get Info.", domain: "com.apple.finder", key: "AppleShowAllExtensions", defaultValue: false, group: "Finder", restart: "Finder"),
        Row(id: "finder-folders", title: "Keep folders on top", detail: "Sorts folders before files in Finder windows.", domain: "com.apple.finder", key: "_FXSortFoldersFirst", defaultValue: false, group: "Finder", restart: "Finder"),
        Row(id: "finder-warning", title: "Warn before changing an extension", detail: "Keeps the safety prompt that stops a rename from breaking a file.", domain: "com.apple.finder", key: "FXEnableExtensionChangeWarning", defaultValue: true, group: "Finder", restart: "Finder"),
        Row(id: "finder-quit", title: "Allow quitting Finder", detail: "Adds Quit to Finder’s menu. The desktop comes back when Finder relaunches.", domain: "com.apple.finder", key: "QuitMenuItem", defaultValue: false, group: "Finder", restart: "Finder"),
        Row(id: "dock-autohide", title: "Auto-hide the Dock", detail: "Gives windows the full screen until you move the pointer to the edge.", domain: "com.apple.dock", key: "autohide", defaultValue: false, group: "Dock", restart: "Dock"),
        Row(id: "dock-recents", title: "Show recent apps in the Dock", detail: "The recent-applications stack on the right side of the Dock.", domain: "com.apple.dock", key: "show-recents", defaultValue: true, group: "Dock", restart: "Dock"),
        Row(id: "dock-minimize", title: "Minimise windows into the app icon", detail: "Minimised windows tuck into their app’s Dock icon instead of a separate thumbnail.", domain: "com.apple.dock", key: "minimize-to-application", defaultValue: false, group: "Dock", restart: "Dock"),
        Row(id: "text-capitalise", title: "Automatic capitalisation", detail: "Capitalises the first word of a sentence in native text fields.", domain: "NSGlobalDomain", key: "NSAutomaticCapitalizationEnabled", defaultValue: true, group: "Typing", restart: nil),
        Row(id: "text-correct", title: "Automatic spelling correction", detail: "Replaces misspellings as you type in native text fields.", domain: "NSGlobalDomain", key: "NSAutomaticSpellingCorrectionEnabled", defaultValue: true, group: "Typing", restart: nil),
        Row(id: "text-quotes", title: "Smart quotes", detail: "Turns straight quotes into curly typographic quotes.", domain: "NSGlobalDomain", key: "NSAutomaticQuoteSubstitutionEnabled", defaultValue: true, group: "Typing", restart: nil),
        Row(id: "text-dashes", title: "Smart dashes", detail: "Turns double hyphens into em dashes.", domain: "NSGlobalDomain", key: "NSAutomaticDashSubstitutionEnabled", defaultValue: true, group: "Typing", restart: nil),
        Row(id: "anim-windows", title: "Window animations", detail: "Turning animations off makes windows appear instantly, which feels faster on older Macs.", domain: "NSGlobalDomain", key: "NSAutomaticWindowAnimationsEnabled", defaultValue: true, group: "Animation", restart: nil)
    ]

    private var groups: [String] {
        var order: [String] = []
        for row in rows where !order.contains(row.group) { order.append(row.group) }
        return order
    }

    var body: some View {
        ToolPage(symbol: "slider.horizontal.3", title: "Hidden Settings", subtitle: "Useful switches that never made it into System Settings, with a plain-English explanation and a one-click way back.") {
            ForEach(groups, id: \.self) { group in
                ToolCard(title: group) {
                    VStack(spacing: 1) {
                        ForEach(rows.filter { $0.group == group }) { row in
                            Toggle(isOn: Binding(
                                get: { values[row.id] ?? row.defaultValue },
                                set: { newValue in
                                    values[row.id] = newValue
                                    apply(row, value: newValue)
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).font(.system(size: 12, weight: .medium))
                                    Text(row.detail).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.raised.opacity(0.35))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            ToolCard(title: "Screenshots") {
                HStack(spacing: 10) {
                    Text(screenshotFolder.isEmpty ? "Desktop (macOS default)" : screenshotFolder)
                        .font(.system(size: 11.5, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button("Choose folder…") {
                        if let folder = FilePicker.folder(title: "Where should screenshots go?") {
                            screenshotFolder = folder.path
                            setScreenshotLocation(folder)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Desktop") { resetScreenshots() }
                        .buttonStyle(QuietButtonStyle())
                }
            }

            ToolCard(title: "Start over") {
                Text("Resets only the switches shown on this page. Other settings are left alone.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    Button("Restore macOS defaults") { pendingReset = true }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    if !job.status.isEmpty { Text(job.status).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                }
                if let error = job.error { InlineError(message: error) }
            }
        }
        .task { load() }
        .alert("Restore these settings to their defaults?", isPresented: $pendingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) { resetAll() }
        } message: {
            Text("Finder and the Dock will restart. Open windows are restored by macOS.")
        }
    }

    private func read(_ domain: String, _ key: String) -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", domain, key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if text == "1" || text == "true" || text == "yes" { return true }
            if text == "0" || text == "false" || text == "no" { return false }
            return nil
        } catch {
            return nil
        }
    }

    private func write(_ domain: String, _ key: String, _ value: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", domain, key, "-bool", value ? "true" : "false"]
        try? process.run()
        process.waitUntilExit()
    }

    private func load() {
        var loaded: [String: Bool] = [:]
        for row in rows {
            loaded[row.id] = read(row.domain, row.key) ?? row.defaultValue
        }
        values = loaded
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "com.apple.screencapture", "location"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        if (try? process.run()) != nil {
            process.waitUntilExit()
            screenshotFolder = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    private func apply(_ row: Row, value: Bool) {
        write(row.domain, row.key, value)
        if let app = row.restart {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [app]
            try? process.run()
            process.waitUntilExit()
        }
        job.finish([], "\(row.title) is now \(value ? "on" : "off").")
    }

    private func resetAll() {
        for row in rows {
            write(row.domain, row.key, row.defaultValue)
            values[row.id] = row.defaultValue
        }
        resetScreenshots()
        for app in ["Finder", "Dock"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [app]
            try? process.run()
            process.waitUntilExit()
        }
        job.finish([], "Restored the macOS defaults for these switches.")
    }

    private func setScreenshotLocation(_ folder: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.screencapture", "location", folder.path]
        try? process.run()
        process.waitUntilExit()
        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        restart.arguments = ["SystemUIServer"]
        try? restart.run()
        restart.waitUntilExit()
        job.finish([], "New screenshots will be saved to \(folder.path).")
    }

    private func resetScreenshots() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["delete", "com.apple.screencapture", "location"]
        try? process.run()
        process.waitUntilExit()
        screenshotFolder = ""
        job.finish([], "Screenshots will go back to the Desktop.")
    }
}
