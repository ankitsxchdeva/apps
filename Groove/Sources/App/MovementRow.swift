import SwiftUI
import DesignSystem

/// The signature control: one big pill per movement. Tapping logs a set and
/// the pill fills with moss from the leading edge, proportional to progress.
struct MovementRow: View {
    @Environment(\.dsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let movement: Movement
    let setsDone: Int
    let onLog: () -> Void
    let onRemoveSet: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var isComplete: Bool { setsDone >= movement.setsPerDay }
    private var fraction: Double {
        guard movement.setsPerDay > 0 else { return 0 }
        return min(1, Double(setsDone) / Double(movement.setsPerDay))
    }

    var body: some View {
        Button(action: onLog) {
            HStack(spacing: DSSpace.m) {
                Image(systemName: movement.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 32)
                    .foregroundStyle(isComplete ? .white : theme.accent)
                Text(movement.name)
                    .font(.dsHeadline)
                    .foregroundStyle(isComplete ? .white : Color.dsInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: DSSpace.s)
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                } else {
                    Text("\(setsDone) of \(movement.setsPerDay)")
                        .font(.dsCaption)
                        .foregroundStyle(Color.dsInkSecondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, DSSpace.l)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background {
                ZStack(alignment: .leading) {
                    shape.fill(Color.dsSurface)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(theme.accent.opacity(isComplete ? 1 : 0.22))
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .clipShape(shape)
            }
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
        .buttonStyle(MovementRowPressStyle())
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8),
            value: setsDone
        )
        .contextMenu {
            Button("Remove a set", systemImage: "arrow.uturn.backward", action: onRemoveSet)
                .disabled(setsDone == 0)
            Button("Edit", systemImage: "pencil", action: onEdit)
            Button("Delete movement", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous)
    }
}

/// Gentle press-down, same spring as the rest of the system.
private struct MovementRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
