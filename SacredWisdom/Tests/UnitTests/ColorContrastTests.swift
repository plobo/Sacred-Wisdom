import SwiftUI
import Testing
import UIKit
@testable import SacredWisdom

/// Exact WCAG contrast for every text color token on every background, in both appearances. (The UI
/// accessibility audit samples pixels and misjudges grouped elements; this is the authoritative check.)
@MainActor
@Suite struct ColorContrastTests {
    static let textTokens: [(String, Color)] = [
        ("textPrimary", SWColors.textPrimary), ("textSecondary", SWColors.textSecondary),
        ("primary", SWColors.primary), ("secondary", SWColors.secondary),
    ] + ["saffron", "sapphire", "emerald", "azure", "amber", "indigo"].map { ($0, SWColors.tint(for: $0)) }
    static let backgrounds: [(String, Color)] = [
        ("backgroundTop", SWColors.backgroundTop), ("backgroundBottom", SWColors.backgroundBottom), ("surface", SWColors.surface),
    ]

    private static func luminance(_ color: Color, _ style: UIUserInterfaceStyle) -> Double {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    static func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        let (la, lb) = (luminance(a, style), luminance(b, style))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func everyTextTokenMeetsAAOnEveryBackground(style: UIUserInterfaceStyle) {
        for (name, token) in Self.textTokens {
            for (backgroundName, background) in Self.backgrounds {
                let ratio = Self.contrast(token, background, style)
                #expect(ratio >= 4.5, "\(name) on \(backgroundName) (\(style == .dark ? "dark" : "light")): \(ratio)")
            }
        }
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func textOnPrimaryFillsMeetsAA(style: UIUserInterfaceStyle) {
        let ratio = Self.contrast(SWColors.onPrimary, SWColors.primary, style)
        #expect(ratio >= 4.5, "onPrimary on primary: \(ratio)")
    }

    /// Equal visual prominence: the six tradition tints stay within a narrow contrast band.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func traditionTintsHaveEqualWeight(style: UIUserInterfaceStyle) {
        let ratios = ["saffron", "sapphire", "emerald", "azure", "amber", "indigo"]
            .map { Self.contrast(SWColors.tint(for: $0), SWColors.surface, style) }
        #expect((ratios.max() ?? 0) - (ratios.min() ?? 0) < 1.6, "\(ratios)")
    }
}
