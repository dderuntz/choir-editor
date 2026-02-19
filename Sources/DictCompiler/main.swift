import Foundation

/// DictCompiler — Pre-compiles text phoneme lexicons into binary .choirdict format.
///
/// Usage: swift run DictCompiler
///
/// Reads:
///   Sources/ChoirController/cmudict.txt       (English, CMU ARPAbet)
///   Sources/ChoirController/swe_lexicon.txt    (Swedish, SAMPA)
///
/// Writes:
///   Sources/ChoirController/en.choirdict       (English binary)
///   Sources/ChoirController/sv.choirdict       (Swedish binary)

let projectRoot: URL = {
    // Walk up from the executable to find Package.swift
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // DictCompiler/
        .deletingLastPathComponent()  // Sources/
        .deletingLastPathComponent()  // project root
    // Verify we found the right place
    if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
        return dir
    }
    // Fallback: current working directory
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()

let choirControllerDir = projectRoot.appendingPathComponent("Sources/ChoirController")

func formatBytes(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
    return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
}

// MARK: - Compile English

print("=== DictCompiler ===\n")

do {
    let cmudictURL = choirControllerDir.appendingPathComponent("cmudict.txt")
    guard FileManager.default.fileExists(atPath: cmudictURL.path) else {
        print("ERROR: cmudict.txt not found at \(cmudictURL.path)")
        exit(1)
    }

    print("Compiling English dictionary...")
    let entries = try EnglishCompiler.compile(cmudictURL: cmudictURL)

    let outputURL = choirControllerDir.appendingPathComponent("en.choirdict")
    try BinaryFormat.write(entries: entries, language: .english, to: outputURL)

    let fileSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int ?? 0
    print("Wrote \(outputURL.lastPathComponent): \(entries.count) entries, \(formatBytes(fileSize))\n")
} catch {
    print("ERROR compiling English: \(error)")
    exit(1)
}

// MARK: - Compile Swedish

do {
    let lexiconURL = choirControllerDir.appendingPathComponent("swe_lexicon.txt")
    guard FileManager.default.fileExists(atPath: lexiconURL.path) else {
        print("ERROR: swe_lexicon.txt not found at \(lexiconURL.path)")
        exit(1)
    }

    print("Compiling Swedish dictionary...")
    let entries = try SwedishCompiler.compile(lexiconURL: lexiconURL)

    let outputURL = choirControllerDir.appendingPathComponent("sv.choirdict")
    try BinaryFormat.write(entries: entries, language: .swedish, to: outputURL)

    let fileSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int ?? 0
    print("Wrote \(outputURL.lastPathComponent): \(entries.count) entries, \(formatBytes(fileSize))\n")
} catch {
    print("ERROR compiling Swedish: \(error)")
    exit(1)
}

print("Done!")
