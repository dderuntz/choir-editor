import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bluetoothManager: BluetoothMidiManager
    @EnvironmentObject var model: SequencerModel
    var midiService: MidiService // Passed explicitly, not observed (prevents redraw loop)
    @StateObject private var audioMonitor = AudioMonitorService()
    @State private var showSettings = false
    @State private var showSoundPad = false
    @AppStorage("showKeyboard") private var showKeyboardStorage = true
    @AppStorage("localAudioEnabled") private var localAudioEnabled = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showKeyboard = true
    
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
                            .foregroundColor(showSettings ? Theme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Settings Panel")
                    
                    Text("Choir Arranger")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Sound Pad (test/browser tool)
                    Button(action: { showSoundPad = true }) {
                        Image(systemName: "waveform")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Sound Pad")
                    
                    // Keyboard toggle
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showKeyboard.toggle(); showKeyboardStorage = showKeyboard } }) {
                        Image(systemName: "pianokeys")
                            .font(.title2)
                            .foregroundColor(showKeyboard ? Theme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Keyboard")
                    
                    // Connection status indicator
                    ConnectionStatusView(midiService: midiService)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Theme.window)
                
                Divider()
                
                // Sequencer fills available space, keyboard is collapsible pane below
                ZStack(alignment: .bottom) {
                    SequencerView(midiService: midiService, audioMonitor: audioMonitor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, showKeyboard ? 150 : 0)
                    
                    if showKeyboard {
                        KeyboardView(midiService: midiService, audioMonitor: audioMonitor)
                            .frame(height: 150)
                            .background(Theme.window)
                            .compositingGroup()
                            .shadow(color: Theme.keyboardShadow(colorScheme), radius: 12, x: 0, y: -4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.window)
            
            // Collapsible Settings Panel (slides in from left)
            if showSettings {
                HStack(spacing: 0) {
                    SettingsPanelView(bluetoothManager: bluetoothManager, midiService: midiService, showSettings: $showSettings)
                        .frame(width: 280)
                        .background(Theme.surface)
                        .transition(.move(edge: .leading))
                    
                    // Dimmed overlay to close
                    Theme.overlay(colorScheme)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { showSettings = false }
                        }
                }
            }
        }
        .frame(minWidth: 650, minHeight: 500)
        .onAppear {
            showKeyboard = showKeyboardStorage
            midiService.start()
            model.loadLastFileIfAvailable()
        }
        .onChange(of: showKeyboardStorage) { newValue in
            withAnimation(.easeInOut(duration: 0.2)) { showKeyboard = newValue }
        }
        .onChange(of: showKeyboard) { newValue in
            showKeyboardStorage = newValue
        }
        .onChange(of: localAudioEnabled) { enabled in
            if enabled {
                audioMonitor.ensureStarted()
            } else {
                audioMonitor.tearDown()
            }
        }
        .sheet(isPresented: $showSoundPad) {
            VStack(spacing: 0) {
                // Sheet header with close button
                HStack {
                    Text("Sound Pad")
                        .font(.headline)
                    Spacer()
                    Button(action: { showSoundPad = false }) {
                        Text("Done")
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
                
                Divider()
                
                ScrollView {
                    SoundPadView(midiService: midiService)
                }
            }
            .frame(minWidth: 700, minHeight: 500)
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
                .fill(midiService.selectedInput != nil ? Theme.statusConnected : Theme.statusWarning)
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
                    .foregroundColor(Theme.statusWarning)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.surface.opacity(0.5))
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
            .background(Theme.surface)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Sequencer Settings
                    GroupBox("Sequencer Settings") {
                        VStack(alignment: .leading, spacing: 10) {
                            // Tempo
                            HStack {
                                Text("Tempo:")
                                    .font(.caption)
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $midiService.tempo, in: 40...200, step: 5)
                                Text("\(Int(midiService.tempo))")
                                    .font(.caption).monospacedDigit()
                                    .frame(width: 30)
                            }
                            
                            // Min Note
                            HStack {
                                Text("Min Note:")
                                    .font(.caption)
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $midiService.minNoteDuration, in: 0.01...0.5, step: 0.01)
                                Text("\(Int(midiService.minNoteDuration * 1000))ms")
                                    .font(.caption).monospacedDigit()
                                    .frame(width: 40)
                            }
                            
                            // Consonant Length
                            HStack {
                                Text("Consonant:")
                                    .font(.caption)
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $midiService.consonantDuration, in: 0.05...0.6, step: 0.05)
                                Text("\(midiService.consonantDuration, specifier: "%.2f")b")
                                    .font(.caption).monospacedDigit()
                                    .frame(width: 40)
                            }
                        }
                    }
                    
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
                                            .fill(Theme.statusConnected)
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
                                        .fill(Theme.statusConnected)
                                        .frame(width: 6, height: 6)
                                    Text(selected.displayName)
                                        .font(.caption)
                                }
                            } else {
                                Text("No MIDI destination selected")
                                    .font(.caption)
                                    .foregroundColor(Theme.statusWarning)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}
