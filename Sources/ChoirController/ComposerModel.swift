import Foundation
import Combine
import os
import FoundationModels

private let log = Logger(subsystem: "com.choir-arranger", category: "composer")

// MARK: - LLM Lyric Generation Types

@available(macOS 26, *)
@Generable
struct LLMLyric {
    @Guide(description: "A short lyric for singing. 2 lines separated by /. Each line 3-8 simple words.")
    let lyric: String
}

@available(macOS 26, *)
@Generable
struct LLMSwedishLyric {
    @Guide(description: "En kort svensk text för sång. 2 rader separerade med /. Varje rad 3-8 enkla svenska ord.")
    let lyric: String
}

// MARK: - Composer Persistence

private struct StoredPhoneme: Codable {
    let text: String
    let consonantCC: UInt8
    let vowelCC: UInt8
    let weight: Int
    var wordIndex: Int = 0
    var isEnsemble: Bool = false
}

private enum ComposerPersistence {
    private static let textKey = "composer.inputText"
    private static let phonemesKey = "composer.phonemes"

    static func saveText(_ text: String) {
        UserDefaults.standard.set(text, forKey: textKey)
    }

    static func loadText() -> String {
        UserDefaults.standard.string(forKey: textKey) ?? ""
    }

    static func savePhonemes(_ phonemes: [ChoirPhoneme]) {
        let stored = phonemes.map { StoredPhoneme(text: $0.text, consonantCC: $0.consonantCC, vowelCC: $0.vowelCC, weight: $0.weight, wordIndex: $0.wordIndex, isEnsemble: $0.isEnsemble) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: phonemesKey)
        }
    }

    static func loadPhonemes() -> [ChoirPhoneme] {
        guard let data = UserDefaults.standard.data(forKey: phonemesKey),
              let stored = try? JSONDecoder().decode([StoredPhoneme].self, from: data)
        else { return [] }
        return stored.map { ChoirPhoneme(text: $0.text, consonantCC: $0.consonantCC, vowelCC: $0.vowelCC, weight: $0.weight, wordIndex: $0.wordIndex, isEnsemble: $0.isEnsemble) }
    }
}

// MARK: - Composer Model

@MainActor
class ComposerModel: ObservableObject {
    @Published var inputText: String = "" {
        didSet { ComposerPersistence.saveText(inputText) }
    }
    @Published var phonemes: [ChoirPhoneme] = [] {
        didSet { ComposerPersistence.savePhonemes(phonemes) }
    }
    /// Text that was used to generate current phonemes; nil = never extracted or cleared.
    @Published var lastExtractedText: String? = nil

