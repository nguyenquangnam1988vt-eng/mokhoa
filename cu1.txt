// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

void main() {
  runApp(const MyApp());
}

const EventChannel _eventChannel = EventChannel(
  'com.example.app/monitor_events',
);

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

  // 🎯 CÁC TRƯỜNG CHO NETWORK DETECTION
  final bool? isActiveBrowsing;
  final String? activityType;

  // 📞 THÊM TRƯỜNG CHO CALL DETECTION
  final bool? isInCall;
  final String? callState;
  final double? callDuration;

  // 📞 THÊM TRƯỜNG CHO VOIP CALL DETECTION
  final bool? isVoIPCall;
  final String? callType;

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
    this.activityType,
    this.isInCall,
    this.callState,
    this.callDuration,
    this.isVoIPCall,
    this.callType,
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
      activityType: json['activityType'] as String?,
      isInCall: json['isInCall'] as bool?,
      callState: json['callState'] as String?,
      callDuration: json['callDuration'] as double?,
      isVoIPCall: json['isVoIPCall'] as bool?,
      callType: json['callType'] as String?,
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
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1F1F1F)),
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
  String _activityType = "";

  // 📞 THÊM BIẾN CHO CALL DETECTION
  bool _isInCall = false;
  double _callDuration = 0.0;

  // 📞 THÊM BIẾN CHO VOIP CALL DETECTION
  bool _isInVoIPCall = false;
  String _voipCallType = "";

  // 🎯 Lưu trữ lịch sử tilt để tính trung bình 3s
  final List<double> _tiltHistory = [];
  static const int _tiltBufferSize = 30;
  double _averageTiltPercent = 0.0;

  // 🎯 Biến lưu trạng thái tilt hiện tại (đồng bộ)
  String _currentTiltStatus = "Chờ dữ liệu...";
  Color _currentTiltColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _startListeningToEvents();
  }

  void _startListeningToEvents() {
    _eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: _onError,
      onDone: _onDone,
    );
  }

  // 🎯 Hàm tính tilt trung bình 3s
  void _updateTiltAverage(double tiltPercent) {
    _tiltHistory.add(tiltPercent);
    if (_tiltHistory.length > _tiltBufferSize) {
      _tiltHistory.removeAt(0);
    }

    if (_tiltHistory.isNotEmpty) {
      _averageTiltPercent =
          _tiltHistory.reduce((a, b) => a + b) / _tiltHistory.length;
    }

    _currentTiltStatus = _getTiltStatus(_averageTiltPercent);
    _currentTiltColor = _getTiltColor(_averageTiltPercent);
  }

  // 🎯 Hàm xác định trạng thái tilt theo ngưỡng mới (80%-90%)
  String _getTiltStatus(double tiltPercent) {
    if (tiltPercent <= 80.0) {
      return "📱 ĐANG XEM";
    } else if (tiltPercent < 90.0) {
      return "⚡ TRUNG GIAN";
    } else {
      return "🔼 KHÔNG XEM";
    }
  }

  // 🎯 Hàm xác định màu sắc theo trạng thái tilt mới
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
    setState(() {
      _connectionStatus = "Đã kết nối";
      try {
        final Map<String, dynamic> data = jsonDecode(event as String);
        final monitorEvent = MonitorEvent.fromJson(data);

        // 📞 XỬ LÝ SỰ KIỆN CUỘC GỌI DI ĐỘNG
        if (monitorEvent.type == 'CALL_EVENT') {
          bool wasInCall = _isInCall; // 🆕 Lưu trạng thái cũ
          _isInCall = monitorEvent.isInCall ?? false;
          _callDuration = monitorEvent.callDuration ?? 0.0;

          // 🆕 RESET KHI CUỘC GỌI KẾT THÚC
          if (wasInCall && !_isInCall) {
            _callDuration = 0.0;
          }

          _historyEvents.insert(0, monitorEvent);
          print(
            "📞 Call Event: ${monitorEvent.message} | InCall: $_isInCall | Duration: $_callDuration",
          );
        }
        // 📞 XỬ LÝ SỰ KIỆN CUỘC GỌI VOIP (ZALO/FACEBOOK)
        else if (monitorEvent.type == 'VOIP_CALL_EVENT') {
          bool wasInVoIPCall = _isInVoIPCall; // 🆕 Lưu trạng thái cũ
          _isInVoIPCall = monitorEvent.isVoIPCall ?? false;
          _voipCallType = monitorEvent.callType ?? "";

          // 🆕 RESET KHI CUỘC GỌI KẾT THÚC
          if (wasInVoIPCall && !_isInVoIPCall) {
            _voipCallType = "";
          }

          _historyEvents.insert(0, monitorEvent);
          print(
            "📱 VoIP Call Event: ${monitorEvent.message} | InCall: $_isInVoIPCall | Type: $_voipCallType",
          );
        } else if (monitorEvent.type == 'TILT_EVENT') {
          _latestTiltEvent = monitorEvent;
          if (monitorEvent.tiltPercent != null) {
            _updateTiltAverage(monitorEvent.tiltPercent!);
          }
          // 🎯 Cập nhật trạng thái web browsing
          if (monitorEvent.isActiveBrowsing != null) {
            _isActiveBrowsing = monitorEvent.isActiveBrowsing!;
          }
          // 📞 Cập nhật trạng thái call từ tilt event
          if (monitorEvent.isInCall != null) {
            bool wasInCall = _isInCall; // 🆕 Lưu trạng thái cũ
            _isInCall = monitorEvent.isInCall!;

            // 🆕 RESET KHI CUỘC GỌI KẾT THÚC
            if (wasInCall && !_isInCall) {
              _callDuration = 0.0;
            }
          }
          // 🆕 CẬP NHẬT VOIP TỪ TILT EVENT
          if (monitorEvent.isVoIPCall != null) {
            bool wasInVoIPCall = _isInVoIPCall; // 🆕 Lưu trạng thái cũ
            _isInVoIPCall = monitorEvent.isVoIPCall!;

            // 🆕 RESET KHI CUỘC GỌI KẾT THÚC
            if (wasInVoIPCall && !_isInVoIPCall) {
              _voipCallType = "";
            }
          }
        } else if (monitorEvent.type == 'DANGER_EVENT') {
          _latestDangerEvent = monitorEvent;
          _historyEvents.insert(0, monitorEvent);
        } else if (monitorEvent.type == 'NETWORK_STATUS') {
          _isNetworkActive = monitorEvent.isNetworkActive ?? false;
          _historyEvents.insert(0, monitorEvent);
        }
        // 🎯 XỬ LÝ SỰ KIỆN NETWORK ANALYSIS
        else if (monitorEvent.type == 'NETWORK_ANALYSIS') {
          _isActiveBrowsing = monitorEvent.isActiveBrowsing ?? false;
          _historyEvents.insert(0, monitorEvent);
        }
        // 🆚 XỬ LÝ SỰ KIỆN REAL NETWORK ANALYSIS MỚI
        else if (monitorEvent.type == 'REAL_NETWORK_ANALYSIS') {
          _isActiveBrowsing = monitorEvent.isActiveBrowsing ?? false;
          _activityType = monitorEvent.activityType ?? "";
          _historyEvents.insert(0, monitorEvent);
          print("🌐 Real Network Event: ${monitorEvent.message}");
        } else if (monitorEvent.type == 'DRIVING_STATUS' ||
            monitorEvent.type == 'LOCATION_UPDATE') {
          _currentSpeed = monitorEvent.speed ?? 0.0;
          _isDriving = monitorEvent.isDriving ?? false;
          _historyEvents.insert(0, monitorEvent);
        } else if (monitorEvent.type == 'SPEED_UPDATE') {
          _currentSpeed = monitorEvent.speed ?? 0.0;
          _isDriving = monitorEvent.isDriving ?? false;
        } else {
          _historyEvents.insert(0, monitorEvent);
        }

        // 🆕 DEBUG LOG ĐỂ KIỂM TRA
        print("""
  📊 STATE UPDATE:
    isInCall: $_isInCall (duration: $_callDuration)
    isInVoIPCall: $_isInVoIPCall (type: $_voipCallType)
    anyCallActive: ${_isInCall || _isInVoIPCall}
  """);
      } catch (e) {
        _connectionStatus = "Lỗi phân tích JSON: $e";
        print('Error decoding JSON: $e, Raw event: $event');
      }
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

  Widget _buildDangerAlertCard() {
    if (_latestDangerEvent == null) return const SizedBox.shrink();

    String dangerType = "";
    if (_latestDangerEvent!.isActiveBrowsing == true) {
      dangerType = "LƯỚT WEB";
    } else if (_latestDangerEvent!.isInCall == true &&
        _latestDangerEvent!.isVoIPCall != true) {
      dangerType = "GỌI ĐIỆN THOẠI";
    } else if (_latestDangerEvent!.isVoIPCall == true) {
      dangerType = "GỌI ZALO/FACEBOOK";
    } else {
      dangerType = "SỬ DỤNG ĐIỆN THOẠI"; // 🆕 THÊM DÒNG NÀY
    }

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
                    'CẢNH BÁO NGUY HIỂM - $dangerType',
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
                'Tilt: ${_latestDangerEvent!.tiltPercent!.toStringAsFixed(1)}% | Web: ${_isActiveBrowsing ? "Đang lướt" : "Không lướt"}${_activityType.isNotEmpty ? " • $_activityType" : ""}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            if (_latestDangerEvent!.isInCall == true &&
                _latestDangerEvent!.isVoIPCall != true)
              Text(
                '📞 Đang nghe điện thoại: ${_callDuration.toStringAsFixed(0)} giây',
                style: const TextStyle(
                  color: Colors.yellow,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (_latestDangerEvent!.isVoIPCall == true)
              Text(
                '📱 Đang gọi Zalo/Facebook: ${_voipCallType.isNotEmpty ? _voipCallType : "Đang gọi"}',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 📞 CARD HIỂN THỊ TRẠNG THÁI TẤT CẢ CUỘC GỌI
  Widget _buildCallStatusCard() {
    final bool anyCallActive = _isInCall || _isInVoIPCall;
    final String callStatus = anyCallActive
        ? (_isInVoIPCall ? "ĐANG GỌI ZALO/FACEBOOK" : "ĐANG GỌI ĐIỆN THOẠI")
        : "KHÔNG CÓ CUỘC GỌI";

    final Color cardColor = anyCallActive
        ? Colors.red.shade900
        : Colors.green.shade900;
    final IconData callIcon = anyCallActive
        ? (_isInVoIPCall ? Icons.video_call : Icons.phone_in_talk)
        : Icons.phone_disabled;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(callIcon, color: Colors.white, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    callStatus,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (anyCallActive) ...[
              const SizedBox(height: 8),
              if (_isInCall)
                Text(
                  'Thời gian gọi: ${_callDuration.toStringAsFixed(0)} giây',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              if (_isInVoIPCall)
                Text(
                  'Loại gọi: ${_voipCallType.replaceAll("voip_", "").toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'CẢNH BÁO: Không nghe/gọi điện thoại khi đang lái xe',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.yellow,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'An toàn - không có cuộc gọi nào',
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDrivingStatusCard() {
    final bool anyCallActive = _isInCall || _isInVoIPCall;

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
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            if (_isDriving && anyCallActive) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.yellow, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'NGUY HIỂM: Đang lái xe và ${_isInVoIPCall ? "GỌI ZALO/FACEBOOK" : "NGHE ĐIỆN THOẠI"}!',
                        style: TextStyle(
                          color: Colors.yellow,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
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
                    _averageTiltPercent <= 80.0
                        ? Icons.warning
                        : _averageTiltPercent < 90.0
                        ? Icons.info
                        : Icons.check_circle,
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

            // 🎯 HIỂN THỊ THÔNG TIN MẠNG CHI TIẾT
            const SizedBox(height: 12),
            const Divider(color: Colors.white10),
            const Text(
              '📊 Phân Tích Mạng Thực Tế:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),

            // 🆚 HIỂN THỊ ACTIVITY TYPE NẾU CÓ
            if (_activityType.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  'Loại hoạt động: $_activityType',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue.shade300,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildNetworkInfoItem(
                        'Mạng:',
                        _isNetworkActive ? "📶 Đang kết nối" : "📵 Mất kết nối",
                        _isNetworkActive
                            ? Colors.green.shade400
                            : Colors.red.shade400,
                      ),
                      _buildNetworkInfoItem(
                        'Web:',
                        _isActiveBrowsing
                            ? "🌐 Đang lướt web"
                            : "💤 Không lướt web",
                        _isActiveBrowsing
                            ? Colors.blue.shade400
                            : Colors.grey.shade400,
                      ),
                      _buildNetworkInfoItem(
                        'Gọi di động:',
                        _isInCall ? "📞 Đang gọi" : "📵 Không gọi",
                        _isInCall ? Colors.red.shade400 : Colors.green.shade400,
                      ),
                      _buildNetworkInfoItem(
                        'Gọi Zalo/FB:',
                        _isInVoIPCall ? "📱 Đang gọi" : "📵 Không gọi",
                        _isInVoIPCall
                            ? Colors.orange.shade400
                            : Colors.green.shade400,
                      ),
                    ],
                  ),
                ),
                // 🎯 HIỂN THỊ TRẠNG THÁI REAL-TIME DETECTION
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _isActiveBrowsing
                            ? Colors.blue.withOpacity(0.2)
                            : Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isActiveBrowsing ? Colors.blue : Colors.green,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _isActiveBrowsing ? 'WEB' : 'NO WEB',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isActiveBrowsing ? Colors.blue : Colors.green,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _isInCall
                            ? Colors.red.withOpacity(0.2)
                            : Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isInCall ? Colors.red : Colors.green,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _isInCall ? 'CALL' : 'NO CALL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isInCall ? Colors.red : Colors.green,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _isInVoIPCall
                            ? Colors.orange.withOpacity(0.2)
                            : Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isInVoIPCall ? Colors.orange : Colors.green,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _isInVoIPCall ? 'VOIP' : 'NO VOIP',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isInVoIPCall ? Colors.orange : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (_latestTiltEvent != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Cập nhật: ${_latestTiltEvent!.timestamp.toString().substring(11, 19)}',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkInfoItem(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final bool anyCallActive = _isInCall || _isInVoIPCall;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        border: Border(bottom: BorderSide(color: Colors.white12, width: 1)),
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
                  _averageTiltPercent <= 80.0
                      ? Icons.phone_android
                      : _averageTiltPercent < 90.0
                      ? Icons.phone_iphone
                      : Icons.phone_disabled,
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
              color: _isDriving
                  ? Colors.orange.withOpacity(0.2)
                  : Colors.green.withOpacity(0.2),
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
              color: _isActiveBrowsing
                  ? Colors.blue.withOpacity(0.2)
                  : Colors.grey.withOpacity(0.2),
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

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: anyCallActive
                  ? Colors.red.withOpacity(0.2)
                  : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: anyCallActive ? Colors.red : Colors.grey,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  anyCallActive ? Icons.phone : Icons.phone_disabled,
                  color: anyCallActive ? Colors.red : Colors.grey,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  anyCallActive ? 'CALL' : 'NO CALL',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: anyCallActive ? Colors.red : Colors.grey,
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
    String subtitle =
        'Thời gian: ${event.timestamp.toString().substring(0, 19)}';

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
          subtitle +=
              '\nWeb: ${event.isActiveBrowsing! ? "Đang lướt" : "Không lướt"}';
        }
        if (event.isInCall == true && event.isVoIPCall != true) {
          subtitle += '\n📞 Đang nghe điện thoại';
        }
        if (event.isVoIPCall == true) {
          subtitle += '\n📱 Đang gọi Zalo/Facebook';
        }
        break;

      case 'DRIVING_STATUS':
        eventColor = event.isDriving == true
            ? Colors.orange.shade400
            : Colors.blue.shade400;
        icon = event.isDriving == true ? Icons.directions_car : Icons.person;
        if (event.speed != null) {
          subtitle += '\nTốc độ: ${event.speed!.toStringAsFixed(1)} km/h';
        }
        break;

      case 'NETWORK_STATUS':
        eventColor = event.isNetworkActive == true
            ? Colors.green.shade400
            : Colors.red.shade400;
        icon = event.isNetworkActive == true ? Icons.wifi : Icons.wifi_off;
        subtitle += '\nTrạng thái mạng';
        break;

      // 🎯 CASE: Network Analysis
      case 'NETWORK_ANALYSIS':
        eventColor = event.isActiveBrowsing == true
            ? Colors.blue.shade400
            : Colors.grey.shade400;
        icon = event.isActiveBrowsing == true
            ? Icons.network_check
            : Icons.network_wifi;
        subtitle +=
            '\nTrạng thái: ${event.isActiveBrowsing! ? "Đang lướt web" : "Không lướt web"}';
        break;

      // 🆚 CASE MỚI: Real Network Analysis
      case 'REAL_NETWORK_ANALYSIS':
        eventColor = event.isActiveBrowsing == true
            ? Colors.purple.shade400
            : Colors.grey.shade400;
        icon = event.isActiveBrowsing == true
            ? Icons.network_ping
            : Icons.network_wifi;
        subtitle +=
            '\nPhát hiện thực tế: ${event.activityType ?? "Không xác định"}';
        break;

      // 📞 CASE MỚI: Call Event
      case 'CALL_EVENT':
        eventColor = event.isInCall == true
            ? Colors.red.shade400
            : Colors.green.shade400;
        icon = event.isInCall == true
            ? Icons.phone_in_talk
            : Icons.phone_disabled;
        subtitle +=
            '\nTrạng thái: ${event.isInCall! ? "Đang gọi" : "Không gọi"}';
        if (event.callDuration != null) {
          subtitle += '\nThời gian: ${event.callDuration!.toStringAsFixed(0)}s';
        }
        break;

      // 📞 CASE MỚI: VoIP Call Event
      case 'VOIP_CALL_EVENT':
        eventColor = event.isVoIPCall == true
            ? Colors.orange.shade400
            : Colors.green.shade400;
        icon = event.isVoIPCall == true ? Icons.video_call : Icons.videocam_off;
        subtitle +=
            '\nTrạng thái: ${event.isVoIPCall! ? "Đang gọi Zalo/FB" : "Không gọi"}';
        if (event.callType != null) {
          subtitle += '\nLoại: ${event.callType!.replaceAll("voip_", "")}';
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        leading: Icon(icon, color: eventColor, size: 32),
        title: Text(
          event.message,
          style: TextStyle(fontWeight: FontWeight.bold, color: eventColor),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool anyCallActive = _isInCall || _isInVoIPCall;

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
                  'Kết nối: $_connectionStatus | Tilt: ${_averageTiltPercent.toStringAsFixed(1)}% | Tốc độ: ${_currentSpeed.toStringAsFixed(1)} km/h | Web: ${_isActiveBrowsing ? "Đang lướt" : "Không lướt"} | Gọi: ${anyCallActive ? "Đang gọi" : "Không gọi"}${_activityType.isNotEmpty ? " • $_activityType" : ""}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
      body: CustomScrollView(
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
              child: _buildCallStatusCard(),
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
              child: _buildTiltMonitorCard(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 10.0,
                bottom: 8.0,
              ),
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
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: _buildEventTile(_historyEvents[index]),
                    );
                  }, childCount: _historyEvents.length),
                ),
        ],
      ),
    );
  }
}
