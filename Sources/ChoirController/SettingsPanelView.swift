import SwiftUI

// Settings panel content (collapsible, slides in from left)
struct SettingsPanelView: View {
    @ObservedObject var midiService: MidiService
    @Binding var showSettings: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — matches doc title style
            HStack {
                Text("Setup")
                    .font(.system(size: 56, weight: .ultraLight))
                    .kerning(-1.4)
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSettings = false } }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(Theme.toolbarInactive)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Theme.surface)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Sequencer Settings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sequencer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        SliderWithDefault(label: "Tempo", value: $midiService.tempo, range: 40...200, defaultValue: 100, displayText: "\(Int(midiService.tempo))", displayWidth: 30) { val in
                            (val / 5).rounded() * 5
                        }
                        
                        SliderWithDefault(label: "Min Note", value: $midiService.minNoteDuration, range: 0.01...0.5, defaultValue: 0.28, displayText: "\(Int(midiService.minNoteDuration * 1000))ms", displayWidth: 40) { val in
                            (val * 100).rounded() / 100
                        }
                    }
                    
                    Divider()
                    
                    // Voice Controls
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Global Choir Effects")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        VoiceControlsView(midiService: midiService)
                    }
                    
                    Divider()
                    
                    Button(action: {
                        midiService.tempo = 100
                        midiService.minNoteDuration = 0.28
                        midiService.vibrato = ChoirDefaults.vibrato
                        midiService.reverb = ChoirDefaults.reverb
                    }) {
                        Text("Reset Defaults")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
        }
    }
}
