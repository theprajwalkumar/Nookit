import SwiftUI
import AppKit

/// Agentic workflows for Google Workspace: describe the outcome, let Nookit
/// draft it, then create the real document, sheet, deck, draft, event or Meet
/// in the user's own Google account.
struct AppsScreen: View {
    @ObservedObject private var service = AppsService.shared
    @ObservedObject private var chat = AIChatService.shared
    @ObservedObject private var google = GoogleAuthService.shared
    @EnvironmentObject private var app: AppState

    @State private var toast: String?
    @State private var hoveredApp: GoogleApp?
    @State private var showGoogleSetup = false
    @State private var showAccount = false
    @State private var setupClientID = ""
    @State private var setupClientSecret = ""

    private var selected: GoogleApp { service.selectedApp }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(Theme.line)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        appPicker

                        if !service.googleConnected {
                            googleBanner
                        }

                        HStack(alignment: .top, spacing: 14) {
                            workflowCard
                                .frame(minWidth: 300, maxWidth: 350)

                            draftCard
                                .frame(maxWidth: .infinity)
                        }

                        if !service.history.isEmpty {
                            historyStrip
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 1040, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }

            if let toast {
                Text(toast)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Theme.card)
                            .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 1))
                            .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
                    )
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: toast)
        .sheet(isPresented: $showGoogleSetup) {
            googleSetupSheet
        }
        .onChange(of: service.needsGoogle) { _, needs in
            guard needs else { return }
            if google.hasClientID {
                Task { await service.connectGoogle() }
            } else {
                openSetup()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x4285F4), Color(hex: 0x34A853)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Apps")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Real Google Workspace actions, drafted by AI.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(chat.isSupported ? Theme.mint : Theme.warning)
                    .frame(width: 5, height: 5)
                Text(chat.isSupported ? "Nookit AI ready" : "AI needs a key")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))

            Button {
                if google.isConnected {
                    showAccount = true
                } else {
                    connectOrSetup()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: google.isConnected ? "checkmark.circle.fill" : "person.badge.key.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(googleLabel)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(google.isConnected ? Theme.mint : Theme.ember)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((google.isConnected ? Theme.mint : Theme.ember).opacity(0.10), in: Capsule())
                .overlay(Capsule().strokeBorder((google.isConnected ? Theme.mint : Theme.ember).opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAccount, arrowEdge: .bottom) {
                accountPopover
            }

            Button {
                app.openAIChat()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("Nookit AI")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.ember)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.ember.opacity(0.10), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.ember.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private var googleLabel: String {
        if google.connecting { return "Connecting…" }
        if google.isConnected {
            return google.accountEmail ?? (google.accountName ?? "Google connected")
        }
        return "Connect Google"
    }

    private var accountPopover: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.mint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(google.accountName ?? "Google account")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(google.accountEmail ?? "Connected")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Divider().overlay(Theme.line)

            Text("Nookit can create Docs, Sheets, Slides, Gmail drafts, Calendar events, Meet links and Drive folders in this account.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("OAuth client") {
                    showAccount = false
                    openSetup()
                }
                .buttonStyle(QuietButtonStyle())

                Spacer()

                Button("Disconnect") {
                    service.disconnectGoogle()
                    showAccount = false
                    showToast("Google disconnected")
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(13)
        .frame(width: 268)
    }

    // MARK: - Google banner

    private var googleBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(hex: 0x4285F4).opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x4285F4))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect Google to create real files")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Nookit uses Google's official OAuth flow. Your draft becomes a document in your account — nothing is faked or copied to the web.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if google.connecting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Finish in your browser")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Button("Set up OAuth") { openSetup() }
                    .buttonStyle(QuietButtonStyle())

                Button("Connect Google") { connectOrSetup() }
                    .buttonStyle(PrimaryButtonStyle(tint: Color(hex: 0x4285F4)))
                    .disabled(!google.hasClientID)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(hex: 0x4285F4).opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color(hex: 0x4285F4).opacity(0.20), lineWidth: 1)
                )
        )
    }

    // MARK: - OAuth setup sheet

    private var googleSetupSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: 0x4285F4).opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x4285F4))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Google OAuth client")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("One-time setup · stored locally")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                Button("Close") { showGoogleSetup = false }
                    .buttonStyle(QuietButtonStyle())
            }

            Text("Nookit connects directly to Google with your own Desktop OAuth client. No shared credentials, no server in the middle.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                setupStep(1, "Open Google Cloud Console and create a project (or pick one).")
                setupStep(2, "Enable the Docs, Sheets, Slides, Gmail, Calendar and Drive APIs.")
                setupStep(3, "Create Credentials → OAuth client ID → Desktop app.")
                setupStep(4, "Paste the client ID and secret below, then connect.")
            }
            .padding(11)
            .background(Theme.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    open("https://console.cloud.google.com/apis/credentials")
                } label: {
                    Label("Credentials", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    open("https://console.cloud.google.com/apis/library")
                } label: {
                    Label("Enable APIs", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(QuietButtonStyle())

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("CLIENT ID")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)

                TextField("1234567890-abc.apps.googleusercontent.com", text: $setupClientID)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .fieldStyle()

                Text("CLIENT SECRET")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)

                SecureField("GOCSPX-… (optional for desktop clients)", text: $setupClientSecret)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .fieldStyle()
            }

            Text("The loopback redirect is handled by Nookit automatically. Tokens are kept in your macOS Keychain; your client credentials stay in local app preferences.")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer()

                Button("Cancel") { showGoogleSetup = false }
                    .buttonStyle(QuietButtonStyle())

                Button {
                    service.configureGoogle(clientID: setupClientID, clientSecret: setupClientSecret)
                    showGoogleSetup = false
                    Task { await service.connectGoogle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("Save & Connect")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(tint: Color(hex: 0x4285F4)))
                .disabled(setupClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 470)
        .background(Theme.background)
        .onAppear {
            setupClientID = google.clientID
            setupClientSecret = google.clientSecret
        }
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("\(number)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(hex: 0x160A04))
                .frame(width: 16, height: 16)
                .background(Color(hex: 0x4285F4), in: Circle())
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - App picker

    private var appPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 128), spacing: 8)], spacing: 8) {
            ForEach(GoogleApp.allCases) { item in
                let active = item == selected
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        service.select(item)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: item.symbol)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(active ? item.tint : item.tint.opacity(0.8))
                                .frame(width: 24, height: 24)
                                .background(item.tint.opacity(active ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Spacer()
                            if active {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(item.tint)
                            }
                        }

                        Text(item.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        Text(item.blurb)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(active ? item.tint.opacity(0.06) : Theme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(active ? item.tint.opacity(0.45) : Theme.line, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .onHover { hoveredApp = $0 ? item : (hoveredApp == item ? nil : hoveredApp) }
                .scaleEffect(hoveredApp == item ? 1.01 : 1)
                .animation(.easeOut(duration: 0.12), value: hoveredApp)
            }
        }
    }

    // MARK: - Workflow

    private var workflowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: selected.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected.tint)
                    .frame(width: 28, height: 28)
                    .background(selected.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(selected.fullName) workflow")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Describe the outcome, not the steps.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Try a starter")
                    .font(.system(size: 9.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)

                ForEach(Array(selected.starterPrompts.enumerated()), id: \.offset) { _, prompt in
                    Button {
                        service.useStarter(prompt)
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(selected.tint)
                                .padding(.top, 2)
                            Text(prompt)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("What should Nookit make?")
                    .font(.system(size: 9.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)

                TextEditor(text: $service.brief)
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(minHeight: 118)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            }

            if let error = service.error {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.warning)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            HStack(spacing: 8) {
                if service.running {
                    Button {
                        service.stop()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("Stop")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.warning))
                } else {
                    Button {
                        service.start()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("Draft with Nookit AI")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(service.brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !service.output.isEmpty && !service.running {
                    Button("Clear") { service.clearOutput() }
                        .buttonStyle(QuietButtonStyle())
                }

                Spacer()
            }
        }
        .padding(14)
        .nookitCard()
    }

    // MARK: - Draft

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Draft")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if service.running {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Writing")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                } else if service.creating {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Creating in \(selected.title)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                } else if let last = service.lastRun, !service.output.isEmpty {
                    Text("Saved \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                if !service.output.isEmpty {
                    CopyButton(value: service.output, label: "Copy")
                }
            }

            if service.output.isEmpty && !service.running {
                VStack(spacing: 9) {
                    Image(systemName: selected.symbol)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(selected.tint.opacity(0.85))
                    Text("Your \(selected.title.lowercased()) draft appears here")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(emptyHint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            } else if service.running && service.output.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Nookit is drafting your \(selected.title.lowercased())…")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                ScrollView {
                    Text(service.output)
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                }
                .frame(minHeight: 260, maxHeight: 320)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
            }

            if let workspace = service.workspace {
                workspaceSuccess(workspace)
            }

            if let note = service.note {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(spacing: 8) {
                if let workspace = service.workspace {
                    Button {
                        service.openWorkspaceResult()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square.fill")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("Open in \(workspace.app.title)")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: workspace.app.tint))
                } else {
                    Button {
                        create()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: service.googleConnected ? selected.symbol : "person.badge.key.fill")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text(primaryActionLabel)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: service.googleConnected ? selected.tint : Color(hex: 0x4285F4)))
                    .disabled(service.output.isEmpty || service.running || service.creating)
                }

                Button {
                    saveDraft()
                } label: {
                    Label("Save", systemImage: "arrow.down.circle")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(service.output.isEmpty || service.running)

                if !service.output.isEmpty {
                    Button(selected.fallbackLabel) { handOff() }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(service.running)
                }

                Spacer()

                Text(selected.outputFormat == .csv ? "CSV" : selected.fileExtension.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.line.opacity(0.45), in: Capsule())
            }
        }
        .padding(14)
        .nookitCard()
    }

    private var primaryActionLabel: String {
        if service.creating { return "Creating…" }
        if !service.googleConnected { return google.hasClientID ? "Connect Google" : "Set up Google" }
        return selected.openLabel
    }

    private func workspaceSuccess(_ result: WorkspaceResult) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.mint)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(result.detail ?? "Created in your Google account")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(result.url.host ?? result.url.absoluteString)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.url.absoluteString, forType: .string)
                showToast("Link copied")
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Copy link")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.mint.opacity(0.22), lineWidth: 1)
        )
    }

    private var emptyHint: String {
        switch selected {
        case .docs: return "A structured brief, proposal or guide. Nookit creates the Doc with this text already inside."
        case .sheets: return "A clean CSV table. Nookit writes the rows into a new Google Sheet."
        case .slides: return "A slide-by-slide outline. Nookit builds the deck with titles and bullets."
        case .gmail: return "A subject line and body. Nookit saves it as a draft in your Gmail."
        case .calendar: return "A timed agenda. Nookit adds the event to your primary calendar."
        case .meet: return "A running order. Nookit creates the event and attaches a Meet link."
        case .drive: return "A folder and naming system. Nookit creates the folder and the document."
        }
    }

    // MARK: - History

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent drafts")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Clear") { service.clearHistory() }
                    .buttonStyle(QuietButtonStyle())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(service.history.prefix(8)) { run in
                        Button {
                            service.restore(run)
                            showToast("Restored \(run.app?.title ?? "draft")")
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: run.app?.symbol ?? "doc.text")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(run.app?.tint ?? Theme.textSecondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(run.title)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                    Text(run.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: 220, alignment: .leading)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", role: .destructive) { service.deleteRun(run.id) }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: - Actions

    private func create() {
        guard service.googleConnected else {
            connectOrSetup()
            return
        }
        Task { await service.createInGoogle() }
    }

    private func connectOrSetup() {
        guard google.hasClientID else {
            openSetup()
            return
        }
        Task {
            await service.connectGoogle()
            if google.isConnected {
                showToast("Google connected")
            }
        }
    }

    private func openSetup() {
        setupClientID = google.clientID
        setupClientSecret = google.clientSecret
        showGoogleSetup = true
    }

    /// Fallback path: copy the draft and open the web app when the user prefers
    /// not to connect an account.
    private func handOff() {
        guard let url = service.actionURL(for: selected) else {
            showToast("Couldn't build the \(selected.title) link.")
            return
        }
        service.copyToPasteboard()
        NSWorkspace.shared.open(url)
        if selected == .gmail || selected == .calendar {
            showToast("Opened \(selected.title) with your draft")
        } else {
            showToast("Draft copied — paste with ⌘V")
        }
    }

    private func saveDraft() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [selected.contentType]
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Nookit-\(selected.title)-\(day.string(from: Date())).\(selected.fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try service.save(to: url)
            showToast("Saved to \(url.lastPathComponent)")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if toast == text { toast = nil }
        }
    }
}
