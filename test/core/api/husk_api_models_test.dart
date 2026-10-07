import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';

import '../../support/fake_adapter.dart';

// Captured from the SM-A750F test phone on 2026-10-07.
const infoJson = '{"app":{"package":"co.xplat.husk","versionName":"1.4","versionCode":"55"},'
    '"device":{"manufacturer":"samsung","model":"SM-A750F","androidRelease":"10","sdkInt":29,"dexCapable":false,"hasCamera":true},'
    '"screen":{"width":1080,"height":2112},"net":{"localIp":"192.168.0.106","tailscaleIp":null},'
    '"battery":{"level":87,"charging":false},"services":{"a11y":true,"camera":true,"screen":false,"dexReconnect":false}}';
const flagsJson = '{"dexReconnect":false,"a11y":true,"camera":true,"front":true,"screen":false,"motion":false,"ntfy":false,"batteryOptIgnored":true,"lastNtfy":""}';
const batteryJson = '{"level":100,"charging":true,"status":"full","health":"good","plugged":"usb","temperatureC":28.8,"voltageMv":4150,"technology":"Li-ion"}';
const displayJson = '{"width":1080,"height":2112,"densityDpi":360,"density":2.25,"refreshHz":60.000004,"rotation":"0"}';
const volumeJson = '{"media":{"level":0,"max":15},"ring":{"level":0,"max":15},"alarm":{"level":11,"max":15},"notification":{"level":0,"max":15},"system":{"level":0,"max":15},"call":{"level":4,"max":5}}';
const sensorsJson = '[{"name":"LSM6DSL Accelerometer","type":1,"vendor":"STM","power":0.13,"max":39.2266},{"name":"CM36658 Light","type":5,"vendor":"Capella Microsystems, Inc.","power":0.75,"max":60000.0}]';
const motionJson = '{"enabled":false,"ntfyServer":"https://ntfy.sh","ntfyTopic":"","sensitivity":5,"lastNtfy":""}';

