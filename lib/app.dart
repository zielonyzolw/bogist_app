import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/ble/ble_service.dart';
import 'features/session/session_service.dart';
import 'features/ui/scan_page.dart';

class BogistApp extends StatelessWidget {
  const BogistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleService()),
        ChangeNotifierProvider(create: (_) => SessionService()),
      ],
      child: MaterialApp(
        title: 'BOGIST',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
          useMaterial3: true,
        ),
        home: const ScanPage(),
      ),
    );
  }
}
