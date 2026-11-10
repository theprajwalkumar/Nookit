import SwiftUI

struct ToolDetailView: View {
    let tool: ToolItem
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var store: ResultStore
    @ObservedObject private var settings = NotchSettings.shared

    private var ready: Bool { ToolRegistry.shared.has(tool.slug) }
    private var category: ToolCategory? { app.catalog.category(id: tool.category) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                backBar

                HStack(alignment: .top, spacing: 18) {
                    IconBadge(symbol: tool.symbol, tint: ready ? Theme.ember : Theme.textTertiary, size: 72, corner: 18)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text(tool.name)
                                .font(Theme.display(30))
                                .foregroundStyle(Theme.textPrimary)
                            StatusBadge(ready: ready)
                        }
                        Text(tool.tagline)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 6) {
                            Badge(text: category?.name ?? tool.category.capitalized)
                            Badge(text: "On-device", tint: Theme.mint)
                            if ready { Badge(text: "Writes new files", tint: Theme.emberSoft) }
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }

                Text(tool.description)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(4.5)
                    .frame(maxWidth: 760, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if ready {
                        Button {
                            app.runTool(tool.slug)
                        } label: {
                            Label("Open tool", systemImage: "arrow.right")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: [])
                    }
                    Button {
                        let folder = store.datedFolder(for: tool.name)
                        store.reveal(folder)
                    } label: {
                        Label("Reveal results folder", systemImage: "folder")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                if ready {
                    readyPanel
                } else {
                    comingSoonPanel
                }

                Spacer(minLength: 20)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    private var backBar: some View {
        HStack(spacing: 8) {
            Button {
                app.selectedToolSlug = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("All tools")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var readyPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: "How it behaves", subtitle: "The Nookit house rules.")
            HStack(alignment: .top, spacing: 10) {
                rule("lock.shield", "Stays local", "No uploads. Nothing leaves this Mac.")
                rule("folder.badge.plus", "New files only", "Saves into a dated folder in Downloads.")
                rule("arrow.uturn.backward", "Nothing overwritten", "Name collisions get a numbered copy.")
            }
        }
        .padding(Theme.Space.m)
        .nookitCard()
    }

    private var comingSoonPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Badge(text: "Queued for 1.1", tint: Theme.emberSoft)
                Text("This screen isn’t wired up yet.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("The catalog entry and design are ready. The tool itself ships in the next update — meanwhile the rest of the kit keeps working offline.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Open notch instead") {
                    settings.enabled = true
                    app.showNotchPreferences()
                }
                .buttonStyle(QuietButtonStyle())
                Button("Request this next") {
                    if let url = URL(string: "mailto:support@nookit.app?subject=Nookit%20request%3A%20\(tool.slug)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(Theme.Space.m)
        .nookitCard()
    }

    private func rule(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ember)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Theme.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}

struct ToolRunnerView: View {
    let tool: ToolItem
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    app.runningToolSlug = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Back")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)

                Divider().frame(height: 12)
                Text(tool.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Saved to \(store.outputRoot.lastPathComponent)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                Button("Reveal") {
                    store.reveal(store.datedFolder(for: tool.name))
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.sidebar)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }

            Group {
                if let view = ToolRegistry.shared.view(for: tool.slug) {
                    view
                } else {
                    ComingSoonView(tool: tool)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
    }
}
