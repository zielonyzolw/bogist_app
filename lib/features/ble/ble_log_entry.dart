enum LogDirection { rx, tx }

/// A single entry in the unified BLE debug log.
/// Covers both RX notification frames and TX write commands.
class BleLogEntry {
  final DateTime timestamp;
  final LogDirection direction;

  /// Upper-case hex string, e.g. "AA 55 01 00 …"
  final String hex;

  /// Human-readable label for TX entries, e.g. "A1".
  /// Null for RX notification frames.
  final String? label;

  /// Parsed speed from an RX frame (km/h). Null for TX.
  /// NOTE: field interpretation is tentative/unverified.
  final int? parsedSpeed;

  /// Parsed raw battery byte from an RX frame. Null for TX.
  /// NOTE: field interpretation is tentative/unverified.
  final int? parsedBattery;

  /// Auto-assigned structural category label, e.g. "Frame-A".
  /// Populated for RX entries after the FrameClassifier has seen the frame.
  /// Null for TX entries.
  final String? frameCategory;

  const BleLogEntry({
    required this.timestamp,
    required this.direction,
    required this.hex,
    this.label,
    this.parsedSpeed,
    this.parsedBattery,
    this.frameCategory,
  });
}
