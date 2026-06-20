import SwiftUI
import os

private let log = Logger(subsystem: "com.choir-arranger", category: "menu")

// MARK: - App Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case system  = "system"
    case english = "en"
    case swedish = "sv"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:  return "System Default"
        case .english: return "English"
        case .swedish: return "Svenska"
        }
    }

    /// Resolve to a concrete language (never returns .system).
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("sv") { return .swedish }
        return .english
    }
}

// MARK: - Localization Helper

/// Bundle for localized resources, respecting the user's chosen appLanguage.
/// Falls back to the base bundle if no .lproj exists for the selected language.
var localizedBundle: Bundle {
    let base: Bundle = {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }()
    let stored = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
    let lang = stored.resolved.rawValue
    if let path = base.path(forResource: lang, ofType: "lproj"),
       let langBundle = Bundle(path: path) {
        return langBundle
    }
    return base
}

/// Look up a localized string from the resource bundle.
/// UI element names embedded as **bold** in the catalog stay untranslated.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: localizedBundle)
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
        case .system: return L("appearance.system")
        case .light: return L("appearance.light")
        case .dark: return L("appearance.dark")
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
            Button(L("menu.new")) { model.newDocument() }
                .keyboardShortcut("n", modifiers: .command)

            Button(L("menu.open")) { actions.showOpenDialog() }
                .keyboardShortcut("o", modifiers: .command)

            // Open Recent submenu
            Menu {
                let recents = SequencerModel.recentFileURLs()
                if recents.isEmpty {
                    Text(L("menu.noRecentFiles"))
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

                    Button(L("menu.clearRecents")) {
                        SequencerModel.clearRecentFiles()
                    }
                }
            } label: {
                Text(L("menu.openRecent"))
            }

            Divider()

            Button(L("menu.save")) { actions.saveCurrentOrPrompt() }
                .keyboardShortcut("s", modifiers: .command)

            Button(L("menu.saveAs")) { actions.showSaveDialog() }
                .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button(L("menu.exportMIDI")) { actions.showExportMIDIDialog() }
                .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Export as OP-XY…") { actions.showExportXYDialog() }
                .keyboardShortcut("e", modifiers: [.command, .option, .shift])
        }
    }
}

// MARK: - Edit Menu Commands

