package com.example.pos_weight

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import kotlin.math.max
import kotlin.text.Charsets

class MainActivity : FlutterActivity() {
    private val channelName = "pos_weight/serial"
    private val usbPermissionAction by lazy { "${BuildConfig.APPLICATION_ID}.USB_PERMISSION" }
    private val logTag = "SerialScale"

    private var methodChannel: MethodChannel? = null
    private var receiverRegistered = false

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
                        "readWeight" -> handleReadWeight(call, result)
                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun handleReadWeight(call: MethodCall, result: MethodChannel.Result) {
        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        val portHint = call.argument<String>("port")?.trim().orEmpty()
        val baudRate = call.argument<Number>("baudRate")?.toInt() ?: 9600

        val device = selectUsbDevice(usbManager, portHint)
        if (device == null) {
            result.error(
                "device_not_found",
                "ไม่พบอุปกรณ์ USB Serial ที่ตรงกับ '$portHint'",
                null
            )
            return
        }

        if (!usbManager.hasPermission(device)) {
            requestUsbPermission(usbManager, device)
            result.error(
                "usb_permission",
                "กรุณาอนุญาตการเข้าถึงอุปกรณ์ ${device.deviceName} แล้วลองใหม่",
                null
            )
            return
        }

        Thread {
            val outcome = readFromUsbDevice(usbManager, device, baudRate)
            runOnUiThread {
                when (outcome) {
                    is SerialReadOutcome.Success -> result.success(outcome.payload)
                    is SerialReadOutcome.Failure ->
                        result.error(outcome.code, outcome.message, null)
                }
            }
        }.start()
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

    private fun selectUsbDevice(usbManager: UsbManager, hint: String): UsbDevice? {
        val devices = usbManager.deviceList.values
        if (devices.isEmpty()) {
            return null
        }
        if (hint.isBlank()) {
            return devices.first()
        }
        val normalized = hint.lowercase(Locale.US)
        return devices.firstOrNull { matchesDevice(it, normalized) } ?: devices.first()
    }

    private fun matchesDevice(device: UsbDevice, hint: String): Boolean {
        return tryMatch(device.deviceName, hint)
                || tryMatch("${device.vendorId}:${device.productId}", hint)
                || tryMatch(device.productName, hint)
                || tryMatch(device.manufacturerName, hint)
    }

    private fun tryMatch(candidate: String?, hint: String): Boolean {
        if (candidate.isNullOrBlank()) return false
        return candidate.lowercase(Locale.US).contains(hint)
    }

    private fun readFromUsbDevice(
        usbManager: UsbManager,
        device: UsbDevice,
        baudRate: Int,
    ): SerialReadOutcome {
        val connection = usbManager.openDevice(device)
            ?: return SerialReadOutcome.Failure(
                "connection_error",
                "ไม่สามารถเชื่อมต่อกับ ${device.deviceName}"
            )

        val claimedInterfaces = mutableListOf<UsbInterface>()
        return try {
            val controlInterface = findInterfaceByClass(
                device,
                UsbConstants.USB_CLASS_COMM
            )
            val dataInterface = findDataInterface(device)
                ?: return SerialReadOutcome.Failure("interface_error", "ไม่พบ data interface")

            if (controlInterface != null) {
                if (!connection.claimInterface(controlInterface, true)) {
                    return SerialReadOutcome.Failure("claim_error", "ไม่สามารถ claim interface")
                }
                claimedInterfaces.add(controlInterface)
            }

            if (!claimedInterfaces.contains(dataInterface)) {
                if (!connection.claimInterface(dataInterface, true)) {
                    return SerialReadOutcome.Failure("claim_error", "ไม่สามารถ claim interface")
                }
                claimedInterfaces.add(dataInterface)
            }

            if (!configureSerialConnection(connection, baudRate)) {
                return SerialReadOutcome.Failure("config_error", "ตั้งค่า serial ไม่สำเร็จ")
            }

            val inEndpoint = findInEndpoint(dataInterface)
                ?: return SerialReadOutcome.Failure("endpoint_error", "ไม่พบ IN endpoint")

            val packetSize = max(inEndpoint.maxPacketSize, 64)
            val buffer = ByteArray(packetSize)
            val bytesRead = connection.bulkTransfer(inEndpoint, buffer, buffer.size, 600)

            if (bytesRead <= 0) {
                return SerialReadOutcome.Failure("no_data", "ไม่ได้รับข้อมูลจากเครื่องชั่ง")
            }

            val raw = buffer.decodeToString(bytesRead)
            val trimmed = raw.trim()
            val numeric = extractNumericValue(trimmed)

            val payload = hashMapOf<String, Any?>(
                "port" to buildPortLabel(device),
                "raw" to trimmed,
                "devicePath" to device.deviceName,
                "vendorId" to device.vendorId,
                "productId" to device.productId,
            )
            if (numeric != null) {
                payload["value"] = numeric
            }

            SerialReadOutcome.Success(payload)
        } catch (ex: Exception) {
            Log.e(logTag, "Failed to read from USB", ex)
            SerialReadOutcome.Failure("read_error", ex.localizedMessage ?: "เกิดข้อผิดพลาด")
        } finally {
            claimedInterfaces.forEach { intf ->
                try {
                    connection.releaseInterface(intf)
                } catch (_: Exception) {
                }
            }
            connection.close()
        }
    }

    private fun findInterfaceByClass(device: UsbDevice, klass: Int): UsbInterface? {
        for (index in 0 until device.interfaceCount) {
            val candidate = device.getInterface(index)
            if (candidate.interfaceClass == klass) {
                return candidate
            }
        }
        return null
    }

    private fun findDataInterface(device: UsbDevice): UsbInterface? {
        val prioritized = mutableListOf<UsbInterface>()
        for (index in 0 until device.interfaceCount) {
            prioritized.add(device.getInterface(index))
        }
        return prioritized.sortedBy {
            when (it.interfaceClass) {
                UsbConstants.USB_CLASS_CDC_DATA -> 0
                UsbConstants.USB_CLASS_COMM -> 1
                UsbConstants.USB_CLASS_VENDOR_SPEC -> 2
                else -> 3
            }
        }.firstOrNull { it.endpointCount > 0 }
    }

    private fun findInEndpoint(usbInterface: UsbInterface): UsbEndpoint? {
        for (index in 0 until usbInterface.endpointCount) {
            val endpoint = usbInterface.getEndpoint(index)
            if (endpoint.direction == UsbConstants.USB_DIR_IN) {
                return endpoint
            }
        }
        return null
    }

    private fun configureSerialConnection(
        connection: UsbDeviceConnection,
        baudRate: Int,
    ): Boolean {
        val lineCoding = ByteBuffer.allocate(7).order(ByteOrder.LITTLE_ENDIAN).apply {
            putInt(baudRate)
            put(UsbCdcStopBitsBits.ONE.value)
            put(UsbCdcParity.NONE.value)
            put(8.toByte())
        }.array()

        val setLineCoding = connection.controlTransfer(
            0x21,
            0x20,
            0,
            0,
            lineCoding,
            lineCoding.size,
            1000
        )
        if (setLineCoding < 0) {
            return false
        }

        val setControlLineState = connection.controlTransfer(
            0x21,
            0x22,
            0x0003,
            0,
            null,
            0,
            1000
        )
        return setControlLineState >= 0
    }

    private fun ByteArray.decodeToString(length: Int): String {
        return String(this, 0, length, Charsets.US_ASCII)
    }

    private fun extractNumericValue(payload: String): Double? {
        if (payload.isEmpty()) return null
        val builder = StringBuilder()
        for (char in payload) {
            when {
                char.isDigit() || char == '.' || char == '-' || char == '+' -> builder.append(char)
                char == ',' -> builder.append('.')
                builder.isNotEmpty() -> break
            }
        }
        return builder.toString().toDoubleOrNull()
    }

    private fun buildPortLabel(device: UsbDevice): String {
        val id = "${device.vendorId}:${device.productId}"
        return "${device.deviceName} ($id)"
    }
}

private sealed class SerialReadOutcome {
    data class Success(val payload: Map<String, Any?>) : SerialReadOutcome()
    data class Failure(val code: String, val message: String) : SerialReadOutcome()
}

private enum class UsbCdcStopBitsBits(val value: Byte) {
    ONE(0),
    ONE_POINT_FIVE(1),
    TWO(2)
}

private enum class UsbCdcParity(val value: Byte) {
    NONE(0),
    ODD(1),
    EVEN(2),
    MARK(3),
    SPACE(4)
}
