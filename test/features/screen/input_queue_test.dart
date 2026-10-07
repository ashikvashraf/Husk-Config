import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/features/screen/input_queue.dart';

void main() {
  test('runs actions one at a time, in order', () async {
    final log = <String>[];
    final queue = InputQueue(onError: (_) {});
    queue.add(() async {
      log.add('a-start');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      log.add('a-end');
      return null;
    });
    queue.add(() async {
      log.add('b');
      return null;
    });
    await queue.idle;
    expect(log, ['a-start', 'a-end', 'b']);
  });

  test('reports thrown errors and ERR replies, and keeps going', () async {
    final errors = <String>[];
    var ran = false;
    final queue = InputQueue(onError: (e) => errors.add('$e'));
    queue.add(() async => throw const OfflineException('down'));
    queue.add(() async => const TextResult('ERR cancelled'));
    queue.add(() async {
      ran = true;
      return const TextResult('OK');
    });
    await queue.idle;
    expect(errors, ['down', 'ERR cancelled']);
    expect(ran, isTrue);
  });
}
