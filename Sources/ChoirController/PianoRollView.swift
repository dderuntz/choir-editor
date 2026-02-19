import SwiftUI
import AppKit
import Combine

// MARK: - Scroll Sync (bidirectional NSScrollView sync)

@MainActor
class ScrollSyncManager: ObservableObject {
    private var scrollViews: [String: NSScrollView] = [:]
    private var activeScroller: String? = nil
    /// Current horizontal scroll offset (published for SwiftUI arrow positioning, etc.)
    @Published var horizontalOffset: CGFloat = 0
    
    func register(_ id: String, scrollView: NSScrollView) {
        scrollViews[id] = scrollView
    }
    
    func handleScroll(from id: String, offset: CGFloat) {
        // Prevent re-entry: if another scroller is active, ignore
        guard activeScroller == nil || activeScroller == id else { return }
        activeScroller = id
        horizontalOffset = offset
        for (key, sv) in scrollViews where key != id {
            let current = sv.contentView.bounds.origin.x
            if abs(current - offset) > 0.5 {
                sv.contentView.setBoundsOrigin(NSPoint(x: offset, y: sv.contentView.bounds.origin.y))
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.activeScroller = nil
        }
    }
}

/// Drop this inside a ScrollView to register it for bidirectional horizontal scroll sync.
struct ScrollSyncHelper: NSViewRepresentable {
    let id: String
    let manager: ScrollSyncManager
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .init(x: 0, y: 0, width: 1, height: 1))
        // Find parent NSScrollView on next runloop (after view is in hierarchy)
        DispatchQueue.main.async {
            guard let sv = Self.findScrollView(of: view) else { return }
            context.coordinator.scrollView = sv
            sv.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.boundsChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: sv.contentView
            )
            Task { @MainActor in
                manager.register(id, scrollView: sv)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(id: id, manager: manager)
    }
    
    static func findScrollView(of view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let parent = current?.superview {
            if let sv = parent as? NSScrollView { return sv }
            current = parent
        }
        return nil
    }
    
    @MainActor
    class Coordinator: NSObject {
        let id: String
        let manager: ScrollSyncManager
        var scrollView: NSScrollView?
        
        init(id: String, manager: ScrollSyncManager) {
            self.id = id
            self.manager = manager
        }
        
