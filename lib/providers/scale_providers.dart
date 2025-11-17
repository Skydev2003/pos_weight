import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/connection_status.dart';
import '../models/weight_reading.dart';
import '../services/serial_scale_service.dart';

/// Provider for the serial scale service instance
final serialScaleServiceProvider = Provider<SerialScaleService>((ref) {
  return SerialScaleService();
});

/// Provider for connection status
final connectionStatusProvider = StateProvider<ConnectionStatus>((ref) {
  return ConnectionStatus.disconnected;
});

/// Provider for the latest weight reading
final weightReadingProvider = StateProvider<WeightReading?>((ref) => null);

/// Provider for error messages
final errorMessageProvider = StateProvider<String?>((ref) => null);

/// Provider for auto-start preference
final autoStartProvider = StateProvider<bool>((ref) => true);

/// Controller for managing scale operations with automatic USB detection
class ScaleController extends StateNotifier<AsyncValue<void>> {
  ScaleController(this.ref) : super(const AsyncValue.data(null)) {
    _initialize();
  }

  final Ref ref;
  Timer? _pollingTimer;
  StreamSubscription<String>? _usbEventSubscription;
  bool _isDisposed = false;

  /// Initialize USB event monitoring
  void _initialize() {
    final service = ref.read(serialScaleServiceProvider);

    // Listen to USB connection events
    _usbEventSubscription = service.usbEvents.listen(
      (event) {
        if (_isDisposed) return;

        if (event == 'connected') {
          _handleUsbConnected();
        } else if (event == 'disconnected') {
          _handleUsbDisconnected();
        }
      },
      onError: (error) {
        // USB event stream error, ignore
      },
    );

    // Try to connect if device is already plugged in
    _tryAutoConnect();
  }

  /// Handle USB device connected event
  void _handleUsbConnected() async {
    ref.read(connectionStatusProvider.notifier).state =
        ConnectionStatus.connecting;

    // Small delay to ensure device is ready
    await Future.delayed(const Duration(milliseconds: 500));

    if (_isDisposed) return;
    await _tryAutoConnect();
  }

  /// Handle USB device disconnected event
  void _handleUsbDisconnected() {
    stopPolling();
    ref.read(connectionStatusProvider.notifier).state =
        ConnectionStatus.disconnected;
    ref.read(weightReadingProvider.notifier).state = null;
    ref.read(errorMessageProvider.notifier).state = null;
  }

  /// Try to automatically connect to USB scale device
  Future<void> _tryAutoConnect() async {
    if (_isDisposed) return;

    final service = ref.read(serialScaleServiceProvider);

    try {
      ref.read(connectionStatusProvider.notifier).state =
          ConnectionStatus.connecting;

      final connected = await service.autoConnect();

      if (_isDisposed) return;

      if (connected) {
        ref.read(connectionStatusProvider.notifier).state =
            ConnectionStatus.connected;
        ref.read(errorMessageProvider.notifier).state = null;

        // Auto-start reading if enabled
        if (ref.read(autoStartProvider)) {
          startPolling();
        }
      } else {
        ref.read(connectionStatusProvider.notifier).state =
            ConnectionStatus.disconnected;
        ref.read(errorMessageProvider.notifier).state =
            'No USB scale device found';
      }
    } catch (e) {
      if (_isDisposed) return;

      ref.read(connectionStatusProvider.notifier).state =
          ConnectionStatus.error;
      ref.read(errorMessageProvider.notifier).state = 'Connection failed: $e';
    }
  }

  /// Start continuous polling of weight data
  void startPolling() {
    if (_pollingTimer != null && _pollingTimer!.isActive) return;

    final status = ref.read(connectionStatusProvider);
    if (!status.isConnected) {
      ref.read(errorMessageProvider.notifier).state =
          'Cannot start reading: Device not connected';
      return;
    }

    // Initial read
    _readWeight();

    // Start periodic polling (every 500ms for real-time updates)
    _pollingTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _readWeight(),
    );
  }

  /// Stop continuous polling
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Manually trigger connection attempt
  Future<void> connect() async {
    await _tryAutoConnect();
  }

  /// Manually disconnect
  Future<void> disconnect() async {
    stopPolling();

    final service = ref.read(serialScaleServiceProvider);
    await service.disconnect();

    ref.read(connectionStatusProvider.notifier).state =
        ConnectionStatus.disconnected;
    ref.read(weightReadingProvider.notifier).state = null;
  }

  /// Internal method to read weight from scale
  Future<void> _readWeight() async {
    if (_isDisposed) return;

    final service = ref.read(serialScaleServiceProvider);
    final status = ref.read(connectionStatusProvider);

    if (!status.isConnected) {
      stopPolling();
      return;
    }

    try {
      final reading = await service.readWeight();

      if (_isDisposed) return;

      // Update state on success
      final previous = ref.read(weightReadingProvider);
      if (_shouldUpdateReading(previous, reading)) {
        ref.read(weightReadingProvider.notifier).state = reading;
      }
      ref.read(errorMessageProvider.notifier).state = null;

      // Ensure status is connected
      if (ref.read(connectionStatusProvider) != ConnectionStatus.connected) {
        ref.read(connectionStatusProvider.notifier).state =
            ConnectionStatus.connected;
      }
    } on PlatformException catch (e) {
      if (_isDisposed) return;

      // Check if it's a disconnection error
      if (e.code == 'device_disconnected' || e.code == 'not_connected') {
        _handleUsbDisconnected();
      } else {
        final errorMsg = e.message ?? 'Communication error';
        ref.read(errorMessageProvider.notifier).state = errorMsg;
      }
    } catch (e) {
      if (_isDisposed) return;
      // Transient read errors are ignored
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pollingTimer?.cancel();
    _usbEventSubscription?.cancel();
    super.dispose();
  }

  bool _shouldUpdateReading(WeightReading? previous, WeightReading next) {
    if (previous == null) return true;

    final prevRaw = previous.raw.trim();
    final nextRaw = next.raw.trim();
    if (prevRaw != nextRaw) return true;

    final prevValue = previous.value;
    final nextValue = next.value;
    if (prevValue != nextValue) return true;

    return false;
  }
}

/// Provider for the scale controller
final scaleControllerProvider =
    StateNotifierProvider<ScaleController, AsyncValue<void>>((ref) {
      return ScaleController(ref);
    });
