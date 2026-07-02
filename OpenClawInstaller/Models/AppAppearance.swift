import SwiftUI

enum AppSystemSymbol {
    static let skills = "wand.and.sparkles"
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    static func storedValue(_ value: String) -> AppAppearanceMode {
        AppAppearanceMode(rawValue: value) ?? .system
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    func resolvesDark(using systemScheme: ColorScheme) -> Bool {
        switch self {
        case .system:
            return systemScheme == .dark
        case .light:
            return false
        case .dark:
            return true
        }
    }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return "desktopcomputer"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }
}

enum AppAccentPalette: String, CaseIterable, Identifiable {
    case green
    case blue
    case violet
    case graphite

    var id: String { rawValue }

    static func storedValue(_ value: String) -> AppAccentPalette {
        AppAccentPalette(rawValue: value) ?? .green
    }

    var title: String {
        switch self {
        case .green:
            return "Green"
        case .blue:
            return "Blue"
        case .violet:
            return "Violet"
        case .graphite:
            return "Graphite"
        }
    }

    var color: Color {
        switch self {
        case .green:
            return Color(red: 0.20, green: 0.49, blue: 0.35)
        case .blue:
            return Color(red: 0.22, green: 0.43, blue: 0.80)
        case .violet:
            return Color(red: 0.47, green: 0.32, blue: 0.78)
        case .graphite:
            return Color(red: 0.32, green: 0.34, blue: 0.34)
        }
    }
}