        @objc func boundsChanged(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView else { return }
            let offset = clipView.bounds.origin.x
            manager.handleScroll(from: id, offset: offset)
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Layout Constants

enum PianoRollLayout {
    static let rowHeight: CGFloat = 24
    static let beatWidth: CGFloat = 80        // pixels per beat
    static let sixteenthWidth: CGFloat = 20   // beatWidth / 4
    static let pianoKeyWidth: CGFloat = 56
    static let resizeHandleWidth: CGFloat = 8
    
    static var totalRows: Int { PitchConstants.pitchCount }
    static func gridHeight() -> CGFloat { CGFloat(totalRows + 1) * rowHeight }
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
    var onNoteUpdate: ((SequencerNote) -> Void)?
    var onNoteDelete: (() -> Void)?
    var scrollSync: ScrollSyncManager? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    // Shared group drag offset for multi-select move
    @State private var groupDragOffset: CGSize = .zero
    
    // Marquee selection state
    @State private var marqueeOrigin: CGPoint? = nil
    @State private var marqueeRect: CGRect? = nil
    
    var body: some View {
        // TODO: Replace nested ScrollViews with a single NSScrollView wrapper for proper 2D scrolling with both scrollbars visible
        // Vertical scroll wraps both piano keys and grid together
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    // Piano key labels (scrolls vertically with grid)
                    pianoKeys
                        .frame(width: PianoRollLayout.pianoKeyWidth)
                    
                    Theme.structuralDivider.opacity(0.4).frame(width: 1)
                    
                    // Grid area: horizontal scroll only
                    ScrollView(.horizontal) {
                        gridContent
                            .frame(
                                width: PianoRollLayout.gridWidth(beats: model.totalBeats),
                                height: PianoRollLayout.gridHeight()
                            )
                            .background {
                                if let sync = scrollSync {
                                    ScrollSyncHelper(id: "grid", manager: sync)
                                }
                            }
                    }
                    .background(Theme.fieldColor(colorScheme))
                }
            }
            .background(Theme.fieldColor(colorScheme))
            .onChange(of: model.highlightedPitch) { _, pitch in
                if let pitch = pitch {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(Int(pitch), anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - Grid Content (ZStack)
    
    private var gridContent: some View {
        ZStack(alignment: .topLeading) {
            // 1. Grid background (row shading + lines + scale helper)
            PianoRollGridBackground(
                totalBeats: model.totalBeats,
                showScaleHelper: model.showScaleHelper,
                isInScale: model.showScaleHelper ? { model.isInScale($0) } : nil
            )
            
            // 2. Keyboard highlight row
            if let pitch = model.highlightedPitch {
                Rectangle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(
                        width: PianoRollLayout.gridWidth(beats: model.totalBeats),
                        height: PianoRollLayout.rowHeight
                    )
                    .offset(y: PianoRollLayout.yForPitch(pitch))
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.1), value: model.highlightedPitch)
            }
            
            // 3. Click-to-add overlay
            gridClickOverlay
            
            // 4. Notes on top
            notesLayer
                .compositingGroup()
                .shadow(color: Theme.dark.opacity(0.15), radius: 10, x: 0, y: 1)
            
            // 5. Scale hatch overlay (sits above notes, passes through clicks)
            if model.showScaleHelper {
                scaleHatchOverlay
                    .allowsHitTesting(false)
            }
            
            // 6. Marquee selection rectangle
            if let rect = marqueeRect {
                Rectangle()
                    .fill(Theme.accent.opacity(0.1))
                    .overlay(
                        Rectangle()
                            .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1, antialiased: false)
                    )
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
            
            // 7. Playhead line (green, full height)
            playheadLine
        }
        .coordinateSpace(name: "pianoGrid")
    }
    
    // MARK: - Scale Hatch Overlay (above notes)
    
    private var scaleHatchOverlay: some View {
        VStack(spacing: 0) {
            ForEach((Int(PitchConstants.minPitch)...Int(PitchConstants.maxPitch)).reversed(), id: \.self) { pitch in
                let p = UInt8(pitch)
                let outOfScale = !(model.isInScale(p))
                
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: PianoRollLayout.rowHeight)
                    .overlay {
                        if outOfScale {
                                HatchShape(spacing: 6)
                                    .stroke(hatchColor, lineWidth: 0.5)
                                    .clipped()
                            }
                        }
            }
            Color.clear.frame(height: PianoRollLayout.rowHeight)
        }
    }
    
    private var hatchColor: Color {
        colorScheme == .dark
            ? Color(red: 0x67/255, green: 0x68/255, blue: 0x5F/255).opacity(0.8)
            : Theme.field.opacity(0.6)
    }
    
    // MARK: - Playhead Line
    
    private var playheadLine: some View {
        let xPos = PianoRollLayout.xForBeat(model.playheadBeat)
        return Rectangle()
            .fill(model.isPlaying ? Theme.green : Theme.accent)
            .frame(width: 2, height: PianoRollLayout.gridHeight())
            .offset(x: xPos)
            .allowsHitTesting(false)
            .animation(nil, value: model.playheadBeat)
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
                        .foregroundColor(p == 60 ? Theme.middleC : Theme.text(colorScheme))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .frame(height: PianoRollLayout.rowHeight)
                .background(
                    PitchConstants.isBlackKey(p)
                        ? Theme.blackKeyRow
                        : Color.clear
                )
                .id(pitch)
            }
            Color.clear.frame(height: PianoRollLayout.rowHeight)
        }
        .background(Theme.fieldColor(colorScheme))
    }
    
    // MARK: - Notes Layer
    
