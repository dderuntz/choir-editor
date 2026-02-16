import SwiftUI

struct ComposerView: View {
    @EnvironmentObject var composerModel: ComposerModel
    @ObservedObject var audioMonitor: AudioMonitorService
    @AppStorage("showKeyboard") private var showKeyboard = true
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextFocused: Bool

    private var lineCount: Int {
        max(1, composerModel.inputText.components(separatedBy: "\n").count)
    }

    private var lineHeight: CGFloat { 67 }

    var body: some View {
        GeometryReader { geo in
        ZStack {
            // Tight group: label + field + buttons
            let hasText = !composerModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            VStack(alignment: .leading, spacing: 8) {
                // Label
                Text("What shall they sing?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.text(colorScheme).opacity(hasText ? 0.4 : 1.0))
                    .padding(.bottom, 8)

                // Text editor (grows with lines, max 4)
                ZStack(alignment: .topLeading) {
                    if composerModel.inputText.isEmpty {
                        Text("prompt or lyric")
                            .font(.system(size: 56, weight: .ultraLight))
                            .kerning(-1.4)
                            .foregroundColor(Theme.text(colorScheme).opacity(0.15))
                            .padding(.top, 0)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $composerModel.inputText)
                        .font(.system(size: 56, weight: .ultraLight))
                        .kerning(-1.4)
                        .scrollContentBackground(.hidden)
                        .focused($isTextFocused)
                }
                .frame(height: lineHeight * CGFloat(lineCount))
                .onChange(of: composerModel.inputText) { newValue in
                    let lines = newValue.components(separatedBy: "\n")
                    if lines.count > 4 {
                        composerModel.inputText = lines.prefix(4).joined(separator: "\n")
                    }
                }

                // Action buttons
                let buttonOpacity: Double = hasText ? 0.85 : 0.35

                let buttonBg = Color(red: 0xD8/255, green: 0xD6/255, blue: 0xD3/255)
                HStack(spacing: 8) {
                    Button(action: {
                        // TODO: LLM text generation
                    }) {
                        Label("Summon Song", systemImage: "eyebrow")
                            .foregroundColor(Theme.dark)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(buttonBg)
                    .disabled(!hasText)

                    Button(action: {
                        Task { await composerModel.extractPhonemes() }
                    }) {
                        Label(composerModel.isProcessing ? "Thinking…" : "Reveal Phonemes",
                              systemImage: composerModel.isProcessing ? "ellipsis" : "eye")
                            .foregroundColor(Theme.dark)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(buttonBg)
                    .disabled(!hasText || composerModel.isProcessing)
                }
                .padding(.top, 4)

                // Phoneme pills
                if !composerModel.phonemes.isEmpty {
                    phonemeStrip(leadingPad: 0)
                        .scrollClipDisabled()
                        .padding(.top, 48)
                }

                // Play + Key/Scale
                if !composerModel.phonemes.isEmpty {
                    HStack(spacing: 12) {
                        Button(action: {
                            if composerModel.isPlaying {
                                composerModel.stop()
                                audioMonitor.stopNote(note: 60)
                            } else {
                                composerModel.playPhonemes(audioMonitor: audioMonitor)
                            }
                        }) {
                            Label(composerModel.isPlaying ? "Stop" : "Play",
                                  systemImage: composerModel.isPlaying ? "stop.fill" : "play.fill")
                                .foregroundColor(Theme.dark)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(composerModel.isPlaying ? Theme.green : Theme.accent)

                        Picker("", selection: $composerModel.musicalKey) {
                            ForEach(MusicalKey.allCases) { key in
                                Text(key.name).tag(key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 52)

                        Picker("", selection: $composerModel.scaleType) {
                            ForEach(ScaleType.allCases) { scale in
                                Text(scale.rawValue).tag(scale)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)

                        Picker("", selection: $composerModel.speedMultiplier) {
                            Text("Normal").tag(1.0)
                            Text("Slower").tag(1.25)
                            Text("Slowest").tag(1.5)
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    .padding(.top, 8)

                    // Instruction caption
                    Text("Shift-click a chip to add chorus")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.35))
                        .padding(.top, 4)
                }

                // Error / status
                if let error = composerModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.7))
                }

                if let status = composerModel.llmStatusMessage, !composerModel.isLLMAvailable {
                    Label(status, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(Theme.text(colorScheme).opacity(0.4))
                }
            }
            .frame(maxWidth: 640)
            .position(x: geo.size.width / 2, y: geo.size.height * 0.40)

            // Bottom keyboard divider
            VStack(spacing: 0) {
                Spacer()
                if showKeyboard {
                    Theme.dark.opacity(0.15)
                        .frame(height: 1)
                }
            }
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg(colorScheme))
        .onAppear { isTextFocused = true }
    }

    // MARK: - Phoneme Strip

    private func phonemeStrip(leadingPad: CGFloat = 0) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(composerModel.phonemes.enumerated()), id: \.element.id) { index, phoneme in
                    PhonemeChip(
                        phoneme: phoneme,
                        isActive: composerModel.currentPlayIndex == index,
                        onDelete: { composerModel.deletePhoneme(phoneme) }
                    )
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.shift) {
                            composerModel.toggleEnsemble(phoneme)
                        } else {
                            composerModel.playSinglePhoneme(phoneme, audioMonitor: audioMonitor)
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        composerModel.toggleEnsemble(phoneme)
                    }
                }

                // Thumbs up + trash at end of strip
                Button(action: { composerModel.approveResult() }) {
                    Image(systemName: composerModel.isApproved ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.title2)
                        .foregroundColor(composerModel.isApproved ? Theme.accent : Theme.text(colorScheme).opacity(0.3))
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
                .help(composerModel.isApproved
                      ? "Saved (\(composerModel.savedExampleCount) examples)"
                      : "Approve — save as training example")

                Button(action: {
                    composerModel.stop()
                    composerModel.clearAll()
                }) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundColor(Theme.text(colorScheme).opacity(0.3))
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .help("Clear all")
            }
            .padding(.leading, leadingPad)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Phoneme Chip

struct PhonemeChip: View {
    let phoneme: ChoirPhoneme
    let isActive: Bool
    var onDelete: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var phonemeLabel: String {
        let c = Consonant.all.first { $0.ccValue == phoneme.consonantCC }
        let v = Vowel.all.first { $0.ccValue == phoneme.vowelCC }
        let isNone = (c?.name == "None")
        let cPart = isNone ? "" : (c?.name ?? "")
        let vPart = v?.symbol ?? ""
        return cPart + vPart
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Text(phoneme.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Theme.ivory)
                if phoneme.isEnsemble {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 7))
                        .foregroundColor(Theme.ivory)
                }
            }

            if !phonemeLabel.isEmpty {
                Text(phonemeLabel)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.ivory.opacity(0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Theme.green : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if isHovered, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.dark)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Theme.ivory))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .animation(.easeInOut(duration: 0.15), value: phoneme.isEnsemble)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}
