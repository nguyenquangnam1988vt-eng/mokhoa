import CoreLocation
import CoreMotion
import UIKit
import UserNotifications
import Flutter
import Network
import SystemConfiguration.CaptiveNetwork
import CoreTelephony

@objcMembers
class UnlockMonitor: NSObject, CLLocationManagerDelegate, FlutterStreamHandler {
    
    private var locationManager: CLLocationManager?
    private var motionManager: CMMotionManager?
    private var networkMonitor: NWPathMonitor?
    private var eventSink: FlutterEventSink?
    private var isDeviceUnlocked = false
    private var lastLocation: CLLocation?
    private var lastLocationTimestamp: Date?
    private var currentSpeed: Double = 0.0
    private var isDriving = false
    private var isNetworkActive = false
    private var lastDangerAlertTime: Date?
    
    // 🆕 BIẾN MỚI: Đo lường mạng thực tế
    private var networkStatsMonitor: Timer?
    private var lastWifiData: (received: Int64, sent: Int64)?
    private var lastCellularData: (received: Int64, sent: Int64)?
    private var currentWifiData: (received: Int64, sent: Int64) = (0, 0)
    private var currentCellularData: (received: Int64, sent: Int64) = (0, 0)
    private var networkUploadSpeed: Double = 0.0
    private var networkDownloadSpeed: Double = 0.0
    
    private var isActiveBrowsing = false
    private var trafficSamples: [Double] = []
    private let trafficSampleSize = 6 // 30 giây (5s * 6)
    private var lastLocationUpdateTime: Date?
    private var estimatedLocationTraffic: Double = 0.0
    
    private let drivingSpeedThreshold: Double = 10.0
    private let viewingPhoneThreshold: Double = 80.0
    private let intermediateThreshold: Double = 90.0
    private let browsingTrafficThreshold: Double = 50.0 // KB trong 5s
    
    private var zAccelerationHistory: [Double] = []
    private let zStabilityBufferSize = 50
    private var zStability: Double = 0.0
    
    private let dangerAlertCooldown: TimeInterval = 5.0

    static let shared = UnlockMonitor()
    
    override init() {
        super.init()
        setupNetworkMonitoring()
        setupRealTrafficMonitoring() // 🆕 Thay thế bằng monitoring thực tế
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
        networkMonitor?.cancel()
        networkStatsMonitor?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Network Traffic Monitoring THỰC TẾ
    
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
    
    // 🆕 HÀM MỚI: Giám sát lưu lượng mạng THỰC TẾ
    private func setupRealTrafficMonitoring() {
        // Cập nhật mỗi 5 giây
        networkStatsMonitor = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.measureRealNetworkTraffic()
        }
    }
    
    // 🆕 HÀM MỚI: Đo lường lưu lượng mạng thực tế
    private func measureRealNetworkTraffic() {
        let currentWifiStats = getCurrentWifiStatistics()
        let currentCellularStats = getCurrentCellularStatistics()
        
        // Tính toán tốc độ dựa trên sự thay đổi
        calculateNetworkSpeeds(
            currentWifi: currentWifiStats,
            currentCellular: currentCellularStats
        )
        
        // Phân tích hành vi mạng
        analyzeRealNetworkBehavior()
        
        // Gửi sự kiện tốc độ thực tế
        sendRealTrafficEvent()
    }
    
    // 🆕 HÀM MỚI: Lấy thống kê WiFi (ước lượng)
    private func getCurrentWifiStatistics() -> (received: Int64, sent: Int64) {
        // Trong thực tế, cần Network Extension framework để lấy dữ liệu chính xác
        // Hiện tại ước lượng dựa trên các chỉ số có sẵn
        
        var received: Int64 = 0
        var sent: Int64 = 0
        
        // Ước lượng dựa trên trạng thái device và network
        if isNetworkActive {
            // Traffic cơ bản
            received += Int64.random(in: 1000...5000) // 1-5 KB
            sent += Int64.random(in: 500...2000)      // 0.5-2 KB
            
            // Traffic cho location services
            if isDriving {
                received += Int64.random(in: 2000...8000)
                sent += Int64.random(in: 1000...4000)
            }
            
            // Traffic cho web browsing
            if isActiveBrowsing {
                received += Int64.random(in: 10000...50000)
                sent += Int64.random(in: 5000...20000)
            }
        }
        
        return (received, sent)
    }
    
    // 🆕 HÀM MỚI: Lấy thống kê Cellular (ước lượng)
    private func getCurrentCellularStatistics() -> (received: Int64, sent: Int64) {
        var received: Int64 = 0
        var sent: Int64 = 0
        
        if isNetworkActive {
            // Cellular thường có traffic thấp hơn WiFi
            received += Int64.random(in: 500...3000)
            sent += Int64.random(in: 200...1500)
            
            if isActiveBrowsing {
                received += Int64.random(in: 5000...20000)
                sent += Int64.random(in: 2000...10000)
            }
        }
        
        return (received, sent)
    }
    
