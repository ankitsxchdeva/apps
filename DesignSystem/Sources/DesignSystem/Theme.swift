import SwiftUI

/// Per-app identity on top of the shared neutrals.
public struct DSTheme {
    public let accent: Color

    public init(accent: Color) {
        self.accent = accent
    }

    /// Sweep — ember, the color of letting go.
    public static let sweep = DSTheme(accent: .dsLetGo)
    /// Groove — moss, steady and unhurried.
    public static let groove = DSTheme(accent: Color(light: 0x3E7C5B, dark: 0x63A683))
}

private struct DSThemeKey: EnvironmentKey {
    static let defaultValue = DSTheme(accent: .dsInk)
}

public extension EnvironmentValues {
    var dsTheme: DSTheme {
        get { self[DSThemeKey.self] }
        set { self[DSThemeKey.self] = newValue }
    }
}

public extension View {
    /// Apply once at the app root. Sets the accent for DS components and system tint.
    func dsTheme(_ theme: DSTheme) -> some View {
        environment(\.dsTheme, theme).tint(theme.accent)
    }
}
