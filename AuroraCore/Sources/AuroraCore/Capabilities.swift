import Foundation

/// One thing Aurora can do, and the request that does it. The same list
/// drives the quick tiles and next steps above the composer, the "What can
/// you do?" card, composer suggestions and a card's refresh, so a capability is never
/// reachable only by guessing its wording.
public struct Capability: Equatable, Identifiable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case log = "Log", understand = "Understand", plan = "Plan", records = "Records", help = "Help"
    }

    public var intent: AssistantIntent
    public var title: String
    /// One line on a tile about 84 pt wide at caption weight. The full
    /// title stays its accessibility label.
    public var shortTitle: String
    /// Sent as if typed. `AssistantPlanner.explicitIntent` routes it without
    /// a model, so tapping always does what the title says.
    public var phrase: String
    public var group: Group
    /// SF Symbol name.
    public var symbol: String
    /// Extra words that find it while typing.
    public var keywords: [String]

    public var id: AssistantIntent { intent }
}

public enum Capabilities {
    public static let all: [Capability] = [
        .init(intent: .logCaffeine, title: "Log caffeine", shortTitle: "Caffeine", phrase: "Log caffeine", group: .log, symbol: "cup.and.saucer", keywords: ["coffee", "drink", "espresso", "tea", "matcha", "add"]),
        .init(intent: .logSleep, title: "Log sleep", shortTitle: "Sleep", phrase: "Log sleep", group: .log, symbol: "moon", keywords: ["slept", "night", "bed", "nap"]),
        .init(intent: .energyCheckIn, title: "Check in my energy", shortTitle: "Check in", phrase: "Check in my energy", group: .log, symbol: "hand.raised", keywords: ["rate", "feel", "feeling", "tired"]),
        .init(intent: .explainEnergy, title: "How is my energy?", shortTitle: "Energy", phrase: "How is my energy?", group: .understand, symbol: "sparkle", keywords: ["energy", "alertness", "tired", "now"]),
        .init(intent: .energyProjection, title: "Show my energy curve", shortTitle: "Curve", phrase: "Show my energy curve", group: .understand, symbol: "chart.xyaxis.line", keywords: ["curve", "later", "tonight", "projection", "24 hours"]),
        .init(intent: .weeklyTrends, title: "Show this week", shortTitle: "This week", phrase: "Show this week", group: .understand, symbol: "chart.bar", keywords: ["trends", "week", "month", "patterns"]),
        .init(intent: .reactionTest, title: "Reaction test", shortTitle: "Reaction", phrase: "Reaction test", group: .understand, symbol: "hand.tap", keywords: ["reaction", "speed", "test", "focus"]),
        .init(intent: .briefing, title: "Morning briefing", shortTitle: "Briefing", phrase: "Morning briefing", group: .plan, symbol: "sun.horizon", keywords: ["today", "day", "summary", "morning"]),
        .init(intent: .calendar, title: "Review my day", shortTitle: "My day", phrase: "Review calendar", group: .plan, symbol: "calendar", keywords: ["calendar", "schedule", "commitments", "events", "meetings"]),
        .init(intent: .cutoffScenario, title: "Cutoff scenario", shortTitle: "Cutoff", phrase: "Cutoff scenario", group: .plan, symbol: "moon.zzz", keywords: ["cutoff", "bedtime", "what if", "scenario", "last coffee"]),
        .init(intent: .history, title: "History", shortTitle: "History", phrase: "History", group: .records, symbol: "clock.arrow.circlepath", keywords: ["past", "entries", "records", "edit"]),
        .init(intent: .exports, title: "Export records", shortTitle: "Export", phrase: "Export records", group: .records, symbol: "square.and.arrow.up", keywords: ["export", "csv", "share", "download"]),
        .init(intent: .reminders, title: "Reminders", shortTitle: "Reminders", phrase: "Reminders", group: .records, symbol: "bell", keywords: ["reminder", "notification", "alert", "wake", "follow up"]),
        .init(intent: .settings, title: "Settings", shortTitle: "Settings", phrase: "settings", group: .records, symbol: "slider.horizontal.3", keywords: ["preferences", "health", "apple health", "appearance", "privacy"]),
        .init(intent: .help, title: "What can you do?", shortTitle: "Help", phrase: "What can you do?", group: .help, symbol: "questionmark.circle", keywords: ["help", "features", "options", "everything"]),
    ]