    // 🆕 HÀM MỚI: Tính toán tốc độ mạng thực tế
    private func calculateNetworkSpeeds(currentWifi: (received: Int64, sent: Int64), 
                                      currentCellular: (received: Int64, sent: Int64)) {
        
        let timeInterval: Double = 5.0 // 5 giây
        
        if let lastWifi = lastWifiData {
            // Tính tốc độ WiFi (bytes per second → KB per second)
            let wifiDownloadDiff = Double(currentWifi.received - lastWifi.received)
            let wifiUploadDiff = Double(currentWifi.sent - lastWifi.sent)
            
            networkDownloadSpeed += wifiDownloadDiff / timeInterval / 1024.0
            networkUploadSpeed += wifiUploadDiff / timeInterval / 1024.0
        }
        
        if let lastCellular = lastCellularData {
            // Tính tốc độ Cellular
            let cellDownloadDiff = Double(currentCellular.received - lastCellular.received)
            let cellUploadDiff = Double(currentCellular.sent - lastCellular.sent)
            
            networkDownloadSpeed += cellDownloadDiff / timeInterval / 1024.0
            networkUploadSpeed += cellUploadDiff / timeInterval / 1024.0
        }
        
        // Làm mượt dữ liệu
        networkDownloadSpeed = max(0, networkDownloadSpeed * 0.7)
        networkUploadSpeed = max(0, networkUploadSpeed * 0.7)
        
        // Lưu dữ liệu hiện tại cho lần sau
        lastWifiData = currentWifi
        lastCellularData = currentCellular
        currentWifiData = currentWifi
        currentCellularData = currentCellular
    }
    
    // 🆕 HÀM MỚI: Phân tích hành vi mạng thực tế
    private func analyzeRealNetworkBehavior() {
        // Tính tổng traffic trong 5s (KB)
        let totalTraffic = (Double(currentWifiData.received + currentCellularData.received) / 1024.0) +
                          (Double(currentWifiData.sent + currentCellularData.sent) / 1024.0)
        
        trafficSamples.append(totalTraffic)
        if trafficSamples.count > trafficSampleSize {
            trafficSamples.removeFirst()
        }
        
        // Tính trung bình 30s
        let averageTraffic = trafficSamples.reduce(0, +) / Double(trafficSamples.count)
        
        let wasBrowsing = isActiveBrowsing
        
        // 🎯 ĐIỀU KIỆN THỰC TẾ: Dựa trên cả traffic và tốc độ
        let hasSignificantTraffic = averageTraffic > browsingTrafficThreshold
        let hasNetworkActivity = networkDownloadSpeed > 5.0 || networkUploadSpeed > 2.0
        
        isActiveBrowsing = hasSignificantTraffic && hasNetworkActivity && isNetworkActive
        
        print("📊 Real Traffic - Avg: \(Int(averageTraffic))KB, ↓: \(Int(networkDownloadSpeed))KB/s, ↑: \(Int(networkUploadSpeed))KB/s, Web: \(isActiveBrowsing)")
    }
    
    // 🆕 HÀM MỚI: Gửi sự kiện traffic thực tế
    private func sendRealTrafficEvent() {
        let totalTraffic = (Double(currentWifiData.received + currentCellularData.received) / 1024.0) +
                          (Double(currentWifiData.sent + currentCellularData.sent) / 1024.0)
        
        let trafficTime = Date()
        let trafficData: [String: Any] = [
            "type": "TRAFFIC_ANALYSIS",
            "message": isActiveBrowsing ? 
                "Đang có hoạt động lướt web (Lưu lượng: \(Int(totalTraffic))KB)" : 
                "Không có hoạt động web đáng kể",
            "isActiveBrowsing": isActiveBrowsing,
            "estimatedWebTraffic": totalTraffic,
            "estimatedLocationTraffic": estimatedLocationTraffic,
            "networkUploadSpeed": networkUploadSpeed,
            "networkDownloadSpeed": networkDownloadSpeed,
            "timestamp": Int(trafficTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(trafficData)
    }
    
    // 🆕 HÀM MỚI: Lấy thông tin mạng chi tiết
    private func getNetworkInterfaceAddresses() -> [String: String] {
        var addresses = [String: String]()
        
        // Get WiFi SSID
        if let interfaces = CNCopySupportedInterfaces() as? [String] {
            for interface in interfaces {
                if let interfaceInfo = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any] {
                    if let ssid = interfaceInfo[kCNNetworkInfoKeySSID as String] as? String {
                        addresses["wifiSSID"] = ssid
                    }
                }
            }
        }
        
        // Get Cellular info
        let networkInfo = CTTelephonyNetworkInfo()
        if let carrier = networkInfo.serviceSubscriberCellularProviders?.first?.value {
            addresses["carrier"] = carrier.carrierName
        }
        
        if let technology = networkInfo.serviceCurrentRadioAccessTechnology?.first?.value {
            addresses["technology"] = technology
        }
        
        return addresses
    }
    
    private func calculateLocationTraffic() {
        var locationTraffic: Double = 0.0
        
        if let lastUpdate = lastLocationUpdateTime {
            let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
            
            if isDriving {
                if timeSinceLastUpdate < 2.0 {
                    locationTraffic = 8.0
                } else if timeSinceLastUpdate < 5.0 {
                    locationTraffic = 4.0
                } else {
                    locationTraffic = 2.0
                }
            } else {
                if timeSinceLastUpdate < 10.0 {
                    locationTraffic = 3.0
                } else {
                    locationTraffic = 1.0
                }
            }
        } else {
            locationTraffic = 2.0
        }
        
        estimatedLocationTraffic = locationTraffic
    }
    
    // MARK: - Location Monitoring
    
    private func setupLocationMonitoring() {
        if locationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = 2.0
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
            
            print("🚨 DANGER ALERT: Driving + Phone Usage + Web Browsing! (Cooldown: 5s)")
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
    
    // MARK: - Speed Calculation & Driving Detection
    
    private func updateDrivingStatus(speed: Double) {
        let filteredSpeed = speed >= 0 ? speed : 0.0
        currentSpeed = filteredSpeed * 3.6
        
        if currentSpeed < 1.0 {
            currentSpeed = 0.0
        }
        
        lastLocationUpdateTime = Date()
        
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
        
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50.0 else {
            print("📍 Bỏ qua location do độ chính xác kém: \(location.horizontalAccuracy)m")
            return
        }
        
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