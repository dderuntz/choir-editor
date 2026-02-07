import SwiftUI

struct SequencerView: View {
    var midiService: MidiService
    @EnvironmentObject var model: SequencerModel
    @State private var previewingNotePitch: UInt8? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            sequencerToolbar
            
            Divider()
            
            // Piano Roll
            PianoRollView(
                model: model,
                onNotePreview: { note in
                    previewNote(note)
                },
                onNotePitchChange: { oldPitch, newPitch in
                    handlePitchChange(oldPitch: oldPitch, newPitch: newPitch)
                },
                onNotePreviewStop: { pitch in
                    stopPreview(pitch: pitch)
                }
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
    
    // MARK: - MIDI Preview
    
    private func previewNote(_ note: SequencerNote) {
        // Stop any currently previewing note
        if let currentPitch = previewingNotePitch {
            midiService.sendNoteOff(note: currentPitch)
        }
        
        // Set CC values for this note
        midiService.consonant = note.consonant
        midiService.vowel = note.vowel
        midiService.vibrato = note.vibrato
        midiService.reverb = note.reverb
        
        // Send NoteOn
        midiService.sendNoteOn(note: note.pitch, velocity: note.velocity)
        previewingNotePitch = note.pitch
        
        // Auto-stop after a short preview (~400ms)
        let pitch = note.pitch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if previewingNotePitch == pitch {
                midiService.sendNoteOff(note: pitch)
                previewingNotePitch = nil
            }
        }
    }
    
    private func handlePitchChange(oldPitch: UInt8, newPitch: UInt8) {
        // NoteOff old, NoteOn new (same CC values)
        midiService.sendNoteOff(note: oldPitch)
        midiService.sendNoteOn(note: newPitch, velocity: model.selectedNote?.velocity ?? 100)
        previewingNotePitch = newPitch
    }
    
    private func stopPreview(pitch: UInt8) {
        midiService.sendNoteOff(note: pitch)
        if previewingNotePitch == pitch {
            previewingNotePitch = nil
        }
    }
    
    private func playNoteForDuration(_ note: SequencerNote) {
        // Stop any current preview
        if let currentPitch = previewingNotePitch {
            midiService.sendNoteOff(note: currentPitch)
        }
        
        // Set CC values
        midiService.consonant = note.consonant
        midiService.vowel = note.vowel
        midiService.vibrato = note.vibrato
        midiService.reverb = note.reverb
        
        // Play for the note's full duration (convert beats to seconds using tempo)
        let beatsPerSecond = model.tempo / 60.0
        let durationSeconds = note.duration / beatsPerSecond
        
        midiService.sendNoteOn(note: note.pitch, velocity: note.velocity)
        previewingNotePitch = note.pitch
        
        let pitch = note.pitch
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) {
            midiService.sendNoteOff(note: pitch)
            if previewingNotePitch == pitch {
                previewingNotePitch = nil
            }
        }
    }
    
    private func clearAll() {
        // Stop any preview
        if let pitch = previewingNotePitch {
            midiService.sendNoteOff(note: pitch)
            previewingNotePitch = nil
        }
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
}
