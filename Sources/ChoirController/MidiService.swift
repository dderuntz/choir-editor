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
    
    func sendNoteOff(note: UInt8, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else { return }
        
        let noteOff = MIDIEvent.noteOff(
            UInt7(note),
            velocity: .midi1(0),
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
}
