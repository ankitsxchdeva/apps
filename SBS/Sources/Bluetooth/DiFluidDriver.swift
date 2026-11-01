import CoreBluetooth
import Foundation

/// DiFluid Microbalance and Microbalance Ti. Not tried on hardware. Per
/// DiFluid's protocol doc (github.com/DiFluid/difluid-sdk-demo,
/// docs/protocolMicrobalance.md) and Beanconqueror's difluidMicrobalance.ts.
///
/// Sensor frames are 19 bytes, `DF DF 03 00 0D` + 13 data bytes + a sum
/// checksum, and can arrive split or back to back. Weight is a signed
/// big-endian tenth of a gram, flow a tenth of a g/s. It reports a timer, but
/// its unit isn't documented, so runs use the phone's clock.
final class DiFluidDriver: ScaleDriver {
    static let brand = "DiFluid"
    static let profiles = ["00EE", "00DD"].map {
        ScaleProfile(service: CBUUID(string: $0), notify: CBUUID(string: "AA01"), write: CBUUID(string: "AA01"))
    }

    static func matches(name: String, services: [CBUUID]) -> Bool {
        let name = name.uppercased()
        return name.contains("MICROBALANCE") || name.contains("MB TI")
            || services.contains { profiles.map(\.service).contains($0) }
    }

    private static let header: [UInt8] = [0xDF, 0xDF, 0x03, 0x00, 0x0D]
    private static let length = 19
    private var buffer: [UInt8] = []

    init(profile: ScaleProfile) {}

    /// Turn on streaming, then switch to grams.
    var handshake: [[UInt8]] {
        [[0xDF, 0xDF, 0x01, 0x00, 0x01, 0x01, 0xC1], [0xDF, 0xDF, 0x01, 0x04, 0x01, 0x00, 0xC4]]
    }

    /// No reset command: the timer resets from the scale's own button.
    func frames(for command: ScaleCommand) -> [[UInt8]] {
        switch command {
        case .tare: [[0xDF, 0xDF, 0x03, 0x02, 0x01, 0x01, 0xC5]]
        case .resetTimer: []
        }
    }

    func readings(from bytes: [UInt8], at now: Date) -> [ScaleReading] {
        buffer += bytes
        var readings: [ScaleReading] = []
        while let start = headerIndex() {
            buffer.removeFirst(start)
            guard buffer.count >= Self.length else { break }
            let frame = Array(buffer[0..<Self.length])
            buffer.removeFirst(Self.length)
            guard frame.dropLast().reduce(0, { $0 &+ $1 }) == frame.last else { continue }
            let tenths = Int32(bitPattern: frame[5...8].reduce(0) { $0 << 8 | UInt32($1) })
            let flow = Int16(bitPattern: UInt16(frame[9]) << 8 | UInt16(frame[10]))
            readings.append(ScaleReading(grams: Double(tenths) / 10, flow: Double(flow) / 10, battery: nil))
        }
        // Keep only what could still become a frame.
        if headerIndex() == nil, buffer.count > Self.header.count {
            buffer.removeFirst(buffer.count - Self.header.count)
        }
        return readings
    }

    private func headerIndex() -> Int? {
        guard buffer.count >= Self.header.count else { return nil }
        return (0...buffer.count - Self.header.count).first {
            Array(buffer[$0..<$0 + Self.header.count]) == Self.header
        }
    }
}
