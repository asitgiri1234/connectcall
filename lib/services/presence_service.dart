import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../core/constants/app_constants.dart';

/// Keeps `users/{uid}/isOnline` honest.
///
/// The naive approach — write `false` when the app backgrounds — silently
/// fails whenever the app is killed, crashes, or loses signal, leaving a user
/// marked online forever. That is the specific bug this class exists to avoid,
/// and the reason the project uses Realtime Database rather than Firestore.
///
/// How it works:
///
///  1. Listen to `.info/connected`, a synthetic node the SDK maintains that
///     reflects whether this client actually has a live socket to Firebase.
///  2. On every (re)connect, register an `onDisconnect()` write *first*. That
///     instruction is stored server-side and executed by Firebase itself when
///     the socket drops, for any reason, including a crash or a dead battery.
///  3. Only then mark the user online.
///
/// The order matters. Registering the disconnect handler after going online
/// leaves a window where a drop would strand the record as online.
class PresenceService {
  PresenceService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  StreamSubscription<DatabaseEvent>? _connectionSub;
  String? _uid;

  bool get isTracking => _connectionSub != null;

  /// Starts tracking presence for [uid]. Safe to call repeatedly; a second
  /// call for the same user is a no-op, and for a different user it
  /// transparently switches over.
  Future<void> start(String uid) async {
    if (_uid == uid && _connectionSub != null) return;
    await stop();
    _uid = uid;

    final userRef = _db.ref(DbPaths.user(uid));
    final connectedRef = _db.ref('.info/connected');

    _connectionSub = connectedRef.onValue.listen((event) async {
      if (event.snapshot.value != true) return;

      try {
        // Registered before going online, so a drop at any moment after this
        // point still results in the user being marked offline.
        await userRef.onDisconnect().update({
          'isOnline': false,
          'lastSeen': ServerValue.timestamp,
        });

        await userRef.update({
          'isOnline': true,
          'lastSeen': ServerValue.timestamp,
        });
      } catch (_) {
        // Presence is best-effort. A failure here must never surface as an
        // error to the user or interrupt an in-progress call.
      }
    });
  }

  /// Marks the user offline and stops tracking. Used on explicit logout,
  /// where we want the record updated immediately rather than waiting for
  /// the socket to close.
  Future<void> stop({bool markOffline = false}) async {
    final uid = _uid;
    await _connectionSub?.cancel();
    _connectionSub = null;
    _uid = null;

    if (markOffline && uid != null) {
      final userRef = _db.ref(DbPaths.user(uid));
      try {
        // Cancel the pending server-side write first, otherwise it would fire
        // later and overwrite whatever the next session has written.
        await userRef.onDisconnect().cancel();
        await userRef.update({
          'isOnline': false,
          'lastSeen': ServerValue.timestamp,
        });
      } catch (_) {
        // Best-effort, as above.
      }
    }
  }

  /// Called when the app is backgrounded or resumed.
  ///
  /// Backgrounding is not the same as disconnecting: the socket usually stays
  /// alive briefly, and a user who switches apps to check something should not
  /// flicker offline. So this only writes `lastSeen`, and leaves `isOnline` to
  /// the connection state.
  Future<void> touch() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.ref(DbPaths.user(uid)).update({
        'lastSeen': ServerValue.timestamp,
      });
    } catch (_) {
      // Best-effort.
    }
  }
}
