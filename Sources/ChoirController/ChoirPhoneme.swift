import Foundation

// MARK: - Phoneme Data

struct ChoirPhoneme: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String       // original syllable text
    let consonantCC: UInt8 // CC2 value
    let vowelCC: UInt8     // CC3 value
    let weight: Int        // stress: 3=primary, 2=secondary, 1=unstressed
    var wordIndex: Int = 0 // which word this chip belongs to (for visual grouping)
    var isEnsemble: Bool = false  // choral harmony on this syllable

    var consonantName: String {
        Consonant.all.first(where: { $0.ccValue == consonantCC })?.name ?? "?"
    }
    var vowelSymbol: String {
        Vowel.all.first(where: { $0.ccValue == vowelCC })?.symbol ?? "?"
    }
}
