import '../models/group_model.dart';

class AttendanceTimingResult {
  final bool isAllowed;
  final String? message;
  final DateTime? groupDateTime;
  final int? minutesRemaining;

  const AttendanceTimingResult({
    required this.isAllowed,
    this.message,
    this.groupDateTime,
    this.minutesRemaining,
  });
}

class AttendanceTimingGuard {
  static const List<String> arabicDays = [
    'الاثنين', // 1
    'الثلاثاء', // 2
    'الأربعاء', // 3
    'الخميس', // 4
    'الجمعة', // 5
    'السبت', // 6
    'الأحد', // 7
  ];

  static String getArabicDayName(int weekday) {
    return arabicDays[(weekday - 1) % 7];
  }

  /// Checks whether attendance can be taken for a specific group right now.
  /// Allowed starting 5 minutes before the session starts, and all through the rest of the day.
  static AttendanceTimingResult checkGroupAttendanceAllowed(GroupModel group, {DateTime? customNow}) {
    final now = customNow ?? DateTime.now();
    final todayArabic = getArabicDayName(now.weekday);

    // 1. Check if group is scheduled for today
    bool isToday = false;
    if (group.days.isNotEmpty && group.days.contains(todayArabic)) {
      isToday = true;
    } else if (group.schedule.isNotEmpty && group.schedule.contains(todayArabic)) {
      isToday = true;
    }

    // If schedule is completely unspecified, allow taking attendance gracefully
    if (group.schedule.isEmpty && group.days.isEmpty) {
      return const AttendanceTimingResult(isAllowed: true);
    }

    if (!isToday) {
      return AttendanceTimingResult(
        isAllowed: false,
        message: 'اليوم ليس ضمن جدول هذه المجموعة ($todayArabic). موعد المجموعة: ${group.schedule}',
      );
    }

    // 2. Extract start time for today
    String timeStr = group.startTime;

    // Check if per-day time format: "السبت (03:00 PM - 04:00 PM)" or "السبت (3:30 م - 4:30 م)"
    final dayRegex = RegExp('$todayArabic\\s*\\(([^-\\)]+)');
    final match = dayRegex.firstMatch(group.schedule);
    if (match != null) {
      timeStr = match.group(1)?.trim() ?? group.startTime;
    } else {
      // Look for time pattern inside schedule: e.g. "5:30 م" or "04:00 PM"
      final timeRegex = RegExp(r'(\d{1,2}:\d{2}\s*(?:ص|م|AM|PM|am|pm)?)');
      final timeMatch = timeRegex.firstMatch(group.schedule);
      if (timeMatch != null && group.startTime.isEmpty) {
        timeStr = timeMatch.group(1) ?? '03:00 PM';
      }
    }

    final parsedTime = _parseTimeOfDay(timeStr);
    if (parsedTime == null) {
      // If time cannot be parsed, don't block teacher
      return const AttendanceTimingResult(isAllowed: true);
    }

    final groupStartTime = DateTime(
      now.year,
      now.month,
      now.day,
      parsedTime.hour,
      parsedTime.minute,
    );

    // Allowed 5 minutes before group start time
    final allowedStartTime = groupStartTime.subtract(const Duration(minutes: 5));

    if (now.isBefore(allowedStartTime)) {
      final diff = allowedStartTime.difference(now);
      final minutesLeft = diff.inMinutes + 1;
      return AttendanceTimingResult(
        isAllowed: false,
        message: 'غير مسموح ببدء التحضير إلا قبل موعد المجموعة بـ 5 دقائق فقط.\nموعد الحصة: ${_formatTimeArabic(parsedTime)}\nمتبقي على إتاحة التحضير: $minutesLeft دقيقة',
        groupDateTime: groupStartTime,
        minutesRemaining: minutesLeft,
      );
    }

    return AttendanceTimingResult(
      isAllowed: true,
      groupDateTime: groupStartTime,
    );
  }

  static ({int hour, int minute})? _parseTimeOfDay(String str) {
    if (str.trim().isEmpty) return null;
    try {
      final clean = str.trim();
      final isPM = clean.contains('م') || clean.toUpperCase().contains('PM');
      final isAM = clean.contains('ص') || clean.toUpperCase().contains('AM');

      final digitsMatch = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(clean);
      if (digitsMatch != null) {
        int h = int.parse(digitsMatch.group(1)!);
        final int m = int.parse(digitsMatch.group(2)!);

        if (isPM && h < 12) h += 12;
        if (isAM && h == 12) h = 0;
        return (hour: h, minute: m);
      }
    } catch (_) {}
    return null;
  }

  static String _formatTimeArabic(({int hour, int minute}) t) {
    final isPM = t.hour >= 12;
    var h = t.hour % 12;
    if (h == 0) h = 12;
    final m = t.minute.toString().padLeft(2, '0');
    final period = isPM ? 'مساءً' : 'صباحاً';
    return '$h:$m $period';
  }
}
