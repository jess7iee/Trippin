import Foundation

/// The main local language for a country, used to show place names the way
/// they appear on signs (e.g. 新宿駅 in Japan, 外滩 in Shanghai).
struct LocalLanguage: Equatable {
    /// BCP-47 code, e.g. "ja" or "zh-Hans".
    var code: String
    /// English name, used in prompts, e.g. "Japanese".
    var name: String

    var locale: Locale { Locale(identifier: code) }

    private static let byCountry: [String: (String, String)] = [
        "JP": ("ja", "Japanese"),
        "CN": ("zh-Hans", "Simplified Chinese"),
        "SG": ("zh-Hans", "Simplified Chinese"),
        "TW": ("zh-Hant", "Traditional Chinese"),
        "HK": ("zh-Hant", "Traditional Chinese"),
        "MO": ("zh-Hant", "Traditional Chinese"),
        "KR": ("ko", "Korean"),
        "TH": ("th", "Thai"),
        "VN": ("vi", "Vietnamese"),
        "KH": ("km", "Khmer"),
        "LA": ("lo", "Lao"),
        "MM": ("my", "Burmese"),
        "NP": ("ne", "Nepali"),
        "LK": ("si", "Sinhala"),
        "MN": ("mn", "Mongolian"),
        "RU": ("ru", "Russian"),
        "UA": ("uk", "Ukrainian"),
        "GE": ("ka", "Georgian"),
        "AM": ("hy", "Armenian"),
        "GR": ("el", "Greek"),
        "CY": ("el", "Greek"),
        "IL": ("he", "Hebrew"),
        "AE": ("ar", "Arabic"), "SA": ("ar", "Arabic"), "EG": ("ar", "Arabic"), "JO": ("ar", "Arabic"),
        "MA": ("ar", "Arabic"), "QA": ("ar", "Arabic"), "OM": ("ar", "Arabic"), "BH": ("ar", "Arabic"),
        "KW": ("ar", "Arabic"), "LB": ("ar", "Arabic"), "TN": ("ar", "Arabic"),
        "IR": ("fa", "Persian"),
        "TR": ("tr", "Turkish"),
        "FR": ("fr", "French"), "BE": ("fr", "French"), "MC": ("fr", "French"),
        "DE": ("de", "German"), "AT": ("de", "German"), "CH": ("de", "German"),
        "ES": ("es", "Spanish"), "MX": ("es", "Spanish"), "AR": ("es", "Spanish"), "CL": ("es", "Spanish"),
        "CO": ("es", "Spanish"), "PE": ("es", "Spanish"), "CR": ("es", "Spanish"), "CU": ("es", "Spanish"),
        "IT": ("it", "Italian"),
        "PT": ("pt-PT", "Portuguese"),
        "BR": ("pt-BR", "Brazilian Portuguese"),
        "NL": ("nl", "Dutch"),
        "PL": ("pl", "Polish"),
        "CZ": ("cs", "Czech"),
        "HU": ("hu", "Hungarian"),
        "SE": ("sv", "Swedish"),
        "NO": ("nb", "Norwegian"),
        "DK": ("da", "Danish"),
        "FI": ("fi", "Finnish"),
        "IS": ("is", "Icelandic"),
        "HR": ("hr", "Croatian"),
        "ID": ("id", "Indonesian"),
        "MY": ("ms", "Malay"),
    ]

    /// The local language for an ISO country code, or nil if unknown.
    static func forCountry(_ isoCode: String?) -> LocalLanguage? {
        guard let isoCode, let entry = byCountry[isoCode.uppercased()] else { return nil }
        return LocalLanguage(code: entry.0, name: entry.1)
    }

    /// True when the traveler's own language already matches, so there is nothing to add.
    func matches(_ locale: Locale) -> Bool {
        // Compare language and script, so Simplified and Traditional Chinese count as different.
        let mine = Locale.Language(identifier: Locale.Language(identifier: code).maximalIdentifier)
        let theirs = Locale.Language(identifier: locale.language.maximalIdentifier)
        return mine.languageCode == theirs.languageCode && mine.script == theirs.script
    }
}
