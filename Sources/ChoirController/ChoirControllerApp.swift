import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable window tabbing (tabs are meaningless in this single-document app)
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}

@main
struct ChoirControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bluetoothManager = BluetoothMidiManager()
    @StateObject private var midiService = MidiService()
    @StateObject private var sequencerModel = SequencerModel()
    
    init() {
        // Ensure the app activates properly when run from command line
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        
        // Auto-open last file is handled in ContentView.onAppear
    }
    
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    var body: some Scene {
        WindowGroup {
            ContentView(midiService: midiService)
                .environmentObject(bluetoothManager)
                .environmentObject(midiService)
                .environmentObject(sequencerModel)
                .preferredColorScheme(appearanceMode.colorScheme)
                .tint(Theme.accent)
        }
        .windowResizability(.contentSize)
        .commands {
            FileCommands(model: sequencerModel)
            EditCommands(model: sequencerModel)
            ViewCommands()
            MidiCommands(midiService: midiService, bluetoothManager: bluetoothManager)
        }
    }
}

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

// MARK: - View Menu Commands

struct ViewCommands: Commands {
    @AppStorage("showKeyboard") private var showKeyboard = true
    @AppStorage("localAudioEnabled") private var localAudioEnabled = false
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Show Keyboard", isOn: $showKeyboard)
                .keyboardShortcut("k", modifiers: [.command, .shift])
            
            Divider()
            
            Toggle("Local Audio Monitor", isOn: $localAudioEnabled)
            
            Divider()
            
            Menu("Appearance") {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button {
                        appearanceMode = mode
                    } label: {
                        if appearanceMode == mode {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Text(mode.label)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - MIDI Menu Commands

struct MidiCommands: Commands {
    @ObservedObject var midiService: MidiService
    @ObservedObject var bluetoothManager: BluetoothMidiManager
    
    var body: some Commands {
        CommandMenu("MIDI") {
            Button("Connect Bluetooth MIDI...") {
                bluetoothManager.showBluetoothMIDIWindow()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            
            Divider()
            
            Button("All Notes Off") { midiService.panicAllNotesOff() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Reconnect") { midiService.reconnect() }
        }
    }
}

// MARK: - Edit Menu Commands

struct EditCommands: Commands {
    @ObservedObject var model: SequencerModel
    
    var body: some Commands {
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

// MARK: - File Menu Commands

struct FileCommands: Commands {
    @ObservedObject var model: SequencerModel
    
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { model.newDocument() }
                .keyboardShortcut("n", modifiers: .command)
            
            Button("Open...") { model.showOpenDialog() }
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
            
            Button("Save") { model.saveCurrentOrPrompt() }
                .keyboardShortcut("s", modifiers: .command)
            
            Button("Save As...") { model.showSaveDialog() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
