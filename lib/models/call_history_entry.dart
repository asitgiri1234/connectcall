import 'call_model.dart';

/// One row of a user's call history, stored at `call_history/{uid}/{callId}`.
///
/// Written from the *owner's* point of view: [peerId] is always the other
/// person, and [direction] says whether the owner placed or received the call.
/// The same call therefore produces two entries, mirrored, one per participant.
class CallHistoryEntry {
  const CallHistoryEntry({
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.type,
    required this.direction,
    required this.status,
    required this.startedAt,
    required this.duration,
    this.peerPhotoUrl,
  });

  final String callId;
  final String peerId;
  final String peerName;
  final String? peerPhotoUrl;
  final CallType type;
  final CallDirection direction;
  final CallStatus status;

  /// When the call was placed, from the server timestamp on the call node,
  /// so both participants' entries agree to the millisecond.
  final DateTime startedAt;

  /// Talk time. Zero for calls that never connected.
  final Duration duration;

  bool get isIncoming => direction == CallDirection.incoming;
  bool get wasAnswered => duration > Duration.zero;

  /// The brief's "missed call indicator": an incoming call the owner never
  /// picked up. An unanswered *outgoing* call is shown as "No answer" instead,
  /// because from the caller's side nothing was missed.
  bool get isMissed => isIncoming && status == CallStatus.missed;

  /// Short outcome for the history row when there is no duration to show.
  String get outcomeLabel => switch (status) {
        CallStatus.missed => isIncoming ? 'Missed' : 'No answer',
        CallStatus.rejected => isIncoming ? 'Declined' : 'Declined by them',
        CallStatus.busy => 'Busy',
        CallStatus.failed => 'Failed',
        CallStatus.disconnected => 'Disconnected',
        _ => 'Not connected',
      };

  factory CallHistoryEntry.fromMap(String callId, Map<Object?, Object?> map) {
    final startedAt = map['startedAt'];
    final seconds = map['durationSeconds'];
    return CallHistoryEntry(
      callId: callId,
      peerId: map['peerId'] as String? ?? '',
      peerName: map['peerName'] as String? ?? 'Unknown',
      peerPhotoUrl: map['peerPhotoUrl'] as String?,
      type: CallType.fromName(map['type'] as String?),
      direction: CallDirection.fromName(map['direction'] as String?),
      status: CallStatus.fromName(map['status'] as String?),
      startedAt: startedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(startedAt)
          : DateTime.fromMillisecondsSinceEpoch(0),
      duration: Duration(seconds: seconds is int ? seconds : 0),
    );
  }

  /// Exactly the keys the database rules allow under `call_history`.
  Map<String, Object?> toMap() => {
        'peerId': peerId,
        'peerName': peerName,
        'peerPhotoUrl': peerPhotoUrl,
        'type': type.name,
        'direction': direction.name,
        'status': status.name,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'durationSeconds': duration.inSeconds,
      };

  /// Builds the mirrored pair of entries for a finished call: one for the
  /// caller (outgoing) and one for the receiver (incoming).
  static ({CallHistoryEntry caller, CallHistoryEntry receiver}) pairFor(
    CallModel call,
  ) {
    final startedAt = call.createdAt ??
        call.connectedAt ??
        call.endedAt ??
        DateTime.now();

    // Measured from connection, never from placement, so ring time is not
    // counted as talk time. A call that never connected lasted zero seconds.
    final connected = call.connectedAt;
    final ended = call.endedAt;
    final duration = (connected != null && ended != null && ended.isAfter(connected))
        ? ended.difference(connected)
        : Duration.zero;

    return (
      caller: CallHistoryEntry(
        callId: call.callId,
        peerId: call.receiverId,
        peerName: call.receiverName,
        peerPhotoUrl: call.receiverPhotoUrl,
        type: call.type,
        direction: CallDirection.outgoing,
        status: call.status,
        startedAt: startedAt,
        duration: duration,
      ),
      receiver: CallHistoryEntry(
        callId: call.callId,
        peerId: call.callerId,
        peerName: call.callerName,
        peerPhotoUrl: call.callerPhotoUrl,
        type: call.type,
        direction: CallDirection.incoming,
        status: call.status,
        startedAt: startedAt,
        duration: duration,
      ),
    );
  }
}
