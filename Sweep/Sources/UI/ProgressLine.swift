import SwiftUI
import DesignSystem

/// Thin horizontal progress track in the app accent. The linear sibling of
/// ProgressRing; a promotion candidate for the DesignSystem package.
struct ProgressLine: View {
    @Environment(\.dsTheme) private var theme
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.dsSeparator)
                if fraction > 0 {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: max(6, geo.size.width * min(fraction, 1)))
                }
            }
        }
        .frame(height: 3)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: fraction)
    }
}
