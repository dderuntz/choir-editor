import SwiftUI

// Settings panel content (collapsible, slides in from left)
struct SettingsPanelView: View {
    @ObservedObject var midiService: MidiService
    @ObservedObject var audioMonitor: AudioMonitorService
    @Binding var showSettings: Bool
    @AppStorage("localAudioMode") private var localAudioMode = LocalAudioMode.automatic.rawValue
    @AppStorage("lyricStyle") private var lyricStyle: LyricStyle = .senryu
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — lines up with doc title (same horizontal padding)
            HStack {
                Text("Prefer")
                    .font(.system(size: 56, weight: .ultraLight))
                    .kerning(-1.4)
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
                VStack(alignment: .leading, spacing: 12) {
                    // Sequencer Settings
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Sequencer")
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundColor(Theme.text(colorScheme).opacity(0.3))
                                .textCase(.uppercase)
                            Spacer()
                            ResetButton {
                                midiService.tempo = 100
                                midiService.minNoteDuration = 0.28
                            }
                        }
                        
                        SliderWithDefault(label: "Tempo", value: $midiService.tempo, range: 40...200, defaultValue: 100, displayText: "\(Int(midiService.tempo))", displayWidth: 30) { val in
                            (val / 5).rounded() * 5
                        }
                        
                        SliderWithDefault(label: "Min Note", value: $midiService.minNoteDuration, range: 0.01...0.5, defaultValue: 0.28, displayText: "\(Int(midiService.minNoteDuration * 1000))ms", displayWidth: 40) { val in
                            (val * 100).rounded() / 100
                        }
                    }
                    
                    Divider().padding(.top, 3)
                    
                    // Voice Controls
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Global Effects")
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .foregroundColor(Theme.text(colorScheme).opacity(0.3))
                                .textCase(.uppercase)
                            Spacer()
                            ResetButton {
                                midiService.vibrato = ChoirDefaults.vibrato
                                midiService.reverb = ChoirDefaults.reverb
                            }
                        }
                        
                        VoiceControlsView(midiService: midiService)
                    }
                    
                    Divider().padding(.top, 3)
                    
                    // Audio
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Audio")
                            .font(.system(size: 10))
                            .fontWeight(.medium)
                            .foregroundColor(Theme.text(colorScheme).opacity(0.3))
                            .textCase(.uppercase)
                        HStack {
                            Text("Local Playback")
                                .font(Theme.toolbarFont)
                            Spacer()
                            Picker("", selection: $localAudioMode) {
                                ForEach(LocalAudioMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode.rawValue)
                                }
                            }
                            .labelsHidden()
                            .controlSize(.small)
                            .fixedSize()
                        }
                        
                        HStack {
                            Text("Playback Engine")
                                .font(Theme.toolbarFont)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { audioMonitor.engineType },
                                set: { audioMonitor.setEngine($0) }
                            )) {
                                ForEach(SynthEngineType.allCases) { type in
                                    Text(type.label).tag(type)
                                }
                            }
                            .labelsHidden()
                            .controlSize(.small)
                            .fixedSize()
                        }
                        
                        Text(audioMonitor.engineType.blurb)
                            .font(Theme.toolbarFont)
                            .foregroundColor(Theme.text(colorScheme).opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Divider().padding(.top, 3)
                    
                    // Composer
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Composer")
                            .font(.system(size: 10))
                            .fontWeight(.medium)
                            .foregroundColor(Theme.text(colorScheme).opacity(0.3))
                            .textCase(.uppercase)
                        
                        HStack {
                            Text("Recomposition Style (AI)")
                                .font(Theme.toolbarFont)
                            Spacer()
                            Picker("", selection: $lyricStyle) {
                                ForEach(LyricStyle.allCases) { style in
                                    Text(style.label).tag(style)
                                }
                            }
                            .labelsHidden()
                            .controlSize(.small)
                            .fixedSize()
                        }
                        
                        Text(lyricStyle.blurb)
                            .font(Theme.toolbarFont)
                            .foregroundColor(Theme.text(colorScheme).opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("The composer uses Apple's on-device Foundation Model. All processing happens locally on your Mac — no data is sent to external servers.")
                            .font(Theme.toolbarFont)
                            .foregroundColor(Theme.text(colorScheme).opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .tint(Theme.text(colorScheme))
            }
        }
    }
}

private struct ResetButton: View {
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text("reset")
                .font(Theme.toolbarFont)
                .foregroundColor(isHovered ? Theme.text(colorScheme) : Theme.text(colorScheme).opacity(0.3))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
