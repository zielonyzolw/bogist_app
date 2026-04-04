import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../analysis/frame_classifier.dart';
import '../ble/ble_service.dart';
import '../commands/checksum.dart';
import '../commands/command_map.dart';
import '../session/session_service.dart';
import '../session/test_record.dart';
import 'debug_page.dart';

class TestLabPage extends StatefulWidget {
  const TestLabPage({super.key});

  @override
  State<TestLabPage> createState() => _TestLabPageState();
}

class _TestLabPageState extends State<TestLabPage> {
  final _hexController = TextEditingController();

  /// True while a send + observation sheet is in progress.
  bool _isTesting = false;

  // ── TX settings ──────────────────────────────────────────────────────────
  WriteMode _writeMode = WriteMode.withResponse;
  ChecksumMode _checksumMode = ChecksumMode.none;
  bool _padTo20 = false;

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final session = context.watch<SessionService>();
    final connected = ble.connectionStatus == BleConnectionStatus.connected;
    final buttonsEnabled = connected && !_isTesting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Command Test Lab'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Full BLE Log',
            onPressed: () => _push(const DebugPage()),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Warning
            const _WarningBanner(),
            const SizedBox(height: 12),

            // 2. Connection status
            _ConnectionCard(ble: ble),
            const SizedBox(height: 12),

            // 3. Live scooter state
            _LiveStateRow(ble: ble),
            const SizedBox(height: 8),

            // 4. Frame classification summary
            _FrameClassificationRow(ble: ble),
            const SizedBox(height: 12),

            // 5. TX Settings panel
            _SendSettingsPanel(
              writeMode: _writeMode,
              checksumMode: _checksumMode,
              padTo20: _padTo20,
              onWriteModeChanged: (m) => setState(() => _writeMode = m),
              onChecksumModeChanged: (m) => setState(() => _checksumMode = m),
              onPadTo20Changed: (v) => setState(() => _padTo20 = v),
            ),
            const SizedBox(height: 12),

            // 6. Session controls
            _SessionControls(session: session),
            const Divider(height: 24),

            // 7. Test button grid
            _SectionHeader(
              'TEST BUTTONS',
              sub: 'Each button sends exactly one probe payload to AB01.',
            ),
            const SizedBox(height: 8),
            _ButtonGrid(
              enabled: buttonsEnabled,
              onTap: _onGridButtonTap,
            ),
            const SizedBox(height: 16),

            // 8. Custom hex
            _SectionHeader('CUSTOM HEX (ADVANCED)'),
            const SizedBox(height: 8),
            _CustomHexRow(
              controller: _hexController,
              enabled: buttonsEnabled,
              checksumMode: _checksumMode,
              padTo20: _padTo20,
              onSend: _onCustomHexSend,
            ),
            const Divider(height: 24),

            // 9. Recent RX frames
            _SectionHeader(
              'RECENT RX',
              sub: 'Last 5 notification frames from AB02.',
            ),
            const SizedBox(height: 6),
            _RecentRxList(ble: ble),
            const Divider(height: 24),

            // 10. Session records
            _SectionHeader(
              'SESSION RECORDS',
              sub: session.isActive
                  ? '${session.records.length} sent  •  '
                    '${session.records.where((r) => r.isFinalized).length} with observations'
                  : 'Start a session to record observations.',
            ),
            const SizedBox(height: 6),
            if (session.records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No records yet.', style: TextStyle(fontSize: 12)),
              )
            else
              ...session.records.reversed.take(20).map(
                    (r) => _RecordTile(record: r),
                  ),

