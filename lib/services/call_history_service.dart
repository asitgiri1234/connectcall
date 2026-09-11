import 'package:firebase_database/firebase_database.dart';

import '../core/constants/app_constants.dart';
import '../models/call_history_entry.dart';
import '../models/call_model.dart';

/// Reads and writes per-user call history.
///
/// Plain Dart with no Flutter imports, like every other service.
class CallHistoryService {
  CallHistoryService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  /// Records a finished call in *both* participants' histories.
  ///
  /// Whichever device observes the call end writes both entries, in one
  /// atomic multi-path update. That is deliberate, and it is what makes the
  /// missed-call indicator work: a call is often missed precisely because the
  /// callee's device was offline, in which case that device never learns the
  /// call existed. The caller's device therefore records the callee's
  /// "missed call" too.
  ///
  /// Both devices usually do observe the end, so the pair is written twice.
  /// That is harmless: both write identical data to the same keys, because
  /// every value comes from the call node's server timestamps rather than
  /// either device's clock.
  Future<void> recordCall(CallModel call) async {
    if (!call.status.isTerminal) return;
    if (call.callerId.isEmpty || call.receiverId.isEmpty) return;

    final pair = CallHistoryEntry.pairFor(call);
    try {
      await _db.ref().update({
        DbPaths.historyEntry(call.callerId, call.callId): pair.caller.toMap(),
        DbPaths.historyEntry(call.receiverId, call.callId): pair.receiver.toMap(),
      });
    } catch (_) {
      // History is a record, not part of the call. A failed write must never
      // surface as a call error; the other device's identical write, or the
      // next observer, fills the gap.
    }
  }

  /// The signed-in user's history, newest first.
  ///
  /// Ordered and limited server-side on the indexed `startedAt` field, so a
  /// long history is never downloaded in full just to show the latest page.
  Stream<List<CallHistoryEntry>> watchHistory(
    String uid, {
    int limit = AppConstants.historyPageSize,
  }) {
    return _db
        .ref(DbPaths.historyOf(uid))
        .orderByChild('startedAt')
        .limitToLast(limit)
        .onValue
        .map((event) {
      final value = event.snapshot.value;
      if (value is! Map<Object?, Object?>) return <CallHistoryEntry>[];

      final entries = <CallHistoryEntry>[];
      value.forEach((key, entry) {
        if (key is String && entry is Map<Object?, Object?>) {
          entries.add(CallHistoryEntry.fromMap(key, entry));
        }
      });
      // limitToLast returns ascending; the screen wants newest first.
      entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return entries;
    });
  }
}
