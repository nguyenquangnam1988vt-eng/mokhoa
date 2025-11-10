import UIKit
import Flutter

@UIApplicationMain
class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        GeneratedPluginRegistrant.register(with: self)
        
        if let controller = window?.rootViewController as? FlutterViewController {
            // Sử dụng EventChannel thay vì MethodChannel
            let eventChannel = FlutterEventChannel(
                name: "com.example.app/monitor_events",
                binaryMessenger: controller.binaryMessenger
            )
            
            // Thiết lập stream handler
            eventChannel.setStreamHandler(UnlockMonitor.shared)
        }
        
        UnlockMonitor.shared.startMonitoring()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}