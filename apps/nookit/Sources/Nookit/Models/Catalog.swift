import Foundation

// MARK: - Catalog shapes (mirrors Resources/catalog.json)

struct CatalogData: Codable, Sendable {
    let product: ProductInfo
    let categories: [ToolCategory]
    let tools: [ToolItem]
    let notchModules: [CatalogNotchModule]
    let counts: CatalogCounts

    static let empty = CatalogData(
        product: ProductInfo(
            name: "Nookit",
            tagline: "94 Mac tools. One notch away.",
            description: "A private toolkit for the Mac.",
            price: 19,
            compareAt: 49.99,
            currency: "USD",
            macsPerLicense: 3,
            minOS: "macOS 14 Sonoma or later",
            site: "https://nookit.app",
            support: "support@nookit.app"
        ),
        categories: [],
        tools: [],
        notchModules: [],
        counts: CatalogCounts(tools: 0, notch: 0, implementedTools: 0, byCategory: [:])
    )

    func category(id: String) -> ToolCategory? {
        categories.first { $0.id == id }
    }

    func tool(slug: String) -> ToolItem? {
        tools.first { $0.slug == slug }
    }

    func tools(in categoryID: String) -> [ToolItem] {
        tools.filter { $0.category == categoryID }
    }
}

struct ProductInfo: Codable, Sendable {
    let name: String
    let tagline: String
    let description: String
    let price: Double
    let compareAt: Double
    let currency: String
    let macsPerLicense: Int
    let minOS: String
    let site: String
    let support: String
}

struct ToolCategory: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let blurb: String

    var symbol: String {
        switch id {
        case "video": return "film"
        case "audio": return "waveform"
        case "images": return "photo"
        case "docs": return "doc.text"
        case "text": return "text.alignleft"
        case "files": return "folder"
        case "mac": return "macbook"
        case "developer": return "chevron.left.forwardslash.chevron.right"
        default: return "square.grid.2x2"
        }
    }
}

struct ToolItem: Codable, Identifiable, Hashable, Sendable {
    let slug: String
    let name: String
    let category: String
    let symbol: String
    let implemented: Bool
    let tagline: String
    let description: String

    var id: String { slug }
}

struct CatalogNotchModule: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let group: String
    let symbol: String
    let implemented: Bool
    let tagline: String
    let shortcut: String?
    let description: String
}

struct CatalogCounts: Codable, Sendable {
    let tools: Int
    let notch: Int
    let implementedTools: Int
    let byCategory: [String: Int]

    var ready: Int {
        max(implementedTools, 0)
    }
}

// MARK: - Loader

enum CatalogStore {
    /// Loaded once. Falls back to an empty catalog instead of trapping so the app always opens.
    static let shared: CatalogData = {
        guard
            let url = catalogURL(),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(CatalogData.self, from: data)
        else {
            NSLog("Nookit: could not load catalog.json; using empty catalog")
            return .empty
        }
        return catalog
    }()

    static func load() -> CatalogData { shared }

    /// The app is built with `swiftc` (SwiftPM's manifest loader is broken on the
    /// current Command Line Tools), so resolve the catalog from the assembled app
    /// bundle first, then from the source tree when running a raw binary.
    private static func catalogURL() -> URL? {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "catalog", withExtension: "json") {
            candidates.append(bundled)
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("catalog.json"))
            candidates.append(resources.appendingPathComponent("Nookit_Nookit.bundle/catalog.json"))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("catalog.json"))
        candidates.append(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // Models
                .deletingLastPathComponent()   // Nookit
                .appendingPathComponent("Resources/catalog.json")
        )
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
