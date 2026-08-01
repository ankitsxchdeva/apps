import SwiftUI
import DesignSystem

@main
struct SweepApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .dsTheme(.sweep)
        }
    }
}