    /// True when phonemes exist but text has changed since last extraction — show Sync button.
    var needsSync: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !phonemes.isEmpty else { return false }
        return lastExtractedText != trimmed
    }
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var llmStatusMessage: String? = nil

    /// Whether the Composer has any content (for icon indicator)
    var hasContent: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !phonemes.isEmpty
    }

    // Undo — one level snapshot of text + phonemes
    private var undoText: String?
    private var undoPhonemes: [ChoirPhoneme]?
    @Published var canUndo: Bool = false

    func saveUndo() {
        undoText = inputText
        undoPhonemes = phonemes
        canUndo = true
    }

    @MainActor
    func undo() {
        guard let text = undoText, let ph = undoPhonemes else { return }
        inputText = text
        phonemes = ph
        undoText = nil
        undoPhonemes = nil
        canUndo = false
    }

    init() {
        inputText = ComposerPersistence.loadText()
        phonemes = ComposerPersistence.loadPhonemes()
        let t = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, !phonemes.isEmpty {
            lastExtractedText = t
        }
    }

    // Scale — synced from SequencerModel by ComposerView
    var musicalKey: MusicalKey = .C
    var scaleType: ScaleType = .pentatonicMajor

    // Speed multiplier (1.0 = normal, 1.5 = slower, 2.5 = slowest)
    @Published var speedMultiplier: Double = 1.0

    // Playback
    @Published var isPlaying: Bool = false
    var minNoteDuration: Int = 280 // ms, from Setup
    @Published var currentPlayIndex: Int? = nil
    @Published var currentBounceIndex: Int = 0     // which bounce we're on (0-based)
    @Published var currentBounceCount: Int = 1     // total bounces for current chip
    @Published var currentArcDuration: Int = 330   // ms per bounce — consistent rhythm
    @Published var bouncePhase: Int = 0              // 0 = going up, 1 = coming down
    private var playbackTask: Task<Void, Never>? = nil
    private var activeMidiPitches: Set<UInt8> = []

    // MARK: - Phoneme Extraction (language-aware)

    private let englishExtractor = EnglishPhonemeExtractor()
    private let swedishExtractor = SwedishPhonemeExtractor()

    /// Current app language from UserDefaults (resolved — never .system)
    private var currentLanguage: AppLanguage {
        let stored = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
        return stored.resolved
    }

    /// Check on-device LLM availability (macOS 26+ only)
    var isLLMAvailable: Bool {
        let extractor: any PhonemeExtracting = currentLanguage == .swedish ? swedishExtractor : englishExtractor
        let (available, message) = extractor.checkAvailability()
        if let msg = message { llmStatusMessage = msg }
        return available
    }

    @MainActor
    func extractPhonemes() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        saveUndo()
        isProcessing = true
        errorMessage = nil

        let extractor: any PhonemeExtracting = currentLanguage == .swedish ? swedishExtractor : englishExtractor
        let result = await extractor.extract(text: text)

        if let normalized = result.normalizedText {
            inputText = normalized
        }
        phonemes = result.phonemes
        if !result.phonemes.isEmpty {
            lastExtractedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        errorMessage = result.errorMessage
        isProcessing = false
    }

    // MARK: - Summon Song (LLM text generation)

    @MainActor
    func summonSong() async {
        guard !isProcessing else { return }
        saveUndo()
        isProcessing = true
        errorMessage = nil

        if #available(macOS 26, *) {
            await generateLyric()
        } else {
            errorMessage = "Requires macOS 26 (Tahoe)"
        }

        isProcessing = false
    }

    @available(macOS 26, *)
    @MainActor
    private func generateLyric() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let userPrompt = prompt.isEmpty ? "anything beautiful" : prompt

        // Read style from menu setting (defaults to senryū)
        let styleRaw = UserDefaults.standard.string(forKey: "lyricStyle") ?? LyricStyle.senryu.rawValue
        let style = LyricStyle(rawValue: styleRaw) ?? .senryu

        let lyricInstructions: String
        switch style {
        case .senryu:
            lyricInstructions = """
            You are a weary, tired robot writing short lyrics for a recital.
            You observe human life with dry wit and quiet humor.
            DO NOT be inspirational or uplifting. DO NOT include introductions or titles.
            Output ONLY the lyric lines. Simple words. Each line 3-8 words.

            EXAMPLES:
            "coffee" → the cup knows more than I do / it has seen me before dawn
            "deadlines" → the clock does not negotiate / it simply wins
            "my cat" → your cat composes better / than most of us ever will
            "Monday" → we meet again old friend / neither of us wanted this

            DO NOT repeat the examples. Write something new and original.
            """
        case .bellman:
            lyricInstructions = """
            You write short, vivid lyrics for a singing choir. Warm, musical, vivid scenes.
            DO NOT include any introduction, title, or quotation marks. Output ONLY the lyric lines.
            Simple words that sound good sung aloud. Each line 3-8 words.

            EXAMPLES:
            "morning" → the sun is waking slowly now / golden light on sleepy hills
            "the sea" → the waves remember every ship / that ever dared to leave the shore
            "rain" → raise a glass to gutters singing / lamplight dancing on the cobblestones
            "winter" → the frost has painted every window / with a song it heard last night

            DO NOT repeat the examples. Write something new and original.
            """
        case .kulning:
            lyricInstructions = """
            You write sparse, echoing lyrics like Swedish mountain herding calls — but for robots.
            A robot calling lost machines home across mountains. Haunting and simple.
            DO NOT include introductions or titles. Output ONLY the lyric words.
            EVERY line MUST blend nature and machine. Mountain AND wire. Snow AND signal. Always both.

            EXAMPLES:
            "morning" → come home over the mountain / your signal fades
            "winter" → snow on the antenna / silence answers
            "lost" → where did you go / the frequency carries nothing
            "night" → the stars ping overhead / no machine answers the valley
            "spring" → meltwater runs through the cables / wake up wake up

            DO NOT repeat the examples. Write something new and original.
            """
        case .dada:
            lyricInstructions = """
            You write absurdist, playful nonsense lyrics for a choir of robots.
            Surreal, unexpected, delightful. Objects do strange things. Logic is optional.
            DO NOT include introductions or titles. Output ONLY the lyric words.
            Each line 3-8 words.

            EXAMPLES:
            "breakfast" → the fork decided to leave today / it took the spoon's advice
            "Tuesday" → the calendar sneezed and lost a day / nobody noticed
            "shoes" → my left shoe sings opera / the right one just listens
            "rain" → the clouds are returning your mail / postage was insufficient

            DO NOT repeat the examples. Write something new and original.
            """
        case .nursery:
            lyricInstructions = """
            You write nursery rhymes for robots.
            Simple rhyming words, sing-song rhythm, fun to say out loud.
            DO NOT include introductions or titles. Output ONLY the rhyme.
            Short lines, simple words.

            EXAMPLES:
            "rain" → rain rain come and play / not so much I rust away
            "charging" → plug me in and dim the lights / beep boop boop now say goodnight
            "morning" → the sun came up the screen turned on / I sang a song but you were gone

            DO NOT repeat the examples. Write something new and original. It should be about the secret lives of robots.
            """
        case .svSenryu:
            lyricInstructions = """
            Du är en trött robot. Du skriver senryū på svenska för en konsert ingen kommer till.

            Senryū är en japansk form: två rader. Rad 1 observerar något vanligt. Rad 2 vänder på det.
            Humorn sitter i vändningen. Inte skämt. Inte sorg. Bara glappet mellan vad saker är och vad vi låtsas.

            Två rader separerade med /. Varje rad 3-8 enkla svenska ord.
            Inga inledningar. Inga titlar. Inget hopp. Bara texten.

            "kaffe" → koppen vet mer än jag / den har sett mig före gryningen
            "deadlines" → klockan förhandlar inte / den bara vinner
            "min katt" → din katt komponerar bättre / än de flesta av oss
            "måndag" → vi möts igen gamla vän / ingen av oss ville detta
            "semester" → vi packade väskorna med hopp / de kom hem tomma
            "wifi" → signalen lovar allt / men levererar ingenting
            "vår" → blommorna öppnar sig igen / som om förra gången räckte
            "möte" → alla nickar och ler / ingen minns varför

            Andra raden MÅSTE vända. Den måste överraska, underminera, eller tyst håna den första.
            Skriv något nytt. Eller inte. Det spelar knappt någon roll.
            """
        }

        let isSwedish = currentLanguage == .swedish
        let userMessage = isSwedish
            ? "Skriv en kort svensk text om: \(userPrompt)"
            : style == .kulning
                ? "Write a short singable robot lyric about: \(userPrompt)"
                : "Write a short singable lyric about: \(userPrompt)"

        do {
            let session = LanguageModelSession(instructions: Instructions(lyricInstructions))

            let rawLyric: String
            if isSwedish {
                let svResponse = try await session.respond(
                    to: userMessage,
                    generating: LLMSwedishLyric.self
                )
                rawLyric = svResponse.content.lyric
            } else {
                let enResponse = try await session.respond(
                    to: userMessage,
                    generating: LLMLyric.self
                )
                rawLyric = enResponse.content.lyric
            }

            let lyric = rawLyric
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " / ", with: " ")
                .replacingOccurrences(of: "/", with: " ")

            if !lyric.isEmpty {
                inputText = lyric
                print("[Composer] 🎵 Summoned (\(style.rawValue)): \(lyric)")
            }
        } catch {
            print("[Composer] ✗ Summon error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Scale Pitch Mapping

    /// Returns sorted MIDI note numbers in the chosen scale, centered around middle C range
    private func scaleNotes(center: UInt8 = 60, range: Int = 12) -> [UInt8] {
        let intervals = Array(scaleType.intervals).sorted()
        var notes: [UInt8] = []
        let root = musicalKey.rawValue
        for octaveOffset in -2...2 {
            for interval in intervals {
                let midi = root + (octaveOffset * 12) + interval + 48 // start from C3 area
                if midi >= Int(center) - range && midi <= Int(center) + range && midi >= 36 && midi <= 84 {
                    notes.append(UInt8(midi))
                }
            }
        }
        return notes.sorted()
    }

    /// Pick a pitch from the scale based on phoneme index and weight (fallback for single-phoneme)
    private func pitchForPhoneme(index: Int, weight: Int, total: Int) -> UInt8 {
        let notes = scaleNotes()
        guard !notes.isEmpty else { return 60 }
        let mid = notes.count / 2
        // Stressed syllables get higher pitches, unstressed stay near center
        let offset: Int
        switch weight {
        case 3: offset = Int.random(in: 1...3)   // reach up
        case 2: offset = Int.random(in: -1...1)   // hover near center
        default: offset = Int.random(in: -2...0)   // dip low
        }
        let idx = max(0, min(notes.count - 1, mid + offset))
        return notes[idx]
    }

    /// Pre-compute a phrase-shaped melody: sine arc + word sub-arcs + stress peaks + stepwise motion.
    /// Each call produces a unique variation — the arc envelope holds but the path through it differs,
    /// like a singer who knows the shape but phrases it differently each time.
    private func buildContour(for phonemes: [ChoirPhoneme]) -> [UInt8] {
        let notes = scaleNotes(center: 60, range: 24)  // full doll range (36–84)
        guard !notes.isEmpty, !phonemes.isEmpty else {
            return phonemes.map { _ in 60 }
        }

        let total = phonemes.count

        // Group phoneme indices by word
        var wordGroups: [Int: [Int]] = [:]
        for (i, p) in phonemes.enumerated() {
            wordGroups[p.wordIndex, default: []].append(i)
        }

        // Step 1-3: compute a normalized target value (0.0–1.0) per phoneme
        var targetValues = [Double](repeating: 0.5, count: total)
        for (i, phoneme) in phonemes.enumerated() {
            // Phrase-level arc: sine peaking ~60% through
            let progress = Double(i) / Double(max(1, total - 1))
            let phraseArc = sin(progress * .pi * 0.85 + 0.15)

            // Word-level sub-arc (±15% variation within each word)
            let wordPhonemes = wordGroups[phoneme.wordIndex] ?? [i]
            let posInWord = wordPhonemes.firstIndex(of: i) ?? 0
            let wordLen = wordPhonemes.count
            let wordProgress = wordLen > 1
                ? Double(posInWord) / Double(wordLen - 1)
                : 0.5
            let subArc = sin(wordProgress * .pi) * 0.15

            // Stress boost
            let stressBoost: Double
            switch phoneme.weight {
            case 3:  stressBoost = 0.2
            case 2:  stressBoost = 0.0
            default: stressBoost = -0.1
            }

            // Per-note jitter so each playthrough takes a different path.
            // Wider at the start of the phrase (±0.15) where we want variety,
            // settling to ±0.06 once the melody has established direction.
            let openingFade = max(0.06, 0.15 - Double(i) * 0.015)
            let jitter = Double.random(in: -openingFade...openingFade)

            // Normalize combined value into 0–1 range
            // phraseArc ranges ~0.15–1.0, so *0.5+0.25 maps it to ~0.33–0.75
            targetValues[i] = max(0, min(1, (phraseArc + subArc) * 0.5 + 0.25 + stressBoost + jitter))
        }

        // Steps 4-5: map targets to scale indices with stepwise constraint
        var resultPitches = [UInt8]()
        resultPitches.reserveCapacity(total)

        // First note lands freely at its target — no leash from a "previous" note.
        // Wide wander (±4 scale steps) is safe: scaleNotes() already clamps to doll range (36–84).
        let firstIdealIdx = Int((targetValues[0] * Double(notes.count - 1)).rounded())
        let startWander = Int.random(in: -4...4)
        var previousIdx = max(0, min(notes.count - 1, firstIdealIdx + startWander))
        resultPitches.append(notes[previousIdx])

        for i in 1..<total {
            let idealIdx = Int((targetValues[i] * Double(notes.count - 1)).rounded())
            // Vary step size: stressed syllables can leap up to 4 steps, unstressed 2-3.
            // scaleNotes array is the boundary — can't exceed doll range.
            let baseMax = phonemes[i].weight >= 3 ? 4 : 3
            let maxStep = Bool.random() ? baseMax : max(1, baseMax - 1)
            // Clamp to within maxStep of previous, then clamp to array bounds
            let constrained = max(0, min(notes.count - 1,
                max(previousIdx - maxStep, min(previousIdx + maxStep, idealIdx))
            ))
            resultPitches.append(notes[constrained])
            previousIdx = constrained
        }

        return resultPitches
    }

    /// Duration in ms based on weight, ensemble, and speed
    /// - weight 3 (primary stress): longest base (750ms)
    /// - weight 2 (secondary): medium (450ms)
    /// - weight 1 (unstressed): brief (280ms)
    /// - isEnsemble: 2x multiplier for choral notes
    /// - Logarithmic speed scaling so longer notes stretch proportionally more
    private func durationFor(weight: Int, isEnsemble: Bool = false) -> Int {
        // Base duration with more dramatic scaling for emphasis
        let base: Double
        switch weight {
        case 3: base = 750    // primary stress - long hold
        case 2: base = 450    // secondary stress - medium
        default: base = 280   // unstressed - brief
        }

        // Ensemble (chorus) notes hold 2x as long (dolls need more time)
        let ensembleMultiplier: Double = isEnsemble ? 2.0 : 1.0

        // Logarithmic speed scaling: longer notes stretch more at slower speeds
        let scaled = base * ensembleMultiplier * pow(speedMultiplier, base / 280.0)
        return max(minNoteDuration, Int(scaled))
    }

    /// Convenience wrapper for phoneme objects
    private func durationForPhoneme(_ phoneme: ChoirPhoneme) -> Int {
        durationFor(weight: phoneme.weight, isEnsemble: phoneme.isEnsemble)
    }

    /// Velocity based on weight
    private func velocityForWeight(_ weight: Int) -> UInt8 {
        switch weight {
        case 3: return 110
        case 2: return 90
        default: return 70
        }
    }

    // MARK: - Chord Progressions

    /// Scale-degree triads for a hymn-style progression (I-IV-V-I), adapted per scale type.
    /// Each inner array is 3 scale degrees (0-indexed) forming a triad.
    private func progressionForScale() -> [[Int]] {
        let degreesPerOctave = scaleType.intervals.count
        if degreesPerOctave <= 5 {
            // Pentatonic: adjacent-tone triads (only 5 notes available)
            return [[0, 1, 2], [1, 2, 3], [3, 4, 0], [0, 1, 2]]
        }
        // 7-note scales (Major, Minor, Dorian, etc.): standard tertian triads
        // I → IV → V → I
        return [[0, 2, 4], [3, 5, 0], [4, 6, 1], [0, 2, 4]]
    }

    /// Assign a chord (scale-degree triad) to each word, adapting progression length
    /// to the number of ensemble phonemes so chords have time to breathe.
    private func buildHarmony(for phonemes: [ChoirPhoneme]) -> [Int: [Int]] {
        let fullProgression = progressionForScale()

        // Count ensemble phonemes to decide how many chords we can afford
        let ensembleCount = phonemes.filter(\.isEnsemble).count

        let progression: [[Int]]
        if ensembleCount <= 6 {
            // Too few notes — stay on tonic (stable drone)
            progression = [fullProgression[0]]
        } else if ensembleCount <= 12 {
            // Enough for one departure: I → V → I
            progression = [fullProgression[0], fullProgression[2], fullProgression[0]]
        } else {
            // Full hymn: I → IV → V → I
            progression = fullProgression
        }

        // Collect unique word indices that have ensemble phonemes
        let ensembleWordIndices = Array(Set(
            phonemes.filter(\.isEnsemble).map(\.wordIndex)
        )).sorted()

        guard !ensembleWordIndices.isEmpty else { return [:] }

        // Distribute progression evenly across ensemble words
        var chordPerWord: [Int: [Int]] = [:]
        for (i, wordIdx) in ensembleWordIndices.enumerated() {
            let slot = (i * progression.count) / ensembleWordIndices.count
            let clampedSlot = min(slot, progression.count - 1)
            chordPerWord[wordIdx] = progression[clampedSlot]
        }

        return chordPerWord
    }

    /// Build up to 3 harmony voices from chord tones, voiced below the melody.
    /// Returns pitches with velocity-drop and reverb values matching the barbershop voicing.
    private func ensembleVoices(
        melody: UInt8,
        chordDegrees: [Int],
        scaleNotes: [UInt8]
    ) -> [(pitch: UInt8, velDrop: UInt8, reverb: UInt8)] {
        let degreesPerOctave = scaleType.intervals.count
        guard degreesPerOctave > 0, !scaleNotes.isEmpty else { return [] }

        // Find the melody's position in the scale array
        let melodyIdx: Int
        if let exact = scaleNotes.firstIndex(of: melody) {
            melodyIdx = exact
        } else if let nearest = scaleNotes.enumerated().min(by: {
            abs(Int($0.element) - Int(melody)) < abs(Int($1.element) - Int(melody))
        }) {
            melodyIdx = nearest.offset
        } else {
            return []
        }

        let voiceParams: [(velDrop: UInt8, reverb: UInt8)] = [
            (15, 38),   // Voice 2 — closest below melody
            (18, 42),   // Voice 3
            (20, 48),   // Voice 4 — lowest, most reverb
        ]

        // Place each chord degree below the melody, walking down the scale
        var voices: [(pitch: UInt8, velDrop: UInt8, reverb: UInt8)] = []
        var usedPitches: Set<UInt8> = [melody]

        for (i, degree) in chordDegrees.enumerated() {
            guard i < voiceParams.count else { break }
            // Target: this scale degree, in the octave below the melody
            let targetIdx = melodyIdx - (degreesPerOctave - degree)
            let clampedIdx = max(0, min(scaleNotes.count - 1, targetIdx))
            let pitch = scaleNotes[clampedIdx]

            if pitch != melody && pitch >= 36 && !usedPitches.contains(pitch) {
                voices.append((pitch, voiceParams[i].velDrop, voiceParams[i].reverb))
                usedPitches.insert(pitch)
            }
        }

        return voices
    }

    // MARK: - Playback

    @MainActor
    func playPhonemes(audioMonitor: AudioMonitorService, midiService: MidiService?) {
        stop(midiService: midiService)
        guard !phonemes.isEmpty else { return }

        isPlaying = true
        let phonemesToPlay = phonemes
        let lastWordIndex = phonemesToPlay.map(\.wordIndex).max() ?? -1

        // Pre-compute melodic contour and chord harmony for the whole phrase
        let contour = buildContour(for: phonemesToPlay)
        let harmony = buildHarmony(for: phonemesToPlay)

        playbackTask = Task { @MainActor in
            for (index, phoneme) in phonemesToPlay.enumerated() {
                guard !Task.isCancelled else { break }

                // Bounce count: emphasized ensemble (w3) = 2 bounces, everything else = 1
                // Last word's emphasis gets doubled again (4 bounces) for a big finish
                let isEmphasizedEnsemble = phoneme.isEnsemble && phoneme.weight >= 3
                let isLastWordEmphasis = isEmphasizedEnsemble && phoneme.wordIndex == lastWordIndex
                let bounceCount = isLastWordEmphasis ? 4 : (isEmphasizedEnsemble ? 2 : 1)
                self.currentBounceCount = bounceCount

                // Duration: all ensemble chips get the 2x multiplier for a longer hold.
                // Emphasized ensemble splits that time across 2 bounces.
                let baseDuration = durationFor(weight: phoneme.weight, isEnsemble: phoneme.isEnsemble)
                let gap = Int(Double(phoneme.weight >= 3 ? 80 : 50) * speedMultiplier)

                let pitch = contour[index]
                let velocity = velocityForWeight(phoneme.weight)

                let ensemble = phoneme.isEnsemble
                log.debug("▶ [\(index)] \(phoneme.text): w\(phoneme.weight) note \(pitch) vel \(velocity) ×\(bounceCount)\(ensemble ? " 🎵" : "")")

                // Start the note
                var activePitches: [UInt8]
                if ensemble {
                    let chord = harmony[phoneme.wordIndex]
                    activePitches = playEnsemble(pitch: pitch, velocity: velocity, phoneme: phoneme, chordDegrees: chord, audioMonitor: audioMonitor, midiService: midiService)
                } else {
                    audioMonitor.playNote(
                        note: pitch, velocity: velocity, vibrato: 64, reverb: 32,
                        vowel: phoneme.vowelCC, consonant: phoneme.consonantCC
                    )
                    if let ms = midiService, ms.isConnected {
                        ms.consonant = phoneme.consonantCC
                        ms.vowel = phoneme.vowelCC
                        ms.vibrato = 64
                        ms.reverb = 32
                        ms.sendNoteOn(note: pitch, velocity: velocity)
                        activeMidiPitches.insert(pitch)
                    }
                    activePitches = [pitch]
                }

                // Multiple bounces on same chip
                // 2 bounces: split in half. 4 bounces (last-word encore): split by 3
                // so each bounce is long enough to complete its arc visually.
                let totalMs = baseDuration + gap
                let bounceDivisor = bounceCount >= 4 ? 3 : max(1, bounceCount)
                var preSendFired = false
                for bounceIdx in 0..<bounceCount {
                    guard !Task.isCancelled else { break }

                    let bounceDuration = bounceCount > 1 ? totalMs / bounceDivisor : totalMs
                    let halfArc = bounceDuration / 2

                    self.currentArcDuration = bounceDuration
                    self.bouncePhase = 0  // up phase
                    self.currentBounceIndex = bounceIdx

                    if bounceIdx == 0 {
                        self.currentPlayIndex = index
                    }

                    // Sleep first half (ball going up), then publish down phase
                    try? await Task.sleep(for: .milliseconds(halfArc))
                    guard !Task.isCancelled else { break }

                    // CC Pre-Send at the peak of the first bounce — halfway through the chip.
                    // Gives BLE time to clear the NoteOn packet before sending next CCs.
                    if !preSendFired, let ms = midiService, ms.ccPreSendEnabled, ms.isConnected, index + 1 < phonemesToPlay.count {
                        let next = phonemesToPlay[index + 1]
                        ms.preSendCC(consonant: next.consonantCC, vowel: next.vowelCC, vibrato: 64, reverb: next.isEnsemble ? 48 : 32)
                        preSendFired = true
                    }

                    self.bouncePhase = 1  // down phase

                    // Sleep second half (ball coming down)
                    try? await Task.sleep(for: .milliseconds(bounceDuration - halfArc))
                }

                // Stop the note after all bounces
                stopAll(pitches: activePitches, audioMonitor: audioMonitor, midiService: midiService)
            }

            self.isPlaying = false
            self.currentPlayIndex = nil
            self.currentBounceIndex = 0
            self.currentBounceCount = 1
        }
    }

    @MainActor
    func toggleEnsemble(at index: Int) {
        guard index >= 0 && index < phonemes.count else { return }
        phonemes[index].isEnsemble.toggle()
    }

    /// Find the nearest scale note to a target MIDI pitch
    private func nearestScaleNote(to target: Int, in scale: [UInt8]) -> UInt8? {
        guard !scale.isEmpty else { return nil }
        return scale.min(by: { abs(Int($0) - target) < abs(Int($1) - target) })
    }

    /// Barbershop quartet: lead + 3 harmony voices.
    /// When chordDegrees is provided, voices are built from chord tones (progression-aware).
    /// When nil, falls back to fixed parallel intervals (for single-phoneme preview).
    @MainActor
    private func playEnsemble(pitch: UInt8, velocity: UInt8, phoneme: ChoirPhoneme, chordDegrees: [Int]? = nil, audioMonitor: AudioMonitorService, midiService: MidiService?) -> [UInt8] {
        let scale = scaleNotes(center: pitch, range: 18)
        var pitches: [UInt8] = [pitch]

        // Lead voice
        audioMonitor.playNote(note: pitch, velocity: velocity, vibrato: 64, reverb: 32,
                              vowel: phoneme.vowelCC, consonant: phoneme.consonantCC)
        if let ms = midiService, ms.isConnected {
            ms.consonant = phoneme.consonantCC
            ms.vowel = phoneme.vowelCC
            ms.vibrato = 64
            ms.reverb = 32
            ms.sendNoteOn(note: pitch, velocity: velocity)
            activeMidiPitches.insert(pitch)
        }

        // Harmony voices — chord-aware when progression is available, else fixed intervals
        let harmonyTargets: [(pitch: UInt8, velDrop: UInt8, reverb: UInt8)]
        if let degrees = chordDegrees {
            harmonyTargets = ensembleVoices(melody: pitch, chordDegrees: degrees, scaleNotes: scale)
        } else {
            // Fallback: original parallel voicing (single-phoneme tap, no phrase context)
            harmonyTargets = [(offset: +7, velDrop: UInt8(15), reverb: UInt8(38)),
                              (offset: -5, velDrop: UInt8(18), reverb: UInt8(42)),
                              (offset: -12, velDrop: UInt8(20), reverb: UInt8(48))]
                .compactMap { t -> (pitch: UInt8, velDrop: UInt8, reverb: UInt8)? in
                    guard let snapped = nearestScaleNote(to: Int(pitch) + t.offset, in: scale),
                          snapped != pitch else { return nil }
                    return (snapped, t.velDrop, t.reverb)
                }
        }

        for t in harmonyTargets {
            let hv = max(50, velocity - t.velDrop)
            audioMonitor.playNote(note: t.pitch, velocity: hv, vibrato: 64, reverb: t.reverb,
                                  vowel: phoneme.vowelCC, consonant: phoneme.consonantCC)
            if let ms = midiService, ms.isConnected {
                ms.consonant = phoneme.consonantCC
                ms.vowel = phoneme.vowelCC
                ms.vibrato = 64
                ms.reverb = t.reverb
                ms.sendNoteOn(note: t.pitch, velocity: hv)
                activeMidiPitches.insert(t.pitch)
            }
            pitches.append(t.pitch)
        }

        log.debug("🎵 quartet: \(pitches.map { String($0) }.joined(separator: " "))")
        return pitches
    }

    @MainActor
    private func stopAll(pitches: [UInt8], audioMonitor: AudioMonitorService, midiService: MidiService?) {
        for p in pitches {
            audioMonitor.stopNote(note: p)
            if let ms = midiService, ms.isConnected {
                ms.sendNoteOff(note: p)
                activeMidiPitches.remove(p)
            }
        }
    }

    @MainActor
    func deletePhoneme(at index: Int) {
        guard index >= 0 && index < phonemes.count else { return }
        saveUndo()
        phonemes.remove(at: index)
    }

    @MainActor
    func insertPhoneme(at index: Int, before: Bool) {
        guard index >= 0 && index < phonemes.count else { return }
        saveUndo()
        let blank = ChoirPhoneme(
            text: "?",
            consonantCC: 0,   // Random
            vowelCC: 0,       // Random
            weight: 1,
            wordIndex: phonemes[index].wordIndex
        )
        let insertIdx = before ? index : index + 1
        phonemes.insert(blank, at: insertIdx)
    }

    @MainActor
    func updatePhoneme(at index: Int, consonantCC: UInt8? = nil, vowelCC: UInt8? = nil) {
        guard index >= 0 && index < phonemes.count else { return }
        saveUndo()
        let p = phonemes[index]
        if let c = consonantCC { phonemes[index] = ChoirPhoneme(text: p.text, consonantCC: c, vowelCC: p.vowelCC, weight: p.weight, wordIndex: p.wordIndex, isEnsemble: p.isEnsemble) }
        if let v = vowelCC { phonemes[index] = ChoirPhoneme(text: p.text, consonantCC: p.consonantCC, vowelCC: v, weight: p.weight, wordIndex: p.wordIndex, isEnsemble: p.isEnsemble) }
    }

    @MainActor
    func clearAll() {
        saveUndo()
        inputText = ""
        phonemes = []
        lastExtractedText = nil
        errorMessage = nil
    }

    @MainActor
    func clearPhonemes() {
        saveUndo()
        phonemes = []
        lastExtractedText = nil
        errorMessage = nil
    }

    // Step index for keyboard-driven playback (loops through chips)
    private var keyboardStepIndex: Int = 0

    @MainActor
    func playNextChip(note: UInt8, audioMonitor: AudioMonitorService, midiService: MidiService?) {
        guard !phonemes.isEmpty else { return }
        let idx = keyboardStepIndex % phonemes.count
        playSinglePhoneme(at: idx, audioMonitor: audioMonitor, midiService: midiService, pitchOverride: note)
        keyboardStepIndex = (keyboardStepIndex + 1) % phonemes.count
    }

    @MainActor
    func playSinglePhoneme(at idx: Int, audioMonitor: AudioMonitorService, midiService: MidiService? = nil, pitchOverride: UInt8? = nil) {
        stop(midiService: midiService)
        guard idx >= 0 && idx < phonemes.count else { return }
        let phoneme = phonemes[idx]
        currentPlayIndex = idx
        // Use phrase-context pitch when tapping a chip (so it previews where it sits in the contour)
        let pitch: UInt8
        if let override = pitchOverride {
            pitch = override
        } else if phonemes.count > 1 {
            let contour = buildContour(for: phonemes)
            pitch = contour[idx]
        } else {
            pitch = pitchForPhoneme(index: idx, weight: phoneme.weight, total: phonemes.count)
        }
        let velocity = velocityForWeight(phoneme.weight)
        log.debug("tap: \(phoneme.text) w\(phoneme.weight) note \(pitch)\(phoneme.isEnsemble ? " 🎵" : "")")
        var activePitches: [UInt8]
        if phoneme.isEnsemble {
            activePitches = playEnsemble(pitch: pitch, velocity: velocity, phoneme: phoneme, audioMonitor: audioMonitor, midiService: midiService)
        } else {
            audioMonitor.playNote(
                note: pitch, velocity: velocity, vibrato: 64, reverb: 32,
                vowel: phoneme.vowelCC, consonant: phoneme.consonantCC
            )
            if let ms = midiService, ms.isConnected {
                ms.consonant = phoneme.consonantCC
                ms.vowel = phoneme.vowelCC
                ms.vibrato = 64
                ms.reverb = 32
                ms.sendNoteOn(note: pitch, velocity: velocity)
                activeMidiPitches.insert(pitch)
            }
            activePitches = [pitch]
        }
        playbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            stopAll(pitches: activePitches, audioMonitor: audioMonitor, midiService: midiService)
            self.currentPlayIndex = nil
        }
    }

    @MainActor
    func stop(midiService: MidiService? = nil) {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        currentPlayIndex = nil
        if let ms = midiService, ms.isConnected, !activeMidiPitches.isEmpty {
            for p in activeMidiPitches { ms.sendNoteOff(note: p) }
            activeMidiPitches.removeAll()
        }
    }

    // MARK: - Copy to Grid

    @MainActor
    func copyToGrid(sequencer: SequencerModel) {
        guard !phonemes.isEmpty else { return }
        stop()

        let tempo = sequencer.tempo
        let msPerBeat = 60_000.0 / tempo

        // Find the end of the last existing note, snapped to next quarter beat
        let lastEnd = sequencer.notes.map { $0.startBeat + $0.duration }.max() ?? 0
        let startBeat = (lastEnd / 0.25).rounded(.up) * 0.25

        var cursor = startBeat
        let allScaleNotes = scaleNotes(center: 60, range: 24)

        // Pre-compute melodic contour and chord harmony (matches playPhonemes)
        let contour = buildContour(for: phonemes)
        let harmony = buildHarmony(for: phonemes)

        for (index, phoneme) in phonemes.enumerated() {
            let pitch = contour[index]
            let durationMs = Double(durationFor(weight: phoneme.weight, isEnsemble: phoneme.isEnsemble))
            let durationBeats = max(0.25, (durationMs / msPerBeat / 0.25).rounded() * 0.25)
            let velocity = velocityForWeight(phoneme.weight)

            var note = SequencerNote(
                pitch: pitch,
                startBeat: cursor,
                duration: durationBeats,
                velocity: velocity,
                consonant: phoneme.consonantCC,
                vowel: phoneme.vowelCC
            )
            note.vibrato = 64
            note.reverb = phoneme.isEnsemble ? 48 : 32

            sequencer.notes.append(note)

            // Ensemble: add chord-aware harmony voices (consistent with playEnsemble)
            if phoneme.isEnsemble {
                let chord = harmony[phoneme.wordIndex]
                let voices = chord.map { ensembleVoices(melody: pitch, chordDegrees: $0, scaleNotes: allScaleNotes) } ?? []
                for voice in voices {
                    var harmonyNote = SequencerNote(
                        pitch: voice.pitch,
                        startBeat: cursor,
                        duration: durationBeats,
                        velocity: max(1, velocity - voice.velDrop),
                        consonant: phoneme.consonantCC,
                        vowel: phoneme.vowelCC
                    )
                    harmonyNote.vibrato = 64
                    harmonyNote.reverb = voice.reverb
                    sequencer.notes.append(harmonyNote)
                }
            }

            cursor += durationBeats
        }

        // Extend bars if needed
        let neededBeats = Int((cursor / 4.0).rounded(.up)) * 4
        if neededBeats > sequencer.totalBeats {
            sequencer.totalBeats = min(64, neededBeats)
        }

        sequencer.hasUnsavedChanges = true
        print("[Composer] Copied \(phonemes.count) phonemes to grid at beat \(startBeat), ending at \(cursor)")
    }

}
