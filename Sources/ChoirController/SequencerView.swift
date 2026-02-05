import SwiftUI

/// A single syllable with its phoneme mapping and display text
struct Syllable: Identifiable {
    let id = UUID()
    let text: String           // Display text (e.g., "An")
    let consonant: UInt8       // CC2 value
    let vowel: UInt8           // CC3 value
    let note: UInt8            // MIDI note to play (or root note for chords)
    let duration: Double       // Duration in beats (1.0 = quarter, 0.5 = eighth)
    let wordIndex: Int         // Which word this belongs to (for shading)
    let isChord: Bool          // If true, play as chord (multiple notes)
    
    init(text: String, consonant: UInt8, vowel: UInt8, note: UInt8, duration: Double = 1.0, word: Int = 0, isChord: Bool = false) {
        self.text = text
        self.consonant = consonant
        self.vowel = vowel
        self.note = note
        self.duration = duration
        self.wordIndex = word
        self.isChord = isChord
    }
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
    static let C_F: UInt8 = 27
    static let C_FR: UInt8 = 37
    static let C_G: UInt8 = 40
    static let C_DJ: UInt8 = 53
    static let C_L: UInt8 = 66
    static let C_M: UInt8 = 69
    static let C_N: UInt8 = 73
    static let C_P: UInt8 = 79
    static let C_S: UInt8 = 92
    static let C_SL: UInt8 = 96
    static let C_SH: UInt8 = 100    // try middle of 99-101 range
    static let C_T: UInt8 = 102
    static let C_TH: UInt8 = 109
    
    // Vowel CC values
    static let V_AA: UInt8 = 8      // ɑː (star)
    static let V_AI: UInt8 = 19     // aɪ (buy/sigh) - middle of range 16-22
    static let V_AE: UInt8 = 23     // æ (pat)
    static let V_SCHWA: UInt8 = 31  // ə (the) - used for trailing consonants
    static let V_AW: UInt8 = 38     // ɔː (store)
    static let V_O: UInt8 = 53      // ɒ (pot)
    static let V_UH: UInt8 = 61     // ʌ (cut)
    static let V_OO: UInt8 = 68     // uː (zoo)
    static let V_EE: UInt8 = 76     // iː (free)
    static let V_AY: UInt8 = 91     // eɪ (stray)
    static let V_MMM: UInt8 = 113   // m (nasal mmm) - for N, M sounds
    
    static let line1: [Syllable] = [
        // "An old silent pond" - words 0, 1, 2, 3
        Syllable(text: "A", consonant: C_NONE, vowel: V_AE, note: 60, duration: 0.6, word: 0),
        Syllable(text: "n", consonant: C_N, vowel: V_MMM, note: 60, duration: 0.4, word: 0),
        Syllable(text: "ol", consonant: C_NONE, vowel: V_AW, note: 62, duration: 0.6, word: 1),
        Syllable(text: "d", consonant: C_D, vowel: V_SCHWA, note: 62, duration: 0.4, word: 1),
        // "silent" 
        Syllable(text: "si", consonant: C_S, vowel: V_AI, note: 64, duration: 0.8, word: 2),
        Syllable(text: "len", consonant: C_L, vowel: V_SCHWA, note: 65, duration: 0.4, word: 2),
        Syllable(text: "t", consonant: C_N, vowel: V_MMM, note: 65, duration: 0.3, word: 2),
        // "pond"
        Syllable(text: "po", consonant: C_P, vowel: V_O, note: 67, duration: 0.5, word: 3),
        Syllable(text: "n", consonant: C_N, vowel: V_MMM, note: 67, duration: 0.3, word: 3),
        Syllable(text: "d", consonant: C_D, vowel: V_SCHWA, note: 67, duration: 0.7, word: 3),
    ]
    
