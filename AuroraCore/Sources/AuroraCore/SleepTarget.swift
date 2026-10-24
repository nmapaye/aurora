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
        isEightAfterNotNow(prefs: prefs, onboarding: onboarding)
            && onboarding.setupOutcomes?[chosenKey] == nil
    }

    /// Written into `setupOutcomes` beside the step outcomes when the file
    /// holds 8 h with "Not now" at setup, which in this build is always a
    /// target the person chose. Older builds drop `sleepTargetFormat` and the
    /// `chosen…` keys when they save, but keep `setupOutcomes` whole (it is
    /// `[String: String]` in every one of them) and look up only step numbers
    /// in it, so this survives a downgrade that saves and keeps the migration
    /// from clearing the choice. Never in the decoded state.
    public static let chosenKey = "sleepTargetChosen"

    static func isEightAfterNotNow(prefs: Prefs, onboarding: Onboarding) -> Bool {
        prefs.targetSleep == formerDefault
            && onboarding.setupOutcomes?[String(SetupStep.sleepTarget.rawValue)] == SetupOutcome.skipped.rawValue
    }
}
