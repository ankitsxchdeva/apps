import SwiftUI
import UIKit

// Shared neutrals and feedback colors. Per-app accents live in DSTheme.
public extension Color {
    /// Warm paper — the base of every screen.
    static let dsBackground   = Color(light: 0xFAF8F5, dark: 0x161514)
    /// Cards and sheets that sit on the paper.
    static let dsSurface      = Color(light: 0xFFFFFF, dark: 0x221F1E)
    static let dsInk          = Color(light: 0x1C1B1A, dark: 0xF4F2EF)
    static let dsInkSecondary = Color(light: 0x8A867F, dark: 0x9B968E)
    static let dsSeparator    = Color(light: 0xECE8E2, dark: 0x2E2C2A)

    /// Swipe-right / positive feedback.
    static let dsKeep   = Color(light: 0x3FA26C, dark: 0x54B981)
    /// Swipe-left / removal feedback.
    static let dsLetGo  = Color(light: 0xE4573D, dark: 0xEB6B52)
    /// Streaks and celebration.
    static let dsStreak = Color(light: 0xD9962E, dark: 0xE3A94F)
}

public extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
