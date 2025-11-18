# รายละเอียดทางเทคนิค

เอกสารนี้อธิบายการทำงานภายในของแอปพลิเคชันเครื่องชั่งดิจิทัล USB

## 🏗️ สถาปัตยกรรมระบบ

### ภาพรวม
```
┌─────────────────────────────────────────┐
│         Flutter UI Layer                │
│  (weight_monitor_screen.dart)           │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│      State Management Layer             │
│         (Riverpod Providers)            │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│       Service Layer (Dart)              │
│    (serial_scale_service.dart)          │
└──────────────┬──────────────────────────┘
               │ Platform Channel
┌──────────────▼──────────────────────────┐
│    Native Layer (Kotlin/Android)        │
│         (MainActivity.kt)               │
└──────────────┬──────────────────────────┘
               │ USB Serial
┌──────────────▼──────────────────────────┐
│         USB Scale Device                │
└─────────────────────────────────────────┘
```

## 🔄 กระบวนการทำงาน

### 1. การเชื่อมต่ออัตโนมัติ

#### ขั้นตอนการตรวจจับ USB
```kotlin
// 1. ตรวจจับเหตุการณ์ USB
UsbManager.ACTION_USB_DEVICE_ATTACHED
    ↓
// 2. ค้นหา USB Serial Drivers
UsbSerialProber.getDefaultProber().findAllDrivers(manager)
    ↓
// 3. เลือก Driver ที่เหมาะสม
selectDriver(drivers) // ให้ความสำคัญกับ CH340 ก่อน
    ↓
// 4. ขอสิทธิ์ (ถ้าจำเป็น)
usbManager.requestPermission(device, pendingIntent)
    ↓
// 5. เปิด Serial Port
port.open(connection)
    ↓
// 6. ตรวจจับ Configuration
configureSerialParameters(port)
```

#### การตรวจจับ Configuration อัตโนมัติ
```kotlin
fun configureSerialParameters(port: UsbSerialPort): Boolean {
    // ลองแต่ละ config ตามลำดับ
    for (config in serialConfigs) {
        // ตั้งค่า baud rate, data bits, parity
        port.setParameters(config.baudRate, config.dataBits, ...)
        
        // อ่านตัวอย่างข้อมูล
        val sample = readAsciiSample(port, config.dataBits)
        
        // ตรวจสอบว่าเป็นข้อมูลน้ำหนักหรือไม่
        if (isLikelyWeightSample(sample)) {
            // พบ config ที่ใช้ได้!
            return true
        }
    }
    return false
}
```

### 2. การอ่านข้อมูล

#### กระบวนการอ่านข้อมูล
```kotlin
fun readFromSerialPort(port: UsbSerialPort): SerialReadOutcome {
    val buffer = ByteArray(512)
    var totalRead = 0
    
    // อ่านข้อมูลจนกว่าจะได้บรรทัดสมบูรณ์
    while (totalRead < buffer.size && !timeout) {
        val count = port.read(chunk, 200) // timeout 200ms
        
        if (count > 0) {
            // คัดลอกข้อมูลไปยัง buffer
            System.arraycopy(chunk, 0, buffer, totalRead, count)
            totalRead += count
            
            // ตรวจสอบว่ามี line terminator หรือไม่
            if (hasNewline) break
        }
    }
    
    // แปลงข้อมูลเป็นค่าน้ำหนัก
    return parseWeightData(buffer, totalRead)
}
```

#### การกรองข้อมูล
```kotlin
fun isValidWeightLine(line: String): Boolean {
    // 1. ต้องมีตัวเลขอย่างน้อย 3 ตัว
    if (line.count { it.isDigit() } < 3) return false
    
    // 2. ต้องมีรูปแบบตัวเลขที่ถูกต้อง
    val hasValidNumber = Regex("\\d+\\.\\d+").containsMatchIn(line)
    if (!hasValidNumber) return false
    
    // 3. ตัวอักษรแปลกปลอมต้องไม่เกิน 10%
    val invalidChars = line.count { !isValidChar(it) }
    return invalidChars <= line.length / 10
}
```

