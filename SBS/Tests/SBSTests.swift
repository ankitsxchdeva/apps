import XCTest
@testable import SBS

final class BookooProtocolTests: XCTestCase {
    /// Frames copied from Bookoo's published command table.
    func testCommandFramesMatchSpec() {
        XCTAssertEqual(BookooProtocol.frame(.tare), [0x03, 0x0A, 0x01, 0x00, 0x00, 0x08])
        XCTAssertEqual(BookooProtocol.frame(.startTimer), [0x03, 0x0A, 0x04, 0x00, 0x00, 0x0D])
        XCTAssertEqual(BookooProtocol.frame(.stopTimer), [0x03, 0x0A, 0x05, 0x00, 0x00, 0x0C])
        XCTAssertEqual(BookooProtocol.frame(.resetTimer), [0x03, 0x0A, 0x06, 0x00, 0x00, 0x0F])
        XCTAssertEqual(BookooProtocol.frame(.tareAndStartTimer), [0x03, 0x0A, 0x07, 0x00, 0x00, 0x0E])
    }

    func testDecodesWeightFrame() {
        let frame = weightFrame(sign: 0x2B, weight: 12345, flowSign: 0x2B, flow: 420, battery: 82)
        XCTAssertEqual(BookooProtocol.reading(from: frame), ScaleReading(grams: 123.45, flow: 4.2, battery: 82, timer: 5))
    }

    func testDecodesTimerHighByteFirst() throws {
        var frame = weightFrame(sign: 0x2B, weight: 0, flowSign: 0x2B, flow: 0, battery: 50)
        frame[2...4] = [0x01, 0xE2, 0x40]  // 123456 ms
        frame[19] = BookooProtocol.checksum(frame[0..<19])
        XCTAssertEqual(try XCTUnwrap(BookooProtocol.reading(from: frame)).timer, 123.456, accuracy: 0.0001)
    }

    func testNegativeSign() {
        let frame = weightFrame(sign: 0x2D, weight: 150, flowSign: 0x2D, flow: 30, battery: 50)
        XCTAssertEqual(BookooProtocol.reading(from: frame), ScaleReading(grams: -1.5, flow: -0.3, battery: 50, timer: 5))
    }

    func testRejectsBadChecksumWrongTypeAndLength() {
        var frame = weightFrame(sign: 0x2B, weight: 100, flowSign: 0x2B, flow: 0, battery: 50)
        frame[19] ^= 0xFF
        XCTAssertNil(BookooProtocol.reading(from: frame))

        var other = weightFrame(sign: 0x2B, weight: 100, flowSign: 0x2B, flow: 0, battery: 50)
        other[1] = 0x0F
        other[19] = BookooProtocol.checksum(other[0..<19])
        XCTAssertNil(BookooProtocol.reading(from: other))

        XCTAssertNil(BookooProtocol.reading(from: [0x03, 0x0B]))
    }

    private func weightFrame(sign: UInt8, weight: Int, flowSign: UInt8, flow: Int, battery: UInt8) -> [UInt8] {
        var f: [UInt8] = [0x03, 0x0B, 0x00, 0x13, 0x88, 0x01, sign,
                          UInt8(weight >> 16 & 0xFF), UInt8(weight >> 8 & 0xFF), UInt8(weight & 0xFF),
                          flowSign, UInt8(flow >> 8 & 0xFF), UInt8(flow & 0xFF),
                          battery, 0x00, 0x32, 0x03, 0x01, 0x00]
        f.append(BookooProtocol.checksum(f))
        return f
    }
}

final class PourStatsTests: XCTestCase {
    func testStatsForSteadyPour() throws {
        // 0 g at 0 s, then 5 g/s from 1 s to 21 s (100 g), then settled.
        var samples = [Sample(t: 0, grams: 0, flow: 0)]
        for i in 0...20 {
            samples.append(Sample(t: 1 + Double(i), grams: Double(i) * 5, flow: 5))
        }
        samples.append(Sample(t: 25, grams: 100, flow: 0))
        let stats = try XCTUnwrap(PourStats(samples))
        XCTAssertEqual(stats.finalGrams, 100)
        XCTAssertEqual(stats.peakFlow, 5)
        // First ≥ 1 g is 5 g at t=2; first ≥ 99 g is 100 g at t=21.
        XCTAssertEqual(try XCTUnwrap(stats.pourTime), 19, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stats.averageFlow), 5, accuracy: 0.001)
    }

    func testNoPourHasNoTime() throws {
        let stats = try XCTUnwrap(PourStats([Sample(t: 0, grams: 0, flow: 0), Sample(t: 3, grams: 0.4, flow: 0)]))
        XCTAssertNil(stats.pourTime)
        XCTAssertNil(stats.averageFlow)
        XCTAssertNil(PourStats([]))
    }
}