            // 11. Export
            if (session.session != null) ...[
              const SizedBox(height: 12),
              _ExportBar(session: session),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Handlers ──────────────────────────────────────────────────────────────

  Future<void> _onGridButtonTap(String label, List<int> rawBytes) async {
    final bytes = _buildPayload(rawBytes);
    await _doSend(
      label: label,
      bytes: bytes,
      originalHex: bytesToHex(rawBytes),
    );
  }

  void _onCustomHexSend() {
    final raw = parseHex(_hexController.text);
    if (raw == null || raw.isEmpty) {
      _snack('Invalid hex — use format: AA 55 01 02');
      return;
    }
    final bytes = _buildPayload(raw);
    _doSend(
      label: 'Custom',
      bytes: bytes,
      originalHex: bytesToHex(raw),
    );
  }

  /// Applies current checksum + padding settings to [rawBytes].
  List<int> _buildPayload(List<int> rawBytes) {
    var bytes = applyChecksum(rawBytes, _checksumMode);
    if (_padTo20) bytes = padTo20Bytes(bytes);
    return bytes;
  }

  Future<void> _doSend({
    required String label,
    required List<int> bytes,
    required String originalHex,
  }) async {
    if (_isTesting) return;
    setState(() => _isTesting = true);

    final ble = context.read<BleService>();
    final session = context.read<SessionService>();

    // Snapshot state and frames 2 seconds BEFORE TX
    final stateBefore = ble.scooterState;
    final beforeCutoff = DateTime.now().subtract(const Duration(seconds: 2));
    final framesBeforeList = ble.rxFramesSince(beforeCutoff);
    final typesBefore =
        ble.frameClassifier.labelsIn(framesBeforeList);

    final payloadHex = bytesToHex(bytes);

    // Write to BLE
    final sentAt = DateTime.now();
    try {
      await ble.writeCommand(
        '$label  [$payloadHex]',
        bytes,
        writeMode: _writeMode,
      );
    } catch (e) {
      _snack('Send failed: $e', error: true);
      if (mounted) setState(() => _isTesting = false);
      return;
    }

    // Register a record if session is active
    TestRecord? record;
    if (session.isActive) {
      record = session.addRecord(
        buttonLabel: label,
        payloadHex: payloadHex,
        originalPayloadHex: originalHex,
        writeMode: _writeMode,
        checksumMode: _checksumMode,
        stateBefore: stateBefore,
        framesBefore: typesBefore,
      );
    }

    // Show observation sheet — passes typesBefore + sentAt for the diff
    final obs = mounted
        ? await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            enableDrag: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (sheetCtx) => _ObservationSheet(
              bleService: ble,
              label: label,
              payloadHex: payloadHex,
              sentAt: sentAt,
              typesBefore: typesBefore,
              onSubmit: (o) => Navigator.of(sheetCtx).pop(o),
            ),
          )
        : null;

    // Finalize record with post-send data
    if (record != null && mounted) {
      final rxFrames = ble.rxFramesSince(sentAt);
      final typesAfter = ble.frameClassifier.labelsIn(rxFrames);
      final newTypes = typesAfter.difference(typesBefore);
      final diff = frameDiffSummary(
        typesBefore: typesBefore,
        typesAfter: typesAfter,
      );

      session.finalizeRecord(
        record,
        stateAfter: ble.scooterState,
        rxFrames: rxFrames,
        observation: obs ?? '(no observation)',
        newFrameTypes: newTypes,
        frameDiff: diff,
      );
    }

    if (mounted) setState(() => _isTesting = false);
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      duration: const Duration(seconds: 3),
    ));
  }
}

// ── Warning banner ────────────────────────────────────────────────────────

class _WarningBanner extends StatelessWidget {
  const _WarningBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade700, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.amber.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900),
                children: const [
                  TextSpan(
                    text: 'EXPERIMENTAL — all commands are unverified probes.\n',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: 'Test only while the scooter is stationary and secured.\n'
                        'Do NOT test while riding or with wheels able to spin freely.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Connection card ───────────────────────────────────────────────────────

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final connected = ble.connectionStatus == BleConnectionStatus.connected;
    final device = ble.connectedDevice;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.circle,
            size: 12, color: connected ? Colors.green : Colors.grey),
        title: Text(
          connected
              ? 'Connected: ${device?.name ?? "?"}'
              : 'Not connected',
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: device != null
            ? Text(device.id, style: const TextStyle(fontSize: 10))
            : null,
      ),
    );
  }
}

// ── Live scooter state row ────────────────────────────────────────────────

class _LiveStateRow extends StatelessWidget {
  const _LiveStateRow({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final s = ble.scooterState;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            label: 'Speed [tent.]',
            value: '${s.speed} km/h',
            icon: Icons.speed,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            label: 'Batt raw [tent.]',
            value: '${s.batteryRaw}',
            icon: Icons.battery_5_bar,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              s.lastFrameHex.isEmpty ? '—' : s.lastFrameHex,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 9),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 10),
              overflow: TextOverflow.ellipsis),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Frame classification summary ──────────────────────────────────────────

