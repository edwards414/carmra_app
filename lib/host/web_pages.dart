import 'dart:convert';

import '../core/connect_info.dart';
import '../core/models.dart';

/// Read-only pages for a phone browser: what the iPhone Camera opens when it
/// scans the desktop's QR code.

const _esc = HtmlEscape();
const _attr = HtmlEscape(HtmlEscapeMode.attribute);

String _page(String title, String body, {bool refresh = false}) =>
    '''
<!doctype html>
<html lang="zh-Hant"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
${refresh ? '<meta http-equiv="refresh" content="5">' : ''}
<title>${_esc.convert(title)}</title>
<style>
  body { font: 16px -apple-system, system-ui, sans-serif; margin: 0; padding: 16px;
         color: #1b1b1b; background: #f6f7f6; }
  h1 { font-size: 22px; margin: 4px 0 12px; }
  .muted { color: #666; font-size: 14px; }
  .btn { display: block; text-align: center; padding: 14px; border-radius: 12px;
         background: #1b6e5a; color: #fff; text-decoration: none; font-weight: 600;
         margin: 16px 0; }
  .card { display: block; background: #fff; border-radius: 12px; padding: 14px;
          margin: 10px 0; color: inherit; text-decoration: none;
          box-shadow: 0 1px 2px rgba(0,0,0,.08); }
  .bar { height: 8px; background: #e3e6e4; border-radius: 4px; overflow: hidden; margin-top: 8px; }
  .bar > div { height: 100%; background: #1b6e5a; }
  .row { display: flex; gap: 10px; padding: 10px 0; border-bottom: 1px solid #e6e6e6; }
  .row .ok { font-size: 20px; }
  .lcsc { font-family: Menlo, monospace; font-weight: 600; }
  @media (prefers-color-scheme: dark) {
    body { background: #121413; color: #e6e6e6; }
    .card { background: #1e2120; } .row { border-color: #2c302e; } .muted { color: #999; }
  }
</style></head><body>$body</body></html>''';

String _progress(int checked, int total) {
  final pct = total == 0 ? 0 : (checked * 100 / total).round();
  return '<div class="muted">$checked / $total 已打勾</div>'
      '<div class="bar"><div style="width:$pct%"></div></div>';
}

String connectPage({
  required ConnectInfo info,
  required String hostName,
  required List<BomProject> projects,
}) {
  final pin = Uri.encodeQueryComponent(info.pin);
  final cards = projects.isEmpty
      ? '<p class="muted">電腦上還沒有專案，先在電腦 App 上傳 ibom.html。</p>'
      : projects
            .map(
              (p) =>
                  '<a class="card" href="/connect/p/${Uri.encodeComponent(p.id)}?pin=$pin">'
                  '<strong>${_esc.convert(p.name)}</strong>'
                  '${_progress(p.checkedCount, p.total)}</a>',
            )
            .join();
  return _page('BOM 掃描', '''
<h1>✅ 已連到電腦 ${_esc.convert(hostName)}</h1>
<p class="muted">手機和電腦網路是通的。要掃零件請用 BOM 掃描 App：</p>
<a class="btn" href="${_attr.convert(info.appLink())}">在 BOM 掃描 App 中開啟</a>
<p class="muted">按了沒反應代表 App 還沒安裝，請先從 TestFlight 安裝。</p>
<h1>專案</h1>
$cards''');
}

String projectPage(BomProject p, {required String pin}) {
  final rows = p.items
      .map(
        (i) =>
            '<div class="row"><div class="ok">${i.checked ? '✅' : '⬜️'}</div><div>'
            '<span class="lcsc">${_esc.convert(i.lcsc ?? '無 LCSC')}</span> '
            '${_esc.convert(i.value)} ×${i.qty}'
            '<div class="muted">${_esc.convert(i.refs.join(', '))}</div></div></div>',
      )
      .join();
  return _page(p.name, '''
<p><a class="muted" href="/connect?pin=${Uri.encodeQueryComponent(pin)}">← 專案列表</a></p>
<h1>${_esc.convert(p.name)}</h1>
${_progress(p.checkedCount, p.total)}
<p class="muted">每 5 秒自動更新。掃描與打勾請用 App。</p>
$rows''', refresh: true);
}

String errorPage(String message) =>
    _page('BOM 掃描', '<h1>⚠️ ${_esc.convert(message)}</h1>');
