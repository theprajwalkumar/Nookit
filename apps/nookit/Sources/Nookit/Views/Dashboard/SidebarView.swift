import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var notchSettings = NotchSettings.shared
    @ObservedObject private var chat = AIChatService.shared
    @ObservedObject private var apps = AppsService.shared
    @AppStorage("NookitSidebarAppsExpanded") private var appsExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group(title: "Library") {
                        sidebarRow(
                            title: "All tools",
                            symbol: "square.grid.2x2",
                            count: app.count(for: nil),
                            active: app.selectedCategory == nil && app.selectedToolSlug == nil && !app.showNotchSettings && !app.showAIChat && !app.showHype && !app.showApps
                        ) {
                            app.openCategory(nil)
                        }
                    }

                    group(title: "Categories") {
                        VStack(spacing: 1) {
                            ForEach(app.catalog.categories) { category in
                                sidebarRow(
                                    title: category.name,
                                    symbol: category.symbol,
                                    count: app.count(for: category.id),
                                    active: app.selectedCategory == category.id && app.selectedToolSlug == nil && !app.showNotchSettings && !app.showAIChat && !app.showHype && !app.showApps
                                ) {
                                    app.openCategory(category.id)
                                }
                            }
                        }
                    }

                    if !app.recentTools.isEmpty {
                        group(title: "Recent") {
                            VStack(spacing: 1) {
                                ForEach(app.recentTools.prefix(5)) { tool in
                                    sidebarRow(
                                        title: tool.name,
                                        symbol: tool.symbol,
                                        count: nil,
                                        active: app.selectedToolSlug == tool.slug,
                                        compact: true
                                    ) {
                                        app.openTool(tool.slug)
                                    }
                                }
                            }
                        }
                    }

                    group(title: "Discover") {
                        VStack(spacing: 1) {
                            sidebarRow(
                                title: "Hype",
                                symbol: "sparkles.rectangle.stack",
                                count: nil,
                                active: app.showHype
                            ) {
                                app.openHype()
                            }

                            HStack(spacing: 0) {
                                sidebarRow(
                                    title: "Apps",
                                    symbol: "square.grid.2x2",
                                    count: GoogleApp.allCases.count,
                                    active: app.showApps
                                ) {
                                    app.openApps()
                                }

                                Button {
                                    withAnimation(.easeOut(duration: 0.16)) { appsExpanded.toggle() }
                                } label: {
                                    Image(systemName: appsExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(Theme.textTertiary)
                                        .frame(width: 18, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 4)
                                .help(appsExpanded ? "Hide Google apps" : "Show Google apps")
                            }

                            if appsExpanded {
                                VStack(spacing: 1) {
                                    ForEach(GoogleApp.allCases) { item in
                                        sidebarRow(
                                            title: item.title,
                                            symbol: item.symbol,
                                            count: nil,
                                            active: app.showApps && apps.selectedApp == item,
                                            compact: true
                                        ) {
                                            app.openApps(item)
                                        }
                                        .padding(.leading, 13)
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }

                    group(title: "AI") {
                        VStack(spacing: 1) {
                            sidebarRow(
                                title: "Nookit AI",
                                symbol: "sparkles",
                                count: nil,
                                active: app.showAIChat
                            ) {
                                app.openAIChat()
                            }

                            chatActionRow(title: "New chat", symbol: "plus") {
                                app.openAIChat()
                                chat.newChat()
                            }

                            ForEach(chat.sessions.prefix(5)) { session in
                                chatRow(session)
                            }
                        }
                    }

                    group(title: "Notch") {
                        VStack(spacing: 1) {
                            sidebarRow(
                                title: "Notch settings",
                                symbol: "rectangle.topthird.inset.filled",
                                count: nil,
                                active: app.showNotchSettings
                            ) {
                                app.showNotchPreferences()
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "circle.dashed")
                                    .font(.system(size: 11))
                                    .foregroundStyle(notchSettings.enabled ? Theme.mint : Theme.textTertiary)
                                    .frame(width: 18)
                                Text(notchSettings.enabled ? "Overlay on" : "Overlay off")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Toggle("", isOn: $notchSettings.enabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }

            Spacer(minLength: 0)

            footer
                .padding(14)
        }
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.line).frame(width: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.ember)
                Image(systemName: "n.square.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(hex: 0x160A04))
                    .opacity(0.9)
                    .hidden()
                Text("N")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: 0x160A04))
            }
            .frame(width: 32, height: 32)
            .shadow(color: Theme.ember.opacity(0.35), radius: 10, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text("Nookit")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("One notch away")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.mint)
                    .frame(width: 5, height: 5)
                Text("\(ToolRegistry.shared.readyCount(in: app.catalog)) of \(app.catalog.tools.count) ready")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("Everything runs on this Mac.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.line.opacity(0.45), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    private func chatActionRow(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.ember.opacity(0.8))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Start a fresh Nookit AI conversation")
    }

    private func chatRow(_ session: ChatSession) -> some View {
        let active = app.showAIChat && chat.currentSessionID == session.id

        return Button {
            app.openAIChat()
            chat.openSession(session.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: active ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(active ? Theme.ember : Theme.textTertiary)
                    .frame(width: 18)
                Text(session.title)
                    .font(.system(size: 11.5, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(session.messageCount)")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(active ? Theme.ember.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(session.preview)
        .contextMenu {
            Button("Delete chat", role: .destructive) {
                chat.deleteSession(session.id)
            }
        }
    }

    @ViewBuilder
    private func group<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 8)
            content()
        }
    }

    @ViewBuilder
    private func sidebarRow(
        title: String,
        symbol: String,
        count: Int?,
        active: Bool,
        compact: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 10.5 : 11.5, weight: .medium))
                    .foregroundStyle(active ? Theme.ember : Theme.textSecondary)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 5 : 6)
            .background(active ? Theme.ember.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
