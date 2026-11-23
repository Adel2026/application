import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/attendance_timing_guard.dart';
import '../core/academy_communication_service.dart';
import '../core/database/database_service.dart';
import '../core/notification_service.dart';
import '../core/report_dispatch_helper.dart';
import '../core/security_service.dart';
import '../core/whatsapp_service.dart';
import '../models/group_model.dart';
import '../models/curriculum_model.dart';
import '../models/exceptional_session_model.dart';
import '../models/student_model.dart';
import '../widgets/exceptional_session_dialog.dart';
import '../widgets/attendance_lesson_picker_sheet.dart';
import '../widgets/section_top_bar.dart';
import '../widgets/visual_student_report_card.dart';
import 'group_attendance_wizard_screen.dart';
import 'scanner_screen.dart';
import 'whatsapp_hub_screen.dart';

class TodayAttendanceScreen extends StatefulWidget {
  const TodayAttendanceScreen({
    super.key,
    required this.database,
    this.onBack,
    this.preselectedGroupId,
    this.initialSessionType,
  });

  final DatabaseService database;
  final VoidCallback? onBack;
  final String? preselectedGroupId;
  final String? initialSessionType;

  @override
  State<TodayAttendanceScreen> createState() => _TodayAttendanceScreenState();
}

class _TodayAttendanceScreenState extends State<TodayAttendanceScreen> {
  List<GroupModel> allGroups = [];
  List<ExceptionalSessionModel> todayExceptionalSessions = [];
  Map<String, int> groupTotalStudents = {};
  Map<String, int> groupPresentStudents = {};
  Map<String, int> groupMarkedStudents = {};
  Map<String, SessionLogModel?> groupTodaySessionLogs = {};
  Map<String, Map<String, dynamic>> todayCancelledGroups = {};
  Map<String, bool> groupCancellationNoticeSent = {};
  Map<String, bool> groupLockedStatus = {};
  Map<String, bool> groupReportSentStatus = {};
  List<Map<String, dynamic>> pendingSessionsAlerts = [];
  bool isAlertsExpanded = true;
  bool filterTodayOnly = true;
  bool isLoading = true;
  StreamSubscription<DataChangeEvent>? _dataSub;

