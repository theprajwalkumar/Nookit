import SwiftUI

enum NotchModule: String, CaseIterable, Identifiable {
    case clipboard
    case notes
    case tasks
    case timer
    case calendar
    case music
    case hydration
    case breathe
    case habits
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .notes: return "Notes"
        case .tasks: return "Tasks"
        case .timer: return "Timer"
        case .calendar: return "Calendar"
        case .music: return "Music"
        case .hydration: return "Water"
        case .breathe: return "Breathe"
        case .habits: return "Habits"
        case .ai: return "Nookit AI"
        }
    }

    var shortTitle: String {
        switch self {
        case .clipboard: return "Clip"
        case .hydration: return "Water"
        case .ai: return "AI"
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .notes: return "note.text"
        case .tasks: return "checklist"
        case .timer: return "timer"
        case .calendar: return "calendar"
        case .music: return "music.note"
        case .hydration: return "drop.fill"
        case .breathe: return "wind"
        case .habits: return "flame.fill"
        case .ai: return "sparkles"
        }
    }

    /// Catalog id for the marketing site’s notch module list.
    var catalogID: String {
        switch self {
        case .timer: return "timers"
        case .ai: return "ai-chat"
        default: return rawValue
        }
    }

    var keyLabel: String {
        guard let index = NotchModule.allCases.firstIndex(of: self) else { return "" }
        if index == 9 { return "0" }
        return "\(index + 1)"
    }

    var tint: Color {
        switch self {
        case .clipboard: return Theme.emberSoft
        case .notes: return Color(hex: 0xF2D17B)
        case .tasks: return Theme.mint
        case .timer: return Color(hex: 0x8EC5FF)
        case .calendar: return Color(hex: 0xFF8E8E)
        case .music: return Color(hex: 0xC69CFF)
        case .hydration: return Color(hex: 0x6FD3FF)
        case .breathe: return Color(hex: 0x8BE9C0)
        case .habits: return Theme.ember
        case .ai: return Color(hex: 0xFFD166)
        }
    }
}
