import Foundation
import CoreBluetooth
import MIDIKit

class BluetoothMidiManager: NSObject, ObservableObject {
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var connectedPeripherals: [CBPeripheral] = []
    @Published var isScanning = false
    
    private var centralManager: CBCentralManager!
    
    // Standard BLE MIDI Service UUID
    private let midiServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        print("Starting scan for BLE MIDI devices...")
        isScanning = true
        // Scan for devices advertising the MIDI service
        centralManager.scanForPeripherals(withServices: [midiServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    func stopScanning() {
        print("Stopping scan.")
        isScanning = false
        centralManager.stopScan()
    }
    
    func connect(to peripheral: CBPeripheral) {
        print("Connecting to \(peripheral.name ?? "Unknown")...")
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect(from peripheral: CBPeripheral) {
        print("Disconnecting from \(peripheral.name ?? "Unknown")...")
        centralManager.cancelPeripheralConnection(peripheral)
    }
}

extension BluetoothMidiManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on.")
            // Automatically start scanning if desired, or wait for user action
        case .poweredOff:
            print("Bluetooth is powered off.")
            isScanning = false
        case .unauthorized:
            print("Bluetooth is unauthorized.")
        case .unknown, .resetting, .unsupported:
            print("Bluetooth state is \(central.state).")
        @unknown default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Avoid duplicates
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            print("Discovered: \(peripheral.name ?? "Unknown")")
            discoveredPeripherals.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "Unknown")")
        
        // Remove from discovered list if present
        if let index = discoveredPeripherals.firstIndex(of: peripheral) {
            discoveredPeripherals.remove(at: index)
        }
        
        connectedPeripherals.append(peripheral)
        
        // Discover services to complete the connection flow for MIDI
        peripheral.delegate = self
        peripheral.discoverServices([midiServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "No error info")")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "Unknown")")
        if let index = connectedPeripherals.firstIndex(of: peripheral) {
            connectedPeripherals.remove(at: index)
        }
        // Optionally move back to discovered if we are still scanning? 
        // For now, just remove it.
    }
}

extension BluetoothMidiManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == midiServiceUUID {
                print("Discovered MIDI service for \(peripheral.name ?? "Unknown")")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        // Once characteristics are discovered, CoreMIDI should pick it up automatically on macOS
        // providing the device conforms to the BLE MIDI standard.
        // We typically need to subscribe to the characteristic to enable notifications.
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            // BLE MIDI characteristic UUID
            if characteristic.uuid.uuidString == "7772E5DB-3868-4112-A1A9-F2669D106BF3" {
                 print("Found MIDI Characteristic. Subscribing...")
                 peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
}
