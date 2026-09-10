import 'package:intl/intl.dart';

/// Display formatting helpers. Pure functions, so they are trivially
/// unit-testable and carry no dependency on the widget tree.
class Formatters {
  const Formatters._();

  /// Call duration as mm:ss, or h:mm:ss once past an hour.
  ///
  ///   90s   -> "01:30"
  ///   3661s -> "1:01:01"
  static String duration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  /// Relative day plus clock time, matching the call history spec:
  /// "Today, 11:45 AM" / "Yesterday, 6:20 PM" / "12 Mar, 6:20 PM".
  static String callTimestamp(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(time.year, time.month, time.day);
    final clock = DateFormat('h:mm a').format(time);

    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today, $clock';
    if (diff == 1) return 'Yesterday, $clock';
    if (diff < 7) return '${DateFormat('EEEE').format(time)}, $clock';
    if (time.year == now.year) {
      return '${DateFormat('d MMM').format(time)}, $clock';
    }
    return '${DateFormat('d MMM yyyy').format(time)}, $clock';
  }

  /// Section header used to group the call history list by day.
  static String daySection(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(time.year, time.month, time.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (time.year == now.year) return DateFormat('d MMMM').format(time);
    return DateFormat('d MMMM yyyy').format(time);
  }

  /// Up to two initials for the avatar fallback when a user has no photo.
  static String initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// "last seen" line for an offline user.
  static String lastSeen(DateTime? time) {
    if (time == null) return 'Offline';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Last seen yesterday';
    return 'Last seen ${DateFormat('d MMM').format(time)}';
  }
}
