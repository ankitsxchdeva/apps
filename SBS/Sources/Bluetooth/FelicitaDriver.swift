import CoreBluetooth
import Foundation

/// Felicita Arc, Incline and Parallel. Not tried on hardware. Per de1app
/// (bluetooth.tcl) and Beanconqueror's felicitaScale.ts.
///
/// Each notification is 18 ASCII-ish bytes: `01 02`, a sign, six digits in
/// hundredths, the unit, then battery at byte 15. No timer, no flow.
final class FelicitaDriver: ScaleDriver {
    static let brand = "Felicita"
    static let profiles = [ScaleProfile(
        service: CBUUID(string: "FFE0"),
        notify: CBUUID(string: "FFE1"),
        write: CBUUID(string: "FFE1")
    )]

    static func matches(name: String, services: [CBUUID]) -> Bool {
        name.uppercased().contains("FELICITA")
    }

    private var flow = FlowEstimator()

    init(profile: ScaleProfile) {}

    func frames(for command: ScaleCommand) -> [[UInt8]] {
        switch command {
        case .tare: [[0x54]]
        case .resetTimer: [[0x43]]
        }
    }

    func readings(from bytes: [UInt8], at now: Date) -> [ScaleReading] {
        guard bytes.count >= 16, bytes[0] == 0x01, bytes[1] == 0x02,
              let digits = String(bytes: bytes[3...8], encoding: .ascii),
              let hundredths = Int(digits) else { return [] }
        let grams = Double(hundredths) / 100 * (bytes[2] == UInt8(ascii: "-") ? -1 : 1)
        // Raw battery runs 129 (empty) to 158 (full).
        let battery = min(100, max(0, (Int(bytes[15]) - 129) * 100 / 29))
        return [ScaleReading(grams: grams, flow: flow.flow(grams: grams, at: now), battery: battery)]
    }
}
