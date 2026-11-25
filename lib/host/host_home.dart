import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/connect_info.dart';
import '../core/ibom_parser.dart';
import '../core/models.dart';
import '../ui/bom_widgets.dart';
import 'bom_server.dart';
import 'project_store.dart';

/// Desktop: import ibom.html files as projects and serve them to phones.
class HostHome extends StatefulWidget {
  const HostHome({super.key});

  @override
  State<HostHome> createState() => _HostHomeState();
}

class _HostHomeState extends State<HostHome> {
  ProjectStore? _store;
  BomServer? _server;
  String? _startError;
  List<String> _addresses = const [];
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final support = await getApplicationSupportDirectory();
      final store = ProjectStore(Directory('${support.path}/projects'));
      await store.load();
      final server = BomServer(store, pin: await loadOrCreatePin(support));
      await server.start();
      final addresses = await BomServer.lanAddresses();
      if (!mounted) return;
      setState(() {
        _store = store;
        _server = server;
        _addresses = addresses;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _startError = '$e');
    }
  }

  Future<void> _refreshAddresses() async {
    final a = await BomServer.lanAddresses();
    if (mounted) setState(() => _addresses = a);
  }

  @override
  void dispose() {
    _server?.stop();
    _store?.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final store = _store!;
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'InteractiveHtmlBom', extensions: ['html', 'htm']),
      ],
    );
    for (final f in files) {
      try {
        final p = await store.importIbom(await f.readAsString(), f.name);
        if (!mounted) return;
        setState(() => _selectedId = p.id);
        _snack(
          '已建立專案「${p.name}」，${p.total} 項 / '
          '${p.items.fold<int>(0, (s, i) => s + i.qty)} 個零件',
        );
      } on IbomParseException catch (e) {
        _snack('${f.name}：$e', error: true);
      } on Object catch (e) {
        _snack('${f.name} 讀取失敗：$e', error: true);
      }
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? kRed : null),
    );
  }

  Future<void> _rename(BomProject p) async {
    final controller = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) await _store!.rename(p.id, name);
  }

  Future<void> _delete(BomProject p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除專案？'),
        content: Text('「${p.name}」和它的打勾紀錄都會刪除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await _store!.delete(p.id);
      if (_selectedId == p.id) setState(() => _selectedId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (_startError != null) {
      return Scaffold(body: Center(child: Text('啟動失敗：$_startError')));
    }
    if (store == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final selected = _selectedId == null
              ? null
              : store.byId(_selectedId!);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: _sidebar(store, selected)),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? _ConnectPanel(
                        info: ConnectInfo(
                          hosts: _addresses,
                          port: _server!.port!,
                          pin: _server!.pin,
                        ),
                        onRefresh: _refreshAddresses,
                      )
                    : _ProjectPanel(
                        key: ValueKey(selected.id),
                        store: store,
                        project: selected,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sidebar(ProjectStore store, BomProject? selected) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('BOM 專案', style: theme.textTheme.headlineSmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.upload_file),
              label: const Text('上傳 ibom.html 建立專案'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: store.projects.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '還沒有專案。\n用 KiCad 的 InteractiveHtmlBom 產生 ibom.html，'
                      '欄位要包含 LCSC，再按上面的按鈕上傳。',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final p in store.projects)
                        ListTile(
                          selected: p.id == selected?.id,
                          title: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: BomProgress(
                              checked: p.checkedCount,
                              total: p.total,
                            ),
                          ),
                          onTap: () => setState(() => _selectedId = p.id),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) =>
                                v == 'rename' ? _rename(p) : _delete(p),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('重新命名'),
                              ),
                              PopupMenuItem(value: 'delete', child: Text('刪除')),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            selected: selected == null,
            leading: const Icon(Icons.phone_iphone),
            title: const Text('手機連線'),
            subtitle: Text('PIN ${_server!.pin} · port ${_server!.port}'),
            onTap: () => setState(() => _selectedId = null),
          ),
        ],
      ),
    );
  }
}

class _ConnectPanel extends StatelessWidget {
  const _ConnectPanel({required this.info, required this.onRefresh});
  final ConnectInfo info;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('用手機掃描連線', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '手機和這台電腦要在同一個 Wi-Fi。打開手機 App → 掃這個 QR code。',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (info.hosts.isEmpty)
              const Text('找不到區網 IP，請確認電腦已連上網路。', style: TextStyle(color: kRed))
            else
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: info.encode(), size: 260),
              ),
            const SizedBox(height: 24),
            SelectableText(
              '位址：${info.hosts.join('  /  ')}\nPort：${info.port}\nPIN：${info.pin}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('重新偵測 IP'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectPanel extends StatefulWidget {
  const _ProjectPanel({super.key, required this.store, required this.project});
  final ProjectStore store;
  final BomProject project;

  @override
  State<_ProjectPanel> createState() => _ProjectPanelState();
}

class _ProjectPanelState extends State<_ProjectPanel> {
  BomFilter _filter = BomFilter.all;

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final store = widget.store;
    final theme = Theme.of(context);
    final items = p.items.where(_filter.accepts).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: theme.textTheme.headlineSmall),
                    Text(
                      '${p.sourceFile} · ${p.total} 項 / '
                      '${p.items.fold<int>(0, (s, i) => s + i.qty)} 個零件',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: kRed),
                onPressed: () async {
                  if (await confirmClear(context, p.name)) {
                    await store.clear(p.id);
                  }
                },
                icon: const Icon(Icons.delete_sweep),
                label: const Text('清除打勾'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: BomProgress(checked: p.checkedCount, total: p.total),
        ),
        ValueListenableBuilder<ScanEvent?>(
          valueListenable: store.lastScan,
          builder: (context, event, _) {
            if (event == null || event.projectId != p.id) {
              return const SizedBox(height: 12);
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: ScanResultCard(
                outcome: event.outcome,
                project: p,
                onCheckCandidate: (key) => store.setChecked(p.id, key, true),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: BomFilterBar(
              filter: _filter,
              project: p,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final item = items[i];
              final last = store.lastScan.value;
              return BomItemTile(
                item: item,
                highlight:
                    last != null &&
                    last.projectId == p.id &&
                    DateTime.now().difference(last.at).inSeconds < 5 &&
                    last.outcome.itemKeys.contains(item.key) &&
                    last.outcome.status == ScanStatus.matched,
                onTap: () => store.setChecked(p.id, item.key, !item.checked),
              );
            },
          ),
        ),
      ],
    );
  }
}
