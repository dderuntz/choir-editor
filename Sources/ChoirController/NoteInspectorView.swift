import SwiftUI

// MARK: - Callout Arrow Shape

/// Inspector background shape: rectangle with a cartouche arrow bump on the top edge
struct InspectorBubbleShape: Shape {
    var arrowX: CGFloat
    var arrowWidth: CGFloat = 44
    var arrowHeight: CGFloat = 10

    var animatableData: CGFloat {
        get { arrowX }
        set { arrowX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Rectangle body (top edge at arrowHeight offset, so arrow lives above)
        let bodyTop = rect.minY + arrowHeight

        // Start at top-left of body
        path.move(to: CGPoint(x: rect.minX, y: bodyTop))

        // Walk along top edge to the arrow
        let aLeft = arrowX - arrowWidth / 2
        let aRight = arrowX + arrowWidth / 2
        let clampedLeft = max(rect.minX, aLeft)
        let clampedRight = min(rect.maxX, aRight)

        path.addLine(to: CGPoint(x: clampedLeft, y: bodyTop))

        // Draw the cartouche arrow bump (SVG viewBox 46x11, flipped Y)
        if clampedRight > clampedLeft {
            let sx = (clampedRight - clampedLeft) / 46
            let sy = arrowHeight / 11
            func p(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: clampedLeft + x * sx, y: bodyTop - y * sy)
            }
            path.addLine(to: p(5.28, 0))
            path.addCurve(to: p(10.03, 0.5), control1: p(7.78, 0), control2: p(8.9, 0.06))
            path.addCurve(to: p(13.11, 2.85), control1: p(11.16, 0.94), control2: p(12.17, 1.92))
            path.addLine(to: p(15.76, 5.5))
            path.addLine(to: p(19.07, 8.81))
            path.addCurve(to: p(23, 10.5), control1: p(20.4, 10.19), control2: p(21.65, 10.5))
            path.addCurve(to: p(26.93, 8.81), control1: p(24.35, 10.5), control2: p(25.6, 10.2))
            path.addLine(to: p(30.24, 5.5))
            path.addLine(to: p(32.89, 2.85))
            path.addCurve(to: p(35.97, 0.5), control1: p(33.83, 1.92), control2: p(34.85, 0.94))
            path.addCurve(to: p(40.72, 0), control1: p(37.1, 0.06), control2: p(38.22, 0))
        }

        path.addLine(to: CGPoint(x: clampedRight, y: bodyTop))

        // Continue along top edge to top-right
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyTop))
        // Down right side
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Along bottom
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Close back to top-left
        path.closeSubpath()

        return path
    }
}

/// Apple cartouche arrow shape (from system popover SVG, flipped to point up)
struct CalloutArrow: Shape {
    func path(in rect: CGRect) -> Path {
        // Original SVG viewBox: 46 x 11, tip pointing down.
        // We flip Y so the tip points up.
        let sx = rect.width / 46
        let sy = rect.height / 11
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + (11 - y) * sy)
        }
        var path = Path()
        path.move(to: p(26.93, 8.81))
        path.addLine(to: p(30.24, 5.5))
        path.addLine(to: p(32.89, 2.85))
        path.addCurve(to: p(35.97, 0.5), control1: p(33.83, 1.92), control2: p(34.85, 0.94))
        path.addCurve(to: p(40.72, 0), control1: p(37.1, 0.06), control2: p(38.22, 0))
        path.addLine(to: p(46, 0))
        path.addLine(to: p(0, 0))
        path.addLine(to: p(5.28, 0))
        path.addCurve(to: p(10.03, 0.5), control1: p(7.78, 0), control2: p(8.9, 0.06))
        path.addCurve(to: p(13.11, 2.85), control1: p(11.16, 0.94), control2: p(12.17, 1.92))
        path.addLine(to: p(15.76, 5.5))
        path.addLine(to: p(19.07, 8.81))
        path.addCurve(to: p(23, 10.5), control1: p(20.4, 10.19), control2: p(21.65, 10.5))
        path.addCurve(to: p(26.93, 8.81), control1: p(24.35, 10.5), control2: p(25.6, 10.2))
        path.closeSubpath()
        return path
    }
}

// MARK: - Note Popover Inspector (attached to selected note, like PhonemeInspector)

struct NotePopoverInspector: View {
    let note: SequencerNote
    let groupCount: Int
    var onUpdate: (SequencerNote) -> Void
    var onPlay: (SequencerNote) -> Void
    var onDelete: () -> Void

