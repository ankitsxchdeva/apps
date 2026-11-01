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
    /// Banner — violet, the color of a dark room.
    public static let banner = DSTheme(accent: Color(light: 0x6C4BD8, dark: 0x8E6CF0))
    /// SBS — roast brown, the color of the cup being tested.
    public static let sbs = DSTheme(accent: Color(light: 0x7A5235, dark: 0xB08560))
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
