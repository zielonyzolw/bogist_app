import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/ble_service.dart';
import '../commands/checksum.dart';
import '../commands/command_map.dart';
import 'auto_test_candidate.dart';

// -- Data model ---------------------------------------------------------------

/// One completed or in-progress auto-test step.
class AutoTestEntry {
  final int index;
  final String label;
  final String payloadHex;      // final bytes sent (after checksum / padding)
  final String rawPayloadHex;   // bytes before checksum / padding
  final WriteMode writeMode;
  final ChecksumMode checksumMode;
  final DateTime sentAt;
  Set<String> frameTypesBefore; // frame category labels seen 2 s before TX
  Set<String> frameTypesAfter;  // frame category labels seen in RX window after TX
  bool newFrameDetected;        // true if typesAfter ⊃ typesBefore
  String? reaction;             // user observation tag, null until marked

  AutoTestEntry({
    required this.index,
    required this.label,
    required this.payloadHex,
    required this.rawPayloadHex,
    required this.writeMode,
    required this.checksumMode,
    required this.sentAt,
    required this.frameTypesBefore,
    Set<String>? frameTypesAfter,
    this.newFrameDetected = false,
    this.reaction,
  }) : frameTypesAfter = frameTypesAfter ?? {};
}

// -- Status enum --------------------------------------------------------------

enum AutoTestStatus { idle, running, paused, stopped, completed, error }

// -- Controller ---------------------------------------------------------------

/// Manages the auto-test sequence: building candidates, timed sends, logging,
/// and stop conditions.
///
/// Uses [BleService] for writes and frame lookup, but owns its own test log
/// and does not touch [SessionService].
class AutoTestController extends ChangeNotifier {
  final BleService _ble;

  // -- Run-time state ---------------------------------------------------------
  AutoTestStatus _status = AutoTestStatus.idle;
  List<AutoTestCandidate> _candidates = [];
  int _currentIndex = -1;
  int _countdownMs = 0;
  Timer? _timer;
  String? _error;

  // -- Settings (editable only when idle) ------------------------------------
  WriteMode _writeMode = WriteMode.withResponse;
  ChecksumMode _checksumMode = ChecksumMode.none;
  bool _padTo20 = true;
  CandidateSource _source = CandidateSource.manualGrid;
  bool _stopOnNewFrameType = false;
  bool _stopOnReactionMarked = false;
  int _maxTests = 20;

  static const int intervalMs = 3000;

  // -- Log -------------------------------------------------------------------
  final List<AutoTestEntry> _log = [];

  // -- Constructor -----------------------------------------------------------

  AutoTestController({required BleService ble}) : _ble = ble {
    _ble.addListener(_onBleChanged);
    _rebuildCandidates(); // initialise preview
  }

  // -- Getters ---------------------------------------------------------------

  AutoTestStatus get status => _status;
  List<AutoTestCandidate> get candidates => List.unmodifiable(_candidates);
  List<AutoTestEntry> get log => List.unmodifiable(_log);
  int get currentIndex => _currentIndex;
  int get totalCandidates => _candidates.length;
  int get countdownMs => _countdownMs;
  String? get error => _error;

  WriteMode get writeMode => _writeMode;
  ChecksumMode get checksumMode => _checksumMode;
  bool get padTo20 => _padTo20;
  CandidateSource get source => _source;
  bool get stopOnNewFrameType => _stopOnNewFrameType;
  bool get stopOnReactionMarked => _stopOnReactionMarked;
  int get maxTests => _maxTests;

  AutoTestEntry? get currentEntry =>
      (_currentIndex >= 0 && _currentIndex < _log.length)
          ? _log[_currentIndex]
          : null;

  // -- Settings setters (idle-only) ------------------------------------------

  void setWriteMode(WriteMode m) {
    if (_status != AutoTestStatus.idle) return;
    _writeMode = m;
    notifyListeners();
  }

  void setChecksumMode(ChecksumMode m) {
    if (_status != AutoTestStatus.idle) return;
    _checksumMode = m;
    notifyListeners();
  }

  void setPadTo20(bool v) {
    if (_status != AutoTestStatus.idle) return;
    _padTo20 = v;
    notifyListeners();
  }

  void setSource(CandidateSource s) {
    if (_status != AutoTestStatus.idle) return;
    _source = s;
    _rebuildCandidates();
  }

  void setMaxTests(int v) {
    if (_status != AutoTestStatus.idle) return;
    _maxTests = v.clamp(3, 20);
    _rebuildCandidates();
  }

  void setStopOnNewFrameType(bool v) {
    _stopOnNewFrameType = v;
    notifyListeners();
  }

  void setStopOnReactionMarked(bool v) {
    _stopOnReactionMarked = v;
    notifyListeners();
  }

  // -- Lifecycle -------------------------------------------------------------

  /// Starts the sequence. Returns false if preconditions are not met.
  bool start() {
    if (_status != AutoTestStatus.idle) return false;
    if (_ble.connectionStatus != BleConnectionStatus.connected) return false;

    _rebuildCandidates();
    if (_candidates.isEmpty) return false;

    _log.clear();
    _currentIndex = -1;
    _error = null;
    _status = AutoTestStatus.running;
    notifyListeners();

    _sendNext();
    return true;
  }