    static let line2: [Syllable] = [
        // "A frog jumps into the pond" - words 4, 5, 6, 7, 8, 9
        Syllable(text: "A", consonant: C_NONE, vowel: V_SCHWA, note: 67, duration: 0.5, word: 4),
        Syllable(text: "fro", consonant: C_FR, vowel: V_O, note: 65, duration: 0.6, word: 5),
        Syllable(text: "g", consonant: C_G, vowel: V_SCHWA, note: 65, duration: 0.4, word: 5),
        // "jumps"
        Syllable(text: "jum", consonant: C_DJ, vowel: V_UH, note: 64, duration: 0.4, word: 6),
        Syllable(text: "m", consonant: C_M, vowel: V_MMM, note: 64, duration: 0.3, word: 6),
        Syllable(text: "s", consonant: C_S, vowel: V_SCHWA, note: 64, duration: 0.3, word: 6),
        // "into"
        Syllable(text: "in", consonant: C_NONE, vowel: V_EE, note: 62, duration: 0.4, word: 7),
        Syllable(text: "to", consonant: C_T, vowel: V_OO, note: 60, duration: 0.5, word: 7),
        // "the"
        Syllable(text: "the", consonant: C_TH, vowel: V_SCHWA, note: 62, duration: 0.5, word: 8),
        // "pond"
        Syllable(text: "po", consonant: C_P, vowel: V_O, note: 64, duration: 0.5, word: 9),
        Syllable(text: "n", consonant: C_N, vowel: V_MMM, note: 64, duration: 0.3, word: 9),
        Syllable(text: "d", consonant: C_D, vowel: V_SCHWA, note: 64, duration: 0.7, word: 9),
    ]
    
    // Chord notes for "Splash!" - C major chord (C4, E4, G4)
    static let splashChord: [UInt8] = [60, 64, 67]  // C, E, G
    
    static let line3: [Syllable] = [
        // "Splash! Silence again" - words 10, 11, 12
        // "Splash" as a single powerful syllable (chord will be triggered separately)
        Syllable(text: "Splash!", consonant: C_SL, vowel: V_AE, note: 72, duration: 1.2, word: 10, isChord: true),
        // "Silence"
        Syllable(text: "Si", consonant: C_S, vowel: V_AI, note: 69, duration: 0.8, word: 11),
        Syllable(text: "len", consonant: C_L, vowel: V_SCHWA, note: 67, duration: 0.5, word: 11),
        Syllable(text: "ce", consonant: C_N, vowel: V_MMM, note: 67, duration: 0.2, word: 11),
        // "again"
        Syllable(text: "a", consonant: C_NONE, vowel: V_SCHWA, note: 65, duration: 0.3, word: 12),
        Syllable(text: "gain", consonant: C_G, vowel: V_AY, note: 64, duration: 0.7, word: 12),
        Syllable(text: "n", consonant: C_N, vowel: V_MMM, note: 64, duration: 0.5, word: 12),
    ]
    
    static let fullHaiku: [Syllable] = line1 + line2 + line3
}

struct SequencerView: View {
    @ObservedObject var midiService: MidiService
    
    @State private var isPlaying = false
    @State private var currentIndex = 0
    @State private var timer: Timer?
    @State private var isHoldingSyllable = false  // For manual syllable testing
    @State private var tempo: Double = 100  // BPM (adjustable)
    let syllables = HaikuData.fullHaiku
    