final class RecorderTests: XCTestCase {
    func testEachScaleIsTimedByItsOwnTimer() throws {
        let recorder = Recorder(scales: ScaleManager(defaults: UserDefaults(suiteName: #function)!))
        recorder.start()
        let reset = Date.now
        func reading(_ grams: Double, timer: Double) -> ScaleReading {
            ScaleReading(grams: grams, flow: 1, battery: 80, timer: timer)
        }

        // The previous run's timer, still arriving before the reset lands: ignored.
        recorder.ingest(reading(50, timer: 30), from: .a, at: reset.addingTimeInterval(0.2))
        XCTAssertEqual(recorder.phase, .waiting)

        // Settled, timers not started yet: still waiting.
        recorder.ingest(reading(0, timer: 0), from: .a, at: reset.addingTimeInterval(1))
        XCTAssertEqual(recorder.phase, .waiting)

        // A's timer starts; B's hasn't, so B records nothing yet.
        recorder.ingest(reading(2, timer: 0.5), from: .a, at: reset.addingTimeInterval(2))
        XCTAssertEqual(recorder.phase, .recording)
        recorder.ingest(reading(0, timer: 0), from: .b, at: reset.addingTimeInterval(2.1))

        // B started 2 s later, but its curve still begins at its own zero.
        recorder.ingest(reading(1.5, timer: 0.3), from: .b, at: reset.addingTimeInterval(4.3))
        recorder.ingest(reading(9, timer: 2.5), from: .a, at: reset.addingTimeInterval(4.4))
        // A's timer stopped: repeated time adds nothing.
        recorder.ingest(reading(9.2, timer: 2.5), from: .a, at: reset.addingTimeInterval(4.5))

        let run = try XCTUnwrap(recorder.stop())
        XCTAssertEqual(run.a.map(\.t), [0, 0.5, 2.5])
        XCTAssertEqual(run.a.map(\.grams), [0, 2, 9])
        XCTAssertEqual(run.b.map(\.t), [0, 0.3])
        XCTAssertEqual(recorder.phase, .idle)
    }

    func testStopWithoutPourReturnsNil() {
        let recorder = Recorder(scales: ScaleManager(defaults: UserDefaults(suiteName: #function)!))
        recorder.start()
        XCTAssertNil(recorder.stop())
    }

    func testMatchScore() {
        func run(_ a: [Sample], _ b: [Sample]) -> Run { Run(date: .now, a: a, b: b) }
        let hundred = [Sample(t: 0, grams: 100, flow: 0), Sample(t: 10, grams: 100, flow: 0)]
        let ninety = [Sample(t: 0, grams: 90, flow: 0), Sample(t: 10, grams: 90, flow: 0)]
        let zero = [Sample(t: 0, grams: 0, flow: 0), Sample(t: 10, grams: 0.5, flow: 0)]

        XCTAssertEqual(run(hundred, hundred).matchScore(.b), 100)
        // Off by 10% the whole way: 100 − 2 × 10.
        XCTAssertEqual(run(hundred, ninety).matchScore(.b), 80)
        XCTAssertEqual(run(ninety, hundred).matchScore(.b), 80)
        // Nothing poured on B: no score, not zero.
        XCTAssertNil(run(hundred, zero).matchScore(.b))
        XCTAssertNil(run(hundred, []).matchScore(.b))
        // Extra scales are each scored against A.
        let four = Run(date: .now, a: hundred, b: hundred, c: ninety, d: [])
        XCTAssertEqual(four.matchScore(.c), 80)
        XCTAssertNil(four.matchScore(.d))
        XCTAssertEqual(four.slots, [.a, .b, .c])
        // B starts 5 s late: 100 g apart on 50 of the 101 grid points, so
        // the average gap is 49.5% → 100 − 99.
        let late = [Sample(t: 0, grams: 0, flow: 0), Sample(t: 4.95, grams: 0, flow: 0),
                    Sample(t: 5, grams: 100, flow: 0), Sample(t: 10, grams: 100, flow: 0)]
        XCTAssertEqual(run(hundred, late).matchScore(.b), 1)
    }

    func testDecodesRunsSavedWithTwoScales() throws {
        let json = #"{"id":"6B1C1A2E-3D4F-4A5B-8C6D-7E8F9A0B1C2D","date":0,"note":"old","a":[{"t":0,"grams":0,"flow":0}],"b":[]}"#
        let run = try JSONDecoder().decode(Run.self, from: Data(json.utf8))
        XCTAssertEqual(run.note, "old")
        XCTAssertEqual(run.a.count, 1)
        XCTAssertEqual(run.c, [])
        XCTAssertEqual(run.d, [])
    }

    func testRecordsOptionalThirdScale() throws {
        let recorder = Recorder(scales: ScaleManager(defaults: UserDefaults(suiteName: #function)!))
        recorder.start()
        let settled = Date.now.addingTimeInterval(1)
        recorder.ingest(ScaleReading(grams: 2, flow: 1, battery: 80, timer: 0.4), from: .a, at: settled)
        recorder.ingest(ScaleReading(grams: 1, flow: 1, battery: 80, timer: 0.2), from: .c, at: settled)
        let run = try XCTUnwrap(recorder.stop())
        XCTAssertEqual(run.c.map(\.t), [0, 0.2])
        XCTAssertEqual(run.slots, [.a, .c])
    }

    func testCSVIsLongFormat() {
        let run = Run(date: .now, a: [Sample(t: 0, grams: 0, flow: 0)], b: [Sample(t: 0.1, grams: 1.25, flow: 2)])
        XCTAssertEqual(run.csv, "scale,time_s,grams,flow_g_per_s\nA,0.000,0.00,0.00\nB,0.100,1.25,2.00\n")
    }
}
