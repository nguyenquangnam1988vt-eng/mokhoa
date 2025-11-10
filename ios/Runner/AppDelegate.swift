// ios/Runner/AppDelegate.swift (Đã cập nhật)

import UIKit
import Flutter
import CoreLocation 
import UserNotifications 

@UIApplicationMain
class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // BƯỚC 1: Đăng ký các plugin của Flutter
        GeneratedPluginRegistrant.register(with: self)

        // BƯỚC 2: Khởi tạo và Thiết lập Kênh Truyền thông
        guard let controller = window?.rootViewController as? FlutterViewController else {
            fatalError("rootViewController is not FlutterViewController")
        }
        UnlockMonitor.shared.setupFlutterChannel(binaryMessenger: controller.binaryMessenger)
        
        // BƯỚC 3: Bắt đầu theo dõi vị trí
        UnlockMonitor.shared.startMonitoring() 

        // BƯỚC 4: Trả về kết quả
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}