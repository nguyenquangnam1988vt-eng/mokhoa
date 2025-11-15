import CoreLocation
import CoreMotion
import UIKit
import UserNotifications
import Flutter
import Network
import SystemConfiguration

@objcMembers
class UnlockMonitor: NSObject, CLLocationManagerDelegate, FlutterStreamHandler {
    
    private var locationManager: CLLocationManager?
    private var motionManager: CMMotionManager?
    private var networkMonitor: NWPathMonitor?
    private var eventSink: FlutterEventSink?
    private var isDeviceUnlocked = false
    private var currentSpeed: Double = 0.0
    private var isDriving = false
    private var isNetworkActive = false
    private var lastDangerAlertTime: Date?
    
    // 🎯 NETWORK DETECTION THÔNG MINH
    private var networkCongestionDetector: NetworkCongestionDetector?
    private var realNetworkMonitor: RealNetworkMonitor?
    private var isActiveBrowsing = false
    
    // 🎯 CẢI THIỆN TỐC ĐỘ - CẬP NHẬT THƯỜNG XUYÊN
    private var lastValidLocation: CLLocation?
    private var speedUpdateTimer: Timer?
    private var lastSpeedUpdateTime: Date = Date()
    
    // Ngưỡng
    private let drivingSpeedThreshold: Double = 10.0 // km/h
    private let viewingPhoneThreshold: Double = 80.0
    private let intermediateThreshold: Double = 90.0
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
        setupRealNetworkMonitoring()
        setupSpeedUpdateTimer()
    }
    
    // MARK: - FlutterStreamHandler Methods
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        print("Flutter EventChannel đã kết nối")
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        speedUpdateTimer?.invalidate()
        print("Flutter EventChannel đã ngắt kết nối")
        return nil
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        setupLocationMonitoring()
        setupTiltMonitoring()
        setupLockUnlockObservers()
        networkCongestionDetector?.startMonitoring()
        realNetworkMonitor?.startMonitoring()
        
        print("Unlock Monitor: Đã đăng ký và bắt đầu theo dõi.")
    }
    
    func stopMonitoring() {
        motionManager?.stopAccelerometerUpdates()
        locationManager?.stopUpdatingLocation()
        networkMonitor?.cancel()
        networkCongestionDetector?.stopMonitoring()
        realNetworkMonitor?.stopMonitoring()
        speedUpdateTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // 🎯 TIMER CẬP NHẬT TỐC ĐỘ THƯỜNG XUYÊN
    private func setupSpeedUpdateTimer() {
        speedUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sendSpeedUpdate()
        }
        RunLoop.current.add(speedUpdateTimer!, forMode: .common)
    }
    
    private func sendSpeedUpdate() {
        let speedData: [String: Any] = [
            "type": "SPEED_UPDATE",
            "speed": currentSpeed,
            "isDriving": isDriving,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        self.sendEventToFlutter(speedData)
    }
    
    // 🎯 REAL NETWORK MONITORING THÔNG MINH
    private func setupRealNetworkMonitoring() {
        realNetworkMonitor = RealNetworkMonitor()
        realNetworkMonitor?.onNetworkActivityDetected = { [weak self] isActive, activityType in
            guard let self = self else { return }
            
            let wasBrowsing = self.isActiveBrowsing
            self.isActiveBrowsing = isActive
            
            if wasBrowsing != isActive {
                let analysisTime = Date()
                let analysisData: [String: Any] = [
                    "type": "REAL_NETWORK_ANALYSIS",
                    "message": isActive ? "Đang có hoạt động web thực tế (\(activityType))" : "Không có hoạt động web",
                    "isActiveBrowsing": isActive,
                    "activityType": activityType,
                    "timestamp": Int(analysisTime.timeIntervalSince1970 * 1000)
                ]
                
                self.sendEventToFlutter(analysisData)
                print("🌐 Real Network Detection: \(isActive ? "ACTIVE - \(activityType)" : "INACTIVE")")
            }
        }
    }
    
    private func setupNetworkCongestionDetection() {
        networkCongestionDetector = NetworkCongestionDetector()
        networkCongestionDetector?.onNetworkStatusUpdate = { [weak self] isBrowsing in
            guard let self = self else { return }
            
            if !self.isActiveBrowsing {
                let wasBrowsing = self.isActiveBrowsing
                self.isActiveBrowsing = isBrowsing
                
                if wasBrowsing != isBrowsing {
                    let analysisTime = Date()
                    let analysisData: [String: Any] = [
                        "type": "NETWORK_ANALYSIS",
                        "message": isBrowsing ? "Đang có hoạt động lướt web" : "Không có hoạt động web",
                        "isActiveBrowsing": isBrowsing,
                        "timestamp": Int(analysisTime.timeIntervalSince1970 * 1000)
                    ]
                    
                    self.sendEventToFlutter(analysisData)
                    print("📊 Network Analysis: Browsing: \(isBrowsing)")
                }
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
    
    // MARK: - Location Monitoring - CẢI THIỆN ĐỘ CHÍNH XÁC
    
    private func setupLocationMonitoring() {
        if locationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            
            // 🎯 SỬ DỤNG GPS ĐỘ CHÍNH XÁC CAO
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = 2.0 // Giảm để cập nhật thường xuyên hơn
            manager.activityType = .automotiveNavigation
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            
            locationManager = manager
        }
        
        locationManager?.requestAlwaysAuthorization()
        
        let status = CLLocationManager.authorizationStatus()
        print("📍 Location Authorization Status: \(status.rawValue)")
        
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            locationManager?.startUpdatingLocation()
            print("📍 Đã bắt đầu cập nhật vị trí với độ chính xác cao")
        } else {
            print("📍 Chưa có quyền truy cập vị trí")
        }
    }
    
    // MARK: - CLLocationManagerDelegate - TÍNH TỐC ĐỘ CHUẨN
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // 🎯 KIỂM TRA ĐỘ CHÍNH XÁC CỦA LOCATION
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50.0 else {
            print("📍 Bỏ qua location - độ chính xác kém: \(location.horizontalAccuracy)m")
            return
        }
        
        // 🎯 TÍNH TỐC ĐỘ CHUẨN
        let calculatedSpeed = calculateAccurateSpeed(currentLocation: location)
        
        updateDrivingStatus(speed: calculatedSpeed)
        
        // 🎯 THÔNG BÁO CHO NETWORK MONITORS
        realNetworkMonitor?.notifyLocationUpdate()
        networkCongestionDetector?.setLocationUpdateCooldown()
        
        let locationData: [String: Any] = [
            "type": "LOCATION_UPDATE",
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "speed": currentSpeed,
            "accuracy": location.horizontalAccuracy,
            "isDriving": isDriving,
            "timestamp": Int(location.timestamp.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(locationData)
        lastSpeedUpdateTime = Date()
    }
    
    // 🎯 TÍNH TỐC ĐỘ CHUẨN - ƯU TIÊN HỆ THỐNG
    private func calculateAccurateSpeed(currentLocation: CLLocation) -> Double {
        // 🎯 PHƯƠNG PHÁP 1: Sử dụng tốc độ từ hệ thống (ưu tiên)
        let systemSpeed = currentLocation.speed
        
        // 🎯 KIỂM TRA TÍNH HỢP LỆ CỦA TỐC ĐỘ HỆ THỐNG
        if systemSpeed >= 0 && systemSpeed < 50.0 {
            // Tốc độ hệ thống hợp lệ, sử dụng trực tiếp
            print("🎯 Using system speed: \(systemSpeed * 3.6) km/h")
            return systemSpeed
        } else {
            // 🎯 PHƯƠNG PHÁP 2: Tính từ khoảng cách
            let calculatedSpeed = calculateSpeedFromDistance(currentLocation: currentLocation)
            print("🎯 Using calculated speed: \(calculatedSpeed * 3.6) km/h")
            return calculatedSpeed
        }
    }
    
    private func calculateSpeedFromDistance(currentLocation: CLLocation) -> Double {
        guard let lastValidLocation = lastValidLocation else {
            lastValidLocation = currentLocation
            return 0.0
        }
        
        let distance = currentLocation.distance(from: lastValidLocation) // mét
        let time = currentLocation.timestamp.timeIntervalSince(lastValidLocation.timestamp) // giây
        
        // 🎯 CHỈ TÍNH KHI CÓ DI CHUYỂN ĐÁNG KỂ VÀ THỜI GIAN HỢP LỆ
        guard time > 0 && distance >= 1.0 else {
            return 0.0
        }
        
        let speed = distance / time // m/s
        
        // 🎯 KIỂM TRA TỐC ĐỘ HỢP LỆ (0-50 m/s ≈ 0-180 km/h)
        guard speed >= 0 && speed < 50.0 else {
            return 0.0
        }
        
        self.lastValidLocation = currentLocation
        return speed
    }
    
    // 🎯 CẬP NHẬT TRẠNG THÁI LÁI XE - THƯỜNG XUYÊN
    private func updateDrivingStatus(speed: Double) {
        let previousSpeed = currentSpeed
        currentSpeed = speed * 3.6 // Chuyển sang km/h
        
        let wasDriving = isDriving
        isDriving = currentSpeed >= drivingSpeedThreshold
        
        // 🎯 CẬP NHẬT THƯỜNG XUYÊN KHI ĐANG DI CHUYỂN
        if isDriving || abs(currentSpeed - previousSpeed) > 2.0 {
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
            print("🎯 Driving status: \(isDriving ? "DRIVING" : "STOPPED") at \(currentSpeed) km/h")
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
    
    private func handleTiltDetection(zValue: Double) {
        let tiltPercent = convertTiltToPercent(zValue)
        let tiltStatus = getTiltStatus(tiltPercent)
        let isViewingPhone = tiltPercent <= viewingPhoneThreshold
        let isZStable = zStability < 1.5
        
        // 🎯 LOGIC CẢNH BÁO ĐÚNG: CHỈ KHI ĐANG LÁI XE + XEM ĐIỆN THOẠI + LƯỚT WEB
        let shouldTriggerDangerAlert = isDeviceUnlocked && 
                                     isDriving && 
                                     isViewingPhone && 
                                     isZStable &&
                                     isActiveBrowsing &&
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
                "isActiveBrowsing": isActiveBrowsing,
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
        
        let tiltTime = Date()
        let tiltData: [String: Any] = [
            "type": "TILT_EVENT",
            "message": "Thiết bị: \(tiltStatus)",
            "tiltValue": zValue,
            "tiltPercent": tiltPercent,
            "speed": currentSpeed,
            "isNetworkActive": isNetworkActive,
            "isActiveBrowsing": isActiveBrowsing,
            "zStability": zStability,
            "timestamp": Int(tiltTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(tiltData)
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

// 🎯 REAL NETWORK MONITOR VỚI NGƯỠNG THÔNG MINH
class RealNetworkMonitor {
    private var timer: Timer?
    private var lastNetworkStats: NetworkInterfaceStats?
    private var activitySamples: [Bool] = []
    private let sampleSize = 5
    private var consecutiveActiveCount = 0
    
    var onNetworkActivityDetected: ((Bool, String) -> Void)?
    
    func startMonitoring() {
        stopMonitoring()
        
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkRealNetworkActivity()
        }
        
        if let timer = timer {
            RunLoop.current.add(timer, forMode: .common)
        }
        
        print("🌐 Real Network Monitor started")
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func notifyLocationUpdate() {
        // Không cần cooldown
    }
    
    private func checkRealNetworkActivity() {
        let currentStats = getCurrentNetworkStats()
        let isActive = detectRealNetworkActivity(currentStats: currentStats)
        let activityType = determineActivityType(currentStats: currentStats)
        
        // 🎯 LOGIC XÁC NHẬN THÔNG MINH
        if isActive {
            consecutiveActiveCount += 1
        } else {
            consecutiveActiveCount = max(0, consecutiveActiveCount - 1)
        }
        
        // 🎯 CHỈ XÁC NHẬN KHI CÓ 3 LẦN ACTIVE LIÊN TIẾP
        let confirmedActive = consecutiveActiveCount >= 3
        
        DispatchQueue.main.async {
            self.onNetworkActivityDetected?(confirmedActive, activityType)
        }
        
        lastNetworkStats = currentStats
    }
    
    private func getCurrentNetworkStats() -> NetworkInterfaceStats {
        var stats = NetworkInterfaceStats()
        
        if let interfaceStats = getNetworkInterfaceStatistics() {
            stats.bytesReceived = interfaceStats.bytesReceived
            stats.bytesSent = interfaceStats.bytesSent
            stats.packetsReceived = interfaceStats.packetsReceived
            stats.hasActiveInterface = true
        }
        
        stats.activeConnections = getActiveURLSessionTasks()
        
        return stats
    }
    
    private func detectRealNetworkActivity(currentStats: NetworkInterfaceStats) -> Bool {
        guard let lastStats = lastNetworkStats else { return false }
        
        let receivedDiff = currentStats.bytesReceived - lastStats.bytesReceived
        let sentDiff = currentStats.bytesSent - lastStats.bytesSent
        let packetsDiff = currentStats.packetsReceived - lastStats.packetsReceived
        
        print("🌐 Traffic Diff - Received: \(receivedDiff), Sent: \(sentDiff), Packets: \(packetsDiff)")
        
        // 🎯 NGƯỠNG THÔNG MINH - PHÙ HỢP WEB NHƯNG TRÁNH APP NỀN
        let hasModerateDownload = receivedDiff > 80000    // 80KB - đủ cho web có ảnh
        let hasModerateUpload = sentDiff > 30000          // 30KB - đủ cho form submit
        let hasPacketActivity = packetsDiff > 20          // 20 packets - traffic đáng kể
        let hasActiveConnections = currentStats.activeConnections > 3
        
        // 🎯 KẾT HỢP NHIỀU YẾU TỐ ĐỂ TRÁNH BÁO ẢO
        let isActive = (hasModerateDownload && hasPacketActivity) || 
                      (hasModerateUpload && hasPacketActivity) ||
                      (hasActiveConnections && hasModerateDownload) ||
                      (receivedDiff > 50000 && packetsDiff > 25) // Web nhẹ nhưng nhiều request
        
        print("🌐 Network Activity Result: \(isActive) - Consecutive: \(consecutiveActiveCount)")
        return isActive
    }
    
    private func determineActivityType(currentStats: NetworkInterfaceStats) -> String {
        guard let lastStats = lastNetworkStats else { return "Không có dữ liệu" }
        
        let receivedDiff = currentStats.bytesReceived - lastStats.bytesReceived
        let sentDiff = currentStats.bytesSent - lastStats.bytesSent
        
        if receivedDiff > 150000 {
            return "Tải dữ liệu lớn (video/file)"
        } else if receivedDiff > 80000 {
            return "Đang xem web có ảnh"
        } else if receivedDiff > 50000 {
            return "Đang lướt web"
        } else if sentDiff > 30000 {
            return "Đang upload/gửi dữ liệu"
        } else {
            return "Hoạt động mạng nhẹ"
        }
    }
    
    private func getNetworkInterfaceStatistics() -> (bytesReceived: Int, bytesSent: Int, packetsReceived: Int)? {
        var ifaddrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrs) == 0 else { return nil }
        
        defer { freeifaddrs(ifaddrs) }
        
        var totalReceived: Int = 0
        var totalSent: Int = 0
        var totalPackets: Int = 0
        
        var pointer = ifaddrs
        while pointer != nil {
            defer { pointer = pointer?.pointee.ifa_next }
            
            guard let interface = pointer?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            
            if name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                if let data = interface.ifa_data {
                    let stats = data.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
                    totalReceived += Int(stats.ifi_ibytes)
                    totalSent += Int(stats.ifi_obytes)
                    totalPackets += Int(stats.ifi_ipackets)
                }
            }
        }
        
        return (totalReceived, totalSent, totalPackets)
    }
    
    private func getActiveURLSessionTasks() -> Int {
        return 0
    }
}

struct NetworkInterfaceStats {
    var bytesReceived: Int = 0
    var bytesSent: Int = 0
    var packetsReceived: Int = 0
    var hasActiveInterface: Bool = false
    var activeConnections: Int = 0
}

// 🎯 NETWORK CONGESTION DETECTOR
class NetworkCongestionDetector {
    private var pingTimer: Timer?
    
    var onNetworkStatusUpdate: ((Bool) -> Void)?
    
    func startMonitoring() {
        stopMonitoring()
        
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performNetworkAnalysis()
        }
    }
    
    func stopMonitoring() {
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    func setLocationUpdateCooldown() {
        // Không cần cooldown
    }
    
    private func performNetworkAnalysis() {
        // Đơn giản hóa, chủ yếu dựa vào RealNetworkMonitor
        DispatchQueue.main.async {
            self.onNetworkStatusUpdate?(false)
        }
    }
}