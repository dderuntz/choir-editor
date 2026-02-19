import SwiftUI
import AppKit

// MARK: - Chip Position Tracking

struct ChipCenterKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}


struct ComposerView: View {
    @EnvironmentObject var composerModel: ComposerModel
    @EnvironmentObject var sequencerModel: SequencerModel
    var midiService: MidiService
    @ObservedObject var audioMonitor: AudioMonitorService
    var onDismiss: (() -> Void)? = nil
    @AppStorage("showKeyboard") private var showKeyboard = true
    @AppStorage("lyricStyle") private var lyricStyle: LyricStyle = .senryu
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextFocused: Bool

    // Onboarding
    @EnvironmentObject var onboarding: OnboardingManager
    @State private var showRecomposeTip = false
    @State private var recomposeTipTimer: Timer?
    @State private var showRevealHint = false
    @State private var revealHintTimer: Timer?
    @State private var showPhonemeGuide = false
    @State private var showCopyToRollHint = false
    @State private var copyToRollHintTimer: Timer?

    // Bouncing ball state
    @State private var chipCenters: [Int: CGFloat] = [:]
    @State private var ballX: CGFloat = 0
    @State private var ballY: CGFloat = 0  // 0 = chip level, negative = above
    @State private var pageLeadingX: CGFloat = 0  // content-space X of viewport's left edge
    @State private var nsScrollView: NSScrollView?

    // Chip inspector
    @State private var inspectedPhonemeId: UUID? = nil

    private var lineHeight: CGFloat { 62 }

    private var editorLineCount: Int {
        let text = composerModel.inputText.isEmpty ? " " : composerModel.inputText
        let font = NSFont.systemFont(ofSize: 48, weight: .light)
        let maxWidth: CGFloat = 600 // slightly less than container's 640 for padding

        let attrString = NSAttributedString(string: text, attributes: [.font: font])
        let boundingRect = attrString.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let visualLines = Int(ceil(boundingRect.height / lineHeight))
        return max(1, min(3, visualLines))
    }

    private static let placeholderText = "type here"

    /// Binding that enforces max 3 lines and 120 characters
    private var limitedInputText: Binding<String> {
        Binding(
            get: { composerModel.inputText },
            set: { newValue in
                var resolved = newValue
                let lines = resolved.components(separatedBy: "\n")
                if lines.count > 3 {
                    resolved = lines.prefix(3).joined(separator: "\n")
                }
                if resolved.count > 120 {
                    resolved = String(resolved.prefix(120))
                }
                composerModel.inputText = resolved
            }
        )
    }

    /// Animate the up-phase of a bounce
    private func animateBounceUp(chipIndex: Int, chipX: CGFloat) {
        let isLastBounce = composerModel.currentBounceIndex >= composerModel.currentBounceCount - 1
        let nextCx = isLastBounce ? (chipCenters[chipIndex + 1] ?? chipX) : chipX
        let distance = abs(nextCx - chipX)

        let arcHeight: CGFloat
        if isLastBounce {
            arcHeight = -min(100, max(32, max(distance, 30) * 0.7))
        } else {
            arcHeight = -60
        }

        let halfArc = Double(composerModel.currentArcDuration) / 1000.0 * 0.5
        let steepOut = Animation.timingCurve(0, 0, 0.05, 1, duration: halfArc)

        withAnimation(steepOut) {
            ballY = arcHeight
        }
        if isLastBounce {
            withAnimation(.linear(duration: halfArc)) {
                ballX = (chipX + nextCx) / 2
            }
        }
    }

    /// Animate the down-phase of a bounce
    private func animateBounceDown(chipIndex: Int, chipX: CGFloat) {
        let isLastBounce = composerModel.currentBounceIndex >= composerModel.currentBounceCount - 1
        let nextCx = isLastBounce ? (chipCenters[chipIndex + 1] ?? chipX) : chipX

        let halfArc = Double(composerModel.currentArcDuration) / 1000.0 * 0.5
        let steepIn = Animation.timingCurve(0.95, 0, 1, 1, duration: halfArc)

        withAnimation(steepIn) {
            ballY = 0
        }
        if isLastBounce {
            withAnimation(.linear(duration: halfArc)) {
                ballX = nextCx
            }
        }
    }