class _FrameClassificationRow extends StatelessWidget {
  const _FrameClassificationRow({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final cats = ble.frameClassifier.categories;
    if (cats.isEmpty) {
      return Text(
        'Frame types: none seen yet',
        style: TextStyle(
            fontSize: 11, color: Theme.of(context).colorScheme.outline),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        Text('Frame types:',
            style: TextStyle(fontSize: 11, color: scheme.outline)),
        for (final cat in cats)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${cat.label} (${cat.count})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
      ],
    );
  }
}

// ── TX Settings panel ─────────────────────────────────────────────────────

class _SendSettingsPanel extends StatelessWidget {
  const _SendSettingsPanel({
    required this.writeMode,
    required this.checksumMode,
    required this.padTo20,
    required this.onWriteModeChanged,
    required this.onChecksumModeChanged,
    required this.onPadTo20Changed,
  });

  final WriteMode writeMode;
  final ChecksumMode checksumMode;
  final bool padTo20;
  final ValueChanged<WriteMode> onWriteModeChanged;
  final ValueChanged<ChecksumMode> onChecksumModeChanged;
  final ValueChanged<bool> onPadTo20Changed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TX SETTINGS', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),

          // Write mode toggle
          Row(
            children: [
              const Text('Write mode:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              SegmentedButton<WriteMode>(
                style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 11),
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(
                    value: WriteMode.withResponse,
                    label: Text('With resp.'),
                  ),
                  ButtonSegment(
                    value: WriteMode.withoutResponse,
                    label: Text('No resp.'),
                  ),
                ],
                selected: {writeMode},
                onSelectionChanged: (s) => onWriteModeChanged(s.first),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Checksum dropdown
          Row(
            children: [
              const Text('Checksum:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              DropdownButton<ChecksumMode>(
                value: checksumMode,
                isDense: true,
                style: const TextStyle(fontSize: 12),
                items: ChecksumMode.values
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(checksumLabel(m)),
                        ))
                    .toList(),
                onChanged: (m) {
                  if (m != null) onChecksumModeChanged(m);
                },
              ),
            ],
          ),
          if (checksumMode != ChecksumMode.none)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 82),
              child: Text(
                checksumInfo(checksumMode),
                style: TextStyle(
                    fontSize: 10, color: scheme.outline,
                    fontStyle: FontStyle.italic),
              ),
            ),
          const SizedBox(height: 4),

          // Pad to 20 bytes toggle
          Row(
            children: [
              const Text('Pad to 20 bytes:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Switch(
                value: padTo20,
                onChanged: onPadTo20Changed,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 4),
              Text(
                padTo20 ? 'ON — 0x00 fill' : 'OFF',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Session controls ──────────────────────────────────────────────────────

class _SessionControls extends StatelessWidget {
  const _SessionControls({required this.session});
  final SessionService session;

  @override
  Widget build(BuildContext context) {
    final s = session.session;

    if (s == null) {
      return FilledButton.icon(
        onPressed: () => context.read<SessionService>().startSession(),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Start Session'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Session: ${s.id}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (s.isActive)
              OutlinedButton.icon(
                onPressed: () =>
                    context.read<SessionService>().endSession(),
                icon: const Icon(Icons.stop_rounded, size: 16),
                label: const Text('End'),
              )
            else
              const Chip(
                label: Text('Ended'),
                avatar: Icon(Icons.check_circle_outline, size: 14),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.sub});
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        if (sub != null)
          Text(
            sub!,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline),
          ),
      ],
    );
  }
}

// ── Test button grid ──────────────────────────────────────────────────────

class _ButtonGrid extends StatelessWidget {
  const _ButtonGrid({required this.enabled, required this.onTap});
  final bool enabled;
  final Future<void> Function(String label, List<int> bytes) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in kButtonLayout)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (int i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _GridButton(
                      label: row[i],
                      bytes: kCommandMap[row[i]] ?? [],
                      enabled: enabled,
                      onTap: onTap,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _GridButton extends StatelessWidget {
  const _GridButton({
    required this.label,
    required this.bytes,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final List<int> bytes;
  final bool enabled;
  final Future<void> Function(String, List<int>) onTap;

  @override
  Widget build(BuildContext context) {
    final hex = bytesToHex(bytes);
    final hexShort = hex.length > 14 ? '${hex.substring(0, 14)}…' : hex;

    return OutlinedButton(
      onPressed: enabled ? () => onTap(label, bytes) : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            hexShort,
            style: TextStyle(
              fontSize: 8,
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Custom hex row ────────────────────────────────────────────────────────

class _CustomHexRow extends StatelessWidget {
  const _CustomHexRow({
    required this.controller,
    required this.enabled,
    required this.checksumMode,
    required this.padTo20,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool enabled;
  final ChecksumMode checksumMode;
  final bool padTo20;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Build preview of final bytes
        final raw = parseHex(controller.text);
        String? preview;
        if (raw != null && raw.isNotEmpty) {
          var bytes = applyChecksum(raw, checksumMode);
          if (padTo20) bytes = padTo20Bytes(bytes);
          preview = '→ ${bytesToHex(bytes)}  (${bytes.length}B)';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    decoration: const InputDecoration(
                      hintText: 'e.g.  AA 55 01 02 03',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.all(10),
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: enabled ? onSend : null,
                  child: const Text('Send'),
                ),
              ],
            ),
            if (preview != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  preview,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Recent RX list ────────────────────────────────────────────────────────

class _RecentRxList extends StatelessWidget {
  const _RecentRxList({required this.ble});
  final BleService ble;

  @override
  Widget build(BuildContext context) {
    final rxEntries = ble.log
        .where((e) => e.direction == LogDirection.rx)
        .take(5)
        .toList();

    if (rxEntries.isEmpty) {
      return const Text('No RX frames yet.', style: TextStyle(fontSize: 12));
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: rxEntries.map((e) {
        final t = e.timestamp;
        final time =
            '${_p(t.hour)}:${_p(t.minute)}:${_p(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Text(time,
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
              if (e.frameCategory != null) ...[
                const SizedBox(width: 4),
                Text(e.frameCategory!,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: scheme.secondary)),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  e.hex,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (e.parsedSpeed != null)
                Text(' ${e.parsedSpeed}km/h',
                    style: TextStyle(fontSize: 9, color: scheme.secondary)),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _p(int v) => v.toString().padLeft(2, '0');
}

// ── Session record tile ───────────────────────────────────────────────────

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});
  final TestRecord record;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final finalized = record.isFinalized;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: finalized
          ? scheme.secondaryContainer
          : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    record.buttonLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Write mode + checksum badges
                _SmallBadge(
                  record.writeMode == WriteMode.withResponse ? 'ACK' : 'noACK',
                  color: record.writeMode == WriteMode.withResponse
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
                if (record.checksumMode != ChecksumMode.none) ...[
                  const SizedBox(width: 4),
                  _SmallBadge(checksumLabel(record.checksumMode),
                      color: Colors.blueGrey.shade600),
                ],
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    record.payloadHex,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${record.rxFramesInWindow.length} RX',
                  style: TextStyle(fontSize: 10, color: scheme.secondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Observation
            Text(
              record.observation ?? '(pending)',
              style: TextStyle(
                fontSize: 12,
                color: finalized
                    ? scheme.onSecondaryContainer
                    : scheme.outline,
                fontStyle: finalized ? FontStyle.normal : FontStyle.italic,
              ),
            ),
            // Frame diff
            if (record.frameDiff != null && record.frameDiff!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  record.frameDiff!,
                  style: TextStyle(
                      fontSize: 10,
                      color: scheme.tertiary,
                      fontFamily: 'monospace'),
                ),
              ),
            // State diff
            if (record.stateAfter != null &&
                (record.stateBefore.speed != record.stateAfter!.speed ||
                    record.stateBefore.batteryRaw !=
                        record.stateAfter!.batteryRaw))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '[tent.] before=[${record.stateBefore}]  after=[${record.stateAfter}]',
                  style: TextStyle(fontSize: 10, color: scheme.tertiary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Export bar ────────────────────────────────────────────────────────────

class _ExportBar extends StatelessWidget {
  const _ExportBar({required this.session});
  final SessionService session;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.content_copy, size: 16),
            label: const Text('Copy JSON'),
            onPressed: () {
              final json = session.exportJson();
              Clipboard.setData(ClipboardData(text: json));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Session JSON copied to clipboard')),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.data_object, size: 16),
            label: const Text('View JSON'),
            onPressed: () => _showJsonDialog(context),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () => _confirmClear(context),
          child: const Text('Clear'),
        ),
      ],
    );
  }

  void _showJsonDialog(BuildContext context) {
    final json = session.exportJson();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session JSON'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied')),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Copy & Close'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear session?'),
        content: const Text('All records in this session will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && context.mounted) {
        context.read<SessionService>().clearSession();
      }
    });
  }
}

// ── Observation bottom sheet ──────────────────────────────────────────────

/// Quick-pick observation tags shown as selectable chips.
const _kTags = [
  'No reaction',
  'Beep',
  'Lights changed',
  'Mode changed',
  'Locked',
  'Unlocked',
  'Scooter responded',
  'Unknown effect',
];

class _ObservationSheet extends StatefulWidget {
  const _ObservationSheet({
    required this.bleService,
    required this.label,
    required this.payloadHex,
    required this.sentAt,
    required this.typesBefore,
    required this.onSubmit,
  });

  final BleService bleService;
  final String label;
  final String payloadHex;
  final DateTime sentAt;

  /// Frame-category labels seen in the 2 seconds BEFORE this TX.
  final Set<String> typesBefore;

  final void Function(String observation) onSubmit;

  @override
  State<_ObservationSheet> createState() => _ObservationSheetState();
}

class _ObservationSheetState extends State<_ObservationSheet> {
  int _remainingMs = BleConstants.rxWindowMs;
  bool _collecting = true;
  String? _selectedTag;
  final _notesController = TextEditingController();
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _countdown = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _remainingMs -= 200;
        if (_remainingMs <= 0) {
          _remainingMs = 0;
          _collecting = false;
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _notesController.dispose();
    super.dispose();
  }

  List<String> _rxFramesSinceSend() =>
      widget.bleService.rxFramesSince(widget.sentAt);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.bleService,
      builder: (context, _) {
        final rxFrames = _rxFramesSinceSend();
        final typesAfter =
            widget.bleService.frameClassifier.labelsIn(rxFrames);
        final diff = frameDiffSummary(
          typesBefore: widget.typesBefore,
          typesAfter: typesAfter,
        );

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Title + collection indicator
                Row(
                  children: [
                    Text(
                      'Observe: ${widget.label}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    if (_collecting) ...[
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(_remainingMs / 1000).toStringAsFixed(1)}s',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ] else
                      Text(
                        'Done — ${rxFrames.length} RX',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                  ],
                ),

                // Sent payload
                const SizedBox(height: 4),
                Text(
                  'TX: ${widget.payloadHex}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
                const Divider(height: 16),

                // Frame diff
                Text('Frame-type diff:',
                    style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(
                  diff,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                const SizedBox(height: 10),

                // RX frames received in window
                if (rxFrames.isEmpty)
                  Text(
                    _collecting ? 'Waiting for RX…' : 'No RX frames received.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RX frames (${rxFrames.length}):',
                          style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 4),
                      ...rxFrames.take(5).map(
                            (h) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                h,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 10),
                              ),
                            ),
                          ),
                      if (rxFrames.length > 5)
                        Text('+${rxFrames.length - 5} more',
                            style: const TextStyle(fontSize: 10)),
                    ],
                  ),

                const SizedBox(height: 14),

                // Quick observation chips
                Text('What did you observe?',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _kTags
                      .map(
                        (tag) => FilterChip(
                          label: Text(tag, style: const TextStyle(fontSize: 12)),
                          selected: _selectedTag == tag,
                          onSelected: (_) =>
                              setState(() => _selectedTag = tag),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),

                // Free-text notes
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    hintText: 'Additional notes (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.all(10),
                  ),
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),

                // Submit / skip row
                Row(
                  children: [
                    TextButton(
                      onPressed: () => widget.onSubmit('(skipped)'),
                      child: const Text('Skip'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _selectedTag != null ? _submit : null,
                        child: const Text('Save Observation'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _submit() {
    final notes = _notesController.text.trim();
    final obs = notes.isEmpty ? _selectedTag! : '$_selectedTag — $notes';
    widget.onSubmit(obs);
  }
}
