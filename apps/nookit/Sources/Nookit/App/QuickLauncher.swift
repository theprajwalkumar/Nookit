import SwiftUI
import AppKit

/// A menu-bar-speed launcher for the whole catalogue. One shortcut from any app,
/// type a few letters, press return, and the tool opens in the main window.
@MainActor
final class QuickLauncher: ObservableObject {
    static let shared = QuickLauncher()

    @Published var query = ""
    @Published var selection = 0
    @Published private(set) var results: [ToolItem] = []

    private weak var app: AppState?
    private var panel: LauncherPanel?
    private var keyMonitor: Any?

    private init() {}

    func attach(app: AppState) {
        self.app = app
    }

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        guard let app else { return }
        query = ""
        selection = 0
        refresh()
        let panel = self.panel ?? buildPanel()
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
    }

    func updateQuery(_ value: String) {
        query = value
        selection = 0
        refresh()
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func openSelection() {
        guard results.indices.contains(selection), let tool = results[safe: selection] else { return }
        open(tool.slug)
    }

    func open(_ slug: String) {
        guard let app else { return }
        app.runTool(slug)
        hide()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func refresh() {
        guard let app else { return }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = app.catalog.tools
        if !needle.isEmpty {
            list = list.filter { tool in
                tool.name.lowercased().contains(needle)
                    || tool.tagline.lowercased().contains(needle)
                    || tool.slug.contains(needle)
                    || (app.catalog.category(id: tool.category)?.name.lowercased().contains(needle) ?? false)
            }
        } else {
            let recents = app.recentTools
            let rest = list.filter { tool in !recents.contains(where: { $0.slug == tool.slug }) }
            list = recents + rest
        }
        results = Array(list.prefix(10))
        if selection >= results.count { selection = max(0, results.count - 1) }
    }

    private func buildPanel() -> LauncherPanel {
        let panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.contentView = NSHostingView(rootView: QuickLauncherView(launcher: self))
        return panel
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isVisible == true else { return event }
            switch event.keyCode {
            case 53: // Escape
                self.hide()
                return nil
            case 125: // Down
                self.move(1)
                return nil
            case 126: // Up
                self.move(-1)
                return nil
            case 36, 76: // Return / keypad enter
                self.openSelection()
                return nil
            default:
                return event
            }
        }
    }
}

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct QuickLauncherView: View {
    @ObservedObject var launcher: QuickLauncher
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search 94 tools…", text: Binding(
                    get: { launcher.query },
                    set: { launcher.updateQuery($0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .focused($focused)
                .onSubmit { launcher.openSelection() }
                Button {
                    launcher.hide()
                } label: {
                    Text("esc")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)

            Rectangle().fill(Theme.line).frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(launcher.results.enumerated()), id: \.element.slug) { index, tool in
                            Button {
                                launcher.open(tool.slug)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: tool.symbol)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(index == launcher.selection ? Theme.ember : Theme.textSecondary)
                                        .frame(width: 24, height: 24)
                                        .background(
                                            (index == launcher.selection ? Theme.ember : Theme.textSecondary).opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        )
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tool.name)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(tool.tagline)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(Theme.textTertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(CatalogStore.shared.category(id: tool.category)?.name ?? tool.category)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(Theme.textTertiary)
                                    if tool.implemented {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.mint)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    index == launcher.selection ? Theme.raised : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(tool.slug)
                        }

                        if launcher.results.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundStyle(Theme.textTertiary)
                                Text("No tool matches “\(launcher.query)”")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 44)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: launcher.selection) { _, value in
                    if let tool = launcher.results[safe: value] {
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(tool.slug, anchor: .center) }
                    }
                }
            }

            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 14) {
                Label("Open", systemImage: "return")
                Label("Move", systemImage: "arrow.up.arrow.down")
                Spacer()
                Text("Nookit · everything on this Mac")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.textTertiary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.ultraThickMaterial)
        .background(Theme.background.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.lineStrong, lineWidth: 1)
        )
        .padding(10)
        .onAppear {
            DispatchQueue.main.async {
                focused = true
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
