import SwiftUI
import DesignSystem

/// Daily reminder times. Authorization is requested only when the first time is added.
struct RemindersSheet: View {
    @State private var reminders = ReminderStore()
    @State private var newTime = defaultTime

    private static var defaultTime: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpace.l) {
                VStack(alignment: .leading, spacing: DSSpace.xs) {
                    Text("Reminders")
                        .font(.dsTitle)
                        .foregroundStyle(Color.dsInk)
                    Text("Little nudges through the day.")
                        .font(.dsBody)
                        .foregroundStyle(Color.dsInkSecondary)
                }

                if reminders.authorizationDenied {
                    deniedNote
                }

                if reminders.times.isEmpty {
                    Text("No reminders yet.")
                        .font(.dsBody)
                        .foregroundStyle(Color.dsInkSecondary)
                } else {
                    VStack(spacing: DSSpace.s) {
                        ForEach(reminders.times) { time in
                            timeRow(time)
                        }
                    }
                }

                addRow
            }
            .padding(DSSpace.l)
        }
        .dsScreen()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await reminders.refreshAuthorizationStatus()
        }
    }

    private func timeRow(_ time: ReminderTime) -> some View {
        HStack(spacing: DSSpace.m) {
            Image(systemName: "bell.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.dsInkSecondary)
            Text(time.date, format: .dateTime.hour().minute())
                .font(.dsHeadline)
                .foregroundStyle(Color.dsInk)
            Spacer()
            Button {
                Haptics.firm()
                Task { await reminders.remove(time) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.dsLetGo)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Delete reminder")
        }
        .padding(.leading, DSSpace.m)
        .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
    }

    private var addRow: some View {
        VStack(spacing: DSSpace.m) {
            HStack {
                Text("New reminder")
                    .font(.dsHeadline)
                    .foregroundStyle(Color.dsInk)
                Spacer()
                DatePicker("New reminder time", selection: $newTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(DSSpace.m)
            .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
            Button("Add reminder") {
                Haptics.firm()
                Task {
                    await reminders.add(newTime)
                }
            }
            .buttonStyle(PillButtonStyle())
        }
    }

    private var deniedNote: some View {
        VStack(alignment: .leading, spacing: DSSpace.m) {
            Text("Notifications are off, so reminders can't fire. Turn them on in Settings.")
                .font(.dsBody)
                .foregroundStyle(Color.dsInkSecondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(PillButtonStyle(.quiet))
        }
        .padding(DSSpace.m)
        .background(Color.dsSurface, in: .rect(cornerRadius: DSRadius.control, style: .continuous))
    }
}

#Preview {
    RemindersSheet()
        .dsTheme(.groove)
}
