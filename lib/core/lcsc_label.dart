/// The QR code on an LCSC bag label, e.g.
/// `{pbn:PICK2205300004,on:WM2611110386001,pc:C2841530,pm:CH342F,qty:2,...}`.
class LcscLabel {
  const LcscLabel({
    required this.raw,
    required this.partNumber,
    this.mpn,
    this.qty,
    this.orderNumber,
    this.pickNumber,
  });

  final String raw;

  /// LCSC part number, upper case (`C2841530`).
  final String partNumber;
  final String? mpn;
  final int? qty;
  final String? orderNumber;
  final String? pickNumber;

  /// True when the label identifies one physical bag, so its quantity can be
  /// counted once.
  bool get isBagLabel => orderNumber != null || pickNumber != null;

  /// Parses a scanned code. Accepts the LCSC label QR and a bare part number
  /// (`C2841530`). Returns null for anything else.
  static LcscLabel? parse(String raw) {
    final text = raw.trim();
    final pc = _field(text, 'pc');
    if (pc != null) {
      final number = _normalizePart(pc);
      if (number == null) return null;
      return LcscLabel(
        raw: text,
        partNumber: number,
        mpn: _field(text, 'pm'),
        qty: int.tryParse(_field(text, 'qty') ?? ''),
        orderNumber: _field(text, 'on'),
        pickNumber: _field(text, 'pbn'),
      );
    }
    final number = _normalizePart(text);
    return number == null ? null : LcscLabel(raw: text, partNumber: number);
  }

  /// Parses what someone typed: `C2841530`, `c2841530` or `2841530`.
  static LcscLabel? parseManual(String input) {
    final t = input.trim().toUpperCase();
    return parse(RegExp(r'^\d{3,}$').hasMatch(t) ? 'C$t' : t);
  }

  static String? _field(String text, String key) {
    final m = RegExp('(?:^|[{,])\\s*$key\\s*:\\s*([^,}]*)').firstMatch(text);
    final v = m?.group(1)?.trim();
    return (v == null || v.isEmpty || v == 'null') ? null : v;
  }

  static String? _normalizePart(String s) {
    final t = s.trim().toUpperCase();
    return RegExp(r'^C\d{3,}$').hasMatch(t) ? t : null;
  }
}
