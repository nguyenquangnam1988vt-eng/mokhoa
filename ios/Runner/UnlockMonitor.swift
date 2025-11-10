// ios/Runner/UnlockMonitor.swift

import CoreLocation
import UIKit
import UserNotifications

@objcMembers 
class UnlockMonitor: NSObject, CLLocationManagerDelegate {
    
    // Khởi tạo lười biếng (Lazy Initialization) cho CLLocationManager
    private var locationManager: CLLocationManager?
    
    // Khởi tạo Singleton để truy cập dễ dàng
    static let shared = UnlockMonitor() 

    override init() {
        super.init()
    }

    func startMonitoring() {
        // Khởi tạo CLLocationManager lần đầu khi được gọi
        if locationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            locationManager = manager
        }
        
        // --- 1. Yêu cầu Quyền ---
        // Phải đảm bảo Info.plist có khóa NSLocationAlwaysAndWhenInUseUsageDescription
        locationManager?.requestAlwaysAuthorization() 

        // --- 2. Bắt đầu Theo dõi ---
        // Dùng startMonitoringSignificantLocationChanges để tiết kiệm pin và giữ ứng dụng sống trong nền
        locationManager?.startMonitoringSignificantLocationChanges()
        
        // --- 3. Đăng ký Lắng nghe Màn hình Mở Khóa ---
        // Lắng nghe thông báo khi protected data có sẵn (thường là sau khi mở khóa)
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
        
        // Bắt đầu Background Task để đảm bảo có thời gian (tối đa 30 giây) để hoàn thành công việc
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "handleUnlockNotification") {
            // Khối code này chạy nếu task hết thời gian
            print("Background Task hết hạn.")
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }

        // --- HÀNH ĐỘNG GỬI THÔNG BÁO TẠI ĐÂY ---
        let unlockTime = Date()
        self.sendLocalNotification(message: "Thiết bị vừa được mở khóa lúc \(formatTime(unlockTime))")

        // 3. Kết thúc Background Task sau khi hoàn thành công việc (cho nó thêm 1 giây để xử lý xong thông báo)
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

    // --- CLLocationManagerDelegate Methods ---
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Hàm này bắt buộc phải có khi sử dụng startMonitoringSignificantLocationChanges 
        // Dùng để giữ cho iOS biết dịch vụ vị trí đang hoạt động
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Lỗi: \(error.localizedDescription)")
    }
}