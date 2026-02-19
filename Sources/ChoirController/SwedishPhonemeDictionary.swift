import Foundation

/// Lookup service that converts Swedish words to ChoirPhoneme arrays
/// using the OpenSLR #29 lexicon (823k entries, Swedish SAMPA notation).
/// License: CC BY 4.0 (NST / Riksbankens Jubileumsfond).
/// Falls back to nil for words not in the dictionary.
enum SwedishPhonemeDictionary {

    // MARK: - Swedish SAMPA → Our IDs

    /// Swedish SAMPA vowel → our Vowel ID
    /// ⚠️ Front rounded vowels (y:, Y, 2:, 9, }:) have no English equivalent.
    /// The doll will sound "English-accented Swedish" for ö/ü/y sounds.
    private static let vowelMap: [String: String] = [
        // Short vowels
        "a":   "aa",     // kort a (katt)
        "E":   "ae",     // ä-ljud (äta)
        "I":   "ee",     // kort i (sitta) — closest: ee (short)
        "O":   "aw",     // kort o (kort) — open-mid back
        "u0":  "uh",     // kort u (hund) — central rounded → closest uh
        "U":   "oo",     // kort u (full) — close back rounded
        "Y":   "ee",     // kort y (syster) — ⚠️ front rounded → ee
        "9":   "ae",     // kort ö (dörr) — ⚠️ front rounded → ae

        // Long vowels
        "A:":  "aa",     // långt a (far)
        "e:":  "ay",     // långt e (lek)
        "E:":  "air",    // långt ä (lär) — open-mid front
        "i:":  "ee",     // långt i (rita)
        "o:":  "oo",     // långt o (sol) — close back rounded
        "u:":  "oo",     // långt u (stol) — close back rounded
        "y:":  "ee",     // långt y (byta) — ⚠️ front rounded → ee
        "2:":  "ay",     // långt ö (öl) — ⚠️ front rounded → ay
        "}:":  "oo",     // långt u/ö (hus) — central rounded → oo

        // Diphthongs (rare)
        "a*U": "aa",     // /aʊ/ — map to first vowel
        "E*U": "ae",     // /ɛʊ/ — map to first vowel

        // Schwa (reduced vowel)
        "e":   "schwa",  // obetonad e (katten) — unstressed e
    ]

    /// Swedish SAMPA consonant → our Consonant ID
    private static let consonantMap: [String: String] = [
        // Standard consonants (same as English)
        "b":   "b",
        "d":   "d",
        "f":   "f",
        "g":   "g",
        "h":   "h",
        "j":   "y",      // Swedish j = English y sound
        "k":   "k",
        "l":   "l",
        "m":   "m",
        "n":   "n",
        "p":   "p",
        "r":   "r",
        "s":   "s",
        "t":   "t",
        "v":   "v",

        // Swedish-specific
        "N":   "n",      // velar nasal (ŋ, as in "sing") → n
        "S":   "sh",     // sj-ljud (ɧ/ʃ) — voiceless
        "s'":  "sh",     // sj-ljud variant → sh

        // Retroflexes (backtick suffix) — map to non-retroflex
        "d`":  "d",      // retroflex d (ɖ)
        "t`":  "t",      // retroflex t (ʈ)
        "n`":  "n",      // retroflex n (ɳ)
        "l`":  "l",      // retroflex l (ɭ)
        "s`":  "s",      // retroflex s (ʂ)
    ]

    /// Valid two-consonant onset clusters in Swedish
    private static let validOnsets: Set<String> = [
        "bl", "br", "dr", "fl", "fr", "gl", "gr", "kl", "kr",
        "pl", "pr", "sl", "tr", "thr",
        // Swedish-specific clusters
        "sk", "sp", "st", "sv", "sn", "sm",
        "skr", "spr", "str",
        // Choir doll clusters
        "bj", "fj", "nj",
    ]

    /// Consonants that can sustain without a vowel (fricatives)
    private static let fricatives: Set<String> = ["s", "sh", "f", "v", "h"]

    /// Consonants that need schwa if trailing (plosives)
    private static let plosives: Set<String> = ["b", "d", "g", "k", "p", "t"]

    /// Nasal consonants → mmm
    private static let nasals: Set<String> = ["m", "n"]

    // MARK: - Dictionary Storage

