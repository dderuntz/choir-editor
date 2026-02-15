import Foundation
import CoreBluetooth
import CoreAudioKit
import Combine
import os

private let log = Logger(subsystem: "com.choir-arranger", category: "bluetooth")

class BluetoothMidiManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    
    // Apple's built-in BLE MIDI pairing window (same UI as MIDI Studio's Bluetooth config)
    private var btleWindowController: CABTLEMIDIWindowController?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Apple BLE MIDI Window
    
    /// Opens Apple's built-in Bluetooth MIDI configuration window.
    /// This handles scanning, pairing, and CoreMIDI bridging at the OS level.
    @MainActor
    func showBluetoothMIDIWindow() {
        guard centralManager.state == .poweredOn else {
            log.warning("Bluetooth not powered on. Cannot open BLE MIDI window.")
            return
        }
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

// Required delegate — centralManager needs it to report Bluetooth power state.
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
}
