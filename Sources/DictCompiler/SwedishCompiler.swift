import Foundation

/// Compiles swe_lexicon.txt → sv.choirdict binary.
/// Contains all Swedish mapping/conversion logic (copied from SwedishPhonemeDictionary.swift).
enum SwedishCompiler {

    // MARK: - Swedish SAMPA → Choir IDs (same as SwedishPhonemeDictionary.swift)

    private static let vowelMap: [String: String] = [
        // Short vowels
        "a":   "aa",
        "E":   "ae",
        "I":   "ee",
        "O":   "aw",
        "u0":  "uh",
        "U":   "oo",
        "Y":   "ee",
        "9":   "ae",
        // Long vowels
        "A:":  "aa",
        "e:":  "ay",
        "E:":  "air",
        "i:":  "ee",
        "o:":  "oo",
        "u:":  "oo",
        "y:":  "ee",
        "2:":  "ay",
        "}:":  "oo",
        // Diphthongs
        "a*U": "aa",
        "E*U": "ae",
        // Schwa
        "e":   "schwa",
    ]

    private static let consonantMap: [String: String] = [
        "b":   "b",
        "d":   "d",
        "f":   "f",
        "g":   "g",
        "h":   "h",
        "j":   "y",
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
        "N":   "n",
        "S":   "sh",
        "s'":  "sh",
        // Retroflexes
        "d`":  "d",
        "t`":  "t",
        "n`":  "n",
        "l`":  "l",
        "s`":  "s",
    ]

    private static let validOnsets: Set<String> = [
        "bl", "br", "dr", "fl", "fr", "gl", "gr", "kl", "kr",
        "pl", "pr", "sl", "tr", "thr",
        "sk", "sp", "st", "sv", "sn", "sm",
        "skr", "spr", "str",
        "bj", "fj", "nj",
    ]

    private static let fricatives: Set<String> = ["s", "sh", "f", "v", "h"]
    private static let plosives: Set<String> = ["b", "d", "g", "k", "p", "t"]
    private static let nasals: Set<String> = ["m", "n"]

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

    private static let vowelLetters: Set<Character> = ["a", "e", "i", "o", "u", "y", "å", "ä", "ö"]
    private static let syntheticVowels: Set<String> = ["none", "schwa", "mmm"]

    /// How each consonant ID could be spelled in Swedish (longest first for greedy match)
    private static let consonantSpellings: [String: [[Character]]] = [
        "s":   [["s", "s"], ["s"]],
        "k":   [["c", "k"], ["k", "k"], ["k"], ["c"]],
        "t":   [["t", "t"], ["t"]],
        "d":   [["d", "d"], ["d"]],
        "n":   [["n", "g"], ["n", "n"], ["n"]],   // ng → velar nasal maps to "n"
        "m":   [["m", "m"], ["m"]],
        "l":   [["l", "l"], ["l"]],
        "r":   [["r", "r"], ["r"]],
        "b":   [["b", "b"], ["b"]],
        "p":   [["p", "p"], ["p"]],
        "f":   [["f", "f"], ["f"]],
        "g":   [["g", "g"], ["g"]],
        "v":   [["v"]],
        "h":   [["h"]],
        "y":   [["j"]],               // Swedish j → our "y"
        "sh":  [["s", "k", "j"], ["s", "t", "j"], ["s", "j"], ["s", "c", "h"], ["s", "k"], ["c", "h"]],
    ]

    // MARK: - Compile

    /// Read swe_lexicon.txt and produce binary entries.
    static func compile(lexiconURL: URL) throws -> [BinaryFormat.Entry] {
        let contents = try String(contentsOf: lexiconURL, encoding: .utf8)

        var entries = [String: BinaryFormat.Entry]()

        for line in contents.split(separator: "\n") {
            let str = String(line)
            guard !str.hasPrefix("!") && !str.hasPrefix("<") else { continue }

            let parts = str.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }

            var word = String(parts[0]).lowercased()
            if word.hasPrefix("-") { word = String(word.dropFirst()) }
            guard word.count >= 2 else { continue }
            guard entries[word] == nil else { continue }

            let (phonemes, stresses) = parseSAMPA(String(parts[1]))

            if let entry = convertToBinaryEntry(word: word, phonemes: phonemes, stresses: stresses) {
                entries[word] = entry
            }
        }

        print("[SwedishCompiler] Total entries: \(entries.count)")
        return Array(entries.values)
    }

    // MARK: - SAMPA Parsing (copied from SwedishPhonemeDictionary.swift)

    private static func parseSAMPA(_ raw: String) -> (phonemes: [String], stresses: [Int]) {
        let tokens = raw.split(separator: " ").map { String($0) }
        var phonemes: [String] = []
        var stresses: [Int] = []
        var pendingStress = 1

        for token in tokens {
            var t = token

            if t.hasPrefix("\"") {
                pendingStress = 3
                t = String(t.dropFirst())
            } else if t.hasPrefix("%") {
                pendingStress = 2
                t = String(t.dropFirst())
            }

            guard !t.isEmpty else { continue }

            let isVowel = vowelMap[t] != nil
            phonemes.append(t)
            stresses.append(isVowel ? pendingStress : -1)

            if isVowel {
                pendingStress = 1
            }
        }

        return (phonemes, stresses)
    }

    // MARK: - SAMPA → Binary Entry

    private static func convertToBinaryEntry(word: String, phonemes: [String], stresses: [Int]) -> BinaryFormat.Entry? {
        let notes = sampaToNotes(phonemes, stresses: stresses)
        guard !notes.isEmpty else { return nil }

        let textChunks = distributeText(word, notes: notes)

        var records: [BinaryFormat.PhonemeRecord] = []
        for (i, note) in notes.enumerated() {
            guard let cCC = consonantCCValues[note.consonant],
                  let vCC = vowelCCValues[note.vowel]
            else { continue }
            let text = i < textChunks.count ? textChunks[i] : ""
            records.append(BinaryFormat.PhonemeRecord(
                consonantCC: cCC, vowelCC: vCC,
                weight: UInt8(note.weight), text: text
            ))
        }

        guard !records.isEmpty else { return nil }
        return BinaryFormat.Entry(word: word, phonemes: records)
    }

    // MARK: - sampaToChoir (copied from SwedishPhonemeDictionary.swift)

    private static func sampaToNotes(_ phonemes: [String], stresses: [Int]) -> [(consonant: String, vowel: String, weight: Int)] {
        struct Sound {
            let isVowel: Bool
            let stress: Int
            let choirID: String
        }

        var sounds: [Sound] = []
        for (i, ph) in phonemes.enumerated() {
            let stress = stresses[i]
            if let vowelID = vowelMap[ph] {
                sounds.append(Sound(isVowel: true, stress: stress, choirID: vowelID))
            } else if let consID = consonantMap[ph] {
                sounds.append(Sound(isVowel: false, stress: -1, choirID: consID))
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

                notes.append((consonant: onset, vowel: sound.choirID, weight: sound.stress))
                pendingConsonants.removeAll()
            } else {
                pendingConsonants.append(sound.choirID)
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

    // MARK: - distributeText (consonant-spelling-aware, adapted from English)

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
                    chunkStart = cursor
                }
                var foundVowel = false
                while cursor < chars.count {
                    if vowelLetters.contains(chars[cursor]) {
                        cursor += 1
                        foundVowel = true
                        // Eat trailing vowel digraphs
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
