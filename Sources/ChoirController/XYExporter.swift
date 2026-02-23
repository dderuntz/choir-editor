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
    private static let magic: [UInt8] = [0xDD, 0xCC, 0xBB, 0xAA]
    private static let minProjectSize = 0x80
    private static let stepTicks = 480
    private static let maxEventNotes = 120
    private static let knownEventTypes: [UInt8] = [0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x25, 0x2D, 0x36]
    private static let multiPatternDescriptorOffset = 0x58
    private static let t5ExemptIndex = 4
    private static let midiTrackIndex = 11
    private static let midiLaneSignature: [UInt8] = [
        0xFD, 0xFF, 0x7F, 0x02,
        0xFC, 0xFF, 0x7F, 0x03,
        0xFB, 0xFF, 0x7F, 0x04,
        0xFA, 0xFF, 0x7F, 0x05
    ]
    private static let midiDefaultsPrefixMarker: [UInt8] = [0xFF, 0xFF, 0x01, 0x7F, 0x00, 0x00]
    private static let midiLockTableConfigTailSignature: [UInt8] = [
        0x40, 0x1F, 0x00, 0x00, 0x0C, 0x40, 0x1F, 0x00, 0x00
    ]
    private static let midiLockTableEmptyEntry: [UInt8] = [0xFF, 0x00, 0x00]
    private static let midiLockTableEntryCount = 55
    private static let track11DefaultCC1 = 64
    private static let track11DefaultCC2 = 127
    private static let track11DefaultCC3 = 0
    private static let track11DefaultCC4 = 32
    // Track 11 defaults-only donor chunk from `dderuntz-saves2/05a.xy`
    // (user-requested profile with CC2 set to 127).
    private static let midiChoirDefaultChunk: [UInt8] = [
        0x0E, 0x69, 0xAA, 0x2A, 0x40, 0x7A, 0xFF, 0x7F, 0x7F, 0x00, 0x00, 0x00, 0x02, 0x89, 0xAA, 0x2A, 0x20
    ]

    static func export(
        templateURL: URL,
        outputURL: URL,
        trackIndex: Int = 11,
        notes: [XYExportNoteData],
        stepLocks: [XYExportStepLockData] = [],
        tempoTenths: Int,
        grooveType: Int
    ) throws {
        guard trackIndex >= 1 && trackIndex <= 16 else {
            throw XYExporterError.invalidTrackIndex(trackIndex)
        }
        guard !notes.isEmpty else {
            throw XYExporterError.invalidNote("at least one note is required")
        }

        let templateData = try Data(contentsOf: templateURL)
        var project = try Project.parse(bytes: [UInt8](templateData))
        project = try stripTrackEvent(project: project, trackIndex: trackIndex, preferredType: 0x36)

        let patterns = try buildPatterns(from: notes)
        let explicitStepLocks = try buildTrack11StepLocks(from: stepLocks)
        guard patterns.count == 1 else {
            throw XYExporterError.unsupported(
                "multi-pattern chaining is not device-validated yet. Export currently supports up to 4 bars (64 steps)."
            )
        }
        let mergedStepLocks = try mergedTrack11StepLocks(
            noteDerived: track11StepLocksFromNotes(patterns[0]),
            explicit: explicitStepLocks
        )
        project = try appendSinglePatternNotes(
            project: project,
            trackIndex: trackIndex,
            notes: patterns[0],
            stepLocks: mergedStepLocks
        )

        var output = project.serialize()
        try applyHeaderPatch(bytes: &output, tempoTenths: tempoTenths, grooveType: grooveType)
        try Data(output).write(to: outputURL, options: .atomic)
    }

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

        var laneMask: UInt8 {
            var mask: UInt8 = 0
            if cc1 != nil { mask |= 0x01 }
            if cc2 != nil { mask |= 0x02 }
            if cc3 != nil { mask |= 0x04 }
            if cc4 != nil { mask |= 0x08 }
            return mask
        }
    }

    private enum Track11LockLane {
        case cc1
        case cc2
    }

    private struct Track11SingleLockTemplate {
        let step: Int
        let lane: Track11LockLane
        let lockSlot: Int
        let headerByte: UInt8
        let nonZeroMarker: UInt8
        let zeroMarker: UInt8?
        let metadata44: UInt16
        let metadata48: UInt16
    }

    private struct Track11StepRecordTemplate {
        let step: Int
        let lane: Track11LockLane
        let lockSlot: Int
        let headerByte: UInt8
        let nonZeroMarker: UInt8
        let zeroMarker: UInt8?
    }

    private struct Track11MultiLockTemplate {
        let steps: [Int]
        let records: [Track11StepRecordTemplate]
        let metadata: [Int: UInt16]
    }

    private struct TrackBlock {
        var index: Int
        var preamble: [UInt8]
        var body: [UInt8]

        var typeByte: UInt8 { body.count > 9 ? body[9] : 0x00 }
    }

    struct Track11LockEntry {
        let slot: Int
        let bytes: [UInt8]
    }

    struct Track11LockTable {
        let startOffset: Int
        let endOffset: Int
        let entries: [Track11LockEntry]
    }

    private struct Project {
        var preTrack: [UInt8]
        var tracks: [TrackBlock]

        static func parse(bytes: [UInt8]) throws -> Project {
            guard bytes.count >= XYExporter.minProjectSize else {
                throw XYExporterError.invalidTemplate("file is too short (\(bytes.count) bytes)")
            }
            guard bytes.starts(with: XYExporter.magic) else {
                throw XYExporterError.invalidTemplate("bad magic header")
            }

            let sigOffsets = XYExporter.findTrackBlocks(bytes)
            guard sigOffsets.count == 16 else {
                throw XYExporterError.invalidTemplate("expected 16 track blocks, found \(sigOffsets.count)")
            }

            let preambleOffsets = sigOffsets.map { $0 - 4 }
            let preTrack = Array(bytes[0..<preambleOffsets[0]])

            var tracks: [TrackBlock] = []
            tracks.reserveCapacity(16)

            for i in 0..<16 {
                let start = preambleOffsets[i]
                let end = (i + 1 < 16) ? preambleOffsets[i + 1] : bytes.count
                let preamble = Array(bytes[start..<(start + 4)])
                let body = Array(bytes[(start + 4)..<end])
                tracks.append(TrackBlock(index: i, preamble: preamble, body: body))
            }

            return Project(preTrack: preTrack, tracks: tracks)
        }

        func serialize() -> [UInt8] {
            var out = preTrack
            for track in tracks {
                out += track.preamble
                out += track.body
            }
            return out
        }
    }

    private struct BlockEntry {
        let owner: Int
        let pattern: Int
        let notes: [EventNote]?
        let isLeader: Bool
        let isClone: Bool
        let isLastInSet: Bool
    }

    private static func buildPatterns(from notes: [XYExportNoteData]) throws -> [[EventNote]] {
        var converted: [EventNote] = []
        converted.reserveCapacity(notes.count)

        for (idx, note) in notes.enumerated() {
            guard note.step >= 1 else {
                throw XYExporterError.invalidNote("notes[\(idx)].step must be >= 1")
            }
            guard (0...127).contains(note.note) else {
                throw XYExporterError.invalidNote("notes[\(idx)].note must be in [0,127]")
            }
            guard (0...127).contains(note.velocity) else {
                throw XYExporterError.invalidNote("notes[\(idx)].velocity must be in [0,127]")
            }
            guard note.gateTicks >= 0 else {
                throw XYExporterError.invalidNote("notes[\(idx)].gateTicks must be >= 0")
            }
            converted.append(
                EventNote(
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
            )
        }

        guard let maxStep = converted.map(\.step).max() else {
            throw XYExporterError.invalidNote("at least one note is required")
        }

        let patternCount = ((maxStep - 1) / 64) + 1
        var patterns: [[EventNote]] = Array(repeating: [], count: patternCount)

        for note in converted {
            let pidx = (note.step - 1) / 64
            let localStep = ((note.step - 1) % 64) + 1
            patterns[pidx].append(
                EventNote(
                    step: localStep,
                    note: note.note,
                    velocity: note.velocity,
                    tickOffset: note.tickOffset,
                    gateTicks: note.gateTicks,
                    cc1: note.cc1,
                    cc2: note.cc2,
                    cc3: note.cc3,
                    cc4: note.cc4
                )
            )
        }

        return patterns
    }

    private static func appendSinglePatternNotes(
        project: Project,
        trackIndex: Int,
        notes: [EventNote],
        stepLocks: [Track11StepLock]
    ) throws -> Project {
        guard !notes.isEmpty else {
            throw XYExporterError.invalidNote("single-pattern export requires at least one note")
        }
        let idx = try trackArrayIndex(trackIndex)
        var tracks = project.tracks

        var track = tracks[idx]
        var body = try activateBody(track.body)
        if trackIndex == midiTrackIndex {
            body = applyTrack11DefaultProfile(to: body)
            body = applyTrack11StepLocks(to: body, stepLocks: stepLocks)
        }
        body += try buildEvent(notes: notes, eventType: 0x36)

        var preamble = track.preamble
        guard preamble.count == 4 else {
            throw XYExporterError.invalidTemplate("track preamble is not 4 bytes")
        }
        preamble[2] = UInt8(clamping: barsForNotes(notes) * 16)
        track.preamble = preamble
        track.body = body
        tracks[idx] = track

        let nextIdx = idx + 1
        if nextIdx < 16 && nextIdx != t5ExemptIndex {
            var next = tracks[nextIdx]
            guard next.preamble.count == 4 else {
                throw XYExporterError.invalidTemplate("track preamble is not 4 bytes")
            }
            next.preamble[0] = 0x64
            tracks[nextIdx] = next
        }

        return Project(preTrack: project.preTrack, tracks: tracks)
    }

    private static func applyTrack11DefaultProfile(to body: [UInt8]) -> [UInt8] {
        guard let laneOffset = findSubsequence(
            in: body,
            needle: midiLaneSignature,
            start: 0,
            endExclusive: body.count
        ) else {
            return body
        }
        guard let markerOffset = findLastSubsequence(
            in: body,
            needle: midiDefaultsPrefixMarker,
            endExclusive: laneOffset
        ) else {
            return body
        }

        let replaceStart = markerOffset + midiDefaultsPrefixMarker.count
        guard replaceStart <= laneOffset else {
            return body
        }

        var out = body
        out.replaceSubrange(replaceStart..<laneOffset, with: midiChoirDefaultChunk)
        return out
    }

    private static func applyTrack11StepLocks(to body: [UInt8], stepLocks: [Track11StepLock]) -> [UInt8] {
        guard !stepLocks.isEmpty else { return body }
        guard let table = parseTrack11LockTable(in: body) else { return body }

        guard let synthesizedTable = synthesizeTrack11LockTable(
            existing: table,
            stepLocks: stepLocks
        ) else {
            return body
        }

        var out = body
        out.replaceSubrange(table.startOffset..<table.endOffset, with: synthesizedTable)
        return out
    }

    private static func synthesizeTrack11LockTable(
        existing table: Track11LockTable,
        stepLocks: [Track11StepLock]
    ) -> [UInt8]? {
        // Safety gate: only synthesize from clean defaults templates
        // and only for capture-backed lock topologies.
        guard table.entries.isEmpty else { return nil }
        if let multi = synthesizeTrack11MultiLockTable(stepLocks: stepLocks) {
            return multi
        }

        guard stepLocks.count == 1 else { return nil }
        guard let lock = stepLocks.first else { return nil }
        guard lock.laneMask == 0x01 || lock.laneMask == 0x02 else { return nil }
        let lane: Track11LockLane = lock.laneMask == 0x01 ? .cc1 : .cc2
        let value: Int = lane == .cc1 ? (lock.cc1 ?? 0) : (lock.cc2 ?? 0)

        guard let template = track11SingleLockTemplate(step: lock.step, lane: lane) else {
            return nil
        }
        guard let pair = encodeTrack11SingleLaneValue(
            value: value,
            nonZeroMarker: template.nonZeroMarker,
            zeroMarker: template.zeroMarker
        ) else {
            return nil
        }

        let lockEntry: [UInt8] = [template.headerByte, pair.marker, pair.value, 0x00, 0x00]
        return buildTrack11LockTableBytes(
            entries: [
                template.lockSlot: lockEntry,
                44: track11MetadataEntry(word: template.metadata44),
                48: track11MetadataEntry(word: template.metadata48)
            ]
        )
    }

    private static func synthesizeTrack11MultiLockTable(stepLocks: [Track11StepLock]) -> [UInt8]? {
        // Current capture-backed multi-step synthesis scope:
        // CC1-only prefix chains from 06a 1..7.
        guard stepLocks.count >= 2 else { return nil }
        guard stepLocks.allSatisfy({ $0.laneMask == 0x01 && $0.cc1 != nil }) else { return nil }
        let requestedSteps = stepLocks.map(\.step).sorted()
        guard let template = track11CC1PrefixTemplate(for: requestedSteps) else { return nil }

        let lockByStep = Dictionary(uniqueKeysWithValues: stepLocks.map { ($0.step, $0) })
        var entries: [Int: [UInt8]] = [:]
        for (metaSlot, metaWord) in template.metadata {
            entries[metaSlot] = track11MetadataEntry(word: metaWord)
        }

        for record in template.records {
            guard let lock = lockByStep[record.step], let value = lock.cc1 else { return nil }
            guard let pair = encodeTrack11SingleLaneValue(
                value: value,
                nonZeroMarker: record.nonZeroMarker,
                zeroMarker: record.zeroMarker
            ) else {
                return nil
            }
            entries[record.lockSlot] = [record.headerByte, pair.marker, pair.value, 0x00, 0x00]
        }

        return buildTrack11LockTableBytes(entries: entries)
    }

    private static func track11MetadataEntry(word: UInt16) -> [UInt8] {
        [UInt8(word & 0x00FF), UInt8((word >> 8) & 0x00FF), 0x00, 0x00]
    }

    private static func track11SingleLockTemplate(step: Int, lane: Track11LockLane) -> Track11SingleLockTemplate? {
        // Capture-backed templates from clean single-lock fixtures:
        // - 06a 1.xy (step1 cc1)
        // - 04f b-s3-cc2v9.xy (step3 cc2)
        // - 07a 1/2/3.xy (step5/8/12 cc1)
        switch (step, lane) {
        case (1, .cc1):
            return Track11SingleLockTemplate(
                step: 1,
                lane: .cc1,
                lockSlot: 2,
                headerByte: 0x18,
                nonZeroMarker: 0x29,
                zeroMarker: 0xD1,
                metadata44: 0x01C4,
                metadata48: 0x01FA
            )
        case (3, .cc2):
            return Track11SingleLockTemplate(
                step: 3,
                lane: .cc2,
                lockSlot: 2,
                headerByte: 0xC2,
                nonZeroMarker: 0x29,
                zeroMarker: 0x84,
                metadata44: 0x022A,
                metadata48: 0x02EA
            )
        case (5, .cc1):
            return Track11SingleLockTemplate(
                step: 5,
                lane: .cc1,
                lockSlot: 3,
                headerByte: 0x67,
                nonZeroMarker: 0x29,
                zeroMarker: nil,
                metadata44: 0x0195,
                metadata48: 0x01DA
            )
        case (8, .cc1):
            return Track11SingleLockTemplate(
                step: 8,
                lane: .cc1,
                lockSlot: 4,
                headerByte: 0x62,
                nonZeroMarker: 0xD4,
                zeroMarker: nil,
                metadata44: 0x01B2,
                metadata48: 0x01C2
            )
        case (12, .cc1):
            return Track11SingleLockTemplate(
                step: 12,
                lane: .cc1,
                lockSlot: 5,
                headerByte: 0xB1,
                nonZeroMarker: 0xD4,
                zeroMarker: nil,
                metadata44: 0x0183,
                metadata48: 0x01A2
            )
        default:
            return nil
        }
    }

    private static func track11CC1PrefixTemplate(for steps: [Int]) -> Track11MultiLockTemplate? {
        let canonical = steps.sorted()

        let recordsPrefix: [Track11StepRecordTemplate] = [
            Track11StepRecordTemplate(step: 1, lane: .cc1, lockSlot: 2, headerByte: 0x18, nonZeroMarker: 0x29, zeroMarker: 0xD1),
            Track11StepRecordTemplate(step: 2, lane: .cc1, lockSlot: 3, headerByte: 0x50, nonZeroMarker: 0xD4, zeroMarker: nil),
            Track11StepRecordTemplate(step: 3, lane: .cc1, lockSlot: 4, headerByte: 0x50, nonZeroMarker: 0x29, zeroMarker: nil),
            Track11StepRecordTemplate(step: 4, lane: .cc1, lockSlot: 5, headerByte: 0x50, nonZeroMarker: 0x29, zeroMarker: nil),
            Track11StepRecordTemplate(step: 9, lane: .cc1, lockSlot: 7, headerByte: 0x9F, nonZeroMarker: 0x29, zeroMarker: nil),
            Track11StepRecordTemplate(step: 13, lane: .cc1, lockSlot: 9, headerByte: 0x4B, nonZeroMarker: 0x29, zeroMarker: nil),
            Track11StepRecordTemplate(step: 16, lane: .cc1, lockSlot: 10, headerByte: 0xF8, nonZeroMarker: 0x29, zeroMarker: nil)
        ]

        switch canonical {
        case [1]:
            return Track11MultiLockTemplate(
                steps: canonical,
                records: Array(recordsPrefix.prefix(1)),
                metadata: [44: 0x01C4, 48: 0x01FA]
            )
        case [1, 2]:
            return Track11MultiLockTemplate(
                steps: canonical,
                records: Array(recordsPrefix.prefix(2)),
                metadata: [45: 0x0170, 46: 0x0105, 50: 0x01F2]
            )
        case [1, 2, 3]:
            return Track11MultiLockTemplate(
                steps: canonical,
                records: Array(recordsPrefix.prefix(3)),
                metadata: [46: 0x011C, 47: 0x0105, 48: 0x0105, 52: 0x01EA]
            )
        case [1, 2, 3, 4]:
            return Track11MultiLockTemplate(
                steps: canonical,
                records: Array(recordsPrefix.prefix(4)),
                metadata: [46: 0x01C9, 47: 0x0105, 48: 0x0105, 49: 0x0105, 53: 0x01E2]
            )
        case [1, 2, 3, 4, 9]:
            return Track11MultiLockTemplate(
                steps: canonical,
                records: Array(recordsPrefix.prefix(5)),
                metadata: [47: 0x0126, 48: 0x0105, 49: 0x0105, 50: 0x0105, 51: 0x0125]
            )
        case [1, 2, 3, 4, 9, 13]:
            return Track11MultiLockTemplate(
                steps: canonical,
                records: Array(recordsPrefix.prefix(6)),
                metadata: [47: 0x01D8, 48: 0x0105, 49: 0x0105, 50: 0x0105, 51: 0x0125, 52: 0x011D]
            )
        case [1, 2, 3, 4, 9, 13, 16]:
            return Track11MultiLockTemplate(
                steps: canonical,
                records: Array(recordsPrefix.prefix(7)),
                metadata: [47: 0x01DD, 48: 0x0105, 49: 0x0105, 50: 0x0105, 51: 0x0125, 52: 0x011D, 53: 0x0115]
            )
        default:
            return nil
        }
    }

    private static func buildTrack11LockTableBytes(entries: [Int: [UInt8]]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(midiLockTableEntryCount * 5)

        for slot in 0..<midiLockTableEntryCount {
            if let entry = entries[slot] {
                out += entry
            } else {
                out += midiLockTableEmptyEntry
            }
        }
        return out
    }

    private static func encodeTrack11SingleLaneValue(
        value: Int,
        nonZeroMarker: UInt8,
        zeroMarker: UInt8?
    ) -> (marker: UInt8, value: UInt8)? {
        let clamped = UInt8(clamping: max(0, min(127, value)))
        if clamped == 0 {
            guard let zeroMarker else { return nil }
            return (zeroMarker, 0x00)
        }
        if clamped == 127 {
            return (0x7E, 0x7F)
        }
        return (nonZeroMarker, clamped)
    }

    private static func buildTrack11StepLocks(from stepLocks: [XYExportStepLockData]) throws -> [Track11StepLock] {
        var byStep: [Int: Track11StepLock] = [:]

        for (idx, lock) in stepLocks.enumerated() {
            guard lock.step >= 1 else {
                throw XYExporterError.invalidNote("stepLocks[\(idx)].step must be >= 1")
            }
            guard lock.step <= 64 else {
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

            if var existing = byStep[normalized.step] {
                if let v = normalized.cc1 { existing.cc1 = v }
                if let v = normalized.cc2 { existing.cc2 = v }
                if let v = normalized.cc3 { existing.cc3 = v }
                if let v = normalized.cc4 { existing.cc4 = v }
                byStep[normalized.step] = existing
            } else {
                byStep[normalized.step] = normalized
            }
        }

        return byStep.values.sorted { $0.step < $1.step }
    }

    private static func track11StepLocksFromNotes(_ notes: [EventNote]) -> [Track11StepLock] {
        var byStep: [Int: Track11StepLock] = [:]

        for note in notes {
            let normalized = Track11StepLock(
                step: note.step,
                cc1: normalizedTrack11LaneValue(note.cc1, defaultValue: track11DefaultCC1),
                cc2: normalizedTrack11LaneValue(note.cc2, defaultValue: track11DefaultCC2),
                cc3: normalizedTrack11LaneValue(note.cc3, defaultValue: track11DefaultCC3),
                cc4: normalizedTrack11LaneValue(note.cc4, defaultValue: track11DefaultCC4)
            )
            guard normalized.hasAnyLane else { continue }

            if var existing = byStep[normalized.step] {
                if let v = normalized.cc1 { existing.cc1 = v }
                if let v = normalized.cc2 { existing.cc2 = v }
                if let v = normalized.cc3 { existing.cc3 = v }
                if let v = normalized.cc4 { existing.cc4 = v }
                byStep[normalized.step] = existing
            } else {
                byStep[normalized.step] = normalized
            }
        }

        return byStep.values.sorted { $0.step < $1.step }
    }

    private static func mergedTrack11StepLocks(
        noteDerived: [Track11StepLock],
        explicit: [Track11StepLock]
    ) throws -> [Track11StepLock] {
        var byStep: [Int: Track11StepLock] = [:]

        for lock in noteDerived {
            byStep[lock.step] = lock
        }

        for lock in explicit {
            if var existing = byStep[lock.step] {
                if let v = lock.cc1 { existing.cc1 = v }
                if let v = lock.cc2 { existing.cc2 = v }
                if let v = lock.cc3 { existing.cc3 = v }
                if let v = lock.cc4 { existing.cc4 = v }
                byStep[lock.step] = existing
            } else {
                byStep[lock.step] = lock
            }
        }

        return byStep.values
            .filter(\.hasAnyLane)
            .sorted { $0.step < $1.step }
    }

    private static func normalizedTrack11StepLock(
        step: Int,
        cc1: Int?,
        cc2: Int?,
        cc3: Int?,
        cc4: Int?,
        where source: String
    ) throws -> Track11StepLock {
        let nCC1 = try normalizedTrack11LaneValueValidated(cc1, defaultValue: track11DefaultCC1, where: "\(source).cc1")
        let nCC2 = try normalizedTrack11LaneValueValidated(cc2, defaultValue: track11DefaultCC2, where: "\(source).cc2")
        let nCC3 = try normalizedTrack11LaneValueValidated(cc3, defaultValue: track11DefaultCC3, where: "\(source).cc3")
        let nCC4 = try normalizedTrack11LaneValueValidated(cc4, defaultValue: track11DefaultCC4, where: "\(source).cc4")
        return Track11StepLock(step: step, cc1: nCC1, cc2: nCC2, cc3: nCC3, cc4: nCC4)
    }

    private static func normalizedTrack11LaneValue(_ value: Int?, defaultValue: Int) -> Int? {
        guard let value else { return nil }
        return value == defaultValue ? nil : value
    }

    private static func normalizedTrack11LaneValueValidated(
        _ value: Int?,
        defaultValue: Int,
        where source: String
    ) throws -> Int? {
        guard let value else { return nil }
        guard (0...127).contains(value) else {
            throw XYExporterError.invalidNote("\(source) must be in [0,127]")
        }
        return value == defaultValue ? nil : value
    }

    private static func buildMultiPatternProject(
        project: Project,
        trackIndex: Int,
        patterns: [[EventNote]]
    ) throws -> Project {
        let owner = try trackArrayIndex(trackIndex)
        guard patterns.count >= 2 else {
            throw XYExporterError.invalidNote("multi-pattern export requires at least 2 patterns")
        }

        let baseline = project.tracks
        let entries = planBlocks(owner: owner, patterns: patterns)

        var allBlocks: [TrackBlock] = []
        allBlocks.reserveCapacity(entries.count)

        for (slotIdx, entry) in entries.enumerated() {
            let block = try buildSingleBlock(
                baseline: baseline,
                entry: entry,
                slotIndex: slotIdx,
                numPatterns: patterns.count
            )
            allBlocks.append(block)
        }

        try applyPreambleRules(blocks: &allBlocks, entries: entries, baseline: baseline)

        let blocks: [TrackBlock]
        if allBlocks.count > 16 {
            var packed = Array(allBlocks.prefix(15))
            let overflow = Array(allBlocks.dropFirst(15))
            guard let first = overflow.first else {
                throw XYExporterError.invalidTemplate("missing overflow block")
            }

            var mergedBody = first.body
            if overflow.count > 1 {
                for block in overflow.dropFirst() {
                    mergedBody += block.preamble
                    mergedBody += block.body
                }
            }

            var packedBlock = first
            packedBlock.index = 15
            packedBlock.body = mergedBody
            packed.append(packedBlock)
            blocks = packed
        } else {
            blocks = allBlocks
        }

        guard blocks.count == 16 else {
            throw XYExporterError.invalidTemplate("multi-pattern packing did not produce 16 blocks")
        }

        let newPreTrack = try buildPreTrack(
            original: project.preTrack,
            trackIndex: trackIndex,
            patternCount: patterns.count
        )

        return Project(preTrack: newPreTrack, tracks: blocks)
    }

    private static func planBlocks(owner: Int, patterns: [[EventNote]]) -> [BlockEntry] {
        var entries: [BlockEntry] = []

        for idx in 0..<16 {
            if idx == owner {
                let numPatterns = patterns.count
                for patternIndex in 0..<numPatterns {
                    let notes = patterns[patternIndex]
                    entries.append(
                        BlockEntry(
                            owner: idx,
                            pattern: patternIndex,
                            notes: notes.isEmpty ? nil : notes,
                            isLeader: patternIndex == 0,
                            isClone: patternIndex > 0,
                            isLastInSet: patternIndex == (numPatterns - 1)
                        )
                    )
                }
            } else {
                entries.append(
                    BlockEntry(
                        owner: idx,
                        pattern: 0,
                        notes: nil,
                        isLeader: false,
                        isClone: false,
                        isLastInSet: true
                    )
                )
            }
        }
        return entries
    }

    private static func buildSingleBlock(
        baseline: [TrackBlock],
        entry: BlockEntry,
        slotIndex: Int,
        numPatterns: Int
    ) throws -> TrackBlock {
        let baseBlock = baseline[entry.owner]
        let baseBody = baseBlock.body
        let basePreamble = baseBlock.preamble

        if !entry.isLeader && !entry.isClone {
            return TrackBlock(index: slotIndex, preamble: basePreamble, body: baseBody)
        }

        if entry.isLeader {
            let body: [UInt8]
            if let notes = entry.notes {
                var b = try activateBody(baseBody)
                b += try buildEvent(notes: notes, eventType: 0x36)
                guard !b.isEmpty else {
                    throw XYExporterError.invalidTemplate("cannot trim empty leader body")
                }
                b.removeLast()
                body = b
            } else {
                guard !baseBody.isEmpty else {
                    throw XYExporterError.invalidTemplate("cannot trim empty leader body")
                }
                body = Array(baseBody.dropLast())
            }

            var preamble = basePreamble
            guard preamble.count == 4 else {
                throw XYExporterError.invalidTemplate("track preamble is not 4 bytes")
            }
            if entry.owner == 0 {
                preamble[0] = 0xB5
            }
            preamble[1] = UInt8(clamping: numPatterns)
            if let notes = entry.notes {
                preamble[2] = UInt8(clamping: barsForNotes(notes) * 16)
            }

            return TrackBlock(index: slotIndex, preamble: preamble, body: body)
        }

        let body: [UInt8]
        if let notes = entry.notes {
            var b = try activateBody(baseBody)
            b += try buildEvent(notes: notes, eventType: 0x36)
            if !entry.isLastInSet {
                guard !b.isEmpty else {
                    throw XYExporterError.invalidTemplate("cannot trim empty clone body")
                }
                b.removeLast()
            }
            body = b
        } else {
            if entry.isLastInSet {
                body = baseBody
            } else {
                guard !baseBody.isEmpty else {
                    throw XYExporterError.invalidTemplate("cannot trim empty clone body")
                }
                body = Array(baseBody.dropLast())
            }
        }

        var preamble = basePreamble
        guard preamble.count == 4 else {
            throw XYExporterError.invalidTemplate("track preamble is not 4 bytes")
        }
        preamble[0] = 0x00
        preamble[1] = 0x00
        if let notes = entry.notes {
            preamble[2] = UInt8(clamping: barsForNotes(notes) * 16)
        }

        return TrackBlock(index: slotIndex, preamble: preamble, body: body)
    }

    private static func applyPreambleRules(
        blocks: inout [TrackBlock],
        entries: [BlockEntry],
        baseline: [TrackBlock]
    ) throws {
        guard blocks.count == entries.count else {
            throw XYExporterError.invalidTemplate("block/entry count mismatch in preamble rules")
        }
        guard blocks.count >= 2 else { return }

        for i in 1..<blocks.count {
            let prevActivated = blocks[i - 1].typeByte == 0x07
            let entry = entries[i]

            var preamble = blocks[i].preamble
            guard preamble.count == 4 else {
                throw XYExporterError.invalidTemplate("track preamble is not 4 bytes")
            }

            if entry.isClone {
                let nextOwner = entry.owner + 1
                if prevActivated && nextOwner != t5ExemptIndex {
                    preamble[1] = 0x64
                } else if nextOwner < 16 {
                    preamble[1] = baseline[nextOwner].preamble[0]
                } else {
                    preamble[1] = 0x00
                }
            } else if prevActivated && entry.owner != t5ExemptIndex {
                preamble[0] = 0x64
            }

            blocks[i].preamble = preamble
        }
    }

    private static func buildPreTrack(
        original: [UInt8],
        trackIndex: Int,
        patternCount: Int
    ) throws -> [UInt8] {
        guard original.count >= multiPatternDescriptorOffset else {
            throw XYExporterError.invalidTemplate("pre-track region too short for descriptor insert")
        }

        var preTrack = original
        let t1Count = trackIndex == 1 ? patternCount : 1
        let t2Count = trackIndex == 2 ? patternCount : 1
        preTrack[0x56] = UInt8(clamping: max(0, t1Count - 1))
        preTrack[0x57] = UInt8(clamping: max(0, t2Count - 1))

        let trackSet = Set([trackIndex - 1])
        guard trackSet.allSatisfy({ $0 >= 2 }) else {
            throw XYExporterError.unsupported("multi-pattern descriptor is currently implemented for Track 3+ only")
        }
        let descriptor = try schemeADescriptor(trackSet: trackSet, patternCounts: [trackIndex - 1: patternCount])
        preTrack.insert(contentsOf: descriptor, at: multiPatternDescriptorOffset)
        return preTrack
    }

    private static func schemeADescriptor(
        trackSet: Set<Int>,
        patternCounts: [Int: Int]
    ) throws -> [UInt8] {
        guard !trackSet.isEmpty else {
            throw XYExporterError.invalidTemplate("empty track set for descriptor")
        }
        guard trackSet.allSatisfy({ $0 >= 2 }) else {
            throw XYExporterError.unsupported("Scheme A descriptor requires Track 3+")
        }

        var out: [UInt8] = []
        for ti in trackSet.sorted() {
            let track1Based = ti + 1
            let gap = track1Based - 3
            let patternCount = patternCounts[ti] ?? 2
            let maxSlot = patternCount - 1
            out.append(UInt8(clamping: gap))
            out.append(UInt8(clamping: maxSlot))
        }

        let lastTrack1Based = (trackSet.max() ?? 2) + 1
        let token = 0x1E - lastTrack1Based
        out += [0x00, 0x00, UInt8(clamping: token), 0x01, 0x00, 0x00]
        return out
    }

    private static func stripTrackEvent(
        project: Project,
        trackIndex: Int,
        preferredType: UInt8
    ) throws -> Project {
        let idx = try trackArrayIndex(trackIndex)
        var tracks = project.tracks
        var track = tracks[idx]

        if let offset = findEventOffset(in: track.body, expectedType: preferredType) {
            var length = try eventLength(in: track.body, at: offset)
            guard offset + length <= track.body.count else {
                throw XYExporterError.invalidTemplate("event length exceeded track body")
            }

            // The event parser length excludes the terminal 2-byte trail.
            // When replacing an event we must remove that trailer too, otherwise
            // a stray `00 00` remains before the new event and corrupts layout.
            if offset + length + 2 <= track.body.count,
               track.body[offset + length] == 0x00,
               track.body[offset + length + 1] == 0x00 {
                length += 2
            }

            track.body.removeSubrange(offset..<(offset + length))
            tracks[idx] = track
        }

        return Project(preTrack: project.preTrack, tracks: tracks)
    }

    private static func findEventOffset(in body: [UInt8], expectedType: UInt8) -> Int? {
        if let offset = scanForEvent(in: body, eventType: expectedType) {
            return offset
        }
        for eventType in knownEventTypes where eventType != expectedType {
            if let offset = scanForEvent(in: body, eventType: eventType) {
                return offset
            }
        }
        return nil
    }

    private static func scanForEvent(in body: [UInt8], eventType: UInt8) -> Int? {
        guard body.count >= 5 else { return nil }
        var start = 0

        while start + 5 <= body.count {
            let idx = indexOf(byte: eventType, in: body, from: start)
            if idx == nil || (idx ?? 0) + 5 > body.count {
                return nil
            }
            let found = idx!
            let count = Int(body[found + 1])

            if (1...maxEventNotes).contains(count) {
                let firstSignature = body[(found + 2)...(found + 4)]
                if firstSignature.elementsEqual([UInt8(0x00), UInt8(0x00), UInt8(0x02)])
                    || firstSignature.elementsEqual([UInt8(0x00), UInt8(0x00), UInt8(0x03)]) {
                    return found
                }
                if found + 7 <= body.count,
                   body[found + 4] == 0x00,
                   body[found + 5] == 0x00,
                   body[found + 6] == 0x00 {
                    return found
                }
            }

            start = found + 1
        }

        return nil
    }

    private static func eventLength(in body: [UInt8], at offset: Int) throws -> Int {
        guard offset + 2 <= body.count else {
            throw XYExporterError.invalidTemplate("event is too short")
        }

        let count = Int(body[offset + 1])
        var pos = offset + 2

        for i in 0..<count {
            var firstNoteCompactLock = false

            if i == 0 {
                guard pos + 3 <= body.count else {
                    throw XYExporterError.invalidTemplate("truncated event header")
                }
                pos += 2 // tick
                let flag = body[pos]
                pos += 1
                if flag == 0x02 {
                    // no-op
                } else if flag == 0x00 {
                    guard pos + 2 <= body.count else {
                        throw XYExporterError.invalidTemplate("truncated first-note padding")
                    }
                    pos += 2
                } else if flag == 0x03 {
                    guard pos + 4 <= body.count else {
                        throw XYExporterError.invalidTemplate("truncated compact lock metadata")
                    }
                    pos += 4
                    firstNoteCompactLock = true
                } else {
                    throw XYExporterError.invalidTemplate("unexpected first-note flag 0x\(String(flag, radix: 16))")
                }
            } else {
                guard pos + 3 <= body.count else {
                    throw XYExporterError.invalidTemplate("truncated event continuation")
                }
                pos += 2 // trail
                let cont = body[pos]
                pos += 1

                if cont == 0x00 {
                    guard pos + 3 <= body.count else {
                        throw XYExporterError.invalidTemplate("truncated cont=0x00 segment")
                    }
                    pos += 2 // tick
                    let flag = body[pos]
                    pos += 1
                    if flag == 0x00 {
                        guard pos + 2 <= body.count else {
                            throw XYExporterError.invalidTemplate("truncated cont=0x00 padding")
                        }
                        pos += 2
                    } else if flag != 0x02 {
                        throw XYExporterError.invalidTemplate("unexpected flag after cont=0x00")
                    }
                } else if cont == 0x01 {
                    guard pos + 2 <= body.count else {
                        throw XYExporterError.invalidTemplate("truncated cont=0x01 segment")
                    }
                    pos += 1 // tick_hi
                    let flag = body[pos]
                    pos += 1
                    if flag == 0x00 {
                        guard pos + 2 <= body.count else {
                            throw XYExporterError.invalidTemplate("truncated cont=0x01 padding")
                        }
                        pos += 2
                    } else if flag != 0x02 {
                        throw XYExporterError.invalidTemplate("unexpected flag after cont=0x01")
                    }
                } else if cont != 0x04 {
                    throw XYExporterError.invalidTemplate("unknown continuation byte 0x\(String(cont, radix: 16))")
                }
            }

            if !firstNoteCompactLock {
                guard pos < body.count else {
                    throw XYExporterError.invalidTemplate("truncated gate bytes")
                }
                if body[pos] == 0xF0 {
                    guard pos + 4 <= body.count else {
                        throw XYExporterError.invalidTemplate("truncated default gate")
                    }
                    pos += 4
                } else {
                    guard pos + 5 <= body.count else {
                        throw XYExporterError.invalidTemplate("truncated explicit gate")
                    }
                    pos += 5
                }
            }

            guard pos + 2 <= body.count else {
                throw XYExporterError.invalidTemplate("truncated note/velocity bytes")
            }
            pos += 2
        }

        return pos - offset
    }

    private static func buildEvent(notes: [EventNote], eventType: UInt8) throws -> [UInt8] {
        guard !notes.isEmpty else {
            throw XYExporterError.invalidNote("need at least one note for event")
        }
        guard knownEventTypes.contains(eventType) else {
            throw XYExporterError.invalidTemplate("unknown event type 0x\(String(eventType, radix: 16))")
        }
        guard notes.count <= maxEventNotes else {
            throw XYExporterError.invalidNote("too many notes in one event (\(notes.count) > \(maxEventNotes))")
        }

        let sorted = notes.sorted { lhs, rhs in
            let lTick = (lhs.step - 1) * stepTicks + lhs.tickOffset
            let rTick = (rhs.step - 1) * stepTicks + rhs.tickOffset
            if lTick != rTick { return lTick < rTick }
            if lhs.note != rhs.note { return lhs.note < rhs.note }
            return lhs.velocity < rhs.velocity
        }

        var out: [UInt8] = [eventType, UInt8(clamping: sorted.count)]
        var previousTick = 0

        for (i, note) in sorted.enumerated() {
            let ticks = (note.step - 1) * stepTicks + note.tickOffset
            guard ticks >= 0 && ticks <= Int(UInt16.max) else {
                throw XYExporterError.unsupported(
                    "compact tick encoding requires ticks in [0,65535]; got \(ticks)"
                )
            }

            if i == 0 {
                out.appendLE16(UInt16(clamping: ticks))
                let flag: UInt8 = (ticks == 0) ? 0x02 : 0x00
                out.append(flag)
                if flag == 0x00 {
                    out += [0x00, 0x00]
                }
            } else {
                // Per-note trail before continuation selector.
                out += [0x00, 0x00]
                if ticks == previousTick {
                    // Chord continuation: same tick as previous note, no tick field.
                    out.append(0x04)
                } else if ticks != 0 && (ticks & 0xFF) == 0 {
                    // Escape form for ticks whose low byte is 0x00.
                    out.append(0x01)
                    out.append(UInt8((ticks >> 8) & 0xFF))
                    out.append(0x00)
                    out += [0x00, 0x00]
                } else {
                    out.append(0x00)
                    out.appendLE16(UInt16(clamping: ticks))
                    let flag: UInt8 = (ticks == 0) ? 0x02 : 0x00
                    out.append(flag)
                    if flag == 0x00 {
                        out += [0x00, 0x00]
                    }
                }
            }

            if note.gateTicks > 0 {
                guard note.gateTicks <= Int(UInt16.max) else {
                    throw XYExporterError.unsupported(
                        "compact gate encoding requires gateTicks in [0,65535]; got \(note.gateTicks)"
                    )
                }
                out.appendLE16(UInt16(clamping: note.gateTicks))
                out += [0x00, 0x00, 0x00]
            } else {
                out += [0xF0, 0x00, 0x00, 0x01]
            }

            let noteByte = UInt8(note.note & 0x7F)
            var velocityByte = UInt8(note.velocity & 0x7F)
            if velocityByte == noteByte {
                velocityByte = velocityByte < 127 ? velocityByte + 1 : velocityByte - 1
            }
            out.append(noteByte)
            out.append(velocityByte)
            previousTick = ticks
        }

        out += [0x00, 0x00]
        return out
    }

    private static func activateBody(_ body: [UInt8]) throws -> [UInt8] {
        guard body.count > 12 else {
            throw XYExporterError.invalidTemplate("track body too short to activate")
        }

        var out = body
        switch out[9] {
        case 0x05:
            out[9] = 0x07
            out.removeSubrange(10..<12)
        case 0x07:
            break
        default:
            throw XYExporterError.invalidTemplate("unexpected type byte 0x\(String(out[9], radix: 16))")
        }
        return out
    }

    private static func barsForNotes(_ notes: [EventNote]) -> Int {
        let maxStep = notes.map(\.step).max() ?? 1
        return Int(ceil(Double(maxStep) / 16.0))
    }

    private static func applyHeaderPatch(
        bytes: inout [UInt8],
        tempoTenths: Int,
        grooveType: Int
    ) throws {
        guard bytes.count >= 0x18 else {
            throw XYExporterError.invalidTemplate("header is too short")
        }
        let oldTempoWord = try readUInt32LE(bytes, at: 8)
        let grooveFlags = (oldTempoWord >> 16) & 0xFF
        let tempoWord = UInt32(tempoTenths & 0xFFFF)
            | (grooveFlags << 16)
            | (UInt32(grooveType & 0xFF) << 24)
        writeUInt32LE(value: tempoWord, into: &bytes, at: 8)
    }

    private static func trackArrayIndex(_ trackIndex: Int) throws -> Int {
        guard (1...16).contains(trackIndex) else {
            throw XYExporterError.invalidTrackIndex(trackIndex)
        }
        return trackIndex - 1
    }

    private static func findTrackBlocks(_ bytes: [UInt8]) -> [Int] {
        var offsets: [Int] = []
        var start = 0

        while start + 8 <= bytes.count {
            if bytes[start] == 0x00,
               bytes[start + 1] == 0x00,
               bytes[start + 2] == 0x01,
               bytes[start + 4] == 0xFF,
               bytes[start + 5] == 0x00,
               bytes[start + 6] == 0xFC,
               bytes[start + 7] == 0x00,
               isProbableTrackStart(bytes, signatureOffset: start) {
                offsets.append(start)
                if offsets.count == 16 { break }
                start += 8
                continue
            }
            start += 1
        }

        return offsets
    }

    private static func isProbableTrackStart(_ bytes: [UInt8], signatureOffset: Int) -> Bool {
        guard signatureOffset >= 4 else { return false }
        guard signatureOffset + 8 <= bytes.count else { return false }

        guard let pointerWord = try? readUInt32LE(bytes, at: signatureOffset - 4) else {
            return false
        }
        if (pointerWord & 0xFF00_0000) != 0xF000_0000 {
            return false
        }
        if (pointerWord & 0x0000_FFFF) == 0 {
            return false
        }
        return true
    }

    private static func indexOf(byte: UInt8, in bytes: [UInt8], from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        for i in start..<bytes.count where bytes[i] == byte {
            return i
        }
        return nil
    }

    private static func findSubsequence(
        in haystack: [UInt8],
        needle: [UInt8],
        start: Int,
        endExclusive: Int
    ) -> Int? {
        guard !needle.isEmpty else { return nil }
        let startBound = max(0, start)
        let endBound = min(endExclusive, haystack.count)
        guard startBound < endBound else { return nil }
        guard needle.count <= (endBound - startBound) else { return nil }

        let lastStart = endBound - needle.count
        if startBound > lastStart { return nil }

        for i in startBound...lastStart {
            if haystack[i..<(i + needle.count)].elementsEqual(needle) {
                return i
            }
        }
        return nil
    }

    private static func findLastSubsequence(
        in haystack: [UInt8],
        needle: [UInt8],
        endExclusive: Int
    ) -> Int? {
        guard !needle.isEmpty else { return nil }
        let endBound = min(endExclusive, haystack.count)
        guard needle.count <= endBound else { return nil }

        var i = endBound - needle.count
        while i >= 0 {
            if haystack[i..<(i + needle.count)].elementsEqual(needle) {
                return i
            }
            if i == 0 { break }
            i -= 1
        }
        return nil
    }

    static func inspectTrack11LockTable(in body: [UInt8]) -> Track11LockTable? {
        parseTrack11LockTable(in: body)
    }

    static func inspectTrackBody(in projectBytes: [UInt8], trackIndex: Int) -> [UInt8]? {
        guard let idx = try? trackArrayIndex(trackIndex),
              let project = try? Project.parse(bytes: projectBytes),
              idx < project.tracks.count else {
            return nil
        }
        return project.tracks[idx].body
    }

    private static func parseTrack11LockTable(in body: [UInt8]) -> Track11LockTable? {
        guard let configOffset = findSubsequence(
            in: body,
            needle: midiLockTableConfigTailSignature,
            start: 0,
            endExclusive: body.count
        ) else {
            return nil
        }

        let tableStart = configOffset + midiLockTableConfigTailSignature.count
        guard tableStart < body.count else { return nil }

        var entries: [Track11LockEntry] = []
        var cursor = tableStart

        for slot in 0..<midiLockTableEntryCount {
            guard cursor + 3 <= body.count else { return nil }

            if body[cursor..<(cursor + 3)].elementsEqual(midiLockTableEmptyEntry) {
                cursor += 3
                continue
            }

            guard let end = findLockEntryEnd(in: body, from: cursor) else {
                return nil
            }
            guard end > cursor && end <= body.count else { return nil }
            entries.append(
                Track11LockEntry(
                    slot: slot,
                    bytes: Array(body[cursor..<end])
                )
            )
            cursor = end
        }

        return Track11LockTable(
            startOffset: tableStart,
            endOffset: cursor,
            entries: entries
        )
    }

    private static func findLockEntryEnd(in body: [UInt8], from offset: Int) -> Int? {
        guard offset + 3 <= body.count else { return nil }
        for i in (offset + 2)..<body.count - 1 {
            if body[i] == 0x00, body[i + 1] == 0x00 {
                return i + 2
            }
        }
        return nil
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) throws -> UInt32 {
        guard offset + 4 <= bytes.count else {
            throw XYExporterError.invalidTemplate("read beyond EOF at \(offset)")
        }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func writeUInt32LE(value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        guard offset + 4 <= bytes.count else { return }
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}

private extension Array where Element == UInt8 {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendLE32(_ value: UInt32) {
        append(UInt8(value & 0x0000_00FF))
        append(UInt8((value >> 8) & 0x0000_00FF))
        append(UInt8((value >> 16) & 0x0000_00FF))
        append(UInt8((value >> 24) & 0x0000_00FF))
    }
}
