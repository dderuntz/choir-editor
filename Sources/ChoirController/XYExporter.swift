import Foundation

struct XYExportNoteData {
    let step: Int
    let note: Int
    let velocity: Int
    let gateTicks: Int
    let tickOffset: Int
    let cc1: Int?
    let cc2: Int?
    let cc3: Int?
    let cc4: Int?

    init(
        step: Int,
        note: Int,
        velocity: Int,
        gateTicks: Int,
        tickOffset: Int,
        cc1: Int? = nil,
        cc2: Int? = nil,
        cc3: Int? = nil,
        cc4: Int? = nil
    ) {
        self.step = step
        self.note = note
        self.velocity = velocity
        self.gateTicks = gateTicks
        self.tickOffset = tickOffset
        self.cc1 = cc1
        self.cc2 = cc2
        self.cc3 = cc3
        self.cc4 = cc4
    }
}

struct XYExportStepLockData {
    let step: Int
    let cc1: Int?
    let cc2: Int?
    let cc3: Int?
    let cc4: Int?

    init(
        step: Int,
        cc1: Int? = nil,
        cc2: Int? = nil,
        cc3: Int? = nil,
        cc4: Int? = nil
    ) {
        self.step = step
        self.cc1 = cc1
        self.cc2 = cc2
        self.cc3 = cc3
        self.cc4 = cc4
    }
}

enum XYExporterError: LocalizedError {
    case invalidTemplate(String)
    case invalidTrackIndex(Int)
    case invalidNote(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidTemplate(let message):
            return "Invalid OP-XY template: \(message)"
        case .invalidTrackIndex(let index):
            return "Invalid OP-XY track index \(index)."
        case .invalidNote(let message):
            return "Invalid note data: \(message)"
        case .unsupported(let message):
            return "Unsupported OP-XY export case: \(message)"
        }
    }
}

enum XYExporter {
    private static let midiTrackIndex = 11

    private struct EventNote {
        let step: Int
        let note: Int
        let velocity: Int
        let tickOffset: Int
        let gateTicks: Int
        let cc1: Int?
        let cc2: Int?
        let cc3: Int?
        let cc4: Int?
    }

    private struct Track11StepLock {
        let step: Int
        var cc1: Int?
        var cc2: Int?
        var cc3: Int?
        var cc4: Int?

        var hasAnyLane: Bool {
            cc1 != nil || cc2 != nil || cc3 != nil || cc4 != nil
        }
    }

    static func export(
        templateURL: URL,
        outputURL: URL,
        trackIndex: Int = midiTrackIndex,
        notes: [XYExportNoteData],
        stepLocks: [XYExportStepLockData] = [],
        tempoTenths: Int,
        grooveType: Int
    ) throws {
        let templateData = [UInt8](try Data(contentsOf: templateURL))
        try export(
            templateData: templateData,
            outputURL: outputURL,
            trackIndex: trackIndex,
            notes: notes,
            stepLocks: stepLocks,
            tempoTenths: tempoTenths,
            grooveType: grooveType
        )
    }

    static func export(
        templateData: [UInt8],
        outputURL: URL,
        trackIndex: Int = midiTrackIndex,
        notes: [XYExportNoteData],
        stepLocks: [XYExportStepLockData] = [],
        tempoTenths: Int,
        grooveType: Int
    ) throws {
        guard (1...XYImageProject.trackCount).contains(trackIndex) else {
            throw XYExporterError.invalidTrackIndex(trackIndex)
        }
        guard !notes.isEmpty else {
            throw XYExporterError.invalidNote("at least one note is required")
        }

        let eventNotes = try buildEventNotes(from: notes)
        let explicitLocks = try buildTrack11StepLocks(from: stepLocks)
        let noteLocks = try track11StepLocksFromNotes(eventNotes)
        let mergedLocks = try mergedTrack11StepLocks(noteDerived: noteLocks, explicit: explicitLocks)

        guard trackIndex == midiTrackIndex || mergedLocks.isEmpty else {
            throw XYExporterError.unsupported("decoded-image CC locks are implemented for Track 11 only")
        }

        do {
            var project = try XYImageProject(data: templateData)
            try project.clearNotes(track: trackIndex)
            try project.setPatternSteps(track: trackIndex, steps: barsForPattern(eventNotes, locks: mergedLocks) * 16)
            try project.setTempoTenths(tempoTenths)
            project.setGrooveType(grooveType)

            for note in eventNotes {
                try project.addNote(
                    track: trackIndex,
                    step: note.step,
                    note: note.note,
                    velocity: note.velocity,
                    gateTicks: note.gateTicks,
                    tickOffset: note.tickOffset
                )
            }

            if trackIndex == midiTrackIndex {
                try project.setTrack11Locks(
                    mergedLocks.map {
                        XYTrack11CCLock(
                            step: $0.step,
                            cc1: $0.cc1.map(UInt8.init),
                            cc2: $0.cc2.map(UInt8.init),
                            cc3: $0.cc3.map(UInt8.init),
                            cc4: $0.cc4.map(UInt8.init)
                        )
                    }
                )
            }

            try Data(project.encodedBytes()).write(to: outputURL, options: .atomic)
        } catch let error as XYExporterError {
            throw error
        } catch {
            throw XYExporterError.invalidTemplate("decoded-image export failed: \(error.localizedDescription)")
        }
    }

