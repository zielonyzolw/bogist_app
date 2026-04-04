import '../commands/checksum.dart';
import '../scooter/scooter_state.dart';

/// Immutable snapshot of scooter telemetry captured at a specific moment.
class ScooterStateSnapshot {
  final int speed;
  final int batteryRaw;
  final String lastFrameHex;

  const ScooterStateSnapshot({
    required this.speed,
    required this.batteryRaw,
    required this.lastFrameHex,
  });

  factory ScooterStateSnapshot.fromState(ScooterState s) =>
      ScooterStateSnapshot(
        speed: s.speed,
        batteryRaw: s.batteryRaw,
        lastFrameHex: s.lastFrameHex,
      );

  Map<String, dynamic> toJson() => {
        'speed': speed,
        'batteryRaw': batteryRaw,
        'lastFrameHex': lastFrameHex,
      };

  @override
  String toString() => 'speed=$speed  battery_raw=$batteryRaw';
}

/// One complete test event: a button press → send → collect RX → observe.
///
/// [stateAfter], [rxFramesInWindow], and [observation] are filled in by
/// [SessionService.finalizeRecord] after the observation sheet is submitted.
class TestRecord {
  final String sessionId;
  final String testId;             // e.g. S20260404_143022-3
  final String buttonLabel;        // e.g. "A1"
  final String payloadHex;         // actual bytes sent (after checksum/padding)
  final String originalPayloadHex; // raw bytes before checksum/padding
  final WriteMode writeMode;
  final ChecksumMode checksumMode;
  final DateTime sentAt;
  final ScooterStateSnapshot stateBefore;

  ScooterStateSnapshot? stateAfter;

  /// RX frames (hex strings, chronological) received in the collection window.
  List<String> rxFramesInWindow;

  /// Frame-category labels seen in the 2-second window BEFORE TX.
  Set<String> framesBefore;

  /// Frame-category labels that appeared in the 2-second window AFTER TX
  /// but were NOT present before.
  Set<String> newFrameTypes;

  /// Human-readable diff summary produced by frameDiffSummary().
  String? frameDiff;

  /// User observation: quick-tag + optional free text, or null if not recorded.
  String? observation;

  TestRecord({
    required this.sessionId,
    required this.testId,
    required this.buttonLabel,
    required this.payloadHex,
    required this.originalPayloadHex,
    required this.writeMode,
    required this.checksumMode,
    required this.sentAt,
    required this.stateBefore,
    this.stateAfter,
    List<String>? rxFramesInWindow,
    Set<String>? framesBefore,
    Set<String>? newFrameTypes,
    this.frameDiff,
    this.observation,
  })  : rxFramesInWindow = rxFramesInWindow ?? [],
        framesBefore = framesBefore ?? {},
        newFrameTypes = newFrameTypes ?? {};

  bool get isFinalized => observation != null;

  Map<String, dynamic> toJson() => {
        'testId': testId,
        'buttonLabel': buttonLabel,
        'payloadHex': payloadHex,
        'originalPayloadHex': originalPayloadHex,
        'writeMode': writeMode.name,
        'checksumMode': checksumMode.name,
        'sentAt': sentAt.toIso8601String(),
        'stateBefore': stateBefore.toJson(),
        'stateAfter': stateAfter?.toJson(),
        'rxFramesInWindow': rxFramesInWindow,
        'framesBefore': framesBefore.toList(),
        'newFrameTypes': newFrameTypes.toList(),
        'frameDiff': frameDiff ?? '',
        'observation': observation ?? '',
      };
}
