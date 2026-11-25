import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/connect_info.dart';
import '../ui/bom_widgets.dart';
import 'api_client.dart';
import 'project_list_page.dart';

/// Pair with the desktop by scanning its QR code or typing its address.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, this.initialError, this.saved});

  final String? initialError;
  final ConnectInfo? saved;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _busy = false;
  String? _error;
  String? _lastRaw;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _connect(ConnectInfo info) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = await ApiClient.connect(info);
      await SavedConnection.save(info, client.host);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ProjectListPage(client: client)),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw == _lastRaw || _busy) return;
    _lastRaw = raw;
    final info = ConnectInfo.decode(raw);
    if (info == null) {
      setState(() => _error = '這不是電腦端顯示的連線 QR code');
      return;
    }
    _connect(info);
  }

  Future<void> _manual() async {
    final saved = widget.saved;
    final host = TextEditingController(text: saved?.hosts.firstOrNull ?? '');
    final port = TextEditingController(text: '${saved?.port ?? kDefaultPort}');
    final pin = TextEditingController(text: saved?.pin ?? '');
    final info = await showDialog<ConnectInfo>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手動輸入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: host,
              decoration: const InputDecoration(
                labelText: '電腦 IP',
                hintText: '192.168.1.10',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            TextField(
              controller: port,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: pin,
              decoration: const InputDecoration(labelText: 'PIN（電腦畫面上的 6 位數）'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(port.text.trim());
              if (host.text.trim().isEmpty || p == null || pin.text.isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                ConnectInfo(
                  hosts: [host.text.trim()],
                  port: p,
                  pin: pin.text.trim(),
                ),
              );
            },
            child: const Text('連線'),
          ),
        ],
      ),
    );
    host.dispose();
    port.dispose();
    pin.dispose();
    if (info != null) await _connect(info);
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.saved;
    return Scaffold(
      appBar: AppBar(title: const Text('連線到電腦')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _scanner, onDetect: _onDetect),
                const _ScanFrame(),
                if (_busy)
                  const ColoredBox(
                    color: Colors.black45,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '在電腦上打開 BOM 掃描 App，點左下「手機連線」，掃描畫面上的 QR code。',
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kRed),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (saved != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _connect(saved),
                          child: const Text('重試上次的電腦'),
                        ),
                      ),
                    if (saved != null) const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _manual,
                        child: const Text('手動輸入 IP'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
