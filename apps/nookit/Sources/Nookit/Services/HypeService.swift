import SwiftUI
import Foundation
import CoreLocation
import MapKit

// MARK: - Models

struct HypePlace: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let latitude: Double
    let longitude: Double
    var countryCode: String? = nil

    var shortName: String {
        if !name.isEmpty { return name }
        return displayName.components(separatedBy: ",").first ?? displayName
    }

    /// Drives provider routing: Swiggy/Zomato/District/BookMyShow/MakeMyTrip in
    /// India, DoorDash/OpenTable/Ticketmaster elsewhere.
    var isIndia: Bool {
        if let code = countryCode?.lowercased(), !code.isEmpty {
            return code == "in"
        }
        let lowered = displayName.lowercased()
        return lowered.contains("india") || lowered.contains("bharat")
    }
}

struct HypeVenue: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
    let cuisine: String?
    let latitude: Double
    let longitude: Double
    let distance: Double
    let priceTier: Int
    let address: String?
    let website: String?
    let phone: String?
    let openingHours: String?

    var priceLabel: String { String(repeating: "$", count: max(1, min(4, priceTier))) }

    var distanceLabel: String {
        if distance < 1_000 { return "\(Int(distance.rounded())) m" }
        return String(format: "%.1f km", distance / 1_000)
    }

    var kindLabel: String {
        switch kind {
        case "fast_food": return "Fast food"
        case "food_court": return "Food court"
        case "cafe": return "Café"
        case "bakery": return "Bakery"
        case "ice_cream": return "Ice cream"
        case "pub": return "Pub"
        case "bar": return "Bar"
        case "restaurant": return "Restaurant"
        case "marketplace": return "Market"
        case "convenience": return "Convenience"
        case "deli": return "Deli"
        case "greengrocer": return "Greengrocer"
        default: return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var symbol: String {
        switch kind {
        case "cafe", "bakery", "ice_cream": return "cup.and.saucer.fill"
        case "pub", "bar": return "wineglass.fill"
        case "fast_food", "food_court": return "takeoutbag.and.cup.and.straw.fill"
        case "marketplace", "greengrocer", "convenience", "deli": return "basket.fill"
        default: return "fork.knife"
        }
    }

    var url: URL? {
        guard let website, !website.isEmpty else { return nil }
        let text = website.lowercased().hasPrefix("http") ? website : "https://\(website)"
        return URL(string: text)
    }

    var mapsURL: URL? {
        URL(string: "https://www.google.com/maps/search/?api=1&query=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&center=\(latitude),\(longitude)")
    }
}

struct HypeDish: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Double
    let isVeg: Bool
    let description: String?

    var priceLabel: String {
        guard price > 0 else { return "—" }
        return "₹\(Int(price.rounded()))"
    }
}

/// A restaurant with a real menu, scraped from Swiggy's dish search. Swiggy is
/// the only public surface that returns both the restaurant and the dishes it
/// sells in one response, so Hype can show a Zomato-style menu list instead of
/// a bare venue name.
struct HypeRestaurantMenu: Identifiable, Hashable {
    let id: String
    let name: String
    let cuisines: [String]
    let rating: Double?
    let costForTwo: String?
    let deliveryTime: String?
    let distanceKm: Double?
    let area: String?
    let address: String?
    let imageId: String?
    let swiggySlug: String?
    var dishes: [HypeDish]

    var cuisineLabel: String {
        cuisines.prefix(3).joined(separator: " · ")
    }

    var distanceLabel: String? {
        guard let distanceKm else { return nil }
        if distanceKm < 1 { return "\(Int((distanceKm * 1_000).rounded())) m" }
        return String(format: "%.1f km", distanceKm)
    }

    var ratingLabel: String? {
        guard let rating, rating > 0 else { return nil }
        return String(format: "%.1f", rating)
    }

    var swiggyURL: URL? {
        if let slug = swiggySlug?.trimmingCharacters(in: .whitespacesAndNewlines), !slug.isEmpty {
            let base = slug.hasSuffix("-\(id)") ? slug : "\(slug)-\(id)"
            return URL(string: "https://www.swiggy.com/restaurants/\(base)")
        }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://www.swiggy.com/search?query=\(encoded)")
    }

    var zomatoURL: URL? {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        return URL(string: "https://www.zomato.com/search?q=\(encoded)")
    }

    var menuImageURL: URL? {
        guard let imageId, !imageId.isEmpty else { return nil }
        return URL(string: "https://media-assets.swiggy.com/swiggy/image/upload/fl_lossy,f_auto,q_auto,w_320/\(imageId)")
    }
}

enum HypeFoodProvider: String, CaseIterable, Identifiable {
    case swiggy
    case zomato

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swiggy: return "Swiggy"
        case .zomato: return "Zomato"
        }
    }

    var symbol: String {
        switch self {
        case .swiggy: return "bag.fill"
        case .zomato: return "fork.knife"
        }
    }

    var tint: Color {
        switch self {
        case .swiggy: return Color(hex: 0xFC8019)
        case .zomato: return Color(hex: 0xE23744)
        }
    }
}

struct HypeShowtime: Identifiable, Hashable {
    let id: String
    let cinema: String
    let distanceKm: Double?
    let time: String
    let price: String?
    let format: String?
    let audi: String?

    var distanceLabel: String? {
        guard let distanceKm else { return nil }
        return String(format: "%.1f km", distanceKm)
    }
}

struct HypeMovie: Identifiable, Hashable {
    let id: String
    let title: String
    let language: String?
    let format: String?
    let genre: String?
    let durationMinutes: Int?
    let censor: String?
    let imageURL: String?
    let urlString: String?
    let movieCode: String?
    let contentId: Int?
    var showtimes: [HypeShowtime]

    var url: URL? {
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    var metaLabel: String {
        [language, format, genre, durationLabel, censor]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var durationLabel: String? {
        guard let durationMinutes, durationMinutes > 0 else { return nil }
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    var groupedShowtimes: [(cinema: String, distance: String?, times: [HypeShowtime])] {
        var order: [String] = []
        var groups: [String: [HypeShowtime]] = [:]
        for showtime in showtimes {
            if groups[showtime.cinema] == nil {
                order.append(showtime.cinema)
                groups[showtime.cinema] = []
            }
            groups[showtime.cinema]?.append(showtime)
        }
        return order.map { cinema in
            let times = (groups[cinema] ?? []).sorted { $0.time < $1.time }
            return (cinema, times.first?.distanceLabel, times)
        }
    }
}

enum HypeFoodCategory: String, CaseIterable, Identifiable {
    case all
    case restaurants
    case cafes
    case bakeries
    case bars
    case fastFood
    case markets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .restaurants: return "Restaurants"
        case .cafes: return "Cafés"
        case .bakeries: return "Bakeries"
        case .bars: return "Bars"
        case .fastFood: return "Fast food"
        case .markets: return "Markets"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .restaurants: return "fork.knife"
        case .cafes: return "cup.and.saucer.fill"
        case .bakeries: return "birthday.cake.fill"
        case .bars: return "wineglass.fill"
        case .fastFood: return "takeoutbag.and.cup.and.straw.fill"
        case .markets: return "basket.fill"
        }
    }

    func matches(_ venue: HypeVenue) -> Bool {
        switch self {
        case .all:
            return true
        case .restaurants:
            return ["restaurant", "food_court", "deli"].contains(venue.kind)
        case .cafes:
            return ["cafe", "ice_cream"].contains(venue.kind)
        case .bakeries:
            return venue.kind == "bakery"
        case .bars:
            return ["bar", "pub"].contains(venue.kind)
        case .fastFood:
            return ["fast_food", "food_court"].contains(venue.kind)
        case .markets:
            return ["marketplace", "convenience", "greengrocer", "deli"].contains(venue.kind)
        }
    }

    func matches(_ menu: HypeRestaurantMenu) -> Bool {
        let cuisines = menu.cuisines.map { $0.lowercased() }
        func has(_ needles: [String]) -> Bool {
            cuisines.contains { cuisine in needles.contains { cuisine.contains($0) } }
        }
        switch self {
        case .all:
            return true
        case .restaurants:
            return !has(["bakery", "dessert", "cafe", "coffee", "bar", "beverage", "burger", "pizza", "fast food"])
        case .cafes:
            return has(["cafe", "coffee", "tea", "sandwich", "continental"])
        case .bakeries:
            return has(["bakery", "dessert", "cake", "ice cream", "sweet"])
        case .bars:
            return has(["bar", "beverage", "alcohol", "pub", "brewery"])
        case .fastFood:
            return has(["burger", "pizza", "fast food", "roll", "sandwich", "fried chicken"])
        case .markets:
            return false
        }
    }
}

enum HypeVegFilter: String, CaseIterable, Identifiable {
    case all
    case veg
    case nonVeg
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .all: return "All"
        case .veg: return "Veg"
        case .nonVeg: return "Non-Veg"
        }
    }
    
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .veg: return "leaf.fill"
        case .nonVeg: return "circle.grid.cross.fill"
        }
    }
    
    var tint: Color {
        switch self {
        case .all: return Theme.ember
        case .veg: return Color(hex: 0x1FAA59)
        case .nonVeg: return Color(hex: 0xD93B3B)
        }
    }
    
    func matches(_ dish: HypeDish) -> Bool {
        switch self {
        case .all: return true
        case .veg: return dish.isVeg
        case .nonVeg: return !dish.isVeg
        }
    }
}

