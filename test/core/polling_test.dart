import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/polling.dart';

void main() {
  ProviderContainer container() {
    final c = ProviderContainer(retry: (_, _) => null);
    addTearDown(c.dispose);
    return c;
  }

  test('Duration.zero fetches exactly once', () async {
    var calls = 0;
    final p = StreamProvider.autoDispose<int>((ref) => pollEvery(ref, Duration.zero, () async => ++calls));
    final c = container();
    final sub = c.listen(p, (_, _) {});
    expect(await c.read(p.future), 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);
    sub.close();
  });

  test('null interval never fetches', () async {
    var calls = 0;
    final p = StreamProvider.autoDispose<int>((ref) => pollEvery(ref, null, () async => ++calls));
    final c = container();
    final sub = c.listen(p, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 0);
    sub.close();
  });

  test('repeats at the interval, keeps going after errors, stops when disposed', () async {
    var calls = 0;
    final p = StreamProvider.autoDispose<int>((ref) => pollEvery(ref, const Duration(milliseconds: 5), () async {
          calls++;
          if (calls == 1) throw StateError('first fails');
          return calls;
        }));
    final c = ProviderContainer(retry: (_, _) => null);
    final seen = <AsyncValue<int>>[];
    c.listen(p, (_, next) => seen.add(next));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, greaterThanOrEqualTo(3));
    expect(seen.any((v) => v.hasError), isTrue);
    expect(seen.last.value, greaterThanOrEqualTo(2));
    c.dispose();
    final atDispose = calls;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls, lessThanOrEqualTo(atDispose + 1));
  });
}
