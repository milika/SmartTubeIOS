import SwiftUI

/// A Casio watch the package can draw as a widget. Each model lives in Models/<Name>/ and is
/// drawn on its own canvas, measured from a photo of the watch, with the kit and LCD parts.
protocol CasioModel {
    associatedtype Face: View
    associatedtype CaseBackground: View
    /// Stable WidgetKit kind; changing it removes the widget from people's Home Screens.
    static var kind: String { get }
    /// Name in the widget gallery ("Casio F-91W").
    static var displayName: String { get }
    /// Description in the widget gallery.
    static var summary: String { get }
    /// Canvas size in points (from the reference photo).
    static var canvas: CGSize { get }
    /// The part of the canvas the widget shows (default: all of it).
    static var widgetArea: CGRect { get }
    /// PostScript names of the fonts the model uses (all bundled in Resources/).
    static var fonts: [String] { get }
    /// Fills the widget behind the face (the case colour).
    static var caseBackground: CaseBackground { get }
    @ViewBuilder static func face(_ context: CasioFaceContext) -> Face
}

extension CasioModel {
    static var widgetArea: CGRect { CGRect(origin: .zero, size: canvas) }

    // Case print fonts (CaseFont), as `Model.michroma(size)` in faces.
    static func michroma(_ size: CGFloat) -> Font { CaseFont.custom(CaseFont.michroma, size) }
    static func saira(_ size: CGFloat) -> Font { CaseFont.custom(CaseFont.saira, size) }
    static func sairaExpanded(_ size: CGFloat) -> Font { CaseFont.custom(CaseFont.sairaExpanded, size) }
    static func archivoBlack(_ size: CGFloat) -> Font { CaseFont.custom(CaseFont.archivoBlack, size) }
}

/// A model that also has a rectangular Apple Watch complication.
protocol CasioComplicationModel: CasioModel {
    associatedtype RectangularComplication: View
    /// Stable WidgetKit kind of the complication (different from `kind`).
    static var complicationKind: String { get }
    /// Name and description in the complication picker.
    static var complicationName: String { get }
    static var complicationSummary: String { get }
    @ViewBuilder static func rectangularComplication(_ context: CasioFaceContext) -> RectangularComplication
}

/// What a face shows: the time, the clock style and whether the light is on.
struct CasioFaceContext {
    var date: Date
    var calendar: Calendar = .current
    var uses12HourClock: Bool = DisplayParts.localeUses12HourClock
    var backlit = false
    /// Fixed seconds for static renders; the timer only animates inside a widget.
    var previewSeconds: Int?
}

/// Every model (and every model with a complication), for tests: unique kinds, bundled fonts.
/// Add new models here.
enum CasioModels {
    static let all: [any CasioModel.Type] = [CasioF91W.self, CasioA158W.self, CasioGMWB5000.self, CasioDW5000C.self]
    static let complications: [any CasioComplicationModel.Type] = [CasioF91W.self]
}
