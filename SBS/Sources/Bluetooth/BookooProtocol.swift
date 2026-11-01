import Foundation

/// One weight notification from a Bookoo scale, in grams regardless of the
/// display unit.
struct ScaleReading: Equatable {
    var grams: Double
    /// The scale's own smoothed flow rate, in g/s.
    var flow: Double
    var battery: Int
    /// The scale's own timer, in seconds. 0 until it's started.
    var timer: TimeInterval = 0
}

/// Bookoo Themis (Mini and Ultra) BLE protocol, per Bookoo's published spec:
/// github.com/BooKooCode/OpenSource — bookoo_ultra_scale/protocols.md
enum BookooProtocol {
    static let serviceUUID = "0FFE"
    static let weightUUID = "FF11"
    static let commandUUID = "FF12"

    enum Command: UInt8 {
        case tare = 0x01
        case startTimer = 0x04
        case stopTimer = 0x05
        case resetTimer = 0x06
        case tareAndStartTimer = 0x07
    }

    /// `03 0A <cmd> 00 00 <xor>`
    static func frame(_ command: Command) -> [UInt8] {
        let body: [UInt8] = [0x03, 0x0A, command.rawValue, 0x00, 0x00]
        return body + [checksum(body)]
    }

    /// Decodes a 20-byte `03 0B` weight frame; anything else (other frame
    /// types, bad checksum) is nil.
    static func reading(from bytes: [UInt8]) -> ScaleReading? {
        guard bytes.count == 20, bytes[0] == 0x03, bytes[1] == 0x0B,
              checksum(bytes[0..<19]) == bytes[19] else { return nil }
        let weight = Double(uint(bytes[7...9])) / 100
        let flow = Double(uint(bytes[11...12])) / 100
        return ScaleReading(
            grams: sign(bytes[6]) * weight,
            flow: sign(bytes[10]) * flow,
            battery: Int(bytes[13]),
            timer: Double(uint(bytes[2...4])) / 1000
        )
    }

    static func checksum<C: Collection>(_ bytes: C) -> UInt8 where C.Element == UInt8 {
        bytes.reduce(0, ^)
    }

    private static func uint(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { $0 << 8 | Int($1) }
    }

    /// The spec doesn't define the sign byte. Community drivers read it as
    /// ASCII: "-" (0x2D) is negative, anything else positive.
    private static func sign(_ byte: UInt8) -> Double {
        byte == 0x2D ? -1 : 1
    }
}
