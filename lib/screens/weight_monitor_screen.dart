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
        title: const Text('USB Scale Monitor'),
        centerTitle: true,
        actions: [
          _ConnectionStatusIndicator(status: connectionStatus),
          const SizedBox(width: 16),
        ],
      ),
      body: Center(
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
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case ConnectionStatus.connecting:
        color = Colors.orange;
        icon = Icons.sync;
        break;
      case ConnectionStatus.error:
        color = Colors.red;
        icon = Icons.error;
        break;
      case ConnectionStatus.disconnected:
        color = Colors.grey;
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
        Icon(Icons.usb_off, size: 120, color: Colors.grey.shade400),
        const SizedBox(height: 32),
        Text(
          'USB Disconnected',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Please connect your USB scale device',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
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
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Detecting USB scale device',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
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
        Icon(Icons.scale, size: 100, color: Colors.blue.shade300),
        const SizedBox(height: 32),
        Text(
          'Connected',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.green.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Waiting for weight data...',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
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
        Icon(Icons.error_outline, size: 120, color: Colors.red.shade400),
        const SizedBox(height: 32),
        Text(
          'Connection Error',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.red.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Failed to connect to USB scale',
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

/// Weight display widget - shows real-time weight
class _WeightDisplay extends StatelessWidget {
  const _WeightDisplay({required this.reading});

  final WeightReading reading;

  @override
  Widget build(BuildContext context) {
    final rawText = reading.raw.trim();
    final weightText = rawText.isNotEmpty
        ? rawText
        : (reading.value != null ? reading.value!.toString() : '--');

    return Card(
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, minHeight: 300),
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "Connected" status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Connected',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Weight value
            Text(
              weightText,
              style: TextStyle(
                fontSize: 96,
                fontWeight: FontWeight.bold,
                letterSpacing: -2,
                color: Colors.blue.shade700,
                height: 1,
              ),
            ),

            const SizedBox(height: 8),

            // Unit
            Text(
              'kg',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),

            const SizedBox(height: 32),

            // Metadata
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _MetadataRow(
                    icon: Icons.data_object,
                    label: 'Raw',
                    value: reading.raw,
                  ),
                  const SizedBox(height: 8),
                  _MetadataRow(
                    icon: Icons.access_time,
                    label: 'Time',
                    value: reading.timestampFormatted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Metadata row widget
class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.black87, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
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
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
