// =============================================================================
// Candidate payload generation for the Auto Test Lab.
//
// All payloads are EXPERIMENTAL / UNVERIFIED probes.
// Do NOT add motor control, throttle, braking, or speed-limit payloads here.
//
// Mutation targets are limited to bytes[2..5] — the structural type bytes
// after the AA 55 header — to keep the candidate set human-reviewable.
// =============================================================================

import '../commands/command_map.dart';

/// A single candidate payload queued for the auto-test runner.
class AutoTestCandidate {
  final String label;

  /// Raw bytes BEFORE checksum / padding are applied.
  final List<int> rawBytes;

  /// Short description shown in the UI.
  final String description;

  const AutoTestCandidate({
    required this.label,
    required this.rawBytes,
    required this.description,
  });
}

/// How to generate the candidate list.
enum CandidateSource {
  /// Use the existing manual grid (A1–C4) from [kCommandMap] — 12 candidates.
  manualGrid,

  /// Fix all bytes except byte[2]; sweep byte[2] through [kByte2Candidates].
  byte2Sweep,

  /// Fix all bytes except byte[3]; sweep byte[3] through [kByte3Candidates].
  byte3Sweep,

  /// Sweep both byte[2] and byte[3]; produces up to maxCandidates entries.
  dualSweep,
}

String candidateSourceLabel(CandidateSource s) => switch (s) {
      CandidateSource.manualGrid => 'Manual grid (A1–C4)',
      CandidateSource.byte2Sweep => 'Byte[2] sweep',
      CandidateSource.byte3Sweep => 'Byte[3] sweep',
      CandidateSource.dualSweep  => 'Dual sweep (byte[2] × byte[3])',
    };

/// Human-selected byte[2] candidate values — NOT a brute-force sweep.
const kByte2Candidates = <int>[
  0x00, 0x01, 0x02, 0x03,
  0x10, 0x11, 0x12,
  0x20, 0x21, 0x22, 0x30,
];

/// Human-selected byte[3] candidate values.
const kByte3Candidates = <int>[0x00, 0x01, 0x02, 0xFF];

/// Default 20-byte base template: AA 55 header, rest 0x00.
const kDefaultTemplate = <int>[
  0xAA, 0x55, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
];

/// Returns a flat list of [AutoTestCandidate]s, capped at [maxCandidates].
///
/// [template] is cloned for every mutation — never modified in place.
List<AutoTestCandidate> generateCandidates({
  required CandidateSource source,
  List<int> template = kDefaultTemplate,
  List<int> byte2Values = kByte2Candidates,
  List<int> byte3Values = kByte3Candidates,
  int maxCandidates = 20,
}) {
  final raw = switch (source) {
    CandidateSource.manualGrid => _fromGrid(),
    CandidateSource.byte2Sweep => _byte2Sweep(template, byte2Values),
    CandidateSource.byte3Sweep => _byte3Sweep(template, byte3Values),
    CandidateSource.dualSweep  => _dualSweep(template, byte2Values, byte3Values),
  };
  return raw.take(maxCandidates).toList();
}

// -- Private generators -------------------------------------------------------

List<AutoTestCandidate> _fromGrid() => [
  for (final row in kButtonLayout)
    for (final label in row)
      if (kCommandMap.containsKey(label))
        AutoTestCandidate(
          label: label,
          rawBytes: List<int>.unmodifiable(kCommandMap[label]!),
          description: bytesToHex(kCommandMap[label]!),
        ),
];

List<AutoTestCandidate> _byte2Sweep(List<int> tmpl, List<int> vals) {
  final base = _pad20(tmpl);
  return [
    for (final v in vals)
      AutoTestCandidate(
        label: 'b2=${_hex(v)}',
        rawBytes: List<int>.from(base)..[2] = v,
        description: '[EXP] byte[2]=${_hex(v)}, rest fixed',
      ),
  ];
}

List<AutoTestCandidate> _byte3Sweep(List<int> tmpl, List<int> vals) {
  final base = _pad20(tmpl);
  return [
    for (final v in vals)
      AutoTestCandidate(
        label: 'b3=${_hex(v)}',
        rawBytes: List<int>.from(base)..[3] = v,
        description: '[EXP] byte[3]=${_hex(v)}, rest fixed',
      ),
  ];
}

List<AutoTestCandidate> _dualSweep(
    List<int> tmpl, List<int> b2, List<int> b3) {
  final base = _pad20(tmpl);
  return [
    for (final v2 in b2)
      for (final v3 in b3)
        AutoTestCandidate(
          label: 'b2=${_hex(v2)} b3=${_hex(v3)}',
          rawBytes: List<int>.from(base)
            ..[2] = v2
            ..[3] = v3,
          description: '[EXP] byte[2]=${_hex(v2)} byte[3]=${_hex(v3)}',
        ),
  ];
}

List<int> _pad20(List<int> bytes) {
  if (bytes.length >= 20) return bytes.take(20).toList();
  return [...bytes, ...List.filled(20 - bytes.length, 0)];
}

String _hex(int v) =>
    '0x${v.toRadixString(16).padLeft(2, '0').toUpperCase()}';