    public static func capability(_ intent: AssistantIntent) -> Capability? {
        all.first { $0.intent == intent }
    }

    /// The four everyday actions on the quick tiles.
    public static let tiles: [AssistantIntent] = [.briefing, .logCaffeine, .explainEnergy, .reactionTest]

    /// One of the four places in the fixed row above the composer.
    public struct RowTile: Equatable, Identifiable, Sendable {
        public var capability: Capability
        /// Offered after the newest answer, not one of the everyday tiles.
        public var isNextStep: Bool
        public var id: AssistantIntent { capability.intent }
    }

    /// The fixed row above the composer, always four: the newest answer's
    /// next steps first, then the everyday tiles not already there. Next
    /// steps live here, not under the answer: moving them between lazy
    /// conversation rows changed two rows' heights off screen, and the
    /// conversation never stopped laying out (iOS 26.5). Timed by the card's
    /// capture, so the steps don't change while it's being read.
    public static func bottomRow(after card: AssistantCard?, clock: LocalClock) -> [RowTile] {
        let next = card.map { FollowUps.after($0, now: $0.capturedAt, clock: clock) } ?? []
        let steps = next.prefix(tiles.count).map { RowTile(capability: $0, isNextStep: true) }
        let everyday = tiles.filter { intent in !steps.contains { $0.id == intent } }
            .compactMap(capability).map { RowTile(capability: $0, isNextStep: false) }
        return Array((steps + everyday).prefix(tiles.count))
    }

    public static let matchLimit = 3

    /// Up to three capabilities for what's being typed: words in the title
    /// first, then keywords, then the phrase. Every typed word must start a
    /// word somewhere in the capability, so "cut" finds Cutoff scenario and
    /// "energy cu" finds the curve.
    public static func matching(_ input: String) -> [Capability] {
        let typed = words(input)
        guard !typed.isEmpty, typed.joined().count >= 2 else { return [] }
        func score(_ capability: Capability) -> Int? {
            let title: [String] = words(capability.title)
            let keywords: [String] = capability.keywords.flatMap { words($0) }
            let named: [String] = title + keywords
            let all: [String] = named + words(capability.phrase)
            guard typed.allSatisfy({ word in all.contains { $0.hasPrefix(word) } }) else { return nil }
            if typed.allSatisfy({ word in title.contains { $0.hasPrefix(word) } }) { return 0 }
            if typed.allSatisfy({ word in named.contains { $0.hasPrefix(word) } }) { return 1 }
            return 2
        }
        var ranked: [(rank: Int, index: Int, capability: Capability)] = []
        for (index, capability) in all.enumerated() {
            if let rank = score(capability) { ranked.append((rank, index, capability)) }
        }
        ranked.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.index < $1.index }
        return ranked.prefix(matchLimit).map(\.capability)
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}

/// Two or three natural next steps after a card. Deterministic, from the
/// card alone, and never an amount or a time to drink.
public enum FollowUps {
    public static func after(_ card: AssistantCard, now: Millis, clock: LocalClock) -> [Capability] {
        let afternoon = (12..<20).contains(clock.hour(now))
        let intents: [AssistantIntent] = switch card.kind {
        case .energy: [.energyProjection, .energyCheckIn]
        case .energyProjection: afternoon ? [.cutoffScenario, .energyCheckIn] : [.energyCheckIn, .weeklyTrends]
        case .energyCheckIn: card.state == .saved ? [.energyProjection, .weeklyTrends] : []
        case .trends: [.history, .exports]
        case .briefing: [.calendar, .energyProjection]
        case .calendar: [.briefing, .energyProjection]
        case .reaction: [.weeklyTrends, .explainEnergy]
        case .history: [.exports, .weeklyTrends]
        case .cutoffScenario: [.energyProjection]
        case .receipt:
            switch card.recordKind {
            case "caffeine": card.state == .saved ? [.energyProjection, .explainEnergy] : []
            case "sleep": card.state == .saved ? [.explainEnergy, .energyProjection] : []
            case "checkin": card.state == .saved ? [.energyProjection] : []
            default: []
            }
        case .reminders, .exports, .caffeineDraft, .sleepDraft, .clarification, .capabilities, .repeatDrink: []
        }
        return intents.compactMap(Capabilities.capability)
    }
}
