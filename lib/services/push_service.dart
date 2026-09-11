import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';

/// Push notifications for calls (bonus features 1 and 2).
///
/// Two halves:
///  - [PushService] registers *this* device to receive calls: it stores the
///    device's FCM token at `fcm_tokens/{uid}`, private to the user under the
///    database rules, and keeps it current as Firebase rotates it.
///  - [CallNotifier] is the *caller's* side: it asks the server's
///    `/api/notify` to wake the callee's phone, or to stop ringing it.
///
/// Push is strictly best-effort. The in-app listener still rings the callee
/// whenever their app is open, so a push failure never blocks a call and is
/// never shown as an error.
class PushService {
  PushService({FirebaseMessaging? messaging, FirebaseDatabase? database})
      : _messaging = messaging ?? FirebaseMessaging.instance,
        _db = database ?? FirebaseDatabase.instance;

  final FirebaseMessaging _messaging;
  final FirebaseDatabase _db;
  StreamSubscription<String>? _refreshSub;

  static String _path(String uid) => 'fcm_tokens/$uid';

  /// Registers this device for incoming-call pushes for [uid].
  Future<void> register(String uid) async {
    try {
      // Android 13+ requires runtime consent to post notifications; on older
      // versions this resolves immediately.
      await _messaging.requestPermission();

      final token = await _messaging.getToken();
      if (token != null) await _db.ref(_path(uid)).set(token);

      await _refreshSub?.cancel();
      _refreshSub = _messaging.onTokenRefresh.listen((fresh) {
        _db.ref(_path(uid)).set(fresh).catchError((_) {});
      });
    } catch (_) {
      // Best-effort: without a token, calls still ring while the app is open.
    }
  }

  /// Removes this device so a signed-out phone stops receiving calls. Must
  /// run *before* sign-out: the rules only let the owner delete their token.
  Future<void> unregister(String uid) async {
    await _refreshSub?.cancel();
    _refreshSub = null;
    try {
      await _db.ref(_path(uid)).remove();
      await _messaging.deleteToken();
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> dispose() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
  }
}

/// The caller's side of push: tells the server to ring or stop ringing the
/// callee's phone. The server only accepts this from the call's caller.
class CallNotifier {
  CallNotifier({FirebaseAuth? auth, http.Client? client, String? baseUrl})
      : _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client(),
        _baseUrl =
            (baseUrl ?? Env.tokenServerUrl).replaceAll(RegExp(r'/+$'), '');

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _baseUrl;

  static const _timeout = Duration(seconds: 8);

  /// Wakes the callee's phone with a full-screen incoming-call screen.
  Future<void> ring(String callId) => _send(callId, 'ring');

  /// Dismisses that screen, when the caller hangs up or the ring times out
  /// before the callee answered.
  Future<void> cancel(String callId) => _send(callId, 'cancel');

  Future<void> _send(String callId, String event) async {
    final user = _auth.currentUser;
    if (_baseUrl.isEmpty || user == null) return;
    try {
      final idToken = await user.getIdToken();
      await _client
          .post(
            Uri.parse('$_baseUrl/api/notify'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'callId': callId, 'event': event}),
          )
          .timeout(_timeout);
    } catch (_) {
      // Best-effort, as above.
    }
  }
}
