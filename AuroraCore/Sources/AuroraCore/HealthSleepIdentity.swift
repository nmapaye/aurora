import Foundation

/// Health-imported sleep ids are `healthkit:sleep:<start>:<end>` with whole
/// milliseconds, so the same sample imported twice keeps one id.
public enum HealthSleepIdentity {
    public static func id(start: Millis, end: Millis) -> String {
        "\(RecordID.healthSleepPrefix)\(Int64(jsRound(start))):\(Int64(jsRound(end)))"
    }

    /// Legacy ids `sleep:<start>:<end>` are rewritten only when both numbers
    /// equal the session's own boundaries.
    static func isBoundaryEquivalentLegacy(_ session: SleepSession) -> Bool {
        guard session.id.hasPrefix("sleep:") else { return false }
        let parts = session.id.dropFirst("sleep:".count).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy(isLegacyNumber),
              let start = Double(parts[0]),
              let end = Double(parts[1]) else { return false }
        return start == session.start && end == session.end
    }

    /// `-?\d+(\.\d+)?`
    private static func isLegacyNumber(_ text: Substring) -> Bool {
        var body = text
        if body.first == "-" { body = body.dropFirst() }
        let pieces = body.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 1 || pieces.count == 2 else { return false }
        return pieces.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }

    public static func normalize(_ session: SleepSession) -> SleepSession {
        guard RecordID.isHealthSleep(session.id) || isBoundaryEquivalentLegacy(session) else { return session }
        var normalized = session
        normalized.id = id(start: session.start, end: session.end)
        return normalized
    }

    /// Normalizes ids and keeps one session per id. A later duplicate replaces
    /// an earlier one but keeps the earlier one's position, as a JavaScript
    /// Map does.
    public static func normalize(_ sessions: [SleepSession]) -> [SleepSession] {
        var order: [String] = []
        var byID: [String: SleepSession] = [:]
        for session in sessions.map(normalize) {
            if byID[session.id] == nil { order.append(session.id) }
            byID[session.id] = session
        }
        return order.compactMap { byID[$0] }
    }
}

public enum ManualSleep {
    public struct Draft: Equatable, Sendable {
        public var start: Millis
        public var end: Millis
        public var note: String

        public init(start: Millis, end: Millis, note: String) {
            self.start = start
            self.end = end
            self.note = note
        }
    }

    /// Eight hours ending now.
    public static func newDraft(now: Millis) -> Draft {
        Draft(start: now - 8 * hourMs, end: now, note: "")
    }

    public static func validate(start: Millis, end: Millis, now: Millis) -> DraftValidation {
        guard start.isFinite, end.isFinite, start < end else {
            return .invalid("Start time must be before end time.")
        }
        if end - start > 24 * hourMs { return .invalid("Sleep duration cannot exceed 24 hours.") }
        if end > now { return .invalid("End time cannot be in the future.") }
        return .valid
    }
}