    private static func buildEventNotes(from notes: [XYExportNoteData]) throws -> [EventNote] {
        try notes.enumerated().map { idx, note in
            guard (1...64).contains(note.step) else {
                throw XYExporterError.unsupported(
                    "notes[\(idx)].step=\(note.step) exceeds single-pattern support (64 steps)"
                )
            }
            guard (0...127).contains(note.note) else {
                throw XYExporterError.invalidNote("notes[\(idx)].note must be in [0,127]")
            }
            guard (0...127).contains(note.velocity) else {
                throw XYExporterError.invalidNote("notes[\(idx)].velocity must be in [0,127]")
            }
            guard note.tickOffset >= 0 else {
                throw XYExporterError.invalidNote("notes[\(idx)].tickOffset must be >= 0")
            }
            guard note.gateTicks >= 0 else {
                throw XYExporterError.invalidNote("notes[\(idx)].gateTicks must be >= 0")
            }
            _ = try normalizedTrack11StepLock(
                step: note.step,
                cc1: note.cc1,
                cc2: note.cc2,
                cc3: note.cc3,
                cc4: note.cc4,
                where: "notes[\(idx)]"
            )

            return EventNote(
                step: note.step,
                note: note.note,
                velocity: note.velocity,
                tickOffset: note.tickOffset,
                gateTicks: note.gateTicks,
                cc1: note.cc1,
                cc2: note.cc2,
                cc3: note.cc3,
                cc4: note.cc4
            )
        }
    }

    private static func buildTrack11StepLocks(from stepLocks: [XYExportStepLockData]) throws -> [Track11StepLock] {
        var byStep: [Int: Track11StepLock] = [:]

        for (idx, lock) in stepLocks.enumerated() {
            guard (1...64).contains(lock.step) else {
                throw XYExporterError.unsupported(
                    "stepLocks[\(idx)].step=\(lock.step) exceeds single-pattern support (64 steps)"
                )
            }

            let normalized = try normalizedTrack11StepLock(
                step: lock.step,
                cc1: lock.cc1,
                cc2: lock.cc2,
                cc3: lock.cc3,
                cc4: lock.cc4,
                where: "stepLocks[\(idx)]"
            )
            guard normalized.hasAnyLane else { continue }
            try merge(normalized, into: &byStep)
        }

        return byStep.values.sorted { $0.step < $1.step }
    }

    private static func track11StepLocksFromNotes(_ notes: [EventNote]) throws -> [Track11StepLock] {
        var byStep: [Int: Track11StepLock] = [:]

        for (idx, note) in notes.enumerated() {
            let lock = try normalizedTrack11StepLock(
                step: note.step,
                cc1: note.cc1,
                cc2: note.cc2,
                cc3: note.cc3,
                cc4: note.cc4,
                where: "notes[\(idx)]"
            )
            guard lock.hasAnyLane else { continue }
            try merge(lock, into: &byStep)
        }

        return byStep.values.sorted { $0.step < $1.step }
    }

    private static func mergedTrack11StepLocks(
        noteDerived: [Track11StepLock],
        explicit: [Track11StepLock]
    ) throws -> [Track11StepLock] {
        var byStep: [Int: Track11StepLock] = [:]

        for lock in noteDerived {
            try merge(lock, into: &byStep)
        }
        for lock in explicit {
            try merge(lock, into: &byStep)
        }

        return byStep.values
            .filter(\.hasAnyLane)
            .sorted { $0.step < $1.step }
    }

    private static func merge(_ incoming: Track11StepLock, into byStep: inout [Int: Track11StepLock]) throws {
        guard var existing = byStep[incoming.step] else {
            byStep[incoming.step] = incoming
            return
        }

        existing.cc1 = try mergeLane(existing.cc1, incoming.cc1, lane: "CC1", step: incoming.step)
        existing.cc2 = try mergeLane(existing.cc2, incoming.cc2, lane: "CC2", step: incoming.step)
        existing.cc3 = try mergeLane(existing.cc3, incoming.cc3, lane: "CC3", step: incoming.step)
        existing.cc4 = try mergeLane(existing.cc4, incoming.cc4, lane: "CC4", step: incoming.step)
        byStep[incoming.step] = existing
    }

    private static func mergeLane(_ existing: Int?, _ incoming: Int?, lane: String, step: Int) throws -> Int? {
        guard let incoming else { return existing }
        if let existing, existing != incoming {
            throw XYExporterError.invalidNote("conflicting \(lane) lock values on step \(step) are not supported")
        }
        return incoming
    }

    private static func normalizedTrack11StepLock(
        step: Int,
        cc1: Int?,
        cc2: Int?,
        cc3: Int?,
        cc4: Int?,
        where source: String
    ) throws -> Track11StepLock {
        Track11StepLock(
            step: step,
            cc1: try normalizedTrack11LaneValue(cc1, where: "\(source).cc1"),
            cc2: try normalizedTrack11LaneValue(cc2, where: "\(source).cc2"),
            cc3: try normalizedTrack11LaneValue(cc3, where: "\(source).cc3"),
            cc4: try normalizedTrack11LaneValue(cc4, where: "\(source).cc4")
        )
    }

    private static func normalizedTrack11LaneValue(_ value: Int?, where source: String) throws -> Int? {
        guard let value else { return nil }
        guard (0...127).contains(value) else {
            throw XYExporterError.invalidNote("\(source) must be in [0,127]")
        }
        return value
    }

    private static func barsForPattern(_ notes: [EventNote], locks: [Track11StepLock]) -> Int {
        let maxNoteStep = notes.map(\.step).max() ?? 1
        let maxLockStep = locks.map(\.step).max() ?? 1
        return max(1, Int(ceil(Double(max(maxNoteStep, maxLockStep)) / 16.0)))
    }
}
