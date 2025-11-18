# คู่มือความเข้ากันได้ของเครื่องชั่ง

เอกสารนี้อธิบายเกี่ยวกับเครื่องชั่งที่รองรับและวิธีการทดสอบ

## ✅ เครื่องชั่งที่รองรับ

### 1. เครื่องชั่งที่ใช้ USB Serial Chip

แอปรองรับเครื่องชั่งที่ใช้ USB Serial Chip ดังนี้:

#### CH340/CH341 (แนะนำ)
- **Vendor ID**: 0x1A86
- **Product ID**: 0x7523 (CH340), 0x5523 (CH341)
- **ความเร็ว**: 2400, 4800, 9600 bps
- **รูปแบบ**: 7E1, 8N1
- **หมายเหตุ**: แอปให้ความสำคัญกับ chip นี้เป็นอันดับแรก

#### FTDI FT232
- **Vendor ID**: 0x0403
- **Product ID**: 0x6001 (FT232R), 0x6015 (FT232H)
- **ความเร็ว**: 2400-115200 bps
- **รูปแบบ**: 7E1, 8N1
- **หมายเหตุ**: เสถียรและรองรับความเร็วสูง

#### Silicon Labs CP210x
- **Vendor ID**: 0x10C4
- **Product ID**: 0xEA60 (CP2102), 0xEA70 (CP2105)
- **ความเร็ว**: 2400-921600 bps
- **รูปแบบ**: 7E1, 8N1
- **หมายเหตุ**: ใช้กันแพร่หลายในอุปกรณ์ POS

#### Prolific PL2303
- **Vendor ID**: 0x067B
- **Product ID**: 0x2303
- **ความเร็ว**: 2400-115200 bps
- **รูปแบบ**: 7E1, 8N1
- **หมายเหตุ**: ราคาถูก แต่อาจมีปัญหากับ driver ปลอม

#### CDC ACM (USB Standard)
- **Vendor ID**: ขึ้นกับผู้ผลิต
- **Product ID**: ขึ้นกับผู้ผลิต
- **ความเร็ว**: 2400-115200 bps
- **รูปแบบ**: 7E1, 8N1
- **หมายเหตุ**: มาตรฐาน USB ไม่ต้องติดตั้ง driver

## 🔍 วิธีตรวจสอบเครื่องชั่งของคุณ

### ขั้นตอนที่ 1: ตรวจสอบ USB Chip

1. **เปิดแอป** และเสียบเครื่องชั่ง
2. **ดู Log** ใน Logcat:
```bash
adb logcat -s SerialScale
```

3. **หาข้อความนี้**:
```
D/SerialScale: Selected device: /dev/bus/usb/005/003, VID=6790, PID=29987
```

4. **แปลง VID/PID เป็น Hex**:
```
VID=6790 (decimal) = 0x1A86 (hex) → CH340
PID=29987 (decimal) = 0x7523 (hex) → CH340
```

### ขั้นตอนที่ 2: ตรวจสอบรูปแบบข้อมูล

1. **ดู Log ข้อมูลดิบ**:
```
D/SerialScale: Raw serial payload (18 bytes): [0.480, 0.480] | HEX: 20 20 20 30 2E 34 38 30 0A 20 20 20 30 2E 34 38 30 0A
```

2. **วิเคราะห์รูปแบบ**:
```
HEX: 20 20 20 30 2E 34 38 30 0A
     │  │  │  │  │  │  │  │  └─ Line Feed (0x0A)
     │  │  │  │  │  │  │  └──── '0' (0x30)
     │  │  │  │  │  │  └─────── '8' (0x38)
     │  │  │  │  │  └────────── '4' (0x34)
     │  │  │  │  └───────────── '.' (0x2E)
     │  │  │  └──────────────── '0' (0x30)
     └──└──└─────────────────── Spaces (0x20)

ASCII: "   0.480\n"
```

### ขั้นตอนที่ 3: ตรวจสอบ Configuration

1. **ดู Log การตรวจจับ**:
```
D/SerialScale: Using serial config 9600 8N1, sample='0.480'
D/SerialScale: Serial port opened successfully
```

