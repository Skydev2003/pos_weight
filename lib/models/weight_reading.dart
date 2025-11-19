/// นี่คือ โมเดลสำหรับการอ่านน้ำหนัก
class WeightReading {
  const WeightReading({
    required this.port,
    required this.raw,
    required this.timestamp,
    this.value,
  });
  //นี่คือ regex สำหรับดึงตัวเลขจากสตริง
  static final RegExp _numericPattern = RegExp(r'-?\d+(?:[.,]\d+)?');

  factory WeightReading.fromMap(Map<String, dynamic> map) {
    final dynamic rawValue = map['value'];
    double? parsedValue;
    if (rawValue is num) {
      parsedValue = rawValue.toDouble();
    } else if (rawValue is String) {
      parsedValue = double.tryParse(rawValue);
    }

    return WeightReading(
      port: (map['port'] as String?) ?? '',
      raw: (map['raw'] as String?) ?? '',
      timestamp: DateTime.now(),
      value: parsedValue,
    );
  }

  final String port;
  final String raw;
  final DateTime timestamp;
  final double? value;

  /// นี่คือ ค่าที่แสดงเป็นสตริง โดยมีทศนิยม 3 ตำแหน่ง หรือ '--' ถ้าไม่มีค่า
  String get displayValue {
    final double? resolvedValue = normalizedValue;
    if (resolvedValue != null) {
      return resolvedValue.toStringAsFixed(3);
    }
    return '--';
  }

  /// ค่าที่ถูกปรับให้เป็นปกติ โดยล็อกค่าใกล้ศูนย์ให้เป็น 0
  double? get normalizedValue {
    final resolvedValue = value ?? _parseRawValue();
    if (resolvedValue == null) return null;
    const zeroLockThreshold = 0.003;
    if (resolvedValue.abs() < zeroLockThreshold) {
      return 0;
    }
    return resolvedValue;
  }

  /// ค่าดิบที่ถูกทำความสะอาดเพื่อให้เหลือเฉพาะตัวเลข, จุดทศนิยม, เครื่องหมายบวกและลบ
  String get sanitizedRaw {
    final match = _numericPattern.firstMatch(raw);
    if (match != null) {
      return match.group(0)!.replaceAll(',', '.');
    }
    return raw.replaceAll(RegExp(r'[^0-9+\-.,]'), '');
  }

  double? _parseRawValue() {
    final match = _numericPattern.firstMatch(raw);
    if (match == null) return null;
    final normalized = match.group(0)!.replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  String get timestampFormatted =>
      '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}:'
      '${timestamp.second.toString().padLeft(2, '0')}';
}
