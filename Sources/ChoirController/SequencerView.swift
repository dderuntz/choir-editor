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

/// A score - a complete piece with lines of words
struct Score: Identifiable {
    let id = UUID()
    let title: String
    let lines: [[Word]]
    
    var allWords: [Word] { lines.flatMap { $0 } }
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
///    - "Spl" → use "Pl" (closest available)
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
    static let C_PL: UInt8 = 83
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
    static let V_NONE: UInt8 = 121  // pure consonant (silence/breath)
    
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
                Phoneme("d", c: C_D, v: V_NONE, note: 62, dur: 0.3)
            ])
        ]),
        // "silent" - 2 syllables: si·lent
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("SUY", c: C_S, v: V_AI, note: 64, dur: 0.3),
                Phoneme("EE", c: C_NONE, v: V_EE, note: 64, dur: 0.4)
            ]),
            Syllable(phonemes: [
                Phoneme("Le", c: C_L, v: V_SCHWA, note: 65, dur: 0.3),
                Phoneme("nn", c: C_N, v: V_MMM, note: 65, dur: 0.3),
                Phoneme("t", c: C_T, v: V_NONE, note: 65, dur: 0.2)
            ])
        ]),
        // "pond" - 1 syllable
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("po", c: C_P, v: V_O, note: 67, dur: 0.5),
                Phoneme("n", c: C_N, v: V_MMM, note: 67, dur: 0.3),
                Phoneme("d", c: C_D, v: V_NONE, note: 67, dur: 0.5)
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
                Phoneme("g", c: C_G, v: V_NONE, note: 65, dur: 0.3)
            ])
        ]),
        // "jumps"
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("jum", c: C_DJ, v: V_UH, note: 64, dur: 0.4),
                Phoneme("ps", c: C_S, v: V_NONE, note: 64, dur: 0.3)
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
                Phoneme("d", c: C_D, v: V_NONE, note: 64, dur: 0.5)
            ])
        ])
    ]
    
    // Line 3: "Splash! Silence again"
    static let line3: [Word] = [
        // "Splash!" - S + pla + sh (using Pl cluster, closest to Spl)
        Word(syllables: [
            Syllable(phonemes: [
                // S (Prefix)
                Phoneme("S", c: C_S, v: V_NONE, note: 72, dur: 0.15),
                // pla (Body) using C_PL (83)
                Phoneme("pla", c: C_PL, v: V_AE, note: 72, dur: 0.6),
                // sh (Tail)
                Phoneme("sh!", c: C_SH, v: V_NONE, note: 72, dur: 0.4)
            ])
        ]),
        // "Silence" - 2 syllables: Si·lence (Si -> SUY-EE, lence -> Le-nnn-sss)
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("SUY", c: C_S, v: V_AI, note: 69, dur: 0.3),
                Phoneme("EE", c: C_NONE, v: V_EE, note: 69, dur: 0.4)
            ]),
            Syllable(phonemes: [
                Phoneme("Le", c: C_L, v: V_SCHWA, note: 67, dur: 0.3),
                Phoneme("nnn", c: C_N, v: V_MMM, note: 67, dur: 0.3),
                Phoneme("sss", c: C_S, v: V_NONE, note: 67, dur: 0.3)
            ])
        ]),
        // "again" - 2 syllables: a·gain
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("a", c: C_NONE, v: V_SCHWA, note: 65, dur: 0.3)
            ]),
            Syllable(phonemes: [
                Phoneme("gain", c: C_G, v: V_AE, note: 64, dur: 0.4),
                Phoneme("n", c: C_N, v: V_MMM, note: 64, dur: 0.4)
            ])
        ])
    ]
    
    static let allWords: [Word] = line1 + line2 + line3
    
    static let haikuScore = Score(
        title: "Haiku",
        lines: [line1, line2, line3]
    )
}

// MARK: - IDEO AI DAY Score

struct IDEOData {
    // Reuse consonant/vowel constants from HaikuData
    static let C_NONE = HaikuData.C_NONE
    static let C_D = HaikuData.C_D
    
    static let V_AI = HaikuData.V_AI      // aɪ (eye)
    static let V_EE = HaikuData.V_EE      // iː (dee)
    static let V_AW = HaikuData.V_AW      // oʊ-ish (oh)
    static let V_AY = HaikuData.V_AY      // eɪ (ay/day)
    
