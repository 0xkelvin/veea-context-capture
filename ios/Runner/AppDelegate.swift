import Flutter
import UIKit
import ReplayKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  private let appGroupID = "group.ai.bluleap.veea"

  // MARK: - Background-entry tracking

  /// Recorded in `applicationDidEnterBackground` so that when the app becomes
  /// active again we know how long it was backgrounded.  This lets us detect
  /// screen-lock-induced extension termination where `broadcastFinished()` may
  /// never be called, leaving `capture_is_running` stale (true).
  private var backgroundEntryTime: Date?

  // MARK: - Restart-banner state

  private var restartBannerView: UIView?
  private var restartCheckTimer: Timer?

  // Delay (s) before the restart banner appears after the screen wakes,
  // giving the Flutter UI time to fully settle.
  private let autoRestartDelay: TimeInterval = 1.0

  // MARK: - Method channel setup

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let bridgeChannel = FlutterMethodChannel(name: "ai.bluleap.veea/bridge",
                                              binaryMessenger: controller.binaryMessenger)
    
    bridgeChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }
      if call.method == "getSharedDir" {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: self.appGroupID)
        guard let path = container?.appendingPathComponent("snapshots").path else {
            result(FlutterError(code: "UNAVAILABLE", message: "App Group not accessible", details: nil))
            return
        }
        result(path)
      } else if call.method == "setSetting" {
          if let args = call.arguments as? [String: Any],
             let key = args["key"] as? String,
             let value = args["value"] {
              let defaults = UserDefaults(suiteName: self.appGroupID)
              defaults?.set(value, forKey: key)
              result(true)
          } else {
              result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
          }
      } else if call.method == "getSetting" {
          if let args = call.arguments as? [String: Any],
             let key = args["key"] as? String {
              let defaults = UserDefaults(suiteName: self.appGroupID)
              let value = defaults?.object(forKey: key)
              result(value)
          } else {
              result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
          }
      } else if call.method == "launchCapture" {
          if let rv = controller.view {
              self.triggerBroadcastPicker(on: rv)
          }
          result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - App-lifecycle hooks

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    backgroundEntryTime = Date()
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    restartCaptureIfNeeded()
  }

  /// Dismiss the restart banner (without animation) whenever the app loses
  /// focus so it never persists in a stale state on next resume.
  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    restartCheckTimer?.invalidate()
    restartCheckTimer = nil
    dismissRestartBanner(animated: false)
  }

  // MARK: - Auto-restart on screen unlock

  /// Checks whether capture needs to be restarted after a screen lock and,
  /// if so, shows the in-app restart banner.
  ///
  /// iOS may terminate the broadcast extension during a screen lock without
  /// calling `broadcastFinished()`, leaving `capture_is_running` stale (true)
  /// and preventing the restart condition from being satisfied.  We detect
  /// this by comparing how long the app was in the background: if it was
  /// backgrounded for more than two seconds the flag is proactively reset.
  private func restartCaptureIfNeeded() {
    let defaults = UserDefaults(suiteName: appGroupID)
    let wantsActive = defaults?.bool(forKey: "capture_wants_active") ?? false

    // Reset a stale isRunning flag caused by silent extension termination.
    if let bgTime = backgroundEntryTime {
      let elapsed = Date().timeIntervalSince(bgTime)
      let isRunning = defaults?.bool(forKey: "capture_is_running") ?? false
      if isRunning && elapsed > 2.0 {
        defaults?.set(false, forKey: "capture_is_running")
        defaults?.synchronize()
      }
      backgroundEntryTime = nil
    }

    let isRunning = defaults?.bool(forKey: "capture_is_running") ?? false
    guard wantsActive && !isRunning else { return }

    // Wait briefly for the app UI to settle, then surface the restart banner.
    DispatchQueue.main.asyncAfter(deadline: .now() + autoRestartDelay) { [weak self] in
      self?.showRestartBanner()
    }
  }

  // MARK: - Restart banner

  /// Displays a floating native banner at the bottom of the window that
  /// contains a real `RPSystemBroadcastPickerView` button.
  ///
  /// Because the user taps the button directly (a genuine UIKit touch event),
  /// iOS starts the broadcast immediately without presenting an additional
  /// system confirmation sheet — unlike a programmatic `sendActions` call,
  /// which iOS 15+ treats as a non-user-initiated action and responds to with
  /// a system-level "Start Broadcast" prompt.
  private func showRestartBanner() {
    guard restartBannerView == nil, let window = self.window else { return }

    let banner = UIView()
    banner.backgroundColor = UIColor(white: 0.10, alpha: 0.94)
    banner.layer.cornerRadius = 14
    banner.clipsToBounds = true
    banner.translatesAutoresizingMaskIntoConstraints = false

    let label = UILabel()
    label.text = "Recording paused — tap \u{25CF} to resume"
    label.textColor = UIColor(white: 0.95, alpha: 1)
    label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.8
    label.translatesAutoresizingMaskIntoConstraints = false

    // The RPSystemBroadcastPickerView is the tappable element.
    // With preferredExtension set, a genuine tap starts the broadcast for
    // our CaptureEngine extension directly — no extension-picker sheet shown.
    let picker = RPSystemBroadcastPickerView()
    if let bundleId = Bundle.main.bundleIdentifier {
      picker.preferredExtension = bundleId + ".CaptureEngine"
    }
    picker.showsMicrophoneButton = false
    picker.translatesAutoresizingMaskIntoConstraints = false

    let closeButton = UIButton(type: .system)
    let xImage = UIImage(systemName: "xmark")?
      .withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
    closeButton.setImage(xImage, for: .normal)
    closeButton.tintColor = UIColor(white: 0.60, alpha: 1)
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.addTarget(self, action: #selector(dismissRestartBannerTapped), for: .touchUpInside)

    banner.addSubview(label)
    banner.addSubview(picker)
    banner.addSubview(closeButton)
    window.addSubview(banner)

    NSLayoutConstraint.activate([
      // Banner floats above the home indicator / bottom safe area.
      banner.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 16),
      banner.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -16),
      banner.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -16),
      banner.heightAnchor.constraint(equalToConstant: 56),

      // Close (×) button on the far right.
      closeButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -4),
      closeButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
      closeButton.widthAnchor.constraint(equalToConstant: 36),
      closeButton.heightAnchor.constraint(equalToConstant: 36),

      // Broadcast picker button to the left of the close button.
      picker.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
      picker.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
      picker.widthAnchor.constraint(equalToConstant: 44),
      picker.heightAnchor.constraint(equalToConstant: 44),

      // Label fills remaining width.
      label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
      label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
      label.trailingAnchor.constraint(lessThanOrEqualTo: picker.leadingAnchor, constant: -8),
    ])

    restartBannerView = banner
    startRestartBannerPolling()
  }

  @objc private func dismissRestartBannerTapped() {
    restartCheckTimer?.invalidate()
    restartCheckTimer = nil
    dismissRestartBanner(animated: true)
  }

  private func dismissRestartBanner(animated: Bool) {
    guard let banner = restartBannerView else { return }
    restartBannerView = nil
    if animated {
      UIView.animate(withDuration: 0.25, animations: {
        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: 20)
      }, completion: { _ in banner.removeFromSuperview() })
    } else {
      banner.removeFromSuperview()
    }
  }

  /// Polls the shared UserDefaults every 0.5 s so the banner auto-dismisses
  /// as soon as the broadcast starts (isRunning becomes true) or the user
  /// cancels their recording intent from the Flutter UI (wantsActive becomes false).
  private func startRestartBannerPolling() {
    restartCheckTimer?.invalidate()
    restartCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      let defaults = UserDefaults(suiteName: self.appGroupID)
      defaults?.synchronize()
      let isRunning   = defaults?.bool(forKey: "capture_is_running")   ?? false
      let wantsActive = defaults?.bool(forKey: "capture_wants_active") ?? false
      if isRunning || !wantsActive {
        self.restartCheckTimer?.invalidate()
        self.restartCheckTimer = nil
        DispatchQueue.main.async { self.dismissRestartBanner(animated: true) }
      }
    }
  }

  // MARK: - Broadcast picker helper (manual launch via Flutter "Tap to Record" button)

  /// Adds an `RPSystemBroadcastPickerView` to `parentView`, programmatically
  /// taps its button to launch the CaptureEngine broadcast, then removes the
  /// view after a short delay.  Used only for the explicit user-initiated
  /// "Tap to Record" / "Resume Capture" actions from the Flutter UI where a
  /// real Flutter tap event has already been received.
  private func triggerBroadcastPicker(on parentView: UIView) {
    let pickerView = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
    if let bundleId = Bundle.main.bundleIdentifier {
      pickerView.preferredExtension = bundleId + ".CaptureEngine"
    }
    // Hide the microphone-button variant: this app captures video frames only
    // and does not use audio, so the simpler single-button layout is correct.
    // The restart banner's RPSystemBroadcastPickerView is configured the same way.
    pickerView.showsMicrophoneButton = false

    parentView.addSubview(pickerView)

    // Programmatically tap the native button
    for view in pickerView.subviews {
      if let button = view as? UIButton {
        button.sendActions(for: .touchUpInside)
        break
      }
    }

    // Remove it after a slight delay to ensure iOS processes the touch
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      pickerView.removeFromSuperview()
    }
  }
}
