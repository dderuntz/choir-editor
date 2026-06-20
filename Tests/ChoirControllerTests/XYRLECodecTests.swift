import XCTest
@testable import ChoirController

final class XYRLECodecTests: XCTestCase {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func fixtureURL(_ path: String) -> URL {
        repoRootURL().appendingPathComponent(path)
    }

    private func assertBytes(
        _ actual: [UInt8],
        _ expected: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    func testSimpleRuns() throws {
        assertBytes(XYRLECodec.encode([0x00, 0x00, 0x00]), [0x00, 0x00, 0x01])
        assertBytes(try XYRLECodec.decode([0x00, 0x00, 0x01]), [0x00, 0x00, 0x00])
        assertBytes(XYRLECodec.encode([0x05]), [0x05])
        assertBytes(XYRLECodec.encode([0x05, 0x05]), [0x05, 0x05, 0x00])
        assertBytes(try XYRLECodec.decode([0x05, 0x05, 0x00]), [0x05, 0x05])
    }

    func testGateTokenDecodesToLittleEndianU32_240() throws {
        assertBytes(
            try XYRLECodec.decode([0xf0, 0x00, 0x00, 0x01]),
            [0xf0, 0x00, 0x00, 0x00]
        )
    }

    func testLongRunChunking() throws {
        let raw = [UInt8](repeating: 0x00, count: 600)
        let encoded = XYRLECodec.encode(raw)
        assertBytes(
            encoded,
            [0x00, 0x00, 0xff] + [0x00, 0x00, 0xff] + [0x00, 0x00, 0x54]
        )
        assertBytes(try XYRLECodec.decode(encoded), raw)
    }

    func testPairStateResetsAfterExtension() throws {
        assertBytes(
            try XYRLECodec.decode([0x08, 0x08, 0x02, 0x08, 0x09]),
            [UInt8](repeating: 0x08, count: 5) + [0x09]
        )
    }

    func testTruncatedExtensionThrows() {
        XCTAssertThrowsError(try XYRLECodec.decode([0x00, 0x00])) { error in
            XCTAssertEqual(error as? XYRLECodecError, .truncatedExtension(index: 2))
        }
    }

    func testFuzzRoundTrip() throws {
        var generator = SeededGenerator(seed: 7)
        let choices: [UInt8] = [0, 0, 0, 1, 2, 0xff]

        for _ in 0..<500 {
            let count = Int.random(in: 0...600, using: &generator)
            let raw = (0..<count).map { _ in choices.randomElement(using: &generator)! }
            XCTAssertEqual(try XYRLECodec.decode(XYRLECodec.encode(raw)), raw)
        }
    }

    func testLocalCaptureRoundTripsByteExact() throws {
        let fixturePaths = [
            ".release/research/dderuntz-saves2/05a.xy",
            ".release/research/dderuntz-saves3/08a 0.xy",
            ".release/research/dderuntz-saves3/08a 51.xy",
            ".release/research/dderuntz-saves08b/08b 0.xy",
            ".release/research/dderuntz-saves08b/08b 54.xy"
        ]

        for path in fixturePaths {
            let url = fixtureURL(path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw XCTSkip("missing local research fixture: \(path)")
            }

            let data = [UInt8](try Data(contentsOf: url))
            let project = try XYRLECodec.decodeProject(data)
            let rebuilt = try XYRLECodec.encodeProject(header: project.header, image: project.image)
            XCTAssertEqual(rebuilt, data, path)
            XCTAssertGreaterThan(project.image.count, data.count, path)
        }
    }

    func testExporterOutputIsCanonicalRLE() throws {
        let templateURL = fixtureURL(".release/research/dderuntz-saves2/05a.xy")
        guard FileManager.default.fileExists(atPath: templateURL.path) else {
            throw XCTSkip("missing local research fixture: \(templateURL.path)")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-rle-canonical-export-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: templateURL,
            outputURL: outputURL,
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
            stepLocks: [XYExportStepLockData(step: 3, cc2: 16)],
            tempoTenths: 1000,
            grooveType: 0
        )

        let data = [UInt8](try Data(contentsOf: outputURL))
        let project = try XYRLECodec.decodeProject(data)
        XCTAssertEqual(try XYRLECodec.encodeProject(header: project.header, image: project.image), data)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
