import SwiftUI
import WidgetKit

// The catalogue: every Casio watch the package publishes. Registering a new model happens here
// only - its Home Screen widget (and complication, if it has one) below, and the model in
// CasioModels next to it (tests iterate CasioModels). The app's widget extension and the watch
// extension list the catalogue once and don't change when a model is added. Widget kinds come
// from the models, so widgets already on people's Home Screens survive.

/// Every model (and every model with a complication). Keep in step with CasioWidgets below.
enum CasioModels {
    static let all: [any CasioModel.Type] = [
        CasioF91W.self, CasioA158W.self, CasioGMWB5000.self, CasioDW5000C.self, CasioW59.self,
    ]
    static let complications: [any CasioComplicationModel.Type] = [CasioF91W.self]
}

/// The package's widgets, for a WidgetBundle.
public enum CasioWidgets {
    #if !os(watchOS)
    /// Every model's small Home Screen widget: `CasioWidgets.homeScreen` in the iOS widget
    /// extension's WidgetBundle.
    @WidgetBundleBuilder public static var homeScreen: some Widget {
        CasioWatchWidget<CasioF91W>()
        CasioWatchWidget<CasioA158W>()
        CasioWatchWidget<CasioGMWB5000>()
        CasioWatchWidget<CasioDW5000C>()
        CasioWatchWidget<CasioW59>()
    }
    #else
    /// Every model's rectangular complication: `CasioWidgets.complications` in the watch
    /// extension's WidgetBundle.
    @WidgetBundleBuilder public static var complications: some Widget {
        CasioComplicationWidget<CasioF91W>()
    }
    #endif
}

/// The complications as live previews with their names, for the watch app's screen.
public struct CasioComplicationGallery: View {
    public init() {}

    public var body: some View {
        TimelineView(.everyMinute) { timeline in
            VStack(alignment: .leading, spacing: 10) {
                ForEach(CasioModels.complications.indices, id: \.self) { index in
                    Self.preview(CasioModels.complications[index], date: timeline.date)
                }
            }
        }
    }

    // AnyView: the view's type depends on the model, which comes out of an existential list.
    private static func preview<Model: CasioComplicationModel>(_ model: Model.Type, date: Date) -> AnyView {
        AnyView(previewContent(model, date: date))
    }

    private static func previewContent<Model: CasioComplicationModel>(_ model: Model.Type, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Model.rectangularComplication(CasioFaceContext(date: date))
                .frame(height: 64)
            Text(Model.complicationName + " complication")
                .font(.headline)
        }
    }
}
