/// Model representing a weight reading from the USB scale
class WeightReading {
  const WeightReading({
    required this.port,
    required this.raw,
    required this.timestamp,
    this.value,
  });

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

  String get timestampFormatted =>
      '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}:'
      '${timestamp.second.toString().padLeft(2, '0')}';
}
