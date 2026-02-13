import SwiftUI
import MIDIKitIO

struct ContentView: View {
    @EnvironmentObject var bluetoothManager: BluetoothMidiManager
    @EnvironmentObject var model: SequencerModel
    var midiService: MidiService // Passed explicitly, not observed (prevents redraw loop)
    @StateObject private var audioMonitor = AudioMonitorService()
    @State private var showSettings = false
    @State private var showSoundPad = false
    @State private var showBluetoothSetup = false
    @AppStorage("showKeyboard") private var showKeyboardStorage = true
    @AppStorage("localAudioEnabled") private var localAudioEnabled = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showKeyboard = true
    @State private var editingTitle: String = ""
    @State private var isSaving = false
    @FocusState private var isTitleFocused: Bool
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Main Content Area
            VStack(spacing: 0) {
                // Top bar with title and connection status
                HStack {
                    // App icon with file menu
                    Button(action: { showFileMenu() }) {
                        HStack(spacing: 2) {
                            Image(systemName: "doc.fill")
                                .font(.title2)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(isSaving ? Theme.accent : Theme.toolbarActive)
                    }
                    .buttonStyle(.plain)
                    .help("File")
                    
                    TextField("Untitled", text: $editingTitle, onCommit: { commitTitleEdit(); isTitleFocused = false })
                        .font(.system(size: 56, weight: .ultraLight))
                        .kerning(-1.4)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .tint(Theme.accent)
                        .fixedSize()
                        .onAppear {
                            syncTitleFromModel()
                            // Ensure not focused on launch
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isTitleFocused = false
                            }
                        }
                        .onChange(of: model.currentFileURL) { _ in syncTitleFromModel() }
                        .onChange(of: isTitleFocused) { focused in
                            if !focused { commitTitleEdit() }
                        }
                    
                    // Done button — only visible while editing title, right next to title
                    if isTitleFocused {
                        Button(action: { commitTitleEdit(); isTitleFocused = false }) {
                            Text("Done")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.toolbarActive)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Theme.toolbarActive, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    // Settings toggle
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() } }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(showSettings ? Theme.accent : Theme.toolbarInactive)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    
                    // Keyboard toggle
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showKeyboard.toggle(); showKeyboardStorage = showKeyboard } }) {
                        Image(systemName: "pianokeys")
                            .font(.title2)
                            .foregroundColor(showKeyboard ? Theme.toolbarActive : Theme.toolbarInactive)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Keyboard")
                    
                    // Connection status indicator (tappable to open Bluetooth setup)
                    ConnectionStatusView(midiService: midiService)
                        .onTapGesture {
                            startBluetoothSetup()
                        }
                        .help(midiService.isConnected ? "MIDI Connected" : "Tap to connect Bluetooth MIDI")
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
            .onTapGesture {
                if isTitleFocused { isTitleFocused = false }
            }
            
            // Collapsible Settings Panel (slides in from left)
            if showSettings {
                HStack(spacing: 0) {
                    SettingsPanelView(midiService: midiService, showSettings: $showSettings)
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
            
            // Bluetooth Setup Panel (slides in from right)
            if showBluetoothSetup {
                HStack(spacing: 0) {
                    // Dimmed overlay to close
                    Theme.overlay(colorScheme)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { showBluetoothSetup = false }
                        }
                    
                    BluetoothSetupPanel(
                        midiService: midiService,
                        isPresented: $showBluetoothSetup,
                        onOpenBluetoothWindow: { bluetoothManager.showBluetoothMIDIWindow() }
                    )
                    .frame(width: 300)
                    .background(Theme.surface)
                    .transition(.move(edge: .trailing))
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
        .onChange(of: showBluetoothSetup) { showing in
            // Close settings panel if Bluetooth setup opens (avoid both panels at once)
            if showing && showSettings {
                withAnimation(.easeInOut(duration: 0.2)) { showSettings = false }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSoundPad)) { _ in
            showSoundPad = true
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
    
    // MARK: - Title Editing
    
    private func syncTitleFromModel() {
        editingTitle = model.currentFileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }
    
    private func commitTitleEdit() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            syncTitleFromModel() // revert to current name
            return
        }
        let currentName = model.currentFileURL?.deletingPathExtension().lastPathComponent ?? ""
        guard trimmed != currentName else { return } // no change
        
        do {
            try model.renameFile(to: trimmed)
            flashSaveIndicator()
        } catch {
            print("Rename failed: \(error)")
            syncTitleFromModel() // revert on failure
        }
    }
    
    private func flashSaveIndicator() {
        withAnimation(.easeIn(duration: 0.1)) { isSaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.3)) { isSaving = false }
        }
    }
    
    // MARK: - Bluetooth Setup Flow
    
    /// Opens the instruction panel and Apple's BLE MIDI window simultaneously
    private func startBluetoothSetup() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showBluetoothSetup = true
        }
        bluetoothManager.showBluetoothMIDIWindow()
    }
    
    private func showFileMenu() {
        let target = FileMenuActions.shared
        target.model = model
        let menu = NSMenu()
        
        let newItem = NSMenuItem(title: "New", action: #selector(FileMenuActions.newDoc(_:)), keyEquivalent: "")
        newItem.target = target
        menu.addItem(newItem)
        
        let openItem = NSMenuItem(title: "Open...", action: #selector(FileMenuActions.openDoc(_:)), keyEquivalent: "")
        openItem.target = target
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let recentURLs = SequencerModel.recentFileURLs()
        if !recentURLs.isEmpty {
            let recentMenu = NSMenu()
            let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
            recentItem.submenu = recentMenu
            for url in recentURLs {
                let item = NSMenuItem(title: url.deletingPathExtension().lastPathComponent, action: #selector(FileMenuActions.openRecent(_:)), keyEquivalent: "")
                item.target = target
                item.representedObject = url
                recentMenu.addItem(item)
            }
            recentMenu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear Recents", action: #selector(FileMenuActions.clearRecents(_:)), keyEquivalent: "")
            clearItem.target = target
            recentMenu.addItem(clearItem)
            menu.addItem(recentItem)
        }
        
        if model.currentFileURL != nil {
            menu.addItem(NSMenuItem.separator())
            let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(FileMenuActions.revealInFinder(_:)), keyEquivalent: "")
            revealItem.target = target
            menu.addItem(revealItem)
        }
        
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

// Helper for NSMenu actions
@MainActor
class FileMenuActions: NSObject {
    static let shared = FileMenuActions()
    var model: SequencerModel?
    
    @objc func newDoc(_ sender: Any?) { model?.newDocument() }
    @objc func openDoc(_ sender: Any?) { model?.showOpenDialog() }
    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        try? model?.load(from: url)
    }
    @objc func clearRecents(_ sender: Any?) { SequencerModel.clearRecentFiles() }
    @objc func revealInFinder(_ sender: Any?) {
        guard let url = model?.currentFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// Compact connection status for top-right
struct ConnectionStatusView: View {
    @ObservedObject var midiService: MidiService
    
    var body: some View {
        HStack(spacing: 6) {
            if let selected = midiService.selectedInput {
                // Connected — subtle indicator
                Circle()
                    .fill(Theme.statusConnected)
                    .frame(width: 8, height: 8)
                Text(selected.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                // Not connected — loud call-to-action
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Text("Connect")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            midiService.selectedInput != nil
                ? Theme.surface.opacity(0.5)
                : Theme.accent
        )
        .cornerRadius(12)
        .contentShape(Rectangle()) // Makes entire area tappable
    }
}

// Settings panel content (collapsible)
struct SettingsPanelView: View {
    @ObservedObject var midiService: MidiService
    @Binding var showSettings: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — matches doc title style
            HStack {
                Text("Setup")
                    .font(.system(size: 56, weight: .ultraLight))
                    .kerning(-1.4)
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSettings = false } }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(Theme.toolbarInactive)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Theme.surface)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Sequencer Settings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sequencer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        SliderWithDefault(label: "Tempo", value: $midiService.tempo, range: 40...200, defaultValue: 100, displayText: "\(Int(midiService.tempo))", displayWidth: 30) { val in
                            (val / 5).rounded() * 5
                        }
                        
                        SliderWithDefault(label: "Min Note", value: $midiService.minNoteDuration, range: 0.01...0.5, defaultValue: 0.28, displayText: "\(Int(midiService.minNoteDuration * 1000))ms", displayWidth: 40) { val in
                            (val * 100).rounded() / 100
                        }
                    }
                    
                    Divider()
                    
                    // Voice Controls
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Global Choir Effects")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        VoiceControlsView(midiService: midiService)
                    }
                    
                    Divider()
                    
                    Button(action: {
                        midiService.tempo = 100
                        midiService.minNoteDuration = 0.28
                        midiService.vibrato = ChoirDefaults.vibrato
                        midiService.reverb = ChoirDefaults.reverb
                    }) {
                        Text("Reset Defaults")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
        }
    }
}

// MARK: - Slider with Default Dot

struct SliderWithDefault: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    let displayText: String
    var displayWidth: CGFloat = 30
    var snap: ((Double) -> Double)? = nil
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 80, alignment: .leading)
            Slider(value: $value, in: range)
                .onChange(of: value) { val in
                    if let snap = snap { value = snap(val) }
                }
                .background(defaultDot)
            Text(displayText)
                .font(.caption).monospacedDigit()
                .frame(width: displayWidth)
        }
    }
    
    private var nearDefault: Bool {
        let totalRange = range.upperBound - range.lowerBound
        return abs(value - defaultValue) / totalRange < 0.03
    }
    
    private var defaultDot: some View {
        GeometryReader { geo in
            let trackInset: CGFloat = 10
            let trackWidth = geo.size.width - trackInset * 2
            let fraction = (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = trackInset + trackWidth * CGFloat(fraction)
            Circle()
                .fill(Color.white.opacity(nearDefault ? 0 : 0.35))
                .frame(width: 6, height: 6)
                .position(x: x, y: geo.size.height / 2)
                .allowsHitTesting(false)
        }
    }
}
