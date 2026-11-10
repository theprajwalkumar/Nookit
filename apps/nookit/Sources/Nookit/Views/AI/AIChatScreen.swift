import SwiftUI
import UniformTypeIdentifiers

/// Full-size AI assistant for the dashboard, styled after a native
/// Claude/Gemini conversation: centered column, light-weight assistant rows,
/// compact composer, and no oversized message blocks.
struct AIChatScreen: View {
    @ObservedObject private var chat = AIChatService.shared
    @Environment(\.openSettings) private var openSettings
    @State private var showFilePicker = false
    @State private var attachedFiles: [AttachedFile] = []
    @State private var isDropTargeted = false
    @FocusState private var inputFocused: Bool

    private let prompts = [
        ("doc.text.magnifyingglass", "Summarise this document"),
        ("photo.on.rectangle", "Describe this image"),
        ("terminal", "Explain a shell error"),
        ("square.and.pencil", "Draft a short email"),
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(Theme.line)

                conversation

                composer
            }
            .frame(maxWidth: 860, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.ember.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Theme.ember.opacity(0.05))
                    )
                    .padding(10)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .background(Theme.background)
        .task { await chat.refresh() }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDroppedFiles(providers)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.ember, Theme.ember.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 27, height: 27)
                    .shadow(color: Theme.ember.opacity(0.28), radius: 6, y: 2)

                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x160A04))
            }

            // Exactly one status line, as requested: "Ready · Nookit AI ·".
            // The raw model ID never appears outside AI Configuration.
            Text(headerStatus)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())

            statusDot

            Spacer(minLength: 8)

            if chat.busy {
                Button {
                    chat.stop()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Stop")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(Theme.warning.opacity(0.10))
                            .overlay(Capsule().strokeBorder(Theme.warning.opacity(0.25), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .help("Stop generating")
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            headerIcon("square.and.pencil", help: "New chat", spinning: false) {
                withAnimation(.easeOut(duration: 0.16)) { chat.newChat() }
                inputFocused = true
            }

            headerIcon("arrow.clockwise", help: "Refresh models", spinning: chat.checking) {
                Task { await chat.refresh() }
            }
            .disabled(chat.checking)

            headerIcon("gearshape", help: "AI Configuration", spinning: false) {
                openSettings()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: chat.busy)
        .animation(.easeOut(duration: 0.2), value: chat.checking)
    }

    private var headerStatus: String {
        if chat.checking { return "Connecting · Nookit AI ·" }
        if chat.busy { return "Thinking · Nookit AI ·" }
        if chat.isSupported { return "Ready · Nookit AI ·" }
        return "Offline · Nookit AI ·"
    }

    private var statusDot: some View {
        Circle()
            .fill(chat.isSupported ? Theme.mint : Theme.warning)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .stroke(chat.isSupported ? Theme.mint : Theme.warning, lineWidth: 1.5)
                    .scaleEffect(chat.checking || chat.busy ? 1.8 : 1)
                    .opacity(chat.checking || chat.busy ? 0 : 1)
                    .animation(
                        chat.checking || chat.busy
                            ? .easeOut(duration: 1.1).repeatForever(autoreverses: false)
                            : .default,
                        value: chat.checking || chat.busy
                    )
            )
    }

    private func headerIcon(_ name: String, help: String, spinning: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 26, height: 26)
                .background(Theme.raised, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    spinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: spinning
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if chat.messages.isEmpty {
                        EmptyStateView(prompts: prompts) { prompt in
                            chat.input = prompt
                            inputFocused = true
                        }
                        .id("empty-state")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    ForEach(chat.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 6))
                                    .animation(.spring(response: 0.38, dampingFraction: 0.9)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            ))
                    }

                    if chat.busy && (chat.messages.last?.text.isEmpty ?? true) {
                        ThinkingRow(reasoning: chat.messages.last?.reasoning ?? "")
                            .id("thinking")
                            .transition(.opacity)
                    }

                    if let error = chat.error {
                        ErrorBanner(message: error)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Color.clear.frame(height: 1).id("bottom-anchor")
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 10)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.never)
            .onChange(of: chat.messages.count) { _, _ in
                scrollToBottom(proxy, animated: true)
            }
            .onChange(of: chat.messages.last?.text) { _, _ in
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: chat.busy) { _, busy in
                if busy { scrollToBottom(proxy, animated: true) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            if animated {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if !attachedFiles.isEmpty {
                    attachmentChips
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                HStack(alignment: .bottom, spacing: 8) {
                    Button {
                        showFilePicker = true
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(attachedFiles.isEmpty ? Theme.textSecondary : Theme.ember)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Attach an image, PDF, or text file")

                    ZStack(alignment: .topLeading) {
                        if chat.input.isEmpty {
                            Text("Ask Nookit anything…")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.vertical, 6)
                                .allowsHitTesting(false)
                        }

                        TextField("", text: $chat.input, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .lineLimit(1...6)
                            .focused($inputFocused)
                            .padding(.vertical, 6)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if chat.busy {
                        Button {
                            chat.stop()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Theme.warning))
                        }
                        .buttonStyle(.plain)
                        .help("Stop generating")
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(canSend ? Color(hex: 0x160A04) : Theme.textTertiary)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle().fill(canSend ? Theme.ember : Theme.line.opacity(0.55))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Send (⌘↩)")
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 7)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.raised)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(
                                    inputFocused ? Theme.ember.opacity(0.35) : Theme.line,
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background],
                startPoint: .top,
                endPoint: .center
            )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: attachedFiles.count)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.image, .pdf, .plainText, .rtf, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { addFiles(urls) }
        }
    }

    private var canSend: Bool {
        !chat.busy && (!chat.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedFiles.isEmpty)
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(attachedFiles) { file in
                    AttachmentChip(file: file) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            attachedFiles.removeAll { $0.id == file.id }
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 40)
    }

    private func send() {
        let text = chat.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        let files = attachedFiles
        attachedFiles.removeAll()
        chat.input = ""
        Task { await chat.sendWithAttachments(text, files: files) }
    }

    private func addFiles(_ urls: [URL]) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url), data.count <= 25_000_000 else { continue }
                guard !attachedFiles.contains(where: { $0.filename == url.lastPathComponent && $0.data == data }) else { continue }
                attachedFiles.append(AttachedFile(data: data, filename: url.lastPathComponent))
            }
        }
    }

    private func loadDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else if let string = item as? String {
                    url = URL(string: string)
                }
                guard let url else { return }
                DispatchQueue.main.async { addFiles([url]) }
            }
        }
        return accepted
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    let prompts: [(String, String)]
    let onPrompt: (String) -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.ember.opacity(0.14), Theme.ember.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.ember)
                }
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.76), value: appeared)

                Text("How can I help?")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)

                Text("Ask anything, attach an image or PDF, or drop a file anywhere in this window.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 8)], spacing: 8) {
                ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
                    Button {
                        onPrompt(prompt.1)
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: prompt.0)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.ember.opacity(0.85))
                            Text(prompt.1)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.raised)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.82).delay(0.12 + Double(index) * 0.05),
                        value: appeared
                    )
                }
            }
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .onAppear { appeared = true }
    }
}

