import AuroraCore

/// What Aurora Plus unlocks. Logging, the alertness estimate, the Reaction
/// Test, Health import, exports and the week views stay free.
enum PlusAccess {
    static func requiresPlus(_ range: InsightsRange) -> Bool { range != .week }
    static func requiresPlus(_ range: SleepRange) -> Bool { range != .week }

    /// The range a screen shows: the chosen one with Plus, otherwise Week.
    static func shown(_ range: InsightsRange, unlocked: Bool) -> InsightsRange {
        unlocked || !requiresPlus(range) ? range : .week
    }

    static func shown(_ range: SleepRange, unlocked: Bool) -> SleepRange {
        unlocked || !requiresPlus(range) ? range : .week
    }

    /// The lines the purchase screen lists, in order.
    static let included: [(symbol: String, title: String, detail: String)] = [
        ("calendar", "Two-week and month views",
         "See caffeine, Reaction Tests and sleep across 14 and 30 days, with comparisons to the previous period."),
        ("sparkles", "Everything Plus gains later",
         "Upcoming Plus features are included at no extra cost."),
        ("heart", "Support an independent app",
         "No ads, no account, and your records stay on this device."),
    ]
}
