import Foundation
import MIDIKit
import Combine
import os

private let log = Logger(subsystem: "com.choir-arranger", category: "midi")

@MainActor
class MidiService: ObservableObject {
    let midiManager = MIDIManager(
        clientName: "ChoirController",
        model: "ChoirControllerApp",
        manufacturer: "IDEO"
    )
    
    @Published var availableInputs: [MIDIInputEndpoint] = []
    @Published var selectedInput: MIDIInputEndpoint?
    
    // Track if we are connected
    @Published var isConnected: Bool = false
    
    // Voice parameters (CC values)
    @Published var vibrato: UInt8 = ChoirDefaults.vibrato
    @Published var reverb: UInt8 = ChoirDefaults.reverb
    @Published var consonant: UInt8 = ChoirDefaults.consonant
    @Published var vowel: UInt8 = ChoirDefaults.vowel
    
    // Global Sequencer Settings
    @Published var tempo: Double = 100
    @Published var minNoteDuration: Double = 0.28
    
    init() {}
    
    func start() {
        midiManager.notificationHandler = { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.updateEndpoints()
            }
        }
        
        do {
            try midiManager.start()
        } catch {
            log.error("Error starting MIDI Manager: \(error.localizedDescription)")
        }
        
        updateEndpoints()
    }
    
    func updateEndpoints() {
        // Get INPUT endpoints (destinations that receive MIDI, like the Choir)
        self.availableInputs = self.midiManager.endpoints.inputs
        
        log.debug("MIDI Input Endpoints Found: \(self.availableInputs.count)")
        for input in self.availableInputs {
            log.debug("   - Name: '\(input.name)', DisplayName: '\(input.displayName)', ID: \(input.uniqueID)")
        }
        
        // Check if our selected endpoint has disappeared
        if let selected = self.selectedInput {
            let stillAvailable = self.availableInputs.contains(where: { $0.uniqueID == selected.uniqueID })
            if !stillAvailable {
                log.info("MIDI device disconnected: \(selected.displayName)")
                self.selectedInput = nil
                self.isConnected = false
            }
        }
        
        // Auto-select only Choir dolls (CH-8, Choir, or TE devices)
        if self.selectedInput == nil {
            let choirDevice = self.availableInputs.first(where: {
                $0.displayName.contains("CH-8") || $0.displayName.contains("Choir") || $0.displayName.contains("TE")
            })
            
            if let input = choirDevice {
                self.selectedInput = input
                self.setupConnection(to: input)
            }
        }
        // If already connected, don't re-create the connection on every notification
    }
    
    func selectInput(_ endpoint: MIDIInputEndpoint) {
        selectedInput = endpoint
        setupConnection(to: endpoint)
    }
    
    private func setupConnection(to endpoint: MIDIInputEndpoint) {
        // Remove old connection
        midiManager.remove(.outputConnection, .withTag("ChoirOutput"))
        
        // Create new connection - we SEND to the device's INPUT
        do {
            try midiManager.addOutputConnection(
                to: .inputs(matching: [.uniqueID(endpoint.uniqueID)]),
                tag: "ChoirOutput"
            )
            isConnected = true
            log.info("Connected to MIDI input: \(endpoint.displayName)")
        } catch {
            log.error("Error creating MIDI output connection: \(error.localizedDescription)")
            isConnected = false
        }
    }
    
    func sendNoteOn(note: UInt8, velocity: UInt8 = 100, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else {
            log.error("MIDI: No output connection 'ChoirOutput' found")
            return
        }
        
        // Send CC values BEFORE the note (Choir requires this)
        sendCC(controller: ChoirCC.vibrato, value: vibrato, channel: channel)
        sendCC(controller: ChoirCC.reverb, value: reverb, channel: channel)
        sendCC(controller: ChoirCC.consonant, value: consonant, channel: channel)
        sendCC(controller: ChoirCC.vowel, value: vowel, channel: channel)
        
        let noteOn = MIDIEvent.noteOn(
            UInt7(note),
            velocity: .midi1(UInt7(velocity)),
            channel: channel
        )
        
        do {
            try connection.send(event: noteOn)
            log.debug("Note On \(note) ch:\(channel)")
        } catch {
            log.error("MIDI send error: \(error.localizedDescription)")
        }
    }
    
    func sendNoteOff(note: UInt8, velocity: UInt8 = 0, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else { return }
        
        let noteOff = MIDIEvent.noteOff(
            UInt7(note),
            velocity: .midi1(UInt7(velocity)),
            channel: channel
        )
        
        do {
            try connection.send(event: noteOff)
            log.debug("Note Off \(note) ch:\(channel)")
        } catch {
            log.error("MIDI Note Off error: \(error.localizedDescription)")
        }
    }
    
    /// Send All Notes Off (CC 123) + All Sound Off (CC 120) on all channels
    func panicAllNotesOff() {
        log.info("MIDI Panic: All Notes Off + CC Reset")
        for ch: UInt8 in 0...15 {
            let channel = UInt4(ch)
            sendCC(controller: 120, value: 0, channel: channel) // All Sound Off
            sendCC(controller: 123, value: 0, channel: channel) // All Notes Off
            sendCC(controller: 121, value: 0, channel: channel) // Reset All Controllers
        }
        // Also send explicit NoteOff for all notes on channel 0
        for note: UInt8 in 0...127 {
            sendNoteOff(note: note, velocity: 0, channel: 0)
        }
        // Re-send Choir CC defaults
        sendCC(controller: ChoirCC.consonant, value: ChoirDefaults.consonant)
        sendCC(controller: ChoirCC.vowel, value: ChoirDefaults.vowel)
        sendCC(controller: ChoirCC.vibrato, value: ChoirDefaults.vibrato)
        sendCC(controller: ChoirCC.reverb, value: ChoirDefaults.reverb)
        log.info("MIDI Panic: CC reset to defaults (cons=\(ChoirDefaults.consonant) vow=\(ChoirDefaults.vowel) vib=\(ChoirDefaults.vibrato) rev=\(ChoirDefaults.reverb))")
    }
    
    func sendCC(controller: UInt8, value: UInt8, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else {
            log.error("CC: No output connection")
            return
        }
        
        let cc = MIDIEvent.cc(
            UInt7(controller),
            value: .midi1(UInt7(value)),
            channel: channel
        )
        
        do {
            try connection.send(event: cc)
            log.debug("CC\(controller)=\(value) ch:\(channel)")
        } catch {
            log.error("CC send error: \(error.localizedDescription)")
        }
    }
    
    /// Send pitch bend. Value range: 0-16383, center (no bend) = 8192
    func sendPitchBend(value: UInt16, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else { return }
        let clampedValue = min(value, 16383)
        let pitchBend = MIDIEvent.pitchBend(value: .midi1(UInt14(clampedValue)), channel: channel)
        do {
            try connection.send(event: pitchBend)
            log.debug("Pitch Bend \(clampedValue) ch:\(channel)")
        } catch {
            log.error("Pitch Bend error: \(error.localizedDescription)")
        }
    }
}
