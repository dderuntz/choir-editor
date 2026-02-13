import SwiftUI

struct VoiceControlsView: View {
    @ObservedObject var midiService: MidiService
    
    // Local state for slider binding (UInt8 -> Double conversion)
    @State private var vibratoValue: Double = Double(ChoirDefaults.vibrato)
    @State private var reverbValue: Double = Double(ChoirDefaults.reverb)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Vibrato
            HStack {
                Text("Vibrato:")
                    .font(.caption)
                    .frame(width: 80, alignment: .leading)
                Slider(value: $vibratoValue, in: 0...127, step: 1)
                    .onChange(of: vibratoValue) { newValue in
                        midiService.vibrato = UInt8(newValue)
                    }
                Text("\(Int(vibratoValue))")
                    .font(.caption).monospacedDigit()
                    .frame(width: 30)
            }
            
            // Reverb
            HStack {
                Text("Reverb:")
                    .font(.caption)
                    .frame(width: 80, alignment: .leading)
                Slider(value: $reverbValue, in: 0...127, step: 1)
                    .onChange(of: reverbValue) { newValue in
                        midiService.reverb = UInt8(newValue)
                    }
                Text("\(Int(reverbValue))")
                    .font(.caption).monospacedDigit()
                    .frame(width: 30)
            }
        }
        .onAppear {
            vibratoValue = Double(midiService.vibrato)
            reverbValue = Double(midiService.reverb)
        }
    }
}
