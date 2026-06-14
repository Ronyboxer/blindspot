//
//  RidePeripheralServer.swift
//  Blind Spot
//
//  BLE (CoreBluetooth) ride control. The iPhone acts as a BLE *peripheral* and
//  advertises a custom Blind Spot service while pairing mode is on. The Raspberry
//  Pi acts as the *central*: it scans, connects, WRITES JSON commands to the
//  command characteristic, and SUBSCRIBES/READS the response characteristic.
//
//  Only tiny control messages cross BLE: ride_start / ride_stop / ride_status,
//  and the iPhone's JSON responses (which carry the Supabase ride_id + status).
//  NO GPS, NO photos are ever sent to the Pi — the phone owns the ride session;
//  the Pi owns the camera and uses the ride_id to attach its own media in Supabase.
//
//  Reuses the existing `RideControlDelegate` (implemented by RideController), so
//  BLE and the (legacy) HTTP path drive the exact same ride lifecycle.
//
//  Custom UUIDs (the example "…-BLINDSPOT001" isn't valid hex, so these are valid
//  substitutes — give these to the Pi):
//    Service : 9B7D0001-6C9E-4F2A-9F1A-9B11D5070001
//    Command : 9B7D0002-6C9E-4F2A-9F1A-9B11D5070001  (write)
//    Response: 9B7D0003-6C9E-4F2A-9F1A-9B11D5070001  (notify + read)
//

import Foundation
import CoreBluetooth

// MARK: - Observable status for the pairing UI

// Not @MainActor: constructed by the (nonisolated) peripheral server. Every
// mutation is routed through a @MainActor Task (see setStatus / handleCommand),
// so it's only ever touched on the main thread for SwiftUI.
@Observable
final class BLEStatus {
    var poweredOn = false
    var isAdvertising = false
    var connectedDevice: String?     // short central id, when subscribed
    var activeRideId: String?
    var lastCommand: String?
    var lastResponse: String?
    /// Rolling debug log (newest first), capped.
    private(set) var log: [String] = []

    func append(_ line: String) {
        log.insert(line, at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
    }
}

// MARK: - BLE peripheral

final class RidePeripheralServer: NSObject {

    static let serviceUUID  = CBUUID(string: "9B7D0001-6C9E-4F2A-9F1A-9B11D5070001")
    static let commandUUID  = CBUUID(string: "9B7D0002-6C9E-4F2A-9F1A-9B11D5070001")
    static let responseUUID = CBUUID(string: "9B7D0003-6C9E-4F2A-9F1A-9B11D5070001")

    /// Drives the actual ride lifecycle (RideController). `@MainActor`.
    weak var delegate: RideControlDelegate?

    /// Observable state for the pairing screen.
    let status = BLEStatus()

    private var manager: CBPeripheralManager?
    private let queue = DispatchQueue(label: "com.ronakrupani.blindspot.ble")
    private var responseChar: CBMutableCharacteristic?
    private var serviceAdded = false
    private var wantAdvertising = false
    /// Last response bytes, served on READ requests (for centrals with small MTU).
    private var latestResponse = Data()

    // MARK: Control (called from the UI, main thread)

    func startAdvertising() {
        wantAdvertising = true
        if manager == nil {
            // Creating the manager triggers the Bluetooth permission prompt.
            manager = CBPeripheralManager(delegate: self, queue: queue)
        } else {
            queue.async { [weak self] in self?.configureAndAdvertise() }
        }
    }

    func stopAdvertising() {
        wantAdvertising = false
        queue.async { [weak self] in
            self?.manager?.stopAdvertising()
            self?.setStatus { $0.isAdvertising = false; $0.append("⏹ advertising stopped") }
        }
    }

    // MARK: Advertising setup (on BLE queue)

    private func configureAndAdvertise() {
        guard let manager, manager.state == .poweredOn, wantAdvertising else { return }
        if !serviceAdded {
            let command = CBMutableCharacteristic(
                type: Self.commandUUID, properties: [.write],
                value: nil, permissions: [.writeable])
            let response = CBMutableCharacteristic(
                type: Self.responseUUID, properties: [.notify, .read],
                value: nil, permissions: [.readable])
            self.responseChar = response
            let service = CBMutableService(type: Self.serviceUUID, primary: true)
            service.characteristics = [command, response]
            manager.add(service)           // advertising begins in didAdd
            serviceAdded = true
        } else {
            beginAdvertising()
        }
    }

