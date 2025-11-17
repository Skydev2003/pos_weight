# USB Scale Monitor - Flutter Application

A professional Flutter application for real-time USB serial scale weight monitoring with **automatic device detection**, clean architecture, and Riverpod state management.

## Features

- **Automatic USB Detection**: Automatically detects and connects to USB scale devices - no manual configuration needed
- **Real-time Weight Display**: Continuously reads and displays weight measurements in real-time
- **USB Event Monitoring**: Automatically detects USB plug/unplug events and updates UI accordingly
- **Connection Status Monitoring**: Visual indicators for connected/disconnected/connecting/error states
- **Riverpod State Management**: Clean, modular state management with proper separation of concerns
- **Platform Channel Communication**: Direct USB serial communication via native platform channels
- **Zero Configuration**: No manual port or baud rate selection required
- **Professional UI**: Material Design 3 with intuitive interface and clear data visualization

## Architecture

### Project Structure

```
lib/
├── main.dart                          # App entry point with ProviderScope
├── models/
│   ├── connection_status.dart         # Connection state enum
│   └── weight_reading.dart            # Weight data model
├── providers/
│   └── scale_providers.dart           # Riverpod providers and controllers
├── screens/
│   └── weight_monitor_screen.dart     # Main UI screen
└── services/
    └── serial_scale_service.dart      # USB serial communication service
```

### State Management with Riverpod

The application uses Riverpod for clean, testable state management:

- **serialScaleServiceProvider**: Provides the serial communication service instance
- **serialPortProvider**: Manages serial port configuration (e.g., COM5)
- **baudRateProvider**: Manages baud rate configuration (default: 9600)
- **connectionStatusProvider**: Tracks connection status (connected/disconnected/error)
- **weightReadingProvider**: Holds the latest weight reading data
- **errorMessageProvider**: Manages error messages for user feedback
- **isPollingProvider**: Tracks whether continuous reading is active
- **scaleControllerProvider**: Main controller for scale operations

### Key Components

#### 1. SerialScaleService
Handles low-level platform channel communication with the USB scale device:
- Sends read requests via method channel
- Parses ASCII-encoded weight data
- Handles connection errors gracefully

#### 2. ScaleController
Manages scale operations and state updates:
- `startPolling()`: Begins continuous weight reading (600ms intervals)
- `stopPolling()`: Stops continuous reading
- `readOnce()`: Performs a single weight reading
- Automatically updates connection status and error states

#### 3. WeightMonitorScreen
Main UI with reactive components:
- Configuration section for port/baud rate
- Control buttons for start/stop/read once
- Real-time weight display card
- Connection status indicator
- Error message display

## Usage

### Starting the Application

1. Install dependencies:
```bash
flutter pub get
```

2. Run the application:
```bash
flutter run
```

### Connecting to a Scale

1. **Configure Serial Port**: Enter your USB serial port (e.g., COM5 on Windows, /dev/ttyUSB0 on Linux)
2. **Set Baud Rate**: Adjust if your scale uses a different baud rate (default: 9600)
3. **Start Reading**: Click "Start Reading" to begin continuous weight monitoring
4. **Monitor Status**: Watch the connection indicator in the app bar

### Connection Status Indicators

- 🟢 **Connected**: Successfully receiving data from scale
- 🟠 **Error**: Communication error occurred
- ⚪ **Disconnected**: No active connection

## Platform Channel Implementation

The app communicates with native code via the `pos_weight/serial` method channel:

### Method: `readWeight`

**Parameters:**
- `port` (String, optional): Serial port identifier
- `baudRate` (int): Communication speed

**Returns:**
```dart
{
  'port': String,      // Port used for communication
  'raw': String,       // Raw ASCII data from scale
  'value': double,     // Parsed weight value
}
```

### Native Implementation Required

You need to implement the native platform code for USB serial communication:

**Android**: Implement in `android/app/src/main/kotlin/MainActivity.kt`
**iOS**: Implement in `ios/Runner/AppDelegate.swift`
**Windows/Linux/macOS**: Implement in respective platform directories

## Data Flow

1. User clicks "Start Reading"
2. `ScaleController.startPolling()` is called
3. Timer triggers `_readWeight()` every 600ms
4. `SerialScaleService.readWeight()` sends platform channel request
5. Native code reads from USB serial port
6. Response is parsed into `WeightReading` model
7. Riverpod providers update state
8. UI automatically rebuilds with new data

## Error Handling

The application handles various error scenarios:

- **Empty Port**: Validates port configuration before reading
- **Platform Exceptions**: Catches and displays native communication errors
- **Connection Loss**: Updates status to disconnected on failure
- **Invalid Data**: Gracefully handles unparseable weight values

## Customization

### Polling Interval

Adjust the polling frequency in `scale_providers.dart`:

```dart
_pollingTimer = Timer.periodic(
  const Duration(milliseconds: 600), // Change this value
  (_) => _readWeight(),
);
```

### Weight Display Format

Modify the decimal places in `weight_monitor_screen.dart`:

```dart
final weightText = reading.value != null
    ? reading.value!.toStringAsFixed(2) // Change decimal places
    : '--';
```

## Dependencies

- **flutter_riverpod**: ^2.6.1 - State management

## Best Practices Implemented

✅ Clean architecture with separation of concerns
✅ Immutable state management with Riverpod
✅ Proper error handling and user feedback
✅ Reactive UI that responds to state changes
✅ Well-documented code with clear comments
✅ Type-safe models and services
✅ Resource cleanup (timer disposal)
✅ Material Design 3 guidelines

## Future Enhancements

- [ ] Add weight history chart
- [ ] Export weight data to CSV
- [ ] Support multiple scale devices
- [ ] Add tare/zero functionality
- [ ] Implement weight unit conversion (kg/lb)
- [ ] Add calibration settings
- [ ] Support Bluetooth scale devices

## License

This project is part of a POS weight monitoring system.
