import SwiftUI
import DesignSystem

/// One scale's live state. Tap to connect or change the scale in this slot.
struct ScaleCard: View {
    let slot: Slot
    let state: ScaleManager.SlotState
    /// What this scale is testing, if labelled.
    var label: String?
    /// This scale's own timer, or its clock since its first pour.
    let time: TimeInterval?
    /// Glow when the weight jumps, so pressing a scale shows its card.
    var identifies = false
    let connect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false

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
                if let label {
                    Text(label)
                        .font(.dsCaption)
                        .foregroundStyle(Color.dsInk)
                        .lineLimit(1)
                }
                switch state.status {
                case .empty:
                    Text(slot.isOptional ? "Optional" : "Not connected")
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
                    Text(time?.clockText ?? "–")
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
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
                    .stroke(slot.color, lineWidth: 3)
                    .opacity(glowing ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: state.latest?.grams) { old, new in
            guard identifies, let old, let new, abs(new - old) >= Self.pressGrams else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { glowing = true }
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) { glowing = false }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(state.status == .empty ? "Connects a scale" : "Changes the scale")
    }

    /// A finger on the pan, well above a settled scale's noise.
    static let pressGrams = 1.0

    private var grams: String {
        guard let reading = state.latest else { return "– g" }
        return reading.grams.formatted(.number.precision(.fractionLength(1))) + " g"
    }

    private var detail: String {
        guard let reading = state.latest else { return state.name ?? "Waiting for weight" }
        let flow = reading.flow.formatted(.number.precision(.fractionLength(1)))
        return "\(flow) g/s" + (reading.battery.map { " · \($0)%" } ?? "")
    }
}
