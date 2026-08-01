import AppIntents
import WidgetKit

/// Logs one set for a movement, straight from the widget.
struct LogSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a set"
    static let description = IntentDescription("Logs one set for a movement.")

    @Parameter(title: "Movement ID")
    var movementID: String

    init() {}

    init(movementID: String) {
        self.movementID = movementID
    }

    func perform() async throws -> some IntentResult {
        let store = GrooveStore()
        if let movement = store.movements.first(where: { $0.id.uuidString == movementID }) {
            store.logSet(movement)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