    private var notesLayer: some View {
        ForEach(model.notes) { note in
            let isInGroup = model.selectedNoteIds.count > 1 && model.selectedNoteIds.contains(note.id)
            NoteRectView(
                note: note,
                isSelected: model.selectedNoteId == note.id,
                isInMultiSelect: isInGroup,
                groupDragOffset: isInGroup ? groupDragOffset : .zero,
                actions: NoteActions(
                    onSelect: {
                        if model.selectedNoteIds.count > 1 && model.selectedNoteIds.contains(note.id) {
                            model.selectedNoteId = note.id
                        } else {
                            model.selectNote(note.id)
                        }
                        onNotePreview?(note)
                    },
                    onShiftSelect: {
                        model.toggleNoteInSelection(note.id)
                    },
                    onMove: { newBeat, newPitch in
                        model.moveNote(id: note.id, toBeat: newBeat, pitch: newPitch)
                    },
                    onResize: { newDuration in
                        model.resizeNote(id: note.id, duration: newDuration)
                    },
                    onDuplicate: {
                        model.duplicateNote(id: note.id)?.id
                    },
                    onDuplicateMove: { dupId, newBeat, newPitch in
                        model.moveNote(id: dupId, toBeat: newBeat, pitch: newPitch)
                    },
                    onCancelDuplicate: { dupId in
                        model.deleteNote(id: dupId)
                    },
                    onGroupDragChanged: { offset in
                        groupDragOffset = offset
                    },
                    onGroupMoveEnded: { beatDelta, pitchDelta in
                        model.moveSelectedNotes(beatDelta: beatDelta, pitchDelta: pitchDelta)
                        groupDragOffset = .zero
                    }
                )
            )
            .equatable()
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
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let isShift = NSEvent.modifierFlags.contains(.shift)
                        let dist = abs(value.translation.width) + abs(value.translation.height)
                        
                        if isShift && dist > 4 {
                            // Start or update marquee
                            if marqueeOrigin == nil {
                                marqueeOrigin = value.startLocation
                            }
                            if let origin = marqueeOrigin {
                                let rect = CGRect(
                                    x: min(origin.x, value.location.x),
                                    y: min(origin.y, value.location.y),
                                    width: abs(value.location.x - origin.x),
                                    height: abs(value.location.y - origin.y)
                                )
                                marqueeRect = rect
                                
                                // Live-update multi-select set without changing primary
                                let hitIds = notesIntersecting(rect: rect)
                                model.selectedNoteIds = hitIds
                            }
                        }
                    }
                    .onEnded { value in
                        if marqueeRect != nil {
                            // Marquee drag ended — finalize primary selection
                            model.selectedNoteId = model.selectedNoteIds.first
                            marqueeRect = nil
                            marqueeOrigin = nil
                        } else {
                            // Regular click: deselect first if anything is selected
                            let dist = abs(value.translation.width) + abs(value.translation.height)
                            guard dist < 4 else { return }
                            if !model.selectedNoteIds.isEmpty {
                                model.clearSelection()
                            } else {
                                // Add a note only when nothing was selected
                                let beat = PianoRollLayout.beatForX(value.location.x)
                                let pitch = PianoRollLayout.pitchForY(value.location.y)
                                if model.noteAt(beat: beat, pitch: pitch) == nil {
                                    let note = model.addNote(atBeat: beat, pitch: pitch, duration: 1.0)
                                    onNotePreview?(note)
                                }
                            }
                        }
                    }
            )
    }
    
    /// Returns IDs of notes whose visual rect intersects the given rect.
    private func notesIntersecting(rect: CGRect) -> Set<UUID> {
        var ids = Set<UUID>()
        for note in model.notes {
            let noteRect = CGRect(
                x: PianoRollLayout.xForBeat(note.startBeat),
                y: PianoRollLayout.yForPitch(note.pitch),
                width: CGFloat(note.duration) * PianoRollLayout.beatWidth,
                height: PianoRollLayout.rowHeight
            )
            if rect.intersects(noteRect) {
                ids.insert(note.id)
            }
        }
        return ids
    }
}

// MARK: - Grid Background View

struct PianoRollGridBackground: View {
    let totalBeats: Int
    var showScaleHelper: Bool = false
    var isInScale: ((UInt8) -> Bool)? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    private var hatchColor: Color {
        colorScheme == .dark
            ? Color(red: 0x67/255, green: 0x68/255, blue: 0x5F/255).opacity(0.8)
            : Theme.field.opacity(0.6)
    }
    
    var body: some View {
        ZStack {
            // Base field color
            Theme.fieldColor(colorScheme)
            
            // Row shading for black keys + scale helper
            VStack(spacing: 0) {
                ForEach((Int(PitchConstants.minPitch)...Int(PitchConstants.maxPitch)).reversed(), id: \.self) { pitch in
                    let p = UInt8(pitch)
                    let isBlack = PitchConstants.isBlackKey(p)
                    let outOfScale = showScaleHelper && !(isInScale?(p) ?? true)
                    
                    Rectangle()
                        .fill(isBlack ? Theme.blackKeyRow : Color.clear)
                        .frame(height: PianoRollLayout.rowHeight)
                        .overlay {
                            if outOfScale {
                                HatchShape(spacing: 6)
                                    .stroke(hatchColor, lineWidth: 0.5)
                                    .clipped()
                            }
                        }
                }
                Color.clear.frame(height: PianoRollLayout.rowHeight)
            }
            
            // 16th note subdivision lines (light)
            SubdivisionGridShape(totalBeats: totalBeats)
                .stroke(Theme.gridSubdivision, lineWidth: 0.5)
            
            // Beat and row boundary lines
            BeatGridShape(totalBeats: totalBeats)
                .stroke(Theme.gridLine, lineWidth: 0.5)
            
            // Bar boundary lines (every 4 beats, stronger)
            BarGridShape(totalBeats: totalBeats)
                .stroke(Theme.gridBar, lineWidth: 0.5)
        }
    }
}

