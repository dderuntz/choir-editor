import Foundation

/// Compiles cmudict.txt → en.choirdict binary.
/// Contains all English mapping/conversion logic (copied from PhonemeDictionary.swift).
enum EnglishCompiler {

    // MARK: - ARPAbet → Choir IDs (same as PhonemeDictionary.swift)

    private static let vowelMap: [String: String] = [
        "AA": "aa",     // father
        "AE": "ae",     // cat
        "AH": "schwa",  // comma (unstressed) — promoted to "uh" when stressed
        "AO": "aw",     // store
        "AW": "aa",     // cow
        "AY": "ai",     // buy
        "EH": "ae",     // bed
        "ER": "air",    // her
        "EY": "ay",     // stray
        "IH": "ee",     // sit
        "IY": "ee",     // free
        "OW": "o",      // go
        "OY": "oi",     // boy
        "UH": "oo",     // book
        "UW": "oo",     // zoo
    ]

    private static let consonantMap: [String: String] = [
        "B":  "b",
        "CH": "tsh",
        "D":  "d",
        "DH": "th",
        "F":  "f",
        "G":  "g",
        "HH": "h",
        "JH": "dj",
        "K":  "k",
        "L":  "l",
        "M":  "m",
        "N":  "n",
        "NG": "n",
        "P":  "p",
        "R":  "r",
        "S":  "s",
        "SH": "sh",
        "T":  "t",
        "TH": "th",
        "V":  "v",
        "W":  "w",
        "Y":  "y",
        "Z":  "s",
        "ZH": "sh",
    ]

    private static let fricatives: Set<String> = ["s", "sh", "th", "f", "v", "h"]
    private static let plosives: Set<String> = ["b", "d", "g", "k", "p", "t", "tsh", "dj"]
    private static let nasals: Set<String> = ["m", "n"]

    private static let validOnsets: Set<String> = [
        "bl", "br", "dr", "fl", "fr", "gl", "gr", "kl", "kr",
        "pl", "pr", "sl", "tr", "thr", "bj", "fj", "nj"
    ]

    private static let voicelessArpa: Set<String> = ["P", "T", "K", "F", "TH"]
    private static let sibilantArpa: Set<String> = ["S", "Z", "SH", "ZH", "CH", "JH"]

    // MARK: - CC Value Lookups (from ChoirMappings.swift)

    private static let consonantCCValues: [String: UInt8] = [
        "random": 0, "b": 4, "bj": 7, "bl": 10, "br": 14, "tsh": 17,
        "d": 20, "dr": 23, "f": 27, "fj": 30, "fl": 33, "fr": 37,
        "g": 40, "gl": 43, "gr": 46, "h": 50, "dj": 53, "k": 56,
        "kl": 60, "kr": 63, "l": 66, "m": 69, "n": 73, "nj": 76,
        "p": 79, "pl": 83, "pr": 86, "r": 89, "s": 92, "sl": 96,
        "sh": 99, "t": 102, "tr": 106, "th": 109, "thr": 112, "v": 115,
        "w": 119, "y": 122, "none": 125,
    ]

    private static let vowelCCValues: [String: UInt8] = [
        "random": 0, "aa": 8, "ai": 16, "ae": 23, "schwa": 31,
        "aw": 38, "oi": 46, "o": 53, "uh": 61, "oo": 68, "ee": 76,
        "ear": 83, "ay": 91, "air": 98, "ure": 106, "mmm": 113, "none": 121,
    ]

    // MARK: - Text Distribution

    private static let vowelLetters: Set<Character> = ["a", "e", "i", "o", "u", "y"]
    private static let syntheticVowels: Set<String> = ["none", "schwa", "mmm"]

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

    // MARK: - Compile

    /// Read cmudict.txt and produce binary entries including suffix variants.
    static func compile(cmudictURL: URL) throws -> [BinaryFormat.Entry] {
        let contents = try String(contentsOf: cmudictURL, encoding: .utf8)

        // Parse text dictionary → [word: [ARPAbet]]
        var rawDict = [String: [String]]()
        for line in contents.split(separator: "\n") {
            let str = String(line)
            guard !str.hasPrefix(";;;") else { continue }
            let parts = str.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }

            var word = String(parts[0]).lowercased()
            if let paren = word.firstIndex(of: "(") {
                word = String(word[..<paren])
            }
            if rawDict[word] != nil { continue }
            rawDict[word] = parts[1].split(separator: " ").map { String($0) }
        }

        print("[EnglishCompiler] Parsed \(rawDict.count) base words")

        // Convert base words
        var entries = [String: BinaryFormat.Entry]()
        for (word, arpa) in rawDict {
            if let entry = convertToBinaryEntry(word: word, arpa: arpa) {
                entries[word] = entry
            }
        }

        // Generate suffix variants (-s, -es, -ed, -ing)
        var suffixCount = 0
        for (word, arpa) in rawDict {
            for (variantWord, variantArpa) in suffixVariants(word: word, baseArpa: arpa, existing: rawDict) {
                guard entries[variantWord] == nil else { continue }
                if let entry = convertToBinaryEntry(word: variantWord, arpa: variantArpa) {
                    entries[variantWord] = entry
                    suffixCount += 1
                }
            }
        }

