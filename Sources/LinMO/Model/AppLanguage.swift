import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case thai = "th"
    case english = "en"

    static let storageKey = "appLanguage"
    static let guideStorageKey = "guideLanguage"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thai: "ไทย"
        case .english: "English"
        }
    }

    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? ""
        return preferred.hasPrefix("th") ? .thai : .english
    }

    static var current: AppLanguage {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .thai
    }
}

func tr(_ thai: String, _ english: String) -> String {
    AppLanguage.current == .english ? english : thai
}
