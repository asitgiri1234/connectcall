import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../models/call_history_entry.dart';
import '../models/call_model.dart';
import '../models/user_model.dart';
import '../providers/auth_providers.dart';
import '../providers/call_providers.dart';
import '../providers/connectivity_providers.dart';
import '../providers/user_providers.dart';
import '../services/permission_service.dart';

/// The one entry point every call button in the app goes through.
///
/// Centralised so that starting a call behaves identically from Home,
/// Contacts or call history. Navigation is deliberately not here: when the
/// controller's state changes, the root listener in main.dart opens the call
/// screen. This function only decides whether the call can start, and
/// explains clearly when it cannot.
Future<void> launchCall(
  BuildContext context,
  WidgetRef ref, {
  required UserModel callee,
  required CallType type,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  // 1. Connectivity. The database queues writes while offline rather than
  //    failing them, so without this check the call would sit silently.
  if (ref.read(firebaseConnectedProvider).value == false) {
    messenger.showSnackBar(const SnackBar(
      content: Text('No internet connection. Check your network and try again.'),
    ));
    return;
  }

  // 2. An offline callee can still be called (they may come back online
  //    while it rings), but the user should know it is unlikely to connect.
  if (!callee.isOnline) {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${callee.name} is offline'),
        content: const Text(
          'They will only get your call if they open ConnectCall while it '
          'is ringing. It will be recorded as a missed call otherwise.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Call anyway'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
  }

  final me = ref.read(currentUserProvider).value;
  if (me == null) {
    messenger.showSnackBar(const SnackBar(
      content: Text('Your profile is still loading. Try again in a moment.'),
    ));
    return;
  }

  final result = await ref
      .read(callControllerProvider.notifier)
      .startCall(me: me, callee: callee, type: type);
  if (!context.mounted) return;

  switch (result) {
    case CallStarted():
      // The call screen opens from the controller state change.
      break;
    case CallBlockedByPermission(:final check):
      await showPermissionDialog(
        context,
        ref,
        check,
        onRetry: () => launchCall(context, ref, callee: callee, type: type),
      );
    case CallCouldNotStart(:final error):
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
}

/// Calls back the other person in a history entry, with the same call type.
///
/// Uses their *live* profile when it is loaded, so the offline warning in
/// [launchCall] reflects whether they are online now rather than whatever was
/// true when the call was recorded.
Future<void> callBack(
  BuildContext context,
  WidgetRef ref,
  CallHistoryEntry entry,
) {
  final live = ref
      .read(usersProvider)
      .value
      ?.where((user) => user.uid == entry.peerId)
      .firstOrNull;
  final callee = live ??
      UserModel(
        uid: entry.peerId,
        name: entry.peerName,
        email: '',
        photoUrl: entry.peerPhotoUrl,
      );
  return launchCall(context, ref, callee: callee, type: entry.type);
}

/// Explains a refused permission, with the right way forward for each case.
///
/// A normal denial offers "Try again", which re-shows the system prompt. A
/// permanent denial offers "Open Settings" instead, because the system prompt
/// will never appear again and a retry button would silently do nothing.
Future<void> showPermissionDialog(
  BuildContext context,
  WidgetRef ref,
  PermissionCheck check, {
  VoidCallback? onRetry,
}) {
  final permanent = check.outcome == PermissionOutcome.permanentlyDenied;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(
        check.missing.contains(CallPermission.camera)
            ? Icons.videocam_off_rounded
            : Icons.mic_off_rounded,
        color: AppColors.decline,
      ),
      title: const Text('Permission needed'),
      content: Text(check.message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Not now'),
        ),
        if (permanent)
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(permissionServiceProvider).openSettings();
            },
            child: const Text('Open Settings'),
          )
        else if (onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onRetry();
            },
            child: const Text('Try again'),
          ),
      ],
    ),
  );
}
