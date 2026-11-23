import 'package:flutter/material.dart';

import '../models/exceptional_session_model.dart';
import '../models/group_model.dart';
import '../models/school_period_model.dart';
import 'alarm_service.dart';

enum ConflictType {
  groupVsGroup,
  groupVsExceptional,
  exceptionalVsExceptional,
  groupVsSchool,
}

class ScheduleConflict {
  final ConflictType type;
  final String day; // 'السبت', 'الأحد', ...
  final String? date; // 'YYYY-MM-DD'
  final String firstId;
  final String firstName;
  final String firstTime;
  final String secondId;
  final String secondName;
  final String secondTime;
  final String message;

  const ScheduleConflict({
    required this.type,
    required this.day,
    this.date,
    required this.firstId,
    required this.firstName,
    required this.firstTime,
    required this.secondId,
    required this.secondName,
    required this.secondTime,
    required this.message,
  });

  String get typeLabel {
    switch (type) {
      case ConflictType.groupVsGroup:
        return 'تعارض مجموعتين';
      case ConflictType.groupVsExceptional:
        return 'تعارض مع حصة استثنائية';
      case ConflictType.exceptionalVsExceptional:
        return 'تعارض حصتين استثنائيتين';
      case ConflictType.groupVsSchool:
        return 'تعارض مع حصة مدرسية';
    }
  }

  IconData get typeIcon {
    switch (type) {
      case ConflictType.groupVsGroup:
        return Icons.groups_rounded;
      case ConflictType.groupVsExceptional:
        return Icons.bolt_rounded;
      case ConflictType.exceptionalVsExceptional:
        return Icons.warning_amber_rounded;
      case ConflictType.groupVsSchool:
        return Icons.school_rounded;
    }
  }
}

class ScheduleConflictService {
  static const List<String> weekdays = [
    'السبت',
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
  ];

