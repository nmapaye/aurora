import Foundation

// One sleep-episode rule for every screen, the model and the Health import
// (docs/research/sleep-and-check-in.md §4 R2, §6). Asleep intervals join
// across gaps under 90 minutes, whatever their source or type. Stage
// samples count only as asleep time: stage minutes are never used.

public enum SleepEpisodeKind: String, Codable, Sendable {
    /// The longest episode of at least 3 hours on its wake day.
    case main
    /// Any other episode of at least 3 hours.
    case secondary
    /// Any other episode under 3 hours.
    case short
    /// The person typed it as a nap, and it isn't the main sleep.
    case nap
}

/// Sessions less than `SleepEpisodes.joinGapMs` apart. `start`/`end` are the
/// span; `asleepMs` is the union of the asleep intervals, overlaps counted
/// once, so a 45-minute awakening is inside the span but not asleep time.
public struct SleepEpisodeV2: Equatable, Sendable {
    public var start: Millis
    public var end: Millis
    public var asleepMs: Millis
    public var kind: SleepEpisodeKind
    /// `LocalClock.dayKey` of `end`.
    public var wakeDayKey: String
    public var sessions: [SleepSession]

    public var sessionIDs: [String] { sessions.map(\.id) }
    public var spanMs: Millis { end - start }
    public var includesSample: Bool { sessions.contains { RecordID.isSample($0.id) } }
}

public enum SleepEpisodes {
    /// A gap shorter than this joins two asleep intervals (`<`, not `<=`).
    /// ABCD Study Fitbit pipeline `gap = 90`.
    public static let joinGapMs: Millis = 90 * minuteMs
    /// A main sleep is at least this much asleep time. ABCD `main_duration = 180`.
    public static let mainMinimumMs: Millis = 180 * minuteMs

    /// Joins intervals whose gap is under `joinGapMs`; touching and
    /// overlapping intervals always join. Returns spans, oldest first.
    public static func spans(_ intervals: [Interval]) -> [Interval] {
        let ordered = intervals
            .filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.end < $1.end }
        var joined: [Interval] = []
        for interval in ordered {
            if let last = joined.last, interval.start - last.end < joinGapMs {
                joined[joined.count - 1].end = max(last.end, interval.end)
            } else {
                joined.append(interval)
            }
        }
        return joined
    }

    public static func spans(_ sessions: [SleepSession]) -> [Interval] {
        spans(sessions.map { Interval(start: $0.start, end: $0.end) })
    }

    /// Episodes from sessions that ended by `now` (end after start, finite),
    /// across every source and type, oldest first, each with its kind.
    public static func build(_ sessions: [SleepSession], now: Millis, clock: LocalClock) -> [SleepEpisodeV2] {
        let ordered = sessions
            .filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start && $0.end <= now }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.start != rhs.element.start { return lhs.element.start < rhs.element.start }
                if lhs.element.end != rhs.element.end { return lhs.element.end < rhs.element.end }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        var groups: [(end: Millis, sessions: [SleepSession])] = []
        for session in ordered {
            if let last = groups.last, session.start - last.end < joinGapMs {
                groups[groups.count - 1].sessions.append(session)
                groups[groups.count - 1].end = max(last.end, session.end)
            } else {
                groups.append((session.end, [session]))
            }
        }
        var episodes = groups.map { group -> SleepEpisodeV2 in
            let start = group.sessions.map(\.start).min() ?? group.sessions[0].start
            return SleepEpisodeV2(
                start: start, end: group.end,
                asleepMs: SleepModel.unionDuration(group.sessions),
                kind: .short, wakeDayKey: clock.dayKey(group.end), sessions: group.sessions
            )
        }
        classify(&episodes)
        return episodes
    }

    /// Main: the longest episode of at least 3 h asleep on its wake day,
    /// ties to the later wake. An episode made only of sessions the person
    /// typed as naps is never main: their label wins.
    static func classify(_ episodes: inout [SleepEpisodeV2]) {
        var mainByDay: [String: Int] = [:]
        for (index, episode) in episodes.enumerated() {
            let eligible = episode.asleepMs >= mainMinimumMs && episode.sessions.contains { $0.type != .nap }
            guard eligible else { continue }
            if let current = mainByDay[episode.wakeDayKey] {
                let best = episodes[current]
                if episode.asleepMs > best.asleepMs || (episode.asleepMs == best.asleepMs && episode.end > best.end) {
                    mainByDay[episode.wakeDayKey] = index
                }
            } else {
                mainByDay[episode.wakeDayKey] = index
            }
        }
        let mains = Set(mainByDay.values)
        for index in episodes.indices {
            if mains.contains(index) {
                episodes[index].kind = .main
            } else if episodes[index].sessions.contains(where: { $0.type == .nap }) {
                episodes[index].kind = .nap
            } else {
                episodes[index].kind = episodes[index].asleepMs >= mainMinimumMs ? .secondary : .short
            }
        }
    }

    /// Asleep time on each wake day: every episode, naps and short sleep
    /// included, overlaps counted once.
    public static func asleepByWakeDay(_ episodes: [SleepEpisodeV2]) -> [String: Millis] {
        var sessions: [String: [SleepSession]] = [:]
        for episode in episodes { sessions[episode.wakeDayKey, default: []].append(contentsOf: episode.sessions) }
        return sessions.mapValues(SleepModel.unionDuration)
    }
}
