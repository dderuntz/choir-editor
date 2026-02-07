import SwiftUI
import AppKit

// MARK: - Layout Constants

enum PianoRollLayout {
    static let rowHeight: CGFloat = 20
    static let beatWidth: CGFloat = 80        // pixels per beat
    static let sixteenthWidth: CGFloat = 20   // beatWidth / 4
    static let pianoKeyWidth: CGFloat = 48
    static let resizeHandleWidth: CGFloat = 8
    
    static var totalRows: Int { PitchConstants.pitchCount }
    static func gridHeight() -> CGFloat { CGFloat(totalRows) * rowHeight }
    static func gridWidth(beats: Int) -> CGFloat { CGFloat(beats) * beatWidth }
    
    // Convert between model and view coordinates
    static func xForBeat(_ beat: Double) -> CGFloat { CGFloat(beat) * beatWidth }
    static func beatForX(_ x: CGFloat) -> Double { Double(x) / Double(beatWidth) }
    
    /// Row 0 is the TOP row = maxPitch. Higher pitches at top.
    static func yForPitch(_ pitch: UInt8) -> CGFloat {
        CGFloat(Int(PitchConstants.maxPitch) - Int(pitch)) * rowHeight
    }
    static func pitchForY(_ y: CGFloat) -> UInt8 {
        let row = Int(y / rowHeight)
        let pitch = Int(PitchConstants.maxPitch) - row
        return PitchConstants.clampPitch(UInt8(clamping: max(0, pitch)))
    }
}

// MARK: - Piano Roll View

struct PianoRollView: View {
    @ObservedObject var model: SequencerModel
    var onNotePreview: ((SequencerNote) -> Void)?
    var onNotePitchChange: ((UInt8, UInt8) -> Void)?  // (oldPitch, newPitch)
    var onNotePreviewStop: ((UInt8) -> Void)?
    
    var body: some View {
        // Vertical scroll wraps both piano keys and grid together
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                // Piano key labels (scrolls vertically with grid)
                pianoKeys
                    .frame(width: PianoRollLayout.pianoKeyWidth)
                
                Divider()
                
                // Grid area: horizontal scroll only
                ScrollView(.horizontal) {
                    gridContent
                        .frame(
                            width: PianoRollLayout.gridWidth(beats: model.totalBeats),
                            height: PianoRollLayout.gridHeight()
                        )
                }
            }
        }
    }
    
    // MARK: - Grid Content (ZStack)
    
    private var gridContent: some View {
        ZStack(alignment: .topLeading) {
            // 1. Grid background (row shading + lines)
            PianoRollGridBackground(totalBeats: model.totalBeats)
            
            // 2. Click-to-add overlay
            gridClickOverlay
            
            // 3. Notes on top
            notesLayer
        }
        .coordinateSpace(name: "pianoGrid")
    }
    
    // MARK: - Piano Key Labels
    
    private var pianoKeys: some View {
        VStack(spacing: 0) {
            ForEach((Int(PitchConstants.minPitch)...Int(PitchConstants.maxPitch)).reversed(), id: \.self) { pitch in
                let p = UInt8(pitch)
                HStack(spacing: 0) {
                    Spacer()
                    Text(PitchConstants.noteName(for: p))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(
                            p == 60 ? .yellow :
                            PitchConstants.isBlackKey(p) ? .secondary : .primary
                        )
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .frame(height: PianoRollLayout.rowHeight)
                .background(
                    PitchConstants.isBlackKey(p)
                        ? Color.black.opacity(0.15)
                        : Color.clear
                )
            }
        }
    }
    
    // MARK: - Notes Layer
    
    private var notesLayer: some View {
        ForEach(model.notes) { note in
            NoteRectView(
                note: note,
                isSelected: model.selectedNoteId == note.id,
                onSelect: {
                    model.selectedNoteId = note.id
                    onNotePreview?(note)
                },
                onMove: { newBeat, newPitch in
                    model.moveNote(id: note.id, toBeat: newBeat, pitch: newPitch)
                },
                onResize: { newDuration in
                    model.resizeNote(id: note.id, duration: newDuration)
                },
                onDragPitchChange: { oldPitch, newPitch in
                    onNotePitchChange?(oldPitch, newPitch)
                },
                onDragStart: { pitch in
                    if let currentNote = model.notes.first(where: { $0.id == note.id }) {
                        onNotePreview?(currentNote)
                    }
                },
                onDragEnd: { pitch in
                    onNotePreviewStop?(pitch)
                }
            )
        }
    }
    
    // MARK: - Grid Click Overlay
    
    private var gridClickOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(
                width: PianoRollLayout.gridWidth(beats: model.totalBeats),
                height: PianoRollLayout.gridHeight()
            )
            .onTapGesture { location in
                let beat = PianoRollLayout.beatForX(location.x)
                let pitch = PianoRollLayout.pitchForY(location.y)
                
                // Only add if no existing note at this position
                if model.noteAt(beat: beat, pitch: pitch) == nil {
                    let note = model.addNote(atBeat: beat, pitch: pitch, duration: 1.0)
                    onNotePreview?(note)
                }
            }
    }
}

