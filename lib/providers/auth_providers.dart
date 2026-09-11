import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_exception.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'push_providers.dart';

/// The service instance. Overriding this in a ProviderScope is how tests
/// swap in a fake without touching any widget.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Raw Firebase auth state. The router redirect watches this.
///
/// Firebase restores a persisted session asynchronously on cold start, so
/// this is deliberately an [AsyncValue]: `loading` genuinely means "we do not
/// know yet", which is what the splash screen waits on. Treating loading as
/// signed-out would bounce returning users to the login screen every launch.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Convenience view of whether someone is signed in, once known.
final isSignedInProvider = Provider<bool?>((ref) {
  return ref.watch(authStateProvider).when(
        data: (user) => user != null,
        loading: () => null,
        error: (_, stack) => false,
      );
});

final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).value?.uid;
});

/// The signed-in user's own record, kept live so profile edits appear at once.
///
/// Re-subscribes when the uid changes, so signing out and back in as someone
/// else does not leave the previous user's record on screen.
final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(authServiceProvider).watchCurrentUser();
});

/// Drives the login, register and logout actions.
///
/// State is `AsyncValue<void>`: `loading` disables the submit button and shows
/// a spinner, `error` renders the message. Keeping this out of the screens
/// means the same submission logic is reused by both auth forms and stays
/// testable without pumping widgets.
class AuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  AuthService get _service => ref.read(authServiceProvider);

  /// Returns true on success so the caller can navigate; errors land in
  /// [state] for the form to display rather than being thrown at the UI.
  Future<bool> login({required String email, required String password}) {
    return _run(() => _service.login(email: email, password: password));
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) {
    return _run(
      () => _service.register(name: name, email: email, password: password),
    );
  }

  Future<bool> logout() => _run(() async {
        // Before signing out: the rules only let the owner delete their
        // push token, and a signed-out phone must stop receiving calls.
        final uid = _service.uid;
        if (uid != null) await ref.read(pushServiceProvider).unregister(uid);
        await _service.logout();
      });

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncValue.loading();
    try {
      await action();
      state = const AsyncValue.data(null);
      return true;
    } on AppException catch (e, stack) {
      state = AsyncValue.error(e, stack);
      return false;
    } catch (e, stack) {
      state = AsyncValue.error(const AppException.unknown(), stack);
      return false;
    }
  }

  /// Clears a previous error, so a stale message does not sit under a form
  /// the user has since edited.
  void clearError() {
    if (state.hasError) state = const AsyncValue.data(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
