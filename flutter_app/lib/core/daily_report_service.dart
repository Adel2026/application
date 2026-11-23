import 'dart:async';

import 'database/database_service.dart';
import 'notification_service.dart';
import 'whatsapp_service.dart';
import '../models/attendance_model.dart';
import '../models/group_model.dart';
import '../models/student_model.dart';

/// Service responsible for generating and dispatching end-of-day
/// student progress reports to parents via WhatsApp.
class DailyReportService {
  DailyReportService._();
  static final DailyReportService instance = DailyReportService._();

  DatabaseService? _database;

  /// Initialize and schedule the daily reminder using the device's local time.
  Future<void> init({
    required DatabaseService database,
  }) async {
    _database = database;
    await _scheduleDailyNotification();
  }

  Future<void> _scheduleDailyNotification() async {
    final db = _database;
    if (db == null) return;

    final enabled = await db.getSetting(
      'daily_report_enabled',
      defaultValue: 'true',
    );
    if (enabled != 'true') {
      await NotificationService.cancelDailyReportNotification();
      return;
    }

    final timeStr = await db.getSetting(
      'daily_report_time',
      defaultValue: '20:00',
    );
    final timeParts = timeStr.split(':');
    final hour = int.tryParse(timeParts.first) ?? 20;
    final minute = int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return;

    final now = DateTime.now();
    final todayStr = _dateString(now);
    final lastSent = await db.getSetting(
      'daily_report_last_sent_date',
      defaultValue: '',
    );

    await NotificationService.scheduleDailyReportNotification(
      hour: hour,
      minute: minute,
      skipToday: lastSent == todayStr,
    );
  }

  /// Build the daily progress report message for a single student.
  Future<String> buildStudentDailyReport({
    required DatabaseService database,
    required StudentModel student,
  }) async {
    // Attendance
    final attendance = await database.getStudentAttendance(student.id);
    final presentCount = attendance
        .where((a) => a.status == 'present' || a.status == 'late')
        .length;
    final totalSessions = attendance.length;
    final attPercent =
      totalSessions > 0
        ? (attendance
              .where((a) => a.status == 'present' || a.status == 'late')
              .length /
            totalSessions *
            100)
          .toInt()
        : 100;

    // Today's attendance
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final todayAttendance = attendance.where((a) => a.attendanceDate == todayStr);
    final todayRecord = todayAttendance.firstOrNull;
    String todayStatus = 'لم يتم التسجيل بعد';
    if (todayRecord != null) {
      final status = todayRecord.status;
      todayStatus = switch (status) {
        'present' => 'حاضر ✅',
        'late' => 'حاضر متأخر ⏰',
        'absent' => 'غائب ❌',
        _ => 'تم التسجيل: $status',
      };
    }

    // Exam Scores
    final examScores = await database.getStudentExamScores(student.id);
    String examsSummary;
    if (examScores.isNotEmpty) {
      final recentExams = examScores.take(3);
      examsSummary = recentExams
          .map((e) => '• ${e['title']}: ${e['score']}/${e['max_score']}')
          .join('\n');
    } else {
      examsSummary = 'لا توجد اختبارات مسجلة حالياً';
    }

    // Financial status
    final debtText = student.hasOutstandingPayment
        ? 'متأخرات: ${student.outstandingAmount} ج.م'
        : 'مسدد بالكامل ✅';

    // Session log
    String sessionPart = '';
    if (student.groupId != null) {
      try {
        final latestSession =
            await database.getLatestSessionLogForGroup(student.groupId!);
        final sessionDate = latestSession?.date.length ?? 0;
        final isTodaySession = latestSession != null &&
            sessionDate >= 10 &&
            latestSession.date.substring(0, 10) == todayStr &&
            (latestSession.studentId == null ||
                latestSession.studentId == student.id);
        if (isTodaySession) {
          final lessonTitle = latestSession.lessonTitle.trim().isNotEmpty
              ? latestSession.lessonTitle
              : 'موضوع الدرس غير مسجل';
          final homework = latestSession.homework.trim().isNotEmpty
              ? '\n• الواجب: ${latestSession.homework}'
              : '\n• لا يوجد واجب مسجل';
          if (todayRecord?.status == 'absent') {
            sessionPart = '\n\n⚠️ الحصة التي فاتت الطالب اليوم:'
                '\n• الدرس: $lessonTitle$homework'
                '\nنرجو مساعدته على مذاكرة الدرس وتعويض ما فاته.';
          } else {
            sessionPart = '\n\n4️⃣ درس اليوم:'
                '\n• الدرس: $lessonTitle$homework'
                '${latestSession.nextTopic.isNotEmpty ? '\n• التحضير القادم: ${latestSession.nextTopic}' : ''}';
          }
        } else if (todayRecord?.status == 'absent') {
          sessionPart = '\n\n⚠️ تم تسجيل غياب الطالب عن حصة اليوم.'
              '\nموضوع الدرس والواجب غير مسجلين؛ نرجو التواصل مع السنتر لمعرفة ما فاته ومساعدته على تعويضه.';
        }
      } catch (_) {}
    }

    final centerName = await database.getSetting(
      'center_name',
      defaultValue: 'سنتر أستاذي التعليمي',
    );
    final teacherName = await database.getSetting(
      'teacher_name',
      defaultValue: 'الأستاذ',
    );

    return '''📊 تقرير المتابعة اليومي 📊
$centerName | المعلم: $teacherName
━━━━━━━━━━━━━━━━━
الطالب: ${student.fullName}
الصف: ${student.grade}
📅 التاريخ: $todayStr

1️⃣ حضور اليوم: $todayStatus
📈 نسبة الحضور الكلية: $attPercent% ($presentCount من $totalSessions حصص)

2️⃣ آخر نتائج الاختبارات:
$examsSummary

3️⃣ الموقف المالي:
$debtText$sessionPart

مع تمنياتنا للطالب بدوام التفوق والنجاح 🌟''';
  }