// MARK: - Grid Background View

struct PianoRollGridBackground: View {
    let totalBeats: Int
    
    var body: some View {
        ZStack {
            // Row shading for black keys
            VStack(spacing: 0) {
                ForEach((Int(PitchConstants.minPitch)...Int(PitchConstants.maxPitch)).reversed(), id: \.self) { pitch in
                    Rectangle()
                        .fill(
                            PitchConstants.isBlackKey(UInt8(pitch))
                                ? Color(NSColor.systemGray).opacity(0.08)
                                : Color.clear
                        )
                        .frame(height: PianoRollLayout.rowHeight)
                }
            }
            
            // 16th note subdivision lines (light)
            SubdivisionGridShape(totalBeats: totalBeats)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
            
            // Beat and row boundary lines (stronger)
            BeatGridShape(totalBeats: totalBeats)
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        }
    }
}

// MARK: - Grid Shapes

struct BeatGridShape: Shape {
    let totalBeats: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows = PitchConstants.pitchCount
        let rh = PianoRollLayout.rowHeight
        let bw = PianoRollLayout.beatWidth
        
        // Horizontal lines (row boundaries)
        for row in 0...rows {
            let y = CGFloat(row) * rh
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        
        // Vertical beat lines
        for beat in 0...totalBeats {
            let x = CGFloat(beat) * bw
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        return path
    }
}

struct SubdivisionGridShape: Shape {
    let totalBeats: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bw = PianoRollLayout.beatWidth
        let sw = PianoRollLayout.sixteenthWidth
        
        for beat in 0..<totalBeats {
            for sub in 1..<4 {
                let x = CGFloat(beat) * bw + CGFloat(sub) * sw
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: rect.height))
            }
        }
        
        return path
    }
}

// MARK: - Note Rectangle View

struct NoteRectView: View {
    let note: SequencerNote
    let isSelected: Bool
    var onSelect: () -> Void
    var onMove: (Double, UInt8) -> Void
    var onResize: (Double) -> Void
    var onDragPitchChange: ((UInt8, UInt8) -> Void)?
    var onDragStart: ((UInt8) -> Void)?
    var onDragEnd: ((UInt8) -> Void)?
    
    // Visual-only offsets (no model mutation during drag = no flicker)
    @State private var dragOffset = CGSize.zero
    @State private var resizeOffset: CGFloat = 0
    
    @State private var hasFiredDragStart = false
    @State private var lastDragPitch: UInt8 = 0
    
    private var isDragging: Bool { dragOffset != .zero }
    private var isResizing: Bool { resizeOffset != 0 }
    
