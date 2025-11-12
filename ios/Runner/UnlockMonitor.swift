import CoreLocation
import CoreMotion
import UIKit
import UserNotifications
import Flutter
import Network
import SystemConfiguration.CaptiveNetwork

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
    
    private var networkActivityMonitor: Timer?
    private var lastHighTrafficTime: Date?
    private var isActiveBrowsing = false
    private var trafficSamples: [Double] = []
    private let trafficSampleSize = 10
    private var lastLocationUpdateTime: Date?
    private var estimatedLocationTraffic: Double = 0.0
    private var networkUploadSpeed: Double = 0.0
    private var networkDownloadSpeed: Double = 0.0
    
    private let drivingSpeedThreshold: Double = 10.0
    private let viewingPhoneThreshold: Double = 80.0
    private let intermediateThreshold: Double = 90.0
    private let browsingTrafficThreshold: Double = 80.0
    
    private var zAccelerationHistory: [Double] = []
    private let zStabilityBufferSize = 50
    private var zStability: Double = 0.0
    
    private let dangerAlertCooldown: TimeInterval = 5.0

    static let shared = UnlockMonitor()
    
    override init() {
        super.init()
        setupNetworkMonitoring()
        setupAdvancedTrafficMonitoring()
    }
    
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
        networkActivityMonitor?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
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
    
    private func setupAdvancedTrafficMonitoring() {
        networkActivityMonitor = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.analyzeNetworkBehavior()
        }
    }
    
    private func analyzeNetworkBehavior() {
        let (simulatedTraffic, uploadSpeed, downloadSpeed) = simulateTrafficMeasurement()
        
        calculateLocationTraffic()
        
        let actualWebTraffic = max(0, simulatedTraffic - estimatedLocationTraffic)
        
        networkUploadSpeed = uploadSpeed
        networkDownloadSpeed = downloadSpeed
        
        trafficSamples.append(actualWebTraffic)
        if trafficSamples.count > trafficSampleSize {
            trafficSamples.removeFirst()
        }
        
        let averageTraffic = trafficSamples.reduce(0, +) / Double(trafficSamples.count)
        
        let wasBrowsing = isActiveBrowsing
        
        let hasSignificantTraffic = averageTraffic > browsingTrafficThreshold
        let hasStableNetworkSpeed = uploadSpeed > 5.0 || downloadSpeed > 10.0
        
        isActiveBrowsing = hasSignificantTraffic && hasStableNetworkSpeed
        
        if isActiveBrowsing {
            lastHighTrafficTime = Date()
        }
        
        if wasBrowsing != isActiveBrowsing || (isActiveBrowsing && Int.random(in: 0...2) == 0) {
            let trafficTime = Date()
            let trafficData: [String: Any] = [
                "type": "TRAFFIC_ANALYSIS",
                "message": isActiveBrowsing ? 
                    "Đang có hoạt động lướt web (Ước tính: \(Int(averageTraffic))KB)" : 
                    "Không có hoạt động web đáng kể",
                "isActiveBrowsing": isActiveBrowsing,
                "estimatedWebTraffic": averageTraffic,
                "estimatedLocationTraffic": estimatedLocationTraffic,
                "networkUploadSpeed": uploadSpeed,
                "networkDownloadSpeed": downloadSpeed,
                "timestamp": Int(trafficTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(trafficData)
            print("📊 Traffic Analysis: Web=\(isActiveBrowsing ? "ACTIVE" : "INACTIVE") (Avg: \(Int(averageTraffic))KB, ↑\(Int(uploadSpeed))KB/s ↓\(Int(downloadSpeed))KB/s)")
        }
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
    
    private func simulateTrafficMeasurement() -> (Double, Double, Double) {
        var baseTraffic: Double = 0.0
        var uploadSpeed: Double = 0.0
        var downloadSpeed: Double = 0.0
        
        baseTraffic += Double.random(in: 2.0...8.0)
        uploadSpeed += Double.random(in: 0.1...2.0)
        downloadSpeed += Double.random(in: 0.5...5.0)
        
        baseTraffic += estimatedLocationTraffic
        uploadSpeed += estimatedLocationTraffic / 15.0
        downloadSpeed += estimatedLocationTraffic / 30.0
        
        if isDeviceUnlocked {
            let randomFactor = Double.random(in: 0.0...1.0)
            
            if randomFactor > 0.8 { 
                let webTraffic = Double.random(in: 150.0...400.0)
                baseTraffic += webTraffic
                downloadSpeed += Double.random(in: 20.0...80.0)
                uploadSpeed += Double.random(in: 5.0...20.0)
                
            } else if randomFactor > 0.6 { 
                let webTraffic = Double.random(in: 30.0...100.0)
                baseTraffic += webTraffic
                downloadSpeed += Double.random(in: 5.0...25.0)
                uploadSpeed += Double.random(in: 1.0...8.0)
            }
        }
        
        return (baseTraffic, uploadSpeed, downloadSpeed)
    }
    
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
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}