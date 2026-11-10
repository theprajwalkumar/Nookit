import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Shared tool building blocks

/// A titled card used by tool screens.
struct ToolCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, subtitle: subtitle, trailing: trailing)
            content()
        }
        .padding(Theme.Space.m)
        .nookitCard()
    }
}

/// Read-only output with Copy and Save-to-Downloads actions.
struct TextOutputCard: View {
    let toolName: String
    let text: String
    var title: String = "Output"
    var filename: String = "output.txt"
    var language: String = "txt"
    var footnote: String? = nil

    @EnvironmentObject private var store: ResultStore
    @State private var savedURL: URL?

    var body: some View {
        ToolCard(
            title: title,
            subtitle: footnote,
            trailing: AnyView(
                HStack(spacing: 6) {
                    CopyButton(value: text)
                    Button(savedURL == nil ? "Save" : "Saved") {
                        save()
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(text.isEmpty)
                    if let savedURL {
                        Button("Reveal") { store.reveal(savedURL) }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
            )
        ) {
            if text.isEmpty {
                Text("Nothing to show yet.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                    .padding(10)
                    .background(Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 120, maxHeight: 320)
                .background(Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
            }
        }
    }

    private func save() {
        do {
            let folder = store.datedFolder(for: toolName)
            savedURL = try store.write(string: text, to: folder, filename: filename)
        } catch {
            savedURL = nil
        }
    }
}

/// A compact metric tile (word counts, durations, sizes).
struct StatTile: View {
    let label: String
    let value: String
    var tint: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}

struct StatRow: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                StatTile(label: item.0, value: item.1)
            }
        }
    }
}

/// Simple labelled picker row that matches the app chrome.
struct OptionPicker<Value: Hashable>: View {
    let label: String
    let options: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Picker(label, selection: $selection) {
                ForEach(options, id: \.1) { option in
                    Text(option.0).tag(option.1)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220)
        }
    }
}

enum ToolFormat {
    static func json(_ value: Any) -> String {
        guard
            JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
            let string = String(data: data, encoding: .utf8)
        else { return "" }
        return string
    }
}

enum ToolError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
