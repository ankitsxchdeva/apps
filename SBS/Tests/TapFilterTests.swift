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

    func testRealJumpThatStaysUpIsKept() {
        let grams = Array(repeating: 50.0, count: 10) + Array(repeating: 60.0, count: 15)
        XCTAssertEqual(record(grams).map(\.grams), grams)
    }

    func testSmallBumpIsKept() {
        let grams = Array(repeating: 50.0, count: 10) + [53] + Array(repeating: 50.0, count: 5)
        XCTAssertEqual(record(grams).map(\.grams), grams)
    }

    func testSpikeThatTakesLongerThanASecondIsKept() {
        let grams = Array(repeating: 50.0, count: 10) + Array(repeating: 70.0, count: 12) + Array(repeating: 50.0, count: 3)
        XCTAssertEqual(record(grams).map(\.grams), grams)
    }
}