        print("[EnglishCompiler] Generated \(suffixCount) suffix variants")
        print("[EnglishCompiler] Total entries: \(entries.count)")
        return Array(entries.values)
    }

    // MARK: - Suffix Generation

    private static func suffixVariants(word: String, baseArpa: [String], existing: [String: [String]]) -> [(String, [String])] {
        var variants: [(String, [String])] = []

        let ing = word + "ing"
        if existing[ing] == nil {
            variants.append((ing, baseArpa + ["IH0", "NG"]))
        }

        let s = word + "s"
        if existing[s] == nil {
            variants.append((s, baseArpa + pluralSuffix(baseArpa)))
        }

        let es = word + "es"
        if existing[es] == nil {
            variants.append((es, baseArpa + esSuffix(baseArpa)))
        }

        let ed = word + "ed"
        if existing[ed] == nil {
            variants.append((ed, baseArpa + pastSuffix(baseArpa)))
        }

        return variants
    }

    private static func pluralSuffix(_ base: [String]) -> [String] {
        guard let last = base.last else { return ["Z"] }
        let s = last.filter { !$0.isNumber }
        if sibilantArpa.contains(s) { return ["IH0", "Z"] }
        if voicelessArpa.contains(s) { return ["S"] }
        return ["Z"]
    }

    private static func esSuffix(_ base: [String]) -> [String] {
        guard let last = base.last else { return ["IH0", "Z"] }
        let s = last.filter { !$0.isNumber }
        if sibilantArpa.contains(s) { return ["IH0", "Z"] }
        return ["Z"]
    }

    private static func pastSuffix(_ base: [String]) -> [String] {
        guard let last = base.last else { return ["D"] }
        let s = last.filter { !$0.isNumber }
        if s == "T" || s == "D" { return ["IH0", "D"] }
        if voicelessArpa.contains(s) { return ["T"] }
        return ["D"]
    }

    // MARK: - ARPAbet → Binary Entry

    private static func convertToBinaryEntry(word: String, arpa: [String]) -> BinaryFormat.Entry? {
        let notes = arpaToNotes(arpa)
        guard !notes.isEmpty else { return nil }

        let textChunks = distributeText(word, notes: notes)

        var phonemes: [BinaryFormat.PhonemeRecord] = []
        for (i, note) in notes.enumerated() {
            guard let cCC = consonantCCValues[note.consonant],
                  let vCC = vowelCCValues[note.vowel]
            else { continue }
            let text = i < textChunks.count ? textChunks[i] : ""
            phonemes.append(BinaryFormat.PhonemeRecord(
                consonantCC: cCC, vowelCC: vCC,
                weight: UInt8(note.weight), text: text
            ))
        }

        guard !phonemes.isEmpty else { return nil }
        return BinaryFormat.Entry(word: word, phonemes: phonemes)
    }

    // MARK: - arpaToChoir (copied from PhonemeDictionary.swift)

    private static func arpaToNotes(_ arpa: [String]) -> [(consonant: String, vowel: String, weight: Int)] {
        struct Sound {
            let isVowel: Bool
            let stress: Int
            let ourID: String
        }

        var sounds: [Sound] = []
        for ph in arpa {
            let stripped: String
            let stress: Int
            if let last = ph.last, last.isNumber {
                stripped = String(ph.dropLast())
                stress = Int(String(last)) ?? 0
            } else {
                stripped = ph
                stress = -1
            }

            if let vowelID = vowelMap[stripped] {
                let finalID = (stripped == "AH" && stress > 0) ? "uh" : vowelID
                sounds.append(Sound(isVowel: true, stress: stress, ourID: finalID))
            } else if let consID = consonantMap[stripped] {
                sounds.append(Sound(isVowel: false, stress: -1, ourID: consID))
            }
        }

        var notes: [(consonant: String, vowel: String, weight: Int)] = []
        var pendingConsonants: [String] = []

        for sound in sounds {
            if sound.isVowel {
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

                let weight = stressToWeight(sound.stress)
                notes.append((consonant: onset, vowel: sound.ourID, weight: weight))
                pendingConsonants.removeAll()
            } else {
                pendingConsonants.append(sound.ourID)
            }
        }

        emitCoda(pendingConsonants, into: &notes)
        return notes
    }

    private static func emitCoda(_ consonants: [String], into notes: inout [(consonant: String, vowel: String, weight: Int)]) {
        for cons in consonants {
            if nasals.contains(cons) {
                notes.append((consonant: cons, vowel: "mmm", weight: 1))
            } else if fricatives.contains(cons) {
                notes.append((consonant: cons, vowel: "none", weight: 1))
            } else if plosives.contains(cons) {
                notes.append((consonant: cons, vowel: "schwa", weight: 1))
            }
        }
    }

    private static func stressToWeight(_ stress: Int) -> Int {
        switch stress {
        case 1: return 3
        case 2: return 2
        default: return 1
        }
    }

    // MARK: - distributeText (copied from PhonemeDictionary.swift)

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

            // Step 1: consonant onset letter matching
            if hasConsonant {
                let spellings = consonantSpellings[note.consonant] ?? []
                var found = false
                for scanPos in cursor..<chars.count {
                    for sp in spellings {
                        let end = scanPos + sp.count
                        if end <= chars.count && Array(chars[scanPos..<end]) == sp {
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
                    if cursor < chars.count { cursor += 1 }
                }
            }

            // Step 2: vowel letter eating
            if needsVowel && cursor < chars.count {
                if !hasConsonant {
                    chunkStart = cursor
                }
                var foundVowel = false
                while cursor < chars.count {
                    if vowelLetters.contains(chars[cursor]) {
                        cursor += 1
                        foundVowel = true
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

        // Second pass: backtrack non-matching coda consonants
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
