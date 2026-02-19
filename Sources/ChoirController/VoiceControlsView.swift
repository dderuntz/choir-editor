import SwiftUI

struct VoiceControlsView: View {
    @ObservedObject var midiService: MidiService
    
    // Local state for slider binding (UInt8 -> Double conversion)
    @State private var vibratoValue: Double = Double(ChoirDefaults.vibrato)
    @State private var reverbValue: Double = Double(ChoirDefaults.reverb)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SliderWithDefault(label: "Vibrato", value: $vibratoValue, range: 0...127, defaultValue: Double(ChoirDefaults.vibrato), displayText: "\(Int(vibratoValue))") { val in
                let rounded = val.rounded()
                midiService.vibrato = UInt8(rounded)
                return rounded
            }
            
            SliderWithDefault(label: "Reverb", value: $reverbValue, range: 0...127, defaultValue: Double(ChoirDefaults.reverb), displayText: "\(Int(reverbValue))") { val in
                let rounded = val.rounded()
                midiService.reverb = UInt8(rounded)
                return rounded
            }
        }
        .onAppear {
            vibratoValue = Double(midiService.vibrato)
            reverbValue = Double(midiService.reverb)
        }
        .onChange(of: midiService.vibrato) { _, val in vibratoValue = Double(val) }
        .onChange(of: midiService.reverb) { _, val in reverbValue = Double(val) }
    }
}
