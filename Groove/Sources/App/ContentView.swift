import SwiftUI
import DesignSystem

/// Home = today. Open, see the checklist, tap a pill. Nothing else to learn.
struct ContentView: View {
    @Environment(GrooveStore.self) private var store
    @Environment(\.dsTheme) private var theme

    @State private var showsAddSheet = false
    @State private var editingMovement: Movement?
    @State private var showsReminders = false

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpace.l) {
                header
                ring
                if store.movements.isEmpty {
                    EmptyStateView(
                        systemImage: "figure.strengthtraining.functional",
                        title: "No movements yet",
                        message: "Add one small thing you can do a few times a day."
                    )
                } else {
                    VStack(spacing: DSSpace.m) {
                        ForEach(store.movements) { movement in
                            MovementRow(
                                movement: movement,
                                setsDone: store.setsDone(for: movement),
                                onLog: { log(movement) },
                                onRemoveSet: {
                                    store.removeSet(movement)
                                    Haptics.tap()
                                },
                                onEdit: { editingMovement = movement },
                                onDelete: {
                                    store.delete(movement)
                                    Haptics.firm()
                                }
                            )
                        }
                    }
                }
                Button("Add a movement") { showsAddSheet = true }
                    .buttonStyle(PillButtonStyle(.quiet))
            }
            .padding(DSSpace.l)
        }
        .dsScreen()
        .sheet(isPresented: $showsAddSheet) {
            MovementFormSheet(editing: nil)
        }
        .sheet(item: $editingMovement) { movement in
            MovementFormSheet(editing: movement)
        }
        .sheet(isPresented: $showsReminders) {
            RemindersSheet()
        }
        #if DEBUG
        .onAppear {
            // Screenshot hooks for UI verification without touch automation.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-groove-screenshot-add") { showsAddSheet = true }
            if arguments.contains("-groove-screenshot-reminders") { showsReminders = true }
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DSSpace.s) {
            DSHeader("Today")
            if store.streak >= 2 {
                streakChip
            }
            Button {
                showsReminders = true
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.dsInkSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Reminders")
        }
    }

    private var streakChip: some View {
        HStack(spacing: DSSpace.xs) {
            Image(systemName: "flame.fill")
                .font(.caption)
                .foregroundStyle(Color.dsStreak)
            Text("\(store.streak) days")
                .font(.dsCaption)
                .foregroundStyle(Color.dsInk)
        }
        .padding(.horizontal, DSSpace.m - DSSpace.xs)
        .padding(.vertical, DSSpace.s)
        .background(Color.dsSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.dsSeparator, lineWidth: 1))
    }

    // MARK: - Ring

    private var ring: some View {
        ZStack {
            ProgressRing(progress: store.progressToday, lineWidth: 12)
                .frame(width: 140, height: 140)
            if store.isTodayComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.accent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                VStack(spacing: 0) {
                    Text("\(store.remainingToday)")
                        .font(.dsDisplay)
                        .foregroundStyle(Color.dsInk)
                        .contentTransition(.numericText(countsDown: true))
                    Text("to go")
                        .font(.dsCaption)
                        .foregroundStyle(Color.dsInkSecondary)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.remainingToday)
        .padding(.vertical, DSSpace.s)
    }

    // MARK: - Logging

    /// One haptic per tap: success the moment the day completes,
    /// firm when a movement hits its target, a light tap otherwise.
    private func log(_ movement: Movement) {
        let wasDone = store.setsDone(for: movement)
        guard wasDone < movement.setsPerDay else { return }
        store.logSet(movement)
        if store.isTodayComplete {
            Haptics.success()
        } else if wasDone + 1 == movement.setsPerDay {
            Haptics.firm()
        } else {
            Haptics.tap()
        }
    }
}

#Preview {
    ContentView()
        .environment(GrooveStore.shared)
        .dsTheme(.groove)
}
