/// Build-time configuration.
///
/// Values are injected with `--dart-define` (or `--dart-define-from-file`)
/// so they never enter source control. See the README "Environment variables"
/// section and `dart_defines.example.json`.
///
///   flutter run --dart-define-from-file=dart_defines.json
///
/// Note these values are compiled into the app binary. That is fine for the
/// App ID and the token server URL, which are identifiers rather than secrets.
/// The Agora App Certificate, which *is* a secret, is deliberately not here:
/// it lives only in the token server's environment.
class Env {
  const Env._();

  /// Agora App ID, used to initialise the RTC engine.
  static const String agoraAppId = String.fromEnvironment('AGORA_APP_ID');

  /// Base URL of the token server, e.g. `https://connectcall.vercel.app`.
  static const String tokenServerUrl =
      String.fromEnvironment('TOKEN_SERVER_URL');

  static bool get hasAgoraAppId => agoraAppId.isNotEmpty;
  static bool get hasTokenServer => tokenServerUrl.isNotEmpty;

  static const String missingAppIdMessage =
      'AGORA_APP_ID is not set. Run the app with:\n'
      '  flutter run --dart-define-from-file=dart_defines.json\n'
      'See the README for details.';

  static const String missingTokenServerMessage =
      'Calling is not configured on this build (TOKEN_SERVER_URL is missing).';
}
