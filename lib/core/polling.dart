import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repeatedly calls [fetch] for a StreamProvider.
///
/// [interval] null → do nothing (app in background); Duration.zero → fetch
/// once (polling off). Errors are emitted and polling continues. Stops when
/// the provider is disposed or rebuilt.
Stream<T> pollEvery<T>(Ref ref, Duration? interval, Future<T> Function() fetch) async* {
  if (interval == null) return;
  while (ref.mounted) {
    try {
      final value = await fetch();
      if (!ref.mounted) return;
      yield value;
    } catch (error, stackTrace) {
      if (!ref.mounted) return;
      yield* Stream<T>.error(error, stackTrace);
    }
    if (interval == Duration.zero) return;
    await Future<void>.delayed(interval);
  }
}
