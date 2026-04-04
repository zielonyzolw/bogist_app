import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants.dart';
import '../analysis/frame_classifier.dart';
import '../commands/checksum.dart';
import '../scooter/bogist_parser.dart';
import '../scooter/scooter_state.dart';
import 'ble_log_entry.dart';

export 'ble_log_entry.dart';

enum BleConnectionStatus { disconnected, connecting, connected, error }

/// Central service for all BLE interactions.
///
/// Exposes scan results, connection state, parsed telemetry, and a unified
/// TX/RX log as ChangeNotifier state so UI widgets rebuild reactively.
class BleService extends ChangeNotifier {
  final _ble = FlutterReactiveBle();
  final _classifier = FrameClassifier();

  // -- Scan ------------------------------------------------------------------
  final List<DiscoveredDevice> _scannedDevices = [];
  bool _isScanning = false;
  StreamSubscription<DiscoveredDevice>? _scanSub;

  List<DiscoveredDevice> get scannedDevices => List.unmodifiable(_scannedDevices);
  bool get isScanning => _isScanning;

  // -- Connection ------------------------------------------------------------
  BleConnectionStatus _connectionStatus = BleConnectionStatus.disconnected;
  DiscoveredDevice? _connectedDevice;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;

  BleConnectionStatus get connectionStatus => _connectionStatus;
  DiscoveredDevice? get connectedDevice => _connectedDevice;

  // -- Telemetry -------------------------------------------------------------
  ScooterState _scooterState = const ScooterState();
  ScooterState get scooterState => _scooterState;

  // -- Frame classifier (read-only access for UI) ----------------------------
  FrameClassifier get frameClassifier => _classifier;

  // -- Unified TX/RX log -----------------------------------------------------
  final List<BleLogEntry> _log = [];
  List<BleLogEntry> get log => List.unmodifiable(_log);

  // -- Last error string (permissions, scan, connection) --------------------
  String? _error;
  String? get error => _error;

  // -- Public API ------------------------------------------------------------

  Future<void> startScan() async {
    if (_isScanning) return;
    _error = null;

    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      if (statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
        _error = 'Bluetooth / Location permissions denied.\n'
            'Please grant them in Settings.';
        notifyListeners();
        return;
      }
    }

    _scannedDevices.clear();
    _isScanning = true;
    notifyListeners();

