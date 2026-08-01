import SwiftUI
import DesignSystem

/// Add or edit a movement: name, daily target, symbol.
/// Add mode also offers one-tap suggestions.
struct MovementFormSheet: View {
    @Environment(GrooveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dsTheme) private var theme

    /// nil = add mode.
    let editing: Movement?

    @State private var name: String
    @State private var setsPerDay: Int
    @State private var symbol: String

    init(editing: Movement?) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _setsPerDay = State(initialValue: editing?.setsPerDay ?? 3)
        _symbol = State(initialValue: editing?.symbol ?? Movement.symbolChoices[0])
    }

    private var isEditing: Bool { editing != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// Suggestions not already on the list.
    private var openSuggestions: [Movement] {
        let existing = Set(store.movements.map(\.name))
        return Movement.suggestions.filter { !existing.contains($0.name) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpace.l) {
                Text(isEditing ? "Edit movement" : "Add a movement")
                    .font(.dsTitle)
                    .foregroundStyle(Color.dsInk)

                nameField
                targetRow
                symbolGrid

                Button(isEditing ? "Save changes" : "Add movement", action: save)
                    .buttonStyle(PillButtonStyle())
                    .disabled(trimmedName.isEmpty)
                    .opacity(trimmedName.isEmpty ? 0.4 : 1)

                if !isEditing && !openSuggestions.isEmpty {
                    suggestions
                }
            }
            .padding(DSSpace.l)
        }
        .dsScreen()
        .presentationDetents(isEditing ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Fields

    private var nameField: some View {
        TextField("Name", text: $name)
            .font(.dsBody)
            .foregroundStyle(Color.dsInk)
            .padding(DSSpace.m)
            .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
    }

    private var targetRow: some View {
        HStack(spacing: DSSpace.m) {
            Text("Sets per day")
                .font(.dsHeadline)
                .foregroundStyle(Color.dsInk)
            Spacer()
            stepperButton("minus", enabled: setsPerDay > 1) { setsPerDay -= 1 }
            Text("\(setsPerDay)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.dsInk)
                .frame(minWidth: 40)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: setsPerDay)
            stepperButton("plus", enabled: setsPerDay < 10) { setsPerDay += 1 }
        }
        .padding(DSSpace.m)
        .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
    }

    private func stepperButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tap()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? theme.accent : Color.dsInkSecondary)
                .frame(width: 36, height: 36)
                .background(Color.dsBackground, in: Circle())
        }
        .disabled(!enabled)
    }

    private var symbolGrid: some View {
        VStack(alignment: .leading, spacing: DSSpace.s) {
            Text("Symbol")
                .font(.dsCaption)
                .foregroundStyle(Color.dsInkSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DSSpace.s), count: 6), spacing: DSSpace.s) {
                ForEach(Movement.symbolChoices, id: \.self) { choice in
                    Button {
                        symbol = choice
                        Haptics.tap()
                    } label: {
                        Image(systemName: choice)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(symbol == choice ? .white : Color.dsInk)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                symbol == choice ? theme.accent : Color.dsSurface,
                                in: .rect(cornerRadius: DSRadius.control, style: .continuous)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Suggestions

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: DSSpace.s) {
            Text("Suggestions")
                .font(.dsCaption)
                .foregroundStyle(Color.dsInkSecondary)
            ForEach(openSuggestions) { suggestion in
                Button {
                    store.add(Movement(
                        name: suggestion.name,
                        symbol: suggestion.symbol,
                        setsPerDay: suggestion.setsPerDay
                    ))
                    Haptics.firm()
                } label: {
                    HStack(spacing: DSSpace.m) {
                        Image(systemName: suggestion.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.name)
                                .font(.dsBody)
                                .foregroundStyle(Color.dsInk)
                            Text("\(suggestion.setsPerDay) sets a day")
                                .font(.dsCaption)
                                .foregroundStyle(Color.dsInkSecondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(theme.accent)
                    }
                    .padding(DSSpace.m)
                    .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
                }
            }
        }
    }

    // MARK: - Saving

    private func save() {
        if var edited = editing {
            edited.name = trimmedName
            edited.setsPerDay = setsPerDay
            edited.symbol = symbol
            store.update(edited)
        } else {
            store.add(Movement(name: trimmedName, symbol: symbol, setsPerDay: setsPerDay))
        }
        Haptics.firm()
        dismiss()
    }
}

#Preview {
    MovementFormSheet(editing: nil)
        .environment(GrooveStore.shared)
        .dsTheme(.groove)
}
