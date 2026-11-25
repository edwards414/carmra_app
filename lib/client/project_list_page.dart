import 'package:flutter/material.dart';

import '../core/models.dart';
import '../ui/bom_widgets.dart';
import 'api_client.dart';
import 'connect_page.dart';
import 'scan_page.dart';

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({super.key, required this.client});
  final ApiClient client;

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  List<ProjectSummary>? _projects;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.client.listProjects();
      if (mounted) {
        setState(() {
          _projects = list;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _switchHost() async {
    final saved = await SavedConnection.load();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ConnectPage(saved: saved)),
    );
  }

  Future<void> _open(ProjectSummary p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanPage(client: widget.client, summary: p),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return Scaffold(
      appBar: AppBar(
        title: const Text('選擇 BOM 專案'),
        actions: [
          IconButton(
            tooltip: '切換電腦',
            onPressed: _switchHost,
            icon: const Icon(Icons.computer),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '已連線 ${widget.client.address}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_error!, style: const TextStyle(color: kRed)),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: _load, child: const Text('重試')),
                  ],
                ),
              ),
            if (projects == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (projects != null && projects.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '電腦上還沒有專案。先在電腦 App 上傳 ibom.html，再下拉重新整理。',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final p in projects ?? const <ProjectSummary>[])
              Card(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  title: Text(
                    p.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: BomProgress(checked: p.checked, total: p.total),
                  ),
                  trailing: const Icon(Icons.qr_code_scanner),
                  onTap: () => _open(p),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
