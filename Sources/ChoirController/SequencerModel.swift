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

// MARK: - Sequencer Model

@MainActor
class SequencerModel: ObservableObject {
    
    @Published var notes: [SequencerNote] = []
    @Published var selectedNoteId: UUID? = nil
    @Published var totalBeats: Int = 16
    @Published var tempo: Double = 100
    
    // Playback state
    @Published var playheadBeat: Double = 0
    @Published var isPlaying: Bool = false
    /// IDs of notes currently sounding via playback/scrub
    var activeNoteIDs: Set<UUID> = []
    
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
    
    // MARK: - CRUD
    
    @discardableResult
    func addNote(atBeat beat: Double, pitch: UInt8, duration: Double = 1.0) -> SequencerNote {
        let snappedBeat = snap(beat)
        let clampedPitch = PitchConstants.clampPitch(pitch)
        let note = SequencerNote(
            pitch: clampedPitch,
            startBeat: snappedBeat,
            duration: max(duration, GridConstants.minDuration)
        )
        notes.append(note)
        selectedNoteId = note.id
        markDirty()
        return note
    }
    
    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedNoteId == id {
            selectedNoteId = nil
        }
        markDirty()
    }
    
    func deleteSelectedNote() {
        guard let id = selectedNoteId else { return }
        deleteNote(id: id)
    }
    
    func moveNote(id: UUID, toBeat beat: Double, pitch: UInt8) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].startBeat = snap(beat)
        notes[index].pitch = PitchConstants.clampPitch(pitch)
        markDirty()
    }
    
    func resizeNote(id: UUID, duration: Double) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].duration = max(snap(duration), GridConstants.minDuration)
        markDirty()
    }
    
    func updateNote(id: UUID, _ transform: (inout SequencerNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        transform(&notes[index])
        markDirty()
    }
    
    // MARK: - Helpers
    
    func snap(_ value: Double) -> Double {
        (value / GridConstants.snapResolution).rounded() * GridConstants.snapResolution
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
        selectedNoteId = nil
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
        print("Saved \(notes.count) notes to \(url.lastPathComponent)")
    }
    
    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let doc = try decoder.decode(ChoirDocument.self, from: data)
        notes = doc.notes
        totalBeats = doc.totalBeats
        tempo = doc.tempo
        selectedNoteId = nil
        currentFileURL = url
        hasUnsavedChanges = false
        print("Loaded \(notes.count) notes from \(url.lastPathComponent)")
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
    }
}
