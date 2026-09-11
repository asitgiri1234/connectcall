import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/call_providers.dart';
import '../../widgets/call_controls.dart';
import '../../widgets/user_avatar.dart';

/// Screen 7: remote video full screen, local preview picture-in-picture,
/// caller info on top, controls along the bottom.
///
/// Video view controllers are cached rather than created in build(). Agora
/// reports network quality every couple of seconds and each report rebuilds
/// this widget; recreating the controllers on every rebuild would tear down
/// and recreate the native video surfaces each time, visibly flickering.
/// They are only rebuilt when the engine or the remote uid actually changes.
class VideoCallView extends ConsumerStatefulWidget {
  const VideoCallView({super.key, required this.active});

  final ActiveCall active;

  @override
  ConsumerState<VideoCallView> createState() => _VideoCallViewState();
}

class _VideoCallViewState extends ConsumerState<VideoCallView> {
  RtcEngine? _engine;
  VideoViewController? _local;
  VideoViewController? _remote;
  int? _remoteUid;

  /// Keeps cached controllers in step with the current engine and remote uid.
  void _syncControllers(RtcEngine? engine, String? channel, int? remoteUid) {
    if (!identical(engine, _engine)) {
      _engine = engine;
      _local = null;
      _remote = null;
      _remoteUid = null;
    }
    if (engine == null) return;

    _local ??= VideoViewController(
      rtcEngine: engine,
      canvas: const VideoCanvas(uid: 0),
    );

    if (remoteUid != _remoteUid) {
      _remoteUid = remoteUid;
      _remote = (remoteUid == null || channel == null)
          ? null
          : VideoViewController.remote(
              rtcEngine: engine,
              canvas: VideoCanvas(uid: remoteUid),
              connection: RtcConnection(channelId: channel),
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final controller = ref.read(callControllerProvider.notifier);
    final media = controller.media;
    _syncControllers(media?.engine, media?.channelName, active.remoteRtcUid);

    final theme = Theme.of(context);
    final peer = active.peer;
    final firstName = peer.name.split(' ').first;
    final showRemote = _remote != null && active.remoteVideoOn;
    final showLocal = _local != null && active.localJoined && active.cameraOn;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Remote video, or a placeholder explaining why there is none.
        if (showRemote)
          AgoraVideoView(controller: _remote!)
        else
          _RemotePlaceholder(
            peerAvatar: UserAvatar(user: peer, radius: 56),
            message: active.remoteRtcUid == null
                ? 'Connecting...'
                : '$firstName turned off their camera',
          ),

        // Top: who and how long, over a gradient so it reads on any video.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peer.name,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (active.reconnecting)
                            const Text('Reconnecting...',
                                style: TextStyle(color: AppColors.qualityFair))
                          else if (active.inCallSince != null)
                            CallDurationText(
                              since: active.inCallSince,
                              style: const TextStyle(color: Colors.white70),
                            )
                          else
                            Text(active.status.label,
                                style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                    NetworkQualityBadge(quality: active.quality),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Local preview, picture-in-picture.
        Positioned(
          right: 16,
          top: MediaQuery.paddingOf(context).top + 96,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 108,
              height: 156,
              child: showLocal
                  ? AgoraVideoView(controller: _local!)
                  : Container(
                      color: AppColors.darkSurface,
                      child: const Icon(Icons.videocam_off_rounded,
                          color: Colors.white54),
                    ),
            ),
          ),
        ),

        // Controls.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 32, 12, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    CallControlButton(
                      icon: active.muted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      label: active.muted ? 'Unmute' : 'Mute',
                      active: active.muted,
                      onPressed: controller.toggleMute,
                    ),
                    CallControlButton(
                      icon: active.cameraOn
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      label: active.cameraOn ? 'Camera' : 'Camera off',
                      active: !active.cameraOn,
                      onPressed: controller.toggleCamera,
                    ),
                    CallControlButton(
                      icon: Icons.cameraswitch_rounded,
                      label: 'Switch',
                      // Switching a camera that is off does nothing useful.
                      onPressed: active.cameraOn ? controller.switchCamera : null,
                    ),
                    CallControlButton(
                      icon: Icons.call_end_rounded,
                      label: 'End',
                      background: AppColors.decline,
                      onPressed: controller.hangUp,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RemotePlaceholder extends StatelessWidget {
  const _RemotePlaceholder({required this.peerAvatar, required this.message});

  final Widget peerAvatar;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.callBg,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          peerAvatar,
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
