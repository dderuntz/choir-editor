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
        let stored = phonemes.map { StoredPhoneme(text: $0.text, consonantCC: $0.consonantCC, vowelCC: $0.vowelCC) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: phonemesKey)
        }
    }

    static func loadPhonemes() -> [ChoirPhoneme] {
        guard let data = UserDefaults.standard.data(forKey: phonemesKey),
              let stored = try? JSONDecoder().decode([StoredPhoneme].self, from: data)
        else { return [] }
        return stored.map { ChoirPhoneme(text: $0.text, consonantCC: $0.consonantCC, vowelCC: $0.vowelCC) }
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

    // Playback
    @Published var isPlaying: Bool = false
    @Published var currentPlayIndex: Int? = nil
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

        WORKED EXAMPLES (text field shows original letters):

        "farmer" → sounds: F-AH-M-ER →
          {text:"far", consonant:f, vowel:aa}, {text:"mer", consonant:m, vowel:schwa}
        "dell" → sounds: D-EH-L →
          {text:"de", consonant:d, vowel:ae}, {text:"ll", consonant:l, vowel:schwa}
        "the" → sounds: TH-UH →
          {text:"The", consonant:th, vowel:schwa}
        "in" → sounds: IH-N →
          {text:"i", consonant:none, vowel:ee}, {text:"n", consonant:n, vowel:schwa}
        "I" → sounds: AH-EE (diphthong) →
          {text:"I", consonant:none, vowel:aa}, {text:"", consonant:none, vowel:ee}
        "love" → sounds: L-UH-V →
          {text:"lu", consonant:l, vowel:uh}, {text:"ve", consonant:v, vowel:schwa}
        "singing" → sounds: S-IH-NG-IH-NG →
          {text:"si", consonant:s, vowel:ee}, {text:"ngi", consonant:n, vowel:ee}, {text:"ng", consonant:n, vowel:mmm}

        FULL EXAMPLE:
        "The farmer in the dell" → 8 notes, then STOP:
          The:th+schwa, far:f+aa, mer:m+schwa, i:none+ee, n:n+schwa, The:th+schwa, de:d+ae, ll:l+schwa
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
                return ChoirPhoneme(text: label, consonantCC: c.ccValue, vowelCC: v.ccValue)
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

    // MARK: - Playback

    @MainActor
    func playPhonemes(audioMonitor: AudioMonitorService) {
        stop()
        guard !phonemes.isEmpty else { return }

        isPlaying = true
        let phonemesToPlay = phonemes  // capture value type copy
        playbackTask = Task { @MainActor in
            for (index, phoneme) in phonemesToPlay.enumerated() {
                guard !Task.isCancelled else { break }
                self.currentPlayIndex = index

                print("[Composer] ▶ [\(index)] \(phoneme.text): \(phoneme.consonantName)·\(phoneme.vowelSymbol) (CC \(phoneme.consonantCC)/\(phoneme.vowelCC))")

                audioMonitor.playNote(
                    note: 60,
                    velocity: 100,
                    vibrato: 64,
                    reverb: 32,
                    vowel: phoneme.vowelCC,
                    consonant: phoneme.consonantCC
                )

                // Hold note (minimum ~300ms for Choir)
                try? await Task.sleep(for: .milliseconds(400))
                audioMonitor.stopNote(note: 60)

                // Gap between syllables — let the engine fully release
                try? await Task.sleep(for: .milliseconds(100))
            }
            self.isPlaying = false
            self.currentPlayIndex = nil
        }
    }

    @MainActor
    func deletePhoneme(_ phoneme: ChoirPhoneme) {
        phonemes.removeAll(where: { $0.id == phoneme.id })
    }

    @MainActor
    func playSinglePhoneme(_ phoneme: ChoirPhoneme, audioMonitor: AudioMonitorService) {
        stop()
        if let idx = phonemes.firstIndex(where: { $0.id == phoneme.id }) {
            currentPlayIndex = idx
        }
        print("[Composer] tap: \(phoneme.text) → \(phoneme.consonantName)·\(phoneme.vowelSymbol)")
        audioMonitor.playNote(
            note: 60, velocity: 100, vibrato: 64, reverb: 32,
            vowel: phoneme.vowelCC, consonant: phoneme.consonantCC
        )
        playbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            audioMonitor.stopNote(note: 60)
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
}