2. **ถ้าเห็นข้อความนี้ แสดงว่าใช้งานได้**:
```
D/SerialScale: Using serial config [baud] [format], sample='[ตัวอย่างข้อมูล]'
```

3. **ถ้าเห็นข้อความนี้ แสดงว่ามีปัญหา**:
```
E/SerialScale: Unable to determine serial configuration
```

## 🛠️ การแก้ปัญหาเครื่องชั่งที่ไม่รองรับ

### ปัญหา 1: ไม่เจอเครื่องชั่ง

**สาเหตุ**: USB Chip ไม่รองรับโดย `usb-serial-for-android`

**วิธีแก้**:
1. ตรวจสอบ VID/PID ของเครื่องชั่ง
2. เพิ่ม VID/PID ใน `selectDriver()`:

```kotlin
private fun selectDriver(drivers: List<UsbSerialDriver>): UsbSerialDriver? {
    if (drivers.isEmpty()) return null
    
    // เพิ่ม VID/PID ของเครื่องชั่งคุณ
    return drivers.firstOrNull { driver ->
        val device = driver.device
        device.vendorId == 0x1A86 && device.productId == 0x7523 // CH340
    } ?: drivers.firstOrNull { driver ->
        val device = driver.device
        device.vendorId == 0xYOUR_VID && device.productId == 0xYOUR_PID // เครื่องชั่งของคุณ
    } ?: drivers.firstOrNull() // ถ้าไม่เจอให้ใช้ตัวแรก
}
```

### ปัญหา 2: ตรวจจับ Config ไม่ได้

**สาเหตุ**: Baud rate หรือ data format ไม่ตรงกับที่เครื่องชั่งใช้

**วิธีแก้**:
1. ตรวจสอบคู่มือเครื่องชั่งว่าใช้ baud rate อะไร
2. เพิ่ม config ใหม่ใน `serialConfigs`:

```kotlin
private val serialConfigs = listOf(
    // เพิ่ม config ของเครื่องชั่งคุณ
    SerialConfig("19200 8N1", 19200, 
        UsbSerialPort.DATABITS_8, 
        UsbSerialPort.STOPBITS_1, 
        UsbSerialPort.PARITY_NONE),
    
    // config เดิม
    SerialConfig("9600 8N1", 9600, ...),
    SerialConfig("4800 7E1", 4800, ...),
    // ...
)
```

### ปัญหา 3: อ่านข้อมูลไม่ได้

**สาเหตุ**: รูปแบบข้อมูลไม่ตรงกับที่แอปคาดหวัง

**วิธีแก้**:
1. ดู log ข้อมูลดิบ (HEX)
2. วิเคราะห์รูปแบบ
3. ปรับ `parseWeight()` ให้รองรับรูปแบบใหม่:

```kotlin
private fun parseWeight(raw: String): Double? {
    val normalized = raw.lowercase(Locale.ROOT)
    
    // เพิ่มการจัดการรูปแบบใหม่
    // ตัวอย่าง: "ST,GS,+00.480kg"
    if (normalized.startsWith("st,gs,")) {
        val match = weightRegex.find(normalized.substring(6))
        val numeric = match?.value?.replace(",", ".")?.toDoubleOrNull()
        return numeric
    }
    
    // รูปแบบเดิม
    val match = weightRegex.find(normalized) ?: return null
    val numeric = match.value.replace(",", ".").toDoubleOrNull() ?: return null
    
    val isGram = normalized.contains(" g") && !normalized.contains("kg")
    return if (isGram) numeric / 1000.0 else numeric
}
```

### ปัญหา 4: ต้องส่งคำสั่งก่อนอ่านข้อมูล

**สาเหตุ**: เครื่องชั่งบางรุ่นต้องส่งคำสั่งก่อนจะส่งข้อมูลกลับมา

**วิธีแก้**:
1. เพิ่มฟังก์ชันส่งคำสั่ง:

```kotlin
private fun sendCommand(port: UsbSerialPort, command: String) {
    val bytes = command.toByteArray(Charsets.US_ASCII)
    port.write(bytes, 1000)
}

private fun readFromSerialPort(port: UsbSerialPort): SerialReadOutcome {
    // ส่งคำสั่งก่อนอ่าน
    sendCommand(port, "W\r\n") // ตัวอย่าง: คำสั่ง "W" เพื่อขอค่าน้ำหนัก
    
    // รอสักครู่
    Thread.sleep(50)
    
    // อ่านข้อมูลตามปกติ
    // ...
}
```

