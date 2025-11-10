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
    
    // 🎯 NGƯỠNG MỚI: SỬ DỤNG PHẦN TRĂM THAY VÌ RADIAN
    private let drivingSpeedThreshold: Double = 10.0
    private let viewingPhoneThreshold: Double = 60.0 // 60% = ĐANG XEM
    
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
    
    // MARK: - Location Monitoring
    
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
    
    // MARK: - Tilt Monitoring (SỬA THEO NGƯỠNG PHẦN TRĂM)
    
    private func setupTiltMonitoring() {
        if motionManager == nil {
            motionManager = CMMotionManager()
        }
        
        guard let motionManager = motionManager else { return }
        
        guard motionManager.isAccelerometerAvailable else {
            print("Accelerometer không khả dụng")
            return
        }
        
        motionManager.accelerometerUpdateInterval = 0.1 // 100ms để tính trung bình mượt hơn
        
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
    
    // 🎯 HÀM MỚI: CHUYỂN ĐỔI RADIAN SANG PHẦN TRĂM
    private func convertTiltToPercent(_ zValue: Double) -> Double {
        // Giả sử: z = 1.0 khi điện thoại nằm ngang (90 độ)
        // z = 0.0 khi điện thoại thẳng đứng (0 độ)
        let tiltAbsolute = abs(zValue)
        let tiltPercent = (tiltAbsolute / 1.0) * 100.0
        return min(max(tiltPercent, 0.0), 100.0) // Giới hạn trong 0-100%
    }
    
    // 🎯 HÀM MỚI: XÁC ĐỊNH TRẠNG THÁI TILT
    private func getTiltStatus(_ tiltPercent: Double) -> String {
        if tiltPercent <= 60.0 {
            return "📱 ĐANG XEM (\(String(format: "%.1f", tiltPercent))%)"
        } else if tiltPercent < 70.0 {
            return "⚡ TRUNG GIAN (\(String(format: "%.1f", tiltPercent))%)"
        } else {
            return "🔼 KHÔNG XEM (\(String(format: "%.1f", tiltPercent))%)"
        }
    }
    
    private func handleTiltDetection(zValue: Double) {
        // 🎯 CHUYỂN ĐỔI SANG PHẦN TRĂM
        let tiltPercent = convertTiltToPercent(zValue)
        let isViewingPhone = tiltPercent <= viewingPhoneThreshold
        
        // 🎯 ĐIỀU KIỆN CẢNH BÁO MỚI: MỞ KHÓA + ĐANG LÁI XE + ĐANG XEM ĐIỆN THOẠI
        if isDeviceUnlocked && isDriving && isViewingPhone {
            let dangerTime = Date()
            let dangerData: [String: Any] = [
                "type": "DANGER_EVENT",
                "message": "CẢNH BÁO NGUY HIỂM: Đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h và sử dụng điện thoại!",
                "tiltValue": zValue, // Vẫn gửi radian để Flutter tính %
                "speed": currentSpeed,
                "timestamp": Int(dangerTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(dangerData)
            self.sendCriticalNotification(
                title: "CẢNH BÁO NGUY HIỂM!",
                message: "Bạn đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h và sử dụng điện thoại (Tilt: \(String(format: "%.1f", tiltPercent))%)"
            )
            
            print("🚨 DANGER ALERT: Driving at \(currentSpeed) km/h, Tilt: \(tiltPercent)%")
            
        } else {
            // Gửi sự kiện tilt thông thường
            let tiltStatus = getTiltStatus(tiltPercent)
            let tiltTime = Date()
            let tiltData: [String: Any] = [
                "type": "TILT_EVENT",
                "message": "Thiết bị: \(tiltStatus)",
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
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Tính toán tốc độ từ location data
        let speed = location.speed >= 0 ? location.speed : 0.0
        updateDrivingStatus(speed: speed)
        
        // Gửi dữ liệu vị trí về Flutter
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