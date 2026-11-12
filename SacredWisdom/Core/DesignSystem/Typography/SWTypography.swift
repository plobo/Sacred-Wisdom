import SwiftUI

/// Type scale. Headings use a serif design for elegance; body text stays system for readability.
/// All styles are built on text styles, so they scale with Dynamic Type.
enum SWTypography {
    static let largeTitle = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let title = Font.system(.title2, design: .serif).weight(.semibold)
    static let headline = Font.system(.headline, design: .serif)
    static let scripture = Font.system(.body, design: .serif)
    static let body = Font.body
    static let caption = Font.caption
    static let reference = Font.footnote.weight(.semibold)
}
