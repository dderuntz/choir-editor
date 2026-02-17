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
    @State private var pendingClearAll = false
    
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
                        .foregroundColor(Theme.dark.opacity(model.showScaleHelper ? 1 : 0.5))

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
                .tint(Theme.dark)
                .foregroundStyle(Theme.dark)

                    if model.showScaleHelper {
                        Picker("", selection: $model.scaleType) {
                            ForEach(ScaleType.allCases) { scale in
                                Text("\(scale.rawValue) Scale").tag(scale)
                            }
                        }
                        .labelsHidden()
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .tint(Theme.dark)
                        .foregroundStyle(Theme.dark)
                    }
                }
                
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
                .buttonStyle(HoverPillStyle(colorScheme: colorScheme, textColor: Theme.dark))
                .disabled(model.notes.isEmpty && model.selectedNoteIds.isEmpty)
                
                
                Button(action: { model.isLooping.toggle() }) {
                    Label("Loop", systemImage: "repeat.circle.fill")
                        .foregroundColor(model.isLooping ? Theme.dark : Theme.dark.opacity(0.25))
                }
                .buttonStyle(.borderless)
                .help(model.isLooping ? "Looping" : "Loop")
                
                Stepper("\(model.totalBeats / 4) Bars", value: Binding(
                    get: { model.totalBeats / 4 },
                    set: { model.totalBeats = $0 * 4 }
                ), in: 1...16)
                .monospacedDigit()
                .controlSize(.small)
                .tint(Theme.fieldLight)
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
                    .foregroundColor(Theme.dark)
                    .frame(width: PianoRollLayout.pianoKeyWidth)
                    .frame(maxHeight: .infinity)
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

// MARK: - Note Inspector

// MARK: - Callout Arrow Shape

/// Inspector background shape: rectangle with a cartouche arrow bump on the top edge
struct InspectorBubbleShape: Shape {
    var arrowX: CGFloat
    var arrowWidth: CGFloat = 44
    var arrowHeight: CGFloat = 10
    
    var animatableData: CGFloat {
        get { arrowX }
        set { arrowX = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Rectangle body (top edge at arrowHeight offset, so arrow lives above)
        let bodyTop = rect.minY + arrowHeight
        
        // Start at top-left of body
        path.move(to: CGPoint(x: rect.minX, y: bodyTop))
        
        // Walk along top edge to the arrow
        let aLeft = arrowX - arrowWidth / 2
        let aRight = arrowX + arrowWidth / 2
        let clampedLeft = max(rect.minX, aLeft)
        let clampedRight = min(rect.maxX, aRight)
        
        path.addLine(to: CGPoint(x: clampedLeft, y: bodyTop))
        
        // Draw the cartouche arrow bump (SVG viewBox 46x11, flipped Y)
        if clampedRight > clampedLeft {
            let sx = (clampedRight - clampedLeft) / 46
            let sy = arrowHeight / 11
            func p(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: clampedLeft + x * sx, y: bodyTop - y * sy)
            }
            path.addLine(to: p(5.28, 0))
            path.addCurve(to: p(10.03, 0.5), control1: p(7.78, 0), control2: p(8.9, 0.06))
            path.addCurve(to: p(13.11, 2.85), control1: p(11.16, 0.94), control2: p(12.17, 1.92))
            path.addLine(to: p(15.76, 5.5))
            path.addLine(to: p(19.07, 8.81))
            path.addCurve(to: p(23, 10.5), control1: p(20.4, 10.19), control2: p(21.65, 10.5))
            path.addCurve(to: p(26.93, 8.81), control1: p(24.35, 10.5), control2: p(25.6, 10.2))
            path.addLine(to: p(30.24, 5.5))
            path.addLine(to: p(32.89, 2.85))
            path.addCurve(to: p(35.97, 0.5), control1: p(33.83, 1.92), control2: p(34.85, 0.94))
            path.addCurve(to: p(40.72, 0), control1: p(37.1, 0.06), control2: p(38.22, 0))
        }
        
        path.addLine(to: CGPoint(x: clampedRight, y: bodyTop))
        
        // Continue along top edge to top-right
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyTop))
        // Down right side
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Along bottom
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Close back to top-left
        path.closeSubpath()
        
        return path
    }
}

