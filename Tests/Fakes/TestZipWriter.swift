import Foundation

/// A minimal ZIP writer for test fixtures: stored or deflated entries, plus archives a real tool
/// wouldn't write (names that climb out, headers that understate an entry's size).
enum TestZipWriter {
    struct Entry {
        var path: String
        var data: Data
        var compressed = true
        /// Written as the uncompressed size in both headers instead of the real one.
        var declaredSize: UInt32?
    }

    static func archive(_ entries: [Entry]) -> Data {
        var output = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.path.utf8)
            let payload = entry.compressed ? deflate(entry.data) : entry.data
            let crc = crc32(entry.data)
            let size = entry.declaredSize ?? UInt32(entry.data.count)
            let method: UInt16 = entry.compressed ? 8 : 0
            let offset = UInt32(output.count)

            output.append(uint32: 0x0403_4B50)
            output.append(uint16: 20)
            output.append(uint16: 0x0800)
            output.append(uint16: method)
            output.append(uint16: 0)
            output.append(uint16: 0x21)
            output.append(uint32: crc)
            output.append(uint32: UInt32(payload.count))
            output.append(uint32: size)
            output.append(uint16: UInt16(name.count))
            output.append(uint16: 0)
            output.append(name)
            output.append(payload)

            central.append(uint32: 0x0201_4B50)
            central.append(uint16: 0x0314)
            central.append(uint16: 20)
            central.append(uint16: 0x0800)
            central.append(uint16: method)
            central.append(uint16: 0)
            central.append(uint16: 0x21)
            central.append(uint32: crc)
            central.append(uint32: UInt32(payload.count))
            central.append(uint32: size)
            central.append(uint16: UInt16(name.count))
            central.append(uint16: 0)
            central.append(uint16: 0)
            central.append(uint16: 0)
            central.append(uint16: 0)
            central.append(uint32: UInt32(0o100644) << 16)
            central.append(uint32: offset)
            central.append(name)
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.append(uint32: 0x0605_4B50)
        output.append(uint16: 0)
        output.append(uint16: 0)
        output.append(uint16: UInt16(entries.count))
        output.append(uint16: UInt16(entries.count))
        output.append(uint32: UInt32(central.count))
        output.append(uint32: centralOffset)
        output.append(uint16: 0)
        return output
    }

    /// Raw DEFLATE (RFC 1951), as ZIP stores it.
    private static func deflate(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data([0x03, 0x00]) }
        return (try? (data as NSData).compressed(using: .zlib) as Data) ?? data
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }
}
