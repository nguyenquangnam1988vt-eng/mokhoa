import CoreLocation
import CoreMotion
import UIKit
import UserNotifications
import Flutter
import Network

@objcMembers
class UnlockMonitor: NSObject, CLLocationManagerDelegate, FlutterStreamHandler {
    
    private var locationManager: CLLocationManager?
    private var motionManager: CMMotionManager?
    private var networkMonitor: NWPathMonitor?
    private var eventSink: FlutterEventSink?
    private var isDeviceUnlocked = false
    private var lastLocation: CLLocation?
    private var currentSpeed: Double = 0.0
    private var isDriving = false
    private var isNetworkActive = false
    private var lastDangerAlertTime: Date?
    
    // 🎯 NETWORK CONGESTION DETECTOR - CHỈ GIỮ LẠI isActiveBrowsing
    private var networkCongestionDetector: NetworkCongestionDetector?
    private var isActiveBrowsing = false
    
    // 🎯 CẬP NHẬT NGUYỠNG TILT MỚI
    private let drivingSpeedThreshold: Double = 10.0
    private let viewingPhoneThreshold: Double = 80.0    // 🆕 <80% = ĐANG XEM
    private let intermediateThreshold: Double = 90.0     // 🆕 80-90% = TRUNG GIAN
    private let dangerAlertCooldown: TimeInterval = 5.0

    // Biến theo dõi độ ổn định trục Z
    private var zAccelerationHistory: [Double] = []
    private let zStabilityBufferSize = 50
    private var zStability: Double = 0.0
    
    static let shared = UnlockMonitor()
    
    override init() {
        super.init()
        setupNetworkMonitoring()
        setupNetworkCongestionDetection()
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
        networkCongestionDetector?.startMonitoring()
        
        print("Unlock Monitor: Đã đăng ký và bắt đầu theo dõi.")
    }
    
    func stopMonitoring() {
        motionManager?.stopAccelerometerUpdates()
        locationManager?.stopUpdatingLocation()
        networkMonitor?.cancel()
        networkCongestionDetector?.stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
    // 🎯 NETWORK CONGESTION DETECTION - ĐƠN GIẢN HÓA
    private func setupNetworkCongestionDetection() {
        networkCongestionDetector = NetworkCongestionDetector()
        networkCongestionDetector?.onNetworkStatusUpdate = { [weak self] isBrowsing in
            guard let self = self else { return }
            
            let wasBrowsing = self.isActiveBrowsing
            self.isActiveBrowsing = isBrowsing
            
            // 🎯 CHỈ gửi sự kiện khi có thay đổi trạng thái
            if wasBrowsing != isBrowsing {
                let analysisTime = Date()
                let analysisData: [String: Any] = [
                    "type": "NETWORK_ANALYSIS",
                    "message": isBrowsing ? "Đang có hoạt động lướt web" : "Không có hoạt động web",
                    "isActiveBrowsing": isBrowsing, // 🎯 CHỈ GIỮ LẠI 1 TRƯỜNG
                    "timestamp": Int(analysisTime.timeIntervalSince1970 * 1000)
                ]
                
                self.sendEventToFlutter(analysisData)
                print("📊 Network Analysis: Browsing: \(isBrowsing)")
            }
        }
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            let wasNetworkActive = self.isNetworkActive
            self.isNetworkActive = (path.status == .satisfied)
            
            if wasNetworkActive != self.isNetworkActive {
                let networkTime = Date()
                let networkData: [String: Any] = [
                    "type": "NETWORK_STATUS",
                    "message": self.isNetworkActive ? "Đã kết nối Internet" : "Mất kết nối Internet",
                    "isNetworkActive": self.isNetworkActive,
                    "timestamp": Int(networkTime.timeIntervalSince1970 * 1000)
                ]
                
                self.sendEventToFlutter(networkData)
                print("🌐 Network Status: \(self.isNetworkActive ? "ACTIVE" : "INACTIVE")")
            }
        }
        
        networkMonitor?.start(queue: queue)
    }
    
    // MARK: - Location Monitoring
    
