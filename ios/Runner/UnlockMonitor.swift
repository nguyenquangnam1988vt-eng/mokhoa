// ios/Runner/UnlockMonitor.swift

import CoreLocation
import UIKit
import UserNotifications

@objcMembers 
class UnlockMonitor: NSObject, CLLocationManagerDelegate {
    
    // Khởi tạo lười biếng (Lazy Initialization)
    private var locationManager: CLLocationManager?
    
    // Khởi tạo Singleton
    static let shared = UnlockMonitor() 

    override init() {
        super.init()
        // Các thiết lập ban đầu (có thể để trống, hoặc chỉ gọi super.init)
    }

    func startMonitoring() {
        // Khởi tạo CLLocationManager trong startMonitoring() thay vì init() 
        // để đảm bảo nó chỉ được setup khi cần thiết
        if locationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            locationManager = manager
        }
        
        // --- 1. Yêu cầu Quyền ---
        locationManager?.requestAlwaysAuthorization() 

        // --- 2. Bắt đầu Theo dõi ---
        locationManager?.startMonitoringSignificantLocationChanges()
        
        // --- 3. Đăng ký Lắng nghe Màn hình Mở Khóa ---
        // Lưu ý: Đăng ký này phải dùng NotificationCenter của hệ thống
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
        // Bắt đầu Background Task để đảm bảo có 30 giây để hoàn thành công việc
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "handleUnlockNotification") {
            // Xử lý khi hết thời gian
            print("Background Task hết hạn.")
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }

        // --- HÀNH ĐỘNG GỬI THÔNG BÁO TẠI ĐÂY ---
        let unlockTime = Date()
        self.sendLocalNotification(message: "Thiết bị vừa được mở khóa lúc \(formatTime(unlockTime))")

        // Kết thúc Background Task sau khi hoàn thành
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { 
             UIApplication.shared.endBackgroundTask(backgroundTaskID)
             print("Background Task kết thúc.")
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

    // CLLocationManagerDelegate: Giữ ứng dụng sống
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Giữ cho iOS biết dịch vụ đang hoạt động
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Lỗi: \(error.localizedDescription)")
    }
}