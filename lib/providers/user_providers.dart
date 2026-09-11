import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../services/block_service.dart';
import '../services/presence_service.dart';
import '../services/user_service.dart';
import 'auth_providers.dart';

final userServiceProvider = Provider<UserService>((ref) => UserService());

final presenceServiceProvider = Provider<PresenceService>((ref) {
  final service = PresenceService();
  ref.onDispose(() => service.stop());
  return service;
});

/// The contacts directory: everyone except the signed-in user.
///
/// Re-subscribes when the uid changes, so the list cannot briefly show the
/// previous account's perspective after switching users.
final usersProvider = StreamProvider<List<UserModel>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <UserModel>[]);
  return ref.watch(userServiceProvider).watchUsers(excludeUid: uid);
});

/// Live view of one specific user, keyed by uid.
final userByIdProvider =
    StreamProvider.family<UserModel?, String>((ref, uid) {
  return ref.watch(userServiceProvider).watchUser(uid);
});

/// The current contacts search query.
///
/// Held in a provider rather than widget state so the Home and Contacts
/// screens share one search behaviour, and so the query survives a tab switch
/// within the navigation shell.
class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void update(String value) => state = value;
  void clear() => state = '';
}

final searchQueryProvider =
    NotifierProvider<SearchQuery, String>(SearchQuery.new);

/// Contacts filtered by the active query.
///
/// Filtering happens client-side against the already-streamed list: at this
/// scale it avoids a second round trip and keeps results instant while typing.
final filteredUsersProvider = Provider<AsyncValue<List<UserModel>>>((ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(visibleUsersProvider).whenData(
        (users) => users.where((u) => u.matches(query)).toList(),
      );
});

/// Binds presence tracking to the signed-in user and the app lifecycle.
///
/// Kept in a provider rather than a widget so that presence survives
/// navigation and is torn down exactly once, on logout or app disposal.
class PresenceController with WidgetsBindingObserver {
  PresenceController(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    _authSub = _ref.listen<String?>(
      currentUidProvider,
      (previous, next) => _onUidChanged(previous, next),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  ProviderSubscription<String?>? _authSub;

  PresenceService get _service => _ref.read(presenceServiceProvider);

  void _onUidChanged(String? previous, String? next) {
    if (next == null) {
      // Signed out: the write is already handled by AuthService.logout, so
      // just stop tracking.
      unawaited(_service.stop());
    } else if (previous != next) {
      unawaited(_service.start(next));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding is not disconnecting - the socket usually survives, and a
    // user checking another app should not flicker offline. Only lastSeen is
    // refreshed; isOnline stays driven by the actual connection.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.resumed) {
      unawaited(_service.touch());
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.close();
    unawaited(_service.stop());
  }
}

final presenceControllerProvider = Provider<PresenceController>((ref) {
  final controller = PresenceController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

// --- blocking (bonus 4) -------------------------------------------------------

final blockServiceProvider = Provider<BlockService>((ref) => BlockService());

/// Uids the signed-in user has blocked, kept live.
final blockedIdsProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <String>{});
  return ref.watch(blockServiceProvider).watchBlocked(uid);
});

/// The directory as this user should see it: everyone except themselves and
/// anyone they have blocked. Every list in the app reads this, not
/// [usersProvider], so a block takes effect everywhere at once.
final visibleUsersProvider = Provider<AsyncValue<List<UserModel>>>((ref) {
  final blocked = ref.watch(blockedIdsProvider).value ?? const <String>{};
  return ref
      .watch(usersProvider)
      .whenData((users) => withoutBlocked(users, blocked));
});

/// Profiles of blocked users, for the Blocked contacts screen.
final blockedUsersProvider = Provider<List<UserModel>>((ref) {
  final blocked = ref.watch(blockedIdsProvider).value ?? const <String>{};
  final users = ref.watch(usersProvider).value ?? const <UserModel>[];
  return users.where((user) => blocked.contains(user.uid)).toList();
});
