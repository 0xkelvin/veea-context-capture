import Flutter
import UIKit
import ReplayKit

@main
@objc class AppDelegate: FlutterAppDelegate {

  private let appGroupID = "group.ai.bluleap.veea"

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

  // MARK: - Auto-restart on screen unlock

  /// Delay before triggering auto-restart, in seconds.
  /// Lets the app UI fully settle after the screen wakes before the broadcast picker is shown.
  private let autoRestartDelay: TimeInterval = 1.5

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    restartCaptureIfNeeded()
  }

  /// Restarts the broadcast capture if the user previously had it running but
  /// it was stopped by a screen lock (power-button press).
  private func restartCaptureIfNeeded() {
    let defaults = UserDefaults(suiteName: appGroupID)
    let wantsActive = defaults?.bool(forKey: "capture_wants_active") ?? false
    let isRunning  = defaults?.bool(forKey: "capture_is_running")  ?? false

    guard wantsActive && !isRunning else { return }

    // Delay slightly to let the app UI fully settle after the screen wakes.
    DispatchQueue.main.asyncAfter(deadline: .now() + autoRestartDelay) { [weak self] in
      guard let self = self,
            let rootView = self.window?.rootViewController?.view else { return }
      self.triggerBroadcastPicker(on: rootView)
    }
  }

  // MARK: - Broadcast picker helper

  /// Adds an `RPSystemBroadcastPickerView` to `parentView`, programmatically
  /// taps its button to launch the CaptureEngine broadcast, then removes the
  /// view after a short delay.
  private func triggerBroadcastPicker(on parentView: UIView) {
    let pickerView = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
    if let bundleId = Bundle.main.bundleIdentifier {
      pickerView.preferredExtension = bundleId + ".CaptureEngine"
    }

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
