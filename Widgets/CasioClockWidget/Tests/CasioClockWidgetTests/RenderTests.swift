import AppKit
import SwiftUI
import Testing

@testable import CasioClockWidget

@MainActor
@Suite("Casio faces render")
struct RenderTests {
    private func pixels<M: CasioModel>(_ model: M.Type, backlit: Bool) throws -> [UInt8] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let time = DateComponents(year: 2026, month: 10, day: 9, hour: 19, minute: 46)
        let date = try #require(calendar.date(from: time))
        let context = CasioFaceContext(
            date: date, calendar: calendar, uses12HourClock: false, backlit: backlit, previewSeconds: 24)
        let view = M.face(context).frame(width: M.canvas.width, height: M.canvas.height, alignment: .topLeading)
        let image = try #require(ImageRenderer(content: view).cgImage)
        let data = try #require(image.dataProvider?.data as Data?)
        return [UInt8](data)
    }

    private func check<M: CasioModel>(_ model: M.Type) throws {
        let off = try pixels(model, backlit: false)
        #expect(off.contains { $0 != 0 }, "\(M.kind) draws nothing")
        #expect(try pixels(model, backlit: true) != off, "\(M.kind): the light changes nothing")
    }

    private func displayPixels<D: LCDModuleDisplay>(_ display: D.Type, twelveHour: Bool) throws -> [UInt8] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let time = DateComponents(year: 2026, month: 10, day: 9, hour: 19, minute: 46)
        let date = try #require(calendar.date(from: time))
        let context = CasioFaceContext(
            date: date, calendar: calendar, uses12HourClock: twelveHour, previewSeconds: 24)
        let view = D(context: context, style: LCDStyle())
            .frame(width: D.glass.width, height: D.glass.height, alignment: .topLeading)
        let image = try #require(ImageRenderer(content: view).cgImage)
        return [UInt8](try #require(image.dataProvider?.data as Data?))
    }

    @Test("every LCD module display draws on its own glass, and 12-hour PM differs from 24-hour")
    func moduleDisplaysRender() throws {
        let displays: [any LCDModuleDisplay.Type] = [
            Module593Display.self, Module3459Display.self, Module240Display.self,
        ]
        for display in displays {
            let twentyFour = try displayPixels(display, twelveHour: false)
            #expect(twentyFour.contains { $0 != 0 }, "\(display) draws nothing")
            #expect(try displayPixels(display, twelveHour: true) != twentyFour, "\(display): 7 PM = 19:00")
        }
    }

    private func lcdTextPixels(_ text: String, font: LCDFont) throws -> [UInt8] {
        let view = LCDText(text: text, font: font, glyph: 40, edge: .leading(0), baseline: 44, style: LCDStyle())
            .frame(width: 120, height: 50, alignment: .topLeading)
        let image = try #require(ImageRenderer(content: view).cgImage)
        return [UInt8](try #require(image.dataProvider?.data as Data?))
    }

    @Test("LCD text in a DSEG7 font draws S, U, O, N in Casio's full-height shapes; DSEG14 letters are left alone")
    func sevenSegmentLetters() throws {
        let dseg7 = LCDFont.dseg7("BoldItalic")
        #expect(try lcdTextPixels("SUN", font: dseg7) == lcdTextPixels("5VM", font: dseg7))
        #expect(try lcdTextPixels("MO", font: dseg7) == lcdTextPixels("M0", font: dseg7))
        let dseg14 = LCDFont.dseg14("BoldItalic")
        #expect(try lcdTextPixels("SU", font: dseg14) != lcdTextPixels("5V", font: dseg14))
    }

    private func windowPixels(_ style: LCDStyle, lit: Bool) throws -> [UInt8] {
        let window = LCDWindow(
            frame: CGRect(x: 0, y: 0, width: 80, height: 50), glass: CGRect(x: 5, y: 5, width: 70, height: 40),
            backlit: lit, style: style.lit(lit))
        let view = ZStack(alignment: .topLeading) { window }.frame(width: 80, height: 50, alignment: .topLeading)
        let image = try #require(ImageRenderer(content: view).cgImage)
        return [UInt8](try #require(image.dataProvider?.data as Data?))
    }

    @Test("the light: a normal LCD's glass glows; an inverted one's glass stays dark and its ink changes")
    func lightOnNormalAndInvertedLCDs() throws {
        let normal = LCDStyle()
        #expect(try windowPixels(normal, lit: true) != windowPixels(normal, lit: false))
        var inverted = LCDStyle(glass: Color(white: 0.1), ink: Color(white: 0.7))
        inverted.litInk = .white
        let litPixels = try windowPixels(inverted, lit: true), offPixels = try windowPixels(inverted, lit: false)
        let largest = zip(litPixels, offPixels).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(largest <= 3)
        #expect(inverted.lit(true).ink == .white)
        #expect(inverted.lit(false).ink == Color(white: 0.7))
    }

    @Test("every module display's measured runs sit inside its glass")
    func runsInsideGlass() {
        let displays: [any LCDModuleDisplay.Type] = [
            Module593Display.self, A158WDisplay.self, Module3459Display.self, Module240Display.self,
            Module590Display.self,
            Module3208Display.self, Module3298Display.self, Module3229Display.self, W738HDisplay.self,
            W800HDisplay.self, GWB5600Display.self, W86Display.self, LA680WDisplay.self, A178WDisplay.self,
            A700WDisplay.self, A700WNegativeDisplay.self, F105WDisplay.self, DBC32Display.self,
            AE1200WHDisplay.self,
        ]
        for display in displays {
            let glass = CGRect(origin: display.canvasOrigin, size: display.glass)
            for run in display.runs {
                #expect(run.baseline - run.glyph >= glass.minY - 1, "\(display): \(run) above the glass")
                #expect(run.baseline <= glass.maxY + 1, "\(display): \(run) below the glass")
                #expect(run.x >= glass.minX && run.x <= glass.maxX, "\(display): \(run) anchored outside the glass")
            }
        }
    }

    @Test("every model draws its face, and the light changes it")
    func facesRender() throws {
        for model in CasioModels.all {
            try check(model)
        }
    }
}
