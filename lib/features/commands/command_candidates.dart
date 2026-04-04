// =============================================================================
// EDIT THIS FILE to add, remove, or adjust candidate command payloads.
//
// IMPORTANT: None of these payloads are verified to work with any BOGIST
// scooter. Every entry is labeled [CANDIDATE ONLY] and must stay that way
// until confirmed by observing a real protocol capture.
//
// SAFE CATEGORIES ONLY:
//   lock, unlock, lights, mode switching
//
// DO NOT ADD:
//   motor control, throttle, braking, speed limit changes, firmware update
// =============================================================================

class CandidateCommand {
  final String label;
  final List<int> bytes;

  const CandidateCommand({required this.label, required this.bytes});

  /// Upper-case hex string for display, e.g. "AA 55 20 00 00 00"
  String get hex =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
}

class CommandCandidates {
  // ---------------------------------------------------------------------------
  // Lock
  // ---------------------------------------------------------------------------
  static const List<CandidateCommand> lock = [
    CandidateCommand(
      label: 'AA 55 — byte[2]=0x20 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x20, 0x00, 0x00, 0x00],
    ),
    CandidateCommand(
      label: 'AA 55 — byte[2]=0x21 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x21, 0x00, 0x00, 0x00],
    ),
    CandidateCommand(
      label: 'AA 55 — byte[2]=0x05 byte[5]=0x01 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x05, 0x00, 0x00, 0x01],
    ),
  ];

  // ---------------------------------------------------------------------------
  // Unlock
  // ---------------------------------------------------------------------------
  static const List<CandidateCommand> unlock = [
    CandidateCommand(
      label: 'AA 55 — byte[2]=0x22 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x22, 0x00, 0x00, 0x00],
    ),
    CandidateCommand(
      label: 'AA 55 — byte[2]=0x23 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x23, 0x00, 0x00, 0x00],
    ),
    CandidateCommand(
      label: 'AA 55 — byte[2]=0x05 byte[5]=0x00 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x05, 0x00, 0x00, 0x00],
    ),
  ];

  // ---------------------------------------------------------------------------
  // Light ON
  // ---------------------------------------------------------------------------
  static const List<CandidateCommand> lightOn = [
    CandidateCommand(
      label: 'AA 55 — light flag byte[3]=0x01 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x11, 0x01, 0x00, 0x00],
    ),
    CandidateCommand(
      label: 'AA 55 — byte[2]=0x12 byte[3]=0x01 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x12, 0x01, 0x00, 0x00],
    ),
    CandidateCommand(
      label: 'Short probe — 0x01 only [CANDIDATE ONLY]',
      bytes: [0x01],
    ),
  ];

  // ---------------------------------------------------------------------------
  // Light OFF
  // ---------------------------------------------------------------------------
  static const List<CandidateCommand> lightOff = [
    CandidateCommand(
      label: 'AA 55 — light flag byte[3]=0x00 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x11, 0x00, 0x00, 0x00],
    ),
    CandidateCommand(
      label: 'AA 55 — byte[2]=0x12 byte[3]=0x00 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x12, 0x00, 0x00, 0x00],
    ),
    CandidateCommand(
      label: 'Short probe — 0x00 only [CANDIDATE ONLY]',
      bytes: [0x00],
    ),
  ];

  // ---------------------------------------------------------------------------
  // Mode 1  (eco / slow)
  // ---------------------------------------------------------------------------
  static const List<CandidateCommand> mode1 = [
    CandidateCommand(
      label: 'AA 55 — mode byte[3]=0x01 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x30, 0x01, 0x00, 0x00],
    ),
    CandidateCommand(
      label: 'AA 55 — byte[2]=0x03 byte[3]=0x01 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x03, 0x01, 0x00, 0x00],
    ),
  ];

  // ---------------------------------------------------------------------------
  // Mode 2  (standard)
  // ---------------------------------------------------------------------------
  static const List<CandidateCommand> mode2 = [
    CandidateCommand(
      label: 'AA 55 — mode byte[3]=0x02 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x30, 0x02, 0x00, 0x00],
    ),
    CandidateCommand(
      label: 'AA 55 — byte[2]=0x03 byte[3]=0x02 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x03, 0x02, 0x00, 0x00],
    ),
  ];

  // ---------------------------------------------------------------------------
  // Mode 3  (sport / fast)
  // ---------------------------------------------------------------------------
  static const List<CandidateCommand> mode3 = [
    CandidateCommand(
      label: 'AA 55 — mode byte[3]=0x03 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x30, 0x03, 0x00, 0x00],
    ),
    CandidateCommand(
      label: 'AA 55 — byte[2]=0x03 byte[3]=0x03 [CANDIDATE ONLY]',
      bytes: [0xAA, 0x55, 0x03, 0x03, 0x00, 0x00],
    ),
  ];
}
