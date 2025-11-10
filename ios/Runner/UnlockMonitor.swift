// ios/Runner/UnlockMonitor.swift

import CoreLocation
import UIKit
import UserNotifications

@objcMembers // Cần thiết để gọi từ Objective-C/Flutter
class UnlockMonitor: NSObject, CLLocationManagerDelegate {
    
    let locationManager = CLLocationManager()
    
    // Khởi tạo Singleton để dễ dàng truy cập
    static let shared = UnlockMonitor() 

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false 
    }

    func startMonitoring() {
        // Yêu cầu quyền truy cập vị trí mọi lúc
        locationManager.requestAlwaysAuthorization() 

        // Bắt đầu theo dõi vị trí để giữ ứng dụng sống (workaround)
        locationManager.startMonitoringSignificantLocationChanges()
        
        // Đăng ký lắng nghe thông báo Màn hình Mở Khóa
        NotificationCenter.default.addObserver(self,
            selector: #selector(deviceDidUnlock),
            name: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil)
        
        // Yêu cầu quyền thông báo
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        print("Unlock Monitor: Đã đăng ký và bắt đầu theo dõi.")
    }

    // Hàm được gọi khi Màn hình được Mở khóa
    @objc func deviceDidUnlock() {
        var taskId: UIBackgroundTaskIdentifier?
        taskId = UIApplication.shared.beginBackgroundTask {
            if let task = taskId {
                UIApplication.shared.endBackgroundTask(task)
            }
        }

        // --- HÀNH ĐỘNG GỬI THÔNG BÁO TẠI ĐÂY ---
        let unlockTime = Date()
        self.sendLocalNotification(message: "Thiết bị vừa được mở khóa lúc \(formatTime(unlockTime))")

        // Kết thúc Background Task
        if let task = taskId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { 
                UIApplication.shared.endBackgroundTask(task)
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