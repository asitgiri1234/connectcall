import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/app_exception.dart';
import '../models/call_model.dart';
import '../models/user_model.dart';
import '../services/agora_service.dart';
import '../services/agora_token_provider.dart';
import '../services/permission_service.dart';
import '../services/signaling_service.dart';
import 'auth_providers.dart';

// --- service providers -------------------------------------------------------
//
// Each is overridable in a ProviderScope, which is how tests replace the
// network and the Agora engine with fakes.

final signalingServiceProvider =
    Provider<SignalingService>((ref) => SignalingService());

final agoraTokenProviderProvider =
    Provider<AgoraTokenProvider>((ref) => ServerAgoraTokenProvider());

final permissionServiceProvider =
    Provider<PermissionService>((ref) => const PermissionService());

/// A factory rather than one shared instance: every call gets a fresh media
/// wrapper, so nothing from one call's engine can leak into the next.
final agoraServiceFactoryProvider =
    Provider<AgoraService Function()>((ref) => AgoraService.new);

// --- state -------------------------------------------------------------------

/// Everything the call screens render, in one immutable value.
class ActiveCall {
  const ActiveCall({
    required this.call,
    required this.isCaller,
    this.muted = false,
    this.speakerOn = false,
    this.cameraOn = true,
    this.localJoined = false,
    this.remoteRtcUid,
    this.remoteVideoOn = true,
    this.quality = NetworkQuality.unknown,
    this.reconnecting = false,
    this.inCallSince,
    this.error,
  });

  /// The latest copy of the shared signaling node.
  final CallModel call;
  final bool isCaller;

  final bool muted;
  final bool speakerOn;
  final bool cameraOn;

  /// This device has joined the media channel. The local camera preview
  /// renders from this point, without waiting for the other person.
  final bool localJoined;

  /// The other participant's Agora uid, known once their media arrives. The
  /// remote video view needs it.
  final int? remoteRtcUid;
  final bool remoteVideoOn;

  final NetworkQuality quality;
  final bool reconnecting;

  /// When media started flowing. The duration timer counts from here, so
  /// ring time is never shown as talk time.
  final DateTime? inCallSince;

  /// The latest problem worth showing, if any.
  final AppException? error;

  CallStatus get status => call.status;
  bool get isVideo => call.type == CallType.video;
  bool get isIncomingRinging => !isCaller && status.isRinging;

  /// The other participant, as a lightweight profile for names and avatars.
  UserModel get peer => isCaller
      ? UserModel(
          uid: call.receiverId,
          name: call.receiverName,
          email: '',
          photoUrl: call.receiverPhotoUrl,
        )
      : UserModel(
          uid: call.callerId,
          name: call.callerName,
          email: '',
          photoUrl: call.callerPhotoUrl,
        );

