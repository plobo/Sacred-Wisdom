import Observation
import SwiftUI

/// Display preferences that apply app-wide, persisted in UserDefaults.
@Observable
@MainActor
final class AppPreferences {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    static let appearanceKey = "appearance"
    static let readerTextScaleKey = "readerTextScale"

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    /// Default scripture text size in the reader (it still follows Dynamic Type; this multiplies it).
    var readerTextScale: Double {
        didSet { defaults.set(readerTextScale, forKey: Self.readerTextScaleKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
        let stored = defaults.double(forKey: Self.readerTextScaleKey)
        readerTextScale = stored == 0 ? 1 : min(max(stored, ReaderViewModel.fontScaleRange.lowerBound),
                                                ReaderViewModel.fontScaleRange.upperBound)
    }
}
