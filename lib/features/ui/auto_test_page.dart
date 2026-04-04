import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auto_test/auto_test_candidate.dart';
import '../auto_test/auto_test_controller.dart';
import '../ble/ble_service.dart';
import '../commands/checksum.dart';
import 'debug_page.dart';

class AutoTestPage extends StatelessWidget {
  const AutoTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AutoTestController>();
    final ble = context.watch<BleService>();
    final connected = ble.connectionStatus == BleConnectionStatus.connected;
    final idle = ctrl.status == AutoTestStatus.idle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Test Lab'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Full BLE Log',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DebugPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Fixed top section — always visible, never scrolls.
          const _SafetyBanner(),
          _StatusControlPanel(
            ctrl: ctrl,
            ble: ble,
            connected: connected,
            onStart: () => _startWithConfirmation(context, ctrl, ble),
          ),
          // Scrollable body.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (!idle) ...[
                  _ProgressCard(ctrl: ctrl),
                  const SizedBox(height: 12),
                ],
                if (idle) ...[
                  _SettingsPanel(ctrl: ctrl),
                  const SizedBox(height: 12),
                  if (ctrl.candidates.isNotEmpty) ...[
                    _CandidatePreview(ctrl: ctrl),
                    const SizedBox(height: 12),
                  ],
                ],
                if (ctrl.log.isNotEmpty) _LogSection(ctrl: ctrl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -- Start with safety confirmation ----------------------------------------

  static Future<void> _startWithConfirmation(
    BuildContext context,
    AutoTestController ctrl,
    BleService ble,
  ) async {
    if (!context.mounted) return;

    final connected = ble.connectionStatus == BleConnectionStatus.connected;
    if (!connected) {
      _snack(context, 'Not connected to scooter.', error: true);
      return;
    }

    if (ctrl.candidates.isEmpty) {
      _snack(context, 'No candidates to send.', error: true);
      return;
    }

    // Extra warning if speed is non-zero.
    final speed = ble.scooterState.speed;
    if (speed > 0) {
      final override = await _showSpeedWarningDialog(context, speed);
      if (!context.mounted) return;
      if (override != true) return;
    }

    // Safety confirmation.
    final confirmed = await _showSafetyDialog(context, ctrl);
    if (!context.mounted) return;
    if (confirmed != true) return;

    final started = ctrl.start();
    if (!started && context.mounted) {
      _snack(context, 'Could not start — check connection.', error: true);
    }
  }

  static Future<bool?> _showSafetyDialog(
      BuildContext context, AutoTestController ctrl) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.amber, size: 36),
        title: const Text('Safety check'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Test only while the scooter is stationary, '
                'preferably with the wheel off the ground.\n\n'
                'Auto-test sends payloads automatically — '
                'you MUST remain at the device to monitor for unexpected reactions.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${ctrl.candidates.length} payload(s) will be sent, '
              '${(AutoTestController.intervalMs / 1000).toStringAsFixed(0)}s apart.',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('I understand — Start'),
          ),
        ],
      ),
    );
  }

  static Future<bool?> _showSpeedWarningDialog(
      BuildContext context, int speed) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.speed, color: Colors.red, size: 36),
        title: const Text('Scooter may be moving'),
        content: Text(
          'The tentative speed reading is $speed km/h. '
          'Auto-test must only run while the scooter is stationary.\n\n'
          'If the speed reading is wrong (unverified parser), '
          'you may override below.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            child: const Text('Override — scooter is stationary'),
          ),
        ],
      ),
    );
  }

  static void _snack(BuildContext context, String msg, {bool error = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      duration: const Duration(seconds: 3),
    ));
  }
}

// -- Safety banner ------------------------------------------------------------

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      color: Colors.red.shade700,
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'EXPERIMENTAL — stationary only. '
              'Payloads are unverified. Stop immediately if anything unexpected happens.',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Status + control panel ---------------------------------------------------

class _StatusControlPanel extends StatelessWidget {
  const _StatusControlPanel({
    required this.ctrl,
    required this.ble,
    required this.connected,
    required this.onStart,
  });

  final AutoTestController ctrl;
  final BleService ble;
  final bool connected;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = ctrl.status;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          // Status chip
          _StatusChip(status: status, error: ctrl.error),
          const SizedBox(width: 12),

