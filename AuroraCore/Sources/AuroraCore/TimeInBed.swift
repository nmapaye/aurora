import Foundation

/// Health's "In bed" Sleep Analysis value (raw 0), kept apart from sleep.
/// iPhone without a Watch records only this, from phone use and the sleep
/// schedule; it overstates sleep by the time taken to fall asleep and time
/// awake in bed, so it is never merged into `AppState.sleeps` and never
/// counted as asleep (docs/research/sleep-and-check-in.md §4 R2, §8 Q2 A).
public struct TimeInBed: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// `healthkit:inbed:<sample uuid>`.
    public var id: String
    public var start: Millis
    public var end: Millis
    /// The app or device Health named, when it did.
    public var sourceName: String?

    public init(id: String, start: Millis, end: Millis, sourceName: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.sourceName = sourceName
    }
}

public enum InBed {
    public static let idPrefix = "healthkit:inbed:"
    /// HealthKit `HKCategoryValueSleepAnalysis.inBed`.
    public static let healthValue = 0
    /// Read for the same window as Health sleep refreshes.
    public static let windowDays = HealthImport.refreshDays

    public static let label = "In bed"
    public static let context = "Time in bed from Health, not counted as sleep"
    /// Health status when Health has time in bed but no asleep time.
    public static let onlyInBedMessage =
        "Health has time in bed but no asleep time. Aurora shows it as In bed and doesn’t count it as sleep."

    public static func record(from sample: HealthSleepSample) -> TimeInBed? {
        guard sample.start.isFinite, sample.end.isFinite, sample.start < sample.end else { return nil }
        let id = sample.provenance.map { "\(idPrefix)\($0.sampleUUID.lowercased())" }
            ?? "\(idPrefix)\(Int64(sample.start)):\(Int64(sample.end))"
        return TimeInBed(id: id, start: sample.start, end: sample.end, sourceName: sample.provenance?.sourceName)
    }

    /// Time in bed with no asleep record overlapping it, merged, ended by
    /// `now`, and ending in the last `days` days, newest first. Where Health
    /// also has asleep time for the same night, that sleep is shown instead.
    public static func uncovered(_ timeInBed: [TimeInBed], sleeps: [SleepSession], now: Millis, days: Double = 7) -> [Interval] {
        let asleep = SleepIntervals.merge(sleeps.filter { $0.start <= now })
        return Array(SleepIntervals.merge(timeInBed.map { Interval(start: $0.start, end: $0.end) })
            .filter { interval in
                interval.end <= now && interval.end > now - days * dayMs
                    && !asleep.contains { $0.start < interval.end && $0.end > interval.start }
            }
            .reversed())
    }

    /// The Sleep card when no main sleep is recorded in the last 7 days but
    /// time in bed is: labelled "In bed", never "sleep".
    public static func signal(_ interval: Interval, now: Millis, clock: LocalClock, text: DateText) -> SignalCardModel {
        let span = "\(text.clockTime(interval.start)) – \(text.clockTime(interval.end))"
        return SignalCardModel(
            id: "sleep-in-bed",
            label: label,
            period: SleepModel.describeAge(interval.end, now: now, clock: clock),
            source: "Health",
            status: .observed,
            value: formatHoursMinutes(durationMs: interval.end - interval.start),
            context: "\(text.weekdayDate(interval.end)) · \(span) · \(context)",
            destination: "Show All Data"
        )
    }
}

extension AppState {
    /// Replaces stored time in bed with Health's current samples for the
    /// window. It is a display cache of Health data, so the window read is
    /// the whole truth: samples deleted in Health disappear here too.
    public mutating func replaceTimeInBed(_ samples: [HealthSleepSample], now: Millis) {
        let windowStart = now - InBed.windowDays * dayMs
        var seen = Set<String>()
        timeInBed = samples.compactMap(InBed.record)
            .filter { $0.end >= windowStart && seen.insert($0.id).inserted }
            .sorted { ($0.end, $0.id) > ($1.end, $1.id) }
        if healthSync.importStatus == .succeeded, healthSync.importedCount == 0, !timeInBed.isEmpty {
            healthSync.lastMessage = InBed.onlyInBedMessage
        }
    }
}