    var body: some View {
        let hasText = !composerModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        GeometryReader { geo in
        VStack(spacing: 0) {
            // MARK: Text Entry Area (centered, max 640)
            VStack(alignment: .center, spacing: 4) {
                Spacer()

                Text("composer.prompt", bundle: localizedBundle)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(promptColor(hasText: hasText))
                    .padding(.bottom, 8)

                ZStack {
                    // Placeholder overlay
                    if composerModel.inputText.isEmpty {
                        Text(Self.placeholderText)
                            .font(.system(size: 48, weight: .light))
                            .kerning(-1.0)
                            .foregroundColor(Theme.fieldColor(colorScheme))
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: limitedInputText)
                        .font(.system(size: 48, weight: .light))
                        .kerning(-1.0)
                        .foregroundColor(Theme.text(colorScheme))
                        .tint(Theme.accent)
                        .scrollContentBackground(.hidden)
                        .focused($isTextFocused)
                        .multilineTextAlignment(.center)
                }
                .frame(height: CGFloat(editorLineCount) * lineHeight)
                .popover(isPresented: Binding(
                    get: { onboarding.showChipsModal },
                    set: { if !$0 { onboarding.dismissChipsModal() } }
                )) {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "eyebrow")
                                .font(.system(size: 13, weight: .semibold))
                            Text("onboarding.welcome.title", bundle: localizedBundle)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text("onboarding.welcome.body", bundle: localizedBundle)
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(Theme.text(colorScheme))
                    .padding()
                    .frame(width: 280)
                }

                HStack(spacing: 8) {
                    let btnHeight: CGFloat = 16
                    let summonDisabled = !hasText || composerModel.isProcessing
                    Button(action: {
                        Task { await composerModel.summonSong() }
                    }) {
                        Label { Text(composerModel.isProcessing ? L("composer.composing") : lyricStyle.localizedButtonLabel) } icon: { Image(systemName: composerModel.isProcessing ? "ellipsis" : "eyebrow") }
                            .frame(height: btnHeight)
                    }
                    .buttonStyle(HoverPillStyle(colorScheme: colorScheme))
                    .disabled(summonDisabled)
                    .opacity(summonDisabled ? 0.3 : 1)
                    .popover(isPresented: $showRecomposeTip) {
                        Text("onboarding.composer.recomposeTip", bundle: localizedBundle)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text(colorScheme))
                            .padding()
                            .frame(width: 260)
                    }
                }
                .padding(.top, -2)

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

                Spacer()
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, maxHeight: composerModel.phonemes.isEmpty ? (geo.size.height - 52) * 0.67 : (geo.size.height - 52) * 0.5)
            .padding(.horizontal)
            .padding(.bottom, 20)
            .overlay(alignment: .topTrailing) {
                if composerModel.canUndo {
                    Button(action: {
                        composerModel.undo()
                    }) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(HoverPillStyle(colorScheme: colorScheme))
                    .padding(.top, 8)
                    .padding(.trailing, 16)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: composerModel.canUndo)

            // MARK: Empty state — Reveal Phonemes
            if composerModel.phonemes.isEmpty {
                let revealDisabled = !hasText || composerModel.isProcessing
                VStack {
                    Spacer()
                    Button(action: {
                        showRevealHint = false
                        onboarding.hasSeenRevealHint = true
                        revealHintTimer?.invalidate()
                        Task { await composerModel.extractPhonemes() }
                    }) {
                        Label { Text(composerModel.isProcessing ? L("composer.thinking") : L("composer.revealPhonemes")) } icon: { Image(systemName: composerModel.isProcessing ? "ellipsis" : "eye") }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(revealDisabled ? Theme.field : Theme.dark)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(revealDisabled ? Theme.fieldColor(colorScheme) : Theme.accent)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(revealDisabled)
                    .help("Turn words into sounds")
                    .popover(isPresented: $showRevealHint) {
                        Text("composer.revealHint", bundle: localizedBundle)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text(colorScheme))
                            .padding()
                            .frame(width: 240)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: (geo.size.height - 52) * 0.33)
            }

            // MARK: Phoneme Area (full width)
            if !composerModel.phonemes.isEmpty {
                // Hairline divider
                Theme.fieldColor(colorScheme)
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                // Actions bar (near top divider)
                ZStack {
                    // Left: Key/Scale
                    HStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .foregroundColor(Theme.field)

                        Picker("", selection: $sequencerModel.musicalKey) {
                            ForEach(MusicalKey.allCases) { key in
                                Text(L("roll.keyOf \(key.name)")).tag(key)
                            }
                        }
                        .labelsHidden()
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .tint(Theme.field)
                        .foregroundStyle(Theme.field)

                        Picker("", selection: $sequencerModel.scaleType) {
                            ForEach(ScaleType.allCases) { scale in
                                Text("\(scale.rawValue) Scale").tag(scale)
                            }
                        }
                        .labelsHidden()
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .tint(Theme.field)
                        .foregroundStyle(Theme.field)

                        Spacer()
                    }

                    // Center: Sync Phonemes (when needsSync)
                    if composerModel.needsSync {
                        Button(action: {
                            Task { await composerModel.extractPhonemes() }
                        }) {
                            Label { Text(composerModel.isProcessing ? L("composer.thinking") : L("composer.syncPhonemes")) } icon: { Image(systemName: composerModel.isProcessing ? "ellipsis" : "arrow.trianglehead.2.clockwise.rotate.90") }
                        }
                        .buttonStyle(HoverPillStyle(colorScheme: colorScheme, textColor: Theme.accent))
                        .disabled(composerModel.isProcessing)
                        .opacity(composerModel.isProcessing ? 0.4 : 1)
                    }

                    // Right: Clear, Copy to Piano Roll
                    HStack(spacing: 12) {
                        Spacer()

                        Button(action: {
                            composerModel.stop()
                            composerModel.clearPhonemes()
                        }) {
                            Label { Text("composer.clear", bundle: localizedBundle) } icon: { Image(systemName: "trash") }
                        }
                        .buttonStyle(HoverPillStyle(colorScheme: colorScheme))
                        .help(L("composer.clearPhonemes"))

                        Button(action: {
                            showCopyToRollHint = false
                            copyToRollHintTimer?.invalidate()
                            onboarding.hasSeenCopyToRollHint = true
                            composerModel.copyToGrid(sequencer: sequencerModel)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                onDismiss?()
                            }
                            // Trigger scale guide invite + piano roll tip tour if unseen
                            if !onboarding.hasSeenScaleGuideInvite || !onboarding.hasSeenTransportTip {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    NotificationCenter.default.post(name: .rollCopiedFromComposer, object: nil)
                                }
                            }
                        }) {
                            Label { Text("composer.copyToRoll", bundle: localizedBundle) } icon: { Image(systemName: "document.on.document") }
                        }
                        .buttonStyle(HoverPillStyle(colorScheme: colorScheme))
                        .popover(isPresented: $showCopyToRollHint) {
                            Text("composer.copyToRollHint", bundle: localizedBundle)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.text(colorScheme))
                                .padding()
                                .frame(width: 240)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Spacer()

                phonemeStrip()
                    .popover(isPresented: $showPhonemeGuide) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("composer.phonemeGuide.title", bundle: localizedBundle)
                                .font(.system(size: 13, weight: .semibold))
                            Text("composer.phonemeGuide.body", bundle: localizedBundle)
                                .font(.system(size: 12))
                        }
                        .foregroundColor(Theme.text(colorScheme))
                        .padding()
                        .frame(width: 280)
                    }
                    .onPreferenceChange(ChipCenterKey.self) { chipCenters = $0 }
                    .onChange(of: composerModel.isPlaying) { _, playing in
                        if playing, let cx = chipCenters[0] {
                            ballX = cx
                            ballY = 0
                        }
                    }
                    .onChange(of: composerModel.currentPlayIndex) { _, newIndex in
                        guard let idx = newIndex, let cx = chipCenters[idx] else { return }
                        animateBounceUp(chipIndex: idx, chipX: cx)
                    }
                    .onChange(of: composerModel.currentBounceIndex) { oldBounce, newBounce in
                        guard newBounce > oldBounce,
                              let idx = composerModel.currentPlayIndex,
                              let cx = chipCenters[idx] else { return }
                        animateBounceUp(chipIndex: idx, chipX: cx)
                    }
                    .onChange(of: composerModel.bouncePhase) { _, newPhase in
                        guard newPhase == 1,
                              let idx = composerModel.currentPlayIndex,
                              let cx = chipCenters[idx] else { return }
                        animateBounceDown(chipIndex: idx, chipX: cx)
                    }
                    .padding(.horizontal)

                Spacer()

                // Play button (centered)
                Button(action: {
                    if composerModel.isPlaying {
                        composerModel.stop(midiService: midiService)
                        audioMonitor.stopNote(note: 60)
                    } else {
                        composerModel.playPhonemes(audioMonitor: audioMonitor, midiService: midiService)
                    }
                }) {
                    Label { Text(composerModel.isPlaying ? L("composer.stop") : L("composer.play")) } icon: { Image(systemName: composerModel.isPlaying ? "stop.fill" : "play.fill") }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.dark)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(composerModel.isPlaying ? Theme.green : Theme.accent)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Spacer()
            }

