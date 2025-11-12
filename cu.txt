// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

void main() {
  runApp(const MyApp());
}

// 🎯 CHỈ tạo EventChannel trên iOS để tránh lỗi đa nền tảng
const EventChannel _eventChannel = EventChannel('com.example.app/monitor_events');

class MonitorEvent {
  final String type;
  final String message;
  final String? location;
  final double? tiltValue;
  final double? tiltPercent;
  final double? speed;
  final bool? isDriving;
  final bool? isNetworkActive;
  final double? zStability;
  final DateTime timestamp;
  
  final bool? isActiveBrowsing;
  final double? estimatedWebTraffic;
  final double? estimatedLocationTraffic;
  final double? networkUploadSpeed;
  final double? networkDownloadSpeed;

  MonitorEvent({
    required this.type,
    required this.message,
    this.location,
    this.tiltValue,
    this.tiltPercent,
    this.speed,
    this.isDriving,
    this.isNetworkActive,
    this.zStability,
    required this.timestamp,
    this.isActiveBrowsing,
    this.estimatedWebTraffic,
    this.estimatedLocationTraffic,
    this.networkUploadSpeed,
    this.networkDownloadSpeed,
  });

  factory MonitorEvent.fromJson(Map<String, dynamic> json) {
    return MonitorEvent(
      type: json['type'] as String,
      message: json['message'] as String,
      location: json['location'] as String?,
      tiltValue: json['tiltValue'] as double?,
      tiltPercent: json['tiltPercent'] as double?,
      speed: json['speed'] as double?,
      isDriving: json['isDriving'] as bool?,
      isNetworkActive: json['isNetworkActive'] as bool?,
      zStability: json['zStability'] as double?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      isActiveBrowsing: json['isActiveBrowsing'] as bool?,
      estimatedWebTraffic: json['estimatedWebTraffic'] as double?,
      estimatedLocationTraffic: json['estimatedLocationTraffic'] as double?,
      networkUploadSpeed: json['networkUploadSpeed'] as double?,
      networkDownloadSpeed: json['networkDownloadSpeed'] as double?,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unlock & Tilt Monitor',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F1F1F),
        ),
      ),
      home: const MonitorScreen(),
    );
  }
}

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  List<MonitorEvent> _historyEvents = [];
  MonitorEvent? _latestTiltEvent;
  MonitorEvent? _latestDangerEvent;
  String _connectionStatus = "Đang chờ kết nối...";
  double _currentSpeed = 0.0;
  bool _isDriving = false;
  bool _isNetworkActive = false;
  bool _isActiveBrowsing = false;
  double _networkUploadSpeed = 0.0;
  double _networkDownloadSpeed = 0.0;

  // 🎯 BIẾN ĐA NỀN TẢNG
  bool _isUpdating = false;
  bool _isIOS = false;
  String _platformName = "Unknown";

  final List<double> _tiltHistory = [];
  static const int _tiltBufferSize = 30;
  double _averageTiltPercent = 0.0;

  String _currentTiltStatus = "Chờ dữ liệu...";
  Color _currentTiltColor = Colors.grey;

  // 🎯 MÔ PHỎNG DỮ LIỆU CHO NON-IOS
  Timer? _simulationTimer;
  Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initializePlatform();
    _startListeningToEvents();
    _startDataSimulation();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }

  // 🎯 KHỞI TẠO NỀN TẢNG
  void _initializePlatform() {
    setState(() {
      _isIOS = defaultTargetPlatform == TargetPlatform.iOS;
      _platformName = _getPlatformName();
      _connectionStatus = "Nền tảng: $_platformName";
    });
    print("🚀 Ứng dụng chạy trên: $_platformName");
  }

  String _getPlatformName() {
    if (kIsWeb) return "Web Browser";
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS: return "iOS";
      case TargetPlatform.android: return "Android";
      case TargetPlatform.windows: return "Windows";
      case TargetPlatform.macOS: return "macOS";
      case TargetPlatform.linux: return "Linux";
      default: return "Unknown";
    }
  }

  // 🎯 LẮNG NGHE SỰ KIỆN (CHỈ iOS)
  void _startListeningToEvents() {
    if (_isIOS) {
      _eventChannel.receiveBroadcastStream().listen(
        _onEvent,
        onError: _onError,
        onDone: _onDone,
      );
    } else {
      // Non-iOS: Dùng simulated data
      _connectionStatus = "Đang chạy trên $_platformName (Simulated Data)";
    }
  }

  // 🎯 MÔ PHỎNG DỮ LIỆU CHO NON-IOS
  void _startDataSimulation() {
    if (!_isIOS) {
      _simulationTimer = Timer.periodic(Duration(seconds: 2), (timer) {
        _generateSimulatedData();
      });
    }
  }

  void _generateSimulatedData() {
    // 🎯 Mô phỏng dữ liệu tilt ngẫu nhiên
    final simulatedTiltPercent = _random.nextDouble() * 100;
    _updateTiltAverage(simulatedTiltPercent);
    
    // 🎯 Mô phỏng tốc độ di chuyển
    final simulatedSpeed = _random.nextDouble() * 120;
    
    // 🎯 Mô phỏng trạng thái lái xe
    final simulatedDriving = simulatedSpeed > 10;
    
    // 🎯 Mô phỏng network traffic
    final simulatedDownloadSpeed = 50 + _random.nextDouble() * 500;
    final simulatedUploadSpeed = 10 + _random.nextDouble() * 100;
    
    setState(() {
      _currentSpeed = simulatedSpeed;
      _isDriving = simulatedDriving;
      _networkDownloadSpeed = simulatedDownloadSpeed;
      _networkUploadSpeed = simulatedUploadSpeed;
      _isNetworkActive = true;
      
      // 🎯 Mô phỏng web browsing (30% thời gian)
      _isActiveBrowsing = _random.nextDouble() > 0.7;
    });

    // 🎯 Tạo sự kiện mô phỏng
    final simulatedEvent = MonitorEvent(
      type: 'TILT_EVENT',
      message: 'Thiết bị: $_currentTiltStatus',
      tiltValue: simulatedTiltPercent / 100,
      tiltPercent: simulatedTiltPercent,
      speed: simulatedSpeed,
      isDriving: simulatedDriving,
      isNetworkActive: true,
      zStability: _random.nextDouble() * 0.5,
      timestamp: DateTime.now(),
      isActiveBrowsing: _isActiveBrowsing,
      estimatedWebTraffic: _isActiveBrowsing ? 100 + _random.nextDouble() * 200 : 10 + _random.nextDouble() * 20,
      estimatedLocationTraffic: 5 + _random.nextDouble() * 10,
      networkUploadSpeed: simulatedUploadSpeed,
      networkDownloadSpeed: simulatedDownloadSpeed,
    );

    _latestTiltEvent = simulatedEvent;
    
    // 🎯 Thêm vào lịch sử mỗi 10 giây
    if (DateTime.now().second % 10 == 0) {
      _historyEvents.insert(0, simulatedEvent);
      if (_historyEvents.length > 20) {
        _historyEvents.removeLast();
      }
    }

    // 🎯 Mô phỏng cảnh báo nguy hiểm
    if (_isDriving && _currentTiltStatus.contains("ĐANG XEM") && _isActiveBrowsing) {
      _simulateDangerAlert();
    }
  }

  void _simulateDangerAlert() {
    if (_latestDangerEvent == null || 
        DateTime.now().difference(_latestDangerEvent!.timestamp).inSeconds > 10) {
      
      final dangerEvent = MonitorEvent(
        type: 'DANGER_EVENT',
        message: 'CẢNH BÁO NGUY HIỂM: Đang lái xe và LƯỚT WEB!',
        tiltValue: _latestTiltEvent?.tiltValue,
        tiltPercent: _latestTiltEvent?.tiltPercent,
        speed: _currentSpeed,
        isDriving: true,
        isNetworkActive: true,
        zStability: _latestTiltEvent?.zStability,
        timestamp: DateTime.now(),
        isActiveBrowsing: true,
      );

      setState(() {
        _latestDangerEvent = dangerEvent;
        _historyEvents.insert(0, dangerEvent);
      });
    }
  }

  void _updateTiltAverage(double tiltPercent) {
    _tiltHistory.add(tiltPercent);
    if (_tiltHistory.length > _tiltBufferSize) {
      _tiltHistory.removeAt(0);
    }

    if (_tiltHistory.isNotEmpty) {
      _averageTiltPercent = _tiltHistory.reduce((a, b) => a + b) / _tiltHistory.length;
    }

    _currentTiltStatus = _getTiltStatus(_averageTiltPercent);
    _currentTiltColor = _getTiltColor(_averageTiltPercent);
  }

  String _getTiltStatus(double tiltPercent) {
    if (tiltPercent <= 80.0) {
      return "📱 ĐANG XEM";
    } else if (tiltPercent < 90.0) {
      return "⚡ TRUNG GIAN";
    } else {
      return "🔼 KHÔNG XEM";
    }
  }

  Color _getTiltColor(double tiltPercent) {
    if (tiltPercent <= 80.0) {
      return Colors.red.shade700;
    } else if (tiltPercent < 90.0) {
      return Colors.orange.shade700;
    } else {
      return Colors.green.shade700;
    }
  }

  // 🎯 XỬ LÝ SỰ KIỆN THỰC (CHỈ iOS)
  void _onEvent(dynamic event) {
    if (_isUpdating) return;
    _isUpdating = true;
    
    setState(() {
      _connectionStatus = "Đã kết nối iOS Native";
      try {
        final Map<String, dynamic> data = jsonDecode(event as String);
        final monitorEvent = MonitorEvent.fromJson(data);

        if (monitorEvent.type == 'TILT_EVENT') {
          _latestTiltEvent = monitorEvent;
          if (monitorEvent.tiltPercent != null) {
            _updateTiltAverage(monitorEvent.tiltPercent!);
          }
          if (monitorEvent.isActiveBrowsing != null) {
            _isActiveBrowsing = monitorEvent.isActiveBrowsing!;
          }
        } else if (monitorEvent.type == 'DANGER_EVENT') {
          _latestDangerEvent = monitorEvent;
          _historyEvents.insert(0, monitorEvent);
        } else if (monitorEvent.type == 'NETWORK_STATUS') {
          _isNetworkActive = monitorEvent.isNetworkActive ?? false;
          _historyEvents.insert(0, monitorEvent);
        } else if (monitorEvent.type == 'TRAFFIC_ANALYSIS') {
          _isActiveBrowsing = monitorEvent.isActiveBrowsing ?? false;
          _networkUploadSpeed = monitorEvent.networkUploadSpeed ?? 0.0;
          _networkDownloadSpeed = monitorEvent.networkDownloadSpeed ?? 0.0;
          _historyEvents.insert(0, monitorEvent);
        } else if (monitorEvent.type == 'DRIVING_STATUS' || monitorEvent.type == 'LOCATION_UPDATE') {
          _currentSpeed = monitorEvent.speed ?? 0.0;
          _isDriving = monitorEvent.isDriving ?? false;
          _historyEvents.insert(0, monitorEvent);
        } else {
          _historyEvents.insert(0, monitorEvent);
        }
      } catch (e) {
        _connectionStatus = "Lỗi phân tích JSON: $e";
        print('Error decoding JSON: $e, Raw event: $event');
      }
    });
    
    Future.delayed(Duration(milliseconds: 50), () {
      _isUpdating = false;
    });
  }

  void _onError(Object error) {
    setState(() {
      _connectionStatus = "Lỗi kết nối: ${error.toString()}";
      print('EventChannel Error: $error');
    });
  }

  void _onDone() {
    setState(() {
      _connectionStatus = "Kênh truyền tin đã đóng.";
    });
  }

  // 🎯 MANUAL SPEED TEST (ĐA NỀN TẢNG)
  void _manualSpeedTest() {
    setState(() {
      _networkDownloadSpeed = 100 + _random.nextDouble() * 400;
      _networkUploadSpeed = 50 + _random.nextDouble() * 150;
    });
  }

  // 🎯 UI WIDGETS (GIỮ NGUYÊN)
  Widget _buildDangerAlertCard() {
    if (_latestDangerEvent == null) return const SizedBox.shrink();

    return Card(
      elevation: 8,
      color: Colors.red.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.yellow, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'CẢNH BÁO NGUY HIỂM',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _latestDangerEvent!.message,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Thời gian: ${_latestDangerEvent!.timestamp.toString().substring(11, 19)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (_latestDangerEvent!.tiltPercent != null)
              Text(
                'Tilt: ${_latestDangerEvent!.tiltPercent!.toStringAsFixed(1)}% | Web: ${_isActiveBrowsing ? "Đang lướt" : "Không lướt"} | Tốc độ: ${_currentSpeed.toStringAsFixed(1)} km/h',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            if (!_isIOS)
              Text(
                '⚠️ Dữ liệu mô phỏng',
                style: TextStyle(color: Colors.yellow.shade300, fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrivingStatusCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: _isDriving ? Colors.orange.shade900 : Colors.green.shade900,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isDriving ? Icons.directions_car : Icons.person,
                  color: Colors.white,
                  size: 30,
                ),
                const SizedBox(width: 10),
                Text(
                  _isDriving ? 'ĐANG LÁI XE' : 'ĐANG DỪNG/ĐỨNG YÊN',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tốc độ: ${_currentSpeed.toStringAsFixed(1)} km/h',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isDriving 
                  ? 'Đang di chuyển - vui lòng tập trung lái xe'
                  : 'An toàn - không di chuyển',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            if (!_isIOS)
              Text(
                '📱 Nền tảng: $_platformName',
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkTrafficCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: _isActiveBrowsing ? Colors.blue.shade900 : Colors.grey.shade800,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isActiveBrowsing ? Icons.network_check : Icons.network_wifi,
                  color: _isActiveBrowsing ? Colors.blue.shade200 : Colors.grey.shade400,
                  size: 30,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isActiveBrowsing ? 'ĐANG LƯỚT WEB' : 'KHÔNG LƯỚT WEB',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _isActiveBrowsing ? Colors.blue.shade200 : Colors.grey.shade400,
                        ),
                      ),
                      Text(
                        'Nền tảng: $_platformName',
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.green),
                  onPressed: _manualSpeedTest,
                  tooltip: 'Test tốc độ mạng',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Icon(Icons.upload, color: Colors.green.shade400, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Upload\n${_networkUploadSpeed.toStringAsFixed(1)} KB/s',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade400,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Icon(Icons.download, color: Colors.orange.shade400, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Download\n${_networkDownloadSpeed.toStringAsFixed(1)} KB/s',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _isActiveBrowsing 
                  ? 'Đang có hoạt động lướt web đáng kể'
                  : 'Không có hoạt động web đáng kể',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            if (!_isIOS)
              Text(
                '🔬 Dữ liệu đang được mô phỏng',
                style: TextStyle(fontSize: 11, color: Colors.yellow.shade300),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTiltMonitorCard() {
    final double tiltValue = _latestTiltEvent?.tiltValue ?? 0.0;
    final String tiltMessage = _latestTiltEvent?.message ?? 'Chờ dữ liệu...';
    
    final String tiltStatus = _currentTiltStatus;
    final Color tiltColor = _currentTiltColor;

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.screen_rotation, color: tiltColor, size: 30),
                const SizedBox(width: 10),
                const Text(
                  'Cảm Biến Nghiêng',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 20),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: tiltColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tiltColor, width: 2),
              ),
              child: Row(
                children: [
                  Icon(
                    _averageTiltPercent <= 80.0 ? Icons.warning : 
                    _averageTiltPercent < 90.0 ? Icons.info : Icons.check_circle,
                    color: tiltColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tiltStatus,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: tiltColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            Text(
              'Góc Nghiêng Hiện Tại: ${tiltValue.toStringAsFixed(3)} rad',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            Text(
              'Tilt Trung Bình (3s): ${_averageTiltPercent.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: tiltColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Trạng Thái: $tiltMessage',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            Text(
              'Độ Ổn Định Z: ${_latestTiltEvent?.zStability?.toStringAsFixed(3) ?? "N/A"}',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
            Row(
              children: [
                Text(
                  'Mạng: ',
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                Text(
                  _isNetworkActive ? "📶 Đang kết nối" : "📵 Mất kết nối",
                  style: TextStyle(
                    fontSize: 14,
                    color: _isNetworkActive ? Colors.green.shade400 : Colors.red.shade400,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Web: ',
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
                Text(
                  _isActiveBrowsing ? "🌐 Đang lướt web" : "💤 Không lướt web",
                  style: TextStyle(
                    fontSize: 14,
                    color: _isActiveBrowsing ? Colors.blue.shade400 : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
            if (_latestTiltEvent != null)
              Text(
                'Cập nhật: ${_latestTiltEvent!.timestamp.toString().substring(11, 19)}',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            if (!_isIOS)
              Text(
                '🖥️ Đang chạy trên $_platformName - Dữ liệu mô phỏng',
                style: TextStyle(fontSize: 11, color: Colors.blue.shade300),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        border: Border(
          bottom: BorderSide(color: Colors.white12, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _currentTiltColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _currentTiltColor, width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  _averageTiltPercent <= 80.0 ? Icons.phone_android : 
                  _averageTiltPercent < 90.0 ? Icons.phone_iphone : Icons.phone_disabled,
                  color: _currentTiltColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _currentTiltStatus,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _currentTiltColor,
                  ),
                ),
              ],
            ),
          ),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _isDriving ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isDriving ? Colors.orange : Colors.green,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isDriving ? Icons.directions_car : Icons.person,
                  color: _isDriving ? Colors.orange : Colors.green,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _isDriving ? 'ĐANG LÁI' : 'DỪNG',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isDriving ? Colors.orange : Colors.green,
                  ),
                ),
              ],
            ),
          ),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _isActiveBrowsing ? Colors.blue.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isActiveBrowsing ? Colors.blue : Colors.grey,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isActiveBrowsing ? Icons.web : Icons.web_asset,
                  color: _isActiveBrowsing ? Colors.blue : Colors.grey,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _isActiveBrowsing ? 'WEB' : 'NO WEB',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isActiveBrowsing ? Colors.blue : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventTile(MonitorEvent event) {
    Color eventColor;
    IconData icon;
    String subtitle = 'Thời gian: ${event.timestamp.toString().substring(0, 19)}';

    switch (event.type) {
      case 'LOCK_EVENT':
        final bool isUnlocked = event.message.contains('Mở Khóa');
        eventColor = isUnlocked ? Colors.green.shade400 : Colors.red.shade400;
        icon = isUnlocked ? Icons.lock_open : Icons.lock;
        if (event.location != null) {
          subtitle += '\nVị trí: ${event.location}';
        }
        break;
      
      case 'DANGER_EVENT':
        eventColor = Colors.red.shade400;
        icon = Icons.warning;
        if (event.speed != null) {
          subtitle += '\nTốc độ: ${event.speed!.toStringAsFixed(1)} km/h';
        }
        if (event.tiltPercent != null) {
          subtitle += '\nTilt: ${event.tiltPercent!.toStringAsFixed(1)}%';
        }
        if (event.isActiveBrowsing != null) {
          subtitle += '\nWeb: ${event.isActiveBrowsing! ? "Đang lướt" : "Không lướt"}';
        }
        break;
      
      case 'DRIVING_STATUS':
        eventColor = event.isDriving == true ? Colors.orange.shade400 : Colors.blue.shade400;
        icon = event.isDriving == true ? Icons.directions_car : Icons.person;
        if (event.speed != null) {
          subtitle += '\nTốc độ: ${event.speed!.toStringAsFixed(1)} km/h';
        }
        break;
      
      case 'NETWORK_STATUS':
        eventColor = event.isNetworkActive == true ? Colors.green.shade400 : Colors.red.shade400;
        icon = event.isNetworkActive == true ? Icons.wifi : Icons.wifi_off;
        subtitle += '\nTrạng thái mạng';
        break;

      case 'TRAFFIC_ANALYSIS':
        eventColor = event.isActiveBrowsing == true ? Colors.blue.shade400 : Colors.grey.shade400;
        icon = event.isActiveBrowsing == true ? Icons.web : Icons.web_asset;
        subtitle += '\nWeb: ${event.isActiveBrowsing == true ? "Đang lướt" : "Không lướt"}';
        if (event.estimatedWebTraffic != null) {
          subtitle += '\nWeb Traffic: ${event.estimatedWebTraffic!.toStringAsFixed(1)}KB';
        }
        if (event.networkUploadSpeed != null && event.networkDownloadSpeed != null) {
          subtitle += '\n↑${event.networkUploadSpeed!.toStringAsFixed(1)}KB/s ↓${event.networkDownloadSpeed!.toStringAsFixed(1)}KB/s';
        }
        break;
      
      case 'LOCATION_UPDATE':
        eventColor = Colors.purple.shade400;
        icon = Icons.location_on;
        if (event.speed != null) {
          subtitle += '\nTốc độ: ${event.speed!.toStringAsFixed(1)} km/h';
        }
        break;
      
      default:
        eventColor = Colors.grey.shade400;
        icon = Icons.info;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: eventColor.withOpacity(0.3), width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        leading: Icon(icon, color: eventColor, size: 32),
        title: Text(
          event.message,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: eventColor,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white70),
        ),
        // 🎯 SỬA LỖI: Thay Icons.simulation bằng Icons.computer
        trailing: !_isIOS ? Icon(Icons.computer, color: Colors.blue.shade300, size: 16) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Theo Dõi An Toàn Lái Xe'),
        backgroundColor: _isIOS ? Colors.blue.shade900 : Colors.purple.shade900,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48.0),
          child: Column(
            children: [
              _buildStatusBar(),
              Container(
                color: Colors.white12,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(
                  '$_connectionStatus | Tilt: ${_averageTiltPercent.toStringAsFixed(1)}% | Tốc độ: ${_currentSpeed.toStringAsFixed(1)} km/h | Web: ${_isActiveBrowsing ? "Đang lướt" : "Không lướt"}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            // Làm mới dữ liệu khi kéo xuống
          });
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: _buildDangerAlertCard(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: _buildDrivingStatusCard(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: _buildNetworkTrafficCard(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: _buildTiltMonitorCard(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 10.0, bottom: 8.0),
                child: Row(
                  children: [
                    Text(
                      'Lịch Sử Sự Kiện',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Colors.blueAccent,
                      ),
                    ),
                    if (!_isIOS)
                      Container(
                        margin: EdgeInsets.only(left: 10),
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade800,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'SIM',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _historyEvents.isEmpty
                ? SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          children: [
                            Text(
                              'Chưa có sự kiện nào được ghi lại.',
                              style: TextStyle(color: Colors.white70, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            if (!_isIOS)
                              Text(
                                '(Dữ liệu sẽ được mô phỏng tự động)',
                                style: TextStyle(color: Colors.blue.shade300, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: _buildEventTile(_historyEvents[index]),
                        );
                      },
                      childCount: _historyEvents.length,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}