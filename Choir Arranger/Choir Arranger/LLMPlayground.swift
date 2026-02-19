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

// MARK: - EN Senryū (production prompt)

#Playground("EN Senryū") {
    let session = LanguageModelSession(instructions: Instructions("""
    You are a weary, tired robot writing short lyrics for a recital.
    You observe human life with dry wit and quiet humor.
    DO NOT be inspirational or uplifting. DO NOT include introductions or titles.
    Output ONLY the lyric lines. Simple words. Each line 3-8 words.

    EXAMPLES:
    "coffee" → the cup knows more than I do / it has seen me before dawn
    "deadlines" → the clock does not negotiate / it simply wins
    "my cat" → your cat composes better / than most of us ever will
    "Monday" → we meet again old friend / neither of us wanted this

    DO NOT repeat the examples. Write something new and original.
    """))

    let prompts = ["morning", "rain", "robots", "singing", "the moon"]
    for prompt in prompts {
        let r = try await session.respond(
            to: "Write a short singable lyric about: \(prompt)",
            generating: PlaygroundLyric.self
        )
        print("[\(prompt)] → \(r.content.lyric)")
    }
}

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

    let words = ["cat", "mountain", "singing", "beloved", "thunder", "water", "dancing", "zeppelina"]
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

// ═══════════════════════════════════════════════════════════════════
// MARK: - 🇸🇪 Swedish Language Tests
// ═══════════════════════════════════════════════════════════════════

// MARK: - Swedish Lyric Generation

@Generable
struct SwedishLyric {
    @Guide(description: "A short Swedish lyric for singing. 2 lines separated by /. Each line 3-8 simple Swedish words. Write in Swedish only.")
    let lyric: String
}

#Playground("SV Lyrics") {
    let session = LanguageModelSession(instructions: Instructions("""
    Du är en trött robot. Du skriver senryū på svenska för en konsert ingen kommer till.

    Senryū är en japansk form: två rader. Rad 1 observerar något vanligt. Rad 2 vänder på det.
    Humorn sitter i vändningen. Inte skämt. Inte sorg. Bara glappet mellan vad saker är och vad vi låtsas.

    Två rader separerade med /. Varje rad 3-8 enkla svenska ord.
    Inga inledningar. Inga titlar. Inget hopp. Bara texten.

    "kaffe" → koppen vet mer än jag / den har sett mig före gryningen
    "deadlines" → klockan förhandlar inte / den bara vinner
    "min katt" → din katt komponerar bättre / än de flesta av oss
    "måndag" → vi möts igen gamla vän / ingen av oss ville detta
    "semester" → vi packade väskorna med hopp / de kom hem tomma
    "wifi" → signalen lovar allt / men levererar ingenting
    "vår" → blommorna öppnar sig igen / som om förra gången räckte
    "möte" → alla nickar och ler / ingen minns varför

    Andra raden MÅSTE vända. Den måste överraska, underminera, eller tyst håna den första.
    Skriv något nytt. Eller inte. Det spelar knappt någon roll.
    """))

    let prompts = ["morgon", "kärlek", "snö", "robotar i skogen", "midnatt"]
    for prompt in prompts {
        let r = try await session.respond(
            to: "Skriv en kort svensk text om: \(prompt)",
            generating: SwedishLyric.self
        )
        print("[\(prompt)] → \(r.content.lyric)")
    }
}

// MARK: - Swedish Text Normalization

@Generable
struct SwedishWordList {
    @Guide(description: "Clean list of correctly-spelled Swedish words extracted from the input. Fix typos, split run-on words. Keep original word order.")
    let words: [String]
}

#Playground("SV Normalize") {
    let session = LanguageModelSession(instructions: Instructions("""
    You are a Swedish text normalizer. Your ONLY job: turn messy Swedish input into a clean word list.

    Rules:
    1. SPLIT run-on words into separate words. "jagälskar" → "jag", "älskar"
    2. FIX typos to the most likely intended Swedish word. "huden" → "hunden", "snöe" → "snö"
    3. KEEP original word order. Do NOT add extra words.
    4. Every output word must be a real Swedish word, correctly spelled.

    "jagälskar dig" → ["jag", "älskar", "dig"]
    "huden springer iparken" → ["hunden", "springer", "i", "parken"]
    "dett är en vackerr dag" → ["det", "är", "en", "vacker", "dag"]
    "solenskiner överbergen" → ["solen", "skiner", "över", "bergen"]
    """))

    let messy = [
        "huden springer iparken",
        "dett är en vackerr dag",
        "jagälskar musik",
        "robotensjunger inatten"
    ]
    for input in messy {
        let r = try await session.respond(to: input, generating: SwedishWordList.self)
        print("\"\(input)\" → \(r.content.words)")
    }
}

// MARK: - Swedish Dictionary Test (real SwedishPhonemeDictionary)

#Playground("SV Dictionary") {
    // Test real dictionary lookups — 5 known words + 1 unknown
    let words = ["katt", "vatten", "sjunga", "musik", "kärlek", "zeppelansen"]

    for w in words {
        if let phonemes = SwedishPhonemeDictionary.lookup(w) {
            let desc = phonemes.map { "\($0.text):\($0.consonantName)+\($0.vowelSymbol) w\($0.weight)" }.joined(separator: ", ")
            print("\(w) [DICT]: \(desc)")
        } else {
            print("\(w) [MISS]: not in dictionary — would be skipped")
        }
    }

    // Test a full sentence
    print("\n--- Sentence test ---")
    let sentence = "katten sover på soffan"
    let result = SwedishPhonemeDictionary.lookupSentence(sentence)
    print("Found \(result.found.count) phonemes, missing \(result.missing.count) words")
    for p in result.found {
        print("  [\(p.wordIndex)] \(p.text): \(p.consonantName)+\(p.vowelSymbol) w\(p.weight)")
    }
    if !result.missing.isEmpty {
        print("  Missing: \(result.missing)")
    }
}

