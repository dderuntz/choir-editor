import SwiftUI

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - File Menu Commands

struct FileCommands: Commands {
    @ObservedObject var model: SequencerModel
    
    private var actions: FileMenuActions {
        let a = FileMenuActions.shared
        a.model = model
        return a
    }
    
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { model.newDocument() }
                .keyboardShortcut("n", modifiers: .command)
            
            Button("Open...") { actions.showOpenDialog() }
                .keyboardShortcut("o", modifiers: .command)
            
            // Open Recent submenu
            Menu("Open Recent") {
                let recents = SequencerModel.recentFileURLs()
                if recents.isEmpty {
                    Text("No Recent Files")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(recents, id: \.path) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            do {
                                try model.load(from: url)
                            } catch {
                                print("Error opening recent: \(error)")
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button("Clear Recents") {
                        SequencerModel.clearRecentFiles()
                    }
                }
            }
            
            Divider()
            
            Button("Save") { actions.saveCurrentOrPrompt() }
                .keyboardShortcut("s", modifiers: .command)
            
            Button("Save As...") { actions.showSaveDialog() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Export as MIDI...") { actions.showExportMIDIDialog() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }
}

// MARK: - Edit Menu Commands

struct EditCommands: Commands {
    @ObservedObject var model: SequencerModel
    
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model.undoManager.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.undoManager.canUndo)
            
            Button("Redo") { model.undoManager.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.undoManager.canRedo)
        }
        
        CommandGroup(after: .pasteboard) {
            Button(model.isPlaying ? "Stop" : "Play") {
                model.togglePlaybackTrigger += 1
            }
            .keyboardShortcut(.space, modifiers: [])
            
            Button("Delete Note") { model.deleteSelectedNote() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selectedNoteIds.isEmpty)
        }
    }
}

// MARK: - View Menu Commands

struct ViewCommands: Commands {
    @AppStorage("showKeyboard") private var showKeyboard = true
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Show Keyboard", isOn: $showKeyboard)
                .keyboardShortcut("k", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Choir Explorer") {
                NotificationCenter.default.post(name: .showSoundPad, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            
            Divider()
            
            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
        }
    }
}

// MARK: - MIDI Menu Commands

struct MidiCommands: Commands {
    @ObservedObject var midiService: MidiService
    @ObservedObject var bluetoothManager: BluetoothMidiManager
    @AppStorage("localAudioEnabled") private var localAudioEnabled = false
    
    var body: some Commands {
        CommandMenu("MIDI") {
            Button("Connect Bluetooth MIDI...") {
                bluetoothManager.showBluetoothMIDIWindow()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            
            Divider()
            
            Toggle("Local Synth Monitor", isOn: $localAudioEnabled)
            
            Divider()
            
            Button("All Notes Off") { midiService.panicAllNotesOff() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Reconnect") { midiService.reconnect() }
        }
    }
}
