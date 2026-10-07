import 'husk_api.dart';
import 'husk_exception.dart';
import 'models/tools_models.dart';

sealed class TokenFlowState {
  const TokenFlowState();

  bool get isTerminal => true;
}

final class TokenFlowRequesting extends TokenFlowState {
  const TokenFlowRequesting();

  @override
  bool get isTerminal => false;

  @override
  String toString() => 'requesting';
}

final class TokenFlowPending extends TokenFlowState {
  const TokenFlowPending(this.secondsLeft);

  final int secondsLeft;

  @override
  bool get isTerminal => false;

  @override
  String toString() => 'pending($secondsLeft)';
}

final class TokenFlowApproved extends TokenFlowState {
  const TokenFlowApproved(this.token);

  final String token;

  /// Deliberately omits the token so it never ends up in logs.
  @override
  String toString() => 'approved';
}

final class TokenFlowDenied extends TokenFlowState {
  const TokenFlowDenied();

  @override
  String toString() => 'denied';
}

final class TokenFlowExpired extends TokenFlowState {
  const TokenFlowExpired();

  @override
  String toString() => 'expired';
}

final class TokenFlowFailed extends TokenFlowState {
  const TokenFlowFailed(this.message);

  final String message;

  @override
  String toString() => 'failed: $message';
}

typedef Delay = Future<void> Function(Duration duration);

/// /token/request → poll /token/status until approved, denied or expired.
/// The phone shows an Approve/Deny notification; nothing here can approve.
class TokenRequestFlow {
  TokenRequestFlow({
    required this.api,
    required this.clientName,
    this.pollInterval = const Duration(seconds: 2),
    Delay? delay,
    DateTime Function()? now,
  })  : _delay = delay ?? Future<void>.delayed,
        _now = now ?? DateTime.now;

  final HuskApi api;
  final String clientName;
  final Duration pollInterval;
  final Delay _delay;
  final DateTime Function() _now;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Stream<TokenFlowState> run() async* {
    yield const TokenFlowRequesting();
    final TokenRequest request;
    try {
      request = await api.requestToken(client: clientName);
    } on HttpStatusException catch (e) {
      yield TokenFlowFailed(switch (e.statusCode) {
        429 => 'Another token request is already waiting on the phone. Try again in a couple of minutes.',
        503 => 'Notifications are disabled on the phone, so it cannot ask for approval.',
        _ => e.message,
      });
      return;
    } on HuskException catch (e) {
      yield TokenFlowFailed(e.message);
      return;
    }

    final deadline = _now().add(Duration(seconds: request.expiresIn));
    while (!_cancelled) {
      final secondsLeft = deadline.difference(_now()).inSeconds;
      if (secondsLeft <= 0) {
        yield const TokenFlowExpired();
        return;
      }
      yield TokenFlowPending(secondsLeft);
      await _delay(pollInterval);
      if (_cancelled) return;

      final TokenStatus status;
      try {
        status = await api.tokenStatus(request.id);
      } on OfflineException {
        continue; // Transient network blip; keep polling until the deadline.
      } on HuskException catch (e) {
        yield TokenFlowFailed(e.message);
        return;
      }

      switch (status.state) {
        case TokenState.pending:
          break;
        case TokenState.approved:
          final token = status.token;
          yield token == null || token.isEmpty
              ? const TokenFlowFailed('The phone approved the request but sent no token.')
              : TokenFlowApproved(token);
          return;
        case TokenState.denied:
          yield const TokenFlowDenied();
          return;
        case TokenState.expired:
          yield const TokenFlowExpired();
          return;
      }
    }
  }
}
