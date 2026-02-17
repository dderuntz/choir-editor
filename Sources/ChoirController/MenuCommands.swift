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
            Menu {
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
            } label: {
                Text("Open Recent")
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
            Button {
                model.togglePlaybackTrigger += 1
            } label: {
                Label(model.isPlaying ? "Stop" : "Play", systemImage: model.isPlaying ? "stop.fill" : "play.fill")
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
            Toggle(isOn: $showSettings) {
                Label("Preferences", systemImage: "nose")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .showComposer, object: nil)
            } label: {
                Label("Compose", systemImage: "eyebrow")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button {
                NotificationCenter.default.post(name: .showSoundPad, object: nil)
            } label: {
                Label("Test (Dolls + MIDI)", systemImage: "ear")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Toggle(isOn: $showKeyboard) {
                Label("Show Keyboard", systemImage: "pianokeys")
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            
            Divider()
            
            Picker(selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
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
        case .senryu: return "Senryū"
        case .bellman: return "Bellman"
        case .kulning: return "Kulning"
        case .dada: return "Dada"
        case .nursery: return "Nursery"
        }
    }

    var blurb: String {
        switch self {
        case .senryu: return "A weary robot observes life with dry wit and quiet humor using the Japanese form called Senryū. It's like haiku but about human, err robot, nature."
        case .bellman: return "Warm, vivid scenes painted in simple words meant to be sung aloud. Inspired by the bellman — a town crier who sang the news. Golden light, painted windows, that sort of thing."
        case .kulning: return "A robot calls lost machines home across mountain valleys using kulning — a Scandinavian herding call meant to carry for miles. Sparse, haunting, nature and wire entwined."
        case .dada: return "A choir of robots embraces the surreal in the spirit of the Dada art movement. The fork left. The calendar sneezed. You get the idea."
        case .nursery: return "Nursery rhymes for robots. Timeless and simple in rhyme, fun to say aloud. Cute on the surface, and unsettling in your motherboard."
        }
    }

    var buttonLabel: String {
        switch self {
        case .senryu: return "Recompose as Senryū"
        case .bellman: return "Recompose as Bellman"
        case .kulning: return "Recompose as Kulning"
        case .dada: return "Recompose as Dada"
        case .nursery: return "Recompose as Nursery Rhyme"
        }
    }
}

// MARK: - Composer Menu Commands

struct ComposerCommands: Commands {
    @AppStorage("lyricStyle") private var lyricStyle: LyricStyle = .senryu

    var body: some Commands {
        CommandMenu("Composer") {
            Button {
                NotificationCenter.default.post(name: .showComposer, object: nil)
            } label: {
                Label("Open Composer", systemImage: "eyebrow")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Picker(selection: $lyricStyle) {
                ForEach(LyricStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            } label: {
                Label("Lyric Style", systemImage: "pencil.and.scribble")
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
    @ObservedObject var onboardingManager: OnboardingManager
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

            Button("Reset Tutorial") {
                onboardingManager.reset()
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
            Button {
                bluetoothManager.showBluetoothMIDIWindow()
            } label: {
                Label("Connect Bluetooth MIDI...", systemImage: "antenna.radiowaves.left.and.right")
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            
            Divider()
            
            Picker(selection: $localAudioMode) {
                ForEach(LocalAudioMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            } label: {
                Label("Local Playback", systemImage: "speaker.wave.3")
            }
            
            Picker(selection: Binding(
                get: { audioMonitor.engineType },
                set: { audioMonitor.setEngine($0) }
            )) {
                ForEach(SynthEngineType.allCases) { type in
                    Text(type.label).tag(type)
                }
            } label: {
                Label("Local Playback Engine", systemImage: "waveform")
            }
            
            Divider()
            
            Button {
                midiService.panicAllNotesOff()
            } label: {
                Label("All Notes Off", systemImage: "music.note.slash")
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            
        }
    }
}
