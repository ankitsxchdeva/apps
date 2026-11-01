import CoreBluetooth
import Foundation

/// Where a scale's weight stream lives. Some brands moved it between models,
/// so a driver can list several; the first one the scale exposes wins.
struct ScaleProfile: Equatable {
    let service: CBUUID
    let notify: CBUUID
    let write: CBUUID
}

/// The commands the app sends. Only these two: everything else is the
/// scale's own buttons.
enum ScaleCommand {
    case tare, resetTimer
}

/// One brand's Bluetooth protocol. A new instance per connection, so drivers
/// can keep partial frames and recent weights between notifications.
protocol ScaleDriver: AnyObject {
    /// Shown when picking a scale; also stored to reconnect with the right driver.
    static var brand: String { get }
    /// Not yet tried on real hardware; labelled in the app.
    static var isBeta: Bool { get }
    static var profiles: [ScaleProfile] { get }
    static func matches(name: String, services: [CBUUID]) -> Bool

    init(profile: ScaleProfile)

    /// Sent once, in order, after notifications are on.
    var handshake: [[UInt8]] { get }
    /// Sent every `ScaleDrivers.keepAliveInterval` while connected, if set.
    var keepAlive: [UInt8]? { get }
    /// Empty when the scale can't do it.
    func frames(for command: ScaleCommand) -> [[UInt8]]
    func readings(from bytes: [UInt8], at now: Date) -> [ScaleReading]
}

extension ScaleDriver {
    static var isBeta: Bool { true }
    var handshake: [[UInt8]] { [] }
    var keepAlive: [UInt8]? { nil }
}

enum ScaleDrivers {
    static let all: [any ScaleDriver.Type] = [
        BookooDriver.self, AcaiaDriver.self, FelicitaDriver.self,
        DecentDriver.self, VariaDriver.self, DiFluidDriver.self,
    ]

    /// Inside every keep-alive window the brands document (Decent: 5 s).
    static let keepAliveInterval: TimeInterval = 2
    /// Some scales drop a command that follows another too closely.
    static let commandGap: TimeInterval = 0.2

    static func match(name: String?, services: [CBUUID]) -> (any ScaleDriver.Type)? {
        all.first { $0.matches(name: name ?? "", services: services) }
    }

    static func named(_ brand: String) -> (any ScaleDriver.Type)? {
        all.first { $0.brand == brand }
    }
}

/// Flow for scales that don't report it: grams gained over about the last
/// second.
struct FlowEstimator {
    private var recent: [(at: Date, grams: Double)] = []

    mutating func flow(grams: Double, at now: Date) -> Double {
        recent.append((now, grams))
        while let first = recent.first, now.timeIntervalSince(first.at) > 1 {
            recent.removeFirst()
        }
        guard let first = recent.first, now > first.at else { return 0 }
        return (grams - first.grams) / now.timeIntervalSince(first.at)
    }
}

// MARK: - Bookoo

/// The only brand that streams its own timer, so its curves use scale time.
final class BookooDriver: ScaleDriver {
    static let brand = "Bookoo"
    static let isBeta = false
    static let profiles = [ScaleProfile(
        service: CBUUID(string: BookooProtocol.serviceUUID),
        notify: CBUUID(string: BookooProtocol.weightUUID),
        write: CBUUID(string: BookooProtocol.commandUUID)
    )]

    static func matches(name: String, services: [CBUUID]) -> Bool {
        name.uppercased().hasPrefix("BOOKOO") || services.contains(profiles[0].service)
    }

    init(profile: ScaleProfile) {}

    func frames(for command: ScaleCommand) -> [[UInt8]] {
        switch command {
        case .tare: [BookooProtocol.frame(.tare)]
        case .resetTimer: [BookooProtocol.frame(.resetTimer)]
        }
    }

    func readings(from bytes: [UInt8], at now: Date) -> [ScaleReading] {
        BookooProtocol.reading(from: bytes).map { [$0] } ?? []
    }
}
