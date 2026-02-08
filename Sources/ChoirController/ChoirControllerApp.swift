import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
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
    
    var body: some Scene {
        WindowGroup {
            ContentView(midiService: midiService)
                .environmentObject(bluetoothManager)
                .environmentObject(midiService)
                .environmentObject(sequencerModel)
        }
        .windowResizability(.contentSize)
        .commands {
            FileCommands(model: sequencerModel)
            EditCommands(model: sequencerModel)
            ViewCommands()
            MidiCommands(midiService: midiService)
        }
    }
}

// MARK: - View Menu Commands

struct ViewCommands: Commands {
    @AppStorage("showKeyboard") private var showKeyboard = true
    @AppStorage("localAudioEnabled") private var localAudioEnabled = false
    
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Show Keyboard", isOn: $showKeyboard)
                .keyboardShortcut("k", modifiers: [.command, .shift])
            
            Divider()
            
            Toggle("Local Audio Monitor", isOn: $localAudioEnabled)
        }
    }
}

// MARK: - MIDI Menu Commands

struct MidiCommands: Commands {
    @ObservedObject var midiService: MidiService
    
    var body: some Commands {
        CommandMenu("MIDI") {
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
