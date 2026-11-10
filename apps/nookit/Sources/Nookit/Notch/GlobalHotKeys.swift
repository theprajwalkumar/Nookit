import Foundation
import Carbon

/// Registers the global shortcuts advertised for the notch modules.
/// Carbon hot keys work while another app is frontmost and do not require
/// Accessibility permission, which keeps the privacy story intact.
final class GlobalHotKeys {
    static let shared = GlobalHotKeys()

    private var handler: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]

    private init() {}

    func start(
        clipboard: @escaping () -> Void,
        notes: @escaping () -> Void,
        ai: @escaping () -> Void,
        launcher: @escaping () -> Void
    ) {
        guard handler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else { return }

        actions = [1: clipboard, 2: notes, 3: ai, 4: launcher]
        register(id: 1, key: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | cmdKey))
        register(id: 2, key: UInt32(kVK_ANSI_J), modifiers: UInt32(optionKey | cmdKey))
        register(id: 3, key: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey | cmdKey))
        // ⌃⌥Space is the shortcut shown on the site. It may already be bound to
        // input-source switching; if registration fails the menu item still works.
        register(id: 4, key: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))

        if ProcessInfo.processInfo.environment["NOOKIT_DEBUG_HOTKEYS"] == "1" {
            let line = "NOOKIT_HOTKEYS registered=\(refs.count)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    private func register(id: UInt32, key: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F4F4B), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            key,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            refs.append(ref)
        }
    }

    fileprivate func dispatch(_ id: UInt32) {
        guard let action = actions[id] else { return }
        DispatchQueue.main.async(execute: action)
    }

    func stop() {
        for ref in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        actions.removeAll()
    }
}

private let hotKeyCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let manager = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
    manager.dispatch(hotKeyID.id)
    return noErr
}