struct HypeCinema: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let distance: Double

    var distanceLabel: String {
        if distance < 1_000 { return "\(Int(distance.rounded())) m" }
        return String(format: "%.1f km", distance / 1_000)
    }

    var mapsURL: URL? {
        URL(string: "https://www.google.com/maps/search/?api=1&query=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&center=\(latitude),\(longitude)")
    }
}

struct HypeEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let venue: String
    let city: String
    let dateLabel: String
    let startsAt: Date?
    let priceLabel: String
    let category: String
    let urlString: String?
    let imageURL: String?
    let isVenueSuggestion: Bool

    var url: URL? {
        guard let urlString else { return nil }
        return URL(string: urlString)
    }
}

enum HypeTravelMode: String, CaseIterable, Identifiable {
    case flights
    case hotels
    case trains

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flights: return "Flights"
        case .hotels: return "Hotels"
        case .trains: return "Trains"
        }
    }

    var symbol: String {
        switch self {
        case .flights: return "airplane"
        case .hotels: return "bed.double.fill"
        case .trains: return "tram.fill"
        }
    }

    var source: String {
        switch self {
        case .flights: return "Google Flights"
        case .hotels: return "Booking.com"
        case .trains: return "Rome2Rio"
        }
    }
}

// MARK: - Service

/// Location-based discovery for Hype. Real geocoding comes from Nominatim,
/// nearby food and venues from OpenStreetMap's Overpass API, and events from
/// Ticketmaster when a free API key is supplied. Travel prices intentionally
/// open the authoritative live search page instead of inventing estimates.
@MainActor
final class HypeService: ObservableObject {
    static let shared = HypeService()

    /// Live listings need a clean slate on every fetch. The shared URL session
    /// keeps a disk cache and persistent cookies, and District uses a cookie to
    /// remember a city — which once made Delhi display Bengaluru concerts. An
    /// ephemeral session has no cache and no shared cookies, so each search is
    /// scoped to exactly the place the user picked.
    static let liveSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    @Published var placeQuery: String = ""
    @Published private(set) var suggestions: [HypePlace] = []
    @Published private(set) var selectedPlace: HypePlace?
    @Published private(set) var recentPlaces: [HypePlace] = []

    @Published private(set) var venues: [HypeVenue] = []
    @Published private(set) var restaurantMenus: [HypeRestaurantMenu] = []
    @Published var foodCategory: HypeFoodCategory = .all
    @Published var dishQuery: String = ""
    @Published var foodProvider: HypeFoodProvider {
        didSet { defaults.set(foodProvider.rawValue, forKey: Keys.foodProvider) }
    }
    @Published var vegFilter: HypeVegFilter = .all {
        didSet { defaults.set(vegFilter.rawValue, forKey: Keys.vegFilter) }
    }
    @Published private(set) var cinemas: [HypeCinema] = []
    @Published private(set) var movies: [HypeMovie] = []
    @Published private(set) var events: [HypeEvent] = []
    @Published private(set) var eventNote: String?
    @Published private(set) var movieNote: String?

    @Published var radiusKm: Double = 3

    @Published var ticketmasterKey: String {
        didSet { defaults.set(ticketmasterKey, forKey: Keys.ticketmaster) }
    }

    @Published private(set) var searchingPlaces = false
    @Published private(set) var locating = false
    @Published private(set) var loadingFood = false
    @Published private(set) var loadingMenus = false
    @Published private(set) var loadingCinemas = false
    @Published private(set) var loadingMovies = false
    @Published private(set) var loadingEvents = false
    @Published private(set) var lastUpdated: Date?
    @Published var error: String?

    // Travel planner
    @Published var origin: String = ""
    @Published var destination: String = ""
    @Published var departDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @Published var returnDate: Date = Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date()
    @Published var travelers: Int = 1
    @Published var travelMode: HypeTravelMode = .flights

    private let defaults = UserDefaults.standard
    private let resolver = LocationResolver()

    private enum Keys {
        static let ticketmaster = "NookitHypeTicketmasterKey"
        static let lastPlace = "NookitHypeLastPlace"
        static let recentPlaces = "NookitHypeRecentPlaces"
        static let foodProvider = "NookitHypeFoodProvider"
        static let vegFilter = "NookitHypeVegFilter"
    }

    private init() {
        ticketmasterKey = defaults.string(forKey: Keys.ticketmaster) ?? ""
        foodProvider = HypeFoodProvider(rawValue: defaults.string(forKey: Keys.foodProvider) ?? "") ?? .swiggy
        vegFilter = HypeVegFilter(rawValue: defaults.string(forKey: Keys.vegFilter) ?? "") ?? .all

        if let data = defaults.data(forKey: Keys.lastPlace),
           let place = try? JSONDecoder().decode(HypePlace.self, from: data) {
            selectedPlace = place
            placeQuery = place.shortName
            origin = place.shortName
        }
        if let data = defaults.data(forKey: Keys.recentPlaces),
           let places = try? JSONDecoder().decode([HypePlace].self, from: data) {
            recentPlaces = places
        }
    }

    // MARK: Places

    var affordablePicks: [HypeVenue] {
        Array(filteredVenues.filter { $0.priceTier <= 2 }.prefix(6))
    }

    var filteredVenues: [HypeVenue] {
        venues.filter { foodCategory.matches($0) }
    }

    var filteredMenus: [HypeRestaurantMenu] {
        restaurantMenus.filter { foodCategory.matches($0) }
    }
    
    /// Returns menus with dishes filtered by veg preference
    func menusWithFilteredDishes() -> [HypeRestaurantMenu] {
        filteredMenus.compactMap { menu in
            let filteredDishes = menu.dishes.filter { vegFilter.matches($0) }
            guard !filteredDishes.isEmpty else { return nil }
            var copy = menu
            copy.dishes = filteredDishes
            return copy
        }
    }

    func loadIfNeeded() async {
        guard selectedPlace != nil, venues.isEmpty, !loadingFood else { return }
        await loadAll()
    }

    /// Loads every Hype surface for the selected place. Each loader owns its own
    /// failure state, so a slow provider never blocks the rest of the tab.
    func loadAll() async {
        guard selectedPlace != nil else { return }
        async let nearby: Void = loadNearby()
        async let menus: Void = loadRestaurantMenus()
        async let events: Void = loadEvents()
        async let movies: Void = loadMovies()
        async let cinemas: Void = loadCinemas()
        _ = await (nearby, menus, events, movies, cinemas)
    }

    func searchPlaces() async {
        let query = placeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            suggestions = []
            return
        }

        searchingPlaces = true
        error = nil
        defer { searchingPlaces = false }

