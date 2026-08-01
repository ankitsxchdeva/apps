import UIKit

/// One vocabulary of touch across both apps.
public enum Haptics {
    /// Passing feedback: a swipe, a toggle.
    public static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Something was queued or committed.
    public static func firm() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// A milestone: deck cleared, checklist complete.
    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
