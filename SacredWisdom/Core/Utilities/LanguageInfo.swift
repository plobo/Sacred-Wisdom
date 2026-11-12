import Foundation

/// Language helpers for scripture display.
enum LanguageInfo {
    private static let rightToLeft: Set<String> = ["ar", "he", "fa", "ur", "yi"]

    static func isRightToLeft(_ code: String) -> Bool {
        rightToLeft.contains(code)
    }

    static func displayName(_ code: String, locale: Locale = .current) -> String {
        locale.localizedString(forLanguageCode: code) ?? code
    }
}

import SwiftUI

extension View {
    /// Lays scripture out in its own language's direction, whatever the interface direction: Arabic and Hebrew
    /// right-to-left, English and Sanskrit left-to-right, even inside a right-to-left interface.
    func scriptureDirection(_ languageCode: String) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, LanguageInfo.isRightToLeft(languageCode) ? .rightToLeft : .leftToRight)
    }
}
