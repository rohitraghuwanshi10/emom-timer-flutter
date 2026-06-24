import Flutter
import UIKit
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, WCSessionDelegate {
  private var eventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if WCSession.isSupported() {
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    
    // Use the standard registrar API to get the binary messenger
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WatchBridgePlugin") {
        let messenger = registrar.messenger()
        let watchChannel = FlutterEventChannel(name: "com.chronoPulse.active/watch_hr", binaryMessenger: messenger)
        watchChannel.setStreamHandler(self)
    }
  }

  // MARK: - WCSessionDelegate
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    // WCSession activated on phone
  }

  func sessionDidBecomeInactive(_ session: WCSession) {
    // Session inactive
  }

  func sessionDidDeactivate(_ session: WCSession) {
    WCSession.default.activate()
  }

  func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
      if let bpm = message["bpm"] as? Int {
          DispatchQueue.main.async {
              self.eventSink?(bpm)
          }
      }
  }
  
  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
      if let bpm = userInfo["bpm"] as? Int {
          DispatchQueue.main.async {
              self.eventSink?(bpm)
          }
      }
  }
}

extension AppDelegate: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
