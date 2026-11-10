import SwiftUI
import AppKit

enum NotchPalette {
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.56)
    static let tertiary = Color.white.opacity(0.34)
    static let surface = Color.white.opacity(0.06)
    static let line = Color.white.opacity(0.09)
}

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject private var settings = NotchSettings.shared
    @ObservedObject private var clipboard = ClipboardService.shared
    @ObservedObject private var tasks = TaskStore.shared
    @ObservedObject private var timer = TimerService.shared
    @ObservedObject private var calendar = CalendarService.shared
    @ObservedObject private var music = MusicService.shared
    @ObservedObject private var water = HydrationService.shared

    var body: some View {
        ZStack {
            shape
                .fill(Color.black)
                .overlay(shape.stroke(NotchPalette.line, lineWidth: 1))
                .shadow(color: .black.opacity(model.expanded ? 0.55 : 0.25), radius: model.expanded ? 24 : 8, y: 6)

            if model.expanded {
                expanded
                    .transition(.opacity)
            } else {
                collapsed
                    .transition(.opacity)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .onHover { inside in
            model.hover(inside)
        }
        .animation(.easeOut(duration: 0.18), value: model.expanded)
        .environment(\.colorScheme, .dark)
    }

    private var shape: UnevenRoundedRectangle {
        let top: CGFloat = model.hasNotch ? (model.expanded ? 12 : 2) : 14
        return UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: model.expanded ? 22 : 17,
            bottomTrailingRadius: model.expanded ? 22 : 17,
            topTrailingRadius: top,
            style: .continuous
        )
    }

    // MARK: - Collapsed

    private var collapsed: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.ember)
                Text("N")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: 0x160A04))
            }
            .frame(width: 17, height: 17)

            Text(statusText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NotchPalette.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 2)

            HStack(spacing: 3) {
                ForEach(model.visibleModules.prefix(4)) { module in
                    Circle()
                        .fill(module.tint.opacity(0.9))
                        .frame(width: 3.5, height: 3.5)
                }
            }
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.togglePin() }
        .help("Click to pin Nookit · hover to open")
    }

    private var statusText: String {
        if let timerText = timer.collapsedText { return timerText }
        if let event = calendar.nextEventText { return event }
        if let summary = music.now.summary { return summary }
        if tasks.openCount > 0 { return "\(tasks.openCount) task\(tasks.openCount == 1 ? "" : "s") left" }
        if water.glasses > 0 { return "\(water.glasses)/\(water.goal) glasses" }
        return "94 tools · on-device"
    }

    // MARK: - Expanded

    private var expanded: some View {
        VStack(spacing: 0) {
            tabRow
            Rectangle().fill(NotchPalette.line).frame(height: 1)
            moduleContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 4)
    }

    private var tabRow: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(model.visibleModules) { module in
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) { model.activeModule = module }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: module.symbol)
                                    .font(.system(size: 10.5, weight: .medium))
                                if model.activeModule == module {
                                    Text(module.shortTitle)
                                        .font(.system(size: 10, weight: .semibold))
                                        .lineLimit(1)
                                }
                            }
                            .foregroundStyle(model.activeModule == module ? Color.black.opacity(0.85) : NotchPalette.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(
                                model.activeModule == module ? module.tint : Color.clear,
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("\(module.title) · press \(module.keyLabel)")
                    }
                }
                .padding(.horizontal, 2)
            }

            Spacer(minLength: 2)

            Button {
                model.pinned.toggle()
            } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(model.pinned ? Theme.emberSoft : NotchPalette.tertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.pinned ? "Unpin" : "Pin open")

            Button {
                model.collapse()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(NotchPalette.tertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 5)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch model.activeModule {
        case .clipboard:
            ClipboardModuleView()
        case .notes:
            NotesModuleView()
        case .tasks:
            TasksModuleView()
        case .timer:
            TimerModuleView()
        case .calendar:
            CalendarModuleView()
        case .music:
            MusicModuleView()
        case .hydration:
            HydrationModuleView()
        case .breathe:
            BreatheModuleView()
        case .habits:
            HabitsModuleView()
        case .ai:
            AIModuleView()
        }
    }
}

// MARK: - Shared module chrome

struct ModuleTitle: View {
    let title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(NotchPalette.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(NotchPalette.tertiary)
            }
            Spacer(minLength: 4)
            if let trailing { trailing }
        }
    }
}

struct NotchIconButton: View {
    let symbol: String
    var tint: Color = NotchPalette.secondary
    var help: String = ""
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.055), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct NotchEmpty: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(NotchPalette.tertiary)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(NotchPalette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}
