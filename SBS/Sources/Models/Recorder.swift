import Foundation
import Observation

/// Turns the live reading streams into one run. Tare and reset every scale, then
/// record each scale from the moment its own timer starts, timed by that
/// timer — so one person can start the second pour a few seconds later.
@Observable
final class Recorder {
    enum Phase: Equatable {
        case idle
        /// Tared and reset; recording starts with any scale's timer.
        case waiting
        case recording
    }

    /// Readings right after a tare can still carry the old weight and timer.
    static let tareSettle: TimeInterval = 0.8

    private(set) var phase: Phase = .idle
    private(set) var run = Run(date: .now)

    @ObservationIgnored private var taredAt = Date.distantPast
    @ObservationIgnored private let scales: ScaleManager

    init(scales: ScaleManager) {
        self.scales = scales
        scales.onReading = { [weak self] slot, reading in
            self?.ingest(reading, from: slot, at: .now)
        }
    }

    func start() {
        run = Run(date: .now)
        taredAt = .now
        phase = .waiting
        scales.tareAndResetAll()
    }

    /// The finished run, or nil if nothing was poured.
    func stop() -> Run? {
        defer { phase = .idle }
        guard phase == .recording else { return nil }
        return run
    }

    func ingest(_ reading: ScaleReading, from slot: Slot, at now: Date) {
        guard phase != .idle,
              now.timeIntervalSince(taredAt) >= Self.tareSettle,
              reading.timer > 0 else { return }
        if phase == .waiting {
            run.date = now
            phase = .recording
        }
        var samples = run.samples(slot)
        // Each curve begins at the origin, so the chart reads "from zero".
        if samples.isEmpty {
            samples = [Sample(t: 0, grams: 0, flow: 0)]
        }
        // A stopped timer keeps repeating its last time; skip those.
        guard reading.timer > samples.last!.t else { return }
        samples.append(Sample(t: reading.timer, grams: reading.grams, flow: reading.flow))
        run.setSamples(samples, for: slot)
    }
}
