import SwiftUI
import DesignSystem

@main
struct BannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(SignStore.shared)
                .dsTheme(.banner)
        }
    }
}

/// The editor is portrait; the sign turns the app sideways while it's up.
/// UIKit owns the orientation mask, so the app delegate exists only for this.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.mask
    }
}

enum Orientation {
    /// Restrict the app to `mask` and rotate to it now.
    static func set(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.mask = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}
