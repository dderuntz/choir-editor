import SwiftUI
import CoreBluetooth

struct ConnectionView: View {
    @ObservedObject var bluetoothManager: BluetoothMidiManager
    @ObservedObject var midiService: MidiService
    
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
            
            Divider()
                .padding(.horizontal)
            
            // MIDI Destination Status
            VStack(alignment: .leading, spacing: 4) {
                Text("MIDI Destination")
                    .font(.headline)
                if let selected = midiService.selectedInput {
                    Text(selected.displayName)
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Text("Not selected")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
                .padding(.horizontal)
            
            // Voice Controls (Vibrato, Reverb)
            VoiceControlsView(midiService: midiService)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .frame(minWidth: 250, minHeight: 450)
    }
}
