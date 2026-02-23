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
            .appendingPathComponent(".release/research/dderuntz-saves2")
            .appendingPathComponent(name)
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

    private func assertExportedLockTableMatchesCapture(
        captureName: String,
        stepLocks: [XYExportStepLockData],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let template = captureURL("04f b-check.xy")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-exporter-locktable-match-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: template,
            outputURL: output,
            trackIndex: 11,
            notes: [
                XYExportNoteData(
                    step: 1,
                    note: 60,
                    velocity: 100,
                    gateTicks: 960,
                    tickOffset: 0
                )
            ],
            stepLocks: stepLocks,
            tempoTenths: 1000,
            grooveType: 0
        )

        let expected = try snapshot(fromCapture: captureName)
        let outputData = try Data(contentsOf: output)
        let outputBody = try XCTUnwrap(
            XYExporter.inspectTrackBody(in: [UInt8](outputData), trackIndex: 11),
            file: file,
            line: line
        )
        let actual = try XCTUnwrap(
            XYExporter.inspectTrack11LockTable(in: outputBody),
            file: file,
            line: line
        )
        XCTAssertEqual(actual.entries.map(\.slot), expected.entries.map(\.slot), file: file, line: line)
        XCTAssertEqual(
            actual.entries.map { hex($0.bytes) },
            expected.entries.map { hex($0.bytes) },
            file: file,
            line: line
        )
    }

    func testDefaultsOnlyTemplateHasNoNonEmptyLockEntries() throws {
        let table = try snapshot(fromCapture: "04f b-check.xy")
        XCTAssertEqual(table.entries.count, 0)
    }

    func testSingleLockOnNoteStepSnapshot() throws {
        let table = try snapshot(fromCapture: "06a 1.xy")
        XCTAssertEqual(table.entries.map(\.slot), [2, 44, 48])
        XCTAssertEqual(hex(table.entries[0].bytes), "18 29 10 00 00")
        XCTAssertEqual(hex(table.entries[1].bytes), "c4 01 00 00")
        XCTAssertEqual(hex(table.entries[2].bytes), "fa 01 00 00")
    }

    func testSingleLockOnEmptyStepSnapshot() throws {
        let table = try snapshot(fromCapture: "04f b-s3-cc2v9.xy")
        XCTAssertEqual(table.entries.map(\.slot), [2, 44, 48])
        XCTAssertEqual(hex(table.entries[0].bytes), "c2 29 09 00 00")
        XCTAssertEqual(hex(table.entries[1].bytes), "2a 02 00 00")
        XCTAssertEqual(hex(table.entries[2].bytes), "ea 02 00 00")
    }

    func testMultiLaneLockSnapshot() throws {
        let table = try snapshot(fromCapture: "04d b-s3-cc1v64-cc2v32-cc3v16-cc4v8.xy")
        XCTAssertEqual(table.entries.map(\.slot), [2, 3, 7, 45, 46, 47, 51])
        XCTAssertEqual(hex(table.entries[1].bytes), "a4 d4 40 29 20 d4 10 29 08 00 00")
    }

    func testExporterPreservesLockTableWhenNoLocksRequested() throws {
        let template = captureURL("04f b-check.xy")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-exporter-locktable-defaults-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: template,
            outputURL: output,
            trackIndex: 11,
            notes: [
                XYExportNoteData(
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
            ],
            tempoTenths: 1000,
            grooveType: 0
        )

        let templateTable = try snapshot(fromCapture: "04f b-check.xy")
        let outputData = try Data(contentsOf: output)
        let outputBody = try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](outputData), trackIndex: 11))
        let outputTable = try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: outputBody))
        XCTAssertEqual(outputTable.entries.count, templateTable.entries.count)
        XCTAssertEqual(outputTable.startOffset, templateTable.startOffset)
        XCTAssertEqual(outputTable.endOffset, templateTable.endOffset)
    }

    func testExporterSynthesizesSupportedNoteStepLock() throws {
        let template = captureURL("04f b-check.xy")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-exporter-locktable-supported-note-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: template,
            outputURL: output,
            trackIndex: 11,
            notes: [
                XYExportNoteData(
                    step: 1,
                    note: 60,
                    velocity: 100,
                    gateTicks: 960,
                    tickOffset: 0,
                    cc1: 16,
                    cc2: 127,
                    cc3: 0,
                    cc4: 32
                )
            ],
            tempoTenths: 1000,
            grooveType: 0
        )

        let outputData = try Data(contentsOf: output)
        let outputBody = try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](outputData), trackIndex: 11))
        let outputTable = try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: outputBody))
        XCTAssertEqual(outputTable.entries.map(\.slot), [2, 44, 48])
        XCTAssertEqual(hex(outputTable.entries[0].bytes), "18 29 10 00 00")
        XCTAssertEqual(hex(outputTable.entries[1].bytes), "c4 01 00 00")
        XCTAssertEqual(hex(outputTable.entries[2].bytes), "fa 01 00 00")
    }

    func testExporterSynthesizesSupportedLockOnlyStep() throws {
        let template = captureURL("04f b-check.xy")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-exporter-locktable-supported-lockonly-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: template,
            outputURL: output,
            trackIndex: 11,
            notes: [
                XYExportNoteData(
                    step: 1,
                    note: 60,
                    velocity: 100,
                    gateTicks: 960,
                    tickOffset: 0
                )
            ],
            stepLocks: [
                XYExportStepLockData(
                    step: 3,
                    cc2: 9
                )
            ],
            tempoTenths: 1000,
            grooveType: 0
        )

        let outputData = try Data(contentsOf: output)
        let outputBody = try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](outputData), trackIndex: 11))
        let outputTable = try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: outputBody))
        XCTAssertEqual(outputTable.entries.map(\.slot), [2, 44, 48])
        XCTAssertEqual(hex(outputTable.entries[0].bytes), "c2 29 09 00 00")
        XCTAssertEqual(hex(outputTable.entries[1].bytes), "2a 02 00 00")
        XCTAssertEqual(hex(outputTable.entries[2].bytes), "ea 02 00 00")
    }

    func testExporterSynthesizesSupportedIsolatedStep5Lock() throws {
        let template = captureURL("04f b-check.xy")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-exporter-locktable-supported-step5-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: template,
            outputURL: output,
            trackIndex: 11,
            notes: [
                XYExportNoteData(
                    step: 1,
                    note: 60,
                    velocity: 100,
                    gateTicks: 960,
                    tickOffset: 0
                )
            ],
            stepLocks: [
                XYExportStepLockData(
                    step: 5,
                    cc1: 16
                )
            ],
            tempoTenths: 1000,
            grooveType: 0
        )

        let outputData = try Data(contentsOf: output)
        let outputBody = try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](outputData), trackIndex: 11))
        let outputTable = try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: outputBody))
        XCTAssertEqual(outputTable.entries.map(\.slot), [3, 44, 48])
        XCTAssertEqual(hex(outputTable.entries[0].bytes), "67 29 10 00 00")
        XCTAssertEqual(hex(outputTable.entries[1].bytes), "95 01 00 00")
        XCTAssertEqual(hex(outputTable.entries[2].bytes), "da 01 00 00")
    }

    func testExporterFallsBackWhenUnsupportedZeroEncodingIsRequested() throws {
        let template = captureURL("04f b-check.xy")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-exporter-locktable-fallback-zero-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: template,
            outputURL: output,
            trackIndex: 11,
            notes: [
                XYExportNoteData(
                    step: 1,
                    note: 60,
                    velocity: 100,
                    gateTicks: 960,
                    tickOffset: 0
                )
            ],
            stepLocks: [
                XYExportStepLockData(
                    step: 5,
                    cc1: 0
                )
            ],
            tempoTenths: 1000,
            grooveType: 0
        )

        let templateTable = try snapshot(fromCapture: "04f b-check.xy")
        let outputData = try Data(contentsOf: output)
        let outputBody = try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](outputData), trackIndex: 11))
        let outputTable = try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: outputBody))
        XCTAssertEqual(outputTable.entries.count, templateTable.entries.count)
        XCTAssertEqual(outputTable.startOffset, templateTable.startOffset)
        XCTAssertEqual(outputTable.endOffset, templateTable.endOffset)
    }

    func testExporterSynthesizesCC1PrefixChainUpToStep2() throws {
        try assertExportedLockTableMatchesCapture(
            captureName: "06a 2.xy",
            stepLocks: [
                XYExportStepLockData(step: 1, cc1: 16),
                XYExportStepLockData(step: 2, cc1: 16)
            ]
        )
    }

    func testExporterSynthesizesCC1PrefixChainUpToStep16() throws {
        try assertExportedLockTableMatchesCapture(
            captureName: "06a 7.xy",
            stepLocks: [
                XYExportStepLockData(step: 1, cc1: 16),
                XYExportStepLockData(step: 2, cc1: 16),
                XYExportStepLockData(step: 3, cc1: 16),
                XYExportStepLockData(step: 4, cc1: 16),
                XYExportStepLockData(step: 9, cc1: 16),
                XYExportStepLockData(step: 13, cc1: 16),
                XYExportStepLockData(step: 16, cc1: 16)
            ]
        )
    }

    func testExporterFallsBackForUnsupportedNonPrefixCC1Set() throws {
        let template = captureURL("04f b-check.xy")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-exporter-locktable-fallback-nonprefix-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: template,
            outputURL: output,
            trackIndex: 11,
            notes: [
                XYExportNoteData(
                    step: 1,
                    note: 60,
                    velocity: 100,
                    gateTicks: 960,
                    tickOffset: 0
                )
            ],
            stepLocks: [
                XYExportStepLockData(step: 1, cc1: 16),
                XYExportStepLockData(step: 3, cc1: 16)
            ],
            tempoTenths: 1000,
            grooveType: 0
        )

        let templateTable = try snapshot(fromCapture: "04f b-check.xy")
        let outputData = try Data(contentsOf: output)
        let outputBody = try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](outputData), trackIndex: 11))
        let outputTable = try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: outputBody))
        XCTAssertEqual(outputTable.entries.count, templateTable.entries.count)
        XCTAssertEqual(outputTable.startOffset, templateTable.startOffset)
        XCTAssertEqual(outputTable.endOffset, templateTable.endOffset)
    }

    func testExporterPreservesLockTableWhenLockSynthesisIsUnavailable() throws {
        let template = captureURL("04f b-check.xy")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-exporter-locktable-fallback-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: template,
            outputURL: output,
            trackIndex: 11,
            notes: [
                XYExportNoteData(
                    step: 2,
                    note: 60,
                    velocity: 100,
                    gateTicks: 960,
                    tickOffset: 0,
                    cc1: 16,
                    cc2: 127,
                    cc3: 0,
                    cc4: 32
                )
            ],
            tempoTenths: 1000,
            grooveType: 0
        )

        let templateTable = try snapshot(fromCapture: "04f b-check.xy")
        let outputData = try Data(contentsOf: output)
        let outputBody = try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](outputData), trackIndex: 11))
        let outputTable = try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: outputBody))
        XCTAssertEqual(outputTable.entries.count, templateTable.entries.count)
        XCTAssertEqual(outputTable.startOffset, templateTable.startOffset)
        XCTAssertEqual(outputTable.endOffset, templateTable.endOffset)
    }
}
