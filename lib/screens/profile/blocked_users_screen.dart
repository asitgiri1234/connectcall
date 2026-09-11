import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_exception.dart';
import '../../providers/auth_providers.dart';
import '../../providers/user_providers.dart';
import '../../widgets/state_views.dart';
import '../../widgets/user_avatar.dart';

/// Everyone the signed-in user has blocked, each with an Unblock button.
class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  Future<void> _unblock(
    BuildContext context,
    WidgetRef ref,
    String blockedUid,
    String name,
  ) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(blockServiceProvider).unblock(uid, blockedUid);
      messenger.showSnackBar(SnackBar(content: Text('$name unblocked')));
    } on AppException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(blockedIdsProvider);
    final blockedUsers = ref.watch(blockedUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked contacts')),
      body: blockedAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(blockedIdsProvider),
        ),
        data: (_) {
          if (blockedUsers.isEmpty) {
            return const EmptyView(
              icon: Icons.block_rounded,
              title: 'Nobody blocked',
              message: 'People you block will appear here so you can unblock '
                  'them later.',
            );
          }
          return ListView.separated(
            itemCount: blockedUsers.length,
            separatorBuilder: (_, index) => const Divider(indent: 76),
            itemBuilder: (context, index) {
              final user = blockedUsers[index];
              return ListTile(
                leading: UserAvatar(user: user, radius: 22),
                title: Text(user.name),
                subtitle: Text(user.email),
                trailing: TextButton(
                  onPressed: () => _unblock(context, ref, user.uid, user.name),
                  child: const Text('Unblock'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
