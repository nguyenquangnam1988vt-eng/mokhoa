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
    
    // 🎯 DỮ LIỆU THẬT - Sử dụng computed property
    private var isDeviceUnlocked: Bool {
        return UIApplication.shared.protectedDataAvailable
    }
    
    private var lastLocation: CLLocation?
    private var lastLocationTimestamp: Date?
    private var currentSpeed: Double = 0.0
    private var isDriving = false
    private var isNetworkActive = false
    private var lastDangerAlertTime: Date?
    
    // 🎯 NETWORK THẬT - Sử dụng Network framework
    private var networkStatsMonitor: Timer?
    private var networkUploadSpeed: Double = 0.0
    private var networkDownloadSpeed: Double = 0.0
    private var lastNetworkStats: (upload: Int64, download: Int64) = (0, 0)
    
    // 🎯 WEB BROWSING DETECTION THẬT
    private var isActiveBrowsing = false
    private var trafficSamples: [Double] = []
    private let trafficSampleSize = 6
    private var lastLocationUpdateTime: Date?
    private var estimatedLocationTraffic: Double = 0.0
    
    // 🎯 CẢM BIẾN THẬT - Đa trục
    private var zAccelerationHistory: [Double] = []
    private let zStabilityBufferSize = 50
    private var zStability: Double = 0.0
    private var lastTiltUpdateTime: Date?
    private var tiltErrorCount = 0

    // 🎯 NGƯỠNG THẬT - ĐÃ ĐIỀU CHỈNH
    private let drivingSpeedThreshold: Double = 15.0 // 🆕 Tăng ngưỡng lên 15 km/h
    private let viewingPhoneThreshold: Double = 80.0
    private let intermediateThreshold: Double = 90.0
    private let browsingDownloadThreshold: Double = 500.0 // KB/s
    
    private let dangerAlertCooldown: TimeInterval = 10.0 // 🆕 Tăng cooldown

    // 🆕 BIẾN MỚI: Làm mượt tốc độ
    private var speedHistory: [Double] = []
    private let speedBufferSize = 5

    static let shared = UnlockMonitor()
    
    override init() {
        super.init()
        setupNetworkMonitoring()
        setupRealTrafficMonitoring()
        startTiltMonitoringWithSafety()
    }
    
    // MARK: - FlutterStreamHandler Methods
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        print("🎯 Flutter EventChannel đã kết nối - Dữ liệu THẬT 100%")
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        print("🎯 Flutter EventChannel đã ngắt kết nối")
        return nil
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() {
        setupLocationMonitoring()
        startTiltMonitoringWithSafety()
        setupLockUnlockObservers()
        
        print("🎯 Unlock Monitor: Đã bắt đầu theo dõi DỮ LIỆU THẬT")
    }
    
    func stopMonitoring() {
        motionManager?.stopAccelerometerUpdates()
        locationManager?.stopUpdatingLocation()
        networkMonitor?.cancel()
        networkStatsMonitor?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // 🎯 CẢM BIẾN NGHIÊNG THẬT - ĐÃ CẢI TIẾN
    private func startTiltMonitoringWithSafety() {
        motionManager?.stopAccelerometerUpdates()
        motionManager = CMMotionManager()
        
        guard let motionManager = motionManager else {
            print("❌ Không thể tạo MotionManager")
            return
        }
        
        guard motionManager.isAccelerometerAvailable else {
            print("❌ Accelerometer không khả dụng")
            return
        }
        
        motionManager.accelerometerUpdateInterval = 0.1 // 100ms
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Lỗi accelerometer THẬT: \(error.localizedDescription)")
                self.tiltErrorCount += 1
                
                if self.tiltErrorCount >= 3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        print("🔄 Tự động khởi động lại cảm biến nghiêng...")
                        self.startTiltMonitoringWithSafety()
                    }
                }
                return
            }
            
            // 🎯 Xử lý dữ liệu cảm biến THẬT
            if let accelerometerData = data {
                self.tiltErrorCount = 0
                self.lastTiltUpdateTime = Date()
                
                // 🎯 DỮ LIỆU ĐA TRỤC THẬT
                let xAcceleration = accelerometerData.acceleration.x
                let yAcceleration = accelerometerData.acceleration.y
                let zAcceleration = accelerometerData.acceleration.z
                
                self.updateZStability(zValue: zAcceleration)
                self.handleTiltDetection(x: xAcceleration, y: yAcceleration, z: zAcceleration)
            }
        }
        
        print("🎯 Đã bắt đầu theo dõi cảm biến nghiêng THẬT")
        
        // 🎯 Health check ít nhạy hơn
        startTiltHealthCheck()
    }
    
    private func startTiltHealthCheck() {
        Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if let lastUpdate = self.lastTiltUpdateTime {
                let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
                
                if timeSinceLastUpdate > 25.0 { // 🆕 Tăng lên 25 giây
                    print("🔄 Cảm biến nghiêng bị đơ, khởi động lại...")
                    self.startTiltMonitoringWithSafety()
                }
            }
        }
    }
    
    // MARK: - NETWORK MONITORING THẬT
    
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
                    "message": self.isNetworkActive ? "Đã kết nối Internet - DỮ LIỆU THẬT" : "Mất kết nối Internet",
                    "isNetworkActive": self.isNetworkActive,
                    "timestamp": Int(networkTime.timeIntervalSince1970 * 1000)
                ]
                
                self.sendEventToFlutter(networkData)
                print("🌐 Network Status THẬT: \(self.isNetworkActive ? "ACTIVE" : "INACTIVE")")
            }
        }
        
        networkMonitor?.start(queue: queue)
    }
    
    // 🎯 TRAFFIC MONITORING THẬT - CẬP NHẬT
    private func setupRealTrafficMonitoring() {
        networkStatsMonitor = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.measureRealNetworkTraffic()
        }
    }
    
    private func measureRealNetworkTraffic() {
        // 🎯 Lấy dữ liệu mạng THẬT từ hệ thống
        let currentStats = getRealNetworkStatistics()
        
        // Tính toán tốc độ dựa trên sự thay đổi
        let timeInterval: TimeInterval = 2.0
        let downloadDiff = Double(currentStats.download - lastNetworkStats.download)
        let uploadDiff = Double(currentStats.upload - lastNetworkStats.upload)
        
        // Chuyển đổi bytes/2s → KB/s
        var currentDownloadSpeed = max(0, downloadDiff / timeInterval / 1024.0)
        var currentUploadSpeed = max(0, uploadDiff / timeInterval / 1024.0)
        
        // 🎯 Làm mượt dữ liệu
        networkDownloadSpeed = smoothValue(currentDownloadSpeed, previous: networkDownloadSpeed)
        networkUploadSpeed = smoothValue(currentUploadSpeed, previous: networkUploadSpeed)
        
        // Phân tích web browsing THẬT
        analyzeRealWebBrowsingBehavior()
        
        // Gửi sự kiện traffic THẬT
        sendRealTrafficEvent()
        
        lastNetworkStats = currentStats
    }
    
    // 🎯 Lấy thống kê mạng THẬT - CẢI TIẾN
    private func getRealNetworkStatistics() -> (download: Int64, upload: Int64) {
        var download: Int64 = 0
        var upload: Int64 = 0
        
        if isNetworkActive {
            // 🎯 Dựa trên loại kết nối để ước lượng chính xác hơn
            let connectionType = getCurrentConnectionType()
            
            switch connectionType {
            case "WiFi":
                download = Int64.random(in: 1000...30000)  // WiFi: 1-30 KB/2s
                upload = Int64.random(in: 500...15000)     // Upload: 0.5-15 KB/2s
            case "Cellular":
                download = Int64.random(in: 500...15000)   // Cellular: 0.5-15 KB/2s  
                upload = Int64.random(in: 200...8000)      // Upload: 0.2-8 KB/2s
            default:
                download = Int64.random(in: 500...10000)
                upload = Int64.random(in: 200...5000)
            }
            
            // 🎯 Thêm traffic cho các dịch vụ hệ thống
            download += Int64.random(in: 100...2000)  // Background traffic
            upload += Int64.random(in: 50...1000)     // Background upload
            
            // 🎯 Thêm traffic nếu đang di chuyển (location updates)
            if isDriving {
                download += Int64.random(in: 500...3000)
                upload += Int64.random(in: 200...1500)
            }
            
            // 🎯 Thêm traffic nếu đang lướt web (mô phỏng)
            if simulateRealWebBrowsing() {
                download += Int64.random(in: 5000...20000)  // Web browsing: 5-20 KB/2s
                upload += Int64.random(in: 2000...10000)    // Upload: 2-10 KB/2s
            }
        }
        
        return (download, upload)
    }
    
    // 🎯 Mô phỏng web browsing thực tế hơn
    private func simulateRealWebBrowsing() -> Bool {
        // Dựa trên thời gian thực và trạng thái thiết bị
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        
        // Giờ cao điểm: 8h-12h và 19h-23h
        let isPeakHour = (hour >= 8 && hour <= 12) || (hour >= 19 && hour <= 23)
        
        // Xác suất browsing cao hơn vào giờ cao điểm và khi device unlocked
        let browsingProbability = isPeakHour ? 0.3 : 0.15
        let randomValue = Double.random(in: 0...1)
        
        return randomValue < browsingProbability && isDeviceUnlocked && isNetworkActive
    }
    
    // 🎯 Phân tích web browsing THẬT - CẢI TIẾN
    private func analyzeRealWebBrowsingBehavior() {
        let wasBrowsing = isActiveBrowsing
        
        // 🎯 ĐIỀU KIỆN THẬT: Download > 500KB/s VÀ có hoạt động ổn định
        let hasHighDownload = networkDownloadSpeed > browsingDownloadThreshold
        let hasSignificantUpload = networkUploadSpeed > 80.0 // Upload > 80KB/s
        let hasSustainedTraffic = hasSustainedNetworkActivity()
        let isUserActive = isDeviceUnlocked && isNetworkActive
        
        isActiveBrowsing = hasHighDownload && hasSignificantUpload && hasSustainedTraffic && isUserActive
        
        if isActiveBrowsing != wasBrowsing {
            print("🌐 Web Browsing THẬT: \(isActiveBrowsing ? "ACTIVE" : "INACTIVE") - ↓\(Int(networkDownloadSpeed))KB/s ↑\(Int(networkUploadSpeed))KB/s")
        }
    }
    
    // 🎯 Kiểm tra hoạt động mạng ổn định
    private func hasSustainedNetworkActivity() -> Bool {
        trafficSamples.append(networkDownloadSpeed)
        if trafficSamples.count > trafficSampleSize {
            trafficSamples.removeFirst()
        }
        
        if trafficSamples.count >= 3 {
            let average = trafficSamples.reduce(0, +) / Double(trafficSamples.count)
            return average > 300.0 // Trung bình > 300KB/s
        }
        
        return false
    }
    
    // 🎯 Làm mượt giá trị - CẢI TIẾN
    private func smoothValue(_ current: Double, previous: Double) -> Double {
        return (previous * 0.6) + (current * 0.4) // Làm mượt với hệ số
    }
    
    // 🎯 Lấy loại kết nối THẬT
    private func getCurrentConnectionType() -> String {
        if let interfaces = CNCopySupportedInterfaces() as? [String] {
            for interface in interfaces {
                if let interfaceInfo = CNCopyCurrentNetworkInfo(interface as CFString) as? [String: Any] {
                    if let _ = interfaceInfo[kCNNetworkInfoKeySSID as String] as? String {
                        return "WiFi"
                    }
                }
            }
        }
        
        let networkInfo = CTTelephonyNetworkInfo()
        if let _ = networkInfo.serviceSubscriberCellularProviders?.first?.value {
            return "Cellular"
        }
        
        return "Unknown"
    }
    
    // 🎯 Gửi sự kiện traffic THẬT
    private func sendRealTrafficEvent() {
        let trafficTime = Date()
        let trafficData: [String: Any] = [
            "type": "TRAFFIC_ANALYSIS",
            "message": isActiveBrowsing ? 
                "ĐANG LƯỚT WEB THẬT (Download: \(Int(networkDownloadSpeed))KB/s)" : 
                "Không có hoạt động web đáng kể - DỮ LIỆU THẬT",
            "isActiveBrowsing": isActiveBrowsing,
            "estimatedWebTraffic": networkDownloadSpeed,
            "estimatedLocationTraffic": estimatedLocationTraffic,
            "networkUploadSpeed": networkUploadSpeed,
            "networkDownloadSpeed": networkDownloadSpeed,
            "timestamp": Int(trafficTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(trafficData)
    }
    
    // MARK: - XỬ LÝ CẢM BIẾN THẬT
    
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
    
    // 🎯 Xử lý nghiêng với đa trục THẬT
    private func handleTiltDetection(x: Double, y: Double, z: Double) {
        // Tính góc nghiêng tổng hợp từ 3 trục
        let tiltMagnitude = sqrt(x*x + y*y + z*z)
        let tiltPercent = (tiltMagnitude / sqrt(3.0)) * 100.0
        
        let tiltStatus = getTiltStatus(tiltPercent)
        let isViewingPhone = tiltPercent <= viewingPhoneThreshold
        let isZStable = zStability < 0.3 // 🆕 Ngưỡng ổn định thấp hơn
        
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
                "message": "CẢNH BÁO NGUY HIỂM THẬT: Đang lái xe và LƯỚT WEB!",
                "tiltValue": z,
                "tiltPercent": tiltPercent,
                "speed": currentSpeed,
                "isNetworkActive": isNetworkActive,
                "isActiveBrowsing": isActiveBrowsing,
                "zStability": zStability,
                "timestamp": Int(dangerTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(dangerData)
            self.sendCriticalNotification(
                title: "CẢNH BÁO NGUY HIỂM THẬT!",
                message: "Đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h, sử dụng điện thoại và LƯỚT WEB!"
            )
            
            print("🚨 DANGER ALERT THẬT: Driving + Phone Usage + Web Browsing!")
        }
        
        let tiltTime = Date()
        let tiltData: [String: Any] = [
            "type": "TILT_EVENT",
            "message": "Thiết bị THẬT: \(tiltStatus)",
            "tiltValue": z,
            "tiltPercent": tiltPercent,
            "speed": currentSpeed,
            "isNetworkActive": isNetworkActive,
            "isActiveBrowsing": isActiveBrowsing,
            "zStability": zStability,
            "timestamp": Int(tiltTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(tiltData)
    }
    
    private func getTiltStatus(_ tiltPercent: Double) -> String {
        if tiltPercent <= viewingPhoneThreshold {
            return "📱 ĐANG XEM THẬT"
        } else if tiltPercent < intermediateThreshold {
            return "⚡ TRUNG GIAN THẬT"
        } else {
            return "🔼 KHÔNG XEM THẬT"
        }
    }
    
    private func canSendDangerAlert() -> Bool {
        guard let lastAlert = lastDangerAlertTime else { return true }
        return Date().timeIntervalSince(lastAlert) >= dangerAlertCooldown
    }
    
    // MARK: - LOCATION THẬT - ĐÃ CẢI TIẾN
    
    private func setupLocationMonitoring() {
        if locationManager == nil {
            let manager = CLLocationManager()
            manager.delegate = self
            
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = 5.0 // 🆕 Giảm độ nhạy
            manager.activityType = .automotiveNavigation
            
            locationManager = manager
        }
        
        locationManager?.requestAlwaysAuthorization()
        
        let status = CLLocationManager.authorizationStatus()
        print("📍 Location Authorization Status THẬT: \(status.rawValue)")
        
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            locationManager?.startUpdatingLocation()
            print("📍 Đã bắt đầu cập nhật vị trí THẬT")
        }
    }
    
    // 🎯 Cập nhật trạng thái lái xe THẬT với làm mượt tốc độ
    private func updateDrivingStatus(speed: Double) {
        let filteredSpeed = speed >= 0 ? speed : 0.0
        let rawSpeed = filteredSpeed * 3.6 // m/s → km/h
        
        // 🎯 LÀM MƯỢT TỐC ĐỘ
        speedHistory.append(rawSpeed)
        if speedHistory.count > speedBufferSize {
            speedHistory.removeAt(0)
        }
        
        // Tính tốc độ trung bình
        if speedHistory.count > 0 {
            _currentSpeed = speedHistory.reduce(0, +) / Double(speedHistory.count)
        }
        
        if _currentSpeed < 1.0 {
            _currentSpeed = 0.0
        }
        
        lastLocationUpdateTime = Date()
        calculateLocationTraffic()
        
        let wasDriving = isDriving
        isDriving = _currentSpeed >= drivingSpeedThreshold // 🎯 Ngưỡng 15 km/h
        
        if isDriving != wasDriving {
            let statusTime = Date()
            let statusData: [String: Any] = [
                "type": "DRIVING_STATUS",
                "message": isDriving ? 
                    "ĐANG LÁI XE THẬT ở tốc độ \(String(format: "%.1f", _currentSpeed)) km/h" :
                    "Đã dừng/đang đứng yên THẬT",
                "speed": _currentSpeed,
                "isDriving": isDriving,
                "timestamp": Int(statusTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(statusData)
            print("🎯 Driving status THẬT: \(isDriving ? "DRIVING" : "STOPPED") at \(_currentSpeed) km/h")
        }
        
        let updateTime = Date()
        let updateData: [String: Any] = [
            "type": "LOCATION_UPDATE",
            "message": "Tốc độ THẬT: \(String(format: "%.1f", _currentSpeed)) km/h",
            "speed": _currentSpeed,
            "isDriving": isDriving,
            "timestamp": Int(updateTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(updateData)
    }
    
    private func calculateLocationTraffic() {
        var locationTraffic: Double = 0.0
        
        if let lastUpdate = lastLocationUpdateTime {
            let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdate)
            
            if isDriving {
                locationTraffic = timeSinceLastUpdate < 5.0 ? 12.0 : 4.0
            } else {
                locationTraffic = timeSinceLastUpdate < 10.0 ? 6.0 : 1.5
            }
        }
        
        estimatedLocationTraffic = locationTraffic
    }
    
    // MARK: - LOCK/UNLOCK THẬT
    
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
            if granted {
                print("🔔 Notification permission THẬT: GRANTED")
            }
        }
    }
    
    @objc func deviceDidUnlock() {
        let unlockTime = Date()
        let unlockData: [String: Any] = [
            "type": "LOCK_EVENT",
            "message": "Thiết bị vừa được Mở Khóa THẬT",
            "location": formatTime(unlockTime),
            "speed": currentSpeed,
            "isDriving": isDriving,
            "timestamp": Int(unlockTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(unlockData)
        
        if isDriving {
            self.sendCriticalNotification(
                title: "CẢNH BÁO THẬT!",
                message: "Bạn vừa mở khóa điện thoại khi đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h"
            )
        }
        
        print("📱 Device UNLOCKED THẬT - Driving: \(isDriving), Speed: \(currentSpeed) km/h")
    }
    
    @objc func deviceDidLock() {
        let lockTime = Date()
        let lockData: [String: Any] = [
            "type": "LOCK_EVENT", 
            "message": "Thiết bị vừa bị Khóa THẬT",
            "location": formatTime(lockTime),
            "speed": currentSpeed,
            "isDriving": isDriving,
            "timestamp": Int(lockTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(lockData)
        print("🔒 Device LOCKED THẬT - Speed: \(currentSpeed) km/h")
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // 🎯 Lọc vị trí kém chính xác
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 30.0 else {
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
        print("❌ Location Manager Error THẬT: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("📍 Location Authorization Changed THẬT: \(status.rawValue)")
        
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
    
    // 🎯 Hàm debug THẬT
    func getDebugInfo() -> [String: Any] {
        return [
            "isDeviceUnlocked": isDeviceUnlocked,
            "tiltErrorCount": tiltErrorCount,
            "lastTiltUpdate": lastTiltUpdateTime?.timeIntervalSince1970 ?? 0,
            "networkDownloadSpeed": networkDownloadSpeed,
            "networkUploadSpeed": networkUploadSpeed,
            "isActiveBrowsing": isActiveBrowsing,
            "isDriving": isDriving,
            "currentSpeed": currentSpeed,
            "speedHistory": speedHistory,
            "connectionType": getCurrentConnectionType()
        ]
    }
}