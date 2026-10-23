import SwiftUI
import UIKit

// [01] Keep one preference for every tab, detail page and sheet.
enum AppAppearance: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    static let storageKey = "dfe.appearance"
    static let defaultPreference: AppAppearance = .light
    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    static let preferenceStore: UserDefaults = {
        #if DEBUG
        // [02] Interface tests must not change the owner's saved appearance.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           let isolated = UserDefaults(suiteName: "dfe.appearance.ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("-ui-reset-appearance") {
                isolated.removeObject(forKey: storageKey)
                removeRetiredGardenPreferences(in: isolated)
            }
            return isolated
        }
        #endif
        removeRetiredGardenPreferences(in: .standard)
        return .standard
    }()

    // [03] Full local deletion clears display choices too.
    static func resetLocalPreferences(in defaults: UserDefaults = preferenceStore) {
        defaults.removeObject(forKey: storageKey)
        removeRetiredGardenPreferences(in: defaults)
    }

    // [04] These experimental choices were removed; they must not affect the greeting.
    static func removeRetiredGardenPreferences(in defaults: UserDefaults) {
        defaults.removeObject(forKey: "dfe.garden.name")
        defaults.removeObject(forKey: "dfe.garden.focus")
    }

    // [05] A test can ask for a fixed appearance without changing the saved choice.
    // For normal use, every screen follows the same preference.
    static func resolvedColorScheme(
        for preference: AppAppearance,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ColorScheme? {
        #if DEBUG
        if arguments.contains("-ui-testing") {
            if let rawValue = environment["UI_TEST_COLOR_SCHEME"],
               let requested = AppAppearance(rawValue: rawValue.lowercased()) {
                return requested.colorScheme
            }
            if arguments.contains("-ui-dark-mode") { return .dark }
            if arguments.contains("-ui-light-mode") { return .light }
        }
        #endif
        return preference.colorScheme
    }
}

// [06] These colors follow the app's chosen appearance, including an open sheet.
enum AppSurface {
    static let canvasUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemBackground : .white
    }
    static let canvas = Color(uiColor: canvasUIColor)

    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .secondarySystemGroupedBackground
            : UIColor(white: 0.96, alpha: 1)
    })

    static let inset = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .tertiarySystemGroupedBackground
            : UIColor(white: 0.93, alpha: 1)
    })
}
