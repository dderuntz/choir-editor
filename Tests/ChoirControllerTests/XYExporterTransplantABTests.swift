import Foundation
import XCTest
@testable import ChoirController

final class XYExporterTransplantABTests: XCTestCase {
    private struct Scenario {
        let name: String
        let extraLockSteps: [Int]
    }

    private struct ExportSnapshot {
        let scenario: String
        let strategy: String
        let outputURL: URL
        let requestedStepLocks: Int
        let exportedLockEntries: Int
        let requestedTopology: String
        let exportedSlots: String
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func robotsURL() -> URL {
        repoRootURL().appendingPathComponent("Sources/ChoirController/Robots.choir")
    }

    private func outputDirectoryURL() -> URL {
        repoRootURL()
            .appendingPathComponent("export")
            .appendingPathComponent("robots-debug")
            .appendingPathComponent("ab")
    }

    private func extraMask6Note(step: Int) -> SequencerNote {
        let beat = Double(step - 1) / 4.0
        return SequencerNote(
            pitch: 60,
            startBeat: beat,
            duration: 0.25,
            velocity: 100,
            consonant: 32,
            vowel: 16,
            vibrato: 64,
            reverb: 32
        )
    }

    private func parseDebugSidecar(_ debugURL: URL) throws -> (requestedStepLocks: Int, exportedLockEntries: Int, requestedTopology: String, exportedSlots: String) {
        let text = try String(contentsOf: debugURL, encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init)

        func value(prefix: String) -> String? {
            lines.first(where: { $0.hasPrefix(prefix) })?
                .replacingOccurrences(of: prefix, with: "")
        }

        let requestedStepLocks = Int(value(prefix: "requested_step_locks=") ?? "") ?? -1
        let exportedLockEntries = Int(value(prefix: "exported_lock_entries=") ?? "") ?? -1
        let requestedTopology = value(prefix: "requested_topology=") ?? ""
        let exportedSlots = value(prefix: "exported_slots=") ?? ""

        return (requestedStepLocks, exportedLockEntries, requestedTopology, exportedSlots)
    }

    @MainActor
    private func runExport(
        scenario: Scenario,
        strategy: String?
    ) throws -> ExportSnapshot {
        let fm = FileManager.default
        let outDir = outputDirectoryURL()
        if !fm.fileExists(atPath: outDir.path) {
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        }

        let strategyName = strategy ?? "baseline"
        let outputURL = outDir.appendingPathComponent("\(scenario.name)-\(strategyName).xy")

        if let strategy {
            setenv("CHOIR_XY_LOCK_STRATEGY", strategy, 1)
        } else {
            unsetenv("CHOIR_XY_LOCK_STRATEGY")
        }

        let model = SequencerModel()
        try model.load(from: robotsURL())
        for step in scenario.extraLockSteps {
            model.notes.append(extraMask6Note(step: step))
        }
        try model.exportXY(to: outputURL)

        let debugURL = outputURL.deletingPathExtension().appendingPathExtension("export-debug.txt")
        XCTAssertTrue(fm.fileExists(atPath: outputURL.path), "missing export \(outputURL.lastPathComponent)")
        XCTAssertTrue(fm.fileExists(atPath: debugURL.path), "missing debug sidecar \(debugURL.lastPathComponent)")

        let parsed = try parseDebugSidecar(debugURL)
        return ExportSnapshot(
            scenario: scenario.name,
            strategy: strategyName,
            outputURL: outputURL,
            requestedStepLocks: parsed.requestedStepLocks,
            exportedLockEntries: parsed.exportedLockEntries,
            requestedTopology: parsed.requestedTopology,
            exportedSlots: parsed.exportedSlots
        )
    }