  void pause() {
    if (_status != AutoTestStatus.running) return;
    _timer?.cancel();
    _status = AutoTestStatus.paused;
    notifyListeners();
  }

  void resume() {
    if (_status != AutoTestStatus.paused) return;
    _status = AutoTestStatus.running;
    notifyListeners();
    // Resume countdown from where it was left (countdownMs still holds value).
    _startCountdown(fromMs: _countdownMs);
  }

  void stop() {
    if (_status != AutoTestStatus.running && _status != AutoTestStatus.paused) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _updateCurrentEntryFrames(); // finalise the in-progress entry
    _status = AutoTestStatus.stopped;
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _status = AutoTestStatus.idle;
    _log.clear();
    _currentIndex = -1;
    _countdownMs = 0;
    _error = null;
    _rebuildCandidates();
  }

  // -- Reaction marking ------------------------------------------------------

  void markReaction(int entryIndex, String reaction) {
    if (entryIndex < 0 || entryIndex >= _log.length) return;
    _log[entryIndex].reaction = reaction;
    notifyListeners();

    if (_stopOnReactionMarked && _status == AutoTestStatus.running) {
      stop();
    }
  }

  // -- Private ---------------------------------------------------------------

  void _rebuildCandidates() {
    _candidates = generateCandidates(
      source: _source,
      maxCandidates: _maxTests,
    );
    notifyListeners();
  }

  /// Sends the next candidate, or marks sequence complete if exhausted.
  Future<void> _sendNext() async {
    if (_status != AutoTestStatus.running) return;

    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _candidates.length) {
      // Sequence exhausted.
      _status = AutoTestStatus.completed;
      notifyListeners();
      return;
    }

    _currentIndex = nextIndex;
    final candidate = _candidates[nextIndex];

    // Build final bytes (checksum + optional padding).
    var bytes = applyChecksum(candidate.rawBytes, _checksumMode);
    if (_padTo20) bytes = padTo20Bytes(bytes);
    final payloadHex = bytesToHex(bytes);
    final rawHex = bytesToHex(candidate.rawBytes);

    // Snapshot frame types seen 2 seconds before TX.
    final beforeCutoff = DateTime.now().subtract(const Duration(seconds: 2));
    final typesBefore = _ble.frameClassifier.labelsIn(
      _ble.rxFramesSince(beforeCutoff),
    );

    // Create log entry before sending so UI updates immediately.
    final entry = AutoTestEntry(
      index: nextIndex,
      label: candidate.label,
      payloadHex: payloadHex,
      rawPayloadHex: rawHex,
      writeMode: _writeMode,
      checksumMode: _checksumMode,
      sentAt: DateTime.now(),
      frameTypesBefore: typesBefore,
    );
    _log.add(entry);
    notifyListeners();

    // Write to BLE.
    try {
      await _ble.writeCommand(
        '[Auto-${nextIndex + 1}] ${candidate.label}  [$payloadHex]',
        bytes,
        writeMode: _writeMode,
      );
    } catch (e) {
      _error = 'Error at test ${nextIndex + 1}: $e';
      _status = AutoTestStatus.error;
      notifyListeners();
      return;
    }

    // Start countdown to the next send.
    _startCountdown();
  }

  /// Starts (or restarts from a given offset) the inter-send countdown.
  void _startCountdown({int? fromMs}) {
    _timer?.cancel();
    _countdownMs = fromMs ?? intervalMs;
    notifyListeners();

    _timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (_status != AutoTestStatus.running) {
        t.cancel();
        return;
      }
      _countdownMs = (_countdownMs - 200).clamp(0, intervalMs);
      if (_countdownMs == 0) {
        t.cancel();
        _updateCurrentEntryFrames();
        _sendNext();
      } else {
        notifyListeners();
      }
    });
  }

  /// Updates the current entry with frame types observed since TX.
  /// Does NOT call notifyListeners — caller is responsible.
  void _updateCurrentEntryFrames() {
    if (_currentIndex < 0 || _currentIndex >= _log.length) return;
    final entry = _log[_currentIndex];
    final framesAfter = _ble.rxFramesSince(entry.sentAt);
    final typesAfter = _ble.frameClassifier.labelsIn(framesAfter);
    entry.frameTypesAfter = typesAfter;
    entry.newFrameDetected =
        typesAfter.difference(entry.frameTypesBefore).isNotEmpty;

    if (_stopOnNewFrameType &&
        entry.newFrameDetected &&
        _status == AutoTestStatus.running) {
      // Don't call stop() here — we're inside the timer; cancel cleanly.
      _timer?.cancel();
      _timer = null;
      _status = AutoTestStatus.stopped;
    }
  }

  void _onBleChanged() {
    if (_ble.connectionStatus != BleConnectionStatus.connected &&
        (_status == AutoTestStatus.running ||
            _status == AutoTestStatus.paused)) {
      _timer?.cancel();
      _timer = null;
      _error = 'Auto-test stopped: BLE disconnected.';
      _status = AutoTestStatus.stopped;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ble.removeListener(_onBleChanged);
    super.dispose();
  }
}
