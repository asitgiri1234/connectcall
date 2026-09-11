import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../core/config/env.dart';
import '../core/utils/app_exception.dart';
import 'agora_token_provider.dart';

/// Coarse connection quality, as shown in the call screen's indicator.
enum NetworkQuality { unknown, good, fair, poor }

/// The media connection's state, reduced to what the UI can act on.
enum MediaConnectionState { connecting, connected, reconnecting, failed, disconnected }

/// Something that happened in the media layer, translated out of Agora's
/// vocabulary so nothing above this file imports the Agora SDK's enums.
sealed class MediaEvent {
  const MediaEvent();
}

/// This device joined the channel.
class JoinedChannel extends MediaEvent {
  const JoinedChannel();
}

/// The other participant's media arrived. This, not the database's
/// "connected" status, is the moment the call is truly live.
class RemoteUserJoined extends MediaEvent {
  const RemoteUserJoined(this.rtcUid);
  final int rtcUid;
}

/// The other participant left. [dropped] distinguishes a lost connection from
/// a deliberate hang-up, which drives "Disconnected" versus "Call ended".
class RemoteUserLeft extends MediaEvent {
  const RemoteUserLeft(this.rtcUid, {required this.dropped});
  final int rtcUid;
  final bool dropped;
}

class ConnectionChanged extends MediaEvent {
  const ConnectionChanged(this.state, {this.error});
  final MediaConnectionState state;

  /// Set when [state] is [MediaConnectionState.failed], explaining why.
  final AppException? error;
}

class NetworkQualityChanged extends MediaEvent {
  const NetworkQualityChanged(this.quality);
  final NetworkQuality quality;
}

/// The other participant turned their camera on or off.
class RemoteVideoChanged extends MediaEvent {
  const RemoteVideoChanged(this.rtcUid, {required this.enabled});
  final int rtcUid;
  final bool enabled;
}

/// The token will expire shortly; the caller should fetch a fresh one and
/// pass it to [AgoraService.renewToken].
class TokenWillExpire extends MediaEvent {
  const TokenWillExpire();
}

class MediaError extends MediaEvent {
  const MediaError(this.error);
  final AppException error;
}

/// A thin wrapper around the Agora RTC engine for one 1-to-1 call.
///
/// Its job is translation, not policy: it turns Agora's callbacks into
/// [MediaEvent]s and exposes the handful of controls the call screens need.
/// Deciding what an event *means* for the call (for example, that a remote
/// drop should end it) belongs to the call controller, which also watches the
/// signaling node. Keeping the two apart means the media layer can be swapped
/// or faked without touching call logic.
///
/// Lifecycle: [initialize] once, [join], [leave], then [dispose]. A fresh
/// instance is used per call, so no state leaks from one call into the next.
class AgoraService {
  RtcEngine? _engine;
  RtcEngineEventHandler? _handler;
  final _events = StreamController<MediaEvent>.broadcast();

  String? _channelName;
  bool _videoCall = false;

  Stream<MediaEvent> get events => _events.stream;

  /// Exposed for the video views, which must render against the same engine.
  RtcEngine? get engine => _engine;
  String? get channelName => _channelName;