            // Bottom keyboard divider (keyboard hidden in composer until chips exist)
            if showKeyboard && !composerModel.phonemes.isEmpty {
                Theme.dark.opacity(0.15)
                    .frame(height: 1)
            }
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg(colorScheme))
        .onAppear {
            composerModel.musicalKey = sequencerModel.musicalKey
            composerModel.scaleType = sequencerModel.scaleType
            DispatchQueue.main.async { isTextFocused = true }
        }
        .onChange(of: sequencerModel.musicalKey) { composerModel.musicalKey = sequencerModel.musicalKey }
        .onChange(of: sequencerModel.scaleType) { composerModel.scaleType = sequencerModel.scaleType }
        .onChange(of: appLanguage) {
            let available = LyricStyle.styles(for: appLanguage)
            if !available.contains(lyricStyle), let first = available.first {
                lyricStyle = first
            }
        }
        // MARK: Onboarding — Recompose tip + Reveal Phonemes hint timer
        .onChange(of: composerModel.inputText) { _, newText in
            let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[onboarding] inputText changed, trimmed length: \(trimmed.count), phonemes: \(composerModel.phonemes.count), hasSeenRecomposeTip: \(onboarding.hasSeenRecomposeTip)")

            // Cancel any existing timers
            recomposeTipTimer?.invalidate()
            recomposeTipTimer = nil
            revealHintTimer?.invalidate()
            revealHintTimer = nil

            // Start timer if text is non-empty, no phonemes, and tips not yet seen
            let needsRecomposeTip = !onboarding.hasSeenRecomposeTip
            let needsRevealHint = !onboarding.hasSeenRevealHint
            if !trimmed.isEmpty && composerModel.phonemes.isEmpty && (needsRecomposeTip || needsRevealHint) {
                let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        // Re-check conditions at fire time
                        guard !composerModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && composerModel.phonemes.isEmpty else { return }
                        if !onboarding.hasSeenRecomposeTip {
                            print("[onboarding] Showing recompose tip popover")
                            withAnimation { showRecomposeTip = true }
                        } else if !onboarding.hasSeenRevealHint {
                            print("[onboarding] Showing reveal hint popover")
                            withAnimation { showRevealHint = true }
                        }
                    }
                }
                if needsRecomposeTip {
                    recomposeTipTimer = timer
                } else {
                    revealHintTimer = timer
                }
            }
        }
        // MARK: Onboarding — Recompose tip dismissed → Reveal hint
        .onChange(of: showRecomposeTip) { wasShowing, isShowing in
            if wasShowing && !isShowing {
                onboarding.hasSeenRecomposeTip = true
                // Immediately show reveal hint
                if !onboarding.hasSeenRevealHint && composerModel.phonemes.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation { showRevealHint = true }
                    }
                }
            }
        }
        // MARK: Onboarding — Post-reveal phoneme guide
        .onChange(of: composerModel.phonemes.count) { oldCount, newCount in
            print("[onboarding] phonemes count changed: \(oldCount) → \(newCount), hasSeenPhonemeGuide: \(onboarding.hasSeenPhonemeRevealGuide)")
            if oldCount == 0 && newCount > 0 && !onboarding.hasSeenPhonemeRevealGuide {
                // Dismiss reveal hint if still showing
                showRevealHint = false
                revealHintTimer?.invalidate()
                revealHintTimer = nil
                // Show phoneme guide after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    print("[onboarding] Showing phoneme guide popover")
                    withAnimation { showPhonemeGuide = true }
                }
            }
        }
        // MARK: Onboarding — Copy to Piano Roll hint (after phoneme guide dismissed)
        .onChange(of: showPhonemeGuide) { wasShowing, isShowing in
            // User just dismissed the phoneme guide
            if wasShowing && !isShowing {
                onboarding.hasSeenPhonemeRevealGuide = true
            }
            if wasShowing && !isShowing && !onboarding.hasSeenCopyToRollHint {
                copyToRollHintTimer?.invalidate()
                copyToRollHintTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        if !composerModel.phonemes.isEmpty && !onboarding.hasSeenCopyToRollHint {
                            print("[onboarding] Showing copy-to-roll hint")
                            withAnimation { showCopyToRollHint = true }
                            onboarding.hasSeenCopyToRollHint = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func promptColor(hasText: Bool) -> Color {
        let base: Color = colorScheme == .dark ? Theme.ivory : Theme.dark
        return hasText ? base.opacity(0.4) : base
    }

    // MARK: - Phoneme Strip

    private func phonemeStrip() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(composerModel.phonemes.enumerated()), id: \.offset) { index, phoneme in
                    let isNewWord = index > 0 && phoneme.wordIndex != composerModel.phonemes[index - 1].wordIndex
                    let isLastOfWord = index == composerModel.phonemes.count - 1 || composerModel.phonemes[index + 1].wordIndex != phoneme.wordIndex
                    let isFirstOfWord = index == 0 || isNewWord
                    let position: WordPosition = {
                        if isFirstOfWord && isLastOfWord { return .only }
                        if isFirstOfWord { return .first }
                        if isLastOfWord { return .last }
                        return .middle
                    }()
                    PhonemeChip(
                        phoneme: phoneme,
                        isActive: composerModel.currentPlayIndex == index,
                        wordPosition: position,
                        onDelete: { composerModel.deletePhoneme(phoneme) }
                    )
                    .padding(.leading, index == 0 ? 0 : isNewWord ? 12 : 1)
                    .id(index)
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
                            composerModel.playSinglePhoneme(phoneme, audioMonitor: audioMonitor, midiService: midiService)
                            inspectedPhonemeId = (inspectedPhonemeId == phoneme.id) ? nil : phoneme.id
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        composerModel.toggleEnsemble(phoneme)
                    }
                    .contextMenu {
                        Button(L("composer.insertBefore")) {
                            composerModel.insertPhoneme(relativeTo: phoneme, before: true)
                        }
                        Button(L("composer.insertAfter")) {
                            composerModel.insertPhoneme(relativeTo: phoneme, before: false)
                        }
                        Divider()
                        Button(L("roll.delete"), role: .destructive) {
                            composerModel.deletePhoneme(phoneme)
                        }
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

            }
            .padding(.top, 40)
            .frame(minWidth: nsScrollView?.frame.width ?? 0, alignment: .center)
            .coordinateSpace(name: "phonemeStrip")
            .overlay(alignment: .topLeading) {
                // Bouncing ball — lives inside scroll content so it scrolls with chips
                if composerModel.isPlaying {
                    Circle()
                        .fill(Theme.green)
                        .frame(width: 14, height: 14)
                        .offset(x: ballX - 7, y: ballY + 26)
                        .allowsHitTesting(false)
                }
            }
            .background(ScrollViewFinder { self.nsScrollView = $0 })
        }
        .onChange(of: composerModel.currentPlayIndex) { _, idx in
            guard let idx = idx, let chipX = chipCenters[idx] else { return }
            let viewWidth = nsScrollView?.frame.width ?? 800
            let ballInViewport = chipX - pageLeadingX

            if ballInViewport > viewWidth * 0.75 {
                pageLeadingX = chipX - viewWidth * 0.15
                animateScroll(to: pageLeadingX, duration: 1.5)
            }
        }
        .onChange(of: composerModel.isPlaying) { _, playing in
            if !playing {
                pageLeadingX = 0
                animateScroll(to: 0, duration: 1.5)
            }
        }
        .modifier(ScrollClipDisabledModifier())
    }

    private func animateScroll(to offsetX: CGFloat, duration: TimeInterval) {
        guard let scrollView = nsScrollView else {
            print("[animateScroll] nsScrollView is nil!")
            return
        }
        print("[animateScroll] scrolling to \(offsetX) over \(duration)s")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: offsetX, y: 0))
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

