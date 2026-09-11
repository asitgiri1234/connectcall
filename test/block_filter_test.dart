import 'package:connectcall/models/user_model.dart';
import 'package:connectcall/services/block_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alice = UserModel(uid: 'a', name: 'Alice', email: 'a@x.com');
  const bob = UserModel(uid: 'b', name: 'Bob', email: 'b@x.com');
  const cara = UserModel(uid: 'c', name: 'Cara', email: 'c@x.com');

  group('withoutBlocked', () {
    test('removes exactly the blocked users', () {
      final visible = withoutBlocked([alice, bob, cara], {'b'});
      expect(visible.map((u) => u.uid), ['a', 'c']);
    });

    test('keeps the original order', () {
      final visible = withoutBlocked([cara, alice, bob], {'a'});
      expect(visible.map((u) => u.uid), ['c', 'b']);
    });

    test('an empty block list changes nothing', () {
      final users = [alice, bob];
      expect(withoutBlocked(users, const {}), same(users));
    });

    test('blocking someone not in the list is harmless', () {
      expect(withoutBlocked([alice], {'zz'}).map((u) => u.uid), ['a']);
    });
  });
}
