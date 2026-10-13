import OSLog

/// Content-free timing for Instruments (Points of Interest and os_signpost).
/// Only fixed names and fixed route/phase words are recorded: never request
/// text, records, Health, calendar or conversation contents, counts derived
/// from them, or identifiers. Signposts stay on the device's unified log;
/// nothing is uploaded. They measure this build's work, not physical-device
/// speed, which needs separate profiling on hardware.
enum Signposts {
    static let signposter = OSSignposter(subsystem: "com.nmapaye.aurora", category: .pointsOfInterest)
    static let lifecycle = Logger(subsystem: "com.nmapaye.aurora", category: "lifecycle")

    /// Times synchronous work. `name` must be a literal.
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        try signposter.withIntervalSignpost(name, around: work)
    }

    /// Times asynchronous work. `name` must be a literal.
    @MainActor static func measureAsync<T>(_ name: StaticString, _ work: @MainActor () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await work()
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}
