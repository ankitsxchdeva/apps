import CoreBluetooth
import Foundation
import Observation

/// Owns Bluetooth: finds supported scales, keeps one connected in each slot,
/// and forwards every reading. Brand specifics live in each `ScaleDriver`.
/// Remembers which scale sits where, so the next launch reconnects them
/// without asking.
@Observable
final class ScaleManager: NSObject {
    static let shared = ScaleManager()

    enum Status: Equatable {
        case empty, connecting, connected
    }

    struct SlotState {
        var status: Status = .empty
        var name: String?
        var latest: ScaleReading?
    }

    struct Nearby: Identifiable {
        let id: UUID
        let name: String
        let brand: String
        let isBeta: Bool
    }

    private(set) var slots: [Slot: SlotState] = Dictionary(uniqueKeysWithValues: Slot.allCases.map { ($0, SlotState()) })
    /// What each slot's scale is testing ("V60"). Moves with the scale on a swap.
    private(set) var labels: [Slot: String] = [:]
    private(set) var nearby: [Nearby] = []
    private(set) var bluetoothState: CBManagerState = .unknown
    /// Fake scales are standing in for real ones.
    private(set) var isDemo = false

    /// Every decoded reading, as it arrives.
    @ObservationIgnored var onReading: ((Slot, ScaleReading) -> Void)?

    /// A and B are required; C and D are optional.
    var canStart: Bool {
        Slot.allCases.filter { !$0.isOptional }.allSatisfy { slots[$0]?.status == .connected }
    }

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [Slot: CBPeripheral] = [:]
    /// Known from the scan; the driver itself is made once the scale's
    /// services show which profile it uses.
    @ObservationIgnored private var driverTypes: [Slot: any ScaleDriver.Type] = [:]
    @ObservationIgnored private var drivers: [Slot: any ScaleDriver] = [:]
    @ObservationIgnored private var profiles: [Slot: ScaleProfile] = [:]
    @ObservationIgnored private var commandCharacteristics: [Slot: CBCharacteristic] = [:]
    @ObservationIgnored private var keepAlives: [Slot: Timer] = [:]
    @ObservationIgnored private var discovered: [UUID: (peripheral: CBPeripheral, driver: any ScaleDriver.Type)] = [:]
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        for slot in Slot.allCases {
            labels[slot] = defaults.string(forKey: Self.labelKey(slot))
        }
        #if DEBUG
        // The simulator has no Bluetooth: launch with `-sbs-mock`.
        if ProcessInfo.processInfo.arguments.contains("-sbs-mock") {
            startDemo()
            return
        }
        #endif
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Demo

    /// Four fake scales, for trying SBS without any (and for App Review).
    /// Real scales are let go but not forgotten.
    func startDemo() {
        guard demo == nil else { return }
        for slot in Slot.allCases {
            if let peripheral = peripherals.removeValue(forKey: slot) {
                central?.cancelPeripheralConnection(peripheral)
            }
            disconnected(slot)
            driverTypes[slot] = nil
        }
        demo = DemoScales(manager: self)
        isDemo = true
    }

    func endDemo() {
        demo?.stop()
        demo = nil
        isDemo = false
        for slot in Slot.allCases {
            slots[slot] = SlotState()
        }
        reconnectRemembered()
    }

    // MARK: - Pairing

    func startScan() {
        wantsScan = true
        nearby = []
        discovered = [:]
        if central?.state == .poweredOn {
            // Not every scale advertises its service UUID, so scan
            // everything and match by name or service in didDiscover.
            central?.scanForPeripherals(withServices: nil)
        }
    }

    func stopScan() {
        wantsScan = false
        central?.stopScan()
    }

    /// Put a nearby scale in `slot`, moving it out of the other slot if needed.
    func assign(_ id: UUID, to slot: Slot) {
        guard let found = discovered[id] else { return }
        for other in Slot.allCases where peripherals[other]?.identifier == id {
            forget(other)
        }
        forget(slot)
        connect(found.peripheral, driver: found.driver, in: slot)
    }

