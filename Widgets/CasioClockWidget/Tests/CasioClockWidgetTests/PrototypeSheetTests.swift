import AppKit
import SwiftUI
import Testing

@testable import CasioClockWidget

/// Renders the look prototypes into one labelled sheet (not part of the normal test run's
/// assertions; writes ~/DevTemp/smarttube/scratch/casio-prototypes.png).
@MainActor
@Test("render prototype sheet")
func renderPrototypeSheet() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 26, hour: 18, minute: 4, second: 56))!

    let vintageGlass = Color(red: 0.72, green: 0.76, blue: 0.62)
    let backlitGlass = Color(red: 0.42, green: 0.80, blue: 0.62)
    let variants: [(String, CasioFaceStyle)] = [
        ("A  DSEG Italic + unlit segments", CasioFaceStyle()),
        ("B  DSEG Upright + unlit segments", CasioFaceStyle(digits: .dseg7("Regular"), letters: .dseg14("Regular"))),
        ("C  DSEG Bold Italic + unlit", CasioFaceStyle(digits: .dseg7("BoldItalic"), letters: .dseg14("BoldItalic"))),
        ("D  DSEG Light Italic + unlit", CasioFaceStyle(digits: .dseg7("LightItalic"), letters: .dseg14("LightItalic"))),
        ("E  DSEG Italic, no unlit segments", CasioFaceStyle(unlitOpacity: 0)),
        ("F  DSEG Italic, vintage yellow-green LCD", CasioFaceStyle(unlitOpacity: 0.1, glass: vintageGlass)),
        ("G  DSEG Italic, backlight on", CasioFaceStyle(unlitOpacity: 0.1, glass: backlitGlass)),
        ("H  Current (hand-drawn segments)", CasioFaceStyle(digits: .handDrawn, letters: .handDrawn, unlitOpacity: 0)),
    ]

    let tile = CGSize(width: 594 * 0.6, height: 530 * 0.6)
    let sheet = VStack(spacing: 24) {
        ForEach(0..<2) { row in
            HStack(spacing: 24) {
                ForEach(0..<4) { col in
                    let (label, style) = variants[row * 4 + col]
                    VStack(spacing: 10) {
                        CasioWatchFace(date: date, calendar: cal, uses12HourClock: true, style: style, previewSeconds: 56)
                            .background(CasioWatchFace.resin)
                            .frame(width: tile.width, height: tile.height)
                            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                        Text(label).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    }
                }
            }
        }
    }
    .padding(32)
    .background(Color(white: 0.2))

    let renderer = ImageRenderer(content: sheet)
    renderer.scale = 1.5
    let rep = NSBitmapImageRep(data: try #require(renderer.nsImage).tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: NSHomeDirectory() + "/DevTemp/smarttube/scratch/casio-prototypes.png"))
}
