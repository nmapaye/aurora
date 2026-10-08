import BackgroundTasks
import Foundation

enum BackgroundRefresh {
    static let identifier = "com.nmapaye.aurora.assistant.refresh"
    static func schedule(enabled: Bool) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard enabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(30 * 60)
        // iOS controls whether/when this opportunity is granted. Foreground
        // refresh and explicit local reminders remain the reliable paths.
        try? BGTaskScheduler.shared.submit(request)
    }
}
