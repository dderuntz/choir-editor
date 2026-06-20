import Foundation

struct XYRLEProject {
    let header: [UInt8]
    let image: [UInt8]
}

enum XYRLECodecError: Error, LocalizedError, Equatable {
    case badMagic
    case badHeaderLength
    case invalidRange
    case truncatedExtension(index: Int)

    var errorDescription: String? {
        switch self {
        case .badMagic:
            "not a .xy file (bad magic)"
        case .badHeaderLength:
            "header must be the original 8 bytes including magic"
        case .invalidRange:
            "invalid RLE decode range"
        case let .truncatedExtension(index):
            "extension byte needed past end at \(index)"
        }
    }
}

enum XYRLECodec {
    static let headerLength = 8
    static let magic: [UInt8] = [0xdd, 0xcc, 0xbb, 0xaa]
    static let maxRun = 257

    static func decode(_ bytes: [UInt8], start: Int = 0, end: Int? = nil) throws -> [UInt8] {
        let stop = end ?? bytes.count
        guard start >= 0, stop >= start, stop <= bytes.count else {
            throw XYRLECodecError.invalidRange
        }

        var output: [UInt8] = []
        output.reserveCapacity(stop - start)

        var index = start
        var previous: UInt8?

        while index < stop {
            let byte = bytes[index]
            index += 1
            output.append(byte)

            if byte == previous {
                guard index < stop else {
                    throw XYRLECodecError.truncatedExtension(index: index)
                }

                let extensionCount = Int(bytes[index])
                index += 1
                if extensionCount > 0 {
                    output.append(contentsOf: repeatElement(byte, count: extensionCount))
                }
                previous = nil
            } else {
                previous = byte
            }
        }

        return output
    }

    static func encode(_ bytes: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)

        var index = 0
        while index < bytes.count {
            let value = bytes[index]
            var runEnd = index
            while runEnd < bytes.count, bytes[runEnd] == value {
                runEnd += 1
            }

            var runLength = runEnd - index
            while runLength >= 2 {
                let chunkLength = min(runLength, maxRun)
                output.append(value)
                output.append(value)
                output.append(UInt8(chunkLength - 2))
                runLength -= chunkLength
            }

            if runLength == 1 {
                output.append(value)
            }

            index = runEnd
        }

        return output
    }

    static func decodeProject(_ data: [UInt8]) throws -> XYRLEProject {
        guard data.count >= headerLength, Array(data.prefix(magic.count)) == magic else {
            throw XYRLECodecError.badMagic
        }

        let header = Array(data.prefix(headerLength))
        let image = try decode(data, start: headerLength)
        return XYRLEProject(header: header, image: image)
    }

    static func encodeProject(header: [UInt8], image: [UInt8]) throws -> [UInt8] {
        guard header.count == headerLength, Array(header.prefix(magic.count)) == magic else {
            throw XYRLECodecError.badHeaderLength
        }

        return header + encode(image)
    }
}
