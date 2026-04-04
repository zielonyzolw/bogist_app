// =============================================================================
// EDIT THIS FILE to change what each test button sends.
//
// Each entry maps ONE neutral button label (A1, B2, …) to ONE byte payload.
// Labels are intentionally neutral — do NOT rename them to "Lock", "Light", etc.
// until you have confirmed evidence from a real protocol capture.
//
// Rules:
//   • Do NOT add motor control, speed limit, throttle, or braking commands.
//   • All payloads are unverified reverse-engineering probes.
//   • Each button sends exactly one payload (no per-button candidate list).
//
// To add a new button: add an entry to kCommandMap and add the label to
// kButtonLayout.  The UI will automatically show it.
// =============================================================================

/// Maps button label → bytes to write to characteristic AB01.
///
/// Rows are A / B / C.  Columns are 1 / 2 / 3 / 4.
/// Bytes are candidate probes — not verified commands.
const Map<String, List<int>> kCommandMap = {
  // ── Row A — varies byte[2]: 0x01 .. 0x04 ─────────────────────────────────
  'A1': [0xAA, 0x55, 0x01, 0x00, 0x00, 0x00],
  'A2': [0xAA, 0x55, 0x02, 0x00, 0x00, 0x00],
  'A3': [0xAA, 0x55, 0x03, 0x00, 0x00, 0x00],
  'A4': [0xAA, 0x55, 0x04, 0x00, 0x00, 0x00],

  // ── Row B — varies byte[2]: 0x10 .. 0x12, with byte[3] toggle ────────────
  'B1': [0xAA, 0x55, 0x10, 0x00, 0x00, 0x00],
  'B2': [0xAA, 0x55, 0x11, 0x00, 0x00, 0x00],
  'B3': [0xAA, 0x55, 0x11, 0x01, 0x00, 0x00],
  'B4': [0xAA, 0x55, 0x12, 0x00, 0x00, 0x00],

  // ── Row C — varies byte[2]: 0x20 .. 0x30 range ───────────────────────────
  'C1': [0xAA, 0x55, 0x20, 0x00, 0x00, 0x00],
  'C2': [0xAA, 0x55, 0x21, 0x00, 0x00, 0x00],
  'C3': [0xAA, 0x55, 0x22, 0x00, 0x00, 0x00],
  'C4': [0xAA, 0x55, 0x30, 0x01, 0x00, 0x00],
};

/// Row × column layout used to render the button grid.
/// Each inner list is one row of button labels.
const List<List<String>> kButtonLayout = [
  ['A1', 'A2', 'A3', 'A4'],
  ['B1', 'B2', 'B3', 'B4'],
  ['C1', 'C2', 'C3', 'C4'],
];

/// Returns the upper-case hex string for [bytes], space-separated.
String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

/// Parses a hex string (e.g. "AA 55 01") into a byte list.
/// Returns null if the input is malformed.
List<int>? parseHex(String input) {
  final clean = input.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  if (clean.isEmpty || clean.length % 2 != 0) return null;
  try {
    return [
      for (int i = 0; i < clean.length; i += 2)
        int.parse(clean.substring(i, i + 2), radix: 16),
    ];
  } catch (_) {
    return null;
  }
}
