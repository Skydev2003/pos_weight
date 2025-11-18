/// Model representing a weight reading from the USB scale
class WeightReading {
  const WeightReading({
    required this.port,
    required this.raw,
    required this.timestamp,
    this.value,
  });

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

  /// Display-friendly numeric text with 3 decimal places when possible.
  String get displayValue {
    final double? resolvedValue = normalizedValue;
    if (resolvedValue != null) {
      return resolvedValue.toStringAsFixed(3);
    }
    return '--';
  }

  /// Normalized numeric value with small jitters snapped to zero.
  double? get normalizedValue {
    final resolvedValue = value ?? _parseRawValue();
    if (resolvedValue == null) return null;
    const zeroLockThreshold = 0.003;
    if (resolvedValue.abs() < zeroLockThreshold) {
      return 0;
    }
    return resolvedValue;
  }

  /// Raw reading stripped of special characters for debugging display.
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
