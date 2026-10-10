import AppKit
import SwiftUI

// MARK: - Palette Focale (§8.3 du PRD), adaptative clair/sombre.

extension NSColor {
    convenience init?(focaleHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func focaleDynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(focaleHex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha) ?? .clear
        }
    }
}

extension Color {
    static let focaleBackground = Color(nsColor: .focaleDynamic(light: 0xF5F5F7, dark: 0x1C1C1E))
    static let focaleGlass = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            NSColor(focaleHex: 0x2C2C2E, alpha: 0.72) ?? .clear
        } else {
            NSColor.white.withAlphaComponent(0.70)
        }
    })
    static let focaleTextPrimary = Color(nsColor: .focaleDynamic(light: 0x1D1D1F, dark: 0xF5F5F7))
    static let focaleTextSecondary = Color(nsColor: .focaleDynamic(light: 0x6E6E73, dark: 0x98989D))
    static let focaleAccentStart = Color(nsColor: NSColor(focaleHex: 0x0A84FF) ?? .systemBlue)
    static let focaleAccentEnd = Color(nsColor: NSColor(focaleHex: 0x5E5CE6) ?? .systemPurple)
    static let focaleSuccess = Color(nsColor: NSColor(focaleHex: 0x30D158) ?? .systemGreen)
    static let focaleDanger = Color(nsColor: NSColor(focaleHex: 0xFF453A) ?? .systemRed)
}

extension LinearGradient {
    /// Dégradé signature bleu → violet, réservé au bouton principal.
    static var focaleAccent: LinearGradient {
        LinearGradient(
            colors: [.focaleAccentStart, .focaleAccentEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Couleur d'annotation (sérialisable pour SwiftData / préréglages).

struct AnnotColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let red = AnnotColor(hex: 0xFF3B30)
    static let orange = AnnotColor(hex: 0xFF9500)
    static let yellow = AnnotColor(hex: 0xFFCC00)
    static let green = AnnotColor(hex: 0x34C759)
    static let blue = AnnotColor(hex: 0x0A84FF)
    static let purple = AnnotColor(hex: 0xAF52DE)
    static let black = AnnotColor(hex: 0x1D1D1F)
    static let white = AnnotColor(hex: 0xFFFFFF)

    static let palette: [AnnotColor] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
}
