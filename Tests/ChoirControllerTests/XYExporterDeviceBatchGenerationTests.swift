import Foundation
import XCTest
@testable import ChoirController

final class XYExporterDeviceBatchGenerationTests: XCTestCase {
    private struct BatchCase {
        let filename: String
        let expectedCapture: String
        let note: XYExportNoteData
        let stepLocks: [XYExportStepLockData]
        let scenario: String
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func captureURL(_ name: String) -> URL {
        repoRootURL()
            .appendingPathComponent(".release/research/dderuntz-saves3")
            .appendingPathComponent(name)
    }

    private func appWorkingTemplateURL() -> URL {
        repoRootURL()
            .appendingPathComponent(".release/research/dderuntz-saves2/04f b-check.xy")
    }

    private func outputDirectoryURL() -> URL {
        repoRootURL()
            .appendingPathComponent("export")
            .appendingPathComponent("device-batch-08a-small")
    }

    private func lockTable(fromProjectAt url: URL) throws -> XYExporter.Track11LockTable {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        let body = try XCTUnwrap(XYExporter.inspectTrackBody(in: bytes, trackIndex: 11))
        return try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: body))
    }

    private func lockTable(fromCapture name: String) throws -> XYExporter.Track11LockTable {
        try lockTable(fromProjectAt: captureURL(name))
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    func testGenerateSmall08aDeviceBatch() throws {
        let template = appWorkingTemplateURL()
        let outDir = outputDirectoryURL()
        let fm = FileManager.default

        if fm.fileExists(atPath: outDir.path) {
            try fm.removeItem(at: outDir)
        }
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        let baseNote = XYExportNoteData(
            step: 1,
            note: 60,
            velocity: 100,
            gateTicks: 960,
            tickOffset: 0
        )

        let cases: [BatchCase] = [
            BatchCase(
                filename: "batch-00-control-notes-only.xy",
                expectedCapture: "08a 0.xy",
                note: baseNote,
                stepLocks: [],
                scenario: "control: notes-only export (no step locks)"
            ),
            BatchCase(
                filename: "batch-01-note-step-cc1-16.xy",
                expectedCapture: "08a 1.xy",
                note: XYExportNoteData(
                    step: 1,
                    note: 60,
                    velocity: 100,
                    gateTicks: 960,
                    tickOffset: 0,
                    cc1: 16
                ),
                stepLocks: [],
                scenario: "single lock on note step (CC1=16 at step 1)"
            ),
            BatchCase(
                filename: "batch-02-lockonly-step3-cc2-16.xy",
                expectedCapture: "08a 19.xy",
                note: baseNote,
                stepLocks: [XYExportStepLockData(step: 3, cc2: 16)],
                scenario: "single lock-only step (CC2=16 at step 3)"
            ),
            BatchCase(
                filename: "batch-03-zero-step5-cc1.xy",
                expectedCapture: "08a 34.xy",
                note: baseNote,
                stepLocks: [XYExportStepLockData(step: 5, cc1: 0)],
                scenario: "known-safe zero encoding (CC1=0 at step 5)"
            ),
            BatchCase(
                filename: "batch-04-multilane-step3-cc1cc2.xy",
                expectedCapture: "08a 39.xy",
                note: baseNote,
                stepLocks: [XYExportStepLockData(step: 3, cc1: 64, cc2: 32)],
                scenario: "multi-lane same step (step 3: CC1=64, CC2=32)"
            ),
            BatchCase(
                filename: "batch-05-multilane-step3-all4.xy",
                expectedCapture: "08a 41.xy",
                note: baseNote,
                stepLocks: [XYExportStepLockData(step: 3, cc1: 64, cc2: 32, cc3: 16, cc4: 8)],
                scenario: "multi-lane same step (step 3: CC1/CC2/CC3/CC4)"
            ),
            BatchCase(
                filename: "batch-06-nonprefix-1-5-9-13.xy",
                expectedCapture: "08a 51.xy",
                note: baseNote,
                stepLocks: [
                    XYExportStepLockData(step: 1, cc1: 16),
                    XYExportStepLockData(step: 5, cc1: 16),
                    XYExportStepLockData(step: 9, cc1: 16),
                    XYExportStepLockData(step: 13, cc1: 16)
                ],
                scenario: "non-prefix multi-step set (steps 1,5,9,13 CC1=16)"
            )
        ]

        var manifest: [String] = []
        manifest.append("# Small Device Batch (08a-backed, app-template)")
        manifest.append("Generated: \(Date())")
        manifest.append("Template: \(template.path)")
        manifest.append("")
        manifest.append("Each file was lock-table-verified against its capture before writing this manifest.")
        manifest.append("")

        for item in cases {
            let outputURL = outDir.appendingPathComponent(item.filename)
            try XYExporter.export(
                templateURL: template,
                outputURL: outputURL,
                trackIndex: 11,
                notes: [item.note],
                stepLocks: item.stepLocks,
                tempoTenths: 1000,
                grooveType: 0
            )

            let expected = try lockTable(fromCapture: item.expectedCapture)
            let actual = try lockTable(fromProjectAt: outputURL)

            XCTAssertEqual(actual.entries.map(\.slot), expected.entries.map(\.slot), "slot mismatch for \(item.filename)")
            XCTAssertEqual(
                actual.entries.map { hex($0.bytes) },
                expected.entries.map { hex($0.bytes) },
                "entry bytes mismatch for \(item.filename)"
            )

            manifest.append("- \(item.filename)")
            manifest.append("  - scenario: \(item.scenario)")
            manifest.append("  - expected capture: \(item.expectedCapture)")
        }

        let manifestURL = outDir.appendingPathComponent("README-device-test-batch.md")
        try manifest.joined(separator: "\n").write(to: manifestURL, atomically: true, encoding: .utf8)
    }
}