// MARK: - Crosshatch Pattern

/// Diagonal hatch pattern for out-of-scale rows (↗ direction).
struct HatchShape: Shape {
    var spacing: CGFloat = 6
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let d = spacing
        let w = rect.width
        let h = rect.height
        
        // ↗ lines (bottom-left to top-right)
        var offset: CGFloat = -h
        while offset < w + h {
            path.move(to: CGPoint(x: offset, y: h))
            path.addLine(to: CGPoint(x: offset + h, y: 0))
            offset += d
        }
        
        return path
    }
}

// MARK: - Grid Shapes

struct BeatGridShape: Shape {
    let totalBeats: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bw = PianoRollLayout.beatWidth
        
        // Vertical beat lines
        for beat in 0...totalBeats {
            let x = CGFloat(beat) * bw
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        return path
    }
}

struct BarGridShape: Shape {
    let totalBeats: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bw = PianoRollLayout.beatWidth
        
        // Vertical bar lines (every 4 beats)
        for beat in stride(from: 0, through: totalBeats, by: 4) {
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

// MARK: - Note Action Callbacks

struct NoteActions {
    // Selection
    var onSelect: () -> Void
    var onShiftSelect: () -> Void
    // Single note
    var onMove: (Double, UInt8) -> Void
    var onResize: (Double) -> Void
    // Duplicate (alt-drag)
    var onDuplicate: (() -> UUID?)?
    var onDuplicateMove: ((UUID, Double, UInt8) -> Void)?
    var onCancelDuplicate: ((UUID) -> Void)?
    // Multi-select group
    var onGroupDragChanged: ((CGSize) -> Void)?
    var onGroupMoveEnded: ((Double, Int) -> Void)?
}

// MARK: - Note Rectangle View

struct NoteRectView: View, Equatable {
    let note: SequencerNote
    let isSelected: Bool
    let isInMultiSelect: Bool
    let groupDragOffset: CGSize
    var actions: NoteActions
    
    nonisolated static func == (lhs: NoteRectView, rhs: NoteRectView) -> Bool {
        lhs.note == rhs.note &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isInMultiSelect == rhs.isInMultiSelect &&
        lhs.groupDragOffset == rhs.groupDragOffset
    }
    
    // Visual-only offsets (no model mutation during drag = no flicker)
    @State private var dragOffset = CGSize.zero
    @State private var resizeOffset: CGFloat = 0
    @State private var hasFiredDragStart = false
    @State private var didDuplicate = false
    @State private var duplicatedNoteId: UUID?
    
    /// Effective visual offset: group offset for multi-select, own offset otherwise
    private var effectiveOffset: CGSize {
        if isInMultiSelect { return groupDragOffset }
        return dragOffset
    }
    
    private var isDragging: Bool { effectiveOffset != .zero }
    private var isResizing: Bool { resizeOffset != 0 }
    
    private var noteColor: Color {
        return Theme.noteColor(pitch: note.pitch)
    }
    
    private var x: CGFloat { PianoRollLayout.xForBeat(note.startBeat) }
    private var y: CGFloat { PianoRollLayout.yForPitch(note.pitch) }
    private var noteWidth: CGFloat { CGFloat(note.duration) * PianoRollLayout.beatWidth }
    private var noteHeight: CGFloat { PianoRollLayout.rowHeight }
    
    // Visual width includes resize offset, inset 0.5px each side
    private var visualWidth: CGFloat { max(noteWidth + resizeOffset - 1, 6) }
    
    var body: some View {
        noteBody
            .frame(width: visualWidth, height: noteHeight - 2)
            .offset(
                x: x + 0.5 + effectiveOffset.width,
                y: y + 1 + effectiveOffset.height
            )
            .zIndex(isSelected ? 10 : (isDragging ? 5 : 1))
    }
    
    private var noteBody: some View {
        ZStack(alignment: .trailing) {
            // Main note rectangle
            RoundedRectangle(cornerRadius: 3)
                .fill(noteColor.opacity(isDragging ? 0.6 : 1))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            (isSelected || isInMultiSelect)
                                ? Theme.accent
                                : (PitchConstants.isBlackKey(note.pitch) ? noteColor.opacity(0.5) : Theme.dark.opacity(0.15)),
                            lineWidth: (isSelected || isInMultiSelect) ? 2 : 0.5
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
        .onHover { hovering in
            if hovering {
                NSCursor.openHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(moveGesture)
    }
    
    // MARK: - Label
    
    @ViewBuilder
    private var noteLabel: some View {
        if visualWidth > 28 {
            let c = Consonant.all.first { $0.ccValue == note.consonant }
            let v = Vowel.all.first { $0.ccValue == note.vowel }
            let isRandomCons = (c?.name == "Random")
            let isNoneCons = (c?.name == "None")
            let isRandomVowel = (v?.ccValue == 0)
            
            HStack(spacing: 1) {
                if isRandomCons && isRandomVowel {
                    // Both random → just show "Random"
                    Text("Random")
                } else if isRandomCons {
                    // Random cons + specific vowel → shuffle + vowel
                    Image(systemName: "shuffle")
                    Text(v?.symbol ?? "")
                } else if isRandomVowel {
                    // Specific cons + random vowel → cons + shuffle
                    if !isNoneCons { Text(c?.name ?? "") }
                    Image(systemName: "shuffle")
                } else {
                    // Specific cons + specific vowel
                    if !isNoneCons { Text(c?.name ?? "") }
                    Text(v?.symbol ?? "")
                }
            }
            .font(Theme.labelSmall)
            .foregroundColor(Theme.noteLabelColor(pitch: note.pitch))
            .lineLimit(1)
            .padding(.leading, 3)
        }
    }
    
    // MARK: - Move Gesture
    
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("pianoGrid"))
            .onChanged { value in
                // Select on first touch (mousedown)
                if !hasFiredDragStart {
                    hasFiredDragStart = true
                    let isShift = NSEvent.modifierFlags.contains(.shift)
                    if isShift {
                        actions.onShiftSelect()
                    } else {
                        actions.onSelect()
                    }
                }
                
                let dist = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)
                guard dist > 4 else { return }
                
                if !isDragging { NSCursor.closedHand.push() }
                
                // Alt-drag: duplicate note on first real drag movement
                if !didDuplicate && NSEvent.modifierFlags.contains(.option) {
                    didDuplicate = true
                    duplicatedNoteId = actions.onDuplicate?()
                }
                
                // Use isInMultiSelect (updated by SwiftUI after selection change)
                if isInMultiSelect {
                    actions.onGroupDragChanged?(value.translation)
                } else {
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                NSCursor.pop()
                let dist = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)
                
                let beatDelta = PianoRollLayout.beatForX(value.translation.width)
                let pitchDelta = -Int(round(value.translation.height / PianoRollLayout.rowHeight))
                let landedOnOriginal = (beatDelta == 0 && pitchDelta == 0) || dist <= 4
                
                if let dupId = duplicatedNoteId {
                    if landedOnOriginal {
                        actions.onCancelDuplicate?(dupId)
                    } else {
                        let newBeat = max(0, note.startBeat + beatDelta)
                        let rawPitch = Int(note.pitch) + pitchDelta
                        let newPitch = PitchConstants.clampPitch(UInt8(clamping: max(0, rawPitch)))
                        actions.onDuplicateMove?(dupId, newBeat, newPitch)
                    }
                } else if dist > 4 {
                    if isInMultiSelect {
                        actions.onGroupMoveEnded?(beatDelta, pitchDelta)
                    } else {
                        let newBeat = max(0, note.startBeat + beatDelta)
                        let rawPitch = Int(note.pitch) + pitchDelta
                        let newPitch = PitchConstants.clampPitch(UInt8(clamping: max(0, rawPitch)))
                        actions.onMove(newBeat, newPitch)
                    }
                }
                
                dragOffset = .zero
                actions.onGroupDragChanged?(.zero)
                hasFiredDragStart = false
                didDuplicate = false
                duplicatedNoteId = nil
            }
    }
    
    // MARK: - Resize Gesture
    
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("pianoGrid"))
            .onChanged { value in
                resizeOffset = value.translation.width
            }
            .onEnded { value in
                let beatDelta = PianoRollLayout.beatForX(value.translation.width)
                let newDuration = max(GridConstants.minDuration, note.duration + beatDelta)
                resizeOffset = 0
                actions.onResize(newDuration)
            }
    }
}

