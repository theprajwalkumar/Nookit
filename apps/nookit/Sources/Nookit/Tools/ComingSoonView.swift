import SwiftUI

struct ComingSoonView: View {
    let tool: ToolItem

    private var categoryName: String {
        CatalogStore.shared.category(id: tool.category)?.name ?? tool.category.capitalized
    }

    var body: some View {
        ToolPage(symbol: tool.symbol, title: tool.name, subtitle: tool.tagline, ready: false) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(spacing: 8) {
                    Badge(text: "Queued for 1.1", tint: Theme.emberSoft)
                    Badge(text: categoryName)
                }

                Text(tool.description)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader(title: "What it will do", subtitle: "Built with the same rules as everything in Nookit.")
                    roadmapRow("Runs entirely on your Mac", "No uploads, no accounts, no telemetry.", "lock.shield")
                    roadmapRow("Writes new files, never edits originals", "Results land in a dated folder in Downloads.", "folder.badge.plus")
                    roadmapRow("Shows progress and can be cancelled", "Long jobs stay responsive and honest.", "gauge.with.dots.needle.50percent")
                    roadmapRow("Full keyboard and drag-and-drop support", "Drop files straight onto the window.", "keyboard")
                }

                HStack(spacing: 10) {
                    Text("Missing this one?")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textTertiary)
                    Button("Tell us what you need") {
                        if let url = URL(string: "mailto:support@nookit.app?subject=Nookit%20tool%20request%3A%20\(tool.slug)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                .padding(.top, 4)
            }
        }
    }

    private func roadmapRow(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ember.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(Theme.ember.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Theme.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}
