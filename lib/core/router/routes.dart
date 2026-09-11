/// Route paths and names in one place, so navigation calls are never
/// stringly-typed at the call site.
class Routes {
  const Routes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';

  // Shell tabs
  static const String home = '/home';
  static const String contacts = '/contacts';
  static const String history = '/history';
  static const String profile = '/profile';

  /// The full-screen call UI, pushed above the shell. One route for every
  /// call state: the screen switches between incoming, ringing, audio and
  /// video views by reading the call controller.
  static const String call = '/call';

  /// Tabs in bottom-navigation order. The index of a path here is its
  /// branch index in the shell route.
  static const List<String> shellTabs = [home, contacts, history, profile];
}
