import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';

class DebugPage extends StatelessWidget {
  const DebugPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final log = ble.log;

    return Scaffold(
      appBar: AppBar(
        title: Text('BLE Log — ${log.length} entries'),
        actions: [
          if (log.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear log',
              onPressed: () => context.read<BleService>().clearLog(),
            ),
        ],
      ),
      body: log.isEmpty
          ? const Center(child: Text('No frames logged yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: log.length,
              itemBuilder: (context, i) => _LogTile(entry: log[i]),
            ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final BleLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = entry.timestamp;
    final time =
        '${_pad(t.hour)}:${_pad(t.minute)}:${_pad(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';

    final isRx = entry.direction == LogDirection.rx;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: isRx ? scheme.primaryContainer : scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Direction badge + frame-category badge + timestamp
            Row(
              children: [
                _DirBadge(isRx: isRx),
                if (entry.frameCategory != null) ...[
                  const SizedBox(width: 6),
                  _CategoryBadge(label: entry.frameCategory!),
                ],
                const SizedBox(width: 8),
                Text(time, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),

            // Label (TX only)
            if (entry.label != null) ...[
              const SizedBox(height: 3),
              Text(
                entry.label!,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],

            // Hex payload
            const SizedBox(height: 4),
            SelectableText(
              entry.hex,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),

            // Parsed values (RX only) — marked tentative
            if (entry.parsedSpeed != null || entry.parsedBattery != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '[tentative] speed≈${entry.parsedSpeed ?? "?"} km/h'
                  '  |  battery_raw≈${entry.parsedBattery ?? "?"}',
                  style: TextStyle(fontSize: 11, color: scheme.secondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _pad(int v) => v.toString().padLeft(2, '0');
}

class _DirBadge extends StatelessWidget {
  const _DirBadge({required this.isRx});
  final bool isRx;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isRx ? scheme.primary : scheme.tertiary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isRx ? 'RX' : 'TX',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isRx ? scheme.onPrimary : scheme.onTertiary,
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
