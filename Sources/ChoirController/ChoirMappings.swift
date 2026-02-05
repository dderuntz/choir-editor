import Foundation

/// MIDI CC mappings for Teenage Engineering Choir dolls.
/// Sourced from: https://github.com/jetztgradnet/Choirama
/// License: CC0-1.0 (Public Domain)

enum ChoirCC {
    static let vibrato: UInt8 = 1
    static let consonant: UInt8 = 2
    static let vowel: UInt8 = 3
    static let reverb: UInt8 = 4
}

/// Default values (to be tuned through testing)
enum ChoirDefaults {
    static let vibrato: UInt8 = 64      // Mid-range, adjust after testing
    static let reverb: UInt8 = 32       // Light reverb, adjust after testing
    static let consonant: UInt8 = 0     // Random - varies naturally
    static let vowel: UInt8 = 0         // Random - varies naturally
}

// MARK: - Consonant Mappings (CC2)

struct Consonant: Identifiable, Hashable {
    let id: String
    let name: String
    let example: String
    let ccValue: UInt8
    
    static let all: [Consonant] = [
        Consonant(id: "random", name: "Random", example: "", ccValue: 0),
        Consonant(id: "b", name: "B", example: "Bat", ccValue: 4),
        Consonant(id: "bj", name: "Bj", example: "Bjorn", ccValue: 7),
        Consonant(id: "bl", name: "Bl", example: "Black", ccValue: 10),
        Consonant(id: "br", name: "Br", example: "Bread", ccValue: 14),
        Consonant(id: "tsh", name: "Tsh", example: "Tshe", ccValue: 17),
        Consonant(id: "d", name: "D", example: "Dog", ccValue: 20),
        Consonant(id: "dr", name: "Dr", example: "Dream", ccValue: 23),
        Consonant(id: "f", name: "F", example: "Fox", ccValue: 27),
        Consonant(id: "fj", name: "Fj", example: "Fjord", ccValue: 30),
        Consonant(id: "fl", name: "Fl", example: "Flower", ccValue: 33),
        Consonant(id: "fr", name: "Fr", example: "Frog", ccValue: 37),
        Consonant(id: "g", name: "G", example: "Game", ccValue: 40),
        Consonant(id: "gl", name: "Gl", example: "Glue", ccValue: 43),
        Consonant(id: "gr", name: "Gr", example: "Grape", ccValue: 46),
        Consonant(id: "h", name: "H", example: "Hat", ccValue: 50),
        Consonant(id: "dj", name: "Dj", example: "Djembe", ccValue: 53),
        Consonant(id: "k", name: "K", example: "Kangaroo", ccValue: 56),
        Consonant(id: "kl", name: "Kl", example: "Klang", ccValue: 60),
        Consonant(id: "kr", name: "Kr", example: "Kraken", ccValue: 63),
        Consonant(id: "l", name: "L", example: "Lion", ccValue: 66),
        Consonant(id: "m", name: "M", example: "Moon", ccValue: 69),
        Consonant(id: "n", name: "N", example: "Night", ccValue: 73),
        Consonant(id: "nj", name: "Nj", example: "Njord", ccValue: 76),
        Consonant(id: "p", name: "P", example: "Panda", ccValue: 79),
        Consonant(id: "pl", name: "Pl", example: "Plate", ccValue: 83),
        Consonant(id: "pr", name: "Pr", example: "Prize", ccValue: 86),
        Consonant(id: "r", name: "R", example: "Rabbit", ccValue: 89),
        Consonant(id: "s", name: "S", example: "Snake", ccValue: 92),
        Consonant(id: "sl", name: "Sl", example: "Sled", ccValue: 96),
        Consonant(id: "sh", name: "Sh", example: "Sheep", ccValue: 99),
        Consonant(id: "t", name: "T", example: "Tree", ccValue: 102),
        Consonant(id: "tr", name: "Tr", example: "Train", ccValue: 106),
        Consonant(id: "th", name: "Th", example: "Thing", ccValue: 109),
        Consonant(id: "thr", name: "Thr", example: "Throw", ccValue: 112),
        Consonant(id: "v", name: "V", example: "Vase", ccValue: 115),
        Consonant(id: "w", name: "W", example: "Water", ccValue: 119),
        Consonant(id: "y", name: "Y", example: "Yarn", ccValue: 122),
        Consonant(id: "none", name: "None", example: "", ccValue: 125),
    ]
}

// MARK: - Vowel Mappings (CC3)

struct Vowel: Identifiable, Hashable {
    let id: String
    let symbol: String      // IPA symbol
    let example: String     // Example word with emphasis
    let ccValue: UInt8
    
    static let all: [Vowel] = [
        Vowel(id: "random", symbol: "?", example: "Random", ccValue: 0),
        Vowel(id: "aa", symbol: "ɑː", example: "stAr", ccValue: 8),
        Vowel(id: "ai", symbol: "aɪ", example: "bUY", ccValue: 16),
        Vowel(id: "ae", symbol: "æ", example: "pAt", ccValue: 23),
        Vowel(id: "schwa", symbol: "ə", example: "thE", ccValue: 31),
        Vowel(id: "aw", symbol: "ɔː", example: "stOre", ccValue: 38),
        Vowel(id: "oi", symbol: "ɔɪ", example: "cOY", ccValue: 46),
        Vowel(id: "o", symbol: "ɒ", example: "pOt", ccValue: 53),
        Vowel(id: "uh", symbol: "ʌ", example: "cUt", ccValue: 61),
        Vowel(id: "oo", symbol: "uː", example: "zOO", ccValue: 68),
        Vowel(id: "ee", symbol: "iː", example: "frEE", ccValue: 76),
        Vowel(id: "ear", symbol: "ɪə", example: "hEAr", ccValue: 83),
        Vowel(id: "ay", symbol: "eɪ", example: "strAY", ccValue: 91),
        Vowel(id: "air", symbol: "ɛə", example: "stAIr", ccValue: 98),
        Vowel(id: "ure", symbol: "ʊə", example: "cUre", ccValue: 106),
        Vowel(id: "mmm", symbol: "m", example: "mmm (nasal)", ccValue: 113),
        Vowel(id: "none", symbol: "–", example: "None", ccValue: 121),
    ]
}
