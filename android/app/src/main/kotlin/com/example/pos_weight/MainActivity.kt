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
    private val usbPermissionAction: String by lazy { "$packageName.USB_PERMISSION" }
    private val logTag = "SerialScale"

    private var methodChannel: MethodChannel? = null
    private var receiverRegistered = false

    private var usbManager: UsbManager? = null
    private var serialDriver: UsbSerialDriver? = null
    private var serialPort: UsbSerialPort? = null
    private var serialConnection: UsbDeviceConnection? = null

    private val weightRegex = Regex("[-+]?\\d+(?:[.,]\\d+)?")

    private val serialConfigs = listOf(
        SerialConfig("2400 7E1", 2400, UsbSerialPort.DATABITS_7, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_EVEN),
        SerialConfig("2400 8N1", 2400, UsbSerialPort.DATABITS_8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE),
        SerialConfig("4800 7E1", 4800, UsbSerialPort.DATABITS_7, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_EVEN),
        SerialConfig("4800 8N1", 4800, UsbSerialPort.DATABITS_8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE),
        SerialConfig("9600 7E1", 9600, UsbSerialPort.DATABITS_7, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_EVEN),
        SerialConfig("9600 8N1", 9600, UsbSerialPort.DATABITS_8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE),
    )

    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != usbPermissionAction) return
            val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            }
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            val message = if (granted) {
                "อนุญาตการเข้าถึง ${device?.deviceName ?: "USB"} แล้ว"
            } else {
                "ปฏิเสธการเข้าถึง USB"
            }
            Toast.makeText(this@MainActivity, message, Toast.LENGTH_SHORT).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        registerUsbPermissionReceiver()
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            try {
                unregisterReceiver(usbPermissionReceiver)
            } catch (ex: IllegalArgumentException) {
                Log.w(logTag, "Receiver already unregistered", ex)
            }
            receiverRegistered = false
        }
        closeSerialPort()
        super.onDestroy()
    }

    private fun registerUsbPermissionReceiver() {
        val filter = IntentFilter(usbPermissionAction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbPermissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(usbPermissionReceiver, filter)
        }
        receiverRegistered = true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }

    private fun handleAutoConnect(result: MethodChannel.Result) {
        val manager = usbManager
        if (manager == null) {
            result.success(false)
            return
        }

        val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(manager)
        if (drivers.isEmpty()) {
            Log.w(logTag, "No USB serial drivers found")
            result.success(false)
            return
        }

        val driver = selectDriver(drivers)
        if (driver == null) {
            Log.w(logTag, "No supported USB serial device detected")
            result.success(false)
            return
        }

        val device = driver.device
        Log.d(logTag, "Selected device: ${device.deviceName}, VID=${device.vendorId}, PID=${device.productId}")

        if (!manager.hasPermission(device)) {
            Log.d(logTag, "Requesting permission for ${device.deviceName}")
            requestUsbPermission(manager, device)
            result.success(false)
            return
        }

        Thread {
            val success = openSerialPort(driver)
            runOnUiThread {
                result.success(success)
            }
        }.start()
    }

    private fun handleReadWeight(@Suppress("UNUSED_PARAMETER") call: MethodCall, result: MethodChannel.Result) {
        val port = serialPort
        if (port == null) {
            result.error("not_connected", "ยังไม่ได้เชื่อมต่ออุปกรณ์", null)
            return
        }

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

    private fun handleDisconnect(result: MethodChannel.Result) {
        closeSerialPort()
        result.success(true)
    }

    private fun handleIsConnected(result: MethodChannel.Result) {
        result.success(serialPort != null)
    }

    private var activeSerialConfig: SerialConfig? = null

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

            while (totalRead < buffer.size && System.currentTimeMillis() - start < 1000) {
                val count = port.read(chunk, 150)
                if (count > 0) {
                    System.arraycopy(chunk, 0, buffer, totalRead, count)
                    totalRead += count
                    lastReadAt = System.currentTimeMillis()

                    val hasTerminator = chunk.take(count).any { byte ->
                        byte == 0x0A.toByte() || byte == 0x0D.toByte()
                    }
                    if (hasTerminator) break
                } else {
                    if (totalRead > 0 && System.currentTimeMillis() - lastReadAt > 120) {
                        break
                    }
                }
            }

            if (totalRead <= 0) {
                return SerialReadOutcome.Failure("no_data", "ไม่ได้รับข้อมูลจากเครื่องชั่ง")
            }

            val data = buffer.copyOfRange(0, totalRead)
            val lines = data.toString(Charsets.US_ASCII)
                .split("\r", "\n")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
            val firstLine = lines.firstOrNull() ?: ""
            val hexDump = data.joinToString(" ") { "%02X".format(it) }

            Log.d(logTag, "Raw serial payload ($totalRead bytes): $lines | HEX: $hexDump")

            val device = serialDriver?.device
            val payload = hashMapOf<String, Any?>(
                "port" to buildPortLabel(device),
                "raw" to firstLine.ifEmpty { hexDump },
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
                val binaryWeight = parseBinaryWeight(data)
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
            SerialReadOutcome.Failure("read_error", ex.localizedMessage ?: "เกิดข้อผิดพลาด")
        }
    }

    private fun configureSerialParameters(port: UsbSerialPort): Boolean {
        serialConfigs.forEach { config ->
            try {
                port.setParameters(
                    config.baudRate,
                    config.dataBits,
                    config.stopBits,
                    config.parity,
                )
                port.dtr = true
                port.rts = true

                val sample = readAsciiSample(port)
                if (sample != null && sample.any { it.isDigit() }) {
                    activeSerialConfig = config
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

    private fun readAsciiSample(port: UsbSerialPort): String? {
        return try {
            val buffer = ByteArray(128)
            val bytes = port.read(buffer, 200)
            if (bytes <= 0) return null
            buffer.copyOf(bytes)
                .filter { it in 32..126 || it == 0x0A.toByte() || it == 0x0D.toByte() }
                .toByteArray()
                .toString(Charsets.US_ASCII)
                .trim()
                .takeIf { it.isNotEmpty() }
        } catch (ex: Exception) {
            null
        }
    }

    private fun parseWeight(raw: String): Double? {
        val normalized = raw.lowercase(Locale.ROOT)
        val match = weightRegex.find(normalized) ?: return null
        val numeric = match.value.replace(",", ".").toDoubleOrNull() ?: return null

        val isGram = normalized.contains(" g") && !normalized.contains("kg")
        return if (isGram) numeric / 1000.0 else numeric
    }

    private fun parseBinaryWeight(data: ByteArray): BinaryWeight? {
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

    private fun selectDriver(drivers: List<UsbSerialDriver>): UsbSerialDriver? {
        if (drivers.isEmpty()) return null
        return drivers.firstOrNull { driver ->
            val device = driver.device
            device.vendorId == 0x1A86 && device.productId == 0x7523
        } ?: drivers.firstOrNull()
    }

    private fun buildPortLabel(device: UsbDevice?): String {
        if (device == null) return "USB"
        val id = "${device.vendorId}:${device.productId}"
        return "${device.deviceName} ($id)"
    }

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
        }
    }

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

private data class SerialConfig(
    val label: String,
    val baudRate: Int,
    val dataBits: Int,
    val stopBits: Int,
    val parity: Int,
)

private sealed class SerialReadOutcome {
    data class Success(val payload: Map<String, Any?>) : SerialReadOutcome()
    data class Failure(val code: String, val message: String) : SerialReadOutcome()
}

private data class BinaryWeight(val valueKg: Double, val rawCounts: Int? = null)
