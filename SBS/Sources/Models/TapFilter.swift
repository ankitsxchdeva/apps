import Foundation

/// Removes accidental taps on a scale: a jump well above where the curve was
/// heading that comes back to that path within a second. Taps ramp up and
/// down over a few samples, so only the peak has to clear `rise`. Real
/// pours that jump and stay up are left alone.
enum TapFilter {
    /// How far above the curve's path a tap's peak has to reach, in grams.
    /// Light taps on a real Bookoo peaked at 4.4 g; a pour never goes up and
    /// then back down, so this can sit low.
    static let rise = 3.0
    /// Within this of the path counts as on it, in grams.
    static let tolerance = 2.0
    /// The longest a tap can last, in seconds.
    static let window = 1.0
    /// How much history sets the curve's path, in seconds.
    static let trendSpan = 0.5

    /// If the newest sample ends a tap, the tap's samples are redrawn as a
    /// straight line from just before it to the newest sample. Run after
    /// every append.
    static func smoothed(_ samples: [Sample]) -> [Sample] {
        guard samples.count >= 3, let last = samples.last else { return samples }
        let end = samples.count - 1
        // Try each possible start of a tap, latest first.
        var start = end - 1
        while start >= 1, last.t - samples[start].t <= window {
            let base = samples[start - 1]
            let slope = slope(before: start, in: samples)
            func path(_ t: Double) -> Double { base.grams + slope * (t - base.t) }
            let tap = samples[start..<end]
            if tap.allSatisfy({ $0.grams > path($0.t) + tolerance }),
               tap.contains(where: { $0.grams >= path($0.t) + rise }),
               abs(last.grams - path(last.t)) <= tolerance {
                var smoothed = samples
                for i in start..<end {
                    let f = (samples[i].t - base.t) / (last.t - base.t)
                    smoothed[i].grams = base.grams + f * (last.grams - base.grams)
                    smoothed[i].flow = base.flow + f * (last.flow - base.flow)
                }
                return smoothed
            }
            start -= 1
        }
        return samples
    }

    /// Grams per second over the `trendSpan` before `index`.
    private static func slope(before index: Int, in samples: [Sample]) -> Double {
        let base = samples[index - 1]
        guard let from = samples[..<index].last(where: { base.t - $0.t >= trendSpan }) ?? samples.first,
              base.t > from.t else { return 0 }
        return (base.grams - from.grams) / (base.t - from.t)
    }
}
