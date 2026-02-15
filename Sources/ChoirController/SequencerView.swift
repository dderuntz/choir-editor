import SwiftUI

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
    
    // Scroll sync between scrub zone and piano roll grid
    @StateObject private var scrollSync = ScrollSyncManager()
    
    /// X position of the callout arrow (note center, accounting for scroll offset)
    private var noteArrowX: CGFloat {
        guard let note = model.selectedNote else { return -20 }
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
                scrollSync: scrollSync
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, model.selectedNote != nil ? 70 : 0)
            .animation(.easeInOut(duration: 0.15), value: model.selectedNote != nil)
        }
        .overlay(alignment: .bottom) {
            // Note Inspector (always alive, overlays bottom edge)
            NoteInspectorView(
                note: model.selectedNote ?? SequencerNote.placeholder,
                arrowX: noteArrowX,
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
                onDelete: {
                    model.deleteSelectedNote()
                }
            )
            .id(model.selectedNoteId ?? SequencerView.noSelectionId)
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: -4)
            .offset(y: model.selectedNote != nil ? 0 : 70)
            .allowsHitTesting(model.selectedNote != nil)
            .animation(.easeInOut(duration: 0.15), value: model.selectedNote != nil)
        }
        .onDeleteCommand {
            model.deleteSelectedNote()
        }
        .onDisappear {
            stopPlayback()
        }
        .onChange(of: model.togglePlaybackTrigger) { _ in
            togglePlayback()
        }
    }
    
    // MARK: - Toolbar
    
    private var sequencerToolbar: some View {
        HStack(spacing: 12) {
            // Enable Guide group
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { model.showScaleHelper.toggle() } }) {
                HStack(spacing: 5) {
                    Image(systemName: "music.note.list")
                    if !model.showScaleHelper {
                        Text("Enable guide")
                    }
                }
                .foregroundColor(model.showScaleHelper ? Theme.accent : Theme.text(colorScheme).opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Scale guide")
            
            if model.showScaleHelper {
                Picker("", selection: $model.musicalKey) {
                    ForEach(MusicalKey.allCases) { key in
                        Text(key.name).tag(key)
                    }
                }
                .labelsHidden()
                .frame(width: 50)
                .controlSize(.small)
                .tint(Theme.text(colorScheme).opacity(0.7))
                .accentColor(Theme.text(colorScheme).opacity(0.7))
                
                Picker("", selection: $model.scaleType) {
                    ForEach(ScaleType.allCases) { scale in
                        Text(scale.rawValue).tag(scale)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .controlSize(.small)
                .tint(Theme.text(colorScheme).opacity(0.7))
                .accentColor(Theme.text(colorScheme).opacity(0.7))
                
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { model.showScaleHelper = false } }) {
                    Text("Clear guide")
                        .foregroundColor(Theme.text(colorScheme).opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            
            Rectangle()
                .fill(Theme.text(colorScheme).opacity(0.15))
                .frame(width: 1, height: 16)
            
            // Bar navigation: < X Bars >
            HStack(spacing: 6) {
                Button(action: { if model.totalBeats > 4 { model.totalBeats -= 4 } }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .foregroundColor(model.totalBeats > 4 ? Theme.text(colorScheme).opacity(0.7) : Theme.text(colorScheme).opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(model.totalBeats <= 4)
                
                Text("\(model.totalBeats / 4) Bars")
                    .foregroundColor(Theme.text(colorScheme).opacity(0.7))
                    .monospacedDigit()
                
                Button(action: { if model.totalBeats < 64 { model.totalBeats += 4 } }) {
                    Image(systemName: "chevron.right.circle.fill")
                        .foregroundColor(model.totalBeats < 64 ? Theme.text(colorScheme).opacity(0.7) : Theme.text(colorScheme).opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(model.totalBeats >= 64)
            }
            
            Rectangle()
                .fill(Theme.text(colorScheme).opacity(0.15))
                .frame(width: 1, height: 16)
            
            // Loop toggle
            Button(action: { model.isLooping.toggle() }) {
                Label("Loop", systemImage: "repeat")
                    .foregroundColor(model.isLooping ? Theme.accent : Theme.text(colorScheme).opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(model.isLooping ? "Looping" : "Loop")
            
            Spacer()
            
            // Clear button (right-aligned)
            Button(action: {
                if model.selectedNoteIds.isEmpty {
                    clearAll()
                } else {
                    model.deleteSelectedNote()
                }
            }) {
                Label(
                    model.selectedNoteIds.isEmpty
                        ? "Clear Notes"
                        : "Clear Selection (\(model.selectedNoteIds.count))",
                    systemImage: "xmark.circle.fill"
                )
                .foregroundColor(Theme.text(colorScheme).opacity(0.7))
            }
            .buttonStyle(.plain)
            .disabled(model.notes.isEmpty && model.selectedNoteIds.isEmpty)
        }
        .font(Theme.toolbarFont)
        .padding(.horizontal)
        .frame(height: 32)
        .background(Theme.bg(colorScheme))
    }
    
    // MARK: - Transport Bar
    
    private var transportBar: some View {
        HStack(spacing: 0) {
            // Play/Stop + Loop buttons (aligned with piano key column)
            Button(action: { togglePlayback() }) {
                Image(systemName: model.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.dark)
                    .frame(width: PianoRollLayout.pianoKeyWidth, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.isPlaying ? "Stop" : "Play")
            
            Theme.structuralDivider.frame(width: 1)
            
            // Scrub zone (same width as the grid, scrolls in sync)
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Beat markers
                    scrubBackground
                    
                    // Playhead line (dark on gold transport)
                    Rectangle()
                        .fill(Theme.dark)
                        .frame(width: 2, height: 32)
                        .offset(x: PianoRollLayout.xForBeat(model.playheadBeat))
                        .allowsHitTesting(false)
                        .animation(nil, value: model.playheadBeat)
                }
                .frame(
                    width: PianoRollLayout.gridWidth(beats: model.totalBeats),
                    height: 32
                )
                .contentShape(Rectangle())
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
        .frame(height: 32)
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
        .frame(
            width: PianoRollLayout.gridWidth(beats: model.totalBeats),
            height: 32
        )
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
            if localAudioEnabled { audioMonitor.playNote(note: note.pitch, velocity: note.velocity) }
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
        if localAudioEnabled { audioMonitor.playNote(note: pitch, velocity: note.velocity) }
        
        print("🔊 play pitch=\(pitch) for \(String(format: "%.2f", durationSeconds))s")
        
        // Schedule stop
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) { [self] in
            print("🔊 stop pitch=\(pitch)")
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

// MARK: - Note Inspector

// MARK: - Callout Arrow Shape

struct CalloutArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))     // tip
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))  // bottom-right
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))  // bottom-left
        path.closeSubpath()
        return path
    }
}

struct NoteInspectorView: View {
    let note: SequencerNote
    var arrowX: CGFloat = 0  // horizontal position of arrow from leading edge
    var onUpdate: (SequencerNote) -> Void
    var onPlay: (SequencerNote) -> Void
    var onDelete: () -> Void
    
    // Local editing state synced from the note (view is recreated via .id() on selection change)
    @State private var consonant: UInt8 = 125
    @State private var vowel: UInt8 = 0
    @State private var velocity: Double = 100
    @State private var vibrato: Double = 64
    @State private var reverb: Double = 32
    
    private var isBlackKey: Bool { PitchConstants.isBlackKey(note.pitch) }
    private var bg: Color { isBlackKey ? Theme.dark : Theme.ivory }
    private var fg: Color { isBlackKey ? Theme.ivory : Theme.dark }
    private var fgDim: Color { fg.opacity(0.5) }
    private var dividerColor: Color { fg.opacity(0.15) }
    
    var body: some View {
        HStack(spacing: 16) {
            // Note info
            VStack(alignment: .leading, spacing: 2) {
                Text(PitchConstants.noteName(for: note.pitch))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(fg)
                Text("Beat \(Int(note.startBeat + 1))")
                    .font(.caption2)
                    .foregroundColor(fgDim)
                    .monospacedDigit()
            }
            .frame(width: 50, alignment: .leading)
            
            dividerColor.frame(width: 1, height: 40)
            
            // Consonant picker
            HStack(spacing: 6) {
                Text("Consonant")
                    .font(.caption)
                    .foregroundColor(fgDim)
                Picker("", selection: $consonant) {
                    ForEach(Consonant.all) { c in
                        Text(c.name).tag(c.ccValue)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
                .controlSize(.small)
                .tint(fg)
                .accentColor(fg)
                .onChange(of: consonant) { _ in pushUpdate() }
            }
            
            // Vowel picker
            HStack(spacing: 6) {
                Text("Vowel")
                    .font(.caption)
                    .foregroundColor(fgDim)
                Picker("", selection: $vowel) {
                    ForEach(Vowel.all) { v in
                        Text(v.ccValue == 0 ? "Random" : "\(v.symbol) \(v.example)").tag(v.ccValue)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .controlSize(.small)
                .tint(fg)
                .accentColor(fg)
                .onChange(of: vowel) { _ in pushUpdate() }
            }
            
            // Velocity
            inspectorSlider(label: "Velocity", value: $velocity, range: 1...127) { pushUpdate() }
            
            // Vibrato
            inspectorSlider(label: "Vibrato", value: $vibrato, range: 0...127) { pushUpdate() }
            
            // Reverb
            inspectorSlider(label: "Reverb", value: $reverb, range: 0...127) { pushUpdate() }
            
            Spacer()
            
            // Test button
            Button(action: { onPlay(currentNote()) }) {
                HStack(spacing: 5) {
                    Image(systemName: "ear")
                    Text("Test")
                }
                .font(Theme.toolbarFont)
                .foregroundColor(Theme.dark)
                .padding(.horizontal, Theme.buttonPaddingH)
                .padding(.vertical, Theme.buttonPaddingV)
                .background(
                    RoundedRectangle(cornerRadius: Theme.buttonRadius)
                        .fill(Theme.accent)
                )
            }
            .buttonStyle(.plain)
            
            // Delete
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundColor(fg.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .frame(height: 70)
        .background(bg)
        .overlay(alignment: .bottom) {
            Theme.structuralDivider.opacity(0.25).frame(height: 1)
        }
        .overlay(alignment: .topLeading) {
            // Callout arrow pointing up toward the note
            CalloutArrow()
                .fill(bg)
                .frame(width: 14, height: 8)
                .offset(x: arrowX - 7, y: -8)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, isBlackKey ? .dark : .light)
        .onAppear { syncFromNote() }
    }
    
    private func syncFromNote() {
        consonant = note.consonant
        vowel = note.vowel
        velocity = Double(note.velocity)
        vibrato = Double(note.vibrato)
        reverb = Double(note.reverb)
    }
    
    private func currentNote() -> SequencerNote {
        var n = note
        n.consonant = consonant
        n.vowel = vowel
        n.velocity = UInt8(velocity)
        n.vibrato = UInt8(vibrato)
        n.reverb = UInt8(reverb)
        return n
    }
    
    private func pushUpdate() {
        onUpdate(currentNote())
    }
    
    private func inspectorSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, onChange: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(fgDim)
                Text("\(Int(value.wrappedValue))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(fg)
                    .monospacedDigit()
            }
            .frame(minWidth: 48, alignment: .leading)
            
            Slider(value: value, in: range)
                .tint(fg)
                .accentColor(fg)
                .onChange(of: value.wrappedValue) { _ in onChange() }
        }
    }
}
