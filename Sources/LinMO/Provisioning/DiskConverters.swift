import Compression
import CryptoKit
import Foundation

enum DiskConverters {


    static func decompressXZ(source: URL, destination: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try createOutput(at: destination)
        defer { try? output.close() }

        let filter = try InputFilter<Data>(.decompress, using: .lzma) { length in
            try input.read(upToCount: length)
        }

        var position: UInt64 = 0
        while let page = try filter.readData(ofLength: 1 << 20), !page.isEmpty {
            if !isAllZero(page) {
                try output.seek(toOffset: position)
                try output.write(contentsOf: page)
            }
            position += UInt64(page.count)
        }
        try output.truncate(atOffset: position)
    }


    static func convertQcow2(source: URL, destination: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }

        func read(_ offset: UInt64, _ count: Int, exact: Bool = true) throws -> Data {
            try input.seek(toOffset: offset)
            let data = try input.read(upToCount: count) ?? Data()
            if exact && data.count != count {
                throw LinMOError.message("ไฟล์ qcow2 ไม่สมบูรณ์")
            }
            return data
        }

        let header = try read(0, 104, exact: false)
        guard header.count >= 72, header.be32(0) == 0x5146_49FB else {
            throw LinMOError.message("ไม่ใช่ไฟล์ qcow2")
        }
        let version = header.be32(4)
        guard version == 2 || version == 3 else {
            throw LinMOError.message("ไม่รองรับ qcow2 เวอร์ชัน \(version)")
        }
        guard header.be64(8) == 0 else {
            throw LinMOError.message("ไม่รองรับ qcow2 ที่มี backing file")
        }
        let clusterBits = Int(header.be32(20))
        let virtualSize = header.be64(24)
        guard header.be32(32) == 0 else {
            throw LinMOError.message("ไม่รองรับ qcow2 ที่เข้ารหัส")
        }
        let l1Size = Int(header.be32(36))
        let l1Offset = header.be64(40)
        if version == 3, header.count >= 80 {
            let incompatible = header.be64(72)
            guard incompatible & ~UInt64(1) == 0 else {
                throw LinMOError.message("ไฟล์ qcow2 ใช้ฟีเจอร์ที่ยังไม่รองรับ")
            }
        }
        guard (9...21).contains(clusterBits) else {
            throw LinMOError.message("ขนาด cluster ของ qcow2 ไม่ถูกต้อง")
        }

        let clusterSize = 1 << clusterBits
        let l2Count = clusterSize / 8
        let offsetMask: UInt64 = 0x00FF_FFFF_FFFF_FE00
        let compressedFlag: UInt64 = 1 << 62
        let compressedOffsetBits = UInt64(62 - (clusterBits - 8))
        let compressedOffsetMask: UInt64 = (1 << compressedOffsetBits) - 1
        let sectorCountMask: UInt64 = (1 << UInt64(clusterBits - 8)) - 1

        let output = try createOutput(at: destination)
        defer { try? output.close() }
        try output.truncate(atOffset: virtualSize)

        let l1 = try read(l1Offset, l1Size * 8)
        for i in 0..<l1Size {
            let l2Offset = l1.be64(i * 8) & offsetMask
            if l2Offset == 0 { continue }
            let l2 = try read(l2Offset, clusterSize)

            for j in 0..<l2Count {
                let guestOffset = (UInt64(i) * UInt64(l2Count) + UInt64(j)) * UInt64(clusterSize)
                if guestOffset >= virtualSize { break }
                let entry = l2.be64(j * 8)
                var cluster: Data?

                if entry & compressedFlag != 0 {
                    let hostOffset = entry & compressedOffsetMask
                    let additionalSectors = (entry >> compressedOffsetBits) & sectorCountMask
                    let length = Int((additionalSectors + 1) * 512 - (hostOffset & 511))
                    let compressed = try read(hostOffset, length, exact: false)
                    cluster = try inflate(compressed, expectedSize: clusterSize)
                } else {
                    let hostOffset = entry & offsetMask
                    let isZeroCluster = version == 3 && entry & 1 != 0
                    if hostOffset != 0 && !isZeroCluster {
                        cluster = try read(hostOffset, clusterSize)
                    }
                }

                if let cluster, !isAllZero(cluster) {
                    let remaining = Int(min(UInt64(cluster.count), virtualSize - guestOffset))
                    try output.seek(toOffset: guestOffset)
                    try output.write(contentsOf: cluster.prefix(remaining))
                }
            }
        }
    }

    private static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else {
            throw LinMOError.message("คลายข้อมูลใน qcow2 ไม่สำเร็จ")
        }
        return output
    }


    static func hash(of url: URL, algorithm: HashAlgorithm) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        switch algorithm {
        case .sha256:
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().hexString
        case .sha512:
            var hasher = SHA512()
            while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().hexString
        }
    }


    private static func createOutput(at url: URL) throws -> FileHandle {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw LinMOError.message("สร้างไฟล์ \(url.lastPathComponent) ไม่สำเร็จ")
        }
        return try FileHandle(forWritingTo: url)
    }

    static func isAllZero(_ data: Data) -> Bool {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let words = raw.count / 8
            if words > 0 {
                let base = raw.baseAddress!
                for k in 0..<words where base.loadUnaligned(fromByteOffset: k * 8, as: UInt64.self) != 0 {
                    return false
                }
            }
            for k in (words * 8)..<raw.count where raw[k] != 0 {
                return false
            }
            return true
        }
    }
}

private extension Data {
    func be32(_ offset: Int) -> UInt32 {
        self[startIndex + offset ..< startIndex + offset + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    func be64(_ offset: Int) -> UInt64 {
        self[startIndex + offset ..< startIndex + offset + 8].reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
