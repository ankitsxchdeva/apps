import CoreBluetooth
import Foundation

/// Decent Scale. Not tried on hardware. Per decentespresso.com/decentscale_api
/// and de1app (machine.tcl, binary.tcl).
///
/// Weight frames are `03 CE|CA wHi wLo …` ending in an XOR checksum: 7 bytes
/// before firmware 1.2, 10 after. The scale only weighs after a write and
/// wants a heartbeat at least every 5 s. Its time bytes aren't the timer
/// display, so runs use the phone's clock.
final class DecentDriver: ScaleDriver {
    static let brand = "Decent"
    static let profiles = [ScaleProfile(
        service: CBUUID(string: "FFF0"),
        notify: CBUUID(string: "FFF4"),
        write: CBUUID(string: "36F5")
    )]

    static func matches(name: String, services: [CBUUID]) -> Bool {
        name.uppercased().hasPrefix("DECENT")
    }

    private var flow = FlowEstimator()

    init(profile: ScaleProfile) {}

    /// LEDs on, with heartbeat enforcement.
    var handshake: [[UInt8]] { [[0x03, 0x0A, 0x01, 0x01, 0x00, 0x01, 0x08]] }
    var keepAlive: [UInt8]? { [0x03, 0x0A, 0x03, 0xFF, 0xFF, 0x00, 0x0A] }

    func frames(for command: ScaleCommand) -> [[UInt8]] {
        switch command {
        case .tare: [[0x03, 0x0F, 0x00, 0x00, 0x00, 0x01, 0x0D]]
        case .resetTimer: [[0x03, 0x0B, 0x02, 0x00, 0x00, 0x00, 0x0A]]
        }
    }

    func readings(from bytes: [UInt8], at now: Date) -> [ScaleReading] {
        guard bytes.count == 7 || bytes.count == 10, bytes[0] == 0x03,
              bytes[1] == 0xCE || bytes[1] == 0xCA,
              bytes.dropLast().reduce(0, ^) == bytes.last else { return [] }
        let grams = Double(Int16(bitPattern: UInt16(bytes[2]) << 8 | UInt16(bytes[3]))) / 10
        return [ScaleReading(grams: grams, flow: flow.flow(grams: grams, at: now), battery: nil)]
    }
}
