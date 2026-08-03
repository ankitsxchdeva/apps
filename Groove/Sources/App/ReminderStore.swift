import Foundation
import Observation
import UserNotifications

/// A daily reminder time.
struct ReminderTime: Identifiable, Codable, Hashable {
    var id: UUID
    var hour: Int
    var minute: Int

    init(id: UUID = UUID(), hour: Int, minute: Int) {
        self.id = id
        self.hour = hour
        self.minute = minute
    }

    var date: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}

/// Reminder times live in the app group so they survive relaunch;
/// notifications are rescheduled on every change.
@MainActor
@Observable
final class ReminderStore {
    private(set) var times: [ReminderTime] = []
    private(set) var authorizationDenied = false

    private let defaults: UserDefaults
    private static let key = "reminderTimes"

    init() {
        defaults = UserDefaults(suiteName: GrooveStore.appGroupID) ?? .standard
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([ReminderTime].self, from: data) {
            times = decoded
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationDenied = settings.authorizationStatus == .denied
    }

    func add(_ date: Date) async {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let time = ReminderTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        // A second reminder at the same time would just fire twice.
        guard !times.contains(where: { $0.hour == time.hour && $0.minute == time.minute }) else { return }
        // Ask only when the first time is added.
        if times.isEmpty {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            authorizationDenied = !granted
        }
        times.append(time)
        times.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        persist()
        await reschedule()
    }

    func remove(_ time: ReminderTime) async {
        times.removeAll { $0.id == time.id }
        persist()
        await reschedule()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(times) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Drops every pending reminder and schedules one repeating daily trigger per time.
    func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix("reminder-") }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for time in times {
            let content = UNMutableNotificationContent()
            content.title = "Time for a set"
            content.body = "Push-ups, squats or a stretch — pick one, 30 seconds."
            content.sound = .default

            var components = DateComponents()
            components.hour = time.hour
            components.minute = time.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "reminder-\(time.id.uuidString)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }
}
