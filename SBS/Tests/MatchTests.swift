import XCTest
@testable import SBS

/// Calibrated so only a machine-level repeat reaches 99 or 100: the
/// scale's own 0.1 g steps and timing jitter cost nothing, anything a
/// person would do costs at least a couple of points.
final class MatchTests: XCTestCase {
    /// A bloom then three pulses to ~250 g, sampled at 10 Hz like a Bookoo,
    /// rounded to 0.1 g with a little seeded noise.
    private func pour(rate: Double = 1, late: Double = 0, pulses: [Double] = [5, 4, 4],
                      wobble: Double = 0, jitter: Double = 0, seed: UInt64 = 1) -> [Sample] {
        var rng = seed
        func random() -> Double {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Double(rng >> 11) / Double(1 << 53) * 2 - 1
        }
        let segments = [(0.0, 6.0, 7.5), (30, 30 + 75 / pulses[0], pulses[0] * rate),
                        (50, 50 + 75 / pulses[1], pulses[1] * rate), (70, 70 + 55 / pulses[2], pulses[2] * rate)]
        var samples: [Sample] = [], grams = 0.0
        for i in 0...1000 {
            let t = Double(i) / 10
            let flow = segments.first { t >= $0.0 + late && t < $0.1 + late }.map { $0.2 * (1 + wobble * sin(t * 2.1)) } ?? 0
            grams += flow / 10
            let shown = grams == 0 ? 0 : ((grams + random() * 0.05) * 10).rounded() / 10
            samples.append(Sample(t: i == 0 ? 0 : t + random() * jitter, grams: shown, flow: 0))
        }
        return samples
    }

    private func score(_ b: [Sample]) throws -> Run.Match {
        try XCTUnwrap(Run(date: .now, a: pour(), b: b).match(.b))
    }

    func testOnlyAMachineScores99OrMore() throws {
        XCTAssertEqual(try score(pour()).score, 100)
        XCTAssertGreaterThanOrEqual(try score(pour(jitter: 0.03, seed: 2)).score, 99)
        XCTAssertGreaterThanOrEqual(try score(pour(jitter: 0.05, seed: 3)).score, 99)
        for human in [pour(late: 0.5, seed: 4), pour(rate: 1.05, seed: 5), pour(wobble: 0.25, seed: 6),
                      pour(rate: 1.05, late: 1.5, seed: 7), pour(pulses: [7, 3, 5], seed: 8)] {
            XCTAssertLessThan(try score(human).score, 99)
        }
    }

    func testFlowCountsWhenTheCurvesEndTogether() throws {
        // Same weight at every pulse's end, but poured at a different pace.
        let paced = try score(pour(pulses: [7, 3, 5], seed: 8))
        XCTAssertGreaterThan(paced.curve, 85)
        XCTAssertLessThan(paced.flow, 70)
        XCTAssertLessThan(paced.score, paced.curve)
    }

    func testScoreIsSeventyThirty() throws {
        let m = try score(pour(rate: 1.05, late: 1.5, seed: 7))
        XCTAssertEqual(Double(m.score), 0.7 * Double(m.curve) + 0.3 * Double(m.flow), accuracy: 1)
    }

    func testNoPourHasNoScore() {
        let zero = [Sample(t: 0, grams: 0, flow: 0), Sample(t: 10, grams: 0.5, flow: 0)]
        XCTAssertNil(Run(date: .now, a: pour(), b: zero).match(.b))
        XCTAssertNil(Run(date: .now, a: pour(), b: []).match(.b))
        let four = Run(date: .now, a: pour(), b: pour(), c: pour(rate: 1.05, seed: 5), d: [])
        XCTAssertNotNil(four.match(.c))
        XCTAssertNil(four.match(.d))
    }
}
