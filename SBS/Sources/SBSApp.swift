import SwiftUI
import DesignSystem

@main
struct SBSApp: App {
    @State private var recorder = Recorder(scales: .shared)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(ScaleManager.shared)
                .environment(RunStore.shared)
                .environment(recorder)
                .dsTheme(.sbs)
        }
    }
}
