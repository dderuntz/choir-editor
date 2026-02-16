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
    @Guide(description: "The letters from the original word for this sound (e.g. 'The', 'far', 'mer', 'dell')")
    let text: String

    @Guide(description: "Consonant onset sound",
           .anyOf(["none", "b", "bj", "bl", "br", "tsh", "d", "dr",
                   "f", "fj", "fl", "fr", "g", "gl", "gr", "h", "dj",
                   "k", "kl", "kr", "l", "m", "n", "nj", "p", "pl",
                   "pr", "r", "s", "sl", "sh", "t", "tr", "th", "thr",
                   "v", "w", "y"]))
    let consonant: String

    @Guide(description: "Vowel nucleus sound",
           .anyOf(["aa", "ai", "ae", "schwa", "aw", "oi", "o",
                   "uh", "oo", "ee", "ear", "ay", "air", "ure",
                   "mmm", "none"]))
    let vowel: String

    @Guide(description: "Stress level: 3=primary accent, 2=secondary, 1=unstressed/weak")
    let weight: Int
}

@available(macOS 26, *)
@Generable
struct LLMPhonemeResult {
    @Guide(description: "Ordered list of syllables extracted from the input text")
    let syllables: [LLMSyllable]
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
    private static let maxExamples = 10  // keep prompt manageable

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
    let isEnsemble: Bool
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
        let stored = phonemes.map { StoredPhoneme(text: $0.text, consonantCC: $0.consonantCC, vowelCC: $0.vowelCC, weight: $0.weight, isEnsemble: $0.isEnsemble) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: phonemesKey)
        }
    }

    static func loadPhonemes() -> [ChoirPhoneme] {
        guard let data = UserDefaults.standard.data(forKey: phonemesKey),
              let stored = try? JSONDecoder().decode([StoredPhoneme].self, from: data)
        else { return [] }
        return stored.map { ChoirPhoneme(text: $0.text, consonantCC: $0.consonantCC, vowelCC: $0.vowelCC, weight: $0.weight, isEnsemble: $0.isEnsemble) }
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

        isProcessing = true
        errorMessage = nil
        isApproved = false

        if #available(macOS 26, *) {
            await extractWithLLM(text: text)
        } else {
            errorMessage = "Requires macOS 26 (Tahoe)"
        }

        isProcessing = false
    }

    // MARK: - Summon Song (LLM text generation)

    @MainActor
    func summonSong() async {
        guard !isProcessing else { return }
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

        let instructions = """
        You are a songwriter's muse. Given a theme or prompt, write a very short singable lyric.

        STYLE:
        Choose a form that fits the prompt naturally. Draw from these traditions:
        - Senryū — wry, human, a little dark or funny. 3 lines about people, not nature.
        - Bellman — musical, vivid, Swedish tavern-poet warmth. Characters, scenes, melody in the words.
        - Haiku — still, observational, one image that opens up.
        - Lullaby — gentle, repeating, soothing.
        - Free verse — when the prompt is very specific, just write what it asks for.

        RULES:
        - 2-4 lines, each line 3-6 words maximum (short lines!)
        - Simple, evocative language that sings well aloud
        - Rhythm and natural stress matter — these words will be sung by a choir
        - NEVER preface with "Here is..." or any introduction — output ONLY the lyric words
        - No titles, no labels, no quotation marks, no form names — just the lyric itself
        - If the prompt already IS a lyric, refine or extend it slightly
        - Match the mood of the prompt: playful prompt → senryū/Bellman, quiet prompt → haiku/lullaby

        EXAMPLES:
        Prompt: "morning"
        the sun is waking slowly now
        golden light on sleepy hills

        Prompt: "coffee"
        the cup knows more than I do
        it has seen me before dawn

        Prompt: "Stockholm rain"
        Bellman would have raised a glass
        to gutters singing in the dark

        Prompt: "sleep"
        close your eyes and drift away
        the stars will keep the watch tonight

        Prompt: "my cat sits on the keyboard"
        your cat composes better
        than most of us ever will
        """

        do {
            let session = LanguageModelSession {
                instructions
            }

            let response = try await session.respond(
                to: "Write a short singable lyric about: \(userPrompt)"
            )

            var raw = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")

            // Strip LLM preamble like "Here is a short singable lyric about X:"
            if let colonRange = raw.range(of: ":"),
               raw.distance(from: raw.startIndex, to: colonRange.lowerBound) < 60 {
                raw = String(raw[colonRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let lyric = raw

            if !lyric.isEmpty {
                inputText = lyric
                print("[Composer] 🎵 Summoned lyric: \(lyric)")
            }
        } catch {
            print("[Composer] ✗ Summon error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    @available(macOS 26, *)
    @MainActor
    private func extractWithLLM(text: String) async {
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
            let session = LanguageModelSession {
                fullInstructions
            }

            let response = try await session.respond(
                to: "Extract singable phonemes from: \(text)",
                generating: LLMPhonemeResult.self
            )

            // Cap output: ~4 notes per word max to prevent hallucination
            let wordCount = text.split(separator: " ").count
            let maxNotes = wordCount * 4
            let syllables = Array(response.content.syllables.prefix(maxNotes))

            // Convert LLM result → ChoirPhoneme array, filter junk
            phonemes = syllables.compactMap { syl in
                guard let c = Consonant.all.first(where: { $0.id == syl.consonant }),
                      let v = Vowel.all.first(where: { $0.id == syl.vowel })
                else {
                    print("[Composer] ⚠ Unmapped: \(syl.text) → \(syl.consonant)+\(syl.vowel)")
                    return nil
                }
                // Skip empty chips (none+none with no text)
                let trimmed = syl.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty && syl.consonant == "none" && syl.vowel == "none" { return nil }
                let label = trimmed.isEmpty ? "\(c.name)" : trimmed
                let w = max(1, min(3, syl.weight))
                return ChoirPhoneme(text: label, consonantCC: c.ccValue, vowelCC: v.ccValue, weight: w)
            }

            print("[Composer] Extracted \(phonemes.count) phonemes from: \(text)")
            for (i, p) in phonemes.enumerated() {
                print("  [\(i)] \(p.text): \(p.consonantName)·\(p.vowelSymbol) (CC \(p.consonantCC)/\(p.vowelCC))")
            }
        } catch {
            print("[Composer] ✗ LLM error: \(error)")
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
        phonemes.removeAll(where: { $0.id == phoneme.id })
    }

    @MainActor
    func updatePhoneme(id: UUID, consonantCC: UInt8? = nil, vowelCC: UInt8? = nil) {
        guard let idx = phonemes.firstIndex(where: { $0.id == id }) else { return }
        if let c = consonantCC { phonemes[idx] = ChoirPhoneme(text: phonemes[idx].text, consonantCC: c, vowelCC: phonemes[idx].vowelCC, weight: phonemes[idx].weight, isEnsemble: phonemes[idx].isEnsemble) }
        if let v = vowelCC { phonemes[idx] = ChoirPhoneme(text: phonemes[idx].text, consonantCC: phonemes[idx].consonantCC, vowelCC: v, weight: phonemes[idx].weight, isEnsemble: phonemes[idx].isEnsemble) }
    }

    @MainActor
    func clearAll() {
        inputText = ""
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
