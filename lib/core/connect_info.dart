const kAppId = 'carmra_bom';
const kDefaultPort = 8787;

/// What the desktop shows as a QR code and the phone needs to connect.
///
/// The QR holds an http link to the desktop,
/// `http://192.168.1.5:8787/connect?pin=123456&hosts=192.168.1.5,10.0.0.2`,
/// so the iPhone Camera opens a page served by the desktop even before the
/// app is installed. That page links to the app with the same data as
/// `carmra://connect?hosts=...&port=8787&pin=123456`.
class ConnectInfo {
  const ConnectInfo({
    required this.hosts,
    required this.port,
    required this.pin,
  });

  /// Candidate addresses of the desktop; the phone uses the first that
  /// answers.
  final List<String> hosts;
  final int port;
  final String pin;

  /// The link shown as the desktop's QR code.
  String encode() => Uri(
    scheme: 'http',
    host: hosts.first,
    port: port,
    path: '/connect',
    queryParameters: {'pin': pin, 'hosts': hosts.join(',')},
  ).toString();

  /// The link that opens the phone app.
  String appLink() => Uri(
    scheme: 'carmra',
    host: 'connect',
    queryParameters: {'hosts': hosts.join(','), 'port': '$port', 'pin': pin},
  ).toString();

  /// Accepts both [encode] and [appLink] forms.
  static ConnectInfo? decode(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null) return null;
    final q = uri.queryParameters;
    final pin = q['pin'];
    final hosts = (q['hosts'] ?? '')
        .split(',')
        .map((h) => h.trim())
        .where((h) => h.isNotEmpty)
        .toList();
    int? port;
    switch (uri.scheme) {
      case 'carmra':
        port = int.tryParse(q['port'] ?? '');
      case 'http':
        if (uri.path != '/connect') return null;
        port = uri.port;
        if (!hosts.contains(uri.host)) hosts.insert(0, uri.host);
      default:
        return null;
    }
    if (hosts.isEmpty || port == null || pin == null || pin.isEmpty) {
      return null;
    }
    return ConnectInfo(hosts: hosts, port: port, pin: pin);
  }
}
