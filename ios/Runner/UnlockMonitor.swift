import CoreLocation
import CoreMotion
import UIKit
import UserNotifications
import Flutter
import Network
import SystemConfiguration
import CoreTelephony
import AVFoundation

// 🎯 CLASS CALL DETECTOR CHO CUỘC GỌI DI ĐỘNG
class CallDetectorManager: NSObject {
    private let callCenter = CTCallCenter()
    private var isInCall = false
    private var callStartTime: Date?
    
    var onCallStateChanged: ((Bool, String) -> Void)?
    
    func startMonitoring() {
        callCenter.callEventHandler = { [weak self] call in
            DispatchQueue.main.async {
                self?.handleCallEvent(call: call)
            }
        }
    }
    
    private func handleCallEvent(call: CTCall) {
        let previousCallState = isInCall
        
        switch call.callState {
        case CTCallStateIncoming:
            print("📞 CUỘC GỌI ĐẾN: \(call.callID ?? "Unknown")")
            // Chưa set isInCall = true vì chưa nhấc máy
            
        case CTCallStateConnected:
            print("📞 ĐÃ NHẤC MÁY - BẮT ĐẦU CUỘC GỌI")
            isInCall = true
            callStartTime = Date()
            onCallStateChanged?(true, "connected")
            
        case CTCallStateDisconnected:
            print("📞 ĐÃ KẾT THÚC CUỘC GỌI")
            isInCall = false
            callStartTime = nil
            onCallStateChanged?(false, "disconnected")
            
        default:
            break
        }
        
        print("📞 Call State: \(call.callState) - isInCall: \(isInCall)")
    }
    
    func isCurrentlyInCall() -> Bool {
        return isInCall
    }
    
    func getCallDuration() -> TimeInterval? {
        guard let startTime = callStartTime else { return nil }
        return Date().timeIntervalSince(startTime)
    }
}

// 🎯 CLASS VOIP CALL DETECTOR CHO ZALO/FACEBOOK
class VoIPCallDetector: NSObject {
    private let audioSession = AVAudioSession.sharedInstance()
    private var isInVoIPCall = false
    private var voipCallStartTime: Date?
    private var lastAudioRoute: String = ""
    
    var onVoIPCallStateChanged: ((Bool, String) -> Void)?
    
    func startMonitoring() {
        // Lắng nghe thay đổi audio route
        NotificationCenter.default.addObserver(self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil)
        
        // Lắng nghe thay đổi audio session
        NotificationCenter.default.addObserver(self,
            selector: #selector(audioSessionInterrupted),
            name: AVAudioSession.interruptionNotification,
            object: nil)
        
        print("📱 VoIP Call Detector started")
    }
    
    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func audioRouteChanged(notification: Notification) {
        DispatchQueue.main.async {
            self.checkCurrentAudioState()
        }
    }
    
    @objc private func audioSessionInterrupted(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let interruptionType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
        
        DispatchQueue.main.async {
            if interruptionType == AVAudioSession.InterruptionType.began.rawValue {
                // Cuộc gọi bắt đầu
                self.handleVoIPCallStarted()
            } else if interruptionType == AVAudioSession.InterruptionType.ended.rawValue {
                // Cuộc gọi kết thúc
                self.handleVoIPCallEnded()
            }
        }
    }
    
    private func checkCurrentAudioState() {
        let currentRoute = audioSession.currentRoute
        
        // 🎯 PHÁT HIỆN CUỘC GỌI VoIP DỰA TRÊN AUDIO ROUTE
        let isLikelyInVoIPCall = isAudioRouteIndicatingCall(currentRoute)
        
        if isLikelyInVoIPCall && !isInVoIPCall {
            handleVoIPCallStarted()
        } else if !isLikelyInVoIPCall && isInVoIPCall {
            handleVoIPCallEnded()
        }
        
        lastAudioRoute = describeAudioRoute(currentRoute)
    }
    
