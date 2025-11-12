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
            let eventChannel = FlutterEventChannel(
                name: "com.example.app/monitor_events",
                binaryMessenger: controller.binaryMessenger
            )
            eventChannel.setStreamHandler(UnlockMonitor.shared)
        }
        
        // 🎯 THÊM: Khởi động monitoring sau 1 giây để đảm bảo Flutter ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            UnlockMonitor.shared.startMonitoring()
            print("🚀 UnlockMonitor đã khởi động")
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // 🎯 THÊM: Xử lý khi app vào background/foreground (tùy chọn)
    override func applicationDidEnterBackground(_ application: UIApplication) {
        print("📱 App vào background - Monitoring vẫn chạy")
    }
    
    override func applicationWillEnterForeground(_ application: UIApplication) {
        print("📱 App lên foreground - Monitoring tiếp tục")
    }
}