  late DateTime selectedDate;
  late String todayDateStr;
  late String todayArabicDay;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedGroupId != null) {
      filterTodayOnly = false;
    }
    final now = DateTime.now();
    selectedDate = now;
    todayDateStr = now.toIso8601String().substring(0, 10);
    todayArabicDay = _getArabicDayName(now.weekday);
    _loadGroupsData().then((_) {
      if (widget.preselectedGroupId != null && mounted) {
        final target = allGroups
            .where((g) => g.id == widget.preselectedGroupId)
            .firstOrNull;
        if (target != null) {
          _openGroupAttendanceSheet(
            target,
            initialSessionType: widget.initialSessionType,
            isExceptional:
                widget.initialSessionType == 'early_auth' ||
                widget.initialSessionType == 'exceptional',
          );
        }
      }
    });
    _dataSub = widget.database.onDataChanged.listen((event) {
      if (event == DataChangeEvent.attendance ||
          event == DataChangeEvent.groups ||
          event == DataChangeEvent.students ||
          event == DataChangeEvent.all) {
        if (mounted) _loadGroupsData();
      }
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    super.dispose();
  }

  String _getArabicDayName(int weekday) {
    const days = [
      'الاثنين', // 1
      'الثلاثاء', // 2
      'الأربعاء', // 3
      'الخميس', // 4
      'الجمعة', // 5
      'السبت', // 6
      'الأحد', // 7
    ];
    return days[(weekday - 1) % 7];
  }

  Future<void> _loadGroupsData() async {
    if (allGroups.isEmpty) {
      setState(() => isLoading = true);
    }
    final groups = await widget.database.getGroups();
    final exSessions = await widget.database.getExceptionalSessions(
      date: todayDateStr,
      day: todayArabicDay,
      status: 'active',
    );

    final totals = <String, int>{};
    final presents = <String, int>{};
    final marked = <String, int>{};
    final todayLogs = <String, SessionLogModel?>{};

    final cancellations = await widget.database.getAllCancellationsForDate(
      todayDateStr,
    );
    final groupCancels = <String, Map<String, dynamic>>{};
    for (final c in cancellations) {
      final sId = c['student_id'];
      if (sId == null || sId.toString().trim().isEmpty) {
        groupCancels[c['group_id'] as String] = c;
      }
    }

    await Future.wait(
      groups.map((g) async {
        final studentsWithAtt = await widget.database
            .getGroupStudentsWithAttendance(groupId: g.id, date: todayDateStr);
        totals[g.id] = studentsWithAtt.length;
        presents[g.id] = studentsWithAtt
            .where((s) => s['attendance_status'] == 'present')
            .length;
        marked[g.id] = studentsWithAtt
            .where((s) => s['attendance_status'] != null)
            .length;

        final sLogs = await widget.database.getSessionLogs(
          groupId: g.id,
          date: todayDateStr,
        );
        todayLogs[g.id] = sLogs.isNotEmpty ? sLogs.first : null;
      }),
    );

    final lockedMap = <String, bool>{};
    await Future.wait(
      groups.map((g) async {
        final lock = await widget.database.getSetting(
          'attendance_lock_${g.id}_$todayDateStr',
          defaultValue: 'false',
        );
        if (lock == 'true') {
          lockedMap[g.id] = true;
        }
      }),
    );

    final reportSentMap = <String, bool>{};
    await Future.wait(
      groups.map((g) async {
        final sent = await widget.database.getSetting(
          'report_sent_${g.id}_$todayDateStr',
          defaultValue: 'false',
        );
        if (sent == 'true') {
          reportSentMap[g.id] = true;
        }
      }),
    );

    final noticeSentMap = await widget.database.getGroupCancellationNoticeSentStatus(todayDateStr);
    await widget.database.reconcileAttendanceBillingForDate(todayDateStr);
    final pendingAlerts = await widget.database.getPendingAttendanceSessions(limit: 8);

    if (mounted) {
      setState(() {
        allGroups = groups;
        todayExceptionalSessions = exSessions;
        todayCancelledGroups = groupCancels;
        groupCancellationNoticeSent = noticeSentMap;
        groupLockedStatus = lockedMap;
        groupReportSentStatus = reportSentMap;
        groupTotalStudents = totals;
        groupPresentStudents = presents;
        groupMarkedStudents = marked;
        groupTodaySessionLogs = todayLogs;
        pendingSessionsAlerts = pendingAlerts;
        isLoading = false;
      });
    }
  }

  Future<void> _openWhatsAppSessionReport(GroupModel group) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GroupSessionReportSheet(
        group: group,
        database: widget.database,
        date: todayDateStr,
      ),
    );
    if (mounted) {
      await _loadGroupsData();
    }
  }

  List<GroupModel> get displayGroups {
    final groupsToDisplay = filterTodayOnly
        ? allGroups.where((g) {
            final isRegularToday = g.schedule.contains(todayArabicDay) ||
                g.days.contains(todayArabicDay);
            final hasExToday = todayExceptionalSessions.any(
              (ex) => ex.groupId == g.id,
            );
            return isRegularToday || hasExToday;
          }).toList()
        : List<GroupModel>.from(allGroups);
    groupsToDisplay.sort(GroupModel.compareByStartTime);
    return groupsToDisplay;
  }

  void _openGroupAttendanceSheet(
    GroupModel group, {
    String? initialSessionType,
    bool isExceptional = false,
    String? customDate,
  }) async {
    final effectiveDate = customDate ?? todayDateStr;
    final isAlreadyCancelled = todayCancelledGroups.containsKey(group.id);
    final isReportSent = groupReportSentStatus[group.id] == true ||
        (await widget.database.getSetting(
          'report_sent_${group.id}_$effectiveDate',
          defaultValue: 'false',
        )) == 'true';
    final isLocked = (await widget.database.getSetting(
      'attendance_lock_${group.id}_$effectiveDate',
      defaultValue: 'false',
    )) == 'true' || isAlreadyCancelled;

    if (!isReportSent && isLocked) {
      if (!mounted) return;
      final didAuth = await SecurityService.authenticateWithBiometrics(
        context: context,
        database: widget.database,
        reason: 'تأكيد البصمة لفتح الحصة المقفلة لعدم التلاعب في بيانات الطلاب 🔒',
      );
      if (!didAuth) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('الحصة مقفلة لعدم التلاعب في بيانات الطلاب! يلزم تأكيد البصمة لفتحها 🔒'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    if (isAlreadyCancelled) {
      if (mounted) {
        final noticeSent = groupCancellationNoticeSent[group.id] == true;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.lock_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    noticeSent
                        ? 'تم قفل الحصة لأنها ملغية 🔒 • تم ارسال الاشعار مسبقا لولي الامر'
                        : 'تم قفل الحصة لأنها ملغية 🔒',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      await _showGroupCancellationDialog(group);
      return;
    }

    // If opening for past/custom date, bypass timing guard to let teacher complete pending sessions
    final isToday = effectiveDate == DateTime.now().toIso8601String().substring(0, 10);
    final hasExToday =
        isExceptional ||
        todayExceptionalSessions.any((ex) => ex.groupId == group.id);
    if (isToday && !hasExToday) {
      final timingCheck = AttendanceTimingGuard.checkGroupAttendanceAllowed(
        group,
      );
      if (!timingCheck.isAllowed) {
        if (!mounted) return;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: const [
                Icon(Icons.fingerprint, color: Color(0xFF0D9488), size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تأكيد البصمة لفتح التحضير 🔒',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timingCheck.message ??
                      'التحضير متاح فقط قبل موعد الحصة بـ 5 دقائق.',
                  style: const TextStyle(fontSize: 13.5, height: 1.5),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.amber.shade400.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.lock_clock, color: Colors.amber, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'لفتح دفتر التحضير في غير موعده، يلزم التحقق من بصمة إصبعك.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.brown,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.fingerprint, size: 18),
                label: const Text('تأكيد البصمة للفتح 👆'),
              ),
            ],
          ),
        );
        if (proceed != true) return;

        // Perform biometric authentication
        final authenticated = await SecurityService.authenticateWithBiometrics(
          context: context,
          database: widget.database,
          reason: 'تأكيد البصمة لفتح دفتر تحضير الحصة مبكراً 🔒',
        );

        if (!authenticated) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تم إلغاء أو فشل التحقق من البصمة. لا يمكن فتح التحضير خارج الموعد المحدد!',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          return;
        }
      }
    }

    final sessionLogs = await widget.database.getSessionLogs(
      groupId: group.id,
      date: effectiveDate,
    );
    final sessionLog = sessionLogs.isNotEmpty
        ? sessionLogs.first
        : await widget.database.getLatestSessionLogForGroup(group.id);

    final exForGroup = todayExceptionalSessions
        .where((ex) => ex.groupId == group.id)
        .firstOrNull;
    final effSessionType = initialSessionType ?? exForGroup?.scale ?? 'regular';

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupAttendanceWizardScreen(
          database: widget.database,
          group: group,
          date: effectiveDate,
          latestLog: sessionLog,
          onAttendanceUpdated: _loadGroupsData,
          initialSessionType: effSessionType,
        ),
      ),
    );
    _loadGroupsData();
  }

  Future<void> _uncancelGroupSession(
    GroupModel group, {
    bool openAttendanceAfter = true,
  }) async {
    final didAuth = await SecurityService.authenticateWithBiometrics(
      context: context,
      database: widget.database,
      reason: 'تأكيد البصمة للتراجع عن إلغاء حصة "${group.name}" ومنع التلاعب 🔒',
    );
    if (!didAuth) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الحصة مقفلة لعدم التلاعب في بيانات الطلاب! يلزم تأكيد البصمة للتراجع عن الإلغاء 🔒'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Row(
          children: const [
            Icon(Icons.lock_open_rounded, color: Colors.teal, size: 24),
            SizedBox(width: 8),
            Text('التراجع عن الإلغاء 🔒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'هل ترغب بالتراجع عن إلغاء حصة مجموعة "${group.name}" والعودة لتسجيل حضور الطلاب؟',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('نعم، التراجع عن الإلغاء'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.database.deleteSessionCancellation(
        groupId: group.id,
        date: todayDateStr,
      );
      await widget.database.setSetting(
        'attendance_lock_${group.id}_$todayDateStr',
        'false',
      );

      final db = await widget.database.database;
      await db.delete(
        'attendance',
        where:
            'attendance_date = ? AND status IN (?, ?) AND student_id IN (SELECT id FROM students WHERE group_id = ?)',
        whereArgs: [todayDateStr, 'cancelled_teacher', 'cancelled_student', group.id],
      );

      await _loadGroupsData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم التراجع عن الإلغاء بنجاح لمجموعة "${group.name}" والعودة لكشف الحضور ✅',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.teal.shade800,
          ),
        );

        if (openAttendanceAfter) {
          _openGroupAttendanceSheet(group);
        }
      }
    }
  }

  void _confirmDeleteExceptionalSession(ExceptionalSessionModel session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الحصة الاستثنائية'),
        content: Text(
          'هل أنت متأكد من إلغاء الحصة الاستثنائية المجدولة اليوم لمجموعة "${session.groupName}"؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await widget.database.deleteExceptionalSession(session.id);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              await _loadGroupsData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم إلغاء الحصة الاستثنائية لمجموعة "${session.groupName}" بنجاح 🗑️'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGroupCancellationDialog(GroupModel group) async {
    final isReportSent = groupReportSentStatus[group.id] == true ||
        (await widget.database.getSetting(
          'report_sent_${group.id}_$todayDateStr',
          defaultValue: 'false',
        )) == 'true';
    if (isReportSent) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.lock_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'لا يمكن إلغاء الحصة بعد رصد حضورها وإرسال تقرير المتابعة لأولياء الأمور 🔒',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final existingCancel = todayCancelledGroups[group.id];
    final isAlreadyCancelled = existingCancel != null;
    final isLocked = (await widget.database.getSetting(
      'attendance_lock_${group.id}_$todayDateStr',
      defaultValue: 'false',
    )) == 'true';
    if (isLocked && !isAlreadyCancelled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.lock_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'كشف الحصة معتمد ومقفل! لا يمكن إلغاء حصة معتمدة لحماية بيانات الحضور والماليات 🔒',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final isNoticeAlreadySent = groupCancellationNoticeSent[group.id] == true;
    String cancelledBy = (existingCancel?['cancelled_by'] as String?) ?? 'teacher';

    final teacherReasons = [
      'ظروف طارئة',
      'وعكة صحية',
      'سفر مفاجئ',
      'ارتباط تعليمي / إداري',
      'عطل فني / كهرباء',
      'ظروف خاصة',
    ];

    final studentReasons = [
      'اعتذار مسبق من الطلاب',
      'ظروف صحية / انتشار مرض',
      'امتحانات مدرسية',
      'مناسبة / رحلة مدرسية',
      'ظروف خاصة بالطلاب',
    ];

    String selectedReason = cancelledBy == 'teacher'
        ? (teacherReasons.contains(existingCancel?['reason'])
            ? existingCancel!['reason'] as String
            : teacherReasons.first)
        : (studentReasons.contains(existingCancel?['reason'])
            ? existingCancel!['reason'] as String
            : studentReasons.first);

    final noteController = TextEditingController(
      text: (existingCancel?['notes'] as String?) ?? '',
    );
    bool shouldSendWhatsApp = true;
    bool shouldScheduleMakeup = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dlgCtx, setDlgState) {
            final isDark = Theme.of(dlgCtx).brightness == Brightness.dark;
            final isTeacher = cancelledBy == 'teacher';
            final activeColor = isTeacher ? Colors.red : Colors.purple;
            final reasons = isTeacher ? teacherReasons : studentReasons;

            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isTeacher
                          ? Icons.event_busy_rounded
                          : Icons.groups_rounded,
                      color: activeColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'خيارات إلغاء الحصة للمجموعة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'مجموعة: ${group.name} (${group.grade})',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isAlreadyCancelled) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal.shade400, width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.lock_rounded, color: Colors.red, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'تم قفل الحصة لأنها ملغية 🔒',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (isNoticeAlreadySent) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF059669), width: 1),
                                ),
                                child: Row(
                                  children: const [
                                    Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 16),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'تم ارسال الاشعار مسبقا لولي الامر ✅',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF065F46),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
                              label: const Text(
                                'التراجع عن الإلغاء 🔄',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                              onPressed: () async {
                                Navigator.pop(dlgCtx);
                                await _uncancelGroupSession(group, openAttendanceAfter: true);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Text(
                      'اختر جهة الإلغاء / الاعتذار:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // خياري من جهة الطالب أو من جهة المعلم
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setDlgState(() {
                                cancelledBy = 'student';
                                selectedReason = studentReasons.first;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: !isTeacher
                                    ? Colors.purple.withValues(alpha: 0.15)
                                    : (isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: !isTeacher
                                      ? Colors.purple
                                      : (isDark
                                            ? const Color(0xFF334155)
                                            : Colors.grey.shade300),
                                  width: !isTeacher ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.groups_outlined,
                                    color: !isTeacher
                                        ? Colors.purple
                                        : Colors.grey,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'من جهة الطالب',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: !isTeacher
                                          ? Colors.purple
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    'اعتذار الطلاب',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setDlgState(() {
                                cancelledBy = 'teacher';
                                selectedReason = teacherReasons.first;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isTeacher
                                    ? Colors.red.withValues(alpha: 0.15)
                                    : (isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isTeacher
                                      ? Colors.red
                                      : (isDark
                                            ? const Color(0xFF334155)
                                            : Colors.grey.shade300),
                                  width: isTeacher ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.school_outlined,
                                    color: isTeacher ? Colors.red : Colors.grey,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'من جهة المعلم',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: isTeacher
                                          ? Colors.red
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    'اعتذار المعلم',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // سبب الإلغاء
                    Text(
                      isTeacher ? 'سبب إلغاء المعلم:' : 'سبب اعتذار الطلاب:',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: reasons.map((r) {
                        final isSel = selectedReason == r;
                        return ChoiceChip(
                          label: Text(
                            r,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSel
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          selected: isSel,
                          selectedColor: activeColor.withValues(alpha: 0.25),
                          side: BorderSide(
                            color: isSel
                                ? activeColor
                                : (isDark
                                      ? const Color(0xFF334155)
                                      : Colors.grey.shade300),
                          ),
                          onSelected: (_) =>
                              setDlgState(() => selectedReason = r),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'ملاحظة إضافية للسبب (اختياري)...',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // جدولة حصة تعويضية
                    CheckboxListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: shouldScheduleMakeup,
                      activeColor: activeColor,
                      title: const Text(
                        'جدولة حصة تعويضية للمجموعة الآن 📅',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'تحديد موعد بديل قبل إشعار أولياء الأمور',
                        style: TextStyle(fontSize: 10.5),
                      ),
                      onChanged: (v) =>
                          setDlgState(() => shouldScheduleMakeup = v ?? false),
                    ),

                    // إرسال رسالة تنبيه لطلاب وأولياء أمور المجموعة (الخطوة الأخيرة)
                    CheckboxListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: shouldSendWhatsApp,
                      activeColor: const Color(0xFF25D366),
                      title: const Text(
                        'إرسال إشعار اعتذار لأولياء الأمور عبر واتساب 📲 (الخطوة الأخيرة)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'فتح نافذة إرسال رسائل الاعتذار لجميع أولياء أمور المجموعة كخطوة نهائية',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                      onChanged: (v) =>
                          setDlgState(() => shouldSendWhatsApp = v ?? true),
                    ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.end,
              actions: [
                if (isAlreadyCancelled) ...[
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669).withValues(alpha: 0.15),
                      foregroundColor: const Color(0xFF059669),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text(
                      'إرسال تنبيه لولي الأمر 📲',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      if (isNoticeAlreadySent) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: const [
                                Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'تم ارسال الاشعار مسبقا لولي الامر',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: const Color(0xFF059669),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      } else {
                        Navigator.pop(dlgCtx);
                        await _showGroupCancellationNoticeSheet(
                          group: group,
                          isTeacher: isTeacher,
                          reason: selectedReason,
                        );
                      }
                    },
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.teal),
                    icon: const Icon(Icons.settings_backup_restore_rounded, size: 16),
                    label: const Text(
                      'التراجع عن الإلغاء 🔄',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      Navigator.pop(dlgCtx);
                      await _uncancelGroupSession(group, openAttendanceAfter: true);
                    },
                  ),
                ],
                TextButton(
                  onPressed: () => Navigator.pop(dlgCtx),
                  child: const Text('إغلاق'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: activeColor,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    'تأكيد الإلغاء (${isTeacher ? "المعلم" : "الطلاب"})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    final fullReason = noteController.text.trim().isNotEmpty
                        ? '$selectedReason (${noteController.text.trim()})'
                        : selectedReason;

                    Navigator.pop(dlgCtx);

                    // 1. Record cancellation in database
                    await widget.database.recordSessionCancellation(
                      groupId: group.id,
                      date: todayDateStr,
                      cancelledBy: cancelledBy,
                      studentId: null,
                      reason: fullReason,
                      notes: noteController.text.trim(),
                      noticeSent: isNoticeAlreadySent,
                    );

                    // 2. Mark all students in the group with the new cancellation status
                    final newStatus = isTeacher ? 'cancelled_teacher' : 'cancelled_student';
                    await widget.database.markAllGroupAttendance(
                      groupId: group.id,
                      date: todayDateStr,
                      status: newStatus,
                    );

                    // 3. Immediately lock the session to prevent tampering!
                    await widget.database.setSetting(
                      'attendance_lock_${group.id}_$todayDateStr',
                      'true',
                    );

                    await _loadGroupsData();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isTeacher
                                ? 'تم إلغاء حصة مجموعة "${group.name}" وقفلها رسمياً 🔒'
                                : 'تم تسجيل اعتذار الطلاب وإلغاء حصة "${group.name}" وقفلها 🔒',
                          ),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: activeColor,
                        ),
                      );
                    }

                    // 3. Open makeup dialog if requested before sending final notice
                    if (shouldScheduleMakeup && mounted) {
                      await showAddExceptionalSessionDialog(
                        context: context,
                        database: widget.database,
                        preselectedGroup: group,
                        initialReason: isTeacher ? 'teacher_makeup' : 'student_makeup',
                        initialNotes: 'حصة تعويضية لمجموعة: ${group.name} عن حصة $todayDateStr - السبب: $fullReason',
                        onSaved: () {
                          _loadGroupsData();
                        },
                      );
                    }

                    // 4. FINAL STEP (الخطوة الأخيرة): Send WhatsApp notice to parent(s)
                    if (shouldSendWhatsApp && mounted) {
                      if (isNoticeAlreadySent) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: const [
                                Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'تم ارسال الاشعار مسبقا لولي الامر',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: const Color(0xFF059669),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      } else {
                        await _showGroupCancellationNoticeSheet(
                          group: group,
                          isTeacher: isTeacher,
                          reason: fullReason,
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showGroupCancellationNoticeSheet({
    required GroupModel group,
    required bool isTeacher,
    required String reason,
  }) async {
    final students = await widget.database.getStudents(groupId: group.id);
    final centerName = await widget.database.getSetting(
      'center_name',
      defaultValue: 'سنتر أستاذي',
    );
    final teacherName = await widget.database.getSetting(
      'teacher_name',
      defaultValue: 'الأستاذ',
    );

    String defaultMessage = isTeacher
        ? WhatsAppService.teacherCancellationMessage(
            centerName: centerName,
            teacherName: teacherName,
            groupName: group.name,
            date: todayDateStr,
            reason: reason,
          )
        : '''السلام عليكم ورحمة الله وبركاته 🌸
أولياء أمور وطلاب مجموعة: ${group.name}
━━━━━━━━━━━━━━━━━━━━━
📋 إشعار تأكيد اعتذار وإلغاء الحصة
🏛️ السنتر: $centerName
👨‍🏫 المدرس: $teacherName
📅 تاريخ الحصة: $todayDateStr
📝 سبب الاعتذار: $reason
━━━━━━━━━━━━━━━━━━━━━
تم تسجيل اعتذار وإلغاء الحصة لليوم بناءً على طلب الطلاب وأولياء الأمور.
⏳ سيتم التنسيق معكم لموعد الحصة القادمة أو التعويضية بمشيئة الله.
شاكرين ومقدرين حسن تفهمكم وتعاونكم الدائم 🌟''';

    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isTeacher ? Colors.red : Colors.purple;
    final sentStudentIds = <String>{};

    for (final s in students) {
      final phone = s.parentPhone.trim();
      if (phone.isNotEmpty) {
        final sent = await WhatsAppService.isMessageAlreadySentToday(
          database: widget.database,
          phone: phone,
          studentId: s.id,
          category: 'cancellation',
          date: todayDateStr,
        );
        if (sent) sentStudentIds.add(s.id);
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (bCtx, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header with badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.send_rounded,
                          color: Color(0xFF25D366),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'إرسال إشعار الإلغاء لولي الأمر',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: activeColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'الخطوة الأخيرة',
                                    style: TextStyle(
                                      color: activeColor,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'مجموعة: ${group.name} (${students.length} طلاب مسجلين)',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Message preview card
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.mark_email_read_outlined, size: 14, color: Color(0xFF25D366)),
                            SizedBox(width: 6),
                            Text(
                              'نص رسالة الإشعار لولي الأمر:',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          defaultMessage,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Send to all button
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    icon: const Icon(Icons.forward_to_inbox_rounded, size: 18),
                    label: const Text(
                      'إرسال الإشعار لجميع أولياء الأمور عبر واتساب 📲',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () async {
                      final validStudents = students.where((s) => s.parentPhone.trim().isNotEmpty).toList();
                      if (validStudents.isNotEmpty && validStudents.every((s) => sentStudentIds.contains(s.id))) {
                        if (sheetCtx.mounted) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: const [
                                  Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'تم ارسال الاشعار مسبقا لولي الامر',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: const Color(0xFF059669),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                        return;
                      }

                      int sentCount = 0;
                      int alreadySentCount = 0;
                      for (final s in students) {
                        final phone = s.parentPhone.trim();
                        if (phone.isNotEmpty) {
                          String message;
                          if (isTeacher) {
                            message = WhatsAppService.teacherCancellationMessage(
                              centerName: centerName,
                              teacherName: teacherName,
                              groupName: group.name,
                              date: todayDateStr,
                              reason: reason,
                            );
                          } else {
                            message = WhatsAppService.studentCancellationMessage(
                              centerName: centerName,
                              teacherName: teacherName,
                              studentName: s.fullName,
                              groupName: group.name,
                              date: todayDateStr,
                              reason: reason,
                            );
                          }

                          final result = await WhatsAppService.dispatchMessageDetailed(
                            database: widget.database,
                            phone: phone,
                            message: message,
                            studentId: s.id,
                            studentName: s.fullName,
                            category: 'cancellation',
                          );
                          sentStudentIds.add(s.id);
                          if (result.alreadySent) {
                            alreadySentCount++;
                          } else {
                            sentCount++;
                          }
                        }
                      }
                      await widget.database.markSessionCancellationNoticeSent(
                        groupId: group.id,
                        date: todayDateStr,
                      );
                      groupCancellationNoticeSent[group.id] = true;
                      setSheetState(() {});
                      if (sheetCtx.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    alreadySentCount > 0 && sentCount == 0
                                        ? 'تم ارسال الاشعار مسبقا لولي الامر'
                                        : 'تم إرسال إشعار الإلغاء لـ ${sentCount + alreadySentCount} من أولياء الأمور بنجاح 📲✅',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF059669),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),

                  // Student parent list
                  Expanded(
                    child: ListView.separated(
                      itemCount: students.length,
                      separatorBuilder: (_, __) => const Divider(height: 8),
                      itemBuilder: (lCtx, index) {
                        final s = students[index];
                        final phone = s.parentPhone.trim();
                        final isSent = sentStudentIds.contains(s.id);

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 17,
                            backgroundColor: (isSent ? const Color(0xFF25D366) : activeColor).withValues(alpha: 0.12),
                            child: Icon(
                              isSent ? Icons.check_circle_rounded : Icons.person_outline_rounded,
                              size: 18,
                              color: isSent ? const Color(0xFF25D366) : activeColor,
                            ),
                          ),
                          title: Text(
                            s.fullName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            phone.isNotEmpty
                                ? 'ولي الأمر: $phone'
                                : '⚠️ لا يوجد هاتف مسجل لولي الأمر',
                            style: TextStyle(
                              fontSize: 11,
                              color: phone.isNotEmpty
                                  ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
                                  : Colors.orange,
                            ),
                          ),
                          trailing: phone.isNotEmpty
                              ? (isSent
                                  ? InkWell(
                                      onTap: () {
                                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: const [
                                                Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                                                SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'تم ارسال الاشعار مسبقا لولي الامر',
                                                    style: TextStyle(fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                            backgroundColor: const Color(0xFF059669),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF25D366).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF059669)),
                                            SizedBox(width: 4),
                                            Text(
                                              'تم الإرسال مسبقاً ✓',
                                              style: TextStyle(
                                                color: Color(0xFF059669),
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.send_rounded, color: Color(0xFF25D366), size: 20),
                                      tooltip: 'إرسال إشعار لولي الأمر عبر واتساب',
                                      onPressed: () async {
                                        String message;
                                        if (isTeacher) {
                                          message = WhatsAppService.teacherCancellationMessage(
                                            centerName: centerName,
                                            teacherName: teacherName,
                                            groupName: group.name,
                                            date: todayDateStr,
                                            reason: reason,
                                          );
                                        } else {
                                          message = WhatsAppService.studentCancellationMessage(
                                            centerName: centerName,
                                            teacherName: teacherName,
                                            studentName: s.fullName,
                                            groupName: group.name,
                                            date: todayDateStr,
                                            reason: reason,
                                          );
                                        }

                                        final result = await WhatsAppService.dispatchMessageDetailed(
                                          database: widget.database,
                                          phone: phone,
                                          message: message,
                                          studentId: s.id,
                                          studentName: s.fullName,
                                          category: 'cancellation',
                                        );

                                        await widget.database.markSessionCancellationNoticeSent(
                                          groupId: group.id,
                                          date: todayDateStr,
                                        );
                                        groupCancellationNoticeSent[group.id] = true;

                                        setSheetState(() {
                                          sentStudentIds.add(s.id);
                                        });

                                        if (sheetCtx.mounted) {
                                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      result.alreadySent
                                                          ? 'تم ارسال الاشعار مسبقا لولي الامر'
                                                          : 'تم إرسال إشعار الإلغاء لولي أمر (${s.fullName}) بنجاح 📲✅',
                                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              behavior: SnackBarBehavior.floating,
                                              backgroundColor: const Color(0xFF059669),
                                            ),
                                          );
                                        }
                                      },
                                    ))
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: SectionTopBar(
        title: 'التحضير',
        icon: Icons.fact_check_rounded,
        onBack: widget.onBack,
        actionLabel: 'مسح QR',
        actionIcon: Icons.qr_code_scanner_rounded,
        onAction: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScannerScreen(database: widget.database),
            ),
          ).then((_) => _loadGroupsData());
        },
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadGroupsData,
              child: ListView(
                key: const PageStorageKey<String>('today_attendance_groups_list_scroll'),
                padding: const EdgeInsets.all(18),
                children: [
                  // Pending Sessions & Unfinished Attendance Alerts Section
                  if (pendingSessionsAlerts.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [
                                  const Color(0xFF7C2D12).withValues(alpha: 0.35),
                                  const Color(0xFF451A03).withValues(alpha: 0.25),
                                ]
                              : [
                                  const Color(0xFFFFFBEB),
                                  const Color(0xFFFEF3C7),
                                ],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : const Color(0xFFF59E0B),
                          width: 1.3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: () => setState(() => isAlertsExpanded = !isAlertsExpanded),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.warning_amber_rounded,
                                      color: Color(0xFFD97706),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Flexible(
                                              child: Text(
                                                'قسم التحذيرات ⚠️',
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFFB45309),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFD97706),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                '${pendingSessionsAlerts.length}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isAlertsExpanded
                                              ? 'حصص تحتاج استكمال الشرح أو التقرير (انقر للطي)'
                                              : 'يوجد (${pendingSessionsAlerts.length}) حصة معلقة (انقر للمعاينة والاستكمال)',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? Colors.grey.shade400 : Colors.brown.shade700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD97706).withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isAlertsExpanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      color: const Color(0xFFD97706),
                                      size: 22,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isAlertsExpanded) ...[
                            const SizedBox(height: 10),
                            ...pendingSessionsAlerts.map((p) {
                              final gId = p['group_id'] as String;
                              final gName = p['group_name'] as String;
                              final dStr = p['date'] as String;
                              final grade = p['grade'] as String;
                              final presentCount = p['present_count'] as int;
                              final totalCount = p['total_students'] as int;
                              final hasLesson = p['has_lesson'] as bool;

                              return Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            gName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.calendar_today_rounded,
                                                size: 11,
                                                color: Color(0xFF2563EB),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                dStr,
                                                style: const TextStyle(
                                                  color: Color(0xFF2563EB),
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            hasLesson
                                                ? 'تم تسجيل الحضور ($presentCount/$totalCount) • متبقي إرسال التقرير'
                                                : 'تم رصد الحضور ($presentCount/$totalCount) • لم يُسجل المنهج بعد ⚠️',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: hasLesson ? const Color(0xFF059669) : const Color(0xFFD97706),
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFFD97706),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            visualDensity: VisualDensity.compact,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          icon: const Icon(Icons.edit_note_rounded, size: 14),
                                          label: const Text(
                                            'استكمال ✍️',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                          onPressed: () {
                                            final targetGroup = allGroups.where((g) => g.id == gId).firstOrNull;
                                            if (targetGroup != null) {
                                              _openGroupAttendanceSheet(
                                                targetGroup,
                                                customDate: dStr,
                                              );
                                            } else {
                                              final dummyGroup = GroupModel(
                                                id: gId,
                                                name: gName,
                                                stage: 'عام',
                                                grade: grade,
                                                schedule: '',
                                                monthlyPrice: 0,
                                              );
                                              _openGroupAttendanceSheet(
                                                dummyGroup,
                                                customDate: dStr,
                                              );
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // Today Banner Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withValues(alpha: 0.8),
                        ],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.25,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'جدول يوم $todayArabicDay',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            InkWell(
                              onTap: () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(now.year - 1),
                                  lastDate: DateTime(now.year + 1),
                                  helpText: 'اختر تاريخ كشف الحضور والتحضير',
                                  cancelText: 'إلغاء',
                                  confirmText: 'اختيار',
                                );
                                if (picked != null) {
                                  setState(() {
                                    selectedDate = picked;
                                    todayDateStr = picked.toIso8601String().substring(0, 10);
                                    todayArabicDay = _getArabicDayName(picked.weekday);
                                    filterTodayOnly = false; // Show groups when browsing custom dates
                                  });
                                  await _loadGroupsData();
                                }
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.calendar_month_rounded, size: 14, color: Colors.white),
                                    const SizedBox(width: 4),
                                    Text(
                                      todayDateStr,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'اضغط على أي مجموعة لبدء رصد الحضور اليدوي أو عبر الـ QR فورياً.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (todayDateStr != DateTime.now().toIso8601String().substring(0, 10))
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.today_rounded, size: 14),
                                label: const Text('العودة لليوم', style: TextStyle(fontSize: 11)),
                                onPressed: () {
                                  final now = DateTime.now();
                                  setState(() {
                                    selectedDate = now;
                                    todayDateStr = now.toIso8601String().substring(0, 10);
                                    todayArabicDay = _getArabicDayName(now.weekday);
                                    filterTodayOnly = true;
                                  });
                                  _loadGroupsData();
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Filter Switch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          filterTodayOnly
                              ? 'مجموعات حصص اليوم ($todayArabicDay)'
                              : 'جميع المجموعات الدراسية',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: Icon(
                          filterTodayOnly
                              ? Icons.filter_alt
                              : Icons.filter_alt_outlined,
                          size: 18,
                        ),
                        label: Text(
                          filterTodayOnly ? 'عرض الكل' : 'مجموعات اليوم فقط',
                        ),
                        onPressed: () =>
                            setState(() => filterTodayOnly = !filterTodayOnly),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (displayGroups.isEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.event_busy_rounded,
                                size: 44,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              filterTodayOnly
                                  ? 'لا توجد مجموعات مجدولة ليوم $todayArabicDay'
                                  : 'لا توجد أي مجموعات مسجلة',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              filterTodayOnly
                                  ? 'لا توجد حصص مجدولة لهذا اليوم. يمكنك الضغط على "عرض الكل" لتحضير أي مجموعة أخرى.'
                                  : 'قم بإضافة مجموعات جديدة من شاشة المجموعات',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                            if (filterTodayOnly && allGroups.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () => setState(() => filterTodayOnly = false),
                                icon: const Icon(Icons.people_outline_rounded, size: 18),
                                label: Text('عرض جميع المجموعات (${allGroups.length})'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  else
                    ...displayGroups.map((group) {
                      final total = groupTotalStudents[group.id] ?? 0;
                      final present = groupPresentStudents[group.id] ?? 0;
                      final marked = groupMarkedStudents[group.id] ?? 0;
                      final percent = total > 0
                          ? (present / total * 100).toInt()
                          : 0;
                      final isToday = group.schedule.contains(todayArabicDay) ||
                          group.days.contains(todayArabicDay);
                      final finalExSession = todayExceptionalSessions
                          .where((ex) => ex.groupId == group.id)
                          .firstOrNull;
                      final groupCancelInfo = todayCancelledGroups[group.id];
                      final bool isGroupCancelled = groupCancelInfo != null;
                      final bool isCancelledByTeacher = groupCancelInfo?['cancelled_by'] == 'teacher';

                      final todayLog = groupTodaySessionLogs[group.id];
                      final bool isAttendanceTaken = total > 0 &&
                          (marked > 0 && (marked == total || present > 0));
                      final bool isAttendanceCompleted = total > 0 && marked == total;
                      final bool hasLessonRecorded = todayLog != null &&
                          todayLog.lessonTitle.trim().isNotEmpty &&
                          todayLog.lessonTitle.trim() != 'حصة دراسية اعتيادية';
                      final String lessonTitle = todayLog?.lessonTitle.trim() ?? '';
                      final bool isGroupReadyForReport = isAttendanceTaken && hasLessonRecorded;
                      final bool isReportSent = groupReportSentStatus[group.id] == true;
                      final bool isLocked = groupLockedStatus[group.id] == true;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: isLocked ? 0.5 : 1,
                        color: isLocked
                            ? (isDark
                                ? const Color(0xFF1E293B).withValues(alpha: 0.55)
                                : const Color(0xFFF1F5F9))
                            : (isGroupCancelled
                                ? (isDark
                                    ? (isCancelledByTeacher
                                        ? Colors.red.withValues(alpha: 0.08)
                                        : Colors.purple.withValues(alpha: 0.08))
                                    : (isCancelledByTeacher
                                        ? const Color(0xFFFEF2F2)
                                        : const Color(0xFFFAF5FF)))
                                : (isGroupReadyForReport
                                    ? (isDark
                                        ? const Color(0xFF064E3B).withValues(alpha: 0.12)
                                        : const Color(0xFFF0FDF4))
                                    : null)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: isLocked
                              ? BorderSide(
                                  color: Colors.red.shade300.withValues(alpha: 0.4),
                                  width: 1.2,
                                )
                              : (isGroupCancelled
                                  ? BorderSide(
                                      color: isCancelledByTeacher ? Colors.red.shade400 : Colors.purple.shade400,
                                      width: 1.2,
                                    )
                                  : (isGroupReadyForReport
                                      ? const BorderSide(color: Color(0xFF10B981), width: 1.2)
                                      : (isDark
                                          ? const BorderSide(color: Color(0xFF334155))
                                          : BorderSide.none))),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            InkWell(
                              onTap: () => _openGroupAttendanceSheet(group),
                              borderRadius: BorderRadius.circular(14),
                              child: Opacity(
                                opacity: isLocked ? 0.70 : 1.0,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top row: Avatar + Name & Schedule + Status Tag + Chevron
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: isGroupCancelled
                                          ? (isCancelledByTeacher
                                              ? Colors.red.withValues(alpha: 0.12)
                                              : Colors.purple.withValues(alpha: 0.12))
                                          : (isGroupReadyForReport
                                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                              : theme.colorScheme.primary.withValues(alpha: 0.12)),
                                      child: Icon(
                                        isGroupCancelled
                                            ? (isCancelledByTeacher
                                                ? Icons.event_busy_rounded
                                                : Icons.person_off_rounded)
                                            : (isGroupReadyForReport
                                                ? Icons.task_alt_rounded
                                                : Icons.groups_rounded),
                                        size: 19,
                                        color: isGroupCancelled
                                            ? (isCancelledByTeacher ? Colors.red : Colors.purple)
                                            : (isGroupReadyForReport
                                                ? const Color(0xFF059669)
                                                : theme.colorScheme.primary),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  group.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (!group.isActive)
                                                Container(
                                                  margin: const EdgeInsets.only(right: 4),
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.amber.shade700, width: 0.6),
                                                  ),
                                                  child: const Text(
                                                    'متوقفة ⏸️',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.amber,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${group.grade} • ${group.schedule}',
                                            style: TextStyle(
                                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (isGroupCancelled)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: (isCancelledByTeacher ? Colors.red : Colors.purple).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: (isCancelledByTeacher ? Colors.red : Colors.purple).withValues(alpha: 0.4),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          isCancelledByTeacher ? 'ملغية (المعلم) 🚫' : 'ملغية (الطلاب) ⚠️',
                                          style: TextStyle(
                                            color: isCancelledByTeacher ? Colors.red.shade700 : Colors.purple.shade700,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    else if (finalExSession != null)
                                      InkWell(
                                        onTap: () => _confirmDeleteExceptionalSession(finalExSession),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                finalExSession.scale == 'double' ? '⚡ دوبل 2x' : '⚡ استثنائية',
                                                style: const TextStyle(color: Color(0xFFD97706), fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(Icons.close_rounded, size: 12, color: Color(0xFFD97706)),
                                            ],
                                          ),
                                        ),
                                      )
                                    else if (isToday)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'اليوم',
                                          style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.chevron_left,
                                      size: 18,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),

                                // Status row: Attendance status & Lesson title (Clear & Proportional)
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    if (isGroupCancelled) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: (isCancelledByTeacher ? Colors.red : Colors.purple).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isCancelledByTeacher ? Icons.cancel_outlined : Icons.person_off_rounded,
                                              size: 12,
                                              color: isCancelledByTeacher ? Colors.red : Colors.purple,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              'حصة ملغية',
                                              style: TextStyle(
                                                color: isCancelledByTeacher ? Colors.red : Colors.purple,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          groupCancellationNoticeSent[group.id] == true
                                              ? 'تم إرسال التنبيه لولي الأمر ✅'
                                              : 'لم يتم إرسال تنبيه الإلغاء بعد ⚠️',
                                          style: TextStyle(
                                            color: groupCancellationNoticeSent[group.id] == true
                                                ? const Color(0xFF059669)
                                                : Colors.amber.shade800,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ] else if (isGroupReadyForReport) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF059669)),
                                            SizedBox(width: 3),
                                            Text(
                                              'تم التحضير',
                                              style: TextStyle(color: Color(0xFF065F46), fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '📖 $lessonTitle',
                                          style: const TextStyle(
                                            color: Color(0xFF2563EB),
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ] else if (isAttendanceTaken) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.done_rounded, size: 12, color: Colors.teal),
                                            const SizedBox(width: 3),
                                            Text(
                                              isAttendanceCompleted ? 'تم التحضير بالكامل' : 'تم رصد الحضور',
                                              style: const TextStyle(color: Colors.teal, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '⚠️ المنهج لم يُسجل بعد',
                                          style: TextStyle(
                                            color: Colors.amber.shade800,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ] else ...[
                                      Icon(Icons.schedule_rounded, size: 13, color: Colors.grey.shade500),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'بانتظار رصد حضور الطلاب',
                                          style: TextStyle(
                                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                            fontSize: 11,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Attendance Progress Bar or Cancellation Notice
                                if (isGroupCancelled)
                                  Builder(
                                    builder: (context) {
                                      final bool isNoticeAlreadySent =
                                          groupCancellationNoticeSent[group.id] == true;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: (isCancelledByTeacher ? Colors.red : Colors.purple).withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: (isCancelledByTeacher ? Colors.red : Colors.purple).withValues(alpha: 0.25),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  isCancelledByTeacher ? Icons.event_busy_rounded : Icons.person_off_rounded,
                                                  size: 16,
                                                  color: isCancelledByTeacher ? Colors.red : Colors.purple,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        isCancelledByTeacher
                                                            ? 'الحصة ملغاة من جهة المعلم 🚫'
                                                            : 'الحصة ملغاة باعتذار من الطلاب ⚠️',
                                                        style: TextStyle(
                                                          color: isCancelledByTeacher ? Colors.red.shade800 : Colors.purple.shade800,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      if ((groupCancelInfo['reason'] ?? '').toString().isNotEmpty) ...[
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          'السبب: ${groupCancelInfo['reason']}',
                                                          style: TextStyle(
                                                            color: isCancelledByTeacher ? Colors.red.shade700 : Colors.purple.shade700,
                                                            fontSize: 11,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                InkWell(
                                                  onTap: () {
                                                    if (isNoticeAlreadySent) {
                                                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(
                                                          content: Row(
                                                            children: [
                                                              Icon(Icons.info_outline, color: Colors.white, size: 20),
                                                              SizedBox(width: 8),
                                                              Expanded(
                                                                child: Text(
                                                                  'تم ارسال الاشعار مسبقا لولي الامر',
                                                                  style: TextStyle(fontWeight: FontWeight.bold),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          behavior: SnackBarBehavior.floating,
                                                          backgroundColor: Color(0xFF059669),
                                                        ),
                                                      );
                                                    }
                                                    _showGroupCancellationDialog(group);
                                                  },
                                                  borderRadius: BorderRadius.circular(6),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: (isCancelledByTeacher ? Colors.red : Colors.purple).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.tune_rounded,
                                                          size: 13,
                                                          color: isCancelledByTeacher ? Colors.red : Colors.purple,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'متابعة الإلغاء',
                                                          style: TextStyle(
                                                            color: isCancelledByTeacher ? Colors.red : Colors.purple,
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (isNoticeAlreadySent) ...[
                                              const SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF059669).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                                                ),
                                                child: const Row(
                                                  children: [
                                                    Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF059669)),
                                                    SizedBox(width: 5),
                                                    Expanded(
                                                      child: Text(
                                                        'تم ارسال الاشعار مسبقا لولي الامر ✅',
                                                        style: TextStyle(
                                                          color: Color(0xFF065F46),
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    style: OutlinedButton.styleFrom(
                                                      visualDensity: VisualDensity.compact,
                                                      foregroundColor: isNoticeAlreadySent ? const Color(0xFF059669) : const Color(0xFF25D366),
                                                      side: BorderSide(
                                                        color: isNoticeAlreadySent ? const Color(0xFF059669) : const Color(0xFF25D366),
                                                      ),
                                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                    icon: Icon(
                                                      isNoticeAlreadySent ? Icons.check_circle : Icons.send_rounded,
                                                      size: 14,
                                                    ),
                                                    label: Text(
                                                      isNoticeAlreadySent ? 'تم إرسال التنبيه ✅' : 'إرسال تنبيه 📲',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                                    ),
                                                    onPressed: () {
                                                      if (isNoticeAlreadySent) {
                                                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          const SnackBar(
                                                            content: Row(
                                                              children: [
                                                                Icon(Icons.info_outline, color: Colors.white, size: 20),
                                                                SizedBox(width: 8),
                                                                Expanded(
                                                                  child: Text(
                                                                    'تم ارسال الاشعار مسبقا لولي الامر',
                                                                    style: TextStyle(fontWeight: FontWeight.bold),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            behavior: SnackBarBehavior.floating,
                                                            backgroundColor: Color(0xFF059669),
                                                          ),
                                                        );
                                                      } else {
                                                        _showGroupCancellationNoticeSheet(
                                                          group: group,
                                                          isTeacher: isCancelledByTeacher,
                                                          reason: (groupCancelInfo['reason'] ?? 'ظروف طارئة').toString(),
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: FilledButton.tonalIcon(
                                                    style: FilledButton.styleFrom(
                                                      backgroundColor: Colors.teal.shade700,
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                    ),
                                                    icon: const Icon(Icons.settings_backup_restore_rounded, size: 14),
                                                    label: const Text(
                                                      'التراجع عن الإلغاء 🔄',
                                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                                    ),
                                                    onPressed: () => _uncancelGroupSession(group, openAttendanceAfter: true),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  )
                                else ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'حضور المجموعة: $present من $total طالب ($percent%)',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isGroupReadyForReport) ...[
                                            if (!isReportSent) ...[
                                              InkWell(
                                                onTap: () => _openWhatsAppSessionReport(group),
                                                borderRadius: BorderRadius.circular(6),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF25D366),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.send_rounded, size: 11, color: Colors.white),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'إرسال التقرير 📲',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ] else ...[
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.mark_chat_read_rounded, size: 11, color: Color(0xFF059669)),
                                                    SizedBox(width: 3),
                                                    Text(
                                                      'تم إرسال التقرير ✅',
                                                      style: TextStyle(
                                                        color: Color(0xFF059669),
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                          if (!isAttendanceTaken && !isReportSent && !isLocked) ...[
                                            if (isGroupReadyForReport && !isReportSent) const SizedBox(width: 6),
                                            InkWell(
                                              onTap: () => _showGroupCancellationDialog(group),
                                              borderRadius: BorderRadius.circular(6),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.withValues(alpha: 0.08),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: Colors.red.withValues(alpha: 0.25),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.event_busy_rounded, size: 12, color: Colors.red.shade700),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'إلغاء الحصة',
                                                      style: TextStyle(
                                                        color: Colors.red.shade700,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: total > 0 ? (present / total) : 0,
                                      minHeight: 6,
                                      backgroundColor: isDark
                                          ? const Color(0xFF334155)
                                          : Colors.grey.shade200,
                                      color: percent >= 70
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (isLocked)
                        PositionedDirectional(
                          end: 18,
                          top: 14,
                          child: _buildCircularSealStamp(isDark),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularSealStamp(bool isDark) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: -0.16, // authentic tilted ink stamp angle
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFDC2626).withValues(alpha: isDark ? 0.9 : 0.85),
              width: 2.2,
            ),
            color: const Color(0xFFDC2626).withValues(alpha: isDark ? 0.16 : 0.08),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.12),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3.5),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFDC2626).withValues(alpha: 0.55),
                width: 1.0,
              ),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 13,
                  color: Color(0xFFDC2626),
                ),
                SizedBox(height: 1),
                Text(
                  'تم التحضير',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 9.2,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'معتمدة ومغلقة 🔒',
                  style: TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 7.5,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'لعدم التعديل',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 7.0,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// شيت رصد الحضور التفاعلي ودفتر الحصة والتسميع للمجموعة
// ==========================================
class GroupAttendanceSheet extends StatefulWidget {
  const GroupAttendanceSheet({
    super.key,
    required this.database,
    required this.group,
    required this.date,
    this.latestLog,
    required this.onAttendanceUpdated,
    this.initialSessionType,
  });

  final DatabaseService database;
  final GroupModel group;
  final String date;
  final SessionLogModel? latestLog;
  final VoidCallback onAttendanceUpdated;
  final String? initialSessionType;

  @override
  State<GroupAttendanceSheet> createState() => _GroupAttendanceSheetState();
}

class _GroupAttendanceSheetState extends State<GroupAttendanceSheet> {
  List<Map<String, dynamic>> students = [];
  List<CurriculumLessonModel> groupLessons = [];
  bool isLoading = true;
  bool isNotebookExpanded = false;
  bool isSessionLocked = false;
  String sessionType = 'regular'; // 'regular' or 'double'
  Map<String, dynamic>? teacherCancellation;
  bool get isSessionCancelledByTeacher => teacherCancellation != null;

  late TextEditingController topicController;
  late TextEditingController contentController;
  late TextEditingController homeworkController;
  late TextEditingController nextTopicController;
  late TextEditingController prevHomeworkController;
  late TextEditingController prevLessonController;
  late TextEditingController notesController;

  @override
  void initState() {
    super.initState();
    sessionType = widget.initialSessionType ?? 'regular';
    topicController = TextEditingController(
      text: widget.latestLog?.lessonTitle ?? '',
    );
    contentController = TextEditingController(
      text: widget.latestLog?.contentCovered ?? '',
    );
    homeworkController = TextEditingController(
      text: widget.latestLog?.homework ?? '',
    );
    nextTopicController = TextEditingController(
      text: widget.latestLog?.nextTopic ?? '',
    );
    prevHomeworkController = TextEditingController(
      text: widget.latestLog?.previousHomeworkReview ?? '',
    );
    prevLessonController = TextEditingController(
      text: widget.latestLog?.previousLessonReview ?? '',
    );
    notesController = TextEditingController(
      text: widget.latestLog?.notes ?? '',
    );
    _loadInitialData();
  }

  @override
  void dispose() {
    topicController.dispose();
    contentController.dispose();
    homeworkController.dispose();
    nextTopicController.dispose();
    prevHomeworkController.dispose();
    prevLessonController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => isLoading = true);
    final data = await widget.database.getGroupStudentsWithAttendance(
      groupId: widget.group.id,
      date: widget.date,
    );

    final bindings = await widget.database.getGroupCurriculumBindings();
    final myBinding = bindings
        .where((b) => b['id'] == widget.group.id)
        .firstOrNull;
    final boundCurriculum = myBinding?['curriculum_name'] as String?;
    final lessons = await widget.database.getCurriculumLessons(
      curriculumName: boundCurriculum,
      grade: widget.group.grade,
    );

    final lockVal = await widget.database.getSetting(
      'attendance_lock_${widget.group.id}_${widget.date}',
      defaultValue: 'false',
    );
    final savedType = await widget.database.getSetting(
      'session_type_${widget.group.id}_${widget.date}',
      defaultValue: widget.initialSessionType ?? 'regular',
    );
    final cancelInfo = await widget.database.getGroupSessionCancellation(
      groupId: widget.group.id,
      date: widget.date,
    );
    if (mounted) {
      final studentList = List<Map<String, dynamic>>.from(
        data.map((m) => Map<String, dynamic>.from(m)),
      );
      setState(() {
        students = studentList;
        groupLessons = lessons;
        isSessionLocked = lockVal == 'true';
        sessionType = savedType;
        teacherCancellation = cancelInfo;
        isLoading = false;
      });
    }
  }

  Future<void> _setSessionType(String type) async {
    if (isSessionLocked) {
      _showLockedNotice();
      return;
    }
    setState(() => sessionType = type);
    await widget.database.setSetting(
      'session_type_${widget.group.id}_${widget.date}',
      type,
    );
    for (final s in students) {
      if (s['attendance_status'] != null) {
        await widget.database.setStudentAttendanceStatus(
          studentId: s['id'] as String,
          date: widget.date,
          status: s['attendance_status'] as String,
          sessionType: type,
        );
      }
    }

    await _loadStudentsOnly();
    widget.onAttendanceUpdated();
  }

  void _showLockedNotice() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.amber.shade900,
        behavior: SnackBarBehavior.floating,
        content: const Row(
          children: [
            Icon(Icons.lock, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'الجلسة مقفلة ومعتمدة لمنع التلاعب! انقر "إلغاء القفل بالبصمة" أولاً 🔒',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _lockAttendanceAndSendAbsenceAlerts() async {
    await widget.database.setSetting(
      'attendance_lock_${widget.group.id}_${widget.date}',
      'true',
    );
    if (mounted) {
      setState(() => isSessionLocked = true);
    }

    // Strict Lock: Lock attendance securely without background WhatsApp spam
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
          content: const Text(
            'تم اعتماد وقفل كشف الحضور رسمياً 🔒 ومحمي بنجاح',
          ),
        ),
      );
    }
  }

  Future<void> _unlockAttendanceWithSecurity() async {
    final authOk = await SecurityService.authenticate(
      context: context,
      database: widget.database,
      reason: 'تأكيد الهوية لإلغاء قفل وتعديل كشف الحضور',
    );
    if (authOk) {
      await widget.database.setSetting(
        'attendance_lock_${widget.group.id}_${widget.date}',
        'false',
      );
      if (mounted) {
        setState(() => isSessionLocked = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.blueAccent,
            behavior: SnackBarBehavior.floating,
            content: Text('تم إلغاء القفل بنجاح، يمكنك تعديل الحضور الآن 🔓'),
          ),
        );
      }
    }
  }

  Future<void> _updateStatus(
    String studentId,
    String? status,
    String studentName,
  ) async {
    if (isSessionLocked) {
      _showLockedNotice();
      return;
    }

    // Instant optimistic UI update so the button lights up immediately
    setState(() {
      final index = students.indexWhere((s) => s['id'] == studentId);
      if (index != -1) {
        final updated = Map<String, dynamic>.from(students[index]);
        updated['attendance_status'] = status;
        students[index] = updated;
      }
    });

    try {
      if (status == null || status.isEmpty || status == 'unmarked') {
        await widget.database.deleteStudentAttendance(
          studentId: studentId,
          date: widget.date,
        );
        await widget.database.deleteSessionCancellation(
          groupId: widget.group.id,
          date: widget.date,
          studentId: studentId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم ضبط حالة الطالب ($studentName) إلى (لم يحدد) 🔄'),
              backgroundColor: Colors.blueGrey,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        await widget.database.setStudentAttendanceStatus(
          studentId: studentId,
          date: widget.date,
          status: status,
          sessionType: sessionType,
        );

        if (status == 'cancelled_student') {
          await widget.database.recordSessionCancellation(
            groupId: widget.group.id,
            date: widget.date,
            cancelledBy: 'student',
            studentId: studentId,
            reason: 'اعتذار مسبق عن الحصة من جهة الطالب',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'تم تسجيل اعتذار وإلغاء الحصة للطالب ($studentName) ⚠️',
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.purple.shade800,
              ),
            );
          }
        } else if (status == 'cancelled_teacher') {
          await widget.database.recordSessionCancellation(
            groupId: widget.group.id,
            date: widget.date,
            cancelledBy: 'teacher',
            studentId: studentId,
            reason: 'إلغاء الحصة للطالب من جهة المعلم',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'تم إلغاء الحصة للطالب ($studentName) من جهة المعلم 🚫',
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.red.shade900,
              ),
            );
          }
        } else {
          await widget.database.deleteSessionCancellation(
            groupId: widget.group.id,
            date: widget.date,
            studentId: studentId,
          );
        }

        if (status == 'absent') {
          NotificationService.showAbsenceAlert(
            studentName: studentName,
            groupName: widget.group.name,
          );
        } else if (status == 'present') {
          if (mounted) {
            final nowTime = TimeOfDay.now().format(context);
            NotificationService.showAttendanceConfirmation(
              studentName: studentName,
              time: nowTime,
            );
          }
        }
      }

      // Process automated session billing and financial claims
      final billingResult = await widget.database
          .processAttendanceSessionBilling(
            group: widget.group,
            studentId: studentId,
            studentName: studentName,
            date: widget.date,
            status: status,
          );

      if (billingResult['applied'] == true && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (billingResult['reverted'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم إلغاء واسترجاع مبلغ الحصة (${(billingResult['amount'] as num?)?.toStringAsFixed(0)} ج.م) من حساب $studentName 🔄',
              ),
              backgroundColor: Colors.blueGrey,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '🔔 مطالبة مالية فورية: تم تسجيل حضور $studentName وإضافة ${(billingResult['amount'] as num?)?.toStringAsFixed(0)} ج.م للمطالبات (مطالبة فردية) 💰',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: const Color(0xFF059669),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e, stack) {
      debugPrint('Error updating student attendance: $e\n$stack');
    } finally {
      await _loadStudentsOnly();
      widget.onAttendanceUpdated();
    }
  }

  DateTime? _parseTimeStr(String timeStr) {
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPm = clean.contains('PM') || clean.contains('م');
      final digits = clean.replaceAll(RegExp(r'[^0-9:]'), '');
      final parts = digits.split(':');
      if (parts.length >= 2) {
        int h = int.parse(parts[0]);
        int m = int.parse(parts[1]);
        if (isPm && h < 12) h += 12;
        if (!isPm && h == 12) h = 0;
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day, h, m);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadStudentsOnly() async {
    final data = await widget.database.getGroupStudentsWithAttendance(
      groupId: widget.group.id,
      date: widget.date,
    );
    if (mounted) {
      final studentList = List<Map<String, dynamic>>.from(
        data.map((m) => Map<String, dynamic>.from(m)),
      );
      setState(() => students = studentList);
    }
  }

  Future<void> _updateStudentRecitation(String studentId, String rating) async {
    if (isSessionLocked) {
      _showLockedNotice();
      return;
    }
    await widget.database.updateStudentAttendanceDetails(
      studentId: studentId,
      date: widget.date,
      recitationRating: rating,
    );
    await _loadStudentsOnly();
  }

  Future<void> _updateStudentHomework(String studentId, String hwStatus) async {
    if (isSessionLocked) {
      _showLockedNotice();
      return;
    }
    await widget.database.updateStudentAttendanceDetails(
      studentId: studentId,
      date: widget.date,
      homeworkStatus: hwStatus,
    );
    await _loadStudentsOnly();
  }

  Future<void> _markAll(String status) async {
    if (isSessionLocked) {
      _showLockedNotice();
      return;
    }
    await widget.database.markAllGroupAttendance(
      groupId: widget.group.id,
      date: widget.date,
      status: status,
      sessionType: sessionType,
    );
    await _loadStudentsOnly();
    widget.onAttendanceUpdated();
  }

  Future<void> _saveSessionNotebook() async {
    final log = SessionLogModel(
      groupId: widget.group.id,
      date: widget.date,
      lessonTitle: topicController.text.trim().isNotEmpty
          ? topicController.text.trim()
          : 'حصة دراسية اعتيادية',
      contentCovered: contentController.text.trim().isNotEmpty
          ? contentController.text.trim()
          : topicController.text.trim(),
      homework: homeworkController.text.trim(),
      nextTopic: nextTopicController.text.trim(),
      previousHomeworkReview: prevHomeworkController.text.trim(),
      previousLessonReview: prevLessonController.text.trim(),
      notes: notesController.text.trim(),
    );
    await widget.database.saveSessionLog(log);
    await widget.database.setSetting(
      'attendance_lock_${widget.group.id}_${widget.date}',
      'true',
    );
    widget.onAttendanceUpdated();
    if (mounted) {
      setState(() {
        isNotebookExpanded = false;
        isSessionLocked = true;
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم حفظ دفتر الحصة وقفلها رسمياً 🔒 لعدم التلاعب في بيانات الطلاب',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'إرسال لولي الأمر 📲',
            textColor: Colors.white,
            onPressed: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) => GroupSessionReportSheet(
                  group: widget.group,
                  database: widget.database,
                  date: widget.date,
                ),
              );
            },
          ),
        ),
      );
    }
  }

  void _showLessonPicker() async {
    final progressMap = await widget.database.getGroupLessonProgressMap(
      widget.group.id,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return AttendanceLessonPickerSheet(
          groupLessons: groupLessons,
          group: widget.group,
          date: widget.date,
          initialProgressMap: progressMap,
          initialTopic: topicController.text,
          database: widget.database,
          isPreviousLessonMode: false,
          onConfirmed: (selectedLessons) async {
            if (selectedLessons.isEmpty) return;
            setState(() {
              if (selectedLessons.length == 1) {
                final l = selectedLessons.first;
                topicController.text = '${l.unitName} - ${l.lessonTitle}';
                if (l.objectives.isNotEmpty) {
                  contentController.text = l.objectives;
                }
              } else {
                final titles = selectedLessons
                    .map((l) => l.lessonTitle)
                    .join(' + ');
                final unit = selectedLessons.first.unitName;
                topicController.text = '$unit: $titles';
                final objectives = selectedLessons
                    .where((l) => l.objectives.isNotEmpty)
                    .map((l) => '• ${l.lessonTitle}: ${l.objectives}')
                    .join('\n');
                if (objectives.isNotEmpty) {
                  contentController.text = objectives;
                }
              }
              isNotebookExpanded = true;
            });

            // Auto-mark chosen lessons as 'current' for this group
            final ids = selectedLessons
                .map((l) => l.id)
                .whereType<int>()
                .toList();
            if (ids.isNotEmpty) {
              await widget.database.bulkSetGroupLessonProgress(
                groupId: widget.group.id,
                lessonIds: ids,
                status: 'current',
                taughtDate: widget.date,
              );
            }
          },
        );
      },
    );
  }

  void _showPreviousLessonPicker() async {
    final progressMap = await widget.database.getGroupLessonProgressMap(
      widget.group.id,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return AttendanceLessonPickerSheet(
          groupLessons: groupLessons,
          group: widget.group,
          date: widget.date,
          initialProgressMap: progressMap,
          initialTopic: prevLessonController.text,
          database: widget.database,
          isPreviousLessonMode: true,
          onConfirmed: (selectedLessons) {
            if (selectedLessons.isEmpty) return;
            setState(() {
              if (selectedLessons.length == 1) {
                final l = selectedLessons.first;
                prevLessonController.text =
                    'مراجعة: ${l.unitName} - ${l.lessonTitle}';
              } else {
                final titles = selectedLessons
                    .map((l) => l.lessonTitle)
                    .join(' + ');
                prevLessonController.text = 'مراجعة: $titles';
              }
              isNotebookExpanded = true;
            });
          },
        );
      },
    );
  }

  Future<void> _markAllPresentFast() async {
    if (isSessionLocked) {
      _showLockedNotice();
      return;
    }
    if (students.isEmpty) return;

    setState(() {
      for (final s in students) {
        s['attendance_status'] = 'present';
      }
    });

    await widget.database.markAllGroupAttendance(
      groupId: widget.group.id,
      date: widget.date,
      status: 'present',
      sessionType: sessionType,
    );

    for (final s in students) {
      final sId = s['id'] as String;
      final sName = s['full_name'] as String? ?? '';
      await widget.database.processAttendanceSessionBilling(
        group: widget.group,
        studentId: sId,
        studentName: sName,
        date: widget.date,
        status: 'present',
      );
    }

    await _loadStudentsOnly();
    widget.onAttendanceUpdated();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تحضير جميع الطلاب حاضر (${students.length} طالب) بضغطة واحدة ⚡',
          ),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _resetAllAttendanceFast() async {
    if (isSessionLocked) {
      _showLockedNotice();
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'تصفير الكشف',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'هل تريد إزالة حالات الحضور والغياب لجميع الطلاب في كشف هذه الحصة وإعادتهم إلى (لم يحدد)؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، تصفير الكشف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Instant optimistic UI reset
    setState(() {
      for (final s in students) {
        s['attendance_status'] = null;
      }
    });

    await widget.database.resetGroupAttendanceForDate(
      groupId: widget.group.id,
      date: widget.date,
    );
    await _loadStudentsOnly();
    widget.onAttendanceUpdated();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تصفير كشف الحضور وإعادة ضبط جميع الطلاب إلى (لم يحدد) 🔄'),
          backgroundColor: Colors.blueGrey,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sendSingleAbsenceAlert(Map<String, dynamic> student) async {
    final parentPhone = (student['parent_phone'] as String? ?? '').trim();
    final studentName = student['full_name'] as String? ?? '';
    final studentId = student['id']?.toString() ?? student['student_id']?.toString();
    if (parentPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم هاتف ولي الأمر غير مسجل')),
      );
      return;
    }

    final centerName = await widget.database.getSetting(
      'center_name',
      defaultValue: 'سنتر أستاذي',
    );
    final teacherName = await widget.database.getSetting(
      'teacher_name',
      defaultValue: 'الأستاذ',
    );

    final message = WhatsAppService.absenceMessage(
      centerName: centerName,
      teacherName: teacherName,
      studentName: studentName,
      date: widget.date,
    );

    final studentCode = student['code']?.toString() ?? studentId ?? '';
    final channel = await ReportDispatchHelper.dispatchReport(
      context: context,
      studentId: studentId ?? '',
      studentName: studentName,
      studentCode: studentCode,
      parentPhone: parentPhone,
      reportTitle: 'إشعار غياب عن الحصة 🚨',
      reportMessage: message,
      notifType: 'absence',
      database: widget.database,
    );

    if (channel != null && mounted) {
      // إغلاق النافذة الخاصة بتحضير المجموعة بعد تأكيد الإرسال
      Navigator.of(context).pop();
    }
  }

  Future<void> _sendSingleFollowupReport(Map<String, dynamic> student) async {
    final parentPhone = student['parent_phone'] as String? ?? '';
    final studentName = student['full_name'] as String? ?? '';
    if (parentPhone.isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'رقم هاتف ولي الأمر غير مسجل',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      return;
    }

    final centerName = await widget.database.getSetting(
      'center_name',
      defaultValue: 'سنتر أستاذي',
    );
    final teacherName = await widget.database.getSetting(
      'teacher_name',
      defaultValue: 'الأستاذ',
    );

    final attStatus = student['attendance_status'] as String? ?? 'present';
    final arabicStatus = attStatus == 'present'
        ? 'حاضر في الموعد ✅'
        : (attStatus == 'late'
              ? 'حاضر متأخر ⏰'
              : (attStatus == 'excused'
                    ? 'غياب بعذر مسبق 📝'
                    : (attStatus == 'cancelled_student'
                          ? 'إلغاء واعتذار مسبق من الطالب ⚠️'
                          : (attStatus == 'cancelled_teacher'
                                ? 'إلغاء الحصة من جهة المعلم 🚫'
                                : 'غائب 🚨'))));

    final recitation = student['recitation_rating'] as String?;
    final hwStatus = student['homework_status'] as String?;

    final message = WhatsAppService.sessionFollowUpMessage(
      centerName: centerName,
      teacherName: teacherName,
      studentName: studentName,
      groupName: widget.group.name,
      date: widget.date,
      lessonTitle: topicController.text.trim().isNotEmpty
          ? topicController.text.trim()
          : 'مقرر الحصة اليومي',
      lessonContent: contentController.text.trim().isNotEmpty
          ? contentController.text.trim()
          : null,
      homework: homeworkController.text.trim().isNotEmpty
          ? homeworkController.text.trim()
          : null,
      notes: notesController.text.trim().isNotEmpty
          ? notesController.text.trim()
          : null,
      attendanceStatus: arabicStatus,
      recitationRating: recitation,
      homeworkStatus: hwStatus,
      nextQuiz: nextTopicController.text.trim().isNotEmpty
          ? nextTopicController.text.trim()
          : null,
      previousHomeworkReview: prevHomeworkController.text.trim().isNotEmpty
          ? prevHomeworkController.text.trim()
          : null,
      previousLessonReview: prevLessonController.text.trim().isNotEmpty
          ? prevLessonController.text.trim()
          : null,
    );

    final studentId = student['id']?.toString() ?? student['student_id']?.toString() ?? '';
    final studentCode = student['code']?.toString() ?? studentId;
    await ReportDispatchHelper.dispatchReport(
      context: context,
      studentId: studentId,
      studentName: studentName,
      studentCode: studentCode,
      parentPhone: parentPhone,
      reportTitle: 'تقرير متابعة الحصة اليومية 📋',
      reportMessage: message,
      notifType: 'sessionFollowup',
      database: widget.database,
    );
  }

  void _showBulkAbsenceSheet(List<Map<String, dynamic>> absentStudents) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.campaign, color: Colors.red, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'إرسال تنبيهات غياب واتساب (${absentStudents.length} طلاب)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'إخطار أولياء الأمور بغياب أبنائهم عن حصة اليوم ${widget.date} - ${widget.group.name}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const Divider(height: 20),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: absentStudents.length,
                  itemBuilder: (c, i) {
                    final st = absentStudents[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.shade50,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        st['full_name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'ولي الأمر: ${st['parent_phone'] ?? "غير مسجل"}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.send, color: Color(0xFF25D366)),
                        tooltip: 'إرسال تنبيه واتساب',
                        onPressed: () => _sendSingleAbsenceAlert(st),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendStudentCancellationAlert(
    Map<String, dynamic> student,
  ) async {
    final parentPhone = (student['parent_phone'] as String? ?? '').trim();
    final studentName = student['full_name'] as String? ?? '';
    final studentId = student['id']?.toString() ?? student['student_id']?.toString();
    if (parentPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'رقم هاتف ولي الأمر غير مسجل',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      return;
    }

    final centerName = await widget.database.getSetting(
      'center_name',
      defaultValue: 'سنتر أستاذي',
    );
    final teacherName = await widget.database.getSetting(
      'teacher_name',
      defaultValue: 'الأستاذ',
    );

    final isTeacherCancelled =
        student['attendance_status'] == 'cancelled_teacher';
    final message = isTeacherCancelled
        ? WhatsAppService.teacherCancellationMessage(
            centerName: centerName,
            teacherName: teacherName,
            groupName: widget.group.name,
            date: widget.date,
            reason: 'ظروف خاصة من جهة المعلم',
          )
        : WhatsAppService.studentCancellationMessage(
            centerName: centerName,
            teacherName: teacherName,
            studentName: studentName,
            groupName: widget.group.name,
            date: widget.date,
            reason: 'اعتذار مسبق عن حضور الحصة',
          );

    final result = await WhatsAppService.dispatchMessageDetailed(
      database: widget.database,
      phone: parentPhone,
      message: message,
      studentId: studentId,
      studentName: studentName,
      category: 'cancellation',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF059669),
          content: Text(
            result.alreadySent
                ? 'تم إرسال إشعار اعتذار وإلغاء الحصة لولي أمر ($studentName) مسبقاً بنجاح ✅'
                : 'تم فتح إشعار اعتذار وإلغاء الحصة للطالب ($studentName) عبر واتساب 📲✅',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
  }

  Future<void> _showStudentCancellationOptionsDialog({
    required String studentId,
    required String studentName,
    required String? currentStatus,
  }) async {
    final studentData = students.where((s) => s['id'] == studentId).firstOrNull;
    final parentPhone = (studentData?['parent_phone'] as String? ?? '').trim();
    final isAlreadyCancelled =
        currentStatus == 'cancelled_student' ||
        currentStatus == 'cancelled_teacher';

    String cancelledBy = currentStatus == 'cancelled_teacher'
        ? 'teacher'
        : 'student';

    final studentReasons = [
      'اعتذار مسبق',
      'ظروف صحية / مرض',
      'سفر أو مناسبة',
      'امتحانات مدرسية',
      'ظروف خاصة',
    ];

    final teacherReasons = [
      'ظروف طارئة',
      'وعكة صحية',
      'سفر مفاجئ',
      'ارتباط تعليمي / إداري',
      'عطل فني / كهرباء',
    ];

    String selectedReason = cancelledBy == 'teacher'
        ? teacherReasons.first
        : studentReasons.first;
    final noteController = TextEditingController();
    bool shouldSendWhatsApp = true;
    bool shouldScheduleMakeup = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dlgCtx, setDlgState) {
            final isDark = Theme.of(dlgCtx).brightness == Brightness.dark;
            final isTeacher = cancelledBy == 'teacher';
            final activeColor = isTeacher ? Colors.red : Colors.purple;
            final reasons = isTeacher ? teacherReasons : studentReasons;

            return AlertDialog(
              scrollable: true,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isTeacher
                          ? Icons.event_busy_rounded
                          : Icons.person_off_rounded,
                      color: activeColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'خيارات إلغاء الحصة للطالب',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          studentName,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'اختر جهة الإلغاء / الاعتذار:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // خياري من جهة الطالب أو من جهة المعلم
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setDlgState(() {
                                cancelledBy = 'student';
                                selectedReason = studentReasons.first;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: !isTeacher
                                    ? Colors.purple.withValues(alpha: 0.15)
                                    : (isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: !isTeacher
                                      ? Colors.purple
                                      : (isDark
                                            ? const Color(0xFF334155)
                                            : Colors.grey.shade300),
                                  width: !isTeacher ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.person_outline_rounded,
                                    color: !isTeacher
                                        ? Colors.purple
                                        : Colors.grey,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'من جهة الطالب',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: !isTeacher
                                          ? Colors.purple
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    'اعتذار الطالب',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setDlgState(() {
                                cancelledBy = 'teacher';
                                selectedReason = teacherReasons.first;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isTeacher
                                    ? Colors.red.withValues(alpha: 0.15)
                                    : (isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isTeacher
                                      ? Colors.red
                                      : (isDark
                                            ? const Color(0xFF334155)
                                            : Colors.grey.shade300),
                                  width: isTeacher ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.school_outlined,
                                    color: isTeacher ? Colors.red : Colors.grey,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'من جهة المعلم',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: isTeacher
                                          ? Colors.red
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    'اعتذار المعلم',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // سبب الإلغاء
                    Text(
                      isTeacher ? 'سبب إلغاء المعلم:' : 'سبب اعتذار الطالب:',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: reasons.map((r) {
                        final isSel = selectedReason == r;
                        return ChoiceChip(
                          label: Text(
                            r,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSel
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          selected: isSel,
                          selectedColor: activeColor.withValues(alpha: 0.25),
                          side: BorderSide(
                            color: isSel
                                ? activeColor
                                : (isDark
                                      ? const Color(0xFF334155)
                                      : Colors.grey.shade300),
                          ),
                          onSelected: (_) =>
                              setDlgState(() => selectedReason = r),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'ملاحظة إضافية للسبب (اختياري)...',
                        hintStyle: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // جدولة حصة تعويضية
                    CheckboxListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: shouldScheduleMakeup,
                      activeColor: activeColor,
                      title: const Text(
                        'جدولة حصة تعويضية الآن 📅',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'تحديد موعد بديل لتعويض هذه الحصة قبل إشعار ولي الأمر',
                        style: TextStyle(fontSize: 10.5),
                      ),
                      onChanged: (v) =>
                          setDlgState(() => shouldScheduleMakeup = v ?? false),
                    ),

                    // إرسال رسالة تنبيه لولي الأمر (الخطوة الأخيرة)
                    CheckboxListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: shouldSendWhatsApp,
                      activeColor: const Color(0xFF25D366),
                      title: const Text(
                        'إرسال رسالة تنبيه لولي الأمر عبر واتساب 📲 (الخطوة الأخيرة)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        parentPhone.isNotEmpty
                            ? 'رقم ولي الأمر: $parentPhone (إشعار ولي الأمر كخطوة نهائية)'
                            : '⚠️ لا يوجد رقم هاتف مسجل لولي الأمر',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: parentPhone.isNotEmpty
                              ? (isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600)
                              : Colors.orange,
                        ),
                      ),
                      onChanged: (v) =>
                          setDlgState(() => shouldSendWhatsApp = v ?? true),
                    ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.end,
              actions: [
                if (isAlreadyCancelled)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    icon: const Icon(Icons.undo, size: 15),
                    label: const Text(
                      'إلغاء الاعتذار',
                      style: TextStyle(fontSize: 12),
                    ),
                    onPressed: () async {
                      Navigator.pop(dlgCtx);
                      await _updateStatus(studentId, 'present', studentName);
                    },
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dlgCtx),
                  child: const Text('تراجع'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: activeColor,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    'تأكيد الإلغاء (${isTeacher ? "المعلم" : "الطالب"})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    final fullReason = noteController.text.trim().isNotEmpty
                        ? '$selectedReason (${noteController.text.trim()})'
                        : selectedReason;

                    final newStatus = isTeacher
                        ? 'cancelled_teacher'
                        : 'cancelled_student';

                    Navigator.pop(dlgCtx);

                    // 1. Update status and record cancellation in database
                    await _updateStatus(studentId, newStatus, studentName);

                    await widget.database.recordSessionCancellation(
                      groupId: widget.group.id,
                      date: widget.date,
                      cancelledBy: isTeacher ? 'teacher' : 'student',
                      studentId: studentId,
                      reason: fullReason,
                    );

                    // 2. Open makeup session dialog first if selected
                    if (shouldScheduleMakeup && mounted) {
                      await showAddExceptionalSessionDialog(
                        context: context,
                        database: widget.database,
                        preselectedGroup: widget.group,
                        initialReason: isTeacher
                            ? 'teacher_makeup'
                            : 'student_makeup',
                        initialNotes:
                            'حصة تعويضية للطالب/ة: $studentName عن حصة ${widget.date} - السبب: $fullReason',
                        onSaved: () {
                          _loadStudentsOnly();
                          widget.onAttendanceUpdated();
                        },
                      );
                    }

                    // 3. FINAL STEP (الخطوة الأخيرة): Send notification to parent
                    if (shouldSendWhatsApp && parentPhone.isNotEmpty && mounted) {
                      final centerName = await widget.database.getSetting(
                        'center_name',
                        defaultValue: 'سنتر أستاذي',
                      );
                      final teacherName = await widget.database.getSetting(
                        'teacher_name',
                        defaultValue: 'الأستاذ',
                      );

                      String message;
                      if (isTeacher) {
                        message = WhatsAppService.teacherCancellationMessage(
                          centerName: centerName,
                          teacherName: teacherName,
                          groupName: widget.group.name,
                          date: widget.date,
                          reason: fullReason,
                        );
                      } else {
                        message = WhatsAppService.studentCancellationMessage(
                          centerName: centerName,
                          teacherName: teacherName,
                          studentName: studentName,
                          groupName: widget.group.name,
                          date: widget.date,
                          reason: fullReason,
                        );
                      }

                      await WhatsAppService.dispatchMessage(
                        database: widget.database,
                        phone: parentPhone,
                        message: message,
                        studentId: studentId,
                        studentName: studentName,
                        category: 'cancellation',
                      );

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'تم فتح إرسال إشعار الإلغاء لولي أمر ($studentName) عبر واتساب 📲✅',
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF059669),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _uncancelSession() async {
    final didAuth = await SecurityService.authenticateWithBiometrics(
      context: context,
      database: widget.database,
      reason: 'تأكيد البصمة للتراجع عن إلغاء الحصة ومنع التلاعب 🔒',
    );
    if (!didAuth) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الحصة مقفلة لعدم التلاعب في بيانات الطلاب! يلزم تأكيد البصمة للتراجع عن الإلغاء 🔒'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('التراجع عن الإلغاء 🔒'),
        content: const Text(
          'هل ترغب بالتراجع عن إلغاء الحصة والعودة لرصد حضور الطلاب؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، التراجع عن الإلغاء'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.database.deleteSessionCancellation(
        groupId: widget.group.id,
        date: widget.date,
      );
      await widget.database.setSetting(
        'attendance_lock_${widget.group.id}_${widget.date}',
        'false',
      );

      final db = await widget.database.database;
      await db.delete(
        'attendance',
        where:
            'attendance_date = ? AND status IN (?, ?) AND student_id IN (SELECT id FROM students WHERE group_id = ?)',
        whereArgs: [widget.date, 'cancelled_teacher', 'cancelled_student', widget.group.id],
      );

      await _loadInitialData();
      widget.onAttendanceUpdated();

      if (mounted) {
        setState(() => isSessionLocked = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم التراجع عن إلغاء الحصة بنجاح لمجموعة "${widget.group.name}" والعودة لكشف الحضور ✅',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final presentCount = students
        .where((s) => s['attendance_status'] == 'present')
        .length;
    final absentCount = students
        .where((s) => s['attendance_status'] == 'absent')
        .length;
    final lateCount = students
        .where((s) => s['attendance_status'] == 'late')
        .length;
    final excusedCount = students
        .where((s) => s['attendance_status'] == 'excused')
        .length;
    final cancelledStudentCount = students
        .where((s) => s['attendance_status'] == 'cancelled_student')
        .length;
    final cancelledTeacherCount = students
        .where((s) => s['attendance_status'] == 'cancelled_teacher')
        .length;
    final totalCancelledCount = cancelledStudentCount + cancelledTeacherCount;
    final unmarkedCount = students
        .where((s) => s['attendance_status'] == null || (s['attendance_status'] as String).isEmpty)
        .length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'تحضير: ${widget.group.name}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSessionCancelledByTeacher) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.shade400, width: 0.8),
                            ),
                            child: const Text(
                              'ملغية 🚫',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        if (topicController.text.trim().isNotEmpty &&
                            topicController.text.trim() != 'حصة دراسية اعتيادية') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.menu_book_rounded, size: 11, color: Color(0xFF3B82F6)),
                                const SizedBox(width: 3),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 120),
                                  child: Text(
                                    topicController.text.trim(),
                                    style: const TextStyle(
                                      color: Color(0xFF3B82F6),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      'تاريخ الحصة: ${widget.date} • ${widget.group.schedule}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 10),

          // Cancellation Banner if cancelled (Teacher or Student)
          if (isSessionCancelledByTeacher)
            Builder(
              builder: (ctx) {
                final isTeacher = teacherCancellation?['cancelled_by'] == 'teacher';
                final activeColor = isTeacher ? Colors.red : Colors.purple;
                final bool isNoticeSent = teacherCancellation?['notice_sent'] == 1;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: activeColor.shade400, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isTeacher ? Icons.cancel_outlined : Icons.person_off_rounded,
                            color: activeColor,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isTeacher
                                      ? 'تم إلغاء هذه الحصة من جهة المعلم 🚫'
                                      : 'تم إلغاء هذه الحصة باعتذار من الطلاب ⚠️',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: activeColor,
                                  ),
                                ),
                                if (teacherCancellation?['reason']
                                        ?.toString()
                                        .isNotEmpty ??
                                    false)
                                  Text(
                                    'السبب: ${teacherCancellation!['reason']}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isTeacher ? Colors.redAccent : Colors.purpleAccent,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (isNoticeSent) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF059669)),
                              SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  'تم ارسال الاشعار مسبقا لولي الامر ✅',
                                  style: TextStyle(
                                    color: Color(0xFF065F46),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: isNoticeSent ? const Color(0xFF059669) : const Color(0xFF25D366),
                              side: BorderSide(
                                color: isNoticeSent ? const Color(0xFF059669) : const Color(0xFF25D366),
                              ),
                            ),
                            icon: Icon(
                              isNoticeSent ? Icons.check_circle : Icons.send_rounded,
                              size: 14,
                            ),
                            label: Text(
                              isNoticeSent ? 'تم إرسال التنبيه ✅' : 'إرسال تنبيه 📲',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              if (isNoticeSent) {
                                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Row(
                                      children: [
                                        Icon(Icons.info_outline, color: Colors.white, size: 20),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'تم ارسال الاشعار مسبقا لولي الامر',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: Color(0xFF059669),
                                  ),
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: isTeacher ? Colors.red.shade700 : Colors.purple.shade700,
                              side: BorderSide(color: isTeacher ? Colors.red.shade300 : Colors.purple.shade300),
                            ),
                            icon: const Icon(Icons.undo, size: 14),
                            label: const Text(
                              'التراجع عن الإلغاء',
                              style: TextStyle(fontSize: 11.5),
                            ),
                            onPressed: _uncancelSession,
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: Colors.amber.shade800,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.bolt_rounded, size: 14),
                            label: const Text(
                              'جدولة حصة تعويضية 📅',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () {
                              showAddExceptionalSessionDialog(
                                context: context,
                                database: widget.database,
                                preselectedGroup: widget.group,
                                initialReason: isTeacher ? 'teacher_makeup' : 'student_makeup',
                                initialNotes:
                                    'تعويض حصة ${widget.group.name} الملغاة بتاريخ ${widget.date}',
                                onSaved: () {
                                  _loadInitialData();
                                  widget.onAttendanceUpdated();
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

          // Session Scale Selector (حصة عادية / حصة دوبل)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: sessionType == 'double'
                    ? Colors.amber.shade700.withValues(alpha: 0.6)
                    : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _setSessionType('regular'),
                    borderRadius: BorderRadius.circular(9),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: sessionType == 'regular'
                            ? (isDark
                                  ? theme.colorScheme.primary
                                  : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: sessionType == 'regular'
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 15,
                            color: sessionType == 'regular'
                                ? (isDark
                                      ? Colors.white
                                      : theme.colorScheme.primary)
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'حصة عادية (1x)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: sessionType == 'regular'
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: sessionType == 'regular'
                                  ? (isDark
                                        ? Colors.white
                                        : theme.colorScheme.primary)
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    onTap: () => _setSessionType('double'),
                    borderRadius: BorderRadius.circular(9),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: sessionType == 'double'
                            ? Colors.amber.shade700
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: sessionType == 'double'
                            ? [
                                BoxShadow(
                                  color: Colors.amber.shade900.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bolt,
                            size: 16,
                            color: sessionType == 'double'
                                ? Colors.white
                                : Colors.amber.shade800,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'حصة دوبل (2x)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: sessionType == 'double'
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: sessionType == 'double'
                                  ? Colors.white
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Action Toolbar: Mark all + QR shortcut + Notebook Toggle
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.withValues(alpha: 0.15),
                    foregroundColor: Colors.green.shade800,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text(
                    'تحضير الكل',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () => _markAll('present'),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner, size: 16),
                label: const Text('QR', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScannerScreen(database: widget.database),
                    ),
                  ).then((_) => _loadStudentsOnly());
                },
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: isNotebookExpanded
                      ? Colors.indigo.shade800
                      : Colors.indigo.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: Icon(
                  isNotebookExpanded
                      ? Icons.people_alt_rounded
                      : Icons.menu_book_outlined,
                  size: 16,
                ),
                label: Text(
                  isNotebookExpanded ? 'كشف الطلاب' : 'دفتر الحصة',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                onPressed: () =>
                    setState(() => isNotebookExpanded = !isNotebookExpanded),
              ),
              const SizedBox(width: 6),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(8),
                  visualDensity: VisualDensity.compact,
                ),
                tooltip: 'إرسال تقرير الحصة لولي الأمر عبر واتساب',
                icon: const Icon(Icons.send_rounded, size: 16),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) => GroupSessionReportSheet(
                      group: widget.group,
                      database: widget.database,
                      date: widget.date,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (isNotebookExpanded)
            Expanded(child: _buildSessionNotebook(isDark))
          else ...[
            // Summary counters
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text(
                    'الطلاب: ${students.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    'حاضر: $presentCount',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    'متأخر: $lateCount',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    'معذور: $excusedCount',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    'غائب: $absentCount',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    'لم يحدد: $unmarkedCount',
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  if (totalCancelledCount > 0)
                    Text(
                      'إلغاء: $totalCancelledCount',
                      style: const TextStyle(
                        color: Colors.purple,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Session Lock / Save Action Banner
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSessionLocked
                    ? Colors.amber.shade900.withValues(alpha: 0.12)
                    : const Color(0xFF059669).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSessionLocked
                      ? Colors.amber.shade700
                      : const Color(0xFF059669),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSessionLocked
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    color: isSessionLocked
                        ? Colors.amber.shade800
                        : const Color(0xFF059669),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSessionLocked
                              ? 'كشف الحضور معتمد ومقفل 🔒'
                              : 'كشف الحضور مفتوح للتعديل 🔓',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isSessionLocked
                                ? Colors.amber.shade900
                                : const Color(0xFF059669),
                          ),
                        ),
                        Text(
                          isSessionLocked
                              ? 'محمي ضد التعديل - فك القفل بالبصمة للتعديل'
                              : 'عدّل بيانات الطلاب بحرية ثم اضغط حفظ للقفل والاعتماد',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isSessionLocked)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amber.shade100,
                        foregroundColor: Colors.amber.shade900,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.fingerprint, size: 20),
                      label: const Text(
                        'فك القفل بالبصمة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _unlockAttendanceWithSecurity,
                    )
                  else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 1,
                      ),
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text(
                        'حفظ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _lockAttendanceAndSendAbsenceAlerts,
                    ),
                ],
              ),
            ),

            // Quick Attendance Toolbar (تحضير الكل حاضر بضغطة واحدة / تصفير)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.withValues(alpha: 0.15),
                        foregroundColor: const Color(0xFF059669),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.done_all_rounded, size: 20),
                      label: const Text(
                        'تحضير الكل حاضر ⚡',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: _markAllPresentFast,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      side: BorderSide(color: Colors.grey.shade400),
                    ),
                    icon: const Icon(
                      Icons.refresh_rounded,
                      size: 17,
                      color: Colors.blueGrey,
                    ),
                    label: const Text(
                      'تصفير',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    onPressed: _resetAllAttendanceFast,
                  ),
                ],
              ),
            ),

            // Bulk Absence WhatsApp Button
            if (absentCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(
                    Icons.campaign,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    'تنبيه غياب واتساب لجميع الغائبين ($absentCount طالب) 🚨',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  onPressed: () {
                    final absents = students
                        .where((s) => s['attendance_status'] == 'absent')
                        .toList();
                    _showBulkAbsenceSheet(absents);
                  },
                ),
              ),

            // Students List with Recitation & Homework
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : students.isEmpty
                  ? const Center(
                      child: Text('لا يوجد طلاب مسجلين في هذه المجموعة بعد'),
                    )
                  : ListView.builder(
                      itemCount: students.length,
                      itemBuilder: (context, i) {
                        final s = students[i];
                        final sId = s['id'] as String;
                        final sName = s['full_name'] as String? ?? '';
                        final status = s['attendance_status'] as String?;
                        final recitation = s['recitation_rating'] as String?;
                        final hwStatus = s['homework_status'] as String?;

                        final isPresent = status == 'present';
                        final isAbsent = status == 'absent';
                        final isLate = status == 'late';
                        final isExcused = status == 'excused';
                        final isCancelledStudent =
                            status == 'cancelled_student';
                        final isCancelledTeacher =
                            status == 'cancelled_teacher';
                        final isUnmarked = status == null || status.isEmpty;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0.8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isPresent
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : (isAbsent
                                        ? Colors.red.withValues(alpha: 0.3)
                                        : (isCancelledStudent
                                              ? Colors.purple.withValues(
                                                  alpha: 0.4,
                                                )
                                              : (isCancelledTeacher
                                                    ? Colors.red.withValues(
                                                        alpha: 0.3,
                                                      )
                                                    : Colors.transparent))),
                              width: (isCancelledStudent || isCancelledTeacher)
                                  ? 1.2
                                  : 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Student Row
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: isCancelledStudent
                                          ? Colors.purple.withValues(
                                              alpha: 0.15,
                                            )
                                          : (isCancelledTeacher
                                                ? Colors.red.withValues(
                                                    alpha: 0.15,
                                                  )
                                                : theme.colorScheme.primary
                                                      .withValues(alpha: 0.12)),
                                      child: Text(
                                        sName.isNotEmpty
                                            ? sName.characters.first
                                            : 'ط',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isCancelledStudent
                                              ? Colors.purple
                                              : (isCancelledTeacher
                                                    ? Colors.red
                                                    : theme
                                                          .colorScheme
                                                          .primary),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  sName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isCancelledStudent) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.purple
                                                        .withValues(
                                                          alpha: 0.15,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.purple
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    'إلغاء من الطالب',
                                                    style: TextStyle(
                                                      color: Colors.purple,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ] else if (isCancelledTeacher) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red
                                                        .withValues(
                                                          alpha: 0.15,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.red
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    'ملغاة من المعلم',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ] else if (s['session_type'] ==
                                                      'double' ||
                                                  (isPresent &&
                                                      sessionType ==
                                                          'double')) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.shade900
                                                        .withValues(
                                                          alpha: 0.15,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors
                                                          .amber
                                                          .shade700
                                                          .withValues(
                                                            alpha: 0.5,
                                                          ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'دوبل 2x',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.amber.shade900,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              Text(
                                                'ولي الأمر: ${s['parent_phone'] ?? "غير مسجل"}',
                                                style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 11,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Send WhatsApp Report Button
                                    IconButton(
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF25D366,
                                        ).withValues(alpha: 0.15),
                                      ),
                                      icon: const Icon(
                                        Icons.send,
                                        color: Color(0xFF25D366),
                                        size: 18,
                                      ),
                                      tooltip:
                                          'إرسال تقرير المتابعة لولي الأمر عبر واتساب',
                                      onPressed: () {
                                        if (isCancelledStudent ||
                                            isCancelledTeacher) {
                                          _sendStudentCancellationAlert(s);
                                        } else if (isAbsent) {
                                          _sendSingleAbsenceAlert(s);
                                        } else {
                                          _sendSingleFollowupReport(s);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Status Toggle Buttons (حاضر, غائب, متأخر, معذور, إلغاء طالب) مع شرط الـ 5 دقائق
                                Builder(
                                  builder: (_) {
                                    final slotStart = widget.group.startTime;
                                    final now = DateTime.now();
                                    final todayStr =
                                        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                                    final bool isToday =
                                        widget.date == todayStr;

                                    DateTime? studentStartTime = _parseTimeStr(
                                      slotStart,
                                    );
                                    bool isTimeLocked = false;
                                    int minutesRemaining = 0;
                                    String unlockTimeFormatted = '';

                                    if (isToday && studentStartTime != null) {
                                      final unlockTime = studentStartTime
                                          .subtract(const Duration(minutes: 5));
                                      if (now.isBefore(unlockTime)) {
                                        isTimeLocked = true;
                                        minutesRemaining =
                                            unlockTime
                                                .difference(now)
                                                .inMinutes +
                                            1;
                                        final h = unlockTime.hour > 12
                                            ? unlockTime.hour - 12
                                            : (unlockTime.hour == 0
                                                  ? 12
                                                  : unlockTime.hour);
                                        final period = unlockTime.hour >= 12
                                            ? 'م'
                                            : 'ص';
                                        unlockTimeFormatted =
                                            '${h.toString().padLeft(2, '0')}:${unlockTime.minute.toString().padLeft(2, '0')} $period';
                                      }
                                    }

                                    return Column(
                                      children: [
                                        if (isTimeLocked && !isPresent)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade900
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.amber.shade700
                                                    .withValues(alpha: 0.3),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.hourglass_top_rounded,
                                                  size: 14,
                                                  color: Colors.amber.shade900,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    'يفتح التحضير قبل الموعد بـ 5 دقائق ($unlockTimeFormatted) • متبقي $minutesRemaining دقيقة',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          Colors.amber.shade900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        Row(
                                          children: [
                                            _buildStatusBtn(
                                              'حاضر',
                                              'present',
                                              isPresent,
                                              Colors.green,
                                              sId,
                                              sName,
                                              isTimeLocked: isTimeLocked,
                                              minutesRemaining:
                                                  minutesRemaining,
                                              slotStart: slotStart,
                                              unlockTimeFormatted:
                                                  unlockTimeFormatted,
                                            ),
                                            const SizedBox(width: 3),
                                            _buildStatusBtn(
                                              'غائب',
                                              'absent',
                                              isAbsent,
                                              Colors.red,
                                              sId,
                                              sName,
                                            ),
                                            const SizedBox(width: 3),
                                            _buildStatusBtn(
                                              'لم يحدد',
                                              'unmarked',
                                              isUnmarked,
                                              Colors.blueGrey,
                                              sId,
                                              sName,
                                            ),
                                            const SizedBox(width: 3),
                                            _buildStatusBtn(
                                              'متأخر',
                                              'late',
                                              isLate,
                                              Colors.orange,
                                              sId,
                                              sName,
                                            ),
                                            const SizedBox(width: 3),
                                            _buildStatusBtn(
                                              'معذور',
                                              'excused',
                                              isExcused,
                                              Colors.blue,
                                              sId,
                                              sName,
                                            ),
                                            const SizedBox(width: 3),
                                            _buildStatusBtn(
                                              isCancelledTeacher
                                                  ? 'ملغية (معلم)'
                                                  : (isCancelledStudent
                                                        ? 'ملغية (طالب)'
                                                        : 'إلغاء'),
                                              'cancelled',
                                              isCancelledStudent ||
                                                  isCancelledTeacher,
                                              isCancelledTeacher
                                                  ? Colors.red
                                                  : Colors.purple,
                                              sId,
                                              sName,
                                              currentStatus: status,
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),

                                // Notice & Makeup button if student cancelled
                                if (isCancelledStudent || isCancelledTeacher)
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.purple.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.person_off_rounded,
                                          size: 16,
                                          color: Colors.purple,
                                        ),
                                        const SizedBox(width: 6),
                                        const Expanded(
                                          child: Text(
                                            'اعتذار مسبق عن الحصة من جهة الطالب',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.purple,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        FilledButton.tonalIcon(
                                          style: FilledButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            backgroundColor:
                                                Colors.purple.shade700,
                                            foregroundColor: Colors.white,
                                          ),
                                          icon: const Icon(
                                            Icons.calendar_month,
                                            size: 13,
                                          ),
                                          label: const Text(
                                            'جدولة تعويض',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          onPressed: () {
                                            showAddExceptionalSessionDialog(
                                              context: context,
                                              database: widget.database,
                                              preselectedGroup: widget.group,
                                              initialReason: 'student_makeup',
                                              initialNotes:
                                                  'حصة تعويضية للطالب/ة: $sName عن غياب تاريخ ${widget.date}',
                                              onSaved: () {
                                                _loadStudentsOnly();
                                                widget.onAttendanceUpdated();
                                              },
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),

                                // Recitation & Homework Sections (Active if present or late)
                                if (isPresent || isLate) ...[
                                  const SizedBox(height: 8),
                                  const Divider(height: 10),

                                  // Recitation Chips
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        const Text(
                                          'التسميع: ',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        _buildRecitationChip(
                                          sId,
                                          'جيد',
                                          recitation,
                                          Colors.green,
                                        ),
                                        const SizedBox(width: 4),
                                        _buildRecitationChip(
                                          sId,
                                          'مقبول',
                                          recitation,
                                          Colors.blue,
                                        ),
                                        const SizedBox(width: 4),
                                        _buildRecitationChip(
                                          sId,
                                          'ضعيف',
                                          recitation,
                                          Colors.orange,
                                        ),
                                        const SizedBox(width: 4),
                                        _buildRecitationChip(
                                          sId,
                                          'مذاكرش خالص',
                                          recitation,
                                          Colors.red,
                                        ),
                                        const SizedBox(width: 4),
                                        _buildRecitationChip(
                                          sId,
                                          'لا يوجد',
                                          recitation,
                                          Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),

                                  // Homework Chips
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        const Text(
                                          'الواجب: ',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        _buildHwChip(
                                          sId,
                                          'حل الواجب',
                                          hwStatus,
                                          Colors.teal,
                                        ),
                                        const SizedBox(width: 4),
                                        _buildHwChip(
                                          sId,
                                          'جزئي',
                                          hwStatus,
                                          Colors.amber.shade800,
                                        ),
                                        const SizedBox(width: 4),
                                        _buildHwChip(
                                          sId,
                                          'لم يحل',
                                          hwStatus,
                                          Colors.redAccent,
                                        ),
                                        const SizedBox(width: 4),
                                        _buildHwChip(
                                          sId,
                                          'لا يوجد',
                                          hwStatus,
                                          Colors.grey.shade600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBtn(
    String label,
    String value,
    bool isSelected,
    Color color,
    String studentId,
    String studentName, {
    String? currentStatus,
    bool isTimeLocked = false,
    int minutesRemaining = 0,
    String slotStart = '',
    String unlockTimeFormatted = '',
  }) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          if (isSessionLocked) {
            _showLockedNotice();
            return;
          }
          if (value == 'unmarked') {
            await _updateStatus(studentId, null, studentName);
            return;
          }
          if (value == 'cancelled') {
            await _showStudentCancellationOptionsDialog(
              studentId: studentId,
              studentName: studentName,
              currentStatus: currentStatus,
            );
            return;
          }
          if (value == 'present' && isSelected) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم تحضير الطالب ($studentName) مسبقاً ✅',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF059669),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }
          if (value == 'present' && isTimeLocked && !isSelected) {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Row(
                  children: const [
                    Icon(Icons.hourglass_top_rounded, color: Colors.amber),
                    SizedBox(width: 8),
                    Text(
                      'التحضير المجدول للطالب ⏱️',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                content: Text(
                  'موعد فقرة الطالب ($studentName) تبدأ الساعة $slotStart (التحضير المجدول يفتح قبلها بـ 5 دقائق الساعة $unlockTimeFormatted).\n\nمتبقي $minutesRemaining دقيقة على الموعد.\n\nهل تريد تأكيد حضور الطالب مبكراً بطلبك الآن؟',
                  style: const TextStyle(fontSize: 13.5),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('انتظار الموعد'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('نعم، تحضير مبكر'),
                  ),
                ],
              ),
            );
            if (confirm != true) return;
          }
          await _updateStatus(studentId, value, studentName);
        },
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 1.5),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.25),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
              maxLines: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecitationChip(
    String studentId,
    String value,
    String? current,
    Color color,
  ) {
    final isSelected = current == value;
    return InkWell(
      onTap: () {
        if (isSessionLocked) {
          _showLockedNotice();
        } else {
          _updateStudentRecitation(studentId, isSelected ? '' : value);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
    );
  }

  Widget _buildHwChip(
    String studentId,
    String value,
    String? current,
    Color color,
  ) {
    final isSelected = current == value;
    return InkWell(
      onTap: () {
        if (isSessionLocked) {
          _showLockedNotice();
        } else {
          _updateStudentHomework(studentId, isSelected ? '' : value);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickChip(
    String label,
    TextEditingController controller, {
    Color? color,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        final cur = controller.text.trim();
        if (cur.isEmpty) {
          controller.text = label;
        } else if (!cur.contains(label)) {
          controller.text = '$cur - $label';
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: (color ?? Colors.indigo).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (color ?? Colors.indigo).withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? Colors.indigo,
          ),
        ),
      ),
    );
  }

  Widget _buildSessionNotebook(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.indigo.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Notebook Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: Colors.indigo,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'دفتر الحصة الشامل والمتابعة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.indigo,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'يوثق أركان الحصة والواجبات لولي الأمر',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      backgroundColor: Colors.indigo.shade50,
                      foregroundColor: Colors.indigo.shade800,
                    ),
                    icon: const Icon(Icons.playlist_add_check, size: 16),
                    label: const Text(
                      'المنهج',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _showLessonPicker,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ==========================================
              // 1️⃣ تصحيح وتقييم واجب الحصة السابقة
              // ==========================================
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.assignment_turned_in_rounded,
                          size: 20,
                          color: Color(0xFF059669),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '1️⃣ تصحيح وتقييم واجب الحصة السابقة',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: Color(0xFF059669),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: prevHomeworkController,
                      style: const TextStyle(fontSize: 14.5),
                      decoration: InputDecoration(
                        labelText: 'ملاحظات تصحيح الواجب السابق للأستاذ',
                        labelStyle: const TextStyle(fontSize: 13.5),
                        hintText:
                            'مثال: تم تصحيح ص 24 إلى 28 ومناقشة المسألة 5',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildQuickChip(
                          'تم تصحيح الواجب كاملاً ⭐',
                          prevHomeworkController,
                          color: const Color(0xFF059669),
                        ),
                        _buildQuickChip(
                          'مراجعة الأخطاء الشائعة 🔍',
                          prevHomeworkController,
                          color: const Color(0xFF059669),
                        ),
                        _buildQuickChip(
                          'واجب متقن ومتميز 👏',
                          prevHomeworkController,
                          color: const Color(0xFF059669),
                        ),
                        _buildQuickChip(
                          'تنبيه للمقصرين ⚠️',
                          prevHomeworkController,
                          color: Colors.orange.shade800,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ==========================================
              // 2️⃣ مراجعة وتسميع الدرس السابق
              // ==========================================
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.amber.shade700.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.rate_review_rounded,
                          size: 20,
                          color: Colors.amber.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '2️⃣ مراجعة وتسميع الدرس السابق',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: Colors.amber.shade900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _showPreviousLessonPicker,
                          icon: const Icon(Icons.menu_book_rounded, size: 16),
                          label: const Text(
                            'اختيار من المنهج',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            backgroundColor: isDark
                                ? Colors.amber.shade900.withValues(alpha: 0.3)
                                : Colors.amber.shade100,
                            foregroundColor: isDark
                                ? Colors.amber.shade200
                                : Colors.amber.shade900,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: prevLessonController,
                      style: const TextStyle(fontSize: 14.5),
                      decoration: InputDecoration(
                        labelText: 'موضوع المراجعة أو أسئلة التسميع',
                        labelStyle: const TextStyle(fontSize: 13.5),
                        hintText:
                            'مثال: تسميع كلمات الوحدة الأولى ومراجعة قوانين نيوتن',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildQuickChip(
                          'تسميع شفوي بداية الحصة 🗣️',
                          prevLessonController,
                          color: Colors.amber.shade900,
                        ),
                        _buildQuickChip(
                          'كويز سريع مفاجئ ✍️',
                          prevLessonController,
                          color: Colors.amber.shade900,
                        ),
                        _buildQuickChip(
                          'مراجعة شاملة وتثبيت 🎯',
                          prevLessonController,
                          color: Colors.amber.shade900,
                        ),
                        _buildQuickChip(
                          'مناقشة أفكار الامتحان 📝',
                          prevLessonController,
                          color: Colors.amber.shade900,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ==========================================
              // 3️⃣ ما تم شرحه اليوم في الحصة
              // ==========================================
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.indigo.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_stories_rounded,
                          size: 20,
                          color: Colors.indigo,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '3️⃣ شرح درس اليوم',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: Colors.indigo,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _showLessonPicker,
                          icon: const Icon(
                            Icons.playlist_add_check_rounded,
                            size: 17,
                          ),
                          label: const Text(
                            'اختيار من المنهج',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            backgroundColor: isDark
                                ? Colors.indigo.shade900.withValues(alpha: 0.4)
                                : Colors.indigo.shade100,
                            foregroundColor: isDark
                                ? Colors.indigo.shade200
                                : Colors.indigo.shade800,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: topicController,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        labelText: 'عنوان درس اليوم المشروح *',
                        labelStyle: const TextStyle(fontSize: 13.5),
                        hintText: 'مثال: الدرس الثاني: قوانين الحركة والسرعة',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: contentController,
                      style: const TextStyle(fontSize: 14.5),
                      decoration: InputDecoration(
                        labelText: 'أهم العناصر والنقاط المشروحة (اختياري)',
                        labelStyle: const TextStyle(fontSize: 13.5),
                        hintText:
                            'مثال: شرح النظرية، حل مسائل النموذج الأول، وتطبيقات عملية',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ==========================================
              // 4️⃣ تكليفات الحصة القادمة
              // ==========================================
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFFAF5FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.purple.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.edit_calendar_rounded,
                          size: 20,
                          color: Colors.purple,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '4️⃣ تكليفات وواجب الحصة القادمة',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: Colors.purple,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: homeworkController,
                      style: const TextStyle(fontSize: 14.5),
                      decoration: InputDecoration(
                        labelText: 'واجب الحصة القادمة المطلوب *',
                        labelStyle: const TextStyle(fontSize: 13.5),
                        hintText:
                            'مثال: كتاب التدريبات ص 45 إلى 48 + حفظ الكلمات',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nextTopicController,
                      style: const TextStyle(fontSize: 14.5),
                      decoration: InputDecoration(
                        labelText: 'كويز أو اختبار قادم (للتنبيه والاستعداد)',
                        labelStyle: const TextStyle(fontSize: 13.5),
                        hintText:
                            'مثال: كويز تراكمي على الوحدة الأولى الحصة القادمة',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildQuickChip(
                          'حل تدريبات المذكرة 📚',
                          homeworkController,
                          color: Colors.purple,
                        ),
                        _buildQuickChip(
                          'حفظ وتسميع الجزء القادم 📖',
                          homeworkController,
                          color: Colors.purple,
                        ),
                        _buildQuickChip(
                          'كويز شامل بداية الحصة القادمة 🎯',
                          nextTopicController,
                          color: Colors.deepPurple,
                        ),
                        _buildQuickChip(
                          'امتحان دوري رسمي ⏰',
                          nextTopicController,
                          color: Colors.deepPurple,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Save button
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                label: const Text(
                  'حفظ وتثبيت دفتر الحصة 💾',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                ),
                onPressed: _saveSessionNotebook,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// DIRECT GROUP SESSION REPORT BOTTOM SHEET (WITH PREVIEW OPTION)
// ============================================================================
class GroupSessionReportSheet extends StatefulWidget {
  const GroupSessionReportSheet({
    super.key,
    required this.group,
    required this.database,
    required this.date,
  });

  final GroupModel group;
  final DatabaseService database;
  final String date;

  @override
  State<GroupSessionReportSheet> createState() => _GroupSessionReportSheetState();
}

class _GroupSessionReportSheetState extends State<GroupSessionReportSheet> {
  bool isLoading = true;
  bool isSending = false;
  bool _cancelSendingRequested = false;
  bool showPreview = false;
  double sendProgress = 0.0;
  String progressText = '';
  int sentSuccessCount = 0;
  int sentFailCount = 0;

  List<Map<String, dynamic>> students = [];
  Set<String> selectedStudentIds = {};
  Set<String> sentStudentIds = {};
  String? previewStudentId;

  SessionLogModel? sessionLog;
  String centerName = 'أكاديمية المستقبل';
  String teacherName = 'الأستاذ';
  String waMode = 'manual';
  String customTemplate = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    final results = await Future.wait([
      widget.database.getGroupStudentsWithAttendance(
        groupId: widget.group.id,
        date: widget.date,
      ),
      widget.database.getLatestSessionLogForGroup(widget.group.id),
      widget.database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل'),
      widget.database.getSetting('teacher_name', defaultValue: 'الأستاذ'),
      widget.database.getSetting('whatsapp_mode', defaultValue: 'manual'),
      widget.database.getSetting('whatsapp_template_session_report', defaultValue: ''),
      widget.database.getSentStudentIdsStrict(
        category: 'daily_report',
        contextKey: widget.date,
      ),
      widget.database.getSetting('report_card_send_as_visual', defaultValue: 'true'),
      widget.database.getSetting('report_card_include_text_message', defaultValue: 'true'),
    ]);

    final rawStudents = results[0] as List<Map<String, dynamic>>;
    final log = results[1] as SessionLogModel?;
    final cName = results[2] as String;
    final tName = results[3] as String;
    final mode = results[4] as String;
    final cTpl = results[5] as String;
    final alreadySentIds = results[6] as Set<String>;
    final visualCardPref = results[7] as String;
    final includeTextPref = results[8] as String;

    final selected = <String>{};
    for (final s in rawStudents) {
      final sId = s['id'] as String? ?? '';
      final pPhone = (s['parent_phone'] as String? ?? '').trim();
      final sPhone = (s['student_phone'] as String? ?? '').trim();
      // Strictly do NOT auto-select students who have already received today's report
      if (sId.isNotEmpty &&
          (pPhone.isNotEmpty || sPhone.isNotEmpty) &&
          !alreadySentIds.contains(sId)) {
        selected.add(sId);
      }
    }

    final examScoresMap = <String, List<Map<String, dynamic>>>{};
    for (final s in rawStudents) {
      final sId = s['id'] as String? ?? '';
      if (sId.isNotEmpty) {
        examScoresMap[sId] = await widget.database.getStudentExamScores(sId);
      }
    }

    if (mounted) {
      setState(() {
        students = rawStudents;
        sessionLog = log;
        centerName = cName;
        teacherName = tName;
        waMode = mode;
        customTemplate = cTpl;
        sentStudentIds = alreadySentIds;
        selectedStudentIds = selected;
        studentExamScoresMap = examScoresMap;
        previewStudentId = rawStudents.isNotEmpty ? rawStudents.first['id'] as String? : null;
        sendAsVisualCard = visualCardPref == 'true';
        includeTextMessageWithCard = includeTextPref == 'true';
        isLoading = false;
      });
    }
  }

  bool sendAsVisualCard = true;
  bool includeTextMessageWithCard = true;
  ReportCardFont selectedFont = ReportCardFont.cairo;
  ReportCardTheme selectedTheme = ReportCardTheme.cyan;
  final GlobalKey _offscreenRepaintKey = GlobalKey();
  Map<String, dynamic>? _currentlyRenderingStudent;
  Map<String, List<Map<String, dynamic>>> studentExamScoresMap = {};

  Widget _buildCardWidgetForStudent(Map<String, dynamic> s) {
    final sId = s['id'] as String? ?? '';
    final sName = s['full_name'] as String? ?? 'طالب';
    final pPhone = (s['parent_phone'] as String? ?? '').trim();
    final sPhone = (s['student_phone'] as String? ?? '').trim();
    final attStatus = s['attendance_status'] as String?;
    final recitation = s['recitation_rating'] as String?;
    final hwStatus = s['homework_status'] as String?;

    final isPresent = attStatus == 'present';
    final isLate = attStatus == 'late';
    final isAbsent = attStatus == 'absent';
    final isExcused = attStatus == 'excused';

    final arabicStatus = isPresent
        ? 'حاضر في الموعد 🟢'
        : (isLate
            ? 'حاضر متأخر 🟡'
            : (isExcused
                ? 'غياب بعذر ⚪'
                : (attStatus == 'cancelled_student'
                    ? 'اعتذار مسبق ⚠️'
                    : (attStatus == 'cancelled_teacher'
                        ? 'إلغاء من المعلم 🚫'
                        : (isAbsent ? 'غائب عن الحصة 🚨' : 'لم يُرصد ⏱️')))));

    final effHwStatus = isAbsent
        ? 'لم يحضر للتسليم (غائب) 🚨'
        : (isExcused
            ? 'غياب بعذر ⚪'
            : (attStatus == 'cancelled_student'
                ? 'اعتذار مسبق ⚠️'
                : (attStatus == 'cancelled_teacher'
                    ? 'إلغاء من المعلم 🚫'
                    : (hwStatus ?? (isPresent ? 'تم التسليم ✅' : 'لم يسلم ❌')))));

    final effRecitation = isAbsent
        ? 'لم يُسمّع (غائب) 🚨'
        : (isExcused
            ? 'غياب بعذر ⚪'
            : (attStatus == 'cancelled_student' || attStatus == 'cancelled_teacher'
                ? null
                : recitation));

    final effRank = isPresent
        ? 'متميز ومنتظم 🌟'
        : (isLate
            ? 'تنبيه تأخير ⏰'
            : (isAbsent ? 'تنبيه غياب ومتابعة ⚠️' : (isExcused ? 'غياب بعذر ⚪' : 'متابعة دورية')));

    final effStage = widget.group.stage.isNotEmpty ? widget.group.stage : (s['stage']?.toString() ?? '');
    final effGrade = widget.group.grade.isNotEmpty ? widget.group.grade : (s['grade']?.toString() ?? '');

    if (s['grade'] != effGrade && effGrade.isNotEmpty) {
      widget.database.updateStudentsBatchFields([sId], grade: effGrade, stage: effStage);
    }

    final studentModel = StudentModel(
      id: sId,
      fullName: sName,
      stage: effStage,
      grade: effGrade,
      studentPhone: sPhone,
      parentPhone: pPhone,
      groupId: widget.group.id,
      paymentPlan: s['payment_plan']?.toString() ?? widget.group.billingType,
    );

    final sNotes = sessionLog?.notes;
    final sHw = sessionLog?.homework;
    final sNextQuiz = sessionLog?.nextQuiz;

    final effNotes = isAbsent
        ? ((sNotes != null && sNotes.isNotEmpty)
            ? sNotes
            : 'نرجو من ولي الأمر متابعة سبب غياب الطالب والحرص على تعويض ما فاته من المقرر والتكليفات ⚠️')
        : ((sNotes != null && sNotes.isNotEmpty)
            ? sNotes
            : ((sHw != null && sHw.isNotEmpty)
                ? 'الواجب: $sHw'
                : 'تمنياتنا بدوام التميز والتفوق 🌟'));

    final realExamScores = studentExamScoresMap[sId] ?? const [];
    double realAvgPercent = 0.0;
    if (realExamScores.isNotEmpty) {
      double totalObtained = 0;
      double totalPossible = 0;
      for (final e in realExamScores) {
        final sc = (e['score'] ?? 0).toDouble();
        final mx = (e['max_score'] ?? 50).toDouble();
        if (mx > 0) {
          totalObtained += sc;
          totalPossible += mx;
        }
      }
      if (totalPossible > 0) {
        realAvgPercent = (totalObtained / totalPossible) * 100;
      }
    }

    return Material(
      color: Colors.transparent,
      child: VisualStudentReportCard(
        student: studentModel,
        groupName: widget.group.name,
        groupGrade: widget.group.grade,
        showFinance: false,
        attendancePercent: isPresent ? 100 : (isLate ? 85 : 0),
        presentCount: (isPresent || isLate) ? 1 : 0,
        totalSessions: 1,
        averageScorePercent: realAvgPercent,
        examScores: realExamScores,
        teacherNote: effNotes,
        centerName: centerName,
        teacherName: teacherName,
        rankText: effRank,
        reportTitle: 'تقرير متابعة الحصة الدراسية لولي الأمر 📊',
        sessionDate: widget.date,
        attendanceStatusLabel: arabicStatus,
        homeworkStatusLabel: effHwStatus,
        recitationRatingLabel: effRecitation,
        lessonTitle: (sessionLog?.lessonTitle != null && sessionLog!.lessonTitle.trim().isNotEmpty) ? sessionLog!.lessonTitle.trim() : null,
        previousHomeworkReview: (sessionLog?.previousHomeworkReview != null && sessionLog!.previousHomeworkReview.trim().isNotEmpty) ? sessionLog!.previousHomeworkReview.trim() : null,
        homeworkText: (sHw != null && sHw.trim().isNotEmpty) ? sHw.trim() : null,
        nextTopic: (sessionLog?.nextTopic != null && sessionLog!.nextTopic.trim().isNotEmpty) ? sessionLog!.nextTopic.trim() : null,
        nextQuiz: (sNextQuiz != null && sNextQuiz.trim().isNotEmpty) ? sNextQuiz.trim() : null,
        subAttendanceNote: isAbsent ? 'غائب عن الحصة' : 'حصة اليوم',
        font: selectedFont,
        theme: selectedTheme,
      ),
    );
  }

  Future<File?> _captureStudentCardFile(Map<String, dynamic> student) async {
    try {
      setState(() {
        _currentlyRenderingStudent = student;
      });
      await Future.delayed(const Duration(milliseconds: 90));
      final boundary = _offscreenRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final sName = student['full_name'] as String? ?? 'student';
      final cleanName = sName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '_');
      final file = File('${tempDir.path}/ReportCard_${student['id']}_$cleanName.png');
      await file.writeAsBytes(pngBytes);
      return file;
    } catch (e) {
      debugPrint('Error generating report card for student: $e');
      return null;
    }
  }

  Future<void> _openCardPreviewForStudent(Map<String, dynamic> student) async {
    final sId = student['id'] as String? ?? '';
    final sName = student['full_name'] as String? ?? 'طالب';
    final pPhone = (student['parent_phone'] as String? ?? '').trim();
    final sPhone = (student['student_phone'] as String? ?? '').trim();
    final attStatus = student['attendance_status'] as String?;
    final recitation = student['recitation_rating'] as String?;
    final hwStatus = student['homework_status'] as String?;

    final isPresent = attStatus == 'present';
    final isLate = attStatus == 'late';
    final isAbsent = attStatus == 'absent';
    final isExcused = attStatus == 'excused';

    final arabicStatus = isPresent
        ? 'حاضر في الموعد 🟢'
        : (isLate
            ? 'حاضر متأخر 🟡'
            : (isExcused
                ? 'غياب بعذر ⚪'
                : (attStatus == 'cancelled_student'
                    ? 'اعتذار مسبق ⚠️'
                    : (attStatus == 'cancelled_teacher'
                        ? 'إلغاء من المعلم 🚫'
                        : (isAbsent ? 'غائب عن الحصة 🚨' : 'لم يُرصد ⏱️')))));

    final effHwStatus = isAbsent
        ? 'لم يحضر للتسليم (غائب) 🚨'
        : (isExcused
            ? 'غياب بعذر ⚪'
            : (attStatus == 'cancelled_student'
                ? 'اعتذار مسبق ⚠️'
                : (attStatus == 'cancelled_teacher'
                    ? 'إلغاء من المعلم 🚫'
                    : (hwStatus ?? (isPresent ? 'تم التسليم ✅' : 'لم يسلم ❌')))));

    final effRecitation = isAbsent
        ? 'لم يُسمّع (غائب) 🚨'
        : (isExcused
            ? 'غياب بعذر ⚪'
            : (attStatus == 'cancelled_student' || attStatus == 'cancelled_teacher'
                ? null
                : recitation));

    final effRank = isPresent
        ? 'متميز ومنتظم 🌟'
        : (isLate
            ? 'تنبيه تأخير ⏰'
            : (isAbsent ? 'تنبيه غياب ومتابعة ⚠️' : (isExcused ? 'غياب بعذر ⚪' : 'متابعة دورية')));

    final effStage = widget.group.stage.isNotEmpty ? widget.group.stage : (student['stage']?.toString() ?? '');
    final effGrade = widget.group.grade.isNotEmpty ? widget.group.grade : (student['grade']?.toString() ?? '');

    if (student['grade'] != effGrade && effGrade.isNotEmpty) {
      widget.database.updateStudentsBatchFields([sId], grade: effGrade, stage: effStage);
    }

    final studentModel = StudentModel(
      id: sId,
      fullName: sName,
      stage: effStage,
      grade: effGrade,
      studentPhone: sPhone,
      parentPhone: pPhone,
      groupId: widget.group.id,
      paymentPlan: student['payment_plan']?.toString() ?? widget.group.billingType,
    );

    final sNotes = sessionLog?.notes;
    final sHw = sessionLog?.homework;
    final sNextQuiz = sessionLog?.nextQuiz;

    final effNotes = isAbsent
        ? ((sNotes != null && sNotes.isNotEmpty)
            ? sNotes
            : 'نرجو من ولي الأمر متابعة سبب غياب الطالب والحرص على تعويض ما فاته من المقرر والتكليفات ⚠️')
        : ((sNotes != null && sNotes.isNotEmpty)
            ? sNotes
            : ((sHw != null && sHw.isNotEmpty) ? 'الواجب: $sHw' : 'تمنياتنا بدوام التميز والتفوق 🌟'));

    final realExamScores = studentExamScoresMap[sId] ?? (sId.isNotEmpty ? await widget.database.getStudentExamScores(sId) : <Map<String, dynamic>>[]);
    double realAvgPercent = 0.0;
    if (realExamScores.isNotEmpty) {
      double totalObtained = 0;
      double totalPossible = 0;
      for (final e in realExamScores) {
        final sc = (e['score'] ?? 0).toDouble();
        final mx = (e['max_score'] ?? 50).toDouble();
        if (mx > 0) {
          totalObtained += sc;
          totalPossible += mx;
        }
      }
      if (totalPossible > 0) {
        realAvgPercent = (totalObtained / totalPossible) * 100;
      }
    }

    if (!mounted) return;
    VisualReportCardHelper.showPreview(
      context,
      student: studentModel,
      groupName: widget.group.name,
      groupGrade: widget.group.grade,
      attendancePercent: isPresent ? 100 : (isLate ? 85 : 0),
      presentCount: (isPresent || isLate) ? 1 : 0,
      totalSessions: 1,
      averageScorePercent: realAvgPercent,
      examScores: realExamScores,
      teacherNote: effNotes,
      centerName: centerName,
      teacherName: teacherName,
      rankText: effRank,
      reportTitle: 'تقرير متابعة الحصة الدراسية لولي الأمر 📊',
      sessionDate: widget.date,
      attendanceStatusLabel: arabicStatus,
      homeworkStatusLabel: effHwStatus,
      recitationRatingLabel: effRecitation,
      lessonTitle: (sessionLog?.lessonTitle != null && sessionLog!.lessonTitle.trim().isNotEmpty) ? sessionLog!.lessonTitle.trim() : null,
      previousHomeworkReview: (sessionLog?.previousHomeworkReview != null && sessionLog!.previousHomeworkReview.trim().isNotEmpty) ? sessionLog!.previousHomeworkReview.trim() : null,
      homeworkText: (sHw != null && sHw.trim().isNotEmpty) ? sHw.trim() : null,
      nextTopic: (sessionLog?.nextTopic != null && sessionLog!.nextTopic.trim().isNotEmpty) ? sessionLog!.nextTopic.trim() : null,
      nextQuiz: (sNextQuiz != null && sNextQuiz.trim().isNotEmpty) ? sNextQuiz.trim() : null,
      subAttendanceNote: isAbsent ? 'غائب عن الحصة' : 'حصة اليوم',
      database: widget.database,
    );
  }

  String _buildMessageForStudent(Map<String, dynamic> student) {
    final sName = student['full_name'] as String? ?? 'الطالب';
    final attStatus = student['attendance_status'] as String?;
    final recitation = student['recitation_rating'] as String?;
    final hwStatus = student['homework_status'] as String?;

    final isPresent = attStatus == 'present';
    final isLate = attStatus == 'late';
    final isAbsent = attStatus == 'absent';
    final isExcused = attStatus == 'excused';

    final arabicStatus = isPresent
        ? 'حاضر في الموعد 🟢'
        : (isLate
            ? 'حاضر متأخر 🟡'
            : (isExcused
                ? 'غياب بعذر مسبق ⚪'
                : (attStatus == 'cancelled_student'
                    ? 'إلغاء واعتذار مسبق من الطالب ⚠️'
                    : (attStatus == 'cancelled_teacher'
                        ? 'إلغاء الحصة من جهة المعلم 🚫'
                        : (isAbsent ? 'غائب عن الحصة 🚨' : 'لم يُرصد حضوره ⏱️')))));

    final effHwStatus = isAbsent
        ? 'لم يحضر للتسليم (غائب عن الحصة) 🚨'
        : (isExcused
            ? 'غياب بعذر مسبق ⚪'
            : (attStatus == 'cancelled_student' || attStatus == 'cancelled_teacher'
                ? 'ملغي 🚫'
                : (hwStatus ?? (isPresent ? 'تم التسليم والمراجعة ✅' : 'لم يسلم ❌'))));

    final effRecitation = isAbsent
        ? 'لم يُسمّع (غائب عن الحصة) 🚨'
        : (isExcused
            ? 'غياب بعذر مسبق ⚪'
            : (attStatus == 'cancelled_student' || attStatus == 'cancelled_teacher'
                ? null
                : recitation));

    final effNotes = isAbsent
        ? ((sessionLog?.notes != null && sessionLog!.notes.trim().isNotEmpty)
            ? sessionLog!.notes.trim()
            : 'نرجو من ولي الأمر متابعة سبب غياب الطالب والحرص على تعويض ما فاته من الشرح والتكليفات.')
        : sessionLog?.notes;

    return WhatsAppService.sessionFollowUpMessage(
      centerName: centerName,
      teacherName: teacherName,
      studentName: sName,
      groupName: widget.group.name,
      date: widget.date,
      lessonTitle: sessionLog?.lessonTitle.isNotEmpty == true
          ? sessionLog!.lessonTitle
          : 'مقرر الحصة اليومي',
      lessonContent: sessionLog?.contentCovered,
      homework: sessionLog?.homework,
      notes: effNotes,
      attendanceStatus: arabicStatus,
      recitationRating: effRecitation,
      homeworkStatus: effHwStatus,
      nextQuiz: sessionLog?.nextQuiz,
      previousHomeworkReview: sessionLog?.previousHomeworkReview,
      previousLessonReview: sessionLog?.previousLessonReview,
      customTemplate: customTemplate.trim().isNotEmpty ? customTemplate : null,
    );
  }

  Future<void> _showEditMasterTemplateDialog() async {
    final tplController = TextEditingController(
      text: customTemplate.trim().isNotEmpty
          ? customTemplate
          : WhatsAppService.defaultSessionReportTemplate,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const emeraldColor = Color(0xFF059669);

    final tags = [
      {'tag': '{اسم_الطالب}', 'label': 'اسم الطالب 👤'},
      {'tag': '{حالة_الحضور}', 'label': 'حالة الحضور 📍'},
      {'tag': '{موضوع_الدرس}', 'label': 'موضوع الدرس 📖'},
      {'tag': '{عناصر_الشرح}', 'label': 'عناصر الشرح 📝'},
      {'tag': '{الواجب}', 'label': 'الواجب المطلوب 📚'},
      {'tag': '{كويز_الحصة_القادمة}', 'label': 'كويز القادم 🎯'},
      {'tag': '{تقييم_الواجب}', 'label': 'تقييم الواجب السابق ✏️'},
      {'tag': '{ملاحظات_الواجب}', 'label': 'ملاحظات الواجب 🗒️'},
      {'tag': '{تقييم_التسميع}', 'label': 'تقييم التسميع ⭐'},
      {'tag': '{موضوع_المراجعة}', 'label': 'موضوع المراجعة 🔄'},
      {'tag': '{ملاحظات}', 'label': 'ملاحظات المعلم 💡'},
      {'tag': '{المجموعة}', 'label': 'اسم المجموعة 👥'},
      {'tag': '{التاريخ}', 'label': 'التاريخ 📅'},
      {'tag': '{السنتر}', 'label': 'السنتر 🏛️'},
      {'tag': '{المعلم}', 'label': 'المعلم 👨‍🏫'},
    ];

    void insertTag(String tag) {
      final text = tplController.text;
      final selection = tplController.selection;
      if (selection.start >= 0 && selection.end >= 0) {
        final newText = text.replaceRange(selection.start, selection.end, tag);
        tplController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: selection.start + tag.length),
        );
      } else {
        tplController.text = text + tag;
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          height: MediaQuery.of(ctx).size.height * 0.88,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.edit_note_rounded, color: Color(0xFF0284C7), size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'تعديل النموذج العام لجميع الرسائل ⚙️',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'التعديل هنا يُعتمد كقالب رسمي لجميع الطلاب والمجموعات',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              // Tags Chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'اضغط على المتغير لإدراجه في نص الرسالة:',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: tags.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (ctx, i) {
                          final t = tags[i];
                          return ActionChip(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            label: Text(
                              t['label']!,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                            backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            side: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                              width: 0.8,
                            ),
                            onPressed: () => insertTag(t['tag']!),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Editor
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: tplController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 12.5, height: 1.45),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      hintText: 'اكتب نص النموذج هنا...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Bottom Action Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber.shade800,
                        side: BorderSide(color: Colors.amber.shade700),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      icon: const Icon(Icons.restore_rounded, size: 16),
                      label: const Text('الافتراضي 🔄', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        tplController.text = WhatsAppService.defaultSessionReportTemplate;
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: emeraldColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text(
                          'حفظ واعتماد النموذج العام 💾',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          final newText = tplController.text.trim();
                          await widget.database.setSetting(
                            'whatsapp_template_session_report',
                            newText,
                          );
                          widget.database.notifyChange(DataChangeEvent.settings);
                          if (mounted) {
                            setState(() {
                              customTemplate = newText;
                            });
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم حفظ واعتماد النموذج العام لجميع تقارير الطلاب بنجاح ✅'),
                                backgroundColor: Color(0xFF059669),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleWaMode([StateSetter? dialogSetState]) async {
    HapticFeedback.mediumImpact();
    final newMode = waMode == 'api' ? 'manual' : 'api';
    if (newMode == 'api') {
      final endpoint = await widget.database.getSetting('whatsapp_api_endpoint', defaultValue: '');
      final apiKey = await widget.database.getSetting('whatsapp_api_key', defaultValue: '');
      if (endpoint.trim().isEmpty || apiKey.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تنبيه: يجب إدخال رابط البوابة ومفتاح الـ API في الإعدادات للتمكن من الإرسال السحابي.',
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
    await widget.database.setSetting('whatsapp_mode', newMode);
    if (mounted) {
      setState(() {
        waMode = newMode;
      });
      if (dialogSetState != null) {
        dialogSetState(() {});
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newMode == 'api'
                ? 'تم التحويل إلى وضع الإرسال التلقائي السحابي (API) ☁️'
                : 'تم التحويل إلى وضع الإرسال اليدوي المباشر (تطبيق واتساب) 📲',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ignore: unused_element
  Future<bool> _confirmSend({
    required int count,
    String? singleStudentName,
    String? singlePhone,
  }) async {
    final isSingle = singleStudentName != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const emeraldColor = Color(0xFF059669);

    return await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: emeraldColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.help_outline_rounded, color: emeraldColor, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isSingle ? 'تأكيد إرسال تقرير الطالب 📲' : 'تأكيد إرسال تقارير الحصة 🚀',
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSingle) ...[
                    Text(
                      'هل تريد بالتأكيد إرسال تقرير المتابعة لولي أمر الطالب:',
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade300 : const Color(0xFF334155)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: emeraldColor.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('👤 $singleStudentName', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text('📞 $singlePhone', style: TextStyle(fontSize: 11.5, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ] else ...[
                    Text(
                      'أنت على وشك إرسال تقرير متابعة الحصة لجميع الطلاب المحددين:',
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade300 : const Color(0xFF334155)),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: emeraldColor.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.people_alt_rounded, color: emeraldColor, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'عدد المستلمين: $count أولياء أمور',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.class_rounded, color: emeraldColor, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'المجموعة: ${widget.group.name}',
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (sessionLog != null && sessionLog!.lessonTitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.menu_book_rounded, color: emeraldColor, size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'الدرس: ${sessionLog!.lessonTitle}',
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Dispatch Format Indicator
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (sendAsVisualCard ? const Color(0xFF00F2FE) : emeraldColor).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (sendAsVisualCard ? const Color(0xFF00F2FE) : emeraldColor).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sendAsVisualCard
                              ? (includeTextMessageWithCard ? Icons.photo_library_rounded : Icons.image_rounded)
                              : Icons.article_rounded,
                          size: 15,
                          color: sendAsVisualCard ? const Color(0xFF00F2FE) : emeraldColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            !sendAsVisualCard
                                ? 'صيغة الإرسال: رسالة نصية فقط 📝'
                                : (includeTextMessageWithCard
                                    ? 'صيغة الإرسال: كارت مصور + رسالة نصية 🖼️📝'
                                    : 'صيغة الإرسال: صورة كارت التقرير فقط (بدون نص) 🖼️'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: sendAsVisualCard ? const Color(0xFF00F2FE) : emeraldColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (waMode == 'api' ? const Color(0xFF10B981) : const Color(0xFF0284C7))
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          waMode == 'api' ? Icons.cloud_done_rounded : Icons.phone_android_rounded,
                          size: 17,
                          color: waMode == 'api' ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            waMode == 'api'
                                ? 'طريقة الإرسال: سحابية فورية (API)'
                                : 'طريقة الإرسال: يدوية (تطبيق واتساب)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey.shade300 : const Color(0xFF334155),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _toggleWaMode(setDialogState),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (waMode == 'api' ? const Color(0xFF10B981) : const Color(0xFF0284C7))
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 13,
                                  color: waMode == 'api' ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  waMode == 'api' ? 'تحويل ليدوي' : 'تحويل لـ API',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: waMode == 'api' ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('تراجع / إلغاء', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: emeraldColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('تأكيد الإرسال 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _showSuccessResultDialog({
    required String title,
    required String subtitle,
    required int successCount,
    required int failCount,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const emeraldColor = Color(0xFF059669);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: emeraldColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: emeraldColor, size: 56),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.grey.shade300 : const Color(0xFF334155),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: emeraldColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('الناجحة ✅', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        '$successCount',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: emeraldColor),
                      ),
                    ],
                  ),
                  if (failCount > 0) ...[
                    Container(width: 1, height: 26, color: Colors.grey.shade400),
                    Column(
                      children: [
                        const Text('المتعذرة ❌', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '$failCount',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: emeraldColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً، تم بنجاح 👍', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendSingle(Map<String, dynamic> student) async {
    final sId = student['id'] as String? ?? '';
    final sName = student['full_name'] as String? ?? 'الطالب';
    final pPhone = (student['parent_phone'] as String? ?? '').trim();
    final sPhone = (student['student_phone'] as String? ?? '').trim();
    final phone = pPhone.isNotEmpty ? pPhone : sPhone;

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('عذراً، لا يوجد رقم هاتف مسجل للطالب $sName'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final wasSent = await widget.database.isStudentReportSentToday(
      studentId: sId,
      date: widget.date,
    );
    if (wasSent) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.shield_rounded, color: Colors.amber, size: 24),
              SizedBox(width: 8),
              Expanded(child: Text('تم الإرسال لولي الأمر مسبقاً 🛡️')),
            ],
          ),
          content: Text(
            'نحيطكم علماً بأنه تم إرسال تقرير حصة اليوم (${widget.date}) إلى ولي أمر الطالب "$sName" مسبقاً.\n\nيقوم النظام بمنع تكرار الإرسال تلقائياً لتفادي إزعاج ولي الأمر.',
            style: const TextStyle(height: 1.4, fontSize: 13),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً، فهمت ذلك'),
            ),
          ],
        ),
      );
      return;
    }

    final channel = await ReportDispatchHelper.showChannelPicker(
      context: context,
      studentName: sName,
      reportTitle: 'تقرير متابعة حصة اليوم 📋',
    );
    if (channel == null || !mounted) return;

    if (sentStudentIds.contains(sId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال تقرير اليوم لهذا الطالب مسبقاً بالفعل ✅')),
      );
      return;
    }

    File? cardImage;
    if (sendAsVisualCard) {
      cardImage = await _captureStudentCardFile(student);
    }

    final message = (sendAsVisualCard && !includeTextMessageWithCard)
        ? ''
        : _buildMessageForStudent(student);

    final sCode = student['code']?.toString() ?? sId;

    // 1. إرسال إلى تطبيق الطالب
    if (channel == ReportDispatchChannel.appOnly || channel == ReportDispatchChannel.both) {
      try {
        final notifBody = message.isNotEmpty ? message : 'تم إصدار تقرير الحصة اليومية بنجاح 📋';
        await AcademyCommunicationService.instance.sendNotification(
          title: '📋 تقرير متابعة الحصة اليومية',
          body: notifBody.length > 250 ? '${notifBody.substring(0, 247)}...' : notifBody,
          type: 'sessionFollowup',
          targetType: 'student',
          targetId: sId,
          targetName: sName,
        );
        await AcademyCommunicationService.instance.sendMessageFromTeacher(
          studentId: sId,
          studentName: sName,
          studentCode: sCode,
          text: notifBody,
        );
      } catch (e) {
        debugPrint('Error sending report to student app: $e');
      }
    }

    // 2. إرسال إلى واتساب
    bool ok = true;
    if (channel == ReportDispatchChannel.whatsappOnly || channel == ReportDispatchChannel.both) {
      ok = await WhatsAppService.dispatchMessage(
        database: widget.database,
        phone: phone,
        message: message,
        studentId: sId,
        studentName: sName,
        recipientType: 'parent',
        category: 'daily_report',
        imageFile: cardImage,
        forceManual: false,
      );
    }

    if (mounted) {
      if (ok) {
        setState(() {
          sentStudentIds.add(sId);
          selectedStudentIds.remove(sId);
        });
        await widget.database.recordSentMessage(
          studentId: sId,
          category: 'daily_report',
          contextKey: widget.date,
          phone: phone,
          status: 'sent',
        );
        await widget.database.setSetting('report_sent_${widget.group.id}_${widget.date}', 'true');
        await NotificationService.cancelUnsentReportReminder(widget.group.id);
        await _showSuccessResultDialog(
          title: 'تم إرسال التقرير بنجاح! 🚀',
          subtitle: 'تم إرسال تقرير المتابعة إلى الطالب:\n$sName بنجاح.',
          successCount: 1,
          failCount: 0,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إرسال التقرير للطالب $sName'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendBulk() async {
    final targets = students.where((s) {
      final sId = s['id'] as String? ?? '';
      final pPhone = (s['parent_phone'] as String? ?? '').trim();
      final sPhone = (s['student_phone'] as String? ?? '').trim();
      return selectedStudentIds.contains(sId) && (pPhone.isNotEmpty || sPhone.isNotEmpty);
    }).toList();

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد طالب واحد على الأقل لديه رقم هاتف')),
      );
      return;
    }

    final unsentTargets = <Map<String, dynamic>>[];
    int alreadySentCount = 0;
    for (final s in targets) {
      final sId = s['id'] as String? ?? '';
      final wasSent = await widget.database.isStudentReportSentToday(
        studentId: sId,
        date: widget.date,
      );
      if (wasSent) {
        alreadySentCount++;
      } else {
        unsentTargets.add(s);
      }
    }

    if (unsentTargets.isEmpty) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
              SizedBox(width: 8),
              Expanded(child: Text('تم إرسال التقارير مسبقاً ✅')),
            ],
          ),
          content: Text(
            'جميع الطلاب المحددين (${targets.length} طالب) تم إرسال تقرير حصة اليوم (${widget.date}) إلى أولياء أمورهم مسبقاً.\n\nتم منع التكرار تلقائياً 🛡️.',
            style: const TextStyle(height: 1.4, fontSize: 13),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      return;
    }

    if (alreadySentCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'تنبيه: تم استبعاد $alreadySentCount طالب تلقائياً لسبق إرسال التقرير لولي الأمر اليوم 🛡️'),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    final channel = await ReportDispatchHelper.showChannelPicker(
      context: context,
      studentName: 'جميع طلاب المجموعة (${unsentTargets.length} طالب)',
      reportTitle: 'إرسال تقارير حصة المجموعة 📋',
    );
    if (channel == null || !mounted) return;

    setState(() {
      isSending = true;
      _cancelSendingRequested = false;
      sendProgress = 0.0;
      progressText = 'بدء الإرسال لـ ${unsentTargets.length} طالب...';
      sentSuccessCount = 0;
      sentFailCount = 0;
    });

    final delaySetting = await widget.database.getSetting('whatsapp_send_delay_seconds', defaultValue: '3');
    final baseDelaySec = int.tryParse(delaySetting) ?? 3;
    final random = Random();

    for (int i = 0; i < unsentTargets.length; i++) {
      if (!mounted || _cancelSendingRequested) break;
      final student = unsentTargets[i];
      final sId = student['id'] as String? ?? '';
      final sName = student['full_name'] as String? ?? 'الطالب';
      final pPhone = (student['parent_phone'] as String? ?? '').trim();
      final sPhone = (student['student_phone'] as String? ?? '').trim();
      final phone = pPhone.isNotEmpty ? pPhone : sPhone;

      File? cardImage;
      if (sendAsVisualCard) {
        setState(() {
          progressText = 'جاري توليد كارت التقرير المصور لـ $sName (${i + 1} من ${unsentTargets.length})...';
        });
        cardImage = await _captureStudentCardFile(student);
      }

      setState(() {
        sendProgress = (i + 1) / unsentTargets.length;
        progressText = channel == ReportDispatchChannel.appOnly
            ? 'جاري الإرسال لتطبيق الطالب لـ $sName (${i + 1} من ${unsentTargets.length})...'
            : (waMode == 'api'
                ? 'جاري الإرسال الإلكتروني السحابي لـ $sName (${i + 1} من ${unsentTargets.length})...'
                : 'جاري إرسال التقرير لـ $sName (${i + 1} من ${unsentTargets.length})...');
      });

      final message = (sendAsVisualCard && !includeTextMessageWithCard)
          ? ''
          : _buildMessageForStudent(student);

      final sCode = student['code']?.toString() ?? sId;

      // 1. إرسال إلى تطبيق الطالب
      if (channel == ReportDispatchChannel.appOnly || channel == ReportDispatchChannel.both) {
        try {
          final notifBody = message.isNotEmpty ? message : 'تم إصدار تقرير الحصة اليومية بنجاح 📋';
          await AcademyCommunicationService.instance.sendNotification(
            title: '📋 تقرير متابعة الحصة اليومية',
            body: notifBody.length > 250 ? '${notifBody.substring(0, 247)}...' : notifBody,
            type: 'sessionFollowup',
            targetType: 'student',
            targetId: sId,
            targetName: sName,
          );
          await AcademyCommunicationService.instance.sendMessageFromTeacher(
            studentId: sId,
            studentName: sName,
            studentCode: sCode,
            text: notifBody,
          );
        } catch (e) {
          debugPrint('Error sending bulk report to student app: $e');
        }
      }

      // 2. إرسال إلى واتساب
      bool ok = true;
      if (channel == ReportDispatchChannel.whatsappOnly || channel == ReportDispatchChannel.both) {
        ok = await WhatsAppService.dispatchMessage(
          database: widget.database,
          phone: phone,
          message: message,
          studentId: sId,
          studentName: sName,
          recipientType: 'parent',
          category: 'daily_report',
          imageFile: cardImage,
          forceManual: false,
        );
      }

      if (ok) {
        sentSuccessCount++;
        sentStudentIds.add(sId);
        selectedStudentIds.remove(sId);
        await widget.database.recordSentMessage(
          studentId: sId,
          category: 'daily_report',
          contextKey: widget.date,
          phone: phone,
          status: 'sent',
        );
      } else {
        sentFailCount++;
      }

      if (i < targets.length - 1 && mounted && !_cancelSendingRequested) {
        if (channel != ReportDispatchChannel.appOnly) {
          final jitterMs = waMode == 'api' ? 400 : (baseDelaySec * 1000) + random.nextInt(600);
          await Future.delayed(Duration(milliseconds: jitterMs));
        } else {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }

    if (mounted) {
      if (sentSuccessCount > 0) {
        await widget.database.setSetting('report_sent_${widget.group.id}_${widget.date}', 'true');
        await NotificationService.cancelUnsentReportReminder(widget.group.id);
      }
      setState(() {
        isSending = false;
        progressText = 'اكتمل الإرسال: $sentSuccessCount ناجح • $sentFailCount تعذر';
      });

      await _showSuccessResultDialog(
        title: _cancelSendingRequested ? 'تم إيقاف الإرسال' : 'اكتمل إرسال تقارير الحصة! 🎉',
        subtitle: 'تم إرسال تقرير متابعة حصة ${widget.group.name} بنجاح إلى أولياء الأمور.',
        successCount: sentSuccessCount,
        failCount: sentFailCount,
      );
    }
  }

  void _copyPreviewMessage(String msg) {
    Clipboard.setData(ClipboardData(text: msg));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ نص التقرير إلى الحافظة بنجاح 📋'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const emeraldColor = Color(0xFF059669);

    final validStudents = students.where((s) {
      final pPhone = (s['parent_phone'] as String? ?? '').trim();
      final sPhone = (s['student_phone'] as String? ?? '').trim();
      return pPhone.isNotEmpty || sPhone.isNotEmpty;
    }).toList();

    final previewStudent = students.firstWhere(
      (s) => s['id'] == previewStudentId,
      orElse: () => students.isNotEmpty ? students.first : <String, dynamic>{},
    );

    final previewMsg = previewStudent.isNotEmpty ? _buildMessageForStudent(previewStudent) : '';

    return Stack(
      children: [
        Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
            minHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag Handle
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 10),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: emeraldColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.mark_chat_unread_rounded, color: emeraldColor, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إرسال تقرير الحصة • ${widget.group.name}',
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.group.grade} • تاريخ: ${widget.date}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 18),

              // Body Content
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          // 0. Visual Report Card Format Selector & Live Customizer
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: sendAsVisualCard
                                    ? [const Color(0xFF0F172A), const Color(0xFF1E1B4B)]
                                    : [
                                        isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                        isDark ? const Color(0xFF0F172A) : Colors.white,
                                      ],
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: sendAsVisualCard
                                    ? const Color(0xFF00F2FE).withValues(alpha: 0.5)
                                    : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.style_rounded, color: Color(0xFF00F2FE), size: 20),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'صيغة التقرير: كارت رقمي مصور فاخر 🖼️✨',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            'كارت مصور عالي الدقة بهوية الأكاديمية والدرجات وتقييم المعلم',
                                            style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: sendAsVisualCard,
                                      activeTrackColor: const Color(0xFF00F2FE),
                                      onChanged: (val) {
                                        HapticFeedback.selectionClick();
                                        setState(() => sendAsVisualCard = val);
                                        widget.database.setSetting('report_card_send_as_visual', val.toString());
                                      },
                                    ),
                                  ],
                                ),
                                if (sendAsVisualCard) ...[
                                  const SizedBox(height: 10),
                                  Divider(color: const Color(0xFF00F2FE).withValues(alpha: 0.2), height: 1),
                                  const SizedBox(height: 8),

                                  // Toggle: Send Image Only vs Image + Text
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          includeTextMessageWithCard
                                              ? Icons.chat_bubble_outline_rounded
                                              : Icons.image_rounded,
                                          size: 19,
                                          color: includeTextMessageWithCard
                                              ? const Color(0xFF00F2FE)
                                              : const Color(0xFFF59E0B),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                includeTextMessageWithCard
                                                    ? 'إرسال صورة الكارت + الرسالة النصية 🖼️📝'
                                                    : 'إرسال صورة الكارت فقط بدون نص 🖼️',
                                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                              ),
                                              Text(
                                                includeTextMessageWithCard
                                                    ? 'سيتم إرفاق صورة الكارت الفاخرة مع تقرير نصي كامل'
                                                    : 'سيتم إرسال صورة كارت التقرير الملونة فقط دون أي نص في الرسالة',
                                                style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Switch.adaptive(
                                          value: includeTextMessageWithCard,
                                          activeTrackColor: const Color(0xFF00F2FE),
                                          onChanged: (val) {
                                            HapticFeedback.selectionClick();
                                            setState(() => includeTextMessageWithCard = val);
                                            widget.database.setSetting('report_card_include_text_message', val.toString());
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Font selector chips
                                  Row(
                                    children: [
                                      const Text('الخط: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: ReportCardFont.values.map((f) {
                                              final isSel = selectedFont == f;
                                              return Padding(
                                                padding: const EdgeInsets.only(left: 6),
                                                child: ChoiceChip(
                                                  label: Text(f.label, style: TextStyle(fontSize: 10.5, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                                                  selected: isSel,
                                                  selectedColor: const Color(0xFF00F2FE),
                                                  backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                                                  labelStyle: TextStyle(color: isSel ? Colors.black : (isDark ? Colors.white70 : Colors.black87)),
                                                  onSelected: (val) {
                                                    if (val) setState(() => selectedFont = f);
                                                  },
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Preview Card Button
                                  SizedBox(
                                    width: double.infinity,
                                    height: 38,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF00F2FE),
                                        side: const BorderSide(color: Color(0xFF00F2FE)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.remove_red_eye_rounded, size: 17),
                                      label: const Text(
                                        'معاينة كارت التقرير المصور الفاخر للطلاب 👁️✨',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      onPressed: () {
                                        final studentToPreview = previewStudent.isNotEmpty
                                            ? previewStudent
                                            : (validStudents.isNotEmpty ? validStudents.first : null);
                                        if (studentToPreview != null) {
                                          _openCardPreviewForStudent(studentToPreview);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // 1. Session Curriculum Summary Card
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                            ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.menu_book_rounded, color: emeraldColor, size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    sessionLog != null && sessionLog!.lessonTitle.trim().isNotEmpty
                                        ? 'موضوع الدرس: ${sessionLog!.lessonTitle}'
                                        : 'موضوع الدرس: مقرر الحصة اليومي',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: sessionLog != null
                                        ? emeraldColor.withValues(alpha: 0.15)
                                        : Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    sessionLog != null ? '✅ المنهج مسجل' : '⚠️ دفتر الحصة فارغ',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: sessionLog != null ? emeraldColor : Colors.amber.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (sessionLog?.homework.isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              Text(
                                '📝 الواجب: ${sessionLog!.homework}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark ? Colors.grey.shade300 : const Color(0xFF334155),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 2. Message Preview Option Card (Requested Feature)
                      Container(
                        decoration: BoxDecoration(
                          color: showPreview
                              ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.15) : const Color(0xFFECFDF5))
                              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: showPreview
                                ? emeraldColor.withValues(alpha: 0.4)
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => showPreview = !showPreview);
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Icon(
                                      showPreview ? Icons.visibility_rounded : Icons.visibility_outlined,
                                      color: showPreview ? emeraldColor : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'معاينة نص الرسالة قبل الإرسال 👁️',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: showPreview ? emeraldColor : (isDark ? Colors.white : const Color(0xFF0F172A)),
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            'راجع محتوى التقرير كما سيصل لولي الأمر عبر واتساب',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: showPreview,
                                      activeTrackColor: emeraldColor,
                                      onChanged: (val) {
                                        HapticFeedback.selectionClick();
                                        setState(() => showPreview = val);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Expanded Preview Body
                            if (showPreview) ...[
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (sendAsVisualCard && !includeTextMessageWithCard)
                                      Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.info_outline_rounded, color: Colors.amber, size: 16),
                                            SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'تنبيه: تم ضبط الإرسال على (صورة الكارت فقط بدون نص 🖼️). لن يتم إرفاق هذا النص في رسالة واتساب.',
                                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amber),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    // Student selector for preview & copy button
                                    Wrap(
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              'معاينة لـ: ',
                                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                            ),
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: MediaQuery.of(context).size.width * 0.45,
                                              ),
                                              child: students.length > 1
                                                  ? DropdownButtonHideUnderline(
                                                      child: DropdownButton<String>(
                                                        value: previewStudentId,
                                                        isDense: true,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                          color: isDark ? Colors.white : Colors.black87,
                                                        ),
                                                        items: students.map((s) {
                                                          final sId = s['id'] as String? ?? '';
                                                          final sName = s['full_name'] as String? ?? 'طالب';
                                                          return DropdownMenuItem(
                                                            value: sId,
                                                            child: Text(sName, overflow: TextOverflow.ellipsis),
                                                          );
                                                        }).toList(),
                                                        onChanged: (val) {
                                                          if (val != null) setState(() => previewStudentId = val);
                                                        },
                                                      ),
                                                    )
                                                  : Text(
                                                      previewStudent['full_name'] as String? ?? '',
                                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              onTap: _showEditMasterTemplateDialog,
                                              borderRadius: BorderRadius.circular(6),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.tune_rounded, size: 13, color: Color(0xFF0284C7)),
                                                    SizedBox(width: 3),
                                                    Text(
                                                      'النموذج العام ⚙️',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF0284C7),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            InkWell(
                                              onTap: () => _copyPreviewMessage(previewMsg),
                                              borderRadius: BorderRadius.circular(6),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                                                decoration: BoxDecoration(
                                                  color: emeraldColor.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: emeraldColor.withValues(alpha: 0.3),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.copy_rounded, size: 13, color: emeraldColor),
                                                    SizedBox(width: 3),
                                                    Text(
                                                      'نسخ 📋',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: emeraldColor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // WhatsApp Chat Bubble
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF064E3B).withValues(alpha: 0.3)
                                            : const Color(0xFFDCF8C6).withValues(alpha: 0.8),
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(14),
                                          topRight: Radius.circular(14),
                                          bottomLeft: Radius.circular(14),
                                          bottomRight: Radius.circular(4),
                                        ),
                                        border: Border.all(
                                          color: emeraldColor.withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: SelectableText(
                                        previewMsg,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.45,
                                          color: isDark ? Colors.grey.shade200 : const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // WhatsApp Send Mode Toggle Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: (waMode == 'api' ? const Color(0xFF10B981) : const Color(0xFF0284C7))
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              waMode == 'api' ? Icons.cloud_done_rounded : Icons.phone_android_rounded,
                              size: 18,
                              color: waMode == 'api' ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    waMode == 'api'
                                        ? 'وضع الإرسال: آلي وسحابي (API) ☁️'
                                        : 'وضع الإرسال: يدوي ومباشر (تطبيق واتساب) 📲',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    waMode == 'api'
                                        ? 'يرسل في الخلفية تلقائياً دون فتح تطبيق واتساب'
                                        : 'يفتح محادثة ولي الأمر داخل تطبيق واتساب',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () => _toggleWaMode(),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: (waMode == 'api' ? const Color(0xFF10B981) : const Color(0xFF0284C7))
                                      .withValues(alpha: isDark ? 0.2 : 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: (waMode == 'api' ? const Color(0xFF10B981) : const Color(0xFF0284C7))
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.swap_horiz_rounded,
                                      size: 15,
                                      color: waMode == 'api' ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      waMode == 'api' ? 'تحويل ليدوي' : 'تحويل لـ API',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: waMode == 'api' ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 3. Students Selection Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'أولياء أمور المجموعة (${selectedStudentIds.length} من ${validStudents.length} محدد)',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () {
                              setState(() {
                                final unsentIds = validStudents
                                    .map((s) => s['id'] as String? ?? '')
                                    .where((id) => id.isNotEmpty && !sentStudentIds.contains(id))
                                    .toSet();
                                if (selectedStudentIds.length == unsentIds.length && unsentIds.isNotEmpty) {
                                  selectedStudentIds.clear();
                                } else {
                                  selectedStudentIds = unsentIds;
                                }
                              });
                            },
                            child: Text(
                              selectedStudentIds.isNotEmpty &&
                                      selectedStudentIds.length ==
                                          validStudents
                                              .map((s) => s['id'] as String? ?? '')
                                              .where((id) => id.isNotEmpty && !sentStudentIds.contains(id))
                                              .length
                                  ? 'إلغاء التحديد'
                                  : 'تحديد المتبقي للإرسال',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // 4. Students List
                      if (students.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(child: Text('لا يوجد طلاب مسجلين في هذه المجموعة')),
                        )
                      else
                        ...students.map((student) {
                          final sId = student['id'] as String? ?? '';
                          final sName = student['full_name'] as String? ?? 'طالب';
                          final pPhone = (student['parent_phone'] as String? ?? '').trim();
                          final sPhone = (student['student_phone'] as String? ?? '').trim();
                          final phone = pPhone.isNotEmpty ? pPhone : sPhone;
                          final hasPhone = phone.isNotEmpty;
                          final isSelected = selectedStudentIds.contains(sId);
                          final isSent = sentStudentIds.contains(sId);

                          final attStatus = student['attendance_status'] as String?;
                          final recitation = student['recitation_rating'] as String?;
                          final hwStatus = student['homework_status'] as String?;

                          Color statusColor = Colors.grey;
                          String statusText = 'لم يرصد';
                          if (attStatus == 'present') {
                            statusColor = emeraldColor;
                            statusText = 'حاضر 🟢';
                          } else if (attStatus == 'late') {
                            statusColor = Colors.orange;
                            statusText = 'متأخر 🟡';
                          } else if (attStatus == 'absent') {
                            statusColor = Colors.red;
                            statusText = 'غائب 🚨';
                          } else if (attStatus == 'excused') {
                            statusColor = Colors.blue;
                            statusText = 'معذور ⚪';
                          }

                          return Opacity(
                            opacity: isSent ? 0.55 : 1.0,
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 7),
                              elevation: isSent ? 0 : 0.5,
                              color: isSent
                                  ? (isDark
                                      ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                                      : const Color(0xFFF1F5F9))
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isSent
                                      ? (isDark ? Colors.grey.shade700 : Colors.grey.shade300)
                                      : (isSelected
                                          ? emeraldColor.withValues(alpha: 0.25)
                                          : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Row(
                                  children: [
                                    // Checkbox
                                    Checkbox(
                                      value: isSent ? false : isSelected,
                                      activeColor: emeraldColor,
                                      visualDensity: VisualDensity.compact,
                                      onChanged: hasPhone && !isSending && !isSent
                                          ? (val) {
                                              setState(() {
                                                if (val == true) {
                                                  selectedStudentIds.add(sId);
                                                } else {
                                                  selectedStudentIds.remove(sId);
                                                }
                                              });
                                            }
                                          : null,
                                    ),
                                    const SizedBox(width: 4),

                                    // Student Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  sName,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: isSent
                                                        ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
                                                        : null,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: statusColor.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  statusText,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: statusColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 6,
                                            runSpacing: 2,
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    hasPhone ? Icons.phone_rounded : Icons.phone_disabled_rounded,
                                                    size: 12,
                                                    color: hasPhone ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600) : Colors.red,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    hasPhone ? phone : 'لا يوجد رقم هاتف مسجل',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: hasPhone
                                                          ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
                                                          : Colors.red,
                                                      fontWeight: hasPhone ? FontWeight.normal : FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (recitation != null && recitation.trim().isNotEmpty)
                                                Text(
                                                  '• تسميع: $recitation',
                                                  style: const TextStyle(fontSize: 10.5, color: emeraldColor, fontWeight: FontWeight.w600),
                                                ),
                                              if (hwStatus != null && hwStatus.trim().isNotEmpty)
                                                Text(
                                                  '• واجب: $hwStatus',
                                                  style: TextStyle(fontSize: 10.5, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Single Send Action / Sent Indicator
                                    if (isSent)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.check_circle_rounded,
                                              size: 13,
                                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'تم الإرسال بالفعل ✓',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else if (hasPhone)
                                      IconButton(
                                        icon: const Icon(Icons.send_rounded, color: Color(0xFF25D366), size: 18),
                                        tooltip: 'إرسال التقرير لهذا الطالب فقط',
                                        onPressed: isSending ? null : () => _sendSingle(student),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
          ),

          // Bottom Action Area
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress Bar if sending
                if (isSending) ...[
                  LinearProgressIndicator(
                    value: sendProgress > 0 ? sendProgress : null,
                    color: emeraldColor,
                    backgroundColor: emeraldColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          progressText,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          setState(() => _cancelSendingRequested = true);
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            'إيقاف 🛑',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Big Primary Send Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emeraldColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 1,
                    ),
                    onPressed: isSending || selectedStudentIds.isEmpty ? null : _sendBulk,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            isSending
                                ? 'جاري الإرسال...'
                                : 'إرسال التقرير لـ (${selectedStudentIds.length}) من أولياء الأمور 🚀',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Link to Open in Full WhatsApp Hub
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WhatsAppHubScreen(
                          database: widget.database,
                          initialGroupId: widget.group.id,
                          initialCategory: ParentServiceCategory.sessionFollowup,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text(
                      'فتح في مركز الرسائل المتقدم ↗',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    // Hidden Offscreen Render Target for generating high-definition report card PNGs
    Positioned(
      left: -9999,
      top: 0,
      child: RepaintBoundary(
        key: _offscreenRepaintKey,
        child: _currentlyRenderingStudent != null
            ? _buildCardWidgetForStudent(_currentlyRenderingStudent!)
            : const SizedBox.shrink(),
      ),
    ),
  ],
);
  }
}

