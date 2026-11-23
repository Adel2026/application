import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_center/core/schedule_conflict_service.dart';
import 'package:teacher_center/models/group_model.dart';
import 'package:teacher_center/models/exceptional_session_model.dart';

void main() {
  group('ScheduleConflictService Tests', () {
    test('Overlapping intervals are detected correctly', () {
      // 03:00 PM (900 min) - 04:00 PM (960 min)
      // 03:30 PM (930 min) - 04:30 PM (990 min)
      final overlap = ScheduleConflictService.isTimeOverlapping(
        startA: 900,
        endA: 960,
        startB: 930,
        endB: 990,
      );
      expect(overlap, isTrue);

      // Non-overlapping: 03:00 PM - 04:00 PM vs 04:00 PM - 05:00 PM
      final touching = ScheduleConflictService.isTimeOverlapping(
        startA: 900,
        endA: 960,
        startB: 960,
        endB: 1020,
      );
      expect(touching, isFalse);

      // Distant intervals
      final separated = ScheduleConflictService.isTimeOverlapping(
        startA: 600,
        endA: 700,
        startB: 800,
        endB: 900,
      );
      expect(separated, isFalse);
    });

    test('Detects conflict between two groups on the same weekday', () {
      final g1 = GroupModel(
        id: 'g1',
        name: 'أولى ثانوي أ',
        stage: 'ثانوي',
        grade: 'أولى ثانوي',
        days: 'السبت,الثلاثاء',
        schedule: 'السبت والثلاثاء من 03:00 PM إلى 04:30 PM',
        startTime: '03:00 PM',
        endTime: '04:30 PM',
        monthlyPrice: 200,
        room: 'قاعة 1',
        isActive: true,
      );

      final g2 = GroupModel(
        id: 'g2',
        name: 'ثانية ثانوي ب',
        stage: 'ثانوي',
        grade: 'ثانية ثانوي',
        days: 'السبت,الأربعاء',
        schedule: 'السبت والأربعاء من 04:00 PM إلى 05:30 PM',
        startTime: '04:00 PM',
        endTime: '05:30 PM',
        monthlyPrice: 250,
        room: 'قاعة 2',
        isActive: true,
      );

      final conflicts = ScheduleConflictService.detectAllConflicts(
        groups: [g1, g2],
      );

      expect(conflicts.containsKey('g1'), isTrue);
      expect(conflicts.containsKey('g2'), isTrue);
      expect(conflicts['g1']!.first.day, 'السبت');
      expect(conflicts['g1']!.first.type, ConflictType.groupVsGroup);
    });

    test('No conflict if groups have completely different days', () {
      final g1 = GroupModel(
        id: 'g1',
        name: 'مجموعة الأحد',
        stage: 'ثانوي',
        grade: 'أولى',
        days: 'الأحد',
        schedule: 'الأحد من 03:00 PM إلى 04:30 PM',
        startTime: '03:00 PM',
        endTime: '04:30 PM',
        monthlyPrice: 200,
        room: '1',
        isActive: true,
      );

      final g2 = GroupModel(
        id: 'g2',
        name: 'مجموعة الاثنين',
        stage: 'ثانوي',
        grade: 'ثانية',
        days: 'الاثنين',
        schedule: 'الاثنين من 03:00 PM إلى 04:30 PM',
        startTime: '03:00 PM',
        endTime: '04:30 PM',
        monthlyPrice: 200,
        room: '1',
        isActive: true,
      );

      final conflicts = ScheduleConflictService.detectAllConflicts(
        groups: [g1, g2],
      );

      expect(conflicts.isEmpty, isTrue);
    });

    test('Detects conflict between regular group and exceptional session', () {
      final g1 = GroupModel(
        id: 'g1',
        name: 'تالتة إعدادي',
        stage: 'إعدادي',
        grade: 'تالتة',
        days: 'الخميس',
        schedule: 'الخميس من 05:00 PM إلى 06:30 PM',
        startTime: '05:00 PM',
        endTime: '06:30 PM',
        monthlyPrice: 180,
        room: '1',
        isActive: true,
      );

      final ex = ExceptionalSessionModel(
        id: 'ex1',
        groupId: 'g2',
        groupName: 'أولى ثانوي',
        title: 'مراجعة',
        reason: 'revision',
        scale: 'single',
        date: '2026-11-20',
        day: 'الخميس',
        time: '05:30 PM',
        isRecurring: false,
        notes: '',
        status: 'active',
        createdAt: DateTime.now().toIso8601String(),
      );

      final conflicts = ScheduleConflictService.detectAllConflicts(
        groups: [g1],
        exceptionalSessions: [ex],
      );

      expect(conflicts.containsKey('g1'), isTrue);
      expect(conflicts.containsKey('ex1'), isTrue);
      expect(conflicts['g1']!.first.type, ConflictType.groupVsExceptional);
    });

    test('checkProposedGroupConflicts detects live conflict before saving', () {
      final existingGroup = GroupModel(
        id: 'g_existing',
        name: 'جروب البرمجة',
        stage: 'ثانوي',
        grade: 'ثانية',
        days: 'الجمعة',
        schedule: 'الجمعة من 02:00 PM إلى 04:00 PM',
        startTime: '02:00 PM',
        endTime: '04:00 PM',
        monthlyPrice: 300,
        room: 'لاب 1',
        isActive: true,
      );

      final liveConflicts = ScheduleConflictService.checkProposedGroupConflicts(
        proposedGroupName: 'جروب الذكاء الاصطناعي الجديد',
        proposedDays: ['الجمعة'],
        proposedStartTime: '03:00 PM',
        proposedEndTime: '05:00 PM',
        allGroups: [existingGroup],
      );

      expect(liveConflicts.isNotEmpty, isTrue);
      expect(liveConflicts.first.secondName, 'جروب البرمجة');
      expect(liveConflicts.first.day, 'الجمعة');
    });

    test('Detects conflict with per-day custom schedule (differentTimePerDay)', () {
      // Group with custom timings: Saturday at 3PM, Tuesday at 6PM
      final gCustom = GroupModel(
        id: 'g_custom',
        name: 'مجموعة مواعيد متغيرة',
        stage: 'ثانوي',
        grade: 'أولى',
        days: 'السبت,الثلاثاء',
        schedule: 'السبت (03:00 PM - 04:30 PM)، الثلاثاء (06:00 PM - 07:30 PM)',
        startTime: '03:00 PM',
        endTime: '04:30 PM',
        monthlyPrice: 200,
        room: '1',
        isActive: true,
      );

      // Other group on Tuesday at 6:30 PM -> conflict on Tuesday
      final gTuesday = GroupModel(
        id: 'g_tue',
        name: 'مجموعة الثلاثاء',
        stage: 'ثانوي',
        grade: 'ثانية',
        days: 'الثلاثاء',
        schedule: 'الثلاثاء من 06:30 PM إلى 08:00 PM',
        startTime: '06:30 PM',
        endTime: '08:00 PM',
        monthlyPrice: 200,
        room: '2',
        isActive: true,
      );

      final conflicts = ScheduleConflictService.detectAllConflicts(
        groups: [gCustom, gTuesday],
      );

      expect(conflicts.containsKey('g_custom'), isTrue);
      expect(conflicts['g_custom']!.first.day, 'الثلاثاء');
      expect(conflicts['g_custom']!.first.secondName, 'مجموعة الثلاثاء');
    });

    test('Detects conflict between two exceptional sessions on the exact same date and overlapping time', () {
      final ex1 = ExceptionalSessionModel(
        id: 'ex_a',
        groupId: 'g1',
        groupName: 'أولى ثانوي',
        title: 'تعويض',
        reason: 'teacher_makeup',
        scale: 'single', // 60 min
        date: '2026-11-25',
        day: 'الأربعاء',
        time: '04:00 PM',
        isRecurring: false,
        notes: '',
        status: 'active',
        createdAt: DateTime.now().toIso8601String(),
      );

      final liveConflicts = ScheduleConflictService.checkProposedExceptionalSessionConflicts(
        targetGroupId: 'g2',
        targetGroupName: 'ثانية ثانوي',
        proposedDate: '2026-11-25',
        proposedDay: 'الأربعاء',
        proposedTime: '04:30 PM',
        proposedScale: 'double',
        allGroups: [],
        exceptionalSessions: [ex1],
      );

      expect(liveConflicts.isNotEmpty, isTrue);
      expect(liveConflicts.first.type, ConflictType.exceptionalVsExceptional);
      expect(liveConflicts.first.secondName, contains('أولى ثانوي'));
    });
  });
}
