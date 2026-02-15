import SwiftUI

// Settings panel content (collapsible, slides in from left)
struct SettingsPanelView: View {
    @ObservedObject var midiService: MidiService
    @Binding var showSettings: Bool
    @AppStorage("localAudioMode") private var localAudioMode = LocalAudioMode.automatic.rawValue
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — lines up with doc title (same horizontal padding)
            HStack {
                HStack(alignment: .top, spacing: 2) {
                    Text("Setup")
                        .font(.system(size: 56, weight: .ultraLight))
                        .kerning(-1.4)
                    Image(systemName: "nose")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.text(colorScheme))
                        .offset(x: 2, y: 11)
                }
                Spacer()
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSettings = false } }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(Theme.text(colorScheme).opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
            .background(Theme.bg(colorScheme))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Sequencer Settings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sequencer")
                            .font(Theme.toolbarFont)
                            .foregroundColor(Theme.text(colorScheme).opacity(0.5))
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
                            .font(Theme.toolbarFont)
                            .foregroundColor(Theme.text(colorScheme).opacity(0.5))
                            .textCase(.uppercase)
                        
                        VoiceControlsView(midiService: midiService)
                    }
                    
                    Divider()
                    
                    Picker("Local Synth Monitor", selection: $localAudioMode) {
                        ForEach(LocalAudioMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .font(Theme.toolbarFont)
                    .controlSize(.small)
                    
                    Button(action: {
                        midiService.tempo = 100
                        midiService.minNoteDuration = 0.28
                        midiService.vibrato = ChoirDefaults.vibrato
                        midiService.reverb = ChoirDefaults.reverb
                    }) {
                        Text("Reset Defaults")
                            .font(Theme.toolbarFont)
                            .foregroundColor(Theme.text(colorScheme).opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .tint(Theme.text(colorScheme))
            }
        }
    }
}