    private func setupLocationMonitoring() {
        if locationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            
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
    
    // MARK: - Tilt Monitoring
    
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
    
    // 🎯 CẬP NHẬT: Hàm xác định trạng thái tilt theo ngưỡng mới
    private func getTiltStatus(_ tiltPercent: Double) -> String {
        if tiltPercent <= viewingPhoneThreshold {
            return "📱 ĐANG XEM"
        } else if tiltPercent < intermediateThreshold {
            return "⚡ TRUNG GIAN"
        } else {
            return "🔼 KHÔNG XEM"
        }
    }
    
    private func canSendDangerAlert() -> Bool {
        guard let lastAlert = lastDangerAlertTime else { return true }
        return Date().timeIntervalSince(lastAlert) >= dangerAlertCooldown
    }
    
    // 🎯 CẬP NHẬT: Điều kiện cảnh báo với tilt ngưỡng mới
    private func handleTiltDetection(zValue: Double) {
        let tiltPercent = convertTiltToPercent(zValue)
        let tiltStatus = getTiltStatus(tiltPercent)
        let isViewingPhone = tiltPercent <= viewingPhoneThreshold // 🆕 <80%
        let isZStable = zStability < 1.5
        
        // 🎯 ĐIỀU KIỆN CHÍNH XÁC: Dùng network detection thực tế
        let shouldTriggerDangerAlert = isDeviceUnlocked && 
                                     isDriving && 
                                     isViewingPhone && 
                                     isZStable &&
                                     isActiveBrowsing && // 🎯 Phát hiện lướt web thực tế
                                     canSendDangerAlert()
        
        if shouldTriggerDangerAlert {
            let dangerTime = Date()
            lastDangerAlertTime = dangerTime
            
            let dangerData: [String: Any] = [
                "type": "DANGER_EVENT",
                "message": "CẢNH BÁO NGUY HIỂM: Đang lái xe và LƯỚT WEB!",
                "tiltValue": zValue,
                "tiltPercent": tiltPercent,
                "speed": currentSpeed,
                "isNetworkActive": isNetworkActive,
                "isActiveBrowsing": isActiveBrowsing, // 🎯 CHỈ GIỮ LẠI
                "zStability": zStability,
                "timestamp": Int(dangerTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(dangerData)
            self.sendCriticalNotification(
                title: "CẢNH BÁO NGUY HIỂM!",
                message: "Đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h, sử dụng điện thoại và LƯỚT WEB!"
            )
            
            print("🚨 DANGER ALERT: Driving + Phone Usage + Web Browsing! (Tilt: \(tiltPercent)%)")
        }
        
        // Gửi sự kiện tilt thông thường
        let tiltTime = Date()
        let tiltData: [String: Any] = [
            "type": "TILT_EVENT",
            "message": "Thiết bị: \(tiltStatus)",
            "tiltValue": zValue,
            "tiltPercent": tiltPercent,
            "speed": currentSpeed,
            "isNetworkActive": isNetworkActive,
            "isActiveBrowsing": isActiveBrowsing, // 🎯 CHỈ GIỮ LẠI
            "zStability": zStability,
            "timestamp": Int(tiltTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(tiltData)
    }
    
    // MARK: - Speed Calculation & Driving Detection
    
    private func updateDrivingStatus(speed: Double) {
        currentSpeed = speed * 3.6
        
        let wasDriving = isDriving
        isDriving = currentSpeed >= drivingSpeedThreshold
        
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
        }
        
        let updateTime = Date()
        let updateData: [String: Any] = [
            "type": "LOCATION_UPDATE",
            "message": "Tốc độ: \(String(format: "%.1f", currentSpeed)) km/h",
            "speed": currentSpeed,
            "isDriving": isDriving,
            "timestamp": Int(updateTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(updateData)
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
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location Manager Error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("📍 Location Authorization Changed: \(status.rawValue)")
        
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager?.startUpdatingLocation()
        default:
            break
        }
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

// 🎯 NETWORK CONGESTION DETECTOR CLASS - ĐƠN GIẢN HÓA
class NetworkCongestionDetector {
    private var pingTimer: Timer?
    private var latencySamples: [Double] = []
    private var packetLossSamples: [Bool] = []
    private var requestCount = 0
    private var lastRequestTime: Date?
    
    private let sampleSize = 10
    private let pingTargets = ["8.8.8.8", "1.1.1.1", "208.67.222.222"]
    
    // 🎯 CHỈ TRẢ VỀ isActiveBrowsing
    var onNetworkStatusUpdate: ((Bool) -> Void)?
    
    func startMonitoring() {
        stopMonitoring()
        
        pingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.performNetworkAnalysis()
        }
    }
    
    func stopMonitoring() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    private func performNetworkAnalysis() {
        measureNetworkCongestion { [weak self] latency, packetLoss in
            guard let self = self else { return }
            
            self.latencySamples.append(latency)
            self.packetLossSamples.append(packetLoss)
            
            if self.latencySamples.count > self.sampleSize {
                self.latencySamples.removeFirst()
            }
            if self.packetLossSamples.count > self.sampleSize {
                self.packetLossSamples.removeFirst()
            }
            
            // 🎯 CHỈ XÁC ĐỊNH isActiveBrowsing
            let isBrowsing = self.detectWebBrowsingActivity()
            
            self.onNetworkStatusUpdate?(isBrowsing)
        }
    }
    
    private func measureNetworkCongestion(completion: @escaping (Double, Bool) -> Void) {
        let startTime = Date()
        let target = pingTargets.randomElement() ?? "8.8.8.8"
        
        guard let url = URL(string: "https://\(target)") else {
            completion(999, true)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        request.httpMethod = "HEAD"
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            let latency = Date().timeIntervalSince(startTime) * 1000
            let success = (error == nil) && (response != nil)
            
            DispatchQueue.main.async {
                completion(latency, !success)
            }
        }
        
        task.resume()
        incrementRequestCount()
    }
    
    private func incrementRequestCount() {
        requestCount += 1
        lastRequestTime = Date()
    }
    
    // 🎯 CHỈ PHÁT HIỆN WEB BROWSING - DỰA TRÊN 3 CHỈ SỐ THỰC TẾ
    private func detectWebBrowsingActivity() -> Bool {
        let requestRate = calculateRequestRate()
        let hasBurstPattern = detectBurstPattern()
        let hasHighLatency = detectHighLatency()
        
        // 🎯 Web browsing: nhiều request + burst pattern + độ trễ cao
        return requestRate > 3.0 && hasBurstPattern && hasHighLatency
    }
    
    private func calculateRequestRate() -> Double {
        guard let lastRequest = lastRequestTime else { return 0.0 }
        let timeWindow = Date().timeIntervalSince(lastRequest)
        
        if timeWindow < 30.0 {
            return Double(requestCount) / 30.0
        }
        return 0.0
    }
    
    private func detectBurstPattern() -> Bool {
        if let lastRequest = lastRequestTime, Date().timeIntervalSince(lastRequest) > 30.0 {
            requestCount = 0
        }
        
        return requestCount > 8
    }
    
    private func detectHighLatency() -> Bool {
        guard !latencySamples.isEmpty else { return false }
        let avgLatency = latencySamples.reduce(0, +) / Double(latencySamples.count)
        return avgLatency > 100.0 // 🎯 Độ trễ > 100ms
    }
}