    @MainActor
    func testGenerateTransplantABReportForRobotsSupersetTopologies() throws {
        setenv("CHOIR_XY_EXPORT_DEBUG", "1", 1)
        defer {
            unsetenv("CHOIR_XY_EXPORT_DEBUG")
            unsetenv("CHOIR_XY_LOCK_STRATEGY")
        }

        let scenarios: [Scenario] = [
            Scenario(name: "robots-base", extraLockSteps: []),
            Scenario(name: "robots-plus-step7", extraLockSteps: [7]),
            Scenario(name: "robots-plus-step7-step11", extraLockSteps: [7, 11]),
            Scenario(name: "robots-plus-step2", extraLockSteps: [2]),
            Scenario(name: "robots-plus-step2-step6", extraLockSteps: [2, 6]),
            Scenario(name: "robots-plus-step2-step6-step7", extraLockSteps: [2, 6, 7]),
            Scenario(name: "robots-plus-step2-step7-step11", extraLockSteps: [2, 7, 11]),
            Scenario(name: "robots-plus-step2-step6-step7-step11", extraLockSteps: [2, 6, 7, 11]),
            Scenario(name: "robots-plus-step2-step6-step7-step11-step14", extraLockSteps: [2, 6, 7, 11, 14]),
            Scenario(name: "robots-plus-step2-step6-step7-step11-step14-step15", extraLockSteps: [2, 6, 7, 11, 14, 15])
        ]

        var baselineByScenario: [String: ExportSnapshot] = [:]
        var transplantByScenario: [String: ExportSnapshot] = [:]

        for scenario in scenarios {
            let supportsStrict = scenario.name != "robots-plus-step2-step6-step7-step11-step14-step15"
            let baseline: ExportSnapshot?
            if supportsStrict {
                baseline = try runExport(scenario: scenario, strategy: "strict")
            } else {
                XCTAssertThrowsError(try runExport(scenario: scenario, strategy: "strict"))
                baseline = nil
            }
            let transplant = try runExport(scenario: scenario, strategy: "transplant")
            if let baseline {
                baselineByScenario[scenario.name] = baseline
            }
            transplantByScenario[scenario.name] = transplant

            let expectedRequested = 19 + scenario.extraLockSteps.count
            if let baseline {
                XCTAssertEqual(baseline.requestedStepLocks, expectedRequested)
            }
            XCTAssertEqual(transplant.requestedStepLocks, expectedRequested)
            XCTAssertGreaterThan(transplant.exportedLockEntries, 0)
            if let baseline {
                XCTAssertGreaterThanOrEqual(transplant.exportedLockEntries, baseline.exportedLockEntries)
            }

            if scenario.name == "robots-base"
                || scenario.name == "robots-plus-step7"
                || scenario.name == "robots-plus-step7-step11"
                || scenario.name == "robots-plus-step2"
                || scenario.name == "robots-plus-step2-step6"
                || scenario.name == "robots-plus-step2-step6-step7"
                || scenario.name == "robots-plus-step2-step7-step11"
                || scenario.name == "robots-plus-step2-step6-step7-step11"
                || scenario.name == "robots-plus-step2-step6-step7-step11-step14" {
                XCTAssertGreaterThan(
                    baseline?.exportedLockEntries ?? 0,
                    0,
                    "captured superset topology should now synthesize without transplant"
                )
            }
        }

        // Default strategy should fail closed instead of silently dropping locks.
        if let frontier = scenarios.first(where: { $0.name == "robots-plus-step2-step6-step7-step11-step14-step15" }) {
            XCTAssertThrowsError(try runExport(scenario: frontier, strategy: nil))
        }

        let improvedScenarios = scenarios.filter { scenario in
            guard let baseline = baselineByScenario[scenario.name],
                  let transplant = transplantByScenario[scenario.name] else {
                return false
            }
            return transplant.exportedLockEntries > baseline.exportedLockEntries
        }
        if let frontierTransplant = transplantByScenario["robots-plus-step2-step6-step7-step11-step14-step15"] {
            XCTAssertGreaterThan(
                frontierTransplant.exportedLockEntries,
                0,
                "transplant strategy should remain available as an explicit diagnostic escape hatch"
            )
        }

        let reportURL = outputDirectoryURL().appendingPathComponent("transplant-ab-report.txt")
        var lines: [String] = []
        lines.append("OP-XY lock topology A/B report")
        lines.append("generated=\(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        for scenario in scenarios {
            guard let baseline = baselineByScenario[scenario.name],
                  let transplant = transplantByScenario[scenario.name] else {
                continue
            }
            lines.append("scenario=\(scenario.name)")
            lines.append("baseline: requested=\(baseline.requestedStepLocks), exported=\(baseline.exportedLockEntries), file=\(baseline.outputURL.lastPathComponent)")
            lines.append("baseline_topology=\(baseline.requestedTopology)")
            lines.append("baseline_slots=\(baseline.exportedSlots)")
            lines.append("transplant: requested=\(transplant.requestedStepLocks), exported=\(transplant.exportedLockEntries), file=\(transplant.outputURL.lastPathComponent)")
            lines.append("transplant_topology=\(transplant.requestedTopology)")
            lines.append("transplant_slots=\(transplant.exportedSlots)")
            lines.append("")
        }

        lines.append("improved_scenarios=\(improvedScenarios.map(\.name).joined(separator: ","))")
        try lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
    }
}
