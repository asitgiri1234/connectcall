import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/call_history_entry.dart';
import '../services/call_history_service.dart';
import 'auth_providers.dart';
import 'user_providers.dart';

final callHistoryServiceProvider =
    Provider<CallHistoryService>((ref) => CallHistoryService());

/// The signed-in user's call history, newest first, kept live so a call that
/// just ended appears without a refresh.
final callHistoryProvider = StreamProvider<List<CallHistoryEntry>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <CallHistoryEntry>[]);

  // Calls with people you have blocked are hidden, not deleted: unblocking
  // brings them back.
  final blocked = ref.watch(blockedIdsProvider).value ?? const <String>{};
  return ref.watch(callHistoryServiceProvider).watchHistory(uid).map(
        (all) => blocked.isEmpty
            ? all
            : all.where((entry) => !blocked.contains(entry.peerId)).toList(),
      );
});

/// The few most recent calls, for the Home screen.
final recentCallsProvider = Provider<AsyncValue<List<CallHistoryEntry>>>((ref) {
  return ref.watch(callHistoryProvider).whenData((all) => all.take(3).toList());
});

/// People this user talks to most, ranked by number of calls in the loaded
/// history, ties broken by who was called most recently (bonus 5).
///
/// Derived from history already on the device rather than a separate counter
/// in the database, so there is nothing extra to keep in sync.
final frequentContactIdsProvider = Provider<List<String>>((ref) {
  final history = ref.watch(callHistoryProvider).value ?? const [];
  final counts = <String, int>{};
  final lastSeen = <String, DateTime>{};
  for (final entry in history) {
    counts.update(entry.peerId, (c) => c + 1, ifAbsent: () => 1);
    final previous = lastSeen[entry.peerId];
    if (previous == null || entry.startedAt.isAfter(previous)) {
      lastSeen[entry.peerId] = entry.startedAt;
    }
  }
  final ids = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : lastSeen[b]!.compareTo(lastSeen[a]!);
    });
  return ids.take(5).toList();
});