          // Connection + index info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.circle,
                        size: 8,
                        color: connected ? Colors.green : Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      connected
                          ? (ble.connectedDevice?.name ?? 'Connected')
                          : 'Not connected',
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                if (status == AutoTestStatus.running ||
                    status == AutoTestStatus.paused) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Test ${ctrl.currentIndex + 1} / ${ctrl.totalCandidates}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),

          // Action buttons
          ..._buildButtons(context, status),
        ],
      ),
    );
  }

  List<Widget> _buildButtons(BuildContext context, AutoTestStatus status) {
    switch (status) {
      case AutoTestStatus.idle:
        return [
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Start'),
            onPressed: connected ? onStart : null,
          ),
        ];

      case AutoTestStatus.running:
        return [
          OutlinedButton(
            onPressed: ctrl.pause,
            style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact),
            child: const Text('Pause'),
          ),
          const SizedBox(width: 8),
          _StopButton(onPressed: ctrl.stop),
        ];

      case AutoTestStatus.paused:
        return [
          FilledButton(
            onPressed: ctrl.resume,
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact),
            child: const Text('Resume'),
          ),
          const SizedBox(width: 8),
          _StopButton(onPressed: ctrl.stop),
        ];

      case AutoTestStatus.stopped:
      case AutoTestStatus.completed:
      case AutoTestStatus.error:
        return [
          OutlinedButton(
            onPressed: ctrl.reset,
            child: const Text('Reset'),
          ),
        ];
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.error});
  final AutoTestStatus status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AutoTestStatus.idle      => ('IDLE',      Colors.grey),
      AutoTestStatus.running   => ('RUNNING',   Colors.green),
      AutoTestStatus.paused    => ('PAUSED',    Colors.orange),
      AutoTestStatus.stopped   => ('STOPPED',   Colors.blueGrey),
      AutoTestStatus.completed => ('DONE',      Colors.teal),
      AutoTestStatus.error     => ('ERROR',     Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.stop_rounded, size: 18),
      label: const Text('STOP'),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// -- Progress card (shown while running / paused) -----------------------------

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.ctrl});
  final AutoTestController ctrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = ctrl.totalCandidates;
    final idx = ctrl.currentIndex;
    final progress = total > 0 ? (idx + 1) / total : 0.0;
    final entry = ctrl.currentEntry;
    final isRunning = ctrl.status == AutoTestStatus.running;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress bar
            LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),

            // Index + countdown
            Row(
              children: [
                Text(
                  'Test ${idx + 1} of $total',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const Spacer(),
                if (isRunning)
                  Text(
                    'Next in ${(ctrl.countdownMs / 1000).toStringAsFixed(1)}s',
                    style: TextStyle(
                        fontSize: 12, color: scheme.primary),
                  )
                else
                  Text(
                    ctrl.status == AutoTestStatus.paused ? 'Paused' : '',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
              ],
            ),

            // Countdown bar
            if (isRunning) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: ctrl.countdownMs / AutoTestController.intervalMs,
                minHeight: 3,
                color: scheme.primary,
                backgroundColor: scheme.primaryContainer,
              ),
            ],

            // Current payload
            if (entry != null) ...[
              const SizedBox(height: 8),
              Text(entry.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 2),
              SelectableText(
                entry.payloadHex,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.writeMode.name}  •  '
                'checksum: ${checksumLabel(entry.checksumMode)}',
                style: TextStyle(fontSize: 10, color: scheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -- Settings panel (shown when idle) -----------------------------------------

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.ctrl});
  final AutoTestController ctrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SETTINGS', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 12),

          // Candidate source
          Text('Candidate source', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          DropdownButtonFormField<CandidateSource>(
            initialValue: ctrl.source,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: CandidateSource.values
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(candidateSourceLabel(s),
                          style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged: (s) {
              if (s != null) context.read<AutoTestController>().setSource(s);
            },
          ),
          const SizedBox(height: 12),

          // Max tests slider
          Row(
            children: [
              Text('Max tests: ${ctrl.maxTests}',
                  style: const TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: ctrl.maxTests.toDouble(),
                  min: 3,
                  max: 20,
                  divisions: 17,
                  label: '${ctrl.maxTests}',
                  onChanged: (v) =>
                      context.read<AutoTestController>().setMaxTests(v.round()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Write mode
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
                selected: {ctrl.writeMode},
                onSelectionChanged: (s) =>
                    context.read<AutoTestController>().setWriteMode(s.first),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Checksum
          Row(
            children: [
              const Text('Checksum:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              DropdownButton<ChecksumMode>(
                value: ctrl.checksumMode,
                isDense: true,
                style: const TextStyle(fontSize: 12),
                items: ChecksumMode.values
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(checksumLabel(m)),
                        ))
                    .toList(),
                onChanged: (m) {
                  if (m != null) {
                    context.read<AutoTestController>().setChecksumMode(m);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Pad to 20
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Pad to 20 bytes',
                style: TextStyle(fontSize: 12)),
            subtitle: const Text('Fills with 0x00',
                style: TextStyle(fontSize: 10)),
            value: ctrl.padTo20,
            onChanged: context.read<AutoTestController>().setPadTo20,
          ),

          const Divider(height: 16),
          Text('STOP CONDITIONS',
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),

          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Stop on new frame type detected',
                style: TextStyle(fontSize: 12)),
            subtitle: const Text(
                'Stops the sequence when a Frame-X type appears that was not present before TX',
                style: TextStyle(fontSize: 10)),
            value: ctrl.stopOnNewFrameType,
            onChanged: context.read<AutoTestController>().setStopOnNewFrameType,
          ),

          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Stop when reaction is marked',
                style: TextStyle(fontSize: 12)),
            subtitle: const Text(
                'Stops after you tap a reaction button on any entry',
                style: TextStyle(fontSize: 10)),
            value: ctrl.stopOnReactionMarked,
            onChanged:
                context.read<AutoTestController>().setStopOnReactionMarked,
          ),
        ],
      ),
    );
  }
}

