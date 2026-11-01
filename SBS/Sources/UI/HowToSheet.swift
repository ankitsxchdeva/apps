import SwiftUI
import DesignSystem

/// How a run works, in four steps, with a way to try it on demo scales.
struct HowToSheet: View {
    @Environment(ScaleManager.self) private var scales
    @Environment(\.dismiss) private var dismiss

    private let steps: [(title: String, detail: String)] = [
        ("Connect your scales",
         "Tap Scale A, then Scale B, and pick each scale. C and D are optional. SBS reconnects them next time. Not sure which is which? Press on a scale and its card lights up. Hold a card to swap it with another."),
        ("Tare and reset all",
         "Put your vessels on the scales, then tap Tare and reset all."),
        ("Start each pour",
         "Press a scale's timer button as you start pouring on it. Every curve starts at its own zero, so the next pour can start a few seconds later. Scales without a timer start when they first see 1 g."),
        ("Stop and compare",
         "Tap Stop to see how closely each pour matched scale A, and export the run as CSV."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpace.l) {
                    DSHeader("How to use", subtitle: "Compare pours side by side, one scale each.")
                    VStack(alignment: .leading, spacing: DSSpace.m) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: DSSpace.m) {
                                Text("\(index + 1)")
                                    .font(.dsHeadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: DSSpace.xs) {
                                    Text(step.title)
                                        .font(.dsHeadline)
                                        .foregroundStyle(Color.dsInk)
                                    Text(step.detail)
                                        .font(.dsBody)
                                        .foregroundStyle(Color.dsInkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(DSSpace.m)
                    .dsCard()
                    Text("Bumped a scale? Accidental taps are smoothed out of the curve automatically. Bookoo scales are fully supported; other brands are in beta.")
                        .font(.dsCaption)
                        .foregroundStyle(Color.dsInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !scales.isDemo {
                        Button("Try with demo scales") {
                            Haptics.firm()
                            scales.startDemo()
                            dismiss()
                        }
                        .buttonStyle(PillButtonStyle(.quiet))
                    }
                }
                .padding(DSSpace.l)
            }
            .dsScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
