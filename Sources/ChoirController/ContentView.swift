import SwiftUI
import os

private let log = Logger(subsystem: "com.choir-arranger", category: "ui")

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

/// Blocks window dragging in this area (used with isMovableByWindowBackground).
struct NonDraggableArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NonDraggableView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    private class NonDraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

struct ContentView: View {
    @EnvironmentObject var bluetoothManager: BluetoothMidiManager
    @EnvironmentObject var model: SequencerModel
    @EnvironmentObject var composerModel: ComposerModel
    var midiService: MidiService // Passed explicitly, not observed (prevents redraw loop)
    @EnvironmentObject var audioMonitor: AudioMonitorService
    @AppStorage("showSettings") private var showSettingsStorage = false
    @State private var showSettings = false
    @State private var showSoundPad = false
    @State private var showBluetoothSetup = false
    @AppStorage("showComposer") private var showComposerStorage = false
    @State private var showComposer = false
    @AppStorage("showKeyboard") private var showKeyboardStorage = true
    @AppStorage("localAudioEnabled") private var localAudioEnabled = false
    @AppStorage("localAudioMode") private var localAudioMode = LocalAudioMode.automatic.rawValue
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
                            Image(systemName: "apple.classical.pages.fill")
                                .font(.title2)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(isSaving ? Theme.accent : Theme.text(colorScheme).opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("File")
                    
                    TextField("Untitled", text: $editingTitle, onCommit: { commitTitleEdit(); isTitleFocused = false })
                        .font(.system(size: showComposer ? 24 : 56, weight: showComposer ? .light : .ultraLight))
                        .kerning(showComposer ? -0.5 : -1.4)
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
                                .foregroundColor(Theme.text(colorScheme).opacity(0.85))
                                .padding(.horizontal, Theme.buttonPaddingH)
                                .padding(.vertical, Theme.buttonPaddingV)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.buttonRadius)
                                        .stroke(Theme.text(colorScheme).opacity(0.85), lineWidth: Theme.buttonStroke)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    // Settings toggle
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() } }) {
                        Image(systemName: "nose")
                            .font(.title2)
                            .foregroundColor(showSettings ? Theme.text(colorScheme) : Theme.text(colorScheme).opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Inhale")
                    
                    // Composer toggle
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) { showComposer.toggle() }
                    }) {
                        Image(systemName: "eyebrow")
                            .font(.title2)
                            .foregroundColor(showComposer ? Theme.text(colorScheme) : Theme.text(colorScheme).opacity(0.4))
                            .overlay(alignment: .topTrailing) {
                                if composerModel.hasContent && !showComposer {
                                    Circle()
                                        .fill(Theme.accent)
                                        .frame(width: 6, height: 6)
                                        .offset(x: 3, y: -3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Compose")
                    
                    // Listen
                    Button(action: { showSoundPad = true }) {
                        Image(systemName: "ear")
                            .font(.title2)
                            .foregroundColor(showSoundPad ? Theme.text(colorScheme) : Theme.text(colorScheme).opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Listen")
                    
                    // Keyboard toggle
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showKeyboard.toggle(); showKeyboardStorage = showKeyboard } }) {
                        Image(systemName: "pianokeys")
                            .font(.title2)
                            .foregroundColor(showKeyboard ? Theme.text(colorScheme).opacity(0.85) : Theme.text(colorScheme).opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Express")
                    
                    // Connection status indicator
                    Button(action: { startBluetoothSetup() }) {
                        ConnectionStatusView(midiService: midiService)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(midiService.isConnected
                                  ? Color(red: 0xD8/255, green: 0xD6/255, blue: 0xD3/255).opacity(0.6)
                                  : Theme.accent)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .help(midiService.isConnected ? "MIDI Connected" : "Tap to connect Bluetooth MIDI")
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                .background(Theme.bg(colorScheme))
                
                Theme.bg(colorScheme).opacity(0.15).frame(height: 1)
                
                // Main content: Composer or Sequencer
                ZStack(alignment: .bottom) {
                    if showComposer {
                        ComposerView(audioMonitor: audioMonitor, onDismiss: { showComposer = false })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(NonDraggableArea())
                            .padding(.bottom, showKeyboard ? 150 : 0)
                            .transition(.opacity)
                    } else {
                        SequencerView(midiService: midiService, audioMonitor: audioMonitor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(NonDraggableArea())
                            .padding(.bottom, showKeyboard ? 150 : 0)
                    }
                    
                    if showKeyboard {
                        KeyboardView(midiService: midiService, audioMonitor: audioMonitor, isComposerActive: showComposer)
                            .frame(height: 150)
                            .background(NonDraggableArea())
                            .background(Theme.bg(colorScheme))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.bg(colorScheme))
            .onTapGesture {
                if isTitleFocused { isTitleFocused = false }
            }
            
            // Collapsible Settings Panel (slides in from left)
            if showSettings {
                HStack(spacing: 0) {
                    SettingsPanelView(midiService: midiService, showSettings: $showSettings)
                        .frame(width: 280)
                        .background(Theme.bg(colorScheme))
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
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .frame(minWidth: 650, minHeight: 500)
        .onAppear {
            showKeyboard = showKeyboardStorage
            showComposer = showComposerStorage
            midiService.start()
            model.loadLastFileIfAvailable()
            applyLocalAudioMode()
        }
        .onChange(of: showKeyboardStorage) { newValue in
            withAnimation(.easeInOut(duration: 0.2)) { showKeyboard = newValue }
        }
        .onChange(of: showKeyboard) { newValue in
            showKeyboardStorage = newValue
        }
        .onChange(of: showComposerStorage) { newValue in
            withAnimation(.easeInOut(duration: 0.25)) { showComposer = newValue }
        }
        .onChange(of: showComposer) { newValue in
            showComposerStorage = newValue
        }
        .onChange(of: localAudioEnabled) { enabled in
            if enabled {
                audioMonitor.ensureStarted()
            } else {
                audioMonitor.tearDown()
            }
        }
        .onChange(of: localAudioMode) { _ in applyLocalAudioMode() }
        .onChange(of: midiService.isConnected) { _ in applyLocalAudioMode() }
        .onAppear { showSettings = showSettingsStorage }
        .onChange(of: showSettingsStorage) { newValue in
            withAnimation(.easeInOut(duration: 0.2)) { showSettings = newValue }
        }
        .onChange(of: showSettings) { newValue in
            showSettingsStorage = newValue
        }
        .onChange(of: showBluetoothSetup) { showing in
            // Close settings panel if Bluetooth setup opens (avoid both panels at once)
            if showing && showSettings {
                withAnimation(.easeInOut(duration: 0.2)) { showSettings = false }
            }
        }
        .onChange(of: midiService.isConnected) { connected in
            // Close Apple Bluetooth window when doll connects
            if connected {
                bluetoothManager.closeBluetoothMIDIWindow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSoundPad)) { _ in
            showSoundPad = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showComposer)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { showComposer = true }
        }
        .sheet(isPresented: $showSoundPad) {
            SoundPadView(midiService: midiService, audioMonitor: audioMonitor, isPresented: $showSoundPad)
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
            log.error("Rename failed: \(error)")
            syncTitleFromModel() // revert on failure
        }
    }
    
    private func flashSaveIndicator() {
        withAnimation(.easeIn(duration: 0.1)) { isSaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.3)) { isSaving = false }
        }
    }
    
    // MARK: - Local Audio Mode
    
    /// Resolve the three-state mode (automatic / on / off) into the boolean flag
    /// that every other view reads via @AppStorage("localAudioEnabled").
    private func applyLocalAudioMode() {
        let mode = LocalAudioMode(rawValue: localAudioMode) ?? .automatic
        switch mode {
        case .automatic:
            localAudioEnabled = !midiService.isConnected
        case .on:
            localAudioEnabled = true
        case .off:
            localAudioEnabled = false
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
        
        menu.addItem(NSMenuItem.separator())
        
        let exportItem = NSMenuItem(title: "Export as MIDI...", action: #selector(FileMenuActions.exportMIDI(_:)), keyEquivalent: "")
        exportItem.target = target
        menu.addItem(exportItem)
        
        if model.currentFileURL != nil {
            menu.addItem(NSMenuItem.separator())
            let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(FileMenuActions.revealInFinder(_:)), keyEquivalent: "")
            revealItem.target = target
            menu.addItem(revealItem)
        }
        
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