    _scanSub = _ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen(
      (device) {
        final idx = _scannedDevices.indexWhere((d) => d.id == device.id);
        if (idx >= 0) {
          _scannedDevices[idx] = device;
        } else {
          _scannedDevices.add(device);
        }
        notifyListeners();
      },
      onError: (Object e) {
        _error = 'Scan error: $e';
        _isScanning = false;
        notifyListeners();
      },
      onDone: () {
        _isScanning = false;
        notifyListeners();
      },
    );
  }

  void stopScan() {
    _scanSub?.cancel();
    _scanSub = null;
    _isScanning = false;
    notifyListeners();
  }

  void connectToDevice(DiscoveredDevice device) {
    _cancelConnectionStreams(); // tear down any previous connection first

    _connectionStatus = BleConnectionStatus.connecting;
    _connectedDevice = device;
    _error = null;
    notifyListeners();

    _connectionSub = _ble
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (update) {
            // _connectionSub is nulled BEFORE cancel() in _cancelConnectionStreams,
            // so any in-flight post-disconnect event is silently dropped here.
            if (_connectionSub == null) return;

            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                _connectionStatus = BleConnectionStatus.connected;
                notifyListeners();
                _subscribeToNotifications(device.id);

              case DeviceConnectionState.disconnected:
                // Unexpected remote disconnect (e.g. scooter powered off).
                final notiSub = _notifySub;
                _notifySub = null;
                notiSub?.cancel();
                _connectionStatus = BleConnectionStatus.disconnected;
                notifyListeners();

              default:
                break;
            }
          },
          onError: (Object e) {
            if (_connectionSub == null) return;
            _error = 'Connection error: $e';
            _connectionStatus = BleConnectionStatus.error;
            notifyListeners();
          },
        );
  }

  /// Disconnect cleanly and prevent auto-reconnect.
  ///
  /// Subscription references are nulled BEFORE cancel() is called.
  /// Any stream event that fires during the async cancel sees null and exits
  /// early, preventing double state-resets or accidental reconnect triggers.
  void disconnect() {
    _cancelConnectionStreams();
    _connectionStatus = BleConnectionStatus.disconnected;
    _connectedDevice = null;
    notifyListeners();
  }

  void clearLog() {
    _log.clear();
    notifyListeners();
  }

  /// Write [bytes] to characteristic AB01 and append a TX log entry.
  ///
  /// [withResponse] selects writeWithResponse (default) vs writeWithoutResponse.
  ///
  /// Throws [StateError] if not connected, or rethrows BLE errors so the
  /// caller can display a SnackBar.
  Future<void> writeCommand(
    String label,
    List<int> bytes, {
    WriteMode writeMode = WriteMode.withResponse,
  }) async {
    if (_connectionStatus != BleConnectionStatus.connected ||
        _connectedDevice == null) {
      throw StateError('Not connected to a device');
    }

    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(BleConstants.serviceUuid),
      characteristicId: Uuid.parse(BleConstants.writeCharUuid),
      deviceId: _connectedDevice!.id,
    );

    if (writeMode == WriteMode.withResponse) {
      await _ble.writeCharacteristicWithResponse(characteristic, value: bytes);
    } else {
      await _ble.writeCharacteristicWithoutResponse(characteristic, value: bytes);
    }

    _appendLog(BleLogEntry(
      timestamp: DateTime.now(),
      direction: LogDirection.tx,
      hex: _bytesToHex(bytes),
      label: label,
    ));
  }

  /// Returns the hex strings of all RX frames logged at or after [since].
  List<String> rxFramesSince(DateTime since) => _log
      .where((e) =>
          e.direction == LogDirection.rx &&
          !e.timestamp.isBefore(since))
      .map((e) => e.hex)
      .toList();

  // -- Private ---------------------------------------------------------------

  /// Null refs first, then cancel — so callbacks that fire during async cancel
  /// see null subscriptions and return immediately without touching state.
  void _cancelConnectionStreams() {
    final connSub = _connectionSub;
    final notiSub = _notifySub;
    _connectionSub = null;
    _notifySub = null;
    connSub?.cancel();
    notiSub?.cancel();
  }

  void _subscribeToNotifications(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(BleConstants.serviceUuid),
      characteristicId: Uuid.parse(BleConstants.notifyCharUuid),
      deviceId: deviceId,
    );

    _notifySub = _ble.subscribeToCharacteristic(characteristic).listen(
      (data) {
        final frame = BogistParser.parse(data);
        if (frame == null) return;

        _scooterState = _scooterState.copyWith(
          speed: frame.speed,
          batteryRaw: frame.batteryRaw,
          lastFrameHex: frame.hex,
        );

        // Classify before appending so the log entry carries the label.
        final cat = _classifier.classify(frame.hex);

        _appendLog(BleLogEntry(
          timestamp: frame.timestamp,
          direction: LogDirection.rx,
          hex: frame.hex,
          parsedSpeed: frame.speed,
          parsedBattery: frame.batteryRaw,
          frameCategory: cat?.label,
        ));
      },
      onError: (Object e) {
        debugPrint('BLE notification error: $e');
      },
    );
  }

  void _appendLog(BleLogEntry entry) {
    _log.insert(0, entry);
    if (_log.length > BleConstants.maxLogEntries) _log.removeLast();
    notifyListeners();
  }

  static String _bytesToHex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  @override
  void dispose() {
    stopScan();
    _cancelConnectionStreams();
    super.dispose();
  }
}
