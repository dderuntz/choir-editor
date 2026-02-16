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

                HStack(spacing: 8) {
                    Button(action: {
                        // TODO: LLM text generation
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "eyebrow")
                            Text("Summon Song")
                                .font(Theme.buttonFont)
                                .fontWeight(Theme.buttonWeight)
                        }
                        .foregroundColor(Theme.text(colorScheme).opacity(buttonOpacity))
                        .padding(.horizontal, Theme.buttonPaddingH)
                        .padding(.vertical, Theme.buttonPaddingV)
                        .overlay(
                            Capsule()
                                .stroke(Theme.text(colorScheme).opacity(buttonOpacity), lineWidth: Theme.buttonStroke)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasText)

                    Button(action: {
                        Task { await composerModel.extractPhonemes() }
                    }) {
                        HStack(spacing: 6) {
                            if composerModel.isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "eye")
                            }
                            Text(composerModel.isProcessing ? "Thinking…" : "Reveal Phonemes")
                                .font(Theme.buttonFont)
                                .fontWeight(Theme.buttonWeight)
                        }
                        .foregroundColor(Theme.text(colorScheme).opacity(buttonOpacity))
                        .padding(.horizontal, Theme.buttonPaddingH)
                        .padding(.vertical, Theme.buttonPaddingV)
                        .overlay(
                            Capsule()
                                .stroke(Theme.text(colorScheme).opacity(buttonOpacity), lineWidth: Theme.buttonStroke)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasText || composerModel.isProcessing)
                }
                .padding(.top, 4)

                // Phoneme pills (ScrollView within 640, scrolls naturally)
                if !composerModel.phonemes.isEmpty {
                    phonemeStrip(leadingPad: 0)
                        .scrollClipDisabled()
                        .padding(.top, 48)
                }

                // Play / Stop
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
                        .foregroundColor(Theme.dark)
                        .padding(.horizontal, Theme.buttonPaddingH)
                        .padding(.vertical, Theme.buttonPaddingV)
                        .background(
                            Capsule()
                                .fill(composerModel.isPlaying ? Theme.green : Theme.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
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

    var body: some View {
        VStack(spacing: 2) {
            Text(phoneme.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.text(colorScheme))

            HStack(spacing: 3) {
                Text(phoneme.consonantName)
                    .font(.system(size: 10))
                Text("·")
                    .font(.system(size: 8))
                Text(phoneme.vowelSymbol)
                    .font(.system(size: 10))
            }
            .foregroundColor(Theme.text(colorScheme).opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.text(colorScheme).opacity(0.05))
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
