import XCTest
@testable import ChoirController

final class XYImageProjectTests: XCTestCase {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func fixtureURL(_ path: String) -> URL {
        repoRootURL().appendingPathComponent(path)
    }

    private func requireFixture(_ path: String) throws -> URL {
        let url = fixtureURL(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("missing local research fixture: \(path)")
        }
        return url
    }

    private func imageBytes(_ path: String) throws -> [UInt8] {
        let data = [UInt8](try Data(contentsOf: try requireFixture(path)))
        return try XYRLECodec.decodeProject(data).image
    }

    private func assertImagesEqual(
        _ actual: [UInt8],
        _ expected: [UInt8],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard actual != expected else { return }
        let limit = min(actual.count, expected.count)
        let firstDiff = (0..<limit).first { actual[$0] != expected[$0] }
        XCTFail(
            "image mismatch: actual.count=\(actual.count), expected.count=\(expected.count), firstDiff=\(firstDiff.map { String(format: "0x%X actual=%02X expected=%02X", $0, actual[$0], expected[$0]) } ?? "none")",
            file: file,
            line: line
        )
    }

    func testScansTrackStartsAndNotes() throws {
        let project = try XYImageProject(contentsOf: try requireFixture(".release/research/dderuntz-saves3/08a 0.xy"))

        XCTAssertEqual(try project.trackStart(1), 0x0D79)
        XCTAssertEqual(try project.trackStart(11), 0x2C7C1)
        XCTAssertEqual(try project.notes(track: 11), [])
    }

    func testTempoAndGrooveWriteInDecodedImage() throws {
        var project = try XYImageProject(contentsOf: try requireFixture(".release/research/dderuntz-saves3/08a 0.xy"))

        try project.setTempoTenths(1_000)
        project.setGrooveType(4)

        XCTAssertEqual(project.image[0], 0xE8)
        XCTAssertEqual(project.image[1], 0x03)
        XCTAssertEqual(project.image[3], 0x04)
        XCTAssertEqual(try XYRLECodec.decodeProject(try project.encodedBytes()).image, project.image)
    }

    func testAddsTrack11NoteInDecodedVector() throws {
        var project = try XYImageProject(contentsOf: try requireFixture(".release/research/dderuntz-saves3/08a 0.xy"))

        try project.addNote(track: 11, step: 5, note: 60, velocity: 100, gateTicks: 960)

        let notes = try project.notes(track: 11)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0], XYImageNote(tick: 1_920, gate: 960, note: 60, velocity: 100, flags: 0))
        XCTAssertEqual(try project.trackStart(12), 0x30DA1)
        XCTAssertEqual(try XYRLECodec.decodeProject(try project.encodedBytes()).image, project.image)
    }

    func testClearsExistingTrack11Notes() throws {
        var project = try XYImageProject(contentsOf: try requireFixture(".release/research/dderuntz-saves2/04 c.xy"))
        XCTAssertGreaterThan(try project.notes(track: 11).count, 0)

        try project.clearNotes(track: 11)

        XCTAssertEqual(try project.notes(track: 11), [])
        XCTAssertEqual(try XYRLECodec.decodeProject(try project.encodedBytes()).image, project.image)
    }

    func testReproduces08aStep1CC1LockInDecodedImage() throws {
        var project = try XYImageProject(contentsOf: try requireFixture(".release/research/dderuntz-saves3/08a 0.xy"))

        try project.setTrack11Locks([XYTrack11CCLock(step: 1, cc1: 16)])

        assertImagesEqual(project.image, try imageBytes(".release/research/dderuntz-saves3/08a 1.xy"))
    }

    func testReproduces08aStep3CC2LockInDecodedImage() throws {
        var project = try XYImageProject(contentsOf: try requireFixture(".release/research/dderuntz-saves3/08a 0.xy"))

        try project.setTrack11Locks([XYTrack11CCLock(step: 3, cc2: 16)])

        assertImagesEqual(project.image, try imageBytes(".release/research/dderuntz-saves3/08a 19.xy"))
    }

    func testReproduces08aStep3AllFourCCLockInDecodedImage() throws {
        var project = try XYImageProject(contentsOf: try requireFixture(".release/research/dderuntz-saves3/08a 0.xy"))

        try project.setTrack11Locks([XYTrack11CCLock(step: 3, cc1: 64, cc2: 32, cc3: 16, cc4: 8)])

        assertImagesEqual(project.image, try imageBytes(".release/research/dderuntz-saves3/08a 41.xy"))
    }

    func testReproduces08bStep1CC2CC3Mask6LockInDecodedImage() throws {
        var project = try XYImageProject(contentsOf: try requireFixture(".release/research/dderuntz-saves08b/08b 0.xy"))

        try project.setTrack11Locks([XYTrack11CCLock(step: 1, cc2: 32, cc3: 16)])

        assertImagesEqual(project.image, try imageBytes(".release/research/dderuntz-saves08b/08b 1.xy"))
    }

    func testTrack11MasterFlagAggregatesMixedLaneLocks() throws {
        var project = try XYImageProject(contentsOf: try requireFixture(".release/research/dderuntz-saves3/08a 0.xy"))

        try project.setTrack11Locks([
            XYTrack11CCLock(step: 1, cc1: 16),
            XYTrack11CCLock(step: 3, cc2: 16)
        ])

        let track11 = try project.trackStart(11)
        XCTAssertEqual(project.image[track11 + 0x2C4F], 0x01)
        XCTAssertEqual(project.image[track11 + 0x2C4F + 8 * 2], 0x02)
        XCTAssertEqual(project.image[track11 + 0x304F], 0x03)
    }
}
