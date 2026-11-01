import CoreBluetooth
import Foundation

/// Varia AKU, AKU Mini, Pro and Micro. Not tried on hardware. Per
/// Beanconqueror's variaAku.ts, de1app and crema's varia_aku.rs.
///
/// Weight frames are `hdr 01 03 w1 w2 w3 xor`: hundredths in the low 20 bits,
/// bit 4 of `w1` set when negative. Tare is the only command it takes; no
/// timer, no flow.
final class VariaDriver: ScaleDriver {
    static let brand = "Varia"
    static let profiles = [ScaleProfile(
        service: CBUUID(string: "FFF0"),
        notify: CBUUID(string: "FFF1"),
        write: CBUUID(string: "FFF2")
    )]

    /// FFF0 is shared with other brands, so match on name only.
    static func matches(name: String, services: [CBUUID]) -> Bool {
        let name = name.uppercased()
        return name.contains("VARIA") || name.contains("AKU")
    }

    private var flow = FlowEstimator()

    init(profile: ScaleProfile) {}

    func frames(for command: ScaleCommand) -> [[UInt8]] {
        switch command {
        case .tare: [[0xFA, 0x82, 0x01, 0x01, 0x82]]
        case .resetTimer: []
        }
    }

    func readings(from bytes: [UInt8], at now: Date) -> [ScaleReading] {
        // Sources don't agree on the checksum's span, so it isn't checked.
        guard bytes.count >= 6, bytes[1] == 0x01, bytes[2] == 0x03 else { return [] }
        let hundredths = Int(bytes[3] & 0x0F) << 16 | Int(bytes[4]) << 8 | Int(bytes[5])
        let grams = Double(hundredths) / 100 * (bytes[3] & 0x10 != 0 ? -1 : 1)
        return [ScaleReading(grams: grams, flow: flow.flow(grams: grams, at: now), battery: nil)]
    }
}
