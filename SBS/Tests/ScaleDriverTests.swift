import CoreBluetooth
import XCTest
@testable import SBS

/// Frames are built from the byte layouts in each brand's published spec or
/// open-source drivers (see each driver's header). None of these brands has
/// been tried on real hardware yet.
final class ScaleDriverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testMatchesByName() {
        func brand(_ name: String, _ services: [CBUUID] = []) -> String? {
            ScaleDrivers.match(name: name, services: services)?.brand
        }
        XCTAssertEqual(brand("BOOKOO_SC 1234"), "Bookoo")
        XCTAssertEqual(brand("LUNAR-0A1B2C"), "Acaia")
        XCTAssertEqual(brand("PYXIS-123"), "Acaia")
        XCTAssertEqual(brand("FELICITA ARC"), "Felicita")
        XCTAssertEqual(brand("Decent Scale"), "Decent")
        XCTAssertEqual(brand("Varia AKU"), "Varia")
        XCTAssertEqual(brand("Microbalance Ti"), "DiFluid")
        XCTAssertEqual(brand("Anything", [CBUUID(string: "00EE")]), "DiFluid")
        XCTAssertNil(brand("AirPods Pro"))
    }

    func testBookooKeepsItsOwnTimer() throws {
        let driver = BookooDriver(profile: BookooDriver.profiles[0])
        var frame: [UInt8] = [0x03, 0x0B, 0x00, 0x13, 0x88, 0x01, 0x2B, 0x00, 0x30, 0x39,
                              0x2B, 0x01, 0xA4, 82, 0x00, 0x32, 0x03, 0x01, 0x00]
        frame.append(BookooProtocol.checksum(frame))
        let reading = try XCTUnwrap(driver.readings(from: frame, at: now).first)
        XCTAssertEqual(reading.grams, 123.45, accuracy: 0.001)
        XCTAssertEqual(reading.timer, 5)
        XCTAssertEqual(driver.frames(for: .resetTimer), [BookooProtocol.frame(.resetTimer)])
    }

    // MARK: - Acaia

    func testAcaiaWeightSplitAcrossNotifications() throws {
        let driver = AcaiaDriver(profile: AcaiaDriver.profiles[0])
        // Noise, then EF DD 0C len=8 event=05 weight=12345 LE, 2 decimals, flags, checksums.
        let message: [UInt8] = [0xEF, 0xDD, 0x0C, 0x08, 0x05, 0x39, 0x30, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00]
        XCTAssertEqual(driver.readings(from: [0x01] + Array(message[0..<6]), at: now), [])
        let reading = try XCTUnwrap(driver.readings(from: Array(message[6...]), at: now).first)
        XCTAssertEqual(reading.grams, 123.45, accuracy: 0.001)
        XCTAssertNil(reading.timer)
    }

    func testAcaiaNegativeWeight() throws {
        let driver = AcaiaDriver(profile: AcaiaDriver.profiles[0])
        let message: [UInt8] = [0xEF, 0xDD, 0x0C, 0x08, 0x05, 0x0F, 0x00, 0x00, 0x00, 0x01, 0x02, 0x00, 0x00]
        XCTAssertEqual(try XCTUnwrap(driver.readings(from: message, at: now).first).grams, -1.5, accuracy: 0.001)
    }

    func testAcaiaFrames() {
        let legacy = AcaiaDriver(profile: AcaiaDriver.profiles.first { $0.service == CBUUID(string: "1820") }!)
        XCTAssertEqual(legacy.handshake.first, [0xEF, 0xDD, 0x0B] + Array(repeating: 0x2D, count: 15) + [0x68, 0x3B])
        XCTAssertEqual(legacy.handshake.last, [0xEF, 0xDD, 0x0C, 0x09, 0x00, 0x01, 0x01, 0x02, 0x02, 0x05, 0x03, 0x04, 0x15, 0x06])
        XCTAssertEqual(legacy.keepAlive, [0xEF, 0xDD, 0x00, 0x02, 0x00, 0x02, 0x00])
        XCTAssertEqual(legacy.frames(for: .tare), [[0xEF, 0xDD, 0x04, 0x00, 0x00, 0x00]])
        XCTAssertEqual(legacy.frames(for: .resetTimer), [[0xEF, 0xDD, 0x0D, 0x00, 0x01, 0x00, 0x01]])
    }

    // MARK: - Felicita

    func testFelicitaAsciiFrame() throws {
        let driver = FelicitaDriver(profile: FelicitaDriver.profiles[0])
        func frame(_ sign: Character) -> [UInt8] {
            [0x01, 0x02, sign.asciiValue!] + Array("012345".utf8) + Array("g ".utf8) + [0, 0, 0, 0, 158, 0x0D, 0x0A]
        }
        let reading = try XCTUnwrap(driver.readings(from: frame("+"), at: now).first)
        XCTAssertEqual(reading.grams, 123.45, accuracy: 0.001)
        XCTAssertEqual(reading.battery, 100)
        XCTAssertEqual(try XCTUnwrap(driver.readings(from: frame("-"), at: now).first).grams, -123.45, accuracy: 0.001)
        XCTAssertEqual(driver.frames(for: .tare), [[0x54]])
        XCTAssertEqual(driver.frames(for: .resetTimer), [[0x43]])
    }

    // MARK: - Decent

    func testDecentShortAndLongFrames() throws {
        let driver = DecentDriver(profile: DecentDriver.profiles[0])
        func withXor(_ bytes: [UInt8]) -> [UInt8] { bytes + [bytes.reduce(0, ^)] }
        let short = withXor([0x03, 0xCE, 0x04, 0xD2, 0x00, 0x00])
        XCTAssertEqual(try XCTUnwrap(driver.readings(from: short, at: now).first).grams, 123.4, accuracy: 0.001)
        let long = withXor([0x03, 0xCA, 0xFF, 0x9C, 0x00, 0x00, 0x05, 0x01, 0x00])
        XCTAssertEqual(try XCTUnwrap(driver.readings(from: long, at: now).first).grams, -10, accuracy: 0.001)
        var bad = short
        bad[6] ^= 0xFF
        XCTAssertEqual(driver.readings(from: bad, at: now), [])
    }

    func testDecentFrames() {
        let driver = DecentDriver(profile: DecentDriver.profiles[0])
        XCTAssertEqual(driver.handshake, [[0x03, 0x0A, 0x01, 0x01, 0x00, 0x01, 0x08]])
        XCTAssertEqual(driver.keepAlive, [0x03, 0x0A, 0x03, 0xFF, 0xFF, 0x00, 0x0A])
        XCTAssertEqual(driver.frames(for: .tare), [[0x03, 0x0F, 0x00, 0x00, 0x00, 0x01, 0x0D]])
        XCTAssertEqual(driver.frames(for: .resetTimer), [[0x03, 0x0B, 0x02, 0x00, 0x00, 0x00, 0x0A]])
    }

    // MARK: - Varia

    func testVariaWeightAndSign() throws {
        let driver = VariaDriver(profile: VariaDriver.profiles[0])
        let positive: [UInt8] = [0xFA, 0x01, 0x03, 0x00, 0x30, 0x39, 0x0B]
        XCTAssertEqual(try XCTUnwrap(driver.readings(from: positive, at: now).first).grams, 123.45, accuracy: 0.001)
        let negative: [UInt8] = [0xFA, 0x01, 0x03, 0x10, 0x00, 0x96, 0x84]
        XCTAssertEqual(try XCTUnwrap(driver.readings(from: negative, at: now).first).grams, -1.5, accuracy: 0.001)
        // Battery and other frames carry no weight.
        XCTAssertEqual(driver.readings(from: [0xFA, 0x85, 0x01, 0x50, 0xD4], at: now), [])
        XCTAssertEqual(driver.frames(for: .tare), [[0xFA, 0x82, 0x01, 0x01, 0x82]])
        XCTAssertEqual(driver.frames(for: .resetTimer), [])
    }

    // MARK: - DiFluid

    func testDiFluidCoalescedAndSplitFrames() throws {
        let driver = DiFluidDriver(profile: DiFluidDriver.profiles[0])
        func frame(tenths: Int32, flowTenths: UInt16) -> [UInt8] {
            let w = UInt32(bitPattern: tenths)
            var f: [UInt8] = [0xDF, 0xDF, 0x03, 0x00, 0x0D,
                              UInt8(w >> 24 & 0xFF), UInt8(w >> 16 & 0xFF), UInt8(w >> 8 & 0xFF), UInt8(w & 0xFF),
                              UInt8(flowTenths >> 8), UInt8(flowTenths & 0xFF),
                              0x00, 0x05, 0, 0, 0, 0, 0x00]
            f.append(UInt8(f.reduce(0) { $0 + Int($1) } & 0xFF))
            return f
        }
        let first = frame(tenths: 1234, flowTenths: 25), second = frame(tenths: -15, flowTenths: 0)
        // Two frames in one notification, the second cut short.
        let readings = driver.readings(from: first + second[0..<10], at: now)
        XCTAssertEqual(readings.map(\.grams), [123.4])
        XCTAssertEqual(readings.first?.flow, 2.5)
        XCTAssertEqual(driver.readings(from: Array(second[10...]), at: now).map(\.grams), [-1.5])
    }

    func testDiFluidFrames() {
        let driver = DiFluidDriver(profile: DiFluidDriver.profiles[0])
        XCTAssertEqual(driver.handshake, [[0xDF, 0xDF, 0x01, 0x00, 0x01, 0x01, 0xC1],
                                          [0xDF, 0xDF, 0x01, 0x04, 0x01, 0x00, 0xC4]])
        XCTAssertEqual(driver.frames(for: .tare), [[0xDF, 0xDF, 0x03, 0x02, 0x01, 0x01, 0xC5]])
    }

    // MARK: - Shared

    func testFlowEstimatorUsesTheLastSecond() {
        var flow = FlowEstimator()
        XCTAssertEqual(flow.flow(grams: 0, at: now), 0)
        XCTAssertEqual(flow.flow(grams: 2, at: now.addingTimeInterval(0.5)), 4, accuracy: 0.001)
        XCTAssertEqual(flow.flow(grams: 5, at: now.addingTimeInterval(1.5)), 3, accuracy: 0.001)
    }

    func testScaleWithoutTimerStartsAtFirstPour() throws {
        let recorder = Recorder(scales: ScaleManager(defaults: UserDefaults(suiteName: #function)!))
        recorder.start()
        let settled = Date.now.addingTimeInterval(1)
        func reading(_ grams: Double) -> ScaleReading { ScaleReading(grams: grams, flow: 0, battery: nil) }
        recorder.ingest(reading(0.3), from: .a, at: settled)
        XCTAssertEqual(recorder.phase, .waiting)
        recorder.ingest(reading(1.2), from: .a, at: settled.addingTimeInterval(1))
        recorder.ingest(reading(4), from: .a, at: settled.addingTimeInterval(1.5))
        let run = try XCTUnwrap(recorder.stop())
        XCTAssertEqual(run.a.map(\.t), [0, 0, 0.5])
        XCTAssertEqual(run.a.map(\.grams), [0, 1.2, 4])
    }
}
