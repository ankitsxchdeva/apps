import Foundation
import Observation

/// Saved runs, newest first, as one JSON file in Application Support. A run
/// holds thousands of samples, too many for UserDefaults.
@Observable
final class RunStore {
    static let shared = RunStore()

    private(set) var runs: [Run] = []

    private let url: URL

    init(url: URL = RunStore.defaultURL) {
        self.url = url
        load()
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "runs.json")
    }

    /// Insert or replace by id.
    func save(_ run: Run) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.insert(run, at: 0)
        }
        persist()
    }

    func delete(_ run: Run) {
        runs.removeAll { $0.id == run.id }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Run].self, from: data) else { return }
        runs = decoded
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(runs).write(to: url, options: .atomic)
        } catch {
            assertionFailure("Saving runs failed: \(error)")
        }
    }
}
