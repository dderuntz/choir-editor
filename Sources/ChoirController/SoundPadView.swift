import SwiftUI
import AppKit

/// A grid pad for exploring vowel/consonant combinations
struct SoundPadView: View {
    @ObservedObject var midiService: MidiService
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedConsonant: UInt8 = 125  // None
    @State private var selectedVowel: UInt8 = 16       // ai (buy)
    @State private var testNote: UInt8 = 60            // Middle C
    @State private var testVelocity: UInt8 = 100
    @State private var isPlaying = false
    
    // CC Discovery
    @State private var discoveryCC: Double = 5
    @State private var discoveryCCValue: Double = 64
    @State private var discoveryDuration: Double = 1.5
    @State private var isDiscoveryPlaying: Bool = false
    @State private var isSweeping: Bool = false
    @State private var isSweepingCCs: Bool = false
    @State private var sweepValue: Int = 0
    @State private var sweepStep: Int = 1
    
    // Pitch bend
    @State private var pitchBendValue: Double = 0
    
    // Packet log
    @State private var lastPacketLog: String = "READY"
    
    // Musical pattern for sweeps
    let sweepPattern: [UInt8] = [
        60, 64, 67, 72, 69, 72, 76, 65, 69, 72, 67, 71, 74, 72, 67, 64, 60
    ]
    @State private var sweepPatternIndex: Int = 0
    
    private var hasModifiedDefaults: Bool {
        testNote != 60 || testVelocity != 100 || pitchBendValue != 0
    }
    
