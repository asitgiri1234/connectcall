import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/app_exception.dart';
import '../models/user_model.dart';

/// Authentication and the user record that shadows it.
///
/// Plain Dart with no Flutter imports, so it can be unit-tested and swapped
/// behind a provider. Every platform exception is translated to
/// [AppException] at this boundary; nothing above this layer sees a
/// `FirebaseAuthException`.
///
/// Firebase Auth owns credentials; it does not store a display name we can
/// query by. So every account gets a mirrored record under `users/{uid}`,
/// which is what the contacts list and presence system actually read.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseDatabase? database})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = database ?? FirebaseDatabase.instance;

  final FirebaseAuth _auth;
  final FirebaseDatabase _db;

  /// Emits on login, logout and token refresh. The router listens to this to
  /// decide between the auth flow and the app shell.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;
  bool get isSignedIn => _auth.currentUser != null;

  /// Creates the account, sets the display name, and writes the user record.
  ///
  /// If the database write fails after the credential is created, the account
  /// would exist with no profile — invisible in contacts and impossible to
  /// call. Rather than leave that orphan, the credential is deleted so the
  /// user can simply try again with the same email.
  Future<UserModel> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final trimmedName = name.trim();
    final trimmedEmail = email.trim();

    UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthErrorMapper.map(e.code, e.message);
    }

    final user = credential.user;
    if (user == null) throw const AppException.unknown();

    final profile = UserModel(
      uid: user.uid,
      name: trimmedName,
      email: trimmedEmail,
      isOnline: true,
      lastSeen: DateTime.now(),
      createdAt: DateTime.now(),
    );

    try {
      await user.updateDisplayName(trimmedName);
      await _db.ref(DbPaths.user(user.uid)).set(profile.toMap());
    } catch (_) {
      await user.delete().catchError((_) {});
      throw const AppException(
        'Could not finish creating your account. Please try again.',
        code: 'profile-write-failed',
      );
    }

    return profile;
  }

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw const AppException.unknown();
      return await _ensureProfile(user);
    } on FirebaseAuthException catch (e) {
      throw AuthErrorMapper.map(e.code, e.message);
    }
  }

  Future<void> logout() async {
    // Presence is marked offline before the credential is dropped, because
    // the database rules require an authenticated user to write the record.
    final id = uid;
    if (id != null) {
      await _db.ref(DbPaths.user(id)).update({
        'isOnline': false,
        'lastSeen': ServerValue.timestamp,
      }).catchError((_) {});
    }
    await _auth.signOut();
  }

  /// Reads the user record, recreating it from the credential if missing.
  ///
  /// Covers accounts created before the record existed, and the rare case
  /// where registration was interrupted between the two writes.
  Future<UserModel> _ensureProfile(User user) async {
    final ref = _db.ref(DbPaths.user(user.uid));
    final snapshot = await ref.get();

    final value = snapshot.value;
    if (snapshot.exists && value is Map<Object?, Object?>) {
      return UserModel.fromMap(user.uid, value);
    }

    final rebuilt = UserModel(
      uid: user.uid,
      name: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (user.email?.split('@').first ?? 'User'),
      email: user.email ?? '',
      isOnline: true,
      lastSeen: DateTime.now(),
      createdAt: DateTime.now(),
    );
    await ref.set(rebuilt.toMap());
    return rebuilt;
  }

  /// Live view of the signed-in user's own record, so profile edits and
  /// presence changes reflect immediately wherever they are shown.
  Stream<UserModel?> watchCurrentUser() {
    final id = uid;
    if (id == null) return Stream.value(null);
    return _db.ref(DbPaths.user(id)).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is Map<Object?, Object?>) return UserModel.fromMap(id, value);
      return null;
    });
  }

  Future<void> updateProfile({String? name, String? photoUrl}) async {
    final id = uid;
    if (id == null) throw const AppException('You are not signed in.');

    final updates = <String, Object?>{};
    if (name != null && name.trim().isNotEmpty) updates['name'] = name.trim();
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    if (updates.isEmpty) return;

    try {
      await _db.ref(DbPaths.user(id)).update(updates);
      if (updates.containsKey('name')) {
        await _auth.currentUser?.updateDisplayName(updates['name'] as String);
      }
    } catch (_) {
      throw const AppException('Could not save your changes. Please try again.');
    }
  }
}
