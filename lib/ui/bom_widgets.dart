import 'package:flutter/material.dart';

import '../core/models.dart';

const kGreen = Color(0xFF1B8A3A);
const kBlue = Color(0xFF1F5FBF);
const kOrange = Color(0xFFC86A00);
const kRed = Color(0xFFC62828);
const kGrey = Color(0xFF616161);

enum BomFilter { open, all, done }

extension BomFilterLabel on BomFilter {
  String get label => switch (this) {
    BomFilter.open => '未打勾',
    BomFilter.all => '全部',
    BomFilter.done => '已打勾',
  };

  bool accepts(BomItem i) => switch (this) {
    BomFilter.open => !i.checked,
    BomFilter.all => true,
    BomFilter.done => i.checked,
  };
}

/// Progress bar with "checked / total".
class BomProgress extends StatelessWidget {
  const BomProgress({super.key, required this.checked, required this.total});
  final int checked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final done = total > 0 && checked == total;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : checked / total,
              minHeight: 8,
              color: done ? kGreen : null,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$checked / $total',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            color: done ? kGreen : null,
          ),
        ),
      ],
    );
  }
}

class BomFilterBar extends StatelessWidget {
  const BomFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    required this.project,
  });
  final BomFilter filter;
  final ValueChanged<BomFilter> onChanged;
  final BomProject project;

  @override
  Widget build(BuildContext context) {
    int count(BomFilter f) => project.items.where(f.accepts).length;
    return SegmentedButton<BomFilter>(
      showSelectedIcon: false,
      segments: [
        for (final f in BomFilter.values)
          ButtonSegment(value: f, label: Text('${f.label} ${count(f)}')),
      ],
      selected: {filter},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// One BOM line; tap toggles the check.
class BomItemTile extends StatelessWidget {
  const BomItemTile({
    super.key,
    required this.item,
    required this.onTap,
    this.highlight = false,
  });

  final BomItem item;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final details = [
      item.footprint,
      item.mpn,
    ].where((s) => s.isNotEmpty).join(' · ');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: highlight ? kGreen.withValues(alpha: 0.15) : Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          item.checked ? Icons.check_circle : Icons.radio_button_unchecked,
          color: item.checked ? kGreen : muted,
          size: 30,
        ),
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: item.lcsc ?? '無 LCSC',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Menlo',
                  fontFamilyFallback: const ['Courier'],
                  color: item.lcsc == null ? kOrange : null,
                ),
              ),
              TextSpan(text: '   ${item.value}'),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${item.refs.join(', ')}\n$details',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: muted),
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('×${item.qty}', style: theme.textTheme.titleMedium),
            if (item.scannedQty > 0)
              Text(
                '已掃 ${item.scannedQty}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: item.scannedQty >= item.qty ? kGreen : kOrange,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Big colored card telling whether the last scanned label is in the BOM.
class ScanResultCard extends StatelessWidget {
  const ScanResultCard({
    super.key,
    required this.outcome,
    required this.project,
    this.onCheckCandidate,
  });

  final ScanOutcome outcome;
  final BomProject? project;
  final ValueChanged<String>? onCheckCandidate;

  @override
  Widget build(BuildContext context) {
    final (color, icon, title) = switch (outcome.status) {
      ScanStatus.matched => (kGreen, Icons.check_circle, '在 BOM 內，已打勾'),
      ScanStatus.alreadyChecked => (kBlue, Icons.done_all, '在 BOM 內（之前已打勾）'),
      ScanStatus.mpnMatch => (kOrange, Icons.help, 'LCSC 編號不同，但型號相符'),
      ScanStatus.notInBom => (kRed, Icons.cancel, '不在這個 BOM'),
      ScanStatus.invalid => (kGrey, Icons.qr_code_2, '不是 LCSC 料號標籤'),
    };
    final label = [
      if (outcome.partNumber != null) outcome.partNumber!,
      if (outcome.mpn != null) outcome.mpn!,
      if (outcome.labelQty != null) '本包 ${outcome.labelQty} pcs',
    ].join('   ');
    final items = [for (final k in outcome.itemKeys) ?project?.itemByKey(k)];
    const onColor = Colors.white;
    return Card(
      color: color,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: onColor, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: onColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label.isNotEmpty ? label : outcome.raw,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: onColor, fontSize: 16),
            ),
            for (final item in items) ...[
              const SizedBox(height: 4),
              Text(
                '${item.lcsc ?? item.key}  ${item.value}  ×${item.qty}\n'
                '位置：${item.refs.join(', ')}',
                style: const TextStyle(color: onColor, fontSize: 15),
              ),
              if (outcome.status == ScanStatus.mpnMatch &&
                  onCheckCandidate != null &&
                  !item.checked)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FilledButton.tonalIcon(
                    onPressed: () => onCheckCandidate!(item.key),
                    icon: const Icon(Icons.check),
                    label: Text('當作 ${item.lcsc ?? item.key} 打勾'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmClear(BuildContext context, String projectName) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('清除全部打勾？'),
      content: Text('「$projectName」的打勾和已掃數量都會清掉，BOM 本身會保留。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kRed),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('清除'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
