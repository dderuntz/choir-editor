import Foundation

/// Lookup service that converts Swedish words to ChoirPhoneme arrays
/// using a pre-compiled binary dictionary (sv.choirdict).
/// Falls back to English dictionary if not found in Swedish.
enum SwedishPhonemeDictionary {

    // MARK: - Dictionary Storage

    private nonisolated(unsafe) static var dictionary: [String: [ChoirPhoneme]]? = nil

    /// Load the binary dictionary from bundle
    static func loadIfNeeded() {
        guard dictionary == nil else { return }
        dictionary = BinaryPhonemeDictionary.load(resource: "sv")
        print("[SwPhonemeDict] Loaded \(dictionary?.count ?? 0) words from sv.choirdict")
    }

    // MARK: - Lookup

    /// Look up a single word → array of ChoirPhoneme, or nil if not found.
    /// Falls back to English dictionary if not found in Swedish.
    static func lookup(_ word: String) -> [ChoirPhoneme]? {
        if let result = lookupSwedish(word) { return result }
        return PhonemeDictionary.lookupEnglish(word)
    }

    /// Swedish-only lookup (no cross-language fallback)
    static func lookupSwedish(_ word: String) -> [ChoirPhoneme]? {
        loadIfNeeded()
        let key = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard !key.isEmpty else { return nil }
        return dictionary?[key]
    }

    /// Look up a full sentence → array of ChoirPhoneme
    /// Words not in dictionary are returned in missing (caller skips them).
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
