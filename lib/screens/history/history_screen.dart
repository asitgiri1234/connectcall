import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/call_history_entry.dart';
import '../../providers/history_providers.dart';
import '../../widgets/call_launcher.dart';
import '../../widgets/history_tile.dart';
import '../../widgets/state_views.dart';

/// Screen 9: every call this user placed or received, newest first, grouped
/// by day. Missed calls are marked in red; any row can be called back.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(callHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Calls')),
      body: historyAsync.when(
        loading: () => const LoadingView(message: 'Loading call history'),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(callHistoryProvider),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyView(
              icon: Icons.history_rounded,
              title: 'No calls yet',
              message: 'Calls you make and receive will appear here.',
            );
          }

          final items = groupHistoryByDay(entries);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(callHistoryProvider),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                if (item is String) return _DayHeader(label: item);

                final entry = item as CallHistoryEntry;
                return HistoryTile(
                  entry: entry,
                  onCallBack: () => callBack(context, ref, entry),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.textTheme.bodySmall?.color,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