    @State private var consonant: UInt8
    @State private var vowel: UInt8
    @State private var velocity: Double
    @State private var vibrato: Double
    @State private var reverb: Double
    @State private var isSyncing = true

    init(note: SequencerNote, groupCount: Int = 1, onUpdate: @escaping (SequencerNote) -> Void, onPlay: @escaping (SequencerNote) -> Void, onDelete: @escaping () -> Void) {
        self.note = note
        self.groupCount = groupCount
        self.onUpdate = onUpdate
        self.onPlay = onPlay
        self.onDelete = onDelete
        _consonant = State(initialValue: note.consonant)
        _vowel = State(initialValue: note.vowel)
        _velocity = State(initialValue: Double(note.velocity))
        _vibrato = State(initialValue: Double(note.vibrato))
        _reverb = State(initialValue: Double(note.reverb))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            if groupCount > 1 {
                Text("\(groupCount) notes")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 2) {
                    Text(PitchConstants.noteName(for: note.pitch))
                        .font(.system(size: 13, weight: .medium))
                    Text("Beat \(Int(note.startBeat + 1))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            // Consonant
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
                .onChange(of: consonant) { pushUpdate() }
            }

            // Vowel
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
                .onChange(of: vowel) { pushUpdate() }
            }

            // Velocity
            compactSlider(label: "Vel", value: $velocity, range: 1...127)

            // Vibrato
            compactSlider(label: "Vib", value: $vibrato, range: 0...127)

            // Reverb
            compactSlider(label: "Rev", value: $reverb, range: 0...127)

            Divider()

            // Actions
            HStack {
                Button(action: { onPlay(currentNote()) }) {
                    Label("Test", systemImage: "ear")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(width: 170)
        .padding(12)
        .onAppear {
            DispatchQueue.main.async { isSyncing = false }
        }
    }

    private func compactSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)
            Text("\(Int(value.wrappedValue))")
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
            Slider(value: value, in: range)
                .controlSize(.small)
                .onChange(of: value.wrappedValue) { pushUpdate() }
        }
    }

    private func currentNote() -> SequencerNote {
        var n = note
        n.consonant = consonant
        n.vowel = vowel
        n.velocity = UInt8(velocity)
        n.vibrato = UInt8(vibrato)
        n.reverb = UInt8(reverb)
        return n
    }

    private func pushUpdate() {
        guard !isSyncing else { return }
        onUpdate(currentNote())
    }
}

// MARK: - Note Inspector (bottom bar)

struct NoteInspectorView: View {
    let note: SequencerNote
    var arrowX: CGFloat = 0  // horizontal position of arrow from leading edge
    var groupCount: Int = 1  // number of selected notes (1 = single)
    var onUpdate: (SequencerNote) -> Void
    var onPlay: (SequencerNote) -> Void
    var noteDurationSeconds: Double = 1.0
    var onDelete: () -> Void

    // Local editing state synced from the note (view is recreated via .id() on selection change)
    @State private var consonant: UInt8 = 125
    @State private var vowel: UInt8 = 0
    @State private var velocity: Double = 100
    @State private var vibrato: Double = 64
    @State private var reverb: Double = 32
    @State private var isSyncing = true  // suppress pushUpdate during initial sync
    @State private var isTesting = false

    private var isBlackKey: Bool { PitchConstants.isBlackKey(note.pitch) }
    private var bg: Color { isBlackKey ? Theme.dark : Theme.ivory }
    private var fg: Color { isBlackKey ? Theme.ivory : Theme.dark }
    private var fgDim: Color { fg.opacity(0.5) }
    private var dividerColor: Color { fg.opacity(0.15) }

    private var phonemeLabel: String {
        let c = Consonant.all.first { $0.ccValue == consonant }
        let v = Vowel.all.first { $0.ccValue == vowel }
        let isRandomCons = (c?.name == "Random")
        let isNoneCons = (c?.name == "None")
        let isRandomVowel = (v?.ccValue == 0)

        if isRandomCons && isRandomVowel { return "Random" }

        var parts = ""
        if !isRandomCons && !isNoneCons { parts += c?.name ?? "" }
        if isRandomCons { parts += "?" }
        if !isRandomVowel { parts += v?.symbol ?? "" }
        else if !isRandomCons { parts += "?" }
        return parts.isEmpty ? "—" : parts
    }

