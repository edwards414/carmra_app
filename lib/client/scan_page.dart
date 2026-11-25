import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/lcsc_label.dart';
import '../core/models.dart';
import '../ui/bom_widgets.dart';
import 'api_client.dart';

/// Scan LCSC bag labels; lines in the BOM get checked on the desktop.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.client, required this.summary});
  final ApiClient client;
  final ProjectSummary summary;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionTimeoutMs: 300,
  );

  BomProject? _project;
  String? _error;
  ScanOutcome? _outcome;
  BomFilter _filter = BomFilter.open;
  bool _busy = false;
  String? _lastRaw;
  DateTime _lastRawAt = DateTime(0);
  Timer? _poll;

  String get _id => widget.summary.id;
  ApiClient get _api => widget.client;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Picks up checks made on the desktop or another phone.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_busy) _refresh(quiet: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool quiet = false}) async {
    try {
      final p = await _api.getProject(_id);
      if (!mounted) return;
      setState(() {
        _project = p;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted && (!quiet || _project == null)) {
        setState(() => _error = e.message);
      }
    }
  }

  /// Runs [call] with the scanner paused against duplicate requests.
  Future<void> _run(Future<void> Function() call) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await call();
    } on ApiException catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || _busy) return;
    final now = DateTime.now();
    // The camera reports the same code many times a second.
    if (raw == _lastRaw && now.difference(_lastRawAt).inMilliseconds < 3000) {
      return;
    }
    _lastRaw = raw;
    _lastRawAt = now;
    _submit(raw);
  }

  void _submit(String raw) {
    if (LcscLabel.parse(raw) == null) {
      HapticFeedback.selectionClick();
      setState(
        () =>
            _outcome = ScanOutcome(status: ScanStatus.invalid, raw: raw.trim()),
      );
      return;
    }
    _run(() async {
      final (outcome, project) = await _api.scan(_id, raw);
      if (!mounted) return;
      setState(() {
        _outcome = outcome;
        _project = project;
      });
      await _feedback(outcome.status);
    });
  }

  Future<void> _feedback(ScanStatus status) async {
    switch (status) {
      case ScanStatus.matched:
        await HapticFeedback.mediumImpact();
      case ScanStatus.alreadyChecked:
        await HapticFeedback.lightImpact();
      case ScanStatus.mpnMatch:
      case ScanStatus.notInBom:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await HapticFeedback.heavyImpact();
      case ScanStatus.invalid:
        await HapticFeedback.selectionClick();
    }
  }

  void _setChecked(BomItem item, bool checked) {
    _run(() async {
      final p = await _api.setChecked(_id, item.key, checked);
      if (!mounted) return;
      setState(() => _project = p);
      if (!checked) {
        _snack(
          '已取消 ${item.lcsc ?? item.key}',
          undo: () => _setChecked(item, true),
        );
      }
    });
  }

  Future<void> _clear() async {
    final p = _project;
    if (p == null || !await confirmClear(context, p.name)) return;
    await _run(() async {
      final cleared = await _api.clear(_id);
      if (!mounted) return;
      setState(() {
        _project = cleared;
        _outcome = null;
      });
      _snack('已清除全部打勾');
    });
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('輸入 LCSC 編號'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'C25804'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('查詢'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    final label = LcscLabel.parseManual(text);
    if (label == null) {
      _snack('「$text」不是 LCSC 編號（例：C25804）', error: true);
      return;
    }
    _submit(label.raw);
  }

  void _snack(String text, {bool error = false, VoidCallback? undo}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? kRed : null,
          action: undo == null
              ? null
              : SnackBarAction(label: '復原', onPressed: undo),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    final screen = MediaQuery.sizeOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          p?.name ?? widget.summary.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '手動輸入編號',
            onPressed: _manualEntry,
            icon: const Icon(Icons.keyboard),
          ),
          IconButton(
            tooltip: '清除全部打勾',
            onPressed: p == null ? null : _clear,
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: (screen.height * 0.32).clamp(180.0, 320.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scanner,
                  onDetect: _onDetect,
                  tapToFocus: true,
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white70, width: 3),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: ValueListenableBuilder(
                    valueListenable: _scanner,
                    builder: (context, state, _) {
                      if (state.torchState == TorchState.unavailable) {
                        return const SizedBox.shrink();
                      }
                      return IconButton.filledTonal(
                        onPressed: _scanner.toggleTorch,
                        icon: Icon(
                          state.torchState == TorchState.on
                              ? Icons.flash_on
                              : Icons.flash_off,
                        ),
                      );
                    },
                  ),
                ),
                if (_busy)
                  const Positioned(
                    left: 12,
                    top: 12,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _outcome == null
                  ? const Padding(
                      key: ValueKey('hint'),
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '把零件袋標籤上的 QR code 對準框框',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : ScanResultCard(
                      key: ValueKey(_outcome),
                      outcome: _outcome!,
                      project: p,
                      onCheckCandidate: (key) {
                        final item = p?.itemByKey(key);
                        if (item != null) _setChecked(item, true);
                      },
                    ),
            ),
          ),
          if (_error != null && p == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_error!, style: const TextStyle(color: kRed)),
                  OutlinedButton(onPressed: _refresh, child: const Text('重試')),
                ],
              ),
            ),
          if (p != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: BomProgress(checked: p.checkedCount, total: p.total),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: BomFilterBar(
                filter: _filter,
                project: p,
                onChanged: (f) => setState(() => _filter = f),
              ),
            ),
            Expanded(child: _list(p)),
          ],
        ],
      ),
    );
  }

  Widget _list(BomProject p) {
    final items = p.items.where(_filter.accepts).toList();
    if (items.isEmpty) {
      return Center(
        child: Text(
          _filter == BomFilter.open && p.isComplete ? '全部到齊 🎉' : '沒有項目',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }
    final justMatched = _outcome?.status == ScanStatus.matched
        ? _outcome!.itemKeys
        : const <String>[];
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = items[i];
        return BomItemTile(
          item: item,
          highlight: justMatched.contains(item.key),
          onTap: () => _setChecked(item, !item.checked),
        );
      },
    );
  }
}
