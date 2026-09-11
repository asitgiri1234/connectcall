import 'package:firebase_database/firebase_database.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/app_exception.dart';
import '../models/user_model.dart';

/// Blocking other users (bonus feature 4).
///
/// Stored at `blocks/{uid}/{blockedUid}: true`. The database rules make each
/// list private to its owner: nobody can read who you blocked, and nobody can
/// add themselves to, or remove themselves from, your list.
///
/// Blocking is enforced on the *blocker's* device, deliberately silently:
///  - a blocked person disappears from contacts, Home and call history;
///  - their incoming calls never ring. The caller just hears it ring out and
///    sees "No answer", so the block is not revealed to them.
class BlockService {
  BlockService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  /// Live set of uids that [uid] has blocked.
  Stream<Set<String>> watchBlocked(String uid) {
    return _db.ref(DbPaths.blocksOf(uid)).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map<Object?, Object?>) return <String>{};
      return {
        for (final entry in value.entries)
          if (entry.key is String && entry.value == true) entry.key as String,
      };
    });
  }

  Future<void> block(String uid, String blockedUid) async {
    if (uid == blockedUid) return;
    try {
      await _db.ref(DbPaths.block(uid, blockedUid)).set(true);
    } catch (_) {
      throw const AppException('Could not block this person. Try again.');
    }
  }

  Future<void> unblock(String uid, String blockedUid) async {
    try {
      await _db.ref(DbPaths.block(uid, blockedUid)).remove();
    } catch (_) {
      throw const AppException('Could not unblock this person. Try again.');
    }
  }
}

/// [users] without anyone in [blocked]. A pure function, so the filtering
/// every screen relies on is unit-testable without Firebase.
List<UserModel> withoutBlocked(List<UserModel> users, Set<String> blocked) {
  if (blocked.isEmpty) return users;
  return users.where((user) => !blocked.contains(user.uid)).toList();
}
