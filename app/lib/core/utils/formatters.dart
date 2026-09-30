import 'package:intl/intl.dart';

/// Short relative time for feeds: "now", "4m", "3h", "2d", "Mar 4", "Mar 4, 2024".
String timeAgo(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final local = time.toLocal();
  final diff = current.difference(local);
  if (diff.inSeconds < 45) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  if (local.year == current.year) return DateFormat('MMM d').format(local);
  return DateFormat('MMM d, y').format(local);
}

/// "Last seen 5 min ago" style text for chat headers.
String lastSeen(DateTime? time, {DateTime? now}) {
  if (time == null) return 'Offline';
  final diff = (now ?? DateTime.now()).difference(time.toLocal());
  if (diff.inMinutes < 2) return 'Active just now';
  if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
  if (diff.inDays < 7) return 'Active ${diff.inDays}d ago';
  return 'Offline';
}

/// Chat bubble timestamps: "9:41 AM".
String clockTime(DateTime time) => DateFormat('h:mm a').format(time.toLocal());

/// Chat list timestamps: time today, weekday this week, date otherwise.
String chatTime(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final local = time.toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days == 0) return DateFormat('h:mm a').format(local);
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEE').format(local);
  if (local.year == current.year) return DateFormat('d MMM').format(local);
  return DateFormat('d/M/yy').format(local);
}

/// Day separators in a conversation: "Today", "Yesterday", "Monday, 4 March".
String dayLabel(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final local = time.toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEEE').format(local);
  if (local.year == current.year) return DateFormat('EEEE, d MMMM').format(local);
  return DateFormat('d MMMM y').format(local);
}

/// "Sat, 28 Sep · 6:30 PM".
String eventWhen(DateTime start, {DateTime? end}) {
  final s = start.toLocal();
  final date = DateFormat('EEE, d MMM').format(s);
  final time = DateFormat('h:mm a').format(s);
  if (end == null) return '$date · $time';
  final e = end.toLocal();
  final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
  if (sameDay) return '$date · $time – ${DateFormat('h:mm a').format(e)}';
  return '$date, $time – ${DateFormat('EEE, d MMM').format(e)}';
}

/// "In 3 days", "Tomorrow", "Happening now", "Ended".
String eventCountdown(DateTime start, DateTime? end, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final s = start.toLocal();
  final e = (end ?? start.add(const Duration(hours: 2))).toLocal();
  if (current.isAfter(e)) return 'Ended';
  if (current.isAfter(s)) return 'Happening now';
  final today = DateTime(current.year, current.month, current.day);
  final startDay = DateTime(s.year, s.month, s.day);
  final days = startDay.difference(today).inDays;
  if (days == 0) {
    final hours = s.difference(current).inHours;
    return hours < 1 ? 'Starting soon' : 'Today';
  }
  if (days == 1) return 'Tomorrow';
  if (days < 7) return 'In $days days';
  if (days < 14) return 'Next week';
  return DateFormat('d MMM').format(s);
}

String monthShort(DateTime time) => DateFormat('MMM').format(time.toLocal()).toUpperCase();
String dayOfMonth(DateTime time) => DateFormat('d').format(time.toLocal());

/// 950, 1.2k, 12k, 1.4M.
String compactCount(num value) {
  if (value < 1000) return value.toInt().toString();
  if (value < 10000) return '${(value / 1000).toStringAsFixed(1).replaceAll('.0', '')}k';
  if (value < 1000000) return '${(value / 1000).floor()}k';
  return '${(value / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
}

/// "1 member", "12 members".
String plural(int count, String singular, [String? pluralForm]) {
  final word = count == 1 ? singular : (pluralForm ?? '${singular}s');
  return '${compactCount(count)} $word';
}

String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String ordinalYear(int year) {
  const suffixes = {1: 'st', 2: 'nd', 3: 'rd'};
  return '$year${suffixes[year] ?? 'th'} year';
}
