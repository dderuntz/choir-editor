import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bluetoothManager: BluetoothMidiManager
    @EnvironmentObject var midiService: MidiService
    
    var body: some View {
        HSplitView {
            // Sidebar / Connection View
            ConnectionView(bluetoothManager: bluetoothManager)
                .frame(minWidth: 200, maxWidth: 300)
                .layoutPriority(1)
            
            // Main Content Area
            VStack {
                Text("Choir Controller")
                    .font(.largeTitle)
                    .padding()
                    .padding(.top, 20) // Add extra top padding
                
                // Connection Status Display
                if let selected = midiService.selectedOutput {
                    Text("MIDI Output: \(selected.displayName)")
                        .foregroundStyle(.green)
                } else {
                    Text("No MIDI Output Selected")
                        .foregroundStyle(.orange)
                }
                
                Spacer()
                
                // Piano Keyboard
                KeyboardView(midiService: midiService)
                    .frame(height: 150)
                    .padding()
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            midiService.start()
        }
    }
}
