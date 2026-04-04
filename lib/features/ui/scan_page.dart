import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../ble/ble_service.dart';
import 'dashboard_page.dart';

class ScanPage extends StatelessWidget {
  const ScanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('BOGIST — Scan'),
        actions: [
          if (ble.isScanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Error banner
          if (ble.error != null)
            MaterialBanner(
              content: Text(ble.error!),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              actions: [
                TextButton(
                  onPressed: () => openAppSettings(),
                  child: const Text('Open Settings'),
                ),
              ],
            ),

          // Scan button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: ble.isScanning ? ble.stopScan : ble.startScan,
                icon: Icon(ble.isScanning ? Icons.stop : Icons.search),
                label: Text(ble.isScanning ? 'Stop Scan' : 'Start Scan'),
              ),
            ),
          ),

          // Device list
          Expanded(
            child: ble.scannedDevices.isEmpty
                ? Center(
                    child: Text(
                      ble.isScanning
                          ? 'Searching for devices…'
                          : 'No devices found.\nTap Start Scan.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    itemCount: ble.scannedDevices.length,
                    itemBuilder: (context, i) =>
                        _DeviceTile(device: ble.scannedDevices[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
    final isBogist = device.name == BleConstants.deviceName;
    final displayName = device.name.isEmpty ? '(unknown)' : device.name;

    return ListTile(
      leading: Icon(
        isBogist ? Icons.electric_scooter : Icons.bluetooth,
        color: isBogist ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        displayName,
        style: isBogist
            ? TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              )
            : null,
      ),
      subtitle: Text(device.id, style: const TextStyle(fontSize: 11)),
      trailing: isBogist
          ? FilledButton(
              onPressed: () => _connect(context),
              child: const Text('Connect'),
            )
          : null,
      onTap: () => _connect(context),
    );
  }

  void _connect(BuildContext context) {
    context.read<BleService>().connectToDevice(device);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DashboardPage()),
    );
  }
}