    var body: some View {
        HStack(spacing: 16) {
            // Note info
            VStack(alignment: .leading, spacing: 2) {
                if groupCount > 1 {
                    Text("\(groupCount) notes")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.accent)
                } else {
                    Text(phonemeLabel)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(fg)
                    Text("\(PitchConstants.noteName(for: note.pitch)) · \(beatLabel(note.startBeat))")
                        .font(.caption2)
                        .foregroundColor(fgDim)
                        .monospacedDigit()
                }
            }
            .frame(minWidth: 55, alignment: .leading)

            dividerColor.frame(width: 1, height: 40)

            // Consonant picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Consonant")
                    .font(.caption2)
                    .foregroundColor(fgDim)
                Picker("", selection: $consonant) {
                    ForEach(Consonant.all) { c in
                        Text(c.name).tag(c.ccValue)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
                .controlSize(.small)
                .tint(fg)
                .accentColor(fg)
                .onChange(of: consonant) { pushUpdate() }
            }

            // Vowel picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Vowel")
                    .font(.caption2)
                    .foregroundColor(fgDim)
                Picker("", selection: $vowel) {
                    ForEach(Vowel.all) { v in
                        Text(v.ccValue == 0 ? "Random" : "\(v.symbol) \(v.example)").tag(v.ccValue)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .controlSize(.small)
                .tint(fg)
                .accentColor(fg)
                .onChange(of: vowel) { pushUpdate() }
            }

            // Velocity
            inspectorDial(label: "Velocity", value: $velocity, range: 1...127)

            // Vibrato
            inspectorDial(label: "Vibrato", value: $vibrato, range: 0...127)

            // Reverb
            inspectorDial(label: "Reverb", value: $reverb, range: 0...127)

            Spacer()

            // Test button
            Button(action: {
                onPlay(currentNote())
                isTesting = true
                DispatchQueue.main.asyncAfter(deadline: .now() + noteDurationSeconds) {
                    isTesting = false
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "ear")
                    Text("Test")
                }
                .font(Theme.toolbarFont)
                .foregroundColor(Theme.dark)
                .padding(.horizontal, Theme.buttonPaddingH)
                .padding(.vertical, Theme.buttonPaddingV)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isTesting ? Theme.green : Theme.accent)
                )
                .animation(.easeInOut(duration: 0.15), value: isTesting)
            }
            .buttonStyle(.plain)

            // Delete
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundColor(fg.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .frame(height: 80) // 70 body + 10 arrow
        .padding(.top, 10) // reserve space for arrow above body
        .background(.ultraThinMaterial, in: InspectorBubbleShape(arrowX: arrowX))
        .glassEffect(in: InspectorBubbleShape(arrowX: arrowX))
        .environment(\.colorScheme, isBlackKey ? .dark : .light)
        .onAppear { syncFromNote() }
    }

    private func syncFromNote() {
        isSyncing = true
        consonant = note.consonant
        vowel = note.vowel
        velocity = Double(note.velocity)
        vibrato = Double(note.vibrato)
        reverb = Double(note.reverb)
        // Allow onChange to settle before re-enabling pushUpdate
        DispatchQueue.main.async { isSyncing = false }
    }

    private func currentNote() -> SequencerNote {
        var n = note
        n.consonant = consonant
        n.vowel = vowel
        n.velocity = UInt8(velocity)
        n.vibrato = UInt8(vibrato)
        n.reverb = UInt8(reverb)
        return n
    }

    private func pushUpdate() {
        guard !isSyncing else { return }
        onUpdate(currentNote())
    }

    /// Format beat as "Beat bar.sixteenth" (1-indexed, e.g. "Beat 2.3")
    private func beatLabel(_ beat: Double) -> String {
        let wholeBeat = Int(beat)
        let sixteenth = Int(round((beat - Double(wholeBeat)) * 4)) + 1
        return "Beat \(wholeBeat + 1).\(sixteenth)"
    }

    private func inspectorDial(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let span = range.upperBound - range.lowerBound
        let normalized = Binding<Double>(
            get: { span > 0 ? (value.wrappedValue - range.lowerBound) / span : 0 },
            set: { value.wrappedValue = round(range.lowerBound + $0 * span) }
        )
        return VStack(spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundColor(fgDim)
            CircularSlider(normalized: normalized)
                .frame(width: 32, height: 32)
                .onChange(of: value.wrappedValue) { pushUpdate() }
            Text("\(Int(value.wrappedValue))")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(fg)
                .monospacedDigit()
        }
        .frame(width: 56)
    }
}
