import Foundation
import MIDIKit
import Combine

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
    @Published var consonantDuration: Double = 0.15
    @Published var minNoteDuration: Double = 0.28
    
    init() {
        // We need to defer notification handler setup or handle concurrency carefully
        // Since we are in init, self is not fully available/sendable yet in some contexts, 
        // but let's try setting it up.
        // To avoid Sendable warnings in strict mode with closure capturing self:
        // We can use a helper or just assume MainActor isolation.
    }
    
    func start() {
        midiManager.notificationHandler = { [weak self] notification in
            Task { @MainActor in
                self?.updateEndpoints()
            }
        }
        
        do {
            try midiManager.start()
        } catch {
            print("Error starting MIDI Manager: \(error.localizedDescription)")
        }
        
        updateEndpoints()
    }
    
    func updateEndpoints() {
        // Get INPUT endpoints (destinations that receive MIDI, like the Choir)
        self.availableInputs = self.midiManager.endpoints.inputs
        
        print("🔍 MIDI Input Endpoints Found: \(self.availableInputs.count)")
        for input in self.availableInputs {
            print("   - Name: '\(input.name)', DisplayName: '\(input.displayName)', ID: \(input.uniqueID)")
        }
        
        // Auto-select if we find a Teenage Engineering device or just the first one if none selected
        if self.selectedInput == nil {
            self.selectedInput = self.availableInputs.first(where: { $0.displayName.contains("CH-8") || $0.displayName.contains("Choir") || $0.displayName.contains("TE") }) 
                ?? self.availableInputs.first
        }
        
        // If we have a selection, ensure connection is set up
        if let input = self.selectedInput {
            self.setupConnection(to: input)
        }
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
            print("✅ Successfully connected to MIDI input: \(endpoint.displayName)")
        } catch {
            print("❌ Error creating MIDI output connection: \(error.localizedDescription)")
            isConnected = false
        }
    }
    
    func sendNoteOn(note: UInt8, velocity: UInt8 = 100, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else {
            print("❌ MIDI: No output connection 'ChoirOutput' found!")
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
            print("🎹 MIDI Sent: Note On \(note) ch:\(channel)")
        } catch {
            print("❌ MIDI Error: \(error.localizedDescription)")
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
            print("🎹 MIDI Sent: Note Off \(note) ch:\(channel)")
        } catch {
            print("❌ MIDI Error sending Note Off: \(error.localizedDescription)")
        }
    }
    
    func sendCC(controller: UInt8, value: UInt8, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else { return }
        
        let cc = MIDIEvent.cc(
            UInt7(controller),
            value: .midi1(UInt7(value)),
            channel: channel
        )
        
        do {
            try connection.send(event: cc)
        } catch {
            print("Error sending CC: \(error.localizedDescription)")
        }
    }
    
    /// Send pitch bend. Value range: 0-16383, center (no bend) = 8192
    func sendPitchBend(value: UInt16, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else { return }
        
        // MIDIKit uses UInt14 for pitch bend (0-16383)
        let clampedValue = min(value, 16383)
        let pitchBend = MIDIEvent.pitchBend(value: .midi1(UInt14(clampedValue)), channel: channel)
        
        do {
            try connection.send(event: pitchBend)
            print("🎹 MIDI Sent: Pitch Bend \(clampedValue) ch:\(channel)")
        } catch {
            print("❌ MIDI Error sending Pitch Bend: \(error.localizedDescription)")
        }
    }
    
    /// Send channel aftertouch (pressure). Value range: 0-127
    func sendAftertouch(pressure: UInt8, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else { return }
        
        let aftertouch = MIDIEvent.pressure(amount: .midi1(UInt7(min(pressure, 127))), channel: channel)
        
        do {
            try connection.send(event: aftertouch)
            print("🎹 MIDI Sent: Aftertouch \(pressure) ch:\(channel)")
        } catch {
            print("❌ MIDI Error sending Aftertouch: \(error.localizedDescription)")
        }
    }
    
    /// Send program change. Value range: 0-127
    func sendProgramChange(program: UInt8, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else { return }
        
        let pc = MIDIEvent.programChange(program: UInt7(min(program, 127)), channel: channel)
        
        do {
            try connection.send(event: pc)
            print("🎹 MIDI Sent: Program Change \(program) ch:\(channel)")
        } catch {
            print("❌ MIDI Error sending Program Change: \(error.localizedDescription)")
        }
    }
    
    /// Send NRPN (Non-Registered Parameter Number)
    /// Parameter range: 0-16383, Value range: 0-16383
    func sendNRPN(parameter: UInt16, value: UInt16, channel: UInt4 = 0) {
        // NRPN uses 4 CC messages:
        // CC99 = parameter MSB (high 7 bits)
        // CC98 = parameter LSB (low 7 bits)
        // CC6 = value MSB (high 7 bits)
        // CC38 = value LSB (low 7 bits) - optional for fine control
        
        let paramMSB = UInt8((parameter >> 7) & 0x7F)
        let paramLSB = UInt8(parameter & 0x7F)
        let valueMSB = UInt8((value >> 7) & 0x7F)
        let valueLSB = UInt8(value & 0x7F)
        
        sendCC(controller: 99, value: paramMSB, channel: channel)
        sendCC(controller: 98, value: paramLSB, channel: channel)
        sendCC(controller: 6, value: valueMSB, channel: channel)
        sendCC(controller: 38, value: valueLSB, channel: channel)
        
        print("🎹 MIDI Sent: NRPN param=\(parameter) value=\(value) ch:\(channel)")
    }
    
    /// Send Song Select (0-127)
    func sendSongSelect(song: UInt8, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else { return }
        
        let songSelect = MIDIEvent.songSelect(
            number: UInt7(min(song, 127))
        )
        
        do {
            try connection.send(event: songSelect)
            print("🎹 MIDI Sent: Song Select \(song)")
        } catch {
            print("❌ MIDI Error sending Song Select: \(error.localizedDescription)")
        }
    }
}
