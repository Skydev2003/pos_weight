import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WeightHomePage(),
    );
  }
}

class WeightHomePage extends StatefulWidget {
  const WeightHomePage({super.key});

  @override
  State<WeightHomePage> createState() => _WeightHomePageState();
}

class _WeightHomePageState extends State<WeightHomePage> {
  late final TextEditingController _portController;
  late final TextEditingController _baudController;
  final SerialScaleService _service = SerialScaleService();

  Timer? _timer;
  bool _isPolling = false;
  bool _isBusy = false;
  WeightReading? _reading;
  String? _error;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(text: _initialPortValue());
    _baudController = TextEditingController(text: '9600');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _portController.dispose();
    _baudController.dispose();
    super.dispose();
  }

  void _togglePolling() {
    if (_isPolling) {
      _timer?.cancel();
      setState(() {
        _isPolling = false;
      });
      return;
    }

    setState(() {
      _isPolling = true;
      _error = null;
    });

    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      _fetchReading();
    });
    _fetchReading();
  }

  Future<void> _fetchReading() async {
    final String port = _portController.text.trim();
    final int? baud = int.tryParse(_baudController.text.trim());
    final bool portRequired = _portRequiredOnThisPlatform;
    final String? portArgument =
        portRequired ? port : (port.isNotEmpty ? port : null);

    if ((portRequired && (portArgument == null || portArgument.isEmpty)) ||
        baud == null) {
      setState(() {
        _error = portRequired
            ? 'กรุณาระบุพอร์ตและ Baud rate ให้ถูกต้อง'
            : 'กรุณาระบุ Baud rate ให้ถูกต้อง';
        _reading = null;
      });
      return;
    }

    if (_isBusy) {
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      final WeightReading next = await _service.read(
        port: portArgument,
        baudRate: baud,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _reading = next;
        _error = null;
      });
    } on PlatformException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.message ?? 'เกิดข้อผิดพลาดไม่ทราบสาเหตุ';
        _reading = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.toString();
        _reading = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool portRequired = _portRequiredOnThisPlatform;
    return Scaffold(
      appBar: AppBar(
        title: const Text('USB Scale Monitor'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _portController,
                    decoration: InputDecoration(
                      labelText: portRequired
                          ? 'Serial Port (เช่น COM3)'
                          : 'ตัวเลือก (ใช้เมื่อมีหลายอุปกรณ์)',
                      helperText: portRequired
                          ? 'ระบุชื่อพอร์ต Serial บน Windows/Linux'
                          : 'Android จะค้นหาอัตโนมัติ ปล่อยว่างได้',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _baudController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Baud rate',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _togglePolling,
                  icon: Icon(_isPolling ? Icons.stop : Icons.play_arrow),
                  label: Text(_isPolling ? 'หยุดอ่านค่าน้ำหนัก' : 'เริ่มอ่าน'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _isBusy ? null : _fetchReading,
                  child: const Text('อ่านทันที'),
                ),
                if (_isBusy) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: _buildReadingCard(),
              ),
            ),
            if (_error != null) ...[
              const Divider(),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReadingCard() {
    if (_reading == null) {
      return const Text(
        'ยังไม่มีข้อมูลจากเครื่องชั่ง',
        style: TextStyle(fontSize: 18),
      );
    }

    final WeightReading reading = _reading!;
    final String weightText =
        reading.value != null ? reading.value!.toStringAsFixed(2) : '--';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'น้ำหนักปัจจุบัน',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              weightText,
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'ข้อมูลดิบ: ${reading.raw}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Text(
              'พอร์ต: ${reading.port}',
              style: const TextStyle(color: Colors.black54),
            ),
            Text(
              'เวลา: ${reading.timestampFormatted}',
              style: const TextStyle(color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  bool get _portRequiredOnThisPlatform {
    if (kIsWeb) {
      return false;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  String _initialPortValue() {
    return _portRequiredOnThisPlatform ? 'COM3' : '';
  }
}

class SerialScaleService {
  static const MethodChannel _channel = MethodChannel('pos_weight/serial');

  Future<WeightReading> read({
    String? port,
    int baudRate = 9600,
  }) async {
    final Map<String, dynamic>? response =
        await _channel.invokeMapMethod<String, dynamic>(
      'readWeight',
      <String, dynamic>{
        if (port != null) 'port': port,
        'baudRate': baudRate,
      },
    );

    if (response == null) {
      throw PlatformException(
        code: 'empty_response',
        message: 'ไม่ได้รับข้อมูลจากเครื่องชั่ง',
      );
    }

    return WeightReading.fromMap(response);
  }
}

class WeightReading {
  const WeightReading({
    required this.port,
    required this.raw,
    required this.timestamp,
    this.value,
  });

  factory WeightReading.fromMap(Map<String, dynamic> map) {
    final dynamic rawValue = map['value'];
    double? parsedValue;
    if (rawValue is num) {
      parsedValue = rawValue.toDouble();
    } else if (rawValue is String) {
      parsedValue = double.tryParse(rawValue);
    }

    return WeightReading(
      port: (map['port'] as String?) ?? '',
      raw: (map['raw'] as String?) ?? '',
      timestamp: DateTime.now(),
      value: parsedValue,
    );
  }

  final String port;
  final String raw;
  final DateTime timestamp;
  final double? value;

  String get timestampFormatted =>
      '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}:'
      '${timestamp.second.toString().padLeft(2, '0')}';
}
