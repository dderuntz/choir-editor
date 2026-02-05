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
    
    @Published var availableOutputs: [MIDIOutputEndpoint] = []
    @Published var selectedOutput: MIDIOutputEndpoint?
    
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
        // No need for dispatch main async if we are MainActor and called from MainActor task
        self.availableOutputs = self.midiManager.endpoints.outputs
        
        // Auto-select if we find a Teenage Engineering device or just the first one if none selected
        if self.selectedOutput == nil {
            self.selectedOutput = self.availableOutputs.first(where: { $0.displayName.contains("Choir") || $0.displayName.contains("TE") }) 
                ?? self.availableOutputs.first
        }
        
        // If we have a selection, ensure connection is set up
        if let output = self.selectedOutput {
            self.setupConnection(to: output)
        }
    }
    
    func selectOutput(_ endpoint: MIDIOutputEndpoint) {
        selectedOutput = endpoint
        setupConnection(to: endpoint)
    }
    
    private func setupConnection(to endpoint: MIDIOutputEndpoint) {
        // Remove old connection
        // Assuming .tag wraps the string
        midiManager.remove(.outputConnection, .withTag("ChoirOutput"))
        
        // Create new connection
        do {
            try midiManager.addOutputConnection(
                to: .inputs(matching: [.uniqueID(endpoint.uniqueID)]),
                tag: "ChoirOutput"
            )
            isConnected = true
            print("Successfully connected to MIDI output: \(endpoint.displayName)")
        } catch {
            print("Error creating MIDI output connection: \(error.localizedDescription)")
            isConnected = false
        }
    }
    
    func sendNoteOn(note: UInt8, velocity: UInt8 = 100, channel: UInt4 = 0) {
        guard let connection = midiManager.managedOutputConnections["ChoirOutput"] else { return }
        
        let noteOn = MIDIEvent.noteOn(
            UInt7(note),
            velocity: .midi1(UInt7(velocity)),
            channel: channel
        )
        
        do {
            try connection.send(event: noteOn)
        } catch {
            print("Error sending Note On: \(error.localizedDescription)")
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
        } catch {
            print("Error sending Note Off: \(error.localizedDescription)")
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
