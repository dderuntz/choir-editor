import Foundation
import XCTest
@testable import ChoirController

final class XYExporterRobotsNoLocksDiagnosticsTests: XCTestCase {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @MainActor
    func testGenerateRobotsExportWithLocksDisabled() throws {
        let repo = repoRootURL()
        let robotsURL = repo
            .appendingPathComponent("Sources/ChoirController/Robots.choir")
        let outDir = repo
            .appendingPathComponent("export")
            .appendingPathComponent("robots-debug")
        let outXY = outDir.appendingPathComponent("Robots-app-export-nolocks.xy")

        let fm = FileManager.default
        if !fm.fileExists(atPath: outDir.path) {
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        }

        setenv("CHOIR_XY_EXPORT_DEBUG", "1", 1)
        setenv("CHOIR_XY_DISABLE_LOCKS", "1", 1)
        defer {
            unsetenv("CHOIR_XY_EXPORT_DEBUG")
            unsetenv("CHOIR_XY_DISABLE_LOCKS")
        }

        let model = SequencerModel()
        try model.load(from: robotsURL)
        try model.exportXY(to: outXY)

        let debugURL = outXY.deletingPathExtension().appendingPathExtension("export-debug.txt")
        XCTAssertTrue(fm.fileExists(atPath: outXY.path), "missing exported xy file")
        XCTAssertTrue(fm.fileExists(atPath: debugURL.path), "missing export debug sidecar")

        let debugText = try String(contentsOf: debugURL, encoding: .utf8)
        let lines = debugText.split(separator: "\n").map(String.init)
        let disabledLine = lines.first { $0.hasPrefix("locks_disabled=") } ?? ""
        XCTAssertEqual(disabledLine, "locks_disabled=1")
        let exportedCountLine = lines.first { $0.hasPrefix("exported_lock_entries=") } ?? ""
        XCTAssertEqual(exportedCountLine, "exported_lock_entries=0")
    }
}
