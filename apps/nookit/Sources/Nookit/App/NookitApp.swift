import SwiftUI
import AppKit

@main
struct NookitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var appState = AppState()
    @StateObject private var store = ResultStore.shared
    @StateObject private var notch = NotchController()
    @ObservedObject private var keepAwake = KeepAwakeService.shared
    @ObservedObject private var notchSettings = NotchSettings.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            DashboardView()
                .environmentObject(appState)
                .environmentObject(store)
                .frame(minWidth: 940, minHeight: 640)
                .navigationTitle("Nookit")
                .task {
                    QuickLauncher.shared.attach(app: appState)
                    notch.start()
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Search Tools…") {
                    appState.openCategory(nil)
                    appState.requestSearchFocus()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Quick Launcher…") {
                    QuickLauncher.shared.toggle()
                }
                .keyboardShortcut(.space, modifiers: [.control, .option])

                Button("Toggle Notch") {
                    notchSettings.enabled.toggle()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }

            CommandMenu("Tools") {
                Button("Nookit AI…") {
                    openAIChat()
                }
                .keyboardShortcut("a", modifiers: [.command, .option])

                Button("Hype…") {
                    openHype()
                }
                .keyboardShortcut("h", modifiers: [.command, .option])

                Menu("Apps") {
                    ForEach(GoogleApp.allCases) { item in
                        Button(item.fullName) {
                            openApps(item)
                        }
                    }
                }

                Divider()

                ForEach(quickTools, id: \.slug) { tool in
                    Button(tool.name) {
                        open(tool.slug)
                    }
                }
                Divider()
                Button("Clipboard History") {
                    openNotchModule(.clipboard)
                }
                Button("Keep Awake for 30 Minutes") {
                    keepAwake.start(minutes: 30)
                }
                if keepAwake.active {
                    Button("Stop Keep Awake") {
                        keepAwake.stop()
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarContent(app: appState, notch: notch)
                .environmentObject(appState)
                .environmentObject(store)
        } label: {
            Image(systemName: keepAwake.active ? "cup.and.saucer.fill" : "n.square")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(store)
        }
    }

    private var quickTools: [ToolItem] {
        ["json-formatter", "base64", "hash-generator", "qr-code"].compactMap { appState.catalog.tool(slug: $0) }
    }

    private func open(_ slug: String) {
        appState.openTool(slug)
        appState.runTool(slug)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func openNotchModule(_ module: NotchModule) {
        notchSettings.enabled = true
        notch.model.activate(module)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openAIChat() {
        appState.openAIChat()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func openHype() {
        appState.openHype()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func openApps(_ app: GoogleApp) {
        appState.openApps(app)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = nil
        if ProcessInfo.processInfo.environment["NOOKIT_SMOKE"] == "1" {
            runSmokeTest()
        }
        if ProcessInfo.processInfo.environment["NOOKIT_AUDIT"] == "1" {
            runRenderAudit()
        }
        if ProcessInfo.processInfo.environment["NOOKIT_TEST"] == "1" {
            FunctionalTests.run()
        }
    }

    /// Headless-ish render check: `NOOKIT_SMOKE=1 ./Nookit` renders every
    /// registered tool view and exits. Used during development to catch missing
    /// environment objects or views that trap while building their body.
    private func runSmokeTest() {
        DispatchQueue.main.async {
            let catalog = CatalogStore.shared
            let app = AppState(catalog: catalog)
            var rendered = 0
            var missing: [String] = []
            for tool in catalog.tools where tool.implemented {
                guard let view = ToolRegistry.shared.view(for: tool.slug) else {
                    missing.append(tool.slug)
                    continue
                }
                let host = NSHostingView(rootView: view
                    .environmentObject(app)
                    .environmentObject(ResultStore.shared))
                host.frame = NSRect(x: 0, y: 0, width: 980, height: 720)
                host.layoutSubtreeIfNeeded()
                rendered += 1
            }
            print("NOOKIT_SMOKE rendered=\(rendered) missing=\(missing.joined(separator: ","))")
            NSApp.terminate(nil)
        }
    }

    /// Render audit: `NOOKIT_AUDIT=1 ./Nookit` builds every tool, gives SwiftUI a
    /// frame, renders it offscreen to a PNG, and flags blank or collapsed screens.
    private func runRenderAudit() {
        DispatchQueue.main.async {
            let catalog = CatalogStore.shared
            let app = AppState(catalog: catalog)
            let folder = URL(fileURLWithPath: "/tmp/nookit-audit", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var rendered = 0
            var blank: [String] = []
            var missing: [String] = []
            var short: [String] = []
            for tool in catalog.tools where tool.implemented {
                guard let view = ToolRegistry.shared.view(for: tool.slug) else {
                    missing.append(tool.slug)
                    continue
                }
                let host = NSHostingView(rootView: view
                    .environmentObject(app)
                    .environmentObject(ResultStore.shared))
                let size = NSSize(width: 980, height: 720)
                host.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(
                    contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.contentView = host
                window.orderFrontRegardless()
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.08))
                if host.fittingSize.height < 80 { short.append(tool.slug) }
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    var buckets = Set<Int>()
                    let columns = 48
                    let rows = 36
                    for row in 0..<rows {
                        for column in 0..<columns {
                            let x = min(rep.pixelsWide - 1, column * rep.pixelsWide / columns)
                            let y = min(rep.pixelsHigh - 1, row * rep.pixelsHigh / rows)
                            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                            let red = Int(color.redComponent * 15)
                            let green = Int(color.greenComponent * 15)
                            let blue = Int(color.blueComponent * 15)
                            buckets.insert((red << 8) | (green << 4) | blue)
                        }
                    }
                    if buckets.count < 3 { blank.append(tool.slug) }
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: folder.appendingPathComponent("\(tool.slug).png"))
                    }
                } else {
                    blank.append(tool.slug)
                }
                window.orderOut(nil)
                window.contentView = nil
                rendered += 1
            }
            print("NOOKIT_AUDIT rendered=\(rendered) missing=\(missing.joined(separator: ",")) blank=\(blank.joined(separator: ",")) short=\(short.joined(separator: ","))")
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeepAwakeService.shared.stop()
        AIChatService.shared.persistNow()
    }
}

// MARK: - Menu bar

struct MenuBarContent: View {
    @ObservedObject var app: AppState
    @ObservedObject var notch: NotchController
    @ObservedObject private var keepAwake = KeepAwakeService.shared
    @ObservedObject private var notchSettings = NotchSettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Nookit") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Button("Nookit AI") {
            app.openAIChat()
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Button("Hype") {
            app.openHype()
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Menu("Apps") {
            ForEach(GoogleApp.allCases) { item in
                Button(item.fullName) {
                    app.openApps(item)
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
            }
        }

        Button(notchSettings.enabled ? "Hide Notch" : "Show Notch") {
            notchSettings.enabled.toggle()
        }

        Divider()

        if keepAwake.active {
            Text("Keep Awake — \(keepAwake.statusText)")
            Button("Stop Keeping Awake") { keepAwake.stop() }
        } else {
            Menu("Keep Awake") {
                Button("For 30 minutes") { keepAwake.start(minutes: 30) }
                Button("For 1 hour") { keepAwake.start(minutes: 60) }
                Button("For 2 hours") { keepAwake.start(minutes: 120) }
                Divider()
                Button("Until I stop it") { keepAwake.start(minutes: nil) }
            }
        }

        Divider()

        Menu("Quick Tools") {
            ForEach(quickTools, id: \.slug) { tool in
                Button(tool.name) { launch(tool.slug) }
            }
        }

        Button("Clipboard History") {
            notch.model.activate(.clipboard)
            notchSettings.enabled = true
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit Nookit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var quickTools: [ToolItem] {
        ["json-formatter", "base64", "clean-links", "uuid-generator"].compactMap { app.catalog.tool(slug: $0) }
    }

    private func launch(_ slug: String) {
        app.openTool(slug)
        app.runTool(slug)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
