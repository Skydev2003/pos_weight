import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/connection_status.dart';
import '../providers/scale_providers.dart';
import '../models/weight_reading.dart';

/// Main screen for monitoring USB scale weight readings with automatic detection
class WeightMonitorScreen extends ConsumerWidget {
  const WeightMonitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure the scale controller initializes and listens for USB events.
    ref.watch(scaleControllerProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final weightReading = ref.watch(weightReadingProvider);
    final errorMessage = ref.watch(errorMessageProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('USB Scale Monitor'),
        centerTitle: true,
        elevation: 0,
        actions: [
          _ConnectionStatusIndicator(status: connectionStatus),
          const SizedBox(width: 16),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF160A2D), Color(0xFF1E1140), Color(0xFF08050F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Main display area
                Expanded(
                  child: Center(
                    child: _buildMainDisplay(
                      context,
                      connectionStatus,
                      weightReading,
                    ),
                  ),
                ),

                // Error message (if any)
                if (errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _ErrorMessage(message: errorMessage),
                ],

                const SizedBox(height: 24),

                // Manual control buttons
                _ControlButtons(connectionStatus: connectionStatus),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainDisplay(
    BuildContext context,
    ConnectionStatus status,
    WeightReading? reading,
  ) {
    switch (status) {
      case ConnectionStatus.disconnected:
        return _DisconnectedView();

      case ConnectionStatus.connecting:
        return _ConnectingView();

      case ConnectionStatus.connected:
        if (reading == null) {
          return _WaitingForDataView();
        }
        return _WeightDisplay(reading: reading);

      case ConnectionStatus.error:
        return _ErrorView();
    }
  }
}

/// Connection status indicator widget
class _ConnectionStatusIndicator extends StatelessWidget {
  const _ConnectionStatusIndicator({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (status) {
      case ConnectionStatus.connected:
        color = Colors.greenAccent;
        icon = Icons.check_circle;
        break;
      case ConnectionStatus.connecting:
        color = Colors.amberAccent;
        icon = Icons.sync;
        break;
      case ConnectionStatus.error:
        color = Colors.redAccent;
        icon = Icons.error;
        break;
      case ConnectionStatus.disconnected:
        color = Colors.white54;
        icon = Icons.usb_off;
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          status.displayText,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

/// Disconnected state view
class _DisconnectedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.usb_off, size: 120, color: Colors.white24),
        const SizedBox(height: 32),
        Text(
          'USB Disconnected',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Please connect your USB scale device',
          style: TextStyle(fontSize: 16, color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Connecting state view
class _ConnectingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(strokeWidth: 6),
        ),
        const SizedBox(height: 32),
        Text(
          'Connecting...',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Detecting USB scale device',
          style: TextStyle(fontSize: 16, color: Colors.white70),
        ),
      ],
    );
  }
}

/// Waiting for data view (connected but no reading yet)
class _WaitingForDataView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.scale, size: 100, color: Colors.purpleAccent.shade100),
        const SizedBox(height: 32),
        Text(
          'Connected',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.greenAccent,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Waiting for weight data...',
          style: TextStyle(fontSize: 16, color: Colors.white70),
        ),
      ],
    );
  }
}

/// Error state view
class _ErrorView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 120, color: Colors.redAccent),
        const SizedBox(height: 32),
        Text(
          'Connection Error',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Failed to connect to USB scale',
          style: TextStyle(fontSize: 16, color: Colors.white70),
        ),
      ],
    );
  }
}

/// Weight display widget - shows real-time weight with smooth animation
class _WeightDisplay extends StatefulWidget {
  const _WeightDisplay({required this.reading});

  final WeightReading reading;

  @override
  State<_WeightDisplay> createState() => _WeightDisplayState();
}

class _WeightDisplayState extends State<_WeightDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _displayedWeight = 0.0;
  double _targetWeight = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _targetWeight = widget.reading.value ?? 0.0;
    _displayedWeight = _targetWeight;
  }

  @override
  void didUpdateWidget(_WeightDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // เมื่อค่าน้ำหนักเปลี่ยน ให้ animate ไปยังค่าใหม่
    final newWeight = widget.reading.value ?? 0.0;
    if (newWeight != _targetWeight) {
      final oldWeight = _displayedWeight;
      _targetWeight = newWeight;

      // สร้าง Tween animation จากค่าปัจจุบันไปยังค่าใหม่
      final tween = Tween<double>(begin: oldWeight, end: _targetWeight);

      _animation =
          tween.animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          )..addListener(() {
            setState(() {
              _displayedWeight = _animation.value;
            });
          });

      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // แสดงค่าน้ำหนักที่กำลัง animate พร้อมทศนิยม 3 ตำแหน่ง
    final weightText = _displayedWeight.toStringAsFixed(3);

    return Container(
      constraints: const BoxConstraints(maxWidth: 520, minHeight: 320),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5C1ED2), Color(0xFF9038FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF120A21),
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Connected',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // แสดงตัวเลขที่ค่อยๆเปลี่ยน
            Text(
              weightText,
              style: const TextStyle(
                fontSize: 100,
                fontWeight: FontWeight.w900,
                letterSpacing: -3,
                color: Colors.white,
                height: 1,
                fontFeatures: [
                  FontFeature.tabularFigures(), // ทำให้ตัวเลขมีความกว้างเท่ากัน
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'kg',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.7),
                letterSpacing: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Control buttons for manual operations
class _ControlButtons extends ConsumerWidget {
  const _ControlButtons({required this.connectionStatus});

  final ConnectionStatus connectionStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Retry connection button
        if (connectionStatus.isDisconnected || connectionStatus.hasError)
          ElevatedButton.icon(
            onPressed: () {
              ref.read(scaleControllerProvider.notifier).connect();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry Connection'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

        // Disconnect button
        if (connectionStatus.isConnected) ...[
          OutlinedButton.icon(
            onPressed: () {
              ref.read(scaleControllerProvider.notifier).disconnect();
            },
            icon: const Icon(Icons.close),
            label: const Text('Disconnect'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              side: const BorderSide(color: Color(0xFFB388FF)),
              foregroundColor: const Color(0xFFB388FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Error message widget
class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.redAccent.shade100,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
