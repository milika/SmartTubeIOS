import AppIntents
import Foundation

/// Turns a model's LCD light on for a few seconds, like the watch's LIGHT button.
public struct CasioBacklightIntent: AppIntent {
    public static let title: LocalizedStringResource = "Casio Light"
    public static let description = IntentDescription("Lights up a Casio widget for a few seconds.")
    public static let isDiscoverable = false

    static let duration: TimeInterval = 3

    /// The model's widget kind.
    @Parameter(title: "Model")
    var model: String

    public init() {}

    init(model: String) {
        self.model = model
    }

    public func perform() async throws -> some IntentResult {
        // WidgetKit reloads the widget's timeline after a widget intent runs.
        UserDefaults.standard.set(Date().addingTimeInterval(Self.duration), forKey: Self.defaultsKey(model: model))
        return .result()
    }

    static func defaultsKey(model: String) -> String { "CasioClockWidget.backlightUntil.\(model)" }

    static func backlightUntil(model: String, defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: defaultsKey(model: model)) as? Date
    }
}
