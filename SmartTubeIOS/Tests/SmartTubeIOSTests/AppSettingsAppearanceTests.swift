import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("AppSettings accent color and grid columns")
struct AppSettingsAppearanceTests {

    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    @Test("Missing keys fall back to defaults")
    func missingKeysUseDefaults() throws {
        let settings = try decode("{}")
        #expect(settings.accentColor == .system)
        #expect(settings.gridColumnsPortrait == 2)
        #expect(settings.gridColumnsLandscape == 3)
    }

    @Test("Accent color round-trips", arguments: AppSettings.AccentColorChoice.allCases)
    func accentColorRoundTrip(choice: AppSettings.AccentColorChoice) throws {
        var settings = AppSettings()
        settings.accentColor = choice
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.accentColor == choice)
    }

    @Test("Unknown accent color falls back to system")
    func unknownAccentColor() throws {
        #expect(try decode(#"{"accentColor": "chartreuse"}"#).accentColor == .system)
    }

    @Test("Column counts are clamped to the selectable range")
    func columnsClamped() throws {
        let settings = try decode(#"{"gridColumnsPortrait": 0, "gridColumnsLandscape": 9}"#)
        #expect(settings.gridColumnsPortrait == 1)
        #expect(settings.gridColumnsLandscape == 3)
    }

    @Test("Valid column counts are preserved")
    func columnsPreserved() throws {
        let settings = try decode(#"{"gridColumnsPortrait": 1, "gridColumnsLandscape": 2}"#)
        #expect(settings.gridColumnsPortrait == 1)
        #expect(settings.gridColumnsLandscape == 2)
    }

    @Test("High-res thumbnails default off and decode when present")
    func highResThumbnails() throws {
        #expect(try decode("{}").highResThumbnails == false)
        #expect(try decode(#"{"highResThumbnails": true}"#).highResThumbnails == true)
    }

    @Test("High-res fallback chain starts at hq720 and ends at mqdefault")
    func highResFallbackChain() {
        let names = Video(id: "abc", title: "t", channelTitle: "c").highResThumbnailFallbackURLs.map(
            \.lastPathComponent)
        #expect(names == ["hq720.jpg", "sddefault.jpg", "hqdefault.jpg", "mqdefault.jpg"])
    }
}
