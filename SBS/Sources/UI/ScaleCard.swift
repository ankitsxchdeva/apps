import SwiftUI
import DesignSystem

/// One scale's live state. Tap to connect or swap the scale in this slot.
struct ScaleCard: View {
    let slot: Slot
    let state: ScaleManager.SlotState
    let connect: () -> Void

    var body: some View {
        Button(action: connect) {
            VStack(alignment: .leading, spacing: DSSpace.s) {
                HStack(spacing: DSSpace.s) {
                    Circle().fill(slot.color).frame(width: 10, height: 10)
                    Text("Scale \(slot.name)")
                        .font(.dsHeadline)
                        .foregroundStyle(Color.dsInk)
                    Spacer(minLength: 0)
                }
                switch state.status {
                case .empty:
                    Text("Not connected")
                        .font(.dsCaption)
                        .foregroundStyle(Color.dsInkSecondary)
                    Text("Connect")
                        .font(.dsHeadline)
                        .foregroundStyle(.tint)
                        .padding(.top, DSSpace.s)
                case .connecting:
                    Text(state.name ?? "Bookoo scale")
                        .font(.dsCaption)
                        .foregroundStyle(Color.dsInkSecondary)
                        .lineLimit(1)
                    Text("Connecting…")
                        .font(.dsHeadline)
                        .foregroundStyle(Color.dsInkSecondary)
                        .padding(.top, DSSpace.s)
                case .connected:
                    Text(grams)
                        .font(.dsTitle)
                        .monospacedDigit()
                        .foregroundStyle(Color.dsInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(state.latest?.timer.clockText ?? "–")
                        .font(.dsHeadline)
                        .monospacedDigit()
                        .foregroundStyle(Color.dsInkSecondary)
                        .accessibilityLabel("Timer")
                    Text(detail)
                        .font(.dsCaption)
                        .monospacedDigit()
                        .foregroundStyle(Color.dsInkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(DSSpace.m)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .dsCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(state.status == .empty ? "Connects a scale" : "Swaps the scale")
    }

    private var grams: String {
        guard let reading = state.latest else { return "– g" }
        return reading.grams.formatted(.number.precision(.fractionLength(1))) + " g"
    }

    private var detail: String {
        guard let reading = state.latest else { return state.name ?? "Waiting for weight" }
        let flow = reading.flow.formatted(.number.precision(.fractionLength(1)))
        return "\(flow) g/s · \(reading.battery)%"
    }
}