    // "IDEO AI DAY"
    // IDEO = eye-dee-oh (1 word, 3 syllables)
    // AI = ay-eye (1 word, 2 syllables) 
    // DAY = day (1 word, 1 syllable)
    
    static let V_EYE: UInt8 = 20      // aɪ (eye) - trying 20
    
    static let line1: [Word] = [
        // IDEO (1 word, 3 syllables)
        Word(syllables: [
            // I (Eye) -> AI + EE
            Syllable(phonemes: [
                Phoneme("I-1", c: C_NONE, v: V_AI, note: 64, dur: 0.3), // Start
                Phoneme("I-2", c: C_NONE, v: V_EE, note: 64, dur: 0.3)  // Glide end
            ]),
            // DE (Dee)
            Syllable(phonemes: [
                Phoneme("DE", c: C_D, v: V_EE, note: 67, dur: 0.5)
            ]),
            // O (Oh) -> AW + OO? Or just AW
            Syllable(phonemes: [
                Phoneme("O", c: C_NONE, v: V_AW, note: 72, dur: 0.6)
            ])
        ]),
        // AI (1 word, 2 syllables: A, I) -> Ay-Eye
        Word(syllables: [
            // A (Ay) -> AY + EE
            Syllable(phonemes: [
                Phoneme("A-1", c: C_NONE, v: V_AY, note: 69, dur: 0.3),
                Phoneme("A-2", c: C_NONE, v: V_EE, note: 69, dur: 0.2)
            ]),
            // I (Eye) -> AI + EE
            Syllable(phonemes: [
                Phoneme("I-1", c: C_NONE, v: V_AI, note: 71, dur: 0.3),
                Phoneme("I-2", c: C_NONE, v: V_EE, note: 71, dur: 0.3)
            ])
        ]),
        // DAY (1 word, 1 syllable) -> D + AY + EE
        Word(syllables: [
            Syllable(phonemes: [
                Phoneme("DA", c: C_D, v: V_AY, note: 72, dur: 0.4),
                Phoneme("Y", c: C_NONE, v: V_EE, note: 72, dur: 0.4)
            ])
        ])
    ]
    
    static let ideoScore = Score(
        title: "IDEO AI DAY",
        lines: [line1]
    )
}

// MARK: - All Scores

struct Scores {
    static let all: [Score] = [
        HaikuData.haikuScore,
        IDEOData.ideoScore
    ]
}

// MARK: - Sequencer View

struct SequencerView: View {
    var midiService: MidiService  // Don't observe to prevent redraws on CC changes during playback
    
    @State private var isPlaying = false
    var beatDuration: Double { 60.0 / midiService.tempo }
    @State private var timer: Timer?
    
    // Selected score (tab)
    @State private var selectedScoreIndex = 0
    
    // Track current position for auto-playback
    @State private var currentWordIndex = 0
    @State private var currentSyllableIndex = 0
    @State private var currentPhonemeIndex = 0
    
    @State private var debugLastClick = "None"
    
    // MARK: Mouse + Hover Tracking
    // Each phoneme button tracks its own hover state and triggers itself directly.
    // No frame-based hit-testing, no GeometryReader, no stale coordinate lookups.
    @State private var isMouseDown = false
    @State private var mouseMonitor: Any?
    
    // Which phoneme the cursor is currently over (set by each phoneme's .onHover)
    @State private var hoveredWordIndex: Int?
    @State private var hoveredSyllableIndex: Int?
    @State private var hoveredPhonemeIndex: Int?
    @State private var hoveredPhonemeData: Phoneme?
    
    // For manual interaction (holding a phoneme)
    @State private var isHolding = false
    @State private var holdingWordIndex: Int?
    @State private var holdingSyllableIndex: Int?
    @State private var holdingPhonemeIndex: Int?
    @State private var currentHeldPhoneme: Phoneme?
    @State private var pressStartTime: Date?
    
    // Note cache: tracks all notes we've turned on with whether they're chorus (harmony) notes
    struct CachedNote: Equatable {
        let note: UInt8
        let isChorus: Bool  // true = harmony note (3rd/5th), false = root note
    }
    @State private var noteCache: [CachedNote] = []
    
