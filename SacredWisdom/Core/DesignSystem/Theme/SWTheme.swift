import SwiftUI

/// Spacing, radius and elevation tokens.
enum SWSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum SWRadius {
    static let card: CGFloat = 18
    static let field: CGFloat = 14
}

extension View {
    /// Applies the app's warm gradient background behind the content.
    func swScreenBackground() -> some View {
        background(SWColors.backgroundGradient.ignoresSafeArea())
    }
}