  Future<void> initialize() async {
    if (_engine != null) return;
    if (!Env.hasAgoraAppId) {
      throw const AppException(
        Env.missingAppIdMessage,
        code: 'agora-no-app-id',
        isRecoverable: false,
      );
    }

    final engine = createAgoraRtcEngine();
    try {
      await engine.initialize(const RtcEngineContext(
        appId: Env.agoraAppId,
        // Communication profile: every participant can publish, tuned for
        // low-latency two-way talk rather than one-to-many broadcast.
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));
    } on AgoraRtcException catch (e) {
      await engine.release();
      throw AppException(
        'Could not start the calling engine.',
        code: 'agora-init-${e.code}',
      );
    }

    _handler = RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) =>
          _emit(const JoinedChannel()),
      onRejoinChannelSuccess: (connection, elapsed) =>
          _emit(const ConnectionChanged(MediaConnectionState.connected)),
      onUserJoined: (connection, remoteUid, elapsed) =>
          _emit(RemoteUserJoined(remoteUid)),
      onUserOffline: (connection, remoteUid, reason) => _emit(RemoteUserLeft(
            remoteUid,
            dropped: reason == UserOfflineReasonType.userOfflineDropped,
          )),
      onConnectionStateChanged: _onConnectionStateChanged,
      onNetworkQuality: (connection, remoteUid, txQuality, rxQuality) {
        // remoteUid 0 is this device's own link. The worse of the two
        // directions is what the user actually experiences.
        if (remoteUid != 0) return;
        _emit(NetworkQualityChanged(
          _worse(_mapQuality(txQuality), _mapQuality(rxQuality)),
        ));
      },
      onRemoteVideoStateChanged:
          (connection, remoteUid, state, reason, elapsed) {
        if (state == RemoteVideoState.remoteVideoStateStopped ||
            state == RemoteVideoState.remoteVideoStateFailed) {
          _emit(RemoteVideoChanged(remoteUid, enabled: false));
        } else if (state == RemoteVideoState.remoteVideoStateDecoding) {
          _emit(RemoteVideoChanged(remoteUid, enabled: true));
        }
      },
      onTokenPrivilegeWillExpire: (connection, token) =>
          _emit(const TokenWillExpire()),
      onError: (err, msg) {
        final mapped = _mapError(err);
        if (mapped != null) _emit(MediaError(mapped));
      },
    );
    engine.registerEventHandler(_handler!);
    _engine = engine;
  }

  /// Joins the call's channel with credentials from the token server.
  ///
  /// Audio calls start on the earpiece and video calls on the loudspeaker,
  /// matching what people expect from a phone.
  Future<void> join({
    required AgoraCredentials credentials,
    required bool video,
  }) async {
    final engine = _requireEngine();
    _channelName = credentials.channelName;
    _videoCall = video;

    try {
      await engine.enableAudio();
      if (video) {
        await engine.enableVideo();
        await engine.startPreview();
      } else {
        await engine.disableVideo();
      }
      await engine.setDefaultAudioRouteToSpeakerphone(video);

      await engine.joinChannel(
        token: credentials.token,
        channelId: credentials.channelName,
        uid: credentials.rtcUid,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          publishCameraTrack: video,
          autoSubscribeAudio: true,
          autoSubscribeVideo: video,
        ),
      );
    } on AgoraRtcException catch (e) {
      throw AppException(
        'Could not connect the call.',
        code: 'agora-join-${e.code}',
      );
    }
  }

  Future<void> setMuted(bool muted) =>
      _safely(() => _requireEngine().muteLocalAudioStream(muted));

  Future<void> setSpeakerOn(bool on) =>
      _safely(() => _requireEngine().setEnableSpeakerphone(on));

  /// Turns the camera off entirely rather than just stopping the stream, so
  /// the device's camera indicator light goes out too: "camera off" should
  /// mean the camera is actually off.
  Future<void> setCameraEnabled(bool enabled) async {
    if (!_videoCall) return;
    final engine = _requireEngine();
    await _safely(() => engine.enableLocalVideo(enabled));
    await _safely(() => engine.muteLocalVideoStream(!enabled));
  }

  Future<void> switchCamera() {
    if (!_videoCall) return Future.value();
    return _safely(() => _requireEngine().switchCamera());
  }

  Future<void> renewToken(String token) =>
      _safely(() => _requireEngine().renewToken(token));

  Future<void> leave() async {
    final engine = _engine;
    if (engine == null) return;
    await _safely(() => engine.leaveChannel());
    if (_videoCall) await _safely(() => engine.stopPreview());
    _channelName = null;
  }

  /// Releases the native engine. Must be called exactly once per instance;
  /// the camera and microphone stay claimed until it is.
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      if (_handler != null) engine.unregisterEventHandler(_handler!);
      await _safely(() => engine.release());
    }
    _handler = null;
    await _events.close();
  }

  // --- internals ------------------------------------------------------------

  RtcEngine _requireEngine() {
    final engine = _engine;
    if (engine == null) {
      throw const AppException('The calling engine is not ready.');
    }
    return engine;
  }

  void _emit(MediaEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// Control calls such as mute should never crash an active call. A failure
  /// is reported as an event so the UI can surface it, and the call goes on.
  Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } on AgoraRtcException catch (e) {
      _emit(MediaError(AppException(
        'That control did not respond. Try again.',
        code: 'agora-control-${e.code}',
      )));
    }
  }

  void _onConnectionStateChanged(
    RtcConnection connection,
    ConnectionStateType state,
    ConnectionChangedReasonType reason,
  ) {
    switch (state) {
      case ConnectionStateType.connectionStateConnecting:
        _emit(const ConnectionChanged(MediaConnectionState.connecting));
      case ConnectionStateType.connectionStateConnected:
        _emit(const ConnectionChanged(MediaConnectionState.connected));
      case ConnectionStateType.connectionStateReconnecting:
        // Agora retries on its own after a network blip. The UI shows
        // "Reconnecting..." and the call continues if it recovers.
        _emit(const ConnectionChanged(MediaConnectionState.reconnecting));
      case ConnectionStateType.connectionStateFailed:
        _emit(ConnectionChanged(
          MediaConnectionState.failed,
          error: _mapFailureReason(reason),
        ));
      case ConnectionStateType.connectionStateDisconnected:
        _emit(const ConnectionChanged(MediaConnectionState.disconnected));
    }
  }

  static AppException _mapFailureReason(ConnectionChangedReasonType reason) {
    return switch (reason) {
      ConnectionChangedReasonType.connectionChangedInvalidToken ||
      ConnectionChangedReasonType.connectionChangedTokenExpired =>
        const AppException(
          'The call could not be authorised. Please try again.',
          code: 'agora-token',
        ),
      ConnectionChangedReasonType.connectionChangedInvalidAppId ||
      ConnectionChangedReasonType.connectionChangedInconsistentAppid =>
        const AppException(
          'Calling is misconfigured on this build.',
          code: 'agora-app-id',
          isRecoverable: false,
        ),
      ConnectionChangedReasonType.connectionChangedBannedByServer ||
      ConnectionChangedReasonType.connectionChangedRejectedByServer =>
        const AppException(
          'The calling service refused the connection.',
          code: 'agora-rejected',
        ),
      _ => const AppException(
          'The call connection failed. Check your network and try again.',
          code: 'agora-connection-failed',
        ),
    };
  }

  static AppException? _mapError(ErrorCodeType err) {
    return switch (err) {
      ErrorCodeType.errInvalidToken || ErrorCodeType.errTokenExpired =>
        const AppException(
          'The call could not be authorised. Please try again.',
          code: 'agora-token',
        ),
      ErrorCodeType.errInvalidAppId => const AppException(
          'Calling is misconfigured on this build.',
          code: 'agora-app-id',
          isRecoverable: false,
        ),
      // Other codes are mostly transient and already reflected through the
      // connection state, so they are not surfaced twice.
      _ => null,
    };
  }

  static NetworkQuality _mapQuality(QualityType quality) {
    return switch (quality) {
      QualityType.qualityExcellent || QualityType.qualityGood =>
        NetworkQuality.good,
      QualityType.qualityPoor => NetworkQuality.fair,
      QualityType.qualityBad ||
      QualityType.qualityVbad ||
      QualityType.qualityDown =>
        NetworkQuality.poor,
      _ => NetworkQuality.unknown,
    };
  }

  static NetworkQuality _worse(NetworkQuality a, NetworkQuality b) {
    if (a == NetworkQuality.unknown) return b;
    if (b == NetworkQuality.unknown) return a;
    return a.index >= b.index ? a : b;
  }
}
