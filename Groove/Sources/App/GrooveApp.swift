import SwiftUI
import DesignSystem

@main
struct GrooveApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = GrooveStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .dsTheme(.groove)
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up sets logged from the widget while backgrounded.
            if phase == .active {
                store.reload()
            }
        }
    }
}
