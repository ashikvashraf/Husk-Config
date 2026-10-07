import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/providers.dart';
import 'package:huskconfig/core/storage/server_config.dart';
import 'package:huskconfig/features/servers/api_provider.dart';
import 'package:huskconfig/features/servers/servers_controller.dart';

import '../../support/memory_repos.dart';

void main() {
  late MemoryServerRepository repo;

  ProviderContainer container() {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [serverRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => repo = MemoryServerRepository([
        ServerConfig(id: 's1', name: 'One', host: '10.0.0.1', port: 8090, createdAt: DateTime.utc(2026)),
      ]));

  test('loads saved servers', () {
    expect(container().read(serversProvider).map((s) => s.id), ['s1']);
  });

  test('add persists with a fresh id and drops an empty token', () async {
    final c = container();
    final added = await c.read(serversProvider.notifier).add(name: 'Two', host: '10.0.0.2', port: 8091, token: '');
    expect(added.id, isNot('s1'));
    expect(added.token, isNull);
    expect(repo.saved.map((s) => s.name), ['One', 'Two']);
  });

  test('update, setToken, touch and remove persist', () async {
    final c = container();
    final notifier = c.read(serversProvider.notifier);
    await notifier.update(notifier.byId('s1')!.copyWith(name: 'Renamed'));
    await notifier.setToken('s1', 'tok');
    await notifier.touch('s1');
    expect(repo.saved.single.name, 'Renamed');
    expect(repo.saved.single.token, 'tok');
    expect(repo.saved.single.lastUsedAt, isNotNull);
    await notifier.remove('s1');
    expect(repo.saved, isEmpty);
  });

  test('isDuplicate compares host and port, excluding the edited server', () {
    final notifier = container().read(serversProvider.notifier);
    expect(notifier.isDuplicate('10.0.0.1', 8090), isTrue);
    expect(notifier.isDuplicate('10.0.0.1', 8091), isFalse);
    expect(notifier.isDuplicate('10.0.0.1', 8090, exceptId: 's1'), isFalse);
  });

  test('apiProvider builds a client for the server and is stable across touch()', () async {
    final c = container();
    final sub = c.listen(apiProvider('s1'), (_, _) {});
    final first = sub.read();
    expect(first.baseUrl, 'http://10.0.0.1:8090');
    await c.read(serversProvider.notifier).touch('s1');
    expect(c.read(apiProvider('s1')), same(first));
    await c.read(serversProvider.notifier).setToken('s1', 'new');
    expect(c.read(apiProvider('s1')).token, 'new');
    sub.close();
  });
}
