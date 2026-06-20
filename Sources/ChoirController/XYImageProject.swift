import Foundation

enum XYImageProjectError: Error, LocalizedError, Equatable {
    case invalidTrack(Int)
    case invalidStep(Int)
    case invalidNote(String)
    case invalidImage(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case let .invalidTrack(track):
            "invalid OP-XY track \(track)"
        case let .invalidStep(step):
            "invalid OP-XY step \(step)"
        case let .invalidNote(message):
            "invalid OP-XY note: \(message)"
        case let .invalidImage(message):
            "invalid decoded OP-XY image: \(message)"
        case let .unsupported(message):
            "unsupported decoded OP-XY image edit: \(message)"
        }
    }
}

struct XYImageNote: Equatable {
    let tick: UInt32
    let gate: UInt32
    let note: UInt8
    let velocity: UInt8
    let flags: UInt16
}

struct XYTrack11CCLock: Equatable {
    let step: Int
    let cc1: UInt8?
    let cc2: UInt8?
    let cc3: UInt8?
    let cc4: UInt8?

    init(step: Int, cc1: UInt8? = nil, cc2: UInt8? = nil, cc3: UInt8? = nil, cc4: UInt8? = nil) {
        self.step = step
        self.cc1 = cc1
        self.cc2 = cc2
        self.cc3 = cc3
        self.cc4 = cc4
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

struct XYImageProject {
    static let trackCount = 16
    static let trackBase0 = 0x0D79
    static let trackStride = 17_876
    static let noteCountOffset = 0x456F
    static let noteSize = 12
    static let stepTicks = 480
    static let maxNotes = 120

    private static let patternStepsOffset = 0x01
    private static let pristineOffset = 0x11
    private static let globalTempoOffset = 0x00
    private static let globalGrooveTypeOffset = 0x03

    // T11 External MIDI p-lock offsets from local OP-XY captures. These are
    // intentionally T11-specific; generic synth-track p-lock docs use +0x2A0.
    private static let track11LockBase = 0x025E
    private static let track11LockStride = 84
    private static let track11StepFlagBase = 0x2C4F
    private static let track11MasterFlag = 0x304F

    private var header: [UInt8]
    private(set) var image: [UInt8]
    private var trackStarts: [Int]

    init(data: [UInt8]) throws {
        let project = try XYRLECodec.decodeProject(data)
        self.header = project.header
        self.image = project.image
        self.trackStarts = try Self.scanTrackStarts(in: project.image)
    }

    init(contentsOf url: URL) throws {
        try self.init(data: [UInt8](Data(contentsOf: url)))
    }

    func encodedBytes() throws -> [UInt8] {
        try XYRLECodec.encodeProject(header: header, image: image)
    }

    func trackStart(_ track: Int) throws -> Int {
        guard (1...Self.trackCount).contains(track) else {
            throw XYImageProjectError.invalidTrack(track)
        }
        guard trackStarts.count == Self.trackCount else {
            throw XYImageProjectError.invalidImage("expected 16 track starts, found \(trackStarts.count)")
        }
        return trackStarts[track - 1]
    }

    mutating func setTempoTenths(_ tempoTenths: Int) throws {
        guard (0...Int(UInt16.max)).contains(tempoTenths) else {
            throw XYImageProjectError.unsupported("tempo tenths must fit u16")
        }
        writeUInt16LE(UInt16(tempoTenths), at: Self.globalTempoOffset)
    }

    mutating func setGrooveType(_ grooveType: Int) {
        image[Self.globalGrooveTypeOffset] = UInt8(clamping: grooveType)
    }

    mutating func setPatternSteps(track: Int, steps: Int) throws {
        guard (1...64).contains(steps) else {
            throw XYImageProjectError.unsupported("pattern steps must be 1...64")
        }
        let start = try trackStart(track)
        image[start + Self.patternStepsOffset] = UInt8(steps)
        try markEdited(track: track)
    }

    func notes(track: Int) throws -> [XYImageNote] {
        let start = try trackStart(track)
        let countOffset = start + Self.noteCountOffset
        guard countOffset < image.count else {
            throw XYImageProjectError.invalidImage("note count offset outside image")
        }
        let count = Int(image[countOffset])
        guard count <= Self.maxNotes else {
            throw XYImageProjectError.invalidImage("note count \(count) exceeds max")
        }
        let recordsStart = countOffset + 1
        let recordsEnd = recordsStart + count * Self.noteSize
        guard recordsEnd <= image.count else {
            throw XYImageProjectError.invalidImage("note records extend outside image")
        }

        return stride(from: recordsStart, to: recordsEnd, by: Self.noteSize).map { offset in
            XYImageNote(
                tick: readUInt32LE(at: offset),
                gate: readUInt32LE(at: offset + 4),
                note: image[offset + 8],
                velocity: image[offset + 9],
                flags: readUInt16LE(at: offset + 10)
            )
        }
    }

    mutating func clearNotes(track: Int) throws {
        let start = try trackStart(track)
        let countOffset = start + Self.noteCountOffset
        guard countOffset < image.count else {
            throw XYImageProjectError.invalidImage("note count offset outside image")
        }
        let count = Int(image[countOffset])
        guard count <= Self.maxNotes else {
            throw XYImageProjectError.invalidImage("note count \(count) exceeds max")
        }
        let recordsStart = countOffset + 1
        let recordsEnd = recordsStart + count * Self.noteSize
        guard recordsEnd <= image.count else {
            throw XYImageProjectError.invalidImage("note records extend outside image")
        }
        image.removeSubrange(recordsStart..<recordsEnd)
        image[countOffset] = 0
        try markEdited(track: track)
        try rescan()
    }

    mutating func addNote(track: Int, step: Int, note: Int, velocity: Int, gateTicks: Int, tickOffset: Int = 0) throws {
        guard step >= 1 else { throw XYImageProjectError.invalidStep(step) }
        guard (0...127).contains(note) else { throw XYImageProjectError.invalidNote("note must be 0...127") }
        guard (0...127).contains(velocity) else { throw XYImageProjectError.invalidNote("velocity must be 0...127") }
        guard gateTicks >= 0 else { throw XYImageProjectError.invalidNote("gate must be non-negative") }

        let tick = (step - 1) * Self.stepTicks + tickOffset
        guard tick >= 0, tick <= Int(UInt32.max), gateTicks <= Int(UInt32.max) else {
            throw XYImageProjectError.unsupported("tick/gate must fit u32")
        }

        let start = try trackStart(track)
        let countOffset = start + Self.noteCountOffset
        let count = Int(image[countOffset])
        guard count < Self.maxNotes else {
            throw XYImageProjectError.invalidNote("pattern note limit reached")
        }

        var record: [UInt8] = []
        record.appendLE32(UInt32(tick))
        record.appendLE32(UInt32(gateTicks))
        record.append(UInt8(note))
        record.append(UInt8(velocity))
        record.appendLE16(0)

        let insertAt = countOffset + 1 + count * Self.noteSize
        image.insert(contentsOf: record, at: insertAt)
        image[countOffset] = UInt8(count + 1)
        try markEdited(track: track)
        try rescan()
    }

    mutating func setTrack11Locks(_ locks: [XYTrack11CCLock]) throws {
        let track = 11
        for lock in locks {
            try setTrack11Lock(lock)
        }
        if locks.contains(where: { $0.laneMask != 0 }) {
            let base = try trackStart(track)
            let aggregateMask = locks.reduce(UInt8(0)) { $0 | $1.laneMask }
            guard base + Self.track11MasterFlag < image.count else {
                throw XYImageProjectError.invalidImage("T11 lock master flag outside image")
            }
            image[base + Self.track11MasterFlag] = aggregateMask
            try markEdited(track: track)
        }
    }

    private mutating func setTrack11Lock(_ lock: XYTrack11CCLock) throws {
        guard (1...64).contains(lock.step) else {
            throw XYImageProjectError.invalidStep(lock.step)
        }
        let base = try trackStart(11)
        let row = base + Self.track11LockBase + (lock.step - 1) * Self.track11LockStride
        let lanes: [(offset: Int, value: UInt8?, lane: Int)] = [
            (0, lock.cc1, 1),
            (2, lock.cc2, 2),
            (4, lock.cc3, 3),
            (6, lock.cc4, 4)
        ]

        for lane in lanes {
            guard let value = lane.value else { continue }
            guard row + lane.offset + 1 < image.count else {
                throw XYImageProjectError.invalidImage("T11 lock row outside image")
            }
            image[row + lane.offset] = track11Marker(step: lock.step, lane: lane.lane, value: value, lock: lock)
            image[row + lane.offset + 1] = value
        }

        if lock.laneMask != 0 {
            let flagOffset = base + Self.track11StepFlagBase + (lock.step - 1) * 8
            guard flagOffset < image.count, base + Self.track11MasterFlag < image.count else {
                throw XYImageProjectError.invalidImage("T11 lock flags outside image")
            }
            image[flagOffset] = lock.laneMask
        }
    }

    private func track11Marker(step: Int, lane: Int, value: UInt8, lock: XYTrack11CCLock) -> UInt8 {
        if lane == 2 || lane == 3,
           let cc2 = lock.cc2,
           let cc3 = lock.cc3,
           let override = track11Mask6MarkerOverride(cc2: cc2, cc3: cc3) {
            return lane == 2 ? override.cc2 : override.cc3
        }
        if step == 3, lane == 1, lock.laneMask == 0x0F {
            return 0xD5
        }

        switch lane {
        case 1:
            return Self.track11CC1MarkersByStep[step] ?? 0xD4
        case 2:
            return Self.track11CC2MarkersByStep[step] ?? 0xD4
        case 3:
            return Self.track11CC3MarkersByStep[step] ?? 0xD4
        case 4:
            return Self.track11CC4MarkersByStep[step] ?? 0xD4
        default:
            return 0xD4
        }
    }

    private func track11Mask6MarkerOverride(cc2: UInt8, cc3: UInt8) -> (cc2: UInt8, cc3: UInt8)? {
        switch (cc2, cc3) {
        case (89, 38): return (0x29, 0xD4)
        case (92, 121): return (0xD4, 0xD4)
        case (4, 8): return (0x2A, 0x29)
        default: return nil
        }
    }

    private mutating func markEdited(track: Int) throws {
        let start = try trackStart(track)
        guard start + Self.pristineOffset + 1 < image.count else {
            throw XYImageProjectError.invalidImage("pristine flag outside image")
        }
        image[start + Self.pristineOffset] = 0
        image[start + Self.pristineOffset + 1] = 0
    }

    private mutating func rescan() throws {
        trackStarts = try Self.scanTrackStarts(in: image)
    }

    private static func scanTrackStarts(in image: [UInt8]) throws -> [Int] {
        var starts: [Int] = []
        var position = trackBase0

        for _ in 0..<trackCount {
            guard position >= 0, position + trackStride <= image.count else {
                throw XYImageProjectError.invalidImage("track struct outside image at \(position)")
            }
            starts.append(position)

            var patternCount = Int(image[position])
            if !(1...9).contains(patternCount) {
                patternCount = 1
            }

            position = try nextPatternPosition(after: position, in: image)
            for _ in 1..<patternCount {
                let cloneStart = position - 1
                guard cloneStart >= 0 else {
                    throw XYImageProjectError.invalidImage("clone starts before image")
                }
                position = try nextPatternPosition(after: cloneStart, in: image)
            }
        }

        guard starts.count == trackCount else {
            throw XYImageProjectError.invalidImage("expected 16 track starts")
        }
        return starts
    }

    private static func nextPatternPosition(after start: Int, in image: [UInt8]) throws -> Int {
        let countOffset = start + noteCountOffset
        guard countOffset < image.count else {
            throw XYImageProjectError.invalidImage("note count outside image")
        }
        let noteCount = Int(image[countOffset])
        guard noteCount <= maxNotes else {
            throw XYImageProjectError.invalidImage("note count \(noteCount) exceeds max")
        }
        return start + trackStride + noteCount * noteSize
    }

    private func readUInt16LE(at offset: Int) -> UInt16 {
        UInt16(image[offset]) | (UInt16(image[offset + 1]) << 8)
    }

    private func readUInt32LE(at offset: Int) -> UInt32 {
        UInt32(image[offset])
            | (UInt32(image[offset + 1]) << 8)
            | (UInt32(image[offset + 2]) << 16)
            | (UInt32(image[offset + 3]) << 24)
    }

    private mutating func writeUInt16LE(_ value: UInt16, at offset: Int) {
        image[offset] = UInt8(value & 0x00FF)
        image[offset + 1] = UInt8((value >> 8) & 0x00FF)
    }

    // CC1/CC2 first-bar markers are decoded from `08a 1...32`.
    private static let track11CC1MarkersByStep: [Int: UInt8] = [
        1: 0xD4, 2: 0xD4, 3: 0x29, 4: 0x29,
        5: 0x29, 6: 0x29, 7: 0xD4, 8: 0x29,
        9: 0x29, 10: 0xD4, 11: 0xD4, 12: 0xD4,
        13: 0x29, 14: 0x29, 15: 0xD4, 16: 0x29
    ]

    private static let track11CC2MarkersByStep: [Int: UInt8] = [
        1: 0xD4, 2: 0xD4, 3: 0x29, 4: 0x29,
        5: 0x29, 6: 0xD4, 7: 0x29, 8: 0xD4,
        9: 0x29, 10: 0xD4, 11: 0x29, 12: 0x29,
        13: 0xD4, 14: 0xD4, 15: 0x29, 16: 0x29
    ]

    private static let track11CC3MarkersByStep: [Int: UInt8] = [
        1: 0x29, 3: 0xD4, 4: 0xD4, 8: 0xD4, 16: 0xD4,
        17: 0x29, 20: 0xD4, 24: 0x29, 29: 0x29, 30: 0xD4,
        33: 0x29, 36: 0x29, 40: 0xD4, 46: 0xD4, 49: 0x29,
        51: 0xD4, 52: 0xD4, 63: 0xD4, 64: 0x29
    ]

    private static let track11CC4MarkersByStep: [Int: UInt8] = [
        3: 0xD4
    ]
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