    var currentScore: Score { Scores.all[selectedScoreIndex] }
    var words: [Word] { currentScore.allWords }
    
    var body: some View {
        VStack(spacing: 12) {
            // Tab bar for scores
            HStack(spacing: 0) {
                ForEach(Array(Scores.all.enumerated()), id: \.element.id) { idx, score in
                    Button(action: { 
                        if !isPlaying {
                            selectedScoreIndex = idx 
                            reset()
                        }
                    }) {
                        Text(score.title)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(selectedScoreIndex == idx ? Color.accentColor : Color.gray.opacity(0.3))
                            .foregroundColor(selectedScoreIndex == idx ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
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
            
            // DEBUG INFO
            Text("Debug: \(debugLastClick)")
                .font(.caption)
                .foregroundColor(.red)
            
            Text("Settings moved to sidebar")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            installMouseMonitor()
            dumpAllWords()
        }
        .onDisappear { removeMouseMonitor() }
    }
    
    // MARK: - Debug Dump
    
    func dumpAllWords() {
        print("====== WORD DUMP ======")
        for (wIdx, word) in words.enumerated() {
            let phonemeTexts = word.allPhonemes.map { "\($0.text)(C:\($0.consonant) V:\($0.vowel))" }
            print("Word \(wIdx): [\(phonemeTexts.joined(separator: ", "))]")
            for (sIdx, syl) in word.syllables.enumerated() {
                for (pIdx, ph) in syl.phonemes.enumerated() {
                    print("  \(wIdx)-\(sIdx)-\(pIdx): '\(ph.text)' C:\(ph.consonant) V:\(ph.vowel) note:\(ph.note)")
                }
            }
        }
        print("====== END DUMP ======")
    }
    
    // MARK: - Mouse Event Monitor
    
    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .flagsChanged]) { [self] event in
            switch event.type {
            case .leftMouseDown:
                isMouseDown = true
                // Trigger whatever phoneme the cursor is currently hovering over
                if let wIdx = hoveredWordIndex,
                   let sIdx = hoveredSyllableIndex,
                   let pIdx = hoveredPhonemeIndex,
                   let phoneme = hoveredPhonemeData {
                    handlePhonemePress(wordIndex: wIdx, syllableIndex: sIdx, phonemeIndex: pIdx, phoneme: phoneme)
                }
            case .leftMouseUp:
                isMouseDown = false
                if isHolding {
                    handlePhonemeRelease()
                }
            case .flagsChanged:
                // Handle shift key toggle while holding a phoneme
                if isHolding, let phoneme = currentHeldPhoneme {
                    let shiftNow = event.modifierFlags.contains(.shift)
                    let hasChorus = noteCache.contains { $0.isChorus }
                    if shiftNow && !hasChorus {
                        addChorusNotes(for: phoneme)
                    } else if !shiftNow && hasChorus {
                        removeChorusNotes()
                    }
                }
            default:
                break
            }
            return event  // Don't consume - let other views (buttons, etc.) process normally
        }
    }
    
    private func removeMouseMonitor() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }
    
    // MARK: - Word Display (no DragGesture, no frame tracking)
    
