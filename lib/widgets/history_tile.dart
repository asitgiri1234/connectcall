import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../models/call_history_entry.dart';
import '../models/call_model.dart';
import '../models/user_model.dart';
import 'user_avatar.dart';

/// One call in the history list (screen 9).
///
/// Shows everything the brief asks for per record: the other person, date and
/// time, call type, direction, duration, and a missed-call indicator.
class HistoryTile extends StatelessWidget {
  const HistoryTile({super.key, required this.entry, this.onCallBack});

  final CallHistoryEntry entry;

  /// Calls this person back with the same call type. Null hides the button.
  final VoidCallback? onCallBack;

  IconData get _directionIcon {
    if (entry.isMissed) return Icons.call_missed_rounded;
    return entry.isIncoming
        ? Icons.call_received_rounded
        : Icons.call_made_rounded;
  }

  String get _semanticLabel {
    final kind = entry.type == CallType.video ? 'video call' : 'audio call';
    final when = Formatters.callTimestamp(entry.startedAt);
    final what = entry.isMissed
        ? 'Missed $kind from ${entry.peerName}'
        : entry.isIncoming
            ? 'Incoming $kind from ${entry.peerName}'
            : 'Outgoing $kind to ${entry.peerName}';
    final outcome = entry.wasAnswered
        ? 'lasted ${Formatters.duration(entry.duration)}'
        : entry.outcomeLabel;
    return '$what, $when, $outcome';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    final accent = entry.isMissed ? AppColors.decline : muted;

    return Semantics(
      label: _semanticLabel,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            UserAvatar(
              user: UserModel(
                uid: entry.peerId,
                name: entry.peerName,
                email: '',
                photoUrl: entry.peerPhotoUrl,
              ),
              radius: 23,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.peerName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: entry.isMissed ? AppColors.decline : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(_directionIcon, size: 15, color: accent),
                      const SizedBox(width: 5),
                      Icon(
                        entry.type == CallType.video
                            ? Icons.videocam_rounded
                            : Icons.call_rounded,
                        size: 14,
                        color: muted,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          Formatters.callTimestamp(entry.startedAt),
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
            const SizedBox(width: 8),
            Text(
              entry.wasAnswered
                  ? Formatters.duration(entry.duration)
                  : entry.outcomeLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: accent,
                fontWeight: entry.isMissed ? FontWeight.w600 : null,
              ),
            ),
            if (onCallBack != null) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: onCallBack,
                tooltip: 'Call ${entry.peerName} back',
                icon: Icon(
                  entry.type == CallType.video
                      ? Icons.videocam_outlined
                      : Icons.call_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Splits a newest-first history into day sections ("Today", "Yesterday",
/// "12 March") with a header string before each day's entries.
///
/// A pure function over the list, so grouping is testable without widgets.
List<Object> groupHistoryByDay(List<CallHistoryEntry> entries) {
  final items = <Object>[];
  String? currentDay;
  for (final entry in entries) {
    final day = Formatters.daySection(entry.startedAt);
    if (day != currentDay) {
      items.add(day);
      currentDay = day;
    }
    items.add(entry);
  }
  return items;
}
