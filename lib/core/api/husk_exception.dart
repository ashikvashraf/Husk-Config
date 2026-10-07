import 'dart:convert';

/// Every failure surfaced by HuskApi. [message] is safe to show to the user.
sealed class HuskException implements Exception {
  const HuskException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Connection refused, timed out, or otherwise unreachable.
final class OfflineException extends HuskException {
  const OfflineException(super.message);
}

final class UnauthorizedException extends HuskException {
  const UnauthorizedException() : super('Token missing or invalid. Edit the server or request a token.');
}

/// Any other non-2xx response.
final class HttpStatusException extends HuskException {
  HttpStatusException(this.statusCode, this.body) : super(_messageFor(statusCode, body));

  final int statusCode;
  final String body;

  static String _messageFor(int statusCode, String body) {
    final text = body.trim();
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map && decoded['error'] is String) return decoded['error'] as String;
      } on FormatException {
        // Not JSON after all; fall through to the raw text.
      }
    }
    return text.isEmpty ? 'HTTP $statusCode' : text;
  }
}

/// A JSON endpoint answered plain text, e.g. `ERR no-fix (…)` from /location.
final class DeviceErrorException extends HuskException {
  const DeviceErrorException(super.message);
}