// -- Candidate preview (shown when idle and candidates non-empty) -------------

class _CandidatePreview extends StatelessWidget {
  const _CandidatePreview({required this.ctrl});
  final AutoTestController ctrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = ctrl.candidates;
    final shown = all.take(5).toList();
    final overflow = all.length - shown.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primaryContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUEUED CANDIDATES (${all.length})',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < shown.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Text(
                    '${i + 1}.',
                    style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    shown[i].label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      shown[i].description,
                      style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: scheme.outline),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (overflow > 0)
            Text(
              '+ $overflow more (capped at ${ctrl.maxTests})',
              style: TextStyle(fontSize: 10, color: scheme.outline),
            ),
        ],
      ),
    );
  }
}

// -- Log section --------------------------------------------------------------

class _LogSection extends StatelessWidget {
  const _LogSection({required this.ctrl});
  final AutoTestController ctrl;

  @override
  Widget build(BuildContext context) {
    final entries = ctrl.log.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('TEST LOG (${entries.length})',
              style: Theme.of(context).textTheme.labelMedium),
        ),
        for (final entry in entries)
          _EntryCard(entry: entry, ctrl: ctrl),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.ctrl});
  final AutoTestEntry entry;
  final AutoTestController ctrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasReaction = entry.reaction != null;
    final isNew = entry.newFrameDetected;

    Color cardColor;
    if (isNew && !hasReaction) {
      cardColor = Colors.orange.shade50;
    } else if (hasReaction) {
      cardColor = scheme.secondaryContainer;
    } else {
      cardColor = scheme.surfaceContainerHighest;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Index badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#${entry.index + 1}',
                    style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11),
                  ),
                ),
                const SizedBox(width: 6),
                Text(entry.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12)),
                const Spacer(),
                if (isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('NEW FRAME',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 4),

            // Payload hex
            SelectableText(
              entry.payloadHex,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
            const SizedBox(height: 2),

            // Frame diff
            Text(
              _frameDiffText(entry),
              style: TextStyle(fontSize: 10, color: scheme.tertiary),
            ),

            // Reaction row
            const SizedBox(height: 6),
            Row(
              children: [
                if (!hasReaction) ...[
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: _kReactionTags.map((tag) {
                        return ActionChip(
                          label: Text(tag,
                              style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              ctrl.markReaction(entry.index, tag),
                        );
                      }).toList(),
                    ),
                  ),
                ] else ...[
                  Icon(Icons.check_circle,
                      size: 14, color: scheme.secondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      entry.reaction!,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _frameDiffText(AutoTestEntry e) {
    if (e.frameTypesAfter.isEmpty && e.frameTypesBefore.isEmpty) {
      return 'before: — / after: —';
    }
    final before = e.frameTypesBefore.isEmpty
        ? '—'
        : e.frameTypesBefore.join(', ');
    final after = e.frameTypesAfter.isEmpty
        ? 'collecting…'
        : e.frameTypesAfter.join(', ');
    final newTypes = e.frameTypesAfter.difference(e.frameTypesBefore);
    final suffix = newTypes.isNotEmpty
        ? '  ★ NEW: ${newTypes.join(', ')}'
        : '';
    return 'before: $before  /  after: $after$suffix';
  }
}

/// Quick reaction tags for auto-test entries.
const _kReactionTags = [
  'No reaction',
  'Beep',
  'Light changed',
  'Mode changed',
  'Unknown reaction',
  'Reaction noticed',
];
