import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/call_providers.dart';
import '../../widgets/call_controls.dart';
import '../../widgets/call_launcher.dart';

/// Screen 8: someone is calling. Decline or Accept.
///
/// If the caller cancels or the ring times out, the controller sees the
/// status change on the shared call node and this view is replaced by the
/// "Missed call" state, then closed. Nothing here has to handle that case.
class IncomingCallView extends ConsumerWidget {
  const IncomingCallView({super.key, required this.active});

  final ActiveCall active;

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(callControllerProvider.notifier).accept();
    if (!context.mounted) return;

    switch (result) {
      case CallStarted():
        break;
      case CallBlockedByPermission(:final check):
        await showPermissionDialog(
          context,
          ref,
          check,
          onRetry: () => _accept(context, ref),
        );
      case CallCouldNotStart(:final error):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final peer = active.peer;
    final controller = ref.read(callControllerProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              active.isVideo ? 'Incoming video call' : 'Incoming audio call',
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Text(
              peer.name,
              style: theme.textTheme.displaySmall?.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            PulsingAvatar(user: peer, pulsing: true, radius: 72),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallControlButton(
                  icon: Icons.call_end_rounded,
                  label: 'Decline',
                  background: AppColors.decline,
                  size: 72,
                  onPressed: controller.decline,
                ),
                CallControlButton(
                  icon: active.isVideo
                      ? Icons.videocam_rounded
                      : Icons.call_rounded,
                  label: 'Accept',
                  background: AppColors.accept,
                  size: 72,
                  onPressed: () => _accept(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
