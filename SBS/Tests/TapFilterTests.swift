import XCTest
@testable import SBS

final class TapFilterTests: XCTestCase {
    /// Feeds samples one at a time, the way the recorder does.
    private func record(_ grams: [Double], step: Double = 0.1) -> [Sample] {
        var samples: [Sample] = []
        for (i, g) in grams.enumerated() {
            samples.append(Sample(t: Double(i) * step, grams: g, flow: 5))
            samples = TapFilter.smoothed(samples)
        }
        return samples
    }

    /// 5 g/s at 10 Hz: 0.5 g per sample.
    private func pour(_ count: Int) -> [Double] { (0..<count).map { Double($0) * 0.5 } }

    func testTapDuringPourBecomesAStraightLine() {
        var grams = pour(30)
        for i in 20...22 { grams[i] += 40 }
        let samples = record(grams)
        for i in 20...22 {
            XCTAssertEqual(samples[i].grams, Double(i) * 0.5, accuracy: 0.01, "sample \(i)")
        }
        XCTAssertEqual(samples.map(\.grams).max(), 14.5)
    }

    func testTapAfterPourSettles() {
        let samples = record(Array(repeating: 100, count: 10) + [108] + Array(repeating: 100, count: 5))
        XCTAssertEqual(samples.map(\.grams).max(), 100)
    }

    // From a real run on two Bookoos (SBS 2026-11-01T04-40-12.csv): taps
    // ramp up and down over a few samples, so only the peak clears 5 g.

    func testRealTapWithRampsIsRemoved() {
        let samples = record([269.9, 269.9, 269.9, 269.9, 269.9, 269.9, 270.4, 274.2, 279.7, 274.1, 270.6, 269.9, 269.9])
        XCTAssertLessThan(samples.map(\.grams).max()!, 271)
    }

    func testRealDoubleBumpTapIsRemoved() {
        let samples = record([267.4, 267.4, 267.4, 267.4, 267.4, 267.4, 271.1, 284.79, 280.6, 270.5, 267.5, 267.29])
        XCTAssertLessThan(samples.map(\.grams).max()!, 268)
    }

    func testPressingTheTimerButtonAtTheStartIsRemoved() {
        // The origin sample, then the press of the scale's own timer button.
        let samples = record([0, 24.3, 17.2, 4.5, 0.3, -0.1, 0, 0])
        XCTAssertLessThan(samples.map(\.grams).max()!, 0.5)
    }

    func testRealLightTapIsRemoved() {
        let samples = record([267.4, 267.4, 267.4, 267.4, 267.4, 267.4, 271.5, 271.64, 271.79, 268.1, 267.4, 267.29])
        // 268.1 is where it lands back within tolerance; the plateau is gone.
        XCTAssertLessThan(samples.map(\.grams).max()!, 268.5)
    }

    func testRealFastPourIsKept() {
        // A bloom pour: 0 to 135 g in half a second, then it stays.
        let grams = [0, 0, 0, 0, 0, 0, 3.2, 27, 80.69, 119.1, 134.5, 135, 135.2, 135.2, 135.2]
        XCTAssertEqual(record(grams).map(\.grams), grams)
    }

    func testRealJumpThatStaysUpIsKept() {
        let grams = Array(repeating: 50.0, count: 10) + Array(repeating: 60.0, count: 15)
        XCTAssertEqual(record(grams).map(\.grams), grams)
    }

    func testSmallBumpIsKept() {
        let grams = Array(repeating: 50.0, count: 10) + [52.5] + Array(repeating: 50.0, count: 5)
        XCTAssertEqual(record(grams).map(\.grams), grams)
    }

    func testSpikeThatTakesLongerThanASecondIsKept() {
        let grams = Array(repeating: 50.0, count: 10) + Array(repeating: 70.0, count: 12) + Array(repeating: 50.0, count: 3)
        XCTAssertEqual(record(grams).map(\.grams), grams)
    }
}
