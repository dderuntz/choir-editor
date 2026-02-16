import Foundation
import Combine
import os
import FoundationModels

private let log = Logger(subsystem: "com.choir-arranger", category: "composer")

// MARK: - Phoneme Data

struct ChoirPhoneme: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String       // original syllable text
    let consonantCC: UInt8 // CC2 value
    let vowelCC: UInt8     // CC3 value
    let weight: Int        // stress: 3=primary, 2=secondary, 1=unstressed
    var wordIndex: Int = 0 // which word this chip belongs to (for visual grouping)
    var isEnsemble: Bool = false  // choral harmony on this syllable

    var consonantName: String {
        Consonant.all.first(where: { $0.ccValue == consonantCC })?.name ?? "?"
    }
    var vowelSymbol: String {
        Vowel.all.first(where: { $0.ccValue == vowelCC })?.symbol ?? "?"
    }
}

// MARK: - LLM Structured Output Types

@available(macOS 26, *)
@Generable
struct LLMSyllable {
    @Guide(description: "Consonant onset sound for this syllable of singing",
           .anyOf(["none", "b", "bj", "bl", "br", "tsh", "d", "dr",
                   "f", "fj", "fl", "fr", "g", "gl", "gr", "h", "dj",
                   "k", "kl", "kr", "l", "m", "n", "nj", "p", "pl",
                   "pr", "r", "s", "sl", "sh", "t", "tr", "th", "thr",
                   "v", "w", "y"]))
    let consonant: String

    @Guide(description: "Vowel nucleus — the sustained singing sound",
           .anyOf(["aa", "ai", "ae", "schwa", "aw", "oi", "o",
                   "uh", "oo", "ee", "ear", "ay", "air", "ure",
                   "mmm", "none"]))
    let vowel: String

    @Guide(description: "Stress for singing accent and length. 3 = the LOUD syllable in each word (FAR-mer, SING-ing). 2 = secondary. 1 = weak (the, in, a).",
           .range(1...3))
    let weight: Int

    @Guide(description: "Original letters from the input word for this sound (e.g. 'far', 'mer', 'The')")
    let text: String
}

@available(macOS 26, *)
@Generable
struct LLMPhonemeResult {
    @Guide(description: "Ordered syllables extracted from the input text for singing")
    let syllables: [LLMSyllable]
}

// MARK: - LLM Lyric Generation Types

@available(macOS 26, *)
@Generable
struct LLMLyric {
    @Guide(description: "A short lyric for singing. 2 lines separated by /. Each line 3-8 simple words.")
    let lyric: String
}

@available(macOS 26, *)
@Generable
struct LLMWordList {
    @Guide(description: "Clean list of correctly-spelled English words extracted from the input. Fix typos, split run-on words. Keep original word order.")
    let words: [String]
}

// MARK: - Few-Shot Example Storage

struct PhonemeExample: Codable {
    let inputText: String
    let syllables: [SyllableExample]

    struct SyllableExample: Codable {
        let text: String
        let consonant: String  // consonant ID
        let vowel: String      // vowel ID
    }
}

enum PhonemeExampleStore {
    private static let storageKey = "composer.fewShotExamples"
    private static let maxExamples = 5  // Apple: "less than five examples" for 3B model

