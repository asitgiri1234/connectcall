import 'package:firebase_database/firebase_database.dart';

import '../core/constants/app_constants.dart';
import '../models/user_model.dart';

/// Reads the user directory that backs the contacts list and search.
///
/// Plain Dart, no Flutter imports, so it can be tested against a fake
/// [FirebaseDatabase] without pumping widgets.
class UserService {
  UserService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  /// Live list of everyone except [excludeUid] (the signed-in user, who
  /// should not appear in their own contacts).
  ///
  /// The whole `users` node is streamed rather than paged. At assignment
  /// scale that is a handful of records, and it means presence changes arrive
  /// without a refresh. A production version would page and index instead;
  /// this is called out in the README's known limitations.
  Stream<List<UserModel>> watchUsers({String? excludeUid}) {
    return _db.ref(DbPaths.users).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map<Object?, Object?>) return <UserModel>[];

      final users = <UserModel>[];
      value.forEach((key, entry) {
        if (key is! String || entry is! Map<Object?, Object?>) return;
        if (key == excludeUid) return;
        users.add(UserModel.fromMap(key, entry));
      });

      // Online users first, then alphabetical. Sorting here rather than in
      // the widget keeps the list stable across rebuilds.
      users.sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return users;
    });
  }

  /// Live view of a single user, used by the call screens so the callee's
  /// name and avatar stay correct if they edit their profile mid-call.
  Stream<UserModel?> watchUser(String uid) {
    return _db.ref(DbPaths.user(uid)).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is Map<Object?, Object?>) return UserModel.fromMap(uid, value);
      return null;
    });
  }

  /// One-shot read, for places that need a snapshot rather than a stream
  /// (writing a call history record, for instance).
  Future<UserModel?> getUser(String uid) async {
    final snapshot = await _db.ref(DbPaths.user(uid)).get();
    final value = snapshot.value;
    if (value is Map<Object?, Object?>) return UserModel.fromMap(uid, value);
    return null;
  }
}
