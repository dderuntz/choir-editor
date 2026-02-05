import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bluetoothManager: BluetoothMidiManager
    @EnvironmentObject var midiService: MidiService
    @State private var showSettings = false
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Main Content Area
            VStack(spacing: 0) {
                // Top bar with title and connection status
                HStack {
                    // Settings toggle
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() } }) {
                        Image(systemName: showSettings ? "sidebar.left" : "sidebar.left")
                            .font(.title2)
                            .foregroundColor(showSettings ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Settings Panel")
                    
                    Text("Choir Controller")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Connection status indicator
                    ConnectionStatusView(midiService: midiService)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                // Main content
                VStack {
                    // Sequencer
                    SequencerView(midiService: midiService)
                        .frame(maxWidth: 550)
                        .padding(.top, 20)
                    
                    Spacer()
                    
                    // Piano Keyboard
                    KeyboardView(midiService: midiService)
                        .frame(height: 180)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            // Collapsible Settings Panel (slides in from left)
            if showSettings {
                HStack(spacing: 0) {
                    SettingsPanelView(bluetoothManager: bluetoothManager, midiService: midiService, showSettings: $showSettings)
                        .frame(width: 280)
                        .background(Color(NSColor.controlBackgroundColor))
                        .transition(.move(edge: .leading))
                    
                    // Dimmed overlay to close
                    Color.black.opacity(0.1)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { showSettings = false }
                        }
                }
            }
        }
        .frame(minWidth: 650, minHeight: 500)
        .onAppear {
            midiService.start()
        }
    }
}

// Compact connection status for top-right
struct ConnectionStatusView: View {
    @ObservedObject var midiService: MidiService
    
    var body: some View {
        HStack(spacing: 6) {
            // Status dot
            Circle()
                .fill(midiService.selectedInput != nil ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            
            // Device name or status
            if let selected = midiService.selectedInput {
                Text(selected.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text("No MIDI")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
}

// Settings panel content (collapsible)
struct SettingsPanelView: View {
    @ObservedObject var bluetoothManager: BluetoothMidiManager
    @ObservedObject var midiService: MidiService
    @Binding var showSettings: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSettings = false } }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Voice Controls
                    GroupBox("Voice Controls") {
                        VoiceControlsView(midiService: midiService)
                    }
                    
                    // Bluetooth MIDI
                    GroupBox("Bluetooth MIDI") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                if bluetoothManager.isScanning {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("Scanning...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("Stop") {
                                        bluetoothManager.stopScanning()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Button("Scan for Devices") {
                                        bluetoothManager.startScanning()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            
                            if !bluetoothManager.connectedPeripherals.isEmpty {
                                Divider()
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(bluetoothManager.connectedPeripherals, id: \.identifier) { peripheral in
                                    HStack {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                        Text(peripheral.name ?? "Unknown")
                                            .font(.caption)
                                        Spacer()
                                        Button("Disconnect") {
                                            bluetoothManager.disconnect(from: peripheral)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }
                            }
                            
                            if !bluetoothManager.discoveredPeripherals.isEmpty {
                                Divider()
                                Text("Discovered")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(bluetoothManager.discoveredPeripherals, id: \.identifier) { peripheral in
                                    HStack {
                                        Text(peripheral.name ?? "Unknown")
                                            .font(.caption)
                                        Spacer()
                                        Button("Connect") {
                                            bluetoothManager.connect(to: peripheral)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }
                            }
                        }
                    }
                    
                    // MIDI Destination
                    GroupBox("MIDI Output") {
                        VStack(alignment: .leading, spacing: 4) {
                            if let selected = midiService.selectedInput {
                                HStack {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 6, height: 6)
                                    Text(selected.displayName)
                                        .font(.caption)
                                }
                            } else {
                                Text("No MIDI destination selected")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}
