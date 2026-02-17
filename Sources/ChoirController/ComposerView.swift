import SwiftUI
import SwiftUIIntrospect
import AppKit
import ObjectiveC
// MARK: - Placeholder Cursor (notification observer — SwiftUI owns NSTextView's delegate)

private enum PlaceholderObserverKeys { static nonisolated(unsafe) var observer: UInt8 = 0 }

private final class PlaceholderCursorObserver {
    let placeholder: String
    weak var textView: NSTextView?
    private var token: NSObjectProtocol?

    init(placeholder: String, textView: NSTextView) {
        self.placeholder = placeholder
        self.textView = textView
    }

    func start() {
        let ph = placeholder
        token = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main) { note in
            guard let textView = note.object as? NSTextView else { return }
            Task { @MainActor in
                guard textView.string == ph,
                      textView.selectedRange().location != 0 else { return }
                textView.selectedRange = NSRange(location: 0, length: 0)
            }
        }
    }

    deinit {
        if let t = token { NotificationCenter.default.removeObserver(t) }
    }
}

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
    @ObservedObject var audioMonitor: AudioMonitorService
    var onDismiss: (() -> Void)? = nil
    @AppStorage("showKeyboard") private var showKeyboard = true
    @AppStorage("lyricStyle") private var lyricStyle: LyricStyle = .senryu
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextFocused: Bool

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
        let newlines = composerModel.inputText.components(separatedBy: "\n").count
        return max(1, min(3, newlines))
    }

    private static let placeholderText = "prompt or lyric"

    /// When user edits the placeholder (typing front/middle/end), extract only what they typed
    private static func extractTypedFromPlaceholder(_ newValue: String) -> String {
        let p = placeholderText
        if newValue == p { return "" }
        let fromReplace = newValue.replacingOccurrences(of: p, with: "")
        if fromReplace != newValue { return fromReplace }
        var inserted = ""
        var pi = p.startIndex
        for c in newValue {
            if pi < p.endIndex && p[pi] == c {
                pi = p.index(after: pi)
            } else {
                inserted.append(c)
            }
        }
        return inserted
    }

    var body: some View {
        let isPlaceholder = composerModel.inputText.isEmpty
        let hasText = !isPlaceholder && !composerModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let displayText = Binding(
            get: { composerModel.inputText.isEmpty ? Self.placeholderText : composerModel.inputText },
            set: { newValue in
                var resolved = Self.extractTypedFromPlaceholder(newValue)
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

        GeometryReader { geo in
        VStack(spacing: 0) {
            // MARK: Text Entry Area (centered, max 640)
            VStack(alignment: .center, spacing: 4) {
                Spacer()

                Text("What shall we sing?")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(hasText ? Theme.field : Theme.dark)
                    .padding(.bottom, 8)

                TextEditor(text: displayText)
                    .font(.system(size: 48, weight: .light))
                    .kerning(-1.0)
                    .foregroundColor(isPlaceholder ? Theme.fieldLight : Theme.text(colorScheme))
                    .tint(Theme.accent)
                    .scrollContentBackground(.hidden)
                    .focused($isTextFocused)
                    .multilineTextAlignment(.center)
                    .frame(height: CGFloat(editorLineCount) * lineHeight)
                    .introspect(.textEditor, on: .macOS(.v11, .v12, .v13, .v14, .v15, .v26)) { textView in
                        if objc_getAssociatedObject(textView, &PlaceholderObserverKeys.observer) == nil {
                            let obs = PlaceholderCursorObserver(placeholder: Self.placeholderText, textView: textView)
                            objc_setAssociatedObject(textView, &PlaceholderObserverKeys.observer, obs, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                            obs.start()
                        }
                        if textView.string == Self.placeholderText, textView.selectedRange().location != 0 {
                            textView.selectedRange = NSRange(location: 0, length: 0)
                        }
                    }

                HStack(spacing: 8) {
                    let btnHeight: CGFloat = 16
                    let summonDisabled = !hasText || composerModel.isProcessing
                    Button(action: {
                        Task { await composerModel.summonSong() }
                    }) {
                        Label(composerModel.isProcessing ? "Composing…" : lyricStyle.buttonLabel,
                              systemImage: composerModel.isProcessing ? "ellipsis" : "eyebrow")
                            .frame(height: btnHeight)
                    }
                    .buttonStyle(HoverPillStyle(colorScheme: colorScheme))
                    .disabled(summonDisabled)
                    .opacity(summonDisabled ? 0.3 : 1)
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
                        Task { await composerModel.extractPhonemes() }
                    }) {
                        Label(composerModel.isProcessing ? "Thinking…" : "Reveal Phonemes",
                              systemImage: composerModel.isProcessing ? "ellipsis" : "eye")
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
                                Text("Key of \(key.name)").tag(key)
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
                            Label(composerModel.isProcessing ? "Thinking…" : "Sync Phonemes",
                                  systemImage: composerModel.isProcessing ? "ellipsis" : "arrow.trianglehead.2.clockwise.rotate.90")
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
                            Label("Clear", systemImage: "trash")
                        }
                        .buttonStyle(HoverPillStyle(colorScheme: colorScheme))
                        .help("Clear phonemes")

                        Button(action: {
                            composerModel.copyToGrid(sequencer: sequencerModel)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                onDismiss?()
                            }
                        }) {
                            Label("Copy to Piano Roll", systemImage: "document.on.document")
                        }
                        .buttonStyle(HoverPillStyle(colorScheme: colorScheme))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Spacer()

                phonemeStrip(leadingPad: 0)
                    .onPreferenceChange(ChipCenterKey.self) { chipCenters = $0 }
                    .onChange(of: composerModel.isPlaying) { _, playing in
                        if playing, let cx = chipCenters[0] {
                            ballX = cx
                            ballY = 0
                        }
                    }
                    .onChange(of: composerModel.currentPlayIndex) { _, newIndex in
                        guard let idx = newIndex, let cx = chipCenters[idx] else { return }

                        let nextCx = chipCenters[idx + 1] ?? cx
                        let distance = abs(nextCx - cx)
                        let arcHeight = -min(100, max(32, max(distance, 30) * 0.7))
                        let fullArc = Double(composerModel.currentArcDuration) / 1000.0
                        let halfArc = fullArc * 0.5

                        let steepOut = Animation.timingCurve(0, 0, 0.05, 1, duration: halfArc)
                        let steepIn = Animation.timingCurve(0.95, 0, 1, 1, duration: halfArc)

                        withAnimation(steepOut) {
                            ballY = arcHeight
                        }
                        withAnimation(.linear(duration: halfArc)) {
                            ballX = (cx + nextCx) / 2
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + halfArc) {
                            withAnimation(steepIn) {
                                ballY = 0
                            }
                            withAnimation(.linear(duration: halfArc)) {
                                ballX = nextCx
                            }
                        }
                    }
                    .padding(.horizontal)

                Spacer()

                // Play button (centered)
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

            // Bottom keyboard divider
            if showKeyboard {
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
    }

    // MARK: - Phoneme Strip

    private func phonemeStrip(leadingPad: CGFloat = 0) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(composerModel.phonemes.enumerated()), id: \.element.id) { index, phoneme in
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
                            composerModel.playSinglePhoneme(phoneme, audioMonitor: audioMonitor)
                            inspectedPhonemeId = (inspectedPhonemeId == phoneme.id) ? nil : phoneme.id
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        composerModel.toggleEnsemble(phoneme)
                    }
                    .contextMenu {
                        Button("Insert Before") {
                            composerModel.insertPhoneme(relativeTo: phoneme, before: true)
                        }
                        Button("Insert After") {
                            composerModel.insertPhoneme(relativeTo: phoneme, before: false)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
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

                // Thumbs up at end of strip
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
            }
            .padding(.leading, leadingPad)
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
                onFind(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Phoneme Chip

enum WordPosition {
    case only      // single-chip word → fully rounded
    case first     // left rounded, right sharp
    case middle    // both sides sharp
    case last      // left sharp, right rounded
}

struct PhonemeChip: View {
    let phoneme: ChoirPhoneme
    let isActive: Bool
    var wordPosition: WordPosition = .only
    var onDelete: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var bump: CGFloat = 0
    @State private var flashGreen = false

    private var isRandomCons: Bool { phoneme.consonantCC == 0 }
    private var isRandomVowel: Bool { phoneme.vowelCC == 0 }

    private var phonemeLabel: String {
        let c = Consonant.all.first { $0.ccValue == phoneme.consonantCC }
        let v = Vowel.all.first { $0.ccValue == phoneme.vowelCC }
        let isNone = (c?.name == "None")
        let cPart = (isNone || isRandomCons) ? "" : (c?.name ?? "")
        let vPart = isRandomVowel ? "" : (v?.symbol ?? "")
        return cPart + vPart
    }

    var body: some View {
        VStack(spacing: 2) {
            if isRandomCons && isRandomVowel {
                Image(systemName: "shuffle")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.dark)
            } else {
                Text(phoneme.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Theme.dark)
            }

            if !phonemeLabel.isEmpty || isRandomCons || isRandomVowel || phoneme.isEnsemble {
                HStack(spacing: 3) {
                    if isRandomCons && !isRandomVowel {
                        Image(systemName: "shuffle")
                            .font(.system(size: 8))
                    }
                    if !phonemeLabel.isEmpty {
                        Text(phonemeLabel)
                            .font(.system(size: 10))
                    }
                    if isRandomVowel && !isRandomCons {
                        Image(systemName: "shuffle")
                            .font(.system(size: 8))
                    }
                    if phoneme.isEnsemble {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 7))
                    }
                }
                .foregroundColor(Theme.dark.opacity(0.4))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: wordPosition == .middle || wordPosition == .last ? 6 : 14,
                bottomLeadingRadius: wordPosition == .middle || wordPosition == .last ? 6 : 14,
                bottomTrailingRadius: wordPosition == .middle || wordPosition == .first ? 6 : 14,
                topTrailingRadius: wordPosition == .middle || wordPosition == .first ? 6 : 14
            )
            .fill(flashGreen ? Theme.green : Theme.fieldColor(colorScheme))
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
        .onChange(of: isActive) { _, active in
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
                .onChange(of: consonant) { _, val in onUpdate(val, nil) }
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
                .onChange(of: vowel) { _, val in onUpdate(nil, val) }
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
