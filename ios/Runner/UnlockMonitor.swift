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
    private var lastLocation: CLLocation?
    private var currentSpeed: Double = 0.0
    private var isDriving = false
    private var isNetworkActive = false
    private var lastDangerAlertTime: Date?
    
    // 🎯 NETWORK DETECTION
    private var networkCongestionDetector: NetworkCongestionDetector?
    private var realNetworkMonitor: RealNetworkMonitor?
    private var isActiveBrowsing = false
    
    // 🎯 CẢI THIỆN TỐC ĐỘ - THÊM BIẾN LỌC VÀ TÍNH TOÁN
    private var speedHistory: [Double] = []
    private let speedHistorySize = 5
    private var lastValidLocation: CLLocation?
    private var locationHistory: [CLLocation] = []
    private let maxLocationHistory = 10
    
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
        realNetworkMonitor?.startMonitoring()
        
        print("Unlock Monitor: Đã đăng ký và bắt đầu theo dõi.")
    }
    
    func stopMonitoring() {
        motionManager?.stopAccelerometerUpdates()
        locationManager?.stopUpdatingLocation()
        networkMonitor?.cancel()
        networkCongestionDetector?.stopMonitoring()
        realNetworkMonitor?.stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
    // 🎯 REAL NETWORK MONITORING - SỬA COOLDOWN
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
            
            // 🎯 CHỈ CẬP NHẬT NẾU RealNetworkMonitor CHƯA PHÁT HIỆN
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
            manager.distanceFilter = 5.0 // 🎯 Chỉ update khi di chuyển 5m
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
    
    // MARK: - CLLocationManagerDelegate - TÍNH TỐC ĐỘ CHÍNH XÁC
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // 🎯 KIỂM TRA ĐỘ CHÍNH XÁC CỦA LOCATION
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 65.0 else {
            print("📍 Bỏ qua location - độ chính xác kém: \(location.horizontalAccuracy)m")
            return
        }
        
        // 🎯 THÊM VÀO LỊCH SỬ VỊ TRÍ
        locationHistory.append(location)
        if locationHistory.count > maxLocationHistory {
            locationHistory.removeFirst()
        }
        
        // 🎯 TÍNH TỐC ĐỘ CHÍNH XÁC DỰA TRÊN KHOẢNG CÁCH VÀ THỜI GIAN
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
        lastLocation = location
    }
    
    // 🎯 TÍNH TỐC ĐỘ CHÍNH XÁC DỰA TRÊN KHOẢNG CÁCH VÀ THỜI GIAN
    private func calculateAccurateSpeed(currentLocation: CLLocation) -> Double {
        var speed = currentLocation.speed
        
        // 🎯 PHƯƠNG PHÁP 1: TÍNH TỐC ĐỘ TỪ KHOẢNG CÁCH GIỮA CÁC VỊ TRÍ
        if locationHistory.count >= 2 {
            let recentLocations = Array(locationHistory.suffix(3)) // Lấy 3 vị trí gần nhất
            
            var totalDistance: Double = 0
            var totalTime: Double = 0
            
            for i in 1..<recentLocations.count {
                let prevLocation = recentLocations[i-1]
                let currLocation = recentLocations[i]
                
                let distance = currLocation.distance(from: prevLocation) // mét
                let time = currLocation.timestamp.timeIntervalSince(prevLocation.timestamp) // giây
                
                if time > 0 && distance >= 0 {
                    totalDistance += distance
                    totalTime += time
                }
            }
            
            if totalTime > 0 && totalDistance > 0 {
                let calculatedSpeed = totalDistance / totalTime // m/s
                
                // 🎯 KIỂM TRA TỐC ĐỘ HỢP LỆ (0-50 m/s ≈ 0-180 km/h)
                if calculatedSpeed >= 0 && calculatedSpeed < 50 {
                    speed = calculatedSpeed
                    print("🎯 Calculated speed from distance: \(calculatedSpeed * 3.6) km/h (distance: \(totalDistance)m, time: \(totalTime)s)")
                }
            }
        }
        
        // 🎯 PHƯƠNG PHÁP 2: LỌC TỐC ĐỘ BẤT THƯỜNG
        let filteredSpeed = filterAbnormalSpeed(speed)
        
        return filteredSpeed
    }
    
    // 🎯 LỌC TỐC ĐỘ BẤT THƯỜNG
    private func filterAbnormalSpeed(_ speed: Double) -> Double {
        // 🎯 CHỈ CHẤP NHẬN TỐC ĐỘ HỢP LỆ (0-50 m/s ≈ 0-180 km/h)
        guard speed >= 0 && speed < 50.0 else {
            print("📍 Bỏ qua tốc độ không hợp lệ: \(speed * 3.6) km/h")
            return 0.0
        }
        
        // 🎯 THÊM VÀO LỊCH SỬ TỐC ĐỘ
        speedHistory.append(speed)
        if speedHistory.count > speedHistorySize {
            speedHistory.removeFirst()
        }
        
        // 🎯 TÍNH TRUNG BÌNH ĐỂ LÀM MỊN
        let averageSpeed = speedHistory.reduce(0, +) / Double(speedHistory.count)
        
        // 🎯 KIỂM TRA SỰ THAY ĐỔI ĐỘT NGỘT
        if speedHistory.count >= 2 {
            let lastSpeed = speedHistory[speedHistory.count - 2]
            let speedChange = abs(averageSpeed - lastSpeed)
            
            // 🎯 NẾU THAY ĐỔI QUÁ LỚN (>10 m/s ≈ 36 km/h), GIỮ TỐC ĐỘ CŨ
            if speedChange > 10.0 {
                print("📍 Tốc độ thay đổi đột ngột: \(lastSpeed * 3.6) -> \(averageSpeed * 3.6) km/h")
                return lastSpeed
            }
        }
        
        return averageSpeed
    }
    
    // 🎯 CẬP NHẬT TRẠNG THÁI LÁI XE
    private func updateDrivingStatus(speed: Double) {
        let previousSpeed = currentSpeed
        currentSpeed = speed * 3.6 // Chuyển sang km/h
        
        let wasDriving = isDriving
        isDriving = currentSpeed >= drivingSpeedThreshold
        
        // 🎯 CHỈ GỬI SỰ KIỆN KHI CÓ THAY ĐỔI ĐÁNG KỂ
        if isDriving != wasDriving || abs(currentSpeed - previousSpeed) > 5.0 {
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
    
    // MARK: - Tilt Monitoring (giữ nguyên)
    
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
    
    // MARK: - Lock/Unlock Observers (giữ nguyên)
    
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

// 🎯 REAL NETWORK MONITOR VỚI NGƯỠNG CAO 500KB
class RealNetworkMonitor {
    private var timer: Timer?
    private var lastNetworkStats: NetworkInterfaceStats?
    private var activitySamples: [Bool] = []
    private let sampleSize = 5
    private var locationUpdateCooldown: Date?
    
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
        locationUpdateCooldown = Date()
    }
    
    private func checkRealNetworkActivity() {
        // 🎯 VẪN TIẾP TỤC KIỂM TRA NGAY CẢ KHI CÓ LOCATION UPDATE
        if let cooldown = locationUpdateCooldown, Date().timeIntervalSince(cooldown) < 2.0 {
            print("📍 Real Network Monitor: Location update detected, but continuing network check...")
            // VẪN TIẾP TỤC, KHÔNG RETURN
        }
        
        let currentStats = getCurrentNetworkStats()
        let isActive = detectRealNetworkActivity(currentStats: currentStats)
        let activityType = determineActivityType(currentStats: currentStats)
        
        activitySamples.append(isActive)
        if activitySamples.count > sampleSize {
            activitySamples.removeFirst()
        }
        
        // 🎯 NGƯỠNG XÁC NHẬN CAO HƠN
        let activeCount = activitySamples.filter { $0 }.count
        let confirmedActive = activeCount >= 3
        
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
        
        // 🎯 TĂNG NGƯỠNG RẤT CAO - CHỈ PHÁT HIỆN KHI THỰC SỰ LƯỚT WEB MẠNH
        let hasSignificantDownload = receivedDiff > 500000  // ⬅️ 500KB download
        let hasSignificantUpload = sentDiff > 200000        // ⬅️ 200KB upload
        let hasPacketActivity = packetsDiff > 50
        let hasActiveConnections = currentStats.activeConnections > 3
        
        // 🎯 CHỈ TÍNH LÀ ACTIVITY KHI CÓ TRAFFIC RẤT LỚN
        let isActive = (hasSignificantDownload && hasPacketActivity) || 
                      (hasSignificantUpload && hasPacketActivity) ||
                      (hasActiveConnections && hasSignificantDownload)
        
        print("🌐 Network Activity Result: \(isActive) - Threshold: 500KB")
        return isActive
    }
    
    private func determineActivityType(currentStats: NetworkInterfaceStats) -> String {
        guard let lastStats = lastNetworkStats else { return "Không có dữ liệu" }
        
        let receivedDiff = currentStats.bytesReceived - lastStats.bytesReceived
        let sentDiff = currentStats.bytesSent - lastStats.bytesSent
        
        if receivedDiff > sentDiff * 2 {
            return "Đang tải dữ liệu (xem web, video)"
        } else if sentDiff > receivedDiff {
            return "Đang gửi dữ liệu (upload, chat)"
        } else if currentStats.activeConnections > 2 {
            return "Nhiều kết nối (lướt web, app)"
        } else {
            return "Hoạt động mạng"
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

// 🎯 NETWORK CONGESTION DETECTOR VỚI NGƯỠNG CAO
class NetworkCongestionDetector {
    private var pingTimer: Timer?
    private var latencySamples: [Double] = []
    private var packetLossSamples: [Bool] = []
    private var requestCount = 0
    private var lastRequestTime: Date?
    private var locationUpdateCooldown: Date?
    
    private let sampleSize = 10
    private let pingTargets = ["8.8.8.8", "1.1.1.1", "208.67.222.222"]
    
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
    
    func setLocationUpdateCooldown() {
        locationUpdateCooldown = Date()
    }
    
    private func performNetworkAnalysis() {
        // 🎯 VẪN TIẾP TỤC PHÂN TÍCH KHI CÓ LOCATION UPDATE
        if let cooldown = locationUpdateCooldown, Date().timeIntervalSince(cooldown) < 3.0 {
            print("📍 Network Congestion Detector: Location cooldown active, but continuing analysis...")
            // VẪN TIẾP TỤC, KHÔNG RETURN
        }
        
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
            
            let isBrowsing = self.detectWebBrowsingActivity()
            
            DispatchQueue.main.async {
                self.onNetworkStatusUpdate?(isBrowsing)
            }
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
    
    private func detectWebBrowsingActivity() -> Bool {
        // 🎯 KHI CÓ LOCATION UPDATE, COI NHƯ KHÔNG CÓ WEB BROWSING
        if let cooldown = locationUpdateCooldown, Date().timeIntervalSince(cooldown) < 3.0 {
            return false
        }
        
        let requestRate = calculateRequestRate()
        let hasBurstPattern = detectBurstPattern()
        
        // 🎯 TĂNG NGƯỠNG RẤT CAO
        let isBrowsing = (requestRate > 8.0 && hasBurstPattern) // ⬅️ Tăng từ 5.0 lên 8.0
        
        print("📊 Web Browsing Detection - Rate: \(requestRate), Burst: \(hasBurstPattern), Result: \(isBrowsing)")
        
        return isBrowsing
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
        
        return requestCount > 15  // ⬅️ Tăng từ 8 lên 15
    }
    
    private func detectHighLatency() -> Bool {
        guard !latencySamples.isEmpty else { return false }
        let avgLatency = latencySamples.reduce(0, +) / Double(latencySamples.count)
        return avgLatency > 100.0
    }
    
    private func detectContinuousNetworkActivity() -> Bool {
        guard let lastRequest = lastRequestTime else { return false }
        let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
        return timeSinceLastRequest < 15.0 && requestCount > 5
    }
    
    private func isWebTrafficPattern() -> Bool {
        return requestCount > 3
    }
}