import Flutter
import UIKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as? FlutterViewController
    let channel = FlutterMethodChannel(
      name: "study_assistant/external_links",
      binaryMessenger: controller!.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "openUrl" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let urlText = args["url"] as? String,
        let url = URL(string: urlText)
      else {
        result(false)
        return
      }
      application.open(url, options: [:]) { opened in
        result(opened)
      }
    }
    let permissionsChannel = FlutterMethodChannel(
      name: "study_assistant/permissions",
      binaryMessenger: controller!.binaryMessenger
    )
    permissionsChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "openNotificationSettings",
        "openExactAlarmSettings",
        "openLockScreenNotificationSettings",
        "openBatterySettings",
        "openAppSettings":
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          result(false)
          return
        }
        application.open(url, options: [:]) { opened in
          result(opened)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
