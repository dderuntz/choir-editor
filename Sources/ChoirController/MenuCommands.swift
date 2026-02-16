import SwiftUI
import os

private let log = Logger(subsystem: "com.choir-arranger", category: "menu")

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
                                log.error("Error opening recent: \(error)")
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
    @ObservedObject var composerModel: ComposerModel
    
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if composerModel.canUndo {
                    composerModel.undo()
                } else {
                    model.undoManager.undo()
                }
            }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.undoManager.canUndo && !composerModel.canUndo)
            
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
    @AppStorage("showSettings") private var showSettings = false
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Intake (Settings)", isOn: $showSettings)
                .keyboardShortcut(",", modifiers: .command)

            Button("Compose") {
                NotificationCenter.default.post(name: .showComposer, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Listen (MIDI Tests)") {
                NotificationCenter.default.post(name: .showSoundPad, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Toggle("Show Keyboard", isOn: $showKeyboard)
                .keyboardShortcut("k", modifiers: [.command, .shift])
            
            Divider()
            
            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
        }
    }
}

// MARK: - Lyric Style

enum LyricStyle: String, CaseIterable, Identifiable {
    case senryu = "senryu"
    case bellman = "bellman"
    case kulning = "kulning"
    case dada = "dada"
    case nursery = "nursery"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .senryu: return "Senryū (Wry Robot)"
        case .bellman: return "Bellman (Warm Scenes)"
        case .kulning: return "Kulning (Mountain Signals)"
        case .dada: return "Dada (Absurdist)"
        case .nursery: return "Nursery (Dark Rhymes)"
        }
    }
}

// MARK: - Composer Menu Commands

struct ComposerCommands: Commands {
    @AppStorage("lyricStyle") private var lyricStyle: LyricStyle = .senryu

    var body: some Commands {
        CommandMenu("Composer") {
            Button("Open Composer") {
                NotificationCenter.default.post(name: .showComposer, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Picker("Lyric Style", selection: $lyricStyle) {
                ForEach(LyricStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
        }
    }
}

// MARK: - About Panel

struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Choir Arranger") {
                AppDelegate.showAboutPanel()
            }
        }
    }
}

// MARK: - Help Menu Commands

struct HelpCommands: Commands {
    private let repoURL = "https://github.com/dderuntz/choir-editor"
    
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("How to Use Choir Arranger") {
                if let url = URL(string: "\(repoURL)#getting-started") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            Button("About the Project") {
                if let url = URL(string: repoURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            
            Divider()
            
            Button("Report an Issue...") {
                if let url = URL(string: "\(repoURL)/issues") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - MIDI Menu Commands

struct MidiCommands: Commands {
    @ObservedObject var midiService: MidiService
    @ObservedObject var bluetoothManager: BluetoothMidiManager
    @ObservedObject var audioMonitor: AudioMonitorService
    @AppStorage("localAudioMode") private var localAudioMode = LocalAudioMode.automatic.rawValue
    
    var body: some Commands {
        CommandMenu("MIDI") {
            Button("Connect Bluetooth MIDI...") {
                bluetoothManager.showBluetoothMIDIWindow()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            
            Divider()
            
            Picker("Local Synth Monitor", selection: $localAudioMode) {
                ForEach(LocalAudioMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            
            Picker("Local Synth Engine", selection: Binding(
                get: { audioMonitor.engineType },
                set: { audioMonitor.setEngine($0) }
            )) {
                ForEach(SynthEngineType.allCases) { type in
                    Text(type.label).tag(type)
                }
            }
            
            Divider()
            
            Button("All Notes Off") { midiService.panicAllNotesOff() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Reconnect") { midiService.reconnect() }
        }
    }
}
