import 'package:firebase_database/firebase_database.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/app_exception.dart';
import '../models/call_model.dart';
import '../models/user_model.dart';

/// Call signaling over the Realtime Database.
///
/// This is the layer Agora does not provide. Agora carries media once both
/// peers are in the same channel, but nothing in it tells device B that
/// device A wants to call. That is what this class does.
///
/// The design is deliberately one shared document per call:
///
///   calls/{callId}  { callerId, receiverId, type, status, channelName, ... }
///
/// Both peers listen to the same node, so every transition is observed by both
/// sides. That symmetry is what makes behaviours like "caller cancels, so the
/// callee's incoming screen disappears" fall out of the design rather than
/// needing to be special-cased: the callee is already watching `status`, and
/// `cancelled` is just another value it reacts to.
///
/// `user_calls/{uid}` holds a pointer to a user's active call. It exists so
/// the callee can watch a single, cheap node for incoming calls instead of
/// querying the whole `calls` collection, and so a second caller can detect
/// that someone is already busy.
class SignalingService {
  SignalingService({FirebaseDatabase? database})
      : _db = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _db;

  /// Places a call and returns the created record.
  ///
  /// Throws [AppException] if the callee is already on another call, so the
  /// caller sees "user is busy" rather than both parties being dropped into a
  /// channel that the callee never agreed to join.
  Future<CallModel> placeCall({
    required UserModel caller,
    required UserModel receiver,
    required CallType type,
  }) async {
    if (caller.uid == receiver.uid) {
      throw const AppException('You cannot call yourself.');
    }

    final busy = await _isBusy(receiver.uid);
    if (busy) {
      throw const AppException(
        'That person is already on another call.',
        code: 'busy',
      );
    }

    // push() generates a chronologically sortable unique key server-side, so
    // no coordination is needed to avoid collisions.
    final callRef = _db.ref(DbPaths.calls).push();
    final callId = callRef.key!;

    final call = CallModel(
      callId: callId,
      callerId: caller.uid,
      callerName: caller.name,
      callerPhotoUrl: caller.photoUrl,
      receiverId: receiver.uid,
      receiverName: receiver.name,
      receiverPhotoUrl: receiver.photoUrl,
      type: type,
      status: CallStatus.calling,
      // Channel name is derived from the call id, so it is unique per call
      // and both peers can compute it without a second round trip.
      channelName: 'call_$callId',
      createdAt: DateTime.now(),
    );

    // The call node is written before the pointers. If this write succeeds but
    // the pointers fail, the call simply never rings and times out, which is a
    // recoverable state. The reverse order could leave a pointer to a call
    // node that does not exist.
    await callRef.set({
      ...call.toMap(),
      'createdAt': ServerValue.timestamp,
    });

    await Future.wait([
      _db.ref(DbPaths.userCall(caller.uid)).set(callId),
      _db.ref(DbPaths.userCall(receiver.uid)).set(callId),
    ]);

    // If either side disconnects while the call node is live, clear it
    // server-side so a crashed app does not leave the other party stuck on a
    // ringing screen forever.
    await callRef.onDisconnect().update({
      'status': CallStatus.disconnected.name,
      'endedAt': ServerValue.timestamp,
    });

    return call;
  }

  /// Watches a single call. Both peers subscribe to this.
  ///
  /// Emits null once the node is removed, which the controller treats as the
  /// call being fully torn down.
  Stream<CallModel?> watchCall(String callId) {
    return _db.ref(DbPaths.call(callId)).onValue.map((event) {
      final value = event.snapshot.value;
      if (value is Map<Object?, Object?>) {
        return CallModel.fromMap(callId, value);
      }
      return null;
    });
  }

  /// Watches for a call directed at [uid].
  ///
  /// Resolves the pointer at `user_calls/{uid}` into the full call record.
  /// Returns null when there is no active call.
  Stream<CallModel?> watchIncoming(String uid) async* {
    await for (final event in _db.ref(DbPaths.userCall(uid)).onValue) {
      final callId = event.snapshot.value;
      if (callId is! String || callId.isEmpty) {
        yield null;
        continue;
      }

      final snapshot = await _db.ref(DbPaths.call(callId)).get();
      final value = snapshot.value;
      if (value is Map<Object?, Object?>) {
        yield CallModel.fromMap(callId, value);
      } else {
        yield null;
      }
    }
  }