  /// Safely converts time string into minutes from midnight (0 - 1440)
  static int parseTimeToMinutes(String? raw, {int fallback = 0}) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    final parsed = AlarmService.parseTimeString(raw);
    if (parsed == null) return fallback;
    return parsed.$1 * 60 + parsed.$2;
  }

  /// Checks if two time intervals overlap (open intervals): startA < endB && endA > startB
  static bool isTimeOverlapping({
    required int startA,
    required int endA,
    required int startB,
    required int endB,
  }) {
    // If end is before or equal to start, treat as at least 45 minutes
    final safeEndA = endA > startA ? endA : startA + 45;
    final safeEndB = endB > startB ? endB : startB + 45;
    return startA < safeEndB && safeEndA > startB;
  }

  /// Extracts scheduled days from GroupModel (both from `days` and `schedule`)
  static Set<String> getGroupDays(GroupModel group) {
    final Set<String> result = {};
    for (final day in weekdays) {
      if (AlarmService.isGroupScheduledOnDay(group, day)) {
        result.add(day);
      }
    }
    return result;
  }

  /// Extracts start & end time in minutes for a specific day for a group
  /// Supports per-day customized schedule e.g.: "السبت (04:00 PM - 05:30 PM)"
  static ({int start, int end, String label}) getGroupIntervalForDay(
    GroupModel group,
    String day,
  ) {
    final schedule = group.schedule;

    // Check if per-day custom time is embedded in schedule
    // e.g. "السبت (من 03:00 PM إلى 04:00 PM)" or "السبت (03:00 PM - 04:00 PM)"
    if (schedule.contains('(') && schedule.contains(')')) {
      final pattern = RegExp(
        '$day\\s*\\((?:من\\s*)?([^\\-–إلى\\)]+)(?:[\\-–]|إلى)\\s*([^\\)]+)\\)',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(schedule);
      if (match != null) {
        final rawStart = match.group(1)?.trim() ?? group.startTime;
        final rawEnd = match.group(2)?.trim() ?? group.endTime;
        final start = parseTimeToMinutes(rawStart, fallback: 15 * 60);
        var end = parseTimeToMinutes(rawEnd, fallback: start + 60);
        if (end <= start) end = start + 60;
        return (start: start, end: end, label: '$rawStart - $rawEnd');
      }
    }

    // Default to group's standard startTime & endTime
    final start = parseTimeToMinutes(group.startTime, fallback: 15 * 60);
    var end = parseTimeToMinutes(group.endTime, fallback: start + 60);
    if (end <= start) end = start + 60;

    final startLabel = group.startTime.isNotEmpty ? group.startTime : '03:00 PM';
    final endLabel = group.endTime.isNotEmpty ? group.endTime : '04:00 PM';

    return (start: start, end: end, label: '$startLabel - $endLabel');
  }

  /// Check conflicts for a group being created or updated in real-time
  static List<ScheduleConflict> checkProposedGroupConflicts({
    String? currentGroupId,
    String proposedGroupName = 'المجموعة الحالية',
    required List<String> proposedDays,
    required String proposedStartTime,
    required String proposedEndTime,
    Map<String, String>? dayStartTimes,
    Map<String, String>? dayEndTimes,
    required List<GroupModel> allGroups,
    List<ExceptionalSessionModel>? exceptionalSessions,
    List<SchoolPeriodModel>? schoolPeriods,
  }) {
    final List<ScheduleConflict> conflicts = [];
    final safePropName = proposedGroupName.trim().isNotEmpty
        ? proposedGroupName.trim()
        : 'المجموعة الحالية';

    for (final day in proposedDays) {
      final sTime = dayStartTimes?[day] ?? proposedStartTime;
      final eTime = dayEndTimes?[day] ?? proposedEndTime;
      final propStart = parseTimeToMinutes(sTime, fallback: 15 * 60);
      var propEnd = parseTimeToMinutes(eTime, fallback: propStart + 60);
      if (propEnd <= propStart) propEnd = propStart + 60;
      final propLabel = '$sTime - $eTime';

      // 1. Check against other groups
      for (final other in allGroups) {
        if (!other.isActive) continue;
        if (currentGroupId != null && other.id == currentGroupId) continue;

        if (AlarmService.isGroupScheduledOnDay(other, day)) {
          final otherInterval = getGroupIntervalForDay(other, day);
          if (isTimeOverlapping(
            startA: propStart,
            endA: propEnd,
            startB: otherInterval.start,
            endB: otherInterval.end,
          )) {
            conflicts.add(
              ScheduleConflict(
                type: ConflictType.groupVsGroup,
                day: day,
                firstId: currentGroupId ?? 'new',
                firstName: safePropName,
                firstTime: propLabel,
                secondId: other.id,
                secondName: other.name,
                secondTime: otherInterval.label,
                message:
                    'يوم $day: تعارض في الموعد ($propLabel) مع مجموعة "${other.name}" ($otherInterval.label)',
              ),
            );
          }
        }
      }

      // 2. Check against exceptional sessions on this day of week
      if (exceptionalSessions != null) {
        for (final ex in exceptionalSessions) {
          if (ex.status != 'active') continue;
          if (currentGroupId != null && ex.groupId == currentGroupId) continue;
          if (ex.day == day) {
            final exStart = parseTimeToMinutes(ex.time, fallback: 16 * 60);
            final exDuration = ex.scale == 'double' ? 120 : 60;
            final exEnd = exStart + exDuration;
            final exLabel = '${ex.time} (${ex.scaleLabel})';

            if (isTimeOverlapping(
              startA: propStart,
              endA: propEnd,
              startB: exStart,
              endB: exEnd,
            )) {
              conflicts.add(
                ScheduleConflict(
                  type: ConflictType.groupVsExceptional,
                  day: day,
                  date: ex.date,
                  firstId: currentGroupId ?? 'new',
                  firstName: safePropName,
                  firstTime: propLabel,
                  secondId: ex.id,
                  secondName: ex.groupName.isNotEmpty ? ex.groupName : 'حصة استثنائية',
                  secondTime: exLabel,
                  message:
                      'يوم $day (${ex.date}): تعارض مع حصة استثنائية لمجموعة "${ex.groupName}" ($exLabel)',
                ),
              );
            }
          }
        }
      }

      // 3. Check against school periods if enabled
      if (schoolPeriods != null) {
        final normDay = AlarmService.normalizeArabicDay(day);
        for (final sp in schoolPeriods) {
          if (sp.isRecess) continue;
          if (AlarmService.normalizeArabicDay(sp.dayOfWeek) == normDay) {
            final spStart = parseTimeToMinutes(sp.startTime, fallback: 8 * 60);
            var spEnd = parseTimeToMinutes(sp.endTime, fallback: spStart + 45);
            if (spEnd <= spStart) spEnd = spStart + 45;

            if (isTimeOverlapping(
              startA: propStart,
              endA: propEnd,
              startB: spStart,
              endB: spEnd,
            )) {
              final spLabel = '${sp.startTime} - ${sp.endTime}';
              conflicts.add(
                ScheduleConflict(
                  type: ConflictType.groupVsSchool,
                  day: day,
                  firstId: currentGroupId ?? 'new',
                  firstName: safePropName,
                  firstTime: propLabel,
                  secondId: sp.id,
                  secondName: 'حصة مدرسية: ${sp.className} (${sp.subject})',
                  secondTime: spLabel,
                  message:
                      'يوم $day: تعارض مع حصة مدرسية في ${sp.className} ($spLabel)',
                ),
              );
            }
          }
        }
      }
    }

    return conflicts;
  }

  /// Check conflicts for an exceptional session being added or modified
  static List<ScheduleConflict> checkProposedExceptionalSessionConflicts({
    String? currentSessionId,
    required String targetGroupId,
    required String targetGroupName,
    required String proposedDate, // YYYY-MM-DD
    required String proposedDay, // 'السبت'
    required String proposedTime, // e.g. '04:00 PM'
    required String proposedScale, // 'single' or 'double'
    required List<GroupModel> allGroups,
    required List<ExceptionalSessionModel> exceptionalSessions,
  }) {
    final List<ScheduleConflict> conflicts = [];
    final propStart = parseTimeToMinutes(proposedTime, fallback: 16 * 60);
    final duration = proposedScale == 'double' ? 120 : 60;
    final propEnd = propStart + duration;
    final propLabel = '$proposedTime (${proposedScale == "double" ? "2x دوبل" : "1x فردية"})';

    // 1. Check against regular groups on this day
    for (final group in allGroups) {
      if (!group.isActive) continue;
      if (AlarmService.isGroupScheduledOnDay(group, proposedDay)) {
        final gInterval = getGroupIntervalForDay(group, proposedDay);
        if (isTimeOverlapping(
          startA: propStart,
          endA: propEnd,
          startB: gInterval.start,
          endB: gInterval.end,
        )) {
          conflicts.add(
            ScheduleConflict(
              type: ConflictType.groupVsExceptional,
              day: proposedDay,
              date: proposedDate,
              firstId: currentSessionId ?? 'new_exceptional',
              firstName: 'حصة استثنائية: $targetGroupName',
              firstTime: propLabel,
              secondId: group.id,
              secondName: group.name,
              secondTime: gInterval.label,
              message:
                  'تعارض مع الموعد الثابت لمجموعة "${group.name}" يوم $proposedDay ($gInterval.label)',
            ),
          );
        }
      }
    }

    // 2. Check against other exceptional sessions on the exact same date
    for (final ex in exceptionalSessions) {
      if (ex.status != 'active') continue;
      if (currentSessionId != null && ex.id == currentSessionId) continue;
      if (ex.date == proposedDate) {
        final exStart = parseTimeToMinutes(ex.time, fallback: 16 * 60);
        final exDuration = ex.scale == 'double' ? 120 : 60;
        final exEnd = exStart + exDuration;
        final exLabel = '${ex.time} (${ex.scaleLabel})';

        if (isTimeOverlapping(
          startA: propStart,
          endA: propEnd,
          startB: exStart,
          endB: exEnd,
        )) {
          conflicts.add(
            ScheduleConflict(
              type: ConflictType.exceptionalVsExceptional,
              day: proposedDay,
              date: proposedDate,
              firstId: currentSessionId ?? 'new_exceptional',
              firstName: 'حصة استثنائية: $targetGroupName',
              firstTime: propLabel,
              secondId: ex.id,
              secondName: 'حصة استثنائية: ${ex.groupName}',
              secondTime: exLabel,
              message:
                  'تعارض في نفس اليوم ($proposedDate) مع حصة استثنائية لمجموعة "${ex.groupName}" ($exLabel)',
            ),
          );
        }
      }
    }

    return conflicts;
  }

  /// Detect all active schedule conflicts across all groups and active exceptional sessions
  static Map<String, List<ScheduleConflict>> detectAllConflicts({
    required List<GroupModel> groups,
    List<ExceptionalSessionModel>? exceptionalSessions,
  }) {
    final Map<String, List<ScheduleConflict>> result = {};
    final activeGroups = groups.where((g) => g.isActive).toList();

    // 1. Group vs Group conflicts
    for (int i = 0; i < activeGroups.length; i++) {
      final gA = activeGroups[i];
      final daysA = getGroupDays(gA);

      for (int j = i + 1; j < activeGroups.length; j++) {
        final gB = activeGroups[j];
        final commonDays = daysA.where((d) => AlarmService.isGroupScheduledOnDay(gB, d));

        for (final day in commonDays) {
          final intA = getGroupIntervalForDay(gA, day);
          final intB = getGroupIntervalForDay(gB, day);

          if (isTimeOverlapping(
            startA: intA.start,
            endA: intA.end,
            startB: intB.start,
            endB: intB.end,
          )) {
            final conflictForA = ScheduleConflict(
              type: ConflictType.groupVsGroup,
              day: day,
              firstId: gA.id,
              firstName: gA.name,
              firstTime: intA.label,
              secondId: gB.id,
              secondName: gB.name,
              secondTime: intB.label,
              message:
                  'يوم $day: تعارض الموعد بين "${gA.name}" ($intA.label) و "${gB.name}" ($intB.label)',
            );

            final conflictForB = ScheduleConflict(
              type: ConflictType.groupVsGroup,
              day: day,
              firstId: gB.id,
              firstName: gB.name,
              firstTime: intB.label,
              secondId: gA.id,
              secondName: gA.name,
              secondTime: intA.label,
              message:
                  'يوم $day: تعارض الموعد بين "${gB.name}" ($intB.label) و "${gA.name}" ($intA.label)',
            );

            result.putIfAbsent(gA.id, () => []).add(conflictForA);
            result.putIfAbsent(gB.id, () => []).add(conflictForB);
          }
        }
      }
    }

    // 2. Group vs Exceptional Session conflicts
    if (exceptionalSessions != null) {
      final activeExSessions = exceptionalSessions.where((s) => s.status == 'active').toList();
      for (final ex in activeExSessions) {
        final exStart = parseTimeToMinutes(ex.time, fallback: 16 * 60);
        final exDuration = ex.scale == 'double' ? 120 : 60;
        final exEnd = exStart + exDuration;
        final exLabel = '${ex.time} (${ex.scaleLabel})';

        for (final g in activeGroups) {
          if (AlarmService.isGroupScheduledOnDay(g, ex.day)) {
            final gInt = getGroupIntervalForDay(g, ex.day);
            if (isTimeOverlapping(
              startA: exStart,
              endA: exEnd,
              startB: gInt.start,
              endB: gInt.end,
            )) {
              final conflict = ScheduleConflict(
                type: ConflictType.groupVsExceptional,
                day: ex.day,
                date: ex.date,
                firstId: g.id,
                firstName: g.name,
                firstTime: gInt.label,
                secondId: ex.id,
                secondName: 'حصة استثنائية: ${ex.groupName}',
                secondTime: exLabel,
                message:
                    'يوم ${ex.day} (${ex.date}): تعارض مجموعة "${g.name}" ($gInt.label) مع حصة استثنائية لمجموعة "${ex.groupName}" ($exLabel)',
              );

              result.putIfAbsent(g.id, () => []).add(conflict);
              result.putIfAbsent(ex.id, () => []).add(conflict);
            }
          }
        }
      }

      // 3. Exceptional Session vs Exceptional Session on the same date
      for (int i = 0; i < activeExSessions.length; i++) {
        final sA = activeExSessions[i];
        final startA = parseTimeToMinutes(sA.time, fallback: 16 * 60);
        final endA = startA + (sA.scale == 'double' ? 120 : 60);

        for (int j = i + 1; j < activeExSessions.length; j++) {
          final sB = activeExSessions[j];
          if (sA.date == sB.date) {
            final startB = parseTimeToMinutes(sB.time, fallback: 16 * 60);
            final endB = startB + (sB.scale == 'double' ? 120 : 60);

            if (isTimeOverlapping(startA: startA, endA: endA, startB: startB, endB: endB)) {
              final conflict = ScheduleConflict(
                type: ConflictType.exceptionalVsExceptional,
                day: sA.day,
                date: sA.date,
                firstId: sA.id,
                firstName: 'حصة استثنائية: ${sA.groupName}',
                firstTime: '${sA.time} (${sA.scaleLabel})',
                secondId: sB.id,
                secondName: 'حصة استثنائية: ${sB.groupName}',
                secondTime: '${sB.time} (${sB.scaleLabel})',
                message:
                    'تاريخ ${sA.date}: تعارض حصة استثنائية (${sA.groupName}) مع (${sB.groupName})',
              );
              result.putIfAbsent(sA.id, () => []).add(conflict);
              result.putIfAbsent(sB.id, () => []).add(conflict);
            }
          }
        }
      }
    }

    return result;
  }

  /// Builds a prominent, beautiful warning banner or card widget
  static Widget buildConflictWarningBanner({
    required List<ScheduleConflict> conflicts,
    required BuildContext context,
    VoidCallback? onResolve,
  }) {
    if (conflicts.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFEF4444),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تحذير: تم اكتشاف تعارض في المواعيد (${conflicts.length})',
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...conflicts.take(3).map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        c.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.red.shade200 : Colors.red.shade900,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          if (conflicts.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '+ ${conflicts.length - 3} تعارضات أخرى...',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Show modal dialog confirming whether user wants to proceed despite conflict
  static Future<bool> confirmSaveWithConflictDialog({
    required BuildContext context,
    required List<ScheduleConflict> conflicts,
    String? targetName,
    String title = 'تنبيه تعارض في المواعيد',
    String confirmButtonText = 'حفظ على أي حال',
    String cancelButtonText = 'تعديل الموعد',
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.schedule_send_rounded,
                color: Color(0xFFEF4444),
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                targetName != null && targetName.isNotEmpty
                    ? 'الموعد المحدد لـ "$targetName" يتداخل ويتعارض مع مواعيد أخرى مسجلة مسبقاً:'
                    : 'الموعد الذي حددته يتداخل ويتعارض مع مواعيد أخرى مسجلة مسبقاً:',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                    ),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: conflicts.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (c, i) {
                      final item = conflicts[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(item.typeIcon, size: 16, color: const Color(0xFFEF4444)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.message,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'هل ترغب في العودة لتعديل الموعد لتجنب تداخل الحصص، أم الاستمرار وحفظ الموعد؟',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              cancelButtonText,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmButtonText),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}