    private func isAudioRouteIndicatingCall(_ route: AVAudioSessionRouteDescription) -> Bool {
        let inputs = route.inputs.map { $0.portType }
        let outputs = route.outputs.map { $0.portType }
        
        // 🎯 KIỂM TRA BLUETOOTH - NẾU CÓ BLUETOOTH → KHÔNG BÁO VOIP
        let hasBluetooth = inputs.contains { port in
            port == .bluetoothHFP || 
            port == .bluetoothA2DP || 
            port == .bluetoothLE ||
            port.rawValue.contains("Bluetooth")
        } || outputs.contains { port in
            port == .bluetoothHFP || 
            port == .bluetoothA2DP || 
            port == .bluetoothLE ||
            port.rawValue.contains("Bluetooth")
        }
        
        // 🚗 NẾU CÓ BLUETOOTH → KHÔNG PHẢI VOIP NGUY HIỂM
        if hasBluetooth {
            print("🎧 Bluetooth device detected - Safe for calls")
            return false  // ❌ KHÔNG BÁO VOIP
        }
        
        // 🎯 PHÁT HIỆN CUỘC GỌI VoIP THÔNG THƯỜNG (KHÔNG Bluetooth)
        let hasMicrophone = inputs.contains { $0 == .builtInMic }
        let hasReceiver = outputs.contains { $0 == .builtInReceiver }
        let hasSpeaker = outputs.contains { $0 == .builtInSpeaker }
        let hasHeadphones = outputs.contains { $0 == .headphones }
        
        // 📱 CUỘC GỌI VoIP THẬT: điện thoại cầm tay (không Bluetooth)
        let isRealVoIPCall = hasMicrophone && (hasReceiver || hasSpeaker || hasHeadphones)
        
        print("🎧 Audio Route - Bluetooth: \(hasBluetooth), IsVoIPCall: \(isRealVoIPCall)")
        return isRealVoIPCall
    }
    
    private func handleVoIPCallStarted() {
        isInVoIPCall = true
        voipCallStartTime = Date()
        
        let callType = determineCallType()
        onVoIPCallStateChanged?(true, callType)
        
        print("📱 VoIP Call STARTED: \(callType)")
    }
    
    private func handleVoIPCallEnded() {
        isInVoIPCall = false
        voipCallStartTime = nil
        onVoIPCallStateChanged?(false, "ended")
        
        print("📱 VoIP Call ENDED")
    }
    