  /// Marks the call as ringing, so the caller's UI can move from
  /// "Calling..." to "Ringing...". Written by the callee once its incoming
  /// screen is actually on display.
  Future<void> markRinging(String callId) =>
      _updateStatus(callId, CallStatus.ringing);

  /// Callee accepted. Both sides join the media channel on observing this.
  Future<void> acceptCall(String callId) async {
    await _db.ref(DbPaths.call(callId)).update({
      'status': CallStatus.connected.name,
      'connectedAt': ServerValue.timestamp,
    });
  }

  Future<void> rejectCall(String callId) =>
      _endWith(callId, CallStatus.rejected);

  /// Caller gave up, or the ring timed out with no answer.
  Future<void> markMissed(String callId) =>
      _endWith(callId, CallStatus.missed);

  /// Normal hang-up after the call connected.
  Future<void> endCall(String callId) => _endWith(callId, CallStatus.ended);

  Future<void> markFailed(String callId) =>
      _endWith(callId, CallStatus.failed);

  /// Media is flowing. Separate from `connected` so the duration timer starts
  /// from actual media rather than from the accept tap.
  Future<void> markInCall(String callId) =>
      _updateStatus(callId, CallStatus.inCall);

  Future<void> _updateStatus(String callId, CallStatus status) async {
    try {
      await _db.ref(DbPaths.call(callId)).update({'status': status.name});
    } catch (_) {
      // A failed status write must not crash an in-progress call.
    }
  }

  /// Writes a terminal status, then releases both parties' busy pointers.
  ///
  /// The status write happens first so the other peer observes the reason the
  /// call ended before the node is cleaned up.
  Future<void> _endWith(String callId, CallStatus status) async {
    final callRef = _db.ref(DbPaths.call(callId));

    try {
      // Cancel the disconnect handler, otherwise it would later overwrite the
      // real reason with "disconnected".
      await callRef.onDisconnect().cancel();
    } catch (_) {
      // Best effort.
    }

    final snapshot = await callRef.get();
    final value = snapshot.value;
    if (value is! Map<Object?, Object?>) return;

    final call = CallModel.fromMap(callId, value);

    // Guard against double-ending: whoever writes a terminal status first
    // wins, so a simultaneous hang-up on both sides does not produce two
    // conflicting outcomes.
    if (call.status.isTerminal) return;

    await callRef.update({
      'status': status.name,
      'endedAt': ServerValue.timestamp,
    });

    await Future.wait([
      _clearPointer(call.callerId, callId),
      _clearPointer(call.receiverId, callId),
    ]);
  }

  /// Clears a busy pointer only if it still refers to this call, so ending an
  /// old call cannot free a pointer that a newer call has since claimed.
  Future<void> _clearPointer(String uid, String callId) async {
    final ref = _db.ref(DbPaths.userCall(uid));
    try {
      final snapshot = await ref.get();
      if (snapshot.value == callId) await ref.remove();
    } catch (_) {
      // Best effort.
    }
  }

  /// True if [uid] has a pointer to a call that has not reached a terminal
  /// state. A pointer to an already-ended call is treated as stale and
  /// cleared, so a crash cannot leave someone permanently "busy".
  Future<bool> _isBusy(String uid) async {
    final pointer = await _db.ref(DbPaths.userCall(uid)).get();
    final callId = pointer.value;
    if (callId is! String || callId.isEmpty) return false;

    final snapshot = await _db.ref(DbPaths.call(callId)).get();
    final value = snapshot.value;
    if (value is! Map<Object?, Object?>) {
      await _clearPointer(uid, callId);
      return false;
    }

    final call = CallModel.fromMap(callId, value);
    if (call.status.isTerminal) {
      await _clearPointer(uid, callId);
      return false;
    }
    return true;
  }

  /// Removes the call node once both sides have torn down. Called by the
  /// caller only, to avoid a double delete.
  Future<void> disposeCall(String callId) async {
    try {
      await _db.ref(DbPaths.call(callId)).remove();
    } catch (_) {
      // Best effort - a leftover node is harmless, it is already terminal.
    }
  }
}
