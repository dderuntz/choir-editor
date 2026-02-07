import Foundation
import SwiftUI

// MARK: - Data Model

struct SequencerNote: Identifiable, Equatable {
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
        return note
    }
    
    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedNoteId == id {
            selectedNoteId = nil
        }
    }
    
    func deleteSelectedNote() {
        guard let id = selectedNoteId else { return }
        deleteNote(id: id)
    }
    
    func moveNote(id: UUID, toBeat beat: Double, pitch: UInt8) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].startBeat = snap(beat)
        notes[index].pitch = PitchConstants.clampPitch(pitch)
    }
    
    func resizeNote(id: UUID, duration: Double) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].duration = max(snap(duration), GridConstants.minDuration)
    }
    
    func updateNote(id: UUID, _ transform: (inout SequencerNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        transform(&notes[index])
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
}
