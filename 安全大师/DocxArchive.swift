//
//  DocxArchive.swift
//  安全大师
//

import Compression
import Foundation
import zlib

struct DocxArchiveEntry {
    var path: String
    var data: Data
}

enum DocxArchive {
    static func entries(in data: Data, maxEntryBytes: Int = 12 * 1024 * 1024) -> [DocxArchiveEntry]? {
        guard data.count > 22, let eocd = findEndOfCentralDirectory(in: data) else { return nil }
        let entryCount = Int(readUInt16LE(data, at: eocd + 10) ?? 0)
        let centralDirectoryOffset = Int(readUInt32LE(data, at: eocd + 16) ?? 0)
        var cursor = centralDirectoryOffset
        var result: [DocxArchiveEntry] = []

        for _ in 0..<entryCount {
            guard cursor + 46 <= data.count,
                  readUInt32LE(data, at: cursor) == 0x02014B50
            else { return nil }
            let method = Int(readUInt16LE(data, at: cursor + 10) ?? 0)
            let compressedSize = Int(readUInt32LE(data, at: cursor + 20) ?? 0)
            let uncompressedSize = Int(readUInt32LE(data, at: cursor + 24) ?? 0)
            let nameLength = Int(readUInt16LE(data, at: cursor + 28) ?? 0)
            let extraLength = Int(readUInt16LE(data, at: cursor + 30) ?? 0)
            let commentLength = Int(readUInt16LE(data, at: cursor + 32) ?? 0)
            let localHeaderOffset = Int(readUInt32LE(data, at: cursor + 42) ?? 0)
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count,
                  uncompressedSize <= maxEntryBytes,
                  compressedSize <= data.count
            else { return nil }
            let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) ?? ""
            if let payload = payload(
                in: data,
                localHeaderOffset: localHeaderOffset,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                compressionMethod: method
            ) {
                result.append(DocxArchiveEntry(path: name, data: payload))
            }
            cursor = nameEnd + extraLength + commentLength
        }
        return result
    }

    static func entryData(named targetName: String, in data: Data) -> Data? {
        entries(in: data)?.first { $0.path == targetName }?.data
    }

    static func build(entries: [DocxArchiveEntry]) -> Data? {
        var main = Data()
        var central = Data()
        var offset: UInt32 = 0
        let utf8NameFlag: UInt16 = 0x0800

        for entry in entries {
            let pathBytes = Data(entry.path.utf8)
            let crc = crc32UInt32(entry.data)
            let size = UInt32(entry.data.count)
            guard let nameLen = UInt16(exactly: pathBytes.count) else { return nil }

            var local = Data()
            local.appendUInt32LE(0x0403_4b50)
            local.appendUInt16LE(20)
            local.appendUInt16LE(utf8NameFlag)
            local.appendUInt16LE(0)
            local.appendUInt16LE(0)
            local.appendUInt16LE(0)
            local.appendUInt32LE(crc)
            local.appendUInt32LE(size)
            local.appendUInt32LE(size)
            local.appendUInt16LE(nameLen)
            local.appendUInt16LE(0)
            local.append(pathBytes)

            let localHeaderLen = UInt32(local.count)
            main.append(local)
            main.append(entry.data)

            var cd = Data()
            cd.appendUInt32LE(0x0201_4b50)
            cd.appendUInt16LE(20)
            cd.appendUInt16LE(20)
            cd.appendUInt16LE(utf8NameFlag)
            cd.appendUInt16LE(0)
            cd.appendUInt16LE(0)
            cd.appendUInt16LE(0)
            cd.appendUInt32LE(crc)
            cd.appendUInt32LE(size)
            cd.appendUInt32LE(size)
            cd.appendUInt16LE(nameLen)
            cd.appendUInt16LE(0)
            cd.appendUInt16LE(0)
            cd.appendUInt16LE(0)
            cd.appendUInt16LE(0)
            cd.appendUInt32LE(0)
            cd.appendUInt32LE(offset)
            cd.append(pathBytes)
            central.append(cd)

            offset += localHeaderLen + size
        }

        var eocd = Data()
        eocd.appendUInt32LE(0x0605_4b50)
        eocd.appendUInt16LE(0)
        eocd.appendUInt16LE(0)
        eocd.appendUInt16LE(UInt16(entries.count))
        eocd.appendUInt16LE(UInt16(entries.count))
        eocd.appendUInt32LE(UInt32(central.count))
        eocd.appendUInt32LE(offset)
        eocd.appendUInt16LE(0)

        main.append(central)
        main.append(eocd)
        return main
    }

    private static func payload(
        in data: Data,
        localHeaderOffset: Int,
        compressedSize: Int,
        uncompressedSize: Int,
        compressionMethod: Int
    ) -> Data? {
        guard localHeaderOffset + 30 <= data.count,
              readUInt32LE(data, at: localHeaderOffset) == 0x04034B50
        else { return nil }
        let nameLength = Int(readUInt16LE(data, at: localHeaderOffset + 26) ?? 0)
        let extraLength = Int(readUInt16LE(data, at: localHeaderOffset + 28) ?? 0)
        let start = localHeaderOffset + 30 + nameLength + extraLength
        let end = start + compressedSize
        guard start >= 0, end <= data.count else { return nil }
        let payload = Data(data[start..<end])
        switch compressionMethod {
        case 0:
            return payload
        case 8:
            return inflateDeflate(payload, expectedSize: uncompressedSize)
        default:
            return nil
        }
    }

    private static func inflateDeflate(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty, expectedSize > 0 else { return nil }
        var output = Data(count: expectedSize)
        let decodedCount = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount > 0 else { return nil }
        output.removeSubrange(decodedCount..<output.count)
        return output
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        let minimumOffset = max(0, data.count - 65_557)
        guard data.count >= 22, minimumOffset < data.count - 3 else { return nil }
        var cursor = data.count - 22
        while cursor >= minimumOffset {
            if readUInt32LE(data, at: cursor) == 0x06054B50 {
                return cursor
            }
            if cursor == 0 { break }
            cursor -= 1
        }
        return nil
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func crc32UInt32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            let len = uInt(min(data.count, Int(UInt32.max)))
            return UInt32(truncatingIfNeeded: crc32(0, base, len))
        }
    }
}

private extension Data {
    mutating func appendUInt16LE(_ v: UInt16) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ v: UInt32) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}

