import AuroraCore
import UIKit

/// Owns the app model so Health observer queries are registered at launch,
/// as HealthKit background delivery requires, including when Health wakes
/// Aurora in the background. Observers exist only for Health reads the
/// person chose; Health wakes Aurora only if they also chose background
/// updates.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-AuroraDesignGallery") { return true }
        #endif
        model.load()
        if model.phase == .ready, model.state.onboarding.completed {
            Task { await model.healthSync.startObservers() }
        }
        return true
    }
}
