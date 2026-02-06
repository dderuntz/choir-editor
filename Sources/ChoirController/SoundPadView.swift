import SwiftUI
import AppKit

/// A grid pad for exploring vowel/consonant combinations
struct SoundPadView: View {
    @ObservedObject var midiService: MidiService
    
    @State private var selectedConsonant: UInt8 = 125  // None
    @State private var selectedVowel: UInt8 = 16       // ai (buy)
    @State private var testNote: UInt8 = 60            // Middle C
    @State private var testVelocity: UInt8 = 100       // Velocity (untested parameter!)
    @State private var isPlaying = false
    @State private var firstNoteDuration: Double = 0.3  // How long first note plays (300ms - minimum for Choir)
    
    // CC Discovery
    @State private var discoveryCC: Double = 5         // Which CC number to test (start at 5, skip known 1-4)
    @State private var discoveryCCValue: Double = 64   // Value to send
    @State private var discoveryDuration: Double = 1.5 // How long to hold note (1-2 sec)
    @State private var isDiscoveryPlaying: Bool = false
    @State private var isSweeping: Bool = false
    @State private var isSweepingCCs: Bool = false
    @State private var sweepValue: Int = 0  // Current value being tested in sweep
    @State private var sweepStep: Int = 1   // Step size for sweep (1=fine, 16=coarse)
    
    
    // Latch for testing
    @State private var isLatched: Bool = false
    
    
    // NRPN test
    @State private var nrpnParam: Double = 0
    @State private var nrpnValue: Double = 64
    
    // Pitch bend (sent before NoteOn as part of packet)
    @State private var pitchBendValue: Double = 0  // -100 to +100, 0 = center
    
    // Packet log - what was sent before NoteOn
    @State private var lastPacketLog: String = "No packet sent yet"
    