void main() {
  test('info() parses the nested device snapshot', () async {
    final f = fakeApi((_) => jsonBody(infoJson));
    final info = await f.api.info();
    expect(info.appVersionName, '1.4');
    expect(info.displayName, 'samsung SM-A750F');
    expect(info.sdkInt, 29);
    expect(info.screenWidth, 1080);
    expect(info.localIp, '192.168.0.106');
    expect(info.tailscaleIp, isNull);
    expect(info.batteryLevel, 87);
    expect(info.services.a11y, isTrue);
    expect(info.services.screen, isFalse);
  });

  test('flags()', () async {
    final flags = await fakeApi((_) => jsonBody(flagsJson)).api.flags();
    expect(flags.front, isTrue);
    expect(flags.screen, isFalse);
    expect(flags.batteryOptIgnored, isTrue);
  });

  test('battery()', () async {
    final b = await fakeApi((_) => jsonBody(batteryJson)).api.battery();
    expect(b.level, 100);
    expect(b.charging, isTrue);
    expect(b.temperatureC, 28.8);
    expect(b.voltageMv, 4150);
    expect(b.technology, 'Li-ion');
  });

  test('display() accepts rotation as a string', () async {
    final d = await fakeApi((_) => jsonBody(displayJson)).api.display();
    expect((d.width, d.height, d.rotation, d.densityDpi), (1080, 2112, 0, 360));
  });

  test('display() sends d only for a non-default display', () async {
    final f = fakeApi((_) => jsonBody(displayJson));
    await f.api.display();
    expect(f.adapter.last.uri.queryParameters.containsKey('d'), isFalse);
    await f.api.display(display: 1);
    expect(f.adapter.last.uri.queryParameters['d'], '1');
  });

  test('connectivity()', () async {
    final c = await fakeApi((_) => jsonBody('{"connected":true,"type":"wifi","metered":false,"validated":true}')).api.connectivity();
    expect((c.connected, c.type, c.metered, c.validated), (true, 'wifi', false, true));
  });

  test('location() turns a plain-text ERR reply into DeviceErrorException', () async {
    final f = fakeApi((_) => textBody('ERR no-fix (no known position; is location turned on?)'));
    expect(f.api.location(), throwsA(isA<DeviceErrorException>().having((e) => e.message, 'message', contains('no-fix'))));
  });

  test('location() parses a fix', () async {
    final l = await fakeApi((_) => jsonBody('{"lat":55.67,"lon":12.56,"accuracyM":12.5,"altitude":20.0,"time":1759838400000,"provider":"fused"}')).api.location();
    expect((l.lat, l.lon, l.provider), (55.67, 12.56, 'fused'));
    expect(l.time, DateTime.fromMillisecondsSinceEpoch(1759838400000));
  });

  test('mic()', () async {
    final m = await fakeApi((_) => jsonBody('{"amplitude":16383,"max":32767}')).api.mic();
    expect(m.fraction, closeTo(0.5, 0.001));
  });

  test('volume() keeps every stream in order', () async {
    final v = await fakeApi((_) => jsonBody(volumeJson)).api.volume();
    expect(v.keys, ['media', 'ring', 'alarm', 'notification', 'system', 'call']);
    expect((v['alarm']!.level, v['call']!.max), (11, 5));
  });

  test('ringerMode() and brightness()', () async {
    expect(await fakeApi((_) => jsonBody('{"mode":"silent"}')).api.ringerMode(), 'silent');
    final b = await fakeApi((_) => jsonBody('{"level":105,"max":255,"auto":true}')).api.brightness();
    expect((b.level, b.max, b.auto), (105, 255, true));
  });

  test('sensors() and sensor(type)', () async {
    final list = await fakeApi((_) => jsonBody(sensorsJson)).api.sensors();
    expect(list.map((s) => s.name), ['LSM6DSL Accelerometer', 'CM36658 Light']);
    expect(list.last.type, 5);
    final f = fakeApi((_) => jsonBody('{"sensor":"CM36658 Light","type":5,"values":[5.0]}'));
    final reading = await f.api.sensor('light');
    expect(f.adapter.last.uri.queryParameters['type'], 'light');
    expect(reading.values, [5.0]);
  });

  test('displays() parses the plain-text list', () async {
    final d = await fakeApi((_) => textBody('0:0\n2:1\n')).api.displays();
    expect(d.map((e) => e.id), [0, 2]);
    expect(d.first.raw, '0:0');
  });

  test('motion() and events()', () async {
    final m = await fakeApi((_) => jsonBody(motionJson)).api.motion();
    expect((m.enabled, m.ntfyServer, m.ntfyTopic, m.sensitivity), (false, 'https://ntfy.sh', '', 5));
    final e = await fakeApi((_) => jsonBody('[{"t":1759838400000,"source":"camera","change":12.5}]')).api.events();
    expect(e.single.source, 'camera');
    expect(e.single.change, 12.5);
    expect(e.single.time, DateTime.fromMillisecondsSinceEpoch(1759838400000));
    expect(await fakeApi((_) => jsonBody('[]')).api.events(), isEmpty);
  });

  test('requestToken() sends client, never the token', () async {
    final f = fakeApi((_) => jsonBody('{"id":"0123456789abcdef0123456789abcdef","expires_in":120}'), token: 'old');
    final r = await f.api.requestToken(client: 'Husk Config');
    expect((r.id, r.expiresIn), ('0123456789abcdef0123456789abcdef', 120));
    expect(f.adapter.last.uri.queryParameters, {'client': 'Husk Config'});
  });

  test('tokenStatus() parses every state', () async {
    Future<TokenStatus> status(String body) => fakeApi((_) => jsonBody(body)).api.tokenStatus('id1');
    expect((await status('{"status":"pending"}')).state, TokenState.pending);
    expect((await status('{"status":"denied"}')).state, TokenState.denied);
    expect((await status('{"status":"expired"}')).state, TokenState.expired);
    final approved = await status('{"status":"approved","token":"abc"}');
    expect((approved.state, approved.token), (TokenState.approved, 'abc'));
    expect((await status('{"status":"weird"}')).state, TokenState.expired);
  });

  test('wd() and pair()', () async {
    final wd = await fakeApi((_) => jsonBody('{"ip":"192.168.0.106","port":37123,"ipport":"192.168.0.106:37123"}')).api.wd();
    expect((wd.ip, wd.port, wd.ipport), ('192.168.0.106', 37123, '192.168.0.106:37123'));
    final pair = await fakeApi((_) => jsonBody('{"addr":"192.168.0.106:41234","code":"123456"}')).api.pair();
    expect((pair.addr, pair.code), ('192.168.0.106:41234', '123456'));
    expect(fakeApi((_) => textBody('ERR needs-api30')).api.wd(), throwsA(isA<DeviceErrorException>()));
  });
}
