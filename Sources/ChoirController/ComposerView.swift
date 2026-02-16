import SwiftUI

// MARK: - Chip Position Tracking

struct ChipCenterKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct ComposerView: View {
    @EnvironmentObject var composerModel: ComposerModel
    @EnvironmentObject var sequencerModel: SequencerModel
    @ObservedObject var audioMonitor: AudioMonitorService
    var onDismiss: (() -> Void)? = nil
    @AppStorage("showKeyboard") private var showKeyboard = true
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextFocused: Bool

    // Bouncing ball state
    @State private var chipCenters: [Int: CGFloat] = [:]
    @State private var ballX: CGFloat = 0
    @State private var ballY: CGFloat = 0  // 0 = chip level, negative = above

    // Chip inspector
    @State private var inspectedPhonemeId: UUID? = nil

    private var lineCount: Int {
        max(1, composerModel.inputText.components(separatedBy: "\n").count)
    }

    private var lineHeight: CGFloat { 62 }

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
                            .font(.system(size: 48, weight: .light))
                            .kerning(-1.0)
                            .foregroundColor(Theme.text(colorScheme).opacity(0.15))
                            .padding(.top, 0)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $composerModel.inputText)
                        .font(.system(size: 48, weight: .light))
                        .kerning(-1.0)
                        .scrollContentBackground(.hidden)
                        .focused($isTextFocused)
                }
                .frame(minHeight: lineHeight, maxHeight: lineHeight * 4)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: composerModel.inputText) { newValue in
                    var capped = newValue
                    let lines = capped.components(separatedBy: "\n")
                    if lines.count > 4 {
                        capped = lines.prefix(4).joined(separator: "\n")
                    }
                    if capped.count > 120 {
                        capped = String(capped.prefix(120))
                    }
                    if capped != newValue {
                        composerModel.inputText = capped
                    }
                }

                // Action buttons
                let buttonOpacity: Double = hasText ? 0.85 : 0.35

                let buttonBg = Color(red: 0xD8/255, green: 0xD6/255, blue: 0xD3/255)
                HStack(spacing: 8) {
                    let summonDisabled = !hasText || composerModel.isProcessing
                    Button(action: {
                        Task { await composerModel.summonSong() }
                    }) {
                        Label(composerModel.isProcessing ? "Summoning…" : "Summon Song",
                              systemImage: composerModel.isProcessing ? "ellipsis" : "eyebrow")
                            .foregroundColor(Theme.dark.opacity(summonDisabled ? 0.3 : 1))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(buttonBg.opacity(summonDisabled ? 0.4 : 1))
                    .disabled(summonDisabled)

                    let revealDisabled = !hasText || composerModel.isProcessing
                    Button(action: {
                        Task { await composerModel.extractPhonemes() }
                    }) {
                        Label(composerModel.isProcessing ? "Thinking…" : "Reveal Phonemes",
                              systemImage: composerModel.isProcessing ? "ellipsis" : "eye")
                            .foregroundColor(Theme.dark.opacity(revealDisabled ? 0.3 : 1))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(buttonBg.opacity(revealDisabled ? 0.4 : 1))
                    .disabled(revealDisabled)
                }
                .padding(.top, 4)

                // Phoneme pills + bouncing ball
                if !composerModel.phonemes.isEmpty {
                    ZStack(alignment: .topLeading) {
                        phonemeStrip(leadingPad: 0)
                            .scrollClipDisabled()

                        // Bouncing ball
                        if composerModel.isPlaying {
                            Circle()
                                .fill(Theme.green)
                                .frame(width: 10, height: 10)
                                .offset(x: ballX - 5, y: ballY - 3)
                        }
                    }
                    .onPreferenceChange(ChipCenterKey.self) { chipCenters = $0 }
                    // Snap ball to first chip when play starts
                    .onChange(of: composerModel.isPlaying) { playing in
                        if playing, let cx = chipCenters[0] {
                            ballX = cx
                            ballY = 0
                        }
                    }
                    .onChange(of: composerModel.currentPlayIndex) { newIndex in
                        guard let idx = newIndex, let cx = chipCenters[idx] else { return }

                        let nextCx = chipCenters[idx + 1] ?? cx
                        let distance = abs(nextCx - cx)
                        let arcHeight = -min(50, max(16, max(distance, 30) * 0.35))
                        // Full arc = note duration + gap — ball never sits still
                        let fullArc = Double(composerModel.currentArcDuration) / 1000.0
                        let halfArc = fullArc * 0.5

                        // Very steep curves: near-vertical launch/drop, long hang at apex
                        let steepOut = Animation.timingCurve(0, 0, 0.05, 1, duration: halfArc)
                        let steepIn = Animation.timingCurve(0.95, 0, 1, 1, duration: halfArc)

                        // Phase 1 — UP: steep launch, linear X travel
                        withAnimation(steepOut) {
                            ballY = arcHeight
                        }
                        withAnimation(.linear(duration: halfArc)) {
                            ballX = (cx + nextCx) / 2
                        }

                        // Phase 2 — DOWN: steep drop, linear X arrival
                        DispatchQueue.main.asyncAfter(deadline: .now() + halfArc) {
                            withAnimation(steepIn) {
                                ballY = 0
                            }
                            withAnimation(.linear(duration: halfArc)) {
                                ballX = nextCx
                            }
                        }
                    }
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
                            Text("Normal Speed").tag(1.0)
                            Text("Slower").tag(1.25)
                            Text("Slowest").tag(1.5)
                        }
                        .labelsHidden()
                        .frame(width: 90)

                        Spacer()

                        Button(action: {
                            composerModel.copyToGrid(sequencer: sequencerModel)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                onDismiss?()
                            }
                        }) {
                            Label("Add to Sequencer", systemImage: "rectangle.grid.1x3")
                                .foregroundColor(Theme.dark)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0xD8/255, green: 0xD6/255, blue: 0xD3/255))
                    }
                    .padding(.top, 8)

                    // Instruction caption
                    Text("Shift-click a chip to add choir")
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
                    .background(
                        GeometryReader { chipGeo in
                            Color.clear.preference(
                                key: ChipCenterKey.self,
                                value: [index: chipGeo.frame(in: .named("phonemeStrip")).midX]
                            )
                        }
                    )
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.shift) {
                            composerModel.toggleEnsemble(phoneme)
                        } else {
                            composerModel.playSinglePhoneme(phoneme, audioMonitor: audioMonitor)
                            inspectedPhonemeId = (inspectedPhonemeId == phoneme.id) ? nil : phoneme.id
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        composerModel.toggleEnsemble(phoneme)
                    }
                    .popover(isPresented: Binding(
                        get: { inspectedPhonemeId == phoneme.id },
                        set: { if !$0 { inspectedPhonemeId = nil } }
                    )) {
                        PhonemeInspector(
                            phoneme: phoneme,
                            onUpdate: { consonant, vowel in
                                composerModel.updatePhoneme(id: phoneme.id, consonantCC: consonant, vowelCC: vowel)
                            },
                            onToggleEnsemble: {
                                composerModel.toggleEnsemble(phoneme)
                            }
                        )
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
        .coordinateSpace(name: "phonemeStrip")
    }
}

