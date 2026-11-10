import SwiftUI
import AppKit

// MARK: - Hydration

struct HydrationModuleView: View {
    @ObservedObject private var water = HydrationService.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

    var body: some View {
        VStack(spacing: 10) {
            ModuleTitle(
                title: "Water",
                subtitle: "Resets at midnight",
                trailing: AnyView(
                    HStack(spacing: 8) {
                        Button { water.remove() } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(NotchPalette.tertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(water.glasses == 0)
                        Button { water.add() } label: {
                            Label("Glass", systemImage: "plus")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.85))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Color(hex: 0x6FD3FF), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                )
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(water.glasses)")
                    .font(.system(size: 38, weight: .light, design: .rounded))
                    .foregroundStyle(NotchPalette.primary)
                    .contentTransition(.numericText())
                Text("/ \(water.goal) glasses")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchPalette.secondary)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<max(water.goal, 1), id: \.self) { index in
                    Image(systemName: index < water.glasses ? "drop.fill" : "drop")
                        .font(.system(size: 13))
                        .foregroundStyle(index < water.glasses ? Color(hex: 0x6FD3FF) : NotchPalette.tertiary.opacity(0.6))
                        .frame(height: 18)
                }
            }
            .frame(maxWidth: 310)

            ProgressView(value: water.progress)
                .tint(Color(hex: 0x6FD3FF))
                .frame(width: 230)

            HStack(spacing: 6) {
                Text("Daily goal")
                    .font(.system(size: 9))
                    .foregroundStyle(NotchPalette.tertiary)
                Button { water.setGoal(water.goal - 1) } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(NotchPalette.tertiary)
                }
                .buttonStyle(.plain)
                Text("\(water.goal)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchPalette.secondary)
                    .monospacedDigit()
                Button { water.setGoal(water.goal + 1) } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(NotchPalette.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Breathe

struct BreatheModuleView: View {
    @State private var running = false
    @State private var phase = "Ready"
    @State private var scale: CGFloat = 0.62
    @State private var remaining = 120
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            ModuleTitle(
                title: "Breathe",
                subtitle: "4 in · 7 hold · 8 out",
                trailing: AnyView(
                    Button(running ? "Stop" : "Start") {
                        running ? stop() : start()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(running ? NotchPalette.secondary : Color.black.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(running ? Color.white.opacity(0.07) : Theme.mint, in: Capsule())
                )
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    .frame(width: 148, height: 148)
                Circle()
                    .fill(Theme.mint.opacity(0.08))
                    .frame(width: 148, height: 148)
                    .scaleEffect(scale)
                Circle()
                    .strokeBorder(Theme.mint.opacity(0.5), lineWidth: 1)
                    .frame(width: 148, height: 148)
                    .scaleEffect(scale)
                VStack(spacing: 2) {
                    Text(phase)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NotchPalette.primary)
                    Text(running ? Fmt.clock(remaining) : "2 minutes")
                        .font(.system(size: 9))
                        .foregroundStyle(NotchPalette.tertiary)
                        .monospacedDigit()
                }
            }
            .frame(maxHeight: .infinity)

            Text(running ? "Let the shoulders drop. The exhale is the long one." : "A two-minute reset. Nothing is recorded.")
                .font(.system(size: 9))
                .foregroundStyle(NotchPalette.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onDisappear { stop() }
    }

    private func start() {
        stop()
        running = true
        remaining = 120
        scale = 0.62
        task = Task { await runSession() }
    }

    private func stop() {
        task?.cancel()
        task = nil
        running = false
        phase = "Ready"
        withAnimation(.easeInOut(duration: 0.5)) { scale = 0.62 }
    }

    private func runSession() async {
        let deadline = Date().addingTimeInterval(120)
        do {
            while !Task.isCancelled && Date() < deadline {
                phase = "Breathe in"
                withAnimation(.easeInOut(duration: 4)) { scale = 1.0 }
                try await Task.sleep(for: .seconds(4))
                try Task.checkCancellation()

                phase = "Hold"
                try await Task.sleep(for: .seconds(7))
                try Task.checkCancellation()

                phase = "Breathe out"
                withAnimation(.easeInOut(duration: 8)) { scale = 0.62 }
                try await Task.sleep(for: .seconds(8))
                try Task.checkCancellation()

                remaining = max(0, Int(deadline.timeIntervalSinceNow))
            }
            running = false
            phase = "Done"
            NSSound(named: "Glass")?.play()
        } catch {
            // Cancelled by the user.
        }
    }
}

// MARK: - Habits

struct HabitsModuleView: View {
    @ObservedObject private var store = HabitsStore.shared
    @State private var newHabit = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTitle(
                title: "Habits",
                subtitle: store.bestStreak > 0 ? "Best streak \(store.bestStreak)d" : "Tap to mark today",
                trailing: AnyView(
                    Text(Fmt.stamp.string(from: Date()))
                        .font(.system(size: 8.5))
                        .foregroundStyle(NotchPalette.tertiary)
                )
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(spacing: 6) {
                TextField("Add a habit", text: $newHabit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onSubmit { add() }
                Button { add() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.emberSoft)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(newHabit.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)

            if store.habits.isEmpty {
                NotchEmpty(symbol: "flame", text: "Small things, marked daily. A streak survives as long as yesterday or today is checked.")
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(store.habits) { habit in
                            Button {
                                store.toggleToday(habit.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: habit.doneToday ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(habit.doneToday ? Theme.emberSoft : NotchPalette.tertiary)
                                    Text(habit.title)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(habit.doneToday ? NotchPalette.primary : NotchPalette.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    if habit.streak > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "flame.fill")
                                                .font(.system(size: 8))
                                            Text("\(habit.streak)")
                                                .font(.system(size: 9, weight: .semibold))
                                                .monospacedDigit()
                                        }
                                        .foregroundStyle(Theme.ember)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", role: .destructive) { store.delete(habit.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func add() {
        store.add(newHabit)
        newHabit = ""
    }
}

// MARK: - AI

struct AIModuleView: View {
    @ObservedObject private var chat = AIChatService.shared

    var body: some View {
        VStack(spacing: 0) {
            ModuleTitle(
                title: "Nookit AI",
                subtitle: chat.subtitle,
                trailing: AnyView(
                    HStack(spacing: 8) {
                        if chat.nookitAIModels.count > 1 {
                            Menu {
                                ForEach(chat.nookitAIModels, id: \.self) { model in
                                    Button {
                                        chat.provider = .nookitAI
                                        chat.nookitAIModel = model
                                    } label: {
                                        Text(model)
                                    }
                                }
                            } label: {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        Button("Clear") { chat.clear() }
                            .buttonStyle(.plain)
                            .font(.system(size: 9))
                            .foregroundStyle(NotchPalette.tertiary)
                    }
                )
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if !chat.isSupported {
                VStack(spacing: 8) {
                    if chat.checking {
                        ProgressView().controlSize(.mini)
                    }
                    NotchEmpty(
                        symbol: "sparkles",
                        text: chat.unavailableReason
                    )
                    Text("Open Settings → AI Configuration to add your NVIDIA API key and use Nookit AI in the notch.")
                        .font(.system(size: 9))
                        .foregroundStyle(NotchPalette.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 10)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if chat.messages.isEmpty {
                                Text("Ask a short question. Answers stay on this Mac or your local network.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(NotchPalette.tertiary)
                                    .padding(.vertical, 12)
                            }
                            ForEach(chat.messages) { message in
                                HStack {
                                    if message.role == .user { Spacer(minLength: 30) }
                                    Text(message.text)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(message.role == .user ? Color.black.opacity(0.85) : NotchPalette.primary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .background(
                                            message.role == .user ? Theme.emberSoft : Color.white.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        )
                                        .textSelection(.enabled)
                                    if message.role != .user { Spacer(minLength: 30) }
                                }
                                .id(message.id)
                            }
                            if let error = chat.error {
                                Text(error)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Theme.warning)
                                    .padding(8)
                                    .background(Theme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: chat.messages.count) { _, _ in
                        if let last = chat.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: chat.messages.last?.text) { _, _ in
                        if let last = chat.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("Ask Nookit…", text: $chat.input)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10.5))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .onSubmit { send() }
                        Button { send() } label: {
                            if chat.busy {
                                ProgressView().controlSize(.mini).frame(width: 26, height: 26)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.85))
                                    .frame(width: 26, height: 26)
                                    .background(Theme.emberSoft, in: Circle())
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(chat.busy || chat.input.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .task { await chat.refresh() }
    }

    private func send() {
        let text = chat.input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { await chat.send() }
    }
}