/// Apple cartouche arrow shape (from system popover SVG, flipped to point up)
struct CalloutArrow: Shape {
    func path(in rect: CGRect) -> Path {
        // Original SVG viewBox: 46 x 11, tip pointing down.
        // We flip Y so the tip points up.
        let sx = rect.width / 46
        let sy = rect.height / 11
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + (11 - y) * sy)
        }
        var path = Path()
        path.move(to: p(26.93, 8.81))
        path.addLine(to: p(30.24, 5.5))
        path.addLine(to: p(32.89, 2.85))
        path.addCurve(to: p(35.97, 0.5), control1: p(33.83, 1.92), control2: p(34.85, 0.94))
        path.addCurve(to: p(40.72, 0), control1: p(37.1, 0.06), control2: p(38.22, 0))
        path.addLine(to: p(46, 0))
        path.addLine(to: p(0, 0))
        path.addLine(to: p(5.28, 0))
        path.addCurve(to: p(10.03, 0.5), control1: p(7.78, 0), control2: p(8.9, 0.06))
        path.addCurve(to: p(13.11, 2.85), control1: p(11.16, 0.94), control2: p(12.17, 1.92))
        path.addLine(to: p(15.76, 5.5))
        path.addLine(to: p(19.07, 8.81))
        path.addCurve(to: p(23, 10.5), control1: p(20.4, 10.19), control2: p(21.65, 10.5))
        path.addCurve(to: p(26.93, 8.81), control1: p(24.35, 10.5), control2: p(25.6, 10.2))
        path.closeSubpath()
        return path
    }
}

// MARK: - Note Popover Inspector (attached to selected note, like PhonemeInspector)

struct NotePopoverInspector: View {
    let note: SequencerNote
    let groupCount: Int
    var onUpdate: (SequencerNote) -> Void
    var onPlay: (SequencerNote) -> Void
    var onDelete: () -> Void
    
    @State private var consonant: UInt8
    @State private var vowel: UInt8
    @State private var velocity: Double
    @State private var vibrato: Double
    @State private var reverb: Double
    @State private var isSyncing = true
    
