import SwiftUI
import DesignSystem

/// The places a scale can sit, in reading order. A and B are required; C and
/// D are optional extras. A is the reference every other scale is scored against.
enum Slot: String, Codable, CodingKeyRepresentable, CaseIterable, Identifiable {
    case a, b, c, d

    var id: String { rawValue }
    var name: String { rawValue.uppercased() }
    var isOptional: Bool { self == .c || self == .d }

    /// Series identity in every chart and card. Validated as a set of four,
    /// all pairs, for colorblind separation in light and dark.
    var color: Color {
        switch self {
        case .a: Color(light: 0x2F6FDB, dark: 0x5B93F0)
        case .b: Color(light: 0xC7651A, dark: 0xD27A2C)
        case .c: Color(light: 0x0F8A6A, dark: 0x199E70)
        case .d: Color(light: 0xC766B0, dark: 0xC766B0)
        }
    }
}

struct Sample: Codable, Equatable {
    /// Seconds on this scale's own timer.
    var t: Double
    var grams: Double
    var flow: Double
}

/// One side-by-side test: each scale recorded on its own timer, so both
/// curves start at zero even when the pours start seconds apart.
struct Run: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var note = ""
    /// What each scale was testing, as labelled when the run started.
    var labels: [Slot: String] = [:]
    var a: [Sample] = []
    var b: [Sample] = []
    var c: [Sample] = []
    var d: [Sample] = []

    func samples(_ slot: Slot) -> [Sample] {
        switch slot {
        case .a: a
        case .b: b
        case .c: c
        case .d: d
        }
    }

    mutating func setSamples(_ samples: [Sample], for slot: Slot) {
        switch slot {
        case .a: a = samples
        case .b: b = samples
        case .c: c = samples
        case .d: d = samples
        }
    }

    /// The scales that recorded anything.
    var slots: [Slot] {
        Slot.allCases.filter { !samples($0).isEmpty }
    }

    /// "A · V60", or just "A" when unlabelled.
    func seriesName(_ slot: Slot) -> String {
        labels[slot].map { "\(slot.name) · \($0)" } ?? slot.name
    }

    var duration: Double {
        Slot.allCases.compactMap { samples($0).last?.t }.max() ?? 0
    }

    var title: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? date.formatted(date: .abbreviated, time: .shortened)
            : note
    }

    /// Long format — one row per sample — so the two scales' independent
    /// timestamps survive intact.
    var csv: String {
        var rows = ["scale,label,time_s,grams,flow_g_per_s"]
        for slot in Slot.allCases {
            // Quoted only when needed, with inner quotes doubled.
            let label = labels[slot].map { $0.contains(where: { ",\"\n".contains($0) })
                ? "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : $0 } ?? ""
            for s in samples(slot) {
                rows.append(String(format: "%@,%@,%.3f,%.2f,%.2f", slot.name, label, s.t, s.grams, s.flow))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// How closely one scale's pour tracked A's, each 0–100.
    struct Match: Equatable {
        /// 70% curve, 30% flow.
        var score: Int
        /// The weight curves: the average gap, as a share of the larger final
        /// weight, costs three points per percent.
        var curve: Int
        /// The pace: the average gap in flow during the pour, as a share of the
        /// average flow, costs one and a half points per percent.
        var flow: Int
    }

    /// Gaps this small are the scales' own noise and 0.1 g steps, so a
    /// machine-level repeat scores 99–100 and nothing a person does can.
    static let weightNoise = 0.3, flowNoise = 0.2
    /// Flow here is the weight gained over this many seconds, for both scales.
    static let matchFlowSpan = 2.0

    /// Nil when either scale saw no real pour.
    func match(_ slot: Slot) -> Match? {
        let other = samples(slot)
        guard let finalA = a.last?.grams, let finalB = other.last?.grams else { return nil }
        let reference = max(finalA, finalB)
        guard min(finalA, finalB) > PourStats.threshold * 2 else { return nil }

        // Both curves on one 0.1 s grid.
        let step = 0.1
        let points = Int((max(a.last?.t ?? 0, other.last?.t ?? 0) / step).rounded()) + 1
        var cursorA = Cursor(samples: a), cursorB = Cursor(samples: other)
        var weightsA: [Double] = [], weightsB: [Double] = []
        for i in 0..<points {
            weightsA.append(cursorA.grams(at: Double(i) * step))
            weightsB.append(cursorB.grams(at: Double(i) * step))
        }

        let weightGap = zip(weightsA, weightsB).reduce(0) { $0 + max(0, abs($1.0 - $1.1) - Self.weightNoise) }
        let curve = max(0, 100 - 3 * weightGap / Double(points) / reference * 100)

        // From either scale starting until both have about finished.
        let span = Int(Self.matchFlowSpan / step)
        func flow(_ weights: [Double], _ i: Int) -> Double {
            let back = max(1, min(i, span))
            return (weights[i] - weights[max(0, i - back)]) / (Double(back) * step)
        }
        let pour = (0..<points).filter {
            max(weightsA[$0], weightsB[$0]) >= PourStats.threshold
                && min(weightsA[$0], weightsB[$0]) < reference - PourStats.threshold
        }
        var pace = 100.0
        if !pour.isEmpty {
            let averageFlow = reference / (Double(pour.count) * step)
            let flowGap = pour.reduce(0) { $0 + max(0, abs(flow(weightsA, $1) - flow(weightsB, $1)) - Self.flowNoise) }
            pace = max(0, 100 - 1.5 * flowGap / Double(pour.count) / averageFlow * 100)
        }
        // Rounded down, so 100 means no measurable difference at all.
        return Match(score: Int(0.7 * curve + 0.3 * pace), curve: Int(curve), flow: Int(pace))
    }

    /// Walks forward through samples: the last reading at or before `t`,
    /// i.e. what the scale showed then. `t` must not decrease between calls.
    private struct Cursor {
        let samples: [Sample]
        var index = 0
        var current = 0.0

        mutating func grams(at t: Double) -> Double {
            while index < samples.count, samples[index].t <= t + 1e-9 {
                current = samples[index].grams
                index += 1
            }
            return current
        }
    }
}

extension Run {
    /// Runs saved before C and D existed have no "c" or "d" key, and those
    /// saved before labels have no "labels".
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        note = try container.decode(String.self, forKey: .note)
        labels = try container.decodeIfPresent([Slot: String].self, forKey: .labels) ?? [:]
        a = try container.decode([Sample].self, forKey: .a)
        b = try container.decode([Sample].self, forKey: .b)
        c = try container.decodeIfPresent([Sample].self, forKey: .c) ?? []
        d = try container.decodeIfPresent([Sample].self, forKey: .d) ?? []
    }
}

extension TimeInterval {
    /// "1:05.3" — minutes, then seconds to a tenth.
    var clockText: String {
        let seconds = Swift.max(0, self)
        let minutes = Int(seconds) / 60
        return String(format: "%d:%04.1f", minutes, seconds - Double(minutes * 60))
    }
}

/// What a pour did, reduced to the numbers worth comparing.
struct PourStats: Equatable {
    /// Weight where the pour counts as started, and the margin under the final
    /// weight where it counts as finished. Ignores drips and settling noise.
    static let threshold = 1.0

    var finalGrams: Double
    /// From first crossing the threshold to first coming within it of final.
    var pourTime: Double?
    var averageFlow: Double?
    var peakFlow: Double

    init?(_ samples: [Sample]) {
        guard let last = samples.last else { return nil }
        finalGrams = last.grams
        peakFlow = samples.map(\.flow).max() ?? 0
        if finalGrams > Self.threshold * 2,
           let start = samples.first(where: { $0.grams >= Self.threshold }),
           let end = samples.first(where: { $0.grams >= last.grams - Self.threshold }),
           end.t > start.t {
            pourTime = end.t - start.t
            averageFlow = (end.grams - start.grams) / (end.t - start.t)
        }
    }
}
