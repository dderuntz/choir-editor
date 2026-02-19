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
    @State private var showComposerHelp = false
    @State private var emptyHelperDismissed = false
    @State private var hasCompletedInitialLoad = false
    @State private var showRollEntryModal = false
    @FocusState private var isTitleFocused: Bool

    // Onboarding
    @EnvironmentObject var onboarding: OnboardingManager
    @State private var showKeyboardHint = false
    @State private var showComposerHint = false
    @State private var keyboardHintTimer: Timer?
    @State private var composerHintTimer: Timer?
    
    private var isEmptyState: Bool {
        model.notes.isEmpty && !composerModel.hasContent
    }

    /// Keyboard is unavailable when in composer with no phoneme chips
    private var keyboardAvailable: Bool {
        !showComposer || !composerModel.phonemes.isEmpty
    }
    
    private var showEmptyHelper: Bool {
        // Show on true empty state, OR when Reset Tutorial forces it
        (isEmptyState && !emptyHelperDismissed && hasCompletedInitialLoad) || onboarding.showIntroPicker
    }
    
    var body: some View {
        rootContent
            .frame(minWidth: 650, minHeight: 500)
            .onAppear(perform: handleAppear)
            .modifier(ContentViewEventHandlers(
                showKeyboardStorage: $showKeyboardStorage,
                showKeyboard: $showKeyboard,
                showComposerStorage: $showComposerStorage,
                showComposer: $showComposer,
                showSettingsStorage: $showSettingsStorage,
                showSettings: $showSettings,
                showBluetoothSetup: $showBluetoothSetup,
                showSoundPad: $showSoundPad,
                emptyHelperDismissed: $emptyHelperDismissed,
                isEmptyState: isEmptyState,
                midiService: midiService,
                audioMonitor: audioMonitor,
                model: model,
                composerModel: composerModel,
                bluetoothManager: bluetoothManager,
                onboarding: onboarding,
                localAudioEnabled: $localAudioEnabled,
                localAudioMode: localAudioMode,
                applyLocalAudioMode: applyLocalAudioMode
            ))
            // Piano roll onboarding: keyboard hint (8s after transport tip dismissed)
            .onReceive(NotificationCenter.default.publisher(for: .rollTransportTipDismissed)) { _ in
                guard !onboarding.hasSeenKeyboardHint else { return }
                keyboardHintTimer?.invalidate()
                keyboardHintTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in
                    Task { @MainActor in showKeyboardHint = true }
                }
            }
            .onChange(of: showKeyboardHint) { wasShowing, isShowing in
                if wasShowing && !isShowing {
                    onboarding.hasSeenKeyboardHint = true
                    // Start composer hint timer (15s) if user hasn't visited composer
                    if !onboarding.hasSeenComposerHint && !onboarding.hasVisitedComposer {
                        composerHintTimer?.invalidate()
                        composerHintTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
                            Task { @MainActor in showComposerHint = true }
                        }
                    }
                }
            }
            .onChange(of: showComposerHint) { wasShowing, isShowing in
                if wasShowing && !isShowing {
                    onboarding.hasSeenComposerHint = true
                }
            }
            // Cancel pending roll hints if user navigates to composer
            .onChange(of: showComposer) { _, isComposer in
                if isComposer {
                    keyboardHintTimer?.invalidate()
                    composerHintTimer?.invalidate()
                    showKeyboardHint = false
                    showComposerHint = false
                }
            }
    }

    private func handleAppear() {
        showSettings = showSettingsStorage
        midiService.start()
        model.loadLastFileIfAvailable()
        hasCompletedInitialLoad = true
        applyLocalAudioMode()

        let isEmpty = model.notes.isEmpty && !composerModel.hasContent

        // Default to piano roll on empty launch so the empty-state helper
        // isn't competing with the composer view behind it
        if isEmpty {
            showComposer = false
            showKeyboard = false  // hide keyboard on fresh/empty launch
        } else {
            showComposer = showComposerStorage
            showKeyboard = showKeyboardStorage
        }

        // Trigger phonemes explanation if composer is already showing on launch
        // (onChange won't fire for the initial value)
        if showComposer {
            onboarding.showChipsExplanationIfNeeded(hasPhonemes: !composerModel.phonemes.isEmpty)
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

    // MARK: - Onboarding


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

    // MARK: - Root Content

    private var rootContent: some View {
        ZStack(alignment: .leading) {
            mainContentArea
            if showSettings { settingsPanel }
            if showBluetoothSetup { bluetoothPanel }
            if showEmptyHelper {
                EmptyStateHelperModal(
                    onStartWithMelody: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            emptyHelperDismissed = true
                            onboarding.dismissIntroPicker()
                            if showComposer { showComposer = false }
                        }
                        // Give a beat before showing the roll entry modal
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRollEntryModal = true
                            }
                        }
                    },
                    onStartWithIdeas: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            emptyHelperDismissed = true
                            onboarding.dismissIntroPicker()
                            if !showComposer { showComposer = true }
                        }
                    },
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            emptyHelperDismissed = true
                            onboarding.dismissIntroPicker()
                        }
                    }
                )
            }
            // ChipsExplanation is now a popover on the text field in ComposerView
            if onboarding.showFirstPlayModal {
                FirstPlayGuideModal(onConnectDolls: startBluetoothSetup)
            }
            if showRollEntryModal {
                PianoRollEntryModal(
                    onStartAdding: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRollEntryModal = false
                        }
                        NotificationCenter.default.post(name: .rollStartAdding, object: nil)
                    },
                    onLoadDemo: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRollEntryModal = false
                        }
                        model.loadDemoFile()
                        // Kick off demo onboarding path after a brief settle
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            NotificationCenter.default.post(name: .rollDemoLoaded, object: nil)
                        }
                    },
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRollEntryModal = false
                        }
                    }
                )
            }
        }
    }

    // MARK: - Main Layout

    private var mainContentArea: some View {
        VStack(spacing: 0) {
            toolbar
            Theme.bg(colorScheme).opacity(0.15).frame(height: 1)
            mainContent
        }
        .background(Theme.bg(colorScheme))
        .onTapGesture {
            if isTitleFocused { isTitleFocused = false }
        }
        .allowsHitTesting(!showSettings && !showBluetoothSetup)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolbarLeading
            Spacer()
            toolbarTrailing
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .background(Theme.bg(colorScheme))
    }

    private var toolbarLeading: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 4) {
                Button(action: { showFileMenu() }) {
                    HStack(spacing: 2) {
                        Image(systemName: "apple.classical.pages.fill")
                            .font(.system(size: Theme.toolbarIconSize, weight: .light))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(Theme.text(colorScheme).opacity(isSaving ? 0.35 : 1))
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isTitleFocused = false
                        }
                    }
                    .onChange(of: model.currentFileURL) { syncTitleFromModel() }
                    .onChange(of: isTitleFocused) { _, focused in
                        if !focused { commitTitleEdit() }
                    }

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
            }
            .opacity(showComposer ? 0 : 1)
            .allowsHitTesting(!showComposer)

            if showComposer {
                composerToolbarLeading
            }
        }
    }

    private var composerToolbarLeading: some View {
        HStack(spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) { showComposer = false }
            }) {
                Label {
                    Text("Piano Roll")
                } icon: {
                    Image("GridIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundColor(Theme.text(colorScheme))
                }
            }
            .buttonStyle(HoverPillStyle(colorScheme: colorScheme, textColor: Theme.text(colorScheme)))
            .help("Return to Piano Roll")

            Button(action: { showComposerHelp.toggle() }) {
                Label("Composer Help", systemImage: "questionmark.circle")
            }
            .buttonStyle(HoverPillStyle(colorScheme: colorScheme))
            .popover(isPresented: $showComposerHelp) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("help.composerTips.title", bundle: localizedBundle)
                        .font(.system(size: 13, weight: .semibold))
                    Text("help.composerTips.body", bundle: localizedBundle)
                    Label { Text("help.composerTips.clickPhoneme", bundle: localizedBundle) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)).opacity(0.6) }
                    Label { Text("help.composerTips.shiftClick", bundle: localizedBundle) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)).opacity(0.6) }
                    Label { Text("help.composerTips.rightClick", bundle: localizedBundle) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)).opacity(0.6) }
                    Label { Text("help.composerTips.copyToRoll", bundle: localizedBundle) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)).opacity(0.6) }
                }
                .font(.system(size: 12))
                .foregroundColor(Theme.text(colorScheme))
                .padding()
                .frame(width: 260)
            }
            .help("Composer tips")
        }
    }

    private var toolbarTrailing: some View {
        HStack(spacing: 10) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() } }) {
                Image(systemName: "nose")
                    .font(.system(size: Theme.toolbarIconSize, weight: .light))
                    .foregroundColor(showSettings ? Theme.text(colorScheme) : Theme.text(colorScheme).opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Prefer")

            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) { showComposer.toggle() }
            }) {
                Image(systemName: "eyebrow")
                    .font(.system(size: Theme.toolbarIconSize, weight: .light))
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
            .popover(isPresented: $showComposerHint) {
                Text("\(Image(systemName: "eyebrow")) \(Text("onboarding.roll.composerHint", bundle: localizedBundle))")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text(colorScheme))
                    .padding()
                    .frame(width: 240)
            }

            Button(action: { showSoundPad = true }) {
                Image(systemName: "ear")
                    .font(.system(size: Theme.toolbarIconSize, weight: .light))
                    .foregroundColor(showSoundPad ? Theme.text(colorScheme) : Theme.text(colorScheme).opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Test")

            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showKeyboard.toggle(); showKeyboardStorage = showKeyboard } }) {
                Image(systemName: "pianokeys")
                    .font(.system(size: Theme.toolbarIconSize, weight: .light))
                    .foregroundColor(
                        !keyboardAvailable ? Theme.text(colorScheme).opacity(0.15)
                        : showKeyboard ? Theme.text(colorScheme).opacity(0.85)
                        : Theme.text(colorScheme).opacity(0.4)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!keyboardAvailable)
            .help(keyboardAvailable ? "Touch" : "Add phonemes to use the keyboard")
            .popover(isPresented: $showKeyboardHint) {
                Text("\(Image(systemName: "pianokeys")) \(Text("onboarding.roll.keyboardHint", bundle: localizedBundle))")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text(colorScheme))
                    .padding()
                    .frame(width: 240)
            }

            Button(action: { startBluetoothSetup() }) {
                ConnectionStatusView(midiService: midiService, colorScheme: colorScheme)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(midiService.isConnected
                          ? Theme.fieldColor(colorScheme).opacity(0.6)
                          : Theme.text(colorScheme))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.leading, 2)
            .help(midiService.isConnected ? "MIDI Connected" : "Tap to connect Bluetooth MIDI")
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            if showComposer {
                ComposerView(midiService: midiService, audioMonitor: audioMonitor, onDismiss: { showComposer = false })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NonDraggableArea())
                    .padding(.bottom, showKeyboard && keyboardAvailable ? 150 : 0)
                    .transition(.opacity)
            } else {
                SequencerView(midiService: midiService, audioMonitor: audioMonitor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NonDraggableArea())
                    .padding(.bottom, showKeyboard ? 150 : 0)
            }

            if showKeyboard && keyboardAvailable {
                KeyboardView(midiService: midiService, audioMonitor: audioMonitor, isComposerActive: showComposer)
                    .frame(height: 150)
                    .background(NonDraggableArea())
                    .background(Theme.bg(colorScheme))
                    .zIndex(1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settingsPanel: some View {
        HStack(spacing: 0) {
            SettingsPanelView(midiService: midiService, audioMonitor: audioMonitor, showSettings: $showSettings)
                .frame(width: 280)
                .background(Theme.bg(colorScheme))
                .transition(.move(edge: .leading))

            Theme.overlay(colorScheme)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showSettings = false }
                }
        }
    }

    private var bluetoothPanel: some View {
        HStack(spacing: 0) {
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

// MARK: - Event Handlers Modifier

private struct ContentViewEventHandlers: ViewModifier {
    @Binding var showKeyboardStorage: Bool
    @Binding var showKeyboard: Bool
    @Binding var showComposerStorage: Bool
    @Binding var showComposer: Bool
    @Binding var showSettingsStorage: Bool
    @Binding var showSettings: Bool
    @Binding var showBluetoothSetup: Bool
    @Binding var showSoundPad: Bool
    @Binding var emptyHelperDismissed: Bool
    var isEmptyState: Bool
    var midiService: MidiService
    @ObservedObject var audioMonitor: AudioMonitorService
    @ObservedObject var model: SequencerModel
    @ObservedObject var composerModel: ComposerModel
    @ObservedObject var bluetoothManager: BluetoothMidiManager
    @ObservedObject var onboarding: OnboardingManager
    @Binding var localAudioEnabled: Bool
    var localAudioMode: String
    var applyLocalAudioMode: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(KeyboardHandlers(showKeyboardStorage: $showKeyboardStorage, showKeyboard: $showKeyboard))
            .modifier(ComposerHandlers(showComposerStorage: $showComposerStorage, showComposer: $showComposer, onboarding: onboarding, composerModel: composerModel))
            .modifier(SettingsHandlers(showSettingsStorage: $showSettingsStorage, showSettings: $showSettings, showBluetoothSetup: $showBluetoothSetup))
            .modifier(PlaybackHandlers(model: model, composerModel: composerModel, onboarding: onboarding, midiService: midiService))
            .modifier(AudioHandlers(localAudioEnabled: $localAudioEnabled, localAudioMode: localAudioMode, audioMonitor: audioMonitor, midiService: midiService, applyLocalAudioMode: applyLocalAudioMode))
            .modifier(MiscHandlers(isEmptyState: isEmptyState, emptyHelperDismissed: $emptyHelperDismissed, showSoundPad: $showSoundPad, showComposer: $showComposer, midiService: midiService, bluetoothManager: bluetoothManager, audioMonitor: audioMonitor))
    }
}

private struct KeyboardHandlers: ViewModifier {
    @Binding var showKeyboardStorage: Bool
    @Binding var showKeyboard: Bool
    func body(content: Content) -> some View {
        content
            .onChange(of: showKeyboardStorage) { _, v in withAnimation(.easeInOut(duration: 0.2)) { showKeyboard = v } }
            .onChange(of: showKeyboard) { _, v in showKeyboardStorage = v }
    }
}

private struct ComposerHandlers: ViewModifier {
    @Binding var showComposerStorage: Bool
    @Binding var showComposer: Bool
    @ObservedObject var onboarding: OnboardingManager
    @ObservedObject var composerModel: ComposerModel
    func body(content: Content) -> some View {
        content
            .onChange(of: showComposerStorage) { _, v in withAnimation(.easeInOut(duration: 0.25)) { showComposer = v } }
            .onChange(of: showComposer) { _, v in
                showComposerStorage = v
                if v {
                    onboarding.showChipsExplanationIfNeeded(hasPhonemes: !composerModel.phonemes.isEmpty)
                    onboarding.hasVisitedComposer = true
                }
            }
    }
}

private struct SettingsHandlers: ViewModifier {
    @Binding var showSettingsStorage: Bool
    @Binding var showSettings: Bool
    @Binding var showBluetoothSetup: Bool
    func body(content: Content) -> some View {
        content
            .onChange(of: showSettingsStorage) { _, v in withAnimation(.easeInOut(duration: 0.2)) { showSettings = v } }
            .onChange(of: showSettings) { _, v in showSettingsStorage = v }
            .onChange(of: showBluetoothSetup) { _, showing in
                if showing && showSettings { withAnimation(.easeInOut(duration: 0.2)) { showSettings = false } }
            }
    }
}

private struct PlaybackHandlers: ViewModifier {
    @ObservedObject var model: SequencerModel
    @ObservedObject var composerModel: ComposerModel
    @ObservedObject var onboarding: OnboardingManager
    var midiService: MidiService
    func body(content: Content) -> some View {
        content
            .onChange(of: model.isPlaying) { _, playing in
                if playing { onboarding.showFirstPlayGuideIfNeeded(isDollsConnected: midiService.isConnected) }
            }
            .onChange(of: composerModel.isPlaying) { _, playing in
                if playing { onboarding.showFirstPlayGuideIfNeeded(isDollsConnected: midiService.isConnected) }
            }
    }
}

private struct AudioHandlers: ViewModifier {
    @Binding var localAudioEnabled: Bool
    var localAudioMode: String
    @ObservedObject var audioMonitor: AudioMonitorService
    var midiService: MidiService
    var applyLocalAudioMode: () -> Void
    func body(content: Content) -> some View {
        content
            .onChange(of: localAudioEnabled) { _, enabled in
                if enabled { audioMonitor.ensureStarted() } else { audioMonitor.tearDown() }
            }
            .onChange(of: localAudioMode) { applyLocalAudioMode() }
            .onChange(of: midiService.isConnected) { applyLocalAudioMode() }
    }
}

private struct MiscHandlers: ViewModifier {
    var isEmptyState: Bool
    @Binding var emptyHelperDismissed: Bool
    @Binding var showSoundPad: Bool
    @Binding var showComposer: Bool
    var midiService: MidiService
    @ObservedObject var bluetoothManager: BluetoothMidiManager
    @ObservedObject var audioMonitor: AudioMonitorService
    func body(content: Content) -> some View {
        content
            // Empty helper shows once per launch — don't re-trigger when content changes
            .onChange(of: midiService.isConnected) { _, connected in if connected { bluetoothManager.closeBluetoothMIDIWindow() } }
            .onReceive(NotificationCenter.default.publisher(for: .showSoundPad)) { _ in showSoundPad = true }
            .onReceive(NotificationCenter.default.publisher(for: .showComposer)) { _ in withAnimation(.easeInOut(duration: 0.25)) { showComposer = true } }
            .sheet(isPresented: $showSoundPad) {
                SoundPadView(midiService: midiService, audioMonitor: audioMonitor, isPresented: $showSoundPad)
                    .frame(minWidth: 700, minHeight: 580)
            }
    }
}
