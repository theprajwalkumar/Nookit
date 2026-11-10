import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Badges & labels

struct Badge: View {
    let text: String
    var tint: Color = Theme.textSecondary
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.4)
            .foregroundStyle(filled ? Color(hex: 0x160A04) : tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(filled ? tint : tint.opacity(0.13), in: Capsule())
    }
}

struct StatusBadge: View {
    let ready: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ready ? Theme.mint : Theme.textTertiary)
                .frame(width: 5, height: 5)
            Text(ready ? "Ready" : "Soon")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(ready ? Theme.mint : Theme.textTertiary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((ready ? Theme.mint : Theme.textTertiary).opacity(0.12), in: Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

struct IconBadge: View {
    let symbol: String
    var tint: Color = Theme.ember
    var size: CGFloat = 38
    var corner: CGFloat = 10

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - Copy

struct CopyButton: View {
    let value: String
    var label: String = "Copy"
    var compact: Bool = false

    @State private var copied = false

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.4))
                copied = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                Text(copied ? "Copied" : label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(copied ? Theme.mint : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((copied ? Theme.mint : Theme.textSecondary).opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(value.isEmpty)
        .opacity(value.isEmpty ? 0.4 : 1)
        .help("Copy to clipboard")
    }
}

// MARK: - Tool chrome

struct ToolHeader: View {
    let symbol: String
    let title: String
    let subtitle: String
    var ready: Bool = true
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: symbol, tint: ready ? Theme.ember : Theme.textTertiary, size: 48, corner: Theme.radiusSmall)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    if !ready { StatusBadge(ready: false) }
                }
                Text(subtitle)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let trailing { trailing }
        }
    }
}

struct ToolPage<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    var ready: Bool = true
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                ToolHeader(symbol: symbol, title: title, subtitle: subtitle, ready: ready, trailing: trailing)
                content()
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }
}

// MARK: - Progress & errors

struct ProgressCard: View {
    @ObservedObject var context: ToolContext
    var cancel: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(context.status.isEmpty ? "Working…" : context.status)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let cancel {
                    Button("Cancel", action: cancel)
                        .buttonStyle(QuietButtonStyle())
                }
            }
            if let progress = context.progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(Theme.ember)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.ember)
            }
        }
        .padding(Theme.Space.m)
        .nookitCard(raised: true)
    }
}

struct InlineError: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
                .font(.system(size: 13))
            Text(message)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(12)
        .background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Results

struct ResultsPanel: View {
    @ObservedObject var context: ToolContext
    @EnvironmentObject private var store: ResultStore

    var body: some View {
        if !context.results.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Results", subtitle: "\(context.results.count) file\(context.results.count == 1 ? "" : "s") saved")
                    Spacer()
                    Button("Show folder") {
                        if let first = context.results.first {
                            store.reveal(first.url.deletingLastPathComponent())
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                VStack(spacing: 1) {
                    ForEach(context.results) { file in
                        ResultRow(file: file)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
            }
        }
    }
}

struct ResultRow: View {
    let file: ResultFile
    @EnvironmentObject private var store: ResultStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ember)
                .frame(width: 26, height: 26)
                .background(Theme.ember.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(Fmt.bytes(file.size))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button("Reveal") { store.reveal(file.url) }
                .buttonStyle(QuietButtonStyle())
            Button("Open") { store.open(file.url) }
                .buttonStyle(QuietButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(hovering ? Theme.raised : Theme.card)
        .onHover { hovering = $0 }
    }

    private var icon: String {
        switch file.url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "tiff", "gif": return "photo"
        case "mp4", "mov", "m4v": return "film"
        case "m4a", "aiff", "wav", "mp3": return "waveform"
        case "pdf": return "doc.richtext"
        case "zip": return "archivebox"
        case "json": return "curlybraces"
        case "md", "txt": return "doc.text"
        default: return "doc"
        }
    }
}

// MARK: - Inputs

struct CodeEditor: View {
    @Binding var text: String
    var height: CGFloat = 220
    var placeholder: String = ""
    var monospaced: Bool = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(monospaced ? .system(size: 12, design: .monospaced) : Theme.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: height)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
            if text.isEmpty && !placeholder.isEmpty {
                Text(placeholder)
                    .font(monospaced ? .system(size: 12, design: .monospaced) : Theme.body)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct LabelledField<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if let hint {
                    Text(hint)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            content()
        }
    }
}

struct DropZone: View {
    let title: String
    var subtitle: String = "Drop files here, or click to choose."
    var allowsMultiple: Bool = true
    var types: [UTType]? = nil
    var height: CGFloat = 120
    var onFiles: ([URL]) -> Void

    @State private var targeted = false

    var body: some View {
        Button {
            let picked = FilePicker.files(title: title, types: types, allowsMultiple: allowsMultiple)
            if !picked.isEmpty { onFiles(picked) }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: targeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(targeted ? Theme.ember : Theme.textSecondary)
                Text(targeted ? "Drop to add" : title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(targeted ? Theme.ember.opacity(0.07) : Theme.raised.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(
                        targeted ? Theme.ember.opacity(0.6) : Theme.lineStrong,
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            DropHandler.fileURLs(from: providers) { urls in
                if !allowsMultiple { onFiles(Array(urls.prefix(1))) } else { onFiles(urls) }
            }
            return true
        }
    }
}

struct FileChip: View {
    let url: URL
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.system(size: 10))
                .foregroundStyle(Theme.ember)
            Text(url.lastPathComponent)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.xl)
        .nookitCard()
    }
}

// MARK: - Misc

struct ConfirmButton: View {
    let title: String
    var confirmTitle: String = "Are you sure?"
    var detail: String = "This action can’t be undone."
    var destructive: Bool = false
    var action: () -> Void

    @State private var showing = false

    var body: some View {
        Button(title) { showing = true }
            .buttonStyle(destructive ? AnyButtonStyle(PrimaryButtonStyle(tint: Theme.danger)) : AnyButtonStyle(SecondaryButtonStyle()))
            .alert(confirmTitle, isPresented: $showing) {
                Button("Cancel", role: .cancel) {}
                Button(title, role: destructive ? .destructive : nil) { action() }
            } message: {
                Text(detail)
            }
    }
}

/// Type-erasing wrapper so we can pick a button style dynamically.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
