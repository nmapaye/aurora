import Foundation

/// The nightly sleep target has no default (docs/research/sleep-and-check-in.md
/// §4 R1, §7). Earlier builds pre-selected 8 h and kept it when setup's
/// sleep-target question was answered "Not now", so a stored 8 h didn't
/// always mean the person chose it.
public enum SleepTargetMigration {
    /// `AppState.sleepTargetFormat` written by builds where the target can be
    /// unset. Files without it come from builds that pre-selected 8 h.
    public static let currentFormat = 1
    /// The value earlier builds pre-selected.
    public static let formerDefault: Double = 8

    /// True for a target the person never chose: 8 h kept by answering
    /// "Not now" at setup's sleep-target question. A target answered at
    /// setup, any other value, or one from before setup outcomes were kept
    /// is theirs and stays.
    public static func clearsTarget(prefs: Prefs, onboarding: Onboarding) -> Bool {
        prefs.targetSleep == formerDefault
            && onboarding.setupOutcomes?[String(SetupStep.sleepTarget.rawValue)] == SetupOutcome.skipped.rawValue
    }
}