    /// Scheme-aware text color for the explorer (swaps ivory/dark)
    private var txt: Color { Theme.text(colorScheme) }
    /// Scheme-aware dimmed text
    private var txtDim: Color { txt.opacity(0.6) }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header bar
            HStack {
                Text("Explorer")
                    .font(.system(size: 56, weight: .ultraLight))
                    .kerning(-1.4)
                    .foregroundColor(txt)
                Spacer()
                if hasModifiedDefaults {
                    pillButton("Reset") {
                        pitchBendValue = 0
                        discoveryCC = 5
                        discoveryCCValue = 64
                        discoveryDuration = 1.5
                        selectedConsonant = 125
                        selectedVowel = 16
                        testNote = 60
                        testVelocity = 100
                        lastPacketLog = "Reset to defaults"
                    }
                }
                Button(action: { isPresented = false }) {
                    Text("Done")
                        .font(Theme.buttonFont)
                        .fontWeight(Theme.buttonWeight)
                        .foregroundColor(Theme.bg(colorScheme))
                        .padding(.horizontal, Theme.buttonPaddingH)
                        .padding(.vertical, Theme.buttonPaddingV)
                        .background(txt)
                        .cornerRadius(Theme.buttonRadius)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(Theme.bg(colorScheme))
            
            // MARK: Field area (green-gray)
            VStack(spacing: 0) {
                // Two-column grid: Consonants | Vowels
                HStack(alignment: .top, spacing: 16) {
                    // Consonants
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Consonants")
                            .font(.caption)
                            .foregroundColor(txtDim)
                            .padding(.bottom, 12)
                        
                        phonemeGrid(items: Consonant.all.map { PhonemeItem(id: $0.id, label: $0.name, subtitle: "\($0.ccValue)", ccValue: $0.ccValue) },
                                    selected: selectedConsonant,
                                    columns: 5) { value in
                            selectedConsonant = value
                            startSound()
                        } onRelease: {
                            stopSound()
                        }
                    }
                    
                    // Vowels
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Vowels")
                            .font(.caption)
                            .foregroundColor(txtDim)
                            .padding(.bottom, 12)
                        
                        phonemeGrid(items: Vowel.all.map { PhonemeItem(id: $0.id, label: $0.symbol, subtitle: String($0.example.prefix(4)), ccValue: $0.ccValue) },
                                    selected: selectedVowel,
                                    columns: 5) { value in
                            selectedVowel = value
                            startSound()
                        } onRelease: {
                            stopSound()
                        }
                    }
                }
                .padding(.top, 20)
                
                // Note + Hold row
                HStack(spacing: 16) {
                    explorerSliderRow(label: "Note", display: noteName(testNote), value: Binding(
                        get: { Double(testNote) },
                        set: { testNote = UInt8($0) }
                    ), range: 40...81)
                    
                    explorerSliderRow(label: "Hold", display: String(format: "%.1fs", discoveryDuration), value: $discoveryDuration, range: 1.0...10.0)
                }
                .padding(.vertical, 20)
                
                Divider().background(Theme.explorerGridBorder)
                
                // CC Discovery
                VStack(alignment: .leading, spacing: 0) {
                    Text("CC Discovery")
                        .font(.caption)
                        .foregroundColor(txtDim)
                        .textCase(.uppercase)
                        .padding(.bottom, 12)
                    
                    // Velocity + Pitch Bend
                    HStack(spacing: 16) {
                        explorerSliderRow(label: "Velocity", display: "\(testVelocity)", value: Binding(
                            get: { Double(testVelocity) },
                            set: { testVelocity = UInt8($0) }
                        ), range: 1...127)
                        
                        explorerSliderRow(label: "Pitch Bend", display: "\(Int(pitchBendValue))", value: $pitchBendValue, range: -100...100)
                    }
                    .padding(.bottom, 12)
                    
                    // CC# + Value (two-column matching rows above)
                    HStack(spacing: 16) {
                        explorerPickerRow(label: "CC#", selection: $discoveryCC)
                        
                        explorerSliderRow(label: "Value", display: "\(Int(discoveryCCValue))", value: $discoveryCCValue, range: 0...127)
                    }
                    .padding(.bottom, 16)
                    
                    // Action buttons
                    HStack(spacing: 8) {
                        pillButton("Test CC\(Int(discoveryCC))", disabled: isDiscoveryPlaying || isSweeping || isSweepingCCs) {
                            runDiscoveryTest()
                        }
                        pillButton(isSweepingCCs ? "Stop Hunt" : "Hunt CC# 5-119", accent: isSweepingCCs, disabled: isSweeping || isDiscoveryPlaying) {
                            if isSweepingCCs { stopSweep() } else {
                                discoveryDuration = 1.5
                                startCCSweep()
                            }
                        }
                        pillButton(isSweeping ? "Stop Val" : "Sweep Val 0→127", disabled: isSweepingCCs || isDiscoveryPlaying) {
                            if isSweeping { stopSweep() } else { startSweep(step: 16) }
                        }
                        pillButton("Fine", disabled: isSweeping || isSweepingCCs || isDiscoveryPlaying) {
                            startSweep(step: 1)
                        }
                        
                        if isDiscoveryPlaying {
                            Text("Playing...").font(.caption).foregroundColor(.orange)
                        }
                        if isSweeping {
                            Text("CC\(Int(discoveryCC)) val=\(sweepValue)").font(.caption).foregroundColor(.purple)
                        }
                        if isSweepingCCs {
                            Text("Testing CC\(Int(discoveryCC))...").font(.caption).foregroundColor(.orange)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .background(Theme.fieldColor(colorScheme))
            
            // MARK: Console readout (black bar — stays black)
            HStack(spacing: 0) {
                Text("SEND →")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.field)
                Text("  C:\(selectedConsonant)  V:\(selectedVowel)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.ivory)
                Spacer()
                Text(lastPacketLog)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(Theme.console)
        }
        .onDisappear {
            stopSweep()
            stopSound()
            isDiscoveryPlaying = false
            isSweepingCCs = false
        }
    }
    
    // MARK: - Phoneme Grid (edge-to-edge, no gaps)
    
    private struct PhonemeItem {
        let id: String
        let label: String
        var subtitle: String? = nil
        let ccValue: UInt8
    }
    
    private func phonemeGrid(items: [PhonemeItem], selected: UInt8, columns: Int, onSelect: @escaping (UInt8) -> Void, onRelease: @escaping () -> Void) -> some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { start in
            Array(items[start..<min(start + columns, items.count)])
        }
        
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.id) { item in
                        phonemeCell(item: item, isSelected: selected == item.ccValue, onSelect: onSelect, onRelease: onRelease)
                    }
                    // Fill remaining cells in last row
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .border(width: [.trailing, .bottom], color: Theme.explorerGridBorder)
                        }
                    }
                }
            }
        }
    }
    
    private func phonemeCell(item: PhonemeItem, isSelected: Bool, onSelect: @escaping (UInt8) -> Void, onRelease: @escaping () -> Void) -> some View {
        VStack(spacing: 1) {
            Group {
                if item.label == "?" || item.label == "Random" {
                    Image(systemName: "shuffle")
                } else {
                    Text(item.label)
                }
            }
            .font(.system(size: 12, weight: isSelected ? .bold : .regular))
            .foregroundColor(isSelected ? Theme.dark : txt)
            if let sub = item.subtitle {
                Text(sub)
                    .font(.system(size: 8))
                    .foregroundColor(isSelected ? Theme.dark.opacity(0.5) : txt.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(isSelected ? Theme.accent : Color.clear)
        .border(width: [.trailing, .bottom], color: Theme.explorerGridBorder)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPlaying {
                        onSelect(item.ccValue)
                    }
                }
                .onEnded { _ in
                    onRelease()
                }
        )
    }
    
    // MARK: - Explorer Slider Row
    
    private func explorerSliderRow(label: String, display: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(txtDim)
                Text(display)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(txt)
                    .monospacedDigit()
            }
            .frame(minWidth: 80, alignment: .leading)
            
            Slider(value: value, in: range)
                .tint(Theme.bg(colorScheme))
                .accentColor(Theme.bg(colorScheme))
        }
    }
    
    // MARK: - Pill Button
    
    private func pillButton(_ label: String, accent: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.buttonFont)
                .fontWeight(Theme.buttonWeight)
                .foregroundColor(accent ? Theme.dark : txt.opacity(0.85))
                .padding(.horizontal, Theme.buttonPaddingH)
                .padding(.vertical, Theme.buttonPaddingV)
                .background(accent ? Theme.accent : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.buttonRadius)
                        .stroke(accent ? Color.clear : txt.opacity(0.85), lineWidth: Theme.buttonStroke)
                )
                .cornerRadius(Theme.buttonRadius)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
    
    // MARK: - Explorer Picker Row
    
    private func explorerPickerRow(label: String, selection: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(txtDim)
                .frame(minWidth: 80, alignment: .leading)
            
            Picker("", selection: selection) {
                Text("5 - Portamento Time").tag(Double(5))
                Text("6 - Data Entry MSB").tag(Double(6))
                Text("7 - Volume").tag(Double(7))
                Text("8 - Balance").tag(Double(8))
                Text("9 - Undefined").tag(Double(9))
                Text("10 - Pan").tag(Double(10))
                Text("11 - Expression").tag(Double(11))
                Text("12 - Effect 1").tag(Double(12))
                Text("13 - Effect 2").tag(Double(13))
                ForEach(14...31, id: \.self) { n in
                    Text("\(n) - Undefined").tag(Double(n))
                }
                Text("64 - Sustain Pedal").tag(Double(64))
                Text("65 - Portamento On/Off").tag(Double(65))
                Text("66 - Sostenuto").tag(Double(66))
                Text("67 - Soft Pedal").tag(Double(67))
                Text("68 - Legato").tag(Double(68))
                Text("69 - Hold 2").tag(Double(69))
                Text("70 - Sound Variation").tag(Double(70))
                Text("71 - Resonance/Timbre").tag(Double(71))
                Text("72 - Release Time").tag(Double(72))
                Text("73 - Attack Time").tag(Double(73))
                Text("74 - Brightness/Cutoff").tag(Double(74))
                Text("75 - Decay Time").tag(Double(75))
                Text("76 - Vibrato Rate").tag(Double(76))
                Text("77 - Vibrato Depth").tag(Double(77))
                Text("78 - Vibrato Delay").tag(Double(78))
                ForEach(79...84, id: \.self) { n in
                    Text("\(n) - GP/Undefined").tag(Double(n))
                }
                Text("91 - Reverb Depth").tag(Double(91))
                Text("92 - Tremolo Depth").tag(Double(92))
                Text("93 - Chorus Depth").tag(Double(93))
                Text("94 - Detune/Celeste").tag(Double(94))
                Text("95 - Phaser Depth").tag(Double(95))
                ForEach(102...119, id: \.self) { n in
                    Text("\(n) - Undefined").tag(Double(n))
                }
            }
            .labelsHidden()
            .tint(txt)
            .accentColor(txt)
        }
    }
    
    // MARK: - Sound Playback
    
    func startSound() {
        let pbMidi = UInt16((pitchBendValue + 100) / 200.0 * 16383)
        midiService.sendPitchBend(value: pbMidi)
        midiService.consonant = selectedConsonant
        midiService.vowel = selectedVowel
        lastPacketLog = "PB:\(Int(pitchBendValue)) CC2:\(selectedConsonant) CC3:\(selectedVowel) → NoteOn \(testNote)"
        midiService.sendNoteOn(note: testNote, velocity: testVelocity)
        isPlaying = true
    }
    
    func stopSound() {
        midiService.sendNoteOff(note: testNote)
        lastPacketLog = "NoteOff \(testNote)"
        isPlaying = false
    }
    
    // MARK: - CC Discovery
    
    func runDiscoveryTest() {
        isDiscoveryPlaying = true
        midiService.sendNoteOff(note: testNote)
        midiService.sendCC(controller: 121, value: 0)
        midiService.sendCC(controller: UInt8(discoveryCC), value: UInt8(discoveryCCValue))
        midiService.consonant = 125
        midiService.vowel = 16
        lastPacketLog = "CC\(Int(discoveryCC))=\(Int(discoveryCCValue)) CC2:125 CC3:16 → NoteOn \(testNote)"
        midiService.sendNoteOn(note: testNote, velocity: testVelocity)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + discoveryDuration) {
            midiService.sendNoteOff(note: testNote)
            isDiscoveryPlaying = false
        }
    }
    
    func startSweep(step: Int = 1) {
        isSweeping = true
        sweepValue = 0
        sweepStep = step
        sweepPatternIndex = 0
        runSweepStep()
    }
    
    func stopSweep() {
        isSweeping = false
        isSweepingCCs = false
        midiService.sendNoteOff(note: testNote)
    }
    
    func startCCSweep() {
        isSweepingCCs = true
        discoveryCC = 5
        runCCSweepStep()
    }
    
    func runCCSweepStep() {
        guard isSweepingCCs, discoveryCC < 120 else {
            isSweepingCCs = false
            return
        }
        midiService.sendNoteOff(note: testNote)
        midiService.sendCC(controller: 121, value: 0)
        midiService.sendCC(controller: UInt8(discoveryCC), value: UInt8(discoveryCCValue))
        midiService.consonant = 125
        midiService.vowel = 16
        midiService.sendNoteOn(note: testNote, velocity: testVelocity)
        lastPacketLog = "Testing CC\(Int(discoveryCC)) with val \(Int(discoveryCCValue))..."
        
        DispatchQueue.main.asyncAfter(deadline: .now() + discoveryDuration) { [self] in
            midiService.sendNoteOff(note: testNote)
            discoveryCC += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { runCCSweepStep() }
        }
    }
    
    func nextSweepNote() -> UInt8 {
        let note = sweepPattern[sweepPatternIndex % sweepPattern.count]
        sweepPatternIndex += 1
        return note
    }
    
    func runSweepStep() {
        guard isSweeping, sweepValue <= 127 else {
            isSweeping = false
            return
        }
        discoveryCCValue = Double(sweepValue)
        let ccNum = UInt8(discoveryCC)
        let note = nextSweepNote()
        
        for n in sweepPattern { midiService.sendNoteOff(note: n) }
        midiService.sendCC(controller: 121, value: 0)
        midiService.sendCC(controller: ccNum, value: UInt8(sweepValue))
        midiService.consonant = 125
        midiService.vowel = 16
        midiService.sendNoteOn(note: note, velocity: testVelocity)
        lastPacketLog = "CC\(ccNum)=\(sweepValue) C=125 V=16 → Note \(note)"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + discoveryDuration) { [self] in
            midiService.sendNoteOff(note: note)
            sweepValue += sweepStep
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { runSweepStep() }
        }
    }
    
    func noteName(_ note: UInt8) -> String {
        PitchConstants.noteName(for: note)
    }
}

// MARK: - Edge Border Helper

private extension View {
    func border(width edges: [Edge], color: Color) -> some View {
        overlay(
            EdgeBorder(edges: edges)
                .foregroundColor(color)
        )
    }
}

private struct EdgeBorder: Shape {
    let edges: [Edge]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            switch edge {
            case .top:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            case .bottom:
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            case .leading:
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            case .trailing:
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
        }
        return path.strokedPath(StrokeStyle(lineWidth: 1))
    }
}
