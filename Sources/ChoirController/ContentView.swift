import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bluetoothManager: BluetoothMidiManager
    @EnvironmentObject var midiService: MidiService
    
    var body: some View {
        HSplitView {
            // Sidebar / Connection View (with Voice Controls)
            ConnectionView(bluetoothManager: bluetoothManager, midiService: midiService)
                .frame(minWidth: 200, maxWidth: 300)
                .layoutPriority(1)
            
            // Main Content Area
            VStack {
                Text("Choir Controller")
                    .font(.largeTitle)
                    .padding()
                    .padding(.top, 20) // Add extra top padding
                
                // Haiku Sequencer
                SequencerView(midiService: midiService)
                    .frame(maxWidth: 500)
                    .padding(.top)
                
                Spacer()
                
                // Piano Keyboard
                KeyboardView(midiService: midiService)
                    .frame(height: 180)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 850, minHeight: 500)
        .onAppear {
            midiService.start()
        }
    }
}
