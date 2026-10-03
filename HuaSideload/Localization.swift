import Foundation

// In-app language (English / Turkish), chosen from the globe menu on the main screen.
// The first launch follows the phone's language; English is the default for everything else.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case turkish = "tr"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: return "English"
        case .turkish: return "Türkçe"
        }
    }

    static var current: AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: storageKey), let language = AppLanguage(rawValue: saved) {
            return language
        }
        return Locale.preferredLanguages.first?.hasPrefix("tr") == true ? .turkish : .english
    }
}

/// Picks the English or the Turkish text according to the in-app language.
func L(_ english: String, _ turkish: String) -> String {
    AppLanguage.current == .turkish ? turkish : english
}

enum AppInfo {
    // CFBundleDisplayName, so a fork or a private build can carry its own name
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "HuaSideload"
    }
}
