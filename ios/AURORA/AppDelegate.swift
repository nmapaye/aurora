internal import Expo
import React
import ReactAppDependencyProvider

@main
class AppDelegate: ExpoAppDelegate {
  var window: UIWindow?

  var reactNativeDelegate: ExpoReactNativeFactoryDelegate?
  var reactNativeFactory: RCTReactNativeFactory?
  private var launchOptions: [UIApplication.LaunchOptionsKey: Any]?

  public override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    self.launchOptions = launchOptions
    return prepareReactNative(application)
  }

  private func prepareReactNative(_ application: UIApplication) -> Bool {
    if reactNativeFactory != nil { return true }

    do {
      let documents = try FileManager.default.url(
        for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      try StoragePrivacy.prepareMMKV(in: documents)
    } catch {
      // Do not start MMKV or import Health records until backup exclusion holds.
      // The connecting scene presents recovery without starting React Native.
      return true
    }

    let delegate = ReactNativeDelegate()
    let factory = ExpoReactNativeFactory(delegate: delegate)
    delegate.dependencyProvider = RCTAppDependencyProvider()

    reactNativeDelegate = delegate
    reactNativeFactory = factory

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func startReactNative(
    in window: UIWindow,
    connectionOptions: UIScene.ConnectionOptions
  ) {
    self.window = window
    _ = prepareReactNative(UIApplication.shared)
    guard let factory = reactNativeFactory else {
      showStorageRecovery(in: window, connectionOptions: connectionOptions)
      return
    }

    // UIKit supplies cold-start links to the scene, not didFinishLaunching.
    var options = launchOptions ?? [:]
    if let context = connectionOptions.urlContexts.first {
      options[.url] = context.url
      options[.sourceApplication] = context.options.sourceApplication
      options[.annotation] = context.options.annotation
    }
    if let activity = connectionOptions.userActivities.first {
      options[.userActivityDictionary] = [
        "UIApplicationLaunchOptionsUserActivityTypeKey": activity.activityType,
        "UIApplicationLaunchOptionsUserActivityKey": activity,
      ]
    }
    factory.startReactNative(withModuleName: "main", in: window, launchOptions: options)
  }

  private func showStorageRecovery(
    in window: UIWindow,
    connectionOptions: UIScene.ConnectionOptions
  ) {
    let controller = UIViewController()
    controller.view.backgroundColor = .systemBackground
    let message = UILabel()
    message.text = "AURORA could not protect local records from device backups. Your existing records have not been deleted. Retry to open the app. If this continues, close the app and contact support."
    message.numberOfLines = 0
    message.font = .preferredFont(forTextStyle: .body)
    message.adjustsFontForContentSizeCategory = true
    let retry = UIButton(type: .system)
    retry.setTitle("Retry opening AURORA", for: .normal)
    retry.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    retry.titleLabel?.adjustsFontForContentSizeCategory = true
    retry.addAction(UIAction { [weak self, weak window] _ in
      guard let window else { return }
      self?.startReactNative(in: window, connectionOptions: connectionOptions)
    }, for: .touchUpInside)
    let scroll = UIScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    controller.view.addSubview(scroll)
    let stack = UIStackView(arrangedSubviews: [message, retry])
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(stack)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
      stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
      retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
    window.rootViewController = controller
    window.makeKeyAndVisible()
  }

  // Linking API
  public override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return super.application(app, open: url, options: options) || RCTLinkingManager.application(app, open: url, options: options)
  }

  // Universal Links
  public override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    let result = RCTLinkingManager.application(application, continue: userActivity, restorationHandler: restorationHandler)
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler) || result
  }
}

// Expo SDK 57's installed runtime still uses application delegate callbacks.
// Bridge the single scene to those callbacks until Expo supplies its scene delegate.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  private var appDelegate: AppDelegate? {
    UIApplication.shared.delegate as? AppDelegate
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    self.window = window
    appDelegate?.startReactNative(in: window, connectionOptions: connectionOptions)
  }

  func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    for context in contexts {
      var options: [UIApplication.OpenURLOptionsKey: Any] = [
        .openInPlace: context.options.openInPlace,
      ]
      options[.sourceApplication] = context.options.sourceApplication
      options[.annotation] = context.options.annotation
      _ = appDelegate?.application(UIApplication.shared, open: context.url, options: options)
    }
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    _ = appDelegate?.application(
      UIApplication.shared, continue: userActivity, restorationHandler: { _ in })
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    appDelegate?.applicationDidBecomeActive(UIApplication.shared)
  }

  func sceneWillResignActive(_ scene: UIScene) {
    appDelegate?.applicationWillResignActive(UIApplication.shared)
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    appDelegate?.applicationWillEnterForeground(UIApplication.shared)
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    appDelegate?.applicationDidEnterBackground(UIApplication.shared)
  }
}

class ReactNativeDelegate: ExpoReactNativeFactoryDelegate {
  // Extension point for config-plugins

  override func sourceURL(for bridge: RCTBridge) -> URL? {
    // needed to return the correct URL for expo-dev-client.
    bridge.bundleURL ?? bundleURL()
  }

  override func bundleURL() -> URL? {
#if DEBUG
    return RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: ".expo/.virtual-metro-entry")
#else
    return Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
  }
}