### 3. การแสดงผลแบบ Smooth

#### Animation Controller
```dart
class _WeightDisplayState extends State<_WeightDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _displayedWeight = 0.0;
  double _targetWeight = 0.0;

  @override
  void didUpdateWidget(_WeightDisplay oldWidget) {
    final newWeight = widget.reading.value ?? 0.0;
    
    if (newWeight != _targetWeight) {
      // สร้าง Tween จากค่าปัจจุบันไปค่าใหม่
      final tween = Tween<double>(
        begin: _displayedWeight,
        end: newWeight,
      );
      
      // Animate ด้วย easeOutCubic curve
      _animation = tween.animate(
        CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
        ),
      )..addListener(() {
        setState(() {
          _displayedWeight = _animation.value;
        });
      });
      
      _controller.forward(from: 0.0);
    }
  }
}
```

## 📊 รูปแบบข้อมูลที่รองรับ

### ASCII Text Format

#### รูปแบบที่ 1: ตัวเลขล้วน
```
"   0.480\n"
"   0.000\n"
"   1.234\n"
```

#### รูปแบบที่ 2: มีหน่วย
```
"0.480 kg\n"
"480 g\n"
"1.234 kg\n"
```

#### รูปแบบที่ 3: หลายบรรทัด
```
"   0.480\n   0.480\n   0.480\n"
```

### Binary Format

#### 16-bit Integer (Little Endian)
```
Bytes: [0xE0, 0x01]  // 480 (grams)
→ 480 / 1000 = 0.480 kg
```

#### 32-bit Float (Little Endian)
```
Bytes: [0x9A, 0x99, 0x99, 0x3E]  // 0.3 (float)
→ 0.300 kg
```

## 🔧 การปรับแต่งขั้นสูง

### 1. เพิ่ม Baud Rate ใหม่

แก้ไขใน `MainActivity.kt`:
```kotlin
private val serialConfigs = listOf(
    // เพิ่ม config ใหม่
    SerialConfig("19200 8N1", 19200, 
        UsbSerialPort.DATABITS_8, 
        UsbSerialPort.STOPBITS_1, 
        UsbSerialPort.PARITY_NONE),
    
    // config เดิม
    SerialConfig("9600 8N1", 9600, ...),
    // ...
)
```

### 2. ปรับ Timeout

```kotlin
// ใน readFromSerialPort()
while (totalRead < buffer.size && 
       System.currentTimeMillis() - start < 800) { // เปลี่ยนจาก 800ms
    
    val count = port.read(chunk, 200) // เปลี่ยนจาก 200ms
    
    // ...
    
    if (totalRead > 0 && 
        System.currentTimeMillis() - lastReadAt > 150) { // เปลี่ยนจาก 150ms
        break
    }
}
```

### 3. ปรับความเข้มงวดในการกรอง

```kotlin
fun isValidWeightLine(line: String): Boolean {
    // ...
    
    // เปลี่ยนจาก 10% เป็น 20% (ผ่อนปรนมากขึ้น)
    return invalidChars <= line.length / 5
}
```

### 4. เปลี่ยนความเร็ว Animation

```dart
// ใน _WeightDisplayState
_controller = AnimationController(
  duration: const Duration(milliseconds: 300), // เร็วขึ้น
  // หรือ
  duration: const Duration(milliseconds: 600), // ช้าลง
  vsync: this,
);
```

### 5. เปลี่ยน Animation Curve

```dart
_animation = tween.animate(
  CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,      // นุ่มนวลทั้งเริ่มและจบ
    // หรือ
    curve: Curves.linear,          // เร็วสม่ำเสมอ
    // หรือ
    curve: Curves.bounceOut,       // มีการตีกลับเล็กน้อย
  ),
);
```

## 🐛 การ Debug

### 1. ดู Log ใน Logcat

```bash
# กรอง log ด้วย tag
adb logcat -s SerialScale

# ดู log แบบเรียลไทม์
adb logcat | grep "SerialScale"
```

### 2. Log ที่สำคัญ

