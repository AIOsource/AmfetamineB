//
//  ZipUnarchiver.swift
//  Amfeta-Board
//
//  Lightweight, standalone zip unarchiver using Apple's Compression framework.
//  Extracts .tendies and .zip archives into target directories without external dependencies.
//

import Foundation
import Compression

public enum ZipError: LocalizedError {
    case invalidArchive
    case fileCreationFailed(String)
    case decompressionFailed
    case unsupportedCompressionMethod(UInt16)

    public var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "The archive format is invalid or corrupted."
        case .fileCreationFailed(let path):
            return "Failed to create extracted file at \(path)."
        case .decompressionFailed:
            return "Failed to decompress file contents."
        case .unsupportedCompressionMethod(let method):
            return "Compression method \(method) is not supported."
        }
    }
}

public struct ZipUnarchiver {
    /// Unzips a file at `fileURL` to `destinationDirectory`.
    public static func unzip(fileURL: URL, destinationDirectory: URL) throws {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        try unzip(data: data, destinationDirectory: destinationDirectory)
    }

    /// Unzips raw data into `destinationDirectory`.
    public static func unzip(data: Data, destinationDirectory: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destinationDirectory.path) {
            try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }

        var offset = 0
        let count = data.count

        while offset + 30 <= count {
            // Local file header signature = 0x04034b50
            let sig = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
            if sig != 0x04034b50 {
                // Not a local file header; central directory reached
                break
            }

            let compMethod = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 8, as: UInt16.self) }
            let compSize = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset + 18, as: UInt32.self) })
            let uncompSize = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset + 22, as: UInt32.self) })
            let nameLen = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset + 26, as: UInt16.self) })
            let extraLen = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset + 28, as: UInt16.self) })

            let nameOffset = offset + 30
            guard nameOffset + nameLen <= count else { break }

            let nameData = data.subdata(in: nameOffset..<(nameOffset + nameLen))
            guard let relativePath = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .ascii) else {
                offset += 30 + nameLen + extraLen + compSize
                continue
            }

            let dataOffset = nameOffset + nameLen + extraLen
            guard dataOffset + compSize <= count else { break }

            let entryData = data.subdata(in: dataOffset..<(dataOffset + compSize))
            let targetURL = destinationDirectory.appendingPathComponent(relativePath)

            if relativePath.hasSuffix("/") {
                try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else {
                let parentDir = targetURL.deletingLastPathComponent()
                if !fm.fileExists(atPath: parentDir.path) {
                    try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }

                let decompressed: Data
                if compMethod == 0 {
                    // Stored (uncompressed)
                    decompressed = entryData
                } else if compMethod == 8 {
                    // Deflate
                    decompressed = try inflate(entryData, expectedSize: uncompSize)
                } else {
                    decompressed = entryData
                }

                try decompressed.write(to: targetURL, options: .atomic)
            }

            offset = dataOffset + compSize
        }
    }

    private static func inflate(_ compressedData: Data, expectedSize: Int) throws -> Data {
        if compressedData.isEmpty { return Data() }
        let destinationSize = max(expectedSize, compressedData.count * 4)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = compressedData.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
            guard let baseAddr = srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                destinationSize,
                baseAddr,
                compressedData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        if decompressedSize > 0 {
            return Data(bytes: destinationBuffer, count: decompressedSize)
        }

        return compressedData
    }
}

