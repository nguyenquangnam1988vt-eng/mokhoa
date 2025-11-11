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
    
    // 🆕 MỚI: Biến cảm biến tiệm cận
    private var isProximityDetected = false
    private var proximityMonitoringEnabled = false
    
    // Khởi tạo Singleton
    static let shared = UnlockMonitor()
    
    override init() {
        super.init()
        // 🆕 MỚI: Thiết lập cảm biến tiệm cận
        setupProximitySensor()
    }
    
    // MARK: - FlutterStreamHandler Methods
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        print("Flutter EventChannel đã kết nối")
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        // 🆕 MỚI: Tắt cảm biến tiệm cận khi ngắt kết nối
        disableProximitySensor()
        print("Flutter EventChannel đã ngắt kết nối")
        return nil
    }
    
    // MARK: - Proximity Sensor Methods (MỚI)
    
    private func setupProximitySensor() {
        // Kiểm tra thiết bị có cảm biến tiệm cận không
        let device = UIDevice.current
        if device.isProximityMonitoringEnabled {
            print("📱 Cảm biến tiệm cận đã được bật")
        } else {
            device.isProximityMonitoringEnabled = true
            if device.isProximityMonitoringEnabled {
                print("📱 Đã kích hoạt cảm biến tiệm cận")
                proximityMonitoringEnabled = true
            } else {
                print("❌ Thiết bị không hỗ trợ cảm biến tiệm cận")
                return
            }
        }
        
        // Đăng ký theo dõi thay đổi cảm biến tiệm cận
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(proximityStateChanged),
            name: UIDevice.proximityStateDidChangeNotification,
            object: nil
        )
    }
    
    private func disableProximitySensor() {
        UIDevice.current.isProximityMonitoringEnabled = false
        NotificationCenter.default.removeObserver(self, name: UIDevice.proximityStateDidChangeNotification, object: nil)
        print("📱 Đã tắt cảm biến tiệm cận")
    }
    
    @objc private func proximityStateChanged() {
        let proximityState = UIDevice.current.proximityState
        isProximityDetected = proximityState
        
        let proximityTime = Date()
        let proximityData: [String: Any] = [
            "type": "PROXIMITY_EVENT",
            "message": proximityState ? 
                "📱 Cảm biến tiệm cận: CÓ VẬT TIẾP CẬN (đang cầm điện thoại)" :
                "📱 Cảm biến tiệm cận: KHÔNG có vật tiếp cận",
            "isProximityDetected": proximityState,
            "timestamp": Int(proximityTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(proximityData)
        print("📱 Proximity Sensor: \(proximityState ? "DETECTED" : "CLEAR")")
        
        // 🆕 KIỂM TRA CẢNH BÁO KHI CÓ THAY ĐỔI CẢM BIẾN TIỆM CẬN
        checkDangerCondition()
    }
    
    // 🆕 MỚI: Hàm kiểm tra điều kiện cảnh báo
    private func checkDangerCondition() {
        guard isDeviceUnlocked && isDriving else { return }
        
        let tiltPercent = calculateCurrentTiltPercent()
        let isViewingPhone = tiltPercent <= viewingPhoneThreshold
        let isZStable = zStability < 1.5
        
        // 🎯 ĐIỀU KIỆN CẢNH BÁO MỚI: THÊM CẢM BIẾN TIỆM CẬN
        if isProximityDetected && isViewingPhone && isZStable {
            triggerDangerAlert(tiltPercent: tiltPercent)
        }
    }
    
    // 🆕 MỚI: Hàm tính tilt phần trăm hiện tại
    private func calculateCurrentTiltPercent() -> Double {
        // Giả sử đang có dữ liệu tilt mới nhất từ accelerometer
        // Trong thực tế, bạn cần lấy từ biến lưu trữ tilt hiện tại
        return 0.0 // Placeholder - sẽ được cập nhật từ accelerometer data
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        setupLocationMonitoring()
        setupTiltMonitoring()
        setupLockUnlockObservers()
        
        // 🆕 MỚI: Bật cảm biến tiệm cận khi bắt đầu monitoring
        UIDevice.current.isProximityMonitoringEnabled = true
        
        print("Unlock Monitor: Đã đăng ký và bắt đầu theo dõi.")
    }
    
    func stopMonitoring() {
        motionManager?.stopAccelerometerUpdates()
        locationManager?.stopUpdatingLocation()
        disableProximitySensor()
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
            manager.distanceFilter = 1.0
            manager.activityType = .automotiveNavigation
            
            locationManager = manager
        }
        
        locationManager?.requestAlwaysAuthorization()
        
        let status = CLLocationManager.authorizationStatus()
        print("📍 Location Authorization Status: \(status.rawValue)")
        
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            locationManager?.startUpdatingLocation()
            print("📍 Đã bắt đầu cập nhật vị trí")
        } else {
            print("📍 Chưa có quyền truy cập vị trí")
        }
    }
    
    // MARK: - Tilt Monitoring (CẬP NHẬT)
    
    private func setupTiltMonitoring() {
        if motionManager == nil {
            motionManager = CMMotionManager()
        }
        
        guard let motionManager = motionManager else { return }
        
        guard motionManager.isAccelerometerAvailable else {
            print("Accelerometer không khả dụng")
            return
        }
        
        motionManager.accelerometerUpdateInterval = 0.1
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("Lỗi accelerometer: \(error.localizedDescription)")
                return
            }
            
            if self.isDeviceUnlocked, let accelerometerData = data {
                let zAcceleration = accelerometerData.acceleration.z
                
                self.updateZStability(zValue: zAcceleration)
                self.handleTiltDetection(zValue: zAcceleration)
            }
        }
        
        print("Đã bắt đầu theo dõi cảm biến nghiêng")
    }
    
    private func updateZStability(zValue: Double) {
        zAccelerationHistory.append(zValue)
        if zAccelerationHistory.count > zStabilityBufferSize {
            zAccelerationHistory.removeFirst()
        }
        
        if zAccelerationHistory.count >= 2 {
            let mean = zAccelerationHistory.reduce(0, +) / Double(zAccelerationHistory.count)
            let variance = zAccelerationHistory.map { pow($0 - mean, 2) }.reduce(0, +) / Double(zAccelerationHistory.count)
            zStability = sqrt(variance)
        }
    }
    
    private func convertTiltToPercent(_ zValue: Double) -> Double {
        let tiltAbsolute = abs(zValue)
        let tiltPercent = (tiltAbsolute / 1.0) * 100.0
        return min(max(tiltPercent, 0.0), 100.0)
    }
    
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
        let tiltPercent = convertTiltToPercent(zValue)
        let isViewingPhone = tiltPercent <= viewingPhoneThreshold
        let isZStable = zStability < 1.5
        
        // 🎯 CẬP NHẬT: Điều kiện cảnh báo mới với CẢM BIẾN TIỆM CẬN
        if isDeviceUnlocked && isDriving && isViewingPhone && isZStable && isProximityDetected {
            triggerDangerAlert(tiltPercent: tiltPercent)
        } else {
            // Gửi sự kiện tilt thông thường
            let tiltStatus = getTiltStatus(tiltPercent)
            let tiltTime = Date()
            let tiltData: [String: Any] = [
                "type": "TILT_EVENT",
                "message": "Thiết bị: \(tiltStatus)",
                "tiltValue": zValue,
                "speed": currentSpeed,
                "isProximityDetected": isProximityDetected, // 🆕 THÊM trạng thái cảm biến tiệm cận
                "timestamp": Int(tiltTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(tiltData)
        }
    }
    
    // 🆕 MỚI: Hàm kích hoạt cảnh báo nguy hiểm
    private func triggerDangerAlert(tiltPercent: Double) {
        let dangerTime = Date()
        let dangerData: [String: Any] = [
            "type": "DANGER_EVENT",
            "message": "CẢNH BÁO NGUY HIỂM: Đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h và sử dụng điện thoại!",
            "tiltValue": tiltPercent,
            "speed": currentSpeed,
            "isProximityDetected": isProximityDetected,
            "timestamp": Int(dangerTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(dangerData)
        self.sendCriticalNotification(
            title: "CẢNH BÁO NGUY HIỂM!",
            message: "Bạn đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h và sử dụng điện thoại (Tilt: \(String(format: "%.1f", tiltPercent))%, Đang cầm: \(isProximityDetected ? "CÓ" : "KHÔNG"))"
        )
        
        print("🚨 DANGER ALERT: Driving at \(currentSpeed) km/h, Tilt: \(tiltPercent)%, Proximity: \(isProximityDetected), Z Stability: \(zStability)")
    }
    
    // MARK: - Speed Calculation & Driving Detection
    
    private func updateDrivingStatus(speed: Double) {
        currentSpeed = speed * 3.6
        
        let wasDriving = isDriving
        isDriving = currentSpeed >= drivingSpeedThreshold
        
        print("🚗 Speed Update: \(currentSpeed) km/h | Driving: \(isDriving)")
        
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
        
        // 🆕 MỚI: Kiểm tra cảnh báo khi thay đổi trạng thái lái xe
        if isDriving {
            checkDangerCondition()
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
            "isProximityDetected": isProximityDetected, // 🆕 THÊM cảm biến tiệm cận
            "timestamp": Int(unlockTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(unlockData)
        
        if isDriving {
            self.sendCriticalNotification(
                title: "CẢNH BÁO!",
                message: "Bạn vừa mở khóa điện thoại khi đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h"
            )
        }
        
        print("📱 Device UNLOCKED at \(formatTime(unlockTime)) - Driving: \(isDriving), Speed: \(currentSpeed) km/h, Proximity: \(isProximityDetected)")
        
        // 🆕 MỚI: Kiểm tra cảnh báo khi mở khóa
        checkDangerCondition()
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
        guard let location = locations.last else { return }
        
        let speed = location.speed >= 0 ? location.speed : 0.0
        
        updateDrivingStatus(speed: speed)
        
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
    
    private func sendCriticalNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = UNNotificationSound.defaultCritical
        
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