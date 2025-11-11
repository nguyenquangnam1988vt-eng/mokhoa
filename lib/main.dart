// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final double? speed;
  final bool? isDriving;
  final DateTime timestamp;

  MonitorEvent({
    required this.type,
    required this.message,
    this.location,
    this.tiltValue,
    this.speed,
    this.isDriving,
    required this.timestamp,
  });

  factory MonitorEvent.fromJson(Map<String, dynamic> json) {
    return MonitorEvent(
      type: json['type'] as String,
      message: json['message'] as String,
      location: json['location'] as String?,
      tiltValue: json['tiltValue'] as double?,
      speed: json['speed'] as double?,
      isDriving: json['isDriving'] as bool?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
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

  // 🎯 CẬP NHẬT: Lưu trữ lịch sử tilt để tính trung bình 3s
  final List<double> _tiltHistory = [];
  static const int _tiltBufferSize = 30; // 30 mẫu * 100ms = 3 giây
  double _averageTiltPercent = 0.0;

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

  // 🎯 CẬP NHẬT: Hàm tính tilt trung bình 3s
  void _updateTiltAverage(double tiltRadians) {
    // Chuyển radian sang phần trăm (0-100%)
    double tiltPercent = (tiltRadians.abs() / (pi / 2)) * 100.0;
    tiltPercent = tiltPercent.clamp(0.0, 100.0);

    _tiltHistory.add(tiltPercent);
    if (_tiltHistory.length > _tiltBufferSize) {
      _tiltHistory.removeAt(0);
    }

    // Tính trung bình 3s
    if (_tiltHistory.isNotEmpty) {
      _averageTiltPercent = _tiltHistory.reduce((a, b) => a + b) / _tiltHistory.length;
    }
  }

  // 🎯 CẬP NHẬT: Hàm xác định trạng thái tilt theo ngưỡng mới
  String _getTiltStatus(double tiltPercent) {
    if (tiltPercent <= 55.0) {
      return "📱 ĐANG XEM";
    } else if (tiltPercent < 65.0) {
      return "⚡ TRUNG GIAN";
    } else {
      return "🔼 KHÔNG XEM";
    }
  }

  // 🎯 CẬP NHẬT: Hàm xác định màu sắc theo trạng thái tilt mới
  Color _getTiltColor(double tiltPercent) {
    if (tiltPercent <= 55.0) {
      return Colors.red.shade700; // ĐANG XEM - ĐỎ
    } else if (tiltPercent < 65.0) {
      return Colors.orange.shade700; // TRUNG GIAN - CAM
    } else {
      return Colors.green.shade700; // KHÔNG XEM - XANH
    }
  }

  void _onEvent(dynamic event) {
    setState(() {
      _connectionStatus = "Đã kết nối";
      try {
        final Map<String, dynamic> data = jsonDecode(event as String);
        final monitorEvent = MonitorEvent.fromJson(data);

        if (monitorEvent.type == 'TILT_EVENT') {
          _latestTiltEvent = monitorEvent;
          // Cập nhật tilt trung bình khi có dữ liệu mới
          if (monitorEvent.tiltValue != null) {
            _updateTiltAverage(monitorEvent.tiltValue!);
          }
        } else if (monitorEvent.type == 'DANGER_EVENT') {
          _latestDangerEvent = monitorEvent;
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
            // Hiển thị tilt trung bình khi cảnh báo
            Text(
              'Tilt trung bình: ${_averageTiltPercent.toStringAsFixed(1)}%',
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

  Widget _buildTiltMonitorCard() {
    final double tiltValue = _latestTiltEvent?.tiltValue ?? 0.0;
    final String tiltMessage = _latestTiltEvent?.message ?? 'Chờ dữ liệu...';
    
    // 🎯 CẬP NHẬT: Sử dụng tilt trung bình và ngưỡng mới
    final String tiltStatus = _getTiltStatus(_averageTiltPercent);
    final Color tiltColor = _getTiltColor(_averageTiltPercent);

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
            
            // 🎯 CẬP NHẬT: Hiển thị trạng thái tilt theo ngưỡng mới (không có %)
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
                    _averageTiltPercent <= 55.0 ? Icons.warning : 
                    _averageTiltPercent < 65.0 ? Icons.info : Icons.check_circle,
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
        if (event.tiltValue != null) {
          double tiltPercent = (event.tiltValue!.abs() / (pi / 2)) * 100.0;
          subtitle += '\nTilt: ${tiltPercent.toStringAsFixed(1)}%';
        }
        break;
      
      case 'DRIVING_STATUS':
        eventColor = event.isDriving == true ? Colors.orange.shade400 : Colors.blue.shade400;
        icon = event.isDriving == true ? Icons.directions_car : Icons.person;
        if (event.speed != null) {
          subtitle += '\nTốc độ: ${event.speed!.toStringAsFixed(1)} km/h';
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
          preferredSize: const Size.fromHeight(24.0),
          child: Container(
            color: Colors.white12,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              'Trạng thái kênh: $_connectionStatus | Tilt trung bình: ${_averageTiltPercent.toStringAsFixed(1)}%',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
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
    );
  }
}