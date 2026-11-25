import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:carmra_app/core/board.dart';
import 'package:carmra_app/core/ibom_parser.dart';
import 'package:carmra_app/host/project_store.dart';
import 'package:carmra_app/ui/board_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mini = File('test/fixtures/mini_ibom.html').readAsStringSync();
  final board = parseIbomHtml(mini).board!;

  group('board geometry', () {
    test('reads the outline, silkscreen and footprints', () {
      expect(board.width, 40);
      expect(board.height, 30);
      expect(board.edges, hasLength(8));
      expect(board.outline, hasLength(1), reason: 'edges chain into one loop');
      expect(board.outline.single.closed, isTrue);
      // segment + 2 svg strokes + polygon
      expect(board.silk['F'], hasLength(4));
      expect(board.silk['F']!.last.filled, isTrue);
      expect(board.footprints, hasLength(9));
      expect(board.footprint('D2')!.layer, 'B');
      expect(board.hasSide('B'), isTrue);
    });

    test('finds a part by position, on its side only', () {
      expect(board.footprintAt(10, 10, 'F')!.ref, 'R1');
      expect(board.footprintAt(10.9, 10.4, 'F')!.ref, 'R1');
      expect(board.footprintAt(11.2, 10, 'F'), isNull);
      expect(board.footprintAt(25, 20, 'F'), isNull);
      expect(board.footprintAt(25, 20, 'B')!.ref, 'D2');
    });

    test('a rotated part has a rotated box', () {
      // C1 is 2 x 1 mm turned 90 degrees, so 1 mm wide and 2 mm tall.
      expect(board.footprintAt(10, 10 + 0.9, 'F'), isNull, reason: 'R1 row');
      expect(board.footprintAt(10, 20.9, 'F')!.ref, 'C1');
      expect(board.footprintAt(10.9, 20, 'F'), isNull);
      final (cx, cy) = board.footprint('C1')!.center;
      expect(cx, closeTo(10, 1e-9));
      expect(cy, closeTo(20, 1e-9));
    });

    test('survives a JSON round trip', () {
      final copy = BoardGeometry.fromJson(
        jsonDecode(jsonEncode(board.toJson())) as Map<String, dynamic>,
      );
      expect(
        copy.footprints.map((f) => f.ref),
        board.footprints.map((f) => f.ref),
      );
      expect(
        copy.outline.single.points.length,
        board.outline.single.points.length,
      );
      expect(copy.footprintAt(25, 20, 'B')!.ref, 'D2');
      expect(copy.footprint('R1')!.pads, hasLength(2));
    });

    test('an open outline is not filled', () {
      final open = chainOutline(const [
        BoardShape([0, 0, 10, 0]),
        BoardShape([10, 0, 10, 10]),
      ]);
      expect(open, isEmpty);
    });

    test('a page without a board still imports', () {
      final html =
          '<script>\nvar config = {"fields": ["Value", "LCSC"]}\n'
          'var pcbdata = {"metadata": {}, "bom": {"both": '
          '[[["R1", 0]]], "skipped": [], "fields": {"0": ["1k", "C21190"]}}}\n'
          '</script>';
      final bom = parseIbomHtml(html);
      expect(bom.items, hasLength(1));
      expect(bom.board, isNull);
    });
  });

  group('project store boards', () {
    late Directory dir;
    late ProjectStore store;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('carmra_board');
      store = ProjectStore(dir);
      await store.load();
    });
    tearDown(() => dir.delete(recursive: true));

    test('import keeps the board, and a reload finds it', () async {
      final p = await store.importIbom(mini, 'mini_ibom.html');
      final again = ProjectStore(dir);
      await again.load();
      expect(
        again.projects,
        hasLength(1),
        reason: 'board file is not a project',
      );
      expect((await again.board(p.id))!.footprints, hasLength(9));
    });

    test(
      'attachBoard adds a board to an older project and keeps checks',
      () async {
        final p = await store.importIbom(mini, 'mini_ibom.html');
        await store.scan(p.id, 'C25804');
        File('${dir.path}/${p.id}.board.json').deleteSync();
        final fresh = ProjectStore(dir);
        await fresh.load();
        expect(await fresh.board(p.id), isNull);

        await fresh.attachBoard(p.id, mini);
        expect((await fresh.board(p.id))!.footprints, hasLength(9));
        expect(fresh.byId(p.id)!.checkedCount, 1);
      },
    );

    test('attachBoard refuses another board', () async {
      final p = await store.importIbom(mini, 'mini_ibom.html');
      final unrelated =
          '<script>\nvar config = {"fields": ["Value", "LCSC"]}\n'
          'var pcbdata = {"metadata": {}, "edges_bbox": {"minx": 0, "miny": 0, '
          '"maxx": 1, "maxy": 1}, "edges": [], "footprints": [{"ref": "Z1", '
          '"layer": "F", "bbox": {"pos": [0, 0], "relpos": [0, 0], '
          '"size": [1, 1], "angle": 0}, "pads": []}], "bom": {"both": '
          '[[["Z1", 0]]], "skipped": [], "fields": {"0": ["1k", "C21190"]}}}\n'
          '</script>';
      await expectLater(
        store.attachBoard(p.id, unrelated),
        throwsA(isA<IbomParseException>()),
      );
    });

    test('deleting a project removes its board file', () async {
      final p = await store.importIbom(mini, 'mini_ibom.html');
      await store.delete(p.id);
      expect(File('${dir.path}/${p.id}.board.json').existsSync(), isFalse);
    });
  });

  testWidgets('board view paints and picks a part by click', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: BoardView(
              board: board,
              highlight: const {'R1', 'R2', 'R10'},
              checked: const {'C1'},
              onTapRef: (r) => tapped = r,
            ),
          ),
        ),
      ),
    );
    expect(find.text('目前這顆料'), findsOneWidget);
    expect(find.text('正面'), findsOneWidget, reason: 'board has a back side');

    // Click where U1 (30, 8) is: map board mm to the paint area.
    final paint = find.byType(CustomPaint).last;
    final box = tester.getRect(paint);
    const pad = 24.0;
    final scale = [
      (box.width - 2 * pad) / 40,
      (box.height - 2 * pad) / 30,
    ].reduce((a, b) => a < b ? a : b);
    final ox = (box.width - 40 * scale) / 2, oy = (box.height - 30 * scale) / 2;
    await tester.tapAt(box.topLeft + Offset(ox + 30 * scale, oy + 8 * scale));
    expect(tapped, 'U1');
  });

  // Renders a real ibom's board to a PNG to eyeball it:
  // IBOM_PATH=... BOARD_PNG=/tmp/board.png flutter test test/board_test.dart
  final ibomPath = Platform.environment['IBOM_PATH'];
  final pngPath = Platform.environment['BOARD_PNG'];
  testWidgets('render a real board', (tester) async {
    final real = parseIbomHtml(File(ibomPath!).readAsStringSync()).board!;
    final key = GlobalKey();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: BoardView(
              board: real,
              highlight: const {'R102', 'R204', 'R205', 'R206', 'R211', 'R212'},
              checked: const {'C201', 'C202', 'C204', 'C205', 'U101', 'L101'},
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(pngPath!).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }, skip: ibomPath == null || pngPath == null);
}
