import XCTest
@testable import ChoirController

final class XYExporterImagePathTests: XCTestCase {
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

    func testEmbeddedSeedStartsWithCleanTrack11() throws {
        let project = try XYImageProject(data: try XYProjectSeed.data())
        let track11 = try project.trackStart(11)

        XCTAssertEqual(try project.notes(track: 11), [])
        XCTAssertEqual(project.image[track11 + 0x304F], 0)
        XCTAssertEqual(
            (0..<64).filter { project.image[track11 + 0x2C4F + 8 * $0] != 0 },
            []
        )
    }

    func testDecodedImageExportWritesNotesTempoAndLocks() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-image-export-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: try requireFixture(".release/research/dderuntz-saves3/08a 0.xy"),
            outputURL: outputURL,
            trackIndex: 11,
            notes: [
                XYExportNoteData(
                    step: 3,
                    note: 60,
                    velocity: 100,
                    gateTicks: 960,
                    tickOffset: 0,
                    cc2: 16
                )
            ],
            tempoTenths: 1_000,
            grooveType: 4
        )

        let data = [UInt8](try Data(contentsOf: outputURL))
        let rleProject = try XYRLECodec.decodeProject(data)
        XCTAssertEqual(rleProject.image[0], 0xE8)
        XCTAssertEqual(rleProject.image[1], 0x03)
        XCTAssertEqual(rleProject.image[3], 0x04)
        XCTAssertEqual(try XYRLECodec.encodeProject(header: rleProject.header, image: rleProject.image), data)

        let imageProject = try XYImageProject(data: data)
        XCTAssertEqual(
            try imageProject.notes(track: 11),
            [XYImageNote(tick: 960, gate: 960, note: 60, velocity: 100, flags: 0)]
        )

        let track11 = try imageProject.trackStart(11)
        let lockOffset = track11 + 0x025E + 84 * 2 + 2
        XCTAssertEqual(Array(imageProject.image[lockOffset..<(lockOffset + 2)]), [0x29, 0x10])
        XCTAssertEqual(imageProject.image[track11 + 0x2C4F + 8 * 2], 0x02)
        XCTAssertEqual(imageProject.image[track11 + 0x304F], 0x02)
    }

    func testDecodedImageExportExtendsPatternForExplicitLockStep() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-image-export-lock-step-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: try requireFixture(".release/research/dderuntz-saves3/08a 0.xy"),
            outputURL: outputURL,
            trackIndex: 11,
            notes: [
                XYExportNoteData(step: 1, note: 60, velocity: 100, gateTicks: 480, tickOffset: 0)
            ],
            stepLocks: [
                XYExportStepLockData(step: 17, cc2: 16)
            ],
            tempoTenths: 1_000,
            grooveType: 0
        )

        let imageProject = try XYImageProject(data: [UInt8](try Data(contentsOf: outputURL)))
        let track11 = try imageProject.trackStart(11)
        XCTAssertEqual(imageProject.image[track11 + 0x01], 32)
        XCTAssertEqual(imageProject.image[track11 + 0x2C4F + 8 * 16], 0x02)
        XCTAssertEqual(imageProject.image[track11 + 0x304F], 0x02)
    }

    func testDecodedImageExportPreservesSameStepPolyphony() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-image-export-polyphony-\(UUID().uuidString).xy")

        try XYExporter.export(
            templateURL: try requireFixture(".release/research/dderuntz-saves3/08a 0.xy"),
            outputURL: outputURL,
            trackIndex: 11,
            notes: [
                XYExportNoteData(step: 1, note: 60, velocity: 100, gateTicks: 720, tickOffset: 0),
                XYExportNoteData(step: 1, note: 64, velocity: 96, gateTicks: 720, tickOffset: 0),
                XYExportNoteData(step: 1, note: 67, velocity: 92, gateTicks: 720, tickOffset: 0)
            ],
            stepLocks: [
                XYExportStepLockData(step: 1, cc2: 89, cc3: 38)
            ],
            tempoTenths: 1_000,
            grooveType: 0
        )

        let notes = try XYImageProject(data: [UInt8](try Data(contentsOf: outputURL))).notes(track: 11)
        XCTAssertEqual(
            notes,
            [
                XYImageNote(tick: 0, gate: 720, note: 60, velocity: 100, flags: 0),
                XYImageNote(tick: 0, gate: 720, note: 64, velocity: 96, flags: 0),
                XYImageNote(tick: 0, gate: 720, note: 67, velocity: 92, flags: 0)
            ]
        )
    }

    @MainActor
    func testSequencerExportWritesLockOnlyPreSendAndDefaultResets() throws {
        let oldPreSendEnabled = UserDefaults.standard.object(forKey: "ccPreSendEnabled")
        let oldPreSendDelay = UserDefaults.standard.object(forKey: "ccPreSendDelayMs")
        UserDefaults.standard.set(true, forKey: "ccPreSendEnabled")
        UserDefaults.standard.set(185.0, forKey: "ccPreSendDelayMs")
        defer {
            if let oldPreSendEnabled {
                UserDefaults.standard.set(oldPreSendEnabled, forKey: "ccPreSendEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "ccPreSendEnabled")
            }
            if let oldPreSendDelay {
                UserDefaults.standard.set(oldPreSendDelay, forKey: "ccPreSendDelayMs")
            } else {
                UserDefaults.standard.removeObject(forKey: "ccPreSendDelayMs")
            }
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy-image-export-presend-\(UUID().uuidString).xy")
        let model = SequencerModel()
        model.tempo = 100
        model.notes = [
            SequencerNote(
                pitch: 60,
                startBeat: 0,
                duration: 1,
                velocity: 100,
                consonant: 89,
                vowel: 38,
                vibrato: 64,
                reverb: 32
            ),
            SequencerNote(
                pitch: 64,
                startBeat: 1,
                duration: 1,
                velocity: 100,
                consonant: 127,
                vowel: 0,
                vibrato: 64,
                reverb: 32
            )
        ]

        try model.exportXY(to: outputURL)

        let project = try XYImageProject(contentsOf: outputURL)
        let track11 = try project.trackStart(11)
        XCTAssertEqual(try project.notes(track: 11).count, 2)
        XCTAssertEqual(project.image[track11 + 0x2C4F], 0x06)
        XCTAssertEqual(project.image[track11 + 0x2C4F + 8], 0x06)
        XCTAssertEqual(project.image[track11 + 0x2C4F + 8 * 4], 0x06)

        let preSendRow = track11 + 0x025E + 84
        XCTAssertEqual(project.image[preSendRow + 3], 127)
        XCTAssertEqual(project.image[preSendRow + 5], 0)

        let noteOnRow = track11 + 0x025E + 84 * 4
        XCTAssertEqual(project.image[noteOnRow + 3], 127)
        XCTAssertEqual(project.image[noteOnRow + 5], 0)
    }

    func testGenerateDecodedImageDeviceProbeBatch() throws {
        let outDir = repoRootURL()
            .appendingPathComponent("export")
            .appendingPathComponent("decoded-image-probes")
        let fm = FileManager.default
        try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        struct Probe {
            let filename: String
            let template: String
            let note: XYExportNoteData
            let description: String
        }

        let probes = [
            Probe(
                filename: "image-00-step3-note-cc2.xy",
                template: ".release/research/dderuntz-saves3/08a 0.xy",
                note: XYExportNoteData(step: 3, note: 60, velocity: 100, gateTicks: 960, tickOffset: 0, cc2: 16),
                description: "Decoded-image writer: one C4-ish note on step 3, CC2=16 lock."
            ),
            Probe(
                filename: "image-01-step3-note-all4.xy",
                template: ".release/research/dderuntz-saves3/08a 0.xy",
                note: XYExportNoteData(step: 3, note: 60, velocity: 100, gateTicks: 960, tickOffset: 0, cc1: 64, cc2: 32, cc3: 16, cc4: 8),
                description: "Decoded-image writer: one note on step 3, CC1/2/3/4 locks."
            ),
            Probe(
                filename: "image-02-step1-note-mask6.xy",
                template: ".release/research/dderuntz-saves08b/08b 0.xy",
                note: XYExportNoteData(step: 1, note: 60, velocity: 100, gateTicks: 960, tickOffset: 0, cc2: 32, cc3: 16),
                description: "Decoded-image writer: one note on step 1, CC2+CC3 mask-6 lock."
            )
        ]

        var manifest = [
            "# Decoded Image OP-XY Device Probes",
            "",
            "Generated by `XYExporterImagePathTests`.",
            "These are decoded-image writer probes, not production exports.",
            ""
        ]

        for probe in probes {
            let outputURL = outDir.appendingPathComponent(probe.filename)
            try XYExporter.export(
                templateURL: try requireFixture(probe.template),
                outputURL: outputURL,
                trackIndex: 11,
                notes: [probe.note],
                tempoTenths: 1_000,
                grooveType: 0
            )
            XCTAssertTrue(fm.fileExists(atPath: outputURL.path))
            manifest.append("- `\(probe.filename)`: \(probe.description)")
        }

        let chordURL = outDir.appendingPathComponent("image-03-step1-c-major-chord.xy")
        try XYExporter.export(
            templateURL: try requireFixture(".release/research/dderuntz-saves08b/08b 0.xy"),
            outputURL: chordURL,
            trackIndex: 11,
            notes: [
                XYExportNoteData(step: 1, note: 60, velocity: 100, gateTicks: 960, tickOffset: 0),
                XYExportNoteData(step: 1, note: 64, velocity: 100, gateTicks: 960, tickOffset: 0),
                XYExportNoteData(step: 1, note: 67, velocity: 100, gateTicks: 960, tickOffset: 0)
            ],
            stepLocks: [
                XYExportStepLockData(step: 1, cc2: 32, cc3: 16)
            ],
            tempoTenths: 1_000,
            grooveType: 0
        )
        XCTAssertEqual(try XYImageProject(contentsOf: chordURL).notes(track: 11).count, 3)
        manifest.append("- `image-03-step1-c-major-chord.xy`: Decoded-image writer: C major triad on step 1, each note 2 steps, shared CC2+CC3 lock.")

        if fm.fileExists(atPath: outDir.appendingPathComponent("Robots-image-export.xy").path) {
            manifest.append("- `Robots-image-export.xy`: Decoded-image export of bundled Robots.choir with 27 notes and 19 CC2+CC3 phoneme lock steps.")
        }

        try manifest.joined(separator: "\n")
            .write(to: outDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func testGenerateDecodedImageRobotsExport() throws {
        let outDir = repoRootURL()
            .appendingPathComponent("export")
            .appendingPathComponent("decoded-image-probes")
        let fm = FileManager.default
        if !fm.fileExists(atPath: outDir.path) {
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        }

        let outputURL = outDir.appendingPathComponent("Robots-image-export.xy")
        let model = SequencerModel()
        try model.load(from: fixtureURL("Sources/ChoirController/Robots.choir"))
        try model.exportXY(to: outputURL)

        let project = try XYImageProject(contentsOf: outputURL)
        let notes = try project.notes(track: 11)
        let track11 = try project.trackStart(11)
        let expectedLockSteps = [1, 4, 8, 16, 17, 20, 24, 29, 30, 33, 36, 40, 46, 49, 51, 52, 55, 63, 64]

        XCTAssertEqual(notes.count, 27)
        XCTAssertEqual(project.image[track11 + 0x01], 64)
        XCTAssertEqual(project.image[track11 + 0x304F], 0x06)
        XCTAssertEqual(
            expectedLockSteps.filter { project.image[track11 + 0x2C4F + 8 * ($0 - 1)] == 0x06 },
            expectedLockSteps
        )

        let readmeURL = outDir.appendingPathComponent("README.md")
        var readme = (try? String(contentsOf: readmeURL, encoding: .utf8)) ?? "# Decoded Image OP-XY Device Probes\n"
        if !readme.contains("Robots-image-export.xy") {
            readme += "\n- `Robots-image-export.xy`: Decoded-image export of bundled Robots.choir with 27 notes and 19 CC2+CC3 phoneme lock steps.\n"
            try readme.write(to: readmeURL, atomically: true, encoding: .utf8)
        }
    }
}