// MARK: - ScrollView Finder


private struct ScrollViewFinder: NSViewRepresentable {
    var onFind: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                // Walk up to the Composer's hosting view so scroll wheel works anywhere in the panel
                var parent: NSView? = scrollView.superview
                while let p = parent?.superview { parent = p }
                VerticalToHorizontalScroller.install(on: scrollView, parentView: parent)
                onFind(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Intercepts vertical scroll-wheel events on a horizontal NSScrollView
/// and converts them to horizontal scrolling.
private final class VerticalToHorizontalScroller {
    private var monitor: Any?
    private weak var scrollView: NSScrollView?

    /// parentView: the enclosing Composer view — scroll wheel anywhere in it scrolls the chips
    static func install(on scrollView: NSScrollView, parentView: NSView? = nil) {
        let scroller = VerticalToHorizontalScroller()
        scroller.scrollView = scrollView
        scroller.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let sv = scroller.scrollView,
                  event.deltaX == 0, event.deltaY != 0,
                  !event.modifierFlags.contains(.shift) else {
                return event  // pass through shift+scroll (already works natively)
            }
            // Hit-test against the parent Composer view (or scroll view if no parent)
            let hitView = parentView ?? sv
            let point = hitView.convert(event.locationInWindow, from: nil)
            guard hitView.bounds.contains(point) else { return event }

            // Convert vertical scroll → horizontal, matching native shift+scroll direction and speed
            guard let doc = sv.documentView else { return event }
            let current = sv.contentView.bounds.origin
            let maxX = doc.frame.width - sv.contentView.bounds.width
            let newX = max(0, min(maxX, current.x - event.scrollingDeltaY * 4))
            sv.contentView.scroll(to: NSPoint(x: newX, y: current.y))
            sv.reflectScrolledClipView(sv.contentView)
            return nil  // consume the original vertical event
        }
        // Prevent deallocation by attaching to the scroll view
        objc_setAssociatedObject(scrollView, "vtoh", scroller, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - Availability Wrapper

private struct ScrollClipDisabledModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.scrollClipDisabled()
        } else {
            content
        }
    }
}
