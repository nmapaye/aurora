import SwiftUI
import AuroraSpikeUI
#if os(macOS)
import AppKit

@MainActor
final class PreviewAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
#endif

@main
struct AuroraSpikePreviewApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(PreviewAppDelegate.self) private var appDelegate
    #endif
    var body: some Scene {
        WindowGroup("Aurora · Native design preview") {
            AuroraSpikeRootView()
                .frame(minWidth: 380, minHeight: 680)
        }
        .defaultSize(width: 1080, height: 820)
    }
}