## 📋 ตารางเปรียบเทียบ USB Chips

| Chip | VID | PID | ความเร็ว | ราคา | ความเสถียร | หมายเหตุ |
|------|-----|-----|----------|------|-----------|----------|
| CH340 | 0x1A86 | 0x7523 | 2400-2M | ถูก | ดี | แนะนำ |
| FTDI FT232 | 0x0403 | 0x6001 | 300-3M | แพง | ดีมาก | มาตรฐาน |
| CP210x | 0x10C4 | 0xEA60 | 300-1M | ปานกลาง | ดี | นิยม |
| PL2303 | 0x067B | 0x2303 | 300-1M | ถูกมาก | พอใช้ | ระวัง driver ปลอม |

## 🧪 การทดสอบเครื่องชั่งใหม่

### ขั้นตอนการทดสอบ

1. **เตรียมอุปกรณ์**
   - เครื่องชั่งที่ต้องการทดสอบ
   - สาย USB OTG
   - อุปกรณ์ Android ที่ติดตั้งแอปแล้ว

2. **เปิด Debug Mode**
```bash
# เชื่อมต่อ Android กับคอมพิวเตอร์
adb devices

# เปิด Logcat
adb logcat -s SerialScale
```

3. **เสียบเครื่องชั่ง**
   - เสียบสาย USB OTG
   - สังเกต log ที่แสดง

4. **บันทึกข้อมูล**
   - VID/PID
   - Baud rate ที่ใช้ได้
   - รูปแบบข้อมูล (ASCII/Binary)
   - ตัวอย่างข้อมูลดิบ (HEX)

5. **ทดสอบการอ่านค่า**
   - วางของหนักบนเครื่องชั่ง
   - ตรวจสอบว่าแอปแสดงค่าถูกต้อง
   - ทดสอบหลายค่าน้ำหนัก

### ตัวอย่างการบันทึกผล

```
เครื่องชั่ง: [ชื่อรุ่น]
USB Chip: CH340
VID: 0x1A86 (6790)
PID: 0x7523 (29987)
Baud Rate: 9600
Data Format: 8N1
รูปแบบข้อมูล: ASCII Text
ตัวอย่าง: "   0.480\n"
HEX: 20 20 20 30 2E 34 38 30 0A
สถานะ: ✅ ใช้งานได้
หมายเหตุ: ทำงานได้ดี ไม่มีปัญหา
```

## 🔧 เครื่องมือช่วยทดสอบ

### 1. USB Device Info (Android App)
- ดาวน์โหลดจาก Play Store
- ดูข้อมูล VID/PID ของอุปกรณ์ USB

### 2. Serial USB Terminal (Android App)
- ทดสอบการสื่อสารกับเครื่องชั่งโดยตรง
- ดูข้อมูลดิบที่ส่งมา

### 3. ADB Logcat
```bash
# ดู log ทั้งหมด
adb logcat

# กรองเฉพาะ SerialScale
adb logcat -s SerialScale

# บันทึก log ลงไฟล์
adb logcat -s SerialScale > scale_log.txt
```

## 📞 รายงานปัญหา

หากพบเครื่องชั่งที่ไม่รองรับ กรุณารายงานพร้อมข้อมูลดังนี้:

1. **ข้อมูลเครื่องชั่ง**
   - ยี่ห้อและรุ่น
   - VID/PID
   - คู่มือการใช้งาน (ถ้ามี)

2. **Log ไฟล์**
   - Log จาก Logcat
   - ข้อมูลดิบ (HEX)

3. **ภาพหน้าจอ**
   - หน้าจอแอป
   - ข้อความ error

4. **ข้อมูลเพิ่มเติม**
   - Android version
   - อุปกรณ์ที่ใช้ทดสอบ

---

**หมายเหตุ**: แอปนี้ออกแบบมาให้รองรับเครื่องชั่งได้หลากหลาย แต่อาจต้องปรับแต่งเล็กน้อยสำหรับเครื่องชั่งบางรุ่น