    static func load() -> [PhonemeExample] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let examples = try? JSONDecoder().decode([PhonemeExample].self, from: data)
        else { return [] }
        return examples
    }

    static func save(_ examples: [PhonemeExample]) {
        // Keep only the most recent N
        let trimmed = Array(examples.suffix(maxExamples))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func addExample(_ example: PhonemeExample) {
        var existing = load()
        // Don't duplicate same input text
        existing.removeAll(where: { $0.inputText == example.inputText })
        existing.append(example)
        save(existing)
        print("[Composer] ✓ Saved example: \"\(example.inputText)\" (\(example.syllables.count) syllables, \(load().count) total)")
    }

    /// Format saved examples as prompt text
    static func promptSection() -> String? {
        let examples = load()
        guard !examples.isEmpty else { return nil }
        var lines = ["USER-APPROVED EXAMPLES (highest priority — match these exactly):"]
        for ex in examples {
            let pairs = ex.syllables.map { "\($0.text):\($0.consonant)+\($0.vowel)" }.joined(separator: ", ")
            lines.append("  \"\(ex.inputText)\" → [\(pairs)]")
        }
        return lines.joined(separator: "\n")
    }

    /// Export all examples as JSONL for adapter training
    static func exportJSONL() -> String {
        let examples = load()
        return examples.map { ex in
            let syllablesJSON = ex.syllables.map {
                "{\"text\":\"\($0.text)\",\"consonant\":\"\($0.consonant)\",\"vowel\":\"\($0.vowel)\"}"
            }.joined(separator: ",")
            let prompt = "Extract singable phonemes from: \(ex.inputText)"
            let response = "{\"syllables\":[\(syllablesJSON)]}"
            return "[{\"role\":\"user\",\"content\":\"\(prompt)\"},{\"role\":\"assistant\",\"content\":\"\(response)\"}]"
        }.joined(separator: "\n")
    }
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

class ComposerModel: ObservableObject {
    @Published var inputText: String = "" {
        didSet { ComposerPersistence.saveText(inputText) }
    }
    @Published var phonemes: [ChoirPhoneme] = [] {
        didSet { ComposerPersistence.savePhonemes(phonemes) }
    }
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var llmStatusMessage: String? = nil

    // Approval
    @Published var isApproved: Bool = false
    var savedExampleCount: Int { PhonemeExampleStore.load().count }

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
    @Published var currentArcDuration: Int = 330  // ms, note + gap — full time between bounces
    private var playbackTask: Task<Void, Never>? = nil

    /// Check on-device LLM availability (macOS 26+ only)
    var isLLMAvailable: Bool {
        if #available(macOS 26, *) {
            return checkAvailability()
        }
        return false
    }

    @available(macOS 26, *)
    private func checkAvailability() -> Bool {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return true
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                llmStatusMessage = "This Mac doesn't support Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                llmStatusMessage = "Enable Apple Intelligence in System Settings"
            case .modelNotReady:
                llmStatusMessage = "Model is downloading…"
            @unknown default:
                llmStatusMessage = "Apple Intelligence unavailable"
            }
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Phoneme Extraction

    @MainActor
    func approveResult() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !phonemes.isEmpty else { return }

        let syllables = phonemes.map { p -> PhonemeExample.SyllableExample in
            let cID = Consonant.all.first(where: { $0.ccValue == p.consonantCC })?.id ?? "none"
            let vID = Vowel.all.first(where: { $0.ccValue == p.vowelCC })?.id ?? "schwa"
            return PhonemeExample.SyllableExample(text: p.text, consonant: cID, vowel: vID)
        }
        let example = PhonemeExample(inputText: text, syllables: syllables)
        PhonemeExampleStore.addExample(example)
        isApproved = true
    }

    @MainActor
    func extractPhonemes() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        saveUndo()
        isProcessing = true
        errorMessage = nil
        isApproved = false

        // ── Tier 1: Cheap heuristic — basic whitespace split → dictionary ──
        let firstTry = PhonemeDictionary.lookupSentence(text)

        if firstTry.missing.isEmpty {
            phonemes = firstTry.found
            print("[Composer] Dict (direct): \(phonemes.count) phonemes from: \(text)")
            logPhonemes(phonemes)
            isProcessing = false
            return
        }

        print("[Composer] Dict missed \(firstTry.missing.count) words: \(firstTry.missing)")

        // ── Tier 2: LLM normalizes text (fix typos, split run-ons) → retry dict ──
        if #available(macOS 26, *) {
            if let cleanWords = await normalizeWithLLM(text: text) {
                let cleanText = cleanWords.joined(separator: " ")

                // Update the text field so user sees the cleaned version
                inputText = cleanText

                let retry = PhonemeDictionary.lookupSentence(cleanText)

                if retry.missing.isEmpty {
                    phonemes = retry.found
                    print("[Composer] Dict (after LLM normalize): \(phonemes.count) phonemes")
                    logPhonemes(phonemes)
                    isProcessing = false
                    return
                }

                // ── Tier 3: Dict got most, LLM fallback for remaining words ──
                print("[Composer] Still missing after normalize: \(retry.missing)")
                var combined = retry.found
                let nextWordIdx = (combined.map(\.wordIndex).max() ?? -1) + 1
                let missingText = retry.missing.joined(separator: " ")
                var llmResult = await extractWithLLM(text: missingText)
                for i in llmResult.indices { llmResult[i].wordIndex = nextWordIdx + i }
                combined.append(contentsOf: llmResult)
                phonemes = combined
                print("[Composer] Combined: \(retry.found.count) dict + \(llmResult.count) LLM = \(phonemes.count) total")
                logPhonemes(phonemes)
            } else {
                // Normalize failed — full LLM fallback on original text
                print("[Composer] Normalize failed, full LLM fallback")
                phonemes = await extractWithLLM(text: text)
                logPhonemes(phonemes)
            }
        } else {
            errorMessage = "Requires macOS 26 (Tahoe)"
        }

        isProcessing = false
    }

    private func logPhonemes(_ list: [ChoirPhoneme]) {
        for (i, p) in list.enumerated() {
            print("  [\(i)] \(p.text): \(p.consonantName)·\(p.vowelSymbol) w\(p.weight)")
        }
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
        }

        let userMessage = style == .kulning
            ? "Write a short singable robot lyric about: \(userPrompt)"
            : "Write a short singable lyric about: \(userPrompt)"

        do {
            let session = LanguageModelSession(instructions: Instructions(lyricInstructions))

            let response = try await session.respond(
                to: userMessage,
                generating: LLMLyric.self
            )

            let lyric = response.content.lyric
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

    // MARK: - LLM Text Normalization

    @available(macOS 26, *)
    @MainActor
    private func normalizeWithLLM(text: String) async -> [String]? {
        let instructions = """
        You are a text normalizer. Your ONLY job: turn messy input into a clean word list.

        Rules:
        1. SPLIT run-on words into separate words. "forexample" → "for", "example"
        2. FIX typos to the most likely intended word. "farmr" → "farmer", "teh" → "the"
        3. KEEP original word order. Do NOT add extra words.
        4. Every output word must be a real English word, correctly spelled.

        "forexample like that" → ["for", "example", "like", "that"]
        "teh qiuck brwon fox" → ["the", "quick", "brown", "fox"]
        "iloveyou" → ["i", "love", "you"]
        "sining in therain" → ["singing", "in", "the", "rain"]
        "farmr in duh dell" → ["farmer", "in", "the", "dell"]
        "runningaway fromthe robots" → ["running", "away", "from", "the", "robots"]
        """

        do {
            let session = LanguageModelSession(instructions: Instructions(instructions))
            let response = try await session.respond(
                to: text,
                generating: LLMWordList.self
            )
            let words = response.content.words.map { $0.lowercased() }
            print("[Composer] LLM normalized: \"\(text)\" → \(words)")
            return words
        } catch {
            print("[Composer] ✗ Normalize error: \(error)")
            return nil
        }
    }

    // MARK: - LLM Phoneme Extraction

    @available(macOS 26, *)
    @MainActor
    private func extractWithLLM(text: String) async -> [ChoirPhoneme] {
        let instructions = """
        You decompose English text into singing notes for a voice synthesizer.

        ALGORITHM — for each word:
        1. Sound out the word into its consonant (C) and vowel (V) sounds, left to right.
        2. Pair each C with the V that follows it → one note.
        3. A V with no preceding C → consonant "none".
        4. A C at the end with no following V → pair it with "schwa" (or "mmm" for m/n).
        5. Diphthongs (two vowel sounds) → split into two separate notes.

        CONSONANT IDs:
        none b d f g h k l m n p r s t v w y \
        sh th tsh dj bl br dr fl fr gl gr kl kr pl pr sl tr thr

        VOWEL IDs — matched by sound:
        ee (frEE) | ae (cAt) | aa (fAther) | o (pOt) | aw (lAW) \
        | uh (cUt) | oo (zOO) | schwa (commA) | air (cARE) | ear (hEAr) \
        | ure (cURE) | mmm (humming) | none (pure consonant, no voice)

        The "text" field MUST contain the ORIGINAL LETTERS from the input word \
        (not phonetic notation). Split the word's spelling across its notes.

        STOP after processing every word in the input. Do NOT add extra sounds.

        STRESS / WEIGHT (the "weight" field):
        3 = primary stress (the LOUD syllable: FAR-mer, SING-ing, LOVE)
        2 = secondary stress (medium: farm-ER has secondary on "er" in compound words)
        1 = unstressed / weak (articles, pure consonant tails: "the", "in", trailing "n")
        Rule: every word has exactly ONE syllable with weight 3. Function words (the, in, a, and) get weight 1.

        WORKED EXAMPLES (text field shows original letters):

        "farmer" → sounds: F-AH-M-ER →
          {text:"far", consonant:f, vowel:aa, weight:3}, {text:"mer", consonant:m, vowel:schwa, weight:1}
        "dell" → sounds: D-EH-L →
          {text:"de", consonant:d, vowel:ae, weight:3}, {text:"ll", consonant:l, vowel:schwa, weight:1}
        "the" → sounds: TH-UH →
          {text:"The", consonant:th, vowel:schwa, weight:1}
        "in" → sounds: IH-N →
          {text:"i", consonant:none, vowel:ee, weight:1}, {text:"n", consonant:n, vowel:schwa, weight:1}
        "I" → sounds: AH-EE (diphthong) →
          {text:"I", consonant:none, vowel:aa, weight:3}, {text:"", consonant:none, vowel:ee, weight:1}
        "love" → sounds: L-UH-V →
          {text:"lu", consonant:l, vowel:uh, weight:3}, {text:"ve", consonant:v, vowel:schwa, weight:1}
        "singing" → sounds: S-IH-NG-IH-NG →
          {text:"si", consonant:s, vowel:ee, weight:3}, {text:"ngi", consonant:n, vowel:ee, weight:2}, {text:"ng", consonant:n, vowel:mmm, weight:1}

        FULL EXAMPLE:
        "The farmer in the dell" → 8 notes, then STOP:
          The:th+schwa+w1, far:f+aa+w3, mer:m+schwa+w1, i:none+ee+w1, n:n+schwa+w1, The:th+schwa+w1, de:d+ae+w3, ll:l+schwa+w1
        """

        // Inject user-approved examples if any exist
        var fullInstructions = instructions
        if let fewShot = PhonemeExampleStore.promptSection() {
            fullInstructions += "\n\n" + fewShot
        }

        do {
            let session = LanguageModelSession(instructions: Instructions(fullInstructions))

            let response = try await session.respond(
                to: "Extract singable phonemes from: \(text)",
                generating: LLMPhonemeResult.self
            )

            // Cap output: ~4 notes per word max to prevent hallucination
            let wordCount = text.split(separator: " ").count
            let maxNotes = wordCount * 4
            let syllables = Array(response.content.syllables.prefix(maxNotes))

            // Convert LLM result → ChoirPhoneme array, filter junk
            let result = syllables.compactMap { syl -> ChoirPhoneme? in
                guard let c = Consonant.all.first(where: { $0.id == syl.consonant }),
                      let v = Vowel.all.first(where: { $0.id == syl.vowel })
                else {
                    print("[Composer] ⚠ Unmapped: \(syl.text) → \(syl.consonant)+\(syl.vowel)")
                    return nil
                }
                let trimmed = syl.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty && syl.consonant == "none" && syl.vowel == "none" { return nil }
                let label = trimmed.isEmpty ? "\(c.name)" : trimmed
                let w = max(1, min(3, syl.weight))
                return ChoirPhoneme(text: label, consonantCC: c.ccValue, vowelCC: v.ccValue, weight: w)
            }

            print("[Composer] LLM: extracted \(result.count) phonemes from: \(text)")
            for (i, p) in result.enumerated() {
                print("  [\(i)] \(p.text): \(p.consonantName)·\(p.vowelSymbol) (CC \(p.consonantCC)/\(p.vowelCC))")
            }
            return result
        } catch {
            print("[Composer] ✗ LLM error: \(error)")
            errorMessage = error.localizedDescription
            return []
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

    /// Pick a pitch from the scale based on phoneme index and weight
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

    /// Duration in ms based on weight + speed, logarithmic scaling
    /// Longer base notes stretch proportionally more at slower speeds
    private func durationForWeight(_ weight: Int) -> Int {
        let base: Double
        switch weight {
        case 3: base = 500    // long hold
        case 2: base = 380    // medium
        default: base = 280   // brief
        }
        // Logarithmic: multiply = multiplier ^ (base/280)
        // So 280ms note gets linear scaling, but 500ms note stretches more
        let scaled = base * pow(speedMultiplier, base / 280.0)
        return max(minNoteDuration, Int(scaled))
    }

    /// Velocity based on weight
    private func velocityForWeight(_ weight: Int) -> UInt8 {
        switch weight {
        case 3: return 110
        case 2: return 90
        default: return 70
        }
    }

    // MARK: - Playback

    @MainActor
    func playPhonemes(audioMonitor: AudioMonitorService) {
        stop()
        guard !phonemes.isEmpty else { return }

        isPlaying = true
        let phonemesToPlay = phonemes
        let total = phonemesToPlay.count
        playbackTask = Task { @MainActor in
            for (index, phoneme) in phonemesToPlay.enumerated() {
                guard !Task.isCancelled else { break }

                let duration = durationForWeight(phoneme.weight)
                let gap = Int(Double(phoneme.weight >= 3 ? 80 : 50) * speedMultiplier)
                self.currentArcDuration = duration + gap
                self.currentPlayIndex = index

                let pitch = pitchForPhoneme(index: index, weight: phoneme.weight, total: total)
                let velocity = velocityForWeight(phoneme.weight)

                let ensemble = phoneme.isEnsemble
                print("[Composer] ▶ [\(index)] \(phoneme.text): \(phoneme.consonantName)·\(phoneme.vowelSymbol) w\(phoneme.weight) → note \(pitch) vel \(velocity) \(duration)ms\(ensemble ? " 🎵ensemble" : "")")

                var activePitches: [UInt8]
                if ensemble {
                    activePitches = playEnsemble(pitch: pitch, velocity: velocity, phoneme: phoneme, audioMonitor: audioMonitor)
                } else {
                    audioMonitor.playNote(
                        note: pitch, velocity: velocity, vibrato: 64, reverb: 32,
                        vowel: phoneme.vowelCC, consonant: phoneme.consonantCC
                    )
                    activePitches = [pitch]
                }

                try? await Task.sleep(for: .milliseconds(duration))
                stopAll(pitches: activePitches, audioMonitor: audioMonitor)

                // Gap between syllables (already computed above for arc)
                try? await Task.sleep(for: .milliseconds(gap))
            }
            self.isPlaying = false
            self.currentPlayIndex = nil
        }
    }

    @MainActor
    func toggleEnsemble(_ phoneme: ChoirPhoneme) {
        guard let idx = phonemes.firstIndex(where: { $0.id == phoneme.id }) else { return }
        phonemes[idx].isEnsemble.toggle()
    }

    /// Find the nearest scale note to a target MIDI pitch
    private func nearestScaleNote(to target: Int, in scale: [UInt8]) -> UInt8? {
        guard !scale.isEmpty else { return nil }
        return scale.min(by: { abs(Int($0) - target) < abs(Int($1) - target) })
    }

    /// Barbershop quartet: lead + 3 harmony voices, all snapped to scale
    /// Tenor: ~3rd above lead, Baritone: ~3rd below, Bass: ~octave below
    private func playEnsemble(pitch: UInt8, velocity: UInt8, phoneme: ChoirPhoneme, audioMonitor: AudioMonitorService) -> [UInt8] {
        let scale = scaleNotes(center: pitch, range: 18)
        var pitches: [UInt8] = [pitch]

        // Lead voice
        audioMonitor.playNote(note: pitch, velocity: velocity, vibrato: 64, reverb: 32,
                              vowel: phoneme.vowelCC, consonant: phoneme.consonantCC)

        // Quartet intervals — wider open voicing, all snapped to scale
        let targets: [(offset: Int, velDrop: UInt8, reverb: UInt8)] = [
            (+7,  15, 38),   // Tenor — 5th above
            (-5,  18, 42),   // Baritone — 4th below
            (-12, 20, 48),   // Bass — octave below
        ]

        for t in targets {
            let raw = Int(pitch) + t.offset
            guard let snapped = nearestScaleNote(to: raw, in: scale),
                  snapped != pitch else { continue }  // skip duplicates
            let hv = max(50, velocity - t.velDrop)
            audioMonitor.playNote(note: snapped, velocity: hv, vibrato: 64, reverb: t.reverb,
                                  vowel: phoneme.vowelCC, consonant: phoneme.consonantCC)
            pitches.append(snapped)
        }

        print("[Composer] 🎵 quartet: \(pitches.map { String($0) }.joined(separator: " "))")
        return pitches
    }

    private func stopAll(pitches: [UInt8], audioMonitor: AudioMonitorService) {
        for p in pitches { audioMonitor.stopNote(note: p) }
    }

    @MainActor
    func deletePhoneme(_ phoneme: ChoirPhoneme) {
        saveUndo()
        phonemes.removeAll(where: { $0.id == phoneme.id })
    }

    @MainActor
    func insertPhoneme(relativeTo phoneme: ChoirPhoneme, before: Bool) {
        guard let idx = phonemes.firstIndex(where: { $0.id == phoneme.id }) else { return }
        saveUndo()
        let blank = ChoirPhoneme(
            text: "?",
            consonantCC: 0,   // Random
            vowelCC: 0,       // Random
            weight: 1,
            wordIndex: phoneme.wordIndex
        )
        let insertIdx = before ? idx : idx + 1
        phonemes.insert(blank, at: insertIdx)
    }

    @MainActor
    func updatePhoneme(id: UUID, consonantCC: UInt8? = nil, vowelCC: UInt8? = nil) {
        saveUndo()
        guard let idx = phonemes.firstIndex(where: { $0.id == id }) else { return }
        if let c = consonantCC { phonemes[idx] = ChoirPhoneme(text: phonemes[idx].text, consonantCC: c, vowelCC: phonemes[idx].vowelCC, weight: phonemes[idx].weight, wordIndex: phonemes[idx].wordIndex, isEnsemble: phonemes[idx].isEnsemble) }
        if let v = vowelCC { phonemes[idx] = ChoirPhoneme(text: phonemes[idx].text, consonantCC: phonemes[idx].consonantCC, vowelCC: v, weight: phonemes[idx].weight, wordIndex: phonemes[idx].wordIndex, isEnsemble: phonemes[idx].isEnsemble) }
    }

    @MainActor
    func clearAll() {
        saveUndo()
        inputText = ""
        phonemes = []
        isApproved = false
        errorMessage = nil
    }

    @MainActor
    func clearPhonemes() {
        saveUndo()
        phonemes = []
        isApproved = false
        errorMessage = nil
    }

    // Step index for keyboard-driven playback (loops through chips)
    private var keyboardStepIndex: Int = 0

    @MainActor
    func playNextChip(note: UInt8, audioMonitor: AudioMonitorService) {
        guard !phonemes.isEmpty else { return }
        let phoneme = phonemes[keyboardStepIndex % phonemes.count]
        playSinglePhoneme(phoneme, audioMonitor: audioMonitor, pitchOverride: note)
        keyboardStepIndex = (keyboardStepIndex + 1) % phonemes.count
    }

    @MainActor
    func playSinglePhoneme(_ phoneme: ChoirPhoneme, audioMonitor: AudioMonitorService, pitchOverride: UInt8? = nil) {
        stop()
        let idx = phonemes.firstIndex(where: { $0.id == phoneme.id }) ?? 0
        currentPlayIndex = idx
        let pitch = pitchOverride ?? pitchForPhoneme(index: idx, weight: phoneme.weight, total: phonemes.count)
        let velocity = velocityForWeight(phoneme.weight)
        print("[Composer] tap: \(phoneme.text) → \(phoneme.consonantName)·\(phoneme.vowelSymbol) w\(phoneme.weight) note \(pitch)\(phoneme.isEnsemble ? " 🎵ensemble" : "")")
        var activePitches: [UInt8]
        if phoneme.isEnsemble {
            activePitches = playEnsemble(pitch: pitch, velocity: velocity, phoneme: phoneme, audioMonitor: audioMonitor)
        } else {
            audioMonitor.playNote(
                note: pitch, velocity: velocity, vibrato: 64, reverb: 32,
                vowel: phoneme.vowelCC, consonant: phoneme.consonantCC
            )
            activePitches = [pitch]
        }
        playbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            stopAll(pitches: activePitches, audioMonitor: audioMonitor)
            self.currentPlayIndex = nil
        }
    }

    @MainActor
    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        currentPlayIndex = nil
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
        let total = phonemes.count

        for (index, phoneme) in phonemes.enumerated() {
            let pitch = pitchForPhoneme(index: index, weight: phoneme.weight, total: total)
            let durationMs = Double(durationForWeight(phoneme.weight))
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
