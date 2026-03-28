import Flutter
import UIKit
import ReplayKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let bridgeChannel = FlutterMethodChannel(name: "ai.bluleap.veea/bridge",
                                              binaryMessenger: controller.binaryMessenger)
    
    bridgeChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "getSharedDir" {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ai.bluleap.veea")
        guard let path = container?.appendingPathComponent("snapshots").path else {
            result(FlutterError(code: "UNAVAILABLE", message: "App Group not accessible", details: nil))
            return
        }
        result(path)
      } else if call.method == "setSetting" {
          if let args = call.arguments as? [String: Any],
             let key = args["key"] as? String,
             let value = args["value"] {
              let defaults = UserDefaults(suiteName: "group.ai.bluleap.veea")
              defaults?.set(value, forKey: key)
              defaults?.synchronize()
              result(true)
          } else {
              result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
          }
      } else if call.method == "getSetting" {
          if let args = call.arguments as? [String: Any],
             let key = args["key"] as? String {
              let defaults = UserDefaults(suiteName: "group.ai.bluleap.veea")
              let value = defaults?.object(forKey: key)
              result(value)
          } else {
              result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
          }
      } else if call.method == "launchCapture" {
          let pickerView = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
          if let bundleId = Bundle.main.bundleIdentifier {
              pickerView.preferredExtension = bundleId + ".CaptureEngine"
          }
          
          if let rv = controller.view {
              rv.addSubview(pickerView)
              
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
          result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
