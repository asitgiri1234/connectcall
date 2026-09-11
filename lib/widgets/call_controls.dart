import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../models/user_model.dart';
import '../services/agora_service.dart';
import 'user_avatar.dart';

/// A round call-screen button with a label underneath.
///
/// [active] shows a toggled-on state (for example, muted) as a filled white
/// circle. [background] overrides the colour entirely, for End and Accept,
/// whose meaning comes from their colour.
class CallControlButton extends StatelessWidget {
  const CallControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.background,
    this.size = 64,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fill = background ?? (active ? Colors.white : AppColors.callControl);
    final iconColor =
        background != null ? Colors.white : (active ? AppColors.callBg : Colors.white);
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      // Toggle buttons announce their state to screen readers; End and
      // Accept are plain actions.
      toggled: background == null ? active : null,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: enabled ? fill : fill.withValues(alpha: 0.5),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, color: iconColor, size: size * 0.42),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// A live mm:ss counter from [since].
///
/// Owns its own one-second timer so that ticking rebuilds only this text,
/// not the whole call screen and certainly not the video views.
class CallDurationText extends StatefulWidget {
  const CallDurationText({super.key, required this.since, this.style});

  final DateTime? since;
  final TextStyle? style;

  @override
  State<CallDurationText> createState() => _CallDurationTextState();
}

class _CallDurationTextState extends State<CallDurationText> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final since = widget.since;
    final elapsed =
        since == null ? Duration.zero : DateTime.now().difference(since);
    return Text(
      Formatters.duration(elapsed.isNegative ? Duration.zero : elapsed),
      style: widget.style,
    );
  }
}

/// Good / Fair / Poor connection indicator (bonus feature 9).
class NetworkQualityBadge extends StatelessWidget {
  const NetworkQualityBadge({super.key, required this.quality});

  final NetworkQuality quality;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (quality) {
      NetworkQuality.good => ('Good', AppColors.qualityGood, Icons.signal_cellular_alt),
      NetworkQuality.fair => ('Fair', AppColors.qualityFair, Icons.signal_cellular_alt_2_bar),
      NetworkQuality.poor => ('Poor', AppColors.qualityPoor, Icons.signal_cellular_alt_1_bar),
      NetworkQuality.unknown => ('', Colors.transparent, Icons.signal_cellular_alt),
    };
    if (quality == NetworkQuality.unknown) return const SizedBox.shrink();

    return Semantics(
      label: 'Connection quality: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A large avatar that pulses while a call is ringing, so the screen reads
/// as "waiting" at a glance.
class PulsingAvatar extends StatefulWidget {
  const PulsingAvatar({
    super.key,
    required this.user,
    required this.pulsing,
    this.radius = 64,
  });

  final UserModel user;
  final bool pulsing;
  final double radius;

  @override
  State<PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _controller.repeat();
  }

  @override
  void didUpdateWidget(PulsingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    return SizedBox(
      width: size * 1.5,
      height: size * 1.5,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.pulsing)
                Container(
                  width: size * (1 + 0.5 * t),
                  height: size * (1 + 0.5 * t),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.18 * (1 - t)),
                  ),
                ),
              child!,
            ],
          );
        },
        child: UserAvatar(user: widget.user, radius: widget.radius),
      ),
    );
  }
}
