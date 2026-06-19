import Foundation
import XCTest
@testable import ChoirController

final class XYExporterPlockInferencePipelineTests: XCTestCase {
    private struct Transition {
        let from: String
        let to: String
        let operation: String
    }

    private struct SlotChange {
        let slot: Int
        let oldBytes: [UInt8]
        let newBytes: [UInt8]
    }

    private struct TransitionDelta {
        let transition: Transition
        let addedCount: Int
        let removedCount: Int
        let changedCount: Int
        let insertedStep: Int?

        var turbulence: Int {
            addedCount + removedCount + changedCount
        }
    }

    private struct CaptureCandidate {
        let step: Int
        let score: Int
        let reasons: [String]
    }

    private struct IsolatedBatchCapture {
        let capture: String
        let index: Int
        let step: Int?
        let operation: String
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func capturesDirectoryURL() -> URL {
        repoRootURL()
            .appendingPathComponent(".release/research/dderuntz-saves08b")
    }

    private func outputDirectoryURL() -> URL {
        repoRootURL()
            .appendingPathComponent("export")
            .appendingPathComponent("robots-debug")
            .appendingPathComponent("inference")
    }

    private func lockTable(fromCapture name: String) throws -> XYExporter.Track11LockTable {
        let url = capturesDirectoryURL().appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        let body = try XCTUnwrap(XYExporter.inspectTrackBody(in: bytes, trackIndex: 11), "missing track 11 in \(name)")
        return try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: body), "missing lock table in \(name)")
    }

    private func slotMap(_ table: XYExporter.Track11LockTable) -> [Int: [UInt8]] {
        Dictionary(uniqueKeysWithValues: table.entries.map { ($0.slot, $0.bytes) })
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func diffSlots(old: [Int: [UInt8]], new: [Int: [UInt8]]) -> (added: [Int], removed: [Int], changed: [SlotChange]) {
        let oldSlots = Set(old.keys)
        let newSlots = Set(new.keys)
        let added = newSlots.subtracting(oldSlots).sorted()
        let removed = oldSlots.subtracting(newSlots).sorted()

        var changed: [SlotChange] = []
        for slot in oldSlots.intersection(newSlots).sorted() {
            guard let o = old[slot], let n = new[slot], o != n else { continue }
            changed.append(SlotChange(slot: slot, oldBytes: o, newBytes: n))
        }
        return (added, removed, changed)
    }

    private func byteDeltaSummary(_ oldBytes: [UInt8], _ newBytes: [UInt8]) -> String {
        let count = max(oldBytes.count, newBytes.count)
        var parts: [String] = []
        for idx in 0..<count {
            let oldValue = idx < oldBytes.count ? String(format: "%02x", oldBytes[idx]) : "--"
            let newValue = idx < newBytes.count ? String(format: "%02x", newBytes[idx]) : "--"
            if oldValue != newValue {
                parts.append("@\(idx):\(oldValue)->\(newValue)")
            }
        }
        return parts.joined(separator: ", ")
    }

    private func available08bCaptureNames() throws -> [String] {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: capturesDirectoryURL().path
        )
        return names
            .filter { $0.hasPrefix("08b ") && $0.hasSuffix(".xy") }
            .sorted { lhs, rhs in
                let li = captureIndex(from: lhs) ?? -1
                let ri = captureIndex(from: rhs) ?? -1
                if li == ri { return lhs < rhs }
                return li < ri
            }
    }

    private func captureIndex(from name: String) -> Int? {
        let prefix = "08b "
        let suffix = ".xy"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let start = name.index(name.startIndex, offsetBy: prefix.count)
        let end = name.index(name.endIndex, offsetBy: -suffix.count)
        let number = name[start..<end]
        return Int(number)
    }

    private var inferredStepByCaptureIndex: [Int: Int] {
        // Current isolated-from-08b38 active-learning batch.
        [
            39: 15,
            40: 5,
            41: 3,
            42: 50,
            43: 18,
            44: 9,
            45: 13,
            46: 12,
            47: 10,
            48: 19,
            49: 48,
            50: 53,
            51: 21,
            52: 47,
            53: 54,
            54: 22
        ]
    }

    private func isolatedFrom38BatchCaptures() throws -> [IsolatedBatchCapture] {
        let names = try available08bCaptureNames()
        return names
            .compactMap { name -> IsolatedBatchCapture? in
                guard let index = captureIndex(from: name), index >= 39 else { return nil }
                let step = inferredStepByCaptureIndex[index]
                let operation: String
                if let step {
                    operation = "isolated-from-08b38 +step\(step)"
                } else {
                    operation = "isolated-from-08b38 (step-unknown)"
                }
                return IsolatedBatchCapture(capture: name, index: index, step: step, operation: operation)
            }
            .sorted { $0.index < $1.index }
    }

    private func cumulativeTransitions08b() -> [Transition] {
        [
            Transition(from: "08b 30.xy", to: "08b 31.xy", operation: "cumulative +step2"),
            Transition(from: "08b 31.xy", to: "08b 32.xy", operation: "cumulative +step6"),
            Transition(from: "08b 32.xy", to: "08b 33.xy", operation: "cumulative +step7"),
            Transition(from: "08b 34.xy", to: "08b 35.xy", operation: "cumulative +step11"),
            Transition(from: "08b 35.xy", to: "08b 36.xy", operation: "cumulative +step2"),
            Transition(from: "08b 36.xy", to: "08b 37.xy", operation: "cumulative +step6"),
            Transition(from: "08b 37.xy", to: "08b 38.xy", operation: "cumulative +step14")
        ]
    }

    private func parseInsertedStep(from operation: String) -> Int? {
        guard let range = operation.range(of: "+step") else { return nil }
        let suffix = operation[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }

    private func turbulenceTrendLabel(_ values: [Int]) -> String {
        guard values.count >= 2 else { return "unknown" }
        let diffs = zip(values, values.dropFirst()).map { $1 - $0 }
        if diffs.allSatisfy({ $0 < 0 }) {
            return "stabilizing"
        }
        if diffs.allSatisfy({ $0 > 0 }) {
            return "destabilizing"
        }
        return "mixed"
    }

    private var robotsBaseMask6Steps: Set<Int> {
        [1, 4, 8, 16, 17, 20, 24, 29, 30, 33, 36, 40, 46, 49, 51, 52, 55, 63, 64]
    }

    @MainActor
    func testGenerate08bTransferInferenceReport() throws {
        let fm = FileManager.default
        let outDir = outputDirectoryURL()
        if !fm.fileExists(atPath: outDir.path) {
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        }

        // Isolated matrix: baseline -> one lock scenario.
        let isolatedSingleStep: [(capture: String, operation: String)] = [
            ("08b 1.xy", "isolated add step 1 mask6 value(32,16)"),
            ("08b 2.xy", "isolated add step 4 mask6 value(32,16)"),
            ("08b 3.xy", "isolated add step 8 mask6 value(32,16)"),
            ("08b 4.xy", "isolated add step 16 mask6 value(32,16)"),
            ("08b 5.xy", "isolated add step 17 mask6 value(32,16)"),
            ("08b 6.xy", "isolated add step 20 mask6 value(32,16)"),
            ("08b 7.xy", "isolated add step 24 mask6 value(32,16)"),
            ("08b 8.xy", "isolated add step 29 mask6 value(32,16)"),
            ("08b 9.xy", "isolated add step 30 mask6 value(32,16)"),
            ("08b 10.xy", "isolated add step 33 mask6 value(32,16)"),
            ("08b 11.xy", "isolated add step 36 mask6 value(32,16)"),
            ("08b 12.xy", "isolated add step 40 mask6 value(32,16)"),
            ("08b 13.xy", "isolated add step 46 mask6 value(32,16)"),
            ("08b 14.xy", "isolated add step 49 mask6 value(32,16)"),
            ("08b 15.xy", "isolated add step 51 mask6 value(32,16)"),
            ("08b 16.xy", "isolated add step 52 mask6 value(32,16)"),
            ("08b 17.xy", "isolated add step 55 mask6 value(32,16)"),
            ("08b 18.xy", "isolated add step 63 mask6 value(32,16)"),
            ("08b 19.xy", "isolated add step 64 mask6 value(32,16)")
        ]

        // Cumulative chains show transfer when topology expands.
        let cumulativeTransitions = cumulativeTransitions08b()

        let baseline = try slotMap(lockTable(fromCapture: "08b 0.xy"))
        var lines: [String] = []
        lines.append("OP-XY Track11 P-Lock Transfer Inference Report")
        lines.append("generated=\(ISO8601DateFormatter().string(from: Date()))")
        lines.append("captures_dir=\(capturesDirectoryURL().path)")
        lines.append("")
        lines.append("Section: isolated_single_step")
        for item in isolatedSingleStep {
            let next = try slotMap(lockTable(fromCapture: item.capture))
            let diff = diffSlots(old: baseline, new: next)
            lines.append("from=08b 0.xy to=\(item.capture) op=\(item.operation)")
            lines.append("added_slots=\(diff.added.map(String.init).joined(separator: ","))")
            lines.append("removed_slots=\(diff.removed.map(String.init).joined(separator: ","))")
            lines.append("changed_slots=\(diff.changed.map { String($0.slot) }.joined(separator: ","))")
            for slot in diff.added {
                if let bytes = next[slot] {
                    lines.append("  + slot \(slot): \(hex(bytes))")
                }
            }
            for change in diff.changed {
                lines.append("  * slot \(change.slot): \(byteDeltaSummary(change.oldBytes, change.newBytes))")
                lines.append("    old=\(hex(change.oldBytes))")
                lines.append("    new=\(hex(change.newBytes))")
            }
            lines.append("")
        }

        lines.append("Section: cumulative_frontier")
        for t in cumulativeTransitions {
            let old = try slotMap(lockTable(fromCapture: t.from))
            let new = try slotMap(lockTable(fromCapture: t.to))
            let diff = diffSlots(old: old, new: new)
            lines.append("from=\(t.from) to=\(t.to) op=\(t.operation)")
            lines.append("added_slots=\(diff.added.map(String.init).joined(separator: ","))")
            lines.append("removed_slots=\(diff.removed.map(String.init).joined(separator: ","))")
            lines.append("changed_slots=\(diff.changed.map { String($0.slot) }.joined(separator: ","))")
            for slot in diff.added {
                if let bytes = new[slot] {
                    lines.append("  + slot \(slot): \(hex(bytes))")
                }
            }
            for slot in diff.removed {
                if let bytes = old[slot] {
                    lines.append("  - slot \(slot): \(hex(bytes))")
                }
            }
            for change in diff.changed {
                lines.append("  * slot \(change.slot): \(byteDeltaSummary(change.oldBytes, change.newBytes))")
                lines.append("    old=\(hex(change.oldBytes))")
                lines.append("    new=\(hex(change.newBytes))")
            }
            lines.append("")
        }

        let isolatedBatch = try isolatedFrom38BatchCaptures()
        if !isolatedBatch.isEmpty {
            lines.append("Section: isolated_from_08b38_batch")
            let base = try slotMap(lockTable(fromCapture: "08b 38.xy"))
            for item in isolatedBatch {
                let target = try slotMap(lockTable(fromCapture: item.capture))
                let diff = diffSlots(old: base, new: target)
                lines.append("from=08b 38.xy to=\(item.capture) op=\(item.operation)")
                lines.append("added_slots=\(diff.added.map(String.init).joined(separator: ","))")
                lines.append("removed_slots=\(diff.removed.map(String.init).joined(separator: ","))")
                lines.append("changed_slots=\(diff.changed.map { String($0.slot) }.joined(separator: ","))")
                for slot in diff.added {
                    if let bytes = target[slot] {
                        lines.append("  + slot \(slot): \(hex(bytes))")
                    }
                }
                for slot in diff.removed {
                    if let bytes = base[slot] {
                        lines.append("  - slot \(slot): \(hex(bytes))")
                    }
                }
                for change in diff.changed {
                    lines.append("  * slot \(change.slot): \(byteDeltaSummary(change.oldBytes, change.newBytes))")
                    lines.append("    old=\(hex(change.oldBytes))")
                    lines.append("    new=\(hex(change.newBytes))")
                }
                lines.append("")
            }
        }

        let reportURL = outDir.appendingPathComponent("08b-transfer-inference-report.txt")
        try lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(fm.fileExists(atPath: reportURL.path))
    }

    @MainActor
    func testGenerate08bNextCaptureSuggestions() throws {
        let fm = FileManager.default
        let outDir = outputDirectoryURL()
        if !fm.fileExists(atPath: outDir.path) {
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        }

        let cumulativeTransitions = cumulativeTransitions08b()
        var deltas: [TransitionDelta] = []
        for transition in cumulativeTransitions {
            let old = try slotMap(lockTable(fromCapture: transition.from))
            let new = try slotMap(lockTable(fromCapture: transition.to))
            let diff = diffSlots(old: old, new: new)
            deltas.append(
                TransitionDelta(
                    transition: transition,
                    addedCount: diff.added.count,
                    removedCount: diff.removed.count,
                    changedCount: diff.changed.count,
                    insertedStep: parseInsertedStep(from: transition.operation)
                )
            )
        }

        let latestTransition = try XCTUnwrap(
            deltas.max { lhs, rhs in
                if lhs.transition.to == rhs.transition.to {
                    return lhs.turbulence < rhs.turbulence
                }
                return lhs.transition.to < rhs.transition.to
            }
        )
        let frontierStep = latestTransition.insertedStep

        let isolatedBatch = try isolatedFrom38BatchCaptures()
        let capturedExtraSteps = Set(deltas.compactMap(\.insertedStep)).union(isolatedBatch.compactMap(\.step))
        let activeSteps = robotsBaseMask6Steps.union(capturedExtraSteps)
        let missingSteps = Set(1...64).subtracting(activeSteps)
        let coverageCount = activeSteps.count
        let totalStepCount = 64
        let remainingCount = missingSteps.count
        let coveragePercent = Double(coverageCount) * 100.0 / Double(totalStepCount)

        let turbulenceSeries = deltas
            .sorted {
                (captureIndex(from: $0.transition.to) ?? -1) < (captureIndex(from: $1.transition.to) ?? -1)
            }
            .map(\.turbulence)
        let recentTurbulence = Array(turbulenceSeries.suffix(3))
        let turbulenceTrend = turbulenceTrendLabel(recentTurbulence)
        let recentTurbulenceAverage = recentTurbulence.isEmpty
            ? 0.0
            : Double(recentTurbulence.reduce(0, +)) / Double(recentTurbulence.count)

        var anchorSteps: [Int] = []
        if let frontierStep {
            anchorSteps.append(frontierStep)
        }
        anchorSteps += isolatedBatch.compactMap(\.step)
        if anchorSteps.isEmpty {
            anchorSteps = Array(robotsBaseMask6Steps)
        }

        let candidates: [CaptureCandidate] = missingSteps.map { step in
            var score = 0
            var reasons: [String] = []

            if activeSteps.contains(step - 1) {
                score += 40
                reasons.append("adjacent-left")
            }
            if activeSteps.contains(step + 1) {
                score += 40
                reasons.append("adjacent-right")
            }
            if activeSteps.contains(step - 2) {
                score += 10
                reasons.append("near-left-2")
            }
            if activeSteps.contains(step + 2) {
                score += 10
                reasons.append("near-right-2")
            }
            if activeSteps.contains(step - 1), activeSteps.contains(step + 1) {
                score += 80
                reasons.append("bridges-active-gap")
            }

            let nearestAnchorDistance = anchorSteps.map { abs(step - $0) }.min() ?? Int.max
            let anchorBonus = max(0, 30 - (nearestAnchorDistance * 2))
            if anchorBonus > 0 {
                score += anchorBonus
                reasons.append("near-anchor(+\(anchorBonus))")
            }

            return CaptureCandidate(step: step, score: score, reasons: reasons)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.step < rhs.step }
            return lhs.score > rhs.score
        }

        let top = try XCTUnwrap(candidates.first)
        XCTAssertFalse(capturedExtraSteps.contains(top.step), "suggested step should be uncaptured")
        let nextBatch = Array(candidates.prefix(5))

        var lines: [String] = []
        lines.append("OP-XY Track11 Next-Capture Suggestions")
        lines.append("generated=\(ISO8601DateFormatter().string(from: Date()))")
        lines.append("captures_dir=\(capturesDirectoryURL().path)")
        lines.append("")
        lines.append("coverage_known_active_steps=\(coverageCount)/\(totalStepCount)")
        lines.append("coverage_remaining_steps=\(remainingCount)")
        lines.append("coverage_percent=\(String(format: "%.1f", coveragePercent))")
        lines.append("recent_turbulence_values=\(recentTurbulence.map(String.init).joined(separator: ","))")
        lines.append("recent_turbulence_avg=\(String(format: "%.1f", recentTurbulenceAverage))")
        lines.append("inference_confidence_proxy=turbulence-\(turbulenceTrend)")
        lines.append("")
        lines.append("latest_transition=\(latestTransition.transition.from)->\(latestTransition.transition.to)")
        lines.append("latest_transition_turbulence=\(latestTransition.turbulence)")
        lines.append("latest_transition_inserted_step=\(latestTransition.insertedStep.map(String.init) ?? "unknown")")
        lines.append("captured_isolated_from_08b38_steps=\(isolatedBatch.compactMap(\.step).sorted().map(String.init).joined(separator: ","))")
        lines.append("known_active_steps=\(activeSteps.sorted().map(String.init).joined(separator: ","))")
        lines.append("")
        lines.append("recommended_next_capture_step=\(top.step)")
        lines.append("recommended_reason=\(top.reasons.joined(separator: ","))")
        let nextIndex = (isolatedBatch.map(\.index).max() ?? 38) + 1
        lines.append("capture_recipe=load 08b 38.xy; add step \(top.step) with CC2=32 CC3=16; save as 08b \(nextIndex).xy")
        lines.append("recommended_next_batch_steps=\(nextBatch.map(\.step).map(String.init).joined(separator: ","))")
        lines.append("recommended_next_batch_base=load 08b 38.xy fresh each time; add exactly one step; CC2=32 CC3=16")
        for (offset, candidate) in nextBatch.enumerated() {
            lines.append(
                "recommended_next_batch_item_\(offset + 1)=step\(candidate.step)->08b \(nextIndex + offset).xy reasons=\(candidate.reasons.joined(separator: ","))"
            )
        }
        lines.append("")
        lines.append("ranked_candidates_top10")
        for (idx, candidate) in candidates.prefix(10).enumerated() {
            lines.append(
                "\(idx + 1). step=\(candidate.step) score=\(candidate.score) reasons=\(candidate.reasons.joined(separator: ","))"
            )
        }

        let reportURL = outDir.appendingPathComponent("08b-next-capture-suggestions.txt")
        try lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(fm.fileExists(atPath: reportURL.path))
    }
}
