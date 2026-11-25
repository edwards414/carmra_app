import 'lcsc_label.dart';
import 'models.dart';

/// Matches a scanned code against [project] and checks the line off when the
/// LCSC number is in the BOM. Mutates [project]; the caller persists it.
ScanOutcome applyScan(BomProject project, String raw, {DateTime? now}) {
  final label = LcscLabel.parse(raw);
  if (label == null) {
    return ScanOutcome(status: ScanStatus.invalid, raw: raw.trim());
  }

  ScanOutcome outcome(ScanStatus status, [List<String> keys = const []]) =>
      ScanOutcome(
        status: status,
        raw: label.raw,
        partNumber: label.partNumber,
        mpn: label.mpn,
        labelQty: label.qty,
        itemKeys: keys,
      );

  final item = project.itemByKey(label.partNumber);
  if (item != null) {
    final wasChecked = item.checked;
    if (label.isBagLabel &&
        label.qty != null &&
        project.scannedLabels.add(label.raw)) {
      item.scannedQty += label.qty!;
    }
    if (!wasChecked) {
      item.checked = true;
      item.checkedAt = now ?? DateTime.now();
    }
    project.updatedAt = now ?? DateTime.now();
    return outcome(
      wasChecked ? ScanStatus.alreadyChecked : ScanStatus.matched,
      [item.key],
    );
  }

  final candidates = findMpnCandidates(project, label.mpn);
  if (candidates.isNotEmpty) {
    return outcome(ScanStatus.mpnMatch, [for (final c in candidates) c.key]);
  }
  return outcome(ScanStatus.notInBom);
}

String _norm(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Lines whose MPN or value matches [mpn], for parts bought under a different
/// LCSC number than the one in the BOM.
List<BomItem> findMpnCandidates(BomProject project, String? mpn) {
  if (mpn == null) return const [];
  final m = _norm(mpn);
  if (m.length < 4) return const [];
  return [
    for (final item in project.items)
      if (item.mpns.any((x) => _norm(x).contains(m)) ||
          item.values.any((v) {
            final n = _norm(v);
            return n.length >= 5 &&
                RegExp(r'\d').hasMatch(n) &&
                RegExp(r'[A-Z]').hasMatch(n) &&
                (m.contains(n) || n.contains(m));
          }))
        item,
  ];
}
