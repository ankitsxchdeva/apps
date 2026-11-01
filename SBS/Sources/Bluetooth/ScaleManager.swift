import CoreBluetooth
import Foundation
import Observation

/// Owns Bluetooth: finds Bookoo scales, keeps one connected in each slot, and
/// forwards every reading. Remembers which scale sits where, so the next
/// launch reconnects both without asking.
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
    }

    private(set) var slots: [Slot: SlotState] = Dictionary(uniqueKeysWithValues: Slot.allCases.map { ($0, SlotState()) })
    private(set) var nearby: [Nearby] = []
    private(set) var bluetoothState: CBManagerState = .unknown

    /// Every decoded reading, as it arrives.
    @ObservationIgnored var onReading: ((Slot, ScaleReading) -> Void)?

    /// A and B are required; C and D are optional.
    var canStart: Bool {
        Slot.allCases.filter { !$0.isOptional }.allSatisfy { slots[$0]?.status == .connected }
    }

    var connectedCount: Int {
        slots.values.filter { $0.status == .connected }.count
    }

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [Slot: CBPeripheral] = [:]
    @ObservationIgnored private var commandCharacteristics: [Slot: CBCharacteristic] = [:]
    @ObservationIgnored private var discovered: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private let defaults: UserDefaults

    private static let service = CBUUID(string: BookooProtocol.serviceUUID)
    private static let weight = CBUUID(string: BookooProtocol.weightUUID)
    private static let command = CBUUID(string: BookooProtocol.commandUUID)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        #if DEBUG
        if MockScales.isEnabled {
            mock = MockScales(manager: self)
            return
        }
        #endif
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Pairing

    func startScan() {
        wantsScan = true
        nearby = []
        discovered = [:]
        if central?.state == .poweredOn {
            // Bookoo doesn't reliably advertise its service UUID, so scan
            // everything and filter by name or service in didDiscover.
            central?.scanForPeripherals(withServices: nil)
        }
    }

    func stopScan() {
        wantsScan = false
        central?.stopScan()
    }

    /// Put a nearby scale in `slot`, moving it out of the other slot if needed.
    func assign(_ id: UUID, to slot: Slot) {
        guard let peripheral = discovered[id] else { return }
        for other in Slot.allCases where peripherals[other]?.identifier == id {
            forget(other)
        }
        forget(slot)
        connect(peripheral, in: slot)
    }

    func forget(_ slot: Slot) {
        if let peripheral = peripherals.removeValue(forKey: slot) {
            central?.cancelPeripheralConnection(peripheral)
        }
        commandCharacteristics[slot] = nil
        slots[slot] = SlotState()
        defaults.removeObject(forKey: Self.key(slot))
    }

    // MARK: - Commands

    func tareAndResetAll() {
        #if DEBUG
        if let mock { mock.tare(); return }
        #endif
        for slot in Slot.allCases {
            send(.tare, to: slot)
            send(.resetTimer, to: slot)
        }
    }

    private func send(_ command: BookooProtocol.Command, to slot: Slot) {
        guard let peripheral = peripherals[slot],
              let characteristic = commandCharacteristics[slot] else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse : .withResponse
        peripheral.writeValue(Data(BookooProtocol.frame(command)), for: characteristic, type: type)
    }

    // MARK: - Internals

    private static func key(_ slot: Slot) -> String { "scale.\(slot.rawValue)" }

    private func connect(_ peripheral: CBPeripheral, in slot: Slot) {
        peripheral.delegate = self
        peripherals[slot] = peripheral
        slots[slot] = SlotState(status: .connecting, name: peripheral.name)
        defaults.set(peripheral.identifier.uuidString, forKey: Self.key(slot))
        central?.connect(peripheral)
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
            connect(peripheral, in: slot)
        }
    }

    fileprivate func deliver(_ reading: ScaleReading, from slot: Slot) {
        slots[slot]?.latest = reading
        onReading?(slot, reading)
    }

    #if DEBUG
    @ObservationIgnored private var mock: MockScales?

    fileprivate func mockConnect() {
        for slot in Slot.allCases {
            slots[slot] = SlotState(status: .connected, name: "Mock scale \(slot.name)")
        }
    }
    #endif
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
        guard services.contains(Self.service) || name?.uppercased().hasPrefix("BOOKOO") == true,
              discovered[peripheral.identifier] == nil else { return }
        discovered[peripheral.identifier] = peripheral
        nearby.append(Nearby(id: peripheral.identifier, name: name ?? "Bookoo scale"))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.service])
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
        commandCharacteristics[slot] = nil
        central.connect(peripheral)
    }
}

// MARK: - CBPeripheralDelegate

extension ScaleManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else { return }
        peripheral.discoverCharacteristics([Self.weight, Self.command], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let slot = slot(of: peripheral) else { return }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.weight: peripheral.setNotifyValue(true, for: characteristic)
            case Self.command: commandCharacteristics[slot] = characteristic
            default: break
            }
        }
        slots[slot]?.status = .connected
        slots[slot]?.name = peripheral.name
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.weight,
              let slot = slot(of: peripheral),
              let value = characteristic.value,
              let reading = BookooProtocol.reading(from: [UInt8](value)) else { return }
        deliver(reading, from: slot)
    }
}

// MARK: - Simulator stand-in

#if DEBUG
/// Two fake scales for the simulator, which has no Bluetooth. Launch with
/// `-sbs-mock`. After a tare each starts its timer and "pours" a slightly
/// different curve, each about 2 s after the one before.
final class MockScales {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-sbs-mock") }

    private weak var manager: ScaleManager?
    private var timer: Timer?
    private var taredAt: Date?

    init(manager: ScaleManager) {
        self.manager = manager
        DispatchQueue.main.async { [weak self] in
            manager.mockConnect()
            self?.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in self?.tick() }
        }
    }

    func tare() { taredAt = .now }

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
#endif