    // Musical pattern for sweeps (C Major arpeggio with chord progression: C, Am, F, G)
    // C: C4-E4-G4, Am: A3-C4-E4, F: F3-A3-C4, G: G3-B3-D4
    let sweepPattern: [UInt8] = [
        60, 64, 67, 72,  // C Major arp up
        69, 72, 76,      // Am arp
        65, 69, 72,      // F arp  
        67, 71, 74,      // G arp
        72, 67, 64, 60   // C back down
    ]
    @State private var sweepPatternIndex: Int = 0
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Sound Pad")
                    .font(.headline)
                Spacer()
                Text("C:\(selectedConsonant) V:\(selectedVowel)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            // Row 1: Note and Velocity
            HStack(spacing: 20) {
                HStack {
                    Text("Note:")
                    Slider(value: Binding(
                        get: { Double(testNote) },
                        set: { testNote = UInt8($0) }
                    ), in: 40...81, step: 1)
                    Text(noteName(testNote))
                        .monospacedDigit()
                        .frame(width: 40)
                }
                
                HStack {
                    Text("Velocity:")
                    Slider(value: Binding(
                        get: { Double(testVelocity) },
                        set: { testVelocity = UInt8($0) }
                    ), in: 1...127, step: 1)
                    Text("\(testVelocity)")
                        .monospacedDigit()
                        .frame(width: 35)
                }
                
                HStack {
                    Text("Pitch Bend:")
                    Slider(value: $pitchBendValue, in: -100...100, step: 1)
                    Text("\(Int(pitchBendValue))")
                        .monospacedDigit()
                        .frame(width: 40)
                    
                    Button("Reset All") {
                        pitchBendValue = 0
                        discoveryCC = 5
                        discoveryCCValue = 64
                        discoveryDuration = 1.5
                        nrpnParam = 0
                        nrpnValue = 64
                        selectedConsonant = 125
                        selectedVowel = 16
                        testNote = 60
                        testVelocity = 100
                        lastPacketLog = "Reset to defaults"
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Row 2: Diphthong timing controls
            HStack(spacing: 20) {
                HStack {
                    Text("1st Note:")
                    Slider(value: $firstNoteDuration, in: 0.25...0.8, step: 0.01)
                    Text("\(Int(firstNoteDuration * 1000))ms")
                        .monospacedDigit()
                        .frame(width: 50)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            HStack(alignment: .top, spacing: 30) {
                // Consonants column
                VStack(alignment: .leading, spacing: 4) {
                    Text("Consonant (CC2)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 4) {
                            ForEach(Consonant.all) { consonant in
                                consonantButton(consonant)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                
                // Vowels column  
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vowel (CC3)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 65))], spacing: 4) {
                            ForEach(Vowel.all) { vowel in
                                vowelButton(vowel)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            
            Divider()
            
            // Quick test: common "eye" candidates
            VStack(alignment: .leading, spacing: 8) {
                Text("Two-Note Diphthong (EYE sound)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                
                HStack(spacing: 8) {
                    twoNoteTestButton(label: "BUY→Y+ee", c1: 125, v1: 16, c2: 122, v2: 76)
                    twoNoteTestButton(label: "BUY→Y+none", c1: 125, v1: 16, c2: 122, v2: 121)
                    twoNoteTestButton(label: "AH→EE", c1: 125, v1: 8, c2: 125, v2: 76)
                    quickTestButton(label: "Y+ee", consonant: 122, vowel: 76)
                    quickTestButton(label: "Y+none", consonant: 122, vowel: 121)
                }
                
                // CC Discovery section
                VStack(alignment: .leading, spacing: 4) {
                    Text("CC Discovery (find hidden parameters)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Official: Diphthongs stretch to 'max duration' (infinity).\nHypothesis: Find a CC that sets 'Duration Hint' to shorten this.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(.top, 8)
                
                // Brainstorm Tests
                HStack(spacing: 12) {
                    Button("Legato Test (Overlap)") {
                        playLegatoTest()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Portamento Test") {
                        playPortamentoTest()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Rel Vel 127") {
                        playReleaseVel(vel: 127)
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Song Select 0-10") {
                        testSongSelect()
                    }
                    .buttonStyle(.bordered)
                }
                
                HStack(spacing: 12) {
                    Picker("CC#", selection: $discoveryCC) {
                        // Low CCs (0-31 standard)
                        Text("5 - Portamento Time").tag(Double(5))
                        Text("6 - Data Entry MSB").tag(Double(6))
                        Text("7 - Volume").tag(Double(7))
                        Text("8 - Balance").tag(Double(8))
                        Text("9 - Undefined").tag(Double(9))
                        Text("10 - Pan").tag(Double(10))
                        Text("11 - Expression").tag(Double(11))
                        Text("12 - Effect 1").tag(Double(12))
                        Text("13 - Effect 2").tag(Double(13))
                        Text("14 - Undefined").tag(Double(14))
                        Text("15 - Undefined").tag(Double(15))
                        Text("16 - GP Slider 1").tag(Double(16))
                        Text("17 - GP Slider 2").tag(Double(17))
                        Text("18 - GP Slider 3").tag(Double(18))
                        Text("19 - GP Slider 4").tag(Double(19))
                        Text("20 - Undefined").tag(Double(20))
                        Text("21 - Undefined").tag(Double(21))
                        Text("22 - Undefined").tag(Double(22))
                        Text("23 - Undefined").tag(Double(23))
                        Text("24 - Undefined").tag(Double(24))
                        Text("25 - Undefined").tag(Double(25))
                        Text("26 - Undefined").tag(Double(26))
                        Text("27 - Undefined").tag(Double(27))
                        Text("28 - Undefined").tag(Double(28))
                        Text("29 - Undefined").tag(Double(29))
                        Text("30 - Undefined").tag(Double(30))
                        Text("31 - Undefined").tag(Double(31))
                        // Switches/Pedals (64-69)
                        Text("64 - Sustain Pedal").tag(Double(64))
                        Text("65 - Portamento On/Off").tag(Double(65))
                        Text("66 - Sostenuto").tag(Double(66))
                        Text("67 - Soft Pedal").tag(Double(67))
                        Text("68 - Legato").tag(Double(68))
                        Text("69 - Hold 2").tag(Double(69))
                        Text("70 - Sound Variation").tag(Double(70))
                        // Sound Controllers (71-79)
                        Text("71 - Resonance/Timbre").tag(Double(71))
                        Text("72 - Release Time").tag(Double(72))
                        Text("73 - Attack Time").tag(Double(73))
                        Text("74 - Brightness/Cutoff").tag(Double(74))
                        Text("75 - Decay Time").tag(Double(75))
                        Text("76 - Vibrato Rate").tag(Double(76))
                        Text("77 - Vibrato Depth").tag(Double(77))
                        Text("78 - Vibrato Delay").tag(Double(78))
                        Text("79 - Undefined").tag(Double(79))
                        Text("80 - GP Button 5").tag(Double(80))
                        Text("81 - GP Button 6").tag(Double(81))
                        Text("82 - GP Button 7").tag(Double(82))
                        Text("83 - GP Button 8").tag(Double(83))
                        Text("84 - Portamento Control").tag(Double(84))
                        Text("85-90 - Undefined").tag(Double(85))
                        // Effects (91-95)
                        Text("91 - Reverb Depth").tag(Double(91))
                        Text("92 - Tremolo Depth").tag(Double(92))
                        Text("93 - Chorus Depth").tag(Double(93))
                        Text("94 - Detune/Celeste").tag(Double(94))
                        Text("95 - Phaser Depth").tag(Double(95))
                        // Undefined (102-119) - often custom
                        Text("102 - Undefined").tag(Double(102))
                        Text("103 - Undefined").tag(Double(103))
                        Text("104 - Undefined").tag(Double(104))
                        Text("105 - Undefined").tag(Double(105))
                        Text("106 - Undefined").tag(Double(106))
                        Text("107 - Undefined").tag(Double(107))
                        Text("108 - Undefined").tag(Double(108))
                        Text("109 - Undefined").tag(Double(109))
                        Text("110 - Undefined").tag(Double(110))
                        Text("111 - Undefined").tag(Double(111))
                        Text("112 - Undefined").tag(Double(112))
                        Text("113 - Undefined").tag(Double(113))
                        Text("114 - Undefined").tag(Double(114))
                        Text("115 - Undefined").tag(Double(115))
                        Text("116 - Undefined").tag(Double(116))
                        Text("117 - Undefined").tag(Double(117))
                        Text("118 - Undefined").tag(Double(118))
                        Text("119 - Undefined").tag(Double(119))
                    }
                    .frame(width: 220)
                    
                    HStack {
                        Text("Val:")
                        Slider(value: $discoveryCCValue, in: 0...127, step: 1)
                            .frame(width: 80)
                        Text("\(Int(discoveryCCValue))")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                    
                    HStack {
                        Text("Hold:")
                        Slider(value: $discoveryDuration, in: 1.0...10.0, step: 0.5)
                            .frame(width: 80)
                        Text("\(discoveryDuration, specifier: "%.1f")s")
                            .monospacedDigit()
                            .frame(width: 35)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    // Test with mystery CC
                    Button("Test CC\(Int(discoveryCC))") {
                        runDiscoveryTest()
                    }
                    .disabled(isDiscoveryPlaying || isSweeping || isSweepingCCs)
                    
                    // CC# Sweep (Hunt Duration Hint)
                    Button(isSweepingCCs ? "Stop Hunt" : "Hunt CC# 5-119") {
                        if isSweepingCCs {
                            stopSweep()
                        } else {
                            // Suggest short duration for the hunt
                            discoveryDuration = 1.5
                            startCCSweep()
                        }
                    }
                    .disabled(isSweeping || isDiscoveryPlaying)
                    .tint(.orange)
                    
                    // Coarse sweep (Values)
                    Button(isSweeping ? "Stop Val" : "Sweep Val 0→127") {
                        if isSweeping {
                            stopSweep()
                        } else {
                            startSweep(step: 16)
                        }
                    }
                    .disabled(isSweepingCCs || isDiscoveryPlaying)
                    
                    // Fine sweep (Values)
                    Button("Fine") {
                        if !isSweeping {
                            startSweep(step: 1)
                        }
                    }
                    .disabled(isSweeping || isSweepingCCs || isDiscoveryPlaying)
                    
                    if isDiscoveryPlaying {
                        Text("Playing...")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if isSweeping {
                        Text("CC\(Int(discoveryCC)) val=\(sweepValue)")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    
                    if isSweepingCCs {
                        Text("Testing CC\(Int(discoveryCC))...")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // Packet log - shows what was sent before NoteOn
                HStack {
                    Text("Last packet:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(lastPacketLog)
                        .font(.caption.monospaced())
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                    Spacer()
                    
                    Button(isLatched ? "🔊 Stop" : "▶️ Latch aɪ") {
                        if isLatched {
                            stopSound()
                            isLatched = false
                        } else {
                            // Send pitch bend before note
                            let pbMidi = UInt16((pitchBendValue + 100) / 200.0 * 16383)
                            midiService.sendPitchBend(value: pbMidi)
                            midiService.consonant = 125
                            midiService.vowel = 16
                            lastPacketLog = "PB:\(Int(pitchBendValue)) CC2:125 CC3:16 → NoteOn \(testNote)"
                            midiService.sendNoteOn(note: testNote, velocity: testVelocity)
                            isPlaying = true
                            isLatched = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isLatched ? .red : .blue)
                }
                
                // NRPN - 16384 possible parameters
                Text("NRPN (extended parameters)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                HStack(spacing: 20) {
                    HStack {
                        Text("NRPN Param:")
                        Slider(value: $nrpnParam, in: 0...200, step: 1)  // Test first 200
                            .frame(width: 100)
                        Text("\(Int(nrpnParam))")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                    
                    HStack {
                        Text("Val:")
                        Slider(value: $nrpnValue, in: 0...127, step: 1)
                            .frame(width: 80)
                        Text("\(Int(nrpnValue))")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                    
                    Button("Send NRPN") {
                        midiService.sendNRPN(parameter: UInt16(nrpnParam), value: UInt16(nrpnValue))
                    }
                    
                    Button("NRPN→Note") {
                        // Send NRPN then play note
                        lastPacketLog = "NRPN[\(Int(nrpnParam))]=\(Int(nrpnValue)) CC2:125 CC3:16 → NoteOn \(testNote)"
                        midiService.sendNRPN(parameter: UInt16(nrpnParam), value: UInt16(nrpnValue))
                        midiService.consonant = 125
                        midiService.vowel = 16  // aɪ
                        midiService.sendNoteOn(note: testNote, velocity: testVelocity)
                        isPlaying = true
                        isLatched = true
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                Text("Component Sounds")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                
                HStack(spacing: 8) {
                    quickTestButton(label: "AH (aa)", consonant: 125, vowel: 8)
                    quickTestButton(label: "EE (iː)", consonant: 125, vowel: 76)
                    quickTestButton(label: "Y cons", consonant: 122, vowel: 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .onDisappear {
            stopSweep()
            stopSound()
            isDiscoveryPlaying = false
            isSweepingCCs = false
        }
    }
    
    func consonantButton(_ consonant: Consonant) -> some View {
        VStack(spacing: 2) {
            Text(consonant.name)
                .font(.caption)
                .fontWeight(selectedConsonant == consonant.ccValue ? .bold : .regular)
            Text("\(consonant.ccValue)")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .frame(width: 45, height: 36)
        .background(selectedConsonant == consonant.ccValue ? Color.accentColor.opacity(0.3) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selectedConsonant == consonant.ccValue ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPlaying {
                        selectedConsonant = consonant.ccValue
                        startSound()
                    }
                }
                .onEnded { _ in
                    stopSound()
                }
        )
    }
    
    func vowelButton(_ vowel: Vowel) -> some View {
        VStack(spacing: 2) {
            Text(vowel.symbol)
                .font(.caption)
                .fontWeight(selectedVowel == vowel.ccValue ? .bold : .regular)
            Text(vowel.example.prefix(6))
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Text("\(vowel.ccValue)")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .frame(width: 55, height: 44)
        .background(selectedVowel == vowel.ccValue ? Color.accentColor.opacity(0.3) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selectedVowel == vowel.ccValue ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPlaying {
                        selectedVowel = vowel.ccValue
                        startSound()
                    }
                }
                .onEnded { _ in
                    stopSound()
                }
        )
    }
    
    func quickTestButton(label: String, consonant: UInt8, vowel: UInt8) -> some View {
        Text(label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(4)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPlaying {
                            selectedConsonant = consonant
                            selectedVowel = vowel
                            startSound()
                        }
                    }
                    .onEnded { _ in
                        stopSound()
                    }
            )
    }
    
    /// Play two notes in sequence with NoteOff between
    func twoNoteTestButton(label: String, c1: UInt8, v1: UInt8, c2: UInt8, v2: UInt8) -> some View {
        Text(label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.3))
            .cornerRadius(4)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPlaying {
                            playTwoNoteSequence(c1: c1, v1: v1, c2: c2, v2: v2)
                        }
                    }
                    .onEnded { _ in
                        // Two-note sequence auto-stops
                    }
            )
    }
    
    /// Play two notes by retriggering (NoteOn without NoteOff first)
    func retriggerTestButton(label: String, c1: UInt8, v1: UInt8, c2: UInt8, v2: UInt8) -> some View {
        Text(label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.3))
            .cornerRadius(4)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPlaying {
                            playRetriggerSequence(c1: c1, v1: v1, c2: c2, v2: v2)
                        }
                    }
                    .onEnded { _ in
                        // Sequence auto-stops
                    }
            )
    }
    
    func playTwoNoteSequence(c1: UInt8, v1: UInt8, c2: UInt8, v2: UInt8) {
        print("🔊 Off/On test: [\(c1),\(v1)] → [\(c2),\(v2)] | 1st:\(Int(firstNoteDuration*1000))ms")
        isPlaying = true
        
        // First sound (AH)
        midiService.consonant = c1
        midiService.vowel = v1
        midiService.sendNoteOn(note: testNote)
        lastPacketLog = "CC2:\(c1) CC3:\(v1) → NoteOn \(testNote)"
        
        // After firstNoteDuration, switch to second sound
        DispatchQueue.main.asyncAfter(deadline: .now() + firstNoteDuration) { [self] in
            midiService.sendNoteOff(note: testNote)
            
            // No gap - immediately play second note
            midiService.consonant = c2
            midiService.vowel = v2
            midiService.sendNoteOn(note: testNote)
            lastPacketLog = "CC2:\(c2) CC3:\(v2) → NoteOn \(testNote)"
            
            // Hold second note for 500ms then stop
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                midiService.sendNoteOff(note: testNote)
                isPlaying = false
            }
        }
    }
    
    /// Retrigger: send second NoteOn WITHOUT NoteOff first
    func playRetriggerSequence(c1: UInt8, v1: UInt8, c2: UInt8, v2: UInt8) {
        print("🔊 Retrigger test: [\(c1),\(v1)] → [\(c2),\(v2)] | 1st:\(Int(firstNoteDuration*1000))ms (no noteOff)")
        isPlaying = true
        
        // First sound (AH)
        midiService.consonant = c1
        midiService.vowel = v1
        midiService.sendNoteOn(note: testNote)
        lastPacketLog = "CC2:\(c1) CC3:\(v1) → NoteOn \(testNote)"
        
        // After firstNoteDuration, send new CC + NoteOn WITHOUT NoteOff
        DispatchQueue.main.asyncAfter(deadline: .now() + firstNoteDuration) { [self] in
            // Change CC values
            midiService.consonant = c2
            midiService.vowel = v2
            // Send another NoteOn (retrigger) - no NoteOff!
            midiService.sendNoteOn(note: testNote)
            lastPacketLog = "CC2:\(c2) CC3:\(v2) → NoteOn \(testNote) (retrigger)"
            
            // Hold second note for 500ms then stop
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                midiService.sendNoteOff(note: testNote)
                isPlaying = false
            }
        }
    }
    
    func startSound() {
        // Send full packet: pitch bend, CCs, then NoteOn
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
        
        // 1. Note off + reset all controllers
        midiService.sendNoteOff(note: testNote)
        midiService.sendCC(controller: 121, value: 0)  // Reset All Controllers
        
        // 2. Send the mystery CC
        midiService.sendCC(controller: UInt8(discoveryCC), value: UInt8(discoveryCCValue))
        
        // 3. Set vowel/consonant
        midiService.consonant = 125  // None
        midiService.vowel = 16       // aɪ (buy)
        
        // Update packet log
        lastPacketLog = "CC\(Int(discoveryCC))=\(Int(discoveryCCValue)) CC2:125 CC3:16 → NoteOn \(testNote)"
        
        // 4. Note on (with velocity)
        midiService.sendNoteOn(note: testNote, velocity: testVelocity)
        
        // Stop after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + discoveryDuration) {
            midiService.sendNoteOff(note: testNote)
            isDiscoveryPlaying = false
            print("🔍 Discovery: Stopped")
        }
    }
    
    func runBaselineTest() {
        isDiscoveryPlaying = true
        
        // 1. Note off + reset all controllers
        midiService.sendNoteOff(note: testNote)
        midiService.sendCC(controller: 121, value: 0)  // Reset All Controllers
        
        // 2. Set vowel/consonant (no mystery CC)
        midiService.consonant = 125  // None
        midiService.vowel = 16       // aɪ (buy)
        
        // 3. Note on (with velocity)
        midiService.sendNoteOn(note: testNote, velocity: testVelocity)
        lastPacketLog = "CC2:125 CC3:16 → NoteOn \(testNote) vel=\(testVelocity) (baseline)"
        print("🔍 Baseline: Playing bUY for \(discoveryDuration)s vel:\(testVelocity) (no extra CC)")
        
        // Stop after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + discoveryDuration) {
            midiService.sendNoteOff(note: testNote)
            isDiscoveryPlaying = false
            print("🔍 Baseline: Stopped")
        }
    }
    
    // MARK: - Sweep (values 0-127 for selected CC)
    
    func startSweep(step: Int = 1) {
        isSweeping = true
        sweepValue = 0  // Start at value 0
        sweepStep = step
        sweepPatternIndex = 0
        runSweepStep()
    }
    
    func stopSweep() {
        isSweeping = false
        isSweepingCCs = false
        midiService.sendNoteOff(note: testNote)
        print("🔍 Sweep: Stopped")
    }
    
    // MARK: - CC Number Sweep (Iterate CC 5-119)
    
    func startCCSweep() {
        isSweepingCCs = true
        discoveryCC = 5
        runCCSweepStep()
    }
    
    func runCCSweepStep() {
        guard isSweepingCCs else { return }
        guard discoveryCC < 120 else {
            isSweepingCCs = false
            print("🔍 CC Sweep: Complete")
            return
        }
        
        // 1. Reset
        midiService.sendNoteOff(note: testNote)
        midiService.sendCC(controller: 121, value: 0)
        
        // 2. Send Test CC (using the value from the slider, e.g. 50 for "short duration"?)
        midiService.sendCC(controller: UInt8(discoveryCC), value: UInt8(discoveryCCValue))
        
        // 3. Set Vowel/Consonant (bUY)
        midiService.consonant = 125
        midiService.vowel = 16
        
        // 4. Note On
        midiService.sendNoteOn(note: testNote, velocity: testVelocity)
        
        lastPacketLog = "Testing CC\(Int(discoveryCC)) with val \(Int(discoveryCCValue))..."
        
        // 5. Next
        DispatchQueue.main.asyncAfter(deadline: .now() + discoveryDuration) { [self] in
             midiService.sendNoteOff(note: testNote)
             discoveryCC += 1
             
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                 runCCSweepStep()
             }
        }
    }
    
    // MARK: - Live Glide & Release Vel Tests
    
    func playLiveGlide(c1: UInt8, v1: UInt8, v2: UInt8) {
        print("🔊 Live Glide Test: [\(c1),\(v1)] → [\(c1),\(v2)]")
        isPlaying = true
        
        // 1. Play First Sound
        midiService.consonant = c1
        midiService.vowel = v1
        midiService.sendNoteOn(note: testNote)
        lastPacketLog = "CC2:\(c1) CC3:\(v1) → NoteOn \(testNote)"
        
        // 2. Wait 1.0s then change vowel ONLY (no new NoteOn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            midiService.vowel = v2
            midiService.sendCC(controller: 3, value: v2)
            lastPacketLog = "CC3:\(v2) (Live Change)"
            print("   -> Live CC3 change to \(v2)")
            
            // 3. Stop after another 1.0s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                midiService.sendNoteOff(note: testNote)
                lastPacketLog = "NoteOff \(testNote)"
                isPlaying = false
            }
        }
    }
    
    func playReleaseVel(vel: UInt8) {
        print("🔊 Release Velocity Test: Vel \(vel)")
        isPlaying = true
        
        // 1. Play Note
        midiService.consonant = 125 // None
        midiService.vowel = 16      // bUY
        midiService.sendNoteOn(note: testNote)
        lastPacketLog = "CC2:125 CC3:16 → NoteOn \(testNote)"
        
        // 2. Stop with custom release velocity
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            midiService.sendNoteOff(note: testNote, velocity: vel)
            lastPacketLog = "NoteOff \(testNote) vel:\(vel)"
            isPlaying = false
        }
    }
    
    // MARK: - Legato & Portamento Tests
    
    func playLegatoTest() {
        print("🔊 Legato Test: Overlapping Notes")
        isPlaying = true
        
        // 1. Play Note 1 (Ah)
        midiService.consonant = 125 // None
        midiService.vowel = 16      // bUY (start)
        midiService.sendNoteOn(note: testNote)
        lastPacketLog = "Note 1: Ah (Held)"
        
        // 2. Wait 300ms, then Play Note 2 (Ee) WITHOUT stopping Note 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            midiService.vowel = 76 // Ee
            midiService.sendCC(controller: 3, value: 76)
            midiService.sendNoteOn(note: testNote) // Retrigger same note? Or different?
            // Usually legato requires different note or same note retrigger
            lastPacketLog = "Note 2: Ee (Overlap)"
            print("   -> Overlap NoteOn")
            
            // 3. Stop all after 1s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                midiService.sendNoteOff(note: testNote)
                isPlaying = false
            }
        }
    }
    
    func playPortamentoTest() {
        print("🔊 Portamento Test")
        isPlaying = true
        
        // 1. Enable Portamento
        midiService.sendCC(controller: 65, value: 127) // On
        midiService.sendCC(controller: 5, value: 64)   // Time
        midiService.sendCC(controller: 84, value: 60)  // Portamento Control (Source note?)
        
        // 2. Play Note 1
        midiService.consonant = 125
        midiService.vowel = 16
        midiService.sendNoteOn(note: testNote)
        lastPacketLog = "Porta ON -> Note 1"
        
        // 3. Overlap Note 2
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
             midiService.vowel = 76
             midiService.sendCC(controller: 3, value: 76)
             midiService.sendNoteOn(note: testNote)
             lastPacketLog = "Porta -> Note 2 (Overlap)"
             
             DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                 midiService.sendNoteOff(note: testNote)
                 midiService.sendCC(controller: 65, value: 0) // Off
                 isPlaying = false
             }
        }
    }

    func testSongSelect() {
        print("🔊 Testing Song Select 0-10")
        // Loop through songs 0-10
        for i in 0...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) { [self] in
                midiService.sendSongSelect(song: UInt8(i))
                lastPacketLog = "Song Select \(i)"
            }
        }
    }

    func nextSweepNote() -> UInt8 {
        let note = sweepPattern[sweepPatternIndex % sweepPattern.count]
        sweepPatternIndex += 1
        return note
    }
    
    func runSweepStep() {
        guard isSweeping else { return }
        guard sweepValue <= 127 else {
            isSweeping = false
            print("🔍 Sweep: Complete! CC\(Int(discoveryCC)) all values tested.")
            return
        }
        
        // Update the UI slider to show current value
        discoveryCCValue = Double(sweepValue)
        
        let ccNum = UInt8(discoveryCC)
        let note = nextSweepNote()
        
        // 1. Note off (all notes in pattern range) + reset controllers
        for n in sweepPattern { midiService.sendNoteOff(note: n) }
        midiService.sendCC(controller: 121, value: 0)  // Reset All Controllers
        
        // 2. Send this CC with current sweep value
        midiService.sendCC(controller: ccNum, value: UInt8(sweepValue))
        print("🔍 Sweep: Testing CC\(ccNum)=\(sweepValue) note:\(note)")
        
        // 3. Set vowel/consonant
        midiService.consonant = 125  // None
        midiService.vowel = 16       // aɪ (buy)
        
        // 4. Note on (with velocity)
        midiService.sendNoteOn(note: note, velocity: testVelocity)
        
        // Update packet log
        lastPacketLog = "CC\(ccNum)=\(sweepValue), C=125, V=16 → Note \(note) vel=\(testVelocity)"
        
        // After duration, move to next value
        DispatchQueue.main.asyncAfter(deadline: .now() + discoveryDuration) { [self] in
            midiService.sendNoteOff(note: note)
            sweepValue += sweepStep
            
            // Small gap between tests
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                runSweepStep()
            }
        }
    }
    
    func noteName(_ note: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (Int(note) / 12) - 1
        let noteName = names[Int(note) % 12]
        return "\(noteName)\(octave)"
    }
}
