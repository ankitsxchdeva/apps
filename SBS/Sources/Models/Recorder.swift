import Foundation
import Observation

/// Turns two live reading streams into one run. Tare both, wait for the first
/// pour on either scale, then record both against that shared zero.
@Observable
final class Recorder {
    enum Phase: Equatable {
        case idle
        /// Tared; the clock starts at the first pour.
        case waiting
        case recording(start: Date)
    }

    /// Readings right after a tare can still carry the old weight.
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
        scales.tareBoth()
    }

    /// The finished run, or nil if nothing was poured.
    func stop() -> Run? {
        defer { phase = .idle }
        guard case .recording = phase else { return nil }
        return run
    }

    func ingest(_ reading: ScaleReading, from slot: Slot, at now: Date) {
        switch phase {
        case .idle:
            return
        case .waiting:
            guard now.timeIntervalSince(taredAt) >= Self.tareSettle,
                  reading.grams >= PourStats.threshold else { return }
            run.date = now
            // Both curves begin at the origin, so the chart reads "from zero".
            run.a = [Sample(t: 0, grams: 0, flow: 0)]
            run.b = [Sample(t: 0, grams: 0, flow: 0)]
            phase = .recording(start: now)
            append(reading, to: slot, start: now, now: now)
        case .recording(let start):
            append(reading, to: slot, start: start, now: now)
        }
    }

    private func append(_ reading: ScaleReading, to slot: Slot, start: Date, now: Date) {
        let sample = Sample(t: now.timeIntervalSince(start), grams: reading.grams, flow: reading.flow)
        switch slot {
        case .a: run.a.append(sample)
        case .b: run.b.append(sample)
        }
    }
}