    var beatDuration: Double {
        60.0 / tempo  // seconds per beat
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Haiku Sequencer")
                .font(.headline)
            
            // Display syllables with cursor
            syllableDisplay
            
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
                
                Text("\(currentIndex + 1) / \(syllables.count)")
                    .monospacedDigit()
                    .foregroundColor(.secondary)
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
    
    var syllableDisplay: some View {
        // Wrap syllables in flowing text
        VStack(alignment: .leading, spacing: 8) {
            // Line 1: "An old silent pond"
            HStack(spacing: 4) {
                ForEach(Array(HaikuData.line1.enumerated()), id: \.element.id) { idx, syllable in
                    syllableView(syllable, globalIndex: idx)
                }
                Text("/")
                    .foregroundColor(.secondary)
            }
            
            // Line 2: "A frog jumps into the pond"
            HStack(spacing: 4) {
                ForEach(Array(HaikuData.line2.enumerated()), id: \.element.id) { idx, syllable in
                    syllableView(syllable, globalIndex: HaikuData.line1.count + idx)
                }
                Text("/")
                    .foregroundColor(.secondary)
            }
            
            // Line 3: "Splash! Silence again"
            HStack(spacing: 4) {
                ForEach(Array(HaikuData.line3.enumerated()), id: \.element.id) { idx, syllable in
                    syllableView(syllable, globalIndex: HaikuData.line1.count + HaikuData.line2.count + idx)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)  // Don't compress horizontally
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
    
    func syllableView(_ syllable: Syllable, globalIndex: Int) -> some View {
        let isCurrentNote = globalIndex == currentIndex
        // Alternate between light bg and darker bg for word boundaries
        let wordBgColor = syllable.wordIndex % 2 == 0 
            ? Color(white: 0.85)   // Light grey
            : Color(white: 0.65)   // Darker grey
        
        return Text(syllable.text)
            .fixedSize()  // Prevent truncation
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isCurrentNote ? Color.yellow : wordBgColor)
            .cornerRadius(4)
            .fontWeight(isCurrentNote ? .bold : .regular)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if currentIndex != globalIndex || !isHoldingSyllable {
                            playSyllableDown(globalIndex)
                        }
                    }
                    .onEnded { _ in
                        playSyllableUp(globalIndex)
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                    // Stop note if mouse leaves while holding
                    if isHoldingSyllable && currentIndex == globalIndex {
                        playSyllableUp(globalIndex)
                    }
                }
            }
    }
    
    func playSyllableDown(_ index: Int) {
        guard !isPlaying else { return }  // Don't interfere with playback
        
        // Stop any previously playing note
        if isHoldingSyllable && currentIndex < syllables.count {
            stopSyllable(syllables[currentIndex])
        }
        
        // Update state
        currentIndex = index
        isHoldingSyllable = true
        
        // Play the syllable
        let syllable = syllables[index]
        midiService.consonant = syllable.consonant
        midiService.vowel = syllable.vowel
        
        if syllable.isChord {
            // Play chord
            for note in HaikuData.splashChord {
                midiService.sendNoteOn(note: note)
            }
            print("🎵 Press CHORD: '\(syllable.text)' - notes: \(HaikuData.splashChord)")
        } else {
            midiService.sendNoteOn(note: syllable.note)
            print("🎵 Press: '\(syllable.text)' - C:\(syllable.consonant) V:\(syllable.vowel) N:\(syllable.note)")
        }
    }
    
    func playSyllableUp(_ index: Int) {
        guard isHoldingSyllable else { return }
        
        isHoldingSyllable = false
        
        if index < syllables.count {
            stopSyllable(syllables[index])
            print("🎵 Release: '\(syllables[index].text)'")
        }
    }
    
    func togglePlayback() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }
    
    func play() {
        isPlaying = true
        playCurrentSyllable()
        scheduleNextSyllable()
    }
    
    func scheduleNextSyllable() {
        guard currentIndex < syllables.count else { return }
        
        let currentDuration = syllables[currentIndex].duration * beatDuration
        
        timer = Timer.scheduledTimer(withTimeInterval: currentDuration, repeats: false) { [self] _ in
            // Send note off for current syllable
            stopSyllable(syllables[currentIndex])
            
            // Move to next syllable
            currentIndex += 1
            
            if currentIndex >= syllables.count {
                // Finished - stop and reset
                isPlaying = false
                timer = nil
                currentIndex = 0
                return
            }
            
            // Small delay before next note to let Choir process CC changes
            // This prevents muddy sounds when CCs change between syllables
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [self] in
                guard isPlaying else { return }  // Check we didn't stop during delay
                playCurrentSyllable()
                scheduleNextSyllable()
            }
        }
    }
    
    func stop() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
        
        // Send note off for the last played note
        let lastPlayedIndex = min(currentIndex, syllables.count - 1)
        stopSyllable(syllables[lastPlayedIndex])
    }
    
    func reset() {
        currentIndex = 0
    }
    
    func playCurrentSyllable() {
        guard currentIndex < syllables.count else { return }
        
        let syllable = syllables[currentIndex]
        
        // Send note off for previous note (if any)
        if currentIndex > 0 {
            let prevSyllable = syllables[currentIndex - 1]
            stopSyllable(prevSyllable)
        }
        
        // Set phoneme values
        midiService.consonant = syllable.consonant
        midiService.vowel = syllable.vowel
        
        // Play note(s) - sendNoteOn will send CC values first
        if syllable.isChord {
            // Play chord - multiple notes distributed across dolls
            for note in HaikuData.splashChord {
                midiService.sendNoteOn(note: note)
            }
            print("🎵 Playing CHORD: '\(syllable.text)' - notes: \(HaikuData.splashChord)")
        } else {
            midiService.sendNoteOn(note: syllable.note)
            print("🎵 Playing: '\(syllable.text)' - C:\(syllable.consonant) V:\(syllable.vowel) N:\(syllable.note)")
        }
    }
    
    func stopSyllable(_ syllable: Syllable) {
        if syllable.isChord {
            // Stop all chord notes
            for note in HaikuData.splashChord {
                midiService.sendNoteOff(note: note)
            }
        } else {
            midiService.sendNoteOff(note: syllable.note)
        }
    }
}