  /// Select students scheduled today with a present, late, or absent mark.
  Future<List<StudentModel>> getStudentsWithClassesToday({
    required DatabaseService database,
    List<StudentModel>? allStudents,
  }) async {
    final today = DateTime.now();
    final targetDay = _arabicDayName(today.weekday);
    final results = await Future.wait([
      allStudents == null
          ? database.getStudents()
          : Future.value(allStudents),
      database.getGroups(),
      database.getAttendanceForDate(_dateString(today)),
    ]);
    final students = results[0] as List<StudentModel>;
    final groups = results[1] as List<GroupModel>;
    final attendance = results[2] as List<AttendanceModel>;
    final attendedStudentIds = attendance
        .where((record) =>
            record.status == 'present' ||
            record.status == 'late' ||
            record.status == 'absent')
        .map((record) => record.studentId)
        .toSet();
    final groupsById = {for (final group in groups) group.id: group};

    return students.where((student) {
      if (student.parentPhone.trim().isEmpty ||
          !attendedStudentIds.contains(student.id)) {
        return false;
      }
      final groupId = student.groupId;
      final group = groupId == null ? null : groupsById[groupId];
      return group != null && _isScheduledOnDay(group, targetDay, today.weekday);
    }).toList();
  }

  static String _dateString(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _arabicDayName(int weekday) => switch (weekday) {
        DateTime.monday => 'الاثنين',
        DateTime.tuesday => 'الثلاثاء',
        DateTime.wednesday => 'الأربعاء',
        DateTime.thursday => 'الخميس',
        DateTime.friday => 'الجمعة',
        DateTime.saturday => 'السبت',
        DateTime.sunday => 'الأحد',
        _ => '',
      };

  static String _normalizeArabicDay(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('اتنين', 'اثنين');

  static bool _isScheduledOnDay(
    GroupModel group,
    String targetDay,
    int weekday,
  ) {
    final normalizedTarget = _normalizeArabicDay(targetDay);
    final normalizedSchedule = _normalizeArabicDay(group.schedule);
    final normalizedDays = _normalizeArabicDay(group.days);
    final bareTarget = normalizedTarget.startsWith('ال')
        ? normalizedTarget.substring(2)
        : normalizedTarget;

    if (normalizedSchedule.contains(normalizedTarget) ||
        normalizedDays.contains(normalizedTarget) ||
        normalizedSchedule.contains(bareTarget) ||
        normalizedDays.contains(bareTarget)) {
      return true;
    }

    final numericDays = group.days.split(RegExp(r'[,;\s]+'));
    return numericDays.any((value) {
      final dayNumber = int.tryParse(value.trim());
      return dayNumber == weekday || (weekday == DateTime.sunday && dayNumber == 0);
    });
  }

  /// Send daily reports only to parents of students with a scheduled class and attendance record today.
  /// Returns a map with counts: {sent, failed, skipped, total}.
  Future<Map<String, int>> sendAllDailyReports({
    required DatabaseService database,
    void Function(int sent, int total)? onProgress,
  }) async {
    final students = await database.getStudents();
    final eligibleStudents = await getStudentsWithClassesToday(
      database: database,
      allStudents: students,
    );

    int sent = 0;
    int failed = 0;
    int skipped = students.length - eligibleStudents.length;

    final messageQueue = <Map<String, String>>[];

    for (final student in eligibleStudents) {
      final report = await buildStudentDailyReport(
        database: database,
        student: student,
      );
      messageQueue.add({
        'phone': student.parentPhone,
        'message': report,
      });
    }

    final successCount = await WhatsAppService.sendBatchMessagesWithDelay(
      database: database,
      messageQueue: messageQueue,
      onProgress: onProgress,
    );
    sent = successCount;
    failed = eligibleStudents.length - successCount;

    if (failed == 0) {
      final now = DateTime.now();
      final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await database.setSetting('daily_report_last_sent_date', todayStr);
      await _scheduleDailyNotification();
    }

    return {
      'sent': sent,
      'failed': failed,
      'skipped': skipped,
      'total': students.length,
    };
  }

  /// Send daily report for a specific group.
  Future<Map<String, int>> sendGroupDailyReports({
    required DatabaseService database,
    required String groupId,
    void Function(int sent, int total)? onProgress,
  }) async {
    final allStudents = await database.getStudents();
    final groupStudents = allStudents
        .where((s) => s.groupId == groupId && s.parentPhone.trim().isNotEmpty)
        .toList();

    final messageQueue = <Map<String, String>>[];
    for (final student in groupStudents) {
      final report = await buildStudentDailyReport(
        database: database,
        student: student,
      );
      messageQueue.add({
        'phone': student.parentPhone,
        'message': report,
      });
    }

    final successCount = await WhatsAppService.sendBatchMessagesWithDelay(
      database: database,
      messageQueue: messageQueue,
      onProgress: onProgress,
    );

    return {
      'sent': successCount,
      'failed': groupStudents.length - successCount,
      'total': groupStudents.length,
    };
  }

  /// Send daily report for a single student.
  Future<bool> sendSingleStudentReport({
    required DatabaseService database,
    required StudentModel student,
  }) async {
    if (student.parentPhone.trim().isEmpty) return false;

    final report = await buildStudentDailyReport(
      database: database,
      student: student,
    );

    return await WhatsAppService.dispatchMessage(
      database: database,
      phone: student.parentPhone,
      message: report,
    );
  }

}
