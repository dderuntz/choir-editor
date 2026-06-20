import Foundation
import SwiftUI
import AppKit
import Combine
import os

private let log = Logger(subsystem: "com.choir-arranger", category: "model")

// MARK: - Data Model

struct SequencerNote: Identifiable, Equatable, Codable {
    var id = UUID()
    var pitch: UInt8          // MIDI note 40-81
    var startBeat: Double     // Position in beats
    var duration: Double      // Length in beats (min 0.25 for 16th)
    var velocity: UInt8 = 100
    var consonant: UInt8 = 127  // CC2 (user-requested default)
    var vowel: UInt8 = 0        // CC3 (Random default)
    var vibrato: UInt8 = 64     // CC1
    var reverb: UInt8 = 32      // CC4
    
    /// Dummy note used when inspector is visible but no note is selected
    static let placeholder = SequencerNote(pitch: 60, startBeat: 0, duration: 1)
}

// MARK: - Choir Document (file format)

struct ChoirDocument: Codable {
    var version: Int = 1
    var tempo: Double = 100
    var totalBeats: Int = 16
    var notes: [SequencerNote] = []
    var scaleEnabled: Bool?
    var scaleKey: Int?
    var scaleType: String?
    var isLooping: Bool?
}

// MARK: - Pitch Constants (non-actor-isolated for use in layout/shapes)

enum PitchConstants {
    static let minPitch: UInt8 = 40  // E2
    static let maxPitch: UInt8 = 81  // A5
    static let pitchCount: Int = Int(maxPitch - minPitch) + 1  // 42 rows
    
    static func clampPitch(_ pitch: UInt8) -> UInt8 {
        min(max(pitch, minPitch), maxPitch)
    }
    
    static func noteName(for pitch: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (Int(pitch) / 12) - 1
        let name = names[Int(pitch) % 12]
        return "\(name)\(octave)"
    }
    
    static func isBlackKey(_ pitch: UInt8) -> Bool {
        let pc = Int(pitch) % 12
        return [1, 3, 6, 8, 10].contains(pc)
    }
}

// MARK: - Grid Constants (non-actor-isolated)

enum GridConstants {
    static let subdivisions: Int = 4  // 16th notes per beat
    static let snapResolution: Double = 0.25  // 1/16th beat
    static let minDuration: Double = 0.25
}

// MARK: - Scale Helper

enum ScaleType: String, CaseIterable, Identifiable {
    case major = "Major"
    case minor = "Minor"
    case harmonicMinor = "Harmonic Minor"
    case dorian = "Dorian"
    case mixolydian = "Mixolydian"
    case pentatonicMajor = "Pentatonic Maj"
    case pentatonicMinor = "Pentatonic Min"
    case chromatic = "Chromatic"
    
    var id: String { rawValue }
    
    /// Semitone intervals in the scale (relative to root)
    var intervals: Set<Int> {
        switch self {
        case .major:           return [0, 2, 4, 5, 7, 9, 11]
        case .minor:           return [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor:   return [0, 2, 3, 5, 7, 8, 11]
        case .dorian:          return [0, 2, 3, 5, 7, 9, 10]
        case .mixolydian:      return [0, 2, 4, 5, 7, 9, 10]
        case .pentatonicMajor: return [0, 2, 4, 7, 9]
        case .pentatonicMinor: return [0, 3, 5, 7, 10]
        case .chromatic:       return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
        }
    }
}

enum MusicalKey: Int, CaseIterable, Identifiable {
    case C = 0, Cs = 1, D = 2, Ds = 3, E = 4, F = 5
    case Fs = 6, G = 7, Gs = 8, A = 9, As = 10, B = 11
    
    var id: Int { rawValue }
    
