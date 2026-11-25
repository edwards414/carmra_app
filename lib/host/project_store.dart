import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/board.dart';
import '../core/ibom_parser.dart';
import '../core/matcher.dart';
import '../core/models.dart';

/// A scan made from a phone, shown on the desktop.
class ScanEvent {
  ScanEvent(this.projectId, this.outcome, this.at);
  final String projectId;
  final ScanOutcome outcome;
  final DateTime at;
}

/// BOM projects kept as one JSON file each under [dir].
class ProjectStore extends ChangeNotifier {
  ProjectStore(this.dir);

  final Directory dir;
  final Map<String, BomProject> _projects = {};
  final lastScan = ValueNotifier<ScanEvent?>(null);

  List<BomProject> get projects =>
      _projects.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  BomProject? byId(String id) => _projects[id];

  Future<void> load() async {
    await dir.create(recursive: true);
    await for (final f in dir.list()) {
      if (f is! File ||
          !f.path.endsWith('.json') ||
          f.path.endsWith('.board.json')) {
        continue;
      }
      try {
        final p = BomProject.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>,
        );
        _projects[p.id] = p;
      } on Object catch (e) {
        debugPrint('skip ${f.path}: $e');
      }
    }
    notifyListeners();
  }

  /// Creates a project from the contents of an ibom.html.
  /// Throws [IbomParseException] when the page cannot be read.
  Future<BomProject> importIbom(
    String html,
    String fileName, {
    String? name,
  }) async {
    final bom = parseIbomHtml(html);
    if (bom.items.isEmpty) {
      throw IbomParseException('ibom.html 裡沒有任何 BOM 項目。');
    }
    final now = DateTime.now();
    final fallback = fileName.replaceAll(RegExp(r'\.html?$'), '');
    final title = [
      bom.title,
      bom.revision,
    ].where((s) => s.isNotEmpty).join(' ');
    final project = BomProject(
      id: _newId(now),
      name: (name?.trim().isNotEmpty ?? false)
          ? name!.trim()
          : (title.isNotEmpty ? title : fallback),
      sourceFile: fileName,
      createdAt: now,
      updatedAt: now,
      items: bom.items,
    );
    _projects[project.id] = project;
    await _save(project);
    if (bom.board != null) await _saveBoard(project.id, bom.board!);
    notifyListeners();
    return project;
  }

  final Map<String, BoardGeometry?> _boards = {};

  /// The project's board for the location view, or null when its ibom.html
  /// was imported without one (see [attachBoard]).
  Future<BoardGeometry?> board(String id) async {
    if (_boards.containsKey(id)) return _boards[id];
    BoardGeometry? board;
    final f = _boardFile(id);
    if (await f.exists()) {
      try {
        board = BoardGeometry.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>,
        );
      } on Object catch (e) {
        debugPrint('bad board file ${f.path}: $e');
      }
    }
    return _boards[id] = board;
  }

  /// Adds the board from [html] to an existing project, keeping its checks.
  /// Throws [IbomParseException] when the page has no board or its parts do
  /// not belong to the project.
  Future<BoardGeometry> attachBoard(String id, String html) async {
    final p = _projects[id];
    if (p == null) throw ArgumentError('no project $id');
    final board = parseIbomHtml(html).board;
    if (board == null) {
      throw IbomParseException('這個 ibom.html 沒有板子圖資料。');
    }
    final refs = {for (final f in board.footprints) f.ref};
    final bomRefs = [for (final i in p.items) ...i.refs];
    final known = bomRefs.where(refs.contains).length;
    if (bomRefs.isNotEmpty && known < bomRefs.length / 2) {
      throw IbomParseException(
        '這個 ibom.html 的零件和專案「${p.name}」對不起來（$known / ${bomRefs.length} 個位號相符）。',
      );
    }
    await _saveBoard(id, board);
    notifyListeners();
    return board;
  }

  Future<void> _saveBoard(String id, BoardGeometry board) async {
    _boards[id] = board;
    final tmp = File('${dir.path}/$id.board.json.tmp');
    await tmp.writeAsString(jsonEncode(board.toJson()), flush: true);
    await tmp.rename(_boardFile(id).path);
  }

  File _boardFile(String id) => File('${dir.path}/$id.board.json');

  Future<void> delete(String id) async {
    _projects.remove(id);
    _boards.remove(id);
    for (final f in [_file(id), _boardFile(id)]) {
      if (await f.exists()) await f.delete();
    }
    notifyListeners();
  }

  Future<void> rename(String id, String name) => _mutate(id, (p) {
    if (name.trim().isNotEmpty) p.name = name.trim();
  });

  Future<ScanOutcome> scan(String id, String raw) async {
    late ScanOutcome outcome;
    await _mutate(id, (p) => outcome = applyScan(p, raw));
    lastScan.value = ScanEvent(id, outcome, DateTime.now());
    return outcome;
  }

  Future<void> setChecked(String id, String key, bool checked) =>
      _mutate(id, (p) {
        final item = p.itemByKey(key);
        if (item == null) throw ArgumentError('no item $key');
        item.checked = checked;
        item.checkedAt = checked ? DateTime.now() : null;
        if (!checked) item.scannedQty = 0;
      });

  Future<void> clear(String id) => _mutate(id, (p) => p.clearChecks());

  Future<void> _mutate(String id, void Function(BomProject) change) async {
    final p = _projects[id];
    if (p == null) throw ArgumentError('no project $id');
    change(p);
    p.updatedAt = DateTime.now();
    await _save(p);
    notifyListeners();
  }

  File _file(String id) => File('${dir.path}/$id.json');

  // Writes are serialized so two quick scans cannot interleave the rename.
  Future<void> _saving = Future.value();

  Future<void> _save(BomProject p) {
    final json = jsonEncode(p.toJson());
    return _saving = _saving.then((_) async {
      final tmp = File('${dir.path}/${p.id}.json.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(_file(p.id).path);
    });
  }

  static String _newId(DateTime now) {
    final r = Random.secure().nextInt(1 << 32).toRadixString(36);
    return '${now.millisecondsSinceEpoch.toRadixString(36)}$r';
  }

  @override
  void dispose() {
    lastScan.dispose();
    super.dispose();
  }
}
