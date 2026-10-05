import Foundation

/// Every signal module names one signal, says where and when its value came
/// from, says whether it is an observation, an estimate, sample data or
/// nothing yet, adds one line of context, and offers one destination. Signals
/// describe what was recorded; they never prescribe a dose or a sleep schedule.
public enum SignalStatus: String, Equatable, Sendable {
    case observed
    case estimated
    case sample
    case empty
}

public struct SignalCardModel: Equatable, Sendable {
    public var id: String
    public var label: String
    /// When the value applies: "Today", "Yesterday", "Sep 24".
    public var period: String
    /// Where the value came from: "Manual", "Health", "Sample Data".
    public var source: String?
    public var status: SignalStatus
    /// Absent when `status` is `.empty`.
    public var value: String?
    public var context: String
    /// The one place this signal leads, e.g. "Open Sleep".
    public var destination: String

    public init(
        id: String,
        label: String,
        period: String,
        source: String? = nil,
        status: SignalStatus,
        value: String? = nil,
        context: String,
        destination: String
    ) {
        self.id = id
        self.label = label
        self.period = period
        self.source = source
        self.status = status
        self.value = value
        self.context = context
        self.destination = destination
    }

    /// "Today · Manual", "Sep 24 · Health · Estimate".
    public var metaLine: String {
        let statusLabel = status == .estimated ? "Estimate" : nil
        return [period, source, statusLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The VoiceOver label for the whole card.
    public var accessibilityDescription: String {
        let parts: [String?] = status == .empty
            ? [label, "No data", context]
            : [label, value, metaLine, context]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// "Today", "Yesterday", or a short date.
public func formatSignalDay(_ ts: Millis, now: Millis, clock: LocalClock, text: DateText) -> String {
    let day = clock.startOfDay(ts)
    let today = clock.startOfDay(now)
    if day == today { return "Today" }
    if day == clock.addingDays(-1, to: today) { return "Yesterday" }
    return text.shortDate(ts)
}

public enum RecordSource: String, Equatable, Sendable {
    case manual = "Manual"
    case sample = "Sample Data"
    case mixed = "Manual and Sample Data"

    public static func of(ids: [String]) -> RecordSource? {
        guard !ids.isEmpty else { return nil }
        let sample = ids.filter(RecordID.isSample).count
        if sample == 0 { return .manual }
        return sample == ids.count ? .sample : .mixed
    }
}
