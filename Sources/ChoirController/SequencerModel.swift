import Foundation
import SwiftUI
import AppKit

// MARK: - Data Model

struct SequencerNote: Identifiable, Equatable, Codable {
    var id = UUID()
    var pitch: UInt8          // MIDI note 40-81
    var startBeat: Double     // Position in beats
    var duration: Double      // Length in beats (min 0.25 for 16th)
    var velocity: UInt8 = 100
    var consonant: UInt8 = 125  // CC2 (None default)
    var vowel: UInt8 = 0        // CC3 (Random default)
    var vibrato: UInt8 = 64     // CC1
    var reverb: UInt8 = 32      // CC4
}

// MARK: - Choir Document (file format)

struct ChoirDocument: Codable {
    var version: Int = 1
    var tempo: Double = 100
    var totalBeats: Int = 16
    var notes: [SequencerNote] = []
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
    
    @Published var notes: [SequencerNote] = []
    @Published var selectedNoteId: UUID? = nil
    @Published var selectedNoteIds: Set<UUID> = []
    @Published var totalBeats: Int = 16
    @Published var tempo: Double = 100
    
    // Playback state
    @Published var playheadBeat: Double = 0
    @Published var isPlaying: Bool = false
    /// Incremented to signal play/stop toggle from menu bar
    @Published var togglePlaybackTrigger: Int = 0
    /// IDs of notes currently sounding via playback/scrub
    var activeNoteIDs: Set<UUID> = []
    
    // Keyboard highlight (set when a bottom keyboard key is pressed)
    @Published var highlightedPitch: UInt8? = nil
    
    // Scale helper
    @Published var showScaleHelper: Bool = false
    @Published var musicalKey: MusicalKey = .C
    @Published var scaleType: ScaleType = .major
    
    func isInScale(_ pitch: UInt8) -> Bool {
        let interval = (Int(pitch) - musicalKey.rawValue + 120) % 12  // +120 to keep positive
        return scaleType.intervals.contains(interval)
    }
    
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
        for id in selectedNoteIds {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
            let newBeat = max(0, notes[index].startBeat + beatDelta)
            notes[index].startBeat = snap(newBeat)
            let rawPitch = Int(notes[index].pitch) + pitchDelta
            notes[index].pitch = PitchConstants.clampPitch(UInt8(clamping: max(0, rawPitch)))
        }
        // Inherit phonemes at landing positions
        for id in selectedNoteIds {
            guard let index = notes.firstIndex(where: { $0.id == id }) else { continue }
            inheritPhoneme(into: &notes[index])
        }
        markDirty()
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
        // Inherit consonant/vowel from any existing note at the same beat
        inheritPhoneme(into: &note)
        notes.append(note)
        selectNote(note.id)
        markDirty()
        return note
    }
    
    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        selectedNoteIds.remove(id)
        if selectedNoteId == id {
            selectedNoteId = selectedNoteIds.first
        }
        markDirty()
    }
    
    func deleteSelectedNote() {
        guard !selectedNoteIds.isEmpty else { return }
        for id in selectedNoteIds {
            notes.removeAll { $0.id == id }
        }
        clearSelection()
        markDirty()
    }
    
    func moveNote(id: UUID, toBeat beat: Double, pitch: UInt8) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].startBeat = snap(beat)
        notes[index].pitch = PitchConstants.clampPitch(pitch)
        // Inherit consonant/vowel from notes already at the landing beat
        inheritPhoneme(into: &notes[index])
        markDirty()
    }
    
    func resizeNote(id: UUID, duration: Double) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].duration = max(snap(duration), GridConstants.minDuration)
        markDirty()
    }
    
    func updateNote(id: UUID, _ transform: (inout SequencerNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let oldConsonant = notes[index].consonant
        let oldVowel = notes[index].vowel
        transform(&notes[index])
        // If consonant or vowel changed, propagate to all notes at the same beat
        let note = notes[index]
        if note.consonant != oldConsonant || note.vowel != oldVowel {
            propagatePhoneme(from: note)
        }
        markDirty()
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
    
    func save(to url: URL) throws {
        let doc = ChoirDocument(
            version: 1,
            tempo: tempo,
            totalBeats: totalBeats,
            notes: notes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(doc)
        try data.write(to: url, options: .atomic)
        currentFileURL = url
        hasUnsavedChanges = false
        Self.addToRecentFiles(url)
        print("Saved \(notes.count) notes to \(url.lastPathComponent)")
    }
    
    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let doc = try decoder.decode(ChoirDocument.self, from: data)
        notes = doc.notes
        totalBeats = doc.totalBeats
        tempo = doc.tempo
        clearSelection()
        currentFileURL = url
        hasUnsavedChanges = false
        Self.addToRecentFiles(url)
        print("Loaded \(notes.count) notes from \(url.lastPathComponent)")
    }
    
    /// Auto-open the last file on launch
    func loadLastFileIfAvailable() {
        guard let path = UserDefaults.standard.string(forKey: "lastOpenedFile") else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try load(from: url)
            print("Auto-opened last file: \(url.lastPathComponent)")
        } catch {
            print("Failed to auto-open last file: \(error)")
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
    
    /// Save to current file, or show Save As if no file yet. Returns true if saved.
    @discardableResult
    func saveCurrentOrPrompt() -> Bool {
        if let url = currentFileURL {
            do {
                try save(to: url)
                return true
            } catch {
                print("Error saving: \(error)")
                return false
            }
        } else {
            return showSaveDialog()
        }
    }
    
    /// Show NSSavePanel and save. Returns true if saved.
    @discardableResult
    func showSaveDialog() -> Bool {
        let panel = NSSavePanel()
        panel.title = "Save Choir Sequence"
        panel.nameFieldStringValue = documentName == "Untitled" ? "Untitled.choir" : "\(documentName).choir"
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        // Force .choir extension
        panel.allowedContentTypes = [.init(filenameExtension: "choir") ?? .json]
        
        guard panel.runModal() == .OK, var url = panel.url else { return false }
        
        // Ensure .choir extension
        if url.pathExtension != "choir" {
            url = url.appendingPathExtension("choir")
        }
        
        do {
            try save(to: url)
            return true
        } catch {
            print("Error saving: \(error)")
            return false
        }
    }
    
    /// Show NSOpenPanel and load. Returns true if loaded.
    @discardableResult
    func showOpenDialog() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Open Choir Sequence"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "choir") ?? .json]
        
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        
        do {
            try load(from: url)
            return true
        } catch {
            print("Error loading: \(error)")
            return false
        }
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
            print("Auto-saved to \(url.lastPathComponent)")
        } catch {
            print("Auto-save failed: \(error)")
        }
    }
}
