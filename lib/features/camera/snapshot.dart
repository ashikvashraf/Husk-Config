import 'dart:typed_data';

import '../../core/api/husk_exception.dart';

/// The lazy camera answers 503 until it has a frame; the first call wakes it,
/// so one retry after [wait] is enough.
Future<Uint8List> fetchWithWarmup(Future<Uint8List> Function() fetch, {Duration wait = const Duration(seconds: 1)}) async {
  try {
    return await fetch();
  } on HttpStatusException catch (e) {
    if (e.statusCode != 503) rethrow;
    await Future<void>.delayed(wait);
    return fetch();
  }
}
