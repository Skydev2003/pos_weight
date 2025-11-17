import 'dart:async';
import 'package:flutter/services.dart';
import '../models/weight_reading.dart';

/// Service for communicating with USB serial scale device
/// Handles automatic device detection and communication
class SerialScaleService {
  static const MethodChannel _channel = MethodChannel('pos_weight/serial');
  static const EventChannel _usbEventChannel = EventChannel(
    'pos_weight/usb_events',
  );

  Stream<String>? _usbEventStream;

  /// Stream of USB connection events
  /// Emits 'connected' when USB device is attached
  /// Emits 'disconnected' when USB device is detached
  Stream<String> get usbEvents {
    _usbEventStream ??= _usbEventChannel.receiveBroadcastStream().map(
      (event) => event.toString(),
    );
    return _usbEventStream!;
  }

  /// Automatically detect and connect to USB scale device
  /// Returns true if device found and connected
  Future<bool> autoConnect() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('autoConnect');
      return result ?? false;
    } on PlatformException {
      // Auto-connect failed, device not found
      return false;
    }
  }

  /// Read weight from the connected USB scale
  /// Device must be connected via autoConnect() first
  ///
  /// Returns [WeightReading] with parsed weight data
  /// Throws [PlatformException] on communication errors
  Future<WeightReading> readWeight() async {
    try {
      final Map<String, dynamic>? response = await _channel
          .invokeMapMethod<String, dynamic>('readWeight');

      if (response == null) {
        throw PlatformException(
          code: 'empty_response',
          message: 'No data received from scale device',
        );
      }

      return WeightReading.fromMap(response);
    } on PlatformException {
      rethrow;
    } catch (e) {
      throw PlatformException(
        code: 'unknown_error',
        message: 'Failed to read weight: $e',
      );
    }
  }

  /// Disconnect from the USB scale device
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod<void>('disconnect');
    } on PlatformException {
      // Disconnect failed, ignore error
    }
  }

  /// Check if USB scale device is currently connected
  Future<bool> isConnected() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('isConnected');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }
}
