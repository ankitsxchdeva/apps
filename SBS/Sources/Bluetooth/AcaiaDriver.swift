import CoreBluetooth
import Foundation

/// Acaia Lunar, Pearl, Pyxis and their 2021+ firmware. Not tried on hardware.
/// Per pyacaia (github.com/lucapinello/pyacaia) and Beanconqueror's
/// src/classes/devices/acaia. Umbra and newer "relay" scales use a third
/// service whose byte order is disputed, so they're left out.
///
/// Messages are `EF DD type len payload… ck1 ck2`, `len + 5` bytes long. The
/// scale only streams after an ident and a notification request, and stops
/// without a heartbeat. Its timer arrives only as occasional events, so runs
/// use the phone's clock.
final class AcaiaDriver: ScaleDriver {
    static let brand = "Acaia"
    private static let legacy = ScaleProfile(
        service: CBUUID(string: "1820"),
        notify: CBUUID(string: "2A80"),
        write: CBUUID(string: "2A80")
    )
    static let profiles = [
        ScaleProfile(
            service: CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFD205E455"),
            notify: CBUUID(string: "49535343-1E4D-4BD9-BA61-23C647249616"),
            write: CBUUID(string: "49535343-8841-43F4-A8D4-ECBE34729BB3")
        ),
        legacy,
    ]

    static func matches(name: String, services: [CBUUID]) -> Bool {
        ["ACAIA", "LUNAR", "PEARL", "PYXIS", "PROCH", "CINCO"].contains { name.uppercased().hasPrefix($0) }
    }

    private let profile: ScaleProfile
    private var buffer: [UInt8] = []
    private var flow = FlowEstimator()

    init(profile: ScaleProfile) {
        self.profile = profile
    }

    var handshake: [[UInt8]] {
        // Newer firmware wants a different ident payload.
        let ident: [UInt8] = profile == Self.legacy
            ? [0xEF, 0xDD, 0x0B] + Array(repeating: 0x2D, count: 15) + [0x68, 0x3B]
            : [0xEF, 0xDD, 0x0B, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
               0x30, 0x31, 0x32, 0x33, 0x34, 0x9A, 0x6D]
        // Weight, battery and timer events, plus keys and settings.
        let notifications: [UInt8] = [0xEF, 0xDD, 0x0C, 0x09, 0x00, 0x01, 0x01, 0x02, 0x02, 0x05, 0x03, 0x04, 0x15, 0x06]
        return [ident, notifications]
    }

    var keepAlive: [UInt8]? { [0xEF, 0xDD, 0x00, 0x02, 0x00, 0x02, 0x00] }

    func frames(for command: ScaleCommand) -> [[UInt8]] {
        switch command {
        case .tare: [[0xEF, 0xDD, 0x04, 0x00, 0x00, 0x00]]
        case .resetTimer: [[0xEF, 0xDD, 0x0D, 0x00, 0x01, 0x00, 0x01]]
        }
    }

    func readings(from bytes: [UInt8], at now: Date) -> [ScaleReading] {
        buffer += bytes
        var readings: [ScaleReading] = []
        while let start = headerIndex() {
            buffer.removeFirst(start)
            guard buffer.count >= 4 else { break }
            let end = Int(buffer[3]) + 5
            guard buffer.count >= end else { break }
            let message = Array(buffer[0..<end])
            buffer.removeFirst(end)
            if let grams = Self.grams(in: message) {
                readings.append(ScaleReading(grams: grams, flow: flow.flow(grams: grams, at: now), battery: nil))
            }
        }
        // Keep only what could still start a message.
        if headerIndex() == nil, buffer.count > 1 {
            buffer.removeFirst(buffer.count - 1)
        }
        return readings
    }

    private func headerIndex() -> Int? {
        guard buffer.count >= 2 else { return nil }
        return (0..<buffer.count - 1).first { buffer[$0] == 0xEF && buffer[$0 + 1] == 0xDD }
    }

    /// Weight from a weight event (0x05) or a heartbeat reply that carries one.
    private static func grams(in message: [UInt8]) -> Double? {
        guard message.count > 5, message[2] == 0x0C else { return nil }
        let payload = Array(message[5...])
        switch message[4] {
        case 0x05: return weight(payload)
        case 0x0B where payload.count > 3 && payload[2] == 0x05: return weight(Array(payload[3...]))
        default: return nil
        }
    }

    /// Little-endian value, a decimal-places byte, then flags (bit 1: negative).
    private static func weight(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 6, (1...4).contains(bytes[4]) else { return nil }
        let raw = bytes[0..<4].reversed().reduce(0) { $0 << 8 | Int($1) }
        let value = Double(raw) / pow(10, Double(bytes[4]))
        return bytes[5] & 0x02 != 0 ? -value : value
    }
}
