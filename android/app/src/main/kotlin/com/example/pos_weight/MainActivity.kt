package com.example.pos_weight

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import com.hoho.android.usbserial.driver.UsbSerialDriver
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import kotlin.math.abs
import kotlin.text.Charsets

class MainActivity : FlutterActivity() {
    private val channelName = "pos_weight/serial"
    private val usbEventsChannelName = "pos_weight/usb_events"
    private val usbPermissionAction: String by lazy { "$packageName.USB_PERMISSION" }
    private val logTag = "SerialScale"

    private var methodChannel: MethodChannel? = null
    private var usbEventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false

    private var usbManager: UsbManager? = null
    private var serialDriver: UsbSerialDriver? = null
    private var serialPort: UsbSerialPort? = null
    private var serialConnection: UsbDeviceConnection? = null

    // Regex สำหรับหาตัวเลขในข้อความ (รองรับทศนิยม)
    private val weightRegex = Regex("[-+]?\\d+(?:[.,]\\d+)?")

    // รายการ serial configurations ที่รองรับ (เรียงตามความนิยม)
    private val serialConfigs = listOf(
        SerialConfig("2400 7E1", 2400, UsbSerialPort.DATABITS_7, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_EVEN),
        SerialConfig("2400 8N1", 2400, UsbSerialPort.DATABITS_8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE),
        SerialConfig("4800 7E1", 4800, UsbSerialPort.DATABITS_7, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_EVEN),
        SerialConfig("4800 8N1", 4800, UsbSerialPort.DATABITS_8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE),
        SerialConfig("9600 7E1", 9600, UsbSerialPort.DATABITS_7, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_EVEN),
        SerialConfig("9600 8N1", 9600, UsbSerialPort.DATABITS_8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE),
    )

    // เก็บ config ที่ใช้งานได้ครั้งล่าสุด เพื่อลองใช้ก่อนในครั้งถัดไป
    private var lastKnownGoodConfig: SerialConfig? = null

