import SwiftUI

/// Transparent view that allows window dragging from its area.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DraggableView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    private class DraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

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
                                .font(Theme.buttonFont)
                                .fontWeight(Theme.buttonWeight)
                                .foregroundColor(Theme.toolbarActive)
                                .padding(.horizontal, Theme.buttonPaddingH)
                                .padding(.vertical, Theme.buttonPaddingV)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.buttonRadius)
                                        .stroke(Theme.toolbarActive, lineWidth: Theme.buttonStroke)
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
                    
                    // Explorer (tuning fork)
                    Button(action: { showSoundPad = true }) {
                        Image(systemName: "tuningfork")
                            .font(.title2)
                            .foregroundColor(showSoundPad ? Theme.accent : Theme.toolbarInactive)
                    }
                    .buttonStyle(.plain)
                    .help("Choir Explorer")
                    
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
                .padding(.bottom, 12)
                .background(WindowDragArea())
                .background(Theme.toolbar)
                
                Theme.divider.frame(height: 1)
                
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
            SoundPadView(midiService: midiService, isPresented: $showSoundPad)
                .frame(minWidth: 700, minHeight: 580)
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
    
    // MARK: - File Menu
    
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
