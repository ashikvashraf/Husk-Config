import '../../core/api/husk_exception.dart';
import '../../core/api/text_result.dart';

typedef SideSwitchDelay = Future<void> Function(Duration duration);

/// Timings of the confirm-and-retry side switch (spec 5.8). Injectable so tests run instantly.
class CameraSideSwitchTiming {
  const CameraSideSwitchTiming({
    this.pollInterval = const Duration(milliseconds: 500),
    this.confirmFor = const Duration(seconds: 5),
    this.retryAfter = const Duration(seconds: 2),
  });

  /// Gap between /flags reads while confirming.
  final Duration pollInterval;

  /// How long to keep reading /flags after each /set.
  final Duration confirmFor;

  /// Wait before the single retry of /set.
  final Duration retryAfter;
}

/// Sends `/set?front=` and confirms it via `/flags.front`, retrying the /set once.
///
/// Husk 1.4 answers OK to `/set?front=1` sent while it is still restarting the camera
/// but does not apply it (spec 3.1), so an OK alone is not trusted. Returns true once
/// [readFront] reports [front]; false if it never does after two /set calls (or the
/// switch is [isCancelled]). An `ERR` reply is thrown as [DeviceErrorException]; /set
/// transport and HTTP errors (e.g. 409) propagate. Neither is retried.
Future<bool> switchCameraSide({
  required bool front,
  required Future<TextResult> Function(bool front) send,
  required Future<bool> Function() readFront,
  CameraSideSwitchTiming timing = const CameraSideSwitchTiming(),
  SideSwitchDelay? delay,
  bool Function()? isCancelled,
}) async {
  final wait = delay ?? Future<void>.delayed;
  bool cancelled() => isCancelled?.call() ?? false;

  // Number of /flags reads per /set: confirmFor / pollInterval (at least one).
  final polls = timing.pollInterval > Duration.zero
      ? (timing.confirmFor.inMicroseconds / timing.pollInterval.inMicroseconds).ceil().clamp(1, 1 << 20)
      : 1;

  Future<bool> confirm() async {
    for (var poll = 0; poll < polls; poll++) {
      await wait(timing.pollInterval);
      if (cancelled()) return false;
      try {
        if (await readFront() == front) return true;
      } on HuskException {
        // The phone can drop a request while it restarts the camera; read again.
      }
      if (cancelled()) return false;
    }
    return false;
  }

  for (var attempt = 0; attempt < 2; attempt++) {
    if (attempt > 0) {
      await wait(timing.retryAfter);
      if (cancelled()) return false;
    }
    final result = await send(front);
    if (result.isErr) throw DeviceErrorException(result.text);
    if (await confirm()) return true;
    if (cancelled()) return false;
  }
  return false;
}
