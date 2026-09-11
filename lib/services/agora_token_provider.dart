import '../core/config/env.dart';

/// Supplies the token Agora requires to join a channel.
///
/// Call code only ever talks to this interface, so switching the Agora
/// project between testing mode and secured mode is a change to which
/// implementation is provided, not to anything in the call flow.
///
///  - Testing mode (App ID only): tokens are not checked, so an empty string
///    is valid. See [StaticAgoraTokenProvider].
///  - Secured mode (App ID + certificate): each join needs a token signed for
///    that exact channel and uid. Channel names are per call, so tokens must
///    be minted on demand by a server that holds the certificate.
///
/// Tokens must never be generated inside the app itself. That would mean
/// shipping the certificate in the APK, where anyone can extract it and mint
/// tokens for any channel, which is weaker than having no auth at all because
/// it only looks secure.
abstract interface class AgoraTokenProvider {
  /// Returns a token authorising [rtcUid] to join [channelName].
  Future<String> tokenFor({required String channelName, required int rtcUid});
}

/// Returns the build-time token from [Env.agoraToken], which is empty while
/// the Agora project runs in testing mode.
class StaticAgoraTokenProvider implements AgoraTokenProvider {
  const StaticAgoraTokenProvider();

  @override
  Future<String> tokenFor({
    required String channelName,
    required int rtcUid,
  }) async =>
      Env.agoraToken;
}
