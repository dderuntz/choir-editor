import Foundation

/// Lookup service that converts English words to ChoirPhoneme arrays
/// using the CMU Pronouncing Dictionary (134k+ words, ARPAbet notation).
/// Falls back to nil for words not in the dictionary.
enum PhonemeDictionary {

    // MARK: - ARPAbet → Our IDs

    /// ARPAbet vowel → our Vowel ID
    private static let vowelMap: [String: String] = [
        "AA": "aa",     // father
        "AE": "ae",     // cat
        "AH": "schwa",  // comma (unstressed) — promoted to "uh" when stressed
        "AO": "aw",     // store
        "AW": "aa",     // cow — diphthong, closest single vowel
        "AY": "ai",     // buy
        "EH": "ae",     // bed → closest is cat
        "ER": "air",    // her, stair
        "EY": "ay",     // stray
        "IH": "ee",     // sit → closest (ee is long, IH is short)
        "IY": "ee",     // free
        "OW": "o",      // go
        "OY": "oi",     // boy
        "UH": "oo",     // book → closest
        "UW": "oo",     // zoo
    ]

    /// ARPAbet consonant → our Consonant ID
    private static let consonantMap: [String: String] = [
        "B":  "b",
        "CH": "tsh",
        "D":  "d",
        "DH": "th",     // voiced th (this) — we only have one "th"
        "F":  "f",
        "G":  "g",
        "HH": "h",
        "JH": "dj",
        "K":  "k",
        "L":  "l",
        "M":  "m",
        "N":  "n",
        "NG": "n",      // ng → closest is n
        "P":  "p",
        "R":  "r",
        "S":  "s",
        "SH": "sh",
        "T":  "t",
        "TH": "th",
        "V":  "v",
        "W":  "w",
        "Y":  "y",
        "Z":  "s",      // z → s
        "ZH": "sh",     // zh → sh
    ]

    /// Consonants that can sustain without a vowel (fricatives)
    private static let fricatives: Set<String> = ["s", "sh", "th", "f", "v", "h"]

    /// Consonants that need schwa if trailing (plosives)
    private static let plosives: Set<String> = ["b", "d", "g", "k", "p", "t", "tsh", "dj"]

    /// Nasal consonants → mmm
    private static let nasals: Set<String> = ["m", "n"]

    // MARK: - Dictionary Storage

    private static var dictionary: [String: [String]]? = nil

    /// Load the CMU dictionary from bundle
    static func loadIfNeeded() {
        guard dictionary == nil else { return }
        var dict = [String: [String]]()

        let url = Bundle.main.url(forResource: "cmudict", withExtension: "txt")

        guard let fileURL = url,
              let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("[PhonemeDict] ⚠ Could not load cmudict.txt")
            dictionary = dict
            return
        }

        for line in contents.split(separator: "\n") {
            let str = String(line)
            // Skip comments
            guard !str.hasPrefix(";;;") else { continue }
            // Format: "word  PH1 PH2 PH3" or "word(2)  PH1 PH2 PH3"
            let parts = str.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }

            var word = String(parts[0]).lowercased()
            // Strip variant markers like "(2)", "(3)"
            if let paren = word.firstIndex(of: "(") {
                word = String(word[..<paren])
            }
            // Only keep the first pronunciation variant
            if dict[word] != nil { continue }

