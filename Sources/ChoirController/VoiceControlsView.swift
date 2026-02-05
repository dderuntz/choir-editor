import SwiftUI

struct VoiceControlsView: View {
    @ObservedObject var midiService: MidiService
    
    // Local state for slider binding (UInt8 -> Double conversion)
    @State private var vibratoValue: Double = Double(ChoirDefaults.vibrato)
    @State private var reverbValue: Double = Double(ChoirDefaults.reverb)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice Controls")
                .font(.headline)
            
            // Vibrato Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Vibrato")
                        .frame(width: 60, alignment: .leading)
                    Slider(value: $vibratoValue, in: 0...127, step: 1)
                        .onChange(of: vibratoValue) { newValue in
                            midiService.vibrato = UInt8(newValue)
                        }
                    Text("\(Int(vibratoValue))")
                        .frame(width: 35, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            
            // Reverb Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Reverb")
                        .frame(width: 60, alignment: .leading)
                    Slider(value: $reverbValue, in: 0...127, step: 1)
                        .onChange(of: reverbValue) { newValue in
                            midiService.reverb = UInt8(newValue)
                        }
                    Text("\(Int(reverbValue))")
                        .frame(width: 35, alignment: .trailing)
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            // Sync with midiService values on appear
            vibratoValue = Double(midiService.vibrato)
            reverbValue = Double(midiService.reverb)
        }
    }
}
