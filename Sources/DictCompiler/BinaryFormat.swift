import Foundation

/// Binary .choirdict format writer and reader.
///
/// Format (all integers little-endian):
/// ```
/// Header (16 bytes):
///   [4B] magic: "CHOR" (0x43484F52)
///   [1B] version: 1
///   [1B] language: 0=English, 1=Swedish
///   [2B] reserved
///   [4B] entryCount (UInt32)
///   [4B] reserved
///
/// Entries (sequential, sorted by word):
///   [1B] wordLen
///   [NB] word (UTF-8)
///   [1B] phonemeCount
///   Per phoneme:
///     [1B] consonantCC
///     [1B] vowelCC
///     [1B] weight
///     [1B] textLen
///     [NB] text (UTF-8)
/// ```
enum BinaryFormat {

    static let magic: UInt32 = 0x43484F52  // "CHOR" in ASCII

    enum Language: UInt8 {
        case english = 0
        case swedish = 1
    }

    struct PhonemeRecord {
        let consonantCC: UInt8
        let vowelCC: UInt8
        let weight: UInt8
        let text: String
    }

    struct Entry {
        let word: String
        let phonemes: [PhonemeRecord]
    }

    /// Write sorted entries to a .choirdict binary file.
    static func write(entries: [Entry], language: Language, to url: URL) throws {
        // Sort by word for consistent output
        let sorted = entries.sorted { $0.word < $1.word }

        var data = Data()
        data.reserveCapacity(sorted.count * 30)  // rough estimate

        // Header (16 bytes)
        appendUInt32(&data, magic)
        data.append(1)  // version
        data.append(language.rawValue)
        data.append(contentsOf: [0, 0])  // reserved
        appendUInt32(&data, UInt32(sorted.count))
        data.append(contentsOf: [0, 0, 0, 0])  // reserved

        // Entries
        for entry in sorted {
            let wordBytes = Array(entry.word.utf8)
            precondition(wordBytes.count <= 255, "Word too long: \(entry.word)")
            data.append(UInt8(wordBytes.count))
            data.append(contentsOf: wordBytes)

            precondition(entry.phonemes.count <= 255, "Too many phonemes for: \(entry.word)")
            data.append(UInt8(entry.phonemes.count))

            for phoneme in entry.phonemes {
                data.append(phoneme.consonantCC)
                data.append(phoneme.vowelCC)
                data.append(phoneme.weight)
                let textBytes = Array(phoneme.text.utf8)
                precondition(textBytes.count <= 255, "Phoneme text too long: \(phoneme.text)")
                data.append(UInt8(textBytes.count))
                data.append(contentsOf: textBytes)
            }
        }

        // Gzip compress before writing
        let compressed = try (data as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: url)

        let ratio = Double(compressed.count) / Double(data.count) * 100
        print("[BinaryFormat] \(data.count) bytes → \(compressed.count) bytes (\(String(format: "%.1f", ratio))% of original)")
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
    }
}
