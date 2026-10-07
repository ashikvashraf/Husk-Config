import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:huskconfig/core/api/token_rules.dart';

void main() {
  test('isValidNewToken enforces alphanumeric 24–128', () {
    expect(isValidNewToken('a' * 24), isTrue);
    expect(isValidNewToken('A1' * 64), isTrue);
    expect(isValidNewToken('a' * 23), isFalse);
    expect(isValidNewToken('a' * 129), isFalse);
    expect(isValidNewToken('${'a' * 30}-'), isFalse);
    expect(isValidNewToken(''), isFalse);
  });

  test('generateToken produces valid, different tokens', () {
    final t1 = generateToken();
    final t2 = generateToken();
    expect(t1.length, 32);
    expect(isValidNewToken(t1), isTrue);
    expect(t1, isNot(t2));
    expect(generateToken(length: 40, random: Random(1)).length, 40);
  });
}