    /// Trade the scales in two slots, live connection and all, so the cards
    /// match where the scales sit. Either slot may be empty.
    func swap(_ x: Slot, _ y: Slot) {
        guard x != y, !isDemo else { return }
        func trade<Value>(_ values: inout [Slot: Value]) {
            (values[x], values[y]) = (values[y], values[x])
        }
        keepAlives.removeValue(forKey: x)?.invalidate()
        keepAlives.removeValue(forKey: y)?.invalidate()
        trade(&slots)
        trade(&peripherals)
        trade(&driverTypes)
        trade(&drivers)
        trade(&profiles)
        trade(&commandCharacteristics)
        trade(&labels)
        for key in [Self.key, Self.brandKey, Self.labelKey] {
            let (valueX, valueY) = (defaults.string(forKey: key(x)), defaults.string(forKey: key(y)))
            defaults.set(valueY, forKey: key(x))
            defaults.set(valueX, forKey: key(y))
        }
        // The keep-alive is tied to its slot, so restart it under the new one.
        for slot in [x, y] where commandCharacteristics[slot] != nil {
            startKeepAlive(slot)
        }
    }

    /// Blank clears the label.
    func setLabel(_ label: String, for slot: Slot) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        labels[slot] = trimmed.isEmpty ? nil : trimmed
        defaults.set(labels[slot], forKey: Self.labelKey(slot))
    }

    func forget(_ slot: Slot) {
        if let peripheral = peripherals.removeValue(forKey: slot) {
            central?.cancelPeripheralConnection(peripheral)
        }
        disconnected(slot)
        driverTypes[slot] = nil
        slots[slot] = SlotState()
        defaults.removeObject(forKey: Self.key(slot))
        defaults.removeObject(forKey: Self.brandKey(slot))
    }

    // MARK: - Commands

    func tareAndResetAll() {
        if let demo { demo.tare(); return }
        for slot in Slot.allCases {
            send(.tare, to: slot)
            DispatchQueue.main.asyncAfter(deadline: .now() + ScaleDrivers.commandGap) { [weak self] in
                self?.send(.resetTimer, to: slot)
            }
        }
    }

    private func send(_ command: ScaleCommand, to slot: Slot) {
        for frame in drivers[slot]?.frames(for: command) ?? [] {
            write(frame, to: slot)
        }
    }

    private func write(_ bytes: [UInt8], to slot: Slot) {
        guard let peripheral = peripherals[slot],
              let characteristic = commandCharacteristics[slot] else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse : .withResponse
        peripheral.writeValue(Data(bytes), for: characteristic, type: type)
    }

    // MARK: - Internals

    private static func key(_ slot: Slot) -> String { "scale.\(slot.rawValue)" }
    private static func brandKey(_ slot: Slot) -> String { "scale.\(slot.rawValue).brand" }
    private static func labelKey(_ slot: Slot) -> String { "scale.\(slot.rawValue).label" }

    private func connect(_ peripheral: CBPeripheral, driver: any ScaleDriver.Type, in slot: Slot) {
        peripheral.delegate = self
        peripherals[slot] = peripheral
        driverTypes[slot] = driver
        slots[slot] = SlotState(status: .connecting, name: peripheral.name)
        defaults.set(peripheral.identifier.uuidString, forKey: Self.key(slot))
        defaults.set(driver.brand, forKey: Self.brandKey(slot))
        central?.connect(peripheral)
    }

    /// Drop everything tied to the live connection; the slot keeps its scale.
    private func disconnected(_ slot: Slot) {
        keepAlives.removeValue(forKey: slot)?.invalidate()
        drivers[slot] = nil
        profiles[slot] = nil
        commandCharacteristics[slot] = nil
    }

    /// Handshake frames go out one gap apart, then the keep-alive starts.
    private func startStreaming(_ slot: Slot) {
        guard let driver = drivers[slot] else { return }
        for (i, frame) in driver.handshake.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * ScaleDrivers.commandGap) { [weak self] in
                self?.write(frame, to: slot)
            }
        }
        startKeepAlive(slot)
    }

    private func startKeepAlive(_ slot: Slot) {
        guard let keepAlive = drivers[slot]?.keepAlive else { return }
        keepAlives[slot]?.invalidate()
        keepAlives[slot] = Timer.scheduledTimer(withTimeInterval: ScaleDrivers.keepAliveInterval, repeats: true) { [weak self] _ in
            self?.write(keepAlive, to: slot)
        }
    }

    private func slot(of peripheral: CBPeripheral) -> Slot? {
        peripherals.first { $0.value.identifier == peripheral.identifier }?.key
    }

    private func reconnectRemembered() {
        guard let central else { return }
        for slot in Slot.allCases where peripherals[slot] == nil {
            guard let raw = defaults.string(forKey: Self.key(slot)),
                  let id = UUID(uuidString: raw),
                  let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first else { continue }
            // Scales saved before other brands existed are all Bookoo.
            let driver = defaults.string(forKey: Self.brandKey(slot)).flatMap(ScaleDrivers.named) ?? BookooDriver.self
            connect(peripheral, driver: driver, in: slot)
        }
    }

    fileprivate func deliver(_ reading: ScaleReading, from slot: Slot) {
        slots[slot]?.latest = reading
        onReading?(slot, reading)
    }

    @ObservationIgnored private var demo: DemoScales?

    fileprivate func demoConnect() {
        for slot in Slot.allCases {
            slots[slot] = SlotState(status: .connected, name: "Demo scale \(slot.name)")
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension ScaleManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        guard central.state == .poweredOn else { return }
        reconnectRemembered()
        if wantsScan { startScan() }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard discovered[peripheral.identifier] == nil,
              let driver = ScaleDrivers.match(name: name, services: services) else { return }
        discovered[peripheral.identifier] = (peripheral, driver)
        nearby.append(Nearby(id: peripheral.identifier, name: name ?? "\(driver.brand) scale",
                             brand: driver.brand, isBeta: driver.isBeta))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let slot = slot(of: peripheral) else { return }
        peripheral.discoverServices(driverTypes[slot]?.profiles.map(\.service))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // A pending connect never times out, so this keeps waiting until the
        // scale is back in range or turned on.
        if slot(of: peripheral) != nil { central.connect(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let slot = slot(of: peripheral) else { return }
        slots[slot]?.status = .connecting
        slots[slot]?.latest = nil
        disconnected(slot)
        central.connect(peripheral)
    }
}

// MARK: - CBPeripheralDelegate

extension ScaleManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let slot = slot(of: peripheral), let type = driverTypes[slot] else { return }
        // The first profile this scale actually exposes.
        for profile in type.profiles {
            guard let service = peripheral.services?.first(where: { $0.uuid == profile.service }) else { continue }
            profiles[slot] = profile
            drivers[slot] = type.init(profile: profile)
            peripheral.discoverCharacteristics([profile.notify, profile.write], for: service)
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let slot = slot(of: peripheral), let profile = profiles[slot] else { return }
        // Some brands notify and take commands on the same characteristic.
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == profile.write { commandCharacteristics[slot] = characteristic }
            if characteristic.uuid == profile.notify { peripheral.setNotifyValue(true, for: characteristic) }
        }
        slots[slot]?.status = .connected
        slots[slot]?.name = peripheral.name
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.isNotifying, let slot = slot(of: peripheral) else { return }
        startStreaming(slot)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let slot = slot(of: peripheral),
              characteristic.uuid == profiles[slot]?.notify,
              let driver = drivers[slot],
              let value = characteristic.value else { return }
        for reading in driver.readings(from: [UInt8](value), at: .now) {
            deliver(reading, from: slot)
        }
    }
}

