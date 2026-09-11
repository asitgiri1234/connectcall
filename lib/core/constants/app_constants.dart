/// Static app-wide values. Anything tunable lives here rather than being
/// scattered through widgets as magic numbers.
class AppConstants {
  const AppConstants._();

  static const String appName = 'ConnectCall';
  static const String tagline = 'Connect with anyone, anywhere.';

  /// How long the caller rings before the call is marked missed on both sides.
  static const Duration ringTimeout = Duration(seconds: 45);

  /// Minimum time the splash screen stays visible, so it cannot flash by.
  static const Duration splashMinimum = Duration(milliseconds: 1500);

  /// Debounce applied to the contacts search field.
  static const Duration searchDebounce = Duration(milliseconds: 300);

  /// Number of call history entries fetched per screen.
  static const int historyPageSize = 50;
}

/// Realtime Database paths, kept in one place so the schema is greppable
/// and a rename cannot silently miss a call site.
///
/// Schema:
///   users/{uid}                  profile + presence
///   calls/{callId}               live signaling node, watched by both peers
///   user_calls/{uid}             pointer to the user's active call, if any
///   call_history/{uid}/{callId}  per-user immutable record
class DbPaths {
  const DbPaths._();

  static const String users = 'users';
  static const String calls = 'calls';
  static const String userCalls = 'user_calls';
  static const String callHistory = 'call_history';

  static String user(String uid) => '$users/$uid';
  static String call(String callId) => '$calls/$callId';
  static String userCall(String uid) => '$userCalls/$uid';
  static String historyOf(String uid) => '$callHistory/$uid';
  static String historyEntry(String uid, String callId) =>
      '$callHistory/$uid/$callId';

  static const String blocks = 'blocks';
  static String blocksOf(String uid) => '$blocks/$uid';
  static String block(String uid, String blockedUid) =>
      '$blocks/$uid/$blockedUid';
}
