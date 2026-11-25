import 'dart:io';

import 'package:flutter/material.dart';

import 'client/client_root.dart';
import 'host/host_home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    BomScannerApp(
      isHost: Platform.isMacOS || Platform.isWindows || Platform.isLinux,
    ),
  );
}

/// On a computer the app is the host (imports ibom.html, serves projects);
/// on a phone it scans.
class BomScannerApp extends StatelessWidget {
  const BomScannerApp({super.key, required this.isHost});
  final bool isHost;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1B6E5A),
        brightness: b,
      ),
    );
    return MaterialApp(
      title: 'BOM 掃描',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: isHost ? const HostHome() : const ClientRoot(),
    );
  }
}
