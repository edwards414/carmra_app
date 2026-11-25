import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/connect_info.dart';
import 'project_store.dart';
import 'web_pages.dart' as web;

/// LAN HTTP API the phone app talks to. Every request carries the PIN in the
/// `x-pin` header.
///
///   GET  /api/ping
///   GET  /api/projects
///   GET  /api/projects/{id}
///   POST /api/projects/{id}/scan    `{"raw": "<QR text>"}`
///   POST /api/projects/{id}/check   `{"key": "C25804", "checked": true}`
///   POST /api/projects/{id}/clear
///
/// Plus read-only pages for a phone browser (PIN in the query), which is what
/// the desktop's QR code opens in the iPhone Camera:
///
///   GET  /connect?pin=...&hosts=...
///   GET  /connect/p/{id}?pin=...
class BomServer {
  BomServer(this.store, {required this.pin});

  final ProjectStore store;
  final String pin;
  HttpServer? _server;

  int? get port => _server?.port;

  /// Binds [preferredPort], or the next free port above it.
  Future<int> start({int preferredPort = kDefaultPort}) async {
    SocketException? last;
    for (var p = preferredPort; p < preferredPort + 10; p++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, p);
        break;
      } on SocketException catch (e) {
        last = e;
      }
    }
    final server = _server;
    if (server == null) throw last!;
    server.listen((req) => unawaited(_handle(req)));
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final first = req.uri.pathSegments.firstOrNull;
      if (first == 'connect' && req.method == 'GET') return _page(req);
      if (req.headers.value('x-pin') != pin) {
        return _json(req, 401, {'error': 'PIN 錯誤'});
      }
      final seg = req.uri.pathSegments;
      if (seg.length < 2 || seg[0] != 'api') {
        return _json(req, 404, {'error': 'not found'});
      }
      final method = req.method;

      if (seg.length == 2 && seg[1] == 'ping' && method == 'GET') {
        return _json(req, 200, {
          'app': kAppId,
          'host': Platform.localHostname,
          'projects': store.projects.length,
        });
      }
      if (seg[1] != 'projects') return _json(req, 404, {'error': 'not found'});

      if (seg.length == 2 && method == 'GET') {
        return _json(req, 200, {
          'projects': [for (final p in store.projects) p.summary.toJson()],
        });
      }

      final project = seg.length >= 3 ? store.byId(seg[2]) : null;
      if (project == null) return _json(req, 404, {'error': '找不到專案'});

      if (seg.length == 3 && method == 'GET') {
        return _json(req, 200, project.toJson());
      }
      if (seg.length == 4 && method == 'POST') {
        final body = await _body(req);
        switch (seg[3]) {
          case 'scan':
            final raw = body['raw'];
            if (raw is! String) return _json(req, 400, {'error': 'raw 必填'});
            final outcome = await store.scan(project.id, raw);
            return _json(req, 200, {
              'outcome': outcome.toJson(),
              'project': project.toJson(),
            });
          case 'check':
            final key = body['key'];
            final checked = body['checked'];
            if (key is! String || checked is! bool) {
              return _json(req, 400, {'error': 'key / checked 必填'});
            }
            if (project.itemByKey(key) == null) {
              return _json(req, 404, {'error': '找不到項目 $key'});
            }
            await store.setChecked(project.id, key, checked);
            return _json(req, 200, project.toJson());
          case 'clear':
            await store.clear(project.id);
            return _json(req, 200, project.toJson());
        }
      }
      return _json(req, 404, {'error': 'not found'});
    } on Object catch (e, st) {
      debugPrint('server error: $e\n$st');
      try {
        await _json(req, 500, {'error': '$e'});
      } on Object {
        // The response was already started.
      }
    }
  }

  Future<void> _page(HttpRequest req) async {
    final q = req.uri.queryParameters;
    if (q['pin'] != pin) {
      return _html(req, 401, web.errorPage('PIN 錯誤，請重新掃電腦上的 QR code'));
    }
    final seg = req.uri.pathSegments;
    if (seg.length == 1) {
      final hosts = (q['hosts'] ?? '').split(',').where((h) => h.isNotEmpty);
      final info = ConnectInfo(
        hosts: [
          req.requestedUri.host,
          ...hosts.where((h) => h != req.requestedUri.host),
        ],
        port: port!,
        pin: pin,
      );
      return _html(
        req,
        200,
        web.connectPage(
          info: info,
          hostName: Platform.localHostname,
          projects: store.projects,
        ),
      );
    }
    final project = seg.length == 3 && seg[1] == 'p'
        ? store.byId(seg[2])
        : null;
    if (project == null) return _html(req, 404, web.errorPage('找不到專案'));
    return _html(req, 200, web.projectPage(project, pin: pin));
  }

  static Future<void> _html(HttpRequest req, int status, String body) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..headers.set('cache-control', 'no-store')
      ..write(body);
    await req.response.close();
  }

  static Future<Map<String, dynamic>> _body(HttpRequest req) async {
    final text = await utf8.decodeStream(req);
    if (text.trim().isEmpty) return {};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  static Future<void> _json(HttpRequest req, int status, Object body) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }

  /// IPv4 addresses a phone on the same network can reach, Wi-Fi/Ethernet
  /// first.
  static Future<List<String>> lanAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    int rank(NetworkInterface i) {
      final n = i.name;
      if (n == 'en0' || n.startsWith('wl') || n.startsWith('eth')) return 0;
      if (n.startsWith('en')) return 1;
      if (n.startsWith('bridge') || n.startsWith('utun')) return 3;
      return 2;
    }

    interfaces.sort((a, b) => rank(a).compareTo(rank(b)));
    return [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLinkLocal) a.address,
    ];
  }
}

/// Returns the saved 6-digit PIN, creating one on first run.
Future<String> loadOrCreatePin(Directory dir) async {
  final f = File('${dir.path}/host.json');
  try {
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final pin = j['pin'];
    if (pin is String && RegExp(r'^\d{6}$').hasMatch(pin)) return pin;
  } on Object {
    // First run or unreadable: make a new one.
  }
  final pin = Random.secure().nextInt(1000000).toString().padLeft(6, '0');
  await dir.create(recursive: true);
  await f.writeAsString(jsonEncode({'pin': pin}));
  return pin;
}
