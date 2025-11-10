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
        
        // BƯỚC 1: Đăng ký các plugin của Flutter trước
        GeneratedPluginRegistrant.register(with: self)

        // BƯỚC 2: Gọi code tùy chỉnh (đã đảm bảo Flutter sẵn sàng)
        // Lưu ý: Nếu UnlockMonitor sử dụng các plugin Flutter, việc này là cần thiết
        UnlockMonitor.shared.startMonitoring() 

        // BƯỚC 3: Trả về kết quả
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}