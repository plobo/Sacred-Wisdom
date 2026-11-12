import SwiftUI
import UIKit

/// Semantic color tokens. Every token adapts to Light and Dark Mode.
enum SWColors {
    static let primary = dynamic(light: 0x552F8D, dark: 0xBAA0EC)        // deep purple
    // Light values meet WCAG AA (4.5:1) on the darkest background; tints share one contrast (≈5.6:1) so no
    // tradition stands out.
    static let secondary = dynamic(light: 0x856119, dark: 0xE2BE6A)      // gold
    static let backgroundTop = dynamic(light: 0xFBF7EE, dark: 0x14111C)  // warm ivory
    static let backgroundBottom = dynamic(light: 0xF3EADB, dark: 0x1D1828)
    static let surface = dynamic(light: 0xFFFDF8, dark: 0x262033)
    static let textPrimary = dynamic(light: 0x221C2E, dark: 0xF4EFE6)
    static let textSecondary = dynamic(light: 0x6B6278, dark: 0xB7AEC4)
    static let separator = dynamic(light: 0xE6DCCB, dark: 0x3A3249)
    /// Text and icons on a `primary` fill (filled buttons, selected chips, question bubbles).
    static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x1D1828)

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Per-tradition tint. All tints share similar luminance so no tradition is visually dominant.
    static func tint(for key: String) -> Color {
        switch key {
        case "saffron": dynamic(light: 0x8F4814, dark: 0xF0A060)
        case "sapphire": dynamic(light: 0x2F5AA7, dark: 0x95B3EB)
        case "emerald": dynamic(light: 0x19684C, dark: 0x5AC59A)
        case "azure": dynamic(light: 0x1E6186, dark: 0x74BAE1)
        case "amber": dynamic(light: 0x7A5413, dark: 0xE3A73B)
        case "indigo": dynamic(light: 0x584CB8, dark: 0xB3A9F2)
        default: primary
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
