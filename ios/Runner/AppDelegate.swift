import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Same channel and method as Android's MainActivity ("phone"), minus the SDK level.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GlyphPlatform") {
      let channel = FlutterMethodChannel(name: "glyph/platform", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "phone" else { return result(FlutterMethodNotImplemented) }
        var info = utsname()
        uname(&info)
        let model = withUnsafePointer(to: &info.machine) {
          $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
        result([
          "model": model,
          "ios": UIDevice.current.systemVersion,
          "tz": TimeZone.current.identifier,
        ])
      }
    }
  }
}
