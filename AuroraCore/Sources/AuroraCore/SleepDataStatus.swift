import Foundation

/// The Sleep Data panel's one-line state and description. Health access is
/// never described as granted, since HealthKit doesn't reveal read decisions.
public enum SleepDataStatus {
    public struct Description: Equatable, Sendable {
        public var state: String
        public var detail: String
    }

    public static func describe(
        onboarding: Onboarding,
        healthSync: HealthSync,
        demoMode: Bool,
        healthAvailable: Bool,
        refreshError: String? = nil
    ) -> Description {
        let failure: String? = refreshError.map { "Health refresh failed. \($0)" }
            ?? (healthSync.importStatus == .failed ? (healthSync.lastMessage ?? "Health refresh failed. Try again.") : nil)
        let state: String
        if failure != nil {
            state = "Health refresh failed"
        } else if demoMode {
            state = "Sample Data"
        } else if !healthAvailable || (onboarding.permissionStatus == .unsupported && onboarding.source != .manual) {
            // 'unsupported' is also what choosing manual logging stores, so
            // only the device check or a Health source reads as unavailable.
            state = "Health unavailable"
        } else if onboarding.permissionStatus == .denied {
            state = "Health not connected"
        } else if onboarding.permissionStatus == .granted {
            switch healthSync.importStatus {
            case .succeeded: state = healthSync.importedCount > 0 ? "Health sleep imported" : "No sleep found"
            case .importing: state = "Importing sleep"
            default: state = "Health access requested"
            }
        } else {
            state = "Manual mode"
        }

        let detail: String
        if let failure {
            detail = failure
        } else if ["Health sleep imported", "No sleep found", "Importing sleep", "Health access requested"].contains(state) {
            detail = healthSync.importStatus == .succeeded && healthSync.importedCount == 0
                ? "Check sleep records and Aurora’s read access in Health, or add sleep manually."
                : "Refresh reads the last 30 days of sleep from Health."
        } else if state == "Health not connected" {
            detail = "Health access wasn’t set up. You can still log sleep manually."
        } else if state == "Health unavailable" {
            detail = "Health import is unavailable on this device."
        } else if state == "Sample Data" {
            detail = "Example sleep and caffeine data is active."
        } else {
            detail = "Add sleep manually or connect Health when you are ready."
        }
        return Description(state: state, detail: detail)
    }

    public static let unavailableMessage = "Health isn’t available on this device. No sleep was imported."
    public static let notSetUpMessage = "Health access wasn’t set up. No sleep was imported."
}
