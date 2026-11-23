import 'package:flutter/services.dart';
import '../models/group_model.dart';
import '../models/school_period_model.dart';
import 'notification_service.dart';

class AlarmService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.teacher_center/alarm',
  );

  /// Convert Arabic weekday name to Android Calendar day integer
  static int convertWeekdayToCalendarDay(String arabicWeekday) {
    switch (arabicWeekday.trim()) {
      case 'الأحد':
        return 1; // Calendar.SUNDAY
      case 'الإثنين':
        return 2; // Calendar.MONDAY
      case 'الثلاثاء':
        return 3; // Calendar.TUESDAY
      case 'الأربعاء':
        return 4; // Calendar.WEDNESDAY
      case 'الخميس':
        return 5; // Calendar.THURSDAY
      case 'الجمعة':
        return 6; // Calendar.FRIDAY
      case 'السبت':
        return 7; // Calendar.SATURDAY
      default:
        return 1;
    }
  }

  /// Set a single alarm in the phone's native Clock/Alarm app
  static Future<bool> setAlarm({
    required int hour,
    required int minutes,
    required String message,
    bool skipUi = false,
    List<int>? days,
    String? ringtone,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('setAlarm', {
        'hour': hour,
        'minutes': minutes,
        'message': message,
        'skipUi': skipUi,
        if (days != null && days.isNotEmpty) 'days': days,
        if (ringtone != null && ringtone.isNotEmpty) 'ringtone': ringtone,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Label prefix used to identify automatically scheduled timetable alarms.
  /// Used to purge previous auto-alarms without touching any user-set manual alarms.
  static const String autoAlarmPrefix = '⏰ [تلقائي]';

  /// Open the phone's Clock app to view and manage alarms
  static Future<bool> showAlarms() async {
    try {
      final res = await _channel.invokeMethod<bool>('showAlarms');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Dismiss an alarm by label or query (Android ACTION_DISMISS_ALARM)
  static Future<bool> dismissAlarm({String? message}) async {
    try {
      final res = await _channel.invokeMethod<bool>('dismissAlarm', {
        if (message != null) 'message': message,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Test device alarm sound directly for 4 seconds
  static Future<bool> testAlarmSound() async {
    try {
      final res = await _channel.invokeMethod<bool>('testAlarmSound');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Get all device system ringtones, alarms, and notifications
  static Future<List<Map<String, String>>> getDeviceRingtones() async {
    try {
      final List<dynamic>? res = await _channel.invokeMethod('getDeviceRingtones');
      if (res == null) return [];
      return res.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return {
          'title': (map['title'] ?? '').toString(),
          'uri': (map['uri'] ?? '').toString(),
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Play custom audio file, built-in toneId, or ringtone URI with auto-stop duration
  static Future<bool> playAudio({
    String? toneId,
    String? uri,
    String? filePath,
    int durationMs = 6000,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('playAlarmSound', {
        if (toneId != null && toneId.isNotEmpty) 'toneId': toneId,
        if (uri != null && uri.isNotEmpty) 'uri': uri,
        if (filePath != null && filePath.isNotEmpty) 'filePath': filePath,
        'durationMs': durationMs,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stop currently playing audio preview immediately
  static Future<bool> stopAudio() async {
    try {
      final res = await _channel.invokeMethod<bool>('stopAlarmSound');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Dismiss all timetable alarms silently and automatically in-app (no external Clock app popup)
  static Future<int> dismissAllAlarms() async {
    return await NotificationService.cancelTimetableAlarms();
  }

  /// Dismiss alarms for today or a specific day silently and automatically in-app
  static Future<int> dismissDayAlarms({String? dayName}) async {
    return await NotificationService.cancelTimetableAlarms(dayName: dayName);
  }

  static Future<int> dismissDateAlarms(DateTime date) {
    return NotificationService.cancelTimetableAlarms(scheduledDate: date);
  }

  /// Safely parse time string from various formats (24h, 12h AM/PM or ص/م, Arabic numerals)
  static (int hour, int minute)? parseTimeString(String? raw) {
    if (raw == null) return null;
    var t = raw.trim();
    if (t.isEmpty) return null;

    // Convert Arabic-Indic numerals (٠-٩) to Western (0-9)
    const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    for (int i = 0; i < 10; i++) {
      t = t.replaceAll(eastern[i], i.toString());
    }

    final upper = t.toUpperCase();
    final isPM = upper.contains('م') || upper.contains('PM');
    final isAM = upper.contains('ص') || upper.contains('AM');

    // Extract digits and colon
    final cleaned = upper.replaceAll(RegExp(r'[^0-9:]'), '');
    final parts = cleaned.split(':');
    if (parts.isEmpty || parts[0].isEmpty) return null;

    int? h = int.tryParse(parts[0]);
    if (h == null) return null;
    int m = 0;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      m = int.tryParse(parts[1]) ?? 0;
    }

    if (isPM && h < 12) {
      h += 12;
    } else if (isAM && h == 12) {
      h = 0;
    }

    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return (h, m);
  }

  /// Normalize Arabic weekday text (unify alef, taa marbouta, etc.)
  static String normalizeArabicDay(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
  }

  /// Robustly check if a tutoring group is scheduled on a given day
  static bool isGroupScheduledOnDay(GroupModel group, String targetDay) {
    if (targetDay == 'الكل' || targetDay.trim().isEmpty) return true;
    final normTarget = normalizeArabicDay(targetDay);
    final normSchedule = normalizeArabicDay(group.schedule);
    final normDays = normalizeArabicDay(group.days);

    if (normSchedule.contains(normTarget) || normDays.contains(normTarget)) {
      return true;
    }

    final bareTarget = normTarget.startsWith('ال')
        ? normTarget.substring(2)
        : normTarget;
    if (bareTarget.length >= 3 &&
        (normSchedule.contains(bareTarget) || normDays.contains(bareTarget))) {
      return true;
    }

    int? targetIndex;
    if (normTarget.contains('اثنين')) {
      targetIndex = 1;
    } else if (normTarget.contains('ثلاثاء')) {
      targetIndex = 2;
    } else if (normTarget.contains('اربعاء')) {
      targetIndex = 3;
    } else if (normTarget.contains('خميس')) {
      targetIndex = 4;
    } else if (normTarget.contains('جمعه')) {
      targetIndex = 5;
    } else if (normTarget.contains('سبت')) {
      targetIndex = 6;
    } else if (normTarget.contains('احد')) {
      targetIndex = 7;
    }

    if (targetIndex != null) {
      final daysSplit = group.days.split(RegExp(r'[,;\s]+'));
      for (final p in daysSplit) {
        final parsed = int.tryParse(p.trim());
        if (parsed != null &&
            (parsed == targetIndex || (targetIndex == 7 && parsed == 0))) {
          return true;
        }
      }
    }
    return false;
  }

  /// Dismiss only the previous day's automatic timetable alarms, preserving all manual alarms
  static Future<bool> dismissAutoAlarms() async {
    return await NotificationService.cancelTimetableAlarms(
          automaticOnly: true,
        ) >
        0;
  }

  /// Set alarm for a specific school period
  static Future<bool> setPeriodAlarm({
    required SchoolPeriodModel period,
    int minutesBefore = 0,
    bool skipUi = true,
  }) async {
    try {
      final parsed = parseTimeString(period.startTime);
      if (parsed == null) return false;
      var (hour, min) = parsed;

      if (minutesBefore > 0) {
        min -= minutesBefore;
        if (min < 0) {
          min += 60;
          hour = (hour - 1 + 24) % 24;
        }
      }

      final dayInt = convertWeekdayToCalendarDay(period.dayOfWeek);
      final msg =
          'حصة فصل ${period.className}${period.subject.isNotEmpty ? " • ${period.subject}" : ""}';

      return await setAlarm(
        hour: hour,
        minutes: min,
        message: msg,
        skipUi: skipUi,
        days: [dayInt],
      );
    } catch (_) {
      return false;
    }
  }

  /// Automatically purges expired and past timetable alarms silently in-app
  static Future<int> cleanExpiredAlarms({
    List<SchoolPeriodModel>? todayPeriods,
    List<GroupModel>? todayGroups,
    String? todayArabic,
  }) async {
    int count = await NotificationService.cancelExpiredAndPastAlarms();
    if (todayPeriods != null &&
        todayGroups != null &&
        todayArabic != null &&
        todayArabic.isNotEmpty) {
      count += await NotificationService.cancelAlarmsForPassedPeriodsToday(
        todayPeriods: todayPeriods,
        todayGroups: todayGroups,
        todayArabic: todayArabic,
      );
    }
    return count;
  }

  /// Sync alarms for all periods of a specific day
  static Future<int> syncDayPeriodAlarms({
    required List<SchoolPeriodModel> dayPeriods,
    int minutesBefore = 0,
    bool isAutomatic = false,
    DateTime? scheduledDate,
    bool useSystemClock = false,
    String? soundTone,
  }) async {
    int count = 0;
    for (final period in dayPeriods) {
      if (period.isReserve) continue; // Skip empty reserve periods
      final parsed = parseTimeString(period.startTime);
      if (parsed == null) continue;
      final (hour, minute) = parsed;

      final message =
          '${isAutomatic ? '$autoAlarmPrefix ' : ''}الجدول [${period.dayOfWeek}] '
          'حصة ${period.periodNumber} (${period.className})'
          '${period.subject.isNotEmpty ? ' • ${period.subject}' : ''}';

      bool ok = false;
      if (useSystemClock) {
        ok = await setAlarm(
          hour: (hour * 60 + minute - minutesBefore + 1440) % 1440 ~/ 60,
          minutes: (hour * 60 + minute - minutesBefore + 1440) % 1440 % 60,
          message: message,
          skipUi: true,
          days: scheduledDate == null
              ? [convertWeekdayToCalendarDay(period.dayOfWeek)]
              : null,
        );
        await Future.delayed(const Duration(milliseconds: 300));
      } else {
        ok = await NotificationService.scheduleTimetableAlarm(
          key: 'period_${period.id}',
          dayName: period.dayOfWeek,
          title: 'موعد الحصة ${period.periodNumber}',
          body:
              '${period.className}${period.subject.isNotEmpty ? ' • ${period.subject}' : ''}',
          hour: hour,
          minute: minute,
          minutesBefore: minutesBefore,
          scheduledDate: scheduledDate,
          isAutomatic: isAutomatic,
          soundTone: soundTone,
        );
      }
      if (ok) count++;
    }
    return count;
  }

  /// Sync alarms for tutoring center groups of a specific day
  static Future<int> syncDayGroupAlarms({
    required List<GroupModel> dayGroups,
    required String dayName,
    int minutesBefore = 0,
    bool isAutomatic = false,
    DateTime? scheduledDate,
    bool useSystemClock = false,
    String? soundTone,
  }) async {
    int count = 0;
    for (final group in dayGroups) {
      if (group.startTime.trim().isEmpty) continue;

      final parsed = parseTimeString(group.startTime);
      if (parsed == null) continue;
      final (hour, minute) = parsed;

      final message =
          '${isAutomatic ? '$autoAlarmPrefix ' : ''}الجدول [$dayName] '
          'مجموعة ${group.name} (${group.grade})'
          '${group.subject.isNotEmpty ? ' • ${group.subject}' : ''}';
      final alarmMinutes = (hour * 60 + minute - minutesBefore + 1440) % 1440;

      bool ok = false;
      if (useSystemClock) {
        ok = await setAlarm(
          hour: alarmMinutes ~/ 60,
          minutes: alarmMinutes % 60,
          message: message,
          skipUi: true,
          days: scheduledDate == null
              ? [convertWeekdayToCalendarDay(dayName)]
              : null,
        );
        await Future.delayed(const Duration(milliseconds: 300));
      } else {
        ok = await NotificationService.scheduleTimetableAlarm(
          key: 'group_${group.id}',
          dayName: dayName,
          title: 'موعد مجموعة ${group.name}',
          body:
              '${group.grade}${group.subject.isNotEmpty ? ' • ${group.subject}' : ''}',
          hour: hour,
          minute: minute,
          minutesBefore: minutesBefore,
          scheduledDate: scheduledDate,
          isAutomatic: isAutomatic,
          soundTone: soundTone,
        );
      }
      if (ok) count++;
    }
    return count;
  }

  /// Automatically schedules app-owned reminders for the next day's timetable.
  /// Removes only previously scheduled automatic timetable reminders.
  static Future<int> syncNextDayAutoAlarms({
    required List<SchoolPeriodModel> nextDayPeriods,
    List<GroupModel> nextDayGroups = const [],
    String nextDayName = '',
    int minutesBefore = 5,
    DateTime? scheduledDate,
    bool useSystemClock = false,
    String? soundTone,
  }) async {
    // 1. Clean up previous auto-alarms
    await dismissAutoAlarms();
    await Future.delayed(const Duration(milliseconds: 200));

    // 2. Schedule new auto-alarms for tomorrow
    int count = await syncDayPeriodAlarms(
      dayPeriods: nextDayPeriods,
      minutesBefore: minutesBefore,
      isAutomatic: true,
      scheduledDate: scheduledDate,
      useSystemClock: useSystemClock,
      soundTone: soundTone,
    );

    if (nextDayGroups.isNotEmpty && nextDayName.isNotEmpty) {
      count += await syncDayGroupAlarms(
        dayGroups: nextDayGroups,
        dayName: nextDayName,
        minutesBefore: minutesBefore,
        isAutomatic: true,
        scheduledDate: scheduledDate,
        useSystemClock: useSystemClock,
        soundTone: soundTone,
      );
    }

    return count;
  }

  /// Synchronize recurring weekly alarms for all school weekdays
  static Future<int> syncWeeklyTimetableAlarms({
    required List<SchoolPeriodModel> periods,
    required List<GroupModel> groups,
    List<String> weekdays = const [
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
    ],
    int minutesBefore = 5,
    bool useSystemClock = false,
    String? soundTone,
  }) async {
    // Automatically purge old weekly alarms first silently in-app
    await NotificationService.cancelTimetableAlarms(scheduledDate: null);

    int total = 0;
    for (final day in weekdays) {
      final normDay = normalizeArabicDay(day);
      final dayPeriods = periods
          .where((p) =>
              normalizeArabicDay(p.dayOfWeek) == normDay && !p.isReserve)
          .toList();
      final dayGroups =
          groups.where((g) => isGroupScheduledOnDay(g, day)).toList();

      if (dayPeriods.isNotEmpty) {
        total += await syncDayPeriodAlarms(
          dayPeriods: dayPeriods,
          minutesBefore: minutesBefore,
          isAutomatic: false,
          scheduledDate: null,
          useSystemClock: useSystemClock,
          soundTone: soundTone,
        );
      }
      if (dayGroups.isNotEmpty) {
        total += await syncDayGroupAlarms(
          dayGroups: dayGroups,
          dayName: day,
          minutesBefore: minutesBefore,
          isAutomatic: false,
          scheduledDate: null,
          useSystemClock: useSystemClock,
          soundTone: soundTone,
        );
      }
    }
    return total;
  }
}
