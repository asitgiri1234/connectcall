import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../models/call_model.dart';
import '../models/user_model.dart';
import 'user_avatar.dart';

/// One row in the contacts list: avatar, name, presence, and the two call
/// buttons the brief specifies.
///
/// Offline users are still callable. The call will ring and time out as
/// missed, which is more useful than a disabled button that gives no feedback,
/// and it matches how every real calling app behaves.
class UserTile extends StatelessWidget {
  const UserTile({
    super.key,
    required this.user,
    required this.onCall,
    this.onTap,
  });

  final UserModel user;
  final void Function(CallType type) onCall;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            UserAvatar(user: user, radius: 25, showPresence: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: user.isOnline
                              ? AppColors.online
                              : AppColors.offline,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          user.isOnline
                              ? 'Online'
                              : Formatters.lastSeen(user.lastSeen),
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _CallIconButton(
              icon: Icons.call_rounded,
              tooltip: 'Audio call ${user.name}',
              onPressed: () => onCall(CallType.audio),
            ),
            const SizedBox(width: 4),
            _CallIconButton(
              icon: Icons.videocam_rounded,
              tooltip: 'Video call ${user.name}',
              onPressed: () => onCall(CallType.video),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallIconButton extends StatelessWidget {
  const _CallIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: 0.12),
        // A 42pt target keeps the two call buttons comfortably tappable
        // without the row growing taller than the avatar.
        minimumSize: const Size(42, 42),
        shape: const CircleBorder(),
      ),
    );
  }
}
