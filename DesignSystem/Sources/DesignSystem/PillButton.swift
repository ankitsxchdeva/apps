import SwiftUI

/// The one button shape both apps use. Full-width capsule that presses like a real thing.
public struct PillButtonStyle: ButtonStyle {
    public enum Kind {
        case primary, quiet, destructive
    }

    @Environment(\.dsTheme) private var theme
    let kind: Kind

    public init(_ kind: Kind = .primary) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsHeadline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background, in: Capsule())
            .overlay {
                if kind == .quiet {
                    Capsule().strokeBorder(Color.dsSeparator, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .destructive: .white
        case .quiet: .dsInk
        }
    }

    private var background: Color {
        switch kind {
        case .primary: theme.accent
        case .quiet: .dsSurface
        case .destructive: .dsLetGo
        }
    }
}
