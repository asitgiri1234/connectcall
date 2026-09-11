import 'package:connectcall/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators.email', () {
    test('accepts well-formed addresses', () {
      expect(Validators.email('sarah@example.com'), isNull);
      expect(Validators.email('  first.last+tag@mail.co.uk '), isNull);
    });

    test('rejects missing or malformed addresses', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email(null), isNotNull);
      expect(Validators.email('sarah'), isNotNull);
      expect(Validators.email('sarah@'), isNotNull);
      expect(Validators.email('sarah@example'), isNotNull);
    });
  });

  group('Validators.password', () {
    test('enforces the same 6-character minimum as Firebase', () {
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password('123456'), isNull);
    });

    test('login only checks presence, not length', () {
      // An existing account must not be told its password is "too short".
      expect(Validators.loginPassword('abc'), isNull);
      expect(Validators.loginPassword(''), isNotNull);
    });
  });

  group('Validators.confirmPassword', () {
    test('must match the original', () {
      expect(Validators.confirmPassword('secret1', 'secret1'), isNull);
      expect(Validators.confirmPassword('secret2', 'secret1'), isNotNull);
      expect(Validators.confirmPassword('', 'secret1'), isNotNull);
    });
  });

  group('Validators.name', () {
    test('requires 2 to 50 characters after trimming', () {
      expect(Validators.name('A'), isNotNull);
      expect(Validators.name('  '), isNotNull);
      expect(Validators.name('Al'), isNull);
      expect(Validators.name('x' * 51), isNotNull);
    });
  });
}
