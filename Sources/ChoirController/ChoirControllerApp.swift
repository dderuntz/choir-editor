import SwiftUI

extension Notification.Name {
    static let showSoundPad = Notification.Name("showSoundPad")
    static let showComposer = Notification.Name("showComposer")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by ChoirControllerApp so we can clean up on quit.
    weak var midiService: MidiService?
    weak var audioMonitor: AudioMonitorService?
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        midiService?.panicAllNotesOff()
        audioMonitor?.tearDown()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        DispatchQueue.main.async {
            NSApp.windows.forEach { $0.isMovableByWindowBackground = true }
        }
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    static func showAboutPanel() {
        let credits = """
        A sequencer for composing phoneme-based choral \
        arrangements for robotic singing dolls.

        Type or summon lyrics, reveal phonemes, tune each \
        chip's consonant and vowel, then send the sequence \
        over MIDI to a choir of dolls.

        Intake → Compose → Listen → Express
        """
        let attrCredits = NSAttributedString(
            string: credits,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: attrCredits
        ])
    }
}

@main
struct ChoirControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var bluetoothManager = BluetoothMidiManager()
    @StateObject private var midiService = MidiService()
    @StateObject private var sequencerModel = SequencerModel()
    @StateObject private var audioMonitor = AudioMonitorService()
    @StateObject private var composerModel = ComposerModel()
    
    init() {
        // Ensure the app activates properly when run from command line
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        // Give the delegate references for cleanup on quit
        appDelegate.midiService = midiService
        appDelegate.audioMonitor = audioMonitor
    }
    
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    var body: some Scene {
        WindowGroup {
            ContentView(midiService: midiService)
                .environmentObject(bluetoothManager)
                .environmentObject(midiService)
                .environmentObject(sequencerModel)
                .environmentObject(audioMonitor)
                .environmentObject(composerModel)
                .preferredColorScheme(appearanceMode.colorScheme)
                .tint(Theme.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            AboutCommands()
            FileCommands(model: sequencerModel)
            EditCommands(model: sequencerModel, composerModel: composerModel)
            ViewCommands()
            MidiCommands(midiService: midiService, bluetoothManager: bluetoothManager, audioMonitor: audioMonitor)
            ComposerCommands()
            HelpCommands()
        }
    }
}
