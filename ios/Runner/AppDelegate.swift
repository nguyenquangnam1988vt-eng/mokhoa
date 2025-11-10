// ios/Runner/AppDelegate.swift

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

        // BƯỚC 2: Khởi tạo và Thiết lập Kênh Truyền thông cho UnlockMonitor
        // Lấy FlutterViewController để truy cập BinaryMessenger
        if let controller = window?.rootViewController as? FlutterViewController {
            UnlockMonitor.shared.setupFlutterChannel(binaryMessenger: controller.binaryMessenger)
        }
        
        // BƯỚC 3: Bắt đầu theo dõi vị trí và sự kiện mở khóa
        UnlockMonitor.shared.startMonitoring() 

        // BƯỚC 4: Trả về kết quả
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}