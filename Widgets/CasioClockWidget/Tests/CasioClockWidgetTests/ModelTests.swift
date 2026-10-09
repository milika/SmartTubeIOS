import CoreText
import Foundation
import Testing

@testable import CasioClockWidget

@Suite("Casio models")
struct ModelTests {
    @Test("kinds are unique; the F-91W keeps the original kind")
    func kinds() {
        let kinds = CasioModels.all.map { $0.kind }
        #expect(Set(kinds).count == kinds.count)
        #expect(CasioF91W.kind == "CasioClockWidget")
    }

    @Test("every model's fonts are bundled and register")
    func fonts() {
        BundledFonts.register()
        for model in CasioModels.all {
            for name in model.fonts {
                let font = CTFontCreateWithName(name as CFString, 12, nil)
                #expect(CTFontCopyPostScriptName(font) as String == name, "\(model.kind): \(name)")
            }
        }
    }

    @Test("the light is per model")
    func backlightPerModel() throws {
        let defaults = try #require(UserDefaults(suiteName: "CasioModelTests"))
        defaults.removePersistentDomain(forName: "CasioModelTests")
        let until = Date().addingTimeInterval(3)
        defaults.set(until, forKey: CasioBacklightIntent.defaultsKey(model: "A"))
        #expect(CasioBacklightIntent.backlightUntil(model: "A", defaults: defaults) == until)
        #expect(CasioBacklightIntent.backlightUntil(model: "B", defaults: defaults) == nil)
    }
}
