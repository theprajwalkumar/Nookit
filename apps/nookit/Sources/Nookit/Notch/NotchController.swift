import SwiftUI
import AppKit
import Combine

// MARK: - Model

@MainActor
final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var pinned = false
    @Published var activeModule: NotchModule = .clipboard
    @Published var hasNotch = false

    let settings: NotchSettings
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?

    init(settings: NotchSettings) {
        self.settings = settings
        self.pinned = settings.pinnedOnLaunch
        self.activeModule = NotchModule.allCases.first(where: { settings.isEnabled($0) }) ?? .clipboard
        if pinned { expanded = true }
    }

    var visibleModules: [NotchModule] {
        Weave.visibleModules(settings: settings)
    }

    func hover(_ inside: Bool) {
        expandWork?.cancel()
        collapseWork?.cancel()
        if inside {
            guard !expanded else { return }
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in self?.expanded = true }
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.02, settings.hoverDelay), execute: work)
        } else {
            guard !pinned else { return }
            let work = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self, !self.pinned else { return }
                    withAnimation(.easeOut(duration: 0.18)) { self.expanded = false }
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    func togglePin() {
        pinned.toggle()
        expandWork?.cancel()
        if pinned {
            withAnimation(.easeOut(duration: 0.18)) { expanded = true }
        } else if !expanded {
            withAnimation(.easeOut(duration: 0.18)) { expanded = true }
        }
    }

    func expand() {
        pinned = true
        withAnimation(.easeOut(duration: 0.18)) { expanded = true }
    }

    func collapse() {
        pinned = false
        expandWork?.cancel()
        collapseWork?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { expanded = false }
    }

    func activate(_ module: NotchModule) {
        activeModule = module
        if !expanded { pinned = true; expanded = true }
    }

    func normalizeSelection() {
        let visible = visibleModules
        if !visible.contains(activeModule), let first = visible.first {
            activeModule = first
        }
    }
}

/// Tiny namespace so the model does not need to know the settings object’s internals.
enum Weave {
    @MainActor
    static func visibleModules(settings: NotchSettings) -> [NotchModule] {
        let modules = NotchModule.allCases.filter { settings.isEnabled($0) }
        return modules.isEmpty ? [.clipboard] : modules
    }
}

// MARK: - Controller

@MainActor
final class NotchController: ObservableObject {
    let model: NotchModel
    private let settings: NotchSettings
    private var panel: NotchPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?
    private var started = false

    private let collapsedNotch = NSSize(width: 240, height: 34)
    private let collapsedPill = NSSize(width: 200, height: 28)
    private let expandedSize = NSSize(width: 640, height: 420)

    init(settings: NotchSettings? = nil) {
        let settings = settings ?? .shared
        self.settings = settings
        self.model = NotchModel(settings: settings)
    }

    func start() {
        guard !started else { return }
        started = true
        buildPanel()
        observe()
        refresh(animated: false)
        if settings.enabled {
            panel?.orderFrontRegardless()
            panel?.alphaValue = 1
        }
        installKeyMonitor()
        GlobalHotKeys.shared.start(
            clipboard: { [weak self] in self?.reveal(.clipboard) },
            notes: { [weak self] in self?.reveal(.notes) },
            ai: { [weak self] in self?.reveal(.ai) },
            launcher: { QuickLauncher.shared.toggle() }
        )
    }

    func stop() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        GlobalHotKeys.shared.stop()
        panel?.orderOut(nil)
    }

    /// Opens the notch on a module from a global shortcut.
    private func reveal(_ module: NotchModule) {
        settings.enabled = true
        model.activate(module)
    }

    private func buildPanel() {
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: collapsedNotch),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = collectionBehavior
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Keep the notch out of screen recordings and shares.
        panel.sharingType = .none
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = NSHostingView(
            rootView: NotchView(model: model)
                .environmentObject(ResultStore.shared)
        )
        panel.contentView?.wantsLayer = true
        panel.alphaValue = settings.enabled ? 1 : 0
        self.panel = panel
    }

    private var collectionBehavior: NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary]
        if settings.showOnAllSpaces {
            behavior.formUnion([.canJoinAllSpaces, .stationary])
        }
        return behavior
    }

    private func observe() {
        model.$expanded
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh(animated: true) }
            }
            .store(in: &cancellables)

        settings.$enabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                Task { @MainActor in self?.applyEnabled(enabled) }
            }
            .store(in: &cancellables)

        settings.$expandedWidth
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh(animated: false) }
            }
            .store(in: &cancellables)

        settings.$showOnAllSpaces
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, let panel = self.panel else { return }
                    panel.collectionBehavior = self.collectionBehavior
                    panel.orderFrontRegardless()
                }
            }
            .store(in: &cancellables)

        settings.$enabledModules
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.model.normalizeSelection() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh(animated: false) }
            }
            .store(in: &cancellables)
    }

    private func applyEnabled(_ enabled: Bool) {
        guard let panel else { return }
        if enabled {
            refresh(animated: false)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in panel.orderOut(nil) }
            })
        }
    }

    private func refresh(animated: Bool) {
        guard let panel else { return }
        let target = targetFrame()
        let screen = notchScreen() ?? NSScreen.main
        model.hasNotch = (screen?.safeAreaInsets.top ?? 0) > 0
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.safeAreaInsets.top > 0
                || screen.auxiliaryTopLeftArea != nil
                || screen.auxiliaryTopRightArea != nil
        } ?? NSScreen.main
    }

    func targetFrame() -> NSRect {
        let screen = notchScreen() ?? NSScreen.screens.first ?? NSScreen.main
        guard let screen else { return NSRect(x: 0, y: 0, width: 240, height: 34) }
        let hasNotch = screen.safeAreaInsets.top > 0
            || screen.auxiliaryTopLeftArea != nil
            || screen.auxiliaryTopRightArea != nil
        let width = model.expanded ? min(max(settings.expandedWidth, 560), 760) : (hasNotch ? collapsedNotch.width : collapsedPill.width)
        let height = model.expanded ? expandedSize.height : (hasNotch ? collapsedNotch.height : collapsedPill.height)
        let x = screen.frame.midX - width / 2
        let top: CGFloat
        if hasNotch {
            // The physical notch and the menu bar occupy the top of the display.
            // Starting the panel at screen.frame.maxY hid the tab row and the
            // first line of every module behind it, so begin below that inset.
            top = screen.frame.maxY - screen.safeAreaInsets.top
        } else {
            top = screen.visibleFrame.maxY - 8
        }
        return NSRect(x: x.rounded(), y: top - height, width: width, height: height)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            let editingText = panel.firstResponder is NSTextView

            if event.keyCode == 53, self.model.expanded {
                self.model.collapse()
                return nil
            }

            guard self.model.expanded, !editingText else { return event }
            guard let characters = event.charactersIgnoringModifiers else { return event }

            if characters == "0" {
                self.model.activate(.ai)
                return nil
            }
            if let number = Int(characters), number >= 1, number <= 9 {
                let modules = self.model.visibleModules
                if number <= modules.count {
                    self.model.activate(modules[number - 1])
                    return nil
                }
            }
            if event.keyCode == 36, self.model.expanded {
                // Return opens the first available module target rather than closing.
                return event
            }
            return event
        }
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
