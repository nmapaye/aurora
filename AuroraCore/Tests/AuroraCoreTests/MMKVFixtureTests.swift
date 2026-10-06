import Foundation
import Testing
@testable import AuroraCore

/// Files written by the MMKV Core that react-native-mmkv 3.3.0 shipped
/// (`AuroraCore/Tools/mmkv-fixtures/generate.py`), so these checks do not
/// depend on `MMKVReader.encode`. Each scenario's expected values are what
/// MMKV itself read back after writing the file.
@Suite struct MMKVFixtureTests {
    struct Scenario {
        let name: String
        let file: URL
        let values: [String: String]
    }

    static func manifest() throws -> JSONValue {
        let url = try #require(Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: "Fixtures/mmkv"))
        return try JSONValue(parsing: Data(contentsOf: url))
    }

    static func scenarios() throws -> [Scenario] {
        guard case .object(let scenarios) = try manifest()["scenarios"] ?? .null else { return [] }
        return try scenarios.keys.sorted().map { name in
            let file = try #require(Bundle.module.url(forResource: "aurora", withExtension: nil, subdirectory: "Fixtures/mmkv/\(name)"))
            var values: [String: String] = [:]
            if case .object(let stored) = scenarios[name]?["values"] ?? .null {
                for (key, value) in stored { values[key] = value.string }
            }
            return Scenario(name: name, file: file, values: values)
        }
    }

    @Test func manifestNamesTheShippedVersions() throws {
        let manifest = try Self.manifest()
        #expect(manifest.text("package") == "react-native-mmkv@3.3.0")
        #expect(manifest.text("mmkvCore") == "v2.0.0")
        #expect(try Self.scenarios().count == 9)
    }

    @Test func readsEveryKeyMMKVReadsBack() throws {
        for scenario in try Self.scenarios() {
            let reader = try MMKVReader(contentsOf: scenario.file)
            #expect(Set(reader.values.keys) == Set(scenario.values.keys), "\(scenario.name)")
            for (key, value) in scenario.values {
                #expect(reader.string(forKey: key) == value, "\(scenario.name) \(key)")
            }
        }
    }

    @Test func storedBlobsMigrate() throws {
        let fixture = try Fixture.load("legacy")
        let now = try #require(fixture.double("now"))
        for scenario in try Self.scenarios() {
            let reader = try MMKVReader(contentsOf: scenario.file)
            guard let raw = reader.string(forKey: "aurora/state") else {
                #expect(scenario.name == "deleted")
                continue
            }
            let state = try LegacyState.decode(raw, now: now)
            if scenario.name == "large" {
                #expect(state.doses.count == 100)
                #expect(state.doses.allSatisfy { $0.note == "Café ☕ 日本" })
            }
        }
    }

    @Test func corruptBackupKeyIsKeptSeparately() throws {
        let scenario = try #require(try Self.scenarios().first { $0.name == "corrupt-backup" })
        let reader = try MMKVReader(contentsOf: scenario.file)
        #expect(reader.string(forKey: "aurora/state.corrupt.1790510400000") == "{not json")
        #expect(reader.string(forKey: "aurora/state")?.hasPrefix("{\"version\":5") == true)
    }

    @Test func appendedOverwritesKeepTheLastWrite() throws {
        // With a second key present MMKV appends, so the file still holds
        // the stale v1 and v4 blobs; one write came after a reopen.
        let manifest = try Self.manifest()
        let records = manifest["scenarios"]?["appended"]?["records"]
        #expect(records?.int("aurora/state") == 3)
        let scenario = try #require(try Self.scenarios().first { $0.name == "appended" })
        let raw = try #require(try MMKVReader(contentsOf: scenario.file).string(forKey: "aurora/state"))
        let legacy = try Fixture.load("legacy")
        #expect(raw == legacy["cases"]?["v6importing"]?.text("raw"))
    }

    @Test func truncatedRealFileIsRejected() throws {
        let scenario = try #require(try Self.scenarios().first { $0.name == "single" })
        let data = try Data(contentsOf: scenario.file)
        // Cut inside the stored value: the header still claims the full size.
        #expect(throws: MMKVReader.Failure.badLength) { try MMKVReader(data: data.prefix(200)) }
    }
}

/// Hostile and damaged inputs must throw, never trap.
@Suite struct MMKVMalformedTests {
    /// A 4-byte header claiming `payload.count`, then the payload.
    static func file(_ payload: [UInt8]) -> Data {
        let size = UInt32(payload.count)
        return Data([UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 24 & 0xFF)] + payload)
    }

    static let placeholder: [UInt8] = [0xFF, 0xFF, 0xFF, 0x07]

    @Test func lengthNearIntMaxThrows() {
        // A ten-byte varint that older code decoded to Int.max, then added to
        // the cursor position.
        let huge: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]
        #expect(throws: MMKVReader.Failure.malformed) { try MMKVReader(data: Self.file(Self.placeholder + huge)) }
        #expect(throws: MMKVReader.Failure.malformed) { try MMKVReader(data: Self.file(Self.placeholder + [1, 0x6B] + huge)) }
    }

    @Test func lengthPastTheEndThrows() {
        // UInt32.max as a length, with only a few bytes left.
        let length: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0x0F]
        #expect(throws: MMKVReader.Failure.malformed) { try MMKVReader(data: Self.file(Self.placeholder + length + [1, 2, 3])) }
    }

    @Test func varintWiderThan32BitsThrows() {
        // Five bytes whose last carries bits above 32.
        #expect(throws: MMKVReader.Failure.malformed) { try MMKVReader(data: Self.file(Self.placeholder + [0x80, 0x80, 0x80, 0x80, 0x10])) }
        // Six bytes.
        #expect(throws: MMKVReader.Failure.malformed) { try MMKVReader(data: Self.file(Self.placeholder + [0x81, 0x80, 0x80, 0x80, 0x80, 0x00])) }
    }

    @Test func paddedVarintThrows() {
        // 0 written as two bytes.
        #expect(throws: MMKVReader.Failure.malformed) { try MMKVReader(data: Self.file(Self.placeholder + [0x80, 0x00])) }
        // 1 written as three bytes.
        #expect(throws: MMKVReader.Failure.malformed) { try MMKVReader(data: Self.file(Self.placeholder + [0x81, 0x80, 0x00, 0x6B, 0x00])) }
    }

    @Test func unterminatedVarintThrows() {
        #expect(throws: MMKVReader.Failure.malformed) { try MMKVReader(data: Self.file(Self.placeholder + [0x80])) }
    }

    @Test func headerLargerThanFileThrows() {
        #expect(throws: MMKVReader.Failure.badLength) { try MMKVReader(data: Data([0xFF, 0xFF, 0xFF, 0xFF, 0])) }
    }

    @Test func malformedValuePrefixFallsBackToRawBytes() throws {
        // A value whose would-be prefix is padded is read as raw bytes, not trusted.
        let reader = try MMKVReader(data: Self.file(Self.placeholder + [1, 0x6B, 3, 0x80, 0x00, 0x41]))
        #expect(reader.values["k"] == Data([0x80, 0x00, 0x41]))
    }
}
