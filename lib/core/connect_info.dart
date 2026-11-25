const kAppId = 'carmra_bom';
const kDefaultPort = 8787;

/// What the desktop shows as a QR code and the phone needs to connect:
/// `carmra://connect?hosts=192.168.1.5,10.0.0.2&port=8787&pin=123456`.
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

  String encode() => Uri(
    scheme: 'carmra',
    host: 'connect',
    queryParameters: {'hosts': hosts.join(','), 'port': '$port', 'pin': pin},
  ).toString();

  static ConnectInfo? decode(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != 'carmra') return null;
    final q = uri.queryParameters;
    final hosts = (q['hosts'] ?? '')
        .split(',')
        .map((h) => h.trim())
        .where((h) => h.isNotEmpty)
        .toList();
    final port = int.tryParse(q['port'] ?? '');
    final pin = q['pin'];
    if (hosts.isEmpty || port == null || pin == null || pin.isEmpty) {
      return null;
    }
    return ConnectInfo(hosts: hosts, port: port, pin: pin);
  }
}
