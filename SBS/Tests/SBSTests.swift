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
        XCTAssertEqual(try XCTUnwrap(BookooProtocol.reading(from: frame)?.timer), 123.456, accuracy: 0.0001)
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

    /// Scale A in SBS 2026-11-01T04-40-12.csv: a tap on a settled cup, with
    /// the Bookoo's own flow swinging for half a second after it.
    func testFlowComesFromTheCleanedWeight() throws {
        let recorder = Recorder(scales: ScaleManager(defaults: UserDefaults(suiteName: #function)!))
        recorder.start()
        let settled = Date.now.addingTimeInterval(1)
        let readings: [(t: Double, grams: Double, flow: Double)] = [
            (23.0, 269.9, 0), (23.1, 269.9, 0), (23.2, 269.9, 0), (23.3, 269.9, 0), (23.4, 269.9, 0),
            (23.5, 269.9, 0), (23.6, 269.9, -0.02), (23.7, 269.9, -0.05), (23.8, 269.9, -0.07),
            (23.9, 270.4, 0.52), (24.0, 274.2, 8.17), (24.1, 279.7, 28.06), (24.2, 274.1, 21.51),
            (24.3, 270.6, -3.68), (24.4, 269.9, -27.49), (24.5, 269.9, -21.12), (24.6, 269.9, -5.63),
        ]
        for r in readings {
            recorder.ingest(ScaleReading(grams: r.grams, flow: r.flow, battery: 80, timer: r.t), from: .a, at: settled)
        }
        let run = try XCTUnwrap(recorder.stop())
        // From 23.6 s: earlier samples measure against the run's 0 g origin.
        let flows = run.a.filter { $0.t >= 23.6 }.map(\.flow)
        XCTAssertLessThan(try XCTUnwrap(flows.map(abs).max()), 2, "\(flows)")
    }

    func testScreenStaysAwakeOnlyDuringARun() {
        let recorder = Recorder(scales: ScaleManager(defaults: UserDefaults(suiteName: #function)!))
        XCTAssertFalse(recorder.keepsScreenAwake)
        recorder.start()
        XCTAssertTrue(recorder.keepsScreenAwake)
        _ = recorder.stop()
        XCTAssertFalse(recorder.keepsScreenAwake)
    }

    func testStopWithoutPourReturnsNil() {
        let recorder = Recorder(scales: ScaleManager(defaults: UserDefaults(suiteName: #function)!))
        recorder.start()
        XCTAssertNil(recorder.stop())
    }

    func testRunSlotsSkipEmptyScales() {
        let hundred = [Sample(t: 0, grams: 100, flow: 0), Sample(t: 10, grams: 100, flow: 0)]
        XCTAssertEqual(Run(date: .now, a: hundred, b: hundred, c: hundred, d: []).slots, [.a, .b, .c])
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
        XCTAssertEqual(run.csv, "scale,label,time_s,grams,flow_g_per_s\nA,,0.000,0.00,0.00\nB,,0.100,1.25,2.00\n")
    }
}
