import Foundation

/// Reads string values out of an unencrypted MMKV file, which is where the
/// React Native build kept its store (`Documents/mmkv/aurora`).
///
/// Layout: a 4-byte little-endian payload length, then the payload. The
/// payload opens with one varint (a size placeholder) followed by key/value
/// pairs, each a varint length and bytes. Writes append pairs, so a later pair
/// replaces an earlier one, and an empty value deletes the key.
///
/// String values are themselves length-prefixed, and some MMKV versions add a
/// second prefix, so `string(forKey:)` accepts either form.
public struct MMKVReader: Sendable {
    public enum Failure: Error, Equatable {
        case tooShort
        case badLength
        case malformed
    }

    public let values: [String: Data]

    public init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { throw Failure.tooShort }
        let actualSize = Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
        guard actualSize >= 0, 4 + actualSize <= bytes.count else { throw Failure.badLength }
        var cursor = Cursor(bytes: Array(bytes[4..<(4 + actualSize)]))
        var values: [String: Data] = [:]
        if !cursor.isAtEnd {
            _ = try cursor.varint()
        }
        while !cursor.isAtEnd {
            let keyBytes = try cursor.lengthPrefixed()
            guard !keyBytes.isEmpty else { continue }
            guard let key = String(bytes: keyBytes, encoding: .utf8) else { throw Failure.malformed }
            let value = try cursor.lengthPrefixed()
            if value.isEmpty {
                values.removeValue(forKey: key)
            } else {
                values[key] = Data(value)
            }
        }
        self.values = values
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    public func string(forKey key: String) -> String? {
        guard let value = values[key] else { return nil }
        let bytes = [UInt8](value)
        func unwrap(_ bytes: [UInt8]) -> [UInt8]? {
            var cursor = Cursor(bytes: bytes)
            guard let body = try? cursor.lengthPrefixed(), cursor.isAtEnd else { return nil }
            return body
        }
        func looksLikeJSON(_ bytes: [UInt8]) -> Bool {
            bytes.first == UInt8(ascii: "{") || bytes.first == UInt8(ascii: "[")
        }
        let candidates: [[UInt8]?] = {
            guard let once = unwrap(bytes) else { return [bytes] }
            if looksLikeJSON(once) { return [once] }
            return [unwrap(once), once, bytes]
        }()
        for candidate in candidates.compactMap({ $0 }) {
            if let string = String(bytes: candidate, encoding: .utf8) { return string }
        }
        return nil
    }

    struct Cursor {
        let bytes: [UInt8]
        var position = 0

        var isAtEnd: Bool { position >= bytes.count }

        mutating func varint() throws -> Int {
            var result = 0
            var shift = 0
            while true {
                guard position < bytes.count, shift < 64 else { throw Failure.malformed }
                let byte = bytes[position]
                position += 1
                result |= Int(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
        }

        mutating func lengthPrefixed() throws -> [UInt8] {
            let length = try varint()
            guard length >= 0, position + length <= bytes.count else { throw Failure.malformed }
            defer { position += length }
            return Array(bytes[position..<(position + length)])
        }
    }

    /// Builds a file in this layout. Tests use it for fixtures; nothing ships
    /// that writes MMKV.
    public static func encode(_ pairs: [(key: String, value: String)], valuePrefixes: Int = 1) -> Data {
        func varint(_ value: Int) -> [UInt8] {
            var value = value
            var out: [UInt8] = []
            repeat {
                var byte = UInt8(value & 0x7F)
                value >>= 7
                if value != 0 { byte |= 0x80 }
                out.append(byte)
            } while value != 0
            return out
        }
        func prefixed(_ bytes: [UInt8]) -> [UInt8] { varint(bytes.count) + bytes }

        // MMKV writes its size placeholder as a fixed 4-byte varint.
        var payload: [UInt8] = [0xFF, 0xFF, 0xFF, 0x07]
        for pair in pairs {
            var value = [UInt8](pair.value.utf8)
            for _ in 0..<valuePrefixes { value = prefixed(value) }
            payload += prefixed([UInt8](pair.key.utf8)) + prefixed(value)
        }
        let size = UInt32(payload.count)
        let header: [UInt8] = [UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 24 & 0xFF)]
        return Data(header + payload)
    }
}
