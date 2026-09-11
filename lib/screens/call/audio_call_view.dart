import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/call_model.dart';
import '../../providers/call_providers.dart';
import '../../widgets/call_controls.dart';

/// Screen 6, plus every state that is not a live video call or an unanswered
/// incoming call: calling, ringing, the live audio call, and the brief
/// "Call ended" / "Declined" / "No answer" moment after any call.
class AudioCallView extends ConsumerWidget {
  const AudioCallView({super.key, required this.active});

  final ActiveCall active;

  /// Status line wording depends on which side you are on: "No answer" is
  /// right for the caller, "Missed call" for the callee.
  String _statusText() {
    final status = active.status;
    if (status == CallStatus.missed && !active.isCaller) return 'Missed call';
    if (status == CallStatus.rejected && !active.isCaller) return 'Call declined';
    if (active.reconnecting) return 'Reconnecting...';
    return status.label;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(callControllerProvider.notifier);
    final peer = active.peer;
    final status = active.status;

    final showTimer =
        status.isActive && active.inCallSince != null && !active.reconnecting;
    final statusStyle = theme.textTheme.titleMedium?.copyWith(
      color: status.isTerminal ? AppColors.muted : Colors.white70,
      fontWeight: FontWeight.w500,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  active.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  size: 16,
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  active.call.type.label,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                ),
                const Spacer(),
                if (status.isActive) NetworkQualityBadge(quality: active.quality),
              ],
            ),
            const Spacer(),
            PulsingAvatar(user: peer, pulsing: status.isRinging, radius: 64),
            const SizedBox(height: 24),
            Text(
              peer.name,
              style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            if (showTimer)
              CallDurationText(since: active.inCallSince, style: statusStyle)
            else
              Text(_statusText(), style: statusStyle),
            const Spacer(),
            _Controls(active: active, controller: controller),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.active, required this.controller});

  final ActiveCall active;
  final CallController controller;

  @override
  Widget build(BuildContext context) {
    final status = active.status;

    // Call over: no controls, the screen closes on its own shortly.
    if (status.isTerminal) return const SizedBox(height: 96);

    // Still ringing: the only sensible action is to give up.
    if (status.isRinging) {
      return CallControlButton(
        icon: Icons.call_end_rounded,
        label: 'Cancel',
        background: AppColors.decline,
        size: 72,
        onPressed: controller.hangUp,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        CallControlButton(
          icon: active.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: active.muted ? 'Unmute' : 'Mute',
          active: active.muted,
          onPressed: controller.toggleMute,
        ),
        CallControlButton(
          icon: Icons.volume_up_rounded,
          label: 'Speaker',
          active: active.speakerOn,
          onPressed: controller.toggleSpeaker,
        ),
        CallControlButton(
          icon: Icons.call_end_rounded,
          label: 'End',
          background: AppColors.decline,
          onPressed: controller.hangUp,
        ),
      ],
    );
  }
}
