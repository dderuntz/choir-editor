import Foundation

/// Lookup service that converts English words to ChoirPhoneme arrays
/// using a pre-compiled binary dictionary (en.choirdict).
/// Suffix variants (-s, -es, -ed, -ing) are pre-computed in the binary.
/// Falls back to Swedish dictionary if not found in English.
enum PhonemeDictionary {

    // MARK: - Dictionary Storage

    private nonisolated(unsafe) static var dictionary: [String: [ChoirPhoneme]]? = nil

    /// Load the binary dictionary from bundle
    static func loadIfNeeded() {
        guard dictionary == nil else { return }
        dictionary = BinaryPhonemeDictionary.load(resource: "en")
        print("[PhonemeDict] Loaded \(dictionary?.count ?? 0) words from en.choirdict")
    }

    // MARK: - Lookup

    /// Look up a single word → array of ChoirPhoneme, or nil if not found.
    /// Falls back to Swedish dictionary if not found in English.
    static func lookup(_ word: String) -> [ChoirPhoneme]? {
        if let result = lookupEnglish(word) { return result }
        return SwedishPhonemeDictionary.lookupSwedish(word)
    }

    /// English-only lookup (no cross-language fallback)
    static func lookupEnglish(_ word: String) -> [ChoirPhoneme]? {
        loadIfNeeded()
        let key = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return dictionary?[key]
    }

    /// Look up a full sentence → array of ChoirPhoneme
    /// Words not in dictionary get nil (caller can fall back to LLM for those)
    static func lookupSentence(_ text: String) -> (found: [ChoirPhoneme], missing: [String]) {
        loadIfNeeded()
        var allPhonemes: [ChoirPhoneme] = []
        var missingWords: [String] = []
        var wordIdx = 0

        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        for word in words {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            guard !clean.isEmpty else { continue }
            if var phonemes = lookup(clean) {
                for i in phonemes.indices { phonemes[i].wordIndex = wordIdx }
                allPhonemes.append(contentsOf: phonemes)
            } else {
                missingWords.append(clean)
            }
            wordIdx += 1
        }

        return (allPhonemes, missingWords)
    }
}
