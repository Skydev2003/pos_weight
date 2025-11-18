import 'dart:async';
import 'package:flutter/services.dart';
import '../models/weight_reading.dart';

/// บริการสำหรับสื่อสารกับเครื่องชั่งผ่าน USB Serial
/// จัดการการตรวจจับและเชื่อมต่ออุปกรณ์อัตโนมัติ
class SerialScaleService {
  static const MethodChannel _channel = MethodChannel('pos_weight/serial');
  static const EventChannel _usbEventChannel = EventChannel(
    'pos_weight/usb_events',
  );

  Stream<String>? _usbEventStream;

  // แคชสถานะการเชื่อมต่อเพื่อลดการเรียก platform channel
  bool _isConnectedCache = false;
  DateTime? _lastConnectionCheck;
  static const _connectionCacheDuration = Duration(milliseconds: 500);

  /// Stream สำหรับรับเหตุการณ์การเชื่อมต่อ USB
  /// ส่งค่า 'connected' เมื่อเสียบ USB
  /// ส่งค่า 'disconnected' เมื่อถอด USB
  Stream<String> get usbEvents {
    _usbEventStream ??= _usbEventChannel.receiveBroadcastStream().map((event) {
      // อัพเดทแคชเมื่อมีเหตุการณ์ USB
      final eventStr = event.toString();
      _isConnectedCache = eventStr == 'connected';
      _lastConnectionCheck = DateTime.now();
      return eventStr;
    });
    return _usbEventStream!;
  }

  /// ตรวจจับและเชื่อมต่อกับเครื่องชั่ง USB อัตโนมัติ
  /// คืนค่า true ถ้าพบอุปกรณ์และเชื่อมต่อสำเร็จ
  Future<bool> autoConnect() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('autoConnect');
      _isConnectedCache = result ?? false;
      _lastConnectionCheck = DateTime.now();
      return _isConnectedCache;
    } on PlatformException {
      // เชื่อมต่ออัตโนมัติล้มเหลว ไม่พบอุปกรณ์
      _isConnectedCache = false;
      _lastConnectionCheck = DateTime.now();
      return false;
    }
  }

  /// อ่านค่าน้ำหนักจากเครื่องชั่ง USB ที่เชื่อมต่ออยู่
  /// ต้องเชื่อมต่ออุปกรณ์ผ่าน autoConnect() ก่อน
  ///
  /// คืนค่า [WeightReading] พร้อมข้อมูลน้ำหนักที่แปลงแล้ว
  /// โยน [PlatformException] เมื่อเกิดข้อผิดพลาดในการสื่อสาร
  Future<WeightReading> readWeight() async {
    try {
      // เรียก native method โดยตรง ไม่ต้องตรวจสอบการเชื่อมต่อก่อน
      // เพื่อลดความดีเลย์
      final Map<String, dynamic>? response = await _channel
          .invokeMapMethod<String, dynamic>('readWeight');

      if (response == null) {
        _isConnectedCache = false; // อัพเดทแคชเมื่อไม่ได้รับข้อมูล
        throw PlatformException(
          code: 'empty_response',
          message: 'ไม่ได้รับข้อมูลจากเครื่องชั่ง',
        );
      }

      return WeightReading.fromMap(response);
    } on PlatformException catch (e) {
      // อัพเดทแคชเมื่อเกิดข้อผิดพลาด
      if (e.code == 'not_connected' || e.code == 'device_disconnected') {
        _isConnectedCache = false;
        _lastConnectionCheck = DateTime.now();
      }
      rethrow;
    } catch (e) {
      throw PlatformException(
        code: 'unknown_error',
        message: 'อ่านค่าน้ำหนักล้มเหลว: $e',
      );
    }
  }

  /// ตัดการเชื่อมต่อจากเครื่องชั่ง USB
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod<void>('disconnect');
      _isConnectedCache = false;
      _lastConnectionCheck = DateTime.now();
    } on PlatformException {
      // ตัดการเชื่อมต่อล้มเหลว ไม่ต้องทำอะไร
      _isConnectedCache = false;
    }
  }

  /// ตรวจสอบว่าเครื่องชั่ง USB เชื่อมต่ออยู่หรือไม่
  /// ใช้แคชเพื่อลดการเรียก platform channel และเพิ่มความเร็ว
  Future<bool> isConnected() async {
    // ใช้แคชถ้ายังไม่หมดอายุ
    final now = DateTime.now();
    if (_lastConnectionCheck != null &&
        now.difference(_lastConnectionCheck!) < _connectionCacheDuration) {
      return _isConnectedCache;
    }

    // ตรวจสอบจริงถ้าแคชหมดอายุ
    try {
      final bool? result = await _channel.invokeMethod<bool>('isConnected');
      _isConnectedCache = result ?? false;
      _lastConnectionCheck = now;
      return _isConnectedCache;
    } on PlatformException {
      _isConnectedCache = false;
      _lastConnectionCheck = now;
      return false;
    }
  }

  /// ล้างแคชการเชื่อมต่อ (ใช้เมื่อต้องการบังคับตรวจสอบใหม่)
  void clearConnectionCache() {
    _lastConnectionCheck = null;
  }
}