    var wordDisplay: some View {
        VStack(alignment: .leading, spacing: 10) {
            let lines = currentScore.lines
            
            ForEach(Array(lines.enumerated()), id: \.offset) { lineIdx, lineWords in
                let offset = lines.prefix(lineIdx).flatMap { $0 }.count
                let showSlash = lineIdx < lines.count - 1
                lineView(lineWords, lineOffset: offset, showSlash: showSlash)
            }
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
    
    func lineView(_ lineWords: [Word], lineOffset: Int, showSlash: Bool) -> some View {
        HStack(spacing: 24) {
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
        HStack(spacing: 3) {
            ForEach(Array(word.syllables.enumerated()), id: \.element.id) { sylIdx, syllable in
                syllableButton(syllable, wordIndex: wordIndex, syllableIndex: sylIdx)
            }
        }
    }
    
    func syllableButton(_ syllable: Syllable, wordIndex: Int, syllableIndex: Int) -> some View {
        let baseBg = wordIndex % 2 == 0 ? Color(white: 0.85) : Color(white: 0.70)
        
        return HStack(spacing: 0) {
            ForEach(Array(syllable.phonemes.enumerated()), id: \.element.id) { pIdx, phoneme in
                phonemeSegment(phoneme, 
                              wordIndex: wordIndex,
                              syllableIndex: syllableIndex,
                              phonemeIndex: pIdx,
                              isLast: pIdx == syllable.phonemes.count - 1,
                              baseBg: baseBg)
            }
        }
        .padding(.bottom, 16)  // Room for debug labels below buttons
    }
    
    func phonemeSegment(_ phoneme: Phoneme, wordIndex: Int, syllableIndex: Int, phonemeIndex: Int, isLast: Bool, baseBg: Color) -> some View {
        // Highlight if this specific phoneme is being held
        let isActivePhoneme = isHolding && 
            holdingWordIndex == wordIndex && 
            holdingSyllableIndex == syllableIndex && 
            holdingPhonemeIndex == phonemeIndex
        // Debug: color phonemes R/G/B by index to see if views overlap
        let debugColors: [Color] = [.red.opacity(0.3), .green.opacity(0.3), .blue.opacity(0.3)]
        let debugBg = debugColors[phonemeIndex % 3]
        let bg = isActivePhoneme ? Color.yellow : debugBg
        
        return Text(phoneme.text)
            .font(.title2)
            .fixedSize()
            .frame(minWidth: 60)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .fontWeight(isActivePhoneme ? .bold : .regular)
            .overlay(alignment: .bottom) {
                Text("\(wordIndex)-\(syllableIndex)-\(phonemeIndex)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
                    .offset(y: 14)
            }
            .overlay(alignment: .trailing) {
                if !isLast {
                    Rectangle()
                        .fill(Color(white: 0.5))
                        .frame(width: 1)
                        .padding(.vertical, 2)
                }
            }
            .background(bg)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                    print("👆 HOVER IN: \(wordIndex)-\(syllableIndex)-\(phonemeIndex) '\(phoneme.text)' C:\(phoneme.consonant) V:\(phoneme.vowel)")
                    hoveredWordIndex = wordIndex
                    hoveredSyllableIndex = syllableIndex
                    hoveredPhonemeIndex = phonemeIndex
                    hoveredPhonemeData = phoneme
                    if isMouseDown && !isPlaying {
                        handlePhonemePress(wordIndex: wordIndex, syllableIndex: syllableIndex, phonemeIndex: phonemeIndex, phoneme: phoneme)
                    }
                } else {
                    NSCursor.pop()
                    print("👆 HOVER OUT: \(wordIndex)-\(syllableIndex)-\(phonemeIndex) '\(phoneme.text)'")
                    if hoveredWordIndex == wordIndex &&
                       hoveredSyllableIndex == syllableIndex &&
                       hoveredPhonemeIndex == phonemeIndex {
                        hoveredWordIndex = nil
                        hoveredSyllableIndex = nil
                        hoveredPhonemeIndex = nil
                        hoveredPhonemeData = nil
                    }
                }
            }
    }
    
    // MARK: - Press/Release Interaction
    
    /// Handle press on individual phoneme (called from mouse-down or drag-to-switch via hover)
    func handlePhonemePress(wordIndex: Int, syllableIndex: Int, phonemeIndex: Int, phoneme: Phoneme) {
        guard !isPlaying else { return }
        
        debugLastClick = "Pressed: \(wordIndex)-\(syllableIndex)-\(phonemeIndex) (\(phoneme.text)) C:\(phoneme.consonant) V:\(phoneme.vowel)"
        
        // If already holding this exact phoneme, do nothing (prevents re-trigger)
        if isHolding && holdingWordIndex == wordIndex && holdingSyllableIndex == syllableIndex && holdingPhonemeIndex == phonemeIndex {
            return
        }
        
        // Stop any currently playing notes
        stopAllCachedNotes()
        
        // Update state
        isHolding = true
        holdingWordIndex = wordIndex
        holdingSyllableIndex = syllableIndex
        holdingPhonemeIndex = phonemeIndex
        currentWordIndex = wordIndex
        currentSyllableIndex = syllableIndex
        currentHeldPhoneme = phoneme
        pressStartTime = Date()
        
        // Check shift at moment of press
        let shiftPressed = NSEvent.modifierFlags.contains(.shift)
        
        print("🎵 Press: '\(phoneme.text)' - C:\(phoneme.consonant) V:\(phoneme.vowel) \(shiftPressed ? "[CHORD]" : "")")
        
        // Set CCs for this phoneme, then play
        midiService.consonant = phoneme.consonant
        midiService.vowel = phoneme.vowel
        midiService.sendNoteOn(note: phoneme.note)
        noteCache.append(CachedNote(note: phoneme.note, isChorus: false))
        
        // If shift held, also play chorus notes
        if shiftPressed {
            addChorusNotes(for: phoneme)
        }
    }
    
    /// Handle release - stop current note, then auto-complete rest of word
    func handlePhonemeRelease() {
        guard isHolding else { return }
        guard let wordIdx = holdingWordIndex, 
              let sylIdx = holdingSyllableIndex,
              let phonIdx = holdingPhonemeIndex else {
            isHolding = false
            stopAllCachedNotes()
            return
        }
        
        isHolding = false
        
        let word = words[wordIdx]
        let syllable = word.syllables[sylIdx]
        
        // Get remaining phonemes in current syllable (after the held one)
        let remainingPhonemesInSyllable = Array(syllable.phonemes.dropFirst(phonIdx + 1))
        
        // Get remaining syllables in word
        let remainingSyllables = Array(word.syllables.dropFirst(sylIdx + 1))
        
        // If nothing left, stop immediately
        if remainingPhonemesInSyllable.isEmpty && remainingSyllables.isEmpty {
            stopAllCachedNotes()
            holdingWordIndex = nil
            holdingSyllableIndex = nil
            holdingPhonemeIndex = nil
            return
        }
        
        // Calculate how much time remains to satisfy minNoteDuration
        let elapsed = pressStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let remaining = max(midiService.minNoteDuration - elapsed, 0)
        
        // Let current note KEEP PLAYING through the remaining duration,
        // THEN stop it and auto-complete the rest of the word
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [self] in
            stopAllCachedNotes()
            if !remainingPhonemesInSyllable.isEmpty {
                playRemainingPhonemesThenSyllables(remainingPhonemesInSyllable, thenSyllables: remainingSyllables)
            } else if !remainingSyllables.isEmpty {
                playRemainingSyllables(remainingSyllables, index: 0)
            }
        }
        
        holdingWordIndex = nil
        holdingSyllableIndex = nil
        holdingPhonemeIndex = nil
    }
    
    // MARK: - Word Auto-Completion (on release)
    
    func playRemainingPhonemesThenSyllables(_ phonemes: [Phoneme], thenSyllables syllables: [Syllable]) {
        playRemainingPhonemesSequence(phonemes, index: 0) { [self] in
            if !syllables.isEmpty {
                playRemainingSyllables(syllables, index: 0)
            } else {
                stopAllCachedNotes()
            }
        }
    }
    
    func playRemainingPhonemesSequence(_ phonemes: [Phoneme], index: Int, completion: @escaping () -> Void) {
        guard index < phonemes.count else {
            completion()
            return
        }
        
        let phoneme = phonemes[index]
        stopAllCachedNotes()
        
        let shiftHeld = NSEvent.modifierFlags.contains(.shift)
        playPhoneme(phoneme, asChord: shiftHeld)
        
        let isConsonant = phoneme.vowel == HaikuData.V_NONE
        let beats = isConsonant ? midiService.consonantDuration : phoneme.duration
        let duration = max(beats * beatDuration, midiService.minNoteDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in
            playRemainingPhonemesSequence(phonemes, index: index + 1, completion: completion)
        }
    }
    
    func playRemainingSyllables(_ syllables: [Syllable], index: Int) {
        guard index < syllables.count else {
            stopAllCachedNotes()
            return
        }
        
        let syllable = syllables[index]
        playRemainingSyllablePhonemes(syllable.phonemes, phonemeIndex: 0) {
            self.playRemainingSyllables(syllables, index: index + 1)
        }
    }
    
    func playRemainingSyllablePhonemes(_ phonemes: [Phoneme], phonemeIndex: Int, completion: @escaping () -> Void) {
        guard phonemeIndex < phonemes.count else {
            completion()
            return
        }
        
        let phoneme = phonemes[phonemeIndex]
        stopAllCachedNotes()
        
        let shiftHeld = NSEvent.modifierFlags.contains(.shift)
        playPhoneme(phoneme, asChord: shiftHeld)
        
        let isConsonant = phoneme.vowel == HaikuData.V_NONE
        let beats = isConsonant ? midiService.consonantDuration : phoneme.duration
        let duration = max(beats * beatDuration, midiService.minNoteDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in
            playRemainingSyllablePhonemes(phonemes, phonemeIndex: phonemeIndex + 1, completion: completion)
        }
    }
    
    // MARK: - Sound Helpers
    
    /// Add chorus notes (3rd and 5th) for the current phoneme
    func addChorusNotes(for phoneme: Phoneme) {
        let third = phoneme.note + 4
        let fifth = phoneme.note + 7
        
        print("🎶 Adding chorus: \(third), \(fifth) for '\(phoneme.text)'")
        
        midiService.consonant = phoneme.consonant
        midiService.vowel = phoneme.vowel
        midiService.sendNoteOn(note: third)
        noteCache.append(CachedNote(note: third, isChorus: true))
        
        midiService.consonant = phoneme.consonant
        midiService.vowel = phoneme.vowel
        midiService.sendNoteOn(note: fifth)
        noteCache.append(CachedNote(note: fifth, isChorus: true))
    }
    
    /// Remove only the chorus notes (when shift is released)
    func removeChorusNotes() {
        let chorusNotes = noteCache.filter { $0.isChorus }
        for cached in chorusNotes {
            midiService.sendNoteOff(note: cached.note)
        }
        noteCache.removeAll { $0.isChorus }
        print("🎶 Removed chorus notes")
    }
    
    /// Stop all notes in the cache
    func stopAllCachedNotes() {
        print("🛑 stopAllCachedNotes - count: \(noteCache.count)")
        for cached in noteCache {
            print("  -> sending NoteOff \(cached.note)")
            midiService.sendNoteOff(note: cached.note)
        }
        noteCache.removeAll()
    }
    
    /// Play a phoneme, optionally as a chord
    func playPhoneme(_ phoneme: Phoneme, asChord: Bool = false) {
        let playAsChord = asChord || phoneme.isChord
        
        // Set CCs and play root note
        midiService.consonant = phoneme.consonant
        midiService.vowel = phoneme.vowel
        midiService.sendNoteOn(note: phoneme.note)
        noteCache.append(CachedNote(note: phoneme.note, isChorus: false))
        
        if playAsChord {
            let chordNotes = phoneme.isChord ? HaikuData.splashChord : chordFromNote(phoneme.note)
            for note in chordNotes.dropFirst() {
                midiService.consonant = phoneme.consonant
                midiService.vowel = phoneme.vowel
                midiService.sendNoteOn(note: note)
                noteCache.append(CachedNote(note: note, isChorus: true))
            }
        }
        
        print("🎵 Phoneme: '\(phoneme.text)' - C:\(phoneme.consonant) V:\(phoneme.vowel) \(playAsChord ? "[CHORD]" : "")")
    }
    
    // Build chord from a root note (root, +4 semitones, +7 semitones = major chord)
    func chordFromNote(_ root: UInt8) -> [UInt8] {
        return [root, root + 4, root + 7]
    }
    
    // MARK: - Auto-Playback Controls
    
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
        let allPhonemes = words.flatMap { $0.allPhonemes }
        playAllPhonemes(allPhonemes, index: 0)
    }
    
    func playAllPhonemes(_ phonemes: [Phoneme], index: Int) {
        guard isPlaying else { return }
        guard index < phonemes.count else {
            stopAllCachedNotes()
            isPlaying = false
            currentWordIndex = 0
            currentSyllableIndex = 0
            return
        }
        
        let phoneme = phonemes[index]
        
        stopAllCachedNotes()
        updatePositionForPhonemeIndex(index)
        
        guard isPlaying else { return }
        
        playPhoneme(phoneme, asChord: phoneme.isChord)
        
        let isConsonant = phoneme.vowel == HaikuData.V_NONE
        let beats = isConsonant ? midiService.consonantDuration : phoneme.duration
        let duration = max(beats * beatDuration, midiService.minNoteDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in
            playAllPhonemes(phonemes, index: index + 1)
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
        stopAllCachedNotes()
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
