import SwiftUI
import AppKit

// MARK: - Brand tokens

enum Theme {
    // Fixed brand colors
    static let ink = Color(hex: 0x0A0B0E)
    static let inkRaised = Color(hex: 0x12141A)
    static let paper = Color(hex: 0xF6F3EC)
    static let paperRaised = Color(hex: 0xEDE8DD)
    static let ember = Color(hex: 0xFF5A1F)
    static let emberSoft = Color(hex: 0xFFB27A)
    static let mint = Color(hex: 0x8BE9C0)
    static let danger = Color(hex: 0xFF5A5A)
    static let warning = Color(hex: 0xFFC857)

    // Adaptive surfaces
    static let background = dynamic(light: 0xF6F3EC, dark: 0x0A0B0E)
    static let raised = dynamic(light: 0xEDE8DD, dark: 0x12141A)
    static let card = dynamic(light: 0xFFFDF8, dark: 0x171A21)
    static let cardHover = dynamic(light: 0xFFFFFF, dark: 0x1C2028)
    static let sidebar = dynamic(light: 0xEDE8DD, dark: 0x0C0D11)

    static let textPrimary = dynamic(light: 0x14161B, dark: 0xF6F3EC)
    static let textSecondary = dynamic(light: 0x5A5D66, dark: 0x9CA0AA)
    static let textTertiary = dynamic(light: 0x8A8D96, dark: 0x6B6F79)

    static let line = Color.primary.opacity(0.08)
    static let lineStrong = Color.primary.opacity(0.14)

    static let emberTint = ember.opacity(0.14)
    static let mintTint = mint.opacity(0.14)

    // Radii
    static let radiusSmall: CGFloat = 10
    static let radius: CGFloat = 16
    static let radiusLarge: CGFloat = 22

    // Spacing scale
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // Type
    static func display(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static let title = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 13.5)
    static let callout = Font.system(size: 12.5)
    static let caption = Font.system(size: 11.5)
    static let mono = Font.system(size: 12, design: .monospaced)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

// MARK: - Hex helpers

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Reusable styling

struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.radius
    var raised: Bool = false
    var glass: Bool = false

    func body(content: Content) -> some View {
        let base = raised ? Theme.raised : Theme.card
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(glass ? base.opacity(0.85) : base)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    .blendMode(.overlay)
            )
    }
}

extension View {
    func nookitCard(radius: CGFloat = Theme.radius, raised: Bool = false, glass: Bool = false) -> some View {
        modifier(CardBackground(radius: radius, raised: raised, glass: glass))
    }

    func fieldStyle() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }

    func hoverLift(_ hovering: Bool) -> some View {
        scaleEffect(hovering ? 1.015 : 1)
            .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: hovering ? 14 : 0, y: hovering ? 6 : 0)
            .animation(.easeOut(duration: 0.16), value: hovering)
    }

    func glassLift(_ hovering: Bool) -> some View {
        scaleEffect(hovering ? 1.02 : 1)
            .shadow(color: Theme.ember.opacity(hovering ? 0.15 : 0), radius: hovering ? 12 : 0, y: hovering ? 6 : 0)
            .animation(.easeOut(duration: 0.16), value: hovering)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.ember

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(hex: 0x160A04))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(tint.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.line.opacity(configuration.isPressed ? 1 : 0), in: Capsule())
            .contentShape(Capsule())
    }
}
