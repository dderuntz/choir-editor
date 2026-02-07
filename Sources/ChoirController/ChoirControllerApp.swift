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
            ViewCommands()
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

// MARK: - File Menu Commands

struct FileCommands: Commands {
    @ObservedObject var model: SequencerModel
    
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { model.newDocument() }
                .keyboardShortcut("n", modifiers: .command)
            
            Button("Open...") { model.showOpenDialog() }
                .keyboardShortcut("o", modifiers: .command)
            
            Divider()
            
            Button("Save") { model.saveCurrentOrPrompt() }
                .keyboardShortcut("s", modifiers: .command)
            
            Button("Save As...") { model.showSaveDialog() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
