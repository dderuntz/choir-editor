import SwiftUI

extension Notification.Name {
    static let showSoundPad = Notification.Name("showSoundPad")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        
        // Make window draggable by background since we hid the title bar
        if let window = NSApp.windows.first {
            window.isMovableByWindowBackground = true
        }
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
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            FileCommands(model: sequencerModel)
            EditCommands(model: sequencerModel)
            ViewCommands()
            MidiCommands(midiService: midiService, bluetoothManager: bluetoothManager)
        }
    }
}
