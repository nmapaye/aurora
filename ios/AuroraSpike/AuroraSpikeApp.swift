import SwiftUI
import AuroraSpikeUI

/// Separate prototype application. It cannot open Aurora's production container.
@main
struct AuroraSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            AuroraSpikeRootView()
                .tint(.blue)
        }
    }
}
