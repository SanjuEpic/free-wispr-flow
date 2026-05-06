import SwiftUI

// MARK: - Hex initializer

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Token resolvers

extension Color {
    static func windowBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x26231F) : Color(hex: 0xF4F2EE)
    }

    static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF5F1EA, opacity: 0.04) : Color.white.opacity(0.7)
    }

    static func cardBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF5F1EA, opacity: 0.08) : Color.black.opacity(0.08)
    }

    static func rowSeparator(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF5F1EA, opacity: 0.06) : Color.black.opacity(0.06)
    }

    static func textPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF5F1EA, opacity: 0.92) : Color(hex: 0x1F1D1A)
    }

    static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF5F1EA, opacity: 0.65) : Color(hex: 0x1F1D1A, opacity: 0.55)
    }

    static func textTertiary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF5F1EA, opacity: 0.45) : Color(hex: 0x1F1D1A, opacity: 0.40)
    }

    static func pickerBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF5F1EA, opacity: 0.08) : .white
    }

    static func pickerBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF5F1EA, opacity: 0.15) : Color.black.opacity(0.15)
    }

    static func keycapFace(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF5F1EA, opacity: 0.08) : .white
    }

    static func keycapBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF5F1EA, opacity: 0.18) : Color.black.opacity(0.18)
    }

    static func accentLink(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x6FA8E8) : Color(hex: 0x0A66D2)
    }
}
