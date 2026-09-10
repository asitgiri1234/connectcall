/// Build-time configuration.
///
/// Secrets are injected with `--dart-define` so they never enter source
/// control. See the README "Environment variables" section for the run
/// command and the `dart_defines.json` template.
///
///   flutter run --dart-define=AGORA_APP_ID=xxxxxxxxxxxx
class Env {
  const Env._();

  /// Agora App ID, used to initialise the RTC engine.
  static const String agoraAppId = String.fromEnvironment('AGORA_APP_ID');

  /// Agora token. Empty while the Agora project runs in testing mode
  /// (App ID only). Adding a token server later means supplying this value
  /// without touching any call code.
  static const String agoraToken = String.fromEnvironment('AGORA_TOKEN');

  static bool get hasAgoraAppId => agoraAppId.isNotEmpty;

  /// Surfaces a readable message instead of an opaque Agora error code
  /// when someone runs the app without configuring it.
  static const String missingAppIdMessage =
      'AGORA_APP_ID is not set. Run the app with:\n'
      '  flutter run --dart-define=AGORA_APP_ID=<your app id>\n'
      'See the README for details.';
}