    var name: String {
        switch self {
        case .C: return "C"
        case .Cs: return "C#"
        case .D: return "D"
        case .Ds: return "D#"
        case .E: return "E"
        case .F: return "F"
        case .Fs: return "F#"
        case .G: return "G"
        case .Gs: return "G#"
        case .A: return "A"
        case .As: return "A#"
        case .B: return "B"
        }
    }
}

// MARK: - Sequencer Model

@MainActor
class SequencerModel: ObservableObject {
    private enum XYExportError: LocalizedError {
        case emptyArrangement
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyArrangement:
                return "No notes to export."
            case .exportFailed(let message):
                return "OP-XY export failed: \(message)"
            }
        }
    }
    
    @Published var notes: [SequencerNote] = []
    @Published var selectedNoteId: UUID? = nil
    @Published var selectedNoteIds: Set<UUID> = []
    @Published var totalBeats: Int = 16
    @Published var tempo: Double = 100
    
    // Playback state
    @Published var playheadBeat: Double = 0
    @Published var isPlaying: Bool = false
    @Published var isLooping: Bool = false
    /// Incremented to signal play/stop toggle from menu bar
    @Published var togglePlaybackTrigger: Int = 0
    /// IDs of notes currently sounding via playback/scrub
    var activeNoteIDs: Set<UUID> = []
    
    // Keyboard highlight (set when a bottom keyboard key is pressed)
    @Published var highlightedPitch: UInt8? = nil
    
    // Scale helper
    @Published var showScaleHelper: Bool = false
    @Published var musicalKey: MusicalKey = .C
    @Published var scaleType: ScaleType = .pentatonicMajor
    
    func isInScale(_ pitch: UInt8) -> Bool {
        let interval = (Int(pitch) - musicalKey.rawValue + 120) % 12  // +120 to keep positive
        return scaleType.intervals.contains(interval)
    }
    
    // Undo
    let undoManager = UndoManager()
    
    // File state
    @Published var currentFileURL: URL? = nil
    @Published var hasUnsavedChanges: Bool = false
    
    var documentName: String {
        currentFileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }
    
    // Computed
    var selectedNote: SequencerNote? {
        guard let id = selectedNoteId else { return nil }
        return notes.first { $0.id == id }
    }
    
    // MARK: - Selection
    
    /// Single select (click without shift)
    func selectNote(_ id: UUID) {
        selectedNoteId = id
        selectedNoteIds = [id]
    }
    
    /// Toggle note in multi-select (shift-click)
    func toggleNoteInSelection(_ id: UUID) {
        if selectedNoteIds.contains(id) {
            selectedNoteIds.remove(id)
            // Update primary to another selected note, or nil
            selectedNoteId = selectedNoteIds.first
        } else {
            selectedNoteIds.insert(id)
            selectedNoteId = id
        }
    }
    
    /// Move all selected notes by a delta
    func moveSelectedNotes(beatDelta: Double, pitchDelta: Int) {
        withUndo("Move Notes") {
            for id in selectedNoteIds {
                guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
                let newBeat = max(0, notes[index].startBeat + beatDelta)
                notes[index].startBeat = snap(newBeat)
                let rawPitch = Int(notes[index].pitch) + pitchDelta
                notes[index].pitch = PitchConstants.clampPitch(UInt8(clamping: max(0, rawPitch)))
            }
            for id in selectedNoteIds {
                guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
                inheritPhoneme(into: &notes[index])
            }
            // Remove any non-selected notes fully covered by moved notes
            let movedNotes = notes.filter { selectedNoteIds.contains($0.id) }
            for mover in movedNotes {
                removeCoveredNotes(by: mover)
            }
            markDirty()
        }
    }
    
    /// Replace the entire selection with a set of note IDs (marquee select)
    func selectNotes(_ ids: Set<UUID>) {
        selectedNoteIds = ids
        selectedNoteId = ids.first
    }
    
    func clearSelection() {
        selectedNoteId = nil
        selectedNoteIds.removeAll()
    }
    
    // MARK: - CRUD
    
    @discardableResult
    func addNote(atBeat beat: Double, pitch: UInt8, duration: Double = 1.0) -> SequencerNote {
        let snappedBeat = snap(beat)
        let clampedPitch = PitchConstants.clampPitch(pitch)
        var note = SequencerNote(
            pitch: clampedPitch,
            startBeat: snappedBeat,
            duration: max(duration, GridConstants.minDuration)
        )
        inheritPhoneme(into: &note)
        withUndo("Add Note") {
            notes.append(note)
            selectNote(note.id)
            markDirty()
        }
        return note
    }
    
    /// Duplicate a note in place and select the copy (for alt-drag)
    @discardableResult
    func duplicateNote(id: UUID) -> SequencerNote? {
        guard let original = notes.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID()
        withUndo("Duplicate Note") {
            notes.append(copy)
            selectNote(copy.id)
            markDirty()
        }
        return copy
    }
    
    func deleteNote(id: UUID) {
        withUndo("Delete Note") {
            notes.removeAll { $0.id == id }
            selectedNoteIds.remove(id)
            if selectedNoteId == id {
                selectedNoteId = selectedNoteIds.first
            }
            markDirty()
        }
    }
    
    /// Set to true to trigger a confirmation alert before deleting multiple notes
    @Published var pendingDeleteConfirm = false
    
    /// Request deletion — confirms first if multiple notes are selected
    func deleteSelectedNote() {
        guard !selectedNoteIds.isEmpty else { return }
        if selectedNoteIds.count > 1 {
            pendingDeleteConfirm = true
        } else {
            confirmDeleteSelected()
        }
    }
    
    /// Actually delete the selected notes (call after confirmation)
    func confirmDeleteSelected() {
        guard !selectedNoteIds.isEmpty else { return }
        withUndo("Delete Notes") {
            for id in selectedNoteIds {
                notes.removeAll { $0.id == id }
            }
            clearSelection()
            markDirty()
        }
    }
    
    func moveNote(id: UUID, toBeat beat: Double, pitch: UInt8) {
        guard notes.firstIndex(where: { $0.id == id }) != nil else { return }
        withUndo("Move Note") {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].startBeat = snap(beat)
            notes[index].pitch = PitchConstants.clampPitch(pitch)
            inheritPhoneme(into: &notes[index])
            removeCoveredNotes(by: notes[index])
            markDirty()
        }
    }
    
    func resizeNote(id: UUID, duration: Double) {
        guard notes.firstIndex(where: { $0.id == id }) != nil else { return }
        withUndo("Resize Note") {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            notes[index].duration = max(snap(duration), GridConstants.minDuration)
            markDirty()
        }
    }
    
    /// Remove notes that are fully covered (same pitch, start-to-end) by the given note
    private func removeCoveredNotes(by cover: SequencerNote) {
        let coverEnd = cover.startBeat + cover.duration
        notes.removeAll { other in
            guard other.id != cover.id, other.pitch == cover.pitch else { return false }
            let otherEnd = other.startBeat + other.duration
            return other.startBeat >= cover.startBeat && otherEnd <= coverEnd
        }
    }
    
    func updateNote(id: UUID, _ transform: (inout SequencerNote) -> Void) {
        guard notes.firstIndex(where: { $0.id == id }) != nil else { return }
        withUndo("Edit Note") {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
            let oldConsonant = notes[index].consonant
            let oldVowel = notes[index].vowel
            transform(&notes[index])
            let note = notes[index]
            if note.consonant != oldConsonant || note.vowel != oldVowel {
                propagatePhoneme(from: note)
            }
            markDirty()
        }
    }
    
    // MARK: - Helpers
    
    func snap(_ value: Double) -> Double {
        (value / GridConstants.snapResolution).rounded() * GridConstants.snapResolution
    }
    
    /// Inherit consonant/vowel from an existing note at the same start beat (Choir constraint)
    private func inheritPhoneme(into note: inout SequencerNote) {
        if let sibling = notes.first(where: { $0.id != note.id && $0.startBeat == note.startBeat }) {
            note.consonant = sibling.consonant
            note.vowel = sibling.vowel
        }
    }
    
    /// Propagate consonant/vowel from a note to all other notes at the same start beat
    private func propagatePhoneme(from source: SequencerNote) {
        for i in notes.indices {
            if notes[i].id != source.id && notes[i].startBeat == source.startBeat {
                notes[i].consonant = source.consonant
                notes[i].vowel = source.vowel
            }
        }
    }
    
    /// Check if clicking at a beat/pitch hits an existing note
    func noteAt(beat: Double, pitch: UInt8) -> SequencerNote? {
        notes.first { note in
            note.pitch == pitch &&
            beat >= note.startBeat &&
            beat < note.startBeat + note.duration
        }
    }
    
    // MARK: - File Operations
    
    func newDocument() {
        notes.removeAll()
        clearSelection()
        totalBeats = 16
        tempo = 100
        currentFileURL = nil
        hasUnsavedChanges = false
    }
    
    // MARK: - MIDI Export
    
    /// Export the arrangement as a Standard MIDI File (Type 0, single track).
    /// Includes CC events for vibrato (CC1), consonant (CC2), vowel (CC3), and reverb (CC4).
    func exportMIDI(to url: URL) throws {
        let ticksPerBeat: UInt16 = 480
        var events: [(tick: UInt32, bytes: [UInt8])] = []
        
        // Tempo meta event: FF 51 03 tt tt tt (microseconds per beat)
        let uspb = UInt32(60_000_000.0 / tempo)
        events.append((tick: 0, bytes: [0xFF, 0x51, 0x03,
                                         UInt8((uspb >> 16) & 0xFF),
                                         UInt8((uspb >> 8) & 0xFF),
                                         UInt8(uspb & 0xFF)]))
        
        let channel: UInt8 = 0
        for note in notes {
            let onTick = UInt32(note.startBeat * Double(ticksPerBeat))
            let offTick = onTick + UInt32(note.duration * Double(ticksPerBeat))
            
            // CC events just before note-on (same tick)
            events.append((tick: onTick, bytes: [0xB0 | channel, 1, note.vibrato]))   // CC1 vibrato
            events.append((tick: onTick, bytes: [0xB0 | channel, 2, note.consonant]))  // CC2 consonant
            events.append((tick: onTick, bytes: [0xB0 | channel, 3, note.vowel]))      // CC3 vowel
            events.append((tick: onTick, bytes: [0xB0 | channel, 4, note.reverb]))     // CC4 reverb
            
            // Note On
            events.append((tick: onTick, bytes: [0x90 | channel, note.pitch, note.velocity]))
            // Note Off
            events.append((tick: offTick, bytes: [0x80 | channel, note.pitch, 0]))
        }
        
        // End of track
        let lastTick = events.map(\.tick).max() ?? 0
        events.append((tick: lastTick, bytes: [0xFF, 0x2F, 0x00]))
        
        // Sort by tick (stable sort keeps CC before note-on, note-off after note-on at same tick)
        events.sort { $0.tick < $1.tick }
        
        // Build track data with delta times
        var trackData = Data()
        var prevTick: UInt32 = 0
        for event in events {
            let delta = event.tick - prevTick
            prevTick = event.tick
            trackData.append(contentsOf: Self.variableLengthQuantity(delta))
            trackData.append(contentsOf: event.bytes)
        }
        
        // Assemble file: header chunk + track chunk
        var midi = Data()
        
        // MThd
        midi.append(contentsOf: [0x4D, 0x54, 0x68, 0x64]) // "MThd"
        midi.append(contentsOf: Self.uint32BE(6))            // header length
        midi.append(contentsOf: Self.uint16BE(0))            // format 0
        midi.append(contentsOf: Self.uint16BE(1))            // 1 track
        midi.append(contentsOf: Self.uint16BE(ticksPerBeat)) // ticks per beat
        
        // MTrk
        midi.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B]) // "MTrk"
        midi.append(contentsOf: Self.uint32BE(UInt32(trackData.count)))
        midi.append(trackData)
        
        try midi.write(to: url, options: .atomic)
        log.info("Exported \(self.notes.count) notes as MIDI to \(url.lastPathComponent)")
    }
    
    private static func variableLengthQuantity(_ value: UInt32) -> [UInt8] {
        if value == 0 { return [0x00] }
        var v = value
        var bytes: [UInt8] = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            bytes.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        return bytes
    }
    
    private static func uint32BE(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
         UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
    
    private static func uint16BE(_ value: UInt16) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    // MARK: - OP-XY Export

    /// Export the arrangement as an OP-XY project file.
    ///
    /// Current scope:
    /// - Builds from an internal minimal OP-XY project seed and re-encodes canonical RLE.
    /// - Writes notes and CC locks to Track 11 (MIDI track).
    /// - Applies tempo and OP-XY shuffle default.
    /// - `CHOIR_XY_TEMPLATE` can override the seed for local format research.
    func exportXY(to url: URL) throws {
        guard !notes.isEmpty else {
            throw XYExportError.emptyArrangement
        }

        let templateData: [UInt8]
        do {
            if let env = ProcessInfo.processInfo.environment["CHOIR_XY_TEMPLATE"], !env.isEmpty {
                templateData = [UInt8](try Data(contentsOf: URL(fileURLWithPath: env)))
            } else {
                templateData = try XYProjectSeed.data()
            }
        } catch {
            throw XYExportError.exportFailed(error.localizedDescription)
        }

        let sortedNotes = notes
            .sorted { ($0.startBeat, $0.pitch, $0.id.uuidString) < ($1.startBeat, $1.pitch, $1.id.uuidString) }

        typealias StepLockAccumulator = (cc1: Int?, cc2: Int?, cc3: Int?, cc4: Int?)
        typealias CCState = (cc1: Int, cc2: Int, cc3: Int, cc4: Int)
        var lockByStep: [Int: StepLockAccumulator] = [:]

        func mergeLockLane(
            current: Int?,
            incoming: Int,
            step: Int,
            laneName: String
        ) throws -> Int? {
            if let current, current != incoming {
                throw XYExportError.exportFailed(
                    "conflicting \(laneName) lock values on step \(step) are not yet supported"
                )
            }
            return incoming
        }
        func mergeLock(
            step: Int,
            cc1: Int? = nil,
            cc2: Int? = nil,
            cc3: Int? = nil,
            cc4: Int? = nil
        ) throws {
            var lock = lockByStep[step] ?? (nil, nil, nil, nil)
            if let cc1 {
                lock.cc1 = try mergeLockLane(current: lock.cc1, incoming: cc1, step: step, laneName: "CC1")
            }
            if let cc2 {
                lock.cc2 = try mergeLockLane(current: lock.cc2, incoming: cc2, step: step, laneName: "CC2")
            }
            if let cc3 {
                lock.cc3 = try mergeLockLane(current: lock.cc3, incoming: cc3, step: step, laneName: "CC3")
            }
            if let cc4 {
                lock.cc4 = try mergeLockLane(current: lock.cc4, incoming: cc4, step: step, laneName: "CC4")
            }
            lockByStep[step] = lock
        }
        func changedLockValues(from current: CCState, to next: CCState) -> StepLockAccumulator {
            (
                cc1: next.cc1 == current.cc1 ? nil : next.cc1,
                cc2: next.cc2 == current.cc2 ? nil : next.cc2,
                cc3: next.cc3 == current.cc3 ? nil : next.cc3,
                cc4: next.cc4 == current.cc4 ? nil : next.cc4
            )
        }
        func noteOnLockValues(from changed: StepLockAccumulator, to next: CCState) -> StepLockAccumulator {
            (
                cc1: next.cc1 != 64 || changed.cc1 != nil ? next.cc1 : nil,
                cc2: next.cc2 != 127 || changed.cc2 != nil ? next.cc2 : nil,
                cc3: next.cc3 != 0 || changed.cc3 != nil ? next.cc3 : nil,
                cc4: next.cc4 != 32 || changed.cc4 != nil ? next.cc4 : nil
            )
        }
        func hasLockValue(_ lock: StepLockAccumulator) -> Bool {
            lock.cc1 != nil || lock.cc2 != nil || lock.cc3 != nil || lock.cc4 != nil
        }
        func ccState(for notes: [SequencerNote], step: Int) throws -> CCState {
            guard let first = notes.first else {
                return (64, 127, 0, 32)
            }
            for note in notes.dropFirst() {
                if note.vibrato != first.vibrato {
                    throw XYExportError.exportFailed("conflicting CC1 lock values on step \(step) are not yet supported")
                }
                if note.consonant != first.consonant {
                    throw XYExportError.exportFailed("conflicting CC2 lock values on step \(step) are not yet supported")
                }
                if note.vowel != first.vowel {
                    throw XYExportError.exportFailed("conflicting CC3 lock values on step \(step) are not yet supported")
                }
                if note.reverb != first.reverb {
                    throw XYExportError.exportFailed("conflicting CC4 lock values on step \(step) are not yet supported")
                }
            }
            return (
                Int(first.vibrato),
                Int(first.consonant),
                Int(first.vowel),
                Int(first.reverb)
            )
        }

        var noteStartSteps: Set<Int> = []
        let xyNotes = sortedNotes.map { note in
            let step = Int((note.startBeat * 4.0).rounded(.toNearestOrAwayFromZero)) + 1
            let gateTicks = max(0, Int((note.duration * 4.0 * 480.0).rounded(.toNearestOrAwayFromZero)))
            noteStartSteps.insert(step)

            return XYExportNoteData(
                step: step,
                note: Int(note.pitch),
                velocity: Int(note.velocity),
                gateTicks: gateTicks,
                tickOffset: 0
            )
        }

        let notesByStep = Dictionary(grouping: sortedNotes) {
            Int(($0.startBeat * 4.0).rounded(.toNearestOrAwayFromZero)) + 1
        }
        let ccPreSendEnabled = (UserDefaults.standard.object(forKey: "ccPreSendEnabled") as? Bool) ?? true
        let ccPreSendDelayMs = UserDefaults.standard.object(forKey: "ccPreSendDelayMs") as? Double ?? 185
        let beatsPerSecond = tempo / 60.0
        var currentCC: CCState = (64, 127, 0, 32)
        var previousStep: Int?
        var previousBeat: Double?

        for step in notesByStep.keys.sorted() {
            let stepNotes = notesByStep[step] ?? []
            let nextCC = try ccState(for: stepNotes, step: step)
            let changed = changedLockValues(from: currentCC, to: nextCC)
            let noteOnLock = noteOnLockValues(from: changed, to: nextCC)

            if hasLockValue(changed) {
                if ccPreSendEnabled,
                   let previousStep,
                   let previousBeat,
                   previousStep + 1 < step {
                    let targetBeat = stepNotes.map(\.startBeat).min() ?? Double(step - 1) / 4.0
                    let timeToNextNoteOn = max(0.0, (targetBeat - previousBeat) / beatsPerSecond)
                    let requestedDelay = ccPreSendDelayMs / 1000.0
                    let delaySeconds = min(requestedDelay, max(0.001, timeToNextNoteOn / 2.0))
                    let preSendBeat = previousBeat + delaySeconds * beatsPerSecond
                    let preferredStep = max(previousStep + 1, Int((preSendBeat * 4.0).rounded(.down)) + 1)
                    if let preSendStep = (preferredStep..<step).first(where: { !noteStartSteps.contains($0) }) {
                        try mergeLock(
                            step: preSendStep,
                            cc1: changed.cc1,
                            cc2: changed.cc2,
                            cc3: changed.cc3,
                            cc4: changed.cc4
                        )
                    }
                }
            }

            if hasLockValue(noteOnLock) {
                try mergeLock(
                    step: step,
                    cc1: noteOnLock.cc1,
                    cc2: noteOnLock.cc2,
                    cc3: noteOnLock.cc3,
                    cc4: noteOnLock.cc4
                )
            }

            currentCC = nextCC
            previousStep = step
            previousBeat = stepNotes.map(\.startBeat).min() ?? Double(step - 1) / 4.0
        }

        let xyStepLocks = lockByStep
            .keys
            .sorted()
            .compactMap { step -> XYExportStepLockData? in
                guard let lock = lockByStep[step] else { return nil }
                guard lock.cc1 != nil || lock.cc2 != nil || lock.cc3 != nil || lock.cc4 != nil else {
                    return nil
                }
                return XYExportStepLockData(
                    step: step,
                    cc1: lock.cc1,
                    cc2: lock.cc2,
                    cc3: lock.cc3,
                    cc4: lock.cc4
                )
            }

        do {
            try XYExporter.export(
                templateData: templateData,
                outputURL: url,
                trackIndex: 11,
                notes: xyNotes,
                stepLocks: xyStepLocks,
                tempoTenths: Int((tempo * 10.0).rounded(.toNearestOrAwayFromZero)),
                grooveType: 0 // OP-XY shuffle default
            )
        } catch let error as XYExporterError {
            throw XYExportError.exportFailed(error.localizedDescription)
        } catch {
            throw XYExportError.exportFailed(error.localizedDescription)
        }

        log.info("Exported \(self.notes.count) notes as OP-XY to \(url.lastPathComponent)")
    }
    
    // MARK: - Save / Load
    
    func save(to url: URL) throws {
        let doc = ChoirDocument(
            version: 1,
            tempo: tempo,
            totalBeats: totalBeats,
            notes: notes,
            scaleEnabled: showScaleHelper,
            scaleKey: musicalKey.rawValue,
            scaleType: scaleType.rawValue,
            isLooping: isLooping
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(doc)
        try data.write(to: url, options: .atomic)
        currentFileURL = url
        hasUnsavedChanges = false
        Self.addToRecentFiles(url)
        log.info("Saved \(self.notes.count) notes to \(url.lastPathComponent)")
    }
    
    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let doc = try decoder.decode(ChoirDocument.self, from: data)
        notes = doc.notes
        totalBeats = doc.totalBeats
        tempo = doc.tempo
        showScaleHelper = doc.scaleEnabled ?? false
        if let key = doc.scaleKey, let mk = MusicalKey(rawValue: key) { musicalKey = mk }
        if let st = doc.scaleType, let s = ScaleType(rawValue: st) { scaleType = s }
        isLooping = doc.isLooping ?? false
        clearSelection()
        currentFileURL = url
        hasUnsavedChanges = false
        Self.addToRecentFiles(url)
        log.info("Loaded \(self.notes.count) notes from \(url.lastPathComponent)")
    }
    
    /// Rename the current file on disk and update references
    func renameFile(to newName: String) throws {
        guard let currentURL = currentFileURL else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newURL = currentURL.deletingLastPathComponent()
            .appendingPathComponent(trimmed)
            .appendingPathExtension("choir")
        guard newURL != currentURL else { return } // no change
        try FileManager.default.moveItem(at: currentURL, to: newURL)
        currentFileURL = newURL
        hasUnsavedChanges = false
        Self.addToRecentFiles(newURL)
        log.info("Renamed to \(newURL.lastPathComponent)")
    }
    
    /// Load the bundled demo file (Robots.choir) from Documents
    func loadDemoFile() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let demoURL = documentsURL?.appendingPathComponent("Robots.choir"),
              FileManager.default.fileExists(atPath: demoURL.path) else {
            log.warning("Demo file not found in Documents")
            return
        }
        do {
            try load(from: demoURL)
            log.info("Loaded demo file")
        } catch {
            log.error("Failed to load demo file: \(error)")
        }
    }

    /// Auto-open the last file on launch
    func loadLastFileIfAvailable() {
        guard let path = UserDefaults.standard.string(forKey: "lastOpenedFile") else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try load(from: url)
            log.info("Auto-opened last file: \(url.lastPathComponent)")
        } catch {
            log.error("Failed to auto-open last file: \(error)")
        }
    }
    
    // MARK: - Recent Files
    
    static let maxRecentFiles = 10
    
    static func addToRecentFiles(_ url: URL) {
        var recents = recentFilePaths()
        recents.removeAll { $0 == url.path }
        recents.insert(url.path, at: 0)
        if recents.count > maxRecentFiles {
            recents = Array(recents.prefix(maxRecentFiles))
        }
        UserDefaults.standard.set(recents, forKey: "recentFiles")
        UserDefaults.standard.set(url.path, forKey: "lastOpenedFile")
    }
    
    static func recentFilePaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: "recentFiles") ?? []
    }
    
    static func recentFileURLs() -> [URL] {
        recentFilePaths()
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    
    static func clearRecentFiles() {
        UserDefaults.standard.removeObject(forKey: "recentFiles")
    }
    
    /// Save a snapshot of the current notes for undo, then call the mutation block.
    func withUndo(_ actionName: String = "Edit Notes", _ mutation: () -> Void) {
        let snapshot = notes
        let selId = selectedNoteId
        let selIds = selectedNoteIds
        undoManager.registerUndo(withTarget: self) { model in
            // Save current state for redo before restoring
            let redoSnapshot = model.notes
            let redoSelId = model.selectedNoteId
            let redoSelIds = model.selectedNoteIds
            model.undoManager.registerUndo(withTarget: model) { m in
                m.notes = redoSnapshot
                m.selectedNoteId = redoSelId
                m.selectedNoteIds = redoSelIds
                m.markDirty()
            }
            model.undoManager.setActionName(actionName)
            model.notes = snapshot
            model.selectedNoteId = selId
            model.selectedNoteIds = selIds
            model.markDirty()
        }
        undoManager.setActionName(actionName)
        mutation()
    }
    
    func markDirty() {
        hasUnsavedChanges = true
        scheduleAutoSave()
    }
    
    // MARK: - Auto Save
    
    private var autoSaveWork: DispatchWorkItem? = nil
    
    private func scheduleAutoSave() {
        autoSaveWork?.cancel()
        guard currentFileURL != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.autoSave()
        }
        autoSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
    
    private func autoSave() {
        guard let url = currentFileURL else { return }
        do {
            try save(to: url)
            log.debug("Auto-saved to \(url.lastPathComponent)")
        } catch {
            log.error("Auto-save failed: \(error)")
        }
    }
}
