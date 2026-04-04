/// Central location for BLE UUIDs and app-wide constants.
class BleConstants {
  static const String deviceName = 'BOGIST';

  static const String serviceUuid    = '0000AB00-0000-1000-8000-00805F9B34FB';
  static const String writeCharUuid  = '0000AB01-0000-1000-8000-00805F9B34FB';
  static const String notifyCharUuid = '0000AB02-0000-1000-8000-00805F9B34FB';

  /// Maximum entries kept in the unified TX/RX debug log.
  static const int maxLogEntries = 200;

  /// How long (ms) the observation sheet actively highlights incoming RX frames.
  static const int rxWindowMs = 3000;
}
