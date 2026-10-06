import Foundation

/// Exports carry only what was recorded. A day with no entries is written
/// with a blank mg and a "no record" status, never 0 mg, and every row names
/// its data source so Sample Data is never mistaken for the user's entries.
public enum Export {
    public struct DailyTotal: Equatable, Sendable {
        public var date: String
        /// `nil`: nothing was recorded that day.
        public var mg: Int?
        public var entries: Int
        public var source: String?

        public init(date: String, mg: Int?, entries: Int, source: String? = nil) {
            self.date = date
            self.mg = mg
            self.entries = entries
            self.source = source
        }
    }

    static func cell(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func row(_ values: [String]) -> String {
        values.map(cell).joined(separator: ",")
    }

    static func dataSource(_ ids: [String]) -> String {
        RecordSource.of(ids: ids)?.rawValue ?? "Manual"
    }

    public static func dailyTotalsCSV(_ rows: [DailyTotal]) -> String {
        let lines = rows.map { total -> String in
            if let mg = total.mg {
                return row([total.date, "\(mg)", "\(total.entries)", "recorded", total.source ?? ""])
            }
            return row([total.date, "", "0", "no record", ""])
        }
        return (["date,mg,entries,status,data_source"] + lines).joined(separator: "\n")
    }

    /// Gap filling stops past this many days (about 100 years). A longer
    /// span only comes from a mistyped or damaged date, and filling it would
    /// mean millions of rows: -8.64e15 ms, the earliest time a store can
    /// hold, is about 100 million days ago.
    public static let maxFilledDays = 36_600

    /// One row per local calendar day from the first recorded day through
    /// today, stepping by calendar date so DST days are neither skipped nor
    /// doubled. When that span is longer than `maxFilledDays`, only days with
    /// entries are listed, so every recorded day is still exported and the
    /// work grows with the entries, not the span.
    public static func dailyTotalRows(_ doses: [Dose], now: Millis, clock: LocalClock) -> [DailyTotal] {
        let recorded = doses.filter { $0.timestamp.isFinite && $0.mg.isFinite && $0.timestamp <= now }
        guard let first = recorded.map(\.timestamp).min() else { return [] }
        var byDay: [String: [Dose]] = [:]
        for dose in recorded {
            byDay[clock.isoDay(dose.timestamp), default: []].append(dose)
        }
        func total(_ date: String, _ dayDoses: [Dose]) -> DailyTotal {
            DailyTotal(
                date: date,
                mg: jsRoundInt(dayDoses.reduce(0) { $0 + $1.mg }),
                entries: dayDoses.count,
                source: dataSource(dayDoses.map(\.id))
            )
        }
        var day = clock.startOfDay(first)
        let last = clock.startOfDay(now)
        guard (last - day) / dayMs <= Double(maxFilledDays) else {
            // Recorded days only, grouped by each day's absolute start and
            // listed oldest first; date strings don't sort across BC years.
            var byStart: [Millis: [Dose]] = [:]
            for dose in recorded {
                byStart[clock.startOfDay(dose.timestamp), default: []].append(dose)
            }
            return byStart.keys.sorted().map { start in
                total(clock.isoDay(start), byStart[start] ?? [])
            }
        }
        var rows: [DailyTotal] = []
        while day <= last {
            let date = clock.isoDay(day)
            if let dayDoses = byDay[date] {
                rows.append(total(date, dayDoses))
            } else {
                rows.append(DailyTotal(date: date, mg: nil, entries: 0))
            }
            let next = clock.addingDays(1, to: day)
            guard next > day else { break }
            day = next
        }
        return rows
    }

    public static func doseEntriesCSV(_ doses: [Dose], clock: LocalClock) -> String {
        let lines = AppState.stableSorted(doses.filter { $0.timestamp.isFinite && $0.mg.isFinite }) { $0.timestamp < $1.timestamp }
            .map { dose in
                row([
                    dose.id,
                    clock.isoDay(dose.timestamp),
                    numberText(dose.timestamp),
                    isoTimestamp(dose.timestamp),
                    numberText(dose.mg),
                    dose.source ?? "",
                    dose.note ?? "",
                    dataSource([dose.id]),
                ])
            }
        return (["id,local_date,timestamp,datetime,mg,drink,note,data_source"] + lines).joined(separator: "\n")
    }

    public static func vigilanceSessionsCSV(_ sessions: [VigilanceSession]) -> String {
        let header = [
            "id", "started_at", "completed_at", "duration_ms", "trial_count", "valid_reaction_count",
            "false_start_count", "lapse_count", "median_reaction_ms", "mean_reaction_ms",
            "fastest_reaction_ms", "reaction_std_dev_ms", "score", "rating", "data_source",
        ].joined(separator: ",")
        let lines = sessions.map { session in
            row([
                session.id,
                isoTimestamp(session.startedAt),
                isoTimestamp(session.completedAt),
                numberText(session.durationMs),
                "\(session.trialCount)",
                "\(session.validReactionCount)",
                "\(session.falseStartCount)",
                "\(session.lapseCount)",
                session.medianReactionMs.map(numberText) ?? "",
                session.meanReactionMs.map(numberText) ?? "",
                session.fastestReactionMs.map(numberText) ?? "",
                session.reactionStdDevMs.map(numberText) ?? "",
                "\(session.score)",
                session.rating.rawValue,
                RecordID.isSample(session.id) ? "Sample Data" : "Recorded",
            ])
        }
        return ([header] + lines).joined(separator: "\n")
    }
}
