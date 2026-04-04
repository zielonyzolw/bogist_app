import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/ble_service.dart';
import 'debug_page.dart';
import 'test_lab_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final state = ble.scooterState;
    final device = ble.connectedDevice;

    final (statusColor, statusLabel) = switch (ble.connectionStatus) {
      BleConnectionStatus.connected    => (Colors.green,  'Connected'),
      BleConnectionStatus.connecting   => (Colors.orange, 'Connecting...'),
      BleConnectionStatus.error        => (Colors.red,    'Error'),
      BleConnectionStatus.disconnected => (Colors.grey,   'Disconnected'),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'BLE Log',
            onPressed: () => _push(context, const DebugPage()),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection status
            Card(
              child: ListTile(
                leading: Icon(Icons.circle, color: statusColor, size: 14),
                title: Text(statusLabel),
                subtitle: device != null
                    ? Text(
                        '${device.name}  •  ${device.id}',
                        style: const TextStyle(fontSize: 11),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            // Speed & Battery
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.speed,
                    label: 'Speed',
                    value: '${state.speed}',
                    unit: 'km/h',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.battery_5_bar,
                    label: 'Battery (raw)',
                    value: '${state.batteryRaw}',
                    unit: 'byte 8',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Last raw frame
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Last Frame (hex)',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    SelectableText(
                      state.lastFrameHex.isEmpty ? '—' : state.lastFrameHex,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Navigation buttons
            FilledButton.tonalIcon(
              icon: const Icon(Icons.science_outlined),
              label: const Text('Test Lab (Commands)'),
              onPressed: () => _push(context, const TestLabPage()),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('BLE Log'),
              onPressed: () => _push(context, const DebugPage()),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.bluetooth_disabled),
              label: const Text('Disconnect'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () {
                context.read<BleService>().disconnect();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              unit,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