// MARK: - Demo scales

/// Four fake scales. After a tare each starts its timer and "pours" a
/// slightly different curve, each about 2 s after the one before.
final class DemoScales {
    private weak var manager: ScaleManager?
    private var timer: Timer?
    private var taredAt: Date?

    init(manager: ScaleManager) {
        self.manager = manager
        manager.demoConnect()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func tare() { taredAt = .now }

    func stop() { timer?.invalidate() }

    private func tick() {
        guard let manager else { return }
        let elapsed = taredAt.map { Date.now.timeIntervalSince($0) } ?? -1
        manager.deliver(reading(elapsed: elapsed - 1.5, rate: 4.2, target: 250, wobble: 0.6), from: .a)
        manager.deliver(reading(elapsed: elapsed - 3.8, rate: 5.0, target: 245, wobble: 1.4), from: .b)
        manager.deliver(reading(elapsed: elapsed - 5.6, rate: 4.6, target: 238, wobble: 0.9), from: .c)
        manager.deliver(reading(elapsed: elapsed - 7.4, rate: 3.9, target: 252, wobble: 1.1), from: .d)
    }

    /// A pour at `rate` g/s with a wobble in flow, levelling off at `target`.
    private func reading(elapsed: Double, rate: Double, target: Double, wobble: Double) -> ScaleReading {
        guard elapsed > 0 else { return ScaleReading(grams: 0, flow: 0, battery: 82) }
        let grams = min(target, rate * elapsed + wobble * sin(elapsed * 1.3) * 3)
        let flow = grams >= target ? 0 : max(0, rate + wobble * cos(elapsed * 1.3) * 3.9)
        return ScaleReading(grams: max(0, grams), flow: flow, battery: 82, timer: elapsed)
    }
}
