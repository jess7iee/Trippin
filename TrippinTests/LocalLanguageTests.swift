import Testing
import Foundation

struct LocalLanguageTests {

    @Test func mapsCountriesToLanguages() {
        #expect(LocalLanguage.forCountry("JP")?.code == "ja")
        #expect(LocalLanguage.forCountry("cn")?.code == "zh-Hans")
        #expect(LocalLanguage.forCountry("TW")?.code == "zh-Hant")
        #expect(LocalLanguage.forCountry("KR")?.name == "Korean")
        #expect(LocalLanguage.forCountry("US") == nil)
        #expect(LocalLanguage.forCountry(nil) == nil)
    }

    @Test func skipsWhenTravelerAlreadyReadsIt() {
        let japanese = LocalLanguage.forCountry("JP")!
        #expect(japanese.matches(Locale(identifier: "ja_JP")))
        #expect(!japanese.matches(Locale(identifier: "en_US")))
    }

    @Test func treatsChineseScriptsAsDifferent() {
        let simplified = LocalLanguage.forCountry("CN")!
        let traditional = LocalLanguage.forCountry("TW")!
        #expect(simplified.matches(Locale(identifier: "zh-Hans_CN")))
        #expect(!simplified.matches(Locale(identifier: "zh-Hant_TW")))
        #expect(traditional.matches(Locale(identifier: "zh_TW")))
    }
}
