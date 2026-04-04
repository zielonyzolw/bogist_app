/// A single parsed notification frame from characteristic AB02.
class BleFrame {
  final DateTime timestamp;

  /// Raw bytes as received over BLE.
  final List<int> bytes;

  /// Upper-case hex string, e.g. "AA 55 01 00 …"
  final String hex;

  /// Speed in km/h, decoded from bytes 6–7 (little-endian).
  final int speed;

  /// Raw byte 8 — tentative battery-related value (0–255).
  final int batteryRaw;

  const BleFrame({
    required this.timestamp,
    required this.bytes,
    required this.hex,
    required this.speed,
    required this.batteryRaw,
  });
}
