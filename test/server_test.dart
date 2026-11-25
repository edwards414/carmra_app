import 'dart:convert';
import 'dart:io';

import 'package:carmra_app/client/api_client.dart';
import 'package:carmra_app/core/connect_info.dart';
import 'package:carmra_app/core/models.dart';
import 'package:carmra_app/host/bom_server.dart';
import 'package:carmra_app/host/project_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late ProjectStore store;
  late BomServer server;
  late ApiClient client;
  late String projectId;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('carmra_test');
    store = ProjectStore(Directory('${dir.path}/projects'));
    await store.load();
    final project = await store.importIbom(
      File('test/fixtures/mini_ibom.html').readAsStringSync(),
      'mini_ibom.html',
    );
    projectId = project.id;
    final pin = await loadOrCreatePin(dir);
    server = BomServer(store, pin: pin);
    final port = await server.start(preferredPort: 18787);
    client = await ApiClient.connect(
      ConnectInfo(hosts: ['127.0.0.1'], port: port, pin: pin),
    );
  });

  tearDown(() async {
    client.close();
    await server.stop();
    await dir.delete(recursive: true);
  });

  test('connect skips an unreachable host and uses the next', () async {
    final c = await ApiClient.connect(
      ConnectInfo(
        hosts: ['10.255.255.1', '127.0.0.1'],
        port: server.port!,
        pin: server.pin,
      ),
    );
    expect(c.host, '127.0.0.1');
    c.close();
  });

  test('wrong PIN is refused', () async {
    final bad = ApiClient(
      host: '127.0.0.1',
      port: server.port!,
      pin: '000000x',
    );
    await expectLater(bad.ping(), throwsA(isA<ApiException>()));
    bad.close();
  });

  test('list, scan, check, clear', () async {
    final list = await client.listProjects();
    expect(list.single.name, 'MINI-BOARD A1');
    expect(list.single.total, 5);

    final (outcome, project) = await client.scan(
      projectId,
      '{pbn:PICK1,on:WM1,pc:C25804,pm:0603WAF1002T5E,qty:100}',
    );
    expect(outcome.status, ScanStatus.matched);
    expect(project.checkedCount, 1);
    // The desktop sees the same state and the scan event.
    expect(store.byId(projectId)!.checkedCount, 1);
    expect(store.lastScan.value!.outcome.partNumber, 'C25804');

    final (miss, _) = await client.scan(projectId, 'C2841530');
    expect(miss.status, ScanStatus.notInBom);

    var p = await client.setChecked(projectId, 'CONN|PinHeader_1x04', true);
    expect(p.checkedCount, 2);
    p = await client.setChecked(projectId, 'C25804', false);
    expect(p.checkedCount, 1);

    p = await client.clear(projectId);
    expect(p.checkedCount, 0);
  });

  test('state persists across a reload', () async {
    await client.scan(projectId, 'C14663');
    final reloaded = ProjectStore(store.dir);
    await reloaded.load();
    expect(reloaded.byId(projectId)!.itemByKey('C14663')!.checked, isTrue);
  });

  test('the PIN is kept between runs', () async {
    expect(await loadOrCreatePin(dir), server.pin);
  });

  test('connect QR round trip', () {
    const info = ConnectInfo(
      hosts: ['192.168.1.5', '10.0.0.2'],
      port: 8787,
      pin: '123456',
    );
    final back = ConnectInfo.decode(info.encode())!;
    expect(back.hosts, info.hosts);
    expect(back.port, 8787);
    expect(back.pin, '123456');
    expect(ConnectInfo.decode('{pc:C1234}'), isNull);
    expect(info.encode(), startsWith('http://192.168.1.5:8787/connect?'));

    final app = ConnectInfo.decode(info.appLink())!;
    expect(app.hosts, info.hosts);
    expect(app.port, 8787);
    expect(app.pin, '123456');

    // An http link without hosts= still works, from the URL's host.
    final bare = ConnectInfo.decode('http://10.0.0.9:8788/connect?pin=42')!;
    expect(bare.hosts, ['10.0.0.9']);
    expect(bare.port, 8788);
    expect(ConnectInfo.decode('http://10.0.0.9:8788/other?pin=42'), isNull);
  });

  group('browser pages', () {
    Future<(int, String)> get(String pathAndQuery) async {
      final http = HttpClient();
      try {
        final req = await http.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}$pathAndQuery'),
        );
        final res = await req.close();
        return (res.statusCode, await utf8.decodeStream(res));
      } finally {
        http.close();
      }
    }

    test('the QR link shows projects and links to the app', () async {
      final (status, body) = await get(
        '/connect?pin=${server.pin}&hosts=127.0.0.1,10.0.0.2',
      );
      expect(status, 200);
      expect(body, contains('MINI-BOARD A1'));
      expect(body, contains('0 / 5'));
      expect(body, contains('carmra://connect?hosts=127.0.0.1%2C10.0.0.2'));
    });

    test('a project page lists the BOM with checks', () async {
      await client.scan(projectId, 'C25804');
      final (status, body) = await get(
        '/connect/p/$projectId?pin=${server.pin}',
      );
      expect(status, 200);
      expect(body, contains('1 / 5'));
      expect(body, contains('R1, R2, R10'));
      expect(body, contains('✅'));
    });

    test('a wrong PIN is refused', () async {
      final (status, body) = await get('/connect?pin=000');
      expect(status, 401);
      expect(body, isNot(contains('MINI-BOARD')));
    });
  });
}
