import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detail
                .frame(minWidth: 700, minHeight: 600)
        }
        .navigationSplitViewStyle(.balanced)
        .background(Theme.background)
    }

    @ViewBuilder
    private var detail: some View {
        if app.showAIChat {
            AIChatScreen()
        } else if app.showHype {
            HypeScreen()
        } else if app.showApps {
            AppsScreen()
        } else if app.showNotchSettings {
            NotchSettingsView()
        } else if let slug = app.runningToolSlug, let tool = app.catalog.tool(slug: slug) {
            ToolRunnerView(tool: tool)
        } else if let tool = app.selectedTool {
            ToolDetailView(tool: tool)
        } else {
            AllToolsView()
        }
    }
}

// MARK: - Browse all

struct AllToolsView: View {
    @EnvironmentObject private var app: AppState
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 224, maximum: 320), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                HeroStrip()

                if !app.recentTools.isEmpty && app.search.isEmpty && app.selectedCategory == nil {
                    recentRow
                }

                if app.groupedTools.isEmpty {
                    EmptyState(
                        symbol: "magnifyingglass",
                        title: "No tools match “\(app.search)”",
                        message: "Try a category name, a file type, or a shorter word."
                    ) {
                        app.search = ""
                        searchFocused = true
                    }
                } else {
                    ForEach(app.groupedTools, id: \.category.id) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(
                                title: group.category.name,
                                subtitle: group.category.blurb,
                                trailing: AnyView(
                                    Text("\(group.tools.count)")
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(Theme.textTertiary)
                                        .monospacedDigit()
                                )
                            )
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(group.tools) { tool in
                                    ToolTile(tool: tool) {
                                        app.openTool(tool.slug)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.l)
            .padding(.bottom, 40)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .onChange(of: app.searchFocusToken) { _, _ in
            searchFocused = true
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(app.selectedCategory == nil ? "All tools" : (app.catalog.category(id: app.selectedCategory ?? "")?.name ?? "Tools"))
                    .font(Theme.display(28))
                    .foregroundStyle(Theme.textPrimary)
                Text(app.selectedCategory == nil
                     ? "The whole kit, grouped by what you’re trying to get done."
                     : (app.catalog.category(id: app.selectedCategory ?? "")?.blurb ?? ""))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 12)
            searchField
                .frame(width: 270)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("Search 94 tools", text: $app.search)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
            if !app.search.isEmpty {
                Button {
                    app.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            } else {
                Text("⌘K")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Theme.line, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .strokeBorder(searchFocused ? Theme.ember.opacity(0.5) : Theme.line, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    private var recentRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PICK UP WHERE YOU LEFT OFF")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: 8) {
                ForEach(app.recentTools.prefix(4)) { tool in
                    Button {
                        app.openTool(tool.slug)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tool.symbol)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.ember)
                            Text(tool.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Hero

struct HeroStrip: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .fill(Theme.ink)
            // Single restrained ember wash behind the mark.
            Circle()
                .fill(Theme.ember.opacity(0.22))
                .frame(width: 240, height: 240)
                .blur(radius: 70)
                .offset(x: 70, y: -30)

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Circle().fill(Theme.mint).frame(width: 5, height: 5)
                        Text("ON-DEVICE · NO ACCOUNT")
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.paper.opacity(0.65))
                    }
                    Text("94 Mac tools.\nOne notch away.")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.paper)
                        .lineSpacing(1)
                    Text("Video, audio, images, PDFs, files and dev scratchpads — plus a notch that earns its keep.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.paper.opacity(0.62))
                        .frame(maxWidth: 520, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        statPill("\(app.catalog.tools.count) tools")
                        statPill("\(ToolRegistry.shared.readyCount(in: app.catalog)) ready")
                        statPill("macOS 14+")
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
                NotchMark()
                    .frame(width: 156, height: 84)
                    .padding(.trailing, 8)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(minHeight: 164)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func statPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.paper.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}

/// Decorative notch: black housing with the module dots glowing inside.
struct NotchMark: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .frame(height: 40)
                .frame(maxHeight: .infinity, alignment: .top)
            HStack(spacing: 5) {
                Circle().fill(Theme.ember).frame(width: 5, height: 5)
                Circle().fill(Theme.mint).frame(width: 4, height: 4)
                Circle().fill(Color.white.opacity(0.4)).frame(width: 4, height: 4)
                Circle().fill(Color.white.opacity(0.25)).frame(width: 4, height: 4)
            }
            .padding(.top, 17)
        }
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
    }
}

// MARK: - Tile

struct ToolTile: View {
    let tool: ToolItem
    let action: () -> Void

    @State private var hovering = false
    private var ready: Bool { ToolRegistry.shared.has(tool.slug) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    IconBadge(symbol: tool.symbol, tint: ready ? Theme.ember : Theme.textTertiary, size: 34, corner: 9)
                    Spacer()
                    StatusBadge(ready: ready)
                }
                Text(tool.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(tool.tagline)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Image(systemName: CatalogStore.shared.category(id: tool.category)?.symbol ?? "square")
                        .font(.system(size: 8.5))
                    Text(catalogCategoryName)
                        .font(.system(size: 10))
                }
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background(hovering ? Theme.cardHover : Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(hovering ? Theme.ember.opacity(0.32) : Theme.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverLift(hovering)
        .onHover { hovering = $0 }
        .help(tool.description)
    }

    private var catalogCategoryName: String {
        CatalogStore.shared.category(id: tool.category)?.name ?? tool.category.capitalized
    }
}
