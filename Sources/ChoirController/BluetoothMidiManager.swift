import Foundation
import CoreBluetooth
import CoreAudioKit
import Combine
import MIDIKit
import os

private let log = Logger(subsystem: "com.choir-arranger", category: "bluetooth")

class BluetoothMidiManager: NSObject, ObservableObject {
    @Published var connectedPeripherals: [CBPeripheral] = []
    
    private var centralManager: CBCentralManager!
    
    // Standard BLE MIDI Service UUID
    private let midiServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    
    // Apple's built-in BLE MIDI pairing window (same UI as MIDI Studio's Bluetooth config)
    private var btleWindowController: CABTLEMIDIWindowController?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Apple BLE MIDI Window (replaces MIDI Studio)
    
    /// Opens Apple's built-in Bluetooth MIDI configuration window.
    /// This is the same UI shown by MIDI Studio — handles advertising, pairing, and CoreMIDI bridging.
    @MainActor
    func showBluetoothMIDIWindow() {
        guard centralManager.state == .poweredOn else {
            log.warning("Bluetooth not powered on. Cannot open BLE MIDI window.")
            return
        }
        // Reuse existing window if still open
        if let existing = btleWindowController, existing.window?.isVisible == true {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let wc = CABTLEMIDIWindowController()
        wc.showWindow(nil)
        btleWindowController = wc
        log.info("Opened Apple Bluetooth MIDI configuration window.")
    }
    
    @MainActor
    func closeBluetoothMIDIWindow() {
        btleWindowController?.close()
        btleWindowController = nil
    }
}

extension BluetoothMidiManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log.info("Bluetooth is powered on")
        case .poweredOff:
            log.info("Bluetooth is powered off")
        case .unauthorized:
            log.warning("Bluetooth is unauthorized. Check Info.plist and System Settings.")
        case .unknown, .resetting, .unsupported:
            log.info("Bluetooth state: \(String(describing: central.state))")
        @unknown default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        log.debug("Discovered: \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("BLE connected to \(peripheral.name ?? "Unknown")")
        connectedPeripherals.append(peripheral)
        
        // Discover services to complete the connection flow for MIDI
        peripheral.delegate = self
        peripheral.discoverServices([midiServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.error("Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "No error info")")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.info("Disconnected from \(peripheral.name ?? "Unknown")")
        if let index = connectedPeripherals.firstIndex(of: peripheral) {
            connectedPeripherals.remove(at: index)
        }
    }
}

extension BluetoothMidiManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            log.error("Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else {
            log.warning("No services found on \(peripheral.name ?? "Unknown")")
            return 
        }
        
        for service in services {
            if service.uuid == midiServiceUUID {
                log.info("Discovered MIDI service for \(peripheral.name ?? "Unknown"). Discovering characteristics")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log.error("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            // BLE MIDI characteristic UUID
            if characteristic.uuid.uuidString == "7772E5DB-3868-4112-A1A9-F2669D106BF3" {
                 log.info("Found MIDI characteristic. Subscribing to notifications")
                 peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
}
