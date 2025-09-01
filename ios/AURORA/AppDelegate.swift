import UIKit
import ExpoModulesCore

@main
class AppDelegate: ExpoAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ExpoAppDelegate sets up React Native bridge, root view, and Expo modules.
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
