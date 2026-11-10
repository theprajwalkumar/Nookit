import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotchPreferencesContent(embedded: false)
                .tabItem { Label("Notch", systemImage: "rectangle.topthird.inset.filled") }
            AISettingsView()
                .tabItem { Label("AI Configuration", systemImage: "sparkles") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 520)
        .background(Theme.background)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var store: ResultStore
    @AppStorage("NookitLaunchAtLogin") private var launchAtLogin = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Nookit at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in
                        updateLoginItem(value)
                    }
                if let loginError {
                    Text(loginError)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.warning)
                }
                Text("Uses the system login item service. No helper daemon is installed.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Section("Results") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Output folder")
                            .font(Theme.body)
                        Text(abbreviated(store.outputRoot))
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Choose…") {
                        if let url = FilePicker.folder(title: "Choose where Nookit saves results", prompt: "Use folder") {
                            store.setRoot(url)
                        }
                    }
                    Button("Reveal") {
                        store.reveal(store.outputRoot)
                    }
                }
                Toggle("Show results in Finder after saving", isOn: Binding(
                    get: { store.revealOnSave },
                    set: { store.setReveal($0) }
                ))
                Text("Every tool writes a new dated folder here. Originals are never modified.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Section("Privacy") {
                LabeledContent("Processing", value: "On-device")
                LabeledContent("Network", value: "Only tools you run")
                Text("No account, no analytics, no uploads. Files are only read when you choose them. AI chats stay on this Mac or your local network.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func abbreviated(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func updateLoginItem(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = "Couldn’t update the login item: \(error.localizedDescription)"
            launchAtLogin = !enabled
        }
    }
}

// MARK: - Notch preferences (page + settings tab share this)

struct NotchSettingsView: View {
    var body: some View {
        ScrollView {
            NotchPreferencesContent(embedded: true)
                .padding(Theme.Space.xl)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }
}

struct NotchPreferencesContent: View {
    var embedded: Bool
    @ObservedObject private var settings = NotchSettings.shared
    @EnvironmentObject private var app: AppState

