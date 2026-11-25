import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/connect_info.dart';
import '../core/models.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to the desktop's [BomServer].
class ApiClient {
  ApiClient({
    required this.host,
    required this.port,
    required this.pin,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String host;
  final int port;
  final String pin;
  final http.Client _http;

  static const _timeout = Duration(seconds: 6);

  String get address => '$host:$port';

  Uri _uri(String path) =>
      Uri(scheme: 'http', host: host, port: port, path: path);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, dynamic>? body,
    Duration timeout = _timeout,
  ]) async {
    final http.Response res;
    try {
      final headers = {'x-pin': pin, 'content-type': 'application/json'};
      res =
          await (method == 'GET'
                  ? _http.get(_uri(path), headers: headers)
                  : _http.post(
                      _uri(path),
                      headers: headers,
                      body: jsonEncode(body ?? {}),
                    ))
              .timeout(timeout);
    } on TimeoutException {
      throw ApiException('連線逾時（$address）。電腦端 App 有開嗎？同一個 Wi-Fi 嗎？');
    } on SocketException catch (e) {
      throw ApiException('連不到電腦（$address）：${e.osError?.message ?? e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('連不到電腦（$address）：${e.message}');
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw ApiException('電腦回應格式錯誤（HTTP ${res.statusCode}）');
    }
    if (res.statusCode != 200) {
      throw ApiException(json['error']?.toString() ?? 'HTTP ${res.statusCode}');
    }
    return json;
  }

  Future<void> ping({Duration timeout = _timeout}) async {
    final j = await _send('GET', '/api/ping', null, timeout);
    if (j['app'] != kAppId) throw ApiException('$address 不是 BOM 掃描主機');
  }

  Future<List<ProjectSummary>> listProjects() async {
    final j = await _send('GET', '/api/projects');
    return [
      for (final p in j['projects'] as List)
        ProjectSummary.fromJson(p as Map<String, dynamic>),
    ];
  }

  Future<BomProject> getProject(String id) async =>
      BomProject.fromJson(await _send('GET', '/api/projects/$id'));

  Future<(ScanOutcome, BomProject)> scan(String id, String raw) async {
    final j = await _send('POST', '/api/projects/$id/scan', {'raw': raw});
    return (
      ScanOutcome.fromJson(j['outcome'] as Map<String, dynamic>),
      BomProject.fromJson(j['project'] as Map<String, dynamic>),
    );
  }

  Future<BomProject> setChecked(String id, String key, bool checked) async =>
      BomProject.fromJson(
        await _send('POST', '/api/projects/$id/check', {
          'key': key,
          'checked': checked,
        }),
      );

  Future<BomProject> clear(String id) async =>
      BomProject.fromJson(await _send('POST', '/api/projects/$id/clear'));

  void close() => _http.close();

  /// Tries each host in [info] and returns a client for the first that
  /// answers.
  static Future<ApiClient> connect(ConnectInfo info) async {
    ApiException? last;
    for (final host in info.hosts) {
      final client = ApiClient(host: host, port: info.port, pin: info.pin);
      try {
        await client.ping(timeout: const Duration(seconds: 3));
        return client;
      } on ApiException catch (e) {
        last = e;
        client.close();
      }
    }
    throw last ?? ApiException('沒有可用的位址');
  }
}

/// The last desktop the phone paired with.
class SavedConnection {
  static const _key = 'connect_info';

  static Future<ConnectInfo?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    return s == null ? null : ConnectInfo.decode(s);
  }

  /// Saves [info] with [workingHost] tried first next time.
  static Future<void> save(ConnectInfo info, String workingHost) async {
    final prefs = await SharedPreferences.getInstance();
    final hosts = [workingHost, ...info.hosts.where((h) => h != workingHost)];
    await prefs.setString(
      _key,
      ConnectInfo(hosts: hosts, port: info.port, pin: info.pin).encode(),
    );
  }

  static Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
