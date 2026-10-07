import 'dart:math';

final _validToken = RegExp(r'^[A-Za-z0-9]{24,128}$');
const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// Husk accepts new tokens that are alphanumeric and 24–128 characters long.
bool isValidNewToken(String token) => _validToken.hasMatch(token);

String generateToken({int length = 32, Random? random}) {
  final rng = random ?? Random.secure();
  return String.fromCharCodes([for (var i = 0; i < length; i++) _alphabet.codeUnitAt(rng.nextInt(_alphabet.length))]);
}
