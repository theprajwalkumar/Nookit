import SwiftUI
import Combine

/// Persisted notch preferences. The controller and settings UI share this one object.
@MainActor
final class NotchSettings: ObservableObject {
    static let shared = NotchSettings()

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    @Published var pinnedOnLaunch: Bool { didSet { defaults.set(pinnedOnLaunch, forKey: Keys.pinned) } }
    @Published var expandedWidth: Double { didSet { defaults.set(expandedWidth, forKey: Keys.width) } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Keys.hover) } }
    @Published var showOnAllSpaces: Bool { didSet { defaults.set(showOnAllSpaces, forKey: Keys.spaces) } }
    @Published var enabledModules: Set<String> { didSet { defaults.set(Array(enabledModules), forKey: Keys.modules) } }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabled = "NookitNotchEnabled"
        static let pinned = "NookitNotchPinnedOnLaunch"
        static let width = "NookitNotchExpandedWidth"
        static let hover = "NookitNotchHoverDelay"
        static let spaces = "NookitNotchAllSpaces"
        static let modules = "NookitNotchModules"
    }

    private init() {
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        pinnedOnLaunch = defaults.object(forKey: Keys.pinned) as? Bool ?? false
        expandedWidth = defaults.object(forKey: Keys.width) as? Double ?? 640
        hoverDelay = defaults.object(forKey: Keys.hover) as? Double ?? 0.12
        showOnAllSpaces = defaults.object(forKey: Keys.spaces) as? Bool ?? true
        let stored = defaults.stringArray(forKey: Keys.modules)
        enabledModules = Set(stored ?? NotchModule.allCases.map(\.rawValue))
    }

    func isEnabled(_ module: NotchModule) -> Bool {
        enabledModules.contains(module.rawValue)
    }

    func toggle(_ module: NotchModule) {
        if enabledModules.contains(module.rawValue) {
            enabledModules.remove(module.rawValue)
        } else {
            enabledModules.insert(module.rawValue)
        }
    }
}
