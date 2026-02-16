import Foundation
import FoundationModels
import Playgrounds

// Xcode Playground for rapid prompt iteration.
// Open Canvas: Editor → Canvas (Opt+Cmd+Return)
// Tabs at top of Canvas switch between playground blocks.

// MARK: - Types

@Generable
struct PlaygroundLyric {
    @Guide(description: "A short lyric for singing. 2 lines separated by /. Each line 3-8 simple words.")
    let lyric: String
}

// Pass 1: Syllable breaking (no stress)
@Generable
struct PlaygroundNote {
    @Guide(description: "Consonant sound at the start of this sung note",
           .anyOf(["none", "b", "bj", "bl", "br", "tsh", "d", "dr",
                   "f", "fj", "fl", "fr", "g", "gl", "gr", "h", "dj",
                   "k", "kl", "kr", "l", "m", "n", "nj", "p", "pl",
                   "pr", "r", "s", "sl", "sh", "t", "tr", "th", "thr",
                   "v", "w", "y"]))
    let consonant: String

    @Guide(description: "Vowel sound to sustain",
           .anyOf(["aa", "ai", "ae", "schwa", "aw", "oi", "o",
                   "uh", "oo", "ee", "ear", "ay", "air", "ure",
                   "mmm", "none"]))
    let vowel: String

    @Guide(description: "Original letters from the word for this note (e.g. 'far', 'mer', 'the')")
    let text: String
}

@Generable
struct PlaygroundNoteResult {
    @Guide(description: "Singing notes in order, one per syllable")
    let syllables: [PlaygroundNote]
}

// Pass 2: Stress assignment
@Generable
struct PlaygroundStressEntry {
    @Guide(description: "The syllable text exactly as given")
    let text: String

    @Guide(description: "Singing stress: 3 = LOUD syllable, 2 = medium, 1 = weak",
           .range(1...3))
    let weight: Int
}

@Generable
struct PlaygroundStressResult {
    @Guide(description: "Stress assignments for each syllable")
    let syllables: [PlaygroundStressEntry]
}

/*
// MARK: - Senryū Lyrics
#Playground("Senryū") { ... }

// MARK: - Bellman Lyrics
#Playground("Bellman") { ... }

// MARK: - Kulning för Robotar
#Playground("Kulning") { ... }

// MARK: - Dada Lyrics
#Playground("Dada") { ... }

// MARK: - Nursery Rhyme Lyrics
#Playground("Nursery") { ... }

— Lyric playgrounds commented out for speed. Uncomment to test. —
*/

// MARK: - Dictionary Lookup

#Playground("Dict") {
    let words = ["cat", "mountain", "the", "singing", "beloved", "dells", "walked", "dancing"]
    for w in words {
        if let phonemes = PhonemeDictionary.lookup(w) {
            let desc = phonemes.map { "\($0.text):\($0.consonantName)+\($0.vowelSymbol) w\($0.weight)" }.joined(separator: ", ")
            print("\(w): \(desc)")
        } else {
            print("\(w): ⚠ not found")
        }
    }
}

// MARK: - Normalize Messy Text

@Generable
struct PlaygroundWordList {
    @Guide(description: "Clean list of correctly-spelled English words extracted from the input. Fix typos, split run-on words. Keep original word order.")
    let words: [String]
}

#Playground("Normalize") {
    let session = LanguageModelSession(instructions: Instructions("""
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
    """))

    let messy = [
        "teh moontain sings",
        "farmr in duh dell",
        "singwithme tonight",
        "therobots aredancing intherain"
    ]
    for input in messy {
        let r = try await session.respond(to: input, generating: PlaygroundWordList.self)
        let words = r.content.words
        let dictResult = PhonemeDictionary.lookupSentence(words.joined(separator: " "))
        let status = dictResult.missing.isEmpty ? "✓ all found" : "⚠ missing: \(dictResult.missing)"
        print("\"\(input)\" → \(words) → \(status)")
    }
}

// MARK: - LLM Fallback (for words not in dictionary)

@Generable
struct PhonemeString {
    @Guide(description: "IPA pronunciation of the word, e.g. /ˈfɑːr.mər/")
    let phonemes: String
}

#Playground("LLM Fallback") {
    let session = LanguageModelSession(instructions: Instructions("""
    You are an expert linguist. Write the accurate IPA pronunciation of each word. Use ONLY these IPA symbols:

    Consonants: b d f g h k l m n p r s t v w j ʃ θ ð tʃ dʒ ŋ
    Vowels: ɑː (fAther) æ (cAt) iː (frEE) eɪ (strAY) uː (zOO) ʌ (cUt) ɔː (stOre) aɪ (bUY) ɒ (pOt) ɔɪ (bOY) ə (commA) ɛə (stAIr) ɪə (hEAr) ʊə (cURe) aʊ (cOW) ɪ (sIt)

    EXAMPLES:
    "farmer" → /ˈfɑːr.mər/
    "water" → /ˈwɔː.tər/
    "happy" → /ˈhæp.iː/
    "love" → /lʌv/
    "thunder" → /ˈθʌn.dər/
    """))

    let words = ["cat", "mountain", "singing", "beloved", "robotar"]
    for w in words {
        let dictResult = PhonemeDictionary.lookup(w)
        if let found = dictResult {
            print("\(w) [DICT]: \(found.map { "\($0.text):\($0.consonantName)+\($0.vowelSymbol)" }.joined(separator: ", "))")
        } else {
            let r = try await session.respond(
                to: "Rewrite using IPA symbols: \(w)",
                generating: PhonemeString.self
            )
            print("\(w) [LLM]: \(r.content.phonemes)")
        }
    }
}
