import Foundation
import os
import FoundationModels

private let log = Logger(subsystem: "com.choir-arranger", category: "phoneme-extractor")

// MARK: - Extraction Result

struct ExtractionResult {
    let phonemes: [ChoirPhoneme]
    /// If the LLM normalized the text (Tier 2), this contains the cleaned version.
    let normalizedText: String?
    /// Non-nil if LLM failed (phonemes may still be partial from dictionary).
    let errorMessage: String?
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
        log.info("Saved example: \"\(example.inputText)\" (\(example.syllables.count) syllables, \(load().count) total)")
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

// MARK: - English Phoneme Extractor

/// Three-tier extraction pipeline: dictionary → LLM normalize + retry → LLM full extraction.
/// Stateless — returns an ExtractionResult. ComposerModel manages UI state transitions.
@MainActor
class EnglishPhonemeExtractor {

    /// Check on-device LLM availability
    func checkAvailability() -> (available: Bool, message: String?) {
        if #available(macOS 26, *) {
            return checkAvailabilityImpl()
        }
        return (false, nil)
    }

    @available(macOS 26, *)
    private func checkAvailabilityImpl() -> (available: Bool, message: String?) {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return (true, nil)
        case .unavailable(let reason):
            let message: String
            switch reason {
            case .deviceNotEligible:
                message = "This Mac doesn't support Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                message = "Enable Apple Intelligence in System Settings"
            case .modelNotReady:
                message = "Model is downloading…"
            @unknown default:
                message = "Apple Intelligence unavailable"
            }
            return (false, message)
        @unknown default:
            return (false, nil)
        }
    }

    // MARK: - 3-Tier Extraction Pipeline

    func extract(text: String) async -> ExtractionResult {
        // ── Tier 1: Dictionary lookup ──
        let firstTry = PhonemeDictionary.lookupSentence(text)

        if firstTry.missing.isEmpty {
            log.info("Dict (direct): \(firstTry.found.count) phonemes from: \(text)")
            logPhonemes(firstTry.found)
            return ExtractionResult(phonemes: firstTry.found, normalizedText: nil, errorMessage: nil)
        }

        log.info("Dict missed \(firstTry.missing.count) words: \(firstTry.missing)")

        // ── Tier 2: LLM normalizes text → retry dict ──
        if #available(macOS 26, *) {
            if let cleanWords = await normalizeWithLLM(text: text) {
                let cleanText = cleanWords.joined(separator: " ")
                let retry = PhonemeDictionary.lookupSentence(cleanText)

                if retry.missing.isEmpty {
                    log.info("Dict (after LLM normalize): \(retry.found.count) phonemes")
                    logPhonemes(retry.found)
                    return ExtractionResult(phonemes: retry.found, normalizedText: cleanText, errorMessage: nil)
                }

                // ── Tier 3: Dict got most, LLM fallback for remaining words ──
                log.info("Still missing after normalize: \(retry.missing)")
                var combined = retry.found
                let nextWordIdx = (combined.map(\.wordIndex).max() ?? -1) + 1
                let missingText = retry.missing.joined(separator: " ")
                var llmResult = await extractWithLLM(text: missingText)
                let llmError = llmResult.isEmpty && !retry.missing.isEmpty ? "LLM extraction failed for: \(missingText)" : nil
                for i in llmResult.indices { llmResult[i].wordIndex = nextWordIdx + i }
                combined.append(contentsOf: llmResult)
                log.info("Combined: \(retry.found.count) dict + \(llmResult.count) LLM = \(combined.count) total")
                logPhonemes(combined)
                return ExtractionResult(phonemes: combined, normalizedText: cleanText, errorMessage: llmError)
            } else {
                // Normalize failed — full LLM fallback on original text
                log.info("Normalize failed, full LLM fallback")
                let result = await extractWithLLM(text: text)
                logPhonemes(result)
                let error = result.isEmpty ? "LLM extraction failed" : nil
                return ExtractionResult(phonemes: result, normalizedText: nil, errorMessage: error)
            }
        } else {
            return ExtractionResult(phonemes: firstTry.found, normalizedText: nil, errorMessage: "Requires macOS 26 (Tahoe)")
        }
    }

    // MARK: - Private LLM Methods

    @available(macOS 26, *)
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
            log.info("LLM normalized: \"\(text)\" → \(words)")
            return words
        } catch {
            log.error("Normalize error: \(error)")
            return nil
        }
    }

    @available(macOS 26, *)
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
                    log.warning("Unmapped: \(syl.text) → \(syl.consonant)+\(syl.vowel)")
                    return nil
                }
                let trimmed = syl.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty && syl.consonant == "none" && syl.vowel == "none" { return nil }
                let label = trimmed.isEmpty ? "\(c.name)" : trimmed
                let w = max(1, min(3, syl.weight))
                return ChoirPhoneme(text: label, consonantCC: c.ccValue, vowelCC: v.ccValue, weight: w)
            }

            log.info("LLM: extracted \(result.count) phonemes from: \(text)")
            for (i, p) in result.enumerated() {
                log.debug("  [\(i)] \(p.text): \(p.consonantName)·\(p.vowelSymbol) (CC \(p.consonantCC)/\(p.vowelCC))")
            }
            return result
        } catch {
            log.error("LLM error: \(error)")
            return []
        }
    }

    private func logPhonemes(_ list: [ChoirPhoneme]) {
        for (i, p) in list.enumerated() {
            log.debug("  [\(i)] \(p.text): \(p.consonantName)·\(p.vowelSymbol) w\(p.weight)")
        }
    }
}
