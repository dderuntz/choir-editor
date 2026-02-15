import SwiftUI

struct ComposerView: View {
    @EnvironmentObject var composerModel: ComposerModel
    @ObservedObject var audioMonitor: AudioMonitorService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                // Label
                Text("What should they sing?")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.text(colorScheme).opacity(0.4))

                // Text editor
                TextEditor(text: $composerModel.inputText)
                    .font(.title2)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.text(colorScheme).opacity(0.04))
                    )
                    .frame(minHeight: 80, maxHeight: 180)

                // Action bar
                HStack(spacing: 12) {
                    // Extract button
                    Button(action: {
                        Task { await composerModel.extractPhonemes() }
                    }) {
                        HStack(spacing: 6) {
                            if composerModel.isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "waveform")
                            }
                            Text(composerModel.isProcessing ? "Thinking…" : "Extract Phonemes")
                                .font(Theme.buttonFont)
                                .fontWeight(Theme.buttonWeight)
                        }
                        .foregroundColor(Theme.text(colorScheme).opacity(0.85))
                        .padding(.horizontal, Theme.buttonPaddingH)
                        .padding(.vertical, Theme.buttonPaddingV)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.buttonRadius)
                                .stroke(Theme.text(colorScheme).opacity(0.85), lineWidth: Theme.buttonStroke)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(composerModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || composerModel.isProcessing)

                    Spacer()

                    // Play / Stop (visible once phonemes exist)
                    if !composerModel.phonemes.isEmpty {
                        Button(action: {
                            if composerModel.isPlaying {
                                composerModel.stop()
                                audioMonitor.stopNote(note: 60)
                            } else {
                                composerModel.playPhonemes(audioMonitor: audioMonitor)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: composerModel.isPlaying ? "stop.fill" : "play.fill")
                                Text(composerModel.isPlaying ? "Stop" : "Play")
                                    .font(Theme.buttonFont)
                                    .fontWeight(Theme.buttonWeight)
                            }
                            .foregroundColor(composerModel.isPlaying ? Theme.accent : Theme.text(colorScheme).opacity(0.85))
                            .padding(.horizontal, Theme.buttonPaddingH)
                            .padding(.vertical, Theme.buttonPaddingV)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.buttonRadius)
                                    .stroke(composerModel.isPlaying ? Theme.accent : Theme.text(colorScheme).opacity(0.85),
                                            lineWidth: Theme.buttonStroke)
                            )
                        }
                        .buttonStyle(.plain)
                    }
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
            .padding(.horizontal, 32)
            .padding(.top, 24)

            // Phoneme pills
            if !composerModel.phonemes.isEmpty {
                phonemeStrip
                    .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg(colorScheme))
    }

    // MARK: - Phoneme Strip

    private var phonemeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(composerModel.phonemes.enumerated()), id: \.element.id) { index, phoneme in
                    PhonemeChip(
                        phoneme: phoneme,
                        isActive: composerModel.currentPlayIndex == index,
                        onDelete: { composerModel.deletePhoneme(phoneme) }
                    )
                    .onTapGesture {
                        composerModel.playSinglePhoneme(phoneme, audioMonitor: audioMonitor)
                    }
                }

                // Thumbs up at end of strip
                Button(action: { composerModel.approveResult() }) {
                    Image(systemName: composerModel.isApproved ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 14))
                        .foregroundColor(composerModel.isApproved ? Theme.accent : Theme.text(colorScheme).opacity(0.3))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help(composerModel.isApproved
                      ? "Saved (\(composerModel.savedExampleCount) examples)"
                      : "Approve — save as training example")
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
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

    var body: some View {
        VStack(spacing: 2) {
            Text(phoneme.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isActive ? Theme.accent : Theme.text(colorScheme))

            HStack(spacing: 3) {
                Text(phoneme.consonantName)
                    .font(.system(size: 10))
                Text("·")
                    .font(.system(size: 8))
                Text(phoneme.vowelSymbol)
                    .font(.system(size: 10))
            }
            .foregroundColor(isActive ? Theme.accent.opacity(0.7) : Theme.text(colorScheme).opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Theme.accent.opacity(0.15) : Theme.text(colorScheme).opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .overlay(alignment: .topTrailing) {
            if isHovered, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.text(colorScheme).opacity(0.5))
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Theme.text(colorScheme).opacity(0.1)))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}
