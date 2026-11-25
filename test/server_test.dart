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
  });
}
