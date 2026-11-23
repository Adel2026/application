import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pending Sessions & Group Days Schedule Tests', () {
    test('Calculates whether a date matches group schedule days', () {
      bool isGroupDay({
        required String schedule,
        required String days,
        required int weekday,
      }) {
        const arabicDays = [
          'الاثنين', // 1
          'الثلاثاء', // 2
          'الأربعاء', // 3
          'الخميس', // 4
          'الجمعة', // 5
          'السبت', // 6
          'الأحد', // 7
        ];
        final dayName = arabicDays[(weekday - 1) % 7];
        if (days.isNotEmpty && days.contains(dayName)) return true;
        if (schedule.isNotEmpty && schedule.contains(dayName)) return true;
        if (days.isEmpty && schedule.isEmpty) return true;
        return false;
      }

      // Group with schedule 'السبت والثلاثاء 4:00 م'
      const schedule = 'السبت والثلاثاء 4:00 م';
      // Saturday is weekday 6
      expect(isGroupDay(schedule: schedule, days: '', weekday: 6), isTrue);
      // Tuesday is weekday 2
      expect(isGroupDay(schedule: schedule, days: '', weekday: 2), isTrue);
      // Friday is weekday 5 -> false
      expect(isGroupDay(schedule: schedule, days: '', weekday: 5), isFalse);
      // Sunday is weekday 7 -> false
      expect(isGroupDay(schedule: schedule, days: '', weekday: 7), isFalse);
    });

    test('Pending session detection criteria', () {
      bool isPendingSession({
        required bool isReportSent,
        required bool isLocked,
        required bool hasLesson,
      }) {
        return !isReportSent && (!isLocked || !hasLesson);
      }

      // Attendance taken yesterday, but report not sent and no lesson
      expect(isPendingSession(isReportSent: false, isLocked: false, hasLesson: false), isTrue);
      // Attendance taken and lesson filled, but report not sent yet
      expect(isPendingSession(isReportSent: false, isLocked: false, hasLesson: true), isTrue);
      // Report sent successfully -> Not pending
      expect(isPendingSession(isReportSent: true, isLocked: true, hasLesson: true), isFalse);
    });

    test('Today groups filtering does not fallback to all groups when today has no groups', () {
      final allGroups = [
        {'id': 'g1', 'name': 'مجموعة السبت', 'schedule': 'السبت 4:00 م', 'days': 'السبت'},
        {'id': 'g2', 'name': 'مجموعة الثلاثاء', 'schedule': 'الثلاثاء 5:00 م', 'days': 'الثلاثاء'},
      ];

      List<Map<String, String>> filterGroups({
        required bool filterTodayOnly,
        required String todayArabicDay,
      }) {
        if (!filterTodayOnly) return List.from(allGroups);
        return allGroups.where((g) {
          return g['schedule']!.contains(todayArabicDay) || g['days']!.contains(todayArabicDay);
        }).toList();
      }

      // Today is الجمعة (Friday) - no groups scheduled
      final fridayGroups = filterGroups(filterTodayOnly: true, todayArabicDay: 'الجمعة');
      expect(fridayGroups, isEmpty, reason: 'Must be empty and not display all groups when there are no groups today');

      // If user toggles filterTodayOnly to false, show all
      final allWhenToggled = filterGroups(filterTodayOnly: false, todayArabicDay: 'الجمعة');
      expect(allWhenToggled.length, equals(2));

      // Today is السبت (Saturday)
      final saturdayGroups = filterGroups(filterTodayOnly: true, todayArabicDay: 'السبت');
      expect(saturdayGroups.length, equals(1));
      expect(saturdayGroups.first['id'], equals('g1'));
    });
  });
}