    private var noteColor: Color {
        if isSelected { return .accentColor }
        // Color by vowel for visual variety
        let hue = Double(note.vowel) / 127.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.85)
    }
    
    private var x: CGFloat { PianoRollLayout.xForBeat(note.startBeat) }
    private var y: CGFloat { PianoRollLayout.yForPitch(note.pitch) }
    private var noteWidth: CGFloat { CGFloat(note.duration) * PianoRollLayout.beatWidth }
    private var noteHeight: CGFloat { PianoRollLayout.rowHeight }
    
    // Visual width includes resize offset (applied via @GestureState)
    private var visualWidth: CGFloat { max(noteWidth + resizeOffset, 6) }
    
    var body: some View {
        noteBody
            .frame(width: visualWidth, height: noteHeight - 2)
            .offset(
                x: x + dragOffset.width,
                y: y + 1 + dragOffset.height
            )
            .zIndex(isSelected ? 10 : (isDragging ? 5 : 1))
    }
    
    private var noteBody: some View {
        ZStack(alignment: .trailing) {
            // Main note rectangle
            RoundedRectangle(cornerRadius: 3)
                .fill(noteColor.opacity(isDragging ? 0.6 : 0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            isSelected ? Color.white : noteColor.opacity(0.5),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )
                .overlay(noteLabel, alignment: .leading)
            
            // Resize handle on right edge
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: PianoRollLayout.resizeHandleWidth)
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() }
                    else { NSCursor.pop() }
                }
                .highPriorityGesture(resizeGesture)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(moveGesture)
    }
    
    // MARK: - Label
    
    @ViewBuilder
    private var noteLabel: some View {
        if visualWidth > 28 {
            Text(phonemeLabel)
                .font(.system(size: 8))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.leading, 3)
        }
    }
    
    private var phonemeLabel: String {
        let c = Consonant.all.first { $0.ccValue == note.consonant }?.name ?? ""
        let v = Vowel.all.first { $0.ccValue == note.vowel }?.symbol ?? ""
        if c == "None" || c == "Random" {
            return v
        }
        return "\(c)\(v)"
    }
    
    // MARK: - Move Gesture
    // Uses @GestureState for visual offset; only commits to model on .onEnded
    
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("pianoGrid"))
            .onChanged { value in
                let dist = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)
                // Only start visual drag after threshold (tap detection)
                guard dist > 4 else { return }
                
                // Update visual offset (no model mutation = no flicker)
                dragOffset = value.translation
                
                // Fire drag start callback once
                if !hasFiredDragStart {
                    hasFiredDragStart = true
                    lastDragPitch = note.pitch
                    print("🎯 DRAG START: note=\(note.pitch) beat=\(note.startBeat)")
                    onDragStart?(note.pitch)
                }
                
                print("🔄 t=(\(String(format: "%.1f", value.translation.width)), \(String(format: "%.1f", value.translation.height))) loc=(\(String(format: "%.1f", value.location.x)), \(String(format: "%.1f", value.location.y))) start=(\(String(format: "%.1f", value.startLocation.x)), \(String(format: "%.1f", value.startLocation.y))) id=\(note.id.uuidString.prefix(4))")
                
                // Live MIDI preview: compute pitch from offset, no model mutation
                let pitchDelta = -Int(round(value.translation.height / PianoRollLayout.rowHeight))
                let rawPitch = Int(note.pitch) + pitchDelta
                let newPitch = PitchConstants.clampPitch(UInt8(clamping: max(0, rawPitch)))
                
                if newPitch != lastDragPitch {
                    onDragPitchChange?(lastDragPitch, newPitch)
                    lastDragPitch = newPitch
                }
            }
            .onEnded { value in
                let dist = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)
                
                if dist <= 4 {
                    // Tap -- select the note
                    print("🎯 TAP SELECT: note=\(note.pitch)")
                    onSelect()
                } else {
                    // Drag -- commit final position to model
                    let beatDelta = PianoRollLayout.beatForX(value.translation.width)
                    let newBeat = max(0, note.startBeat + beatDelta)
                    
                    let pitchDelta = -Int(round(value.translation.height / PianoRollLayout.rowHeight))
                    let rawPitch = Int(note.pitch) + pitchDelta
                    let newPitch = PitchConstants.clampPitch(UInt8(clamping: max(0, rawPitch)))
                    
                    print("🎯 DRAG END: t=(\(String(format: "%.1f", value.translation.width)), \(String(format: "%.1f", value.translation.height))) newBeat=\(String(format: "%.2f", newBeat)) newPitch=\(newPitch)")
                    
                    onMove(newBeat, newPitch)
                    onDragEnd?(newPitch)
                }
                
                // Reset
                dragOffset = .zero
                hasFiredDragStart = false
            }
    }
    
    // MARK: - Resize Gesture
    // Uses @GestureState for visual width offset; only commits to model on .onEnded
    
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("pianoGrid"))
            .onChanged { value in
                resizeOffset = value.translation.width
            }
            .onEnded { value in
                let beatDelta = PianoRollLayout.beatForX(value.translation.width)
                let newDuration = max(GridConstants.minDuration, note.duration + beatDelta)
                resizeOffset = 0
                onResize(newDuration)
            }
    }
}