            let phonemes = parts[1].split(separator: " ").map { String($0) }
            dict[word] = phonemes
        }

        dictionary = dict
        print("[PhonemeDict] Loaded \(dict.count) words")
    }

    // MARK: - Lookup

    /// Look up a single word → array of ChoirPhoneme, or nil if not found
    static func lookup(_ word: String) -> [ChoirPhoneme]? {
        loadIfNeeded()
        let key = word.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Exact match
        if let arpa = dictionary?[key] {
            return arpaToChoir(arpa, originalWord: key)
        }

        // Suffix stripping: look up base, append suffix in ARPAbet
        if let (arpa, fullWord) = lookupWithSuffix(key) {
            return arpaToChoir(arpa, originalWord: fullWord)
        }

        return nil
    }

    /// ARPAbet voiceless consonants (plural -s → S after these, otherwise Z)
    private static let voicelessArpa: Set<String> = ["P", "T", "K", "F", "TH"]
    /// ARPAbet sibilants (plural gets extra syllable: IH0 Z)
    private static let sibilantArpa: Set<String> = ["S", "Z", "SH", "ZH", "CH", "JH"]

    /// Try stripping -s, -es, -ed, -ing and look up the base word.
    /// Returns the base ARPAbet + suffix phonemes appended, or nil.
    private static func lookupWithSuffix(_ word: String) -> (arpa: [String], word: String)? {
        // Try suffixes from longest to shortest
        let suffixes: [(strip: String, restore: String?, arpaFn: ([String]) -> [String])] = [
            // -ing: strip "ing", try base, also try base+"e" (e.g. "dancing" → "dance")
            ("ing", nil, { _ in ["IH0", "NG"] }),
            // -es: strip "es" (e.g. "watches" → "watch")
            ("es", nil, { base in
                guard let last = base.last else { return ["IH0", "Z"] }
                let stripped = last.filter { !$0.isNumber }
                if sibilantArpa.contains(stripped) { return ["IH0", "Z"] }
                return ["Z"]
            }),
            // -ed: strip "ed"
            ("ed", nil, { base in
                guard let last = base.last else { return ["D"] }
                let stripped = last.filter { !$0.isNumber }
                if stripped == "T" || stripped == "D" { return ["IH0", "D"] }
                if voicelessArpa.contains(stripped) { return ["T"] }
                return ["D"]
            }),
            // -s: strip "s"
            ("s", nil, { base in
                guard let last = base.last else { return ["Z"] }
                let stripped = last.filter { !$0.isNumber }
                if sibilantArpa.contains(stripped) { return ["IH0", "Z"] }
                if voicelessArpa.contains(stripped) { return ["S"] }
                return ["Z"]
            }),
        ]

        for suffix in suffixes {
            guard word.hasSuffix(suffix.strip) else { continue }
            let base = String(word.dropLast(suffix.strip.count))
            guard !base.isEmpty else { continue }

            // Try base as-is
            if let baseArpa = dictionary?[base] {
                let suffixArpa = suffix.arpaFn(baseArpa)
                return (baseArpa + suffixArpa, word)
            }

            // For -ing, also try base+"e" (dancing → dance, loving → love)
            if suffix.strip == "ing", let baseArpa = dictionary?[base + "e"] {
                let suffixArpa = suffix.arpaFn(baseArpa)
                return (baseArpa + suffixArpa, word)
            }
        }

        return nil
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

    // MARK: - ARPAbet → ChoirPhoneme Conversion

    /// Convert ARPAbet phoneme sequence to consonant+vowel note pairs
    private static func arpaToChoir(_ arpa: [String], originalWord: String) -> [ChoirPhoneme] {
        // Classify each ARPAbet phoneme
        struct Sound {
            let arpa: String        // Original ARPAbet symbol (without stress number)
            let isVowel: Bool
            let stress: Int         // 0, 1, or 2 (only for vowels)
            let ourID: String       // Our consonant or vowel ID
        }

        var sounds: [Sound] = []
        for ph in arpa {
            // Strip stress number from vowels (e.g. "AA1" → "AA", stress 1)
            let stripped: String
            let stress: Int
            if let last = ph.last, last.isNumber {
                stripped = String(ph.dropLast())
                stress = Int(String(last)) ?? 0
            } else {
                stripped = ph
                stress = -1 // consonant
            }

            if let vowelID = vowelMap[stripped] {
                // Special case: AH with stress → "uh" instead of "schwa"
                let finalID = (stripped == "AH" && stress > 0) ? "uh" : vowelID
                sounds.append(Sound(arpa: stripped, isVowel: true, stress: stress, ourID: finalID))
            } else if let consID = consonantMap[stripped] {
                sounds.append(Sound(arpa: stripped, isVowel: false, stress: -1, ourID: consID))
            }
            // else: unknown phoneme, skip
        }

        // Pair consonants with following vowels → notes
        // When multiple consonants pile up between vowels, the LAST one (or last valid
        // onset cluster) starts the new syllable. Earlier ones are coda of the previous syllable.
        var notes: [(consonant: String, vowel: String, weight: Int)] = []
        var pendingConsonants: [String] = []

        for sound in sounds {
            if sound.isVowel {
                // Find the onset: try last 2 consonants as cluster, then just last 1
                let onset: String
                if pendingConsonants.count >= 2 {
                    let last2 = pendingConsonants.suffix(2).joined()
                    if validOnsets.contains(last2) {
                        // Last 2 form a cluster — emit earlier ones as coda
                        let coda = Array(pendingConsonants.dropLast(2))
                        emitCoda(coda, into: &notes)
                        onset = last2
                    } else {
                        // Just last 1 is the onset
                        let coda = Array(pendingConsonants.dropLast(1))
                        emitCoda(coda, into: &notes)
                        onset = pendingConsonants.last ?? "none"
                    }
                } else {
                    onset = pendingConsonants.last ?? "none"
                }

                let weight = stressToWeight(sound.stress)
                notes.append((consonant: onset, vowel: sound.ourID, weight: weight))
                pendingConsonants.removeAll()
            } else {
                pendingConsonants.append(sound.ourID)
            }
        }

        // Handle trailing consonants (no vowel follows)
        emitCoda(pendingConsonants, into: &notes)

        // Distribute original word letters across notes (guided by note needs)
        let textChunks = distributeText(originalWord, notes: notes)

        // Convert to ChoirPhoneme
        return notes.enumerated().compactMap { (i, note) in
            guard let c = Consonant.all.first(where: { $0.id == note.consonant }),
                  let v = Vowel.all.first(where: { $0.id == note.vowel })
            else { return nil }
            let text = i < textChunks.count ? textChunks[i] : ""
            return ChoirPhoneme(text: text, consonantCC: c.ccValue, vowelCC: v.ccValue, weight: note.weight)
        }
    }

    /// Valid onset clusters (from our consonant list)
    private static let validOnsets: Set<String> = [
        "bl", "br", "dr", "fl", "fr", "gl", "gr", "kl", "kr",
        "pl", "pr", "sl", "tr", "thr", "bj", "fj", "nj"
    ]

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
            // else: skip (e.g. trailing 'r' gets absorbed)
        }
    }

    /// Map CMU stress (0/1/2) to our weight (1/2/3)
    private static func stressToWeight(_ stress: Int) -> Int {
        switch stress {
        case 1: return 3  // primary → loud
        case 2: return 2  // secondary → medium
        default: return 1 // unstressed → weak
        }
    }

    private static let vowelLetters: Set<Character> = ["a", "e", "i", "o", "u", "y"]
    /// Vowels that are "real" (note needs vowel letters from the word)
    private static let syntheticVowels: Set<String> = ["none", "schwa", "mmm"]

    /// How each consonant ID could be spelled (longest first for greedy match)
    private static let consonantSpellings: [String: [[Character]]] = [
        "s":   [["s", "s"], ["s"], ["c"]],
        "k":   [["c", "k"], ["k"], ["c"]],
        "t":   [["t", "t"], ["t"]],
        "d":   [["d", "d"], ["d"]],
        "n":   [["n", "n"], ["n"]],
        "m":   [["m", "m"], ["m"]],
        "l":   [["l", "l"], ["l"]],
        "r":   [["r", "r"], ["r"]],
        "b":   [["b", "b"], ["b"]],
        "p":   [["p", "p"], ["p"]],
        "f":   [["f", "f"], ["p", "h"], ["g", "h"], ["f"]],
        "g":   [["g", "g"], ["g"]],
        "v":   [["v"]],
        "w":   [["w"]],
        "h":   [["h"]],
        "y":   [["y"]],
        "th":  [["t", "h"]],
        "sh":  [["s", "h"]],
        "tsh": [["t", "c", "h"], ["c", "h"]],
        "dj":  [["d", "g"], ["j"]],
    ]

    /// Distribute letters across notes guided by what each note needs.
    /// Anchor on consonant letters first (using spelling lookup), push skipped letters
    /// to previous chunk, then eat vowel letters if the note has a real vowel.
    private static func distributeText(_ word: String, notes: [(consonant: String, vowel: String, weight: Int)]) -> [String] {
        guard !notes.isEmpty else { return [] }
        let chars = Array(word.lowercased())
        var chunks: [String] = []
        var cursor = 0

        for (idx, note) in notes.enumerated() {
            let isLast = idx == notes.count - 1
            let needsVowel = !syntheticVowels.contains(note.vowel)
            let hasConsonant = note.consonant != "none"

            if isLast {
                chunks.append(cursor < chars.count ? String(chars[cursor...]) : "")
                cursor = chars.count
                continue
            }

            var chunkStart = cursor

            // Step 1: If note has a consonant onset, find its letter(s)
            if hasConsonant {
                let spellings = consonantSpellings[note.consonant] ?? []
                var found = false
                for scanPos in cursor..<chars.count {
                    for sp in spellings {
                        let end = scanPos + sp.count
                        if end <= chars.count && Array(chars[scanPos..<end]) == sp {
                            // Push skipped letters to previous chunk
                            if scanPos > cursor && !chunks.isEmpty {
                                chunks[chunks.count - 1] += String(chars[cursor..<scanPos])
                            }
                            chunkStart = scanPos
                            cursor = end
                            found = true
                            break
                        }
                    }
                    if found { break }
                }
                if !found {
                    // Fallback: consume 1 letter
                    if cursor < chars.count { cursor += 1 }
                }
            }

            // Step 2: If note needs a vowel, eat through the next vowel letter(s)
            if needsVowel && cursor < chars.count {
                if !hasConsonant {
                    // No consonant — start chunk here, eat to vowel
                    chunkStart = cursor
                }
                var foundVowel = false
                while cursor < chars.count {
                    if vowelLetters.contains(chars[cursor]) {
                        cursor += 1
                        foundVowel = true
                        // Eat trailing vowel digraphs (ea, ou, etc.)
                        while cursor < chars.count && vowelLetters.contains(chars[cursor]) {
                            cursor += 1
                        }
                        break
                    }
                    cursor += 1
                }
                if !foundVowel && cursor == chunkStart {
                    cursor = min(chunkStart + 1, chars.count)
                }
            }

            chunks.append(String(chars[chunkStart..<min(cursor, chars.count)]))
        }

        // Second pass: coda chunks that start with non-matching letters
        // push those letters back to the previous chunk
        for i in 1..<chunks.count {
            let note = notes[i]
            guard syntheticVowels.contains(note.vowel), note.consonant != "none" else { continue }
            let chunkChars = Array(chunks[i])
            guard chunkChars.count > 1 else { continue }
            let spellings = consonantSpellings[note.consonant] ?? []
            var trimPos = -1
            outer: for pos in 0..<chunkChars.count {
                for sp in spellings {
                    let end = pos + sp.count
                    if end <= chunkChars.count && Array(chunkChars[pos..<end]) == sp {
                        trimPos = pos
                        break outer
                    }
                }
            }
            if trimPos > 0 {
                chunks[i - 1] += String(chunkChars[0..<trimPos])
                chunks[i] = String(chunkChars[trimPos...])
            }
        }

        return chunks
    }
}
