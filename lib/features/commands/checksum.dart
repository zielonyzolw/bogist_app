// =============================================================================
// TX write-mode selector and checksum/padding utilities.
//
// All checksums are CANDIDATE probes — not confirmed by a real protocol capture.
// =============================================================================

enum WriteMode { withResponse, withoutResponse }

enum ChecksumMode { none, xor, sum8, sum16le, crc16modbus }

/// Returns a human-readable short label for a [ChecksumMode].
String checksumLabel(ChecksumMode m) => switch (m) {
      ChecksumMode.none => 'None',
      ChecksumMode.xor => 'XOR',
      ChecksumMode.sum8 => 'SUM8',
      ChecksumMode.sum16le => 'SUM16 LE',
      ChecksumMode.crc16modbus => 'CRC16 Modbus',
    };

/// Pads [bytes] to 20 bytes by appending 0x00.
/// If already ≥ 20 bytes, returns a copy truncated to 20.
List<int> padTo20Bytes(List<int> bytes) {
  if (bytes.length >= 20) return List<int>.from(bytes.take(20));
  return [...bytes, ...List.filled(20 - bytes.length, 0)];
}

/// Appends the requested checksum byte(s) to [bytes] and returns the new list.
/// Does nothing (returns a copy) when [mode] is [ChecksumMode.none].
List<int> applyChecksum(List<int> bytes, ChecksumMode mode) {
  return switch (mode) {
    ChecksumMode.none => List<int>.from(bytes),
    ChecksumMode.xor => [...bytes, _xor(bytes)],
    ChecksumMode.sum8 => [...bytes, _sum8(bytes)],
    ChecksumMode.sum16le => () {
        final s = _sum16(bytes);
        return [...bytes, s & 0xFF, (s >> 8) & 0xFF];
      }(),
    ChecksumMode.crc16modbus => () {
        final c = _crc16modbus(bytes);
        return [...bytes, c & 0xFF, (c >> 8) & 0xFF];
      }(),
  };
}

/// Returns a one-line description of what [applyChecksum] will append.
String checksumInfo(ChecksumMode mode) => switch (mode) {
      ChecksumMode.none => 'no checksum appended',
      ChecksumMode.xor => 'XOR of all bytes appended (1 byte)',
      ChecksumMode.sum8 => 'SUM8 (byte sum mod 256) appended (1 byte)',
      ChecksumMode.sum16le => 'SUM16 little-endian appended (2 bytes)',
      ChecksumMode.crc16modbus => 'CRC16-Modbus little-endian appended (2 bytes)',
    };

// -- Private helpers ----------------------------------------------------------

int _xor(List<int> bytes) =>
    bytes.fold(0, (acc, b) => acc ^ b) & 0xFF;

int _sum8(List<int> bytes) =>
    bytes.fold(0, (acc, b) => acc + b) & 0xFF;

int _sum16(List<int> bytes) =>
    bytes.fold(0, (acc, b) => acc + b) & 0xFFFF;

int _crc16modbus(List<int> bytes) {
  int crc = 0xFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (int i = 0; i < 8; i++) {
      if ((crc & 0x0001) != 0) {
        crc = (crc >> 1) ^ 0xA001;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc & 0xFFFF;
}
