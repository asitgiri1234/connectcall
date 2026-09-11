import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../core/utils/app_exception.dart';

/// What the app needs to join one call's Agora channel.
///
/// All three values come from the token server rather than being computed on
/// the device, so the app cannot ask for a channel or uid it has no right to.
class AgoraCredentials {
  const AgoraCredentials({
    required this.token,
    required this.rtcUid,
    required this.channelName,
    required this.expiresIn,
  });

  final String token;

  /// Agora's numeric uid for this user, derived server-side from the
  /// Firebase uid so it is stable across calls.
  final int rtcUid;
  final String channelName;
  final Duration expiresIn;
}

/// Supplies the credentials Agora requires to join a call's channel.
///
/// Call code only depends on this interface. That keeps the token server
/// swappable (Vercel today, Cloud Functions tomorrow) and lets tests provide
/// a fake without any network.
abstract interface class AgoraTokenProvider {
  Future<AgoraCredentials> credentialsFor(String callId);
}

/// Fetches credentials from the ConnectCall token server.
///
/// The Agora project runs in secured mode, so every join needs a token signed
/// with the App Certificate. That certificate lives only on the server: a
/// certificate shipped inside the APK could be extracted and used to mint
/// tokens for any channel, which is weaker than no auth at all because it
/// only looks secure.
///
/// The request is authenticated with the user's Firebase ID token. The server
/// verifies it, then confirms the user is one of the call's two participants
/// before signing anything.
class ServerAgoraTokenProvider implements AgoraTokenProvider {
  ServerAgoraTokenProvider({
    FirebaseAuth? auth,
    http.Client? client,
    String? baseUrl,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? Env.tokenServerUrl).replaceAll(RegExp(r'/+$'), '');

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _baseUrl;

  static const _timeout = Duration(seconds: 10);

  @override
  Future<AgoraCredentials> credentialsFor(String callId) async {
    if (_baseUrl.isEmpty) {
      throw const AppException(
        Env.missingTokenServerMessage,
        code: 'token-server-unconfigured',
        isRecoverable: false,
      );
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw const AppException(
        'You are signed out. Log in again to make calls.',
        code: 'unauthenticated',
        isRecoverable: false,
      );
    }

    var response = await _request(user, callId, forceRefresh: false);

    // ID tokens expire after an hour. A cached one can be stale even though
    // the Firebase session is fine, so retry once with a forced refresh
    // before telling the user anything is wrong.
    if (response.statusCode == 401) {
      response = await _request(user, callId, forceRefresh: true);
    }

    return _parse(response);
  }

  Future<http.Response> _request(
    User user,
    String callId, {
    required bool forceRefresh,
  }) async {
    try {
      final idToken = await user.getIdToken(forceRefresh);
      return await _client
          .post(
            Uri.parse('$_baseUrl/api/token'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'callId': callId}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AppException.network();
    } on http.ClientException {
      throw const AppException.network();
    } on FirebaseAuthException catch (e) {
      throw AuthErrorMapper.map(e.code, e.message);
    }
  }

  AgoraCredentials _parse(http.Response response) {
    if (response.statusCode == 200) {
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return AgoraCredentials(
          token: body['token'] as String,
          rtcUid: (body['rtcUid'] as num).toInt(),
          channelName: body['channelName'] as String,
          expiresIn: Duration(seconds: (body['expiresIn'] as num).toInt()),
        );
      } catch (_) {
        throw const AppException(
          'The calling service sent an unexpected response.',
          code: 'token-bad-response',
        );
      }
    }

    throw switch (response.statusCode) {
      401 => const AppException(
          'Your session has expired. Please log in again.',
          code: 'token-unauthenticated',
          isRecoverable: false,
        ),
      403 => const AppException(
          'You are not part of this call.',
          code: 'token-forbidden',
          isRecoverable: false,
        ),
      409 => const AppException(
          'This call has already ended.',
          code: 'token-call-ended',
          isRecoverable: false,
        ),
      400 || 422 => const AppException(
          'Could not start this call.',
          code: 'token-bad-request',
        ),
      _ => const AppException(
          'The calling service is unavailable right now. Try again shortly.',
          code: 'token-server-error',
        ),
    };
  }
}
