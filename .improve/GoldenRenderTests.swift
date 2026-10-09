import AppKit
import SwiftUI
import Testing
import WidgetKit

@testable import CasioClockWidget

// Improvement-run golden renders (copied in by .improve/golden.sh, never committed).
@MainActor
@Test("golden renders (improve run)")
func goldenRenders() throws {
    let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GOLDEN_DIR"]!)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    func save<V: View>(_ v: V, _ size: CGSize, _ name: String) throws {
        let view = ZStack(alignment: .topLeading) { v }.frame(width: size.width, height: size.height, alignment: .topLeading)
        let r = ImageRenderer(content: view); r.scale = 2
        let rep = NSBitmapImageRep(data: try #require(r.nsImage).tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
    }
    func cal(_ tz: String) -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: tz)!; return c }
    let dates: [(String, Calendar, DateComponents, Int)] = [
        ("fri", cal("UTC"), DateComponents(year: 2026, month: 10, day: 9, hour: 19, minute: 46), 24),
        ("sundst", cal("Europe/Berlin"), DateComponents(year: 2026, month: 6, day: 28, hour: 3, minute: 5), 7),
        ("newyear", cal("UTC"), DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 0), 0),
    ]
    func all<M: CasioModel>(_ m: M.Type, _ tag: String) throws {
        for (dn, c, comps, sec) in dates {
            let d = c.date(from: comps)!
            for twelve in [false, true] {
                for lit in [false, true] {
                    let ctx = CasioFaceContext(date: d, calendar: c, uses12HourClock: twelve, backlit: lit, previewSeconds: sec)
                    let n = "\(tag)-\(dn)-\(twelve ? 12 : 24)-\(lit ? "lit" : "off")"
                    try save(M.face(ctx).background(M.caseBackground), M.canvas, "face-" + n)
                    try save(
                        FaceCanvas(size: M.canvas, visible: M.widgetArea) { M.face(ctx) }
                            .frame(width: 170, height: 170).background(M.caseBackground),
                        CGSize(width: 170, height: 170), "widget-" + n)
                }
            }
        }
    }
    for model in CasioModels.all {
        try all(model, model.kind)
    }
    for (dn, c, comps, sec) in dates {
        let d = c.date(from: comps)!
        for twelve in [false, true] {
            let ctx = CasioFaceContext(date: d, calendar: c, uses12HourClock: twelve, previewSeconds: sec)
            try save(CasioF91W.rectangularComplication(ctx).frame(width: 200, height: 80), CGSize(width: 200, height: 80), "comp-\(dn)-\(twelve ? 12 : 24)-full")
            try save(
                CasioF91W.rectangularComplication(ctx).environment(\.widgetRenderingMode, .accented).frame(width: 200, height: 80)
                    .background(Color.black), CGSize(width: 200, height: 80), "comp-\(dn)-\(twelve ? 12 : 24)-accented")
        }
    }
}
