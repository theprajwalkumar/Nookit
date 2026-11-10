import SwiftUI
import AppKit

/// Hype turns a city into something usable: food you can order or book, events
/// and movies you can actually attend, and live travel prices from the sites
/// that sell them.
enum TravelTripType: String, CaseIterable, Identifiable {
    case oneWay = "One way"
    case roundTrip = "Round trip"
    var id: String { rawValue }
}

struct HypeScreen: View {
    @ObservedObject private var hype = HypeService.shared

    @State private var tab: HypeTab = .food
    @State private var radiusDraft: Double = 3
    @State private var showEventsKey = false
    @State private var browserTarget: BrowserTarget?
    @State private var travelBrowser: BrowserTarget?
    @State private var travelTripType: TravelTripType = .oneWay
    @State private var travelFlights: [TravelFlight] = []
    @State private var travelReturnFlights: [TravelFlight] = []
    @State private var travelHotels: [TravelHotel] = []
    @State private var travelTrains: [TravelTrain] = []
    @State private var travelReturnTrains: [TravelTrain] = []
    @State private var travelLoading = false
    @State private var travelError: String?
    @State private var travelSummary: String?
    @State private var travelTask: Task<Void, Never>?
    @State private var hoveredTravelCard: String?
    @State private var selectedVenue: HypeVenue?
    @State private var selectedMenu: HypeRestaurantMenu?
    @State private var eventProvider: HypeEventProvider = .district
    @State private var appeared = false
    @State private var hoveredMode: HypeTravelMode?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            HypeTabGlow(tab: tab)

