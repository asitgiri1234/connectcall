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

  // Full-screen call routes, pushed above the shell.
  static const String outgoingCall = '/call/outgoing';
  static const String incomingCall = '/call/incoming';
  static const String activeCall = '/call/active';

  /// Tabs in bottom-navigation order. The index of a path here is its
  /// branch index in the shell route.
  static const List<String> shellTabs = [home, contacts, history, profile];
}
