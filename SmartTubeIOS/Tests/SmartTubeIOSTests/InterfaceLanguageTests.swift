import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Interface language", .serialized)
struct InterfaceLanguageTests {

    @Test("System language follows the device's preferred languages")
    func systemFollowsDevice() {
        #expect(AppLanguage.resolved(systemLanguages: ["de-AT", "en-US"]) == .german)
        #expect(AppLanguage.resolved(systemLanguages: ["pt-BR"]) == .portugueseBrazil)
        #expect(AppLanguage.resolved(systemLanguages: ["zh-Hans-CN"]) == .chineseSimplified)
    }

    @Test("Unsupported device languages fall back to English")
    func unsupportedFallsBackToEnglish() {
        #expect(AppLanguage.resolved(systemLanguages: ["nl-NL"]) == .english)
        #expect(AppLanguage.resolved(systemLanguages: ["zh-Hant-TW"]) == .english)
        #expect(AppLanguage.resolved(systemLanguages: []) == .english)
    }

    @Test("The setting defaults to system and round-trips through JSON")
    func roundTrip() throws {
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).language == .system)

        var settings = AppSettings()
        settings.language = .japanese
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.language == .japanese)
    }

    @Test("Choosing a language resolves strings from its own localization")
    func stringFollowsSelection() {
        defer { L10n.language = .system }

        L10n.language = .japanese
        #expect(L10n.string("Settings") == "設定")
        #expect(L10n.locale.identifier == "ja")

        L10n.language = .german
        #expect(L10n.string("Settings") == "Einstellungen")
    }
}
