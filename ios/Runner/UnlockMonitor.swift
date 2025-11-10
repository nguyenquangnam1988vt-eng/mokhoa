import CoreLocation
import CoreMotion
import UIKit
import UserNotifications
import Flutter

@objcMembers
class UnlockMonitor: NSObject, CLLocationManagerDelegate, FlutterStreamHandler {
    
    private var locationManager: CLLocationManager?
    private var motionManager: CMMotionManager?
    private var eventSink: FlutterEventSink?
    private var isDeviceUnlocked = false
    private var lastLocation: CLLocation?
    private var lastLocationTimestamp: Date?
    private var currentSpeed: Double = 0.0 // km/h
    private var isDriving = false
    
    // Ngưỡng tốc độ để xác định đang lái xe (km/h)
    private let drivingSpeedThreshold: Double = 10.0
    // Ngưỡng nghiêng để xác định đang cầm điện thoại
    private let tiltThreshold: Double = 0.3
    
    // Khởi tạo Singleton
    static let shared = UnlockMonitor()
    
    override init() {
        super.init()
    }
    
    // MARK: - FlutterStreamHandler Methods
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        print("Flutter EventChannel đã kết nối")
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        print("Flutter EventChannel đã ngắt kết nối")
        return nil
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        setupLocationMonitoring()
        setupTiltMonitoring()
        setupLockUnlockObservers()
        
