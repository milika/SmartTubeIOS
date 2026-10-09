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

    @Test("the A158W is a model with its own kind")
    func a158w() {
        #expect(CasioModels.all.contains { $0.kind == CasioA158W.kind })
        #expect(CasioA158W.kind == "CasioA158W")
    }

    @Test("the GMW-B5000 is a model with its own kind")
    func gmwB5000() {
        #expect(CasioModels.all.contains { $0.kind == CasioGMWB5000.kind })
        #expect(CasioGMWB5000.kind == "CasioGMWB5000")
    }

    @Test("the DW-5000C is a model with its own kind")
    func dw5000c() {
        #expect(CasioModels.all.contains { $0.kind == CasioDW5000C.kind })
        #expect(CasioDW5000C.kind == "CasioDW5000C")
    }

    @Test("DW-5000C date: month first, each number right-aligned in two digits")
    func dw5000cDate() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let date = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 4)))
        #expect(Module240Display.dateText(date, calendar: cal, blank: "!") == "11-!4")
        let date2 = try #require(cal.date(from: DateComponents(year: 2026, month: 6, day: 28)))
        #expect(Module240Display.dateText(date2, calendar: cal, blank: "!") == "!6-28")
    }

    @Test("7-segment weekdays: S, U and O in the full-height shapes (CA-53W, A168W)")
    func ca53wWeekdayLetters() {
        #expect(DisplayParts.sevenSegmentLetters("SU") == "5V")
        #expect(DisplayParts.sevenSegmentLetters("MO") == "M0")
        #expect(DisplayParts.sevenSegmentLetters("TU") == "TV")
        #expect(DisplayParts.sevenSegmentLetters("WE") == "WE")
    }

    @Test("case extension: the window's extra space is equal above and below; bands move top to bottom")
    func caseExtension() {
        let stretch = CaseExtension(amount: 80)
        // Above the window: its offset. Below it: the case's growth minus the offset and the window's growth.
        let above = stretch.offset(.display)
        let below = stretch.caseGrowth - stretch.offset(.display) - stretch.windowGrowth
        #expect(above == below)
        let bands: [CaseExtension.Band] = [.top, .upperSides, .middleSides, .lowerSides, .bottom]
        let offsets = bands.map { stretch.offset($0) }
        #expect(offsets == offsets.sorted())
        #expect(stretch.offset(.top) == 0 && stretch.offset(.bottom) == stretch.caseGrowth)
        // Side labels stay level with the part of the window they sit beside.
        #expect(stretch.offset(.middleSides) == stretch.offset(.display) + stretch.windowGrowth / 2)
        #expect(stretch.offset(.lowerSides) == stretch.offset(.display) + stretch.windowGrowth)
    }

    @Test("complication kinds are unique and differ from the iPhone kinds")
    func complicationKinds() {
        let kinds = CasioModels.all.map { $0.kind } + CasioModels.complications.map { $0.complicationKind }
        #expect(Set(kinds).count == kinds.count)
        #expect(CasioF91W.complicationKind == "CasioF91WComplication")
    }

    @Test("every model's widget area lies on its canvas")
    func widgetAreas() {
        for model in CasioModels.all {
            #expect(CGRect(origin: .zero, size: model.canvas).contains(model.widgetArea), "\(model.kind)")
        }
        // The F-91W widget shows a square around the bezel (the case is extended to fill it).
        #expect(CasioF91W.widgetArea.width == CasioF91W.widgetArea.height)
    }

    @Test(
        "the bundled font files are exactly the fonts the package draws with (case fonts and every model's LCD fonts), and they register"
    )
    func fonts() throws {
        BundledFonts.register()
        let lcdFonts = CasioModels.all.flatMap { [$0.lcd.digits.postScriptName, $0.lcd.letters.postScriptName] }
        let used = Set(CaseFont.all + lcdFonts)
        var bundled = Set<String>()
        for url in BundledFonts.fileURLs {
            let descriptors = try #require(
                CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
            for descriptor in descriptors {
                bundled.insert(try #require(CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String))
            }
        }
        #expect(bundled == used)
        for name in used {
            let font = CTFontCreateWithName(name as CFString, 12, nil)
            #expect(CTFontCopyPostScriptName(font) as String == name)
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
