import SwiftUI
import AppKit
import EventKit

struct TimerModuleView: View {
    @ObservedObject private var timer = TimerService.shared
    @State private var countdownChoice = 10

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(NotchTimerMode.allCases) { mode in
                    Button {
                        switch mode {
                        case .countdown: timer.startCountdown()
                        case .pomodoro: timer.startPomodoro()
                        case .stopwatch: timer.startStopwatch()
                        }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(timer.mode == mode ? Color.black.opacity(0.85) : NotchPalette.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(timer.mode == mode ? Color.white.opacity(0.9) : Color.white.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(timer.display)
                .font(.system(size: 44, weight: .light, design: .monospaced))
                .foregroundStyle(NotchPalette.primary)
                .contentTransition(.numericText())
                .monospacedDigit()

            if timer.mode != .stopwatch {
                VStack(spacing: 4) {
                    ProgressView(value: timer.progress)
                        .tint(timer.mode == .pomodoro ? (timer.pomodoroFocus ? Theme.ember : Theme.mint) : Theme.ember)
                        .frame(width: 230)
                    Text(timer.label.uppercased())
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(NotchPalette.tertiary)
                }
            } else {
                Text(timer.running ? "RUNNING" : "PAUSED")
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(NotchPalette.tertiary)
            }

            HStack(spacing: 8) {
                Button {
                    if timer.mode == .countdown && !timer.running && timer.remaining == 0 {
                        timer.startCountdown(minutes: countdownChoice)
                    } else if timer.mode == .pomodoro && !timer.running && timer.remaining == 0 {
                        timer.startPomodoro()
                    } else if timer.mode == .stopwatch && !timer.running && timer.elapsed == 0 {
                        timer.startStopwatch()
                    } else {
                        timer.pauseOrResume()
                    }
                } label: {
                    Label(timer.running ? "Pause" : "Start", systemImage: timer.running ? "pause.fill" : "play.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Theme.emberSoft, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    if timer.mode == .countdown {
                        timer.startCountdown(minutes: countdownChoice)
                    } else if timer.mode == .pomodoro {
                        timer.startPomodoro()
                    } else {
                        timer.startStopwatch()
                    }
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(NotchPalette.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if timer.mode == .countdown {
                HStack(spacing: 4) {
                    ForEach([5, 10, 25, 45], id: \.self) { minutes in
                        Button("\(minutes)m") {
                            countdownChoice = minutes
                            timer.startCountdown(minutes: minutes)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(timer.countdownMinutes == minutes ? Theme.emberSoft : NotchPalette.tertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.04), in: Capsule())
                    }
                }
            } else if timer.mode == .pomodoro {
                Text("\(timer.focusMinutes) min focus · \(timer.breakMinutes) min break · auto-switches")
                    .font(.system(size: 8.5))
                    .foregroundStyle(NotchPalette.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
    }
}

// MARK: - Calendar

struct CalendarModuleView: View {
    @ObservedObject private var calendar = CalendarService.shared
    @State private var requesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTitle(
                title: "Calendar",
                subtitle: calendar.authorized ? "Next three" : nil,
                trailing: AnyView(
                    Button("Refresh") { calendar.refresh() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(NotchPalette.tertiary)
                )
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if !calendar.authorized {
                VStack(spacing: 8) {
                    NotchEmpty(
                        symbol: calendar.denied ? "calendar.badge.exclamationmark" : "calendar",
                        text: calendar.denied
                            ? "Calendar access is off. Enable it for Nookit in System Settings → Privacy & Security → Calendars."
                            : "Nookit can show your next three meetings without leaving the notch. Access stays on this Mac."
                    )
                    HStack(spacing: 8) {
                        if !calendar.denied {
                            Button {
                                requesting = true
                                Task {
                                    await calendar.requestAccess()
                                    requesting = false
                                }
                            } label: {
                                Text(requesting ? "Asking…" : "Allow calendar access")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.85))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Theme.emberSoft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(requesting)
                        }
                        Button("Open Settings") { Permissions.openPrivacySettings() }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5))
                            .foregroundStyle(NotchPalette.secondary)
                        Button("Open Calendar") { calendar.openInCalendar() }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5))
                            .foregroundStyle(NotchPalette.tertiary)
                    }
                    .padding(.bottom, 8)
                }
            } else if calendar.events.isEmpty {
                NotchEmpty(symbol: "calendar", text: "Nothing on the calendar in the next seven days.")
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(calendar.events, id: \.eventIdentifier) { event in
                            HStack(spacing: 9) {
                                VStack(spacing: 1) {
                                    Text(dayLabel(event.startDate))
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(Theme.emberSoft)
                                    Text(timeLabel(event.startDate))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(NotchPalette.primary)
                                }
                                .frame(width: 48)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title ?? "Untitled event")
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(NotchPalette.primary)
                                        .lineLimit(1)
                                    Text(countdown(event.startDate))
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(NotchPalette.tertiary)
                                }
                                Spacer()
                                if event.url != nil {
                                    Button {
                                        calendar.join(event)
                                    } label: {
                                        Text("Join")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(Color.black.opacity(0.85))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Theme.mint, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
        .onAppear { calendar.refresh() }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func countdown(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval < 0 { return "Happening now" }
        if interval < 3600 { return "In \(max(1, Int(interval / 60))) min" }
        if interval < 86_400 { return "In \(Int(interval / 3600)) hr" }
        return Fmt.shortDate(date)
    }
}

// MARK: - Music

struct MusicModuleView: View {
    @ObservedObject private var music = MusicService.shared

    var body: some View {
        VStack(spacing: 6) {
            ModuleTitle(
                title: "Music",
                subtitle: music.now.available ? music.now.app : nil,
                trailing: AnyView(
                    Button {
                        Task { await music.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(NotchPalette.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh player")
                )
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if !music.now.available {
                VStack(spacing: 9) {
                    NotchEmpty(
                        symbol: "music.note",
                        text: music.now.unauthorized
                            ? "Nookit needs permission to control Music or Spotify. Allow automation in System Settings → Privacy & Security → Automation."
                            : "Open Music or Spotify and press play. Nookit controls whichever is running."
                    )
                    HStack(spacing: 8) {
                        Button("Open Music") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app")) }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(NotchPalette.secondary)
                        Button("Open Spotify") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Spotify.app")) }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(NotchPalette.tertiary)
                    }
                    .padding(.bottom, 8)
                }
            } else {
                VStack(spacing: 7) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.ember.opacity(0.7), Color(hex: 0x6C3BFF).opacity(0.55)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: music.now.playing ? "waveform" : "music.note")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .frame(width: 54, height: 54)
                    .shadow(color: Theme.ember.opacity(0.25), radius: 12, y: 5)

                    Text(music.now.track.isEmpty ? "Nothing playing" : music.now.track)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(NotchPalette.primary)
                        .lineLimit(1)
                        .frame(maxWidth: 360)
                    Text(music.now.artist.isEmpty ? music.now.app : music.now.artist)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchPalette.secondary)
                        .lineLimit(1)

                    HStack(spacing: 18) {
                        NotchIconButton(symbol: "backward.fill", help: "Previous") { music.previous() }
                        Button {
                            music.playPause()
                        } label: {
                            Image(systemName: music.now.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.85))
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.9), in: Circle())
                        }
                        .buttonStyle(.plain)
                        NotchIconButton(symbol: "forward.fill", help: "Next") { music.next() }
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { Task { await music.refresh() } }
    }
}
