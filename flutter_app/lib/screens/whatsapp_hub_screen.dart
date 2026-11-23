import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/database/database_service.dart';
import '../core/daily_report_service.dart';
import '../core/whatsapp_service.dart';
import '../models/attendance_model.dart';
import '../models/curriculum_model.dart';
import '../models/exam_model.dart';
import '../models/group_model.dart';
import '../models/payment_model.dart';
import '../models/student_model.dart';
import '../widgets/section_top_bar.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';

enum ParentServiceCategory {
  sessionFollowup,
  absenceAlert,
  examScore,
  financialReceipt,
  notebookBehavior,
  holisticReport,
  sessionCancellation,
  sessionReminder,
}

enum ServiceDomain { all, academic, attendance, financial }

enum GroupSelectionMode { today, tomorrow, custom }

enum StudentReportPeriod { session, weekly, monthly }

enum WhatsAppRecipientTarget { parent, student, both }

enum WhatsAppSendScope {
  singleStudent, // طالب محدد
  singleGroup, // المجموعة كلها مرة واحدة
  todayGroups, // كل مجاميع اليوم
  customGroups, // اختيار مخصص لأكثر من مجموعة
}

class WhatsAppHubScreen extends StatefulWidget {
  const WhatsAppHubScreen(
      {super.key,
      required this.database,
      this.initialCategory,
      this.initialGroupId,
      this.initialReportPeriod,
      this.onBack,
      this.promptDailyReportSend = false});
  final DatabaseService database;
  final ParentServiceCategory? initialCategory;
  final String? initialGroupId;
  final StudentReportPeriod? initialReportPeriod;
  final VoidCallback? onBack;
  final bool promptDailyReportSend;

  @override
  State<WhatsAppHubScreen> createState() => _WhatsAppHubScreenState();
}

class _WhatsAppHubScreenState extends State<WhatsAppHubScreen> {
  ParentServiceCategory activeCategory = ParentServiceCategory.sessionFollowup;
  WhatsAppRecipientTarget _recipientTarget = WhatsAppRecipientTarget.parent;
  WhatsAppSendScope _sendScope = WhatsAppSendScope.singleGroup;
  final Set<String> _selectedCustomGroupIds = {};
  String? _singleStudentGroupFilter = 'all';

  int _mainTabIndex = 0;
  ServiceDomain _activeDomain = ServiceDomain.all;
  GroupSelectionMode _groupMode = GroupSelectionMode.today;
  String _dailyFilterType = 'all'; // 'all', 'absent', 'debt'
  String _logsSearchText = '';
  String _logsFilterStatus = 'all'; // 'all', 'sent', 'failed'
  final Set<int> _selectedLogIds = {};

  List<StudentModel> allStudents = [];
  List<GroupModel> allGroups = [];
  List<ExamModel> allExams = [];
  List<AttendanceModel> todayAttendance = [];
  List<PaymentModel> allPayments = [];
  Map<String, double> selectedExamScores = {};
  Map<String, SessionLogModel?> groupLatestLogs = {};
  List<AttendanceModel> _studentReportAttendance = [];
  List<Map<String, dynamic>> _studentReportExamScores = [];
  String? _reportDataStudentId;
  bool _isLoadingStudentReport = false;
  StudentReportPeriod _reportPeriod = StudentReportPeriod.session;

  String? selectedGroupId;
  StudentModel? selectedStudent;
  ExamModel? selectedExam;

  String centerName = 'أكاديمية المستقبل';
  String teacherName = 'الأستاذ';
  String currentWaMode = 'manual';
  String messageFooter = '';
  String sessionReportCustomTemplate = '';
  Map<String, String> categoryFooters = {};
  String _logsFilterCategory = 'all';
  final Map<String, List<AttendanceModel>> _batchAttendanceCache = {};
  final Map<String, List<Map<String, dynamic>>> _batchExamCache = {};
  bool enableFooter = true;
  bool isLoading = true;

  // Custom Category Parameters
  String behaviorNote = '';
  bool isTeacherCancellation = true;
  late final TextEditingController _cancelReasonController;
  late final TextEditingController _makeupDateController;
  late final TextEditingController _reminderExtraNoteController;
  bool isDueReminderMode = true;

  final TextEditingController customMessageController = TextEditingController();
  bool isEditingCustomText = false;
  StreamSubscription<DataChangeEvent>? _dataSub;

