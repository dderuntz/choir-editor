import XCTest
@testable import ChoirController

final class XYExporterTrack11LockTableTests: XCTestCase {
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

    private func exportTemplateURL() -> URL {
        captureURL("08a 0.xy")
    }

    private func track11Body(fromCapture name: String) throws -> [UInt8] {
        let url = captureURL(name)
        let data = try Data(contentsOf: url)
        guard let body = XYExporter.inspectTrackBody(in: [UInt8](data), trackIndex: 11) else {
            XCTFail("could not parse Track 11 body from \(name)")
            return []
        }
        return body
    }

    private func snapshot(fromCapture name: String) throws -> XYExporter.Track11LockTable {
        let body = try track11Body(fromCapture: name)
        guard let table = XYExporter.inspectTrack11LockTable(in: body) else {
            XCTFail("could not parse Track 11 lock table for \(name)")
            return XYExporter.Track11LockTable(startOffset: 0, endOffset: 0, entries: [])
        }
        return table
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func export(stepLocks: [XYExportStepLockData], note: XYExportNoteData? = nil) throws -> XYExporter.Track11LockTable {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-exporter-locktable-\(UUID().uuidString).xy")
        let noteData = note ?? XYExportNoteData(
            step: 1,
            note: 60,
            velocity: 100,
            gateTicks: 960,
            tickOffset: 0
        )

        try XYExporter.export(
            templateURL: exportTemplateURL(),
            outputURL: output,
            trackIndex: 11,
            notes: [noteData],
            stepLocks: stepLocks,
            tempoTenths: 1000,
            grooveType: 0
        )

        let outputData = try Data(contentsOf: output)
        let outputBody = try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](outputData), trackIndex: 11))
        return try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: outputBody))
    }

    private func assertExportedLockTableMatchesCapture(
        captureName: String,
        stepLocks: [XYExportStepLockData],
        note: XYExportNoteData? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let expected = try snapshot(fromCapture: captureName)
        let actual = try export(stepLocks: stepLocks, note: note)
        XCTAssertEqual(actual.entries.map(\.slot), expected.entries.map(\.slot), file: file, line: line)
        XCTAssertEqual(
            actual.entries.map { hex($0.bytes) },
            expected.entries.map { hex($0.bytes) },
            file: file,
            line: line
        )
    }

    func testDefaultsOnlyTemplateHasNoNonEmptyLockEntries() throws {
        let table = try snapshot(fromCapture: "08a 0.xy")
        XCTAssertEqual(table.entries.count, 0)
    }

    func testExporterPreservesLockTableWhenNoLocksRequested() throws {
        let templateTable = try snapshot(fromCapture: "08a 0.xy")
        let outputTable = try export(
            stepLocks: [],
            note: XYExportNoteData(
                step: 1,
                note: 60,
                velocity: 100,
                gateTicks: 960,
                tickOffset: 0,
                cc1: 64,
                cc2: 127,
                cc3: 0,
                cc4: 32
            )
        )
        XCTAssertEqual(outputTable.entries.count, templateTable.entries.count)
        XCTAssertEqual(outputTable.startOffset, templateTable.startOffset)
        XCTAssertEqual(outputTable.endOffset, templateTable.endOffset)
    }

    func testExporterSynthesizesSingleStepCC1FromNote() throws {
        try assertExportedLockTableMatchesCapture(
            captureName: "08a 1.xy",
            stepLocks: [],
            note: XYExportNoteData(
                step: 1,
                note: 60,
                velocity: 100,
                gateTicks: 960,
                tickOffset: 0,
                cc1: 16
            )
        )
    }

    func testExporterSynthesizesSingleStepCC2LockOnly() throws {
        try assertExportedLockTableMatchesCapture(
            captureName: "08a 19.xy",
            stepLocks: [XYExportStepLockData(step: 3, cc2: 16)]
        )
    }

    func testExporterSynthesizesSingleStep16CC1Lock() throws {
        try assertExportedLockTableMatchesCapture(
            captureName: "08a 16.xy",
            stepLocks: [XYExportStepLockData(step: 16, cc1: 16)]
        )
    }

    func testExporterSynthesizesSupportedZeroStep5CC1() throws {
        try assertExportedLockTableMatchesCapture(
            captureName: "08a 34.xy",
            stepLocks: [XYExportStepLockData(step: 5, cc1: 0)]
        )
    }

    func testExporterThrowsWhenUnsupportedZeroEncodingIsRequested() throws {
        XCTAssertThrowsError(
            try export(stepLocks: [XYExportStepLockData(step: 2, cc1: 0)])
        )
    }

    func testExporterSynthesizesMultiLaneStep3CC1CC2() throws {
        try assertExportedLockTableMatchesCapture(
            captureName: "08a 39.xy",
            stepLocks: [XYExportStepLockData(step: 3, cc1: 64, cc2: 32)]
        )
    }

    func testExporterSynthesizesMultiLaneStep3CC1CC2CC3CC4() throws {
        try assertExportedLockTableMatchesCapture(
            captureName: "08a 41.xy",
            stepLocks: [XYExportStepLockData(step: 3, cc1: 64, cc2: 32, cc3: 16, cc4: 8)]
        )
    }

    func testExporterSynthesizesSplitMultiLaneStep3CC2CC4() throws {
        try assertExportedLockTableMatchesCapture(
            captureName: "08a 43.xy",
            stepLocks: [XYExportStepLockData(step: 3, cc2: 32, cc4: 8)]
        )
    }

    func testExporterSynthesizesNonPrefixSetStep1Step3() throws {
        try assertExportedLockTableMatchesCapture(
            captureName: "08a 44.xy",
            stepLocks: [
                XYExportStepLockData(step: 1, cc1: 16),
                XYExportStepLockData(step: 3, cc1: 16)
            ]
        )
    }

    func testExporterSynthesizesNonPrefixSetStep1Step5Step9Step13() throws {
        try assertExportedLockTableMatchesCapture(
            captureName: "08a 51.xy",
            stepLocks: [
                XYExportStepLockData(step: 1, cc1: 16),
                XYExportStepLockData(step: 5, cc1: 16),
                XYExportStepLockData(step: 9, cc1: 16),
                XYExportStepLockData(step: 13, cc1: 16)
            ]
        )
    }

    func testExporterThrowsForUnsupportedMultiStepCC1Set() throws {
        XCTAssertThrowsError(
            try export(
                stepLocks: [
                    XYExportStepLockData(step: 2, cc1: 16),
                    XYExportStepLockData(step: 4, cc1: 16)
                ]
            )
        )
    }

    func testExporterThrowsWhenLockSynthesisIsUnavailable() throws {
        XCTAssertThrowsError(
            try export(
                stepLocks: [],
                note: XYExportNoteData(
                    step: 2,
                    note: 60,
                    velocity: 100,
                    gateTicks: 960,
                    tickOffset: 0,
                    cc3: 16
                )
            )
        )
    }
}
