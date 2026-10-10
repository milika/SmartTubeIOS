import AppKit
import Foundation
import SwiftUI
import Testing

@testable import CasioClockWidget

/// Renders one model's face on its whole canvas to a PNG, for matching a face against its reference
/// image (docs/ADDING-A-MODEL.md, tools/casio_measure.py). Opt-in: skipped unless CASIO_RENDER is set.
///
///     CASIO_RENDER=CasioW800H CASIO_OUT=/tmp/w800h.png CASIO_TIME=2024-06-30T22:58:50 \
///         CASIO_12H=1 swift test --filter referenceRender
///
/// CASIO_TZ names the time zone CASIO_TIME is in (default GMT; daylight saving time shows DST on
/// displays that have it). CASIO_LIT=1 lights the LCD; CASIO_LIVE=1 renders the live timer views instead of fixed seconds;
/// CASIO_SCALE sets pixels per point (default 2); CASIO_REFERENCE_LAYOUT=1 leaves the case extension
/// out, as on the reference image (tools/casio_measure.py check does this); CASIO_STEPS sets today's
/// steps for faces with a step display.
@Suite("Reference render (opt-in)")
struct ReferenceRenderTests {
    private static let env = ProcessInfo.processInfo.environment

    @MainActor
    @Test(.enabled(if: env["CASIO_RENDER"] != nil))
    func referenceRender() throws {
        let env = Self.env
        let kind = try #require(env["CASIO_RENDER"])
        let model = try #require(
            CasioModels.all.first { $0.kind == kind || "\($0)" == kind }, "no model with kind or type \(kind)")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = env["CASIO_TZ"].flatMap(TimeZone.init(identifier:)) ?? .gmt
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        formatter.timeZone = calendar.timeZone
        let date = try #require(formatter.date(from: env["CASIO_TIME"] ?? "2024-06-30T22:58:50"))
        let context = CasioFaceContext(
            date: date, calendar: calendar, uses12HourClock: env["CASIO_12H"] == "1", backlit: env["CASIO_LIT"] == "1",
            previewSeconds: env["CASIO_LIVE"] == "1" ? nil : calendar.component(.second, from: date),
            steps: env["CASIO_STEPS"].flatMap { Int($0) })
        let out = URL(fileURLWithPath: env["CASIO_OUT"] ?? NSTemporaryDirectory() + "\(kind).png")
        let scale = CGFloat(Double(env["CASIO_SCALE"] ?? "2") ?? 2)
        try CaseExtension.$referenceLayout.withValue(env["CASIO_REFERENCE_LAYOUT"] == "1") {
            try Self.render(model, context: context, scale: scale, to: out)
        }
    }

    @MainActor
    private static func render<Model: CasioModel>(
        _ model: Model.Type, context: CasioFaceContext, scale: CGFloat, to url: URL
    ) throws {
        let view = ZStack(alignment: .topLeading) { Model.face(context) }
            .frame(width: Model.canvas.width, height: Model.canvas.height, alignment: .topLeading)
            .background(Model.caseBackground)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.nsImage?.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: image)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}
