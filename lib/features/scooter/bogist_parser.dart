import 'ble_frame.dart';

/// Parses raw BLE notification bytes from characteristic AB02.
///
/// Frame layout (TENTATIVE / UNVERIFIED — derived from initial captures only):
///   [0]     0xAA  — header byte 0
///   [1]     0x55  — header byte 1
///   [2..5]  structural type key (used for frame classification)
///   [6..7]  TENTATIVE: speed, little-endian uint16 (km/h) — not confirmed
///   [8]     TENTATIVE: battery-related raw value — not confirmed
///   [9..]   unknown / possible checksum at end
///
/// Do NOT treat any parsed field as ground truth until confirmed by
/// controlled experiment (e.g. observing the field change at a known speed).
class BogistParser {
  static BleFrame? parse(List<int> data) {
    // Must start with AA 55 and be long enough to contain all fields.
    if (data.length < 10) return null;
    if (data[0] != 0xAA || data[1] != 0x55) return null;

    final hex = data
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');

    // TENTATIVE interpretation — treat as unverified candidates.
    final speed = data[6] | (data[7] << 8); // candidate: LE uint16
    final batteryRaw = data[8];              // candidate: raw byte

    return BleFrame(
      timestamp: DateTime.now(),
      bytes: List.unmodifiable(data),
      hex: hex,
      speed: speed,
      batteryRaw: batteryRaw,
    );
  }
}