    init(note: SequencerNote, groupCount: Int = 1, onUpdate: @escaping (SequencerNote) -> Void, onPlay: @escaping (SequencerNote) -> Void, onDelete: @escaping () -> Void) {
        self.note = note
        self.groupCount = groupCount
        self.onUpdate = onUpdate
        self.onPlay = onPlay
        self.onDelete = onDelete
        _consonant = State(initialValue: note.consonant)
        _vowel = State(initialValue: note.vowel)
        _velocity = State(initialValue: Double(note.velocity))
        _vibrato = State(initialValue: Double(note.vibrato))
        _reverb = State(initialValue: Double(note.reverb))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            if groupCount > 1 {
                Text("\(groupCount) notes")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 2) {
                    Text(PitchConstants.noteName(for: note.pitch))
                        .font(.system(size: 13, weight: .medium))
                    Text("Beat \(Int(note.startBeat + 1))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // Consonant
            HStack {
                Text("Cons")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)
                Picker("", selection: $consonant) {
                    ForEach(Consonant.all) { c in
                        Text(c.name).tag(c.ccValue)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 80, maxWidth: .infinity)
                .controlSize(.small)
                .onChange(of: consonant) { pushUpdate() }
            }
            
            // Vowel
            HStack {
                Text("Vowel")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)
                Picker("", selection: $vowel) {
                    ForEach(Vowel.all) { v in
                        Text(v.ccValue == 0 ? "Random" : "\(v.symbol) \(v.example)").tag(v.ccValue)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 80, maxWidth: .infinity)
                .controlSize(.small)
                .onChange(of: vowel) { pushUpdate() }
            }
            
            // Velocity
            compactSlider(label: "Vel", value: $velocity, range: 1...127)
            
            // Vibrato
            compactSlider(label: "Vib", value: $vibrato, range: 0...127)
            
            // Reverb
            compactSlider(label: "Rev", value: $reverb, range: 0...127)
            
            Divider()
            
            // Actions
            HStack {
                Button(action: { onPlay(currentNote()) }) {
                    Label("Test", systemImage: "ear")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(width: 170)
        .padding(12)
        .onAppear {
            DispatchQueue.main.async { isSyncing = false }
        }
    }
    
    private func compactSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)
            Text("\(Int(value.wrappedValue))")
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
            Slider(value: value, in: range)
                .controlSize(.small)
                .onChange(of: value.wrappedValue) { pushUpdate() }
        }
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

// MARK: - Note Inspector (bottom bar — legacy, kept for now)

struct NoteInspectorView: View {
    let note: SequencerNote
    var arrowX: CGFloat = 0  // horizontal position of arrow from leading edge
    var groupCount: Int = 1  // number of selected notes (1 = single)
    var onUpdate: (SequencerNote) -> Void
    var onPlay: (SequencerNote) -> Void
    var noteDurationSeconds: Double = 1.0
    var onDelete: () -> Void
    
    // Local editing state synced from the note (view is recreated via .id() on selection change)
    @State private var consonant: UInt8 = 125
    @State private var vowel: UInt8 = 0
    @State private var velocity: Double = 100
    @State private var vibrato: Double = 64
    @State private var reverb: Double = 32
    @State private var isSyncing = true  // suppress pushUpdate during initial sync
    @State private var isTesting = false
    
    private var isBlackKey: Bool { PitchConstants.isBlackKey(note.pitch) }
    private var bg: Color { isBlackKey ? Theme.dark : Theme.ivory }
    private var fg: Color { isBlackKey ? Theme.ivory : Theme.dark }
    private var fgDim: Color { fg.opacity(0.5) }
    private var dividerColor: Color { fg.opacity(0.15) }
    
    private var phonemeLabel: String {
        let c = Consonant.all.first { $0.ccValue == consonant }
        let v = Vowel.all.first { $0.ccValue == vowel }
        let isRandomCons = (c?.name == "Random")
        let isNoneCons = (c?.name == "None")
        let isRandomVowel = (v?.ccValue == 0)
        
        if isRandomCons && isRandomVowel { return "Random" }
        
        var parts = ""
        if !isRandomCons && !isNoneCons { parts += c?.name ?? "" }
        if isRandomCons { parts += "?" }
        if !isRandomVowel { parts += v?.symbol ?? "" }
        else if !isRandomCons { parts += "?" }
        return parts.isEmpty ? "—" : parts
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Note info
            VStack(alignment: .leading, spacing: 2) {
                if groupCount > 1 {
                    Text("\(groupCount) notes")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.accent)
                } else {
                    Text(phonemeLabel)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(fg)
                    Text("\(PitchConstants.noteName(for: note.pitch)) · \(beatLabel(note.startBeat))")
                        .font(.caption2)
                        .foregroundColor(fgDim)
                        .monospacedDigit()
                }
            }
            .frame(minWidth: 55, alignment: .leading)
            
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
                .onChange(of: consonant) { pushUpdate() }
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
                .onChange(of: vowel) { pushUpdate() }
            }
            
            // Velocity
            inspectorSlider(label: "Velocity", value: $velocity, range: 1...127) { pushUpdate() }
            
            // Vibrato
            inspectorSlider(label: "Vibrato", value: $vibrato, range: 0...127) { pushUpdate() }
            
            // Reverb
            inspectorSlider(label: "Reverb", value: $reverb, range: 0...127) { pushUpdate() }
            
            Spacer()
            
            // Test button
            Button(action: {
                onPlay(currentNote())
                isTesting = true
                DispatchQueue.main.asyncAfter(deadline: .now() + noteDurationSeconds) {
                    isTesting = false
                }
            }) {
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
                        .fill(isTesting ? Theme.green : Theme.accent)
                )
                .animation(.easeInOut(duration: 0.15), value: isTesting)
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
        .frame(height: 80) // 70 body + 10 arrow
        .padding(.top, 10) // reserve space for arrow above body
        .background(.ultraThinMaterial, in: InspectorBubbleShape(arrowX: arrowX))
        .glassEffect(in: InspectorBubbleShape(arrowX: arrowX))
        .environment(\.colorScheme, isBlackKey ? .dark : .light)
        .onAppear { syncFromNote() }
    }
    
    private func syncFromNote() {
        isSyncing = true
        consonant = note.consonant
        vowel = note.vowel
        velocity = Double(note.velocity)
        vibrato = Double(note.vibrato)
        reverb = Double(note.reverb)
        // Allow onChange to settle before re-enabling pushUpdate
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
    
    /// Format beat as "Beat bar.sixteenth" (1-indexed, e.g. "Beat 2.3")
    private func beatLabel(_ beat: Double) -> String {
        let wholeBeat = Int(beat)
        let sixteenth = Int(round((beat - Double(wholeBeat)) * 4)) + 1
        return "Beat \(wholeBeat + 1).\(sixteenth)"
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
                .onChange(of: value.wrappedValue) { onChange() }
        }
    }
}