  @override
  void initState() {
    super.initState();
    _cancelReasonController = TextEditingController();
    _makeupDateController = TextEditingController();
    _reminderExtraNoteController = TextEditingController();
    if (widget.initialCategory != null) {
      activeCategory = widget.initialCategory!;
      _mainTabIndex = 0;
    }
    if (widget.initialReportPeriod != null) {
      _reportPeriod = widget.initialReportPeriod!;
      activeCategory = ParentServiceCategory.holisticReport;
      _mainTabIndex = 0;
    }
    if (widget.initialGroupId != null) {
      selectedGroupId = widget.initialGroupId;
    }
    _loadAllData();
    if (widget.promptDailyReportSend) {
      _mainTabIndex = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_confirmDailyReportSend());
      });
    }
    _dataSub = widget.database.onDataChanged.listen((_) {
      if (mounted) _loadAllData();
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _cancelReasonController.dispose();
    _makeupDateController.dispose();
    _reminderExtraNoteController.dispose();
    customMessageController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (allStudents.isEmpty) {
      setState(() => isLoading = true);
    }
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final results = await Future.wait([
      widget.database.getStudents(),
      widget.database.getGroups(),
      widget.database.getExams(),
      widget.database
          .getSetting('center_name', defaultValue: 'أكاديمية المستقبل'),
      widget.database.getSetting('teacher_name', defaultValue: 'الأستاذ'),
      widget.database.getSetting('whatsapp_mode', defaultValue: 'manual'),
      widget.database.getSetting('whatsapp_message_footer', defaultValue: ''),
      widget.database
          .getSetting('whatsapp_enable_footer', defaultValue: 'true'),
      widget.database.getAttendanceForDate(today),
      widget.database.getAllPayments(),
    ]);

    final students = results[0] as List<StudentModel>;
    final groups = results[1] as List<GroupModel>;
    final exams = results[2] as List<ExamModel>;
    final cName = results[3] as String;
    final tName = results[4] as String;
    final waMode = results[5] as String;
    final waFooter = results[6] as String;
    final waEnableFooter = results[7] as String;
    final attendance = results[8] as List<AttendanceModel>;
    final payments = results[9] as List<PaymentModel>;
    final scores = exams.isEmpty
        ? <String, double>{}
        : await widget.database.getExamScoresForExam(exams.first.id);

    var finalFooter = waFooter;
    if (finalFooter.trim().isEmpty && waEnableFooter == 'true') {
      final phone = await widget.database.getSetting('phone', defaultValue: '');
      final name = cName.isNotEmpty ? cName : tName;
      if (name.isNotEmpty || phone.isNotEmpty) {
        final pPart = phone.isNotEmpty ? '\n📞 للتواصل: $phone' : '';
        finalFooter = '---\n📍 $name$pPart';
      }
    }

    // Parallel fetch for session logs across groups
    final logEntries = await Future.wait(groups.map((g) async {
      final log = await widget.database.getLatestSessionLogForGroup(g.id);
      return MapEntry(g.id, log);
    }));
    final logs = Map<String, SessionLogModel?>.fromEntries(logEntries);

    final Map<String, String> catFooters = {};
    for (final cat in ParentServiceCategory.values) {
      catFooters[cat.name] = await widget.database.getCategoryFooter(cat.name);
    }

    final customTpl = await widget.database.getSetting('whatsapp_template_session_report', defaultValue: '');

    if (mounted) {
      setState(() {
        allStudents = students;
        allGroups = groups;
        allExams = exams;
        todayAttendance = attendance;
        allPayments = payments;
        selectedExamScores = scores;
        groupLatestLogs = logs;
        centerName = cName;
        teacherName = tName;
        currentWaMode = waMode;
        messageFooter = finalFooter;
        sessionReportCustomTemplate = customTpl;
        categoryFooters = catFooters;
        enableFooter = waEnableFooter == 'true';

        final todayArabic = _getTodayArabicName();
        final tomorrowArabic = _getTomorrowArabicName();

        final currentTodayGroups = groups.where((g) {
          if (g.days.isNotEmpty && g.days.contains(todayArabic)) return true;
          if (g.schedule.isNotEmpty && g.schedule.contains(todayArabic)) return true;
          return false;
        }).toList()..sort(GroupModel.compareByStartTime);

        final currentTomorrowGroups = groups.where((g) {
          if (g.days.isNotEmpty && g.days.contains(tomorrowArabic)) return true;
          if (g.schedule.isNotEmpty && g.schedule.contains(tomorrowArabic)) return true;
          return false;
        }).toList()..sort(GroupModel.compareByStartTime);

        GroupSelectionMode initialGroupMode = GroupSelectionMode.today;
        List<GroupModel> targetSmartGroups = currentTodayGroups;

        if (activeCategory == ParentServiceCategory.sessionReminder) {
          if (currentTodayGroups.isNotEmpty) {
            initialGroupMode = GroupSelectionMode.today;
            targetSmartGroups = currentTodayGroups;
          } else if (currentTomorrowGroups.isNotEmpty) {
            initialGroupMode = GroupSelectionMode.tomorrow;
            targetSmartGroups = currentTomorrowGroups;
          }
        }

        if (widget.initialGroupId != null && groups.any((g) => g.id == widget.initialGroupId)) {
          selectedGroupId = widget.initialGroupId;
          if (targetSmartGroups.any((g) => g.id == widget.initialGroupId)) {
            _groupMode = initialGroupMode;
          } else {
            _groupMode = GroupSelectionMode.custom;
          }
        } else if (targetSmartGroups.isNotEmpty) {
          _groupMode = initialGroupMode;
          if (selectedGroupId == null || (!targetSmartGroups.any((g) => g.id == selectedGroupId) && selectedGroupId != 'today_all')) {
            selectedGroupId = targetSmartGroups.first.id;
          }
        } else {
          _groupMode = GroupSelectionMode.custom;
          if (selectedGroupId == null || (!groups.any((g) => g.id == selectedGroupId) && selectedGroupId != 'all')) {
            selectedGroupId = groups.isEmpty ? 'all' : groups.first.id;
          }
        }

        if (_selectedCustomGroupIds.isEmpty) {
          if (currentTodayGroups.isNotEmpty) {
            _selectedCustomGroupIds.addAll(currentTodayGroups.map((g) => g.id));
          } else if (groups.isNotEmpty) {
            _selectedCustomGroupIds.addAll(groups.take(2).map((g) => g.id));
          }
        }

        final initialFiltered = filteredStudents;
        if (initialFiltered.isNotEmpty) {
          selectedStudent = initialFiltered.first;
        } else if (students.isNotEmpty) {
          selectedStudent = students.first;
        }
        if (exams.isNotEmpty) {
          selectedExam = exams.first;
        }
        isLoading = false;
      });
      _syncCustomMessageBuffer();
      if (activeCategory == ParentServiceCategory.holisticReport &&
          selectedStudent != null) {
        unawaited(
          _loadStudentReportData(selectedStudent!.id, force: true),
        );
      }
    }
  }

  String _getTodayArabicName([DateTime? date]) {
    final d = date ?? DateTime.now();
    switch (d.weekday) {
      case DateTime.saturday:
        return 'السبت';
      case DateTime.sunday:
        return 'الأحد';
      case DateTime.monday:
        return 'الاثنين';
      case DateTime.tuesday:
        return 'الثلاثاء';
      case DateTime.wednesday:
        return 'الأربعاء';
      case DateTime.thursday:
        return 'الخميس';
      case DateTime.friday:
        return 'الجمعة';
      default:
        return '';
    }
  }

  String _getTomorrowArabicName([DateTime? date]) {
    final d = (date ?? DateTime.now()).add(const Duration(days: 1));
    return _getTodayArabicName(d);
  }

  bool _isGroupScheduledToday(GroupModel g) {
    final todayArabic = _getTodayArabicName();
    if (g.days.isNotEmpty && g.days.contains(todayArabic)) return true;
    if (g.schedule.isNotEmpty && g.schedule.contains(todayArabic)) return true;
    return false;
  }

  bool _isGroupScheduledTomorrow(GroupModel g) {
    final tomorrowArabic = _getTomorrowArabicName();
    if (g.days.isNotEmpty && g.days.contains(tomorrowArabic)) return true;
    if (g.schedule.isNotEmpty && g.schedule.contains(tomorrowArabic)) return true;
    return false;
  }

  List<GroupModel> get todayGroups {
    return allGroups.where(_isGroupScheduledToday).toList()
      ..sort(GroupModel.compareByStartTime);
  }

  List<GroupModel> get tomorrowGroups {
    return allGroups.where(_isGroupScheduledTomorrow).toList()
      ..sort(GroupModel.compareByStartTime);
  }

  bool get isReminderCategory => activeCategory == ParentServiceCategory.sessionReminder;

  List<GroupModel> get defaultSmartGroups {
    if (_groupMode == GroupSelectionMode.tomorrow) {
      return tomorrowGroups;
    }
    return todayGroups;
  }

  String get smartModeTitle {
    if (_groupMode == GroupSelectionMode.tomorrow) {
      return 'مجموعات الغد';
    }
    return 'مجموعات اليوم';
  }

  String get smartModeDayName {
    if (_groupMode == GroupSelectionMode.tomorrow) {
      return _getTomorrowArabicName();
    }
    return _getTodayArabicName();
  }

  List<StudentModel> get todayGroupStudents {
    final todayIds = todayGroups.map((g) => g.id).toSet();
    return allStudents.where((s) => todayIds.contains(s.groupId)).toList();
  }

  List<StudentModel> get customGroupStudents {
    return allStudents.where((s) => _selectedCustomGroupIds.contains(s.groupId)).toList();
  }

  List<StudentModel> get currentScopeStudents {
    switch (_sendScope) {
      case WhatsAppSendScope.singleStudent:
        final active = selectedStudent ??
            (_studentsForSingleStudentScope.isNotEmpty ? _studentsForSingleStudentScope.first : null);
        return active != null ? [active] : [];
      case WhatsAppSendScope.singleGroup:
        return filteredStudents;
      case WhatsAppSendScope.todayGroups:
        return todayGroupStudents;
      case WhatsAppSendScope.customGroups:
        return customGroupStudents;
    }
  }

  String get currentScopeTitle {
    switch (_sendScope) {
      case WhatsAppSendScope.singleStudent:
        return 'طالب محدد 👤';
      case WhatsAppSendScope.singleGroup:
        return 'المجموعة كلها 👥';
      case WhatsAppSendScope.todayGroups:
        return 'مجاميع اليوم 🌟';
      case WhatsAppSendScope.customGroups:
        return 'مجموعات مخصصة ✨';
    }
  }

  String get currentScopeDescription {
    switch (_sendScope) {
      case WhatsAppSendScope.singleStudent:
        final name = selectedStudent?.fullName ?? (_studentsForSingleStudentScope.isNotEmpty ? _studentsForSingleStudentScope.first.fullName : 'لم يحدد');
        return 'طالب محدد: $name';
      case WhatsAppSendScope.singleGroup:
        final grp = currentSelectedGroup?.name ?? 'المجموعة';
        return 'مجموعة: $grp (${filteredStudents.length} طالب)';
      case WhatsAppSendScope.todayGroups:
        return 'جميع مجاميع اليوم (${todayGroups.length} مجموعات - ${todayGroupStudents.length} طالب)';
      case WhatsAppSendScope.customGroups:
        return 'مجموعات مخصصة (${_selectedCustomGroupIds.length} مجموعات - ${customGroupStudents.length} طالب)';
    }
  }

  List<StudentModel> get _studentsForSingleStudentScope {
    if (_singleStudentGroupFilter == null || _singleStudentGroupFilter == 'all') {
      return allStudents;
    }
    return allStudents.where((s) => s.groupId == _singleStudentGroupFilter).toList();
  }

  void _applyScopeSelection(ParentServiceCategory cat, WhatsAppSendScope scope) {
    HapticFeedback.selectionClick();
    setState(() {
      activeCategory = cat;
      _sendScope = scope;
      isEditingCustomText = false;

      if (scope == WhatsAppSendScope.customGroups) {
        if (_selectedCustomGroupIds.isEmpty) {
          if (todayGroups.isNotEmpty) {
            _selectedCustomGroupIds.addAll(todayGroups.map((g) => g.id));
          } else if (allGroups.isNotEmpty) {
            _selectedCustomGroupIds.addAll(allGroups.take(2).map((g) => g.id));
          }
        }
      } else if (scope == WhatsAppSendScope.todayGroups) {
        _groupMode = GroupSelectionMode.today;
        if (todayGroups.isNotEmpty) {
          selectedGroupId = 'today_all';
        }
      } else if (scope == WhatsAppSendScope.singleGroup) {
        if (todayGroups.isNotEmpty && (selectedGroupId == null || selectedGroupId == 'today_all' || selectedGroupId == 'all')) {
          selectedGroupId = todayGroups.first.id;
        } else if (selectedGroupId == null || selectedGroupId == 'all' || selectedGroupId == 'today_all') {
          selectedGroupId = allGroups.isNotEmpty ? allGroups.first.id : 'all';
        }
      } else if (scope == WhatsAppSendScope.singleStudent) {
        if (selectedGroupId != null && selectedGroupId != 'all' && selectedGroupId != 'today_all') {
          _singleStudentGroupFilter = selectedGroupId;
        }
        final list = _studentsForSingleStudentScope;
        if (list.isNotEmpty && (selectedStudent == null || !list.contains(selectedStudent))) {
          selectedStudent = list.first;
        }
      }

      final list = filteredStudents;
      if (list.isNotEmpty) {
        if (selectedStudent == null || !list.contains(selectedStudent)) {
          selectedStudent = list.first;
        }
      } else {
        selectedStudent = null;
      }
    });

    if (cat == ParentServiceCategory.holisticReport && selectedStudent != null) {
      unawaited(_loadStudentReportData(selectedStudent!.id));
    }
    _syncCustomMessageBuffer();
  }

  Future<void> _loadStudentReportData(
    String studentId, {
    bool force = false,
  }) async {
    if (!force && _reportDataStudentId == studentId) return;
    setState(() {
      _reportDataStudentId = studentId;
      _isLoadingStudentReport = true;
      _studentReportAttendance = [];
      _studentReportExamScores = [];
    });
    _syncCustomMessageBuffer();

    try {
      final attendance = await widget.database.getStudentAttendance(studentId);
      final examScores = await widget.database.getStudentExamScores(studentId);
      if (!mounted || selectedStudent?.id != studentId) return;
      setState(() {
        _studentReportAttendance = attendance;
        _studentReportExamScores = examScores;
        _isLoadingStudentReport = false;
      });
    } catch (_) {
      if (!mounted || selectedStudent?.id != studentId) return;
      setState(() => _isLoadingStudentReport = false);
    }
    _syncCustomMessageBuffer();
  }

  List<StudentModel> get filteredStudents {
    if (_groupMode == GroupSelectionMode.today || _groupMode == GroupSelectionMode.tomorrow) {
      final smartGroups = defaultSmartGroups;
      if (selectedGroupId == 'today_all' || selectedGroupId == 'smart_all') {
        final smartIds = smartGroups.map((g) => g.id).toSet();
        return allStudents.where((s) => smartIds.contains(s.groupId)).toList();
      }
      if (selectedGroupId == null || selectedGroupId == 'all') {
        if (smartGroups.isNotEmpty) {
          final firstId = smartGroups.first.id;
          return allStudents.where((s) => s.groupId == firstId).toList();
        }
        return allStudents;
      }
      return allStudents.where((s) => s.groupId == selectedGroupId).toList();
    } else {
      if (selectedGroupId == null || selectedGroupId == 'all') return allStudents;
      return allStudents.where((s) => s.groupId == selectedGroupId).toList();
    }
  }

  List<StudentModel> get dailyFollowupStudents {
    final absentIds = todayAttendance
        .where((attendance) => attendance.status == 'absent')
        .map((attendance) => attendance.studentId)
        .toSet();
    return allStudents
        .where((student) =>
            absentIds.contains(student.id) || student.outstandingAmount > 0)
        .toList()
      ..sort((a, b) {
        final aAbsent = absentIds.contains(a.id);
        final bAbsent = absentIds.contains(b.id);
        if (aAbsent != bAbsent) return aAbsent ? -1 : 1;
        return b.outstandingAmount.compareTo(a.outstandingAmount);
      });
  }

  bool _hasValidContactPhone(StudentModel student) {
    final parentPhone = WhatsAppService.formatPhone(student.parentPhone);
    final studentPhone = WhatsAppService.formatPhone(student.studentPhone);
    return parentPhone.length >= 7 || studentPhone.length >= 7;
  }

  String _dailyFollowupReason(StudentModel student) {
    final reasons = <String>[];
    if (_attendanceFor(student.id)?.status == 'absent') {
      reasons.add('غياب اليوم');
    }
    if (student.outstandingAmount > 0) {
      reasons.add(
        'رصيد معلّق ${student.outstandingAmount.toStringAsFixed(0)} ج.م',
      );
    }
    return reasons.join(' • ');
  }

  GroupModel? get currentSelectedGroup {
    if (allGroups.isEmpty) return null;
    final smartGroups = defaultSmartGroups;
    if ((_groupMode == GroupSelectionMode.today || _groupMode == GroupSelectionMode.tomorrow) && smartGroups.isNotEmpty) {
      if (selectedGroupId == 'today_all' || selectedGroupId == 'smart_all') return smartGroups.first;
      return smartGroups.firstWhere(
        (g) => g.id == selectedGroupId,
        orElse: () => smartGroups.first,
      );
    }
    if (selectedGroupId == 'all') return allGroups.first;
    return allGroups.firstWhere(
      (g) => g.id == selectedGroupId,
      orElse: () => allGroups.first,
    );
  }

  void _syncCustomMessageBuffer() {
    final msg = _buildCurrentMessage();
    customMessageController.text = msg;
  }

  Future<void> _confirmDailyReportSend() async {
    final students = await widget.database.getStudents();
    if (!mounted) return;
    final eligibleStudents =
        await DailyReportService.instance.getStudentsWithClassesToday(
      database: widget.database,
      allStudents: students,
    );
    if (!mounted) return;
    final eligibleCount = eligibleStudents.length;
    if (eligibleCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد طلاب حضروا حصة مجدولة اليوم لإرسال تقرير لهم.'),
        ),
      );
      return;
    }

    var previewStudent = eligibleStudents.first;
    var previewFuture = DailyReportService.instance.buildStudentDailyReport(
      database: widget.database,
      student: previewStudent,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('معاينة التقرير اليومي'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تقرير مستقل لكل ولي أمر من أولياء أمور $eligibleCount طالبًا سُجل لهم حضور أو غياب في حصة مجدولة اليوم.',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<StudentModel>(
                  key: ValueKey('daily_report_preview_${previewStudent.id}'),
                  initialValue: previewStudent,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'معاينة تقرير الطالب',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  items: eligibleStudents
                      .map((student) => DropdownMenuItem(
                            value: student,
                            child: Text(student.fullName,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (student) {
                    if (student == null) return;
                    setDialogState(() {
                      previewStudent = student;
                      previewFuture = DailyReportService.instance
                          .buildStudentDailyReport(
                        database: widget.database,
                        student: student,
                      );
                    });
                  },
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(dialogContext).size.height * 0.4,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext).brightness ==
                              Brightness.dark
                          ? const Color(0xFF142036)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: FutureBuilder<String>(
                      future: previewFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator.adaptive(),
                          );
                        }
                        if (snapshot.hasError) {
                          return const Text('تعذر تجهيز معاينة التقرير.');
                        }
                        return SingleChildScrollView(
                          child: SelectableText(
                            snapshot.data ?? 'لا توجد بيانات للمعاينة.',
                            style: const TextStyle(fontSize: 12, height: 1.5),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  currentWaMode == 'api'
                      ? 'سيتم الإرسال عبر API بعد تأكيدك.'
                      : 'بعد التأكيد ستُفتح محادثات واتساب بالتتابع حسب إعداد التأخير.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text('تأكيد إرسال $eligibleCount تقريرًا'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final progress = ValueNotifier<(int, int)>((0, eligibleCount));
    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ValueListenableBuilder<(int, int)>(
        valueListenable: progress,
        builder: (context, value, _) {
          final sent = value.$1;
          final total = value.$2;
          return AlertDialog(
            title: const Text('جاري تجهيز التقارير'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تمت معالجة $sent من $total'),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: total == 0 ? null : sent / total,
                  color: const Color(0xFF25D366),
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      final result = await DailyReportService.instance.sendAllDailyReports(
        database: widget.database,
        onProgress: (sent, total) => progress.value = (sent, total),
      );
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'اكتمل الإرسال: ${result['sent']} ناجح، ${result['failed']} فشل، ${result['skipped']} بدون رقم ولي أمر.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال التقارير: $error')),
        );
      }
    } finally {
      await progressDialog;
      progress.dispose();
    }
  }

  AttendanceModel? _attendanceFor(String? studentId) {
    if (studentId == null) return null;
    return todayAttendance
        .where((item) => item.studentId == studentId)
        .firstOrNull;
  }

  PaymentModel? _latestReceiptFor(String? studentId) {
    if (studentId == null) return null;
    final receipts = allPayments
        .where((payment) =>
            payment.studentId == studentId &&
            payment.type != 'مطالبة استحقاق حصة')
        .toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return (b.id ?? 0).compareTo(a.id ?? 0);
      });
    return receipts.firstOrNull;
  }

  String _attendanceLabel(String status) {
    return switch (status) {
      'present' => 'حاضر',
      'late' => 'حاضر متأخر',
      'absent' => 'غائب',
      'excused' => 'غياب بعذر',
      'cancelled_student' => 'الحصة ملغاة من الطالب',
      'cancelled_teacher' => 'الحصة ملغاة من المعلم',
      _ => status,
    };
  }

  String? _sendValidationMessage(StudentModel student) {
    if (isEditingCustomText) return null;
    switch (activeCategory) {
      case ParentServiceCategory.examScore:
        if (selectedExam == null ||
            !selectedExamScores.containsKey(student.id)) {
          return 'لا توجد درجة مسجلة لهذا الطالب في الامتحان المحدد';
        }
      case ParentServiceCategory.absenceAlert:
        if (_attendanceFor(student.id)?.status != 'absent') {
          return 'لا يمكن إرسال إنذار غياب قبل تسجيل غياب الطالب اليوم';
        }
      case ParentServiceCategory.financialReceipt:
        if (isDueReminderMode && student.outstandingAmount <= 0) {
          return 'لا توجد متأخرات مسجلة لهذا الطالب';
        }
        if (!isDueReminderMode && _latestReceiptFor(student.id) == null) {
          return 'لا يوجد إيصال سداد مسجل لهذا الطالب';
        }
      case ParentServiceCategory.notebookBehavior:
        if (behaviorNote.trim().isEmpty) return 'اختر ملاحظة مسجلة قبل الإرسال';
      case ParentServiceCategory.sessionCancellation:
        if (_cancelReasonController.text.trim().isEmpty)
          return 'أدخل سبب إلغاء الحصة قبل الإرسال';
      default:
        return null;
    }
    return null;
  }

  String _buildDailyFollowupMessage(StudentModel student) {
    final group = allGroups
        .where((item) => item.id == student.groupId)
        .toList()
        .firstOrNull;
    final lines = <String>[
      'السلام عليكم ورحمة الله وبركاته 🌸',
      'ولي أمر الطالب/ة ${student.fullName} المحترم،',
      'نود متابعة بعض التفاصيل المسجلة لدى $centerName:',
      'الصف: ${student.grade}',
      if (group != null) 'المجموعة: ${group.name}',
    ];
    if (_attendanceFor(student.id)?.status == 'absent') {
      lines.add('الحضور: تم تسجيل غياب اليوم.');
    }
    if (student.outstandingAmount > 0) {
      lines.add(
        'الرصيد المعلّق: ${student.outstandingAmount.toStringAsFixed(0)} ج.م.',
      );
    }
    lines.add('للاستفسار أو تنسيق المتابعة، يسعدنا تواصلكم معنا.');
    lines.add('مع التحية، $teacherName');

    var message = lines.join('\n');
    if (enableFooter &&
        messageFooter.trim().isNotEmpty &&
        !message.contains(messageFooter.trim())) {
      message = '$message\n\n${messageFooter.trim()}';
    }
    return message;
  }

  void _showDailyFollowupPreview(StudentModel student) {
    final message = _buildDailyFollowupMessage(student);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('معاينة رسالة ${student.fullName}'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          child: SingleChildScrollView(child: SelectableText(message)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _hasValidContactPhone(student)
                ? () {
                    Navigator.pop(dialogContext);
                    _sendToStudent(student, messageOverride: message);
                  }
                : null,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('إرسال لولي الأمر'),
          ),
        ],
      ),
    );
  }

  String _reportPeriodTitle() {
    return switch (_reportPeriod) {
      StudentReportPeriod.session => 'الحصة الأخيرة',
      StudentReportPeriod.weekly => 'أسبوعي • آخر 7 أيام',
      StudentReportPeriod.monthly => 'شهري • ${DateTime.now().month}/${DateTime.now().year}',
    };
  }

  String _buildStudentLevelReport(
    StudentModel student, {
    List<AttendanceModel>? attendanceOverride,
    List<Map<String, dynamic>>? examScoresOverride,
  }) {
    if (attendanceOverride == null && _isLoadingStudentReport) {
      return 'جارٍ تحميل سجلات ${student.fullName} لإعداد التقرير...';
    }

    final rawAttendance = attendanceOverride ?? _studentReportAttendance;
    final rawExamScores = examScoresOverride ?? _studentReportExamScores;

    final group = allGroups
        .where((item) => item.id == student.groupId)
        .toList()
        .firstOrNull;
    final today = DateUtils.dateOnly(DateTime.now());
    final startDate = switch (_reportPeriod) {
      StudentReportPeriod.session => DateTime(1970),
      StudentReportPeriod.weekly => today.subtract(const Duration(days: 6)),
      StudentReportPeriod.monthly => DateTime(today.year, today.month, 1),
    };
    final attendance = rawAttendance.where((record) {
      if (_reportPeriod == StudentReportPeriod.session) return true;
      final date = DateTime.tryParse(record.attendanceDate);
      if (date == null) return false;
      final day = DateUtils.dateOnly(date);
      return !day.isBefore(startDate) && !day.isAfter(today);
    }).toList();
    final examScores = rawExamScores.where((record) {
      if (_reportPeriod == StudentReportPeriod.session) return false;
      final date = DateTime.tryParse(record['date']?.toString() ?? '');
      if (date == null) return false;
      final day = DateUtils.dateOnly(date);
      return !day.isBefore(startDate) && !day.isAfter(today);
    }).toList();

    final isMonthly = _reportPeriod == StudentReportPeriod.monthly;
    final headerTitle = isMonthly
        ? 'تقرير المتابعة والنمو التعليمي والمالي الشهري 📅'
        : 'تقرير مستوى الطالب الأكاديمي والتربوي 📊';

    final lines = <String>[
      headerTitle,
      'السنتر: $centerName | المدرس: $teacherName',
      'الطالب/ة: ${student.fullName} | الصف: ${student.grade}',
      'الفترة: ${_reportPeriodTitle()}',
      if (group != null) 'المجموعة: ${group.name}',
    ];

    if (_reportPeriod == StudentReportPeriod.session) {
      final latest = attendance.firstOrNull;
      final sessionLog = student.groupId == null
          ? null
          : groupLatestLogs[student.groupId];
      if (latest != null) {
        lines.add('تاريخ الحصة المسجل: ${latest.attendanceDate}');
        lines.add('الحضور: ${_attendanceLabel(latest.status)}');
        if (latest.recitationRating?.trim().isNotEmpty == true) {
          lines.add('تقييم التسميع: ${latest.recitationRating}');
        }
        if (latest.recitationScore != null) {
          lines.add(
              'درجة التسميع: ${latest.recitationScore!.toStringAsFixed(0)}');
        }
        if (latest.homeworkStatus?.trim().isNotEmpty == true) {
          lines.add('الواجب: ${latest.homeworkStatus}');
        }
        if (latest.notes?.trim().isNotEmpty == true) {
          lines.add('ملاحظة الحصة: ${latest.notes}');
        }
      }
      if (sessionLog?.lessonTitle.trim().isNotEmpty == true) {
        lines.add('موضوع آخر درس مسجل للمجموعة: ${sessionLog!.lessonTitle}');
      }
      if (sessionLog?.homework.trim().isNotEmpty == true) {
        lines.add('الواجب المسجل للمجموعة: ${sessionLog!.homework}');
      }
      if (latest == null && sessionLog == null) {
        lines.add('لا توجد متابعة مسجلة للحصة حتى الآن.');
      }
    } else {
      final presentCount = attendance
          .where((record) => record.status == 'present' || record.status == 'late')
          .length;
      final absentCount =
          attendance.where((record) => record.status == 'absent').length;
      final excusedCount =
          attendance.where((record) => record.status == 'excused').length;
      final totalSessions = attendance.length;
      final attendanceRate = totalSessions > 0
          ? ((presentCount / totalSessions) * 100).toStringAsFixed(0)
          : '100';

      lines.add(
        '📊 تقرير الحضور: $presentCount حضور | $absentCount غياب | $excusedCount بعذر | نسبة الانضباط: $attendanceRate%',
      );

      final recitationScores = attendance
          .map((record) => record.recitationScore)
          .whereType<double>()
          .toList();
      if (recitationScores.isNotEmpty) {
        final average =
            recitationScores.reduce((a, b) => a + b) / recitationScores.length;
        lines.add('📝 متوسط درجات التسميع: ${average.toStringAsFixed(1)}');
      }

      final homeworkCounts = <String, int>{};
      for (final record in attendance) {
        final status = record.homeworkStatus?.trim() ?? '';
        if (status.isNotEmpty) {
          homeworkCounts.update(status, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      if (homeworkCounts.isNotEmpty) {
        lines.add(
          '📚 متابعة الواجب: ${homeworkCounts.entries.map((entry) => '${entry.key} (${entry.value})').join('، ')}',
        );
      }

      var percentageTotal = 0.0;
      var percentageCount = 0;
      for (final record in examScores) {
        final score = (record['score'] as num?)?.toDouble();
        final maxScore = (record['max_score'] as num?)?.toDouble();
        if (score != null && maxScore != null && maxScore > 0) {
          percentageTotal += score / maxScore * 100;
          percentageCount++;
        }
      }
      if (percentageCount > 0) {
        lines.add(
          '🎯 متوسط الاختبارات المسجلة: ${(percentageTotal / percentageCount).toStringAsFixed(1)}% ($percentageCount اختبار)',
        );
        lines.add('نتائج الاختبارات خلال الفترة:');
        for (final record in examScores.take(4)) {
          lines.add(
            '• ${record['title']}: ${record['score']} من ${record['max_score']} (${record['date']})',
          );
        }
      }
      if (attendance.isEmpty && examScores.isEmpty) {
        lines.add('لا توجد سجلات حضور أو اختبارات مسجلة خلال هذه الفترة.');
      } else {
        // ملخص تقييم التقدم والنمو التعليمي والتقصير
        final hasAbsence = absentCount > 0;
        final hasHwShortcoming = homeworkCounts.keys.any((k) =>
            k.contains('ناقص') || k.contains('لم يسلم') || k.contains('مرفوض') || k.contains('مقصر'));
        final avgRecitation = recitationScores.isNotEmpty
            ? recitationScores.reduce((a, b) => a + b) / recitationScores.length
            : null;

        if (!hasAbsence && !hasHwShortcoming && (avgRecitation == null || avgRecitation >= 8)) {
          lines.add('🌟 تقييم المستوى والنمو: أداء متميز وتطور ملحوظ والتزام كامل بالحضور والواجبات، استمر في التفوق! 👏');
        } else {
          final notes = <String>[];
          if (hasAbsence) notes.add('تسجيل غياب عن $absentCount حصة');
          if (hasHwShortcoming) notes.add('ملاحظات في إتمام الواجبات بدقة');
          if (avgRecitation != null && avgRecitation < 6) notes.add('الحاجة لمزيد من المذاكرة للتسميع');
          lines.add('⚠️ تقرير المتابعة والتوجيه: ${notes.join(' • ')} (نرجو حث الطالب على الانضباط المستمر).');
        }
      }

      // Financial part for Monthly Report ONLY
      if (isMonthly) {
        final currentMonthKey = DateTime.now().toIso8601String().substring(0, 7);
        final studentPaymentsThisMonth = allPayments.where((p) =>
            p.studentId == student.id &&
            p.date.startsWith(currentMonthKey) &&
            p.type != 'مطالبة استحقاق حصة').toList();
        final totalPaidMonth = studentPaymentsThisMonth.fold<double>(0.0, (sum, p) => sum + p.amount);

        lines.add('-----------------------------');
        lines.add('💰 الموقف المالي واشتراك الشهر:');
        if (group != null) {
          final isPerSession = group.billingType == 'per_session';
          final feeLabel = isPerSession ? 'سعر الحصة للمجموعة' : 'اشتراك المجموعة الشهري';
          final feeUnit = isPerSession ? 'ج.م / حصة' : 'ج.م';
          lines.add('• $feeLabel: ${group.monthlyPrice.toStringAsFixed(0)} $feeUnit');
        }
        lines.add('• إجمالي المسدد خلال هذا الشهر: ${totalPaidMonth.toStringAsFixed(0)} ج.م');
        if (student.outstandingAmount > 0) {
          lines.add('• الرصيد المستحق المتبقي: ${student.outstandingAmount.toStringAsFixed(0)} ج.م ⚠️');
          lines.add('• حالة السداد: متبقي مستحق (نرجو التكرم بتسوية المتبقي)');
        } else {
          lines.add('• حالة السداد: خالص السداد بالكامل، شكراً لتعاونكم ✅');
        }
        lines.add('-----------------------------');
        lines.add('📌 هذا التقرير الشهري الشامل معتمد رسمياً من إدارة السنتر للمتابعة الدورية الشاملة.');
      } else {
        // Zero financials guaranteed for session and weekly
        lines.add('📌 هذا التقرير أكاديمي وتربوي معتمد من إدارة السنتر لمتابعة مستوى الطالب (خالٍ تماماً من أي تفاصيل مالية).');
      }
    }

    return lines.join('\n');
  }

  String _buildCurrentMessage({StudentModel? targetStudent}) {
    final st = targetStudent ?? selectedStudent ?? (_studentsForSingleStudentScope.isNotEmpty ? _studentsForSingleStudentScope.first : null);
    final stName = st?.fullName ?? 'الطالب';
    final stGroup = st != null ? allGroups.where((g) => g.id == st.groupId).firstOrNull : null;
    final grp = stGroup ?? currentSelectedGroup;
    final grpName = grp?.name ?? 'المجموعة';
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final log = grp != null ? groupLatestLogs[grp.id] : null;

    String baseMsg;

    switch (activeCategory) {
      case ParentServiceCategory.sessionFollowup:
        final todayLog = log?.date == today ? log : null;
        final attendance = _attendanceFor(st?.id);
        final lesson = todayLog?.lessonTitle.isNotEmpty == true
            ? todayLog!.lessonTitle
            : 'لم يسجل موضوع الدرس';
        final hw =
            todayLog?.homework.isNotEmpty == true ? todayLog!.homework : null;
        final nextTopic =
            todayLog?.nextTopic.isNotEmpty == true ? todayLog!.nextTopic : null;
        baseMsg = WhatsAppService.sessionFollowUpMessage(
          centerName: centerName,
          teacherName: teacherName,
          studentName: stName,
          groupName: grpName,
          date: today,
          lessonTitle: lesson,
          lessonContent: todayLog?.contentCovered,
          homework: hw,
          attendanceStatus:
              attendance == null ? null : _attendanceLabel(attendance.status),
          recitationRating: attendance?.recitationRating,
          homeworkStatus: attendance?.homeworkStatus,
          nextQuiz: nextTopic,
          previousHomeworkReview: todayLog?.previousHomeworkReview,
          previousLessonReview: todayLog?.previousLessonReview,
          customTemplate: sessionReportCustomTemplate.isNotEmpty
              ? sessionReportCustomTemplate
              : null,
        );
        break;

      case ParentServiceCategory.absenceAlert:
        baseMsg = WhatsAppService.absenceMessage(
          centerName: centerName,
          teacherName: teacherName,
          studentName: stName,
          date: today,
        );
        break;

      case ParentServiceCategory.examScore:
        final score = st == null ? null : selectedExamScores[st.id];
        if (selectedExam == null || score == null) {
          baseMsg =
              'لا توجد درجة مسجلة للطالب $stName في الامتحان المحدد حتى الآن.';
          break;
        }
        baseMsg = WhatsAppService.examScoreMessage(
          centerName: centerName,
          studentName: stName,
          examTitle: selectedExam!.title,
          score: score,
          maxScore: selectedExam!.maxScore,
        );
        break;

      case ParentServiceCategory.financialReceipt:
        if (isDueReminderMode) {
          final due = st?.outstandingAmount ?? 0.0;
          if (due <= 0) {
            baseMsg = 'لا توجد متأخرات مالية مسجلة للطالب $stName حالياً.';
            break;
          }
          baseMsg = WhatsAppService.duePaymentMessage(
            centerName: centerName,
            studentName: stName,
            amount: due,
          );
        } else {
          final receipt = _latestReceiptFor(st?.id);
          if (receipt == null) {
            baseMsg = 'لا يوجد إيصال سداد مسجل للطالب $stName حتى الآن.';
            break;
          }
          baseMsg = WhatsAppService.paymentReceiptMessage(
            centerName: centerName,
            studentName: stName,
            amount: receipt.amount,
            type: receipt.type,
            date: receipt.date,
          );
        }
        break;

      case ParentServiceCategory.notebookBehavior:
        baseMsg = '''السلام عليكم ورحمة الله وبركاته 🌸
ولي أمر الطالب المحترم / $stName
نحيطكم علماً بتقرير المتابعة السلوكية والأكاديمية في $centerName:
━━━━━━━━━━━━━━━━━━━━━
المدرس: $teacherName | المجموعة: $grpName
📌 التقرير والملاحظة: $behaviorNote
━━━━━━━━━━━━━━━━━━━━━
شاكرين لكم دعمكم المستمر وتشجيعكم الدائم لأبنائنا الطلاب ✨''';
        break;

      case ParentServiceCategory.holisticReport:
        baseMsg = st == null
            ? 'اختر الطالب لعرض تقرير مستواه.'
            : _buildStudentLevelReport(
                st,
                attendanceOverride: _batchAttendanceCache[st.id],
                examScoresOverride: _batchExamCache[st.id],
              );
        break;

      case ParentServiceCategory.sessionCancellation:
        final reason = _cancelReasonController.text.trim();
        final makeup = _makeupDateController.text.trim();
        if (isTeacherCancellation) {
          baseMsg = WhatsAppService.teacherCancellationMessage(
            centerName: centerName,
            teacherName: teacherName,
            groupName: grpName,
            date: today,
            reason: reason,
            makeupInfo: makeup.isNotEmpty ? makeup : null,
          );
        } else {
          baseMsg = WhatsAppService.studentCancellationMessage(
            centerName: centerName,
            teacherName: teacherName,
            studentName: stName,
            groupName: grpName,
            date: today,
            reason: reason,
            makeupInfo: makeup.isNotEmpty ? makeup : null,
          );
        }
        break;

      case ParentServiceCategory.sessionReminder:
        final bool isTodayMode = _sendScope == WhatsAppSendScope.todayGroups || _groupMode == GroupSelectionMode.today;
        final bool isTomorrowMode = _groupMode == GroupSelectionMode.tomorrow;

        final String dayWord;
        final String titleDay;
        final String dayName;

        if (isTodayMode) {
          dayWord = 'اليوم';
          titleDay = 'اليوم';
          dayName = _getTodayArabicName();
        } else if (isTomorrowMode) {
          dayWord = 'غداً';
          titleDay = 'الغد';
          dayName = _getTomorrowArabicName();
        } else {
          dayWord = 'القادمة';
          titleDay = 'القادمة';
          dayName = grp?.days ?? grp?.schedule ?? '';
        }

        final timeStr = grp?.startTime.isNotEmpty == true ? 'الساعة ${grp!.startTime}' : '';
        final sched = (dayName.isNotEmpty ? '$dayName $timeStr' : timeStr).trim();

        final extraNote = _reminderExtraNoteController.text.trim();
        final extraNoteSection = extraNote.isNotEmpty ? '\n📌 تنبيه: $extraNote' : '';

        baseMsg = '''تذكير بموعد حصة $titleDay 🔔
ولي أمر الطالب المحترم / $stName
نود تذكير سيادتكم بموعد حصة الطالب $dayWord ($sched) في مجموعة ($grpName) بـ $centerName.$extraNoteSection
يرجى الحضور في الموعد ومراجعة الواجبات والتكليفات المطلوبة. بالتوفيق دائماً! 🌸''';
        break;
    }

    if (_recipientTarget == WhatsAppRecipientTarget.student) {
      baseMsg = baseMsg
          .replaceAll('ولي أمر الطالب المحترم / $stName', 'عزيزي الطالب / $stName')
          .replaceAll('ولي أمر الطالب/ة الكريم / $stName', 'عزيزي الطالب / $stName')
          .replaceAll('ولي أمر الطالب الكريم / $stName', 'عزيزي الطالب / $stName')
          .replaceAll('ولي أمر الطالب / $stName', 'عزيزي الطالب / $stName')
          .replaceAll('نود تذكير سيادتكم بموعد حصة الطالب', 'نود تذكيرك بموعد حصتك')
          .replaceAll('أولياء أمور وطلاب مجموعة: $grpName', 'أبطال مجموعة: $grpName')
          .replaceAll('نود إبلاغكم بغياب الطالب عن حضور حصة اليوم', 'نود الاطمئنان عليك لغيابك عن حضور حصة اليوم')
          .replaceAll('نحيطكم علماً بأن هناك مستحقات دراسية متأخرة', 'نود تذكيرك بلطف بوجود مستحقات دراسية متأخرة')
          .replaceAll('يسرنا في $centerName إخطاركم بنتيجة اختبار', 'يسرنا في $centerName إخطارك بنتيجة اختبارك')
          .replaceAll('تم تسجيل حضور الطالب بنجاح', 'تم تسجيل حضورك بنجاح');
    }

    final activeFooter =
        (categoryFooters[activeCategory.name] ?? messageFooter).trim();
    if (enableFooter && activeFooter.isNotEmpty) {
      final normBase = baseMsg.replaceAll('\r\n', '\n');
      final normFooter = activeFooter.replaceAll('\r\n', '\n');
      if (!normBase.contains(normFooter)) {
        return '$normBase\n\n$normFooter';
      }
    }
    return baseMsg;
  }

  Future<void> _sendToStudent(
    StudentModel student, {
    String? messageOverride,
  }) async {
    final validationMessage = messageOverride == null
        ? _sendValidationMessage(student)
        : null;
    if (validationMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(validationMessage)));
      return;
    }

    final parentPhone = WhatsAppService.formatPhone(student.parentPhone);
    final studentPhone = WhatsAppService.formatPhone(student.studentPhone);

    final targets = <({String phone, String type, String label})>[];
    if (_recipientTarget == WhatsAppRecipientTarget.parent) {
      if (student.guardians.isNotEmpty) {
        for (final g in student.guardians) {
          final fmt = WhatsAppService.formatPhone(g.phone);
          if (fmt.length >= 7) {
            targets.add((phone: fmt, type: 'parent', label: '${g.relationship}${g.name.isNotEmpty ? ' (${g.name})' : ''}'));
          }
        }
      } else if (parentPhone.length >= 7) {
        targets.add((phone: parentPhone, type: 'parent', label: 'ولي الأمر'));
      }
      if (targets.isEmpty && studentPhone.length >= 7) {
        targets.add((phone: studentPhone, type: 'student', label: 'الطالب (لعدم توفر هاتف ولي الأمر)'));
      }
    } else if (_recipientTarget == WhatsAppRecipientTarget.student) {
      if (studentPhone.length >= 7) {
        targets.add((phone: studentPhone, type: 'student', label: 'الطالب'));
      } else if (student.guardians.isNotEmpty) {
        for (final g in student.guardians) {
          final fmt = WhatsAppService.formatPhone(g.phone);
          if (fmt.length >= 7) {
            targets.add((phone: fmt, type: 'parent', label: '${g.relationship} (لعدم توفر هاتف الطالب)'));
          }
        }
      } else if (parentPhone.length >= 7) {
        targets.add((phone: parentPhone, type: 'parent', label: 'ولي الأمر (لعدم توفر هاتف الطالب)'));
      }
    } else {
      if (student.guardians.isNotEmpty) {
        for (final g in student.guardians) {
          final fmt = WhatsAppService.formatPhone(g.phone);
          if (fmt.length >= 7) {
            targets.add((phone: fmt, type: 'parent', label: '${g.relationship}${g.name.isNotEmpty ? ' (${g.name})' : ''}'));
          }
        }
      } else if (parentPhone.length >= 7) {
        targets.add((phone: parentPhone, type: 'parent', label: 'ولي الأمر'));
      }
      if (studentPhone.length >= 7 && !targets.any((t) => t.phone == studentPhone)) {
        targets.add((phone: studentPhone, type: 'student', label: 'الطالب'));
      }
    }

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          content: Text(
              'لا يوجد رقم هاتف صالح مسجل لولي الأمر أو للطالب (${student.fullName})',
              overflow: TextOverflow.ellipsis),
        ),
      );
      return;
    }

    // Strict duplicate report prevention against whatsapp_logs
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final currentMonthKey = todayStr.substring(0, 7);
    final weekStart = DateTime.now().subtract(const Duration(days: 6)).toIso8601String().substring(0, 10);

    bool isDuplicate = false;
    String duplicateReason = '';

    if (activeCategory == ParentServiceCategory.sessionFollowup) {
      final sent = await widget.database.isStudentReportSentToday(
        studentId: student.id,
        date: todayStr,
      );
      if (sent) {
        isDuplicate = true;
        duplicateReason = 'تم إرسال تقرير حصة اليوم لولي أمر الطالب (${student.fullName}) مسبقاً ومسجل في السجل بتاريخ ($todayStr).';
      }
    } else if (activeCategory == ParentServiceCategory.holisticReport) {
      if (_reportPeriod == StudentReportPeriod.session) {
        final sent = await widget.database.isStudentReportSentToday(
          studentId: student.id,
          date: todayStr,
        );
        if (sent) {
          isDuplicate = true;
          duplicateReason = 'تم إرسال تقرير الحصة لولي أمر الطالب (${student.fullName}) مسبقاً ومسجل في السجل بتاريخ ($todayStr).';
        }
      } else if (_reportPeriod == StudentReportPeriod.weekly) {
        final sent = await widget.database.isWeeklyReportSentForStudent(
          studentId: student.id,
          weekStartDate: weekStart,
        );
        if (sent) {
          isDuplicate = true;
          duplicateReason = 'تم إرسال التقرير الأسبوعي لولي أمر الطالب (${student.fullName}) مسبقاً ومسجل في السجل لهذا الأسبوع.';
        }
      } else if (_reportPeriod == StudentReportPeriod.monthly) {
        final sent = await widget.database.isMonthlyReportSentForStudent(
          studentId: student.id,
          monthKey: currentMonthKey,
        );
        if (sent) {
          isDuplicate = true;
          duplicateReason = 'تم إرسال التقرير الشهري لولي أمر الطالب (${student.fullName}) مسبقاً ومسجل في السجل لشهر ($currentMonthKey).';
        }
      }
    }

    if (isDuplicate) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.shield_rounded, color: Colors.orange, size: 24),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تم إرسال هذا التقرير لولي الأمر مسبقاً 🛡️',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Text(
                '$duplicateReason\n\nحفاظاً على عدم تكرار الرسائل وإزعاج أولياء الأمور، يمنع النظام إعادة الإرسال.',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('حسناً فهمت', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      }
      return;
    }

    final message = messageOverride ??
      (isEditingCustomText
        ? WhatsAppService.replacePlaceholders(
            customMessageController.text,
            studentName: student.fullName,
            parentName: student.parentName,
            parentPhone: student.parentPhone,
            studentPhone: student.studentPhone,
            groupName: currentSelectedGroup?.name,
            centerName: centerName,
            teacherName: teacherName,
            amount: student.outstandingAmount.toStringAsFixed(0),
            date: DateTime.now().toIso8601String().substring(0, 10),
          )
        : _buildCurrentMessage(targetStudent: student));

    for (final t in targets) {
      final res = await WhatsAppService.dispatchMessageDetailed(
        database: widget.database,
        phone: t.phone,
        message: message,
        studentId: student.id,
        studentName: student.fullName,
        recipientType: t.type,
        category: activeCategory.name,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (res.success) {
          if (res.sentViaApi) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
                content: Row(
                  children: [
                    const Icon(Icons.cloud_done_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            'تم إرسال الرسالة آلياً عبر API لـ ${student.fullName} (${t.label}) بنجاح ✅',
                            overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF25D366),
                behavior: SnackBarBehavior.floating,
                content: Text(
                    'تم فتح محادثة واتساب لـ ${student.fullName} (${t.label}) بنجاح ✅',
                    overflow: TextOverflow.ellipsis),
              ),
            );
          }
        } else {
          if (res.sentViaApi) {
            showDialog(
              context: context,
              builder: (ctx) => Directionality(
                textDirection: TextDirection.rtl,
                child: AlertDialog(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Colors.red.shade700),
                  ),
                  title: const Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('فشل الإرسال عبر API',
                          style: TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        res.errorMessage ??
                            'تعذر إتمام الإرسال عبر خادم الـ API.',
                        style: const TextStyle(
                            color: Color(0xFFFCA5A5), fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'يمكنك إرسال الرسالة الآن بفتح تطبيق واتساب يدوياً، أو فحص بيانات الـ API في الإعدادات.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء',
                          style: TextStyle(color: Colors.grey)),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF38BDF8)),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SettingsScreen(
                                database: widget.database, initialTab: 2),
                          ),
                        );
                        _loadAllData();
                      },
                      icon: const Icon(Icons.settings, size: 16),
                      label: const Text('فحص الـ API'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        WhatsAppService.openWhatsApp(
                          phone: t.phone,
                          message: message,
                          database: widget.database,
                          studentId: student.id,
                          studentName: student.fullName,
                          recipientType: t.type,
                          category: activeCategory.name,
                        );
                      },
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('فتح يدوياً'),
                    ),
                  ],
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                content: Text(
                    'تعذر فتح تطبيق واتساب. يرجى التأكد من تثبيت واتساب على هاتفك أو التحقق من صحة الرقم.',
                    overflow: TextOverflow.ellipsis),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _showBatchSendDialog() async {
    final targets = currentScopeStudents;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _sendScope == WhatsAppSendScope.todayGroups
                ? 'لا يوجد طلاب في مجاميع اليوم المجدولة للإرسال'
                : (_sendScope == WhatsAppSendScope.customGroups
                    ? 'يرجى تحديد مجموعة واحدة على الأقل من قائمة المجموعات المخصصة'
                    : 'لا يوجد طلاب في هذه المجموعة للإرسال الجماعي'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      return;
    }

    var effectiveBatchTargets = List<StudentModel>.from(targets);
    if (activeCategory == ParentServiceCategory.sessionFollowup ||
        activeCategory == ParentServiceCategory.holisticReport) {
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final currentMonthKey = todayStr.substring(0, 7);
      final weekStart = DateTime.now().subtract(const Duration(days: 6)).toIso8601String().substring(0, 10);

      final unsent = <StudentModel>[];
      for (final s in targets) {
        bool alreadySent = false;
        if (activeCategory == ParentServiceCategory.sessionFollowup) {
          alreadySent = await widget.database.isStudentReportSentToday(
            studentId: s.id,
            date: todayStr,
          );
        } else if (activeCategory == ParentServiceCategory.holisticReport) {
          if (_reportPeriod == StudentReportPeriod.session) {
            alreadySent = await widget.database.isStudentReportSentToday(
              studentId: s.id,
              date: todayStr,
            );
          } else if (_reportPeriod == StudentReportPeriod.weekly) {
            alreadySent = await widget.database.isWeeklyReportSentForStudent(
              studentId: s.id,
              weekStartDate: weekStart,
            );
          } else if (_reportPeriod == StudentReportPeriod.monthly) {
            alreadySent = await widget.database.isMonthlyReportSentForStudent(
              studentId: s.id,
              monthKey: currentMonthKey,
            );
          }
        }
        if (!alreadySent) {
          unsent.add(s);
        }
      }

      if (unsent.isEmpty) {
        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Row(
                  children: [
                    Icon(Icons.shield_rounded, color: Colors.orange, size: 24),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم إرسال هذا التقرير مسبقاً 🛡️',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                content: const Text(
                  'تم إرسال هذا التقرير لكافة طلاب هذه المجموعة مسبقاً ومسجل في السجل.\nيمنع النظام إعادة الإرسال المكرر منعاً للإزعاج.',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('حسناً فهمت', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        }
        return;
      }

      if (unsent.length < targets.length) {
        final skipped = targets.length - unsent.length;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم استبعاد ($skipped) طالب تم إرسال التقرير لهم مسبقاً 🛡️'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        effectiveBatchTargets = unsent;
      }
    }

    if (currentWaMode == 'manual') {
      _showManualBatchWizard(effectiveBatchTargets);
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.cloud_upload_rounded, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'إرسال آلي جماعي عبر API',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'سيتم إرسال الرسالة آلياً في الخلفية مع فواصل أمان ضد الحظر لـ (${effectiveBatchTargets.length} طالب):'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10)),
                child: Text('نطاق الإرسال: $currentScopeDescription',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Text('القسم: ${_getCategoryTitle(activeCategory)}',
                  style: const TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981)),
              icon: const Icon(Icons.send, color: Colors.white, size: 18),
              label: const Text('بدء الإرسال الآلي',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(ctx);
                _sendBatchSequentially(effectiveBatchTargets);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showManualBatchWizard(List<StudentModel> targets) async {
    if (targets.isEmpty) return;

    if (activeCategory == ParentServiceCategory.holisticReport) {
      for (final st in targets) {
        if (!_batchAttendanceCache.containsKey(st.id)) {
          _batchAttendanceCache[st.id] =
              await widget.database.getStudentAttendance(st.id);
          _batchExamCache[st.id] =
              await widget.database.getStudentExamScores(st.id);
        }
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        int currentIndex = 0;
        bool hasSentCurrent = false;

        return StatefulBuilder(
          builder: (context, setWizardState) {
            final currentStudent = targets[currentIndex];
            final parentPhone = WhatsAppService.formatPhone(currentStudent.parentPhone);
            final studentPhone = WhatsAppService.formatPhone(currentStudent.studentPhone);
            final isParent = _recipientTarget == WhatsAppRecipientTarget.parent;
            final isStudent = _recipientTarget == WhatsAppRecipientTarget.student;

            final effectivePhone = isStudent
                ? (studentPhone.length >= 7 ? studentPhone : parentPhone)
                : (parentPhone.length >= 7 ? parentPhone : studentPhone);
            final recipientLabel = isStudent ? 'الطالب' : (isParent ? 'ولي الأمر' : 'ولي الأمر / الطالب');

            final stGroup = allGroups.where((g) => g.id == currentStudent.groupId).firstOrNull;
            final message = isEditingCustomText
                ? WhatsAppService.replacePlaceholders(
                    customMessageController.text,
                    studentName: currentStudent.fullName,
                    parentName: currentStudent.parentName,
                    parentPhone: currentStudent.parentPhone,
                    studentPhone: currentStudent.studentPhone,
                    groupName: stGroup?.name ?? currentSelectedGroup?.name,
                    centerName: centerName,
                    teacherName: teacherName,
                    amount: currentStudent.outstandingAmount.toStringAsFixed(0),
                    date: DateTime.now().toIso8601String().substring(0, 10),
                  )
                : _buildCurrentMessage(targetStudent: currentStudent);

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    const Icon(Icons.send_to_mobile_rounded, color: Color(0xFF25D366)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'إرسال يدوي جماعي (${currentIndex + 1} من ${targets.length})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: (currentIndex + 1) / targets.length,
                        backgroundColor: Colors.grey.shade200,
                        color: const Color(0xFF25D366),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person, size: 18, color: Color(0xFF047857)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    currentStudent.fullName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '📞 $effectivePhone ($recipientLabel)',
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'معاينة الرسالة المجهزة لهذا الطالب:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          message,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, height: 1.4, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('إنهاء الإرسال', style: TextStyle(color: Colors.grey)),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      if (currentIndex < targets.length - 1) {
                        setWizardState(() {
                          currentIndex++;
                          hasSentCurrent = false;
                        });
                      } else {
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text('اكتملت قائمة الإرسال الجماعي بنجاح 🎉'),
                          ),
                        );
                      }
                    },
                    child: const Text('تخطي ⏭️'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                    icon: Icon(hasSentCurrent ? Icons.arrow_forward_rounded : Icons.open_in_new_rounded, size: 16),
                    label: Text(hasSentCurrent ? 'التالي ➡️' : 'فتح واتساب 📲'),
                    onPressed: () async {
                      if (!hasSentCurrent) {
                        await WhatsAppService.openWhatsApp(
                          phone: effectivePhone,
                          message: message,
                          database: widget.database,
                          studentId: currentStudent.id,
                          studentName: currentStudent.fullName,
                          recipientType: isStudent ? 'student' : 'parent',
                          category: activeCategory.name,
                        );
                        setWizardState(() {
                          hasSentCurrent = true;
                        });
                      } else {
                        if (currentIndex < targets.length - 1) {
                          setWizardState(() {
                            currentIndex++;
                            hasSentCurrent = false;
                          });
                        } else {
                          Navigator.pop(dialogCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              behavior: SnackBarBehavior.floating,
                              content: Text('اكتملت قائمة الإرسال الجماعي بنجاح 🎉'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendBatchSequentially(List<StudentModel> students) async {
    if (activeCategory == ParentServiceCategory.holisticReport) {
      for (final st in students) {
        if (!_batchAttendanceCache.containsKey(st.id)) {
          _batchAttendanceCache[st.id] =
              await widget.database.getStudentAttendance(st.id);
          _batchExamCache[st.id] =
              await widget.database.getStudentExamScores(st.id);
        }
      }
    }
    final delaySetting = await widget.database
        .getSetting('whatsapp_send_delay_seconds', defaultValue: '5');
    final baseDelaySec = int.tryParse(delaySetting) ?? 5;
    for (int i = 0; i < students.length; i++) {
      final s = students[i];
      await _sendToStudent(s);
      // Wait between launches according to user's anti-ban delay setting
      if (i < students.length - 1) {
        await Future.delayed(Duration(seconds: baseDelaySec));
      }
    }
  }

  Future<void> _showSentHistorySheet() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Set<int> sheetSelectedIds = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: widget.database.getWhatsAppLogs(limit: 100),
            builder: (context, snapshot) {
              final logs = snapshot.data ?? [];
              final isLoadingLogs = snapshot.connectionState == ConnectionState.waiting;

              return Directionality(
                textDirection: TextDirection.rtl,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.75,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      if (sheetSelectedIds.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Color(0xFFEF4444), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'تم تحديد ${sheetSelectedIds.length} رسالة',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                  onPressed: () {
                                    setSheetState(() {
                                      if (sheetSelectedIds.length == logs.length) {
                                        sheetSelectedIds.clear();
                                      } else {
                                        for (final l in logs) {
                                          final id = (l['id'] as num?)?.toInt();
                                          if (id != null) sheetSelectedIds.add(id);
                                        }
                                      }
                                    });
                                  },
                                  child: Text(
                                    sheetSelectedIds.length == logs.length ? 'إلغاء الكل' : 'تحديد الكل',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFEF4444),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.delete_rounded, size: 15, color: Colors.white),
                                  label: const Text('حذف المحدد', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                  onPressed: () async {
                                    final count = sheetSelectedIds.length;
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('حذف الرسائل المحددة'),
                                        content: Text('هل أنت متأكد من حذف ($count) رسالة محددة من السجل؟'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                            onPressed: () => Navigator.pop(c, true),
                                            child: const Text('حذف'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await widget.database.deleteWhatsAppLogsByIds(sheetSelectedIds.toList());
                                      setSheetState(() => sheetSelectedIds.clear());
                                      setState(() {});
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('تم حذف ($count) رسالة محددة من السجل 🗑️'),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'إلغاء التحديد',
                                  onPressed: () => setSheetState(() => sheetSelectedIds.clear()),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            children: [
                              const Icon(Icons.history_rounded, color: Color(0xFF25D366)),
                              const SizedBox(width: 8),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'سجل الرسائل المرسلة',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'اضغط مطولاً على أي رسالة لتحديدها وحذفها',
                                    style: TextStyle(fontSize: 10.5, color: Colors.grey),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              if (logs.isNotEmpty) ...[
                                IconButton(
                                  tooltip: 'تحديد رسائل للحذف',
                                  icon: const Icon(Icons.checklist_rounded, color: Color(0xFF0284C7)),
                                  onPressed: () {
                                    setSheetState(() {
                                      for (final l in logs) {
                                        final id = (l['id'] as num?)?.toInt();
                                        if (id != null) sheetSelectedIds.add(id);
                                      }
                                    });
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const Divider(height: 1),
                      Expanded(
                        child: isLoadingLogs
                            ? const Center(child: CircularProgressIndicator())
                            : logs.isEmpty
                                ? const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                                        SizedBox(height: 12),
                                        Text('لا توجد رسائل مسجلة في السجل حتى الآن', style: TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: logs.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final item = logs[index];
                                      final itemId = (item['id'] as num?)?.toInt();
                                      final isSelected = itemId != null && sheetSelectedIds.contains(itemId);
                                      final studentName = item['student_name'] as String? ?? 'غير محدد';
                                      final phone = item['phone'] as String? ?? '';
                                      final msg = item['message'] as String? ?? '';
                                      final status = item['status'] as String? ?? '';
                                      final sentAt = (item['sent_at'] as String? ?? '').replaceFirst('T', ' ').split('.').first;
                                      final recipientType = item['recipient_type'] as String? ?? 'parent';
                                      final isApi = status == 'sent_api';
                                      final isSuccess = status == 'sent_manual' || isApi;
                                      final isSkipped = status == 'skipped';

                                      Color statusColor = isSuccess
                                          ? (isApi ? const Color(0xFF10B981) : const Color(0xFF25D366))
                                          : (isSkipped ? Colors.orange : Colors.red);
                                      String statusLabel = isApi
                                          ? 'API آلي'
                                          : (status == 'sent_manual'
                                              ? 'تطبيق يدوي'
                                              : (isSkipped ? 'تخطي' : 'فشل'));

                                      return InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onLongPress: () {
                                          HapticFeedback.heavyImpact();
                                          if (itemId != null) {
                                            setSheetState(() {
                                              if (sheetSelectedIds.contains(itemId)) {
                                                sheetSelectedIds.remove(itemId);
                                              } else {
                                                sheetSelectedIds.add(itemId);
                                              }
                                            });
                                          }
                                        },
                                        onTap: sheetSelectedIds.isNotEmpty
                                            ? () {
                                                HapticFeedback.selectionClick();
                                                if (itemId != null) {
                                                  setSheetState(() {
                                                    if (sheetSelectedIds.contains(itemId)) {
                                                      sheetSelectedIds.remove(itemId);
                                                    } else {
                                                      sheetSelectedIds.add(itemId);
                                                    }
                                                  });
                                                }
                                              }
                                            : null,
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFFEF4444).withValues(alpha: isDark ? 0.22 : 0.08)
                                                : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade50),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFFEF4444)
                                                  : (isDark ? const Color(0xFF334155) : Colors.grey.shade200),
                                              width: isSelected ? 1.8 : 1,
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (sheetSelectedIds.isNotEmpty && itemId != null) ...[
                                                Checkbox(
                                                  value: isSelected,
                                                  activeColor: const Color(0xFFEF4444),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  visualDensity: VisualDensity.compact,
                                                  onChanged: (val) {
                                                    setSheetState(() {
                                                      if (val == true) {
                                                        sheetSelectedIds.add(itemId);
                                                      } else {
                                                        sheetSelectedIds.remove(itemId);
                                                      }
                                                    });
                                                  },
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            '$studentName (${recipientType == "student" ? "الطالب" : "ولي الأمر"})',
                                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                          ),
                                                        ),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: statusColor.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            statusLabel,
                                                            style: TextStyle(
                                                              color: statusColor,
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                        if (itemId != null && sheetSelectedIds.isEmpty) ...[
                                                          const SizedBox(width: 4),
                                                          IconButton(
                                                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                                            padding: EdgeInsets.zero,
                                                            constraints: const BoxConstraints(),
                                                            tooltip: 'حذف هذه الرسالة',
                                                            onPressed: () async {
                                                              final confirm = await showDialog<bool>(
                                                                context: context,
                                                                builder: (c) => AlertDialog(
                                                                  title: const Text('حذف الرسالة'),
                                                                  content: const Text('هل أنت متأكد من حذف هذه الرسالة من السجل؟'),
                                                                  actions: [
                                                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                                                                    ElevatedButton(
                                                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                                      onPressed: () => Navigator.pop(c, true),
                                                                      child: const Text('حذف'),
                                                                    ),
                                                                  ],
                                                                ),
                                                              );
                                                              if (confirm == true) {
                                                                await widget.database.deleteWhatsAppLog(itemId);
                                                                setSheetState(() {});
                                                                setState(() {});
                                                                if (mounted) {
                                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                                    const SnackBar(
                                                                      content: Text('تم حذف الرسالة بنجاح 🗑️'),
                                                                      duration: Duration(seconds: 2),
                                                                    ),
                                                                  );
                                                                }
                                                              }
                                                            },
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '📞 $phone  •  🕒 $sentAt',
                                                      style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Container(
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: isDark ? Colors.black26 : Colors.white,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        msg,
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(fontSize: 11, height: 1.4),
                                                      ),
                                                    ),
                                                    if (item['error_message'] != null && (item['error_message'] as String).isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '⚠️ ${item["error_message"]}',
                                                        style: const TextStyle(fontSize: 10, color: Colors.redAccent),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _getCategoryTitle(ParentServiceCategory cat) {
    switch (cat) {
      case ParentServiceCategory.sessionFollowup:
        return 'متابعة الحصة والواجب';
      case ParentServiceCategory.absenceAlert:
        return 'إنذار غياب فوري';
      case ParentServiceCategory.examScore:
        return 'بطاقة درجات الامتحان';
      case ParentServiceCategory.financialReceipt:
        return 'سداد ومطالبة مالية';
      case ParentServiceCategory.notebookBehavior:
        return 'تقرير سلوكي وتسميع';
      case ParentServiceCategory.holisticReport:
        return 'التقرير الشهري الشامل';
      case ParentServiceCategory.sessionCancellation:
        return 'إلغاء حصة وموعد بديل';
      case ParentServiceCategory.sessionReminder:
        return 'تذكير بموعد الحصة';
    }
  }

  IconData _getCategoryIcon(ParentServiceCategory cat) {
    switch (cat) {
      case ParentServiceCategory.sessionFollowup:
        return Icons.auto_stories_rounded;
      case ParentServiceCategory.absenceAlert:
        return Icons.person_off_rounded;
      case ParentServiceCategory.examScore:
        return Icons.military_tech_rounded;
      case ParentServiceCategory.financialReceipt:
        return Icons.receipt_long_rounded;
      case ParentServiceCategory.notebookBehavior:
        return Icons.rate_review_rounded;
      case ParentServiceCategory.holisticReport:
        return Icons.analytics_rounded;
      case ParentServiceCategory.sessionCancellation:
        return Icons.event_busy_rounded;
      case ParentServiceCategory.sessionReminder:
        return Icons.alarm_rounded;
    }
  }

  Color _getCategoryColor(ParentServiceCategory cat) {
    switch (cat) {
      case ParentServiceCategory.sessionFollowup:
        return const Color(0xFF3B82F6);
      case ParentServiceCategory.absenceAlert:
        return const Color(0xFFEF4444);
      case ParentServiceCategory.examScore:
        return const Color(0xFFF59E0B);
      case ParentServiceCategory.financialReceipt:
        return const Color(0xFF10B981);
      case ParentServiceCategory.notebookBehavior:
        return const Color(0xFF8B5CF6);
      case ParentServiceCategory.holisticReport:
        return const Color(0xFF6366F1);
      case ParentServiceCategory.sessionCancellation:
        return const Color(0xFFF43F5E);
      case ParentServiceCategory.sessionReminder:
        return const Color(0xFF06B6D4);
    }
  }

  String _getCategorySubtitle(ParentServiceCategory cat) {
    switch (cat) {
      case ParentServiceCategory.sessionFollowup:
        return 'شرح الحصة والواجبات المنزلية';
      case ParentServiceCategory.absenceAlert:
        return 'إنذار فوري بعدم الحضور';
      case ParentServiceCategory.examScore:
        return 'درجات الاختبار والتقييم النهائي';
      case ParentServiceCategory.financialReceipt:
        return 'إيصال سداد ومطالبة بالمصروفات';
      case ParentServiceCategory.notebookBehavior:
        return 'التسميع والسلوك والملاحظات';
      case ParentServiceCategory.holisticReport:
        return 'تقرير أداء شهري تفصيلي متكامل';
      case ParentServiceCategory.sessionCancellation:
        return 'اعتذار عن حصة وتحديد الموعد البديل';
      case ParentServiceCategory.sessionReminder:
        return 'تذكير بموعد وتوقيت الحصة القادمة';
    }
  }

  ServiceDomain _getCategoryDomain(ParentServiceCategory cat) {
    switch (cat) {
      case ParentServiceCategory.sessionFollowup:
      case ParentServiceCategory.examScore:
      case ParentServiceCategory.holisticReport:
        return ServiceDomain.academic;
      case ParentServiceCategory.absenceAlert:
      case ParentServiceCategory.sessionReminder:
      case ParentServiceCategory.sessionCancellation:
        return ServiceDomain.attendance;
      case ParentServiceCategory.financialReceipt:
      case ParentServiceCategory.notebookBehavior:
        return ServiceDomain.financial;
    }
  }

  Future<void> _showCustomFootersDialog() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    var selectedCat = activeCategory.name;
    final textController = TextEditingController(
      text: categoryFooters[selectedCat] ?? messageFooter,
    );

    final catLabels = {
      ParentServiceCategory.sessionFollowup.name: 'تقرير متابعة الحصة 📝',
      ParentServiceCategory.holisticReport.name: 'التقرير الأسبوعي الشامل 📊',
      ParentServiceCategory.absenceAlert.name: 'إنذار وتنبيه الغياب 🚨',
      ParentServiceCategory.notebookBehavior.name: 'الكشكول والملاحظات السلوكية 📓',
      ParentServiceCategory.sessionReminder.name: 'تذكير بموعد الحصة 🔔',
      ParentServiceCategory.examScore.name: 'نتيجة الاختبار 🎯',
      ParentServiceCategory.sessionCancellation.name: 'إلغاء أو اعتذار عن حصة 🚫',
      'general': 'التذييل العام التلقائي (افتراضي) 🏷️',
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.draw_rounded, color: Color(0xFF25D366), size: 22),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تخصيص تذييل الرسائل لكل خدمة ✍️',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'يمكنك تحديد تذييل وتوقيع مختلف لكل نوع رسالة يتم إرسالها لولي الأمر',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('اختر نوع الرسالة لتعديل تذييلها:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCat,
                          isExpanded: true,
                          items: catLabels.entries.map((e) {
                            return DropdownMenuItem<String>(
                              value: e.key,
                              child: Text(e.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            );
                          }).toList(),
                          onChanged: (newCat) async {
                            if (newCat == null) return;
                            final currentSaved = await widget.database.getCategoryFooter(newCat);
                            setSheetState(() {
                              selectedCat = newCat;
                              textController.text = currentSaved;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('نص التذييل (يظهر في أسفل رسالة هذا النوع):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: textController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'مثال:\n---\n📍 السنتر: أ/ أحمد ...\n📞 للتواصل والاستفسار: ...',
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('استعادة الافتراضي'),
                          onPressed: () async {
                            final phone = await widget.database.getSetting('phone', defaultValue: '');
                            final name = centerName.isNotEmpty ? centerName : teacherName;
                            final pPart = phone.isNotEmpty ? '\n📞 للتواصل والاستفسار: $phone' : '';
                            final smartDefault = switch (selectedCat) {
                              'sessionFollowup' => '---\n📍 إدارة المتابعة اليومية | $name$pPart',
                              'holisticReport' => '---\n📊 تقرير المتابعة الدورية الشامل | $name$pPart',
                              'absenceAlert' => '---\n🚨 قسم شؤون الطلاب والانضباط | $name$pPart',
                              'notebookBehavior' => '---\n📓 المتابعة التربوية والسلوكية | $name$pPart',
                              _ => '---\n📍 $name$pPart',
                            };
                            setSheetState(() {
                              textController.text = smartDefault;
                            });
                          },
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          icon: const Icon(Icons.save_rounded, size: 18, color: Colors.white),
                          label: const Text('حفظ التذييل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          onPressed: () async {
                            final newText = textController.text.trim();
                            await widget.database.setCategoryFooter(selectedCat, newText);
                            if (selectedCat == 'general') {
                              await widget.database.setSetting('whatsapp_message_footer', newText);
                            }
                            categoryFooters[selectedCat] = newText;
                            if (mounted) {
                              setState(() {
                                if (selectedCat == activeCategory.name) {
                                  _syncCustomMessageBuffer();
                                }
                              });
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFF10B981),
                                  behavior: SnackBarBehavior.floating,
                                  content: Text('تم حفظ تذييل "${catLabels[selectedCat]}" بنجاح ✅'),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _startWeeklyReportBulkDispatch() async {
    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 6)).toIso8601String().substring(0, 10);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('جارٍ فحص سجل الرسائل وتحديد الطلاب...'),
              ],
            ),
          ),
        ),
      ),
    );

    final groupStudents = filteredStudents;
    final allCenterStudents = allStudents;
    final sendToAllCenter = selectedGroupId == null || selectedGroupId == 'all' || selectedGroupId == 'today_all';
    final candidates = sendToAllCenter ? allCenterStudents : groupStudents;

    final alreadySentStudentIds = <String>{};
    for (final s in candidates) {
      final wasSent = await widget.database.isWeeklyReportSentForStudent(
        studentId: s.id,
        weekStartDate: weekStart,
      );
      if (wasSent) {
        alreadySentStudentIds.add(s.id);
      }
    }

    if (mounted) Navigator.pop(context);
    if (!mounted) return;

    bool skipAlreadySent = true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final effectiveTargets = candidates.where((s) {
            final hasPhone = (s.parentPhone.trim().isNotEmpty || s.studentPhone.trim().isNotEmpty);
            if (!hasPhone) return false;
            if (skipAlreadySent && alreadySentStudentIds.contains(s.id)) return false;
            return true;
          }).toList();

          final alreadySentCount = candidates.where((s) => alreadySentStudentIds.contains(s.id)).length;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.assessment_rounded, color: Color(0xFF0284C7), size: 24),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'إرسال التقرير الأسبوعي الشامل 📊',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'تقرير أكاديمي وتربوي دقيق لكل طالب بدون أي تفاصيل مالية',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  'إجمالي الطلاب المستهدفين:',
                                  style: TextStyle(fontSize: 12.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${candidates.length} طالب', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  'تم إرسال التقرير لهم هذا الأسبوع:',
                                  style: TextStyle(fontSize: 12.5, color: Colors.green),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('$alreadySentCount طالب (تلقائياً مستبعدين)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  'المتبقي للتجهيز والإرسال:',
                                  style: TextStyle(fontSize: 12.5, color: Color(0xFF0284C7)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${effectiveTargets.length} طالب', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تخطي من استلم التقرير مسبقاً هذا الأسبوع 🛡️',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('فحص سجل الرسائل وتجاهل من أُرسل له مسبقاً لمنع التكرار',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      value: skipAlreadySent,
                      onChanged: (val) => setSheetState(() => skipAlreadySent = val),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 20),
                        label: Text(
                          'بدء الإرسال (${effectiveTargets.length} طالب) 🚀',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        onPressed: effectiveTargets.isEmpty
                            ? null
                            : () async {
                                Navigator.pop(sheetCtx);
                                for (final st in effectiveTargets) {
                                  if (!_batchAttendanceCache.containsKey(st.id)) {
                                    _batchAttendanceCache[st.id] = await widget.database.getStudentAttendance(st.id);
                                    _batchExamCache[st.id] = await widget.database.getStudentExamScores(st.id);
                                  }
                                }
                                if (currentWaMode == 'manual') {
                                  _showManualBatchWizard(effectiveTargets);
                                } else {
                                  _sendBatchSequentially(effectiveTargets);
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _startMonthlyReportBulkDispatch() async {
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('جارٍ فحص سجل الرسائل وتجهيز التقرير الشهري...'),
              ],
            ),
          ),
        ),
      ),
    );

    final groupStudents = filteredStudents;
    final allCenterStudents = allStudents;
    final sendToAllCenter = selectedGroupId == null || selectedGroupId == 'all' || selectedGroupId == 'today_all';
    final candidates = sendToAllCenter ? allCenterStudents : groupStudents;

    final alreadySentStudentIds = <String>{};
    for (final s in candidates) {
      final wasSent = await widget.database.isMonthlyReportSentForStudent(
        studentId: s.id,
        monthKey: monthKey,
      );
      if (wasSent) {
        alreadySentStudentIds.add(s.id);
      }
    }

    if (mounted) Navigator.pop(context);
    if (!mounted) return;

    bool skipAlreadySent = true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final effectiveTargets = candidates.where((s) {
            final hasPhone = (s.parentPhone.trim().isNotEmpty || s.studentPhone.trim().isNotEmpty);
            if (!hasPhone) return false;
            if (skipAlreadySent && alreadySentStudentIds.contains(s.id)) return false;
            return true;
          }).toList();

          final alreadySentCount = candidates.where((s) => alreadySentStudentIds.contains(s.id)).length;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.date_range_rounded, color: Color(0xFF8B5CF6), size: 24),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'إرسال التقرير الشهري الشامل (التعليمي والمالي) 📅',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'ملخص شامل لنمو الطالب التعليمي وموقفه المالي لشهر الحالي، مع فحص السجل لمنع أي تكرار.',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  'إجمالي الطلاب المستهدفين:',
                                  style: TextStyle(fontSize: 12.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${candidates.length} طالب', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  'تم إرسال التقرير لهم هذا الشهر:',
                                  style: TextStyle(fontSize: 12.5, color: Colors.green),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('$alreadySentCount طالب (تلقائياً مستبعدين 🛡️)', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  'المتبقي للتجهيز والإرسال:',
                                  style: TextStyle(fontSize: 12.5, color: Color(0xFF8B5CF6)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${effectiveTargets.length} طالب', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('منع الإرسال المكرر لمن استلم التقرير مسبقاً 🛡️',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('مراجعة السجل وتجاهل من أُرسل له هذا الشهر تلقائياً',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      value: skipAlreadySent,
                      onChanged: (val) => setSheetState(() => skipAlreadySent = val),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 20),
                        label: Text(
                          'بدء الإرسال الشهري (${effectiveTargets.length} طالب) 🚀',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        onPressed: effectiveTargets.isEmpty
                            ? null
                            : () async {
                                Navigator.pop(sheetCtx);
                                setState(() {
                                  _reportPeriod = StudentReportPeriod.monthly;
                                  activeCategory = ParentServiceCategory.holisticReport;
                                });
                                for (final st in effectiveTargets) {
                                  if (!_batchAttendanceCache.containsKey(st.id)) {
                                    _batchAttendanceCache[st.id] = await widget.database.getStudentAttendance(st.id);
                                    _batchExamCache[st.id] = await widget.database.getStudentExamScores(st.id);
                                  }
                                }
                                if (currentWaMode == 'manual') {
                                  _showManualBatchWizard(effectiveTargets);
                                } else {
                                  _sendBatchSequentially(effectiveTargets);
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showReportSchedulingConfigDialog() async {
    final mHourStr = await widget.database.getSetting('monthly_report_hour', defaultValue: '21');
    final mMinStr = await widget.database.getSetting('monthly_report_minute', defaultValue: '0');
    final dHourStr = await widget.database.getSetting('daily_report_evening_hour', defaultValue: '21');
    final dMinStr = await widget.database.getSetting('daily_report_evening_minute', defaultValue: '0');
    final wHourStr = await widget.database.getSetting('weekly_report_hour', defaultValue: '20');
    final wMinStr = await widget.database.getSetting('weekly_report_minute', defaultValue: '0');
    final sTargetStr = await widget.database.getSetting('session_reminder_target', defaultValue: 'today');
    final sHourStr = await widget.database.getSetting('session_reminder_hour', defaultValue: '9');
    final sMinStr = await widget.database.getSetting('session_reminder_minute', defaultValue: '0');

    int monthlyHour = int.tryParse(mHourStr) ?? 21;
    int monthlyMin = int.tryParse(mMinStr) ?? 0;
    int dailyHour = int.tryParse(dHourStr) ?? 21;
    int dailyMin = int.tryParse(dMinStr) ?? 0;
    int weeklyHour = int.tryParse(wHourStr) ?? 20;
    int weeklyMin = int.tryParse(wMinStr) ?? 0;
    String sessionReminderTarget = sTargetStr;
    int sessionReminderHour = int.tryParse(sHourStr) ?? 9;
    int sessionReminderMin = int.tryParse(sMinStr) ?? 0;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String formatTime(int h, int m) {
              final period = h >= 12 ? 'م' : 'ص';
              final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
              final displayM = m.toString().padLeft(2, '0');
              return '$displayH:$displayM $period';
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: Color(0xFF7C3AED)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'مواعيد وساعات إرسال التقارير والتذكيرات ⏰',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'حدد ساعة وتوقيت إرسال وتذكير كل نوع من التقارير ليقوم النظام بجدولتها ومراجعتها مع السجل تلقائياً:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),

                      // Session reminder schedule
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                        ),
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('تذكير بموعد الحصة 🔔', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        Text('تنبيه الطلاب وأولياء الأمور بموعد الحصة', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay(hour: sessionReminderHour, minute: sessionReminderMin),
                                      );
                                      if (picked != null) {
                                        setDialogState(() {
                                          sessionReminderHour = picked.hour;
                                          sessionReminderMin = picked.minute;
                                        });
                                      }
                                    },
                                    child: Text(formatTime(sessionReminderHour, sessionReminderMin), style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Text('المستهدف: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ChoiceChip(
                                    label: const Text('مجموعات اليوم (صباحاً)', style: TextStyle(fontSize: 10.5)),
                                    selected: sessionReminderTarget == 'today',
                                    onSelected: (val) {
                                      if (val) setDialogState(() => sessionReminderTarget = 'today');
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  ChoiceChip(
                                    label: const Text('مجموعات الغد (مساءً)', style: TextStyle(fontSize: 10.5)),
                                    selected: sessionReminderTarget == 'tomorrow',
                                    onSelected: (val) {
                                      if (val) setDialogState(() => sessionReminderTarget = 'tomorrow');
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Monthly report schedule
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                        ),
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                        child: ListTile(
                          title: const Text('التقرير الشهري الشامل 📅', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: const Text('يُجدول بعد آخر حصة في الشهر بآخر اليوم', style: TextStyle(fontSize: 11)),
                          trailing: OutlinedButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(hour: monthlyHour, minute: monthlyMin),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  monthlyHour = picked.hour;
                                  monthlyMin = picked.minute;
                                });
                              }
                            },
                            child: Text(formatTime(monthlyHour, monthlyMin), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Daily session report reminder
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                        ),
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        child: ListTile(
                          title: const Text('تقرير الحصة اليومي 📝', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: const Text('تنبيه مسائي في حال لم يُرسل بعد الحصة', style: TextStyle(fontSize: 11)),
                          trailing: OutlinedButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(hour: dailyHour, minute: dailyMin),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  dailyHour = picked.hour;
                                  dailyMin = picked.minute;
                                });
                              }
                            },
                            child: Text(formatTime(dailyHour, dailyMin), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Weekly report
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                        ),
                        color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                        child: ListTile(
                          title: const Text('التقرير الأسبوعي الشامل 📊', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: const Text('تذكير نهاية الأسبوع للمستوى الأكاديمي', style: TextStyle(fontSize: 11)),
                          trailing: OutlinedButton(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(hour: weeklyHour, minute: weeklyMin),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  weeklyHour = picked.hour;
                                  weeklyMin = picked.minute;
                                });
                              }
                            },
                            child: Text(formatTime(weeklyHour, weeklyMin), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
                    onPressed: () async {
                      await widget.database.setSetting('monthly_report_hour', monthlyHour.toString());
                      await widget.database.setSetting('monthly_report_minute', monthlyMin.toString());
                      await widget.database.setSetting('daily_report_evening_hour', dailyHour.toString());
                      await widget.database.setSetting('daily_report_evening_minute', dailyMin.toString());
                      await widget.database.setSetting('weekly_report_hour', weeklyHour.toString());
                      await widget.database.setSetting('weekly_report_minute', weeklyMin.toString());
                      await widget.database.setSetting('session_reminder_target', sessionReminderTarget);
                      await widget.database.setSetting('session_reminder_hour', sessionReminderHour.toString());
                      await widget.database.setSetting('session_reminder_minute', sessionReminderMin.toString());
                      if (mounted) {
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم حفظ وتحديث مواعيد إرسال التقارير والتذكيرات بنجاح ⏰✅'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    child: const Text('حفظ الإعدادات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(database: widget.database, initialTab: 2),
      ),
    );
    _loadAllData();
  }

  Future<void> _toggleWaMode() async {
    HapticFeedback.mediumImpact();
    final newMode = currentWaMode == 'api' ? 'manual' : 'api';
    if (newMode == 'api') {
      final endpoint = await widget.database.getSetting('whatsapp_api_endpoint', defaultValue: '');
      final apiKey = await widget.database.getSetting('whatsapp_api_key', defaultValue: '');
      if (endpoint.trim().isEmpty || apiKey.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'تنبيه: يجب إدخال رابط البوابة ومفتاح الـ API أولاً من الإعدادات لإرسال الرسائل سحابياً.',
              ),
              backgroundColor: Colors.amber.shade800,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'الإعدادات',
                textColor: Colors.white,
                onPressed: _openSettings,
              ),
            ),
          );
        }
      }
    }
    await widget.database.setSetting('whatsapp_mode', newMode);
    if (mounted) {
      setState(() {
        currentWaMode = newMode;
      });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: SectionTopBar(
        title: 'منظومة الرسائل والتواصل',
        icon: Icons.chat_bubble_rounded,
        onBack: widget.onBack,
        extraActions: [
          IconButton(
            icon: const Icon(Icons.draw_rounded),
            tooltip: 'تخصيص تذييل كل خدمة رسائل ✍️',
            onPressed: _showCustomFootersDialog,
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'إعدادات واتساب وقوالب الرسائل',
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'سجل الرسائل المرسلة',
            onPressed: _showSentHistorySheet,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // -----------------------------------------------------------
                // TOP INTERACTIVE SEGMENTED TABS
                // -----------------------------------------------------------
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildMainTabSegment(
                          index: 0,
                          title: 'خدمات الإرسال (8)',
                          icon: Icons.bolt_rounded,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildMainTabSegment(
                          index: 1,
                          title: 'متابعة اليوم',
                          badgeCount: dailyFollowupStudents.length,
                          icon: Icons.fact_check_rounded,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildMainTabSegment(
                          index: 2,
                          title: 'سجل الرسائل',
                          icon: Icons.history_rounded,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                ),

                // -----------------------------------------------------------
                // ACTIVE TAB CONTENT
                // -----------------------------------------------------------
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _mainTabIndex == 0
                        ? _buildServicesTab(isDark)
                        : (_mainTabIndex == 1
                            ? _buildDailyFollowupTab(isDark)
                            : _buildSentLogsTab(isDark)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMainTabSegment({
    required int index,
    required String title,
    required IconData icon,
    required bool isDark,
    int badgeCount = 0,
  }) {
    final isSelected = _mainTabIndex == index;
    const accentGreen = Color(0xFF25D366);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _mainTabIndex = index);
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF0F172A) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
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
              icon,
              size: 16,
              color: isSelected ? accentGreen : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                      : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFEF4444) : Colors.grey.shade500,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 1: SERVICES & DIRECT MESSAGING (THE 8 SERVICES ENGINE)
  // --------------------------------------------------------------------------
  Widget _buildServicesTab(bool isDark) {
    final visibleCategories = ParentServiceCategory.values.where((c) {
      if (_activeDomain == ServiceDomain.all) return true;
      return _getCategoryDomain(c) == _activeDomain;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
      children: [
        // Mode & Settings Status Bar (Responsive Column & Wrap to prevent overflow)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    currentWaMode == 'api'
                        ? Icons.cloud_done_rounded
                        : Icons.phone_android_rounded,
                    size: 17,
                    color: currentWaMode == 'api'
                        ? const Color(0xFF4ADE80)
                        : const Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentWaMode == 'api'
                          ? 'وضع الإرسال: آلي وسحابي (عبر API دون فتح التطبيق)'
                          : 'وضع الإرسال: يدوي ومباشر (يفتح تطبيق واتساب على الهاتف)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey.shade300 : const Color(0xFF334155),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  InkWell(
                    onTap: _toggleWaMode,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (currentWaMode == 'api'
                                ? const Color(0xFF4ADE80)
                                : const Color(0xFF38BDF8))
                            .withValues(alpha: isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (currentWaMode == 'api'
                                  ? const Color(0xFF4ADE80)
                                  : const Color(0xFF38BDF8))
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 14,
                            color: currentWaMode == 'api'
                                ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
                                : (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            currentWaMode == 'api' ? 'تحويل ليدوي' : 'تحويل لـ API',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: currentWaMode == 'api'
                                  ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
                                  : (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _showCustomFootersDialog,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB))
                            .withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB))
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.draw_rounded,
                            size: 14,
                            color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'تذييل الرسائل ✍️',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _showReportSchedulingConfigDialog,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED))
                            .withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED))
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'مواعيد التنبيهات ⏰',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _openSettings,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF4ADE80) : const Color(0xFF128C4A))
                            .withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (isDark ? const Color(0xFF4ADE80) : const Color(0xFF128C4A))
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.settings_suggest_rounded,
                            size: 14,
                            color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF128C4A),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'ضبط ⚙️',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF128C4A),
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
        ),
        const SizedBox(height: 14),

        // Domain Filter Pills
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'أقسام وخدمات الرسائل (8 خدمات)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            Text(
              'اختر نوع الخدمة:',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildDomainFilterChip('الكل (8)', ServiceDomain.all, Icons.dashboard_rounded),
              const SizedBox(width: 6),
              _buildDomainFilterChip('أكاديمي ومتابعة (3)', ServiceDomain.academic, Icons.school_rounded),
              const SizedBox(width: 6),
              _buildDomainFilterChip('حضور ومواعيد (3)', ServiceDomain.attendance, Icons.schedule_rounded),
              const SizedBox(width: 6),
              _buildDomainFilterChip('ماليات وسلوك (2)', ServiceDomain.financial, Icons.account_balance_wallet_rounded),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Services Rich Cards Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: visibleCategories.map((cat) {
                return SizedBox(
                  width: cardWidth,
                  child: _buildServiceCard(cat, isDark),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 18),

        // --------------------------------------------------------------------
        // CARD: TARGET SELECTION (GROUP & STUDENT & SCOPE)
        // --------------------------------------------------------------------
        _buildTargetSelectionCard(isDark),
        const SizedBox(height: 16),

        // --------------------------------------------------------------------
        // CARD: AUTHENTIC WHATSAPP CHAT BUBBLE PREVIEW
        // --------------------------------------------------------------------
        _buildWhatsAppChatPreview(isDark),
        const SizedBox(height: 16),

        // --------------------------------------------------------------------
        // DISPATCH ACTION BUTTONS
        // --------------------------------------------------------------------
        _buildDispatchActionButtons(isDark),
      ],
    );
  }

  // ==========================================================================
  // SMART TARGET SCOPE & SELECTION COMPONENTS
  // ==========================================================================

  Widget _buildTargetSelectionCard(bool isDark) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.how_to_reg_rounded, size: 18, color: Color(0xFF128C4A)),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'تحديد نطاق والجهة المستهدفة للإرسال',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tune_rounded, size: 13, color: Color(0xFF128C4A)),
                      const SizedBox(width: 4),
                      Text(
                        currentScopeTitle,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF128C4A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Segmented Scope Switcher (4 Options: طالب محدد / مجموعة كاملة / مجاميع اليوم / مجموعات مخصصة)
            _buildScopeSegmentedControl(isDark),
            const SizedBox(height: 12),

            // Scope-Specific Target Controls
            _buildScopeTargetContent(isDark),
            const SizedBox(height: 12),

            // Recipient Target Selector
            _buildRecipientTargetSelector(isDark),

            // Category specific controls
            _buildCategorySpecificControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeSegmentedControl(bool isDark) {
    const scopes = [
      (WhatsAppSendScope.singleStudent, 'طالب محدد', Icons.person_rounded, Color(0xFF3B82F6)),
      (WhatsAppSendScope.singleGroup, 'مجموعة كاملة', Icons.groups_rounded, Color(0xFF10B981)),
      (WhatsAppSendScope.todayGroups, 'مجاميع اليوم', Icons.today_rounded, Color(0xFFF59E0B)),
      (WhatsAppSendScope.customGroups, 'مجموعات مخصصة', Icons.tune_rounded, Color(0xFF8B5CF6)),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Row(
        children: scopes.map((item) {
          final scope = item.$1;
          final title = item.$2;
          final icon = item.$3;
          final color = item.$4;
          final isSelected = _sendScope == scope;

          return Expanded(
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                _applyScopeSelection(activeCategory, scope);
              },
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected
                      ? Border.all(color: color.withValues(alpha: 0.5), width: 1.2)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isSelected ? color : Colors.grey,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? (isDark ? Colors.white : const Color(0xFF0F172A))
                            : Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildScopeTargetContent(bool isDark) {
    switch (_sendScope) {
      case WhatsAppSendScope.singleStudent:
        return _buildSingleStudentScopeContent(isDark);
      case WhatsAppSendScope.singleGroup:
        return _buildSingleGroupScopeContent(isDark);
      case WhatsAppSendScope.todayGroups:
        return _buildTodayGroupsScopeContent(isDark);
      case WhatsAppSendScope.customGroups:
        return _buildCustomGroupsScopeContent(isDark);
    }
  }

  Widget _buildSingleStudentScopeContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group Filter Dropdown
        DropdownButtonFormField<String>(
          key: ValueKey('filtergrp_${_singleStudentGroupFilter}_${allGroups.length}'),
          initialValue: _singleStudentGroupFilter,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'تصفية الطلاب حسب المجموعة',
            prefixIcon: const Icon(Icons.filter_list_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          items: [
            DropdownMenuItem(
              value: 'all',
              child: Text(
                'جميع المجموعات (${allStudents.length} طالب)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ...allGroups.map((g) {
              final count = allStudents.where((s) => s.groupId == g.id).length;
              return DropdownMenuItem(
                value: g.id,
                child: Text(
                  '${g.name} ($count طالب)',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              _singleStudentGroupFilter = val;
              final list = _studentsForSingleStudentScope;
              if (list.isNotEmpty) {
                selectedStudent = list.first;
              } else {
                selectedStudent = null;
              }
              isEditingCustomText = false;
            });
            _syncCustomMessageBuffer();
          },
        ),
        const SizedBox(height: 10),

        // Student Selector Dropdown
        Builder(
          builder: (context) {
            final list = _studentsForSingleStudentScope;
            final currentStudent = list.contains(selectedStudent)
                ? selectedStudent
                : (list.isNotEmpty ? list.first : null);

            return DropdownButtonFormField<StudentModel?>(
              key: ValueKey('wastu_single_${currentStudent?.id}_${list.length}'),
              initialValue: currentStudent,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'الطالب المستهدف',
                prefixIcon: const Icon(Icons.person_rounded, size: 20, color: Color(0xFF3B82F6)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: [
                if (list.isEmpty)
                  const DropdownMenuItem<StudentModel?>(
                    value: null,
                    child: Text(
                      'لا يوجد طلاب في هذه المجموعة',
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  ...list.map((s) => DropdownMenuItem<StudentModel?>(
                        value: s,
                        child: Text(
                          '${s.fullName} (${s.stage} - ${s.grade})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
              ],
              onChanged: (val) {
                setState(() {
                  selectedStudent = val;
                  isEditingCustomText = false;
                });
                if (activeCategory == ParentServiceCategory.holisticReport &&
                    val != null) {
                  unawaited(_loadStudentReportData(val.id));
                }
                _syncCustomMessageBuffer();
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSingleGroupScopeContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group Mode Selector (مجموعات اليوم vs مجموعات الغد vs مجموعة مخصصة)
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            children: isReminderCategory
                ? [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _groupMode = GroupSelectionMode.today;
                            if (todayGroups.isNotEmpty) {
                              selectedGroupId = todayGroups.first.id;
                            } else {
                              selectedGroupId = 'all';
                            }
                            final list = filteredStudents;
                            selectedStudent = list.isNotEmpty ? list.first : null;
                            isEditingCustomText = false;
                          });
                          _syncCustomMessageBuffer();
                        },
                        borderRadius: BorderRadius.circular(9),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _groupMode == GroupSelectionMode.today
                                ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: _groupMode == GroupSelectionMode.today
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
                                Icons.today_rounded,
                                size: 15,
                                color: _groupMode == GroupSelectionMode.today
                                    ? const Color(0xFF10B981)
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'اليوم (${todayGroups.length})',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: _groupMode == GroupSelectionMode.today
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _groupMode == GroupSelectionMode.today
                                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _groupMode = GroupSelectionMode.tomorrow;
                            if (tomorrowGroups.isNotEmpty) {
                              selectedGroupId = tomorrowGroups.first.id;
                            } else {
                              selectedGroupId = 'all';
                            }
                            final list = filteredStudents;
                            selectedStudent = list.isNotEmpty ? list.first : null;
                            isEditingCustomText = false;
                          });
                          _syncCustomMessageBuffer();
                        },
                        borderRadius: BorderRadius.circular(9),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _groupMode == GroupSelectionMode.tomorrow
                                ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: _groupMode == GroupSelectionMode.tomorrow
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
                                Icons.alarm_rounded,
                                size: 15,
                                color: _groupMode == GroupSelectionMode.tomorrow
                                    ? const Color(0xFFF59E0B)
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'الغد (${tomorrowGroups.length})',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: _groupMode == GroupSelectionMode.tomorrow
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _groupMode == GroupSelectionMode.tomorrow
                                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _groupMode = GroupSelectionMode.custom;
                            selectedGroupId = 'all';
                            final list = filteredStudents;
                            selectedStudent = list.isNotEmpty ? list.first : null;
                            isEditingCustomText = false;
                          });
                          _syncCustomMessageBuffer();
                        },
                        borderRadius: BorderRadius.circular(9),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _groupMode == GroupSelectionMode.custom
                                ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: _groupMode == GroupSelectionMode.custom
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
                                Icons.tune_rounded,
                                size: 15,
                                color: _groupMode == GroupSelectionMode.custom
                                    ? const Color(0xFF3B82F6)
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'مخصصة (${allGroups.length})',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: _groupMode == GroupSelectionMode.custom
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _groupMode == GroupSelectionMode.custom
                                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]
                : [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _groupMode = GroupSelectionMode.today;
                            final smartGroups = defaultSmartGroups;
                            if (smartGroups.isNotEmpty) {
                              selectedGroupId = smartGroups.first.id;
                            } else {
                              selectedGroupId = 'all';
                            }
                            final list = filteredStudents;
                            selectedStudent = list.isNotEmpty ? list.first : null;
                            isEditingCustomText = false;
                          });
                          _syncCustomMessageBuffer();
                        },
                        borderRadius: BorderRadius.circular(9),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _groupMode == GroupSelectionMode.today
                                ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: _groupMode == GroupSelectionMode.today
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
                                isReminderCategory ? Icons.alarm_rounded : Icons.today_rounded,
                                size: 15,
                                color: _groupMode == GroupSelectionMode.today
                                    ? (isReminderCategory ? const Color(0xFFF59E0B) : const Color(0xFF10B981))
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '$smartModeTitle (${defaultSmartGroups.length})',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: _groupMode == GroupSelectionMode.today
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _groupMode == GroupSelectionMode.today
                                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                      : Colors.grey,
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
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _groupMode = GroupSelectionMode.custom;
                            selectedGroupId = 'all';
                            final list = filteredStudents;
                            selectedStudent = list.isNotEmpty ? list.first : null;
                            isEditingCustomText = false;
                          });
                          _syncCustomMessageBuffer();
                        },
                        borderRadius: BorderRadius.circular(9),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _groupMode == GroupSelectionMode.custom
                                ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: _groupMode == GroupSelectionMode.custom
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
                                Icons.tune_rounded,
                                size: 15,
                                color: _groupMode == GroupSelectionMode.custom
                                    ? const Color(0xFF3B82F6)
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'مجموعة مخصصة (${allGroups.length})',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: _groupMode == GroupSelectionMode.custom
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _groupMode == GroupSelectionMode.custom
                                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                      : Colors.grey,
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
        const SizedBox(height: 10),

        // Group Selector Dropdown
        Builder(
          builder: (context) {
            final isSmartMode = _groupMode == GroupSelectionMode.today || _groupMode == GroupSelectionMode.tomorrow;
            final smartGroups = defaultSmartGroups;
            String effectiveValue;

            if (isSmartMode) {
              if (smartGroups.isEmpty) {
                effectiveValue = 'all';
              } else if (selectedGroupId == 'today_all' || smartGroups.any((g) => g.id == selectedGroupId)) {
                effectiveValue = selectedGroupId ?? smartGroups.first.id;
              } else {
                effectiveValue = smartGroups.first.id;
              }
            } else {
              if (selectedGroupId == 'all' || allGroups.any((g) => g.id == selectedGroupId)) {
                effectiveValue = selectedGroupId ?? 'all';
              } else {
                effectiveValue = 'all';
              }
            }

            return DropdownButtonFormField<String>(
              key: ValueKey('wagrp_${_groupMode.name}_${isReminderCategory}_$effectiveValue'),
              initialValue: effectiveValue,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: isSmartMode
                    ? '$smartModeTitle ($smartModeDayName)'
                    : 'المجموعة الدراسية المستهدفة',
                prefixIcon: Icon(
                  isSmartMode
                      ? (_groupMode == GroupSelectionMode.tomorrow ? Icons.alarm_rounded : Icons.today_rounded)
                      : Icons.groups_rounded,
                  size: 20,
                  color: isSmartMode
                      ? (_groupMode == GroupSelectionMode.tomorrow ? const Color(0xFFF59E0B) : const Color(0xFF10B981))
                      : const Color(0xFF10B981),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: isSmartMode
                  ? [
                      if (smartGroups.isEmpty)
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(
                            'لا توجد مجموعات مجدولة $smartModeTitle ($smartModeDayName)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else ...[
                        DropdownMenuItem(
                          value: 'today_all',
                          child: Text(
                            '🌟 جميع $smartModeTitle (${smartGroups.length} مجموعات)',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        ...smartGroups.map((g) {
                          final gStudentIds = allStudents.where((s) => s.groupId == g.id).map((s) => s.id).toSet();
                          final count = gStudentIds.length;
                          final hasAttToday = todayAttendance.any((a) => gStudentIds.contains(a.studentId) && (a.status == 'present' || a.status == 'absent'));
                          final tLog = groupLatestLogs[g.id];
                          final todayStr = DateTime.now().toIso8601String().substring(0, 10);
                          final hasCurrToday = tLog != null &&
                              tLog.date == todayStr &&
                              tLog.lessonTitle.trim().isNotEmpty &&
                              tLog.lessonTitle.trim() != 'حصة دراسية اعتيادية';
                          final isReady = hasAttToday && hasCurrToday;
                          final statusTag = isReady
                              ? ' • ✅ جاهزة للإرسال 🚀'
                              : (hasAttToday ? ' • ⏳ تم التحضير' : '');

                          return DropdownMenuItem(
                            value: g.id,
                            child: Text(
                              '📅 ${g.name} ($count طالب)$statusTag • ${g.startTime.isNotEmpty ? g.startTime : g.schedule}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                    ]
                  : [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(
                          'جميع المجموعات (${allStudents.length} طالب)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...allGroups.map((g) {
                        final gStudentIds = allStudents.where((s) => s.groupId == g.id).map((s) => s.id).toSet();
                        final count = gStudentIds.length;
                        final hasAttToday = todayAttendance.any((a) => gStudentIds.contains(a.studentId) && (a.status == 'present' || a.status == 'absent'));
                        final tLog = groupLatestLogs[g.id];
                        final todayStr = DateTime.now().toIso8601String().substring(0, 10);
                        final hasCurrToday = tLog != null &&
                            tLog.date == todayStr &&
                            tLog.lessonTitle.trim().isNotEmpty &&
                            tLog.lessonTitle.trim() != 'حصة دراسية اعتيادية';
                        final isReady = hasAttToday && hasCurrToday;
                        final statusTag = isReady
                            ? ' • ✅ جاهزة للإرسال 🚀'
                            : (hasAttToday ? ' • ⏳ تم التحضير' : '');

                        return DropdownMenuItem(
                          value: g.id,
                          child: Text(
                            '${g.name} ($count طالب)$statusTag',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  selectedGroupId = val;
                  final list = filteredStudents;
                  if (list.isNotEmpty) {
                    selectedStudent = list.first;
                  } else {
                    selectedStudent = null;
                  }
                  isEditingCustomText = false;
                });
                if (activeCategory == ParentServiceCategory.holisticReport &&
                    selectedStudent != null) {
                  unawaited(_loadStudentReportData(selectedStudent!.id));
                }
                _syncCustomMessageBuffer();
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildTodayGroupsScopeContent(bool isDark) {
    if (todayGroups.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'لا توجد مجموعات مجدولة لهذا اليوم (${_getTodayArabicName()}). يمكنك التبديل إلى "مجموعات مخصصة" لتحديد أي مجموعات للإرسال.',
                style: const TextStyle(fontSize: 11.5, height: 1.3),
              ),
            ),
            TextButton(
              onPressed: () {
                _applyScopeSelection(activeCategory, WhatsAppSendScope.customGroups);
              },
              child: const Text('مجموعات مخصصة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.today_rounded, color: Color(0xFFF59E0B), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'مجاميع اليوم المجدولة (${todayGroups.length} مجموعات • ${todayGroupStudents.length} طالب)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'إرسال تلقائي 🌟',
                      style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: todayGroups.map((g) {
                  final count = allStudents.where((s) => s.groupId == g.id).length;
                  final time = g.startTime.isNotEmpty ? g.startTime : g.schedule;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                        Text(
                          '${g.name} ($count طالب)${time.isNotEmpty ? ' • $time' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomGroupsScopeContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'تم تحديد (${_selectedCustomGroupIds.length}) من (${allGroups.length}) مجموعات • (${customGroupStudents.length} طالب)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _selectedCustomGroupIds.clear();
                  _selectedCustomGroupIds.addAll(allGroups.map((g) => g.id));
                });
                _syncCustomMessageBuffer();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('تحديد الكل', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
              ),
            ),
            const SizedBox(width: 6),
            if (todayGroups.isNotEmpty) ...[
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedCustomGroupIds.clear();
                    _selectedCustomGroupIds.addAll(todayGroups.map((g) => g.id));
                  });
                  _syncCustomMessageBuffer();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('مجاميع اليوم فقط', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                ),
              ),
              const SizedBox(width: 6),
            ],
            InkWell(
              onTap: () {
                setState(() {
                  _selectedCustomGroupIds.clear();
                });
                _syncCustomMessageBuffer();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('إلغاء التحديد', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.red)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 210),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.all(6),
            itemCount: allGroups.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final g = allGroups[index];
              final isChecked = _selectedCustomGroupIds.contains(g.id);
              final count = allStudents.where((s) => s.groupId == g.id).length;
              final time = g.startTime.isNotEmpty ? g.startTime : g.schedule;

              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (isChecked) {
                      _selectedCustomGroupIds.remove(g.id);
                    } else {
                      _selectedCustomGroupIds.add(g.id);
                    }
                  });
                  _syncCustomMessageBuffer();
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isChecked,
                        activeColor: const Color(0xFF8B5CF6),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (val == true) {
                              _selectedCustomGroupIds.add(g.id);
                            } else {
                              _selectedCustomGroupIds.remove(g.id);
                            }
                          });
                          _syncCustomMessageBuffer();
                        },
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              g.name,
                              style: TextStyle(
                                fontWeight: isChecked ? FontWeight.bold : FontWeight.w600,
                                fontSize: 12.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (time.isNotEmpty || g.grade.isNotEmpty)
                              Text(
                                '${g.grade}${time.isNotEmpty ? ' • $time' : ''}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isChecked ? const Color(0xFF8B5CF6) : Colors.grey).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$count طالب',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isChecked ? const Color(0xFF8B5CF6) : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDispatchActionButtons(bool isDark) {
    final activeStudent = selectedStudent ??
        (_studentsForSingleStudentScope.isNotEmpty ? _studentsForSingleStudentScope.first : null);

    Widget primaryButton;

    switch (_sendScope) {
      case WhatsAppSendScope.singleStudent:
        String sendButtonLabel = 'إرسال لطالب محدد';
        if (activeStudent != null) {
          final name = activeStudent.fullName;
          switch (_recipientTarget) {
            case WhatsAppRecipientTarget.parent:
              sendButtonLabel = 'إرسال لولي أمر ($name) 🚀';
              break;
            case WhatsAppRecipientTarget.student:
              sendButtonLabel = 'إرسال للطالب ($name) 🚀';
              break;
            case WhatsAppRecipientTarget.both:
              sendButtonLabel = 'إرسال للولي والطالب ($name) 🚀';
              break;
          }
        }
        primaryButton = FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF25D366),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.send_rounded, size: 20),
          label: Text(
            sendButtonLabel,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: activeStudent != null ? () => _sendToStudent(activeStudent) : null,
        );
        break;

      case WhatsAppSendScope.singleGroup:
        final grpName = currentSelectedGroup?.name ?? 'المجموعة';
        final count = filteredStudents.length;
        final label = _recipientTarget == WhatsAppRecipientTarget.parent
            ? 'إرسال جماعي لأولياء أمور $grpName ($count طالب) 📢'
            : (_recipientTarget == WhatsAppRecipientTarget.student
                ? 'إرسال جماعي لطلاب $grpName ($count طالب) 📢'
                : 'إرسال جماعي للطلاب وأولياء أمورهم ($count طالب) 📢');
        primaryButton = FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.campaign_rounded, size: 20),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: count > 0 ? _showBatchSendDialog : null,
        );
        break;

      case WhatsAppSendScope.todayGroups:
        final count = todayGroupStudents.length;
        final grpCount = todayGroups.length;
        final label = _recipientTarget == WhatsAppRecipientTarget.parent
            ? 'إرسال جماعي لكافة مجاميع اليوم ($count طالب في $grpCount مجموعات) 🌟'
            : (_recipientTarget == WhatsAppRecipientTarget.student
                ? 'إرسال لطلاب كافة مجاميع اليوم ($count طالب في $grpCount مجموعات) 🌟'
                : 'إرسال شامل لكافة مجاميع اليوم ($count طالب) 🌟');
        primaryButton = FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.bolt_rounded, size: 20),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: count > 0 ? _showBatchSendDialog : null,
        );
        break;

      case WhatsAppSendScope.customGroups:
        final count = customGroupStudents.length;
        final grpCount = _selectedCustomGroupIds.length;
        final label = _recipientTarget == WhatsAppRecipientTarget.parent
            ? 'إرسال للمجموعات المحددة ($count طالب في $grpCount مجموعات) 🚀'
            : (_recipientTarget == WhatsAppRecipientTarget.student
                ? 'إرسال لطلاب المجموعات المحددة ($count طالب) 🚀'
                : 'إرسال شامل للمجموعات المحددة ($count طالب) 🚀');
        primaryButton = FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF8B5CF6),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.send_and_archive_rounded, size: 20),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: count > 0 ? _showBatchSendDialog : null,
        );
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: primaryButton),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.all(14),
              ),
              icon: const Icon(Icons.copy_rounded, size: 20),
              tooltip: 'نسخ الرسالة',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: customMessageController.text));
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text('تم نسخ نص الرسالة إلى الحافظة 📋'),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDomainFilterChip(String label, ServiceDomain domain, IconData icon) {
    final isSelected = _activeDomain == domain;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 14,
        color: isSelected ? Colors.white : const Color(0xFF128C4A),
      ),
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF25D366),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? Colors.white : null,
      ),
      onSelected: (val) {
        if (val) {
          HapticFeedback.selectionClick();
          setState(() => _activeDomain = domain);
        }
      },
    );
  }

  Widget _buildServiceCard(ParentServiceCategory cat, bool isDark) {
    final isSelected = cat == activeCategory;
    final color = _getCategoryColor(cat);

    return InkWell(
      onTap: () => _applyScopeSelection(cat, _sendScope),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.22 : 0.12)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isSelected ? 0.28 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_getCategoryIcon(cat), color: color, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getCategoryTitle(cat),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected
                          ? (isDark ? Colors.white : const Color(0xFF0F172A))
                          : (isDark ? Colors.white70 : const Color(0xFF334155)),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getCategorySubtitle(cat),
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isSelected) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isDark ? 0.35 : 0.20),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        currentScopeTitle,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 12, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhatsAppChatPreview(bool isDark) {
    final activeStudent = selectedStudent ??
        (_studentsForSingleStudentScope.isNotEmpty ? _studentsForSingleStudentScope.first : null);

    String contactTitle;
    switch (_sendScope) {
      case WhatsAppSendScope.singleStudent:
        contactTitle = 'ولي أمر الطالب';
        if (activeStudent != null) {
          switch (_recipientTarget) {
            case WhatsAppRecipientTarget.parent:
              contactTitle = 'ولي أمر ${activeStudent.fullName}';
              break;
            case WhatsAppRecipientTarget.student:
              contactTitle = activeStudent.fullName;
              break;
            case WhatsAppRecipientTarget.both:
              contactTitle = '${activeStudent.fullName} + ولي الأمر';
              break;
          }
        }
        break;
      case WhatsAppSendScope.singleGroup:
        contactTitle = 'مجموعة ${currentSelectedGroup?.name ?? "المختارة"} (معاينة)';
        break;
      case WhatsAppSendScope.todayGroups:
        contactTitle = 'كافة مجاميع اليوم (${todayGroups.length} مجموعات - نموذج)';
        break;
      case WhatsAppSendScope.customGroups:
        contactTitle = 'مجموعات مخصصة (${_selectedCustomGroupIds.length} مجموعات - نموذج)';
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B141B) : const Color(0xFFEFEAE2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF1F2C34) : const Color(0xFFD1D7DB),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // WhatsApp Top Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2C34) : const Color(0xFF075E54),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF25D366),
                  child: Text(
                    contactTitle.isNotEmpty ? contactTitle[0] : 'و',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contactTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Row(
                        children: [
                          Text(
                            'متصل الآن',
                            style: TextStyle(
                              color: Color(0xFF4ADE80),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.circle, size: 6, color: Color(0xFF4ADE80)),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isEditingCustomText ? Icons.check_circle_rounded : Icons.edit_note_rounded,
                    color: isEditingCustomText ? const Color(0xFF4ADE80) : Colors.white,
                    size: 22,
                  ),
                  tooltip: isEditingCustomText ? 'حفظ التعديل' : 'تعديل نص الرسالة',
                  onPressed: () {
                    setState(() => isEditingCustomText = !isEditingCustomText);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                  tooltip: 'إعادة ضبط النص الأصلي',
                  onPressed: () {
                    setState(() => isEditingCustomText = false);
                    _syncCustomMessageBuffer();
                  },
                ),
              ],
            ),
          ),

          // Encryption Badge
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF182229) : const Color(0xFFFFEECD),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 11,
                      color: isDark ? Colors.grey.shade400 : const Color(0xFF856404),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'الرسائل مشفرة تماماً بين الطرفين',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: isDark ? Colors.grey.shade400 : const Color(0xFF856404),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Variable insertion row if editing
          if (isEditingCustomText) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text('إدراج متغير:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 6),
                    ...[
                      '{اسم_الطالب}',
                      '{ولي_الأمر}',
                      '{المجموعة}',
                      '{المبلغ}',
                      '{التاريخ}',
                      '{السنتر}',
                      '{المعلم}',
                    ].map((chip) => Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: ActionChip(
                        label: Text(chip, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          final sel = customMessageController.selection;
                          final text = customMessageController.text;
                          if (sel.isValid && sel.start >= 0) {
                            final newText = text.replaceRange(sel.start, sel.end, chip);
                            customMessageController.value = TextEditingValue(
                              text: newText,
                              selection: TextSelection.collapsed(offset: sel.start + chip.length),
                            );
                          } else {
                            customMessageController.text = '$text $chip';
                          }
                        },
                      ),
                    )),
                  ],
                ),
              ),
            ),
          ],

          // Outgoing WhatsApp Bubble
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF005C4B) : const Color(0xFFDCF8C6),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                    topRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isEditingCustomText)
                      TextField(
                        controller: customMessageController,
                        maxLines: 9,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'اكتب نص الرسالة هنا...',
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      )
                    else
                      SelectableText(
                        customMessageController.text,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.55,
                          color: isDark ? Colors.white : const Color(0xFF111B21),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'الآن',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.done_all_rounded,
                          size: 15,
                          color: Color(0xFF34B7F1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // TAB 2: DAILY FOLLOWUP & ATTENDANCE BROADCAST
  // --------------------------------------------------------------------------
  Widget _buildDailyFollowupTab(bool isDark) {
    final allFollowup = dailyFollowupStudents;
    final absentStudents = todayAttendance
        .where((a) => a.status == 'absent')
        .map((a) => allStudents.where((s) => s.id == a.studentId).firstOrNull)
        .whereType<StudentModel>()
        .toList();
    final debtStudents = allFollowup.where((s) => s.hasOutstandingPayment).toList();

    List<StudentModel> displayedStudents;
    if (_dailyFilterType == 'absent') {
      displayedStudents = absentStudents;
    } else if (_dailyFilterType == 'debt') {
      displayedStudents = debtStudents;
    } else {
      displayedStudents = allFollowup;
    }

    final mutedColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        // Top Broadcast Action
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.summarize_rounded, color: Color(0xFF25D366), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إرسال التقرير اليومي الشامل',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'إرسال تقرير الحصص والغياب تلقائياً لكل أولياء أمور حصص اليوم',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text(
                    'بدء إرسال التقرير اليومي الآن',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _confirmDailyReportSend,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Summary Stats Row
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'إجمالي المتابعات',
                count: allFollowup.length.toString(),
                icon: Icons.fact_check_rounded,
                color: const Color(0xFF3B82F6),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'غياب اليوم',
                count: absentStudents.length.toString(),
                icon: Icons.person_off_rounded,
                color: const Color(0xFFEF4444),
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                title: 'متأخرات مالية',
                count: debtStudents.length.toString(),
                icon: Icons.account_balance_wallet_rounded,
                color: const Color(0xFFF59E0B),
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('الكل (${allFollowup.length})', 'all'),
              const SizedBox(width: 6),
              _buildFilterChip('غياب اليوم (${absentStudents.length})', 'absent'),
              const SizedBox(width: 6),
              _buildFilterChip('متأخرات (${debtStudents.length})', 'debt'),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (displayedStudents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 54, color: Color(0xFF25D366)),
                  const SizedBox(height: 12),
                  const Text(
                    'رائع! لا توجد حالات تحتاج متابعة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text('جميع الطلاب ملتزمون بالحضور والمدفوعات', style: TextStyle(color: mutedColor, fontSize: 12)),
                ],
              ),
            ),
          )
        else
          ...displayedStudents.map((student) {
            final hasPhone = _hasValidContactPhone(student);
            final group = allGroups.where((g) => g.id == student.groupId).firstOrNull;
            return Card(
              elevation: 0.5,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.15),
                      child: Text(
                        student.fullName.isNotEmpty ? student.fullName[0] : 'ط',
                        style: const TextStyle(color: Color(0xFF128C4A), fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            student.fullName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${group?.name ?? "المجموعة"} • ${_dailyFollowupReason(student)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.visibility_outlined, size: 20),
                      tooltip: 'معاينة الرسالة',
                      onPressed: hasPhone ? () => _showDailyFollowupPreview(student) : null,
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 14),
                      label: const Text('إرسال', style: TextStyle(fontSize: 12)),
                      onPressed: hasPhone
                          ? () async {
                              final phone = student.parentPhone.isNotEmpty
                                  ? student.parentPhone
                                  : student.studentPhone;
                              final msg = _buildDailyFollowupMessage(student);
                              await WhatsAppService.openWhatsApp(
                                phone: phone,
                                message: msg,
                                database: widget.database,
                                studentId: student.id,
                                studentName: student.fullName,
                                recipientType: student.parentPhone.isNotEmpty ? 'parent' : 'student',
                                category: 'daily_followup',
                              );
                            }
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            count,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 10, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _dailyFilterType == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF25D366),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : null,
      ),
      onSelected: (val) {
        if (val) {
          setState(() => _dailyFilterType = value);
        }
      },
    );
  }

  // --------------------------------------------------------------------------
  // TAB 3: SENT MESSAGES LOGS & HISTORY
  // --------------------------------------------------------------------------
  Widget _buildSentLogsTab(bool isDark) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.database.getWhatsAppLogs(limit: 150),
      builder: (context, snapshot) {
        final logs = snapshot.data ?? [];
        final isLoadingLogs = snapshot.connectionState == ConnectionState.waiting;

        final filteredLogs = logs.where((log) {
          final status = log['status']?.toString() ?? '';
          final isSent = status == 'sent' || status == 'success' || status == 'sent_manual';

          if (_logsFilterStatus == 'sent' && !isSent) {
            return false;
          }
          if (_logsFilterStatus == 'failed' && isSent) {
            return false;
          }
          if (_logsFilterCategory != 'all' && log['category'] != _logsFilterCategory) {
            return false;
          }
          if (_logsSearchText.trim().isNotEmpty) {
            final query = _logsSearchText.trim().toLowerCase();
            final name = (log['student_name'] ?? '').toString().toLowerCase();
            final phone = (log['phone'] ?? '').toString().toLowerCase();
            final message = (log['message'] ?? '').toString().toLowerCase();
            return name.contains(query) || phone.contains(query) || message.contains(query);
          }
          return true;
        }).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            // Separation banner: Direct reports to Reports section
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insights_rounded, color: Color(0xFF0284C7), size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سجل تقارير المتابعة متاح في قسم التقارير 📊',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'تم تنظيم تقارير الحصص والتقارير الأسبوعية والشهرية بالكامل داخل قسم التقارير لمنع تداخل الرسائل مع التقارير.',
                          style: TextStyle(fontSize: 10.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFF0284C7),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                    label: const Text('قسم التقارير', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => ReportsScreen(
                            database: widget.database,
                            initialTab: 1,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Search & Filter header
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'بحث في سجل الرسائل (الاسم أو الرقم)...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) => setState(() => _logsSearchText = val),
                  ),
                ),
                if (filteredLogs.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: _selectedLogIds.length == filteredLogs.length && _selectedLogIds.isNotEmpty
                        ? 'إلغاء تحديد الكل'
                        : 'تحديد الكل (${filteredLogs.length})',
                    icon: Icon(
                      _selectedLogIds.length == filteredLogs.length && _selectedLogIds.isNotEmpty
                          ? Icons.check_box_rounded
                          : Icons.checklist_rounded,
                      color: const Color(0xFF0284C7),
                    ),
                    onPressed: () {
                      setState(() {
                        if (_selectedLogIds.length == filteredLogs.length && _selectedLogIds.isNotEmpty) {
                          _selectedLogIds.clear();
                        } else {
                          for (final l in filteredLogs) {
                            final id = (l['id'] as num?)?.toInt();
                            if (id != null) _selectedLogIds.add(id);
                          }
                        }
                      });
                    },
                  ),
                ],
              ],
            ),
            if (_selectedLogIds.isEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      size: 16,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'اضغط مطولاً على أي رسالة لتحديدها وحذفها، أو اختر أكثر من رسالة معاً',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_selectedLogIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFFEF4444), size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'تم تحديد ${_selectedLogIds.length} عنصر للحذف',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => setState(() => _selectedLogIds.clear()),
                      child: const Text('إلغاء', style: TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.delete_rounded, size: 15, color: Colors.white),
                      label: const Text(
                        'حذف المحدد',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      onPressed: () async {
                        final count = _selectedLogIds.length;
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('حذف الرسائل المحددة'),
                            content: Text('هل أنت متأكد من حذف ($count) رسالة محددة من السجل؟'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('حذف'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await widget.database.deleteWhatsAppLogsByIds(_selectedLogIds.toList());
                          setState(() => _selectedLogIds.clear());
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('تم حذف ($count) رسالة محددة من السجل 🗑️'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildLogsFilterChip('الكل (${logs.length})', 'all'),
                  const SizedBox(width: 6),
                  _buildLogsFilterChip('المرسلة بنجاح ✅', 'sent'),
                  const SizedBox(width: 6),
                  _buildLogsFilterChip('المعلقة / الأخطاء ⚠️', 'failed'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildLogsCategoryChip('كافة الأقسام', 'all'),
                  const SizedBox(width: 6),
                  _buildLogsCategoryChip('تقارير الحصص', 'sessionFollowup'),
                  const SizedBox(width: 6),
                  _buildLogsCategoryChip('تقارير أسبوعية', 'holisticReport'),
                  const SizedBox(width: 6),
                  _buildLogsCategoryChip('إنذارات الغياب', 'absenceAlert'),
                  const SizedBox(width: 6),
                  _buildLogsCategoryChip('كشكول وسلوك', 'notebookBehavior'),
                  const SizedBox(width: 6),
                  _buildLogsCategoryChip('نتائج الامتحانات', 'examScore'),
                  const SizedBox(width: 6),
                  _buildLogsCategoryChip('تذكير بموعد', 'sessionReminder'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (isLoadingLogs)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
            else if (filteredLogs.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('لا توجد رسائل مطابقة في السجل', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else
              ...filteredLogs.map((log) {
                final status = log['status']?.toString() ?? 'sent';
                final isSuccess = status == 'sent' || status == 'success' || status == 'sent_manual';
                final isManual = status == 'sent_manual';
                final recipient = log['recipient_type'] == 'student' ? 'الطالب' : 'ولي الأمر';
                final category = log['category']?.toString() ?? '';
                final sentAt = log['sent_at']?.toString() ?? log['created_at']?.toString() ?? '';
                final logId = (log['id'] as num?)?.toInt();
                final isSelected = logId != null && _selectedLogIds.contains(logId);

                final categoryTitle = switch (category) {
                  'sessionFollowup' => 'تقرير حصة 📝',
                  'holisticReport' => 'تقرير أسبوعي/شهري 📊',
                  'absenceAlert' => 'إنذار غياب 🚨',
                  'notebookBehavior' => 'كشكول وسلوك 📓',
                  'sessionReminder' => 'تذكير بموعد 🔔',
                  'examScore' || 'examResult' => 'نتيجة امتحان 🎯',
                  'financialReceipt' => 'ماليات 💳',
                  'sessionCancellation' => 'إلغاء حصة 🚫',
                  _ => 'رسالة عامة 💬',
                };

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () {
                    HapticFeedback.heavyImpact();
                    if (logId != null) {
                      setState(() {
                        if (_selectedLogIds.contains(logId)) {
                          _selectedLogIds.remove(logId);
                        } else {
                          _selectedLogIds.add(logId);
                        }
                      });
                    }
                  },
                  onTap: _selectedLogIds.isNotEmpty
                      ? () {
                          HapticFeedback.selectionClick();
                          if (logId != null) {
                            setState(() {
                              if (_selectedLogIds.contains(logId)) {
                                _selectedLogIds.remove(logId);
                              } else {
                                _selectedLogIds.add(logId);
                              }
                            });
                          }
                        }
                      : null,
                  child: IgnorePointer(
                    ignoring: _selectedLogIds.isNotEmpty,
                    child: Card(
                      elevation: isSelected ? 2 : 0.5,
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isSelected
                          ? const Color(0xFFEF4444).withValues(alpha: isDark ? 0.22 : 0.08)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected
                              ? const Color(0xFFEF4444)
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          width: isSelected ? 1.8 : 1,
                        ),
                      ),
                      child: ExpansionTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (logId != null && _selectedLogIds.isNotEmpty)
                              Checkbox(
                                value: isSelected,
                                activeColor: const Color(0xFFEF4444),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedLogIds.add(logId);
                                    } else {
                                      _selectedLogIds.remove(logId);
                                    }
                                  });
                                },
                              ),
                            CircleAvatar(
                              radius: 17,
                              backgroundColor: isSuccess
                                  ? (isManual
                                      ? Colors.teal.withValues(alpha: 0.15)
                                      : Colors.green.withValues(alpha: 0.15))
                                  : Colors.orange.withValues(alpha: 0.15),
                              child: Icon(
                                isSuccess
                                    ? (isManual ? Icons.send_to_mobile_rounded : Icons.check_circle_rounded)
                                    : Icons.schedule_rounded,
                                color: isSuccess ? (isManual ? Colors.teal : Colors.green) : Colors.orange,
                                size: 17,
                              ),
                            ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                log['student_name']?.toString() ?? log['phone']?.toString() ?? 'مجهول',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(categoryTitle,
                                  style: const TextStyle(
                                      fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(recipient, style: const TextStyle(fontSize: 10)),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${log['phone'] ?? ''} • $sentAt',
                          style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: SelectableText(
                                    log['message']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 12, height: 1.4),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (logId != null)
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          foregroundColor: Colors.redAccent,
                                        ),
                                        icon: const Icon(Icons.delete_outline_rounded, size: 14),
                                        label: const Text('حذف الرسالة', style: TextStyle(fontSize: 11)),
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (c) => AlertDialog(
                                              title: const Text('حذف الرسالة'),
                                              content: const Text('هل أنت متأكد من حذف هذه الرسالة من السجل؟'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () => Navigator.pop(c, false),
                                                    child: const Text('إلغاء')),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                  onPressed: () => Navigator.pop(c, true),
                                                  child: const Text('حذف'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            await widget.database.deleteWhatsAppLog(logId);
                                            setState(() => _selectedLogIds.remove(logId));
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('تم حذف الرسالة من السجل 🗑️'),
                                                  duration: Duration(seconds: 2),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                      icon: const Icon(Icons.copy_rounded, size: 14),
                                      label: const Text('نسخ الرسالة', style: TextStyle(fontSize: 11)),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: log['message']?.toString() ?? ''));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('تم نسخ نص الرسالة إلى الحافظة 📋'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _buildLogsFilterChip(String label, String value) {
    final isSelected = _logsFilterStatus == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF25D366),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : null,
      ),
      onSelected: (val) {
        if (val) setState(() => _logsFilterStatus = value);
      },
    );
  }

  Widget _buildLogsCategoryChip(String label, String value) {
    final isSelected = _logsFilterCategory == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF0284C7).withValues(alpha: 0.25),
      backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? const Color(0xFF0284C7) : null,
      ),
      onSelected: (val) {
        if (val) setState(() => _logsFilterCategory = value);
      },
    );
  }

  Widget _buildCategorySpecificControls() {
    switch (activeCategory) {
      case ParentServiceCategory.examScore:
        if (allExams.isEmpty) return const SizedBox.shrink();
        final ExamModel currentExam =
            (selectedExam != null && allExams.contains(selectedExam))
                ? selectedExam!
                : allExams.first;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: DropdownButtonFormField<ExamModel>(
            key: ValueKey('waexam_${currentExam.id}'),
            initialValue: currentExam,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'اختر الامتحان المطلوب إرسال درجاته',
              prefixIcon: const Icon(Icons.military_tech, size: 20),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: allExams
                .map((exam) => DropdownMenuItem(
                    value: exam,
                    child: Text('${exam.title} (من ${exam.maxScore})',
                        overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => selectedExam = value);
              widget.database.getExamScoresForExam(value.id).then((scores) {
                if (!mounted || selectedExam?.id != value.id) return;
                setState(() => selectedExamScores = scores);
                _syncCustomMessageBuffer();
              });
            },
          ),
        );

      case ParentServiceCategory.holisticReport:
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('فترة التقرير',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: StudentReportPeriod.values.map((period) {
                  final selected = _reportPeriod == period;
                  final label = switch (period) {
                    StudentReportPeriod.session => 'الحصة الأخيرة',
                    StudentReportPeriod.weekly => 'أسبوعي • 7 أيام',
                    StudentReportPeriod.monthly => 'شهري • 30 يومًا',
                  };
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (value) {
                      if (!value) return;
                      setState(() {
                        _reportPeriod = period;
                        isEditingCustomText = false;
                      });
                      _syncCustomMessageBuffer();
                    },
                  );
                }).toList(),
              ),
              if (_reportPeriod == StudentReportPeriod.weekly) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.assessment_rounded, color: Color(0xFF0284C7), size: 20),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'إرسال التقرير الأسبوعي الشامل 📊',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'تقرير أكاديمي وتربوي ذكي، يفحص السجل ويتجاهل تلقائياً من تم إرسال تقرير له هذا الأسبوع، وخالٍ تماماً من أي ماليات.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                          label: const Text('بدء الإرسال الأسبوعي لكافة أولياء الأمور', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                          onPressed: _startWeeklyReportBulkDispatch,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_reportPeriod == StudentReportPeriod.monthly) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.date_range_rounded, color: Color(0xFF8B5CF6), size: 20),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'إرسال التقرير الشهري الشامل (التعليمي والمالي) 📅',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'ملخص شامل لمسيرة ونمو الطالب التعليمي خلال الشهر مدمجاً معه الموقف المالي وحالة السداد، مع مراجعة السجل لمنع أي تكرار.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.rocket_launch_rounded, size: 16, color: Colors.white),
                          label: const Text('بدء الإرسال الشهري لكافة أولياء الأمور', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                          onPressed: _startMonthlyReportBulkDispatch,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_isLoadingStudentReport) ...[
                const SizedBox(height: 8),
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('جارٍ تحميل سجل الطالب...',
                        style: TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ],
          ),
        );

      case ParentServiceCategory.financialReceipt:
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('مطالبة بالمتأخرات'),
                selected: isDueReminderMode,
                onSelected: (val) {
                  setState(() => isDueReminderMode = true);
                  _syncCustomMessageBuffer();
                },
              ),
              ChoiceChip(
                label: const Text('إيصال سداد إلكتروني'),
                selected: !isDueReminderMode,
                onSelected: (val) {
                  setState(() => isDueReminderMode = false);
                  _syncCustomMessageBuffer();
                },
              ),
            ],
          ),
        );

      case ParentServiceCategory.notebookBehavior:
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('اختر الملاحظة السلوكية أو عدلها:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'مستوى متميز وإشادة بالتركيز',
                  'التزام وانضباط ممتاز بالواجبات',
                  'يحتاج لمزيد من التركيز والانتباه',
                  'سلوك غير منضبط وتشتت في الحصة',
                ].map((chip) {
                  final isSel = behaviorNote == chip;
                  return ChoiceChip(
                    label: Text(chip, style: const TextStyle(fontSize: 11)),
                    selected: isSel,
                    onSelected: (val) {
                      setState(() => behaviorNote = chip);
                      _syncCustomMessageBuffer();
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );

      case ParentServiceCategory.sessionCancellation:
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final teacherReasons = [
          'ظرف طارئ واعتذار عن الحصة المقررة اليوم',
          'وعكة صحية مفاجئة للمدرس',
          'إجازة رسمية / عطلة',
          'تعديل في جدول مواعيد المجموعة',
        ];
        final studentReasons = [
          'عذر مرضي وظرف صحي طارئ',
          'ظرف عائلي طارئ',
          'تعارض مع مواعيد الامتحانات المدرسية',
          'طلب ولي الأمر تأجيل الحصة',
        ];
        final makeupPresets = [
          'الحصة القادمة في نفس الموعد',
          'السبت القادم الساعة 4 عصراً',
          'سيتم التنسيق لتحديد الموعد لاحقاً',
        ];

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Segmented toggle: من جهة المعلم / من جهة الطالب
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFCBD5E1),
                  ),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (!isTeacherCancellation) {
                            setState(() {
                              isTeacherCancellation = true;
                              _cancelReasonController.text =
                                  teacherReasons.first;
                              isEditingCustomText = false;
                            });
                            _syncCustomMessageBuffer();
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: isTeacherCancellation
                                ? const Color(0xFF25D366)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: isTeacherCancellation
                                ? [
                                    BoxShadow(
                                        color: const Color(0xFF25D366)
                                            .withValues(alpha: 0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2))
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_pin_rounded,
                                size: 18,
                                color: isTeacherCancellation
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.black87),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'من جهة المعلم',
                                style: TextStyle(
                                  fontWeight: isTeacherCancellation
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isTeacherCancellation
                                      ? Colors.white
                                      : (isDark
                                          ? Colors.white70
                                          : Colors.black87),
                                  fontSize: 13,
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
                        onTap: () {
                          if (isTeacherCancellation) {
                            setState(() {
                              isTeacherCancellation = false;
                              _cancelReasonController.text =
                                  studentReasons.first;
                              isEditingCustomText = false;
                            });
                            _syncCustomMessageBuffer();
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: !isTeacherCancellation
                                ? const Color(0xFF25D366)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: !isTeacherCancellation
                                ? [
                                    BoxShadow(
                                        color: const Color(0xFF25D366)
                                            .withValues(alpha: 0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2))
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.school_rounded,
                                size: 18,
                                color: !isTeacherCancellation
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.black87),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'من جهة الطالب',
                                style: TextStyle(
                                  fontWeight: !isTeacherCancellation
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: !isTeacherCancellation
                                      ? Colors.white
                                      : (isDark
                                          ? Colors.white70
                                          : Colors.black87),
                                  fontSize: 13,
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
              const SizedBox(height: 10),

              // Description banner
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: (isTeacherCancellation
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFFA855F7))
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (isTeacherCancellation
                            ? const Color(0xFF38BDF8)
                            : const Color(0xFFA855F7))
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isTeacherCancellation
                          ? Icons.info_outline
                          : Icons.assignment_late_outlined,
                      size: 15,
                      color: isTeacherCancellation
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF9333EA),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isTeacherCancellation
                            ? 'إلغاء أو اعتذار من المعلم (للمجموعة بأكملها أو لطالب محدد).'
                            : 'إشعار وتوثيق اعتذار الطالب عن الحصة لولي أمره مع تحديد التعويض.',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Preset reasons chips
              Text(
                isTeacherCancellation
                    ? 'اختر سبب إلغاء الحصة (أو اكتب سبباً مخصصاً):'
                    : 'اختر سبب اعتذار الطالب:',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    (isTeacherCancellation ? teacherReasons : studentReasons)
                        .map((reason) {
                  final isSel = _cancelReasonController.text == reason;
                  return ChoiceChip(
                    label: Text(reason, style: const TextStyle(fontSize: 11)),
                    selected: isSel,
                    onSelected: (val) {
                      setState(() {
                        _cancelReasonController.text = reason;
                        isEditingCustomText = false;
                      });
                      _syncCustomMessageBuffer();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),

              // Reason TextField
              TextField(
                controller: _cancelReasonController,
                decoration: InputDecoration(
                  labelText: isTeacherCancellation
                      ? 'سبب الإلغاء / الاعتذار'
                      : 'سبب اعتذار الطالب',
                  prefixIcon: const Icon(Icons.edit_note, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (_) {
                  setState(() => isEditingCustomText = false);
                  _syncCustomMessageBuffer();
                },
              ),
              const SizedBox(height: 12),

              // Preset makeup chips
              const Text(
                'موعد الحصة البديلة / التعويضية:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: makeupPresets.map((preset) {
                  final isSel = _makeupDateController.text == preset;
                  return ChoiceChip(
                    label: Text(preset, style: const TextStyle(fontSize: 11)),
                    selected: isSel,
                    onSelected: (val) {
                      setState(() {
                        _makeupDateController.text = preset;
                        isEditingCustomText = false;
                      });
                      _syncCustomMessageBuffer();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),

              // Makeup date TextField
              TextField(
                controller: _makeupDateController,
                decoration: InputDecoration(
                  labelText: 'تفاصيل موعد الحصة البديلة / التعويضية',
                  hintText: 'اتركه فارغاً إذا كان سيتم التنسيق لاحقاً',
                  prefixIcon: const Icon(Icons.event_available, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (_) {
                  setState(() => isEditingCustomText = false);
                  _syncCustomMessageBuffer();
                },
              ),
            ],
          ),
        );

      case ParentServiceCategory.sessionReminder:
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final reminderPresets = [
          'إحضار كشكول الواجب 📓',
          'اختبار قصير في بداية الحصة ✍️',
          'مراجعة الدرس السابق بدقة 📖',
          'الالتزام بالحضور قبل الموعد بـ 10 دقائق ⏰',
          'سداد القسط / المستحقات المتأخرة 💳',
          'إحضار الآلة الحاسبة والأدوات الهندسية 📐',
        ];

        final isTodayMode = _groupMode == GroupSelectionMode.today;
        final isTomorrowMode = _groupMode == GroupSelectionMode.tomorrow;

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Segmented Toggle: حصة اليوم vs حصة الغد
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _groupMode = GroupSelectionMode.today;
                            if (todayGroups.isNotEmpty) {
                              selectedGroupId = todayGroups.first.id;
                            } else {
                              selectedGroupId = 'all';
                            }
                            final list = filteredStudents;
                            selectedStudent = list.isNotEmpty ? list.first : null;
                            isEditingCustomText = false;
                          });
                          _syncCustomMessageBuffer();
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: isTodayMode ? const Color(0xFF10B981) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: isTodayMode
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.today_rounded,
                                size: 18,
                                color: isTodayMode ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'حصة اليوم (${todayGroups.length})',
                                style: TextStyle(
                                  fontWeight: isTodayMode ? FontWeight.bold : FontWeight.normal,
                                  color: isTodayMode ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                  fontSize: 12.5,
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
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _groupMode = GroupSelectionMode.tomorrow;
                            if (tomorrowGroups.isNotEmpty) {
                              selectedGroupId = tomorrowGroups.first.id;
                            } else {
                              selectedGroupId = 'all';
                            }
                            final list = filteredStudents;
                            selectedStudent = list.isNotEmpty ? list.first : null;
                            isEditingCustomText = false;
                          });
                          _syncCustomMessageBuffer();
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: isTomorrowMode ? const Color(0xFFF59E0B) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: isTomorrowMode
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.alarm_rounded,
                                size: 18,
                                color: isTomorrowMode ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'حصة الغد (${tomorrowGroups.length})',
                                style: TextStyle(
                                  fontWeight: isTomorrowMode ? FontWeight.bold : FontWeight.normal,
                                  color: isTomorrowMode ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                  fontSize: 12.5,
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
              const SizedBox(height: 10),

              // Description banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: (isTodayMode ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (isTodayMode ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isTodayMode ? Icons.event_available_rounded : Icons.schedule_send_rounded,
                      size: 15,
                      color: isTodayMode ? const Color(0xFF10B981) : const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isTodayMode
                            ? 'إرسال تذكير بموعد حصة اليوم للطلاب المجدولين اليوم (${_getTodayArabicName()}).'
                            : 'إرسال تذكير مسبق بموعد حصة الغد للطلاب المجدولين غداً (${_getTomorrowArabicName()}).',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Preset reminder chips
              const Text(
                'تنبيهات وتوجيهات إضافية للحصة (اختياري):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: reminderPresets.map((preset) {
                  final isSel = _reminderExtraNoteController.text.contains(preset.split(' ').take(3).join(' '));
                  return ChoiceChip(
                    label: Text(preset, style: const TextStyle(fontSize: 11)),
                    selected: isSel,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _reminderExtraNoteController.text = preset;
                        } else {
                          _reminderExtraNoteController.clear();
                        }
                        isEditingCustomText = false;
                      });
                      _syncCustomMessageBuffer();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),

              // Extra Note TextField
              TextField(
                controller: _reminderExtraNoteController,
                decoration: InputDecoration(
                  labelText: 'ملاحظة خاصة بالتذكير (مثل: إحضار الواجب أو موعد إضافي)',
                  hintText: 'اتركه فارغاً للتذكير الافتراضي بموعد الحصة',
                  prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (_) {
                  setState(() => isEditingCustomText = false);
                  _syncCustomMessageBuffer();
                },
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildRecipientTargetSelector(bool isDark) {
    final activeStudent = selectedStudent ??
        (filteredStudents.isNotEmpty ? filteredStudents.first : null);

    final parentPhone = activeStudent?.parentPhone.trim() ?? '';
    final studentPhone = activeStudent?.studentPhone.trim() ?? '';

    final hasParentPhone = parentPhone.isNotEmpty;
    final hasStudentPhone = studentPhone.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.send_rounded, size: 16, color: Color(0xFF25D366)),
              const SizedBox(width: 6),
              const Text(
                'إرسال الرسالة إلى:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              if (activeStudent != null)
                Text(
                  _recipientTarget == WhatsAppRecipientTarget.parent
                      ? (hasParentPhone ? 'هاتف الولي: $parentPhone' : 'هاتف الولي غير مسجل ⚠️')
                      : (_recipientTarget == WhatsAppRecipientTarget.student
                          ? (hasStudentPhone ? 'هاتف الطالب: $studentPhone' : 'هاتف الطالب غير مسجل ⚠️')
                          : 'إرسال للرقمين معاً'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: (_recipientTarget == WhatsAppRecipientTarget.parent && !hasParentPhone) ||
                            (_recipientTarget == WhatsAppRecipientTarget.student && !hasStudentPhone)
                        ? Colors.orange.shade800
                        : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // 1. ولي الأمر
              Expanded(
                child: _buildRecipientCard(
                  isDark: isDark,
                  target: WhatsAppRecipientTarget.parent,
                  title: 'ولي الأمر',
                  phone: parentPhone,
                  icon: Icons.escalator_warning_rounded,
                ),
              ),
              const SizedBox(width: 8),

              // 2. الطالب
              Expanded(
                child: _buildRecipientCard(
                  isDark: isDark,
                  target: WhatsAppRecipientTarget.student,
                  title: 'الطالب',
                  phone: studentPhone,
                  icon: Icons.school_rounded,
                ),
              ),
              const SizedBox(width: 8),

              // 3. كلاهما
              Expanded(
                child: _buildRecipientCard(
                  isDark: isDark,
                  target: WhatsAppRecipientTarget.both,
                  title: 'كلاهما',
                  phone: 'الولي + الطالب',
                  icon: Icons.groups_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientCard({
    required bool isDark,
    required WhatsAppRecipientTarget target,
    required String title,
    required String phone,
    required IconData icon,
  }) {
    final isSelected = _recipientTarget == target;
    final hasPhone = phone.isNotEmpty;
    const primaryGreen = Color(0xFF25D366);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _recipientTarget = target;
        });
        if (!isEditingCustomText) {
          _syncCustomMessageBuffer();
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryGreen.withValues(alpha: isDark ? 0.22 : 0.12)
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? primaryGreen
                : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryGreen.withValues(alpha: 0.18),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? primaryGreen : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected
                        ? (isDark ? Colors.white : const Color(0xFF065F46))
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hasPhone ? phone : 'غير مسجل',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: !hasPhone
                    ? Colors.orange.shade800
                    : (isSelected
                        ? (isDark ? Colors.green.shade200 : const Color(0xFF047857))
                        : (isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