            VStack(spacing: 0) {
                header
                Divider().overlay(Theme.line)
                locationBar
                Divider().overlay(Theme.line)

                tabsBar
                Divider().overlay(Theme.line)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            switch tab {
                            case .food: food
                            case .events: events
                            case .travel: travel
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 18)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 1180, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hypeEntrance(appeared, index: 0)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                    .scrollIndicators(.never)
                    .onChange(of: travelSummary) { _, value in
                        guard value != nil, tab == .travel else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(160))
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("travelResults", anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.35)) { appeared = true }
            await hype.loadIfNeeded()
        }
        .onChange(of: hype.radiusKm) { _, value in
            radiusDraft = value
        }
        .onChange(of: hype.travelMode) { _, _ in
            clearTravelResults()
        }
        .onChange(of: hype.foodCategory) { _, _ in
            guard hype.selectedPlace?.isIndia == true else { return }
            Task { await hype.loadRestaurantMenus() }
        }
        .sheet(item: $browserTarget) { target in
            WebBrowserSheet(title: target.title, url: target.url)
        }
        .sheet(item: $selectedVenue) { venue in
            VenueDetailSheet(venue: venue, place: hype.selectedPlace)
        }
        .sheet(item: $selectedMenu) { menu in
            RestaurantMenuDetailSheet(menu: menu, place: hype.selectedPlace, foodProvider: hype.foodProvider)
        }
        .sheet(item: $travelBrowser) { target in
            WebBrowserSheet(title: target.title, url: target.url, onClose: { travelBrowser = nil })
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.ember, Theme.ember.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x160A04))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Hype")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Order food, book tables, catch movies, plan travel.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if hype.loadingFood || hype.loadingMenus || hype.loadingEvents || hype.loadingMovies || hype.loadingCinemas || hype.locating || hype.searchingPlaces {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Looking around…")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                if hype.selectedPlace != nil {
                    Button {
                        Task { await hype.loadAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(
                                (hype.loadingFood || hype.loadingMenus || hype.loadingEvents || hype.loadingMovies || hype.loadingCinemas)
                                ? Theme.textTertiary : Theme.ember
                            )
                            .frame(width: 26, height: 26)
                            .background(Theme.ember.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Refresh everything")
                    .disabled(hype.loadingFood || hype.loadingMenus || hype.loadingEvents || hype.loadingMovies || hype.loadingCinemas)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
    }

    // MARK: - Location

    private var locationBar: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ember)
                TextField("Search for a city…", text: $hype.placeQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit {
                        searchTask?.cancel()
                        Task { await hype.searchPlaces() }
                    }
                    .onChange(of: hype.placeQuery) { _, newValue in
                        searchTask?.cancel()
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.count < 2 {
                            hype.clearSuggestions()
                            return
                        }
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            guard !Task.isCancelled else { return }
                            guard hype.selectedPlace?.shortName.lowercased() != trimmed.lowercased() else { return }
                            await hype.searchPlaces()
                        }
                    }
                if !hype.placeQuery.isEmpty {
                    Button {
                        hype.placeQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))

            if hype.searchingPlaces {
                ProgressView().controlSize(.small)
                    .frame(width: 28)
            }

            // Suggestions are shown as a live dropdown below the search field
            // (see the VStack below), so no separate "check suggestions" button.

            if hype.locating {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await hype.useCurrentLocation() }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.ember)
                        Text(hype.selectedPlace?.shortName ?? "My Location")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 58)
                    }
                    .frame(width: 64, height: 44)
                    .background(Theme.ember.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(hype.selectedPlace?.displayName ?? "Use current location")
            }

            if hype.selectedPlace != nil {
                Menu {
                    ForEach(hype.recentPlaces) { recent in
                        Button(recent.shortName) {
                            Task { await hype.select(recent) }
                        }
                    }
                    Divider()
                    Button("Clear", role: .destructive) {
                        hype.clearPlace()
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .menuStyle(.borderlessButton)
                .help("Recent places")
            }
        }

        if !hype.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(hype.suggestions) { place in
                    Button {
                        searchTask?.cancel()
                        Task { await hype.select(place) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.ember)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(place.shortName)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text(place.displayName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }

        if let place = hype.selectedPlace {
            currentLocationSummary(place)
        }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
    }

    /// Shows the resolved location's proper title plus its full address so the
    /// user can confirm exactly where "My Location" landed.
    private func currentLocationSummary(_ place: HypePlace) -> some View {
        let address = Self.addressRemainder(for: place)
        return HStack(spacing: 6) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ember)
            Text(place.shortName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if !address.isEmpty {
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Text(address)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .help(place.displayName)
    }

    /// Drops the leading place name from the full display name so the title and
    /// address don't repeat, e.g. "Bengaluru, Karnataka, India" → "Karnataka, India".
    private static func addressRemainder(for place: HypePlace) -> String {
        let full = place.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard full.lowercased().hasPrefix(place.shortName.lowercased()) else { return full }
        let remainder = full.dropFirst(place.shortName.count)
        return remainder.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
    }

    // MARK: - Tabs

    @Namespace private var tabNamespace

    private var tabsBar: some View {
        HStack(spacing: 0) {
            tabs
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .frame(maxWidth: 1180, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(HypeTab.allCases) { item in
                let active = tab == item
                let count = badge(for: item)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        tab = item
                    }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 13, weight: active ? .semibold : .medium))
                            Text(item.title)
                                .font(.system(size: 13.5, weight: active ? .semibold : .medium))
                            if let count, count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(active ? Theme.ember : Theme.textTertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background((active ? Theme.ember : Theme.textTertiary).opacity(0.12), in: Capsule())
                            }
                        }
                        .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(active ? Theme.ember.opacity(0.08) : Color.clear)
                        )
                        if active {
                            Rectangle()
                                .fill(Theme.ember)
                                .frame(height: 2.5)
                                .matchedGeometryEffect(id: "tabbar", in: tabNamespace)
                        } else {
                            // Reserve the same height so the bar never jumps.
                            Color.clear.frame(height: 2.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(false)
                .contentShape(Rectangle())
            }
        }
        .padding(4)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func badge(for item: HypeTab) -> Int? {
        switch item {
        case .food:
            return hype.selectedPlace?.isIndia == true ? hype.menusWithFilteredDishes().count : hype.filteredVenues.count
        case .events:
            return hype.events.count + hype.movies.count + hype.cinemas.count
        case .travel:
            return nil
        }
    }

    // MARK: - Food

    @ViewBuilder
    private var food: some View {
        if hype.selectedPlace == nil {
            emptyState(
                symbol: "fork.knife",
                title: "Find something good nearby",
                message: "Search for a city or use your current location. Then order delivery, book a table, or open the restaurant's own page."
            )
        } else if hype.selectedPlace?.isIndia == true {
            indiaFood
        } else {
            globalFood
        }
    }

    private var foodHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            SectionHeader(
                title: "Food around \(hype.selectedPlace?.shortName ?? "you")",
                subtitle: hype.selectedPlace?.isIndia == true
                    ? "Restaurant names and real dishes, live from Swiggy."
                    : "Order online, book a table, or check the menu."
            )

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await hype.loadRestaurantMenus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hype.loadingMenus ? Theme.textTertiary : Theme.ember)
                        .frame(width: 26, height: 26)
                        .background(Theme.ember.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Refresh menus")
                .disabled(hype.loadingMenus)

                Image(systemName: "circle.dashed")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                Slider(value: $radiusDraft, in: 0.5...15, step: 0.5) { editing in
                    guard !editing else { return }
                    hype.radiusKm = radiusDraft
                    Task {
                        await hype.loadNearby()
                        await hype.loadCinemas()
                    }
                }
                .frame(width: 120)
                .tint(Theme.ember)
                Text("\(String(format: "%.1f", radiusDraft)) km")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }
        }
    }

    private var indiaFood: some View {
        VStack(alignment: .leading, spacing: 14) {
            foodHeader
            foodProviderPicker
            vegFilterChips
            dishSearch
            categoryChips

            if hype.loadingMenus && hype.restaurantMenus.isEmpty {
                loadingState("Reading live menus from Swiggy…")
            } else {
                let menus = hype.menusWithFilteredDishes()
                if menus.isEmpty {
                    emptyState(
                        symbol: "fork.knife.circle",
                        title: hype.vegFilter == .all ? "No menus for this craving" : "No \(hype.vegFilter.title.lowercased()) dishes found",
                        message: hype.error ?? "Try a different dish, category, or veg filter, or widen the radius."
                    )
                    nearbyVenueSection
                } else {
                    HStack {
                        Text("Restaurants & menus")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(menus.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.line.opacity(0.5), in: Capsule())
                        Spacer()
                        Text("Dish names and prices are live")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.top, 2)

                    LazyVStack(spacing: 10) {
                        ForEach(Array(menus.enumerated()), id: \.element.id) { index, menu in
                            restaurantCard(menu, index: index)
                        }
                    }

                    nearbyVenueSection
                }
            }
        }
    }

    private var globalFood: some View {
        VStack(alignment: .leading, spacing: 14) {
            foodHeader
            categoryChips

            if hype.loadingFood && hype.venues.isEmpty {
                loadingState("Reading nearby restaurants and markets…")
            } else if hype.venues.isEmpty {
                emptyState(
                    symbol: "fork.knife.circle",
                    title: "Nothing tagged here yet",
                    message: hype.error ?? "Try a wider radius or a different neighbourhood."
                )
            } else if hype.filteredVenues.isEmpty {
                emptyState(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "No \(hype.foodCategory.title.lowercased()) here",
                    message: "Try another category or widen the radius."
                )
            } else {
                if !hype.affordablePicks.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 10)], spacing: 10) {
                        ForEach(Array(hype.affordablePicks.enumerated()), id: \.element.id) { index, venue in
                            affordableCard(venue)
                                .hypeEntrance(appeared, index: index)
                        }
                    }
                }

                HStack {
                    Text("Everything nearby")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(hype.filteredVenues.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.line.opacity(0.5), in: Capsule())
                    Spacer()
                    Text("Price · distance")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, 4)

                LazyVStack(spacing: 6) {
                    ForEach(hype.filteredVenues) { venue in
                        venueRow(venue)
                    }
                }
            }
        }
    }

    private var foodProviderPicker: some View {
        HStack(spacing: 8) {
            Text("Order with")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.4)

            HStack(spacing: 3) {
                ForEach(HypeFoodProvider.allCases) { provider in
                    let active = hype.foodProvider == provider
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            hype.foodProvider = provider
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: provider.symbol)
                                .font(.system(size: 9, weight: .semibold))
                            Text(provider.title)
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(active ? .white : provider.tint)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(active ? provider.tint : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))

            Spacer()

            Text("Selected route opens \(hype.foodProvider.title)")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }

    private var vegFilterChips: some View {
        HStack(spacing: 8) {
            Text("Dietary")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.4)

            HStack(spacing: 6) {
                ForEach(HypeVegFilter.allCases) { filter in
                    let active = hype.vegFilter == filter
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            hype.vegFilter = filter
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filter.symbol)
                                .font(.system(size: 9, weight: .semibold))
                            Text(filter.title)
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(active ? .white : filter.tint)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(active ? filter.tint : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))

            Spacer()

            Text("Shows \(hype.vegFilter == .all ? "all dishes" : "\(hype.vegFilter.title) only")")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }

    private var dishSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            TextField("Craving biryani, pizza, cake…", text: $hype.dishQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { Task { await hype.loadRestaurantMenus() } }

            if hype.loadingMenus {
                ProgressView().controlSize(.mini)
            }

            if !hype.dishQuery.isEmpty {
                Button {
                    hype.dishQuery = ""
                    Task { await hype.loadRestaurantMenus() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Button("Find") {
                Task { await hype.loadRestaurantMenus() }
            }
            .buttonStyle(QuietButtonStyle())
        }
        .fieldStyle()
    }

    private func restaurantCard(_ menu: HypeRestaurantMenu, index: Int) -> some View {
        let isHovered = hoveredFood == menu.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                menuThumb(menu)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Button {
                            selectedMenu = menu
                        } label: {
                            HStack(spacing: 4) {
                                Text(menu.name)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        if let rating = menu.ratingLabel {
                            Text("★ \(rating)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.mint)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Theme.mint.opacity(0.12), in: Capsule())
                        }
                    }

                    if !menu.cuisineLabel.isEmpty {
                        Text(menu.cuisineLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 9) {
                        if let delivery = menu.deliveryTime {
                            Label(delivery, systemImage: "bicycle")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if let distance = menu.distanceLabel {
                            Label(distance, systemImage: "figure.walk")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if let cost = menu.costForTwo {
                            Text(cost)
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

                providerRouteChips(menu)
            }

            Divider().overlay(Theme.line)

            VStack(spacing: 5) {
                ForEach(menu.dishes.prefix(5)) { dish in
                    dishRow(dish)
                }
                if menu.dishes.count > 5 {
                    Button {
                        selectedMenu = menu
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 9, weight: .semibold))
                            Text("View all \(menu.dishes.count) dishes")
                                .font(.system(size: 9.5, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Theme.ember)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .nookitCard(radius: 14, glass: true)
        .glassLift(isHovered)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredFood = hovering ? menu.id : nil
            }
        }
        .hypeEntrance(appeared, index: index)
    }

    @ViewBuilder
    private func menuThumb(_ menu: HypeRestaurantMenu) -> some View {
        if let url = menu.menuImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    thumbPlaceholder
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            thumbPlaceholder
        }
    }

    private var thumbPlaceholder: some View {
        Image(systemName: "fork.knife")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ember)
            .frame(width: 48, height: 48)
            .background(Theme.ember.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func providerRouteChips(_ menu: HypeRestaurantMenu) -> some View {
        HStack(spacing: 4) {
            ForEach(HypeFoodProvider.allCases) { provider in
                let active = hype.foodProvider == provider
                let url = provider == .swiggy ? menu.swiggyURL : menu.zomatoURL
                Button {
                    guard let url else { return }
                    browserTarget = BrowserTarget(title: "\(menu.name) · \(provider.title)", url: url)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: provider.symbol)
                            .font(.system(size: 8, weight: .bold))
                        Text(provider.title)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(active ? .white : provider.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(active ? provider.tint : provider.tint.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(provider.tint.opacity(active ? 0 : 0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(url == nil)
            }
        }
    }

    private func dishRow(_ dish: HypeDish) -> some View {
        HStack(alignment: .top, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 1.5)
                    .strokeBorder(dish.isVeg ? Color(hex: 0x1FAA59) : Color(hex: 0xD93B3B), lineWidth: 1)
                    .frame(width: 9, height: 9)
                Circle()
                    .fill(dish.isVeg ? Color(hex: 0x1FAA59) : Color(hex: 0xD93B3B))
                    .frame(width: 4, height: 4)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(dish.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let description = dish.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(dish.priceLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var nearbyVenueSection: some View {
        if !hype.filteredVenues.isEmpty {
            HStack {
                Text("More places nearby")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(hype.filteredVenues.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.line.opacity(0.5), in: Capsule())
                Spacer()
                Text("Maps · distance")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.top, 6)

            LazyVStack(spacing: 6) {
                ForEach(hype.filteredVenues.prefix(8)) { venue in
                    venueRow(venue)
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HypeFoodCategory.allCases) { category in
                    let active = hype.foodCategory == category
                    let count = hype.selectedPlace?.isIndia == true
                        ? hype.restaurantMenus.filter { category.matches($0) }.count
                        : hype.venues.filter { category.matches($0) }.count
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) {
                            hype.foodCategory = category
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 9, weight: .semibold))
                            Text(category.title)
                                .font(.system(size: 10.5, weight: .medium))
                            if category != .all {
                                Text("\(count)")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .monospacedDigit()
                                    .opacity(0.65)
                            }
                        }
                        .foregroundStyle(active ? Color(hex: 0x160A04) : Theme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(active ? Theme.ember : Theme.raised, in: Capsule())
                        .overlay(Capsule().strokeBorder(active ? Color.clear : Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func affordableCard(_ venue: HypeVenue) -> some View {
        Button {
            selectedVenue = venue
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: venue.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ember)
                        .frame(width: 28, height: 28)
                        .background(Theme.ember.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(venue.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text([venue.kindLabel, venue.cuisine].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text(venue.priceLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.mint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.mint.opacity(0.12), in: Capsule())
                }

                HStack(spacing: 8) {
                    Label(venue.distanceLabel, systemImage: "figure.walk")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textSecondary)
                    if let hours = venue.openingHours {
                        Label(hours, systemImage: "clock")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .glassLift(hoveredVenue == venue.id)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredVenue = hovering ? venue.id : nil
            }
        }
    }

    private func venueRow(_ venue: HypeVenue) -> some View {
        HStack(spacing: 10) {
            Image(systemName: venue.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text([venue.kindLabel, venue.address, venue.cuisine].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let hours = venue.openingHours {
                Text(hours)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .trailing)
            }

            Text(venue.priceLabel)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(venue.priceTier <= 2 ? Theme.mint : Theme.textSecondary)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)

            Text(venue.distanceLabel)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)

            Button {
                selectedVenue = venue
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Order, book or open details")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { selectedVenue = venue }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.card.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        )
        .glassLift(hoveredVenue == venue.id)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredVenue = hovering ? venue.id : nil
            }
        }
    }

    // MARK: - Events

    @ViewBuilder
    private var events: some View {
        if hype.selectedPlace == nil {
            emptyState(
                symbol: "ticket",
                title: "See what's on",
                message: "Choose a location to find movies, concerts, theatre and events — with links to the sites that sell the tickets."
            )
        } else {
            moviesSection
            eventProviderBar
            districtEventsSection
        }
    }

private var isIndiaEvents: Bool { hype.selectedPlace?.isIndia == true }

    @State private var hoveredFood: String?
    @State private var hoveredEvent: String?
    @State private var hoveredCinema: String?
    @State private var hoveredVenue: String?

    private var moviesProviderLabel: String {
        isIndiaEvents ? "District" : "Google Showtimes"
    }

    private var eventsProviderLabel: String {
        isIndiaEvents ? "District" : "Ticketmaster"
    }

    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                SectionHeader(
                    title: "Movies near \(hype.selectedPlace?.shortName ?? "you")",
                    subtitle: "Film, cinema hall and today's showtimes in one place."
                )

                Spacer()

                providerPill(
                    title: "District",
                    symbol: "film.fill",
                    tint: Color(hex: 0xE23744),
                    url: isIndiaEvents
                        ? URL(string: "https://www.district.in/movies")
                        : HypeRouting.moviesURL(place: hype.selectedPlace)
                )
                providerPill(
                    title: "BookMyShow",
                    symbol: "ticket.fill",
                    tint: Color(hex: 0xE23744),
                    url: HypeRouting.moviesURL(place: hype.selectedPlace)
                )
            }

            if hype.loadingMovies && hype.movies.isEmpty {
                loadingState("Reading movies and showtimes…")
            } else if hype.movies.isEmpty {
                cinemasFallback
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(hype.movies.prefix(8).enumerated()), id: \.element.id) { index, movie in
                        movieCard(movie, index: index)
                    }
                }

                if let note = hype.movieNote {
                    noteRow(note, symbol: "film")
                }

                // Nearby cinemas (OpenStreetMap/Apple) are always shown so the
                // user sees venues actually close to their location, even when
                // District's major-multiplex showtimes are the primary list.
                let nearbyCinemas = hype.cinemas.filter { $0.distance <= 10_000 }
                if !nearbyCinemas.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(
                            title: "Cinemas near you",
                            subtitle: "Local halls and theatres within 10 km of \(hype.selectedPlace?.shortName ?? "you")."
                        )
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(nearbyCinemas.prefix(12)) { cinema in
                                    cinemaCard(cinema)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(13)
        .nookitCard(glass: true)
    }

    private func movieCard(_ movie: HypeMovie, index: Int) -> some View {
        HStack(alignment: .top, spacing: 11) {
            moviePoster(movie)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(movie.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    if let censor = movie.censor, !censor.isEmpty {
                        Text(censor)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Theme.line.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                if !movie.metaLabel.isEmpty {
                    Text(movie.metaLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                if movie.showtimes.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text("Showtimes open on \(moviesProviderLabel)")
                            .font(.system(size: 9.5))
                    }
                    .foregroundStyle(Theme.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(movie.groupedShowtimes.prefix(3).enumerated()), id: \.offset) { _, group in
                            showtimeRow(cinema: group.cinema, distance: group.distance, times: group.times)
                        }
                        if movie.groupedShowtimes.count > 3 {
                            Text("+\(movie.groupedShowtimes.count - 3) more cinemas")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        if let url = movie.url {
                            browserTarget = BrowserTarget(title: "\(movie.title) · District", url: url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "ticket.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text("Book on District")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(hex: 0xE23744), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(movie.url == nil)

                    if let bms = HypeRouting.moviesURL(place: hype.selectedPlace) {
                        Button {
                            browserTarget = BrowserTarget(title: "\(movie.title) · BookMyShow", url: bms)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 8, weight: .bold))
                                Text("BookMyShow")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .foregroundStyle(Color(hex: 0xE23744))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(hex: 0xE23744).opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 1)
            }
        }
        .padding(10)
        .nookitCard(radius: 12, glass: true)
        .glassLift(hoveredEvent == movie.id)
        .hypeEntrance(appeared, index: index)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredEvent = hovering ? movie.id : nil
            }
        }
        .hypeEntrance(appeared, index: index)
    }

    @ViewBuilder
    private func moviePoster(_ movie: HypeMovie) -> some View {
        if let raw = movie.imageURL, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    posterPlaceholder
                }
            }
            .frame(width: 68, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        Image(systemName: "film")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(Theme.ember)
            .frame(width: 68, height: 96)
            .background(Theme.ember.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func showtimeRow(cinema: String, distance: String?, times: [HypeShowtime]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(cinema)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if let distance {
                    Text("· \(distance)")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 4) {
                ForEach(times.prefix(5)) { time in
                    Button {
                        if let url = hype.movies.first(where: { $0.showtimes.contains(time) })?.url {
                            browserTarget = BrowserTarget(title: "\(cinema) · \(time.time)", url: url)
                        }
                    } label: {
                        Text(time.time)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Theme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                if times.count > 5 {
                    Text("+\(times.count - 5)")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var cinemasFallback: some View {
        Group {
            if hype.loadingCinemas && hype.cinemas.isEmpty {
                loadingState("Finding cinemas nearby…")
            } else if hype.cinemas.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "film")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ember)
                    Text("No cinema tagged within range. You can still browse what's playing.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if let url = HypeRouting.moviesURL(place: hype.selectedPlace) {
                        Button("Find tickets") {
                            browserTarget = BrowserTarget(title: "Movie tickets", url: url)
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Theme.line.opacity(0.30), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(hype.cinemas.prefix(8)) { cinema in
                            cinemaCard(cinema)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private func cinemaCard(_ cinema: HypeCinema) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "film.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.ember)
                    .frame(width: 25, height: 25)
                    .background(Theme.ember.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(cinema.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }

            Text(cinema.address ?? "Cinema")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Label(cinema.distanceLabel, systemImage: "figure.walk")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Button("Tickets") {
                    guard let url = HypeRouting.moviesURL(place: hype.selectedPlace) else { return }
                    browserTarget = BrowserTarget(title: "\(cinema.name) · tickets", url: url)
                }
                .buttonStyle(QuietButtonStyle())
            }

            Button {
                if let url = cinema.mapsURL {
                    browserTarget = BrowserTarget(title: cinema.name, url: url)
                }
            } label: {
                Text("Directions")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 205, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.background)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        )
        .glassLift(hoveredCinema == cinema.id)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredCinema = hovering ? cinema.id : nil
            }
        }
    }

    private var eventProviderBar: some View {
        HStack(spacing: 8) {
            Text("Tickets from")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.4)

            HStack(spacing: 3) {
                ForEach(HypeEventProvider.allCases) { provider in
                    let active = eventProvider == provider
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            eventProvider = provider
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: provider.symbol)
                                .font(.system(size: 9, weight: .semibold))
                            Text(provider.title)
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(active ? .white : provider.tint)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(active ? provider.tint : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))

            Spacer()

            if !isIndiaEvents {
                Button {
                    showEventsKey = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: hype.ticketmasterKey.isEmpty ? "key" : "key.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(hype.ticketmasterKey.isEmpty ? "Add events key" : "Events key")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(hype.ticketmasterKey.isEmpty ? Theme.textSecondary : Theme.mint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.raised, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEventsKey, arrowEdge: .bottom) {
                    eventsKeyPopover
                }
            } else {
                Text("Live from District · \(hype.selectedPlace?.shortName ?? "")")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var eventsKeyPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ticketmaster events")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("A free Discovery API key unlocks dated concerts, theatre and sports near any location. Without one, Hype still lists venues from OpenStreetMap.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Discovery API key", text: $hype.ticketmasterKey)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .fieldStyle()
            HStack {
                Button("Get a free key") {
                    if let url = URL(string: "https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Refresh") {
                    showEventsKey = false
                    Task { await hype.loadEvents() }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 310)
    }

    private var districtEventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                SectionHeader(
                    title: "Events around \(hype.selectedPlace?.shortName ?? "you")",
                    subtitle: "Comedy, music, theatre and workshops with live tickets."
                )
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        Task { await hype.loadEvents() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                            Text("Refresh")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(hype.loadingEvents ? Theme.textTertiary : Theme.ember)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.ember.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(hype.loadingEvents)

                    providerPill(
                        title: "Open District",
                        symbol: "sparkles",
                        tint: Theme.ember,
                        url: HypeRouting.eventsURL(place: hype.selectedPlace)
                    )
                }
            }

            if let note = hype.eventNote {
                noteRow(note, symbol: "info.circle")
            }

            if hype.loadingEvents && hype.events.isEmpty {
                loadingState("Checking what's on…")
            } else if hype.events.isEmpty {
                emptyState(
                    symbol: "calendar.badge.exclamationmark",
                    title: "No events found",
                    message: "Try another location or widen the radius on the Food tab."
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 265, maximum: 340), spacing: 10)], spacing: 10) {
                    ForEach(Array(hype.events.enumerated()), id: \.element.id) { index, event in
                        eventCard(event, index: index)
                    }
                }
            }
        }
    }

    private func eventCard(_ event: HypeEvent, index: Int) -> some View {
        Button {
            open(event)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                if let raw = event.imageURL, let url = URL(string: raw) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            eventImagePlaceholder
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 104)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                HStack(spacing: 7) {
                    Text(event.category.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(event.isVenueSuggestion ? Theme.textTertiary : Theme.ember)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((event.isVenueSuggestion ? Theme.textTertiary : Theme.ember).opacity(0.10), in: Capsule())
                    Spacer()
                    Text(event.priceLabel)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.mint)
                }

                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 3) {
                    Label(event.dateLabel, systemImage: "calendar")
                    Label(event.venue.isEmpty ? event.city : event.venue, systemImage: "mappin")
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

                HStack(spacing: 5) {
                    Text(event.isVenueSuggestion ? "Find events" : "Get tickets")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                    Spacer()
                }
                .foregroundStyle(Theme.ember)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            )
            .glassLift(hoveredEvent == event.id)
            .hypeEntrance(appeared, index: index)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.16)) {
                    hoveredEvent = hovering ? event.id : nil
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(event.url == nil)
        .hypeEntrance(appeared, index: index)
    }

    private var eventImagePlaceholder: some View {
        ZStack {
            Theme.ember.opacity(0.08)
            Image(systemName: "ticket")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.ember)
        }
    }

    private func noteRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 10.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.line.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func open(_ event: HypeEvent) {
        guard let url = event.url else { return }
        browserTarget = BrowserTarget(title: event.title, url: url)
    }

    // MARK: - Travel

    private var travel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                SectionHeader(
                    title: "Live travel prices",
                    subtitle: "Search real fares, stays and train schedules without leaving Nookit."
                )
                Spacer()
                Button {
                    runTravelSearch()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(travelLoading ? Theme.textTertiary : Theme.ember)
                        .frame(width: 26, height: 26)
                        .background(Theme.ember.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Refresh live travel prices")
                .disabled(travelLoading)
            }

            HStack(spacing: 8) {
                ForEach(HypeTravelMode.allCases) { mode in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            hype.travelMode = mode
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(hype.travelMode == mode ? Theme.ember : Theme.textSecondary)
                            Text(mode.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(hype.travelMode == mode ? Theme.textPrimary : Theme.textSecondary)
                            Text(providerName(for: mode))
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(hype.travelMode == mode ? Theme.ember.opacity(0.08) : Theme.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(hype.travelMode == mode ? Theme.ember.opacity(0.35) : Theme.line, lineWidth: 1)
                                )
                        )
                        .scaleEffect(hoveredMode == mode ? 1.015 : 1)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            hoveredMode = hovering ? mode : (hoveredMode == mode ? nil : hoveredMode)
                        }
                    }
                }
            }

            travelForm

            HStack(spacing: 10) {
                Button {
                    runTravelSearch()
                } label: {
                    HStack(spacing: 6) {
                        if travelLoading {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(travelLoading ? "Searching…" : "Search live prices")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.mint))
                .disabled(travelLoading)


                Spacer(minLength: 0)
            }

            Text(travelCaption)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            travelResults
                .id("travelResults")

            VStack(alignment: .leading, spacing: 8) {
                Text("How Hype keeps prices honest")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                if hype.travelMode == .trains {
                    travelNote("tram", "Schedules, running days and classes come live from eRail, which mirrors Indian Railways. Booking opens on IRCTC.")
                } else if hype.travelMode == .hotels {
                    travelNote("bed.double", "Stay prices, ratings and photos are read live from Google Hotels for your dates and guest count.")
                } else {
                    travelNote("airplane", "Fares, airlines, timings and stops are read live from Google Flights for your route and date.")
                }
                travelNote("checkmark.seal", "Prices are fetched fresh on every search. Nookit never guesses fares.")
            }
            .padding(13)
            .background(Theme.line.opacity(0.25), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: travelBrowser != nil)
    }

    private var travelDestination: String {
        hype.destination.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func providerName(for mode: HypeTravelMode) -> String {
        hype.travelProviderName
    }

    @ViewBuilder
    private var travelForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: hype.travelMode.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.ember)
                    Text(hype.travelMode == .hotels ? "Find stays" : "Find \(hype.travelMode.title.lowercased())")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.ember.opacity(0.08), in: Capsule())

                Spacer()

                if hype.travelMode != .hotels {
                    Text(travelTripType == .oneWay ? "Live one-way prices" : "Live round-trip prices")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if hype.travelMode == .hotels {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                        HStack(spacing: 7) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.ember)
                            TextField("Where do you want to stay?", text: $hype.destination)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .fieldStyle()
                    }
                    Button {
                        if let place = hype.selectedPlace {
                            hype.destination = place.shortName
                        }
                        runTravelSearch()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "location.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Search near my location")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.ember)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.ember.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.ember.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 8) {
                    let fromSymbol = hype.travelMode == .flights ? "airplane.departure" : "tram"
                    let toSymbol = hype.travelMode == .flights ? "airplane.arrival" : "tram.fill"
                    field(title: "From", text: $hype.origin, placeholder: hype.selectedPlace?.shortName ?? "City or station", symbol: fromSymbol)

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            let from = hype.origin
                            hype.origin = hype.destination
                            hype.destination = from
                        }
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 26, height: 26)
                            .background(Theme.raised, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Swap origin and destination")
                    .padding(.top, 14)

                    field(title: "To", text: $hype.destination, placeholder: "Where to?", symbol: toSymbol)
                }

                HStack(spacing: 8) {
                    ForEach(TravelTripType.allCases) { type in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                travelTripType = type
                            }
                        } label: {
                            Text(type.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(travelTripType == type ? .white : Theme.textSecondary)
                                .padding(.horizontal, 12)
                                .frame(height: 24)
                                .background(travelTripType == type ? Theme.ember : Theme.raised, in: Capsule())
                                .overlay(Capsule().strokeBorder(travelTripType == type ? Color.clear : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 10) {
                if hype.travelMode == .hotels {
                    dateField(title: "Check in", date: $hype.departDate)
                    dateField(title: "Check out", date: $hype.returnDate)
                } else if travelTripType == .oneWay {
                    dateField(title: "Depart", date: $hype.departDate)
                } else {
                    dateField(title: "Depart", date: $hype.departDate)
                    dateField(title: "Return", date: $hype.returnDate)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(hype.travelMode == .hotels ? "Guests" : "Travellers")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                    Stepper(value: $hype.travelers, in: 1...8) {
                        Text("\(hype.travelers)")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                    }
                    .controlSize(.small)
                    .fieldStyle()
                }
                .frame(width: 118)

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .nookitCard()
    }

    private func travelNote(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.ember)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field(title: String, text: Binding<String>, placeholder: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textPrimary)
            }
            .fieldStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dateField(title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.ember)
                DatePicker("", selection: date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: 170, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    // MARK: - Live travel results

    private var travelCurrency: String {
        hype.selectedPlace?.isIndia == false ? "USD" : "INR"
    }

    private var travelSourceLabel: String {
        switch hype.travelMode {
        case .flights: return "Google Flights"
        case .hotels: return "Google Hotels"
        case .trains: return "eRail · Indian Railways"
        }
    }

    private var travelDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: hype.departDate)
    }

    private var hotelStayNights: Int {
        let days = Calendar.current.dateComponents([.day], from: hype.departDate, to: hype.returnDate).day ?? 1
        return max(1, days)
    }

    private var travelCaption: String {
        if travelLoading {
            return "Reading live \(hype.travelMode == .hotels ? "stay prices" : hype.travelMode.title.lowercased()) from \(travelSourceLabel)…"
        }
        if let travelError {
            return travelError
        }
        switch hype.travelMode {
        case .flights:
            guard !travelDestination.isEmpty else {
                return "Add a destination, then search live one-way fares for \(travelDateLabel)."
            }
            return "One-way fares on \(travelDateLabel), read live from Google Flights. Prices are per traveller."
        case .hotels:
            guard !travelDestination.isEmpty else {
                return "Add a location, then search live stay prices for your dates."
            }
            return "Nightly stay prices for \(hype.travelers) guest\(hype.travelers == 1 ? "" : "s"), read live from Google Hotels."
        case .trains:
            guard !hype.origin.isEmpty, !travelDestination.isEmpty else {
                return "Add an origin and destination to search live train schedules."
            }
            return "Live schedules, running days, classes and fares from eRail. Booking continues on IRCTC."
        }
    }

    private func currencySymbol(_ code: String) -> String {
        switch code.uppercased() {
        case "INR": return "₹"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return code.uppercased() + " "
        }
    }

    private func clearTravelResults(keepError: Bool = false) {
        travelTask?.cancel()
        travelTask = nil
        travelFlights = []
        travelReturnFlights = []
        travelHotels = []
        travelTrains = []
        travelReturnTrains = []
        travelLoading = false
        travelSummary = nil
        if !keepError { travelError = nil }
    }

    private func runTravelSearch() {
        travelTask?.cancel()
        travelFlights = []
        travelReturnFlights = []
        travelHotels = []
        travelTrains = []
        travelReturnTrains = []
        travelError = nil
        travelSummary = nil
        travelLoading = true

        let mode = hype.travelMode
        let from = hype.origin
        let to = hype.destination
        let city = hype.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (hype.selectedPlace?.shortName ?? "")
            : hype.destination
        let depart = hype.departDate
        let ret = hype.returnDate
        let guests = hype.travelers
        let currency = travelCurrency
        let tripType = travelTripType

        travelTask = Task { @MainActor in
            do {
                switch mode {
                case .flights:
                    if tripType == .oneWay {
                        let results = try await TravelService.shared.flights(
                            from: from, to: to, date: depart, currency: currency
                        )
                        guard !Task.isCancelled else { return }
                        travelFlights = results
                        let cheapest = results.first?.priceLabel ?? "—"
                        travelSummary = "\(results.count) live fares · cheapest \(cheapest)"
                    } else {
                        async let outboundTask = TravelService.shared.flights(from: from, to: to, date: depart, currency: currency)
                        async let returnTask = TravelService.shared.flights(from: to, to: from, date: ret, currency: currency)
                        let outbound = try await outboundTask
                        let inbound = try await returnTask
                        guard !Task.isCancelled else { return }
                        travelFlights = outbound
                        travelReturnFlights = inbound
                        let total = (outbound.first?.price ?? 0) + (inbound.first?.price ?? 0)
                        travelSummary = "\(outbound.count) outbound + \(inbound.count) return · from \(currencySymbol(currency))\(total.formatted(.number.grouping(.automatic))) total"
                    }
                case .hotels:
                    let results = try await TravelService.shared.hotels(
                        city: city, checkIn: depart, checkOut: ret, guests: guests, currency: currency
                    )
                    guard !Task.isCancelled else { return }
                    travelHotels = results
                    let cheapest = results.map(\.price).filter { $0 > 0 }.min()
                    travelSummary = "\(results.count) stays · from \(cheapest.map { "\(currencySymbol(currency))\($0.formatted(.number.grouping(.automatic)))" } ?? "—") a night"
                case .trains:
                    if tripType == .oneWay {
                        let results = try await TravelService.shared.trains(from: from, to: to)
                        guard !Task.isCancelled else { return }
                        travelTrains = results
                        travelSummary = "\(results.count) trains on this route · sorted by departure"
                    } else {
                        async let outboundTask = TravelService.shared.trains(from: from, to: to)
                        async let returnTask = TravelService.shared.trains(from: to, to: from)
                        let outbound = try await outboundTask
                        let inbound = try await returnTask
                        guard !Task.isCancelled else { return }
                        travelTrains = outbound
                        travelReturnTrains = inbound
                        travelSummary = "\(outbound.count) outbound + \(inbound.count) return trains"
                    }
                }
                travelLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                travelLoading = false
                travelError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func openTravel(_ url: URL?, title: String) {
        guard let url else { return }
        travelBrowser = BrowserTarget(title: title, url: url)
    }

    @ViewBuilder
    private var travelResults: some View {
        if travelLoading {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading live results from \(travelSourceLabel)…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .nookitCard()
        } else if let travelError {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ember)
                    Text("Live search didn't finish")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(travelError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    runTravelSearch()
                } label: {
                    Text("Try again")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Theme.raised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nookitCard()
        } else {
            switch hype.travelMode {
            case .flights where !travelFlights.isEmpty:
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        resultsHeader(count: travelFlights.count, unit: "outbound fares", note: "sorted by price")
                        VStack(spacing: 8) {
                            ForEach(travelFlights) { flight in
                                flightCard(flight)
                            }
                        }
                    }
                    if !travelReturnFlights.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            resultsHeader(count: travelReturnFlights.count, unit: "return fares", note: "sorted by price")
                            VStack(spacing: 8) {
                                ForEach(travelReturnFlights) { flight in
                                    flightCard(flight)
                                }
                            }
                        }
                    }
                }
            case .hotels where !travelHotels.isEmpty:
                VStack(alignment: .leading, spacing: 10) {
                    resultsHeader(count: travelHotels.count, unit: "stays", note: "live nightly prices")
                    VStack(spacing: 8) {
                        ForEach(travelHotels) { hotel in
                            hotelCard(hotel)
                        }
                    }
                }
            case .trains where !travelTrains.isEmpty:
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        resultsHeader(count: travelTrains.count, unit: "outbound trains", note: "sorted by departure")
                        VStack(spacing: 8) {
                            ForEach(travelTrains) { train in
                                trainCard(train)
                            }
                        }
                    }
                    if !travelReturnTrains.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            resultsHeader(count: travelReturnTrains.count, unit: "return trains", note: "sorted by departure")
                            VStack(spacing: 8) {
                                ForEach(travelReturnTrains) { train in
                                    trainCard(train)
                                }
                            }
                        }
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    private func resultsHeader(count: Int, unit: String, note: String) -> some View {
        HStack(spacing: 6) {
            Text("\(count) \(unit)")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("·")
                .foregroundStyle(Theme.textTertiary)
            Text(note)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 8.5, weight: .semibold))
                Text(travelSourceLabel)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.line.opacity(0.4), in: Capsule())
        }
        .padding(.horizontal, 2)
    }

    private func flightCard(_ flight: TravelFlight) -> some View {
        let hovering = hoveredTravelCard == flight.id
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Text(flight.airlineCode)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.ember)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Theme.ember.opacity(0.1), in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                Text(flight.flightLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(flight.stopsLabel)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(flight.stops == 0 ? Theme.textSecondary : Theme.emberSoft)
                if let aircraft = flight.aircraft, !aircraft.isEmpty {
                    Text("· \(aircraft)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                timeBlock(flight.departTime, code: flight.fromCode, offset: 0, alignment: .leading)

                VStack(spacing: 3) {
                    Text(flight.durationLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                    ZStack {
                        Capsule()
                            .fill(Theme.lineStrong)
                            .frame(height: 1)
                        Image(systemName: "airplane")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.ember)
                            .padding(.horizontal, 3)
                            .background(Theme.card)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(minWidth: 64, maxWidth: 110)

                timeBlock(flight.arriveTime, code: flight.toCode, offset: flight.arrivalDayOffset, alignment: .trailing)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(flight.priceLabel)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Button {
                        openTravel(flight.bookingURL, title: "Flight · \(flight.fromCode) → \(flight.toCode)")
                    } label: {
                        Text("Book")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x160A04))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 4.5)
                            .background(Theme.mint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(13)
        .nookitCard(raised: hovering, glass: hovering)
        .hoverLift(hovering)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredTravelCard = hovering ? flight.id : (hoveredTravelCard == flight.id ? nil : hoveredTravelCard)
            }
        }
    }

    private func timeBlock(_ time: String, code: String, offset: Int, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 2) {
                Text(time)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                if offset > 0 {
                    Text("+\(offset)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.ember)
                        .offset(y: -5)
                }
            }
            Text(code)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func hotelCard(_ hotel: TravelHotel) -> some View {
        let hovering = hoveredTravelCard == hotel.id
        return HStack(spacing: 12) {
            AsyncImage(url: hotel.photoURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZStack {
                        Theme.raised
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(hotel.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let starClass = hotel.starClass, !starClass.isEmpty {
                    Text(starClass.capitalized)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                HStack(spacing: 5) {
                    if let rating = hotel.ratingLabel {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.emberSoft)
                            Text(rating)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    if hotel.reviewCount > 0 {
                        Text("\(hotel.reviewCount.formatted(.number.grouping(.automatic))) reviews")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                Text(hotel.priceLabel)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text("a night")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
                if hotel.price > 0 {
                    Text("\(currencySymbol(hotel.currency))\((hotel.price * hotelStayNights).formatted(.number.grouping(.automatic))) for \(hotelStayNights) night\(hotelStayNights == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                Button {
                    openTravel(hotel.bookingURL, title: hotel.name)
                } label: {
                    Text("View")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4.5)
                        .background(Theme.raised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .nookitCard(raised: hovering, glass: hovering)
        .hoverLift(hovering)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredTravelCard = hovering ? hotel.id : (hoveredTravelCard == hotel.id ? nil : hoveredTravelCard)
            }
        }
    }

    private func trainCard(_ train: TravelTrain) -> some View {
        let hovering = hoveredTravelCard == train.id
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(train.number)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Theme.ember)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Theme.ember.opacity(0.1), in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                    .monospacedDigit()
                Text(train.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if !train.trainType.isEmpty {
                    Text(train.trainType.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Theme.ember)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.ember.opacity(0.1), in: Capsule())
                }
                Spacer(minLength: 6)
                if train.distanceKm > 0 {
                    Text("\(train.distanceKm) km")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            }

            HStack(alignment: .center, spacing: 12) {
                timeBlock(train.departTime, code: train.fromCode, offset: 0, alignment: .leading)

                VStack(spacing: 3) {
                    Text(train.durationLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                    ZStack {
                        Capsule()
                            .fill(Theme.lineStrong)
                            .frame(height: 1)
                        Image(systemName: "tram.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.ember)
                            .padding(.horizontal, 3)
                            .background(Theme.card)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(minWidth: 64, maxWidth: 110)

                timeBlock(train.arriveTime, code: train.toCode, offset: train.arrivalDayOffset, alignment: .trailing)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    if !train.runsOn.isEmpty {
                        Text(train.runsOn)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Button {
                        openTravel(URL(string: "https://www.irctc.co.in/nget/train-search"), title: "IRCTC · \(train.number)")
                    } label: {
                        Text("Book")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x160A04))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 4.5)
                            .background(Theme.mint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !train.classes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Classes")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                        ForEach(train.classes, id: \.self) { code in
                            Text(code)
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Theme.line.opacity(0.5), in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                        }
                        Spacer(minLength: 0)
                    }
                    let fareItems = train.classes.compactMap { code -> (String, String)? in
                        guard let label = train.fareLabel(for: code) else { return nil }
                        return (code, label)
                    }
                    if !fareItems.isEmpty {
                        HStack(spacing: 6) {
                            Text("Fares")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textTertiary)
                            ForEach(fareItems, id: \.0) { item in
                                HStack(spacing: 2) {
                                    Text(item.0)
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                    Text(item.1)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Theme.mint)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(13)
        .nookitCard(raised: hovering, glass: hovering)
        .hoverLift(hovering)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredTravelCard = hovering ? train.id : (hoveredTravelCard == train.id ? nil : hoveredTravelCard)
            }
        }
    }

    // MARK: - Provider pill

    private func providerPill(title: String, symbol: String, tint: Color, url: URL?) -> some View {
        Button {
            guard let url else { return }
            browserTarget = BrowserTarget(title: title, url: url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .bold))
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }

    // MARK: - Shared states

    private func emptyState(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.ember.opacity(0.08))
                    .frame(width: 52, height: 52)
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.ember)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }

    private func loadingState(_ text: String) -> some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }



}

// MARK: - Venue detail

private struct VenueDetailSheet: View {
    let venue: HypeVenue
    let place: HypePlace?

    @Environment(\.dismiss) private var dismiss
    @State private var browserTarget: BrowserTarget?

    private var isIndia: Bool { place?.isIndia == true }
    private var orderProvider: String { isIndia ? "Swiggy" : "Uber Eats" }
    private var tableProvider: String { isIndia ? "Zomato" : "OpenTable" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: venue.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ember)
                    .frame(width: 38, height: 38)
                    .background(Theme.ember.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(venue.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text([venue.kindLabel, venue.cuisine].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                detailBadge(venue.priceLabel, tint: Theme.mint)
                detailBadge(venue.distanceLabel, tint: Theme.textSecondary)
                if let hours = venue.openingHours {
                    detailBadge(hours, tint: Theme.textSecondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 7) {
                if let address = venue.address {
                    detailRow("mappin.and.ellipse", address)
                }
                if let phone = venue.phone {
                    detailRow("phone", phone)
                }
                if let website = venue.url {
                    detailRow("globe", website.host ?? website.absoluteString)
                }
                if venue.address == nil && venue.phone == nil && venue.url == nil {
                    Text("No contact details are tagged in OpenStreetMap for this place.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Divider().overlay(Theme.line)

            VStack(spacing: 8) {
                actionButton(
                    title: "Order on \(orderProvider)",
                    subtitle: "Delivery or pickup from this restaurant",
                    symbol: "bag.fill",
                    tint: Color(hex: 0xFC8019)
                ) {
                    HypeRouting.foodOrderURL(venue: venue, place: place)
                }

                actionButton(
                    title: "Book a table on \(tableProvider)",
                    subtitle: "Reserve a time for dine-in",
                    symbol: "calendar.badge.clock",
                    tint: Color(hex: 0xE23744)
                ) {
                    HypeRouting.tableBookingURL(venue: venue, place: place)
                }

                HStack(spacing: 8) {
                    smallAction("Directions", symbol: "arrow.triangle.turn.up.right.diamond.fill") {
                        venue.mapsURL
                    }
                    smallAction("Website", symbol: "globe") {
                        venue.url
                    }
                    smallAction("Call", symbol: "phone.fill") {
                        guard let phone = venue.phone else { return nil }
                        let digits = phone.filter { $0.isNumber || $0 == "+" }
                        return URL(string: "tel://\(digits)")
                    }
                }
            }

            Text("Nookit hands off to \(orderProvider) and \(tableProvider) with this restaurant's name. Availability and final prices live in those apps.")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 430, height: 640)
        .background(Theme.background)
        .sheet(item: $browserTarget) { target in
            WebBrowserSheet(title: target.title, url: target.url)
        }
    }

    private func detailBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.11), in: Capsule())
    }

    private func detailRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func actionButton(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        url: @escaping () -> URL?
    ) -> some View {
        Button {
            guard let target = url() else { return }
            browserTarget = BrowserTarget(title: title, url: target)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func smallAction(_ title: String, symbol: String, url: @escaping () -> URL?) -> some View {
        Button {
            guard let target = url() else { return }
            if target.scheme == "tel" {
                NSWorkspace.shared.open(target)
            } else {
                browserTarget = BrowserTarget(title: title, url: target)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Restaurant Menu Detail Sheet

private struct RestaurantMenuDetailSheet: View {
    let menu: HypeRestaurantMenu
    let place: HypePlace?
    let foodProvider: HypeFoodProvider

    @Environment(\.dismiss) private var dismiss
    @State private var browserTarget: BrowserTarget?
    @State private var showFullMenu = false

    private var isIndia: Bool { place?.isIndia == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .top, spacing: 12) {
                    if let url = menu.menuImageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Theme.ember)
                            }
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Theme.ember)
                            .frame(width: 80, height: 80)
                            .background(Theme.ember.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(menu.name)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if !menu.cuisineLabel.isEmpty {
                            Text(menu.cuisineLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 12) {
                            if let rating = menu.ratingLabel {
                                Label("★ \(rating)", systemImage: "star.fill")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Theme.mint)
                            }
                            if let delivery = menu.deliveryTime {
                                Label(delivery, systemImage: "bicycle")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if let distance = menu.distanceLabel {
                                Label(distance, systemImage: "figure.walk")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    Spacer()

                    Button("Done") { dismiss() }
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }

                // Info badges
                HStack(spacing: 8) {
                    if let cost = menu.costForTwo {
                        detailBadge(cost, tint: Theme.mint)
                    }
                    detailBadge(menu.dishes.count == 1 ? "1 dish" : "\(menu.dishes.count) dishes", tint: Theme.textSecondary)
                    if let area = menu.area {
                        detailBadge(area, tint: Theme.textSecondary)
                    }
                    Spacer()
                }

                // Contact & Location
                VStack(alignment: .leading, spacing: 7) {
                    if let address = menu.address {
                        detailRow("mappin.and.ellipse", address)
                    }
                    if let area = menu.area {
                        detailRow("building.2", area)
                    }
                    if menu.address == nil && menu.area == nil {
                        Text("Location details not available from Swiggy.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Divider().overlay(Theme.line)

                // Provider actions
                VStack(spacing: 10) {
                    actionButton(
                        title: "Order on \(foodProvider.title)",
                        subtitle: "Delivery or pickup · \(foodProvider.title) app/website",
                        symbol: foodProvider == .swiggy ? "bag.fill" : "fork.knife",
                        tint: foodProvider.tint
                    ) {
                        foodProvider == .swiggy ? menu.swiggyURL : menu.zomatoURL
                    }

                    if foodProvider == .swiggy, let zomatoURL = menu.zomatoURL {
                        actionButton(
                            title: "Also on Zomato",
                            subtitle: "Compare prices or book a table",
                            symbol: "fork.knife",
                            tint: Color(hex: 0xE23744)
                        ) {
                            zomatoURL
                        }
                    } else if foodProvider == .zomato, let swiggyURL = menu.swiggyURL {
                        actionButton(
                            title: "Also on Swiggy",
                            subtitle: "Compare prices or order delivery",
                            symbol: "bag.fill",
                            tint: Color(hex: 0xFC8019)
                        ) {
                            swiggyURL
                        }
                    }

                    HStack(spacing: 8) {
                        smallAction("Directions", symbol: "arrow.triangle.turn.up.right.diamond.fill") {
                            guard let address = menu.address?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
                            return URL(string: "https://www.google.com/maps/search/?api=1&query=\(address)")
                        }
                        smallAction("Swiggy Page", symbol: "safari") {
                            menu.swiggyURL
                        }
                        smallAction("Zomato Page", symbol: "safari") {
                            menu.zomatoURL
                        }
                    }
                }

                Divider().overlay(Theme.line)

                // Full Menu
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Full Menu (\(menu.dishes.count) dishes)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if menu.dishes.count > 10 {
                            Button(showFullMenu ? "Show less" : "Show all") {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showFullMenu.toggle()
                                }
                            }
                            .buttonStyle(QuietButtonStyle())
                        }
                    }

                    let dishesToShow = showFullMenu ? menu.dishes : Array(menu.dishes.prefix(10))
                    VStack(spacing: 6) {
                        ForEach(dishesToShow) { dish in
                            dishRow(dish)
                        }
                        if !showFullMenu && menu.dishes.count > 10 {
                            Text("+\(menu.dishes.count - 10) more dishes — tap \"Show all\"")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 4)
                        }
                    }
                }

                Text("Nookit opens \(foodProvider.title) (and Zomato) with this restaurant's details. Final prices, availability, and checkout happen in those apps.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 560, height: 720)
        .background(Theme.background)
        .sheet(item: $browserTarget) { target in
            WebBrowserSheet(title: target.title, url: target.url)
        }
    }

    private func detailBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.11), in: Capsule())
    }

    private func detailRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func dishRow(_ dish: HypeDish) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(dish.isVeg ? Color(hex: 0x1FAA59) : Color(hex: 0xD93B3B), lineWidth: 1.5)
                    .frame(width: 10, height: 10)
                Circle()
                    .fill(dish.isVeg ? Color(hex: 0x1FAA59) : Color(hex: 0xD93B3B))
                    .frame(width: 5, height: 5)
            }
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(dish.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let description = dish.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            Text(dish.priceLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()

            if dish.isVeg {
                Text("VEG")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color(hex: 0x1FAA59), in: Capsule())
            } else {
                Text("NON-VEG")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color(hex: 0xD93B3B), in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }

    private func actionButton(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        url: @escaping () -> URL?
    ) -> some View {
        Button {
            guard let target = url() else { return }
            browserTarget = BrowserTarget(title: title, url: target)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func smallAction(_ title: String, symbol: String, url: @escaping () -> URL?) -> some View {
        Button {
            guard let target = url() else { return }
            browserTarget = BrowserTarget(title: title, url: target)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Supporting types

private enum HypeTab: String, CaseIterable, Identifiable {
    case food
    case events
    case travel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: return "Food"
        case .events: return "Events"
        case .travel: return "Travel"
        }
    }

    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .events: return "ticket"
        case .travel: return "airplane"
        }
    }
}

private struct BrowserTarget: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private enum HypeEventProvider: String, CaseIterable, Identifiable {
    case district
    case bookMyShow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .district: return "District"
        case .bookMyShow: return "BookMyShow"
        }
    }

    var symbol: String {
        switch self {
        case .district: return "sparkles"
        case .bookMyShow: return "ticket.fill"
        }
    }

    var tint: Color {
        switch self {
        case .district: return Color(hex: 0xE23744)
        case .bookMyShow: return Color(hex: 0xE23744)
        }
    }
}

/// A soft animated wash behind each Hype tab. It gives the tab switch a sense of
/// place without turning the whole screen into a gradient.
private struct HypeTabGlow: View {
    let tab: HypeTab
    @State private var drift = false

    private var colors: [Color] {
        switch tab {
        case .food: return [Color(hex: 0xFC8019), Color(hex: 0xFF5A1F)]
        case .events: return [Color(hex: 0xE23744), Color(hex: 0xFF8A65)]
        case .travel: return [Color(hex: 0x2F80ED), Color(hex: 0x8BE9C0)]
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [colors[0].opacity(0.13), .clear],
                    center: UnitPoint(x: drift ? 0.18 : 0.32, y: drift ? 0.10 : 0.02),
                    startRadius: 8,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.62
                )
                RadialGradient(
                    colors: [colors[1].opacity(0.09), .clear],
                    center: UnitPoint(x: drift ? 0.86 : 0.68, y: drift ? 0.22 : 0.10),
                    startRadius: 6,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.52
                )
            }
            .animation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true), value: drift)
            .onAppear { drift = true }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.45), value: tab)
    }
}

private struct HypeEntrance: ViewModifier {
    let appeared: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(
                .spring(response: 0.42, dampingFraction: 0.86)
                    .delay(Double(min(index, 8)) * 0.035),
                value: appeared
            )
    }
}

private extension View {
    func hypeEntrance(_ appeared: Bool, index: Int) -> some View {
        modifier(HypeEntrance(appeared: appeared, index: index))
    }
}
