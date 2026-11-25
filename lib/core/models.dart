/// One BOM line. Lines are grouped by LCSC part number, so a bag scanned once
/// covers every reference that uses that part.
class BomItem {
  BomItem({
    required this.key,
    required this.lcsc,
    required this.refs,
    required this.values,
    required this.footprints,
    required this.mpns,
    this.checked = false,
    this.scannedQty = 0,
    this.checkedAt,
  });

  /// The LCSC part number when there is one, otherwise `value|footprint`.
  final String key;
  final String? lcsc;
  final List<String> refs;
  final List<String> values;
  final List<String> footprints;
  final List<String> mpns;

  bool checked;

  /// Sum of `qty:` over the distinct labels scanned for this line.
  int scannedQty;
  DateTime? checkedAt;

  int get qty => refs.length;
  String get value => values.join(' / ');
  String get footprint => footprints.join(' / ');
  String get mpn => mpns.join(' / ');

  factory BomItem.fromJson(Map<String, dynamic> j) => BomItem(
    key: j['key'] as String,
    lcsc: j['lcsc'] as String?,
    refs: _strings(j['refs']),
    values: _strings(j['values']),
    footprints: _strings(j['footprints']),
    mpns: _strings(j['mpns']),
    checked: j['checked'] as bool? ?? false,
    scannedQty: j['scannedQty'] as int? ?? 0,
    checkedAt: j['checkedAt'] == null
        ? null
        : DateTime.parse(j['checkedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'lcsc': lcsc,
    'refs': refs,
    'values': values,
    'footprints': footprints,
    'mpns': mpns,
    'checked': checked,
    'scannedQty': scannedQty,
    'checkedAt': checkedAt?.toIso8601String(),
  };
}

class BomProject {
  BomProject({
    required this.id,
    required this.name,
    required this.sourceFile,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
    Set<String>? scannedLabels,
  }) : scannedLabels = scannedLabels ?? <String>{};

  final String id;
  String name;
  final String sourceFile;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<BomItem> items;

  /// Raw label strings already counted, so rescanning the same bag does not
  /// add its quantity twice.
  final Set<String> scannedLabels;

  int get total => items.length;
  int get checkedCount => items.where((i) => i.checked).length;
  bool get isComplete => total > 0 && checkedCount == total;

  BomItem? itemByKey(String key) {
    for (final item in items) {
      if (item.key == key) return item;
    }
    return null;
  }

  void clearChecks() {
    for (final item in items) {
      item.checked = false;
      item.scannedQty = 0;
      item.checkedAt = null;
    }
    scannedLabels.clear();
  }

  ProjectSummary get summary => ProjectSummary(
    id: id,
    name: name,
    total: total,
    checked: checkedCount,
    updatedAt: updatedAt,
  );

  factory BomProject.fromJson(Map<String, dynamic> j) => BomProject(
    id: j['id'] as String,
    name: j['name'] as String,
    sourceFile: j['sourceFile'] as String? ?? '',
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    items: [
      for (final i in j['items'] as List)
        BomItem.fromJson(i as Map<String, dynamic>),
    ],
    scannedLabels: _strings(j['scannedLabels']).toSet(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sourceFile': sourceFile,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'items': [for (final i in items) i.toJson()],
    'scannedLabels': scannedLabels.toList(),
  };
}

class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.total,
    required this.checked,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int total;
  final int checked;
  final DateTime updatedAt;

  factory ProjectSummary.fromJson(Map<String, dynamic> j) => ProjectSummary(
    id: j['id'] as String,
    name: j['name'] as String,
    total: j['total'] as int,
    checked: j['checked'] as int,
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'total': total,
    'checked': checked,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

enum ScanStatus {
  /// LCSC number is in the BOM; the line was just checked.
  matched,

  /// LCSC number is in the BOM and the line was already checked.
  alreadyChecked,

  /// LCSC number is not in the BOM, but the label's MPN matches a line
  /// (a substitute bought under another LCSC number). Not checked
  /// automatically.
  mpnMatch,

  /// Valid LCSC label, but nothing in the BOM matches.
  notInBom,

  /// Not an LCSC label.
  invalid,
}

class ScanOutcome {
  const ScanOutcome({
    required this.status,
    required this.raw,
    this.partNumber,
    this.mpn,
    this.labelQty,
    this.itemKeys = const [],
  });

  final ScanStatus status;
  final String raw;
  final String? partNumber;
  final String? mpn;
  final int? labelQty;

  /// The matched line (matched / alreadyChecked) or the candidates (mpnMatch).
  final List<String> itemKeys;

  factory ScanOutcome.fromJson(Map<String, dynamic> j) => ScanOutcome(
    status: ScanStatus.values.byName(j['status'] as String),
    raw: j['raw'] as String? ?? '',
    partNumber: j['partNumber'] as String?,
    mpn: j['mpn'] as String?,
    labelQty: j['labelQty'] as int?,
    itemKeys: _strings(j['itemKeys']),
  );

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'raw': raw,
    'partNumber': partNumber,
    'mpn': mpn,
    'labelQty': labelQty,
    'itemKeys': itemKeys,
  };
}

List<String> _strings(Object? v) =>
    v == null ? <String>[] : [for (final s in v as List) s as String];
