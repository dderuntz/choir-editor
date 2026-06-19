import Foundation
import XCTest
@testable import ChoirController

final class XYExporterRobotsDiagnosticsTests: XCTestCase {
    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @MainActor
    func testGenerateRobotsExportWithDebugSidecar() throws {
        let repo = repoRootURL()
        let robotsURL = repo
            .appendingPathComponent("Sources/ChoirController/Robots.choir")
        let outDir = repo
            .appendingPathComponent("export")
            .appendingPathComponent("robots-debug")
        let outXY = outDir.appendingPathComponent("Robots-app-export.xy")

        let fm = FileManager.default
        if !fm.fileExists(atPath: outDir.path) {
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        }

        setenv("CHOIR_XY_EXPORT_DEBUG", "1", 1)
        defer { unsetenv("CHOIR_XY_EXPORT_DEBUG") }

        let model = SequencerModel()
        try model.load(from: robotsURL)
        try model.exportXY(to: outXY)

        let debugURL = outXY.deletingPathExtension().appendingPathExtension("export-debug.txt")
        XCTAssertTrue(fm.fileExists(atPath: outXY.path), "missing exported xy file")
        XCTAssertTrue(fm.fileExists(atPath: debugURL.path), "missing export debug sidecar")

        let debugText = try String(contentsOf: debugURL, encoding: .utf8)
        let lines = debugText.split(separator: "\n").map(String.init)
        let exportedCountLine = lines.first { $0.hasPrefix("exported_lock_entries=") }
        let exportedCount = exportedCountLine
            .flatMap { Int($0.replacingOccurrences(of: "exported_lock_entries=", with: "")) } ?? -1
        XCTAssertGreaterThan(exportedCount, 0, "robots export still wrote no lock entries")

        let requestedTopologyLine = lines.first { $0.hasPrefix("requested_topology=") } ?? ""
        XCTAssertTrue(
            requestedTopologyLine.contains("1:6|4:6|8:6"),
            "unexpected requested topology in debug sidecar"
        )
    }
}
