import SwiftUI
import DesignSystem

/// The two places a scale can sit. A is always left, B always right.
enum Slot: String, Codable, CaseIterable, Identifiable {
    case a, b

    var id: String { rawValue }
    var name: String { rawValue.uppercased() }

    /// Series identity in every chart and card. Validated as a pair for
    /// colorblind separation in light and dark.
    var color: Color {
        switch self {
        case .a: Color(light: 0x2F6FDB, dark: 0x5B93F0)
        case .b: Color(light: 0xC7651A, dark: 0xD27A2C)
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
    var a: [Sample] = []
    var b: [Sample] = []

    func samples(_ slot: Slot) -> [Sample] {
        slot == .a ? a : b
    }

    var duration: Double {
        max(a.last?.t ?? 0, b.last?.t ?? 0)
    }

    var title: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? date.formatted(date: .abbreviated, time: .shortened)
            : note
    }

    /// Long format — one row per sample — so the two scales' independent
    /// timestamps survive intact.
    var csv: String {
        var rows = ["scale,time_s,grams,flow_g_per_s"]
        for slot in Slot.allCases {
            for s in samples(slot) {
                rows.append(String(format: "%@,%.3f,%.2f,%.2f", slot.name, s.t, s.grams, s.flow))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// How closely the two weight curves tracked each other, 0–100. Both are
    /// sampled every 0.1 s; the average gap, as a share of the larger final
    /// weight, costs two points per percent. 5% apart scores 90, 50% scores 0.
    /// Nil when either scale saw no real pour.
    var matchScore: Int? {
        guard let finalA = a.last?.grams, let finalB = b.last?.grams else { return nil }
        let reference = max(finalA, finalB)
        guard min(finalA, finalB) > PourStats.threshold * 2 else { return nil }

        let step = 0.1
        let points = Int((duration / step).rounded()) + 1
        var cursorA = Cursor(samples: a), cursorB = Cursor(samples: b)
        var gap = 0.0
        for i in 0..<points {
            let t = Double(i) * step
            gap += abs(cursorA.grams(at: t) - cursorB.grams(at: t))
        }
        let percent = gap / Double(points) / reference * 100
        return max(0, Int((100 - 2 * percent).rounded()))
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
