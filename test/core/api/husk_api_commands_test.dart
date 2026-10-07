import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_api.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/models/tools_models.dart';

import '../../support/fake_adapter.dart';

void main() {
  // name → (call, expected path, expected query without token)
  final cases = <String, (Future<Object?> Function(HuskApi), String, Map<String, String>)>{
    'setCamera': ((a) => a.setCamera(front: true, flip: false, rotation: 90, fps: 15, screenQuality: 60, screenFps: 20), '/set',
        {'front': '1', 'flip': '0', 'rot': '90', 'fps': '15', 'sq': '60', 'sfps': '20'}),
    'setCamera partial': ((a) => a.setCamera(front: false), '/set', {'front': '0'}),
    'wake': ((a) => a.wake(), '/wake', {}),
    'tap': ((a) => a.tap(10, 20, display: 2, ms: 600), '/tap', {'x': '10', 'y': '20', 'd': '2', 'ms': '600'}),
    'tap defaults': ((a) => a.tap(1, 2), '/tap', {'x': '1', 'y': '2', 'd': '0'}),
    'swipe': ((a) => a.swipe(1, 2, 3, 4, ms: 300), '/swipe', {'x1': '1', 'y1': '2', 'x2': '3', 'y2': '4', 'd': '0', 'ms': '300'}),
    'key': ((a) => a.key(NavKey.recents), '/key', {'k': 'recents'}),
    'click': ((a) => a.click('Wi-Fi|WLAN', display: 2), '/click', {'match': 'Wi-Fi|WLAN', 'd': '2'}),
    'typeText keeps special characters': ((a) => a.typeText('a&b c?=%'), '/text', {'t': 'a&b c?=%'}),
    'scroll back': ((a) => a.scroll(forward: false), '/scroll', {'d': '0', 'dir': 'back'}),
    'launch drops nulls': ((a) => a.launch(action: 'android.settings.SETTINGS'), '/launch', {'action': 'android.settings.SETTINGS', 'd': '0'}),
    'launch full': ((a) => a.launch(action: 'android.intent.action.VIEW', data: 'https://x.y/?a=1&b=2', package: 'com.android.chrome', display: 2), '/launch',
        {'action': 'android.intent.action.VIEW', 'data': 'https://x.y/?a=1&b=2', 'pkg': 'com.android.chrome', 'd': '2'}),
    'setToken': ((a) => a.setToken('A' * 32), '/token/set', {'new': 'A' * 32}),
    'devOptions probe': ((a) => a.devOptions(probe: true), '/devoptions', {'probe': '1'}),
    'devOptions': ((a) => a.devOptions(), '/devoptions', {}),
    'torch': ((a) => a.torch(on: true), '/torch', {'on': '1'}),
    'vibrate': ((a) => a.vibrate(ms: 500), '/vibrate', {'ms': '500'}),
    'setVolume': ((a) => a.setVolume('media', 7), '/volume', {'stream': 'media', 'level': '7'}),
    'setRinger': ((a) => a.setRinger('vibrate'), '/ringer', {'mode': 'vibrate'}),
    'setBrightness': ((a) => a.setBrightness(128), '/brightness', {'level': '128'}),
    'setMotion keeps an empty topic': ((a) => a.setMotion(enabled: true, topic: '', server: 'https://ntfy.sh', sensitivity: 7), '/motion',
        {'on': '1', 'topic': '', 'server': 'https://ntfy.sh', 'sensitivity': '7'}),
  };

  for (final MapEntry(key: name, value: (call, path, query)) in cases.entries) {
    test('$name → $path $query', () async {
      final f = fakeApi((_) => textBody('OK'), token: 'tok');
      await call(f.api);
      expect(f.adapter.last.path, path);
      expect(f.adapter.last.uri.queryParameters, {...query, 'token': 'tok'});
    });
  }

  group('find', () {
    test('parses "x y"', () async {
      expect(await fakeApi((_) => textBody('540 1056\n')).api.find('Settings'), (x: 540, y: 1056));
    });
    test('NONE → null', () async {
      expect(await fakeApi((_) => textBody('NONE')).api.find('nope'), isNull);
    });
    test('ERR → DeviceErrorException', () async {
      expect(fakeApi((_) => textBody('ERR a11y-off')).api.find('x'), throwsA(isA<DeviceErrorException>()));
    });
  });

  test('getText returns text or null for NONE', () async {
    expect(await fakeApi((_) => textBody('Battery 87%')).api.getText('Battery'), 'Battery 87%');
    expect(await fakeApi((_) => textBody('NONE')).api.getText('x'), isNull);
  });

  test('exists maps 1/0 to bool', () async {
    expect(await fakeApi((_) => textBody('1')).api.exists('x'), isTrue);
    expect(await fakeApi((_) => textBody('0')).api.exists('x'), isFalse);
  });

  test('setMotion throws on an ERR reply', () async {
    expect(fakeApi((_) => textBody('ERR https only')).api.setMotion(server: 'http://x'), throwsA(isA<DeviceErrorException>()));
  });

  test('setToken surfaces 409 as HttpStatusException', () async {
    final f = fakeApi((_) => jsonBody('{"error":"no token set; use /token/request"}', status: 409));
    expect(f.api.setToken('A' * 32), throwsA(isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 409)));
  });
}
