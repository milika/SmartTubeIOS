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

    @Test("every model draws its face, and the light changes it")
    func facesRender() throws {
        for model in CasioModels.all {
            try check(model)
        }
    }
}
