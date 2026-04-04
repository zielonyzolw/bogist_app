import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../commands/checksum.dart';
import '../scooter/scooter_state.dart';
import 'test_record.dart';

/// A testing session: a named container for [TestRecord]s.
class TestSession {
  final String id;
  final DateTime startedAt;
  DateTime? endedAt;
  final List<TestRecord> records;

  TestSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    required this.records,
  });

  bool get isActive => endedAt == null;
  int get recordCount => records.length;
  int get finalizedCount => records.where((r) => r.isFinalized).length;

  Map<String, dynamic> toJson() => {
        'sessionId': id,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'recordCount': records.length,
        'records': records.map((r) => r.toJson()).toList(),
      };
}

/// Manages the active testing session and its test records.
///
/// Exposed via ChangeNotifierProvider so the UI rebuilds when records change.
class SessionService extends ChangeNotifier {
  TestSession? _session;

  TestSession? get session => _session;
  bool get isActive => _session != null && _session!.isActive;
  List<TestRecord> get records => List.unmodifiable(_session?.records ?? []);

  // ── Session lifecycle ────────────────────────────────────────────────────

  void startSession() {
    _session = TestSession(
      id: _genId(),
      startedAt: DateTime.now(),
      records: [],
    );
    notifyListeners();
  }

  void endSession() {
    if (_session == null || !_session!.isActive) return;
    _session!.endedAt = DateTime.now();
    notifyListeners();
  }

  /// Discard the current session completely.
  void clearSession() {
    _session = null;
    notifyListeners();
  }

  // ── Record management ────────────────────────────────────────────────────

  /// Creates a [TestRecord], appends it to the active session, and returns it.
  /// The caller must call [finalizeRecord] once the observation is collected.
  TestRecord addRecord({
    required String buttonLabel,
    required String payloadHex,
    required String originalPayloadHex,
    required WriteMode writeMode,
    required ChecksumMode checksumMode,
    required ScooterState stateBefore,
    required Set<String> framesBefore,
  }) {
    assert(_session != null && _session!.isActive, 'No active session');
    final record = TestRecord(
      sessionId: _session!.id,
      testId: '${_session!.id}-${_session!.records.length + 1}',
      buttonLabel: buttonLabel,
      payloadHex: payloadHex,
      originalPayloadHex: originalPayloadHex,
      writeMode: writeMode,
      checksumMode: checksumMode,
      sentAt: DateTime.now(),
      stateBefore: ScooterStateSnapshot.fromState(stateBefore),
      framesBefore: framesBefore,
    );
    _session!.records.add(record);
    notifyListeners();
    return record;
  }

  /// Fills in the post-send fields and marks the record as finalized.
  void finalizeRecord(
    TestRecord record, {
    required ScooterState stateAfter,
    required List<String> rxFrames,
    required String observation,
    required Set<String> newFrameTypes,
    required String frameDiff,
  }) {
    record.stateAfter = ScooterStateSnapshot.fromState(stateAfter);
    record.rxFramesInWindow = rxFrames;
    record.observation = observation;
    record.newFrameTypes = newFrameTypes;
    record.frameDiff = frameDiff;
    notifyListeners();
  }

  // ── Export ───────────────────────────────────────────────────────────────

  /// Returns the active (or ended) session as a pretty-printed JSON string.
  String exportJson() {
    if (_session == null) return '{}';
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(_session!.toJson());
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _genId() {
    final n = DateTime.now();
    return 'S${n.year}${_p(n.month)}${_p(n.day)}_${_p(n.hour)}${_p(n.minute)}${_p(n.second)}';
  }

  static String _p(int v) => v.toString().padLeft(2, '0');
}
