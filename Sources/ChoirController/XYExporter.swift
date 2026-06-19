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
        output = try canonicalizedRLEProject(output)
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
        case cc3
        case cc4
    }

    private struct Track11LaneBindingTemplate {
        let step: Int
        let lane: Track11LockLane
        let markerOffset: Int
        let valueOffset: Int
        let nonZeroMarker: UInt8
        let zeroMarker: UInt8?
        let zeroOmitsValueByte: Bool

        init(
            step: Int,
            lane: Track11LockLane,
            markerOffset: Int,
            valueOffset: Int,
            nonZeroMarker: UInt8,
            zeroMarker: UInt8?,
            zeroOmitsValueByte: Bool = false
        ) {
            self.step = step
            self.lane = lane
            self.markerOffset = markerOffset
            self.valueOffset = valueOffset
            self.nonZeroMarker = nonZeroMarker
            self.zeroMarker = zeroMarker
            self.zeroOmitsValueByte = zeroOmitsValueByte
        }
    }

    private struct Track11LockEntryTemplate {
        let slot: Int
        let bytes: [UInt8]
        let bindings: [Track11LaneBindingTemplate]
    }

    private struct Track11LockTopologyTemplate {
        let entries: [Track11LockEntryTemplate]
        let metadata: [Int: UInt16]
        let zeroMetadataAdjustments: [Int: Int]
        let lockRegionSuffix: [UInt8]?
        let applyMask6ValueMarkerOverrides: Bool

        init(
            entries: [Track11LockEntryTemplate],
            metadata: [Int: UInt16],
            zeroMetadataAdjustments: [Int: Int] = [:],
            lockRegionSuffix: [UInt8]? = nil,
            applyMask6ValueMarkerOverrides: Bool = true
        ) {
            self.entries = entries
            self.metadata = metadata
            self.zeroMetadataAdjustments = zeroMetadataAdjustments
            self.lockRegionSuffix = lockRegionSuffix
            self.applyMask6ValueMarkerOverrides = applyMask6ValueMarkerOverrides
        }
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

    private struct Track11LockSynthesisResult {
        let tableBytes: [UInt8]
        let compactPrefixBytes: [UInt8]
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
            body = try applyTrack11StepLocks(to: body, stepLocks: stepLocks)
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

    private static func applyTrack11StepLocks(to body: [UInt8], stepLocks: [Track11StepLock]) throws -> [UInt8] {
        guard !stepLocks.isEmpty else { return body }
        guard let table = parseTrack11LockTable(in: body) else {
            throw XYExporterError.invalidTemplate("Track 11 lock table marker was not found")
        }

        guard let synthesis = synthesizeTrack11LockTable(
            existing: table,
            stepLocks: stepLocks
        ) else {
            let topology = track11TopologyKey(for: stepLocks)
            throw XYExporterError.unsupported("Track 11 step-lock topology is not capture-backed: \(topology)")
        }

        var out = body
        if let defaultsOffset = findSubsequence(
            in: out,
            needle: midiDefaultsPrefixMarker,
            start: table.endOffset,
            endExclusive: out.count
        ) {
            let replacement = synthesis.tableBytes + synthesis.compactPrefixBytes
            out.replaceSubrange(table.startOffset..<defaultsOffset, with: replacement)
        } else {
            out.replaceSubrange(table.startOffset..<table.endOffset, with: synthesis.tableBytes)
        }
        return out
    }

    private static func synthesizeTrack11LockTable(
        existing table: Track11LockTable,
        stepLocks: [Track11StepLock]
    ) -> Track11LockSynthesisResult? {
        // Safety gate: only synthesize from clean defaults templates
        // and only for capture-backed lock topologies.
        guard table.entries.isEmpty else { return nil }
        guard let template = track11LockTopologyTemplate(for: stepLocks) else { return nil }

        var metadataWords = template.metadata
        var entries: [Int: [UInt8]] = [:]
        var didEncodeZeroValue = false
        let lockByStep = Dictionary(uniqueKeysWithValues: stepLocks.map { ($0.step, $0) })

        for entryTemplate in template.entries {
            var lockEntry = entryTemplate.bytes
            for binding in entryTemplate.bindings {
                guard binding.markerOffset < lockEntry.count,
                      binding.valueOffset < lockEntry.count,
                      let lock = lockByStep[binding.step],
                      let value = track11LockValue(lock: lock, lane: binding.lane),
                      let pair = encodeTrack11SingleLaneValue(
                        value: value,
                        nonZeroMarker: binding.nonZeroMarker,
                        zeroMarker: binding.zeroMarker
                      ) else {
                    return nil
                }
                if pair.value == 0 {
                    didEncodeZeroValue = true
                }
                var marker = pair.marker
                if template.applyMask6ValueMarkerOverrides,
                   (binding.lane == .cc2 || binding.lane == .cc3),
                   let cc2 = lock.cc2,
                   let cc3 = lock.cc3,
                   let override = track11Mask6MarkerOverride(cc2: cc2, cc3: cc3) {
                    marker = binding.lane == .cc2 ? override.cc2 : override.cc3
                }
                lockEntry[binding.markerOffset] = marker
                if pair.value == 0,
                   binding.zeroOmitsValueByte {
                    lockEntry.remove(at: binding.valueOffset)
                } else {
                    lockEntry[binding.valueOffset] = pair.value
                }
            }
            entries[entryTemplate.slot] = lockEntry
        }

        if didEncodeZeroValue {
            for (slot, delta) in template.zeroMetadataAdjustments {
                guard let current = metadataWords[slot] else { continue }
                let next = Int(current) + delta
                guard (0...0xFFFF).contains(next) else { return nil }
                metadataWords[slot] = UInt16(next)
            }
        }
        for (metaSlot, metaWord) in metadataWords {
            entries[metaSlot] = track11MetadataEntry(word: metaWord)
        }
        let compactPrefixBytes = track11CompactLockPrefix(maxUsedSlot: entries.keys.max())
        let suffixBytes = template.lockRegionSuffix ?? compactPrefixBytes
        return Track11LockSynthesisResult(
            tableBytes: buildTrack11LockTableBytes(entries: entries),
            compactPrefixBytes: suffixBytes
        )
    }

    private static func track11MetadataEntry(word: UInt16) -> [UInt8] {
        [UInt8(word & 0x00FF), UInt8((word >> 8) & 0x00FF), 0x00, 0x00]
    }

    private static func track11LockTopologyTemplate(for stepLocks: [Track11StepLock]) -> Track11LockTopologyTemplate? {
        let canonical = stepLocks.sorted { lhs, rhs in
            if lhs.step == rhs.step { return lhs.laneMask < rhs.laneMask }
            return lhs.step < rhs.step
        }

        if canonical.count == 1,
           let lock = canonical.first,
           lock.laneMask == 0x01 || lock.laneMask == 0x02 {
            let lane: Track11LockLane = lock.laneMask == 0x01 ? .cc1 : .cc2
            return track11SingleLaneTemplate(step: lock.step, lane: lane)
        }

        let key = track11TopologyKey(for: canonical)
        if let exact = track11CapturedTopologyTemplate(key: key) {
            return exact
        }

        // Transplant is explicitly opt-in because it can encode only a captured
        // subset of the requested mask-6 topology.
        let lockStrategy = (ProcessInfo.processInfo.environment["CHOIR_XY_LOCK_STRATEGY"] ?? "").lowercased()
        let shouldApplyMask6SubsetFallback: Bool = {
            switch lockStrategy {
            case "transplant":
                return true
            case "", "strict":
                return false
            default:
                return false
            }
        }()
        if shouldApplyMask6SubsetFallback,
           canonical.allSatisfy({ $0.laneMask == 0x06 }) {
            let requestedSteps = Set(canonical.map(\.step))
            if let subsetKey = bestCapturedMask6SubsetTopologyKey(for: requestedSteps) {
                return track11CapturedTopologyTemplate(key: subsetKey)
            }
        }

        return nil
    }

    // Captured mask-6 keys used for fallback subset matching.
    private static let track11CapturedMask6FallbackKeys: [String] = [
        "3:6",
        "1:6",
        "4:6",
        "8:6",
        "16:6",
        "17:6",
        "20:6",
        "24:6",
        "29:6",
        "30:6",
        "33:6",
        "36:6",
        "40:6",
        "46:6",
        "49:6",
        "51:6",
        "52:6",
        "55:6",
        "63:6",
        "64:6",
        "1:6|4:6",
        "1:6|8:6|16:6",
        "17:6|20:6|24:6",
        "29:6|30:6|33:6|36:6",
        "46:6|49:6|51:6|52:6|55:6",
        "63:6|64:6",
        "1:6|4:6|8:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6",
        "1:6|2:6|4:6|8:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6",
        "1:6|2:6|4:6|6:6|8:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6",
        "1:6|2:6|4:6|6:6|7:6|8:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6",
        "1:6|4:6|7:6|8:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6",
        "1:6|4:6|7:6|8:6|11:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6",
        "1:6|2:6|4:6|7:6|8:6|11:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6",
        "1:6|2:6|4:6|6:6|7:6|8:6|11:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6",
        "1:6|2:6|4:6|6:6|7:6|8:6|11:6|14:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6"
    ]

    private static func bestCapturedMask6SubsetTopologyKey(for requestedSteps: Set<Int>) -> String? {
        var bestKey: String?
        var bestCount: Int = -1
        for key in track11CapturedMask6FallbackKeys {
            guard let candidateSteps = track11Mask6Steps(fromTopologyKey: key) else { continue }
            guard candidateSteps.isSubset(of: requestedSteps) else { continue }
            let count = candidateSteps.count
            if count > bestCount {
                bestCount = count
                bestKey = key
                continue
            }
            if count == bestCount, let current = bestKey, key < current {
                bestKey = key
            }
        }
        return bestKey
    }

    private static func track11Mask6Steps(fromTopologyKey key: String) -> Set<Int>? {
        let pairs = key.split(separator: "|")
        guard !pairs.isEmpty else { return nil }
        var steps: Set<Int> = []
        for pair in pairs {
            let parts = pair.split(separator: ":")
            guard parts.count == 2,
                  let step = Int(parts[0]),
                  let laneMask = Int(parts[1]),
                  laneMask == 0x06 else {
                return nil
            }
            steps.insert(step)
        }
        return steps
    }

    private static func track11TopologyKey(for stepLocks: [Track11StepLock]) -> String {
        stepLocks
            .sorted { lhs, rhs in
                if lhs.step == rhs.step { return lhs.laneMask < rhs.laneMask }
                return lhs.step < rhs.step
            }
            .map { "\($0.step):\($0.laneMask)" }
            .joined(separator: "|")
    }

    private static func makeTrack11SingleLaneTopologyTemplate(
        step: Int,
        lane: Track11LockLane,
        slot: Int,
        bytes: [UInt8],
        markerOffset: Int,
        valueOffset: Int,
        nonZeroMarker: UInt8,
        zeroMarker: UInt8?,
        zeroOmitsValueByte: Bool = false,
        metadata: [Int: UInt16],
        zeroMetadataAdjustments: [Int: Int] = [:]
    ) -> Track11LockTopologyTemplate {
        Track11LockTopologyTemplate(
            entries: [
                Track11LockEntryTemplate(
                    slot: slot,
                    bytes: bytes,
                    bindings: [
                        Track11LaneBindingTemplate(
                            step: step,
                            lane: lane,
                            markerOffset: markerOffset,
                            valueOffset: valueOffset,
                            nonZeroMarker: nonZeroMarker,
                            zeroMarker: zeroMarker,
                            zeroOmitsValueByte: zeroOmitsValueByte
                        )
                    ]
                )
            ],
            metadata: metadata,
            zeroMetadataAdjustments: zeroMetadataAdjustments
        )
    }

    private static func makeTrack11Mask6TopologyTemplate(
        entries: [(step: Int, slot: Int, bytes: [UInt8])],
        metadata: [Int: UInt16],
        lockRegionSuffix: [UInt8]? = nil,
        applyMask6ValueMarkerOverrides: Bool = true
    ) -> Track11LockTopologyTemplate {
        Track11LockTopologyTemplate(
            entries: entries.map { entry in
                Track11LockEntryTemplate(
                    slot: entry.slot,
                    bytes: entry.bytes,
                    bindings: [
                        Track11LaneBindingTemplate(
                            step: entry.step,
                            lane: .cc2,
                            markerOffset: 1,
                            valueOffset: 2,
                            nonZeroMarker: entry.bytes[1],
                            zeroMarker: nil
                        ),
                        Track11LaneBindingTemplate(
                            step: entry.step,
                            lane: .cc3,
                            markerOffset: 3,
                            valueOffset: 4,
                            nonZeroMarker: entry.bytes[3],
                            zeroMarker: nil
                        )
                    ]
                )
            },
            metadata: metadata,
            lockRegionSuffix: lockRegionSuffix,
            applyMask6ValueMarkerOverrides: applyMask6ValueMarkerOverrides
        )
    }

    private static func track11SingleLaneTemplate(step: Int, lane: Track11LockLane) -> Track11LockTopologyTemplate? {
        // Capture-backed single-lane templates from `dderuntz-saves3/08a`.
        switch (step, lane) {
        case (1, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 1, lane: .cc1, slot: 2, bytes: [0x18, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: 0x7F, zeroOmitsValueByte: true,
                metadata: [44: 0x01C4, 48: 0x01FA], zeroMetadataAdjustments: [44: 1]
            )
        case (2, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 2, lane: .cc1, slot: 2, bytes: [0x6C, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [44: 0x0178, 48: 0x01F2]
            )
        case (3, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 3, lane: .cc1, slot: 2, bytes: [0xC0, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x012C, 48: 0x01EA]
            )
        case (4, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 4, lane: .cc1, slot: 3, bytes: [0x13, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x01E1, 48: 0x01E2]
            )
        case (5, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 5, lane: .cc1, slot: 3, bytes: [0x67, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: 0x7F, zeroOmitsValueByte: true,
                metadata: [44: 0x0195, 48: 0x01DA], zeroMetadataAdjustments: [44: 1]
            )
        case (6, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 6, lane: .cc1, slot: 3, bytes: [0xBB, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x0149, 48: 0x01D2]
            )
        case (7, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 7, lane: .cc1, slot: 4, bytes: [0x0E, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [44: 0x01FE, 48: 0x01CA]
            )
        case (8, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 8, lane: .cc1, slot: 4, bytes: [0x62, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: 0x84, zeroOmitsValueByte: true,
                metadata: [44: 0x01B2, 48: 0x01C2], zeroMetadataAdjustments: [44: 1]
            )
        case (9, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 9, lane: .cc1, slot: 4, bytes: [0xB6, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x0166, 48: 0x01BA]
            )
        case (10, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 10, lane: .cc1, slot: 5, bytes: [0x09, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [45: 0x011A, 49: 0x01B2]
            )
        case (11, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 11, lane: .cc1, slot: 5, bytes: [0x5D, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [44: 0x01CF, 48: 0x01AA]
            )
        case (12, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 12, lane: .cc1, slot: 5, bytes: [0xB1, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: 0x7F, zeroOmitsValueByte: true,
                metadata: [44: 0x0183, 48: 0x01A2], zeroMetadataAdjustments: [44: 1]
            )
        case (13, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 13, lane: .cc1, slot: 6, bytes: [0x04, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [45: 0x0137, 49: 0x019A]
            )
        case (14, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 14, lane: .cc1, slot: 6, bytes: [0x58, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x01EC, 48: 0x0192]
            )
        case (15, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 15, lane: .cc1, slot: 6, bytes: [0xAC, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [44: 0x01A0, 48: 0x018A]
            )
        case (16, .cc1):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 16, lane: .cc1, slot: 6, bytes: [0xFF, 0x00, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 2, valueOffset: 3, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x0154, 48: 0x0182]
            )
        case (1, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 1, lane: .cc2, slot: 2, bytes: [0x1A, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [44: 0x02C2, 48: 0x02FA]
            )
        case (2, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 2, lane: .cc2, slot: 2, bytes: [0x6E, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [44: 0x0276, 48: 0x02F2]
            )
        case (3, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 3, lane: .cc2, slot: 2, bytes: [0xC2, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: 0x7F, zeroOmitsValueByte: true,
                metadata: [44: 0x022A, 48: 0x02EA], zeroMetadataAdjustments: [44: 1]
            )
        case (4, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 4, lane: .cc2, slot: 3, bytes: [0x15, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x02DF, 48: 0x02E2]
            )
        case (5, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 5, lane: .cc2, slot: 3, bytes: [0x69, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: 0x7F, zeroOmitsValueByte: true,
                metadata: [44: 0x0293, 48: 0x02DA], zeroMetadataAdjustments: [44: 1]
            )
        case (6, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 6, lane: .cc2, slot: 3, bytes: [0xBD, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [44: 0x0247, 48: 0x02D2]
            )
        case (7, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 7, lane: .cc2, slot: 4, bytes: [0x10, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x02FC, 48: 0x02CA]
            )
        case (8, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 8, lane: .cc2, slot: 4, bytes: [0x64, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [44: 0x02B0, 48: 0x02C2]
            )
        case (9, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 9, lane: .cc2, slot: 4, bytes: [0xB8, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x0264, 48: 0x02BA]
            )
        case (10, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 10, lane: .cc2, slot: 5, bytes: [0x0B, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [45: 0x0218, 49: 0x02B2]
            )
        case (11, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 11, lane: .cc2, slot: 5, bytes: [0x5F, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x02CD, 48: 0x02AA]
            )
        case (12, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 12, lane: .cc2, slot: 5, bytes: [0xB3, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x0281, 48: 0x02A2]
            )
        case (13, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 13, lane: .cc2, slot: 6, bytes: [0x06, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [45: 0x0235, 49: 0x029A]
            )
        case (14, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 14, lane: .cc2, slot: 6, bytes: [0x5A, 0xD4, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil,
                metadata: [44: 0x02EA, 48: 0x0292]
            )
        case (15, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 15, lane: .cc2, slot: 6, bytes: [0xAE, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [44: 0x029E, 48: 0x028A]
            )
        case (16, .cc2):
            return makeTrack11SingleLaneTopologyTemplate(
                step: 16, lane: .cc2, slot: 7, bytes: [0x01, 0x29, 0x10, 0x00, 0x00],
                markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil,
                metadata: [45: 0x0252, 49: 0x0282]
            )
        default:
            return nil
        }
    }

    private static func track11CapturedTopologyTemplate(key: String) -> Track11LockTopologyTemplate? {
        // Capture-backed topologies from `dderuntz-saves3/08a`:
        // - A4 multi-lane step-3 masks
        // - A5 non-prefix multi-step CC1 sets
        // Capture-backed mask-6 (CC2+CC3) matrix from `dderuntz-saves08b`:
        // - B1 isolated single-step set
        // - B2 cumulative multi-step sets (including full Robots-like topology)
        switch key {
        case "3:3":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0xC0, 0xD4, 0x40, 0x29, 0x20, 0x00, 0x00],
                        bindings: [
                            Track11LaneBindingTemplate(step: 3, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil),
                            Track11LaneBindingTemplate(step: 3, lane: .cc2, markerOffset: 3, valueOffset: 4, nonZeroMarker: 0x29, zeroMarker: nil)
                        ]
                    )
                ],
                metadata: [44: 0x032A, 48: 0x03EA]
            )
        case "3:7":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0xC0, 0x2A, 0x40, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00],
                        bindings: [
                            Track11LaneBindingTemplate(step: 3, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x2A, zeroMarker: nil),
                            Track11LaneBindingTemplate(step: 3, lane: .cc2, markerOffset: 3, valueOffset: 4, nonZeroMarker: 0xD4, zeroMarker: nil),
                            Track11LaneBindingTemplate(step: 3, lane: .cc3, markerOffset: 5, valueOffset: 6, nonZeroMarker: 0x29, zeroMarker: nil)
                        ]
                    )
                ],
                metadata: [44: 0x0728, 48: 0x07EA]
            )
        case "3:15":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0xC0, 0xD5, 0x40, 0x29, 0x20, 0xD4, 0x10, 0xD4, 0x08, 0x00, 0x00],
                        bindings: [
                            Track11LaneBindingTemplate(step: 3, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD5, zeroMarker: nil),
                            Track11LaneBindingTemplate(step: 3, lane: .cc2, markerOffset: 3, valueOffset: 4, nonZeroMarker: 0x29, zeroMarker: nil),
                            Track11LaneBindingTemplate(step: 3, lane: .cc3, markerOffset: 5, valueOffset: 6, nonZeroMarker: 0xD4, zeroMarker: nil),
                            Track11LaneBindingTemplate(step: 3, lane: .cc4, markerOffset: 7, valueOffset: 8, nonZeroMarker: 0xD4, zeroMarker: nil)
                        ]
                    )
                ],
                metadata: [44: 0x0F26, 48: 0x0FEA]
            )
        case "3:6":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0xC2, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00],
                        bindings: [
                            Track11LaneBindingTemplate(step: 3, lane: .cc2, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil),
                            Track11LaneBindingTemplate(step: 3, lane: .cc3, markerOffset: 3, valueOffset: 4, nonZeroMarker: 0x29, zeroMarker: nil)
                        ]
                    )
                ],
                metadata: [44: 0x0628, 48: 0x06EA]
            )
        case "3:10":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0xC2, 0xD4, 0x20, 0x00, 0x00],
                        bindings: [
                            Track11LaneBindingTemplate(step: 3, lane: .cc2, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil)
                        ]
                    ),
                    Track11LockEntryTemplate(
                        slot: 3,
                        bytes: [0x00, 0x29, 0x08, 0x00, 0x00],
                        bindings: [
                            Track11LaneBindingTemplate(step: 3, lane: .cc4, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)
                        ]
                    )
                ],
                metadata: [45: 0x0A26, 49: 0x0AEA]
            )
        case "1:1|3:1":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0x18, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 1, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    ),
                    Track11LockEntryTemplate(
                        slot: 3,
                        bytes: [0xA4, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 3, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    )
                ],
                metadata: [45: 0x011C, 46: 0x010D, 50: 0x01EA]
            )
        case "1:1|5:1":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0x18, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 1, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    ),
                    Track11LockEntryTemplate(
                        slot: 4,
                        bytes: [0x4B, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 5, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    )
                ],
                metadata: [45: 0x0175, 46: 0x011D, 50: 0x01DA]
            )
        case "1:1|8:1":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0x18, 0xD4, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 1, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil)]
                    ),
                    Track11LockEntryTemplate(
                        slot: 5,
                        bytes: [0x46, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 8, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    )
                ],
                metadata: [45: 0x017A, 46: 0x0135, 50: 0x01C2]
            )
        case "1:1|12:1":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0x18, 0xD4, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 1, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil)]
                    ),
                    Track11LockEntryTemplate(
                        slot: 6,
                        bytes: [0x95, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 12, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    )
                ],
                metadata: [45: 0x012B, 46: 0x0155, 50: 0x01A2]
            )
        case "3:1|8:1":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0xC0, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 3, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    ),
                    Track11LockEntryTemplate(
                        slot: 4,
                        bytes: [0x9F, 0xD4, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 8, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil)]
                    )
                ],
                metadata: [44: 0x018A, 45: 0x0125, 49: 0x01C2]
            )
        case "5:1|12:1":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 3,
                        bytes: [0x67, 0xD4, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 5, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil)]
                    ),
                    Track11LockEntryTemplate(
                        slot: 6,
                        bytes: [0x46, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 12, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    )
                ],
                metadata: [45: 0x014B, 46: 0x0135, 50: 0x01A2]
            )
        case "1:1|3:1|5:1":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0x18, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 1, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    ),
                    Track11LockEntryTemplate(
                        slot: 3,
                        bytes: [0xA4, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 3, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    ),
                    Track11LockEntryTemplate(
                        slot: 4,
                        bytes: [0xA4, 0xD4, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 5, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil)]
                    )
                ],
                metadata: [45: 0x0175, 46: 0x010D, 47: 0x010D, 51: 0x01DA]
            )
        case "1:1|5:1|9:1|13:1":
            return Track11LockTopologyTemplate(
                entries: [
                    Track11LockEntryTemplate(
                        slot: 2,
                        bytes: [0x18, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 1, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    ),
                    Track11LockEntryTemplate(
                        slot: 4,
                        bytes: [0x4B, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 5, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    ),
                    Track11LockEntryTemplate(
                        slot: 6,
                        bytes: [0x4B, 0x29, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 9, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0x29, zeroMarker: nil)]
                    ),
                    Track11LockEntryTemplate(
                        slot: 8,
                        bytes: [0x4B, 0xD4, 0x10, 0x00, 0x00],
                        bindings: [Track11LaneBindingTemplate(step: 13, lane: .cc1, markerOffset: 1, valueOffset: 2, nonZeroMarker: 0xD4, zeroMarker: nil)]
                    )
                ],
                metadata: [46: 0x01D8, 47: 0x011D, 48: 0x011D, 49: 0x011D, 53: 0x019A]
            )
        case "1:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 1, slot: 2, bytes: [0x1A, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00])],
                metadata: [44: 0x06C0, 48: 0x06FA]
            )
        case "4:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 4, slot: 3, bytes: [0x15, 0x29, 0x20, 0xD4, 0x10, 0x00, 0x00])],
                metadata: [44: 0x06DD, 48: 0x06E2]
            )
        case "8:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 8, slot: 4, bytes: [0x64, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00])],
                metadata: [44: 0x06AE, 48: 0x06C2]
            )
        case "16:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 16, slot: 7, bytes: [0x01, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00])],
                metadata: [45: 0x0650, 49: 0x0682]
            )
        case "17:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 17, slot: 7, bytes: [0x55, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00])],
                metadata: [45: 0x0604, 49: 0x067A]
            )
        case "20:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 20, slot: 8, bytes: [0x50, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00])],
                metadata: [45: 0x0621, 49: 0x0662]
            )
        case "24:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 24, slot: 9, bytes: [0x9F, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00])],
                metadata: [44: 0x06F3, 48: 0x0642]
            )
        case "29:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 29, slot: 11, bytes: [0x41, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00])],
                metadata: [45: 0x0678, 49: 0x061A]
            )
        case "30:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 30, slot: 11, bytes: [0x95, 0x29, 0x20, 0xD4, 0x10, 0x00, 0x00])],
                metadata: [45: 0x062C, 49: 0x0612]
            )
        case "33:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 33, slot: 12, bytes: [0x90, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00])],
                metadata: [45: 0x0649, 48: 0x06FB]
            )
        case "36:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 36, slot: 13, bytes: [0x8B, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00])],
                metadata: [45: 0x0666, 48: 0x06E3]
            )
        case "40:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 40, slot: 14, bytes: [0xDA, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00])],
                metadata: [45: 0x0637, 48: 0x06C3]
            )
        case "46:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 46, slot: 16, bytes: [0xD0, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00])],
                metadata: [45: 0x0671, 48: 0x0693]
            )
        case "49:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 49, slot: 17, bytes: [0xCB, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00])],
                metadata: [45: 0x068E, 48: 0x067B]
            )
        case "51:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 51, slot: 18, bytes: [0x72, 0x29, 0x20, 0xD4, 0x10, 0x00, 0x00])],
                metadata: [45: 0x06F7, 48: 0x066B]
            )
        case "52:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 52, slot: 18, bytes: [0xC6, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00])],
                metadata: [45: 0x06AB, 48: 0x0663]
            )
        case "55:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 55, slot: 20, bytes: [0x68, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00])],
                metadata: [46: 0x0630, 49: 0x063B]
            )
        case "63:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 63, slot: 22, bytes: [0x5E, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00])],
                metadata: [46: 0x066A, 49: 0x060B]
            )
        case "64:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [(step: 64, slot: 22, bytes: [0xB2, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00])],
                metadata: [46: 0x061E, 49: 0x0603]
            )
        case "1:6|4:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 1, slot: 2, bytes: [0x1A, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 4, slot: 3, bytes: [0xF6, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00])
                ],
                metadata: [44: 0x06C5, 45: 0x0615, 49: 0x06E2]
            )
        case "1:6|8:6|16:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 1, slot: 2, bytes: [0x1A, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 8, slot: 5, bytes: [0x44, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 16, slot: 8, bytes: [0x98, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00])
                ],
                metadata: [45: 0x06D9, 46: 0x0635, 47: 0x063D, 51: 0x0682]
            )
        case "17:6|20:6|24:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 17, slot: 7, bytes: [0x55, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 20, slot: 8, bytes: [0xF6, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 24, slot: 10, bytes: [0x49, 0x29, 0x20, 0xD4, 0x10, 0x00, 0x00])
                ],
                metadata: [45: 0x06BB, 46: 0x0615, 47: 0x061D, 51: 0x0642]
            )
        case "29:6|30:6|33:6|36:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 29, slot: 11, bytes: [0x41, 0x29, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 30, slot: 12, bytes: [0x4E, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 33, slot: 13, bytes: [0xF6, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 36, slot: 14, bytes: [0xF6, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00])
                ],
                metadata: [46: 0x062E, 47: 0x0605, 48: 0x0615, 49: 0x0615, 52: 0x06E3]
            )
        case "46:6|49:6|51:6|52:6|55:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 46, slot: 16, bytes: [0xD0, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 49, slot: 17, bytes: [0xF6, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 51, slot: 18, bytes: [0xA2, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 52, slot: 19, bytes: [0x4E, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 55, slot: 20, bytes: [0xF6, 0x29, 0x20, 0xD4, 0x10, 0x00, 0x00])
                ],
                metadata: [46: 0x0680, 47: 0x0615, 48: 0x060D, 49: 0x0605, 50: 0x0615, 53: 0x064B]
            )
        case "63:6|64:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 63, slot: 22, bytes: [0x5E, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 64, slot: 23, bytes: [0x4E, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00])
                ],
                metadata: [47: 0x0616, 48: 0x0605, 51: 0x0603]
            )
        case "1:6|2:6|4:6|8:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 1, slot: 2, bytes: [0x1A, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 2, slot: 3, bytes: [0x4E, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 4, slot: 4, bytes: [0xA2, 0x2A, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 8, slot: 6, bytes: [0x49, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 16, slot: 9, bytes: [0x98, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 17, slot: 10, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 20, slot: 11, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 24, slot: 13, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 29, slot: 15, bytes: [0x9D, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 30, slot: 16, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 33, slot: 17, bytes: [0xF6, 0x29, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 36, slot: 18, bytes: [0xF6, 0xD4, 0x04, 0x29, 0x08, 0x00, 0x00]),
                    (step: 40, slot: 20, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 46, slot: 22, bytes: [0xF1, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 49, slot: 23, bytes: [0xF6, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 51, slot: 24, bytes: [0xA2, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 52, slot: 25, bytes: [0x4E, 0xD4, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 55, slot: 26, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 63, slot: 29, bytes: [0x98, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 64, slot: 30, bytes: [0x4E, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00])
                ],
                metadata: [52: 0x0628, 53: 0x0605, 54: 0x060D],
                lockRegionSuffix: [
                    0x1D, 0x06, 0x00, 0x00, 0x3D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x1D, 0x06, 0x00, 0x00, 0x25, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00, 0x2D, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x3D, 0x06, 0x00, 0x00,
                    0x05, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x03, 0x06, 0x00, 0x00, 0xFF, 0x00,
                    0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00,
                    0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x09
                ],
                applyMask6ValueMarkerOverrides: false
            )
        case "1:6|2:6|4:6|6:6|8:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 1, slot: 2, bytes: [0x1A, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 2, slot: 3, bytes: [0x4E, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 4, slot: 4, bytes: [0xA2, 0x2A, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 6, slot: 5, bytes: [0xA2, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 8, slot: 6, bytes: [0xA2, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 16, slot: 9, bytes: [0x98, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 17, slot: 10, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 20, slot: 11, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 24, slot: 13, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 29, slot: 15, bytes: [0x9D, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 30, slot: 16, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 33, slot: 17, bytes: [0xF6, 0x29, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 36, slot: 18, bytes: [0xF6, 0xD4, 0x04, 0x29, 0x08, 0x00, 0x00]),
                    (step: 40, slot: 20, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 46, slot: 22, bytes: [0xF1, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 49, slot: 23, bytes: [0xF6, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 51, slot: 24, bytes: [0xA2, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 52, slot: 25, bytes: [0x4E, 0xD4, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 55, slot: 26, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 63, slot: 29, bytes: [0x98, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 64, slot: 30, bytes: [0x4E, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00])
                ],
                metadata: [52: 0x0628, 53: 0x0605, 54: 0x060D],
                lockRegionSuffix: [
                    0x0D, 0x06, 0x00, 0x00, 0x0D, 0x06, 0x00, 0x00, 0x3D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00, 0x25, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00, 0x2D, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x3D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x03, 0x06,
                    0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00,
                    0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x09
                ],
                applyMask6ValueMarkerOverrides: false
            )
        case "1:6|2:6|4:6|6:6|7:6|8:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 1, slot: 2, bytes: [0x1A, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 2, slot: 3, bytes: [0x4E, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 4, slot: 4, bytes: [0xA2, 0x2A, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 6, slot: 5, bytes: [0xA2, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 7, slot: 6, bytes: [0x4E, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 8, slot: 7, bytes: [0x4E, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 16, slot: 10, bytes: [0x98, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 17, slot: 11, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 20, slot: 12, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 24, slot: 14, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 29, slot: 16, bytes: [0x9D, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 30, slot: 17, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 33, slot: 18, bytes: [0xF6, 0x29, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 36, slot: 19, bytes: [0xF6, 0xD4, 0x04, 0x29, 0x08, 0x00, 0x00]),
                    (step: 40, slot: 21, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 46, slot: 23, bytes: [0xF1, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 49, slot: 24, bytes: [0xF6, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 51, slot: 25, bytes: [0xA2, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 52, slot: 26, bytes: [0x4E, 0xD4, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 55, slot: 27, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 63, slot: 30, bytes: [0x98, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 64, slot: 31, bytes: [0x4E, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00])
                ],
                metadata: [53: 0x0630, 54: 0x060D],
                lockRegionSuffix: [
                    0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x3D, 0x06, 0x00, 0x00,
                    0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00, 0x25, 0x06, 0x00, 0x00,
                    0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00,
                    0x2D, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x3D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF,
                    0x00, 0x00, 0x03, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF,
                    0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x09
                ],
                applyMask6ValueMarkerOverrides: false
            )
        case "1:6|4:6|7:6|8:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 1, slot: 2, bytes: [0x1A, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 4, slot: 3, bytes: [0xF6, 0x2A, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 7, slot: 4, bytes: [0xF6, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 8, slot: 5, bytes: [0x4E, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 16, slot: 8, bytes: [0x98, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 17, slot: 9, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 20, slot: 10, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 24, slot: 12, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 29, slot: 14, bytes: [0x9D, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 30, slot: 15, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 33, slot: 16, bytes: [0xF6, 0x29, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 36, slot: 17, bytes: [0xF6, 0xD4, 0x04, 0x29, 0x08, 0x00, 0x00]),
                    (step: 40, slot: 19, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 46, slot: 21, bytes: [0xF1, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 49, slot: 22, bytes: [0xF6, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 51, slot: 23, bytes: [0xA2, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 52, slot: 24, bytes: [0x4E, 0xD4, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 55, slot: 25, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 63, slot: 28, bytes: [0x98, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 64, slot: 29, bytes: [0x4E, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00])
                ],
                metadata: [51: 0x0628, 52: 0x0615, 53: 0x0615, 54: 0x0605],
                lockRegionSuffix: [
                    0x3D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00,
                    0x25, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x1D, 0x06, 0x00, 0x00, 0x2D, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x0D, 0x06, 0x00, 0x00,
                    0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x3D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00,
                    0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x03, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00,
                    0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF,
                    0x00, 0x00, 0x09
                ],
                applyMask6ValueMarkerOverrides: false
            )
        case "1:6|4:6|7:6|8:6|11:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 1, slot: 2, bytes: [0x1A, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 4, slot: 3, bytes: [0xF6, 0x2A, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 7, slot: 4, bytes: [0xF6, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 8, slot: 5, bytes: [0x4E, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 11, slot: 6, bytes: [0xF6, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 16, slot: 8, bytes: [0x9D, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 17, slot: 9, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 20, slot: 10, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 24, slot: 12, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 29, slot: 14, bytes: [0x9D, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 30, slot: 15, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 33, slot: 16, bytes: [0xF6, 0x29, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 36, slot: 17, bytes: [0xF6, 0xD4, 0x04, 0x29, 0x08, 0x00, 0x00]),
                    (step: 40, slot: 19, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 46, slot: 21, bytes: [0xF1, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 49, slot: 22, bytes: [0xF6, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 51, slot: 23, bytes: [0xA2, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 52, slot: 24, bytes: [0x4E, 0xD4, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 55, slot: 25, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 63, slot: 28, bytes: [0x98, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 64, slot: 29, bytes: [0x4E, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00])
                ],
                metadata: [51: 0x0628, 52: 0x0615, 53: 0x0615, 54: 0x0605],
                lockRegionSuffix: [
                    0x15, 0x06, 0x00, 0x00, 0x25, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x1D, 0x06, 0x00, 0x00, 0x25, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00, 0x2D, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x3D, 0x06, 0x00, 0x00,
                    0x05, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x03, 0x06, 0x00, 0x00, 0xFF, 0x00,
                    0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00,
                    0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x09
                ],
                applyMask6ValueMarkerOverrides: false
            )
        case "1:6|2:6|4:6|7:6|8:6|11:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 1, slot: 2, bytes: [0x1A, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 2, slot: 3, bytes: [0x4E, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 4, slot: 4, bytes: [0xA2, 0x2A, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 7, slot: 5, bytes: [0xF6, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 8, slot: 6, bytes: [0x4E, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 11, slot: 7, bytes: [0xF6, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 16, slot: 9, bytes: [0x9D, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 17, slot: 10, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 20, slot: 11, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 24, slot: 13, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 29, slot: 15, bytes: [0x9D, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 30, slot: 16, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 33, slot: 17, bytes: [0xF6, 0x29, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 36, slot: 18, bytes: [0xF6, 0xD4, 0x04, 0x29, 0x08, 0x00, 0x00]),
                    (step: 40, slot: 20, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 46, slot: 22, bytes: [0xF1, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 49, slot: 23, bytes: [0xF6, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 51, slot: 24, bytes: [0xA2, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 52, slot: 25, bytes: [0x4E, 0xD4, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 55, slot: 26, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 63, slot: 29, bytes: [0x98, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 64, slot: 30, bytes: [0x4E, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00])
                ],
                metadata: [52: 0x0628, 53: 0x0605, 54: 0x060D],
                lockRegionSuffix: [
                    0x15, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x25, 0x06, 0x00, 0x00,
                    0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00, 0x25, 0x06, 0x00, 0x00,
                    0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00,
                    0x2D, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x3D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF,
                    0x00, 0x00, 0x03, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF,
                    0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x09
                ],
                applyMask6ValueMarkerOverrides: false
            )
        case "1:6|2:6|4:6|6:6|7:6|8:6|11:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 1, slot: 2, bytes: [0x1A, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 2, slot: 3, bytes: [0x4E, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 4, slot: 4, bytes: [0xA2, 0x2A, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 6, slot: 5, bytes: [0xA2, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 7, slot: 6, bytes: [0x4E, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 8, slot: 7, bytes: [0x4E, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 11, slot: 8, bytes: [0xF6, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 16, slot: 10, bytes: [0x9D, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 17, slot: 11, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 20, slot: 12, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 24, slot: 14, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 29, slot: 16, bytes: [0x9D, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 30, slot: 17, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 33, slot: 18, bytes: [0xF6, 0x29, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 36, slot: 19, bytes: [0xF6, 0xD4, 0x04, 0x29, 0x08, 0x00, 0x00]),
                    (step: 40, slot: 21, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 46, slot: 23, bytes: [0xF1, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 49, slot: 24, bytes: [0xF6, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 51, slot: 25, bytes: [0xA2, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 52, slot: 26, bytes: [0x4E, 0xD4, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 55, slot: 27, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 63, slot: 30, bytes: [0x98, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 64, slot: 31, bytes: [0x4E, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00])
                ],
                metadata: [53: 0x0628, 54: 0x0605],
                lockRegionSuffix: [
                    0x0D, 0x06, 0x00, 0x00, 0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x25, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x1D, 0x06, 0x00, 0x00, 0x25, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00, 0x2D, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x3D, 0x06, 0x00, 0x00,
                    0x05, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x03, 0x06, 0x00, 0x00, 0xFF, 0x00,
                    0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00,
                    0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x09
                ],
                applyMask6ValueMarkerOverrides: false
            )
        case "1:6|2:6|4:6|6:6|7:6|8:6|11:6|14:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 1, slot: 2, bytes: [0x1A, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 2, slot: 3, bytes: [0x4E, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 4, slot: 4, bytes: [0xA2, 0x2A, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 6, slot: 5, bytes: [0xA2, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 7, slot: 6, bytes: [0x4E, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 8, slot: 7, bytes: [0x4E, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 11, slot: 8, bytes: [0xF6, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 14, slot: 9, bytes: [0xF6, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 16, slot: 10, bytes: [0xA2, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 17, slot: 11, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 20, slot: 12, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x08, 0x00, 0x00]),
                    (step: 24, slot: 14, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 29, slot: 16, bytes: [0x9D, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 30, slot: 17, bytes: [0x4E, 0xD4, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 33, slot: 18, bytes: [0xF6, 0x29, 0x59, 0x29, 0x26, 0x00, 0x00]),
                    (step: 36, slot: 19, bytes: [0xF6, 0xD4, 0x04, 0x29, 0x08, 0x00, 0x00]),
                    (step: 40, slot: 21, bytes: [0x49, 0x29, 0x5C, 0xD4, 0x79, 0x00, 0x00]),
                    (step: 46, slot: 23, bytes: [0xF1, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 49, slot: 24, bytes: [0xF6, 0xD4, 0x59, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 51, slot: 25, bytes: [0xA2, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 52, slot: 26, bytes: [0x4E, 0xD4, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 55, slot: 27, bytes: [0xF6, 0x29, 0x04, 0xD4, 0x26, 0x00, 0x00]),
                    (step: 63, slot: 30, bytes: [0x98, 0x29, 0x5C, 0x29, 0x79, 0x00, 0x00]),
                    (step: 64, slot: 31, bytes: [0x4E, 0x29, 0x59, 0xD4, 0x26, 0x00, 0x00])
                ],
                metadata: [53: 0x0628, 54: 0x0605],
                lockRegionSuffix: [
                    0x0D, 0x06, 0x00, 0x00, 0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00, 0x25, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00, 0x2D, 0x06, 0x00, 0x00,
                    0x15, 0x06, 0x00, 0x00, 0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00,
                    0x3D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x03, 0x06,
                    0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00,
                    0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x09
                ],
                applyMask6ValueMarkerOverrides: false
            )
        case "1:6|4:6|8:6|16:6|17:6|20:6|24:6|29:6|30:6|33:6|36:6|40:6|46:6|49:6|51:6|52:6|55:6|63:6|64:6":
            return makeTrack11Mask6TopologyTemplate(
                entries: [
                    (step: 1, slot: 2, bytes: [0x1A, 0x29, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 4, slot: 3, bytes: [0xF6, 0x29, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 8, slot: 5, bytes: [0x49, 0x29, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 16, slot: 8, bytes: [0x98, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 17, slot: 9, bytes: [0x4E, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 20, slot: 10, bytes: [0xF6, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 24, slot: 12, bytes: [0x49, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 29, slot: 14, bytes: [0x9D, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 30, slot: 15, bytes: [0x4E, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 33, slot: 16, bytes: [0xF6, 0x29, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 36, slot: 17, bytes: [0xF6, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 40, slot: 19, bytes: [0x49, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 46, slot: 21, bytes: [0xF1, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 49, slot: 22, bytes: [0xF6, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 51, slot: 23, bytes: [0xA2, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 52, slot: 24, bytes: [0x4E, 0x29, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 55, slot: 25, bytes: [0xF6, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00]),
                    (step: 63, slot: 28, bytes: [0x98, 0xD4, 0x20, 0xD4, 0x10, 0x00, 0x00]),
                    (step: 64, slot: 29, bytes: [0x4E, 0xD4, 0x20, 0x29, 0x10, 0x00, 0x00])
                ],
                metadata: [51: 0x0628, 52: 0x0615, 53: 0x061D, 54: 0x063D],
                lockRegionSuffix: [
                0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00, 0x25, 0x06, 0x00, 0x00,
                0x05, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x1D, 0x06, 0x00, 0x00,
                0x2D, 0x06, 0x00, 0x00, 0x15, 0x06, 0x00, 0x00, 0x0D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00,
                0x15, 0x06, 0x00, 0x00, 0x3D, 0x06, 0x00, 0x00, 0x05, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF,
                0x00, 0x00, 0x03, 0x06, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF,
                0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x09
                ]
            )
        default:
            return nil
        }
    }

    private static func track11LockValue(lock: Track11StepLock, lane: Track11LockLane) -> Int? {
        switch lane {
        case .cc1: return lock.cc1
        case .cc2: return lock.cc2
        case .cc3: return lock.cc3
        case .cc4: return lock.cc4
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

    private static func track11CompactLockPrefix(maxUsedSlot: Int?) -> [UInt8] {
        guard let maxUsedSlot else { return [] }
        guard maxUsedSlot >= 48 else { return [] }
        let emptyCount = max(0, maxUsedSlot - 46)
        var out: [UInt8] = []
        out.reserveCapacity((emptyCount * midiLockTableEmptyEntry.count) + 1)
        for _ in 0..<emptyCount {
            out += midiLockTableEmptyEntry
        }
        out.append(0x09)
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

    private static func track11Mask6MarkerOverride(
        cc2: Int,
        cc3: Int
    ) -> (cc2: UInt8, cc3: UInt8)? {
        // Capture-backed overrides from `dderuntz-saves08b` value variants:
        // 08b 27 (89,38), 08b 28 (92,121), 08b 29 (4,8).
        switch (cc2, cc3) {
        case (89, 38): return (0x29, 0xD4)
        case (92, 121): return (0xD4, 0xD4)
        case (4, 8): return (0x2A, 0x29)
        default: return nil
        }
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
        let nCC1 = try normalizedTrack11LaneValueValidated(cc1, where: "\(source).cc1")
        let nCC2 = try normalizedTrack11LaneValueValidated(cc2, where: "\(source).cc2")
        let nCC3 = try normalizedTrack11LaneValueValidated(cc3, where: "\(source).cc3")
        let nCC4 = try normalizedTrack11LaneValueValidated(cc4, where: "\(source).cc4")
        return Track11StepLock(step: step, cc1: nCC1, cc2: nCC2, cc3: nCC3, cc4: nCC4)
    }

    private static func normalizedTrack11LaneValue(_ value: Int?, defaultValue: Int) -> Int? {
        guard let value else { return nil }
        return value == defaultValue ? nil : value
    }

    private static func normalizedTrack11LaneValueValidated(
        _ value: Int?,
        where source: String
    ) throws -> Int? {
        guard let value else { return nil }
        guard (0...127).contains(value) else {
            throw XYExporterError.invalidNote("\(source) must be in [0,127]")
        }
        return value
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

    private static func canonicalizedRLEProject(_ bytes: [UInt8]) throws -> [UInt8] {
        do {
            let project = try XYRLECodec.decodeProject(bytes)
            return try XYRLECodec.encodeProject(header: project.header, image: project.image)
        } catch {
            throw XYExporterError.invalidTemplate("exported bytes are not a valid RLE .xy project: \(error.localizedDescription)")
        }
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