  ActiveCall copyWith({
    CallModel? call,
    bool? muted,
    bool? speakerOn,
    bool? cameraOn,
    bool? localJoined,
    int? remoteRtcUid,
    bool? remoteVideoOn,
    NetworkQuality? quality,
    bool? reconnecting,
    DateTime? inCallSince,
    AppException? error,
    bool clearError = false,
  }) {
    return ActiveCall(
      call: call ?? this.call,
      isCaller: isCaller,
      muted: muted ?? this.muted,
      speakerOn: speakerOn ?? this.speakerOn,
      cameraOn: cameraOn ?? this.cameraOn,
      localJoined: localJoined ?? this.localJoined,
      remoteRtcUid: remoteRtcUid ?? this.remoteRtcUid,
      remoteVideoOn: remoteVideoOn ?? this.remoteVideoOn,
      quality: quality ?? this.quality,
      reconnecting: reconnecting ?? this.reconnecting,
      inCallSince: inCallSince ?? this.inCallSince,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// What happened when the user tried to start or answer a call, so the UI
/// can respond appropriately: navigate, explain a permission, or show an error.
sealed class CallAttempt {
  const CallAttempt();
}

class CallStarted extends CallAttempt {
  const CallStarted();
}

class CallBlockedByPermission extends CallAttempt {
  const CallBlockedByPermission(this.check);
  final PermissionCheck check;
}

class CallCouldNotStart extends CallAttempt {
  const CallCouldNotStart(this.error);
  final AppException error;
}

// --- controller --------------------------------------------------------------

/// Owns the lifecycle of the one call this device can be in.
///
/// This is the only place that decides what the call *is*. It reconciles two
/// independent streams of truth:
///
///  - the signaling node (`calls/{callId}`), which both peers watch and which
///    carries the agreed status: calling, ringing, connected, ended, ...
///  - the media layer ([AgoraService]), which reports what is physically
///    happening: the other person's audio arrived, the network dropped.
///
/// The rule that keeps them consistent: **only the signaling node decides a
/// call is over.** When media reports a problem, the controller writes the
/// corresponding terminal status to the node rather than just updating local
/// state, so the other device learns the same outcome through the same path.
///
/// State is `null` when there is no call.
class CallController extends Notifier<ActiveCall?> {
  /// Upper bound on a signaling write. The RTDB SDK queues writes while
  /// offline instead of failing them, so without a timeout a call placed or
  /// answered on a dead connection would wait forever.
  static const _networkTimeout = Duration(seconds: 12);

  StreamSubscription<CallModel?>? _callSub;
  StreamSubscription<MediaEvent>? _mediaSub;
  AgoraService? _media;
  Timer? _ringTimer;
  Timer? _clearTimer;
  bool _mediaStarted = false;

  @override
  ActiveCall? build() {
    ref.onDispose(_disposeAll);
    return null;
  }

  SignalingService get _signaling => ref.read(signalingServiceProvider);
  PermissionService get _permissions => ref.read(permissionServiceProvider);

  /// True while a call is in progress (a finished call still showing its
  /// "Call ended" state does not count).
  bool get isBusy => state != null && !state!.status.isTerminal;

  // --- outgoing --------------------------------------------------------------

  Future<CallAttempt> startCall({
    required UserModel me,
    required UserModel callee,
    required CallType type,
  }) async {
    if (isBusy) {
      return const CallCouldNotStart(
        AppException('You are already on a call.', code: 'already-in-call'),
      );
    }

    // Permissions first: there is no point ringing someone if we then cannot
    // open the microphone when they answer.
    final check = await _permissions.ensureForCall(type);
    if (!check.isGranted) return CallBlockedByPermission(check);

    try {
      final call = await _signaling
          .placeCall(caller: me, receiver: callee, type: type)
          .timeout(_networkTimeout);
      _begin(call, isCaller: true);

      // The caller owns the ring timeout. If nobody answers in time, the call
      // becomes "missed" for both sides through the shared node.
      _ringTimer = Timer(AppConstants.ringTimeout, () {
        final current = state;
        if (current != null && current.status.isRinging) {
          unawaited(_signaling.markMissed(current.call.callId));
        }
      });
      return const CallStarted();
    } on TimeoutException {
      return const CallCouldNotStart(AppException.network());
    } on AppException catch (e) {
      return CallCouldNotStart(e);
    } catch (_) {
      return const CallCouldNotStart(AppException.unknown());
    }
  }

  // --- incoming --------------------------------------------------------------

  /// Called by [incomingCallListenerProvider] when a call arrives.
  void presentIncoming(CallModel call) {
    if (state?.call.callId == call.callId) return;

    if (isBusy) {
      // Two calls landed at once. The second caller hears "busy".
      unawaited(_signaling.markBusy(call.callId));
      return;
    }

    _begin(call, isCaller: false);
    // Tells the caller's screen to move from "Calling..." to "Ringing...":
    // the call has actually reached this device.
    unawaited(_signaling.markRinging(call.callId));
  }

  Future<CallAttempt> accept() async {
    final current = state;
    if (current == null || !current.isIncomingRinging) {
      return const CallCouldNotStart(
        AppException('This call is no longer ringing.', code: 'not-ringing'),
      );
    }

    // Deliberately not auto-declining on refusal: the user may want to grant
    // the permission and answer, or decline themselves.
    final check = await _permissions.ensureForCall(current.call.type);
    if (!check.isGranted) return CallBlockedByPermission(check);

    try {
      await _signaling.acceptCall(current.call.callId).timeout(_networkTimeout);
      return const CallStarted();
    } on TimeoutException {
      return const CallCouldNotStart(AppException.network());
    } catch (_) {
      return const CallCouldNotStart(AppException(
        'Could not answer the call. Check your connection.',
        code: 'accept-failed',
      ));
    }
  }

  Future<void> decline() async {
    final current = state;
    if (current == null || !current.isIncomingRinging) return;
    await _signaling.rejectCall(current.call.callId);
  }

  // --- in call ---------------------------------------------------------------

  Future<void> hangUp() async {
    final current = state;
    if (current == null || current.status.isTerminal) return;
    final id = current.call.callId;

    if (current.status.isRinging) {
      // Hanging up before an answer: for the caller that is a cancelled call,
      // which the callee records as missed; for the callee it is a decline.
      current.isCaller
          ? await _signaling.markMissed(id)
          : await _signaling.rejectCall(id);
    } else {
      await _signaling.endCall(id);
    }
  }

  Future<void> toggleMute() async {
    final current = state;
    if (current == null) return;
    final next = !current.muted;
    state = current.copyWith(muted: next);
    await _media?.setMuted(next);
  }

  Future<void> toggleSpeaker() async {
    final current = state;
    if (current == null) return;
    final next = !current.speakerOn;
    state = current.copyWith(speakerOn: next);
    await _media?.setSpeakerOn(next);
  }

  Future<void> toggleCamera() async {
    final current = state;
    if (current == null || !current.isVideo) return;
    final next = !current.cameraOn;
    state = current.copyWith(cameraOn: next);
    await _media?.setCameraEnabled(next);
  }

  Future<void> switchCamera() async {
    final current = state;
    if (current == null || !current.isVideo || !current.cameraOn) return;
    await _media?.switchCamera();
  }

  /// The engine the video views render against, while media is active.
  AgoraService? get media => _media;

  void clearError() {
    final current = state;
    if (current?.error != null) state = current!.copyWith(clearError: true);
  }

  // --- internals -------------------------------------------------------------

  void _begin(CallModel call, {required bool isCaller}) {
    _clearTimer?.cancel();
    _ringTimer?.cancel();
    unawaited(_callSub?.cancel());
    _mediaStarted = false;

    state = ActiveCall(
      call: call,
      isCaller: isCaller,
      // Video calls default to the loudspeaker, audio calls to the earpiece.
      speakerOn: call.type == CallType.video,
    );

    _callSub = _signaling.watchCall(call.callId).listen(
          _onCallUpdate,
          onError: (Object _) => _onCallLost(),
        );
  }

  void _onCallUpdate(CallModel? call) {
    final current = state;
    if (current == null) return;

    if (call == null) {
      // The node was removed out from under us. Treat it as ended.
      _onCallLost();
      return;
    }

    state = current.copyWith(call: call);

    if (call.status == CallStatus.connected && !_mediaStarted) {
      _ringTimer?.cancel();
      unawaited(_startMedia(call));
    }

    if (call.status == CallStatus.inCall && current.inCallSince == null) {
      _ringTimer?.cancel();
      state = state!.copyWith(inCallSince: DateTime.now());
    }

    if (call.status.isTerminal) _finish(call);
  }

  void _onCallLost() {
    final current = state;
    if (current == null || current.status.isTerminal) return;
    _finish(current.call.copyWith(
      status: CallStatus.disconnected,
      endedAt: DateTime.now(),
    ));
  }

  Future<void> _startMedia(CallModel call) async {
    _mediaStarted = true;
    final media = ref.read(agoraServiceFactoryProvider)();
    _media = media;
    _mediaSub = media.events.listen(_onMedia);

    try {
      final credentials =
          await ref.read(agoraTokenProviderProvider).credentialsFor(call.callId);
      await media.initialize();
      await media.join(
        credentials: credentials,
        video: call.type == CallType.video,
      );
    } on AppException catch (e) {
      state = state?.copyWith(error: e);
      await _signaling.markFailed(call.callId);
    } catch (_) {
      state = state?.copyWith(error: const AppException.unknown());
      await _signaling.markFailed(call.callId);
    }
  }

  void _onMedia(MediaEvent event) {
    final current = state;
    if (current == null || current.status.isTerminal) return;
    final id = current.call.callId;

    switch (event) {
      case JoinedChannel():
        state = current.copyWith(localJoined: true);

      case RemoteUserJoined(:final rtcUid):
        // The other person's media has arrived: this is the true start of
        // the call, and the moment the duration timer begins.
        state = current.copyWith(
          remoteRtcUid: rtcUid,
          reconnecting: false,
          inCallSince: current.inCallSince ?? DateTime.now(),
        );
        unawaited(_signaling.markInCall(id));

      case RemoteUserLeft(:final dropped):
        // A deliberate hang-up already arrives through signaling as "ended".
        // A drop does not, so it is written to the node here, which tells the
        // other device the same thing.
        if (dropped) unawaited(_signaling.markDisconnected(id));

      case ConnectionChanged(state: final connection, :final error):
        switch (connection) {
          case MediaConnectionState.reconnecting:
            state = current.copyWith(reconnecting: true);
          case MediaConnectionState.connected:
            state = current.copyWith(reconnecting: false);
          case MediaConnectionState.failed:
            state = current.copyWith(error: error);
            unawaited(_signaling.markFailed(id));
          case MediaConnectionState.connecting:
          case MediaConnectionState.disconnected:
            break;
        }

      case NetworkQualityChanged(:final quality):
        state = current.copyWith(quality: quality);

      case RemoteVideoChanged(:final enabled):
        state = current.copyWith(remoteVideoOn: enabled);

      case TokenWillExpire():
        unawaited(_renewToken(id));

      case MediaError(:final error):
        state = current.copyWith(error: error);
    }
  }

  Future<void> _renewToken(String callId) async {
    try {
      final credentials =
          await ref.read(agoraTokenProviderProvider).credentialsFor(callId);
      await _media?.renewToken(credentials.token);
    } on AppException catch (e) {
      state = state?.copyWith(error: e);
    }
  }

  /// A terminal status arrived. Tear down media, disarm this device's
  /// disconnect handler, and hold the final state briefly so the screen can
  /// show why the call ended before it closes.
  void _finish(CallModel call) {
    _ringTimer?.cancel();
    state = state?.copyWith(call: call);

    unawaited(_callSub?.cancel());
    _callSub = null;
    unawaited(_signaling.releaseCall(call.callId));
    unawaited(_releaseMedia());

    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(seconds: 2), () {
      if (state?.status.isTerminal ?? false) state = null;
    });
  }

  Future<void> _releaseMedia() async {
    final media = _media;
    _media = null;
    _mediaStarted = false;
    await _mediaSub?.cancel();
    _mediaSub = null;
    if (media != null) {
      await media.leave();
      await media.dispose();
    }
  }

  void _disposeAll() {
    _ringTimer?.cancel();
    _clearTimer?.cancel();
    unawaited(_callSub?.cancel());
    unawaited(_releaseMedia());
  }
}

final callControllerProvider =
    NotifierProvider<CallController, ActiveCall?>(CallController.new);

/// Listens for calls addressed to the signed-in user and hands them to the
/// controller.
///
/// Must be watched from the app root (not a screen) so incoming calls are
/// caught wherever the user is in the app.
final incomingCallListenerProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return;

  final sub = ref.read(signalingServiceProvider).watchIncoming(uid).listen(
    (call) {
      if (call == null) return;

      // user_calls/{uid} is written for both parties, so the caller also
      // sees their own outgoing call here. Only calls *to* us ring.
      if (call.receiverId != uid) return;
      if (call.status != CallStatus.calling) return;

      // A call node left behind by a caller that crashed before its ring
      // timeout could fire would otherwise ring forever on the next launch.
      final created = call.createdAt;
      if (created != null &&
          DateTime.now().difference(created) > AppConstants.ringTimeout) {
        return;
      }

      ref.read(callControllerProvider.notifier).presentIncoming(call);
    },
    onError: (Object _) {
      // A transient listener error must not take the app down. The stream is
      // re-established the next time the uid changes or the app restarts.
    },
  );
  ref.onDispose(sub.cancel);
});
