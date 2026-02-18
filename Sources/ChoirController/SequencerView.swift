import SwiftUI
import AppKit

struct SequencerView: View {
    var midiService: MidiService
    @ObservedObject var audioMonitor: AudioMonitorService
    @EnvironmentObject var model: SequencerModel
    @AppStorage("localAudioEnabled") private var localAudioEnabled = false
    @Environment(\.colorScheme) private var colorScheme
    
    /// Stable identity for the inspector when no note is selected (avoids per-frame recreation)
    private static let noSelectionId = UUID()
    
    // Playback timer
    @State private var playbackTimer: Timer? = nil
    @State private var lastTickTime: Date? = nil
    @State private var pendingClearAll = false
    @State private var showSequencerTips = false

    // Onboarding
    @EnvironmentObject var onboarding: OnboardingManager
    @State private var showInspectorTip = false
    @State private var showTransportTip = false
    @State private var isDemoPath = false  // demo loaded → different tip order
    @State private var showNudgeTip = false  // blank path: "tap grid to add" reminder
    @State private var nudgeTimer: Timer?
    @State private var showScaleGuideInvite = false
    
    // Scroll sync between scrub zone and piano roll grid
    @StateObject private var scrollSync = ScrollSyncManager()
    
    /// X position of the callout arrow (note center, accounting for scroll offset)
    private var noteArrowX: CGFloat {
        guard let note = model.selectedNote else { return -100 }
        let pianoOffset = PianoRollLayout.pianoKeyWidth + 1 // piano keys + divider
        let noteCenterX = PianoRollLayout.xForBeat(note.startBeat)
            + CGFloat(note.duration) * PianoRollLayout.beatWidth / 2
        return pianoOffset + noteCenterX - scrollSync.horizontalOffset
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            sequencerToolbar
            
            // Transport bar (play button + scrub zone)
            transportBar
            
            // Piano Roll
            PianoRollView(
                model: model,
                onNotePreview: { note in
                    playNoteForDuration(note)
                },
                onNoteUpdate: { updatedNote in
                    let ids = model.selectedNoteIds.isEmpty ? [updatedNote.id] : model.selectedNoteIds
                    for id in ids {
                        model.updateNote(id: id) { note in
                            note.consonant = updatedNote.consonant
                            note.vowel = updatedNote.vowel
                            note.velocity = updatedNote.velocity
                            note.vibrato = updatedNote.vibrato
                            note.reverb = updatedNote.reverb
                        }
                    }
                },
                onNoteDelete: {
                    model.deleteSelectedNote()
                },
                scrollSync: scrollSync
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, model.selectedNote != nil ? 80 : 0)
            .animation(.easeInOut(duration: 0.15), value: model.selectedNote != nil)
            .overlay {
                // Invisible center anchor for the nudge tip popover
                Color.clear
                    .frame(width: 1, height: 1)
                    .popover(isPresented: $showNudgeTip) {
                        Text("onboarding.roll.nudgeTip", bundle: localizedBundle)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text(colorScheme))
                            .padding()
                            .frame(width: 240)
                    }
            }
        }
        .overlay(alignment: .bottom) {
            // Note Inspector (always alive, overlays bottom edge)
            NoteInspectorView(
                note: model.selectedNote ?? SequencerNote.placeholder,
                arrowX: noteArrowX,
                groupCount: model.selectedNoteIds.count,
                onUpdate: { updatedNote in
                    // Apply to all selected notes (group edit)
                    let ids = model.selectedNoteIds.isEmpty ? [updatedNote.id] : model.selectedNoteIds
                    for id in ids {
                        model.updateNote(id: id) { note in
                            note.consonant = updatedNote.consonant
                            note.vowel = updatedNote.vowel
                            note.velocity = updatedNote.velocity
                            note.vibrato = updatedNote.vibrato
                            note.reverb = updatedNote.reverb
                        }
                    }
                },
                onPlay: { note in
                    playNoteForDuration(note)
                },
                noteDurationSeconds: {
                    let n = model.selectedNote ?? SequencerNote.placeholder
                    return n.duration / (model.tempo / 60.0)
                }(),
                onDelete: {
                    model.deleteSelectedNote()
                }
            )
            .id(model.selectedNoteId ?? SequencerView.noSelectionId)
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: -4)
            .offset(y: model.selectedNote != nil ? 0 : 100)
            .allowsHitTesting(model.selectedNote != nil)
            .animation(.easeInOut(duration: 0.15), value: model.selectedNote != nil)
            .popover(isPresented: $showInspectorTip) {
                Text("onboarding.roll.inspectorTip", bundle: localizedBundle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text(colorScheme))
                    .padding()
                    .frame(width: 240)
            }
        }
        .onDeleteCommand {
            model.deleteSelectedNote()
        }
        .alert("Delete \(model.selectedNoteIds.count) notes?", isPresented: $model.pendingDeleteConfirm) {
            Button("Delete", role: .destructive) { model.confirmDeleteSelected() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Clear all notes?", isPresented: $pendingClearAll) {
            Button("Clear All", role: .destructive) { clearAll() }
            Button("Cancel", role: .cancel) {}
        }
        .onDisappear {
            stopPlayback()
            nudgeTimer?.invalidate()
        }
        // Copy-from-composer path: scale guide invite first, then demo tip tour
        .onReceive(NotificationCenter.default.publisher(for: .rollCopiedFromComposer)) { _ in
            if !onboarding.hasSeenScaleGuideInvite {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showScaleGuideInvite = true
                }
            } else if !onboarding.hasSeenTransportTip {
                // Scale guide already seen, go straight to tip tour
                isDemoPath = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showTransportTip = true
                }
            }
        }
        .onChange(of: showScaleGuideInvite) { wasShowing, isShowing in
            if wasShowing && !isShowing {
                onboarding.hasSeenScaleGuideInvite = true
                // After scale guide dismissed, start demo tip tour if unseen
                if !onboarding.hasSeenTransportTip {
                    isDemoPath = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showTransportTip = true
                    }
                }
            }
        }
        // Demo path: transport tip shown first via notification
        .onReceive(NotificationCenter.default.publisher(for: .rollDemoLoaded)) { _ in
            guard !onboarding.hasSeenTransportTip else { return }
            isDemoPath = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showTransportTip = true
            }
        }
        // Blank path: 3s nudge if user hasn't placed a note
        .onReceive(NotificationCenter.default.publisher(for: .rollStartAdding)) { _ in
            guard !onboarding.hasSeenInspectorTip else { return }
            nudgeTimer?.invalidate()
            nudgeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                Task { @MainActor in
                    guard model.notes.isEmpty else { return }
                    showNudgeTip = true
                }
            }
        }
        .onChange(of: model.selectedNoteId) { _, newId in
            // Cancel nudge if user places a note
            if newId != nil {
                nudgeTimer?.invalidate()
                showNudgeTip = false
            }
            // Show inspector tip on first note selection (both paths)
            if newId != nil && !onboarding.hasSeenInspectorTip && !isDemoPath {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showInspectorTip = true
                }
            }
        }
        // Also cancel nudge when notes are added (in case selectedNoteId doesn't change)
        .onChange(of: model.notes.count) { oldCount, newCount in
            if newCount > oldCount {
                nudgeTimer?.invalidate()
                showNudgeTip = false
            }
        }
        .onChange(of: showInspectorTip) { wasShowing, isShowing in
            if wasShowing && !isShowing {
                onboarding.hasSeenInspectorTip = true
                if isDemoPath {
                    // Demo path: inspector was last tip here, hand off to keyboard/composer chain
                    NotificationCenter.default.post(name: .rollTransportTipDismissed, object: nil)
                } else {
                    // Blank path: show transport tip next
                    if !onboarding.hasSeenTransportTip {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showTransportTip = true
                        }
                    }
                }
            }
        }
        .onChange(of: showTransportTip) { wasShowing, isShowing in
            if wasShowing && !isShowing {
                onboarding.hasSeenTransportTip = true
                if isDemoPath {
                    // Demo path: after transport tip, scroll to first note and show inspector
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let firstNote = model.notes.sorted(by: { $0.startBeat < $1.startBeat }).first {
                            model.selectNote(firstNote.id)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if !onboarding.hasSeenInspectorTip {
                                    showInspectorTip = true
                                }
                            }
                        }
                    }
                } else {
                    // Blank path: hand off to keyboard/composer chain
                    NotificationCenter.default.post(name: .rollTransportTipDismissed, object: nil)
                }
            }
        }
        .onChange(of: model.togglePlaybackTrigger) {
            togglePlayback()
        }
    }
    
    // MARK: - Toolbar
    
    private var sequencerToolbar: some View {
        ZStack {
            // Left: Key/Scale
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .foregroundColor(Theme.text(colorScheme).opacity(model.showScaleHelper ? 1 : 0.5))

                    Picker("", selection: Binding(
                    get: { model.showScaleHelper ? model.musicalKey.rawValue : -1 },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if newValue == -1 {
                                model.showScaleHelper = false
                            } else {
                                model.musicalKey = MusicalKey(rawValue: newValue) ?? .C
                                model.showScaleHelper = true
                            }
                        }
                    }
                )) {
                    Text("No Scale").tag(-1)
                    ForEach(MusicalKey.allCases) { key in
                        Text("Key of \(key.name)").tag(key.rawValue)
                    }
                }
                .labelsHidden()
                .buttonStyle(.borderless)
                .fixedSize()
                .tint(Theme.text(colorScheme))
                .foregroundStyle(Theme.text(colorScheme))

                    if model.showScaleHelper {
                        Picker("", selection: $model.scaleType) {
                            ForEach(ScaleType.allCases) { scale in
                                Text("\(scale.rawValue) Scale").tag(scale)
                            }
                        }
                        .labelsHidden()
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .tint(Theme.text(colorScheme))
                        .foregroundStyle(Theme.text(colorScheme))
                    }
                }
                .popover(isPresented: $showScaleGuideInvite) {
                    VStack(spacing: 12) {
                        Text("onboarding.roll.scaleGuideInvite", bundle: localizedBundle)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text(colorScheme))
                            .multilineTextAlignment(.center)
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                model.showScaleHelper = true
                            }
                            showScaleGuideInvite = false
                        } label: {
                            Text("onboarding.roll.scaleGuideEnable", bundle: localizedBundle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.dark)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding()
                    .frame(width: 260)
                }

                Button(action: { showSequencerTips.toggle() }) {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .buttonStyle(HoverPillStyle(colorScheme: colorScheme, textColor: Theme.text(colorScheme)))
                .popover(isPresented: $showSequencerTips) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("help.rollTips.title", bundle: localizedBundle)
                            .font(.system(size: 13, weight: .semibold))
                        Text("help.rollTips.body", bundle: localizedBundle)
                        Label { Text("help.rollTips.tapGrid", bundle: localizedBundle) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)).opacity(0.6) }
                        Label { Text("help.rollTips.dragNotes", bundle: localizedBundle) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)).opacity(0.6) }
                        Label { Text("help.rollTips.optionDrag", bundle: localizedBundle) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)).opacity(0.6) }
                        Label { Text("help.rollTips.tapNote", bundle: localizedBundle) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)).opacity(0.6) }
                        Label { Text("help.rollTips.shiftClick", bundle: localizedBundle) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)).opacity(0.6) }
                        Label { Text("help.rollTips.shiftDrag", bundle: localizedBundle) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)).opacity(0.6) }
                        Label { Text("help.rollTips.deleteKey", bundle: localizedBundle) } icon: { Image(systemName: "circle.fill").font(.system(size: 4)).opacity(0.6) }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text(colorScheme))
                    .padding()
                    .frame(width: 260)
                }
                .help("Tips")
                
                Spacer()
            }
            
            // Right: Clear + Loop + Bar stepper
            HStack(spacing: 12) {
                Spacer()
                
                Button(action: {
                    if model.selectedNoteIds.isEmpty {
                        pendingClearAll = true
                    } else {
                        model.deleteSelectedNote()
                    }
                }) {
                    Label(model.selectedNoteIds.isEmpty
                        ? "Clear All"
                        : "Clear Selection (\(model.selectedNoteIds.count))",
                          systemImage: "eraser.line.dashed")
                }
                .buttonStyle(HoverPillStyle(colorScheme: colorScheme, textColor: Theme.text(colorScheme)))
                .disabled(model.notes.isEmpty && model.selectedNoteIds.isEmpty)


                Button(action: { model.isLooping.toggle() }) {
                    Label("Loop", systemImage: "repeat.circle.fill")
                        .foregroundColor(model.isLooping ? Theme.text(colorScheme) : Theme.text(colorScheme).opacity(0.25))
                }
                .buttonStyle(.borderless)
                .help(model.isLooping ? "Looping" : "Loop")
                
                Stepper("\(model.totalBeats / 4) Bars", value: Binding(
                    get: { model.totalBeats / 4 },
                    set: { model.totalBeats = $0 * 4 }
                ), in: 1...16)
                .monospacedDigit()
                .controlSize(.small)
                .tint(Theme.fieldColor(colorScheme))
                .fixedSize()
                .padding(.leading, 6)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.bg(colorScheme))
    }
    
    // MARK: - Transport Bar
    
    private var transportBar: some View {
        HStack(spacing: 0) {
            // Play/Stop button (aligned with piano key column)
            Button(action: { togglePlayback() }) {
                Image(systemName: model.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.text(colorScheme))
                    .frame(width: PianoRollLayout.pianoKeyWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.isPlaying ? "Stop" : "Play")
            .popover(isPresented: $showTransportTip) {
                Text("onboarding.roll.transportTip", bundle: localizedBundle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text(colorScheme))
                    .padding()
                    .frame(width: 240)
            }

            Theme.structuralDivider.frame(width: 1)
            
            // Scrub zone (same width as the grid, scrolls in sync)
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Beat markers
                    scrubBackground
                    
                    // Minimap: notes compressed into transport
                    let minimapHeight: CGFloat = 40 // 56 - 8px top - 8px bottom
                    let sourceHeight: CGFloat = CGFloat(PitchConstants.pitchCount) // 42
                    let scaleY = minimapHeight / sourceHeight
                    Canvas { context, size in
                        let bw = PianoRollLayout.beatWidth
                        for note in model.notes {
                            let x = CGFloat(note.startBeat) * bw
                            let w = CGFloat(note.duration) * bw
                            let row = CGFloat(Int(PitchConstants.maxPitch) - Int(note.pitch))
                            let rect = CGRect(x: x, y: row - 0.5, width: max(w, 2), height: 2)
                            context.fill(Path(rect), with: .color(Theme.dark.opacity(0.1)))
                        }
                    }
                    .frame(
                        width: PianoRollLayout.gridWidth(beats: model.totalBeats),
                        height: sourceHeight
                    )
                    .scaleEffect(x: 1, y: scaleY, anchor: .top)
                    .offset(y: 8)
                    .allowsHitTesting(false)
                    
                    // Playhead line (dark on gold transport)
                    Rectangle()
                        .fill(Theme.dark)
                        .frame(width: 2).frame(maxHeight: .infinity)
                        .offset(x: PianoRollLayout.xForBeat(model.playheadBeat))
                        .allowsHitTesting(false)
                        .animation(nil, value: model.playheadBeat)
                }
                .frame(width: PianoRollLayout.gridWidth(beats: model.totalBeats))
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.iBeam.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let beat = PianoRollLayout.beatForX(value.location.x)
                            scrubTo(beat: beat)
                        }
                        .onEnded { _ in
                            if !model.isPlaying {
                                stopAllActiveNotes()
                            }
                        }
                )
                .background {
                    ScrollSyncHelper(id: "scrub", manager: scrollSync)
                }
            }
        }
        .frame(height: 56)
        .background(model.isPlaying ? Theme.green : Theme.accent)
    }
    
    private var scrubBackground: some View {
        Canvas { context, size in
            let totalBeats = model.totalBeats
            guard totalBeats > 0 else { return }
            let bw = PianoRollLayout.beatWidth
            
            // Beat lines + measure numbers
            for beat in 0...totalBeats {
                let x = CGFloat(beat) * bw
                let isMeasure = beat % 4 == 0
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    path,
                    with: .color(Theme.dark.opacity(isMeasure ? 0.4 : 0.15)),
                    lineWidth: 0.5
                )
                
                if isMeasure && beat < totalBeats {
                    let bar = (beat / 4) + 1
                    let text = Text("\(bar)").font(Theme.labelSmall.weight(.medium)).foregroundColor(Theme.dark)
                    context.draw(text, at: CGPoint(x: x + 8, y: size.height / 2))
                }
            }
        }
        .frame(width: PianoRollLayout.gridWidth(beats: model.totalBeats))
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Playback Engine
    
    private func togglePlayback() {
        if model.isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        // Rolling start: nudge playhead slightly before current position
        // so notes exactly at the start beat get triggered on the first tick
        model.playheadBeat = max(model.playheadBeat - 0.001, -0.001)
        model.isPlaying = true
        lastTickTime = Date()
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor in
                self.playbackTick()
            }
        }
    }
    
    private func stopPlayback() {
        model.isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        lastTickTime = nil
        stopAllActiveNotes()
    }
    
    private func playbackTick() {
        guard model.isPlaying else { return }
        
        let now = Date()
        guard let lastTime = lastTickTime else {
            lastTickTime = now
            return
        }
        
        let dt = now.timeIntervalSince(lastTime)
        lastTickTime = now
        
        let beatsPerSecond = model.tempo / 60.0
        let beatDelta = beatsPerSecond * dt
        let previousBeat = model.playheadBeat
        let newBeat = previousBeat + beatDelta
        
        // Check if we've reached the end
        if newBeat >= Double(model.totalBeats) {
            // Trigger any remaining notes in the final slice
            triggerNotes(from: previousBeat, to: Double(model.totalBeats))
            
            if model.isLooping {
                // Loop: stop active notes, reset to start, trigger notes at beat 0
                stopAllActiveNotes()
                model.playheadBeat = -0.001
                lastTickTime = Date()
                return
            } else {
                stopPlayback()
                model.playheadBeat = 0
                return
            }
        }
        
        model.playheadBeat = newBeat
        triggerNotes(from: previousBeat, to: newBeat)
    }
    
    /// Scrub the playhead to a specific beat, triggering notes at that position
    private func scrubTo(beat: Double) {
        let previousBeat = model.playheadBeat
        let clampedBeat = max(0, min(beat, Double(model.totalBeats)))
        model.playheadBeat = clampedBeat
        
        // Turn off notes that are no longer under the playhead
        let toDeactivate = model.activeNoteIDs.filter { id in
            guard let note = model.notes.first(where: { $0.id == id }) else { return true }
            let noteEnd = note.startBeat + note.duration
            return clampedBeat < note.startBeat || clampedBeat >= noteEnd
        }
        for id in toDeactivate {
            if let note = model.notes.first(where: { $0.id == id }) {
                midiService.sendNoteOff(note: note.pitch)
                if localAudioEnabled { audioMonitor.stopNote(note: note.pitch) }
                model.activeNoteIDs.remove(id)
            }
        }
        
        // If scrubbing forward, trigger notes whose start beat we crossed
        if clampedBeat > previousBeat {
            triggerNotes(from: previousBeat, to: clampedBeat)
        } else if clampedBeat < previousBeat {
            // Scrubbing backward -- trigger notes at the current position
            // (only if their start beat is at this position)
            let snapBeat = model.snap(clampedBeat)
            let notesAtPosition = model.notes.filter { note in
                abs(note.startBeat - snapBeat) < GridConstants.snapResolution &&
                !model.activeNoteIDs.contains(note.id)
            }
            activateNotes(notesAtPosition)
        }
    }
    
    /// Check for notes to trigger between previousBeat and newBeat
    private func triggerNotes(from previousBeat: Double, to newBeat: Double) {
        // NoteOff FIRST: so back-to-back same-pitch notes work correctly
        let toStop = model.activeNoteIDs.filter { id in
            guard let note = model.notes.first(where: { $0.id == id }) else { return true }
            let noteEnd = note.startBeat + note.duration
            return noteEnd > previousBeat && noteEnd <= newBeat
        }
        for id in toStop {
            if let note = model.notes.first(where: { $0.id == id }) {
                midiService.sendNoteOff(note: note.pitch)
                if localAudioEnabled { audioMonitor.stopNote(note: note.pitch) }
            }
            model.activeNoteIDs.remove(id)
        }
        
        // NoteOn SECOND: new notes start after old ones have been released
        let notesToStart = model.notes.filter { note in
            note.startBeat > previousBeat && note.startBeat <= newBeat &&
            !model.activeNoteIDs.contains(note.id)
        }
        activateNotes(notesToStart)
    }
    
    /// Activate up to 8 notes (first 8 by ascending pitch)
    private func activateNotes(_ notes: [SequencerNote]) {
        guard !notes.isEmpty else { return }
        
        // 8-poly limit: first 8 by ascending pitch
        let sorted = notes.sorted { $0.pitch < $1.pitch }
        let toPlay = sorted.prefix(8)
        
        for note in toPlay {
            // Set CC values then NoteOn
            midiService.consonant = note.consonant
            midiService.vowel = note.vowel
            midiService.vibrato = note.vibrato
            midiService.reverb = note.reverb
            midiService.sendNoteOn(note: note.pitch, velocity: note.velocity)
            if localAudioEnabled { audioMonitor.playNote(note: note.pitch, velocity: note.velocity, vibrato: note.vibrato, reverb: note.reverb, vowel: note.vowel, consonant: note.consonant) }
            model.activeNoteIDs.insert(note.id)
        }
    }
    
    private func stopAllActiveNotes() {
        for id in model.activeNoteIDs {
            if let note = model.notes.first(where: { $0.id == id }) {
                midiService.sendNoteOff(note: note.pitch)
                if localAudioEnabled { audioMonitor.stopNote(note: note.pitch) }
            }
        }
        model.activeNoteIDs.removeAll()
    }
    
    // MARK: - MIDI Preview (tap/click on notes)
    
    private func playNoteForDuration(_ note: SequencerNote) {
        let pitch = note.pitch
        let beatsPerSecond = model.tempo / 60.0
        let durationSeconds = note.duration / beatsPerSecond
        
        // Stop any currently playing note first
        midiService.sendNoteOff(note: pitch)
        if localAudioEnabled { audioMonitor.stopNote(note: pitch) }
        
        // Set CC values then play
        midiService.consonant = note.consonant
        midiService.vowel = note.vowel
        midiService.vibrato = note.vibrato
        midiService.reverb = note.reverb
        midiService.sendNoteOn(note: pitch, velocity: note.velocity)
        if localAudioEnabled { audioMonitor.playNote(note: pitch, velocity: note.velocity, vibrato: note.vibrato, reverb: note.reverb, vowel: note.vowel, consonant: note.consonant) }
        
        
        
        // Schedule stop
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) { [self] in
            midiService.sendNoteOff(note: pitch)
            if localAudioEnabled { audioMonitor.stopNote(note: pitch) }
        }
    }
    
    private func clearAll() {
        model.withUndo("Clear All") {
            model.notes.removeAll()
            model.clearSelection()
            model.markDirty()
        }
    }
}
