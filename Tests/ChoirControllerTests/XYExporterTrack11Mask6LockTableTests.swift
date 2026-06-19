import Foundation
import XCTest
@testable import ChoirController

final class XYExporterTrack11Mask6LockTableTests: XCTestCase {
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

    private func exportTemplateURL() -> URL {
        repoRootURL()
            .appendingPathComponent(".release/research/dderuntz-saves3/08a 0.xy")
    }

    private func snapshot(fromCapture name: String) throws -> XYExporter.Track11LockTable {
        let data = try Data(contentsOf: captureURL(name))
        let body = try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](data), trackIndex: 11))
        return try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: body))
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func findSubsequence(in haystack: [UInt8], needle: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for i in 0...(haystack.count - needle.count) {
            if Array(haystack[i..<(i + needle.count)]) == needle {
                return i
            }
        }
        return nil
    }

    private func export(stepLocks: [XYExportStepLockData]) throws -> XYExporter.Track11LockTable {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-exporter-mask6-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: exportTemplateURL(),
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

        let outputData = try Data(contentsOf: output)
        let outputBody = try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](outputData), trackIndex: 11))
        return try XCTUnwrap(XYExporter.inspectTrack11LockTable(in: outputBody))
    }

    private func exportBody(stepLocks: [XYExportStepLockData]) throws -> [UInt8] {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-exporter-mask6-body-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: exportTemplateURL(),
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

        let outputData = try Data(contentsOf: output)
        return try XCTUnwrap(XYExporter.inspectTrackBody(in: [UInt8](outputData), trackIndex: 11))
    }

    private func assertMatchesCapture(
        _ captureName: String,
        stepLocks: [XYExportStepLockData],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let expected = try snapshot(fromCapture: captureName)
        let actual = try export(stepLocks: stepLocks)
        XCTAssertEqual(actual.entries.map(\.slot), expected.entries.map(\.slot), file: file, line: line)
        XCTAssertEqual(
            actual.entries.map { hex($0.bytes) },
            expected.entries.map { hex($0.bytes) },
            file: file,
            line: line
        )
    }

    private func robotsRealValueMask6Locks() -> [XYExportStepLockData] {
        [
            XYExportStepLockData(step: 1, cc2: 89, cc3: 38),
            XYExportStepLockData(step: 4, cc2: 4, cc3: 8),
            XYExportStepLockData(step: 8, cc2: 92, cc3: 121),
            XYExportStepLockData(step: 16, cc2: 89, cc3: 38),
            XYExportStepLockData(step: 17, cc2: 89, cc3: 38),
            XYExportStepLockData(step: 20, cc2: 4, cc3: 8),
            XYExportStepLockData(step: 24, cc2: 92, cc3: 121),
            XYExportStepLockData(step: 29, cc2: 89, cc3: 38),
            XYExportStepLockData(step: 30, cc2: 89, cc3: 38),
            XYExportStepLockData(step: 33, cc2: 89, cc3: 38),
            XYExportStepLockData(step: 36, cc2: 4, cc3: 8),
            XYExportStepLockData(step: 40, cc2: 92, cc3: 121),
            XYExportStepLockData(step: 46, cc2: 89, cc3: 38),
            XYExportStepLockData(step: 49, cc2: 89, cc3: 38),
            XYExportStepLockData(step: 51, cc2: 4, cc3: 38),
            XYExportStepLockData(step: 52, cc2: 4, cc3: 38),
            XYExportStepLockData(step: 55, cc2: 4, cc3: 38),
            XYExportStepLockData(step: 63, cc2: 92, cc3: 121),
            XYExportStepLockData(step: 64, cc2: 89, cc3: 38)
        ]
    }

    func testExporterSynthesizesMask6SingleStep1() throws {
        try assertMatchesCapture(
            "08b 1.xy",
            stepLocks: [XYExportStepLockData(step: 1, cc2: 32, cc3: 16)]
        )
    }

    func testExporterSynthesizesMask6SingleStep30() throws {
        try assertMatchesCapture(
            "08b 9.xy",
            stepLocks: [XYExportStepLockData(step: 30, cc2: 32, cc3: 16)]
        )
    }

    func testExporterSynthesizesMask6SingleStep1VariantValues() throws {
        try assertMatchesCapture(
            "08b 27.xy",
            stepLocks: [XYExportStepLockData(step: 1, cc2: 89, cc3: 38)]
        )
    }

    func testExporterSynthesizesMask6SingleStep8VariantValues() throws {
        try assertMatchesCapture(
            "08b 28.xy",
            stepLocks: [XYExportStepLockData(step: 8, cc2: 92, cc3: 121)]
        )
    }

    func testExporterSynthesizesMask6SingleStep4VariantValues() throws {
        try assertMatchesCapture(
            "08b 29.xy",
            stepLocks: [XYExportStepLockData(step: 4, cc2: 4, cc3: 8)]
        )
    }

    func testExporterSynthesizesMask6PairStep1And4() throws {
        try assertMatchesCapture(
            "08b 20.xy",
            stepLocks: [
                XYExportStepLockData(step: 1, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 4, cc2: 32, cc3: 16)
            ]
        )
    }

    func testExporterSynthesizesMask6GroupStep29To36() throws {
        try assertMatchesCapture(
            "08b 23.xy",
            stepLocks: [
                XYExportStepLockData(step: 29, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 30, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 33, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 36, cc2: 32, cc3: 16)
            ]
        )
    }

    func testExporterSynthesizesMask6FullRobotsTopology() throws {
        try assertMatchesCapture(
            "08b 26.xy",
            stepLocks: [
                XYExportStepLockData(step: 1, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 4, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 8, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 16, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 17, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 20, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 24, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 29, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 30, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 33, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 36, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 40, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 46, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 49, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 51, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 52, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 55, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 63, cc2: 32, cc3: 16),
                XYExportStepLockData(step: 64, cc2: 32, cc3: 16)
            ]
        )
    }

    func testExporterUsesCapturedSuffixForFullMask6Topology() throws {
        let body = try exportBody(stepLocks: [
            XYExportStepLockData(step: 1, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 4, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 8, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 16, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 17, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 20, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 24, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 29, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 30, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 33, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 36, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 40, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 46, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 49, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 51, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 52, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 55, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 63, cc2: 32, cc3: 16),
            XYExportStepLockData(step: 64, cc2: 32, cc3: 16)
        ])
        let marker: [UInt8] = [0xFF, 0xFF, 0x01, 0x7F, 0x00, 0x00]
        let markerOffset = findSubsequence(in: body, needle: marker)
        XCTAssertEqual(markerOffset, 376)
    }

    func testExporterSynthesizesMask6SupersetPlusStep2() throws {
        var locks = robotsRealValueMask6Locks()
        locks.append(XYExportStepLockData(step: 2, cc2: 32, cc3: 16))
        try assertMatchesCapture("08b 31.xy", stepLocks: locks)
    }

    func testExporterSynthesizesMask6SupersetPlusStep2AndStep6() throws {
        var locks = robotsRealValueMask6Locks()
        locks.append(XYExportStepLockData(step: 2, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 6, cc2: 32, cc3: 16))
        try assertMatchesCapture("08b 32.xy", stepLocks: locks)
    }

    func testExporterSynthesizesMask6SupersetPlusStep2AndStep6AndStep7() throws {
        var locks = robotsRealValueMask6Locks()
        locks.append(XYExportStepLockData(step: 2, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 6, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 7, cc2: 32, cc3: 16))
        try assertMatchesCapture("08b 33.xy", stepLocks: locks)
    }

    func testExporterSynthesizesMask6RobotsPlusStep7Only() throws {
        var locks = robotsRealValueMask6Locks()
        locks.append(XYExportStepLockData(step: 7, cc2: 32, cc3: 16))
        try assertMatchesCapture("08b 34.xy", stepLocks: locks)
    }

    func testExporterSynthesizesMask6RobotsPlusStep7AndStep11() throws {
        var locks = robotsRealValueMask6Locks()
        locks.append(XYExportStepLockData(step: 7, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 11, cc2: 32, cc3: 16))
        try assertMatchesCapture("08b 35.xy", stepLocks: locks)
    }

    func testExporterSynthesizesMask6RobotsPlusStep2AndStep7AndStep11() throws {
        var locks = robotsRealValueMask6Locks()
        locks.append(XYExportStepLockData(step: 2, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 7, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 11, cc2: 32, cc3: 16))
        try assertMatchesCapture("08b 36.xy", stepLocks: locks)
    }

    func testExporterSynthesizesMask6RobotsPlusStep2AndStep6AndStep7AndStep11() throws {
        var locks = robotsRealValueMask6Locks()
        locks.append(XYExportStepLockData(step: 2, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 6, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 7, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 11, cc2: 32, cc3: 16))
        try assertMatchesCapture("08b 37.xy", stepLocks: locks)
    }

    func testExporterSynthesizesMask6RobotsPlusStep2AndStep6AndStep7AndStep11AndStep14() throws {
        var locks = robotsRealValueMask6Locks()
        locks.append(XYExportStepLockData(step: 2, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 6, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 7, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 11, cc2: 32, cc3: 16))
        locks.append(XYExportStepLockData(step: 14, cc2: 32, cc3: 16))
        try assertMatchesCapture("08b 38.xy", stepLocks: locks)
    }

}
