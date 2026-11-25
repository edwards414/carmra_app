import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'client/client_root.dart';
import 'client/connect_page.dart';
import 'core/connect_info.dart';
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
class BomScannerApp extends StatefulWidget {
  const BomScannerApp({super.key, required this.isHost});
  final bool isHost;

  @override
  State<BomScannerApp> createState() => _BomScannerAppState();
}

class _BomScannerAppState extends State<BomScannerApp> {
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    if (!widget.isHost) {
      // The desktop's pairing QR is a carmra://connect link, so scanning it
      // with the iPhone Camera opens the app here (at launch or later).
      _links = AppLinks().uriLinkStream.listen(_onLink);
    }
  }

  void _onLink(Uri uri) {
    final info = ConnectInfo.decode(uri.toString());
    final nav = _navigator.currentState;
    if (info == null || nav == null) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => ConnectPage(pending: info)),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1B6E5A),
        brightness: b,
      ),
    );
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'BOM 掃描',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: widget.isHost ? const HostHome() : const ClientRoot(),
    );
  }
}
