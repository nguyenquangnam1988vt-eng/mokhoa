// ios/Runner/AppDelegate.swift

import UIKit
import Flutter
// Cần import CoreLocation và UserNotifications nếu chưa có
import CoreLocation 
import UserNotifications 

@UIApplicationMain
class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Khởi tạo và chạy Monitor ngay khi ứng dụng khởi động
        // Sử dụng Singleton instance
        UnlockMonitor.shared.startMonitoring() 

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}