import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/husk_exception.dart';
import 'package:huskconfig/core/api/text_result.dart';
import 'package:huskconfig/features/camera/camera_side_switch.dart';

/// A scripted phone: /set is counted; /flags.front answers from [frontReads] in order,
/// repeating the last value once the script runs out.
class _FakePhone {
  _FakePhone(this.frontReads, {this.setReply = 'OK'});

  final List<Object> frontReads; // bool or an exception to throw
  final String setReply;
  final sent = <bool>[];
  var reads = 0;
  final waits = <Duration>[];

  Future<TextResult> send(bool front) async {
    sent.add(front);
    return TextResult(setReply);
  }

  Future<bool> readFront() async {
    final value = frontReads[reads < frontReads.length ? reads : frontReads.length - 1];
    reads++;
    if (value is Exception) throw value;
    return value as bool;
  }

  Future<void> delay(Duration d) async => waits.add(d);

  Future<bool> run(bool front) =>
      switchCameraSide(front: front, send: send, readFront: readFront, delay: delay);
}

void main() {
  const poll = Duration(milliseconds: 500);
  const retryWait = Duration(seconds: 2);

  test('confirmed on the first /flags poll: one /set, one poll, no retry', () async {
    final phone = _FakePhone([true]);
    expect(await phone.run(true), isTrue);
    expect(phone.sent, [true]);
    expect(phone.reads, 1);
    expect(phone.waits, [poll]);
  });

  test('keeps polling every 500 ms until /flags agrees within 5 s', () async {
    final phone = _FakePhone([false, false, false, true]);
    expect(await phone.run(true), isTrue);
    expect(phone.sent, [true]);
    expect(phone.reads, 4);
    expect(phone.waits, List.filled(4, poll));
  });

  test('not confirmed in 5 s: waits 2 s, sends /set once more and confirms again', () async {
    // 10 polls (5 s at 500 ms) say Back, then the retry's second poll says Front.
    final phone = _FakePhone([...List.filled(11, false), true]);
    expect(await phone.run(true), isTrue);
    expect(phone.sent, [true, true]);
    expect(phone.reads, 12);
    expect(phone.waits, [...List.filled(10, poll), retryWait, poll, poll]);
  });

  test('never confirmed: exactly two /set calls, 5 s of polling after each, then false', () async {
    final phone = _FakePhone([false]);
    expect(await phone.run(true), isFalse);
    expect(phone.sent, [true, true]);
    expect(phone.reads, 20);
    expect(phone.waits, [...List.filled(10, poll), retryWait, ...List.filled(10, poll)]);
  });

  test('a /flags read that fails while the camera restarts counts as not yet confirmed', () async {
    final phone = _FakePhone([const OfflineException('timeout'), false, true]);
    expect(await phone.run(true), isTrue);
    expect(phone.sent, [true]);
    expect(phone.reads, 3);
  });

  test('an ERR reply is thrown as a device error without polling or retrying', () async {
    final phone = _FakePhone([false], setReply: 'ERR camera busy');
    await expectLater(phone.run(true), throwsA(isA<DeviceErrorException>().having((e) => e.message, 'message', 'ERR camera busy')));
    expect(phone.sent, [true]);
    expect(phone.reads, 0);
  });

  test('a /set HTTP error (e.g. 409) propagates without polling or retrying', () async {
    var sends = 0;
    var reads = 0;
    await expectLater(
      switchCameraSide(
        front: true,
        send: (_) async {
          sends++;
          throw HttpStatusException(409, 'no such camera');
        },
        readFront: () async {
          reads++;
          return false;
        },
        delay: (_) async {},
      ),
      throwsA(isA<HttpStatusException>().having((e) => e.statusCode, 'statusCode', 409)),
    );
    expect(sends, 1);
    expect(reads, 0);
  });

  test('timings are injectable', () async {
    final phone = _FakePhone([false]);
    final ok = await switchCameraSide(
      front: false,
      send: phone.send,
      readFront: () async => true,
      delay: phone.delay,
      timing: const CameraSideSwitchTiming(
        pollInterval: Duration(milliseconds: 100),
        confirmFor: Duration(milliseconds: 300),
        retryAfter: Duration(milliseconds: 700),
      ),
    );
    expect(ok, isFalse);
    expect(phone.sent, [false, false]);
    expect(phone.waits, [...List.filled(3, const Duration(milliseconds: 100)), const Duration(milliseconds: 700), ...List.filled(3, const Duration(milliseconds: 100))]);
  });

  test('stops early when cancelled (tab closed)', () async {
    final phone = _FakePhone([false]);
    final ok = await switchCameraSide(
      front: true,
      send: phone.send,
      readFront: phone.readFront,
      delay: phone.delay,
      isCancelled: () => phone.reads >= 2,
    );
    expect(ok, isFalse);
    expect(phone.sent, [true]);
    expect(phone.reads, 2);
  });
}
