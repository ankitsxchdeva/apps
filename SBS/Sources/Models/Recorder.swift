import Foundation
import Observation

/// Turns the live reading streams into one run. Tare and reset every scale, then
/// record each scale from the moment its own timer starts, timed by that
/// timer — so one person can start the second pour a few seconds later.
/// Scales without a timer start their own clock at their first pour instead.
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
    /// Recorded flow is the weight gained over this much time, in seconds.
    static let flowSpan: TimeInterval = 0.5

    private(set) var phase: Phase = .idle
    private(set) var run = Run(date: .now)

    /// From tare to stop, so the phone doesn't dim or lock mid-pour.
    var keepsScreenAwake: Bool { phase != .idle }

    @ObservationIgnored private var taredAt = Date.distantPast
    /// When each timer-less scale first saw a pour.
    @ObservationIgnored private var pourStarts: [Slot: Date] = [:]
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
        pourStarts = [:]
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
              let t = time(of: reading, from: slot, at: now) else { return }
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
        if reading.timer != nil, t <= samples.last!.t { return }
        samples.append(Sample(t: t, grams: reading.grams, flow: 0))
        samples = TapFilter.smoothed(samples)
        // Flow from the cleaned weights, not the scale: its own flow swings
        // for a while after a tap. A tap can redraw up to `window` back.
        for i in samples.indices.dropFirst() where samples[i].t >= t - TapFilter.window {
            samples[i].flow = Self.flow(at: i, in: samples)
        }
        run.setSamples(samples, for: slot)
    }

    /// Grams per second over the `flowSpan` before sample `i`.
    private static func flow(at i: Int, in samples: [Sample]) -> Double {
        let from = samples[..<i].last { samples[i].t - $0.t >= flowSpan } ?? samples[0]
        let elapsed = samples[i].t - from.t
        return elapsed > 0 ? (samples[i].grams - from.grams) / elapsed : 0
    }

    /// The scale's own timer once it's running, or seconds since this scale's
    /// first pour. Nil until then.
    private func time(of reading: ScaleReading, from slot: Slot, at now: Date) -> TimeInterval? {
        if let timer = reading.timer {
            return timer > 0 ? timer : nil
        }
        if let start = pourStarts[slot] {
            return now.timeIntervalSince(start)
        }
        guard reading.grams >= PourStats.threshold else { return nil }
        pourStarts[slot] = now
        return 0
    }
}
