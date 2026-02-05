import SwiftUI

// MARK: - Data Model (Phoneme → Syllable → Word)

/// A single phoneme - the atomic sound unit
struct Phoneme: Identifiable {
    let id = UUID()
    let text: String           // Display text (e.g., "A", "n")
    let consonant: UInt8       // CC2 value
    let vowel: UInt8           // CC3 value
    let note: UInt8            // MIDI note
    let duration: Double       // Duration in beats
    let isChord: Bool          // If true, play as chord
    
    init(_ text: String, c: UInt8, v: UInt8, note: UInt8, dur: Double = 0.4, chord: Bool = false) {
        self.text = text
        self.consonant = c
        self.vowel = v
        self.note = note
        self.duration = dur
        self.isChord = chord
    }
}

/// A syllable - group of phonemes that play together on press
/// Press: plays through all phonemes, holds the last one
struct Syllable: Identifiable {
    let id = UUID()
    let phonemes: [Phoneme]
    
    var text: String { phonemes.map { $0.text }.joined() }
    var totalDuration: Double { phonemes.reduce(0) { $0 + $1.duration } }
}

/// A word - group of syllables
/// Release: plays remaining syllables in the word
struct Word: Identifiable {
    let id = UUID()
    let syllables: [Syllable]
    
    var text: String { syllables.map { $0.text }.joined(separator: "·") }
    var allPhonemes: [Phoneme] { syllables.flatMap { $0.phonemes } }
}

/// Hardcoded haiku for testing
/// "An old silent pond / A frog jumps into the pond / Splash! Silence again"
/// Phonetically broken down with trailing consonants as short schwas
///
/// PHONETIC RULES FOR AI CONVERSION:
/// ---------------------------------
/// 1. TRAILING CONSONANTS need a schwa (ə) or nasal (mmm) vowel attached
///    - "old" → "ol" + "-d" (D + schwa)
///    - "frog" → "fro" + "-g" (G + schwa)
///
/// 2. NASAL CONSONANTS (N, M) use the "mmm" vowel for humming quality
///    - "pond" → "po" + "-n" (N + mmm) + "-d"
///    - "jumps" → "ju" + "-m" (M + mmm) + "-ps"
///    - "again" → "a" + "-gai" + "-n" (N + mmm)
///
/// 3. STOP CONSONANTS (T, D, P, K) at word end may be OPTIONAL or very short
///    - "silent" - the T is barely voiced, just a stop/cutoff
///    - "it", "strident" - similar pattern
///    - Consider: omit the trailing stop OR use very short duration (0.1-0.2)
///
/// 4. DIPHTHONGS need time to glide (longer duration)
///    - aɪ (buy/sigh) in "silent" needs 0.8+ beats to hear both ah→ee
///    - eɪ (stray) in "again" similar
///
/// 5. TIMING RULES:
///    - Mid-word parts: quick (0.25-0.4 beats) - flow together
///    - Word endings: longer (0.5-0.8 beats) - natural pause/breath
///    - Line endings: longest (0.7-1.0 beats)
///    - Emphasis (like "Splash!"): 1.0+ beats
///
/// 6. CONSONANT CLUSTERS we don't have exact matches for:
///    - "Spl" → use "Sl" (closest available)
///    - "ps" → use "P" + schwa (approximation)
///    - "nce" → use "-n" (nasal) + "-ce" (S + schwa)
///
struct HaikuData {
    // Consonant CC values
    static let C_NONE: UInt8 = 125
    static let C_D: UInt8 = 20
    static let C_FR: UInt8 = 37
    static let C_G: UInt8 = 40
    static let C_DJ: UInt8 = 53
    static let C_L: UInt8 = 66
    static let C_M: UInt8 = 69
    static let C_N: UInt8 = 73
    static let C_P: UInt8 = 79
    static let C_S: UInt8 = 92
    static let C_SL: UInt8 = 96
    static let C_SH: UInt8 = 100
    static let C_T: UInt8 = 102
    static let C_TH: UInt8 = 109
    