// MARK: - Messages

private struct MessageRow: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }
    private var images: [AttachedFile] { message.attachments.filter(\.isImage) }
    private var documents: [AttachedFile] { message.attachments.filter { !$0.isImage } }

    var body: some View {
        if isUser {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 60)

                VStack(alignment: .trailing, spacing: 8) {
                    if !images.isEmpty { imageGrid }
                    if !documents.isEmpty { documentList }

                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.system(size: 13))
                            .lineSpacing(2.5)
                            .foregroundStyle(Color(hex: 0x160A04))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.emberSoft)
                )
                .frame(maxWidth: 560, alignment: .trailing)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                assistantAvatar

                VStack(alignment: .leading, spacing: 7) {
                    if message.text.isEmpty {
                        Text(message.reasoning.isEmpty ? "Thinking…" : "Thinking…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(attributed(message.text))
                            .font(.system(size: 13.5))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !message.text.isEmpty {
                        CopyButton(value: message.text, compact: true)
                            .opacity(0.7)
                    }
                }
                .frame(maxWidth: 650, alignment: .leading)
                .padding(.top, 3)

                Spacer(minLength: 30)
            }
        }
    }

    private var assistantAvatar: some View {
        ZStack {
            Circle()
                .fill(Theme.ember.opacity(0.10))
                .frame(width: 25, height: 25)
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.ember)
        }
    }

    private var imageGrid: some View {
        HStack(spacing: 6) {
            ForEach(images) { file in
                if let image = file.nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 138, height: 138)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                }
            }
        }
    }

    private var documentList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(documents) { file in
                HStack(spacing: 7) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ember)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                    VStack(alignment: .leading, spacing: 0) {
                        Text(file.filename)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color(hex: 0x160A04))
                            .lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .file))
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: 0x160A04).opacity(0.55))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

// MARK: - Thinking

private struct ThinkingRow: View {
    let reasoning: String
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.ember.opacity(0.10))
                    .frame(width: 25, height: 25)
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.ember)
            }

            HStack(spacing: 6) {
                Text("Thinking")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 3) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Theme.textTertiary)
                            .frame(width: 4.5, height: 4.5)
                            .scaleEffect(animating ? 1.15 : 0.7)
                            .opacity(animating ? 0.9 : 0.35)
                            .animation(
                                .easeInOut(duration: 0.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.13),
                                value: animating
                            )
                    }
                }
            }
            .padding(.top, 5)

            Spacer(minLength: 30)
        }
        .onAppear { animating = true }
    }
}

// MARK: - Attachment chip

private struct AttachmentChip: View {
    let file: AttachedFile
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if file.isImage, let image = file.nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Theme.line.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            Text(file.filename)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 130)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hovering ? Theme.warning : Theme.textTertiary)
                    .frame(width: 16, height: 16)
                    .background(Theme.line.opacity(hovering ? 0 : 0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
        .padding(.leading, 4)
        .padding(.trailing, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.raised)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        )
    }
}

// MARK: - Error

private struct ErrorBanner: View {
    let message: String
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)

            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            Button("Dismiss") {
                withAnimation(.easeOut(duration: 0.18)) {
                    AIChatService.shared.error = nil
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Theme.ember)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.warning.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.warning.opacity(0.22), lineWidth: 1))
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 4)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { appeared = true }
        }
    }
}
