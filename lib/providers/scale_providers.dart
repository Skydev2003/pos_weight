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
    Future.microtask(_initialize); // Defer initialization to avoid synchronous provider writes
  }

  static const double _noiseThreshold = 0.005;
  static const double _tinyStepThreshold = 0.02;
  static const double _smallStepThreshold = 0.1;
  static const double _mediumStepThreshold = 0.5;

  final Ref ref;
  Timer? _pollingTimer;
  Timer? _autoReconnectTimer;
  StreamSubscription<String>? _usbEventSubscription;
  bool _isDisposed = false;
  bool _connectInProgress = false;
  int _warmupSamplesRemaining = 0;
  WeightReading? _lastStableReading;
  WeightReading? _pendingReading;
  int _pendingConfirmations = 0;
  int _pendingRequiredConfirmations = 0;

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
    _resetReadingState();
    _scheduleReconnect();
  }

  /// Try to automatically connect to USB scale device
  Future<void> _tryAutoConnect() async {
    if (_isDisposed || _connectInProgress) return;

    final service = ref.read(serialScaleServiceProvider);
    const maxAttempts = 3;

    _connectInProgress = true;
    ref.read(connectionStatusProvider.notifier).state =
        ConnectionStatus.connecting;

    try {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        final connected = await service.autoConnect();
        if (_isDisposed) return;

        if (connected) {
          ref.read(connectionStatusProvider.notifier).state =
              ConnectionStatus.connected;
          ref.read(errorMessageProvider.notifier).state = null;

          if (ref.read(autoStartProvider)) {
            startPolling();
          }
          _cancelReconnect();
          return;
        }

        if (attempt < maxAttempts - 1) {
          await Future.delayed(const Duration(milliseconds: 700));
        }
      }

      if (_isDisposed) return;
      ref.read(connectionStatusProvider.notifier).state =
          ConnectionStatus.disconnected;
      ref.read(errorMessageProvider.notifier).state =
          'Waiting for USB scale... Ensure it is connected and permission is granted.';
      _scheduleReconnect();
    } catch (e) {
      if (_isDisposed) return;

      ref.read(connectionStatusProvider.notifier).state =
          ConnectionStatus.error;
      ref.read(errorMessageProvider.notifier).state = 'Connection failed: $e';
      _scheduleReconnect();
    } finally {
      _connectInProgress = false;
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
    _warmupSamplesRemaining = 1;
    _readWeight();

    // Start periodic polling (faster cadence keeps UI responsive)
    _pollingTimer = Timer.periodic(
      const Duration(milliseconds: 250),
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
    _resetReadingState();
    _scheduleReconnect();
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
      _processReading(reading);
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
      } else if (e.code == 'invalid_payload' || e.code == 'no_data') {
        // Ignore noisy payloads; keep polling for the next valid reading.
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
    _autoReconnectTimer?.cancel();
    _usbEventSubscription?.cancel();
    super.dispose();
  }

  void _processReading(WeightReading reading) {
    final normalizedValue = reading.normalizedValue;
    if (normalizedValue == null) {
      return;
    }

    final WeightReading candidate =
        reading.value == normalizedValue
            ? reading
            : WeightReading(
                port: reading.port,
                raw: reading.raw,
                timestamp: reading.timestamp,
                value: normalizedValue,
              );

    if (_warmupSamplesRemaining > 0) {
      _warmupSamplesRemaining--;
      _lastStableReading = candidate;
      if (_warmupSamplesRemaining == 0) {
        _commitReading(candidate);
      }
      return;
    }

    final last = _lastStableReading;
    if (last == null || last.value == null) {
      _commitReading(candidate);
      return;
    }

    final lastValue = last.value!;
    final nextValue = candidate.value!;
    final difference = (lastValue - nextValue).abs();
    if (difference <= _noiseThreshold) {
      _clearPendingReading();
      return; // Ignore micro fluctuations
    }

    final int confirmationsRequired;
    if (difference <= _tinyStepThreshold) {
      confirmationsRequired = 5;
    } else if (difference <= _smallStepThreshold) {
      confirmationsRequired = 4;
    } else if (difference <= _mediumStepThreshold) {
      confirmationsRequired = 3;
    } else {
      confirmationsRequired = 2;
    }

    _accumulatePendingReading(
      candidate,
      confirmationsRequired: confirmationsRequired,
    );
  }

  void _accumulatePendingReading(
    WeightReading reading, {
    int confirmationsRequired = 2,
  }) {
    if (_pendingReading == null ||
        !_areReadingsSimilar(_pendingReading!, reading)) {
      _pendingReading = reading;
      _pendingConfirmations = 1;
      _pendingRequiredConfirmations = confirmationsRequired;
    } else {
      _pendingConfirmations++;
      _pendingRequiredConfirmations = confirmationsRequired;
    }

    if (_pendingConfirmations >= _pendingRequiredConfirmations) {
      _commitReading(_pendingReading!);
      _pendingReading = null;
      _pendingConfirmations = 0;
      _pendingRequiredConfirmations = 0;
    }
  }

  bool _areReadingsSimilar(WeightReading a, WeightReading b) {
    final aValue = a.value;
    final bValue = b.value;
    if (aValue != null && bValue != null) {
      if ((aValue - bValue).abs() > 0.002) {
        return false;
      }
    } else if (a.sanitizedRaw != b.sanitizedRaw) {
      return false;
    }
    return true;
  }

  void _commitReading(WeightReading reading) {
    _lastStableReading = reading;
    ref.read(weightReadingProvider.notifier).state = reading;
  }

  void _resetReadingState() {
    _lastStableReading = null;
    _clearPendingReading();
    _warmupSamplesRemaining = 0;
  }

  void _clearPendingReading() {
    _pendingReading = null;
    _pendingConfirmations = 0;
    _pendingRequiredConfirmations = 0;
  }

  void _scheduleReconnect() {
    if (_autoReconnectTimer != null || _isDisposed) return;
    _autoReconnectTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        if (_isDisposed) {
          _autoReconnectTimer?.cancel();
          _autoReconnectTimer = null;
          return;
        }
        final status = ref.read(connectionStatusProvider);
        if (!status.isConnected && !_connectInProgress) {
          _tryAutoConnect();
        }
      },
    );
  }

  void _cancelReconnect() {
    _autoReconnectTimer?.cancel();
    _autoReconnectTimer = null;
  }
}

/// Provider for the scale controller
final scaleControllerProvider =
    StateNotifierProvider<ScaleController, AsyncValue<void>>((ref) {
      return ScaleController(ref);
    });
