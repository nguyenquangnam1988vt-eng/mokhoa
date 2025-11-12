// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:internet_speed_test/internet_speed_test.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

void main() {
  runApp(const MyApp());
}

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

  // 🆕 THÊM: Network info và speed test
  final NetworkInfo _networkInfo = NetworkInfo();
  final InternetSpeedTest _speedTest = InternetSpeedTest();
  String _wifiName = "Unknown";
  String _ipAddress = "Unknown";
  bool _isTestingSpeed = false;
  String _speedTestStatus = "";

  bool _isUpdating = false;

  final List<double> _tiltHistory = [];
  static const int _tiltBufferSize = 30;
  double _averageTiltPercent = 0.0;

  String _currentTiltStatus = "Chờ dữ liệu...";
  Color _currentTiltColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _startListeningToEvents();
    _initializeNetworkInfo();
    _startPeriodicSpeedTest();
  }

  // 🆕 HÀM MỚI: Khởi tạo thông tin mạng
  void _initializeNetworkInfo() async {
    try {
      _wifiName = (await _networkInfo.getWifiName()) ?? "Unknown";
      _ipAddress = (await _networkInfo.getWifiIP()) ?? "Unknown";
      
      final networkData: [String: Any] = [
        "type": "NETWORK_INFO",
        "message": "WiFi: $_wifiName | IP: $_ipAddress",
        "wifiName": _wifiName,
        "ipAddress": _ipAddress,
        "timestamp": DateTime.now().millisecondsSinceEpoch
      ];
      
      _sendEventToFlutter(networkData);
    } catch (e) {
      print("Lỗi lấy thông tin mạng: $e");
    }
  }

  // 🆕 HÀM MỚI: Test tốc độ mạng định kỳ
  void _startPeriodicSpeedTest() {
    // Test tốc độ mỗi 30 giây
    Timer.periodic(Duration(seconds: 30), (timer) {
      if (_isNetworkActive && !_isTestingSpeed) {
        _testInternetSpeed();
      }
    });
  }

  // 🆕 HÀM MỚI: Test tốc độ internet thực tế
  void _testInternetSpeed() {
    setState(() {
      _isTestingSpeed = true;
      _speedTestStatus = "Đang test tốc độ...";
    });

    _speedTest.startDownloadTesting(
      onDone: (double transferRate, SpeedUnit unit) {
        setState(() {
          _networkDownloadSpeed = _convertToKBps(transferRate, unit);
          _isTestingSpeed = false;
          _speedTestStatus = "Download: ${_networkDownloadSpeed.toStringAsFixed(1)} KB/s";
        });
        
        _sendSpeedTestEvent();
      },
      onError: (String errorMessage, String speedTestError) {
        print('Lỗi test download: $errorMessage');
        setState(() {
          _isTestingSpeed = false;
          _speedTestStatus = "Lỗi test tốc độ";
        });
      },
      onProgress: (double percent, double transferRate, SpeedUnit unit) {
        final speed = _convertToKBps(transferRate, unit);
        setState(() {
          _networkDownloadSpeed = speed;
        });
      },
      fileSize: 5000000, // 5MB
    );

    // Test upload sau khi download xong
    Timer(Duration(seconds: 10), () {
      if (_isNetworkActive) {
        _speedTest.startUploadTesting(
          onDone: (double transferRate, SpeedUnit unit) {
            setState(() {
              _networkUploadSpeed = _convertToKBps(transferRate, unit);
              _speedTestStatus = "↑${_networkUploadSpeed.toStringAsFixed(1)} ↓${_networkDownloadSpeed.toStringAsFixed(1)} KB/s";
            });
            _sendSpeedTestEvent();
          },
          onError: (String errorMessage, String speedTestError) {
            print('Lỗi test upload: $errorMessage');
          },
          onProgress: (double percent, double transferRate, SpeedUnit unit) {
            final speed = _convertToKBps(transferRate, unit);
            setState(() {
              _networkUploadSpeed = speed;
            });
          },
          fileSize: 3000000, // 3MB
        );
      }
    });
  }

  // 🆕 HÀM MỚI: Chuyển đổi đơn vị tốc độ sang KB/s
  double _convertToKBps(double rate, SpeedUnit unit) {
    switch (unit) {
      case SpeedUnit.kbps:
        return rate / 8.0; // kbps to KB/s
      case SpeedUnit.mbps:
        return rate * 125.0; // mbps to KB/s (1 mbps = 125 KB/s)
      default:
        return rate;
    }
  }

  // 🆕 HÀM MỚI: Gửi sự kiện tốc độ test
  void _sendSpeedTestEvent() {
    final trafficData = {
      "type": "TRAFFIC_ANALYSIS",
      "message": "Tốc độ mạng thực tế: ↑${_networkUploadSpeed.toStringAsFixed(1)} ↓${_networkDownloadSpeed.toStringAsFixed(1)} KB/s",
      "isActiveBrowsing": _isActiveBrowsing,
      "estimatedWebTraffic": 0.0,
      "estimatedLocationTraffic": 0.0,
      "networkUploadSpeed": _networkUploadSpeed,
      "networkDownloadSpeed": _networkDownloadSpeed,
      "timestamp": DateTime.now().millisecondsSinceEpoch
    };
    
    _sendEventToFlutter(trafficData);
  }

  // 🆕 HÀM MỚI: Gửi sự kiện đến Flutter (cho network info)
  void _sendEventToFlutter(Map<String, dynamic> data) {
    // Giả lập gửi sự kiện - trong thực tế sẽ gửi qua MethodChannel
    print("Network Event: $data");
  }

  void _startListeningToEvents() {
    _eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: _onError,
      onDone: _onDone,
    );
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

  void _onEvent(dynamic event) {
    if (_isUpdating) return;
    _isUpdating = true;
    
    setState(() {
      _connectionStatus = "Đã kết nối";
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
          // 🆕 CẬP NHẬT: Dùng tốc độ thực tế từ speed test, không dùng dữ liệu mô phỏng
          // _networkUploadSpeed = monitorEvent.networkUploadSpeed ?? 0.0;
          // _networkDownloadSpeed = monitorEvent.networkDownloadSpeed ?? 0.0;
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

  // 🆕 HÀM MỚI: Test tốc độ thủ công
  void _manualSpeedTest() {
    _testInternetSpeed();
  }

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
                        'WiFi: $_wifiName',
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                // 🆕 NÚT TEST TỐC ĐỘ
                IconButton(
                  icon: Icon(
                    _isTestingSpeed ? Icons.refresh : Icons.speed,
                    color: _isTestingSpeed ? Colors.orange : Colors.green,
                  ),
                  onPressed: _isTestingSpeed ? null : _manualSpeedTest,
                  tooltip: 'Test tốc độ mạng',
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // 🆕 HIỂN THỊ TỐC ĐỘ THỰC TẾ
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Icon(Icons.upload, 
                         color: _isTestingSpeed ? Colors.orange : Colors.green.shade400, 
                         size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Upload\n${_networkUploadSpeed.toStringAsFixed(1)} KB/s',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: _isTestingSpeed ? Colors.orange : Colors.green.shade400,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Icon(Icons.download, 
                         color: _isTestingSpeed ? Colors.orange : Colors.orange.shade400, 
                         size: 24),
                    const SizedBox(height: 4),
                    Text(
                      'Download\n${_networkDownloadSpeed.toStringAsFixed(1)} KB/s',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: _isTestingSpeed ? Colors.orange : Colors.orange.shade400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // 🆕 TRẠNG THÁI TEST TỐC ĐỘ
            if (_isTestingSpeed)
              LinearProgressIndicator(
                backgroundColor: Colors.grey.shade700,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade400),
              ),
            
            Text(
              _isTestingSpeed ? 'Đang test tốc độ mạng...' : _speedTestStatus,
              style: TextStyle(
                fontSize: 12,
                color: _isTestingSpeed ? Colors.blue.shade300 : Colors.white70,
                fontStyle: _isTestingSpeed ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            
            Text(
              _isActiveBrowsing 
                  ? 'Đang có hoạt động lướt web đáng kể'
                  : 'Không có hoạt động web đáng kể',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
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
                  'Cảm Biến Nghiêng (Gia Tốc Kế)',
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Theo Dõi An Toàn Lái Xe'),
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
                  'Kết nối: $_connectionStatus | Tilt: ${_averageTiltPercent.toStringAsFixed(1)}% | Tốc độ: ${_currentSpeed.toStringAsFixed(1)} km/h | Web: ${_isActiveBrowsing ? "Đang lướt" : "Không lướt"} | ${_isTestingSpeed ? "Đang test tốc độ..." : "↑${_networkUploadSpeed.toStringAsFixed(1)} ↓${_networkDownloadSpeed.toStringAsFixed(1)} KB/s"}',
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
                child: Text(
                  'Lịch Sử Sự Kiện',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
            ),
            _historyEvents.isEmpty
                ? SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text(
                          'Chưa có sự kiện nào được ghi lại.',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                          textAlign: TextAlign.center,
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