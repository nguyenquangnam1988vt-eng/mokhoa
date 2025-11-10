// ios/Runner/UnlockMonitor.swift

import CoreLocation
import UIKit
import UserNotifications
import Flutter

@objcMembers 
class UnlockMonitor: NSObject, CLLocationManagerDelegate {
    
    private var locationManager: CLLocationManager?
    private var flutterChannel: FlutterMethodChannel? // Kênh truyền thông
    
    // Khởi tạo Singleton
    static let shared = UnlockMonitor() 

    override init() {
        super.init()
    }

    // Hàm cần được gọi từ AppDelegate để thiết lập kênh Flutter
    func setupFlutterChannel(binaryMessenger: FlutterBinaryMessenger) {
        flutterChannel = FlutterMethodChannel(
            name: "com.example.background_location", 
            binaryMessenger: binaryMessenger
        )
        print("Unlock Monitor: Đã thiết lập Flutter Channel.")
    }
    
    func startMonitoring() {
        if locationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            
            // Cấu hình Bắt buộc cho Nền và Độ chính xác cao
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone // Nhận mọi cập nhật
            manager.activityType = .automotiveNavigation // Hoạt động lái xe/theo dõi liên tục

            locationManager = manager
        }
        
        // --- 1. Yêu cầu Quyền ---
        locationManager?.requestAlwaysAuthorization() 

        // --- 2. Bắt đầu Theo dõi Liên tục (Tiêu hao pin cao!) ---
        locationManager?.startUpdatingLocation() 
        
        // --- 3. Đăng ký Lắng nghe Màn hình Mở Khóa ---
        NotificationCenter.default.addObserver(self,
            selector: #selector(deviceDidUnlock),
            name: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil)
        
        // --- 4. Yêu cầu Quyền Thông báo ---
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        print("Unlock Monitor: Đã đăng ký và bắt đầu theo dõi.")
    }

    // Hàm được gọi khi Màn hình được Mở khóa
    @objc func deviceDidUnlock() {
        
        // KHẮC PHỤC LỖI BIÊN DỊCH: Khai báo biến trước khi gán
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        
        // Bắt đầu Background Task (có thể chạy tối đa khoảng 30 giây)
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "handleUnlockNotification") {
            // Task hết hạn (sau 30s)
            print("Background Task hết hạn.")
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }

        // --- GỌI CODE FLUTTER NỀN HOẶC GỬI THÔNG BÁO TẠI ĐÂY ---
        let unlockTime = Date()
        self.sendDataToFlutter(method: "deviceUnlocked", data: ["time": formatTime(unlockTime)])
        self.sendLocalNotification(message: "Thiết bị vừa được mở khóa lúc \(formatTime(unlockTime))")

        // Kết thúc Background Task sau 1 giây
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { 
             UIApplication.shared.endBackgroundTask(backgroundTaskID)
             print("Background Task kết thúc.")
        }
    }
    
    // Hàm gửi dữ liệu về Flutter (ĐÃ SỬA LỖI CASTING)
    private func sendDataToFlutter(method: String, data: [String: Any]) {
        flutterChannel?.invokeMethod(method, arguments: data) { result in
            
            // Xử lý kết quả trả về từ Flutter/Dart
            if let error = result as? FlutterError {
                print("Lỗi gọi Flutter: \(error.message ?? "")")
            } else if result is NSNull || result == nil {
                // Kiểm tra nếu phương thức chưa được triển khai (result thường là nil hoặc NSNull)
                print("Phương thức Flutter chưa được triển khai hoặc không có kết quả trả về.")
            } else {
                print("Đã gọi thành công Flutter method: \(method). Kết quả: \(result ?? "Không có")")
            }
        }
    }
    
    // Hàm tạo Thông báo Cục bộ
    private func sendLocalNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Trạng thái Màn hình"
        content.body = message
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Lỗi gửi thông báo: \(error.localizedDescription)")
            } else {
                print("Đã gửi thông báo cục bộ thành công.")
            }
        }
    }
    
    // Hàm Tiện ích Định dạng Thời gian
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    // --- CLLocationManagerDelegate Methods ---
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Truyền dữ liệu vị trí liên tục về Flutter
        let data: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "timestamp": location.timestamp.timeIntervalSince1970 * 1000 // Chuyển sang mili giây
        ]
        self.sendDataToFlutter(method: "newLocationUpdate", data: data)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Lỗi: \(error.localizedDescription)")
    }
}