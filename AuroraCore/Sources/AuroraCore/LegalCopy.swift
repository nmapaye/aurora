import Foundation

/// Terms and Privacy, acknowledged once at first launch. These carry the
/// disclosures that cards no longer repeat: estimates are modeled from
/// records, Aurora isn't medical advice, processing stays on device, and how
/// Apple Health data is used. Wording follows the published privacy policy.
public enum LegalCopy {
    /// Bump when the text changes in a way that needs a new acknowledgement.
    public static let version = 1

    public static let acknowledgement = "By continuing, you agree to Aurora’s Terms and Privacy Policy."

    public struct Section: Equatable, Sendable, Identifiable {
        public var id: String { title }
        public var title: String
        public var body: String
    }

    public static let terms: [Section] = [
        Section(title: "Estimates, not measurements",
                body: "Alertness, active caffeine and bedtime caffeine are modeled from what you record: sleep, caffeine, your half-life and sleep target settings, and the time of day. They aren’t measurements, and illness, stress, medication, meals, activity and anything else not recorded aren’t part of the model."),
        Section(title: "Not medical advice",
                body: "Informational only. Aurora doesn’t diagnose, treat, cure or prevent any condition, and it isn’t a medical device. Reaction Tests are a quick check of reaction speed, not a medical assessment. Check with a doctor before medical decisions."),
        Section(title: "On-device explanations",
                body: "When available, Apple’s on-device Foundation Models word explanations and sort requests. Record values and calculations always come from Aurora’s own code; when the model isn’t available, Aurora shows the same facts without it."),
        Section(title: "Sample Data",
                body: "Sample Data is labeled wherever it appears and can be cleared at any time."),
    ]

    public static let privacy: [Section] = [
        Section(title: "On your device",
                body: "Aurora stores your records, settings and conversation on this device. There’s no Aurora account, no cloud AI service, no analytics and no tracking. Exports leave only when you share them."),
        Section(title: "Apple Health",
                body: "Apple Health is optional, with separate choices to read Sleep Analysis, read dietary caffeine, and add caffeine you save in Aurora. What Aurora reads stays read-only. It only updates or removes samples it wrote itself, and never uses Health data for advertising, marketing or resale. Manage access in the Health app under Sharing › Apps › Aurora."),
        Section(title: "Calendars and dictation",
                body: "Only calendars you select are read, and calendar data isn’t sent to an AI provider. Dictation uses on-device speech recognition only."),
        Section(title: "Deleting data",
                body: "Settings can clear records, clear conversation, or erase all local data. Erasing doesn’t delete samples already added to Apple Health; you can delete those in the Health app."),
    ]
}
