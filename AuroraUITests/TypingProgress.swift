import Foundation

/// Decides when text typed into the composer is complete, from successive
/// reads of the field. Pure Foundation, so the rule can be replayed against
/// reads recorded on CI (TypingProgressTests).
///
/// The rule: wait while the field holds a growing prefix of the request.
/// - Every read that shows more correct characters than before restarts a
///   five-second allowance. Five seconds with no new character fails, which
///   catches lost keystrokes ("R" for "Reminders").
/// - Anything that isn't a prefix of the request fails at once (garbled
///   text, or another field's text).
/// - Twenty seconds after typing, it fails whatever the progress.
/// It never accepts partial text and never retypes.
///
/// No-progress time runs from the end of the read that first showed the
/// current text to the start of a later read. Time an AX read spends
/// waiting on a busy app (4.6 s in run 42895134800) is not counted as
/// typing stalling.
struct TypingProgress {
    enum Verdict: Equatable {
        case complete
        case notAPrefix
        case noProgress
        case overCap
    }

    static let noProgressLimit: TimeInterval = 5
    static let totalCap: TimeInterval = 20

    let text: String
    /// The last value actually read, nil when the last read failed. This
    /// is what a failure reports, never a later read.
    private(set) var lastSeen: String?
    /// When the last value was read (end of the read), seconds after typing.
    private(set) var lastSeenAt: TimeInterval?
    private var progress = ""
    private var progressAt: TimeInterval = 0

    init(text: String) { self.text = text }

    /// - Parameters:
    ///   - value: the composer's value, or nil if the read failed.
    ///   - readStart, readEnd: seconds since typeText returned.
    /// - Returns: nil to keep waiting, or the verdict.
    mutating func observe(_ value: String?, readStart: TimeInterval, readEnd: TimeInterval) -> Verdict? {
        if let value {
            lastSeen = value
            lastSeenAt = readEnd
            if value == text { return .complete }
            guard text.hasPrefix(value) else { return .notAPrefix }
            if value.count > progress.count {
                progress = value
                progressAt = readEnd
            }
        }
        if readEnd >= Self.totalCap { return .overCap }
        if readStart - progressAt >= Self.noProgressLimit { return .noProgress }
        return nil
    }

    /// What the check saw, for the failure message.
    func describe(_ verdict: Verdict?) -> String {
        let seen = lastSeen.map { "\"\($0)\"" } ?? "nothing readable"
        let at = lastSeenAt.map { String(format: " at %.1f s", $0) } ?? ""
        let last = String(format: "last new character at %.1f s", progressAt)
        switch verdict {
        case .complete: return "complete: \(seen)\(at)"
        case .notAPrefix: return "the field held \(seen)\(at), which is not a prefix of the request"
        case .noProgress: return "no new character for \(Int(Self.noProgressLimit)) s; the check last saw \(seen)\(at), \(last)"
        case .overCap: return "still incomplete after \(Int(Self.totalCap)) s; the check last saw \(seen)\(at), \(last)"
        case nil: return "undecided; the check last saw \(seen)\(at)"
        }
    }
}