    private nonisolated(unsafe) static var dictionary: [String: (phonemes: [String], stresses: [Int])]? = nil

    /// Load the Swedish lexicon from bundle
    static func loadIfNeeded() {
        guard dictionary == nil else { return }
        var dict = [String: (phonemes: [String], stresses: [Int])]()

        let url = Bundle.main.url(forResource: "swe_lexicon", withExtension: "txt")

        guard let fileURL = url,
              let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("[SwPhonemeDict] ⚠ Could not load swe_lexicon.txt")
            dictionary = dict
            return
        }

        for line in contents.split(separator: "\n") {
            let str = String(line)
            // Skip special entries
            guard !str.hasPrefix("!") && !str.hasPrefix("<") else { continue }

            // Tab-separated: WORD\tphonemes
            let parts = str.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }

            var word = String(parts[0]).lowercased()
            // Strip leading dash (compound part markers)
            if word.hasPrefix("-") { word = String(word.dropFirst()) }
            // Skip empty, numeric-only, or single-char abbreviation entries
            guard word.count >= 2 else { continue }
            // Only keep the first pronunciation variant
            if dict[word] != nil { continue }

            // Parse SAMPA phonemes with stress markers
            let parsed = parseSAMPA(String(parts[1]))
            dict[word] = parsed
        }

        dictionary = dict
        print("[SwPhonemeDict] Loaded \(dict.count) words")
    }

    // MARK: - SAMPA Parsing

    /// Parse a SAMPA phoneme string into (phoneme tokens, stress levels).
    /// Stress markers: " = primary (3), % = secondary (2), none = unstressed (1).
    /// Stress is carried forward to the next vowel.
    private static func parseSAMPA(_ raw: String) -> (phonemes: [String], stresses: [Int]) {
        let tokens = raw.split(separator: " ").map { String($0) }
        var phonemes: [String] = []
        var stresses: [Int] = []
        var pendingStress = 1  // default unstressed

        for token in tokens {
            var t = token

            // Check for stress prefix
            if t.hasPrefix("\"") {
                pendingStress = 3  // primary
                t = String(t.dropFirst())
            } else if t.hasPrefix("%") {
                pendingStress = 2  // secondary
                t = String(t.dropFirst())
            }

            guard !t.isEmpty else { continue }

            // Is this a vowel or consonant?
            let isVowel = vowelMap[t] != nil

            phonemes.append(t)
            stresses.append(isVowel ? pendingStress : -1)  // -1 for consonants

            // Reset stress after attaching to a vowel
            if isVowel {
                pendingStress = 1
            }
        }

        return (phonemes, stresses)
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

        if let entry = dictionary?[key] {
            return sampaToChoir(entry.phonemes, stresses: entry.stresses, originalWord: key)
        }

        return nil
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

    // MARK: - SAMPA → ChoirPhoneme Conversion

    /// Convert parsed SAMPA sequence to consonant+vowel note pairs
    private static func sampaToChoir(_ phonemes: [String], stresses: [Int], originalWord: String) -> [ChoirPhoneme] {
        struct Sound {
            let sampa: String
            let isVowel: Bool
            let stress: Int       // 1/2/3 for vowels, -1 for consonants
            let choirID: String   // our consonant or vowel ID
        }

        var sounds: [Sound] = []
        for (i, ph) in phonemes.enumerated() {
            let stress = stresses[i]
            if let vowelID = vowelMap[ph] {
                sounds.append(Sound(sampa: ph, isVowel: true, stress: stress, choirID: vowelID))
            } else if let consID = consonantMap[ph] {
                sounds.append(Sound(sampa: ph, isVowel: false, stress: -1, choirID: consID))
            }
            // else: unknown phoneme (SIL, SPN, etc.) — skip
        }

        // Pair consonants with following vowels → notes
        var notes: [(consonant: String, vowel: String, weight: Int)] = []
        var pendingConsonants: [String] = []

        for sound in sounds {
            if sound.isVowel {
                // Find onset: try last 2 consonants as cluster, then just last 1
                let onset: String
                if pendingConsonants.count >= 2 {
                    let last2 = pendingConsonants.suffix(2).joined()
                    if validOnsets.contains(last2) {
                        let coda = Array(pendingConsonants.dropLast(2))
                        emitCoda(coda, into: &notes)
                        onset = last2
                    } else {
                        let coda = Array(pendingConsonants.dropLast(1))
                        emitCoda(coda, into: &notes)
                        onset = pendingConsonants.last ?? "none"
                    }
                } else {
                    onset = pendingConsonants.last ?? "none"
                }

                notes.append((consonant: onset, vowel: sound.choirID, weight: sound.stress))
                pendingConsonants.removeAll()
            } else {
                pendingConsonants.append(sound.choirID)
            }
        }

        // Handle trailing consonants
        emitCoda(pendingConsonants, into: &notes)

        // Distribute original word letters across notes
        let textChunks = distributeText(originalWord, noteCount: notes.count)

        // Convert to ChoirPhoneme
        return notes.enumerated().compactMap { (i, note) in
            guard let c = Consonant.all.first(where: { $0.id == note.consonant }),
                  let v = Vowel.all.first(where: { $0.id == note.vowel })
            else { return nil }
            let text = i < textChunks.count ? textChunks[i] : ""
            return ChoirPhoneme(text: text, consonantCC: c.ccValue, vowelCC: v.ccValue, weight: note.weight)
        }
    }

    /// Emit consonants as coda (trailing) notes
    private static func emitCoda(_ consonants: [String], into notes: inout [(consonant: String, vowel: String, weight: Int)]) {
        for cons in consonants {
            if nasals.contains(cons) {
                notes.append((consonant: cons, vowel: "mmm", weight: 1))
            } else if fricatives.contains(cons) {
                notes.append((consonant: cons, vowel: "none", weight: 1))
            } else if plosives.contains(cons) {
                notes.append((consonant: cons, vowel: "schwa", weight: 1))
            }
            // else: trailing r, l, y etc. — absorbed (Swedish trailing r is common)
        }
    }

    // MARK: - Swedish Vowel Letters

    /// Swedish vowel letters (includes å, ä, ö)
    private static let vowelLetters: Set<Character> = ["a", "e", "i", "o", "u", "y", "å", "ä", "ö"]

    /// Distribute word letters across N notes.
    /// Swedish spelling is more regular than English, so a simpler proportional
    /// split works well. We anchor on vowel letters as syllable nuclei.
    private static func distributeText(_ word: String, noteCount: Int) -> [String] {
        guard noteCount > 0 else { return [] }
        let chars = Array(word)
        guard !chars.isEmpty else { return Array(repeating: "", count: noteCount) }

        if noteCount == 1 {
            return [word]
        }

        // Find vowel positions — these are natural syllable anchors
        var vowelPositions: [Int] = []
        for (i, ch) in chars.enumerated() {
            if vowelLetters.contains(ch) {
                vowelPositions.append(i)
            }
        }

        // If we have enough vowels, split around them
        if vowelPositions.count >= noteCount {
            // Use first N vowel positions as cut points
            // Each chunk goes from after the previous cut to after this vowel
            var chunks: [String] = []
            var cursor = 0
            let usedVowels = Array(vowelPositions.prefix(noteCount))
            for (i, vPos) in usedVowels.enumerated() {
                let isLast = i == usedVowels.count - 1
                if isLast {
                    chunks.append(String(chars[cursor...]))
                } else {
                    // Include up to and including the vowel, plus any immediately following
                    // consonants that aren't before the next vowel
                    let nextVowel = usedVowels[i + 1]
                    // Simple midpoint split between this vowel and next vowel
                    let splitPoint = vPos + 1 + (nextVowel - vPos - 1) / 2
                    let end = max(vPos + 1, min(splitPoint, chars.count))
                    chunks.append(String(chars[cursor..<end]))
                    cursor = end
                }
            }
            // If we made fewer chunks than needed, pad
            while chunks.count < noteCount { chunks.append("") }
            return chunks
        }

        // Fallback: proportional split
        let charsPerNote = max(1, chars.count / noteCount)
        var chunks: [String] = []
        var cursor = 0
        for i in 0..<noteCount {
            if i == noteCount - 1 {
                chunks.append(cursor < chars.count ? String(chars[cursor...]) : "")
            } else {
                let end = min(cursor + charsPerNote, chars.count)
                chunks.append(cursor < chars.count ? String(chars[cursor..<end]) : "")
                cursor = end
            }
        }
        return chunks
    }
}
