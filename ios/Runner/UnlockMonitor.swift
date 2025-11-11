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
    
    // 🎯 CẬP NHẬT: Ngưỡng mới
    private let drivingSpeedThreshold: Double = 10.0
    private let viewingPhoneThreshold: Double = 55.0 // 55% = ĐANG XEM
    
    // 🎯 THÊM: Biến theo dõi độ ổn định trục Z
    private var zAccelerationHistory: [Double] = []
    private let zStabilityBufferSize = 50 // 5 giây (50 mẫu * 100ms)
    private var zStability: Double = 0.0
    
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
            manager.distanceFilter = 1.0 // 🎯 GIẢM: Cập nhật mỗi 1 mét (thường xuyên hơn)
            manager.activityType = .automotiveNavigation
            
            locationManager = manager
        }
        
        // Yêu cầu quyền và bắt đầu theo dõi
        locationManager?.requestAlwaysAuthorization()
        
        // KIỂM TRA QUYỀN TRƯỚC KHI BẮT ĐẦU
        let status = CLLocationManager.authorizationStatus()
        print("📍 Location Authorization Status: \(status.rawValue)")
        
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            locationManager?.startUpdatingLocation()
            print("📍 Đã bắt đầu cập nhật vị trí")
        } else {
            print("📍 Chưa có quyền truy cập vị trí")
        }
    }
    
    // MARK: - Tilt Monitoring (CẬP NHẬT THEO NGƯỠNG MỚI)
    
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
                
                // 🎯 CẬP NHẬT: Tính độ ổn định trục Z
                self.updateZStability(zValue: zAcceleration)
                
                self.handleTiltDetection(zValue: zAcceleration)
            }
        }
        
        print("Đã bắt đầu theo dõi cảm biến nghiêng")
    }
    
    // 🎯 THÊM: Hàm tính độ ổn định trục Z trong 5 giây
    private func updateZStability(zValue: Double) {
        zAccelerationHistory.append(zValue)
        if zAccelerationHistory.count > zStabilityBufferSize {
            zAccelerationHistory.removeFirst()
        }
        
        // Tính độ dao động (standard deviation)
        if zAccelerationHistory.count >= 2 {
            let mean = zAccelerationHistory.reduce(0, +) / Double(zAccelerationHistory.count)
            let variance = zAccelerationHistory.map { pow($0 - mean, 2) }.reduce(0, +) / Double(zAccelerationHistory.count)
            zStability = sqrt(variance)
        }
        
        // 🎯 DEBUG: In độ ổn định định kỳ
        if Int(Date().timeIntervalSince1970) % 10 == 0 {
            print("📊 Z Stability (5s): \(String(format: "%.3f", zStability))")
        }
    }
    
    // 🎯 CẬP NHẬT: Hàm chuyển đổi radian sang phần trăm
    private func convertTiltToPercent(_ zValue: Double) -> Double {
        let tiltAbsolute = abs(zValue)
        let tiltPercent = (tiltAbsolute / 1.0) * 100.0
        return min(max(tiltPercent, 0.0), 100.0) // Giới hạn trong 0-100%
    }
    
    // 🎯 CẬP NHẬT: Hàm xác định trạng thái tilt theo ngưỡng mới
    private func getTiltStatus(_ tiltPercent: Double) -> String {
        if tiltPercent <= 55.0 {
            return "📱 ĐANG XEM"
        } else if tiltPercent < 65.0 {
            return "⚡ TRUNG GIAN"
        } else {
            return "🔼 KHÔNG XEM"
        }
    }
    
    private func handleTiltDetection(zValue: Double) {
        // CHUYỂN ĐỔI SANG PHẦN TRĂM
        let tiltPercent = convertTiltToPercent(zValue)
        let isViewingPhone = tiltPercent <= viewingPhoneThreshold
        
        // 🎯 CẬP NHẬT: Điều kiện cảnh báo mới với độ ổn định trục Z
        let isZStable = zStability < 1.5 // Độ dao động dưới 1.5
        
        if isDeviceUnlocked && isDriving && isViewingPhone && isZStable {
            let dangerTime = Date()
            let dangerData: [String: Any] = [
                "type": "DANGER_EVENT",
                "message": "CẢNH BÁO NGUY HIỂM: Đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h và sử dụng điện thoại!",
                "tiltValue": zValue,
                "speed": currentSpeed,
                "timestamp": Int(dangerTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(dangerData)
            self.sendCriticalNotification(
                title: "CẢNH BÁO NGUY HIỂM!",
                message: "Bạn đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h và sử dụng điện thoại (Tilt: \(String(format: "%.1f", tiltPercent))%, Ổn định: \(String(format: "%.2f", zStability)))"
            )
            
            print("🚨 DANGER ALERT: Driving at \(currentSpeed) km/h, Tilt: \(tiltPercent)%, Z Stability: \(zStability)")
            
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
        
        // 🎯 DEBUG TỐC ĐỘ
        print("🚗 Speed Update: \(currentSpeed) km/h | Driving: \(isDriving)")
        
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
            print("🎯 Driving status changed: \(isDriving ? "DRIVING" : "STOPPED") at \(currentSpeed) km/h")
        } else {
            // 🎯 THÊM: Gửi cập nhật tốc độ thường xuyên ngay cả khi không thay đổi trạng thái
            let statusTime = Date()
            let statusData: [String: Any] = [
                "type": "LOCATION_UPDATE",
                "message": "Tốc độ: \(String(format: "%.1f", currentSpeed)) km/h",
                "speed": currentSpeed,
                "isDriving": isDriving,
                "timestamp": Int(statusTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(statusData)
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
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("❌ Notification permission error: \(error)")
            } else {
                print("🔔 Notification permission: \(granted ? "GRANTED" : "DENIED")")
            }
        }
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
        
        print("📱 Device UNLOCKED at \(formatTime(unlockTime)) - Driving: \(isDriving), Speed: \(currentSpeed) km/h")
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
        print("🔒 Device LOCKED at \(formatTime(lockTime)) - Speed: \(currentSpeed) km/h")
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { 
            print("❌ No location data received")
            return 
        }
        
        // Tính toán tốc độ từ location data
        let speed = location.speed >= 0 ? location.speed : 0.0
        
        // 🎯 DEBUG CHI TIẾT VỀ LOCATION
        print("""
        📍 LOCATION UPDATE:
        - Speed: \(speed)m/s (\(speed * 3.6)km/h)
        - Accuracy: \(location.horizontalAccuracy)m
        - Coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)
        - Timestamp: \(location.timestamp)
        """)
        
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
        print("❌ Location Manager Error: \(error.localizedDescription)")
    }
    
    // THÊM: XỬ LÝ THAY ĐỔI QUYỀN LOCATION
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("📍 Location Authorization Changed: \(status.rawValue)")
        
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager?.startUpdatingLocation()
            print("📍 Bắt đầu cập nhật vị trí")
        case .denied, .restricted:
            print("📍 Quyền vị trí bị từ chối")
        case .notDetermined:
            print("📍 Quyền vị trí chưa được xác định")
        @unknown default:
            break
        }
    }
    
    // MARK: - Flutter Communication
    
    private func sendEventToFlutter(_ data: [String: Any]) {
        guard let eventSink = eventSink else { 
            print("❌ EventSink is nil - Flutter chưa kết nối")
            return 
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                eventSink(jsonString)
            }
        } catch {
            print("❌ Lỗi chuyển đổi JSON: \(error)")
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
                print("❌ Lỗi gửi thông báo: \(error.localizedDescription)")
            }
        }
    }
    
    private func sendCriticalNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = UNNotificationSound.defaultCritical
        
        // SỬA LỖI: Thêm điều kiện kiểm tra version iOS
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .critical
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Lỗi gửi thông báo critical: \(error.localizedDescription)")
            } else {
                print("🔔 Đã gửi cảnh báo critical: \(message)")
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