    private func beginAdvertising() {
        guard let manager, wantAdvertising else { return }
        manager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: "Blind Spot"
        ])
    }

    // MARK: Command processing (main actor — touches RideController)

    @MainActor
    private func process(_ data: Data) async -> (Data, String) {
        guard
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let type = obj["type"] as? String
        else {
            return (Self.encode(["ok": false, "type": "error", "error": "invalid json"]), "invalid")
        }

        switch type {
        case "ride_start":
            if let id = await delegate?.rideControlStart() {
                // Returns the existing id if a ride was already active (no dup).
                return (Self.encode([
                    "ok": true, "type": "ride_start_response",
                    "ride_id": id.uuidString, "status": "recording"
                ]), "ride_start")
            }
            return (Self.encode(["ok": false, "type": "error", "error": "could not start ride"]), "ride_start")

        case "ride_stop":
            let requested = (obj["ride_id"] as? String).flatMap(UUID.init(uuidString:))
            guard let active = delegate?.activeRideId else {
                // No active ride → idempotent "already_stopped".
                return (Self.encode([
                    "ok": true, "type": "ride_stop_response",
                    "ride_id": requested?.uuidString as Any, "status": "already_stopped"
                ]), "ride_stop")
            }
            if let requested, requested != active {
                return (Self.encode([
                    "ok": false, "type": "error", "error": "unknown ride id"
                ]), "ride_stop")
            }
            let ok = await delegate?.rideControlStop(rideId: requested) ?? false
            if ok {
                return (Self.encode([
                    "ok": true, "type": "ride_stop_response",
                    "ride_id": active.uuidString, "status": "stopped"
                ]), "ride_stop")
            }
            return (Self.encode(["ok": false, "type": "error", "error": "stop failed"]), "ride_stop")

        case "ride_status":
            let id = delegate?.activeRideId
            let st = delegate?.rideStatusString ?? "idle"
            return (Self.encode([
                "ok": true, "type": "ride_status_response",
                "ride_id": id?.uuidString as Any, "status": st
            ]), "ride_status")

        default:
            return (Self.encode(["ok": false, "type": "error", "error": "unknown command type"]), type)
        }
    }

    private static func encode(_ dict: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
    }

    // MARK: Helpers

    private func setStatus(_ mutate: @escaping (BLEStatus) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            mutate(self.status)
        }
    }
}

// MARK: - CBPeripheralManagerDelegate (all on the BLE queue)

extension RidePeripheralServer: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let on = peripheral.state == .poweredOn
        setStatus { $0.poweredOn = on; $0.append("BLE state: \(peripheral.state.rawValue)") }
        if on { configureAndAdvertise() }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didAdd service: CBService, error: Error?) {
        if let error {
            setStatus { $0.append("⚠️ add service failed: \(error.localizedDescription)") }
            return
        }
        beginAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            setStatus { $0.isAdvertising = false; $0.append("⚠️ advertise failed: \(error.localizedDescription)") }
        } else {
            setStatus { $0.isAdvertising = true; $0.append("📡 advertising as “Blind Spot”") }
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let id = String(central.identifier.uuidString.prefix(8))
        setStatus { $0.connectedDevice = id; $0.append("🔗 Pi connected (\(id))") }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        setStatus { $0.connectedDevice = nil; $0.append("🔌 Pi disconnected") }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        // Serve the latest response (supports long/blob reads via offset).
        guard request.offset <= latestResponse.count else {
            peripheral.respond(to: request, withResult: .invalidOffset); return
        }
        request.value = latestResponse.subdata(in: request.offset..<latestResponse.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // Acknowledge the write first.
        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
        for request in requests {
            guard let data = request.value, !data.isEmpty else { continue }
            handleCommand(data)
        }
    }

    private func handleCommand(_ data: Data) {
        let incoming = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
        setStatus { $0.append("⬇️ cmd: \(incoming)") }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let (response, summary) = await self.process(data)
            let responseString = String(data: response, encoding: .utf8) ?? ""
            self.status.lastCommand = summary
            self.status.lastResponse = responseString
            self.status.activeRideId = self.delegate?.activeRideId?.uuidString
            self.status.append("⬆️ resp: \(responseString)")

            // Send the reply on the BLE queue (notify subscribers + cache for reads).
            self.queue.async { [weak self] in
                guard let self, let char = self.responseChar, let manager = self.manager else { return }
                self.latestResponse = response
                manager.updateValue(response, for: char, onSubscribedCentrals: nil)
            }
        }
    }
}
