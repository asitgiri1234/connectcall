/// Audio or video. Determines which permissions are requested, whether the
/// video track is published, and which call screen is shown.
enum CallType {
  audio,
  video;

  static CallType fromName(String? value) =>
      value == 'video' ? CallType.video : CallType.audio;

  String get label => this == CallType.video ? 'Video call' : 'Audio call';
}

/// Direction of a call relative to the user viewing it.
enum CallDirection {
  incoming,
  outgoing;

  static CallDirection fromName(String? value) =>
      value == 'incoming' ? CallDirection.incoming : CallDirection.outgoing;
}

/// The call lifecycle, covering every state the brief asks for.
///
/// The happy path is:
///   calling -> ringing -> connected -> ended
///
/// Everything else is a terminal state reached from somewhere in that path.
/// Both peers watch the same `calls/{callId}` node, so a transition written by
/// one side is observed by the other. That symmetry is what makes "caller
/// cancels, callee's incoming screen dismisses" fall out for free rather than
/// needing to be special-cased.
enum CallStatus {
  /// Caller has created the call node; callee has not acknowledged yet.
  calling,

  /// Callee's device has the incoming call on screen.
  ringing,

  /// Callee accepted. Both sides are joining the media channel.
  connected,

  /// Media is flowing; the duration timer is running.
  inCall,

  /// Ended normally by either side after connecting.
  ended,

  /// Callee actively declined.
  rejected,

  /// Rang until the timeout with no answer.
  missed,

  /// Callee was already in another call.
  busy,

  /// Could not establish media (permissions, engine error, bad network).
  failed,

  /// Media dropped mid-call and did not recover.
  disconnected;

  static CallStatus fromName(String? value) {
    return CallStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => CallStatus.failed,
    );
  }

  /// True once the call is over, whatever the reason. Used to decide when to
  /// tear down the engine and write the history record.
  bool get isTerminal => const {
        CallStatus.ended,
        CallStatus.rejected,
        CallStatus.missed,
        CallStatus.busy,
        CallStatus.failed,
        CallStatus.disconnected,
      }.contains(this);

  /// True while waiting for the callee to answer.
  bool get isRinging =>
      this == CallStatus.calling || this == CallStatus.ringing;

  /// True once media should be flowing.
  bool get isActive =>
      this == CallStatus.connected || this == CallStatus.inCall;

  /// Whether this outcome counts as a missed call in history.
  bool get isMissed => this == CallStatus.missed;

  /// Short label for the call screen's status line.
  String get label => switch (this) {
        CallStatus.calling => 'Calling...',
        CallStatus.ringing => 'Ringing...',
        CallStatus.connected => 'Connecting...',
        CallStatus.inCall => 'Connected',
        CallStatus.ended => 'Call ended',
        CallStatus.rejected => 'Call declined',
        CallStatus.missed => 'No answer',
        CallStatus.busy => 'User is busy',
        CallStatus.failed => 'Call failed',
        CallStatus.disconnected => 'Disconnected',
      };
}

/// A call as stored at `calls/{callId}` and mirrored into call history.
class CallModel {
  const CallModel({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.receiverId,
    required this.receiverName,
    required this.type,
    required this.status,
    required this.channelName,
    this.callerPhotoUrl,
    this.receiverPhotoUrl,
    this.createdAt,
    this.connectedAt,
    this.endedAt,
  });

  final String callId;
  final String callerId;
  final String callerName;
  final String? callerPhotoUrl;
  final String receiverId;
  final String receiverName;
  final String? receiverPhotoUrl;
  final CallType type;
  final CallStatus status;

  /// Agora channel both peers join. Derived from the call id so it is unique
  /// per call and needs no separate coordination.
  final String channelName;

  final DateTime? createdAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;

  /// Talk time, measured from when media connected rather than from when the
  /// call was placed, so ring time is not counted as duration.
  Duration get duration {
    final start = connectedAt;
    if (start == null) return Duration.zero;
    return (endedAt ?? DateTime.now()).difference(start);
  }

  bool isCaller(String uid) => uid == callerId;

  /// The other party, from [uid]'s point of view.
  String otherPartyId(String uid) => isCaller(uid) ? receiverId : callerId;
  String otherPartyName(String uid) => isCaller(uid) ? receiverName : callerName;
  String? otherPartyPhoto(String uid) =>
      isCaller(uid) ? receiverPhotoUrl : callerPhotoUrl;

  factory CallModel.fromMap(String callId, Map<Object?, Object?> map) {
    return CallModel(
      callId: callId,
      callerId: map['callerId'] as String? ?? '',
      callerName: map['callerName'] as String? ?? 'Unknown',
      callerPhotoUrl: map['callerPhotoUrl'] as String?,
      receiverId: map['receiverId'] as String? ?? '',
      receiverName: map['receiverName'] as String? ?? 'Unknown',
      receiverPhotoUrl: map['receiverPhotoUrl'] as String?,
      type: CallType.fromName(map['type'] as String?),
      status: CallStatus.fromName(map['status'] as String?),
      channelName: map['channelName'] as String? ?? callId,
      createdAt: _asDate(map['createdAt']),
      connectedAt: _asDate(map['connectedAt']),
      endedAt: _asDate(map['endedAt']),
    );
  }

  Map<String, Object?> toMap() => {
        'callerId': callerId,
        'callerName': callerName,
        'callerPhotoUrl': callerPhotoUrl,
        'receiverId': receiverId,
        'receiverName': receiverName,
        'receiverPhotoUrl': receiverPhotoUrl,
        'type': type.name,
        'status': status.name,
        'channelName': channelName,
        'createdAt': createdAt?.millisecondsSinceEpoch,
        'connectedAt': connectedAt?.millisecondsSinceEpoch,
        'endedAt': endedAt?.millisecondsSinceEpoch,
      };

  CallModel copyWith({
    CallStatus? status,
    DateTime? connectedAt,
    DateTime? endedAt,
  }) {
    return CallModel(
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      callerPhotoUrl: callerPhotoUrl,
      receiverId: receiverId,
      receiverName: receiverName,
      receiverPhotoUrl: receiverPhotoUrl,
      type: type,
      status: status ?? this.status,
      channelName: channelName,
      createdAt: createdAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }

  static DateTime? _asDate(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  @override
  String toString() => 'CallModel($callId, ${type.name}, ${status.name})';
}