    private let grid = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if embedded {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The notch")
                            .font(Theme.display(28))
                            .foregroundStyle(Theme.textPrimary)
                        Text("A small panel that lives at the top of the screen. Hover to open, click to pin.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button("Back to tools") { app.openCategory(nil) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $settings.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show the notch overlay")
                            .font(.system(size: 13, weight: .medium))
                        Text("On Macs without a notch, Nookit draws a pill at the top centre instead.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Toggle("Open pinned after launch", isOn: $settings.pinnedOnLaunch)
                    .font(Theme.body)
                Toggle("Show on every Space and over full-screen apps", isOn: $settings.showOnAllSpaces)
                    .font(Theme.body)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Expanded width")
                            .font(Theme.body)
                        Text("\(Int(settings.expandedWidth)) pt")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Slider(value: $settings.expandedWidth, in: 560...760, step: 20)
                        .frame(maxWidth: 260)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hover delay")
                            .font(Theme.body)
                        Text(String(format: "%.2f s before it opens", settings.hoverDelay))
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Slider(value: $settings.hoverDelay, in: 0.05...0.45, step: 0.01)
                        .frame(maxWidth: 260)
                }
                Text("The panel collapses 0.35 s after the pointer leaves. Esc closes it, click pins it open.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Space.m)
            .nookitCard()

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Modules", subtitle: "Only the ones you switch on appear in the tab row.")
                LazyVGrid(columns: grid, alignment: .leading, spacing: 10) {
                    ForEach(NotchModule.allCases) { module in
                        Button {
                            settings.toggle(module)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: module.symbol)
                                    .font(.system(size: 12))
                                    .foregroundStyle(module.tint)
                                    .frame(width: 24, height: 24)
                                    .background(module.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                Text(module.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: settings.isEnabled(module) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(settings.isEnabled(module) ? Theme.mint : Theme.textTertiary)
                            }
                            .padding(8)
                            .background(Theme.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                    .strokeBorder(settings.isEnabled(module) ? Theme.mint.opacity(0.25) : Theme.line, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Theme.Space.m)
            .nookitCard()

            if embedded {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.textTertiary)
                    Text("Clipboard history skips password managers. Calendar access is requested the first time you open the tab.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

// MARK: - AI Configuration

struct AISettingsView: View {
    @ObservedObject private var chat = AIChatService.shared

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Use", selection: $chat.provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: chat.isSupported ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(chat.isSupported ? Theme.mint : Theme.textTertiary)
                    Text(chat.isSupported ? "Ready · \(chat.subtitle ?? "model")" : chat.unavailableReason)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Automatic prefers Apple Intelligence, then Nookit AI (NVIDIA). Configure your API key below to use Nemotron and other NVIDIA models.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Section("Apple Intelligence") {
                HStack(spacing: 6) {
                    Image(systemName: chat.appleSupported ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(chat.appleSupported ? Theme.mint : Theme.textTertiary)
                    Text(chat.appleSupported ? "Available on this Mac (macOS 26+)" : "Not available — requires macOS 26 with Apple Intelligence")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Uses Apple's on-device foundation models. Private, fast, and requires no setup.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Section("Nookit AI (NVIDIA)") {
                TextField("API URL", text: $chat.nookitAIURL, prompt: Text("https://integrate.api.nvidia.com/v1"))
                HStack {
                    TextField("Model", text: $chat.nookitAIModel, prompt: Text("nvidia/nemotron-3.5-super-vl-120b-a12b"))
                    Button("Refresh") { Task { await chat.refresh() } }
                        .disabled(chat.checking)
                }
                if !chat.nookitAIModels.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Current: \(AIChatService.friendlyModelName(chat.nookitAIModel))")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            if chat.nookitAIVisionModels.contains(chat.nookitAIModel) {
                                Text("👁 Vision")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.mint)
                            }
                        }
                        Text("Edit the Model field above to change. Available vision models: \(chat.nookitAIVisionModels.map { AIChatService.friendlyModelName($0) }.joined(separator: ", "))")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                SecureField("NVIDIA API key", text: $chat.nookitAIKey)
                Text("Enter your NVIDIA API key from build.nvidia.com. For image analysis, select a vision model (👁). Your key stays in your Mac's preferences.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Section("Privacy") {
                LabeledContent("Where it runs", value: "Apple Intelligence: on-device · Nookit AI: NVIDIA cloud API")
                LabeledContent("Cloud calls", value: "Only with Nookit AI (NVIDIA API)")
                Text("API keys are stored in this user's preferences and are only sent to the server address you enter. Apple Intelligence runs entirely on-device.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task { await chat.refresh() }
    }
}

// MARK: - About

struct AboutView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.ember)
                Text("N")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: 0x160A04))
            }
            .frame(width: 78, height: 78)
            .shadow(color: Theme.ember.opacity(0.3), radius: 20, y: 8)

            Text("Nookit")
                .font(Theme.display(26))
                .foregroundStyle(Theme.textPrimary)
            Text("94 Mac tools. One notch away.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 6) {
                Badge(text: "Version 0.1.0")
                Badge(text: "macOS 14+", tint: Theme.mint)
                Badge(text: "On-device", tint: Theme.emberSoft)
            }

            Text("A private toolkit for the Mac. Video, audio, images, PDFs, files, text and developer utilities — plus a notch that earns its keep.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            HStack(spacing: 10) {
                Button("Visit nookit.app") {
                    if let url = URL(string: app.catalog.product.site) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(SecondaryButtonStyle())
                Button("Support") {
                    if let url = URL(string: "mailto:\(app.catalog.product.support)") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(.top, 4)

            Spacer()

            Text("© 2026 Nookit. Built for people who would rather not upload their files.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
