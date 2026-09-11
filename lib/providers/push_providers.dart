import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/push_service.dart';
import 'auth_providers.dart';

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService();
  ref.onDispose(service.dispose);
  return service;
});

final callNotifierProvider = Provider<CallNotifier>((ref) => CallNotifier());

/// Registers this device for incoming-call pushes whenever someone is signed
/// in. Watched from the app root, alongside presence.
final pushRegistrationProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return;
  ref.read(pushServiceProvider).register(uid);
});

/// A call the user accepted on Android's native incoming-call screen, which
/// launched the app, but which the app has not answered yet.
///
/// Accepting there opens ConnectCall; the app then has to load, sign in from
/// its saved session, and see the call arrive through its own listener before
/// it can answer. This holds the call id across that gap, so the in-app flow
/// answers that call automatically instead of ringing it a second time.
class PendingNativeAccept extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String callId) => state = callId;

  /// Returns and clears the pending id if it matches [callId].
  bool consume(String callId) {
    if (state != callId) return false;
    state = null;
    return true;
  }
}

final pendingNativeAcceptProvider =
    NotifierProvider<PendingNativeAccept, String?>(PendingNativeAccept.new);