struct EditCommands: Commands {
    @ObservedObject var model: SequencerModel
    @ObservedObject var composerModel: ComposerModel
    
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(L("menu.undo")) {
                if composerModel.canUndo {
                    composerModel.undo()
                } else {
                    model.undoManager.undo()
                }
            }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.undoManager.canUndo && !composerModel.canUndo)

            Button(L("menu.redo")) { model.undoManager.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.undoManager.canRedo)
        }

        CommandGroup(after: .pasteboard) {
            Button {
                model.togglePlaybackTrigger += 1
            } label: {
                Label(model.isPlaying ? L("menu.stop") : L("menu.play"), systemImage: model.isPlaying ? "stop.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])

            Button(L("menu.deleteNote")) { model.deleteSelectedNote() }
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
                Label(L("menu.preferences"), systemImage: "nose")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .showComposer, object: nil)
            } label: {
                Label(L("menu.compose"), systemImage: "eyebrow")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button {
                NotificationCenter.default.post(name: .showSoundPad, object: nil)
            } label: {
                Label(L("menu.test"), systemImage: "ear")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Toggle(isOn: $showKeyboard) {
                Label(L("menu.showKeyboard"), systemImage: "pianokeys")
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Picker(selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                Label(L("menu.appearance"), systemImage: "circle.lefthalf.filled")
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
    case svSenryu = "svSenryu"

    var id: String { rawValue }

    /// Which app language this style belongs to.
    var language: AppLanguage {
        switch self {
        case .svSenryu: return .swedish
        default: return .english
        }
    }

    /// Styles available for a given language (resolves .system automatically).
    static func styles(for language: AppLanguage) -> [LyricStyle] {
        let resolved = language.resolved
        return allCases.filter { $0.language == resolved }
    }

    var label: String {
        switch self {
        case .senryu: return "Senryū"
        case .bellman: return "Bellman"
        case .kulning: return "Kulning"
        case .dada: return "Dada"
        case .nursery: return "Nursery"
        case .svSenryu: return "Senryū (SV)"
        }
    }

    var blurb: String {
        switch self {
        case .senryu: return L("settings.lyricStyle.senryu")
        case .bellman: return L("settings.lyricStyle.bellman")
        case .kulning: return L("settings.lyricStyle.kulning")
        case .dada: return L("settings.lyricStyle.dada")
        case .nursery: return L("settings.lyricStyle.nursery")
        case .svSenryu: return L("settings.lyricStyle.svSenryu")
        }
    }

    var buttonLabel: String {
        switch self {
        case .senryu: return "Recompose as Senryū"
        case .bellman: return "Recompose as Bellman"
        case .kulning: return "Recompose as Kulning"
        case .dada: return "Recompose as Dada"
        case .nursery: return "Recompose as Nursery Rhyme"
        case .svSenryu: return "Skriv om som Senryū"
        }
    }

    var localizedButtonLabel: String {
        switch self {
        case .senryu: return L("composer.recompose.senryu")
        case .bellman: return L("composer.recompose.bellman")
        case .kulning: return L("composer.recompose.kulning")
        case .dada: return L("composer.recompose.dada")
        case .nursery: return L("composer.recompose.nursery")
        case .svSenryu: return L("composer.recompose.svSenryu")
        }
    }
}

// MARK: - Composer Menu Commands

struct ComposerCommands: Commands {
    @AppStorage("lyricStyle") private var lyricStyle: LyricStyle = .senryu
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system

    var body: some Commands {
        CommandMenu(L("menu.composer")) {
            Button {
                NotificationCenter.default.post(name: .showComposer, object: nil)
            } label: {
                Label(L("menu.openComposer"), systemImage: "eyebrow")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Picker(selection: $lyricStyle) {
                ForEach(LyricStyle.styles(for: appLanguage)) { style in
                    Text(style.label).tag(style)
                }
            } label: {
                Label(L("menu.lyricStyle"), systemImage: "pencil.and.scribble")
            }
        }
    }
}

// MARK: - About Panel

struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("menu.about")) {
                AppDelegate.showAboutPanel()
            }
        }
    }
}

// MARK: - Help Menu Commands

struct HelpCommands: Commands {
    @ObservedObject var onboardingManager: OnboardingManager
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system
    private let repoURL = "https://github.com/dderuntz/choir-editor"

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(L("menu.howToUse")) {
                if let url = URL(string: "\(repoURL)#getting-started") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button(L("menu.aboutProject")) {
                if let url = URL(string: repoURL) {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        appLanguage = lang
                    } label: {
                        HStack {
                            Text(lang.label)
                            if lang == appLanguage {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(L("menu.language"), systemImage: "globe")
            }

            Divider()

            Button(L("menu.resetTutorial")) {
                onboardingManager.reset()
            }

            Button(L("menu.resetAppQuit")) {
                onboardingManager.nukeEverything()
            }

            Divider()

            Button(L("menu.reportIssue")) {
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
                Label(L("menu.connectBluetooth"), systemImage: "antenna.radiowaves.left.and.right")
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Divider()

            Picker(selection: $localAudioMode) {
                ForEach(LocalAudioMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            } label: {
                Label(L("menu.localPlayback"), systemImage: "speaker.wave.3")
            }

            Picker(selection: Binding(
                get: { audioMonitor.engineType },
                set: { audioMonitor.setEngine($0) }
            )) {
                ForEach(SynthEngineType.allCases) { type in
                    Text(type.label).tag(type)
                }
            } label: {
                Label(L("menu.playbackEngine"), systemImage: "waveform")
            }

            Divider()

            Button {
                midiService.panicAllNotesOff()
            } label: {
                Label(L("menu.allNotesOff"), systemImage: "music.note.slash")
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            
        }
    }
}