    // BroadcastReceiver สำหรับรับเหตุการณ์ USB
    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return
            when (intent.action) {
                usbPermissionAction -> handleUsbPermission(intent)
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> handleUsbAttached(intent)
                UsbManager.ACTION_USB_DEVICE_DETACHED -> handleUsbDetached(intent)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        registerUsbReceivers()
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            try {
                unregisterReceiver(usbReceiver)
            } catch (ex: IllegalArgumentException) {
                Log.w(logTag, "Receiver already unregistered", ex)
            }
            receiverRegistered = false
        }
        closeSerialPort()
        usbEventSink = null
        super.onDestroy()
    }

    // ลงทะเบียน BroadcastReceiver สำหรับรับเหตุการณ์ USB
    private fun registerUsbReceivers() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(usbPermissionAction)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        // รองรับ Android เวอร์ชันต่างๆ
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(usbReceiver, filter)
        }
        receiverRegistered = true
    }

    // จัดการเมื่อผู้ใช้ตอบรับหรือปฏิเสธการขออนุญาตใช้ USB
    private fun handleUsbPermission(intent: Intent) {
        val device = extractUsbDevice(intent)
        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
        val message = if (granted) {
            "อนุญาตการเข้าถึง ${device?.deviceName ?: "USB"} แล้ว"
        } else {
            "ปฏิเสธการเข้าถึง USB"
        }
        runOnUiThread {
            Toast.makeText(this@MainActivity, message, Toast.LENGTH_SHORT).show()
        }
        if (granted) {
            emitUsbEvent("connected")
        }
    }

    // จัดการเมื่อมีการเสียบ USB
    private fun handleUsbAttached(intent: Intent) {
        val device = extractUsbDevice(intent)
        Log.d(logTag, "USB device attached: ${device?.deviceName}")
        emitUsbEvent("connected")
    }

    // จัดการเมื่อมีการถอด USB
    private fun handleUsbDetached(intent: Intent) {
        val device = extractUsbDevice(intent)
        Log.d(logTag, "USB device detached: ${device?.deviceName}")
        closeSerialPort()
        emitUsbEvent("disconnected")
    }

    // ส่งเหตุการณ์ USB ไปยัง Flutter
    private fun emitUsbEvent(event: String) {
        val sink = usbEventSink ?: return
        runOnUiThread {
            sink.success(event)
        }
    }

    // ตรวจสอบและส่งสถานะ USB ปัจจุบัน
    private fun emitCurrentUsbState() {
        val manager = usbManager ?: return
        val drivers = runCatching {
            UsbSerialProber.getDefaultProber().findAllDrivers(manager)
        }.getOrDefault(emptyList())
        when {
            drivers.isNotEmpty() -> emitUsbEvent("connected")
            manager.deviceList.isEmpty() -> emitUsbEvent("disconnected")
        }
    }

    // ดึงข้อมูล USB device จาก Intent (รองรับ Android เวอร์ชันต่างๆ)
    private fun extractUsbDevice(intent: Intent): UsbDevice? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
    }

    // ตั้งค่า Flutter Engine และ Platform Channels
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ตั้งค่า MethodChannel สำหรับเรียกคำสั่งจาก Flutter
        methodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "autoConnect" -> handleAutoConnect(result)
                        "readWeight" -> handleReadWeight(call, result)
                        "disconnect" -> handleDisconnect(result)
                        "isConnected" -> handleIsConnected(result)
                        else -> result.notImplemented()
                    }
                }
            }
        // ตั้งค่า EventChannel สำหรับส่งเหตุการณ์ USB ไปยัง Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, usbEventsChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    usbEventSink = events
                    emitCurrentUsbState()
                }

                override fun onCancel(arguments: Any?) {
                    usbEventSink = null
                }
            })
    }

    // จัดการคำสั่ง autoConnect จาก Flutter
    private fun handleAutoConnect(result: MethodChannel.Result) {
        val manager = usbManager
        if (manager == null) {
            result.success(false)
            return
        }

        // ค้นหา USB serial drivers ทั้งหมด
        val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(manager)
        if (drivers.isEmpty()) {
            Log.w(logTag, "No USB serial drivers found")
            result.success(false)
            return
        }

        // เลือก driver ที่เหมาะสม
        val driver = selectDriver(drivers)
        if (driver == null) {
            Log.w(logTag, "No supported USB serial device detected")
            result.success(false)
            return
        }

        val device = driver.device
        Log.d(logTag, "Selected device: ${device.deviceName}, VID=${device.vendorId}, PID=${device.productId}")

        // ตรวจสอบว่ามีสิทธิ์เข้าถึง USB หรือไม่
        if (!manager.hasPermission(device)) {
            Log.d(logTag, "Requesting permission for ${device.deviceName}")
            requestUsbPermission(manager, device)
            result.success(false)
            return
        }

        // เปิด serial port ใน background thread
        Thread {
            val success = openSerialPort(driver)
            runOnUiThread {
                result.success(success)
            }
        }.start()
    }

    // จัดการคำสั่ง readWeight จาก Flutter
    private fun handleReadWeight(@Suppress("UNUSED_PARAMETER") call: MethodCall, result: MethodChannel.Result) {
        val port = serialPort
        if (port == null) {
            result.error("not_connected", "ยังไม่ได้เชื่อมต่ออุปกรณ์", null)
            return
        }

        // อ่านข้อมูลใน background thread เพื่อไม่ให้ block UI
        Thread {
            val outcome = readFromSerialPort(port)
            runOnUiThread {
                when (outcome) {
                    is SerialReadOutcome.Success -> result.success(outcome.payload)
                    is SerialReadOutcome.Failure -> result.error(outcome.code, outcome.message, null)
                }
            }
        }.start()
    }

    // จัดการคำสั่ง disconnect จาก Flutter
    private fun handleDisconnect(result: MethodChannel.Result) {
        closeSerialPort()
        result.success(true)
    }

    // จัดการคำสั่ง isConnected จาก Flutter
    private fun handleIsConnected(result: MethodChannel.Result) {
        result.success(serialPort != null)
    }

    // เก็บ config ที่กำลังใช้งาน
    private var activeSerialConfig: SerialConfig? = null

    // เปิดการเชื่อมต่อ serial port
    private fun openSerialPort(driver: UsbSerialDriver): Boolean {
        closeSerialPort()

        return try {
            val manager = usbManager ?: return false
            val connection = manager.openDevice(driver.device)
            if (connection == null) {
                Log.e(logTag, "Unable to open USB device")
                return false
            }

            val port = driver.ports.firstOrNull()
            if (port == null) {
                Log.e(logTag, "No serial ports exposed by device")
                connection.close()
                return false
            }

            port.open(connection)
            // ล้างบัฟเฟอร์ฮาร์ดแวร์เพื่อเริ่มต้นใหม่
            try {
                port.purgeHwBuffers(true, true)
            } catch (_: Exception) {
            }
            // ลด delay จาก 100ms เหลือ 50ms เพื่อเพิ่มความเร็ว
            try {
                Thread.sleep(50)
            } catch (_: InterruptedException) {
            }

            // ตั้งค่า serial parameters
            if (!configureSerialParameters(port)) {
                Log.e(logTag, "Unable to determine serial configuration")
                port.close()
                connection.close()
                return false
            }

            serialDriver = driver
            serialPort = port
            serialConnection = connection
            Log.d(logTag, "Serial port opened successfully")
            true
        } catch (ex: Exception) {
            Log.e(logTag, "Failed to open serial port", ex)
            closeSerialPort()
            false
        }
    }

    private fun readFromSerialPort(port: UsbSerialPort): SerialReadOutcome {
        return try {
            val buffer = ByteArray(512)
            val chunk = ByteArray(64)
            var totalRead = 0
            val start = System.currentTimeMillis()
            var lastReadAt = start

            // ลด timeout จาก 1000ms เหลือ 600ms และลด read timeout จาก 150ms เหลือ 100ms
            while (totalRead < buffer.size && System.currentTimeMillis() - start < 600) {
                val count = port.read(chunk, 100)
                if (count > 0) {
                    System.arraycopy(chunk, 0, buffer, totalRead, count)
                    totalRead += count
                    lastReadAt = System.currentTimeMillis()

                    // ตรวจสอบว่ามี line terminator หรือไม่ เพื่อหยุดอ่านเร็วขึ้น
                    val hasTerminator = chunk.take(count).any { byte ->
                        byte == 0x0A.toByte() || byte == 0x0D.toByte()
                    }
                    if (hasTerminator) break
                } else {
                    // ถ้าไม่มีข้อมูลใหม่มากกว่า 80ms ให้หยุดอ่าน (ลดจาก 120ms)
                    if (totalRead > 0 && System.currentTimeMillis() - lastReadAt > 80) {
                        break
                    }
                }
            }

            if (totalRead <= 0) {
                return SerialReadOutcome.Failure("no_data", "ไม่ได้รับข้อมูลจากเครื่องชั่ง")
            }

            val rawData = buffer.copyOfRange(0, totalRead)
            val sanitizedData = sanitizeForAscii(rawData, activeSerialConfig?.dataBits)
            val asciiPayload = sanitizedData.toString(Charsets.US_ASCII)
            val lines = asciiPayload
                .split("\r", "\n")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
            val firstLine = lines.firstOrNull() ?: ""
            val hexDump = rawData.joinToString(" ") { "%02X".format(it) }

            Log.d(logTag, "Raw serial payload ($totalRead bytes): $lines | HEX: $hexDump")

            val device = serialDriver?.device
            val payload = hashMapOf<String, Any?>(
                "port" to buildPortLabel(device),
                "raw" to firstLine.ifEmpty { asciiPayload.trim().ifEmpty { hexDump } },
                "rawHex" to hexDump,
                "devicePath" to device?.deviceName,
                "vendorId" to device?.vendorId,
                "productId" to device?.productId,
            )

            val asciiLinesWithDigits = lines.filter { line ->
                line.any { it.isDigit() }
            }

            var weightKg = asciiLinesWithDigits.firstNotNullOfOrNull { line ->
                parseWeight(line)
            }

            if (weightKg == null && totalRead <= 4) {
                val binaryWeight = parseBinaryWeight(rawData)
                weightKg = binaryWeight?.valueKg
                binaryWeight?.rawCounts?.let { payload["rawCounts"] = it }
            }

            if (weightKg != null) {
                payload["value"] = weightKg
                return SerialReadOutcome.Success(payload)
            }

            SerialReadOutcome.Failure(
                "invalid_payload",
                "แปลงค่าน้ำหนักไม่สำเร็จ: $hexDump",
            )
        } catch (ex: Exception) {
            Log.e(logTag, "Failed to read serial data", ex)
            closeSerialPort()
            SerialReadOutcome.Failure("device_disconnected", ex.localizedMessage ?: "เกิดข้อผิดพลาด")
        }
    }

    private fun configureSerialParameters(port: UsbSerialPort): Boolean {
        val attempted = mutableSetOf<SerialConfig>()
        // ลำดับความสำคัญ: ใช้ config ที่รู้จักก่อน จากนั้นลองตามลำดับ
        val sequence = buildList {
            lastKnownGoodConfig?.let { add(it) }
            addAll(serialConfigs)
        }

        sequence.forEach { config ->
            if (!attempted.add(config)) return@forEach
            try {
                // ตั้งค่าพารามิเตอร์ serial port
                port.setParameters(
                    config.baudRate,
                    config.dataBits,
                    config.stopBits,
                    config.parity,
                )
                port.dtr = true
                port.rts = true

                // อ่านตัวอย่างข้อมูลเพื่อตรวจสอบว่า config นี้ใช้ได้
                val sample = readAsciiSample(port, config.dataBits)
                if (sample != null && isLikelyWeightSample(sample)) {
                    activeSerialConfig = config
                    lastKnownGoodConfig = config
                    Log.d(logTag, "Using serial config ${config.label}, sample='$sample'")
                    return true
                }
            } catch (ex: Exception) {
                Log.w(logTag, "Serial config ${config.label} failed", ex)
            }
        }
        activeSerialConfig = null
        return false
    }

    // ทำความสะอาดข้อมูลสำหรับ ASCII (7-bit data)
    private fun sanitizeForAscii(data: ByteArray, dataBits: Int?): ByteArray {
        if (dataBits != UsbSerialPort.DATABITS_7) {
            return data
        }
        // ตัดบิตที่ 8 ออกสำหรับ 7-bit data
        val sanitized = ByteArray(data.size)
        data.forEachIndexed { index, byte ->
            sanitized[index] = (byte.toInt() and 0x7F).toByte()
        }
        return sanitized
    }

    private fun readAsciiSample(port: UsbSerialPort, dataBits: Int): String? {
        return try {
            val buffer = ByteArray(128)
            // ลด timeout จาก 200ms เหลือ 150ms เพื่อเพิ่มความเร็วในการทดสอบ config
            val bytes = port.read(buffer, 150)
            if (bytes <= 0) return null
            val raw = buffer.copyOf(bytes)
            val sanitized = sanitizeForAscii(raw, dataBits)
            // กรองเฉพาะตัวอักษรที่อ่านได้และ line terminators
            sanitized
                .filter { it in 32..126 || it == 0x0A.toByte() || it == 0x0D.toByte() }
                .toByteArray()
                .toString(Charsets.US_ASCII)
                .trim()
                .takeIf { it.isNotEmpty() }
        } catch (ex: Exception) {
            null
        }
    }

    // แปลงข้อความเป็นค่าน้ำหนัก (กิโลกรัม)
    private fun parseWeight(raw: String): Double? {
        val normalized = raw.lowercase(Locale.ROOT)
        val match = weightRegex.find(normalized) ?: return null
        val numeric = match.value.replace(",", ".").toDoubleOrNull() ?: return null

        // ตรวจสอบว่าเป็นหน่วยกรัมหรือกิโลกรัม
        val isGram = normalized.contains(" g") && !normalized.contains("kg")
        return if (isGram) numeric / 1000.0 else numeric
    }

    // แปลงข้อมูลแบบ binary เป็นค่าน้ำหนัก (สำหรับเครื่องชั่งบางรุ่น)
    private fun parseBinaryWeight(data: ByteArray): BinaryWeight? {
        // ลองแปลงเป็น 16-bit integer (2 bytes)
        if (data.size >= 2) {
            val shortValue = ByteBuffer.wrap(data, 0, 2)
                .order(ByteOrder.LITTLE_ENDIAN)
                .short
                .toInt()
            val kilograms = shortValue / 1000.0
            if (abs(kilograms) < 500) {
                return BinaryWeight(kilograms, shortValue)
            }
        }

        // ลองแปลงเป็น 32-bit float หรือ integer (4 bytes)
        if (data.size >= 4) {
            val floatValue = ByteBuffer.wrap(data, 0, 4)
                .order(ByteOrder.LITTLE_ENDIAN)
                .float
            if (floatValue.isFinite() && abs(floatValue) < 500) {
                return BinaryWeight(floatValue.toDouble())
            }

            val intValue = ByteBuffer.wrap(data, 0, 4)
                .order(ByteOrder.LITTLE_ENDIAN)
                .int
            val kilograms = intValue / 1000.0
            if (abs(kilograms) < 5000) {
                return BinaryWeight(kilograms, intValue)
            }
        }

        return null
    }

    // เลือก USB driver ที่เหมาะสม (ให้ความสำคัญกับ CH340 chip)
    private fun selectDriver(drivers: List<UsbSerialDriver>): UsbSerialDriver? {
        if (drivers.isEmpty()) return null
        // ลองหา CH340 chip (VID:PID = 1A86:7523) ก่อน
        return drivers.firstOrNull { driver ->
            val device = driver.device
            device.vendorId == 0x1A86 && device.productId == 0x7523
        } ?: drivers.firstOrNull() // ถ้าไม่เจอให้ใช้ตัวแรก
    }

    // สร้างชื่อ port สำหรับแสดงผล
    private fun buildPortLabel(device: UsbDevice?): String {
        if (device == null) return "USB"
        val id = "${device.vendorId}:${device.productId}"
        return "${device.deviceName} ($id)"
    }

    // ปิดการเชื่อมต่อ serial port
    private fun closeSerialPort() {
        try {
            serialPort?.close()
        } catch (ex: Exception) {
            Log.w(logTag, "Error closing serial port", ex)
        } finally {
            serialConnection?.close()
            serialConnection = null
            serialPort = null
            serialDriver = null
            activeSerialConfig = null
        }
    }

    // ตรวจสอบว่าข้อมูลตัวอย่างน่าจะเป็นค่าน้ำหนักหรือไม่
    private fun isLikelyWeightSample(sample: String): Boolean {
        val trimmed = sample.trim()
        if (trimmed.length < 4) return false

        // ต้องมีตัวเลขอย่างน้อย 3 ตัว
        val digits = trimmed.count { it.isDigit() }
        if (digits < 3) return false

        val hasDecimal = trimmed.any { it == '.' || it == ',' }

        // ถ้าไม่มีจุดทศนิยม ต้องเป็นตัวเลขล้วนๆ
        if (!hasDecimal) {
            val looksInteger = trimmed.all { it.isDigit() || it == ' ' }
            if (!looksInteger) return false
        }

        // นับตัวอักษรที่ไม่ใช่ตัวเลข/สัญลักษณ์ที่คาดหวัง
        val invalidChars = trimmed.count { ch ->
            !(ch.isDigit() ||
                    ch == '.' ||
                    ch == ',' ||
                    ch == '-' ||
                    ch == '+' ||
                    ch == ' ' ||
                    ch == 'k' ||
                    ch == 'g' ||
                    ch == 'K' ||
                    ch == 'G')
        }
        // อนุญาตให้มีตัวอักษรแปลกปลอมได้ไม่เกิน 20%
        return invalidChars <= trimmed.length / 5
    }

    // ขออนุญาตใช้ USB device
    private fun requestUsbPermission(usbManager: UsbManager, device: UsbDevice) {
        val mutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag
        val pendingIntent =
            PendingIntent.getBroadcast(this, 0, Intent(usbPermissionAction), flags)
        usbManager.requestPermission(device, pendingIntent)
    }
}

// คลาสเก็บการตั้งค่า serial port
private data class SerialConfig(
    val label: String,
    val baudRate: Int,
    val dataBits: Int,
    val stopBits: Int,
    val parity: Int,
)

// ผลลัพธ์จากการอ่านข้อมูล serial
private sealed class SerialReadOutcome {
    data class Success(val payload: Map<String, Any?>) : SerialReadOutcome()
    data class Failure(val code: String, val message: String) : SerialReadOutcome()
}

// คลาสเก็บค่าน้ำหนักแบบ binary
private data class BinaryWeight(val valueKg: Double, val rawCounts: Int? = null)