    // Vowel CC values
    static let V_AI: UInt8 = 19     // aɪ (buy/sigh)
    static let V_AE: UInt8 = 23     // æ (pat)
    static let V_SCHWA: UInt8 = 31  // ə (the)
    static let V_AW: UInt8 = 38     // ɔː (store)
    static let V_O: UInt8 = 53      // ɒ (pot)
    static let V_UH: UInt8 = 61     // ʌ (cut)
    static let V_OO: UInt8 = 68     // uː (zoo)
    static let V_EE: UInt8 = 76     // iː (free)
    static let V_AY: UInt8 = 91     // eɪ (stray)
    static let V_MMM: UInt8 = 113   // nasal mmm
    
    // Chord notes for "Splash!" - C major chord
    static let splashChord: [UInt8] = [60, 64, 67]
    
    // Line 1: "An old silent pond"
    static let line1: [Word] = [
        // "An" - 1 syllable
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("A", c: C_NONE, v: V_AE, note: 60, dur: 0.5),
                Phoneme("n", c: C_N, v: V_MMM, note: 60, dur: 0.4)
            ])
        ]),
        // "old" - 1 syllable
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("ol", c: C_NONE, v: V_AW, note: 62, dur: 0.5),
                Phoneme("d", c: C_D, v: V_SCHWA, note: 62, dur: 0.3)
            ])
        ]),
        // "silent" - 2 syllables: si·lent
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("si", c: C_S, v: V_AI, note: 64, dur: 0.7)
            ]),
            Syllable(phonemes: [
                Phoneme("len", c: C_L, v: V_SCHWA, note: 65, dur: 0.4),
                Phoneme("t", c: C_T, v: V_SCHWA, note: 65, dur: 0.2)
            ])
        ]),
        // "pond" - 1 syllable
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("po", c: C_P, v: V_O, note: 67, dur: 0.5),
                Phoneme("n", c: C_N, v: V_MMM, note: 67, dur: 0.3),
                Phoneme("d", c: C_D, v: V_SCHWA, note: 67, dur: 0.5)
            ])
        ])
    ]
    
    // Line 2: "A frog jumps into the pond"
    static let line2: [Word] = [
        // "A"
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("A", c: C_NONE, v: V_SCHWA, note: 67, dur: 0.4)
            ])
        ]),
        // "frog"
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("fro", c: C_FR, v: V_O, note: 65, dur: 0.5),
                Phoneme("g", c: C_G, v: V_SCHWA, note: 65, dur: 0.3)
            ])
        ]),
        // "jumps"
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("jum", c: C_DJ, v: V_UH, note: 64, dur: 0.4),
                Phoneme("ps", c: C_S, v: V_SCHWA, note: 64, dur: 0.3)
            ])
        ]),
        // "into" - 2 syllables: in·to
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("in", c: C_NONE, v: V_EE, note: 62, dur: 0.4)
            ]),
            Syllable(phonemes: [
                Phoneme("to", c: C_T, v: V_OO, note: 60, dur: 0.4)
            ])
        ]),
        // "the"
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("the", c: C_TH, v: V_SCHWA, note: 62, dur: 0.4)
            ])
        ]),
        // "pond"
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("po", c: C_P, v: V_O, note: 64, dur: 0.5),
                Phoneme("n", c: C_N, v: V_MMM, note: 64, dur: 0.3),
                Phoneme("d", c: C_D, v: V_SCHWA, note: 64, dur: 0.5)
            ])
        ])
    ]
    
    // Line 3: "Splash! Silence again"
    static let line3: [Word] = [
        // "Splash!" - chord
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("Splash!", c: C_SL, v: V_AE, note: 72, dur: 1.0, chord: true)
            ])
        ]),
        // "Silence" - 2 syllables: Si·lence
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("Si", c: C_S, v: V_AI, note: 69, dur: 0.7)
            ]),
            Syllable(phonemes: [
                Phoneme("len", c: C_L, v: V_SCHWA, note: 67, dur: 0.4),
                Phoneme("ce", c: C_S, v: V_SCHWA, note: 67, dur: 0.2)
            ])
        ]),
        // "again" - 2 syllables: a·gain
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("a", c: C_NONE, v: V_SCHWA, note: 65, dur: 0.3)
            ]),
            Syllable(phonemes: [
                Phoneme("gain", c: C_G, v: V_AY, note: 64, dur: 0.6),
                Phoneme("n", c: C_N, v: V_MMM, note: 64, dur: 0.4)
            ])
        ])
    ]
    
    static let allWords: [Word] = line1 + line2 + line3
}

