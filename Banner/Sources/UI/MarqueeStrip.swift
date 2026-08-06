import SwiftUI
import DesignSystem

/// The scrolling text itself: copies of one line chasing each other leftwards,
/// forever. The sign and the editor's preview use this same view, so the
/// preview can't lie about what the sign will do.
struct MarqueeStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    let ink: Color
    let speed: SignSpeed
    /// Point size of the text. The sign passes a fraction of its height.
    let fontSize: CGFloat

    /// Breathing room between one copy and the next.
    private var gap: CGFloat { fontSize * 0.7 }

    private var line: some View {
        Text(text)
            .font(.dsSign(fontSize))
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
    }

    var body: some View {
        GeometryReader { geo in
            let unit = Font.dsSignWidth(of: text, size: fontSize) + gap
            Group {
                if reduceMotion || unit <= gap {
                    // Reduce Motion, or nothing to say: hold it still and fit it.
                    Text(text)
                        .font(.dsSign(fontSize))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.2)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    TimelineView(.animation) { context in
                        let elapsed = context.date.timeIntervalSinceReferenceDate
                        let phase = (elapsed * speed.pointsPerSecond)
                            .truncatingRemainder(dividingBy: unit)
                        HStack(spacing: gap) {
                            ForEach(0..<copies(across: geo.size.width, unit: unit), id: \.self) { _ in
                                line
                            }
                        }
                        .offset(x: -phase)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    }
                }
            }
            .clipped()
        }
    }

    /// Enough copies to cover the width even when the leading one has scrolled
    /// a full unit off the edge.
    private func copies(across width: CGFloat, unit: CGFloat) -> Int {
        max(2, Int((width / unit).rounded(.up)) + 2)
    }
}

#Preview {
    MarqueeStrip(text: "DJ Nova · main room · 11pm", ink: .dsStreak, speed: .medium, fontSize: 64)
        .frame(height: 100)
        .background(Color.black)
}
