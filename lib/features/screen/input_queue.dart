import '../../core/api/husk_exception.dart';
import '../../core/api/text_result.dart';

/// Sends input commands strictly one after another without blocking the UI.
/// Failures (thrown or `ERR …` replies) go to [onError]; the queue keeps going.
class InputQueue {
  InputQueue({required this.onError});

  final void Function(Object error) onError;
  Future<void> _tail = Future.value();

  Future<void> get idle => _tail;

  void add(Future<Object?> Function() action) {
    _tail = _tail.then((_) async {
      try {
        final result = await action();
        if (result is TextResult && result.isErr) onError(DeviceErrorException(result.text));
      } catch (error) {
        onError(error);
      }
    });
  }
}
