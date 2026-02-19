import Foundation

/// Reads pre-compiled .choirdict binary files into a Swift dictionary.
///
/// Binary format (all integers little-endian):
/// ```
/// Header (16 bytes):
///   [4B] magic "CHOR", [1B] version, [1B] language, [2B] reserved,
///   [4B] entryCount, [4B] reserved
/// Entries (sequential):
///   [1B] wordLen, [NB] word, [1B] phonemeCount,
///   per phoneme: [1B] consonantCC, [1B] vowelCC, [1B] weight, [1B] textLen, [NB] text
/// ```
enum BinaryPhonemeDictionary {

    /// Load a .choirdict binary resource into a dictionary.
    static func load(resource: String, extension ext: String = "choirdict") -> [String: [ChoirPhoneme]] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            print("[BinaryPhonemeDict] Could not find \(resource).\(ext) in bundle")
            return [:]
        }
        return load(url: url)
    }

    /// Load a .choirdict binary file from a URL (zlib-compressed).
    static func load(url: URL) -> [String: [ChoirPhoneme]] {
        let start = CFAbsoluteTimeGetCurrent()
        let name = url.lastPathComponent

        guard let compressed = try? Data(contentsOf: url) else {
            print("[BinaryPhonemeDict] ⚠ Could not read \(name)")
            return [:]
        }

        let readTime = CFAbsoluteTimeGetCurrent()

        guard let data = try? (compressed as NSData).decompressed(using: .zlib) as Data else {
            print("[BinaryPhonemeDict] ⚠ Could not decompress \(name)")
            return [:]
        }

        let decompressTime = CFAbsoluteTimeGetCurrent()
        let dict = parse(data)
        let parseTime = CFAbsoluteTimeGetCurrent()

        let totalMs = (parseTime - start) * 1000
        let readMs = (readTime - start) * 1000
        let zlibMs = (decompressTime - readTime) * 1000
        let parseMs = (parseTime - decompressTime) * 1000

        print("[BinaryPhonemeDict] \(name): \(dict.count) words in \(String(format: "%.0f", totalMs))ms " +
              "(read \(String(format: "%.0f", readMs))ms, decompress \(String(format: "%.0f", zlibMs))ms, parse \(String(format: "%.0f", parseMs))ms)")

        return dict
    }

    private static func parse(_ data: Data) -> [String: [ChoirPhoneme]] {
        guard data.count >= 16 else {
            print("[BinaryPhonemeDict] File too small")
            return [:]
        }

        var offset = 0

        // Header
        let magic = readUInt32(data, at: &offset)
        guard magic == 0x43484F52 else {
            print("[BinaryPhonemeDict] Bad magic: \(String(magic, radix: 16))")
            return [:]
        }

        let version = data[offset]; offset += 1
        guard version == 1 else {
            print("[BinaryPhonemeDict] Unsupported version: \(version)")
            return [:]
        }

        offset += 3  // language + 2 reserved

        let entryCount = readUInt32(data, at: &offset)
        offset += 4  // reserved

        // Pre-allocate dictionary
        var dict = [String: [ChoirPhoneme]](minimumCapacity: Int(entryCount))

        // Read entries
        for _ in 0..<entryCount {
            guard offset < data.count else { break }

            // Word
            let wordLen = Int(data[offset]); offset += 1
            guard offset + wordLen <= data.count else { break }
            let word = String(decoding: data[offset..<offset+wordLen], as: UTF8.self)
            offset += wordLen

            // Phonemes
            guard offset < data.count else { break }
            let phonemeCount = Int(data[offset]); offset += 1

            var phonemes: [ChoirPhoneme] = []
            phonemes.reserveCapacity(phonemeCount)

            for _ in 0..<phonemeCount {
                guard offset + 4 <= data.count else { break }
                let consonantCC = data[offset]; offset += 1
                let vowelCC = data[offset]; offset += 1
                let weight = data[offset]; offset += 1
                let textLen = Int(data[offset]); offset += 1

                guard offset + textLen <= data.count else { break }
                let text = String(decoding: data[offset..<offset+textLen], as: UTF8.self)
                offset += textLen

                phonemes.append(ChoirPhoneme(
                    text: text,
                    consonantCC: consonantCC,
                    vowelCC: vowelCC,
                    weight: Int(weight)
                ))
            }

            if !phonemes.isEmpty {
                dict[word] = phonemes
            }
        }

        return dict
    }

    private static func readUInt32(_ data: Data, at offset: inout Int) -> UInt32 {
        guard offset + 4 <= data.count else { offset += 4; return 0 }
        let value = data[offset..<offset+4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        offset += 4
        return UInt32(littleEndian: value)
    }
}