// MARK: - Phoneme Chip

struct PhonemeChip: View {
    let phoneme: ChoirPhoneme
    let isActive: Bool
    var onDelete: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var bump: CGFloat = 0
    @State private var flashGreen = false

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
            Text(phoneme.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Theme.ivory)

            if !phonemeLabel.isEmpty || phoneme.isEnsemble {
                HStack(spacing: 3) {
                    if !phonemeLabel.isEmpty {
                        Text(phonemeLabel)
                            .font(.system(size: 10))
                    }
                    if phoneme.isEnsemble {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 7))
                    }
                }
                .foregroundColor(Theme.ivory.opacity(0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(flashGreen ? Theme.green : Theme.dark)
                .animation(.easeOut(duration: 0.3), value: flashGreen)
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
        .offset(y: bump)
        .onChange(of: isActive) { active in
            if active {
                bump = 3
                flashGreen = true
                withAnimation(.interpolatingSpring(stiffness: 1500, damping: 20)) {
                    bump = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    flashGreen = false
                }
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: phoneme.isEnsemble)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Phoneme Inspector Popover

struct PhonemeInspector: View {
    let phoneme: ChoirPhoneme
    var onUpdate: (UInt8?, UInt8?) -> Void
    var onToggleEnsemble: () -> Void

    @State private var consonant: UInt8
    @State private var vowel: UInt8

    init(phoneme: ChoirPhoneme, onUpdate: @escaping (UInt8?, UInt8?) -> Void, onToggleEnsemble: @escaping () -> Void) {
        self.phoneme = phoneme
        self.onUpdate = onUpdate
        self.onToggleEnsemble = onToggleEnsemble
        _consonant = State(initialValue: phoneme.consonantCC)
        _vowel = State(initialValue: phoneme.vowelCC)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(phoneme.text)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Text("Cons")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)
                Picker("", selection: $consonant) {
                    ForEach(Consonant.all) { c in
                        Text(c.name).tag(c.ccValue)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 80, maxWidth: .infinity)
                .controlSize(.small)
                .onChange(of: consonant) { val in onUpdate(val, nil) }
            }

            HStack {
                Text("Vowel")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)
                Picker("", selection: $vowel) {
                    ForEach(Vowel.all) { v in
                        Text(v.ccValue == 0 ? "Random" : "\(v.symbol) \(v.example)").tag(v.ccValue)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 80, maxWidth: .infinity)
                .controlSize(.small)
                .onChange(of: vowel) { val in onUpdate(nil, val) }
            }

            HStack {
                Text("Choir")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)
                Spacer()
                Image(systemName: "person.3.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Toggle("", isOn: Binding(
                    get: { phoneme.isEnsemble },
                    set: { _ in onToggleEnsemble() }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
            }
        }
        .frame(width: 136)
        .padding(12)
    }
}
