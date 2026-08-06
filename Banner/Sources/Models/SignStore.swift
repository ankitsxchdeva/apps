import Foundation
import Observation

/// Saved banners, newest first, stored as Codable JSON in UserDefaults.
@Observable
final class SignStore {
    static let shared = SignStore()

    /// Enough to find last night's banner, few enough to scan at a glance.
    static let limit = 8

    private(set) var saved: [Sign] = []

    private let defaults: UserDefaults
    private enum Key {
        static let saved = "savedBanners"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// The banner the editor opens with: whatever was shown last.
    var mostRecent: Sign? { saved.first }

    /// Showing a banner saves it. Same text as an existing one replaces it and
    /// moves it to the front, so re-showing never grows the list.
    func remember(_ sign: Sign) {
        saved.removeAll { $0.id == sign.id || $0.trimmedText.caseInsensitiveCompare(sign.trimmedText) == .orderedSame }
        saved.insert(sign, at: 0)
        if saved.count > Self.limit {
            saved.removeLast(saved.count - Self.limit)
        }
        save()
    }

    func delete(_ sign: Sign) {
        saved.removeAll { $0.id == sign.id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Key.saved),
              let decoded = try? JSONDecoder().decode([Sign].self, from: data) else { return }
        saved = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: Key.saved)
    }
}