struct SequencerView: View {
    @ObservedObject var midiService: MidiService
    
    @State private var isPlaying = false
    @State private var tempo: Double = 100
    @State private var timer: Timer?
    
    // Track current position: which word, syllable, phoneme
    @State private var currentWordIndex = 0
    @State private var currentSyllableIndex = 0
    @State private var currentPhonemeIndex = 0
    
    // For manual interaction
    @State private var isHolding = false
    @State private var holdingWordIndex: Int?
    @State private var holdingSyllableIndex: Int?
    @State private var activeNote: UInt8?
    
    let words = HaikuData.allWords
    
    var beatDuration: Double { 60.0 / tempo }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Haiku Sequencer")
                .font(.headline)
            
            // Display words with syllables
            wordDisplay
            
            // Playback controls
            HStack(spacing: 20) {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.title)
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: reset) {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
                .disabled(isPlaying)
            }
            
            // Tempo slider
            HStack {
                Text("Tempo:")
                    .font(.caption)
                Slider(value: $tempo, in: 40...200, step: 5)
                    .frame(width: 120)
                Text("\(Int(tempo))")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 30)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    var wordDisplay: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Line 1
            lineView(HaikuData.line1, lineOffset: 0, showSlash: true)
            // Line 2
            lineView(HaikuData.line2, lineOffset: HaikuData.line1.count, showSlash: true)
            // Line 3
            lineView(HaikuData.line3, lineOffset: HaikuData.line1.count + HaikuData.line2.count, showSlash: false)
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
    
    func lineView(_ lineWords: [Word], lineOffset: Int, showSlash: Bool) -> some View {
        HStack(spacing: 12) {  // More space between words
            ForEach(Array(lineWords.enumerated()), id: \.element.id) { wordIdx, word in
                wordView(word, wordIndex: lineOffset + wordIdx)
            }
            if showSlash {
                Text("/")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    func wordView(_ word: Word, wordIndex: Int) -> some View {
        // Syllables as separate buttons with small gap
        HStack(spacing: 3) {
            ForEach(Array(word.syllables.enumerated()), id: \.element.id) { sylIdx, syllable in
                syllableButton(syllable, wordIndex: wordIndex, syllableIndex: sylIdx)
            }
        }
    }
    
    func syllableButton(_ syllable: Syllable, wordIndex: Int, syllableIndex: Int) -> some View {
        let isCurrentSyllable = (wordIndex == currentWordIndex && syllableIndex == currentSyllableIndex)
        let isHoldingThis = (holdingWordIndex == wordIndex && holdingSyllableIndex == syllableIndex)
        let isActive = isCurrentSyllable || isHoldingThis
        
        // Alternate word colors
        let baseBg = wordIndex % 2 == 0 ? Color(white: 0.85) : Color(white: 0.70)
        
        // Phonemes as connected segments within the syllable
        return HStack(spacing: 0) {
            ForEach(Array(syllable.phonemes.enumerated()), id: \.element.id) { pIdx, phoneme in
                phonemeSegment(phoneme, 
                              isFirst: pIdx == 0, 
                              isLast: pIdx == syllable.phonemes.count - 1,
                              isActive: isActive,
                              baseBg: baseBg)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isHolding || holdingWordIndex != wordIndex || holdingSyllableIndex != syllableIndex {
                        pressSyllable(wordIndex: wordIndex, syllableIndex: syllableIndex)
                    }
                }
                .onEnded { _ in
                    releaseSyllable(wordIndex: wordIndex, syllableIndex: syllableIndex)
                }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
                if isHolding && holdingWordIndex == wordIndex && holdingSyllableIndex == syllableIndex {
                    releaseSyllable(wordIndex: wordIndex, syllableIndex: syllableIndex)
                }
            }
        }
    }
    
    func phonemeSegment(_ phoneme: Phoneme, isFirst: Bool, isLast: Bool, isActive: Bool, baseBg: Color) -> some View {
        let bg = isActive ? Color.yellow : baseBg
        
        return HStack(spacing: 0) {
            Text(phoneme.text)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .fontWeight(isActive ? .bold : .regular)
            
            // Separator line between phonemes (not after last)
            if !isLast {
                Rectangle()
                    .fill(Color(white: 0.5))
                    .frame(width: 1)
                    .padding(.vertical, 2)
            }
        }
        .background(bg)
    }
    
    // MARK: - Press/Release Interaction
    
    /// Press: Play through all phonemes in the syllable, hold the last one
    func pressSyllable(wordIndex: Int, syllableIndex: Int) {
        guard !isPlaying else { return }
        
        // Stop any currently playing note
        if let note = activeNote {
            midiService.sendNoteOff(note: note)
            // Also stop chord notes if applicable
            for chordNote in HaikuData.splashChord {
                midiService.sendNoteOff(note: chordNote)
            }
        }
        
        isHolding = true
        holdingWordIndex = wordIndex
        holdingSyllableIndex = syllableIndex
        currentWordIndex = wordIndex
        currentSyllableIndex = syllableIndex
        
        let word = words[wordIndex]
        let syllable = word.syllables[syllableIndex]
        
        // Play through all phonemes in the syllable
        playSyllablePhonemes(syllable)
    }
    
    /// Play all phonemes in a syllable sequentially, hold the last one
    func playSyllablePhonemes(_ syllable: Syllable) {
        guard !syllable.phonemes.isEmpty else { return }
        
        // For simplicity, play through each phoneme with timing, hold the last
        playPhonemeSequence(syllable.phonemes, index: 0)
    }
    
    func playPhonemeSequence(_ phonemes: [Phoneme], index: Int) {
        guard index < phonemes.count else { return }
        guard isHolding else { return }  // Stop if released
        
        let phoneme = phonemes[index]
        let isLast = index == phonemes.count - 1
        
        // Stop previous note
        if let note = activeNote {
            midiService.sendNoteOff(note: note)
        }
        
        // Set CCs and play
        midiService.consonant = phoneme.consonant
        midiService.vowel = phoneme.vowel
        
        if phoneme.isChord {
            for note in HaikuData.splashChord {
                midiService.sendNoteOn(note: note)
            }
            activeNote = HaikuData.splashChord[0]
        } else {
            midiService.sendNoteOn(note: phoneme.note)
            activeNote = phoneme.note
        }
        
        print("🎵 Phoneme: '\(phoneme.text)' - C:\(phoneme.consonant) V:\(phoneme.vowel)")
        
        // If not last, schedule next phoneme
        if !isLast {
            let duration = phoneme.duration * beatDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in
                playPhonemeSequence(phonemes, index: index + 1)
            }
        }
        // If last, keep holding until release
    }
    
    /// Release: Play remaining syllables in the word, then stop
    func releaseSyllable(wordIndex: Int, syllableIndex: Int) {
        guard isHolding else { return }
        
        isHolding = false
        
        let word = words[wordIndex]
        let remainingSyllables = Array(word.syllables.dropFirst(syllableIndex + 1))
        
        if remainingSyllables.isEmpty {
            // No more syllables, just stop
            stopAllNotes()
        } else {
            // Play remaining syllables then stop
            playRemainingSyllables(remainingSyllables, index: 0)
        }
        
        holdingWordIndex = nil
        holdingSyllableIndex = nil
    }
    
    func playRemainingSyllables(_ syllables: [Syllable], index: Int) {
        guard index < syllables.count else {
            stopAllNotes()
            return
        }
        
        let syllable = syllables[index]
        playRemainingSyllablePhonemes(syllable.phonemes, phonemeIndex: 0) {
            // After this syllable's phonemes, play next syllable
            self.playRemainingSyllables(syllables, index: index + 1)
        }
    }
    
    func playRemainingSyllablePhonemes(_ phonemes: [Phoneme], phonemeIndex: Int, completion: @escaping () -> Void) {
        guard phonemeIndex < phonemes.count else {
            completion()
            return
        }
        
        let phoneme = phonemes[phonemeIndex]
        
        // Stop previous
        if let note = activeNote {
            midiService.sendNoteOff(note: note)
        }
        
        // Play this phoneme
        midiService.consonant = phoneme.consonant
        midiService.vowel = phoneme.vowel
        midiService.sendNoteOn(note: phoneme.note)
        activeNote = phoneme.note
        
        // Schedule next
        let duration = phoneme.duration * beatDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.playRemainingSyllablePhonemes(phonemes, phonemeIndex: phonemeIndex + 1, completion: completion)
        }
    }
    
    func stopAllNotes() {
        if let note = activeNote {
            midiService.sendNoteOff(note: note)
        }
        for note in HaikuData.splashChord {
            midiService.sendNoteOff(note: note)
        }
        activeNote = nil
    }
    
    // MARK: - Playback Controls
    
    func togglePlayback() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }
    
    func play() {
        isPlaying = true
        currentWordIndex = 0
        currentSyllableIndex = 0
        currentPhonemeIndex = 0
        playSequence()
    }
    
    func playSequence() {
        // Flatten all phonemes for sequential playback
        let allPhonemes = words.flatMap { $0.allPhonemes }
        playAllPhonemes(allPhonemes, index: 0)
    }
    
    func playAllPhonemes(_ phonemes: [Phoneme], index: Int) {
        guard isPlaying else { return }
        guard index < phonemes.count else {
            // Done
            isPlaying = false
            currentWordIndex = 0
            currentSyllableIndex = 0
            return
        }
        
        let phoneme = phonemes[index]
        
        // Stop previous
        if let note = activeNote {
            midiService.sendNoteOff(note: note)
        }
        
        // Update position tracking (approximate)
        updatePositionForPhonemeIndex(index)
        
        // Play
        midiService.consonant = phoneme.consonant
        midiService.vowel = phoneme.vowel
        
        if phoneme.isChord {
            for note in HaikuData.splashChord {
                midiService.sendNoteOn(note: note)
            }
            activeNote = HaikuData.splashChord[0]
        } else {
            midiService.sendNoteOn(note: phoneme.note)
            activeNote = phoneme.note
        }
        
        // Schedule next
        let duration = phoneme.duration * beatDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.playAllPhonemes(phonemes, index: index + 1)
        }
    }
    
    func updatePositionForPhonemeIndex(_ globalIndex: Int) {
        var count = 0
        for (wIdx, word) in words.enumerated() {
            for (sIdx, syllable) in word.syllables.enumerated() {
                for _ in syllable.phonemes {
                    if count == globalIndex {
                        currentWordIndex = wIdx
                        currentSyllableIndex = sIdx
                        return
                    }
                    count += 1
                }
            }
        }
    }
    
    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        stopAllNotes()
    }
    
    func reset() {
        currentWordIndex = 0
        currentSyllableIndex = 0
        currentPhonemeIndex = 0
    }
}

// MARK: - Helper for rounded corners on specific sides

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)
        
        let topLeft = corners.contains(.topLeft) ? r : 0
        let topRight = corners.contains(.topRight) ? r : 0
        let bottomRight = corners.contains(.bottomRight) ? r : 0
        let bottomLeft = corners.contains(.bottomLeft) ? r : 0
        
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        if topRight > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight), radius: topRight, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        if bottomRight > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight), radius: bottomRight, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        if bottomLeft > 0 {
            path.addArc(center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft), radius: bottomLeft, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        if topLeft > 0 {
            path.addArc(center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft), radius: topLeft, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        
        return path
    }
}

// UIRectCorner equivalent for macOS
struct UIRectCorner: OptionSet {
    let rawValue: Int
    
    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
