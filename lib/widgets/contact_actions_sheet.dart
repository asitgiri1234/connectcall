import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/app_exception.dart';
import '../core/utils/formatters.dart';
import '../models/call_model.dart';
import '../models/user_model.dart';
import '../providers/auth_providers.dart';
import '../providers/user_providers.dart';
import 'call_launcher.dart';
import 'user_avatar.dart';

/// Actions for one contact, opened by tapping their row: call them, or block
/// them. Blocking asks for confirmation first, because it silently stops
/// their calls from ringing.
Future<void> showContactActions(
  BuildContext context,
  WidgetRef ref,
  UserModel user,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(user: user, radius: 32, showPresence: true),
            const SizedBox(height: 10),
            Text(user.name, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              user.isOnline ? 'Online' : Formatters.lastSeen(user.lastSeen),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.call_rounded),
              title: const Text('Audio call'),
              onTap: () {
                Navigator.pop(sheetContext);
                launchCall(context, ref, callee: user, type: CallType.audio);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_rounded),
              title: const Text('Video call'),
              onTap: () {
                Navigator.pop(sheetContext);
                launchCall(context, ref, callee: user, type: CallType.video);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded, color: AppColors.decline),
              title: Text(
                'Block ${user.name}',
                style: const TextStyle(color: AppColors.decline),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                confirmBlock(context, ref, user);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Asks before blocking, then blocks and offers an immediate undo.
Future<void> confirmBlock(
  BuildContext context,
  WidgetRef ref,
  UserModel user,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Block ${user.name}?'),
      content: const Text(
        'They will disappear from your contacts and their calls will not '
        'ring. They are not told they have been blocked. You can unblock them '
        'from your profile at any time.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.decline),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final uid = ref.read(currentUidProvider);
  if (uid == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(blockServiceProvider);

  try {
    await service.block(uid, user.uid);
    messenger.showSnackBar(SnackBar(
      content: Text('${user.name} blocked'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => service.unblock(uid, user.uid),
      ),
    ));
  } on AppException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