        print("Unlock Monitor: Đã đăng ký và bắt đầu theo dõi.")
    }
    
    func stopMonitoring() {
        motionManager?.stopAccelerometerUpdates()
        locationManager?.stopUpdatingLocation()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Location Monitoring (CẬP NHẬT ĐỂ TÍNH TỐC ĐỘ)
    
    private func setupLocationMonitoring() {
        if locationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            
            // Cấu hình cho Background Location với độ chính xác cao
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = 5.0 // Cập nhật mỗi 5 mét
            manager.activityType = .automotiveNavigation
            
            locationManager = manager
        }
        
        // Yêu cầu quyền và bắt đầu theo dõi
        locationManager?.requestAlwaysAuthorization()
        locationManager?.startUpdatingLocation()
    }
    
    // MARK: - Tilt Monitoring (KẾT HỢP TỐC ĐỘ)
    
    private func setupTiltMonitoring() {
        if motionManager == nil {
            motionManager = CMMotionManager()
        }
        
        guard let motionManager = motionManager else { return }
        
        guard motionManager.isAccelerometerAvailable else {
            print("Accelerometer không khả dụng")
            return
        }
        
        motionManager.accelerometerUpdateInterval = 1.0
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("Lỗi accelerometer: \(error.localizedDescription)")
                return
            }
            
            // Xử lý tilt khi device đã mở khóa
            if self.isDeviceUnlocked, let accelerometerData = data {
                let zAcceleration = accelerometerData.acceleration.z
                self.handleTiltDetection(zValue: zAcceleration)
            }
        }
        
        print("Đã bắt đầu theo dõi cảm biến nghiêng")
    }
    
    private func handleTiltDetection(zValue: Double) {
        // Chỉ cảnh báo khi device đã mở khóa VÀ đang di chuyển với tốc độ cao
        guard isDeviceUnlocked else { return }
        
        let isTilting = abs(zValue) > tiltThreshold
        
        if isTilting && isDriving {
            // PHÁT HIỆN NGUY HIỂM: Đang lái xe + nghiêng điện thoại + mở khóa
            let dangerTime = Date()
            let dangerData: [String: Any] = [
                "type": "DANGER_EVENT",
                "message": "CẢNH BÁO NGUY HIỂM: Đang lái xe ở tốc độ \(String(format: "%.1f", currentSpeed)) km/h và sử dụng điện thoại!",
                "tiltValue": zValue,
                "speed": currentSpeed,
                "timestamp": Int(dangerTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(dangerData)
            self.sendCriticalNotification(
                title: "CẢNH BÁO NGUY HIỂM!",
                message: "Bạn đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h và sử dụng điện thoại"
            )
            
        } else if isTilting {
            // Chỉ nghiêng thông thường (không nguy hiểm)
            let tiltTime = Date()
            let tiltData: [String: Any] = [
                "type": "TILT_EVENT",
                "message": "Thiết bị đang nghiêng: \(String(format: "%.3f", zValue)) rad",
                "tiltValue": zValue,
                "speed": currentSpeed,
                "timestamp": Int(tiltTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(tiltData)
        }
    }
    
    // MARK: - Speed Calculation & Driving Detection
    
    private func updateDrivingStatus(speed: Double) {
        currentSpeed = speed * 3.6 // Chuyển m/s sang km/h
        
        let wasDriving = isDriving
        isDriving = currentSpeed >= drivingSpeedThreshold
        
        // Thông báo thay đổi trạng thái lái xe
        if isDriving != wasDriving {
            let statusTime = Date()
            let statusData: [String: Any] = [
                "type": "DRIVING_STATUS",
                "message": isDriving ? 
                    "Đang lái xe ở tốc độ \(String(format: "%.1f", currentSpeed)) km/h" :
                    "Đã dừng/đang đứng yên",
                "speed": currentSpeed,
                "isDriving": isDriving,
                "timestamp": Int(statusTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(statusData)
            print("Driving status changed: \(isDriving ? "DRIVING" : "STOPPED") at \(currentSpeed) km/h")
        }
    }
    
    // MARK: - Lock/Unlock Observers
    
    private func setupLockUnlockObservers() {
        NotificationCenter.default.addObserver(self,
            selector: #selector(deviceDidUnlock),
            name: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil)
        
        NotificationCenter.default.addObserver(self,
            selector: #selector(deviceDidLock),
            name: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil)
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    @objc func deviceDidUnlock() {
        isDeviceUnlocked = true
        
        let unlockTime = Date()
        let unlockData: [String: Any] = [
            "type": "LOCK_EVENT",
            "message": "Thiết bị vừa được Mở Khóa",
            "location": formatTime(unlockTime),
            "speed": currentSpeed,
            "isDriving": isDriving,
            "timestamp": Int(unlockTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(unlockData)
        
        // CẢNH BÁO NGUY HIỂM Nếu mở khóa khi đang lái xe
        if isDriving {
            self.sendCriticalNotification(
                title: "CẢNH BÁO!",
                message: "Bạn vừa mở khóa điện thoại khi đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h"
            )
        }
        
        print("Device unlocked at \(formatTime(unlockTime)) - Driving: \(isDriving)")
    }
    
    @objc func deviceDidLock() {
        isDeviceUnlocked = false
        
        let lockTime = Date()
        let lockData: [String: Any] = [
            "type": "LOCK_EVENT", 
            "message": "Thiết bị vừa bị Khóa",
            "location": formatTime(lockTime),
            "speed": currentSpeed,
            "isDriving": isDriving,
            "timestamp": Int(lockTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(lockData)
        print("Device locked at \(formatTime(lockTime))")
    }
    
    // MARK: - CLLocationManagerDelegate (CẬP NHẬT TÍNH TỐC ĐỘ)
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Tính toán tốc độ từ location data
        let speed = location.speed >= 0 ? location.speed : 0.0
        updateDrivingStatus(speed: speed)
        
        // Gửi dữ liệu vị trí về Flutter (nếu cần)
        let locationData: [String: Any] = [
            "type": "LOCATION_UPDATE",
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "speed": currentSpeed,
            "isDriving": isDriving,
            "timestamp": Int(location.timestamp.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(locationData)
        
        lastLocation = location
        lastLocationTimestamp = Date()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager Lỗi: \(error.localizedDescription)")
    }
    
    // MARK: - Flutter Communication
    
    private func sendEventToFlutter(_ data: [String: Any]) {
        guard let eventSink = eventSink else { return }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                eventSink(jsonString)
            }
        } catch {
            print("Lỗi chuyển đổi JSON: \(error)")
        }
    }
    
    // MARK: - Notifications
    
    private func sendLocalNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Trạng thái Màn hình"
        content.body = message
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Lỗi gửi thông báo: \(error.localizedDescription)")
            }
        }
    }
    
    private func sendCriticalNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = UNNotificationSound.defaultCritical
        content.interruptionLevel = .critical
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Lỗi gửi thông báo critical: \(error.localizedDescription)")
            } else {
                print("Đã gửi cảnh báo critical: \(message)")
            }
        }
    }
    
    // MARK: - Utility Methods
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}