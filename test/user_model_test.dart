import 'package:connectcall/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserModel.fromMap', () {
    test('parses a complete record', () {
      final user = UserModel.fromMap('u1', {
        'name': 'Sarah Johnson',
        'email': 'sarah@example.com',
        'isOnline': true,
        'lastSeen': 1000,
      });
      expect(user.uid, 'u1');
      expect(user.name, 'Sarah Johnson');
      expect(user.isOnline, isTrue);
      expect(user.lastSeen, DateTime.fromMillisecondsSinceEpoch(1000));
    });

    test('a malformed record degrades instead of throwing', () {
      // One bad record in the directory must not break the contacts list.
      final user = UserModel.fromMap('u2', {
        'name': 42,
        'isOnline': 'yes',
        'lastSeen': 'yesterday',
      });
      expect(user.name, 'Unknown');
      expect(user.email, '');
      expect(user.isOnline, isFalse);
      expect(user.lastSeen, isNull);
    });

    test('uid always comes from the key, not the payload', () {
      final user = UserModel.fromMap('from-key', {'uid': 'spoofed', 'name': 'X Y'});
      expect(user.uid, 'from-key');
    });
  });

  group('UserModel.matches', () {
    const user = UserModel(
      uid: 'u1',
      name: 'Sarah Johnson',
      email: 'sj@example.com',
    );

    test('matches name or email, ignoring case', () {
      expect(user.matches('sarah'), isTrue);
      expect(user.matches('JOHN'), isTrue);
      expect(user.matches('sj@'), isTrue);
      expect(user.matches('alex'), isFalse);
    });

    test('an empty query matches everyone', () {
      expect(user.matches(''), isTrue);
      expect(user.matches('   '), isTrue);
    });
  });
}
