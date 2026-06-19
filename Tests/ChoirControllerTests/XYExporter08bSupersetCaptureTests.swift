import Foundation
import XCTest
@testable import ChoirController

final class XYExporter08bSupersetCaptureTests: XCTestCase {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func captureURL(_ name: String) -> URL {
        repoRootURL()
            .appendingPathComponent(".release/research/dderuntz-saves08b")
            .appendingPathComponent(name)
    }

    private func lockTable(fromCapture name: String) throws -> XYExporter.Track11LockTable {
        let data = try Data(contentsOf: captureURL(name))
        let body = try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](data), trackIndex: 11))
        return try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: body))
    }

    private func track11Body(fromCapture name: String) throws -> [UInt8] {
        let data = try Data(contentsOf: captureURL(name))
        return try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](data), trackIndex: 11))
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func entryMap(_ table: XYExporter.Track11LockTable) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: table.entries.map { ($0.slot, hex($0.bytes)) })
    }

    private func findSubsequence(in haystack: [UInt8], needle: [UInt8], start: Int = 0) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count, start >= 0 else { return nil }
        guard start <= haystack.count - needle.count else { return nil }
        for i in start...(haystack.count - needle.count) {
            if Array(haystack[i..<(i + needle.count)]) == needle {
                return i
            }
        }
        return nil
    }

    @MainActor
    func testGenerate08b303132333435363738CaptureDiffReport() throws {
        let t30 = try lockTable(fromCapture: "08b 30.xy")
        let t31 = try lockTable(fromCapture: "08b 31.xy")
        let t32 = try lockTable(fromCapture: "08b 32.xy")
        let t33 = try lockTable(fromCapture: "08b 33.xy")
        let t34 = try lockTable(fromCapture: "08b 34.xy")
        let t35 = try lockTable(fromCapture: "08b 35.xy")
        let t36 = try lockTable(fromCapture: "08b 36.xy")
        let t37 = try lockTable(fromCapture: "08b 37.xy")
        let t38 = try lockTable(fromCapture: "08b 38.xy")
        let b30 = try track11Body(fromCapture: "08b 30.xy")
        let b31 = try track11Body(fromCapture: "08b 31.xy")
        let b32 = try track11Body(fromCapture: "08b 32.xy")
        let b33 = try track11Body(fromCapture: "08b 33.xy")
        let b34 = try track11Body(fromCapture: "08b 34.xy")
        let b35 = try track11Body(fromCapture: "08b 35.xy")
        let b36 = try track11Body(fromCapture: "08b 36.xy")
        let b37 = try track11Body(fromCapture: "08b 37.xy")
        let b38 = try track11Body(fromCapture: "08b 38.xy")

        XCTAssertGreaterThan(t30.entries.count, 0)
        XCTAssertGreaterThan(t31.entries.count, 0)
        XCTAssertGreaterThan(t32.entries.count, 0)
        XCTAssertGreaterThan(t33.entries.count, 0)
        XCTAssertGreaterThan(t34.entries.count, 0)
        XCTAssertGreaterThan(t35.entries.count, 0)
        XCTAssertGreaterThan(t36.entries.count, 0)
        XCTAssertGreaterThan(t37.entries.count, 0)
        XCTAssertGreaterThan(t38.entries.count, 0)

        let m30 = entryMap(t30)
        let m31 = entryMap(t31)
        let m32 = entryMap(t32)
        let m33 = entryMap(t33)
        let m34 = entryMap(t34)
        let m35 = entryMap(t35)
        let m36 = entryMap(t36)
        let m37 = entryMap(t37)
        let m38 = entryMap(t38)

        let slots30 = Set(m30.keys)
        let slots31 = Set(m31.keys)
        let slots32 = Set(m32.keys)
        let slots33 = Set(m33.keys)
        let slots34 = Set(m34.keys)
        let slots35 = Set(m35.keys)
        let slots36 = Set(m36.keys)
        let slots37 = Set(m37.keys)
        let slots38 = Set(m38.keys)

        let added30to31 = Array(slots31.subtracting(slots30)).sorted()
        let removed30to31 = Array(slots30.subtracting(slots31)).sorted()
        let changed30to31 = Array(slots30.intersection(slots31)).sorted().filter { m30[$0] != m31[$0] }

        let added31to32 = Array(slots32.subtracting(slots31)).sorted()
        let removed31to32 = Array(slots31.subtracting(slots32)).sorted()
        let changed31to32 = Array(slots31.intersection(slots32)).sorted().filter { m31[$0] != m32[$0] }
        let added32to33 = Array(slots33.subtracting(slots32)).sorted()
        let removed32to33 = Array(slots32.subtracting(slots33)).sorted()
        let changed32to33 = Array(slots32.intersection(slots33)).sorted().filter { m32[$0] != m33[$0] }
        let added33to34 = Array(slots34.subtracting(slots33)).sorted()
        let removed33to34 = Array(slots33.subtracting(slots34)).sorted()
        let changed33to34 = Array(slots33.intersection(slots34)).sorted().filter { m33[$0] != m34[$0] }
        let added34to35 = Array(slots35.subtracting(slots34)).sorted()
        let removed34to35 = Array(slots34.subtracting(slots35)).sorted()
        let changed34to35 = Array(slots34.intersection(slots35)).sorted().filter { m34[$0] != m35[$0] }
        let added35to36 = Array(slots36.subtracting(slots35)).sorted()
        let removed35to36 = Array(slots35.subtracting(slots36)).sorted()
        let changed35to36 = Array(slots35.intersection(slots36)).sorted().filter { m35[$0] != m36[$0] }
        let added36to37 = Array(slots37.subtracting(slots36)).sorted()
        let removed36to37 = Array(slots36.subtracting(slots37)).sorted()
        let changed36to37 = Array(slots36.intersection(slots37)).sorted().filter { m36[$0] != m37[$0] }
        let added37to38 = Array(slots38.subtracting(slots37)).sorted()
        let removed37to38 = Array(slots37.subtracting(slots38)).sorted()
        let changed37to38 = Array(slots37.intersection(slots38)).sorted().filter { m37[$0] != m38[$0] }

        let reportURL = repoRootURL()
            .appendingPathComponent("export")
            .appendingPathComponent("robots-debug")
            .appendingPathComponent("ab")
            .appendingPathComponent("08b-30-31-32-33-34-35-36-37-38-capture-diff.txt")

        let fm = FileManager.default
        let outDir = reportURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: outDir.path) {
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        }

        func linesForTable(name: String, table: XYExporter.Track11LockTable) -> [String] {
            var lines: [String] = []
            lines.append("capture=\(name)")
            lines.append("entry_count=\(table.entries.count)")
            lines.append("slots=\(table.entries.map(\.slot).map(String.init).joined(separator: ","))")
            for entry in table.entries {
                lines.append("slot \(entry.slot): \(hex(entry.bytes))")
            }
            lines.append("")
            return lines
        }

        func suffixLines(name: String, body: [UInt8], table: XYExporter.Track11LockTable) -> [String] {
            let marker: [UInt8] = [0xFF, 0xFF, 0x01, 0x7F, 0x00, 0x00]
            guard let markerOffset = findSubsequence(in: body, needle: marker, start: table.endOffset) else {
                return ["suffix_\(name)=missing-defaults-marker", ""]
            }
            let suffix = Array(body[table.endOffset..<markerOffset])
            return [
                "suffix_\(name)_len=\(suffix.count)",
                "suffix_\(name)_hex=\(hex(suffix))",
                ""
            ]
        }

        func diffLines(from oldName: String, oldMap: [Int: String], to newName: String, newMap: [Int: String], added: [Int], removed: [Int], changed: [Int]) -> [String] {
            var lines: [String] = []
            lines.append("diff=\(oldName)->\(newName)")
            lines.append("added_slots=\(added.map(String.init).joined(separator: ","))")
            lines.append("removed_slots=\(removed.map(String.init).joined(separator: ","))")
            lines.append("changed_slots=\(changed.map(String.init).joined(separator: ","))")
            for slot in changed {
                lines.append("slot \(slot) old=\(oldMap[slot] ?? "")")
                lines.append("slot \(slot) new=\(newMap[slot] ?? "")")
            }
            lines.append("")
            return lines
        }

        var lines: [String] = []
        lines.append("08b superset capture diff")
        lines.append("generated=\(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        lines += linesForTable(name: "08b 30.xy", table: t30)
        lines += suffixLines(name: "08b_30", body: b30, table: t30)
        lines += linesForTable(name: "08b 31.xy", table: t31)
        lines += suffixLines(name: "08b_31", body: b31, table: t31)
        lines += linesForTable(name: "08b 32.xy", table: t32)
        lines += suffixLines(name: "08b_32", body: b32, table: t32)
        lines += linesForTable(name: "08b 33.xy", table: t33)
        lines += suffixLines(name: "08b_33", body: b33, table: t33)
        lines += linesForTable(name: "08b 34.xy", table: t34)
        lines += suffixLines(name: "08b_34", body: b34, table: t34)
        lines += linesForTable(name: "08b 35.xy", table: t35)
        lines += suffixLines(name: "08b_35", body: b35, table: t35)
        lines += linesForTable(name: "08b 36.xy", table: t36)
        lines += suffixLines(name: "08b_36", body: b36, table: t36)
        lines += linesForTable(name: "08b 37.xy", table: t37)
        lines += suffixLines(name: "08b_37", body: b37, table: t37)
        lines += linesForTable(name: "08b 38.xy", table: t38)
        lines += suffixLines(name: "08b_38", body: b38, table: t38)
        lines += diffLines(from: "08b 30.xy", oldMap: m30, to: "08b 31.xy", newMap: m31, added: added30to31, removed: removed30to31, changed: changed30to31)
        lines += diffLines(from: "08b 31.xy", oldMap: m31, to: "08b 32.xy", newMap: m32, added: added31to32, removed: removed31to32, changed: changed31to32)
        lines += diffLines(from: "08b 32.xy", oldMap: m32, to: "08b 33.xy", newMap: m33, added: added32to33, removed: removed32to33, changed: changed32to33)
        lines += diffLines(from: "08b 33.xy", oldMap: m33, to: "08b 34.xy", newMap: m34, added: added33to34, removed: removed33to34, changed: changed33to34)
        lines += diffLines(from: "08b 34.xy", oldMap: m34, to: "08b 35.xy", newMap: m35, added: added34to35, removed: removed34to35, changed: changed34to35)
        lines += diffLines(from: "08b 35.xy", oldMap: m35, to: "08b 36.xy", newMap: m36, added: added35to36, removed: removed35to36, changed: changed35to36)
        lines += diffLines(from: "08b 36.xy", oldMap: m36, to: "08b 37.xy", newMap: m37, added: added36to37, removed: removed36to37, changed: changed36to37)
        lines += diffLines(from: "08b 37.xy", oldMap: m37, to: "08b 38.xy", newMap: m38, added: added37to38, removed: removed37to38, changed: changed37to38)

        try lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
    }
}
