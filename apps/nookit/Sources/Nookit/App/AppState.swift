import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    let catalog: CatalogData

    @Published var search: String = ""
    @Published var selectedCategory: String? = nil
    @Published var selectedToolSlug: String? = nil
    @Published var runningToolSlug: String? = nil
    @Published var searchFocusToken: Int = 0
    @Published var recentSlugs: [String] = []
    @Published var showNotchSettings: Bool = false
    @Published var showAIChat: Bool = false
    @Published var showHype: Bool = false
    @Published var showApps: Bool = false

    private let recentKey = "NookitRecentTools"

    init(catalog: CatalogData = CatalogStore.shared) {
        self.catalog = catalog
        if let stored = UserDefaults.standard.stringArray(forKey: recentKey) {
            recentSlugs = stored
        }
    }

    // MARK: - Derived

    var allTools: [ToolItem] { catalog.tools }

    var filteredTools: [ToolItem] {
        var tools = catalog.tools
        if let selectedCategory {
            tools = tools.filter { $0.category == selectedCategory }
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let needle = query.lowercased()
            tools = tools.filter {
                $0.name.lowercased().contains(needle)
                    || $0.tagline.lowercased().contains(needle)
                    || $0.description.lowercased().contains(needle)
                    || $0.slug.contains(needle)
                    || (catalog.category(id: $0.category)?.name.lowercased().contains(needle) ?? false)
            }
        }
        return tools
    }

    var groupedTools: [(category: ToolCategory, tools: [ToolItem])] {
        let filtered = filteredTools
        return catalog.categories.compactMap { category in
            let items = filtered.filter { $0.category == category.id }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var recentTools: [ToolItem] {
        recentSlugs.compactMap { catalog.tool(slug: $0) }
    }

    func count(for categoryID: String?) -> Int {
        guard let categoryID else { return catalog.tools.count }
        return catalog.tools.filter { $0.category == categoryID }.count
    }

    var heroStats: String {
        let ready = ToolRegistry.shared.readyCount(in: catalog)
        return "\(catalog.tools.count) tools · \(ready) ready · on-device"
    }

    // MARK: - Navigation

    func openTool(_ slug: String) {
        selectedToolSlug = slug
        runningToolSlug = nil
        showNotchSettings = false
        showAIChat = false
        showHype = false
        showApps = false
        remember(slug)
        NSApp.activate(ignoringOtherApps: true)
    }

    func runTool(_ slug: String) {
        selectedToolSlug = slug
        runningToolSlug = slug
        showNotchSettings = false
        showAIChat = false
        showHype = false
        showApps = false
        remember(slug)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openCategory(_ id: String?) {
        selectedCategory = id
        selectedToolSlug = nil
        runningToolSlug = nil
        showNotchSettings = false
        showAIChat = false
        showHype = false
        showApps = false
    }

    func showNotchPreferences() {
        showNotchSettings = true
        selectedToolSlug = nil
        runningToolSlug = nil
        showAIChat = false
        showHype = false
        showApps = false
        NSApp.activate(ignoringOtherApps: true)
    }

    func openAIChat() {
        showAIChat = true
        showNotchSettings = false
        showHype = false
        showApps = false
        selectedCategory = nil
        selectedToolSlug = nil
        runningToolSlug = nil
        NSApp.activate(ignoringOtherApps: true)
    }

    func openHype() {
        showHype = true
        showAIChat = false
        showApps = false
        showNotchSettings = false
        selectedCategory = nil
        selectedToolSlug = nil
        runningToolSlug = nil
        NSApp.activate(ignoringOtherApps: true)
    }

    func openApps(_ app: GoogleApp? = nil) {
        showApps = true
        showHype = false
        showAIChat = false
        showNotchSettings = false
        selectedCategory = nil
        selectedToolSlug = nil
        runningToolSlug = nil
        if let app {
            AppsService.shared.select(app)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func requestSearchFocus() {
        searchFocusToken += 1
        NSApp.activate(ignoringOtherApps: true)
    }

    func remember(_ slug: String) {
        recentSlugs.removeAll { $0 == slug }
        recentSlugs.insert(slug, at: 0)
        if recentSlugs.count > 8 { recentSlugs = Array(recentSlugs.prefix(8)) }
        UserDefaults.standard.set(recentSlugs, forKey: recentKey)
    }

    func clearRecents() {
        recentSlugs = []
        UserDefaults.standard.removeObject(forKey: recentKey)
    }

    var selectedTool: ToolItem? {
        guard let selectedToolSlug else { return nil }
        return catalog.tool(slug: selectedToolSlug)
    }
}
