import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_exception.dart';
import '../../providers/call_providers.dart';
import 'audio_call_view.dart';
import 'incoming_call_view.dart';
import 'video_call_view.dart';

/// The single full-screen call route (screens 6, 7 and 8).
///
/// Holds no call logic. It reads [callControllerProvider] and shows the view
/// for the current state:
///
///  - an incoming call still ringing  -> [IncomingCallView]
///  - a live video call               -> [VideoCallView]
///  - everything else (calling, ringing, a live audio call, and the brief
///    "Call ended" / "Declined" moment after any call) -> [AudioCallView]
///
/// Opening and closing this route is done by the listener in main.dart, never
/// here, so the screen cannot drift out of sync with the controller.
class CallScreen extends ConsumerWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Surface controller errors once each, then clear them.
    ref.listen<AppException?>(
      callControllerProvider.select((call) => call?.error),
      (previous, next) {
        if (next == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.message)),
        );
        ref.read(callControllerProvider.notifier).clearError();
      },
    );

    final active = ref.watch(callControllerProvider);

    final Widget body;
    if (active == null) {
      // Only visible for the frame between the call clearing and the route
      // popping.
      body = const SizedBox.shrink();
    } else if (active.isIncomingRinging) {
      body = IncomingCallView(active: active);
    } else if (active.isVideo && active.status.isActive) {
      body = VideoCallView(active: active);
    } else {
      body = AudioCallView(active: active);
    }

    return PopScope(
      // A call in progress ends when someone presses End, not through an
      // accidental back gesture.
      canPop: active == null || active.status.isTerminal,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColors.callBg,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(body.runtimeType),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
