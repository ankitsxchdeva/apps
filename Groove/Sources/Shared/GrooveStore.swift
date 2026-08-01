import Foundation
import Observation
import WidgetKit

/// The single source of truth: movements plus per-day set counts, stored as
/// Codable JSON in the app group so the widget extension reads the same data.
@Observable
final class GrooveStore {
    static let appGroupID = "group.com.ankit.Groove"
    static let shared = GrooveStore()

    private(set) var movements: [Movement] = []
    /// yyyy-MM-dd → movement id string → sets done.
    private(set) var days: [String: [String: Int]] = [:]

    private let defaults: UserDefaults
    private enum Key {
        static let movements = "movements"
        static let days = "dayLogs"
        static let seeded = "didSeedStarters"
    }

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.appGroupID) ?? .standard
        load()
        seedIfNeeded()
    }

    // MARK: - Dates

    static func dateKey(for date: Date = .now) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    var todayKey: String { Self.dateKey() }

    // MARK: - Reading

    func setsDone(for movement: Movement, on key: String? = nil) -> Int {
        days[key ?? todayKey]?[movement.id.uuidString] ?? 0
    }

    /// Sets still to do today, never negative.
    var remainingToday: Int {
        movements.reduce(0) { $0 + max(0, $1.setsPerDay - setsDone(for: $1)) }
    }

    var targetToday: Int {
        movements.reduce(0) { $0 + $1.setsPerDay }
    }

    /// 0…1 progress through today's checklist.
    var progressToday: Double {
        guard targetToday > 0 else { return 0 }
        return Double(targetToday - remainingToday) / Double(targetToday)
    }

    var isTodayComplete: Bool {
        !movements.isEmpty && remainingToday == 0
    }

    func isComplete(on key: String) -> Bool {
        guard !movements.isEmpty else { return false }
        return movements.allSatisfy { setsDone(for: $0, on: key) >= $0.setsPerDay }
    }

    /// Consecutive complete days ending today or yesterday.
    var streak: Int {
        guard !movements.isEmpty else { return 0 }
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: .now)
        if !isComplete(on: Self.dateKey(for: day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while isComplete(on: Self.dateKey(for: day)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    // MARK: - Logging

    /// Logs one set for today. Capped at the movement's target.
    func logSet(_ movement: Movement) {
        let done = setsDone(for: movement)
        guard done < movement.setsPerDay else { return }
        days[todayKey, default: [:]][movement.id.uuidString] = done + 1
        save()
    }

    /// Undo: removes one set from today.
    func removeSet(_ movement: Movement) {
        let done = setsDone(for: movement)
        guard done > 0 else { return }
        days[todayKey, default: [:]][movement.id.uuidString] = done - 1
        save()
    }

    // MARK: - Editing movements

    func add(_ movement: Movement) {
        movements.append(movement)
        save()
    }

    func update(_ movement: Movement) {
        guard let index = movements.firstIndex(where: { $0.id == movement.id }) else { return }
        movements[index] = movement
        save()
    }

    func delete(_ movement: Movement) {
        movements.removeAll { $0.id == movement.id }
        save()
    }

    // MARK: - Persistence

    /// Re-reads from disk, e.g. after a widget logged a set while the app was backgrounded.
    func reload() {
        load()
    }

    private func load() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Key.movements),
           let decoded = try? decoder.decode([Movement].self, from: data) {
            movements = decoded
        }
        if let data = defaults.data(forKey: Key.days),
           let decoded = try? decoder.decode([String: [String: Int]].self, from: data) {
            days = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(movements) {
            defaults.set(data, forKey: Key.movements)
        }
        if let data = try? encoder.encode(days) {
            defaults.set(data, forKey: Key.days)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func seedIfNeeded() {
        guard !defaults.bool(forKey: Key.seeded) else { return }
        defaults.set(true, forKey: Key.seeded)
        guard movements.isEmpty else { return }
        movements = Movement.starters
        save()
    }
}
