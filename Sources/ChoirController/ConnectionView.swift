import SwiftUI
import CoreBluetooth

struct ConnectionView: View {
    @ObservedObject var bluetoothManager: BluetoothMidiManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bluetooth MIDI Devices")
                    .font(.headline)
                Spacer()
                if bluetoothManager.isScanning {
                    ProgressView()
                        .scaleEffect(0.5)
                    Button("Stop Scan") {
                        bluetoothManager.stopScanning()
                    }
                } else {
                    Button("Scan") {
                        bluetoothManager.startScanning()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 20) // Add top padding for window controls
            
            List {
                Section(header: Text("Connected")) {
                    if bluetoothManager.connectedPeripherals.isEmpty {
                        Text("No devices connected")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(bluetoothManager.connectedPeripherals, id: \.identifier) { peripheral in
                            HStack {
                                Text(peripheral.name ?? "Unknown Device")
                                Spacer()
                                Button("Disconnect") {
                                    bluetoothManager.disconnect(from: peripheral)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Discovered")) {
                    if bluetoothManager.discoveredPeripherals.isEmpty {
                        Text(bluetoothManager.isScanning ? "Scanning..." : "No devices found")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(bluetoothManager.discoveredPeripherals, id: \.identifier) { peripheral in
                            HStack {
                                Text(peripheral.name ?? "Unknown Device")
                                Spacer()
                                Button("Connect") {
                                    bluetoothManager.connect(to: peripheral)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 250, minHeight: 300)
    }
}
