import Testing
import WidgetKit

@testable import CasioClockWidget

@Suite("Casio catalogue")
struct CatalogueTests {
    /// The widgets inside a WidgetBundle builder's result, found by reflection (WidgetKit has no
    /// API to list them). If an SDK hides the structure this finds none and the test fails.
    private func widgets(in value: Any) -> [CasioModelWidget] {
        if let widget = value as? CasioModelWidget { return [widget] }
        return Mirror(reflecting: value).children.flatMap { widgets(in: $0.value) }
    }

    @Test("the Home Screen catalogue publishes exactly one widget per registered model")
    func homeScreen() {
        let published = widgets(in: CasioWidgets.homeScreen).map { $0.modelKind }.sorted()
        let registered = CasioModels.all.map { $0.kind }.sorted()
        #expect(published == registered)
    }
}