        do {
            var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")
            components?.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "format", value: "jsonv2"),
                URLQueryItem(name: "addressdetails", value: "1"),
                URLQueryItem(name: "limit", value: "6"),
                URLQueryItem(name: "accept-language", value: "en")
            ]
            guard let url = components?.url else { return }
            let data = try await fetch(url)

            struct Result: Decodable {
                let place_id: Int?
                let lat: String
                let lon: String
                let name: String?
                let display_name: String
                let address: [String: String]?
            }

            let results = try JSONDecoder().decode([Result].self, from: data)
            suggestions = results.compactMap { item in
                guard let latitude = Double(item.lat), let longitude = Double(item.lon) else { return nil }
                let display = item.display_name
                let name = item.name?.isEmpty == false
                    ? item.name!
                    : (display.components(separatedBy: ",").first ?? display)
                return HypePlace(
                    id: "\(item.place_id ?? 0)-\(item.lat)-\(item.lon)",
                    name: name,
                    displayName: display,
                    latitude: latitude,
                    longitude: longitude,
                    countryCode: item.address?["country_code"]
                )
            }
        } catch {
            self.error = "Couldn't search that place. Check your connection and try again."
        }
    }

    func clearSuggestions() {
        suggestions = []
    }

    func select(_ place: HypePlace) async {
        selectedPlace = place
        placeQuery = place.shortName
        suggestions = []
        origin = place.shortName
        remember(place)
        await loadAll()
    }

    func clearPlace() {
        selectedPlace = nil
        placeQuery = ""
        suggestions = []
        venues = []
        restaurantMenus = []
        cinemas = []
        movies = []
        events = []
        eventNote = nil
        movieNote = nil
        defaults.removeObject(forKey: Keys.lastPlace)
    }

    func useCurrentLocation() async {
        locating = true
        error = nil
        defer { locating = false }

        guard let location = await resolver.current() else {
            error = "Location access is off. Allow it in System Settings → Privacy & Security → Location Services, or search for a city."
            return
        }

        let fallback = HypePlace(
            id: "current-\(location.coordinate.latitude),\(location.coordinate.longitude)",
            name: "My location",
            displayName: String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        var place = fallback
        if let reversed = try? await reverseGeocode(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) {
            place = reversed
        }
        await select(place)
    }

    private func reverseGeocode(latitude: Double, longitude: Double) async throws -> HypePlace {
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "accept-language", value: "en")
        ]
        guard let url = components?.url else { throw ToolError.message("Invalid location.") }
        let data = try await fetch(url)

        struct Result: Decodable {
            let name: String?
            let display_name: String?
            let address: [String: String]?
        }
        let result = try JSONDecoder().decode(Result.self, from: data)
        let city = result.address?["city"]
            ?? result.address?["town"]
            ?? result.address?["village"]
            ?? result.address?["suburb"]
            ?? result.name
            ?? "My location"
        return HypePlace(
            id: "current-\(latitude),\(longitude)",
            name: city,
            displayName: result.display_name ?? city,
            latitude: latitude,
            longitude: longitude,
            countryCode: result.address?["country_code"]
        )
    }

    private func remember(_ place: HypePlace) {
        recentPlaces.removeAll { $0.id == place.id }
        recentPlaces.insert(place, at: 0)
        if recentPlaces.count > 8 { recentPlaces = Array(recentPlaces.prefix(8)) }
        if let data = try? JSONEncoder().encode(place) {
            defaults.set(data, forKey: Keys.lastPlace)
        }
        if let data = try? JSONEncoder().encode(recentPlaces) {
            defaults.set(data, forKey: Keys.recentPlaces)
        }
    }

    // MARK: Nearby food

    func loadNearby() async {
        guard let place = selectedPlace else { return }
        loadingFood = true
        error = nil
        defer { loadingFood = false }

        let radius = Int(max(0.4, min(20, radiusKm)) * 1_000)
        let query = """
        [out:json][timeout:25];
        (
          node["amenity"~"^(restaurant|cafe|fast_food|food_court|pub|bar|ice_cream)$"]["name"](around:\(radius),\(place.latitude),\(place.longitude));
          way["amenity"~"^(restaurant|cafe|fast_food|food_court|pub|bar|ice_cream)$"]["name"](around:\(radius),\(place.latitude),\(place.longitude));
          node["shop"~"^(bakery|deli|greengrocer|convenience)$"]["name"](around:\(radius),\(place.latitude),\(place.longitude));
          way["shop"~"^(bakery|deli|greengrocer|convenience)$"]["name"](around:\(radius),\(place.latitude),\(place.longitude));
          node["amenity"="marketplace"]["name"](around:\(radius),\(place.latitude),\(place.longitude));
        );
        out center tags 100;
        """

        var found: [HypeVenue] = []
        found = await appleFoodVenues(place: place)

        // Apple Maps is the dependable path. OSM adds cuisine, opening hours
        // and price tags when the community Overpass servers are healthy.
        if found.isEmpty {
            do {
                let data = try await overpass(query)
                found = Self.venues(from: data, origin: place)
            } catch {
                found = []
            }
        }

        venues = found
        lastUpdated = Date()
        if venues.isEmpty {
            error = "No food places found within \(Int(radiusKm)) km. Try a wider radius or another neighbourhood."
        }
    }

    // MARK: Swiggy menus

    /// Swiggy's dish search is the only public endpoint that returns a
    /// restaurant and the dishes it sells together, which is what lets Hype show
    /// a real menu instead of a bare restaurant name.
    static let popularDishQueries = ["biryani", "pizza", "burger", "paneer", "chicken", "cake"]

    func loadRestaurantMenus() async {
        guard let place = selectedPlace else { return }
        guard place.isIndia else {
            restaurantMenus = []
            return
        }

        loadingMenus = true
        defer { loadingMenus = false }

        let trimmed = dishQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let queries = trimmed.isEmpty ? Self.popularDishQueries : [trimmed]

        var merged: [String: HypeRestaurantMenu] = [:]
        await withTaskGroup(of: [HypeRestaurantMenu].self) { group in
            for query in queries.prefix(6) {
                group.addTask { await self.swiggyMenus(query: query, place: place) }
            }
            for await batch in group {
                for menu in batch {
                    if var existing = merged[menu.id] {
                        let known = Set(existing.dishes.map(\.id))
                        existing.dishes.append(contentsOf: menu.dishes.filter { !known.contains($0.id) })
                        existing.dishes = Array(existing.dishes.prefix(8))
                        merged[menu.id] = existing
                    } else {
                        merged[menu.id] = menu
                    }
                }
            }
        }

        restaurantMenus = merged.values.sorted { lhs, rhs in
            let leftDistance = lhs.distanceKm ?? 999
            let rightDistance = rhs.distanceKm ?? 999
            if abs(leftDistance - rightDistance) > 0.4 { return leftDistance < rightDistance }
            let leftRating = lhs.rating ?? 0
            let rightRating = rhs.rating ?? 0
            if abs(leftRating - rightRating) > 0.05 { return leftRating > rightRating }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        lastUpdated = Date()
    }

    private func swiggyMenus(query: String, place: HypePlace) async -> [HypeRestaurantMenu] {
        var components = URLComponents(string: "https://www.swiggy.com/dapi/restaurants/search/v3")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(place.latitude)),
            URLQueryItem(name: "lng", value: String(place.longitude)),
            URLQueryItem(name: "str", value: query),
            URLQueryItem(name: "trackingId", value: "undefined"),
            URLQueryItem(name: "submitAction", value: "ENTER"),
            URLQueryItem(name: "queryUniqueId", value: "nookit"),
            URLQueryItem(name: "queryIntent", value: "DISH"),
            URLQueryItem(name: "searchType", value: "DISH")
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 22
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://www.swiggy.com/", forHTTPHeaderField: "Referer")

        guard let (data, response) = try? await Self.liveSession.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return [] }
        return Self.restaurantMenus(from: data)
    }

    static func restaurantMenus(from data: Data) -> [HypeRestaurantMenu] {
        guard let root = try? JSONDecoder().decode(SwiggyResponse.self, from: data) else { return [] }
        var results: [HypeRestaurantMenu] = []

        for card in root.data?.cards ?? [] {
            for dishCard in card.groupedCard?.cardGroupMap?.DISH?.cards ?? [] {
                guard let group = dishCard.card?.card,
                      (group.type ?? "").contains("DishGroup"),
                      let info = group.restaurant?.info,
                      let id = info.id,
                      let name = info.name,
                      !name.isEmpty else { continue }

                let dishes = (group.dishes ?? []).compactMap { ref -> HypeDish? in
                    guard let dish = ref.info,
                          let dishID = dish.id,
                          let dishName = dish.name,
                          !dishName.isEmpty else { return nil }
                    return HypeDish(
                        id: dishID,
                        name: dishName,
                        price: Double(dish.price ?? 0) / 100,
                        isVeg: (dish.isVeg ?? 0) == 1,
                        description: dish.description
                    )
                }
                guard !dishes.isEmpty else { continue }

                let delivery = info.sla?.slaString
                    ?? info.sla?.deliveryTime.map { "\($0) min" }
                results.append(HypeRestaurantMenu(
                    id: id,
                    name: name,
                    cuisines: info.cuisines ?? [],
                    rating: info.avgRating,
                    costForTwo: info.costForTwoMessage,
                    deliveryTime: delivery,
                    distanceKm: info.sla?.lastMileTravel,
                    area: info.areaName,
                    address: info.address,
                    imageId: info.cloudinaryImageId,
                    swiggySlug: info.slugs?.restaurant,
                    dishes: dishes
                ))
            }
        }

        return results
    }

    // MARK: Swiggy response

    private struct SwiggyResponse: Decodable {
        struct DataBlock: Decodable { let cards: [Card]? }
        struct Card: Decodable { let groupedCard: Grouped? }
        struct Grouped: Decodable { let cardGroupMap: GroupMap? }
        struct GroupMap: Decodable { let DISH: CardList? }
        struct CardList: Decodable { let cards: [DishCard]? }
        struct DishCard: Decodable { let card: Body? }
        struct Body: Decodable { let card: DishGroup? }
        struct DishGroup: Decodable {
            let type: String?
            let restaurant: RestaurantRef?
            let dishes: [DishRef]?
            enum CodingKeys: String, CodingKey { case type = "@type", restaurant, dishes }
        }
        struct RestaurantRef: Decodable { let info: RestaurantInfo? }
        struct RestaurantInfo: Decodable {
            let id: String?
            let name: String?
            let cuisines: [String]?
            let avgRating: Double?
            let costForTwoMessage: String?
            let areaName: String?
            let address: String?
            let cloudinaryImageId: String?
            let slugs: Slugs?
            let sla: SLA?
        }
        struct Slugs: Decodable { let restaurant: String? }
        struct SLA: Decodable {
            let deliveryTime: Int?
            let lastMileTravel: Double?
            let slaString: String?
        }
        struct DishRef: Decodable { let info: DishInfo? }
        struct DishInfo: Decodable {
            let id: String?
            let name: String?
            let price: Int?
            let isVeg: Int?
            let description: String?
        }
        let data: DataBlock?
    }

    // MARK: Events

    func loadEvents() async {
        guard let place = selectedPlace else { return }
        loadingEvents = true
        eventNote = nil
        defer { loadingEvents = false }

        if place.isIndia {
            // Try District main page first (has events for major cities like Delhi, Mumbai)
            do {
                let district = try await districtEvents(place: place)
                if !district.isEmpty {
                    events = district
                    eventNote = "Live from District · \(place.shortName) · \(district.count) events"
                    return
                }
            } catch {
                eventNote = "District main page error. Trying \(place.shortName)'s city page…"
            }

            // Try city-specific upcoming-events page
            let slug = Self.districtCitySlug(place.shortName)
            do {
                let upcoming = try await Self.districtUpcomingEvents(slug: slug, targetCity: place.shortName)
                if !upcoming.isEmpty {
                    events = upcoming
                    eventNote = "Live from District · \(place.shortName) · \(upcoming.count) events"
                    return
                }
            } catch {
                eventNote = "District city page error. Trying nearby venues…"
            }

            // Fall back to local venue suggestions only when District truly has
            // no listings for this city (not on a transient parse miss).
            eventNote = "District has no live listings for \(place.shortName) right now. Showing venues you can open directly."
            events = await venueSuggestionsOrApple(place: place, useWideRadius: true)
            return
        }

        let key = ticketmasterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            do {
                events = try await ticketmasterEvents(key: key, place: place)
                if events.isEmpty {
                    eventNote = "No ticketed events listed nearby. Showing venues you can check directly."
                    events = await venueSuggestionsOrApple(place: place, useWideRadius: true)
                }
                return
            } catch {
                eventNote = "Ticketmaster didn't answer. Showing local venues instead."
            }
        } else {
            eventNote = "Add a free Ticketmaster key for dated events, or browse venues below."
        }

        events = await venueSuggestionsOrApple(place: place, useWideRadius: true)
        if events.isEmpty {
            error = "Couldn't load events. Check your connection and try again."
        }
    }

    // MARK: District events

    private func districtEvents(place: HypePlace) async throws -> [HypeEvent] {
        // Try main page first (has events for major cities like Delhi, Mumbai)
        var request = URLRequest(url: URL(string: "https://www.district.in/events")!)
        request.timeoutInterval = 25
        // Live listings must never come from a stale disk cache. District's
        // default page can roll between cities, and a cached copy once made
        // Delhi show Bengaluru concerts.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await Self.liveSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ToolError.message("District answered \(((response as? HTTPURLResponse)?.statusCode) ?? 0).")
        }
        let allEvents = Self.districtEvents(fromHTML: data)
        return Self.filterEventsByCity(allEvents, city: place.shortName)
    }

    /// Converts a city name to District's URL slug format (lowercase, hyphens)
    static func districtCitySlug(_ city: String) -> String {
        let name = city.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "'", with: "")
        // Handle common variations
        if name == "new-delhi" { return "new-delhi" }
        if name == "gurugram" || name == "gurgaon" { return "gurgaon" }
        if name == "bangalore" { return "bengaluru" }
        if name == "bombay" { return "mumbai" }
        if name == "calcutta" { return "kolkata" }
        if name == "madras" { return "chennai" }
        if name == "trivandrum" { return "thiruvananthapuram" }
        if name == "cochin" { return "kochi" }
        if name == "benaras" { return "varanasi" }
        if name == "pondicherry" { return "puducherry" }
        return name
    }

    /// Fetches events from District's city-specific upcoming events page
    private static func districtUpcomingEvents(slug: String, targetCity: String) async throws -> [HypeEvent] {
        let urlString = "https://www.district.in/events/upcoming-events-in-\(slug)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await Self.liveSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ToolError.message("District upcoming events: no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ToolError.message("District upcoming events answered \(http.statusCode) for \(urlString)")
        }
        let allEvents = districtEvents(fromHTML: data)
        // This page is already scoped to the requested city. A strict filter is
        // wrong here: District reports addressLocality as a neighbourhood
        // ("Dwarka"), a metro label ("Delhi/NCR") or an alias ("Bangalore"), so
        // matching only against the city name drops real events and forces the
        // venue fallback. Filter leniently, and keep every parsed event when the
        // filter would otherwise leave nothing.
        let filtered = filterEventsByCity(allEvents, city: targetCity)
        return filtered.isEmpty ? allEvents : filtered
    }

    /// District reports city names inconsistently: neighbourhoods ("Dwarka"),
    /// metro labels ("Delhi/NCR") and historical aliases ("Bangalore"). Match
    /// against every field we have and expand well-known alias pairs so real
    /// listings survive the city check.
    static func filterEventsByCity(_ events: [HypeEvent], city: String) -> [HypeEvent] {
        let targets = cityAliases(city)
        guard !targets.isEmpty else { return events }
        return events.filter { event in
            let haystack = [event.city, event.venue, event.title, event.urlString ?? ""]
                .joined(separator: " ")
                .lowercased()
            return targets.contains { haystack.contains($0) }
        }
    }

    /// Lowercased tokens that identify a city, including common Indian aliases
    /// and the individual parts of a compound label such as "Delhi/NCR".
    static func cityAliases(_ city: String) -> [String] {
        let base = city.lowercased()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return [] }

        var tokens: Set<String> = [base]
        for part in base.components(separatedBy: CharacterSet(charactersIn: "/,")) {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { tokens.insert(trimmed) }
        }

        let pairs: [(String, [String])] = [
            ("delhi", ["delhi", "new delhi", "delhi ncr", "ncr"]),
            ("bengaluru", ["bengaluru", "bangalore"]),
            ("bangalore", ["bengaluru", "bangalore"]),
            ("mumbai", ["mumbai", "bombay"]),
            ("bombay", ["mumbai", "bombay"]),
            ("gurugram", ["gurugram", "gurgaon"]),
            ("gurgaon", ["gurugram", "gurgaon"]),
            ("kolkata", ["kolkata", "calcutta"]),
            ("chennai", ["chennai", "madras"]),
            ("kochi", ["kochi", "cochin"]),
            ("thiruvananthapuram", ["thiruvananthapuram", "trivandrum"]),
            ("puducherry", ["puducherry", "pondicherry"]),
            ("varanasi", ["varanasi", "benaras", "banaras"]),
            ("noida", ["noida", "greater noida"]),
            ("hyderabad", ["hyderabad", "secunderabad"])
        ]
        for (key, values) in pairs where base.contains(key) {
            tokens.formUnion(values)
        }
        return Array(tokens)
    }

    static func districtEvents(fromHTML data: Data) -> [HypeEvent] {
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        let blocks = ldJSONBlocks(in: html)
        let now = Date()
        var results: [HypeEvent] = []

        for block in blocks {
            guard let object = try? JSONSerialization.jsonObject(with: Data(block.utf8)) as? [String: Any],
                  object["@type"] as? String == "ItemList",
                  let items = object["itemListElement"] as? [[String: Any]] else { continue }

            for wrapper in items {
                guard let item = wrapper["item"] as? [String: Any],
                      let title = item["name"] as? String,
                      !title.isEmpty else { continue }

                let start = Self.districtDate(item["startDate"] as? String)
                if let start, start < now.addingTimeInterval(-86_400) { continue }

                let location = item["location"] as? [String: Any]
                let address = location?["address"] as? [String: Any]
                let venue = location?["name"] as? String
                    ?? address?["addressLocality"] as? String
                    ?? "Venue to be announced"
                let city = address?["addressLocality"] as? String ?? ""
                let offer = item["offers"] as? [String: Any]
                let price = Self.districtPrice(offer?["price"] as? String)
                let images = item["image"] as? [String]
                let image = images?.first
                let url = item["url"] as? String

                results.append(HypeEvent(
                    id: "district-\(title.lowercased())-\(start?.timeIntervalSince1970 ?? 0)",
                    title: title,
                    venue: venue,
                    city: city,
                    dateLabel: start.map { Self.eventDateFormatter.string(from: $0) } ?? "Date to be announced",
                    startsAt: start,
                    priceLabel: price,
                    category: Self.eventCategory(title),
                    urlString: url,
                    imageURL: image,
                    isVenueSuggestion: false
                ))
            }
        }

        return results
            .sorted { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
            .prefix(14)
            .map { $0 }
    }

    static func districtDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }

    static func districtPrice(_ raw: String?) -> String {
        guard let raw, let value = Double(raw) else { return "See tickets" }
        if value <= 0 { return "Free entry" }
        return "From ₹\(Int(value.rounded()))"
    }

    static func eventCategory(_ title: String) -> String {
        let text = title.lowercased()
        if text.contains("comedy") || text.contains("laugh") || text.contains("stand-up") { return "Comedy" }
        if text.contains("concert") || text.contains("live") || text.contains("music") || text.contains("tour") { return "Music" }
        if text.contains("theatre") || text.contains("play") || text.contains("drama") { return "Theatre" }
        if text.contains("workshop") || text.contains("masterclass") { return "Workshop" }
        if text.contains("marathon") || text.contains("run") || text.contains("sport") { return "Sports" }
        if text.contains("kids") || text.contains("family") { return "Family" }
        if text.contains("food") || text.contains("dining") { return "Food" }
        return "Event"
    }

    static func ldJSONBlocks(in html: String) -> [String] {
        // Try modern ld+json format first
        let pattern = "<script type=\"application/ld\\+json\">(.*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var results: [String] = []
        regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
            guard let match, let blockRange = Range(match.range(at: 1), in: html) else { return }
            results.append(String(html[blockRange]))
        }
        if !results.isEmpty { return results }
        
        // Fallback: try without type attribute (some sites use plain ld+json)
        let pattern2 = "<script[^>]*ld\\+json[^>]*>(.*?)</script>"
        guard let regex2 = try? NSRegularExpression(pattern: pattern2, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return results }
        let range2 = NSRange(html.startIndex..<html.endIndex, in: html)
        regex2.enumerateMatches(in: html, options: [], range: range2) { match, _, _ in
            guard let match, let blockRange = Range(match.range(at: 1), in: html) else { return }
            results.append(String(html[blockRange]))
        }
        return results
    }

    private static let eventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM · h:mm a"
        return formatter
    }()

    /// Apple local search first, then OSM venue discovery when it has more.
    private func venueSuggestionsOrApple(place: HypePlace, useWideRadius: Bool = false) async -> [HypeEvent] {
        let apple = await appleEventVenues(place: place, useWideRadius: useWideRadius)
        if !apple.isEmpty { return apple }
        return (try? await venueSuggestions(place: place, useWideRadius: useWideRadius)) ?? []
    }

    // MARK: Cinemas

    func loadCinemas() async {
        guard let place = selectedPlace else { return }
        loadingCinemas = true
        defer { loadingCinemas = false }

        // Load nearby cinemas from OpenStreetMap/Apple first (actually near the user).
        var nearby: [HypeCinema] = await appleCinemas(place: place)

        let radius = Int(max(1, min(20, radiusKm)) * 1_000)
        let query = """
        [out:json][timeout:25];
        (
          node["amenity"="cinema"]["name"](around:\(radius),\(place.latitude),\(place.longitude));
          way["amenity"="cinema"]["name"](around:\(radius),\(place.latitude),\(place.longitude));
        );
        out center tags 40;
        """

        if nearby.isEmpty {
            do {
                let data = try await overpass(query)
                nearby = Self.cinemas(from: data, origin: place)
            } catch {
                nearby = []
            }
        }

        // For India, also pull District's major cinemas so the list has venues
        // with real movie showtimes, but only append those not already present.
        if place.isIndia {
            if let district = try? await districtCinemas(place: place), !district.isEmpty {
                let existing = Set(nearby.map { $0.name.lowercased() })
                let extra = district.filter { !existing.contains($0.name.lowercased()) }
                nearby.append(contentsOf: extra)
            }
        }

        cinemas = nearby.sorted { $0.distance < $1.distance }
    }

    // MARK: District movies

    func loadMovies() async {
        guard let place = selectedPlace else { return }
        loadingMovies = true
        movieNote = nil
        defer { loadingMovies = false }

        guard place.isIndia else {
            movies = []
            movieNote = nil
            return
        }

        var found = await districtMovieList(place: place)
        if found.isEmpty {
            found = await districtMoviesFromHTML(place: place)
            if !found.isEmpty {
                movieNote = "Showing District's movie list. Open a film for showtimes."
            } else {
                movieNote = "District didn't return showtimes. Browse movies on BookMyShow."
            }
        }

        let today = Calendar.current.startOfDay(for: Date())
        let withTimes = await withTaskGroup(of: (String, [HypeShowtime]).self) { group in
            for movie in found.prefix(6) {
                group.addTask { (movie.id, await self.districtShowtimes(movie: movie, date: today, place: place)) }
            }
            var map: [String: [HypeShowtime]] = [:]
            for await (id, times) in group { map[id] = times }
            return map
        }

        movies = found.map { movie in
            var copy = movie
            copy.showtimes = withTimes[movie.id] ?? movie.showtimes
            return copy
        }
        if movies.allSatisfy({ $0.showtimes.isEmpty }) {
            movieNote = "No showtimes listed for today yet. Open District or BookMyShow for the full schedule."
        }
    }

    private func districtMovieList(place: HypePlace) async -> [HypeMovie] {
        var components = URLComponents(string: "https://api.edition.in/gw/consumer/movies/v3/movies")
        components?.queryItems = [URLQueryItem(name: "city", value: Self.districtCity(place))]
        guard let url = components?.url else { return [] }
        guard let data = try? await districtJSON(url) else { return [] }
        return Self.districtMovies(from: data)
    }

    private func districtMoviesFromHTML(place: HypePlace) async -> [HypeMovie] {
        var request = URLRequest(url: URL(string: "https://www.district.in/movies")!)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await Self.liveSession.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return [] }
        return Self.districtMoviesFromHTML(data)
    }

    static func districtMovies(from data: Data) -> [HypeMovie] {
        guard let root = try? JSONDecoder().decode(DistrictMoviesResponse.self, from: data) else { return [] }
        return (root.data?.groupedMovies ?? []).compactMap { group -> HypeMovie? in
            guard let title = group.label, !title.isEmpty else { return nil }
            let languageGroup = group.languageFormatGroups?.first
            let format = languageGroup?.screenFormats?.first
            let contentId = group.contentId
            return HypeMovie(
                id: contentId.map(String.init) ?? title,
                title: title,
                language: languageGroup?.lang,
                format: group.scrnFmt?.first ?? format?.scrnFmt,
                genre: group.grn?.prefix(2).joined(separator: " · "),
                durationMinutes: group.duration,
                censor: group.censor,
                imageURL: group.appImgPath,
                urlString: contentId.map { districtMovieURL(title: title, contentId: $0) },
                movieCode: format?.movieCode,
                contentId: contentId,
                showtimes: []
            )
        }
    }

    static func districtMoviesFromHTML(_ data: Data) -> [HypeMovie] {
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        for block in ldJSONBlocks(in: html) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(block.utf8)) as? [String: Any],
                  object["@type"] as? String == "ItemList",
                  let items = object["itemListElement"] as? [[String: Any]] else { continue }
            let movies: [HypeMovie] = items.compactMap { wrapper in
                guard let name = wrapper["name"] as? String,
                      let url = wrapper["url"] as? String,
                      url.contains("/movies/") else { return nil }
                let id = url.components(separatedBy: "-MV").last ?? name
                return HypeMovie(
                    id: id,
                    title: name,
                    language: nil,
                    format: nil,
                    genre: nil,
                    durationMinutes: nil,
                    censor: nil,
                    imageURL: wrapper["image"] as? String,
                    urlString: url,
                    movieCode: nil,
                    contentId: Int(id),
                    showtimes: []
                )
            }
            if !movies.isEmpty { return movies }
        }
        return []
    }

    private func districtShowtimes(movie: HypeMovie, date: Date, place: HypePlace) async -> [HypeShowtime] {
        guard let code = movie.movieCode, !code.isEmpty,
              let contentId = movie.contentId else { return [] }

        var components = URLComponents(string: "https://www.district.in/gw/consumer/movies/v1/movie/sessions")
        components?.queryItems = [
            URLQueryItem(name: "movieCode", value: code),
            URLQueryItem(name: "city_key", value: Self.districtCity(place)),
            URLQueryItem(name: "content_id", value: String(contentId)),
            URLQueryItem(name: "date", value: Self.districtDayFormatter.string(from: date)),
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "cinemaOrderLogic", value: "3"),
            URLQueryItem(name: "version", value: "3"),
            URLQueryItem(name: "site_id", value: "1"),
            URLQueryItem(name: "channel", value: "ANDROIDAPPINSIDER"),
            URLQueryItem(name: "child_site_id", value: "1"),
            URLQueryItem(name: "platform", value: "district")
        ]
        guard let url = components?.url, let data = try? await districtJSON(url) else { return [] }
        return Self.districtShowtimes(from: data)
    }

    static func districtShowtimes(from data: Data) -> [HypeShowtime] {
        guard let root = try? JSONDecoder().decode(DistrictSessionsResponse.self, from: data) else { return [] }
        let cinemas = (root.pageData?.nearbyCinemas ?? []) + (root.pageData?.farCinemas ?? [])
        var results: [HypeShowtime] = []

        for cinema in cinemas {
            let name = cinema.cinemaInfo?.name ?? "Cinema"
            for session in cinema.sessions ?? [] {
                guard let raw = session.showTime else { continue }
                let price = session.areas?.compactMap(\.price).min()
                results.append(HypeShowtime(
                    id: session.sid ?? "\(name)-\(raw)",
                    cinema: name,
                    distanceKm: cinema.distanceFromUser,
                    time: Self.showtimeLabel(raw),
                    price: price.map { "₹\(Int($0.rounded()))" },
                    format: session.scrnFmt,
                    audi: session.audi
                ))
            }
        }
        return results.sorted { $0.time < $1.time }
    }

    private func districtCinemas(place: HypePlace) async throws -> [HypeCinema] {
        var components = URLComponents(string: "https://api.edition.in/gw/consumer/movies/v3/cinemas")
        components?.queryItems = [URLQueryItem(name: "city", value: Self.districtCity(place))]
        guard let url = components?.url else { return [] }
        let data = try await districtJSON(url)
        return Self.districtCinemas(from: data, origin: place)
    }

    static func districtCinemas(from data: Data, origin: HypePlace) -> [HypeCinema] {
        guard let root = try? JSONDecoder().decode(DistrictCinemasResponse.self, from: data) else { return [] }
        return (root.data?.cinemas ?? []).compactMap { cinema -> HypeCinema? in
            guard let name = cinema.name, !name.isEmpty,
                  let latitude = cinema.lat,
                  let longitude = cinema.lon else { return nil }
            return HypeCinema(
                id: cinema.id.map(String.init) ?? name,
                name: name,
                address: cinema.address,
                latitude: latitude,
                longitude: longitude,
                distance: distanceMeters(latitude, longitude, origin.latitude, origin.longitude)
            )
        }
        .sorted { $0.distance < $1.distance }
    }

    private func districtJSON(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("1212", forHTTPHeaderField: "x-guest-token")
        request.setValue("district-web", forHTTPHeaderField: "x-client-id")
        request.setValue("11.11.1", forHTTPHeaderField: "x-app-version")
        request.setValue("ed_web", forHTTPHeaderField: "x-app-type")
        request.setValue("district", forHTTPHeaderField: "api_source")

        let (data, response) = try await Self.liveSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ToolError.message("District answered \(((response as? HTTPURLResponse)?.statusCode) ?? 0).")
        }
        return data
    }

    /// District's movie API only accepts major city keys. Sub-localities such as
    /// "Rohini" or "Dwarka" must be mapped to their metro, otherwise the movie
    /// list and cinema showtimes come back empty and the user sees no timings.
    /// We check both the place name and its full display name (which Nominatim
    /// populates with the enclosing city) so typed searches and "My Location"
    /// both resolve correctly.
    static func districtCity(_ place: HypePlace) -> String {
        let haystack = (place.shortName + " " + place.displayName).lowercased()
        if haystack.contains("delhi") || haystack.contains("rohini") || haystack.contains("dwarka")
            || haystack.contains("gurugram") || haystack.contains("gurgaon") || haystack.contains("noida")
            || haystack.contains("faridabad") || haystack.contains("ghaziabad") || haystack.contains("greater noida") {
            return "Delhi"
        }
        if haystack.contains("mumbai") || haystack.contains("bombay") || haystack.contains("andheri")
            || haystack.contains("bandra") || haystack.contains("thane") || haystack.contains("navi mumbai")
            || haystack.contains("borivali") || haystack.contains("kurla") {
            return "Mumbai"
        }
        if haystack.contains("bengaluru") || haystack.contains("bangalore") || haystack.contains("whitefield")
            || haystack.contains("koramangala") || haystack.contains("indiranagar") || haystack.contains("hsr layout")
            || haystack.contains("electronic city") || haystack.contains("marathahalli") {
            return "Bengaluru"
        }
        if haystack.contains("hyderabad") || haystack.contains("secunderabad") { return "Hyderabad" }
        if haystack.contains("chennai") || haystack.contains("madras") { return "Chennai" }
        if haystack.contains("kolkata") || haystack.contains("calcutta") { return "Kolkata" }
        if haystack.contains("pune") { return "Pune" }
        if haystack.contains("ahmedabad") { return "Ahmedabad" }
        return place.shortName
    }

    static func districtMovieURL(title: String, contentId: Int) -> String {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "https://www.district.in/movies/\(slug)-movie-tickets-MV\(contentId)"
    }

    private static func showtimeLabel(_ raw: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        guard let date = parser.date(from: raw) else { return raw }
        let display = DateFormatter()
        display.dateFormat = "h:mm a"
        return display.string(from: date)
    }

    private static let districtDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private struct DistrictMoviesResponse: Decodable {
        struct DataBlock: Decodable { let groupedMovies: [Grouped]? }
        struct Grouped: Decodable {
            let label: String?
            let contentId: Int?
            let appImgPath: String?
            let censor: String?
            let duration: Int?
            let grn: [String]?
            let scrnFmt: [String]?
            let languageFormatGroups: [LanguageGroup]?
        }
        struct LanguageGroup: Decodable {
            let lang: String?
            let screenFormats: [ScreenFormat]?
        }
        struct ScreenFormat: Decodable {
            let movieCode: String?
            let scrnFmt: String?
            let nextAvailableDate: String?
        }
        let data: DataBlock?
    }

    private struct DistrictCinemasResponse: Decodable {
        struct DataBlock: Decodable { let cinemas: [Cinema]? }
        struct Cinema: Decodable {
            let id: Int?
            let name: String?
            let address: String?
            let lat: Double?
            let lon: Double?
        }
        let data: DataBlock?
    }

    private struct DistrictSessionsResponse: Decodable {
        struct PageData: Decodable {
            let nearbyCinemas: [CinemaBlock]?
            let farCinemas: [CinemaBlock]?
        }
        struct CinemaBlock: Decodable {
            let cinemaInfo: CinemaInfo?
            let distanceFromUser: Double?
            let sessions: [Session]?
        }
        struct CinemaInfo: Decodable {
            let name: String?
            let latitude: Double?
            let longitude: Double?
        }
        struct Session: Decodable {
            let sid: String?
            let showTime: String?
            let scrnFmt: String?
            let audi: String?
            let areas: [Area]?
        }
        struct Area: Decodable { let price: Double? }
        let pageData: PageData?
    }

    private func ticketmasterEvents(key: String, place: HypePlace) async throws -> [HypeEvent] {        var components = URLComponents(string: "https://app.ticketmaster.com/discovery/v2/events.json")
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: key),
            URLQueryItem(name: "latlong", value: "\(place.latitude),\(place.longitude)"),
            URLQueryItem(name: "radius", value: "\(max(25, Int(radiusKm * 4)))"),
            URLQueryItem(name: "unit", value: "km"),
            URLQueryItem(name: "size", value: "24"),
            URLQueryItem(name: "sort", value: "date,asc"),
            URLQueryItem(name: "locale", value: "*")
        ]
        guard let url = components?.url else { throw ToolError.message("Invalid event search.") }
        let data = try await fetch(url)

        struct Response: Decodable {
            struct Embedded: Decodable {
                let events: [Event]?
            }
            struct Event: Decodable {
                let id: String
                let name: String
                let url: String?
                let images: [Image]?
                let dates: Dates?
                let priceRanges: [Price]?
                let _embedded: EventEmbedded?
            }
            struct Image: Decodable {
                let url: String
                let width: Int?
                let ratio: String?
            }
            struct Dates: Decodable {
                let start: Start?
            }
            struct Start: Decodable {
                let localDate: String?
                let localTime: String?
                let dateTime: String?
            }
            struct Price: Decodable {
                let min: Double?
                let max: Double?
                let currency: String?
            }
            struct EventEmbedded: Decodable {
                let venues: [Venue]?
            }
            struct Venue: Decodable {
                let name: String?
                let city: City?
            }
            struct City: Decodable {
                let name: String?
            }
            let _embedded: Embedded?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateTimeFormatter = ISO8601DateFormatter()
        let display = DateFormatter()
        display.dateFormat = "EEE d MMM · h:mm a"

        return (decoded._embedded?.events ?? []).compactMap { item in
            let start = item.dates?.start
            var date: Date?
            if let raw = start?.dateTime {
                date = dateTimeFormatter.date(from: raw)
            } else if let raw = start?.localDate {
                date = formatter.date(from: raw)
            }

            let dateLabel: String
            if let date {
                dateLabel = display.string(from: date)
            } else if let raw = start?.localDate {
                dateLabel = raw
            } else {
                dateLabel = "Date to be announced"
            }

            let priceLabel: String
            if let range = item.priceRanges?.first, let min = range.min {
                let currency = range.currency ?? "USD"
                let symbol = currency == "USD" ? "$" : "\(currency) "
                if let max = range.max, max > min {
                    priceLabel = "\(symbol)\(Int(min))–\(symbol)\(Int(max))"
                } else {
                    priceLabel = "From \(symbol)\(Int(min))"
                }
            } else {
                priceLabel = "See ticket prices"
            }

            let image = item.images?
                .filter { $0.ratio == "16_9" }
                .max { ($0.width ?? 0) < ($1.width ?? 0) }?
                .url

            return HypeEvent(
                id: item.id,
                title: item.name,
                venue: item._embedded?.venues?.first?.name ?? place.shortName,
                city: item._embedded?.venues?.first?.city?.name ?? place.shortName,
                dateLabel: dateLabel,
                startsAt: date,
                priceLabel: priceLabel,
                category: "Event",
                urlString: item.url,
                imageURL: image,
                isVenueSuggestion: false
            )
        }
    }

    private func venueSuggestions(place: HypePlace, useWideRadius: Bool = false) async throws -> [HypeEvent] {
        let baseRadius = Int(max(1, min(20, radiusKm)) * 1_000)
        let radius = useWideRadius ? baseRadius * 3 : baseRadius
        let query = """
        [out:json][timeout:25];
        (
          node["amenity"~"^(theatre|cinema|arts_centre|nightclub|music_venue|community_centre)$"]["name"](around:\(radius),\(place.latitude),\(place.longitude));
          way["amenity"~"^(theatre|cinema|arts_centre|nightclub|music_venue|community_centre)$"]["name"](around:\(radius),\(place.latitude),\(place.longitude));
          node["tourism"~"^(museum|gallery)$"]["name"](around:\(radius),\(place.latitude),\(place.longitude));
          node["leisure"~"^(stadium|sports_centre)$"]["name"](around:\(radius),\(place.latitude),\(place.longitude));
        );
        out center tags 60;
        """
        let data = try await overpass(query)

        struct Response: Decodable {
            struct Element: Decodable {
                struct Center: Decodable {
                    let lat: Double?
                    let lon: Double?
                }
                let type: String
                let id: Int
                let lat: Double?
                let lon: Double?
                let center: Center?
                let tags: [String: String]?
            }
            let elements: [Element]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var seen = Set<String>()
        var results: [HypeEvent] = []

        for element in decoded.elements {
            guard let tags = element.tags, let name = tags["name"], !name.isEmpty else { continue }
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let kind = tags["amenity"] ?? tags["tourism"] ?? tags["leisure"] ?? "venue"
            let queryText = "events at \(name) \(place.shortName)"
            let url = "https://www.google.com/search?q=\(queryText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

            results.append(HypeEvent(
                id: "venue-\(element.type)-\(element.id)",
                title: name,
                venue: name,
                city: place.shortName,
                dateLabel: Self.kindLabel(kind) + " · check listings",
                startsAt: nil,
                priceLabel: "See listings",
                category: Self.kindLabel(kind),
                urlString: url,
                imageURL: nil,
                isVenueSuggestion: true
            ))
        }

        return results.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: Apple local search

    /// MapKit local search is available without an API key and is far more
    /// reliable than the public Overpass instances. It supplies names, phones,
    /// websites and street addresses for food, cinemas and event venues.
    private func appleSearch(_ query: String, place: HypePlace, radius: Double? = nil) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.pointOfInterestFilter = .includingAll
        let meters = max(2_000, min(50_000, (radius ?? radiusKm * 1_000) * 2.2))
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )

        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start() else { return [] }
        return response.mapItems
    }

    private func appleFoodVenues(place: HypePlace) async -> [HypeVenue] {
        let queries = ["restaurants", "cafes", "fast food", "bakeries", "bars", "grocery stores"]
        var items: [MKMapItem] = []
        await withTaskGroup(of: [MKMapItem].self) { group in
            for query in queries {
                group.addTask { await self.appleSearch(query, place: place) }
            }
            for await batch in group {
                items.append(contentsOf: batch)
            }
        }

        let limit = max(1_200, radiusKm * 1_000 * 1.4)
        var seen = Set<String>()
        var results: [HypeVenue] = []

        for item in items {
            let name = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let coordinate = item.placemark.coordinate
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            let distance = Self.distanceMeters(coordinate.latitude, coordinate.longitude, place.latitude, place.longitude)
            guard distance <= limit else { continue }
            seen.insert(key)

            let address = item.placemark.title?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(HypeVenue(
                id: "apple-\(name.lowercased())-\(String(format: "%.4f", coordinate.latitude))",
                name: name,
                kind: Self.appleKind(item.pointOfInterestCategory?.rawValue),
                cuisine: nil,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                distance: distance,
                priceTier: 2,
                address: (address?.isEmpty == false) ? address : nil,
                website: item.url?.absoluteString,
                phone: item.phoneNumber,
                openingHours: nil
            ))
        }

        return results.sorted { $0.distance < $1.distance }
    }

    private func appleCinemas(place: HypePlace) async -> [HypeCinema] {
        let items = await appleSearch("cinema", place: place)
        let limit = max(1_500, radiusKm * 1_000 * 1.4)
        var seen = Set<String>()
        var results: [HypeCinema] = []

        for item in items {
            let name = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let coordinate = item.placemark.coordinate
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            let distance = Self.distanceMeters(coordinate.latitude, coordinate.longitude, place.latitude, place.longitude)
            guard distance <= limit else { continue }
            seen.insert(key)

            let address = item.placemark.title?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(HypeCinema(
                id: "apple-\(name.lowercased())-\(String(format: "%.4f", coordinate.latitude))",
                name: name,
                address: (address?.isEmpty == false) ? address : nil,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                distance: distance
            ))
        }

        return results.sorted { $0.distance < $1.distance }
    }

    private func appleEventVenues(place: HypePlace, useWideRadius: Bool = false) async -> [HypeEvent] {
        let baseQueries = ["theatre", "concert venue", "event venue", "museum", "comedy club"]
        let wideQueries = baseQueries + ["auditorium", "cultural centre", "performing arts", "stadium", "arena", "exhibition centre"]
        let queries = useWideRadius ? wideQueries : baseQueries
        let radiusKmLocal = radiusKm
        var items: [MKMapItem] = []
        await withTaskGroup(of: [MKMapItem].self) { group in
            for query in queries {
                group.addTask { await self.appleSearch(query, place: place, radius: useWideRadius ? radiusKmLocal * 2.5 : nil) }
            }
            for await batch in group {
                items.append(contentsOf: batch)
            }
        }

        let multiplier = useWideRadius ? 2.5 : 1.4
        let limit = max(1_500, radiusKm * 1_000 * multiplier)
        var seen = Set<String>()
        var results: [HypeEvent] = []

        for item in items {
            let name = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let coordinate = item.placemark.coordinate
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            let distance = Self.distanceMeters(coordinate.latitude, coordinate.longitude, place.latitude, place.longitude)
            guard distance <= limit else { continue }
            seen.insert(key)

            let category = Self.appleCategory(item.pointOfInterestCategory?.rawValue)
            let queryText = "events at \(name) \(place.shortName)"
            let url = "https://www.google.com/search?q=\(queryText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

            results.append(HypeEvent(
                id: "apple-venue-\(name.lowercased())-\(String(format: "%.4f", coordinate.latitude))",
                title: name,
                venue: name,
                city: place.shortName,
                dateLabel: "\(category) · check listings",
                startsAt: nil,
                priceLabel: "See listings",
                category: category,
                urlString: url,
                imageURL: nil,
                isVenueSuggestion: true
            ))
        }

        return results.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func appleKind(_ raw: String?) -> String {
        let value = (raw ?? "").lowercased()
        if value.contains("cafe") { return "cafe" }
        if value.contains("bakery") { return "bakery" }
        if value.contains("brewery") || value.contains("winery") || value.contains("nightlife") { return "bar" }
        if value.contains("foodmarket") || value.contains("market") { return "marketplace" }
        if value.contains("fastfood") { return "fast_food" }
        return "restaurant"
    }

    static func appleCategory(_ raw: String?) -> String {
        let value = (raw ?? "").lowercased()
        if value.contains("movie") || value.contains("cinema") { return "Cinema" }
        if value.contains("theater") || value.contains("theatre") { return "Theatre" }
        if value.contains("museum") { return "Museum" }
        if value.contains("music") || value.contains("concert") { return "Music venue" }
        if value.contains("nightlife") { return "Nightlife" }
        return "Venue"
    }

    // MARK: Travel

    var travelProviderName: String {
        HypeRouting.travelProviderName(mode: travelMode, place: selectedPlace)
    }

    var travelURL: URL? {
        let from = origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (selectedPlace?.shortName ?? "City centre")
            : origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !to.isEmpty else { return nil }

        return HypeRouting.travelURL(
            mode: travelMode,
            from: from,
            to: to,
            depart: departDate,
            ret: returnDate,
            travelers: travelers,
            place: selectedPlace
        )
    }

    /// A second live source, so a blocked or changed booking site never leaves
    /// the user without prices. Only shown where it adds a real alternative.
    var alternateTravelURL: URL? {
        guard selectedPlace?.isIndia == true else { return nil }
        let from = origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (selectedPlace?.shortName ?? "City centre")
            : origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !to.isEmpty else { return nil }
        return HypeRouting.alternateTravelURL(
            mode: travelMode,
            from: from,
            to: to,
            depart: departDate,
            ret: returnDate,
            travelers: travelers,
            place: selectedPlace
        )
    }

    var alternateTravelName: String {
        switch travelMode {
        case .flights: return "Google Flights"
        case .hotels: return "Booking.com"
        case .trains: return "Rome2Rio"
        }
    }

    // MARK: Helpers

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Nookit/0.1 (macOS; support@nookit.app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await Self.liveSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ToolError.message("No response from the map service.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ToolError.message("Map service answered \(http.statusCode).")
        }
        return data
    }

    private static let overpassEndpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter"
    ]

    /// Races the public Overpass mirrors and returns the first healthy answer.
    /// These instances regularly shed load, so one bad host must never decide
    /// whether Hype works.
    private func overpass(_ query: String) async throws -> Data {
        let encoded = "data=" + (query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        let body = Data(encoded.utf8)

        return try await withThrowingTaskGroup(of: Result<Data, Error>.self) { group in
            for endpoint in Self.overpassEndpoints {
                group.addTask {
                    do {
                        guard let url = URL(string: endpoint) else {
                            throw ToolError.message("Invalid map endpoint.")
                        }
                        var request = URLRequest(url: url)
                        request.httpMethod = "POST"
                        request.timeoutInterval = 30
                        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                        request.setValue("Nookit/0.1 (macOS; support@nookit.app)", forHTTPHeaderField: "User-Agent")
                        request.httpBody = body
                        let (data, response) = try await Self.liveSession.data(for: request)
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                            throw ToolError.message("OpenStreetMap is busy right now.")
                        }
                        return .success(data)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var lastError: Error = ToolError.message("OpenStreetMap is busy right now.")
            while let result = try await group.next() {
                switch result {
                case .success(let data):
                    group.cancelAll()
                    return data
                case .failure(let error):
                    lastError = error
                }
            }
            throw lastError
        }
    }

    private static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "theatre": return "Theatre"
        case "cinema": return "Cinema"
        case "arts_centre": return "Arts centre"
        case "nightclub": return "Nightclub"
        case "music_venue": return "Music venue"
        case "community_centre": return "Community centre"
        case "museum": return "Museum"
        case "gallery": return "Gallery"
        case "stadium": return "Stadium"
        case "sports_centre": return "Sports centre"
        default: return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func priceTier(tags: [String: String], kind: String) -> Int {
        if let raw = tags["price"]?.lowercased() {
            if raw.contains("cheap") || raw.contains("budget") { return 1 }
            let dollars = raw.filter { $0 == "$" }.count
            if dollars > 0 { return min(4, max(1, dollars)) }
            if let value = Double(raw), value > 0 {
                if value <= 10 { return 1 }
                if value <= 25 { return 2 }
                if value <= 60 { return 3 }
                return 4
            }
        }
        if let cuisine = tags["cuisine"]?.lowercased(),
           cuisine.contains("fine") || cuisine.contains("haute") {
            return 4
        }
        if let name = tags["name"]?.lowercased(),
           name.contains("michelin") || name.contains("fine dining") {
            return 4
        }

        switch kind {
        case "fast_food", "food_court", "marketplace", "convenience":
            return 1
        case "cafe", "bakery", "ice_cream", "deli", "greengrocer", "pub", "bar":
            return 2
        default:
            return 2
        }
    }

    static func venues(from data: Data, origin: HypePlace) -> [HypeVenue] {
        struct Response: Decodable {
            struct Element: Decodable {
                struct Center: Decodable {
                    let lat: Double?
                    let lon: Double?
                }
                let type: String
                let id: Int
                let lat: Double?
                let lon: Double?
                let center: Center?
                let tags: [String: String]?
            }
            let elements: [Element]
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        var seen = Set<String>()
        var results: [HypeVenue] = []

        for element in decoded.elements {
            guard let tags = element.tags,
                  let name = tags["name"],
                  !name.isEmpty else { continue }

            let latitude = element.lat ?? element.center?.lat
            let longitude = element.lon ?? element.center?.lon
            guard let latitude, let longitude else { continue }

            let key = "\(name.lowercased())-\(String(format: "%.3f", latitude))-\(String(format: "%.3f", longitude))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let kind = tags["amenity"] ?? tags["shop"] ?? "restaurant"
            let address = [tags["addr:housenumber"], tags["addr:street"]]
                .compactMap { $0 }
                .joined(separator: " ")
            let addressText = address.isEmpty ? nil : ([address, tags["addr:city"]].compactMap { $0 }.joined(separator: ", "))

            results.append(HypeVenue(
                id: "\(element.type)-\(element.id)",
                name: name,
                kind: kind,
                cuisine: tags["cuisine"]?.replacingOccurrences(of: ";", with: ", "),
                latitude: latitude,
                longitude: longitude,
                distance: distanceMeters(latitude, longitude, origin.latitude, origin.longitude),
                priceTier: priceTier(tags: tags, kind: kind),
                address: addressText,
                website: tags["website"] ?? tags["contact:website"],
                phone: tags["phone"] ?? tags["contact:phone"],
                openingHours: tags["opening_hours"]
            ))
        }

        return results.sorted {
            if $0.priceTier != $1.priceTier { return $0.priceTier < $1.priceTier }
            if abs($0.distance - $1.distance) > 1 { return $0.distance < $1.distance }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func cinemas(from data: Data, origin: HypePlace) -> [HypeCinema] {
        struct Response: Decodable {
            struct Element: Decodable {
                struct Center: Decodable {
                    let lat: Double?
                    let lon: Double?
                }
                let type: String
                let id: Int
                let lat: Double?
                let lon: Double?
                let center: Center?
                let tags: [String: String]?
            }
            let elements: [Element]
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        var seen = Set<String>()
        var results: [HypeCinema] = []

        for element in decoded.elements {
            guard let tags = element.tags, let name = tags["name"], !name.isEmpty else { continue }
            let latitude = element.lat ?? element.center?.lat
            let longitude = element.lon ?? element.center?.lon
            guard let latitude, let longitude else { continue }
            let key = "\(name.lowercased())-\(String(format: "%.3f", latitude))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let address = [tags["addr:housenumber"], tags["addr:street"]]
                .compactMap { $0 }
                .joined(separator: " ")

            results.append(HypeCinema(
                id: "\(element.type)-\(element.id)",
                name: name,
                address: address.isEmpty ? nil : address,
                latitude: latitude,
                longitude: longitude,
                distance: distanceMeters(latitude, longitude, origin.latitude, origin.longitude)
            ))
        }

        return results.sorted { $0.distance < $1.distance }
    }

    static func distanceMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radius = 6_371_000.0
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let deltaPhi = (lat2 - lat1) * .pi / 180
        let deltaLambda = (lon2 - lon1) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

// MARK: - Provider routing

/// Builds the live provider URLs Hype hands off to. India routes to the apps
/// people actually use there (Swiggy, Zomato, District, BookMyShow, MakeMyTrip);
/// everywhere else uses DoorDash, OpenTable, Ticketmaster and Google/Booking.
enum HypeRouting {
    private static let indiaAirports: [String: String] = [
        "new delhi": "DEL", "delhi": "DEL",
        "mumbai": "BOM", "bombay": "BOM",
        "bengaluru": "BLR", "bangalore": "BLR",
        "hyderabad": "HYD", "chennai": "MAA", "madras": "MAA",
        "kolkata": "CCU", "calcutta": "CCU",
        "pune": "PNQ", "ahmedabad": "AMD", "goa": "GOI",
        "kochi": "COK", "cochin": "COK", "jaipur": "JAI",
        "lucknow": "LKO", "chandigarh": "IXC", "guwahati": "GAU",
        "thiruvananthapuram": "TRV", "coimbatore": "CJB",
        "indore": "IDR", "bhopal": "BHO", "nagpur": "NAG",
        "varanasi": "VNS", "patna": "PAT", "srinagar": "SXR",
        "amritsar": "ATQ", "udaipur": "UDR", "agra": "AGR",
        "surat": "STV", "vadodara": "BDQ", "rajkot": "RAJ"
    ]

    private static let indiaCitySlugs: [String: String] = [
        "bengaluru": "bengaluru", "bangalore": "bengaluru",
        "new delhi": "delhi-ncr", "delhi": "delhi-ncr", "gurugram": "gurugram",
        "gurgaon": "gurugram", "noida": "noida", "ghaziabad": "ghaziabad",
        "mumbai": "mumbai", "hyderabad": "hyderabad", "chennai": "chennai",
        "kolkata": "kolkata", "pune": "pune", "ahmedabad": "ahmedabad",
        "chandigarh": "chandigarh", "kochi": "kochi", "jaipur": "jaipur",
        "lucknow": "lucknow"
    ]

    static func foodOrderURL(venue: HypeVenue, place: HypePlace?) -> URL? {
        let name = venue.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if place?.isIndia == true {
            var components = URLComponents(string: "https://www.swiggy.com/search")
            components?.queryItems = [URLQueryItem(name: "query", value: name)]
            return components?.url
        }
        var components = URLComponents(string: "https://www.ubereats.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: name)]
        return components?.url
    }

    static func tableBookingURL(venue: HypeVenue, place: HypePlace?) -> URL? {
        let name = venue.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if place?.isIndia == true {
            var components = URLComponents(string: "https://www.zomato.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: name)]
            return components?.url
        }
        var components = URLComponents(string: "https://www.opentable.com/s")
        components?.queryItems = [
            URLQueryItem(name: "term", value: name),
            URLQueryItem(name: "covers", value: "2")
        ]
        return components?.url
    }

    static func moviesURL(place: HypePlace?) -> URL? {
        guard let place else {
            return URL(string: "https://www.google.com/search?q=movie+showtimes+near+me")
        }
        if place.isIndia {
            return URL(string: "https://in.bookmyshow.com/explore/movies-\(citySlug(place.shortName))")
        }
        return URL(string: "https://www.google.com/search?q=\(query("movie showtimes \(place.shortName)"))")
    }

    static func eventsURL(place: HypePlace?) -> URL? {
        if place?.isIndia == true {
            return URL(string: "https://www.district.in/events")
        }
        let text = place.map { "events in \($0.shortName)" } ?? "events near me"
        return URL(string: "https://www.ticketmaster.com/search?q=\(query(text))")
    }

    static func travelProviderName(mode: HypeTravelMode, place: HypePlace?) -> String {
        switch mode {
        case .flights: return "Google Flights"
        case .hotels: return "Google Hotels"
        case .trains: return "eRail"
        }
    }

    static func travelURL(
        mode: HypeTravelMode,
        from: String,
        to: String,
        depart: Date,
        ret: Date,
        travelers: Int,
        place: HypePlace?
    ) -> URL? {
        let currency = place?.isIndia == true ? "INR" : "USD"
        return globalTravelURL(
            mode: mode,
            from: from,
            to: to,
            depart: depart,
            ret: ret,
            travelers: travelers,
            currency: currency
        )
    }

    static func globalTravelURL(
        mode: HypeTravelMode,
        from: String,
        to: String,
        depart: Date,
        ret: Date,
        travelers: Int,
        currency: String
    ) -> URL? {
        switch mode {
        case .flights:
            var components = URLComponents(string: "https://www.google.com/travel/flights")
            let fromText = airportCode(from) ?? from
            let toText = airportCode(to) ?? to
            let day = isoDayFormatter.string(from: depart)
            components?.queryItems = [
                URLQueryItem(name: "q", value: "Flights from \(fromText) to \(toText) on \(day) one way"),
                URLQueryItem(name: "curr", value: currency),
                URLQueryItem(name: "hl", value: "en")
            ]
            return components?.url
        case .hotels:
            var components = URLComponents(string: "https://www.booking.com/searchresults.html")
            components?.queryItems = [
                URLQueryItem(name: "ss", value: to),
                URLQueryItem(name: "checkin", value: dayFormatter.string(from: depart)),
                URLQueryItem(name: "checkout", value: dayFormatter.string(from: ret)),
                URLQueryItem(name: "group_adults", value: "\(max(1, travelers))"),
                URLQueryItem(name: "no_rooms", value: "1"),
                URLQueryItem(name: "selected_currency", value: currency)
            ]
            return components?.url
        case .trains:
            let fromPath = from.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? from
            let toPath = to.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? to
            return URL(string: "https://www.rome2rio.com/s/\(fromPath)/\(toPath)")
        }
    }

    static func alternateTravelURL(
        mode: HypeTravelMode,
        from: String,
        to: String,
        depart: Date,
        ret: Date,
        travelers: Int,
        place: HypePlace?
    ) -> URL? {
        guard place?.isIndia == true else { return nil }
        return globalTravelURL(
            mode: mode,
            from: from,
            to: to,
            depart: depart,
            ret: ret,
            travelers: travelers,
            currency: "INR"
        )
    }

    static func airportCode(_ city: String) -> String? {
        let key = city.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if key.count == 3, key.allSatisfy({ $0.isLetter }) {
            return key.uppercased()
        }
        for (name, code) in indiaAirports.sorted(by: { $0.key.count > $1.key.count }) {
            if key == name || key.contains(name) { return code }
        }
        return nil
    }

    static func citySlug(_ city: String) -> String {
        let key = city.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let slug = indiaCitySlugs[key] { return slug }
        return key.replacingOccurrences(of: " ", with: "-")
    }

    private static func query(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    /// Google Flights reads ISO dates in its natural-language `q` parameter;
    /// `dd/MM/yyyy` is silently ignored there.
    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()
}

// MARK: - One-shot location

/// Bridges CoreLocation's delegate callbacks to a single async request.
final class LocationResolver: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var settled = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func current() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.settled = false

            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorized:
                manager.requestLocation()
            default:
                finish(nil)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        guard !settled else { return }
        settled = true
        continuation?.resume(returning: location)
        continuation = nil
    }
}
