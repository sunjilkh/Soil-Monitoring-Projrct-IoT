import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref('sensorData');
  StreamSubscription<DatabaseEvent>? _streamSubscription;
  List<SensorData> _dataHistory = [];
  SensorData? _currentData;
  bool _isLoading = true;
  bool _hasError = false;

  // Notification plugin and debouncing variables
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  DateTime? _lastRainNotification;
  DateTime? _lastTempNotification;
  static const Duration _notificationCooldown = Duration(minutes: 5); // 5-minute cooldown

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _initFirebase();
  }

  // Initialize notifications
  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Request notification permission for Android 13+
    if (Platform.isAndroid) {
      final bool? granted = await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      if (granted != null && !granted) {
        print("Notification permission not granted");
      }
    }
  }

  // Show notification
  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'sensor_channel',
      'Sensor Alerts',
      channelDescription: 'Notifications for sensor alerts',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  Future<void> _initFirebase() async {
    try {
      final initialData = await _databaseRef.limitToLast(1).once();
      
      if (initialData.snapshot.value != null) {
        _processData(initialData.snapshot);
      }

      _streamSubscription = _databaseRef.limitToLast(20).onValue.listen((event) {
        _processData(event.snapshot);
      }, onError: (error) {
        print("Firebase Error: $error");
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      });
    } catch (e) {
      print("Initialization Error: $e");
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  void _processData(DataSnapshot snapshot) {
    try {
      final dynamic data = snapshot.value;
      print("Processing Data: $data");

      if (data != null) {
        final Map<dynamic, dynamic> values = data as Map<dynamic, dynamic>;
        final List<SensorData> tempList = [];

        values.forEach((key, value) {
          try {
            final sensorData = SensorData.fromMap(
              value as Map<dynamic, dynamic>,
              key.toString(),
            );
            tempList.add(sensorData);
          } catch (e) {
            print("Data Parsing Error: $e");
          }
        });

        if (tempList.isNotEmpty) {
          setState(() {
            _dataHistory = tempList;
            _currentData = tempList.last;
            _isLoading = false;
            _hasError = false;

            // Check for rain < 2000
            if (_currentData?.rain != null &&
                _currentData!.rain! < 2000 &&
                (_lastRainNotification == null ||
                    DateTime.now().difference(_lastRainNotification!) >
                        _notificationCooldown)) {
              _showNotification(
                'বৃষ্টিপাত সনাক্ত!',
                'বৃষ্টিপাতের পরিমাণ: ${_currentData!.rain} (2000 এর কম)',
              );
              _lastRainNotification = DateTime.now();
            }

            // Check for airTemp > 35.0
            if (_currentData?.airTemp != null &&
                _currentData!.airTemp! > 35.0 &&
                (_lastTempNotification == null ||
                    DateTime.now().difference(_lastTempNotification!) >
                        _notificationCooldown)) {
              _showNotification(
                'উচ্চ তাপমাত্রা সতর্কতা!',
                'বায়ুর তাপমাত্রা ${_currentData!.airTemp!.toStringAsFixed(1)}°C (35°C এর বেশি)',
              );
              _lastTempNotification = DateTime.now();
            }
          });
        }
      }
    } catch (e) {
      print("Processing Error: $e");
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('সেন্সর ড্যাশবোর্ড'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
              _initFirebase();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ডেটা লোড করতে সমস্যা হয়েছে'),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
                _initFirebase();
              },
              child: const Text('আবার চেষ্টা করুন'),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: SpinKitFadingCircle(
          color: Colors.blue,
          size: 50.0,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _initFirebase();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurrentDataCard(),
            const SizedBox(height: 20),
            _buildChart('বায়ুর তাপমাত্রা (°C)', 'airTemp', Colors.red),
            const SizedBox(height: 20),
            _buildChart('বায়ুর আর্দ্রতা (%)', 'airHumidity', Colors.blue),
            const SizedBox(height: 20),
            _buildChart('মাটির তাপমাত্রা (°C)', 'soilTemp', Colors.orange),
            const SizedBox(height: 20),
            _buildChart('মাটির আর্দ্রতা', 'soilMoisture', Colors.green),
            const SizedBox(height: 20),
            _buildChart('বৃষ্টিপাত', 'rain', Colors.indigo),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentDataCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'বর্তমান রিডিং',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDataTile(
                  'বায়ু তাপ',
                  '${_currentData?.airTemp?.toStringAsFixed(1) ?? '--'}°C',
                  Icons.thermostat,
                  Colors.red,
                ),
                _buildDataTile(
                  'বায়ু আর্দ্রতা',
                  '${_currentData?.airHumidity?.toStringAsFixed(1) ?? '--'}%',
                  Icons.water_drop,
                  Colors.blue,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDataTile(
                  'মাটি তাপ',
                  '${_currentData?.soilTemp?.toStringAsFixed(1) ?? '--'}°C',
                  Icons.grass,
                  Colors.orange,
                ),
                _buildDataTile(
                  'মাটি আর্দ্রতা',
                  _currentData?.soilMoisture?.toString() ?? '--',
                  Icons.water,
                  Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDataTile(
              'শেষ আপডেট',
              DateFormat('HH:mm:ss').format(_currentData?.timestamp ?? DateTime.now()),
              Icons.access_time,
              Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTile(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, size: 30, color: color),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 14)),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildChart(String title, String dataField, Color color) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 250,
              child: SfCartesianChart(
                primaryXAxis: DateTimeAxis(
                  title: AxisTitle(text: 'সময়'),
                  intervalType: DateTimeIntervalType.seconds,
                  dateFormat: DateFormat.Hms(),
                ),
                primaryYAxis: NumericAxis(
                  title: AxisTitle(text: title.split(' ')[0]),
                ),
                series: <CartesianSeries>[
                  LineSeries<SensorData, DateTime>(
                    dataSource: _dataHistory,
                    xValueMapper: (SensorData data, _) => data.timestamp,
                    yValueMapper: (SensorData data, _) => _getYValue(data, dataField),
                    color: color,
                    name: title,
                    markerSettings: const MarkerSettings(isVisible: true),
                  )
                ],
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  builder: (dynamic data, dynamic _, dynamic series, int pointIndex, int seriesIndex) {
                    final sensorData = data as SensorData;
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$title: ${_getYValue(sensorData, dataField).toStringAsFixed(1)}'),
                          Text('সময়: ${DateFormat('HH:mm:ss').format(sensorData.timestamp)}'),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getYValue(SensorData data, String dataField) {
    switch (dataField) {
      case 'airTemp':
        return data.airTemp ?? 0.0;
      case 'airHumidity':
        return data.airHumidity ?? 0.0;
      case 'soilTemp':
        return data.soilTemp ?? 0.0;
      case 'soilMoisture':
        return data.soilMoisture?.toDouble() ?? 0.0;
      case 'rain':
        return data.rain?.toDouble() ?? 0.0;
      default:
        return 0.0;
    }
  }
}

class SensorData {
  final String id;
  final double? airTemp;
  final double? airHumidity;
  final double? soilTemp;
  final int? soilMoisture;
  final int? rain;
  final DateTime timestamp;

  SensorData({
    required this.id,
    this.airTemp,
    this.airHumidity,
    this.soilTemp,
    this.soilMoisture,
    this.rain,
    required this.timestamp,
  });

  factory SensorData.fromMap(Map<dynamic, dynamic> map, String id) {
    return SensorData(
      id: id,
      airTemp: _parseDouble(map['airTemp']),
      airHumidity: _parseDouble(map['airHumidity']),
      soilTemp: _parseDouble(map['soilTemp']),
      soilMoisture: _parseInt(map['soilMoisture']),
      rain: _parseInt(map['rain']),
      timestamp: _parseTimestamp(map['timestamp']),
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime _parseTimestamp(dynamic value) {
    try {
      if (value is String) return DateTime.parse(value);
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    } catch (e) {
      print("Timestamp parsing error: $e");
    }
    return DateTime.now();
  }

  @override
  String toString() {
    return 'SensorData($id): '
        'airTemp=$airTemp, '
        'airHumidity=$airHumidity, '
        'soilTemp=$soilTemp, '
        'soilMoisture=$soilMoisture, '
        'rain=$rain, '
        'timestamp=${DateFormat('HH:mm:ss').format(timestamp)}';
  }
}