```kotlin
// การเชื่อมต่อ
Log.d(logTag, "Selected device: ${device.deviceName}, VID=${device.vendorId}")

// การตรวจจับ config
Log.d(logTag, "Using serial config ${config.label}, sample='$sample'")

// ข้อมูลที่อ่านได้
Log.d(logTag, "Raw serial payload ($totalRead bytes): $lines | HEX: $hexDump")
```

### 3. ตรวจสอบ USB Device

```bash
# ดูรายการ USB devices
adb shell ls -l /dev/bus/usb/

# ดูข้อมูล USB device
adb shell dumpsys usb
```

## 📈 การเพิ่มประสิทธิภาพ

### 1. แคชสถานะการเชื่อมต่อ

```dart
// ใน SerialScaleService
bool _isConnectedCache = false;
DateTime? _lastConnectionCheck;
static const _connectionCacheDuration = Duration(milliseconds: 500);

Future<bool> isConnected() async {
  // ใช้แคชถ้ายังไม่หมดอายุ
  final now = DateTime.now();
  if (_lastConnectionCheck != null &&
      now.difference(_lastConnectionCheck!) < _connectionCacheDuration) {
    return _isConnectedCache;
  }
  
  // ตรวจสอบจริงถ้าแคชหมดอายุ
  final result = await _channel.invokeMethod<bool>('isConnected');
  _isConnectedCache = result ?? false;
  _lastConnectionCheck = now;
  return _isConnectedCache;
}
```

### 2. จดจำ Config ที่ใช้ได้

```kotlin
private var lastKnownGoodConfig: SerialConfig? = null

fun configureSerialParameters(port: UsbSerialPort): Boolean {
    val sequence = buildList {
        // ลอง config ที่รู้จักก่อน
        lastKnownGoodConfig?.let { add(it) }
        // จากนั้นลองตามลำดับ
        addAll(serialConfigs)
    }
    
    // ...
    
    if (configSuccess) {
        lastKnownGoodConfig = config // บันทึกไว้
    }
}
```

### 3. ลด Delay ในการเปิด Port

```kotlin
port.open(connection)
port.purgeHwBuffers(true, true)

// ลด delay จาก 100ms เหลือ 50ms (ถ้าเครื่องชั่งรองรับ)
Thread.sleep(50)
```

## 🔒 ความปลอดภัย

### 1. การจัดการ Permissions

```kotlin
// ตรวจสอบสิทธิ์ก่อนเข้าถึง
if (!manager.hasPermission(device)) {
    requestUsbPermission(manager, device)
    return false
}
```

### 2. การจัดการ Lifecycle

```kotlin
override fun onDestroy() {
    // ปิดการเชื่อมต่อก่อน destroy
    closeSerialPort()
    
    // ยกเลิก receiver
    if (receiverRegistered) {
        unregisterReceiver(usbReceiver)
    }
    
    super.onDestroy()
}
```

### 3. การจัดการ Error

```kotlin
try {
    val result = readFromSerialPort(port)
    // ...
} catch (ex: Exception) {
    Log.e(logTag, "Failed to read serial data", ex)
    closeSerialPort() // ปิดการเชื่อมต่อเมื่อเกิด error
    return SerialReadOutcome.Failure(...)
}
```

## 📚 อ้างอิง

### USB Serial Chips
- [CH340/CH341 Datasheet](http://www.wch-ic.com/products/CH340.html)
- [FTDI FT232 Datasheet](https://ftdichip.com/products/ft232rl/)
- [CP210x Datasheet](https://www.silabs.com/interface/usb-bridges/classic)

### Libraries
- [usb-serial-for-android](https://github.com/mik3y/usb-serial-for-android)
- [Flutter Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [Riverpod Documentation](https://riverpod.dev/docs/introduction/getting_started)

### Standards
- [USB CDC ACM](https://www.usb.org/document-library/class-definitions-communication-devices-12)
- [RS-232 Serial Communication](https://en.wikipedia.org/wiki/RS-232)

---

**หมายเหตุ**: เอกสารนี้อธิบายการทำงานภายในของระบบ สำหรับการใช้งานทั่วไป โปรดดู `README_TH.md`
