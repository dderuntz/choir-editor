import SwiftUI

struct SequencerView: View {
    var midiService: MidiService
    @EnvironmentObject var model: SequencerModel
    
    // Playback timer
    @State private var playbackTimer: Timer? = nil
    @State private var lastTickTime: Date? = nil
    
    // Scroll sync between scrub zone and piano roll grid
    @StateObject private var scrollSync = ScrollSyncManager()
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            sequencerToolbar
            
            Divider()
            
            // Transport bar (play button + scrub zone)
            transportBar
            
            Divider()
            
            // Piano Roll
            PianoRollView(
                model: model,
                onNotePreview: { note in
                    playNoteForDuration(note)
                },
                scrollSync: scrollSync
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Note Inspector (when a note is selected)
            if let selectedNote = model.selectedNote {
                NoteInspectorView(
                    note: selectedNote,
                    onUpdate: { updatedNote in
                        model.updateNote(id: updatedNote.id) { note in
                            note.consonant = updatedNote.consonant
                            note.vowel = updatedNote.vowel
                            note.velocity = updatedNote.velocity
                            note.vibrato = updatedNote.vibrato
                            note.reverb = updatedNote.reverb
                        }
                    },
                    onPlay: { note in
                        playNoteForDuration(note)
                    },
                    onDelete: {
                        model.deleteSelectedNote()
                    }
                )
                .frame(height: 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.selectedNoteId)
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
        HStack(spacing: 8) {
            // Document name
            HStack(spacing: 4) {
                Text(model.documentName)
                    .font(.caption)
                    .fontWeight(.medium)
                if model.hasUnsavedChanges {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .help("Unsaved changes")
                }
            }
            
            Divider().frame(height: 16)
            
            // Beats length control
            HStack(spacing: 4) {
                Text("Bars:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper(
                    "\(model.totalBeats / 4)",
                    value: $model.totalBeats,
                    in: 4...64,
                    step: 4
                )
                .font(.caption)
                .frame(width: 80)
            }
            
            Divider().frame(height: 16)
            
            Button(action: { model.deleteSelectedNote() }) {
                Label("Delete", systemImage: "trash")
                    .font(.caption)
            }
            .disabled(model.selectedNoteId == nil)
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button(action: clearAll) {
                Label("Clear All", systemImage: "xmark.circle")
                    .font(.caption)
            }
            .disabled(model.notes.isEmpty)
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Divider().frame(height: 16)
            
            // Scale helper controls
            HStack(spacing: 4) {
                Toggle(isOn: $model.showScaleHelper) {
                    Image(systemName: "music.note.list")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("Show scale helper")
                
                if model.showScaleHelper {
                    Picker("", selection: $model.musicalKey) {
                        ForEach(MusicalKey.allCases) { key in
                            Text(key.name).tag(key)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 50)
                    .controlSize(.small)
                    
                    Picker("", selection: $model.scaleType) {
                        ForEach(ScaleType.allCases) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .controlSize(.small)
                }
            }
            
            Spacer()
            
            Text("\(model.notes.count) notes")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Transport Bar
    
    private var transportBar: some View {
        HStack(spacing: 0) {
            // Play/Stop button (aligned with piano key column)
            Button(action: { togglePlayback() }) {
                Image(systemName: model.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(model.isPlaying ? .red : .green)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(model.isPlaying ? "Stop" : "Play")
            .frame(width: PianoRollLayout.pianoKeyWidth)
            
            Divider().frame(height: 24)
            
            // Scrub zone (same width as the grid, scrolls in sync)
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // Beat markers
                    scrubBackground
                    
                    // Playhead line
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: 2, height: 28)
                        .offset(x: PianoRollLayout.xForBeat(model.playheadBeat))
                        .allowsHitTesting(false)
                        .animation(nil, value: model.playheadBeat)
                }
                .frame(
                    width: PianoRollLayout.gridWidth(beats: model.totalBeats),
                    height: 28
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
        .frame(height: 28)
        .background(Color.green.opacity(0.08))
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
                    with: .color(.gray.opacity(isMeasure ? 0.5 : 0.2)),
                    lineWidth: isMeasure ? 1 : 0.5
                )
                
                if isMeasure && beat < totalBeats {
                    let bar = (beat / 4) + 1
                    let text = Text("\(bar)").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                    context.draw(text, at: CGPoint(x: x + 8, y: size.height / 2))
                }
            }
        }
        .frame(
            width: PianoRollLayout.gridWidth(beats: model.totalBeats),
            height: 28
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
            stopPlayback()
            model.playheadBeat = 0
            return
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
            model.activeNoteIDs.insert(note.id)
        }
    }
    
    private func stopAllActiveNotes() {
        for id in model.activeNoteIDs {
            if let note = model.notes.first(where: { $0.id == id }) {
                midiService.sendNoteOff(note: note.pitch)
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
        
        // Set CC values then play
        midiService.consonant = note.consonant
        midiService.vowel = note.vowel
        midiService.vibrato = note.vibrato
        midiService.reverb = note.reverb
        midiService.sendNoteOn(note: pitch, velocity: note.velocity)
        
        print("🔊 play pitch=\(pitch) for \(String(format: "%.2f", durationSeconds))s")
        
        // Schedule stop
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) { [self] in
            print("🔊 stop pitch=\(pitch)")
            midiService.sendNoteOff(note: pitch)
        }
    }
    
    private func clearAll() {
        model.notes.removeAll()
        model.selectedNoteId = nil
    }
}

// MARK: - Note Inspector

struct NoteInspectorView: View {
    let note: SequencerNote
    var onUpdate: (SequencerNote) -> Void
    var onPlay: (SequencerNote) -> Void
    var onDelete: () -> Void
    
    // Local editing state synced from the note
    @State private var consonant: UInt8 = 125
    @State private var vowel: UInt8 = 0
    @State private var velocity: Double = 100
    @State private var vibrato: Double = 64
    @State private var reverb: Double = 32
    @State private var isSyncing = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Note info
            VStack(alignment: .leading, spacing: 2) {
                Text(PitchConstants.noteName(for: note.pitch))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Beat \(note.startBeat, specifier: "%.2f") | \(note.duration, specifier: "%.2f")b")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 70)
            
            Divider().frame(height: 50)
            
            // Consonant picker
            VStack(alignment: .leading, spacing: 2) {
                Text("Consonant")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Picker("", selection: $consonant) {
                    ForEach(Consonant.all) { c in
                        Text(c.name).tag(c.ccValue)
                    }
                }
                .labelsHidden()
                .frame(width: 70)
                .controlSize(.small)
                .onChange(of: consonant) { _ in pushUpdate() }
            }
            
            // Vowel picker
            VStack(alignment: .leading, spacing: 2) {
                Text("Vowel")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Picker("", selection: $vowel) {
                    ForEach(Vowel.all) { v in
                        Text("\(v.symbol) \(v.example)").tag(v.ccValue)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                .controlSize(.small)
                .onChange(of: vowel) { _ in pushUpdate() }
            }
            
            Divider().frame(height: 50)
            
            // Velocity
            VStack(alignment: .leading, spacing: 2) {
                Text("Velocity")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Slider(value: $velocity, in: 1...127, step: 1)
                        .frame(width: 80)
                        .onChange(of: velocity) { _ in pushUpdate() }
                    Text("\(Int(velocity))")
                        .font(.caption2).monospacedDigit()
                        .frame(width: 24)
                }
            }
            
            // Vibrato
            VStack(alignment: .leading, spacing: 2) {
                Text("Vibrato")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Slider(value: $vibrato, in: 0...127, step: 1)
                        .frame(width: 60)
                        .onChange(of: vibrato) { _ in pushUpdate() }
                    Text("\(Int(vibrato))")
                        .font(.caption2).monospacedDigit()
                        .frame(width: 24)
                }
            }
            
            // Reverb
            VStack(alignment: .leading, spacing: 2) {
                Text("Reverb")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Slider(value: $reverb, in: 0...127, step: 1)
                        .frame(width: 60)
                        .onChange(of: reverb) { _ in pushUpdate() }
                    Text("\(Int(reverb))")
                        .font(.caption2).monospacedDigit()
                        .frame(width: 24)
                }
            }
            
            Divider().frame(height: 50)
            
            // Play button
            Button(action: { onPlay(currentNote()) }) {
                Label("Play", systemImage: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            // Delete
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear { syncFromNote() }
        .onChange(of: note.id) { _ in syncFromNote() }
    }
    
    private func syncFromNote() {
        isSyncing = true
        consonant = note.consonant
        vowel = note.vowel
        velocity = Double(note.velocity)
        vibrato = Double(note.vibrato)
        reverb = Double(note.reverb)
        // Defer clearing the flag so all onChange handlers see isSyncing = true
        DispatchQueue.main.async { isSyncing = false }
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
        guard !isSyncing else { return }
        onUpdate(currentNote())
    }
}
