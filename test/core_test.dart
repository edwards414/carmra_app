import 'dart:io';

import 'package:carmra_app/core/ibom_parser.dart';
import 'package:carmra_app/core/lcsc_label.dart';
import 'package:carmra_app/core/lzstring.dart';
import 'package:carmra_app/core/matcher.dart';
import 'package:carmra_app/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The QR content of a real LCSC bag label (CH342F).
const ch342fLabel =
    '{pbn:PICK2205300004,on:WM2611110386001,pc:C2841530,pm:CH342F,qty:2,'
    'mc:TLAN62,cc:1,pdi:248284107,hp:0,wc:zh}';

BomProject projectFrom(ParsedBom bom) => BomProject(
  id: 'p1',
  name: bom.title,
  sourceFile: 'mini_ibom.html',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  items: bom.items,
);

void main() {
  final mini = File('test/fixtures/mini_ibom.html').readAsStringSync();

  group('lzDecompressFromBase64', () {
    test('decodes non-ASCII and repeated text (lz-string output)', () {
      expect(
        lzDecompressFromBase64(
          'm9pje5AEBCDyCyaKDkZA0doMyiyB4NwkftgIYCMBjfIw4s0ikq86ym+ux25hlp1j9rtnz37voIHD+ooWJHipkmRLnT5TIA==',
        ),
        '零件 BOM ✅ 測試 🎉 ${'abcabcabc' * 50}',
      );
    });

    test('returns null for empty input', () {
      expect(lzDecompressFromBase64(''), isNull);
    });
  });

  group('LcscLabel', () {
    test('parses the bag label QR', () {
      final l = LcscLabel.parse(ch342fLabel)!;
      expect(l.partNumber, 'C2841530');
      expect(l.mpn, 'CH342F');
      expect(l.qty, 2);
      expect(l.orderNumber, 'WM2611110386001');
      expect(l.pickNumber, 'PICK2205300004');
      expect(l.isBagLabel, isTrue);
    });

    test('accepts a bare part number', () {
      expect(LcscLabel.parse(' c25804 ')!.partNumber, 'C25804');
      expect(LcscLabel.parse('C25804')!.isBagLabel, isFalse);
    });

    test('manual input may omit the C', () {
      expect(LcscLabel.parseManual('2841530')!.partNumber, 'C2841530');
      expect(LcscLabel.parseManual('c2841530')!.partNumber, 'C2841530');
    });

    test('rejects other codes', () {
      expect(LcscLabel.parse('https://example.com'), isNull);
      expect(LcscLabel.parse('12345'), isNull);
      expect(LcscLabel.parse('{pc:,pm:X}'), isNull);
      expect(LcscLabel.parse(''), isNull);
    });
  });

  group('parseIbomHtml', () {
    final bom = parseIbomHtml(mini);

    test('reads metadata and finds the LCSC field', () {
      expect(bom.title, 'MINI-BOARD');
      expect(bom.revision, 'A1');
      expect(bom.lcscField, 'LCSC');
    });

    test('groups lines by LCSC number and drops skipped footprints', () {
      expect(bom.items.map((i) => i.key), [
        'C25804',
        'C14663',
        'C2986030',
        'CONN|PinHeader_1x04',
        'C44377',
      ]);
      final leds = bom.items[2];
      expect(leds.refs, ['D1', 'D2']);
      expect(leds.values, ['GRN PWR', 'GRN CH1']);
      expect(leds.mpns, ['Everlight 19-217/G7C-AN1P2/6T']);
    });

    test('sorts references naturally', () {
      expect(bom.items.first.refs, ['R1', 'R2', 'R10']);
      expect(bom.items.first.qty, 3);
    });

    test('a line without an LCSC number has no lcsc', () {
      expect(bom.items[3].lcsc, isNull);
      expect(bom.items[3].refs, ['J1']);
    });

    test('rejects pages that are not ibom', () {
      expect(
        () => parseIbomHtml('<html></html>'),
        throwsA(isA<IbomParseException>()),
      );
    });

    test('reads uncompressed pcbdata too', () {
      final html =
          '<script>\nvar config = {"fields": ["Value", "LCSC"]}\n'
          'var pcbdata = {"metadata": {"title": "T"}, "bom": {"both": '
          '[[["R1", 0]]], "skipped": [], "fields": {"0": ["1k", "C21190"]}}}\n'
          '</script>';
      final b = parseIbomHtml(html);
      expect(b.items.single.key, 'C21190');
    });

    test('finds LCSC numbers in an unnamed column', () {
      final html =
          '<script>\nvar config = {"fields": ["Value", "Part"]}\n'
          'var pcbdata = {"metadata": {}, "bom": {"both": '
          '[[["R1", 0]], [["R2", 1]]], "skipped": [], "fields": '
          '{"0": ["1k", "C21190"], "1": ["2k", "C4190"]}}}\n</script>';
      expect(parseIbomHtml(html).items.map((i) => i.key), ['C21190', 'C4190']);
    });
  });

  group('applyScan', () {
    late BomProject project;
    setUp(() => project = projectFrom(parseIbomHtml(mini)));

    test('checks the line on a matching label and counts its quantity', () {
      const label = '{pbn:PICK1,on:WM1,pc:C25804,pm:0603WAF1002T5E,qty:100}';
      final o = applyScan(project, label);
      expect(o.status, ScanStatus.matched);
      expect(o.itemKeys, ['C25804']);
      final item = project.itemByKey('C25804')!;
      expect(item.checked, isTrue);
      expect(item.scannedQty, 100);
      expect(project.checkedCount, 1);

      // The same bag again: already checked, quantity not added twice.
      expect(applyScan(project, label).status, ScanStatus.alreadyChecked);
      expect(item.scannedQty, 100);

      // A second bag of the same part adds its quantity.
      applyScan(project, '{pbn:PICK2,on:WM2,pc:C25804,pm:X,qty:50}');
      expect(item.scannedQty, 150);
    });

    test('a part that is not in the BOM is reported and changes nothing', () {
      final o = applyScan(project, ch342fLabel);
      expect(o.status, ScanStatus.notInBom);
      expect(o.partNumber, 'C2841530');
      expect(o.mpn, 'CH342F');
      expect(project.checkedCount, 0);
    });

    test('a substitute with the same MPN is offered, not checked', () {
      final o = applyScan(
        project,
        '{pbn:P,on:W,pc:C999999,pm:TPS54360BDDAR,qty:5}',
      );
      expect(o.status, ScanStatus.mpnMatch);
      expect(o.itemKeys, ['C44377']);
      expect(project.checkedCount, 0);
    });

    test('a non-LCSC code is invalid', () {
      expect(applyScan(project, 'hello').status, ScanStatus.invalid);
    });

    test('clearChecks resets checks, quantities and seen labels', () {
      applyScan(project, '{pbn:PICK1,on:WM1,pc:C25804,pm:X,qty:100}');
      project.clearChecks();
      expect(project.checkedCount, 0);
      expect(project.itemByKey('C25804')!.scannedQty, 0);
      expect(project.scannedLabels, isEmpty);
    });

    test('survives a JSON round trip', () {
      applyScan(project, '{pbn:PICK1,on:WM1,pc:C25804,pm:X,qty:100}');
      final copy = BomProject.fromJson(project.toJson());
      expect(copy.checkedCount, 1);
      expect(copy.itemByKey('C25804')!.scannedQty, 100);
      expect(copy.scannedLabels, project.scannedLabels);
    });
  });

  // Runs against a real ibom.html when IBOM_PATH is set, e.g.
  // IBOM_PATH=../automation_robot/hardware/AGR-TR-S3-RLY/bom/ibom.html
  final realPath = Platform.environment['IBOM_PATH'];
  test('parses a real ibom.html', () {
    final bom = parseIbomHtml(File(realPath!).readAsStringSync());
    expect(bom.lcscField, isNotNull);
    expect(bom.items, isNotEmpty);
    // ignore: avoid_print
    print(
      '${bom.title} rev ${bom.revision}: ${bom.items.length} lines, '
      '${bom.items.fold<int>(0, (s, i) => s + i.qty)} parts',
    );
    for (final i in bom.items) {
      // ignore: avoid_print
      print(
        '  ${i.key.padRight(10)} x${i.qty}  ${i.refs.join(',')}  ${i.value}',
      );
    }
  }, skip: realPath == null ? 'IBOM_PATH not set' : false);
}
