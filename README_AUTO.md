# USB Scale Monitor - Automatic Detection

A professional Flutter application for real-time USB serial scale weight monitoring with **automatic device detection**.

## Key Features

✅ **Automatic USB Detection** - Plug and play, no configuration needed
✅ **Real-time Weight Display** - Continuous weight updates
✅ **USB Event Monitoring** - Detects plug/unplug automatically  
✅ **Clean UI** - Shows connection status and weight clearly
✅ **Riverpod State Management** - Professional state management
✅ **Zero Configuration** - No manual port or baud rate selection

## How It Works

### Simple User Experience

1. **Plug in USB Scale** → App automatically detects device
2. **Auto-Connect** → Connects without any button clicks
3. **Real-time Weight** → Weight displays immediately
4. **Unplug USB** → App shows "USB Disconnected" message

### UI States

| State | Display |
|-------|---------|
| **Disconnected** | "USB Disconnected" message with USB icon |
| **Connecting** | Loading spinner with "Connecting..." |
| **Connected** | Green "Connected" badge + real-time weight |
| **Error** | Error icon with error message |

## Project Structure

```
lib/
├── main.dart                          # App entry with ProviderScope
├── models/
│   ├── connection_status.dart         # Connection state enum (4 states)
│   └── weight_reading.dart            # Weight data model
├── providers/
│   └── scale_providers.dart           # Riverpod providers + USB event handling
├── screens/
│   └── weight_monitor_screen.dart     # Main UI with automatic detection
└── services/
    └── serial_scale_service.dart      # USB communication + event stream
```

## Technical Implementation

### Communication Channels

**Method Channel**: `pos_weight/serial`
- `autoConnect()` - Automatically detect and connect to USB scale
- `readWeight()` - Read weight from connected device
- `disconnect()` - Disconnect from device
- `isConnected()` - Check connection status

**Event Channel**: `pos_weight/usb_events`
- Streams: `'connected'` when USB plugged in
- Streams: `'disconnected'` when USB unplugged

### State Management

```dart
// Providers
connectionStatusProvider    // ConnectionStatus enum
weightReadingProvider       // WeightReading? model
errorMessageProvider        // String? error
autoStartProvider          // bool auto-start preference

// Controller
ScaleController
  - Listens to USB events
  - Auto-connects on USB plug
  - Auto-starts reading
  - Handles disconnection
```

### Data Flow

```
USB Plugged In
    ↓
Event: 'connected'
    ↓
Auto-connect
    ↓
Status: Connected
    ↓
Auto-start reading (500ms polling)
    ↓
Display weight
    ↓
USB Unplugged
    ↓
Event: 'disconnected'
    ↓
Stop reading
    ↓
Status: Disconnected
```

## Installation

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Implement Platform Code

See `AUTO_USB_DETECTION_GUIDE.md` for detailed platform implementation:

**Android**: Implement USB detection in MainActivity.kt
**Windows**: Implement COM port detection in flutter_window.cpp
**Linux**: Implement TTY device detection

### 3. Run the App

```bash
flutter run
```

## Platform Implementation

### Android

Required components:
- USB broadcast receiver for plug/unplug events
- USB serial library for communication
- Permission handling
- Device filter configuration

See `AUTO_USB_DETECTION_GUIDE.md` for complete Android implementation.

### Windows

Required components:
- COM port enumeration
- USB device change notifications
- Serial port communication
- Event streaming to Flutter

See `AUTO_USB_DETECTION_GUIDE.md` for complete Windows implementation.

## Usage Example

### Normal Flow

```dart
// 1. User plugs in USB scale
// 2. App receives USB event
// 3. ScaleController auto-connects
// 4. UI shows "Connected"
// 5. Weight displays automatically
// 6. User unplugs USB
// 7. UI shows "USB Disconnected"
```

### Manual Control (Optional)

```dart
// Retry connection
ref.read(scaleControllerProvider.notifier).connect();

// Manual disconnect
ref.read(scaleControllerProvider.notifier).disconnect();
```

## UI Components

### Main Display States

**Disconnected View**
- Large USB icon (gray)
- "USB Disconnected" text
- "Please connect your USB scale device" message

**Connecting View**
- Loading spinner
- "Connecting..." text
- "Detecting USB scale device" message

**Connected View**
- Green "Connected" badge
- Large weight value (96pt font)
- Unit display (kg)
- Raw data and timestamp

**Error View**
- Red error icon
- "Connection Error" text
- Error message

### Status Indicator (App Bar)

- 🟢 Connected - Green check icon
- 🟠 Connecting - Orange sync icon
- 🔴 Error - Red error icon
- ⚪ Disconnected - Gray USB off icon

## Configuration

### Polling Interval

Adjust in `scale_providers.dart`:

```dart
const Duration(milliseconds: 500) // Default: 500ms
```

### Auto-start Reading

Enable/disable in providers:

```dart
final autoStartProvider = StateProvider<bool>((ref) => true);
```

## Testing

### Mock Mode

For testing without hardware:

```dart
// Create mock service
class MockSerialScaleService extends SerialScaleService {
  @override
  Future<bool> autoConnect() async {
    await Future.delayed(Duration(milliseconds: 500));
    return true;
  }
  
  @override
  Future<WeightReading> readWeight() async {
    final weight = 10.0 + Random().nextDouble() * 50.0;
    return WeightReading(
      port: 'MOCK',
      raw: '  ${weight.toStringAsFixed(2)} kg',
      timestamp: DateTime.now(),
      value: weight,
    );
  }
}
```

## Advantages Over Manual Configuration

| Feature | Manual Config | Auto Detection |
|---------|--------------|----------------|
| User Experience | Complex | Simple |
| Configuration | Required | None |
| Connection | Manual button | Automatic |
| USB Events | Not detected | Real-time |
| Error Prone | Yes | No |
| Setup Time | Minutes | Seconds |

## Troubleshooting

### "No USB scale device found"
- Check USB cable is data-capable (not charge-only)
- Verify scale is powered on
- Check USB permissions (Android)
- Try different USB port

### Weight not updating
- Check connection status is green
- Verify scale is sending data
- Check baud rate (default: 9600)
- Review error messages

### USB events not working
- Verify event channel implementation
- Check broadcast receiver (Android)
- Ensure proper permissions

## Documentation

- `AUTO_USB_DETECTION_GUIDE.md` - Complete platform implementation guide
- `ARCHITECTURE.md` - Architecture details
- `QUICKSTART.md` - Quick start guide
- `PROJECT_MAP.md` - Project navigation

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
```

## Best Practices

✅ Automatic USB detection
✅ Real-time event handling
✅ Clean state management
✅ Proper resource cleanup
✅ Error handling
✅ User-friendly UI
✅ Zero configuration

## Future Enhancements

- [ ] Multiple device support
- [ ] Weight history
- [ ] Data export
- [ ] Unit conversion
- [ ] Tare functionality
- [ ] Bluetooth support

## License

This project is part of a POS weight monitoring system.

---

**Ready to use!** Just implement the platform-specific code and plug in your USB scale.