    private func determineCallType() -> String {
        let currentRoute = audioSession.currentRoute
        
        if currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
            return "voip_ear" // Gọi áp tai
        } else if currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker }) {
            return "voip_speaker" // Gọi loa ngoài
        } else if currentRoute.outputs.contains(where: { $0.portType == .headphones }) {
            return "voip_headphones" // Gọi tai nghe
        } else {
            return "voip_unknown"
        }
    }
    
    private func describeAudioRoute(_ route: AVAudioSessionRouteDescription) -> String {
        let inputs = route.inputs.map { $0.portType.rawValue }.joined(separator: ", ")
        let outputs = route.outputs.map { $0.portType.rawValue }.joined(separator: ", ")
        return "Inputs: [\(inputs)], Outputs: [\(outputs)]"
    }
    
    func isCurrentlyInVoIPCall() -> Bool {
        return isInVoIPCall
    }
    
    func getVoIPCallDuration() -> TimeInterval? {
        guard let startTime = voipCallStartTime else { return nil }
        return Date().timeIntervalSince(startTime)
    }
}

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
    
    // 🎯 THÊM CALL DETECTION
    private var callDetector: CallDetectorManager?
    private var isInCall = false
    private var callStartTime: Date?
    private var lastCallAlertTime: Date?
    private let callAlertCooldown: TimeInterval = 10.0 // 10 giây giữa các cảnh báo call
    
    // 📞 THÊM VOIP DETECTION
    private var voipCallDetector: VoIPCallDetector?
    private var isInVoIPCall = false
    private var voipCallStartTime: Date?
    private var lastVoIPAlertTime: Date?
    private let voipAlertCooldown: TimeInterval = 10.0 // 10 giây giữa các cảnh báo VoIP
    
    // 🎯 THÊM BLUETOOTH DETECTION
    private var isBluetoothConnected = false
    
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
        setupCallDetection()
        setupVoIPDetection()
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
        callDetector?.startMonitoring()
        voipCallDetector?.startMonitoring()
        
        print("Unlock Monitor: Đã đăng ký và bắt đầu theo dõi (bao gồm call + VoIP detection).")
    }
    
    func stopMonitoring() {
        motionManager?.stopAccelerometerUpdates()
        locationManager?.stopUpdatingLocation()
        networkMonitor?.cancel()
        networkCongestionDetector?.stopMonitoring()
        realNetworkMonitor?.stopMonitoring()
        callDetector = nil
        voipCallDetector?.stopMonitoring()
        voipCallDetector = nil
        speedUpdateTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // 🎯 THÊM PHƯƠNG THỨC BLUETOOTH CHECK
    private func isUsingBluetooth() -> Bool {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        let allPorts = currentRoute.inputs.map { $0.portType } + currentRoute.outputs.map { $0.portType }
        
        return allPorts.contains { port in
            port == .bluetoothHFP || 
            port == .bluetoothA2DP || 
            port == .bluetoothLE ||
            port.rawValue.lowercased().contains("bluetooth")
        }
    }
    
    // 🎯 THÊM PHƯƠNG THỨC VOIP DETECTION
    private func setupVoIPDetection() {
        voipCallDetector = VoIPCallDetector()
        voipCallDetector?.onVoIPCallStateChanged = { [weak self] isInCall, callType in
            guard let self = self else { return }
            
            let wasInVoIPCall = self.isInVoIPCall
            self.isInVoIPCall = isInCall
            
            if isInCall {
                self.voipCallStartTime = Date()
            } else {
                self.voipCallStartTime = nil
            }
            
            // Gửi sự kiện VoIP call state tới Flutter
            let callTime = Date()
            let callData: [String: Any] = [
                "type": "VOIP_CALL_EVENT",
                "message": isInCall ? "Đang trong cuộc gọi Zalo/Facebook (\(callType))" : "Đã kết thúc cuộc gọi Zalo/Facebook",
                "isInCall": isInCall,
                "isVoIPCall": true,
                "callType": callType,
                "callDuration": self.voipCallDetector?.getVoIPCallDuration() ?? 0,
                "timestamp": Int(callTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(callData)
            print("📱 VoIP Call State: \(isInCall ? "ACTIVE" : "ENDED") - Type: \(callType)")
            
            // 🚨 KIỂM TRA CẢNH BÁO NẾU ĐANG LÁI XE
            if isInCall && self.isDriving && !wasInVoIPCall {
                self.checkVoIPCallWhileDrivingAlert(callType: callType)
            }
        }
        
        voipCallDetector?.startMonitoring()
    }
    
    // 🎯 THÊM PHƯƠNG THỨC CALL DETECTION
    private func setupCallDetection() {
        callDetector = CallDetectorManager()
        callDetector?.onCallStateChanged = { [weak self] isInCall, state in
            guard let self = self else { return }
            
            let wasInCall = self.isInCall
            self.isInCall = isInCall
            
            if isInCall {
                self.callStartTime = Date()
            } else {
                self.callStartTime = nil
            }
            
            // Gửi sự kiện call state tới Flutter
            let callTime = Date()
            let callData: [String: Any] = [
                "type": "CALL_EVENT",
                "message": isInCall ? "Đang trong cuộc gọi điện thoại" : "Đã kết thúc cuộc gọi",
                "isInCall": isInCall,
                "callState": state,
                "callDuration": self.getCallDuration() ?? 0,
                "timestamp": Int(callTime.timeIntervalSince1970 * 1000)
            ]
            
            self.sendEventToFlutter(callData)
            print("📞 Call State Changed: \(isInCall ? "IN_CALL" : "END_CALL") - State: \(state)")
            
            // 🚨 KIỂM TRA CẢNH BÁO NẾU ĐANG LÁI XE VÀ BẮT ĐẦU CUỘC GỌI
            if isInCall && self.isDriving && !wasInCall {
                self.checkCallWhileDrivingAlert()
            }
        }
        
        callDetector?.startMonitoring()
    }
    
    private func getCallDuration() -> TimeInterval? {
        guard let startTime = callStartTime else { return nil }
        return Date().timeIntervalSince(startTime)
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
    
    // 🎯 THÊM HÀM KIỂM TRA CẢNH BÁO KHI NGHE ĐIỆN THOẠI LÁI XE
    private func checkCallWhileDrivingAlert() {
        // 🎯 KIỂM TRA BLUETOOTH TRƯỚC
        if isUsingBluetooth() {
            print("📞 Phone Call via Bluetooth - NO ALERT (Safe)")
            return  // 🎧 AN TOÀN - KHÔNG CẢNH BÁO
        }
        
        guard canSendCallAlert() else { return }
        
        let dangerTime = Date()
        lastCallAlertTime = dangerTime
        
        let dangerData: [String: Any] = [
            "type": "DANGER_EVENT",
            "message": "🚨 NGUY HIỂM CẤP ĐỘ CAO: Đang lái xe và NGHE ĐIỆN THOẠI!",
            "speed": currentSpeed,
            "isInCall": true,
            "callDuration": getCallDuration() ?? 0,
            "timestamp": Int(dangerTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(dangerData)
        self.sendCriticalNotification(
            title: "🚨 NGUY HIỂM KHI LÁI XE!",
            message: "Đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h và NGHE ĐIỆN THOẠI - TẬP TRUNG LÁI XE!"
        )
        
        print("🚨 CALL DANGER ALERT: Driving + Phone Call! Speed: \(currentSpeed) km/h")
    }
    
    // 🎯 THÊM HÀM CẢNH BÁO CHO VOIP CALL
    private func checkVoIPCallWhileDrivingAlert(callType: String) {
        // 🎯 KIỂM TRA BLUETOOTH TRƯỚC
        if isUsingBluetooth() {
            print("📱 VoIP Call via Bluetooth - NO ALERT (Safe)")
            return  // 🎧 AN TOÀN - KHÔNG CẢNH BÁO
        }
        
        guard canSendVoIPAlert() else { return }
        
        let dangerTime = Date()
        lastVoIPAlertTime = dangerTime
        
        let appName = getAppNameFromCallType(callType)
        let callDuration = voipCallDetector?.getVoIPCallDuration() ?? 0
        
        let dangerData: [String: Any] = [
            "type": "DANGER_EVENT",
            "message": "⚠️ CẢNH BÁO: Đang lái xe và GỌI VIDEO/THOẠI QUA ỨNG DỤNG!",
            "speed": currentSpeed,
            "isInCall": true,
            "isVoIPCall": true,
            "callType": callType,
            "callDuration": callDuration,
            "timestamp": Int(dangerTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(dangerData)
        self.sendCriticalNotification(
            title: "⚠️ CẢNH BÁO AN TOÀN!",
            message: "Đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h và GỌI ỨNG DỤNG - RẤT NGUY HIỂM!"
        )
        
        print("🚨 VOIP CALL DANGER ALERT: Driving + \(appName) Call! Speed: \(currentSpeed) km/h, Duration: \(callDuration)s")
    }
    
    private func canSendCallAlert() -> Bool {
        guard let lastAlert = lastCallAlertTime else { return true }
        return Date().timeIntervalSince(lastAlert) >= callAlertCooldown
    }
    
    private func canSendVoIPAlert() -> Bool {
        guard let lastAlert = lastVoIPAlertTime else { return true }
        return Date().timeIntervalSince(lastAlert) >= voipAlertCooldown
    }
    
    private func getAppNameFromCallType(_ callType: String) -> String {
        return "ZALO/FACEBOOK"
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
            
            // 🚨 KIỂM TRA CẢNH BÁO NẾU BẮT ĐẦU LÁI XE KHI ĐANG NGHE ĐIỆN THOẠI
            if isDriving && !wasDriving && (isInCall || isInVoIPCall) {
                if isInCall {
                    checkCallWhileDrivingAlert()
                }
                if isInVoIPCall {
                    let callType = voipCallDetector?.getVoIPCallDuration() != nil ? "voip_active" : "voip_unknown"
                    checkVoIPCallWhileDrivingAlert(callType: callType)
                }
            }
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
            
            if let accelerometerData = data {
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
    
    // 🎯 CẬP NHẬT HÀM HANDLE TILT DETECTION - THÊM 4 TÌNH HUỐNG CẢNH BÁO
    private func handleTiltDetection(zValue: Double) {
        let tiltPercent = convertTiltToPercent(zValue)
        let tiltStatus = getTiltStatus(tiltPercent)
        let isViewingPhone = tiltPercent <= viewingPhoneThreshold
        let isZStable = zStability < 1.5
        
        // 🚨 CẢNH BÁO 1: WEB BROWSING + LÁI XE
        let shouldTriggerWebDangerAlert = isDeviceUnlocked && 
                                         isDriving && 
                                         isViewingPhone && 
                                         isZStable &&
                                         isActiveBrowsing &&
                                         canSendDangerAlert()
        
        // 🚨 CẢNH BÁO 2: CUỘC GỌI DI ĐỘNG + LÁI XE
        let shouldTriggerCallDangerAlert = isDriving && 
                                          isInCall && 
                                          isZStable &&
                                          canSendCallAlert()
        
        // 🚨 CẢNH BÁO 3: CUỘC GỌI ZALO/FACEBOOK + LÁI XE
        let shouldTriggerVoIPDangerAlert = isDriving && 
                                          isInVoIPCall && 
                                          isZStable &&
                                          canSendVoIPAlert()
        // 🆕 CẢNH BÁO 4: KHI CHỈ XEM ĐIỆN THOẠI (KHÔNG lướt web)
        let shouldTriggerPhoneUsageAlert = isDeviceUnlocked && 
                                        isDriving && 
                                        isViewingPhone && 
                                        isZStable && 
                                        !isActiveBrowsing &&  // 🎯 KHÔNG lướt web
                                        !isInCall &&          // 🎯 KHÔNG gọi điện
                                        !isInVoIPCall &&      // 🎯 KHÔNG gọi Zalo
                                        canSendDangerAlert()
        
        // KÍCH HOẠT CÁC CẢNH BÁO
        if shouldTriggerWebDangerAlert {
            triggerWebDangerAlert(tiltPercent: tiltPercent, zValue: zValue)
        }
        
        if shouldTriggerCallDangerAlert {
            checkCallWhileDrivingAlert()
        }
        
        if shouldTriggerVoIPDangerAlert {
            let callType = voipCallDetector?.getVoIPCallDuration() != nil ? "voip_active" : "voip_unknown"
            checkVoIPCallWhileDrivingAlert(callType: callType)
        }

        if shouldTriggerPhoneUsageAlert {
            triggerPhoneUsageAlert(tiltPercent: tiltPercent, zValue: zValue)
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
            "isInCall": isInCall,
            "isVoIPCall": isInVoIPCall,
            "zStability": zStability,
            "timestamp": Int(tiltTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(tiltData)
    }
    
    // 🎯 TÁCH HÀM CẢNH BÁO WEB THÀNH RIÊNG
    private func triggerWebDangerAlert(tiltPercent: Double, zValue: Double) {
        let dangerTime = Date()
        lastDangerAlertTime = dangerTime
        
        let dangerData: [String: Any] = [
            "type": "DANGER_EVENT",
            "message": "🚨 NGUY HIỂM CẤP ĐỘ CAO: Đang lái xe và LƯỚT WEB/ỨNG DỤNG!",
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
            title: "🚨 NGUY HIỂM KHI LÁI XE!",
            message: "Đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h và LƯỚT WEB - VÔ CÙNG NGUY HIỂM!"
        )
        
        print("🚨 WEB DANGER ALERT: Driving + Phone Usage + Web Browsing! (Tilt: \(tiltPercent)%)")
    }

    private func triggerPhoneUsageAlert(tiltPercent: Double, zValue: Double) {
        let dangerTime = Date()
        lastDangerAlertTime = dangerTime
        
        let dangerData: [String: Any] = [
            "type": "DANGER_EVENT",
            "message": "⚠️ CẢNH BÁO: Đang lái xe và SỬ DỤNG ĐIỆN THOẠI!",
            "tiltValue": zValue,
            "tiltPercent": tiltPercent,
            "speed": currentSpeed,
            "isNetworkActive": isNetworkActive,
            "isActiveBrowsing": isActiveBrowsing,  // sẽ là false
            "isInCall": isInCall,                  // sẽ là false  
            "isVoIPCall": isInVoIPCall,            // sẽ là false
            "zStability": zStability,
            "timestamp": Int(dangerTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(dangerData)
        self.sendCriticalNotification(
            title: "⚠️ CẢNH BÁO!",
            message: "Đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h và DÙNG ĐIỆN THOẠI!"
        )
        
        print("📱 PHONE USAGE ALERT: Driving + Using Phone! Tilt: \(tiltPercent)%")
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
            "isInCall": isInCall,
            "isVoIPCall": isInVoIPCall,
            "timestamp": Int(unlockTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(unlockData)
        
        if isDriving {
            self.sendCriticalNotification(
                title: "CẢNH BÁO!",
                message: "Bạn vừa mở khóa điện thoại khi đang lái xe ở \(String(format: "%.1f", currentSpeed)) km/h"
            )
        }
        
        print("📱 Device UNLOCKED at \(formatTime(unlockTime)) - Driving: \(isDriving), Speed: \(currentSpeed) km/h, InCall: \(isInCall), VoIPCall: \(isInVoIPCall)")
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
            "isInCall": isInCall,
            "isVoIPCall": isInVoIPCall,
            "timestamp": Int(lockTime.timeIntervalSince1970 * 1000)
        ]
        
        self.sendEventToFlutter(lockData)
        print("🔒 Device LOCKED at \(formatTime(lockTime)) - Speed: \(currentSpeed) km/h, InCall: \(isInCall), VoIPCall: \(isInVoIPCall)")
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
        let hasModerateDownload = receivedDiff > 60000    // 60KB - web có ảnh
        let hasLargeDownload = receivedDiff > 150000      // 🆕 150KB - video streaming
        let hasModerateUpload = sentDiff > 30000          // 30KB
        let hasPacketActivity = packetsDiff > 20          // 20 packets
        let hasMinimalPackets = packetsDiff > 5           // 🆕 5 packets - cho video
        let hasActiveConnections = currentStats.activeConnections > 3
        
        // 🎯 KẾT HỢP NHIỀU YẾU TỐ - THÊM ĐIỀU KIỆN VIDEO
        let isActive = (hasModerateDownload && hasPacketActivity) || 
                      (hasModerateUpload && hasPacketActivity) ||
                      (hasActiveConnections && hasModerateDownload) ||
                      (receivedDiff > 50000 && packetsDiff > 20) || // Web nhẹ
                      (hasLargeDownload && hasMinimalPackets)       // 🆕 VIDEO STREAMING!
        
        print("🌐 Network Activity Result: \(isActive) - Consecutive: \(consecutiveActiveCount)")
        return isActive
    }
    
    private func determineActivityType(currentStats: NetworkInterfaceStats) -> String {
        guard let lastStats = lastNetworkStats else { return "Không có dữ liệu" }
        
        let receivedDiff = currentStats.bytesReceived - lastStats.bytesReceived
        let sentDiff = currentStats.bytesSent - lastStats.bytesSent
        let packetsDiff = currentStats.packetsReceived - lastStats.packetsReceived
        
        // 🆕 KIỂM TRA VIDEO STREAMING ĐẶC BIỆT
        let isLikelyVideoStreaming = receivedDiff > 150000 && packetsDiff > 5
        
        if isLikelyVideoStreaming {
            return "Xem video trực tuyến (YouTube/Netflix)"
        } else if receivedDiff > 150000 {
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
