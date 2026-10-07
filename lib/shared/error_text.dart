import '../core/api/husk_exception.dart';

/// User-facing text for any error caught in the UI.
String describeError(Object error) => error is HuskException ? error.message : 'Unexpected error: $error';
