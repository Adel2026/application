import 'dart:async';
import 'package:flutter/material.dart';

import '../core/app_locale.dart';
import '../core/contact_picker_service.dart';
import '../core/database/database_service.dart';
import '../core/notification_service.dart';
import '../core/schedule_conflict_service.dart';
import '../core/security_service.dart';
import '../core/whatsapp_service.dart';
import '../models/group_model.dart';
import '../models/exceptional_session_model.dart';
import '../models/student_model.dart';
import '../models/curriculum_model.dart';
import '../widgets/section_top_bar.dart';
import 'today_attendance_screen.dart';
import 'curriculum_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.database, this.onBack});
  final DatabaseService database;
  final VoidCallback? onBack;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<GroupModel> groups = [];
  List<ExceptionalSessionModel> exceptionalSessions = [];
  Map<String, int> groupStudentCounts = {};
  Map<String, Map<String, dynamic>> groupBindings = {};
  Map<String, GroupCurriculumProgress> groupProgressMap = {};
  Map<String, List<StudentModel>> groupStudentsMap = {};
  bool isLoading = true;
  StreamSubscription<DataChangeEvent>? _dataSub;

  // Smart Search & Filter States
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedGradeFilter;
  String? _selectedDayFilter;
  String? _selectedStatusFilter; // 'active', 'inactive', 'conflict'
  final Map<String, String?> _matchedReasons = {};

  final List<String> weekDays = [
    'السبت',
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadGroups();
    _dataSub = widget.database.onDataChanged.listen((event) {
      if (event == DataChangeEvent.groups ||
          event == DataChangeEvent.students ||
          event == DataChangeEvent.curriculum ||
          event == DataChangeEvent.attendance ||
          event == DataChangeEvent.all) {
        if (mounted) _loadGroups();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dataSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    if (groups.isEmpty) {
      setState(() => isLoading = true);
    }
    final fetched = await widget.database.getGroups();
    final allStudents = await widget.database.getStudents();
    final rawBindings = await widget.database.getGroupCurriculumBindings();
    final exSessions = await widget.database.getExceptionalSessions(
      status: 'active',
    );
    final gProgress = await widget.database.getGroupsCurriculumProgressMap();

    final counts = <String, int>{};
    final gStudentsMap = <String, List<StudentModel>>{};
    for (final s in allStudents) {
      if (s.groupId != null && s.groupId!.isNotEmpty) {
        counts[s.groupId!] = (counts[s.groupId!] ?? 0) + 1;
        gStudentsMap.putIfAbsent(s.groupId!, () => []).add(s);
      }
    }

    final bMap = <String, Map<String, dynamic>>{};
    for (final b in rawBindings) {
      final gId = b['id'] as String;
      bMap[gId] = b;
    }

    if (mounted) {
      setState(() {
        groups = fetched;
        exceptionalSessions = exSessions;
        groupStudentCounts = counts;
        groupBindings = bMap;
        groupProgressMap = gProgress;
        groupStudentsMap = gStudentsMap;
        isLoading = false;
      });
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  TimeOfDay _parseTimeOfDay(
    String timeStr, {
    TimeOfDay fallback = const TimeOfDay(hour: 15, minute: 0),
  }) {
    try {
      final parts = timeStr.trim().split(' ');
      if (parts.length >= 2) {
        final timeParts = parts[0].split(':');
        int hour = int.parse(timeParts[0]);
        final minute = int.parse(timeParts[1]);
        final period = parts[1].toUpperCase();
        if (period == 'PM' && hour < 12) hour += 12;
        if (period == 'AM' && hour == 12) hour = 0;
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (_) {}
    return fallback;
  }

  void _showGroupDialog({GroupModel? existing}) async {
    final allAcademyStudents = await widget.database.getStudents();
    final initialEnrolled = existing != null
        ? allAcademyStudents.where((s) => s.groupId == existing.id).toList()
        : <StudentModel>[];

    if (!mounted) return;

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final roomCtrl = TextEditingController(text: existing?.room ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null && existing.monthlyPrice > 0
          ? existing.monthlyPrice.toStringAsFixed(0)
          : '',
    );
    final maxStudentsCtrl = TextEditingController(
      text: existing != null && existing.maxStudents > 0
          ? existing.maxStudents.toString()
          : '',
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');

    String grade =
        existing != null &&
            existing.grade.isNotEmpty &&
            existing.grade != 'مراحل متعددة'
        ? existing.grade
        : (initialEnrolled.firstOrNull?.grade ?? 'الصف الأول الثانوي (Sec 1)');
    String stage = existing != null && existing.stage != 'نظام إخوة'
        ? existing.stage
        : (initialEnrolled.firstOrNull?.stage ?? 'الثانوية العامة');

    // Helper: ربط المادة بالمرحلة (ICT لابتدائي وإعدادي، وبرمجة لثانوي)
    String resolveSubjectForGrade(String g) {
      if (g.contains('الثانوي') || g.contains('Sec')) {
        return 'برمجة';
      } else if (g.contains('الإعدادي') ||
          g.contains('Prep') ||
          g.contains('الابتدائي') ||
          g.contains('Pri')) {
        return 'ICT';
      }
      return 'برمجة';
    }

    final existingSubject = existing?.subject ?? '';
    String subject = existingSubject.contains('تكنولوجيا')
        ? 'ICT'
        : existingSubject.isNotEmpty
        ? existingSubject
        : resolveSubjectForGrade(grade);
    final subjectCtrl = TextEditingController(text: subject);

    String locationType = existing != null && existing.locationType.isNotEmpty
        ? existing.locationType
        : 'منزل المعلم أو الطالب';
    String billingType = existing != null && existing.billingType.isNotEmpty
        ? existing.billingType
        : 'per_session';
    int selectedColor = existing != null && existing.colorValue != 0
        ? existing.colorValue
        : 0xFF2563EB;

    String startTime = existing != null && existing.startTime.isNotEmpty
        ? existing.startTime
        : '03:00 PM';
    String endTime = existing != null && existing.endTime.isNotEmpty
        ? existing.endTime
        : '04:00 PM';
    bool isActive = existing?.isActive ?? true;
    bool differentTimePerDay = false;
    final Map<String, String> dayStartTimes = {};
    final Map<String, String> dayEndTimes = {};

    // Selected weekdays
    final List<String> daysList = [
      'السبت',
      'الأحد',
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
    ];

    Set<String> selectedDays = {};
    if (existing != null && existing.days.isNotEmpty) {
      final rawParts = existing.days
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);
      const numToDayMap = {
        '1': 'الاثنين',
        '2': 'الثلاثاء',
        '3': 'الأربعاء',
        '4': 'الخميس',
        '5': 'الجمعة',
        '6': 'السبت',
        '7': 'الأحد',
        '0': 'الأحد',
      };
      for (final part in rawParts) {
        if (numToDayMap.containsKey(part)) {
          selectedDays.add(numToDayMap[part]!);
        } else {
          selectedDays.add(part);
        }
      }
    }
    if (existing != null && existing.schedule.isNotEmpty) {
      for (final d in daysList) {
        if (existing.schedule.contains(d)) selectedDays.add(d);
      }
    }

    // Initialize per-day times
    for (final d in daysList) {
      dayStartTimes[d] = startTime;
      dayEndTimes[d] = endTime;
    }

    // Check if existing schedule has per-day timing format: "السبت (03:00 PM - 04:00 PM)"
    if (existing != null && existing.schedule.contains('(')) {
      differentTimePerDay = true;
      for (final d in daysList) {
        final match = RegExp(
          d + r'\s*\(([^-\)]+)\s*-\s*([^\)]+)\)',
        ).firstMatch(existing.schedule);
        if (match != null) {
          dayStartTimes[d] = match.group(1)?.trim() ?? startTime;
          dayEndTimes[d] = match.group(2)?.trim() ?? endTime;
        }
      }
    }

    // Currently linked enrolled students
    final List<StudentModel> enrolledStudents = List.from(initialEnrolled);

    final List<int> palette = [
      0xFF6366F1, // Indigo
      0xFF06B6D4, // Cyan
      0xFFE11D48, // Rose
      0xFFF97316, // Orange
      0xFF8B5CF6, // Purple
      0xFF10B981, // Emerald
      0xFF2563EB, // Royal Blue
    ];

    final List<String> gradeOptions = [
      'الصف الرابع الابتدائي (Pri 4)',
      'الصف الخامس الابتدائي (Pri 5)',
      'الصف السادس الابتدائي (Pri 6)',
      'الصف الأول الإعدادي (Prep 1)',
      'الصف الثاني الإعدادي (Prep 2)',
      'الصف الثالث الإعدادي (Prep 3)',
      'الصف الأول الثانوي (Sec 1)',
      'الصف الثاني الثانوي (Sec 2)',
      'الصف الثالث الثانوي (Sec 3)',
      'كورس حر / تعليم مستمر',
    ];

    final List<String> subjectOptions = ['برمجة', 'ICT'];

    final List<String> locationOptions = [
      'منزل المعلم أو الطالب',
      'السنتر / القاعة',
      'أونلاين (عن بعد)',
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final double currentRate =
                double.tryParse(priceCtrl.text.trim()) ?? 0;
            final int daysCount = selectedDays.length;
            final double approxMonthly = billingType == 'per_session'
                ? currentRate * (daysCount > 0 ? daysCount : 2) * 4
                : currentRate;

            final sortedSelectedDays = daysList
                .where((d) => selectedDays.contains(d))
                .toList();

            // Real-time Schedule Conflict Check (فحص تعارض المواعيد الحي)
            final currentConflicts =
                ScheduleConflictService.checkProposedGroupConflicts(
                  currentGroupId: existing?.id,
                  proposedGroupName: nameCtrl.text.trim(),
                  proposedDays: sortedSelectedDays,
                  proposedStartTime: startTime,
                  proposedEndTime: endTime,
                  dayStartTimes: differentTimePerDay ? dayStartTimes : null,
                  dayEndTimes: differentTimePerDay ? dayEndTimes : null,
                  allGroups: groups,
                  exceptionalSessions: exceptionalSessions,
                );

            return Directionality(
              textDirection: AppLocale.isArabic(context)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.94,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF0C1322),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: Color(0xFF243656), width: 1.5),
                  ),
                ),
                child: Column(
                  children: [
                    // --- Header Bar matching target design ---
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0xFF1E2D4A),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Color(
                                selectedColor,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.layers_rounded,
                              color: Color(selectedColor),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            existing == null ? 'مجموعة جديدة' : 'تعديل مجموعة',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF16233B),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.all(6),
                            ),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF94A3B8),
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),

                    // --- Scrollable Form Body ---
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          MediaQuery.of(ctx).viewInsets.bottom + 24,
                        ),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 0. حالة المجموعة (نشطة / متوقفة)
                              Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: (isActive ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: (isActive ? Colors.green : Colors.orange).withValues(alpha: 0.35),
                                  ),
                                ),
                                child: SwitchListTile(
                                  value: isActive,
                                  onChanged: (val) => setModalState(() => isActive = val),
                                  activeThumbColor: Colors.green,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                  title: Text(
                                    isActive ? 'حالة المجموعة: نشطة 🟢' : 'حالة المجموعة: متوقفة مؤقتاً ⏸️',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                      color: isActive ? Colors.green.shade400 : Colors.orange.shade400,
                                    ),
                                  ),
                                  subtitle: Text(
                                    isActive ? 'المجموعة نشطة وتظهر في جدول الحصص اليومي' : 'المجموعة متوقفة ومحفوظة دون حذف بياناتها',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                  ),
                                ),
                              ),

                              // 1. اسم المجموعة *
                              Row(
                                children: const [
                                  Text(
                                    'اسم المجموعة',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '*',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: nameCtrl,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'ادخل اسم المجموعة',
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 13,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF131D31),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF243656),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF243656),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF38BDF8),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'برجاء كتابة اسم المجموعة'
                                    : null,
                              ),
                              const SizedBox(height: 14),

                              // 2. Row: المرحلة / الصف الدراسي & المادة الدراسية (مربوطة بالمرحلة) - مخفية في مجموعة الأخوات
                              ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // المرحلة / الصف الدراسي (Right side in RTL)
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Expanded(
                                                child: Text(
                                                  'المرحلة / الصف',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFFCBD5E1),
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0x1F06B6D4,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'تحدد المادة',
                                                  style: TextStyle(
                                                    color: Color(0xFF38BDF8),
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF131D31),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: const Color(0xFF243656),
                                              ),
                                            ),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value:
                                                    gradeOptions.contains(grade)
                                                    ? grade
                                                    : gradeOptions.first,
                                                isExpanded: true,
                                                dropdownColor: const Color(
                                                  0xFF16233B,
                                                ),
                                                icon: const Icon(
                                                  Icons
                                                      .keyboard_arrow_down_rounded,
                                                  color: Color(0xFF94A3B8),
                                                  size: 20,
                                                ),
                                                items: gradeOptions.map((g) {
                                                  return DropdownMenuItem(
                                                    value: g,
                                                    child: Text(
                                                      g,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12.5,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  );
                                                }).toList(),
                                                onChanged: (v) {
                                                  if (v != null) {
                                                    setModalState(() {
                                                      grade = v;
                                                      // الربط التلقائي: ثانوي -> برمجة | ابتدائي وإعدادي -> ICT
                                                      subject =
                                                          resolveSubjectForGrade(
                                                            v,
                                                          );
                                                      subjectCtrl.text =
                                                          subject;

                                                      if (v.contains(
                                                        'الثانوي',
                                                      )) {
                                                        stage =
                                                            'الثانوية العامة';
                                                      } else if (v.contains(
                                                        'الإعدادي',
                                                      )) {
                                                        stage =
                                                            'المرحلة الإعدادية';
                                                      } else if (v.contains(
                                                        'الابتدائي',
                                                      )) {
                                                        stage =
                                                            'المرحلة الابتدائية';
                                                      } else {
                                                        stage = 'عام';
                                                      }
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),

                                    // المادة الدراسية (Left side in RTL)
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Expanded(
                                                child: Text(
                                                  'المادة الدراسية',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFFCBD5E1),
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: subject == 'برمجة'
                                                      ? const Color(0x262563EB)
                                                      : const Color(0x2610B981),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: subject == 'برمجة'
                                                        ? const Color(
                                                            0x553B82F6,
                                                          )
                                                        : const Color(
                                                            0x5510B981,
                                                          ),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: Text(
                                                  subject == 'برمجة'
                                                      ? 'ثانوي'
                                                      : 'ابتدائي/إعدادي',
                                                  style: TextStyle(
                                                    color: subject == 'برمجة'
                                                        ? const Color(
                                                            0xFF60A5FA,
                                                          )
                                                        : const Color(
                                                            0xFF34D399,
                                                          ),
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF131D31),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: const Color(0xFF243656),
                                              ),
                                            ),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value:
                                                    subjectOptions.contains(
                                                      subject,
                                                    )
                                                    ? subject
                                                    : subjectOptions.first,
                                                isExpanded: true,
                                                dropdownColor: const Color(
                                                  0xFF16233B,
                                                ),
                                                icon: const Icon(
                                                  Icons
                                                      .keyboard_arrow_down_rounded,
                                                  color: Color(0xFF94A3B8),
                                                  size: 20,
                                                ),
                                                items: subjectOptions.map((
                                                  sub,
                                                ) {
                                                  return DropdownMenuItem(
                                                    value: sub,
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          sub == 'برمجة'
                                                              ? Icons
                                                                    .code_rounded
                                                              : Icons
                                                                    .computer_rounded,
                                                          size: 16,
                                                          color: sub == 'برمجة'
                                                              ? const Color(
                                                                  0xFF38BDF8,
                                                                )
                                                              : const Color(
                                                                  0xFF10B981,
                                                                ),
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Text(
                                                          sub,
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }).toList(),
                                                onChanged: (v) {
                                                  if (v != null) {
                                                    setModalState(() {
                                                      subject = v;
                                                      subjectCtrl.text = v;
                                                    });
                                                  }
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ],

                              // 3. Row: مكان انعقاد الحصة & تفاصيل المكان / اسم القاعة
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // مكان انعقاد الحصة
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'مكان انعقاد الحصة',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFCBD5E1),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF131D31),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFF243656),
                                            ),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value:
                                                  locationOptions.contains(
                                                    locationType,
                                                  )
                                                  ? locationType
                                                  : locationOptions.first,
                                              isExpanded: true,
                                              dropdownColor: const Color(
                                                0xFF16233B,
                                              ),
                                              icon: const Icon(
                                                Icons
                                                    .keyboard_arrow_down_rounded,
                                                color: Color(0xFF94A3B8),
                                                size: 20,
                                              ),
                                              items: locationOptions.map((loc) {
                                                return DropdownMenuItem(
                                                  value: loc,
                                                  child: Text(
                                                    loc,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                );
                                              }).toList(),
                                              onChanged: (v) {
                                                if (v != null)
                                                  setModalState(
                                                    () => locationType = v,
                                                  );
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // تفاصيل المكان / اسم القاعة
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'تفاصيل المكان / اسم القاعة',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFCBD5E1),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        TextFormField(
                                          controller: roomCtrl,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                          ),
                                          decoration: InputDecoration(
                                            hintText:
                                                'ادخل تفاصيل المكان أو القاعة',
                                            hintStyle: const TextStyle(
                                              color: Color(0xFF64748B),
                                              fontSize: 12,
                                            ),
                                            filled: true,
                                            fillColor: const Color(0xFF131D31),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 11,
                                                ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: const BorderSide(
                                                color: Color(0xFF243656),
                                              ),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: const BorderSide(
                                                color: Color(0xFF243656),
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: const BorderSide(
                                                color: Color(0xFF38BDF8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // 4. أيام مواعيد الحصص أسبوعياً
                              Row(
                                children: [
                                  const Text(
                                    'أيام مواعيد الحصص أسبوعياً',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (selectedDays.isNotEmpty)
                                    Text(
                                      '${selectedDays.length} أيام مختارة',
                                      style: const TextStyle(
                                        color: Color(0xFF38BDF8),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                                  children: daysList.map((day) {
                                    final isSelected = selectedDays.contains(
                                      day,
                                    );
                                    return Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        end: 6,
                                      ),
                                      child: InkWell(
                                        onTap: () {
                                          setModalState(() {
                                            if (isSelected) {
                                              selectedDays.remove(day);
                                            } else {
                                              selectedDays.add(day);
                                              dayStartTimes[day] ??= startTime;
                                              dayEndTimes[day] ??= endTime;
                                            }
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(10),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 13,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF2563EB)
                                                : const Color(0xFF141F35),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFF3B82F6)
                                                  : const Color(0xFF263753),
                                              width: 1,
                                            ),
                                            boxShadow: isSelected
                                                ? [
                                                    const BoxShadow(
                                                      color: Color(0x402563EB),
                                                      blurRadius: 6,
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Text(
                                            day,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                  : const Color(0xFF94A3B8),
                                              fontSize: 12.5,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // 5. Card: مواعيد وتوقيت الحصص (مع دعم موعد مختلف لكل يوم بالكامل!)
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10192C),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFF1F304E),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.access_time_rounded,
                                          color: Color(0xFF60A5FA),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'مواعيد وتوقيت الحصص',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Spacer(),
                                        // Checkbox: تحديد موعد مختلف لكل يوم
                                        InkWell(
                                          onTap: () {
                                            setModalState(() {
                                              differentTimePerDay =
                                                  !differentTimePerDay;
                                              for (final d in selectedDays) {
                                                dayStartTimes[d] ??= startTime;
                                                dayEndTimes[d] ??= endTime;
                                              }
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 180,
                                                  ),
                                                  width: 18,
                                                  height: 18,
                                                  decoration: BoxDecoration(
                                                    color: differentTimePerDay
                                                        ? const Color(
                                                            0xFF2563EB,
                                                          )
                                                        : const Color(
                                                            0xFF16233B,
                                                          ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          5,
                                                        ),
                                                    border: Border.all(
                                                      color: differentTimePerDay
                                                          ? const Color(
                                                              0xFF60A5FA,
                                                            )
                                                          : const Color(
                                                              0xFF3B82F6,
                                                            ),
                                                      width: 1.2,
                                                    ),
                                                  ),
                                                  child: differentTimePerDay
                                                      ? const Icon(
                                                          Icons.check,
                                                          color: Colors.white,
                                                          size: 13,
                                                        )
                                                      : null,
                                                ),
                                                const SizedBox(width: 7),
                                                Text(
                                                  'مواعيد مخصصة',
                                                  style: TextStyle(
                                                    color: differentTimePerDay
                                                        ? Colors.white
                                                        : const Color(
                                                            0xFF94A3B8,
                                                          ),
                                                    fontSize: 11.5,
                                                    fontWeight:
                                                        differentTimePerDay
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // إذا كان الخيار غير مفعل: عرض توقيت موحد لجميع الأيام
                                    if (!differentTimePerDay)
                                      Row(
                                        children: [
                                          // وقت البداية لجميع الأيام
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'وقت البداية لجميع الأيام',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: Color(0xFFCBD5E1),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                InkWell(
                                                  onTap: () async {
                                                    final initial =
                                                        _parseTimeOfDay(
                                                          startTime,
                                                        );
                                                    final picked =
                                                        await showTimePicker(
                                                          context: ctx,
                                                          initialTime: initial,
                                                        );
                                                    if (picked != null) {
                                                      setModalState(
                                                        () => startTime =
                                                            _formatTimeOfDay(
                                                              picked,
                                                            ),
                                                      );
                                                    }
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFF142036,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFF243656,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Text(
                                                          startTime,
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 13,
                                                              ),
                                                        ),
                                                        const Spacer(),
                                                        const Icon(
                                                          Icons.access_time,
                                                          color: Color(
                                                            0xFF64748B,
                                                          ),
                                                          size: 17,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),

                                          // وقت الانتهاء لجميع الأيام
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'وقت الانتهاء لجميع الأيام',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: Color(0xFFCBD5E1),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                InkWell(
                                                  onTap: () async {
                                                    final initial =
                                                        _parseTimeOfDay(
                                                          endTime,
                                                          fallback:
                                                              const TimeOfDay(
                                                                hour: 16,
                                                                minute: 0,
                                                              ),
                                                        );
                                                    final picked =
                                                        await showTimePicker(
                                                          context: ctx,
                                                          initialTime: initial,
                                                        );
                                                    if (picked != null) {
                                                      setModalState(
                                                        () => endTime =
                                                            _formatTimeOfDay(
                                                              picked,
                                                            ),
                                                      );
                                                    }
                                                  },
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFF142036,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFF243656,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Text(
                                                          endTime,
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 13,
                                                              ),
                                                        ),
                                                        const Spacer(),
                                                        const Icon(
                                                          Icons.access_time,
                                                          color: Color(
                                                            0xFF64748B,
                                                          ),
                                                          size: 17,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    // إذا تم تفعيل "تحديد موعد مختلف لكل يوم":
                                    else if (sortedSelectedDays.isEmpty)
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF142036),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFF243656),
                                          ),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline_rounded,
                                              color: Color(0xFF38BDF8),
                                              size: 18,
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'الرجاء اختيار أيام الحصص أسبوعياً أولاً من الأعلى لتخصيص توقيت كل يوم.',
                                                style: TextStyle(
                                                  color: Color(0xFF94A3B8),
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Column(
                                        children: sortedSelectedDays.map((d) {
                                          final dStart =
                                              dayStartTimes[d] ?? startTime;
                                          final dEnd =
                                              dayEndTimes[d] ?? endTime;

                                          return Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 10,
                                            ),
                                            padding: const EdgeInsets.all(11),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF142036),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: const Color(0xFF243656),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 3,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0x332563EB,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                        border: Border.all(
                                                          color: const Color(
                                                            0x663B82F6,
                                                          ),
                                                          width: 0.8,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .event_available_rounded,
                                                            size: 13,
                                                            color: Color(
                                                              0xFF60A5FA,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 5,
                                                          ),
                                                          Text(
                                                            'حصة يوم $d',
                                                            style:
                                                                const TextStyle(
                                                                  color: Color(
                                                                    0xFF60A5FA,
                                                                  ),
                                                                  fontSize:
                                                                      11.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    // وقت البداية لهذا اليوم
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          const Text(
                                                            'وقت البداية',
                                                            style: TextStyle(
                                                              fontSize: 10.5,
                                                              color: Color(
                                                                0xFF94A3B8,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          InkWell(
                                                            onTap: () async {
                                                              final initial =
                                                                  _parseTimeOfDay(
                                                                    dStart,
                                                                  );
                                                              final picked =
                                                                  await showTimePicker(
                                                                    context:
                                                                        ctx,
                                                                    initialTime:
                                                                        initial,
                                                                  );
                                                              if (picked !=
                                                                  null) {
                                                                setModalState(
                                                                  () => dayStartTimes[d] =
                                                                      _formatTimeOfDay(
                                                                        picked,
                                                                      ),
                                                                );
                                                              }
                                                            },
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical: 8,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    const Color(
                                                                      0xFF0F172A,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                                border: Border.all(
                                                                  color: const Color(
                                                                    0xFF243656,
                                                                  ),
                                                                ),
                                                              ),
                                                              child: Row(
                                                                children: [
                                                                  Text(
                                                                    dStart,
                                                                    style: const TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                                  ),
                                                                  const Spacer(),
                                                                  const Icon(
                                                                    Icons
                                                                        .access_time,
                                                                    color: Color(
                                                                      0xFF64748B,
                                                                    ),
                                                                    size: 15,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),

                                                    // وقت الانتهاء لهذا اليوم
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          const Text(
                                                            'وقت الانتهاء',
                                                            style: TextStyle(
                                                              fontSize: 10.5,
                                                              color: Color(
                                                                0xFF94A3B8,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          InkWell(
                                                            onTap: () async {
                                                              final initial =
                                                                  _parseTimeOfDay(
                                                                    dEnd,
                                                                    fallback:
                                                                        const TimeOfDay(
                                                                          hour:
                                                                              16,
                                                                          minute:
                                                                              0,
                                                                        ),
                                                                  );
                                                              final picked =
                                                                  await showTimePicker(
                                                                    context:
                                                                        ctx,
                                                                    initialTime:
                                                                        initial,
                                                                  );
                                                              if (picked !=
                                                                  null) {
                                                                setModalState(
                                                                  () => dayEndTimes[d] =
                                                                      _formatTimeOfDay(
                                                                        picked,
                                                                      ),
                                                                );
                                                              }
                                                            },
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical: 8,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    const Color(
                                                                      0xFF0F172A,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                                border: Border.all(
                                                                  color: const Color(
                                                                    0xFF243656,
                                                                  ),
                                                                ),
                                                              ),
                                                              child: Row(
                                                                children: [
                                                                  Text(
                                                                    dEnd,
                                                                    style: const TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                                  ),
                                                                  const Spacer(),
                                                                  const Icon(
                                                                    Icons
                                                                        .access_time,
                                                                    color: Color(
                                                                      0xFF64748B,
                                                                    ),
                                                                    size: 15,
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
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                  ],
                                ),
                              ),

                              // تنبيه تعارض المواعيد الحي داخل الديالوج (Live Schedule Conflict Alert)
                              if (currentConflicts.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                ScheduleConflictService.buildConflictWarningBanner(
                                  conflicts: currentConflicts,
                                  context: modalContext,
                                ),
                              ],

                              const SizedBox(height: 14),

                              // 6. Card: نظام حساب واشتراك المجموعة (مخفي في مجموعة الأخوات)
                              ...[
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10192C),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFF1F304E),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'نظام حساب واشتراك المجموعة (اختر إما بالشهر أو بالحصة):',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0x260284C7),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: const Color(0x5538BDF8),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Text(
                                              billingType == 'per_session'
                                                  ? 'نظام الحساب بالحصة مفعل'
                                                  : 'نظام الحساب الشهري مفعل',
                                              style: const TextStyle(
                                                color: Color(0xFF38BDF8),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Two Radio selection cards
                                      Row(
                                        children: [
                                          // Option A: حساب بالحصة
                                          Expanded(
                                            child: InkWell(
                                              onTap: () => setModalState(
                                                () =>
                                                    billingType = 'per_session',
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  11,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      billingType ==
                                                          'per_session'
                                                      ? const Color(0xFF132247)
                                                      : const Color(0xFF131D31),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color:
                                                        billingType ==
                                                            'per_session'
                                                        ? const Color(
                                                            0xFF2563EB,
                                                          )
                                                        : const Color(
                                                            0xFF243656,
                                                          ),
                                                    width:
                                                        billingType ==
                                                            'per_session'
                                                        ? 1.5
                                                        : 1,
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          billingType ==
                                                                  'per_session'
                                                              ? Icons
                                                                    .radio_button_checked
                                                              : Icons
                                                                    .radio_button_unchecked,
                                                          color:
                                                              billingType ==
                                                                  'per_session'
                                                              ? const Color(
                                                                  0xFF38BDF8,
                                                                )
                                                              : const Color(
                                                                  0xFF64748B,
                                                                ),
                                                          size: 18,
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        const Expanded(
                                                          child: Text(
                                                            'حساب بالحصة (بالحضور)',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    const Text(
                                                      'محاسبة متغيرة بناءً على عدد الحصص المحضورة',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFF94A3B8,
                                                        ),
                                                        fontSize: 10,
                                                      ),
                                                      maxLines: 2,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),

                                          // Option B: حساب شهري
                                          Expanded(
                                            child: InkWell(
                                              onTap: () => setModalState(
                                                () => billingType = 'monthly',
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  11,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      billingType == 'monthly'
                                                      ? const Color(0xFF132247)
                                                      : const Color(0xFF131D31),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color:
                                                        billingType == 'monthly'
                                                        ? const Color(
                                                            0xFF2563EB,
                                                          )
                                                        : const Color(
                                                            0xFF243656,
                                                          ),
                                                    width:
                                                        billingType == 'monthly'
                                                        ? 1.5
                                                        : 1,
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          billingType ==
                                                                  'monthly'
                                                              ? Icons
                                                                    .radio_button_checked
                                                              : Icons
                                                                    .radio_button_unchecked,
                                                          color:
                                                              billingType ==
                                                                  'monthly'
                                                              ? const Color(
                                                                  0xFF38BDF8,
                                                                )
                                                              : const Color(
                                                                  0xFF64748B,
                                                                ),
                                                          size: 18,
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        const Expanded(
                                                          child: Text(
                                                            'حساب شهري (بالشهر)',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    const Text(
                                                      'اشتراك شهري ثابت يُدفع شهرياً لكل طالب',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFF94A3B8,
                                                        ),
                                                        fontSize: 10,
                                                      ),
                                                      maxLines: 2,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Sub-row: Rate & Capacity
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Price Field
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        billingType ==
                                                                'per_session'
                                                            ? 'سعر الحصة الفردية *'
                                                            : 'الاشتراك الشهري *',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                            0xFFCBD5E1,
                                                          ),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    if (billingType ==
                                                        'per_session') ...[
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '≈ ${approxMonthly.toStringAsFixed(0)} /شهر',
                                                        style: const TextStyle(
                                                          color: Color(
                                                            0xFF38BDF8,
                                                          ),
                                                          fontSize: 9.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                TextFormField(
                                                  controller: priceCtrl,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  onChanged: (_) =>
                                                      setModalState(() {}),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  decoration: InputDecoration(
                                                    hintText: 'ادخل السعر',
                                                    hintStyle: const TextStyle(
                                                      color: Color(0xFF64748B),
                                                      fontSize: 12,
                                                    ),
                                                    filled: true,
                                                    fillColor: const Color(
                                                      0xFF131D31,
                                                    ),
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 10,
                                                        ),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      borderSide:
                                                          const BorderSide(
                                                            color: Color(
                                                              0xFF243656,
                                                            ),
                                                          ),
                                                    ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                          borderSide:
                                                              const BorderSide(
                                                                color: Color(
                                                                  0xFF243656,
                                                                ),
                                                              ),
                                                        ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                          borderSide:
                                                              const BorderSide(
                                                                color: Color(
                                                                  0xFF38BDF8,
                                                                ),
                                                              ),
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  billingType == 'per_session'
                                                      ? 'يتم ضرب هذا السعر في عدد الحصص المحضورة عند تحصيل الحساب.'
                                                      : 'يتم تحصيل هذا المبلغ شهرياً لكل طالب مسجل.',
                                                  style: const TextStyle(
                                                    color: Color(0xFF64748B),
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),

                                          // Max Capacity Field
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'الحد الأقصى للطلاب بالمجموعة',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFFCBD5E1),
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 6),
                                                TextFormField(
                                                  controller: maxStudentsCtrl,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  decoration: InputDecoration(
                                                    hintText:
                                                        'الحد الأقصى للطلاب',
                                                    hintStyle: const TextStyle(
                                                      color: Color(0xFF64748B),
                                                      fontSize: 12,
                                                    ),
                                                    filled: true,
                                                    fillColor: const Color(
                                                      0xFF131D31,
                                                    ),
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 10,
                                                        ),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      borderSide:
                                                          const BorderSide(
                                                            color: Color(
                                                              0xFF243656,
                                                            ),
                                                          ),
                                                    ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                          borderSide:
                                                              const BorderSide(
                                                                color: Color(
                                                                  0xFF243656,
                                                                ),
                                                              ),
                                                        ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                10,
                                                              ),
                                                          borderSide:
                                                              const BorderSide(
                                                                color: Color(
                                                                  0xFF38BDF8,
                                                                ),
                                                              ),
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                const Text(
                                                  'العدد الأقصى المسموح بتسكينه داخل هذه المجموعة.',
                                                  style: TextStyle(
                                                    color: Color(0xFF64748B),
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],

                              // 7. لون تمييز المجموعة في الجدول
                              const Text(
                                'لون تمييز المجموعة في الجدول',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: palette.map((col) {
                                  final isColSelected = selectedColor == col;
                                  return Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 10,
                                    ),
                                    child: InkWell(
                                      onTap: () => setModalState(
                                        () => selectedColor = col,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: Color(col),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isColSelected
                                                ? Colors.white
                                                : Colors.transparent,
                                            width: isColSelected ? 2.5 : 0,
                                          ),
                                          boxShadow: isColSelected
                                              ? [
                                                  BoxShadow(
                                                    color: Color(
                                                      col,
                                                    ).withValues(alpha: 0.6),
                                                    blurRadius: 10,
                                                    spreadRadius: 2,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: isColSelected
                                            ? const Center(
                                                child: Icon(
                                                  Icons.check,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 14),

                              // 8. ملاحظات إضافية
                              const Text(
                                'ملاحظات إضافية',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: notesCtrl,
                                maxLines: 3,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'شروط خاصة، أهداف المجموعة...',
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF131D31),
                                  contentPadding: const EdgeInsets.all(12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF243656),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF243656),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF38BDF8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // 9. Card: ربط وتسجيل الطلاب في المجموعة
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A1324),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFF1E2E4A),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: const Color(0x3310B981),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.people_alt_rounded,
                                            color: Color(0xFF10B981),
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'ربط وتسجيل الطلاب في المجموعة',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                'يمكنك تسكين الطلاب فورياً أو لاحقاً',
                                                style: TextStyle(
                                                  color: Color(0xFF94A3B8),
                                                  fontSize: 10.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0x260284C7),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: const Color(0x5538BDF8),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            '${enrolledStudents.length} / ${maxStudentsCtrl.text.isNotEmpty ? maxStudentsCtrl.text : "∞"}',
                                            style: const TextStyle(
                                              color: Color(0xFF38BDF8),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Currently enrolled student chips
                                    if (enrolledStudents.isNotEmpty) ...[
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: enrolledStudents.map((st) {
                                          return Chip(
                                            backgroundColor: const Color(
                                              0xFF132247,
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFF2563EB),
                                              width: 0.8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            avatar: CircleAvatar(
                                              backgroundColor: const Color(
                                                0xFF2563EB,
                                              ),
                                              child: Text(
                                                st.fullName.isNotEmpty
                                                    ? st.fullName[0]
                                                    : 'ط',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            label: Text(
                                              st.fullName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            deleteIcon: const Icon(
                                              Icons.close_rounded,
                                              size: 14,
                                              color: Color(0xFFEF4444),
                                            ),
                                            onDeleted: () {
                                              setModalState(() {
                                                enrolledStudents.removeWhere(
                                                  (s) => s.id == st.id,
                                                );
                                              });
                                            },
                                          );
                                        }).toList(),
                                      ),
                                      const SizedBox(height: 10),
                                    ],

                                    // Button: اختيار وتسكين طلاب
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFF38BDF8,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFF0284C7),
                                          width: 1,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                          horizontal: 12,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.person_add_alt_1_rounded,
                                        size: 17,
                                      ),
                                      label: Text(
                                        enrolledStudents.isEmpty
                                            ? 'إضافة وتسكين طلاب في هذه المجموعة'
                                            : 'تعديل قائمة الطلاب المسجلين (${enrolledStudents.length})',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onPressed: () => _showStudentPickerModal(
                                        context,
                                        allAcademyStudents,
                                        enrolledStudents,
                                        grade,
                                        stage,
                                        (newSelected) {
                                          setModalState(() {
                                            enrolledStudents.clear();
                                            enrolledStudents.addAll(
                                              newSelected,
                                            );
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Bottom Buttons: Save & Cancel
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF2563EB,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        elevation: 2,
                                      ),
                                      icon: const Icon(
                                        Icons.check_rounded,
                                        size: 19,
                                      ),
                                      label: Text(
                                        existing == null
                                            ? 'إنشاء المجموعة'
                                            : 'حفظ',
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onPressed: () async {
                                        if (formKey.currentState?.validate() ??
                                            false) {
                                          final sortedDays = daysList
                                              .where(
                                                (d) => selectedDays.contains(d),
                                              )
                                              .toList();
                                          final daysStr = sortedDays.join(',');

                                          // جدول مواعيد المجموعة الذكي
                                          String scheduleStr;
                                          if (differentTimePerDay &&
                                              sortedDays.isNotEmpty) {
                                            scheduleStr = sortedDays
                                                .map((d) {
                                                  final s =
                                                      dayStartTimes[d] ??
                                                      startTime;
                                                  final e =
                                                      dayEndTimes[d] ?? endTime;
                                                  return '$d ($s - $e)';
                                                })
                                                .join('، ');
                                          } else if (sortedDays.isNotEmpty) {
                                            scheduleStr =
                                                '${sortedDays.join(' و ')} من $startTime إلى $endTime';
                                          } else {
                                            scheduleStr = 'بدون مواعيد محددة';
                                          }

                                          // التحقق من تعارض المواعيد وطلب تأكيد المعلم إذا وجد تعارض
                                          if (currentConflicts.isNotEmpty) {
                                            final proceed =
                                                await ScheduleConflictService
                                                    .confirmSaveWithConflictDialog(
                                                      context: modalContext,
                                                      conflicts:
                                                          currentConflicts,
                                                      targetName:
                                                          nameCtrl.text
                                                              .trim()
                                                              .isNotEmpty
                                                              ? nameCtrl.text
                                                                    .trim()
                                                              : 'هذه المجموعة',
                                                    );
                                            if (!proceed) return;
                                          }

                                          final groupId =
                                              existing?.id ??
                                              'grp_${DateTime.now().millisecondsSinceEpoch}';

                                          final updatedGroup = GroupModel(
                                            id: groupId,
                                            name: nameCtrl.text.trim(),
                                            stage: stage,
                                            grade: grade,
                                            schedule: scheduleStr,
                                            monthlyPrice:
                                                double.tryParse(
                                                  priceCtrl.text.trim(),
                                                ) ??
                                                0,
                                            room: roomCtrl.text.trim(),
                                            maxStudents:
                                                int.tryParse(
                                                  maxStudentsCtrl.text.trim(),
                                                ) ??
                                                30,
                                            billingType: billingType,
                                            colorValue: selectedColor,
                                            notes: notesCtrl.text.trim(),
                                            subject: subject,
                                            locationType: locationType,
                                            startTime: startTime,
                                            endTime: endTime,
                                            days: daysStr,
                                            isActive: isActive,
                                          );

                                          await widget.database.saveGroup(
                                            updatedGroup,
                                          );

                                          // Update student enrollments atomically
                                          final enrolledIds = enrolledStudents
                                              .map((s) => s.id)
                                              .toList();
                                          await widget.database
                                              .updateGroupStudents(
                                                groupId,
                                                enrolledIds,
                                              );

                                          // Sync student curricula if shared session

                                          if (ctx.mounted) {
                                            Navigator.pop(ctx);
                                          }
                                          if (mounted) {
                                            _loadGroups();
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                backgroundColor: const Color(
                                                  0xFF10B981,
                                                ),
                                                content: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons
                                                          .check_circle_rounded,
                                                      color: Colors.white,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        existing == null
                                                            ? 'تم إنشاء مجموعة "${updatedGroup.name}" وتسكين ${enrolledIds.length} طالب بنجاح'
                                                            : 'تم تحديث بيانات المجموعة وتسكين الطلاب بنجاح',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF94A3B8),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                        horizontal: 16,
                                      ),
                                    ),
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text(
                                      'إلغاء',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- Helper Modal: Select & Enroll existing students from academy ---
  Future<void> _showStudentPickerModal(
    BuildContext context,
    List<StudentModel> allStudents,
    List<StudentModel> currentEnrolled,
    String defaultGrade,
    String defaultStage,
    Function(List<StudentModel>) onDone,
  ) async {
    final searchCtrl = TextEditingController();
    final selectedSet = currentEnrolled.map((s) => s.id).toSet();
    String query = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (pickerCtx) {
        return StatefulBuilder(
          builder: (c, setPickerState) {
            final filtered = allStudents.where((s) {
              if (query.isEmpty) return true;
              return s.fullName.toLowerCase().contains(query.toLowerCase()) ||
                  s.studentPhone.contains(query) ||
                  s.parentPhone.contains(query) ||
                  s.grade.toLowerCase().contains(query.toLowerCase());
            }).toList();

            return Directionality(
              textDirection: AppLocale.isArabic(context)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(pickerCtx).size.height * 0.85,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: Color(0xFF334155), width: 1.5),
                  ),
                ),
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                            ),
                            onPressed: () => Navigator.pop(pickerCtx),
                          ),
                          const Spacer(),
                          const Text(
                            'تسكين طلاب الأكاديمية بالمجموعة',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.how_to_reg_rounded,
                            color: Color(0xFF38BDF8),
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0xFF1E293B), height: 1),

                    // Search box & Quick Add Student
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: searchCtrl,
                              onChanged: (v) =>
                                  setPickerState(() => query = v.trim()),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                hintText: 'بحث باسم الطالب أو رقم الهاتف...',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: Color(0xFF64748B),
                                  size: 18,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF1E293B),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF38BDF8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              _showQuickAddStudentModal(
                                pickerCtx,
                                defaultGrade,
                                defaultStage,
                                (newStudent) {
                                  setPickerState(() {
                                    allStudents.insert(0, newStudent);
                                    selectedSet.add(newStudent.id);
                                  });
                                },
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x2610B981),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF10B981),
                                  width: 1,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person_add_rounded,
                                    color: Color(0xFF10B981),
                                    size: 16,
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    '+ طالب جديد',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Students List
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'لا توجد نتائج مطابقة',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (ctx, idx) {
                                final stu = filtered[idx];
                                final isSelected = selectedSet.contains(stu.id);

                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF1E293B)
                                        : const Color(0xFF141F35),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF38BDF8)
                                          : const Color(0xFF1E293B),
                                    ),
                                  ),
                                  child: CheckboxListTile(
                                    value: isSelected,
                                    activeColor: const Color(0xFF2563EB),
                                    checkColor: Colors.white,
                                    title: Text(
                                      stu.fullName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${stu.grade} • هاتف: ${stu.studentPhone.isNotEmpty ? stu.studentPhone : stu.parentPhone}',
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 11,
                                      ),
                                    ),
                                    onChanged: (checked) {
                                      setPickerState(() {
                                        if (checked == true) {
                                          selectedSet.add(stu.id);
                                        } else {
                                          selectedSet.remove(stu.id);
                                        }
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                    ),

                    // Bottom Confirm Button
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(
                            'تأكيد اختيار (${selectedSet.length}) طالب',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            final chosen = allStudents
                                .where((s) => selectedSet.contains(s.id))
                                .toList();
                            onDone(chosen);
                            Navigator.pop(pickerCtx);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- Helper Modal: Quick Add Brand New Student ---
  Future<void> _showQuickAddStudentModal(
    BuildContext context,
    String defaultGrade,
    String defaultStage,
    Function(StudentModel) onCreated,
  ) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final studentPhoneCtrl = TextEditingController();
    final parentPhoneCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (addCtx) {
        return Directionality(
          textDirection: AppLocale.isArabic(context)
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 18,
              bottom: MediaQuery.of(addCtx).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: Color(0xFF334155), width: 1.5),
              ),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        // Right side (RTL Start): Person icon + Title
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F3229),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF135E49),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.person_add_rounded,
                            color: Color(0xFF10B981),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'إضافة طالب',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        // Left side (RTL End): Close X button
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                          onPressed: () => Navigator.pop(addCtx),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFF1E293B)),
                    const SizedBox(height: 10),

                    // Student Name
                    TextFormField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'اسم الطالب رباعي *',
                        labelStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                        prefixIcon: const Icon(
                          Icons.person,
                          color: Color(0xFF64748B),
                          size: 18,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF334155),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'برجاء كتابة اسم الطالب'
                          : null,
                    ),
                    const SizedBox(height: 10),

                    // Student Phone
                    TextFormField(
                      controller: studentPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'رقم هاتف الطالب',
                        labelStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                        prefixIcon: const Icon(
                          Icons.phone,
                          color: Color(0xFF64748B),
                          size: 18,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.contacts_rounded,
                            color: Color(0xFF10B981),
                            size: 20,
                          ),
                          tooltip: 'اختيار من دليل الهاتف',
                          onPressed: () async {
                            final contact =
                                await ContactPickerService.pickContact();
                            if (contact != null && contact.phone.isNotEmpty) {
                              studentPhoneCtrl.text = contact.phone;
                              if (nameCtrl.text.trim().isEmpty &&
                                  contact.name.isNotEmpty) {
                                nameCtrl.text = contact.name;
                              }
                            }
                          },
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF334155),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Parent Phone
                    TextFormField(
                      controller: parentPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'رقم ولي الأمر',
                        labelStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                        prefixIcon: const Icon(
                          Icons.contact_phone,
                          color: Color(0xFF64748B),
                          size: 18,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.contacts_rounded,
                            color: Color(0xFF10B981),
                            size: 20,
                          ),
                          tooltip: 'اختيار من دليل الهاتف',
                          onPressed: () async {
                            final contact =
                                await ContactPickerService.pickContact();
                            if (contact != null && contact.phone.isNotEmpty) {
                              parentPhoneCtrl.text = contact.phone;
                            }
                          },
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF334155),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text(
                        'حفظ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () async {
                        if (formKey.currentState?.validate() ?? false) {
                          final nextCode = await widget.database
                              .getNextStudentCode();
                          final newStu = StudentModel(
                            id: nextCode,
                            fullName: nameCtrl.text.trim(),
                            stage: defaultStage,
                            grade: defaultGrade,
                            studentPhone: studentPhoneCtrl.text.trim(),
                            parentPhone: parentPhoneCtrl.text.trim(),
                            groupId: null,
                            paymentPlan: 'شهري',
                            outstandingAmount: 0,
                          );

                          await widget.database.saveStudent(newStu);
                          onCreated(newStu);
                          Navigator.pop(addCtx);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showGroupStudents(GroupModel group) async {
    final students = await widget.database.getStudents(groupId: group.id);
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groupColor = Color(
      group.colorValue != 0 ? group.colorValue : 0xFF2563EB,
    );

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: AppLocale.isArabic(context)
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: Dialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: MediaQuery.of(context).size.height * 0.60,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // Header Row (Fully protected from overflow)
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: groupColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: groupColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.groups_rounded,
                        color: groupColor,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${group.schedule.isNotEmpty ? group.schedule : "بدون مواعيد"} • ${group.monthlyPrice.toStringAsFixed(0)} ${group.billingType == 'per_session' ? 'ج.م/حصة' : 'ج.م/شهر'}',
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 18),

              // Title: Enrolled Students Count
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'الطلاب المقيدون بالمجموعة (${students.length})',
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: groupColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'الحد الأقصى: ${group.maxStudents}',
                      style: TextStyle(
                        color: groupColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // List of students
              if (students.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'لا يوجد طلاب مسجلين في هذه المجموعة حالياً',
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: students.length,
                    itemBuilder: (context, i) {
                      final s = students[i];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF131D31)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF243656)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 13,
                              backgroundColor: groupColor.withValues(
                                alpha: 0.15,
                              ),
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: groupColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'هاتف: ${s.studentPhone.isNotEmpty ? s.studentPhone : s.parentPhone}',
                                    style: TextStyle(
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B),
                                      fontSize: 10.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: s.hasOutstandingPayment
                                    ? Colors.red.withValues(alpha: 0.1)
                                    : Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                s.hasOutstandingPayment
                                    ? 'متأخر ${s.outstandingAmount.toStringAsFixed(0)} ج.م'
                                    : 'مسدد ✅',
                                style: TextStyle(
                                  color: s.hasOutstandingPayment
                                      ? Colors.red
                                      : Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              // Bottom Actions: WhatsApp Reminder + Edit + Delete
              const SizedBox(height: 10),
              if (students.isNotEmpty) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 10,
                    ),
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
                    'تذكير الطلاب (${students.length}) عبر واتساب',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => _showReminderListSheet(group, students),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: group.isActive ? Colors.orange.shade800 : Colors.teal.shade700,
                  side: BorderSide(
                    color: group.isActive ? Colors.orange.shade800 : Colors.teal.shade700,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(group.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 18),
                label: Text(
                  group.isActive ? 'إيقاف المجموعة مؤقتاً ⏸️' : 'تنشيط المجموعة 🟢',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await widget.database.setGroupActiveStatus(group.id, !group.isActive);
                  if (mounted) {
                    _loadGroups();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(group.isActive ? 'تم إيقاف المجموعة مؤقتاً ⏸️' : 'تم تنشيط المجموعة بنجاح 🟢'),
                        backgroundColor: group.isActive ? Colors.orange.shade800 : Colors.teal.shade700,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: const Text(
                        'تعديل المجموعة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showGroupDialog(existing: group);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 19,
                    ),
                    tooltip: 'حذف المجموعة',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('تأكيد حذف المجموعة'),
                          content: Text(
                            'تحذير: هل أنت متأكد من حذف المجموعة (${group.name})؟ سيتم مسح بيانات طلابها وسجلات الحضور والدرجات التابعة لها.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('إلغاء'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('تأكيد الحذف'),
                            ),
                          ],
                        ),
                      );

                      if (confirm != true) return;
                      if (!context.mounted) return;

                      final authOk = await SecurityService.authenticate(
                        context: context,
                        database: widget.database,
                        reason: 'تأكيد الهوية لحذف المجموعة (${group.name})',
                      );

                      if (!authOk) return;

                      await widget.database.deleteGroup(group.id);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (mounted) {
                        _loadGroups();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم حذف المجموعة بنجاح'),
                            behavior: SnackBarBehavior.floating,
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
    ),
  ),
);
}

  void _showReminderListSheet(
    GroupModel group,
    List<StudentModel> students,
  ) async {
    await NotificationService.showSessionReminder(
      groupName: group.name,
      time: group.schedule,
    );

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) {
        return Directionality(
          textDirection: AppLocale.isArabic(context)
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.campaign,
                      color: Color(0xFF25D366),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'إرسال تذكير بالموعد - ${group.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(c),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'الموعد: ${group.schedule}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Divider(height: 18),
                Flexible(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: students.length,
                    itemBuilder: (ctx, i) {
                      final s = students[i];
                      final targetPhone = s.parentPhone.isNotEmpty
                          ? s.parentPhone
                          : s.studentPhone;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.shade50,
                          radius: 14,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          s.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'هاتف: $targetPhone',
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.send,
                            color: Color(0xFF25D366),
                            size: 20,
                          ),
                          tooltip: 'إرسال تذكير عبر واتساب',
                          onPressed: () async {
                            final centerName = await widget.database.getSetting(
                              'center_name',
                              defaultValue: 'سنتر أستاذي',
                            );
                            final msg = WhatsAppService.reminderMessage(
                              centerName: centerName,
                              studentName: s.fullName,
                              schedule: group.schedule,
                            );
                            await WhatsAppService.dispatchMessage(
                              database: widget.database,
                              phone: targetPhone,
                              message: msg,
                            );
                          },
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
  }

  void _showChangeCurriculumDialog(GroupModel group) async {
    // Fetch available detailed curricula for the selected group.
    final availableCurricula = await widget.database.getDetailedCurriculaList();

    final existingBinding = groupBindings[group.id];
    String? currentBound = existingBinding?['curriculum_name'] as String?;

    // Auto-match curriculum based on group grade if nothing bound yet
    String? initialSelected = currentBound;
    if ((initialSelected == null || initialSelected.isEmpty) &&
        availableCurricula.isNotEmpty) {
      final gGrade = group.grade.trim().toLowerCase();
      final gName = group.name.trim().toLowerCase();
      for (final c in availableCurricula) {
        final cName = (c['name'] as String? ?? '').toLowerCase();
        final cGrade = (c['grade'] as String? ?? '').toLowerCase();
        if (cGrade.isNotEmpty &&
            (cGrade.contains(gGrade) || gGrade.contains(cGrade))) {
          initialSelected = c['name'] as String;
          break;
        } else if (cName.contains(gGrade) || gName.contains(cName)) {
          initialSelected = c['name'] as String;
          break;
        }
      }
      initialSelected ??= availableCurricula.first['name'] as String;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final sheetBg = isDark ? const Color(0xFF1E293B) : Colors.white;
        final cardBg = isDark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC);
        final borderColor = isDark ? Colors.white12 : Colors.grey.shade200;

        String? selectedCurriculum = initialSelected;
        final customCtrl = TextEditingController();
        String searchQuery = '';

        return StatefulBuilder(
          builder: (c, setSheetState) {
            final filteredCurricula = availableCurricula.where((cur) {
              if (searchQuery.trim().isEmpty) return true;
              final q = searchQuery.trim().toLowerCase();
              final name = (cur['name'] as String? ?? '').toLowerCase();
              final grade = (cur['grade'] as String? ?? '').toLowerCase();
              final subject = (cur['subject'] as String? ?? '').toLowerCase();
              return name.contains(q) ||
                  grade.contains(q) ||
                  subject.contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.88,
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.link_rounded,
                            color: Colors.indigo,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ربط المنهج الدراسي بالمجموعة',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${group.name} • ${group.grade} • ${group.stage}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'إغلاق',
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Main Content Body based on tab
                  Expanded(
                    child: Column(
                      children: [
                        // Search & Import Bar
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  onChanged: (val) =>
                                      setSheetState(() => searchQuery = val),
                                  decoration: InputDecoration(
                                    hintText: 'بحث في المناهج المستوردة...',
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      size: 18,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CurriculumScreen(
                                        database: widget.database,
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.file_upload_outlined,
                                  size: 16,
                                ),
                                label: const Text(
                                  'إكسل 📂',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // List of imported Curricula Cards
                        Expanded(
                          child: filteredCurricula.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.menu_book_outlined,
                                          size: 48,
                                          color: Colors.grey.shade400,
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'لم يتم العثور على مناهج مطابقة',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'يمكنك استيراد المناهج من ملف إكسل أو كتابة اسم المنهج يدوياً.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        FilledButton.icon(
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    CurriculumScreen(
                                                      database: widget.database,
                                                    ),
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.file_open_rounded,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'استيراد من إكسل الآن',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  itemCount: filteredCurricula.length,
                                  itemBuilder: (context, idx) {
                                    final cur = filteredCurricula[idx];
                                    final curName = cur['name'] as String;
                                    final isCurSelected =
                                        selectedCurriculum == curName;
                                    final totalLessons =
                                        (cur['total_lessons'] as num?)
                                            ?.toInt() ??
                                        0;
                                    final totalUnits =
                                        (cur['total_units'] as num?)?.toInt() ??
                                        0;
                                    final gradeStr =
                                        cur['grade'] as String? ?? '';
                                    final stageStr =
                                        cur['stage'] as String? ?? '';

                                    return InkWell(
                                      onTap: () {
                                        setSheetState(() {
                                          selectedCurriculum = curName;
                                          customCtrl.clear();
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isCurSelected
                                              ? Colors.indigo.withValues(
                                                  alpha: 0.12,
                                                )
                                              : cardBg,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: isCurSelected
                                                ? Colors.indigo
                                                : borderColor,
                                            width: isCurSelected ? 2 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isCurSelected
                                                  ? Icons.check_circle_rounded
                                                  : Icons
                                                        .radio_button_unchecked_rounded,
                                              color: isCurSelected
                                                  ? Colors.indigo
                                                  : Colors.grey.shade400,
                                              size: 22,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    curName,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isCurSelected
                                                          ? Colors.indigo
                                                          : null,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 6,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment
                                                            .center,
                                                    children: [
                                                      if (gradeStr.isNotEmpty)
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Colors.blue
                                                                .withValues(
                                                                  alpha: 0.1,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  6,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            gradeStr,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .blue,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                          ),
                                                        ),
                                                      if (stageStr.isNotEmpty &&
                                                          stageStr !=
                                                              'عام') ...[
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Colors.teal
                                                                .withValues(
                                                                  alpha: 0.1,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  6,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            stageStr,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 10,
                                                                  color: Colors
                                                                      .teal,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                      if (totalLessons > 0)
                                                        Text(
                                                          '$totalLessons درس • $totalUnits وحدة',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: Colors
                                                                .grey
                                                                .shade600,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                    ],
                                                  ),
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

                        // Manual Input field (Optional fallback)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                          child: TextField(
                            controller: customCtrl,
                            onChanged: (val) {
                              if (val.trim().isNotEmpty) {
                                setSheetState(
                                  () => selectedCurriculum = val.trim(),
                                );
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'أو اكتب اسم منهج مخصص يدوياً...',
                              prefixIcon: const Icon(Icons.edit_note, size: 20),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Bottom Action Buttons
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Row(
                      children: [
                        if (currentBound != null && currentBound.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () async {
                              await widget.database.unbindGroupFromCurriculum(
                                group.id,
                                groupName: group.name,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              _loadGroups();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'تم فك ربط منهج المجموعة "${group.name}" بنجاح',
                                    ),
                                    backgroundColor: Colors.blueGrey,
                                  ),
                                );
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.link_off, size: 18),
                            label: const Text('فك الربط'),
                          ),
                        if (currentBound != null && currentBound.isNotEmpty)
                          const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              final target = customCtrl.text.trim().isNotEmpty
                                  ? customCtrl.text.trim()
                                  : (selectedCurriculum ??
                                        'منهج ${group.grade}');

                              await widget.database.bindGroupToCurriculum(
                                groupId: group.id,
                                groupName: group.name,
                                grade: group.grade,
                                curriculumName: target,
                              );

                              if (ctx.mounted) Navigator.pop(ctx);
                              _loadGroups();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'تم ربط المجموعة بـ "$target" بنجاح 🔗',
                                    ),
                                    backgroundColor: const Color(0xFF10B981),
                                  ),
                                );
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 20),
                            label: const Text(
                              'تأكيد وحفظ الربط 🔗',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
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

  // ==========================================
  // خطة شرح دروس المنهج ومتابعة الإنجاز لكل مجموعة
  // ==========================================
  void _showGroupLessonsProgressSheet(GroupModel group) async {
    final binding = groupBindings[group.id];
    final defaultCurriculum = binding?['curriculum_name'] as String?;

    List<CurriculumLessonModel> lessons = await widget.database
        .getCurriculumLessons(curriculumName: defaultCurriculum);

    if (lessons.isEmpty && group.grade.isNotEmpty) {
      lessons = await widget.database.getCurriculumLessons(grade: group.grade);
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _GroupLessonsProgressSheetContent(
          database: widget.database,
          group: group,
          curriculumName:
              defaultCurriculum ??
              (lessons.isNotEmpty ? lessons.first.curriculumName : null),
          initialLessons: lessons,
          onChanged: _loadGroups,
          onChangeCurriculum: () {
            Navigator.pop(ctx);
            _showChangeCurriculumDialog(group);
          },
        );
      },
    );
  }

  // ==========================================
  // إضافة وجدولة حصة استثنائية (تعويضية / مراجعة / دوبل)
  // ==========================================
  void _showAddExceptionalSessionDialog({
    GroupModel? preselectedGroup,
    String initialReason = 'teacher_makeup',
    String? initialNotes,
  }) {
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'يرجى إنشاء مجموعة دراسية أولاً قبل جدولة حصة استثنائية',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    String selectedGroupId = preselectedGroup?.id ?? groups.first.id;
    String selectedReason = initialReason;
    String selectedScale = 'single'; // 'single' or 'double'
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = const TimeOfDay(hour: 16, minute: 0);
    bool isRecurring = false;
    final notesCtrl = TextEditingController(text: initialNotes ?? '');

    final reasons = [
      {
        'key': 'teacher_makeup',
        'label': 'تعويض (إلغاء المدرس)',
        'icon': Icons.person_off_rounded,
        'color': const Color(0xFFF59E0B),
      },
      {
        'key': 'student_makeup',
        'label': 'تعويض (غياب الطالب)',
        'icon': Icons.swap_horiz_rounded,
        'color': const Color(0xFF0284C7),
      },
      {
        'key': 'curriculum',
        'label': 'استكمال المنهج',
        'icon': Icons.menu_book_rounded,
        'color': const Color(0xFF10B981),
      },
      {
        'key': 'revision',
        'label': 'مراجعة ليلة الامتحان',
        'icon': Icons.quiz_rounded,
        'color': const Color(0xFF8B5CF6),
      },
      {
        'key': 'custom',
        'label': 'حصة إضافية مخصصة',
        'icon': Icons.star_rounded,
        'color': const Color(0xFFEC4899),
      },
    ];

    String getArabicDay(DateTime date) {
      switch (date.weekday) {
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

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isDark = Theme.of(modalCtx).brightness == Brightness.dark;
            final theme = Theme.of(modalCtx);
            final dayName = getArabicDay(selectedDate);
            final dateStr =
                '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

            final targetGroup = groups.firstWhere(
              (g) => g.id == selectedGroupId,
              orElse: () => groups.first,
            );

            // فحص تعارض مواعيد الحصة الاستثنائية الحي (Live Conflict Check)
            final currentConflicts =
                ScheduleConflictService.checkProposedExceptionalSessionConflicts(
                  targetGroupId: targetGroup.id,
                  targetGroupName: targetGroup.name,
                  proposedDate: dateStr,
                  proposedDay: dayName,
                  proposedTime: _formatTimeOfDay(selectedTime),
                  proposedScale: selectedScale,
                  allGroups: groups,
                  exceptionalSessions: exceptionalSessions,
                );

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
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: Color(0xFFF59E0B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'جدولة حصة استثنائية',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. اختيار المجموعة
                      const Text(
                        'المجموعة المستهدفة:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: selectedGroupId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF8FAFC),
                        ),
                        items: groups.map((g) {
                          return DropdownMenuItem(
                            value: g.id,
                            child: Text(
                              g.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) setModalState(() => selectedGroupId = v);
                        },
                      ),
                    const SizedBox(height: 14),

                    // 2. سبب الحصة الاستثنائية
                    const Text(
                      'سبب / هدف الحصة:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: reasons.map((r) {
                        final isSelected = selectedReason == r['key'];
                        final rColor = r['color'] as Color;
                        return ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                r['icon'] as IconData,
                                size: 14,
                                color: isSelected ? Colors.white : rColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                r['label'] as String,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark
                                            ? Colors.white70
                                            : const Color(0xFF334155)),
                                ),
                              ),
                            ],
                          ),
                          selected: isSelected,
                          selectedColor: rColor,
                          backgroundColor: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF1F5F9),
                          onSelected: (_) => setModalState(
                            () => selectedReason = r['key'] as String,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // 3. نوع الحصة: فردية (1x) أو دوبل (2x)
                    const Text(
                      'حجم الحصة:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFCBD5E1),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setModalState(() => selectedScale = 'single'),
                              borderRadius: BorderRadius.circular(9),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selectedScale == 'single'
                                      ? (isDark
                                            ? const Color(0xFF0F172A)
                                            : Colors.white)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                  boxShadow: selectedScale == 'single'
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.1,
                                            ),
                                            blurRadius: 4,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.looks_one_rounded,
                                      size: 16,
                                      color: selectedScale == 'single'
                                          ? theme.colorScheme.primary
                                          : Colors.grey,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'حصة فردية (1x)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: selectedScale == 'single'
                                            ? (isDark
                                                  ? Colors.white
                                                  : const Color(0xFF0F172A))
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
                              onTap: () =>
                                  setModalState(() => selectedScale = 'double'),
                              borderRadius: BorderRadius.circular(9),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selectedScale == 'double'
                                      ? const Color(0xFFEA580C)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                  boxShadow: selectedScale == 'double'
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xFFEA580C,
                                            ).withValues(alpha: 0.35),
                                            blurRadius: 6,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.bolt_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'حصة دوبل (2x) 🔥',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Colors.white,
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
                    const SizedBox(height: 14),

                    // 4. التاريخ والوقت
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: modalCtx,
                                initialDate: selectedDate,
                                firstDate: DateTime.now().subtract(
                                  const Duration(days: 7),
                                ),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 90),
                                ),
                              );
                              if (picked != null) {
                                setModalState(() => selectedDate = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'التاريخ واليوم:',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today_rounded,
                                        size: 14,
                                        color: Colors.amber,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '$dayName ($dateStr)',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: modalCtx,
                                initialTime: selectedTime,
                              );
                              if (picked != null) {
                                setModalState(() => selectedTime = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'وقت الحصة:',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.access_time_rounded,
                                        size: 14,
                                        color: Colors.amber,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _formatTimeOfDay(selectedTime),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 5. التكرار الأسبوعي
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'تتكرر أسبوعياً؟',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        isRecurring
                            ? 'نعم، تتكرر كل أسبوع في نفس اليوم والوقت'
                            : 'لا، حصة لمرة واحدة فقط',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      value: isRecurring,
                      onChanged: (v) => setModalState(() => isRecurring = v),
                    ),
                    const SizedBox(height: 6),

                    // 6. ملاحظات
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'ملاحظات إضافية عن الحصة (اختياري)...',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF8FAFC),
                      ),
                    ),

                    // تنبيه تعارض المواعيد الحي للحصة الاستثنائية
                    if (currentConflicts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ScheduleConflictService.buildConflictWarningBanner(
                        conflicts: currentConflicts,
                        context: modalCtx,
                      ),
                    ],
                  ],
                ),
              ),
            ),
              actionsAlignment: MainAxisAlignment.end,
              actionsOverflowButtonSpacing: 8,
              actionsOverflowDirection: VerticalDirection.down,
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(modalCtx),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: const Text(
                    'جدولة الحصة الآن',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    // التحقق من تعارض المواعيد وطلب تأكيد المعلم إذا وجد تعارض
                    if (currentConflicts.isNotEmpty) {
                      final proceed =
                          await ScheduleConflictService
                              .confirmSaveWithConflictDialog(
                                context: modalCtx,
                                conflicts: currentConflicts,
                                targetName:
                                    'الحصة الاستثنائية لمجموعة "${targetGroup.name}"',
                              );
                      if (!proceed) return;
                    }

                    final session = ExceptionalSessionModel(
                      id: 'EX-${DateTime.now().millisecondsSinceEpoch}',
                      groupId: targetGroup.id,
                      groupName: targetGroup.name,
                      title:
                          reasons.firstWhere(
                                (r) => r['key'] == selectedReason,
                              )['label']
                              as String,
                      reason: selectedReason,
                      scale: selectedScale,
                      date: dateStr,
                      day: dayName,
                      time: _formatTimeOfDay(selectedTime),
                      isRecurring: isRecurring,
                      notes: notesCtrl.text.trim(),
                      createdAt: DateTime.now().toIso8601String(),
                    );

                    await widget.database.saveExceptionalSession(session);
                    if (!modalCtx.mounted) return;
                    Navigator.pop(modalCtx);
                    await _loadGroups();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'تم جدولة الحصة الاستثنائية بنجاح لمجموعة "${targetGroup.name}" ⚡',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
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

  void _confirmDeleteExceptionalSession(ExceptionalSessionModel session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الحصة الاستثنائية'),
        content: Text(
          'هل أنت متأكد من إلغاء الحصة الاستثنائية لمجموعة "${session.groupName}"؟',
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
              await _loadGroups();
            },
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: SectionTopBar(
        title: 'المجموعات',
        icon: Icons.groups_rounded,
        onBack: widget.onBack,
        actionLabel: _tabController.index == 1
            ? 'حصة استثنائية'
            : 'إنشاء مجموعة',
        actionIcon: _tabController.index == 1
            ? Icons.bolt_rounded
            : Icons.group_add_rounded,
        onAction: () {
          if (_tabController.index == 1) {
            _showAddExceptionalSessionDialog();
          } else {
            _showGroupDialog();
          }
        },
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: Container(
            color: theme.scaffoldBackgroundColor,
            padding: EdgeInsets.zero,
            child: SizedBox(
              height: 36,
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
                indicatorColor: theme.colorScheme.primary,
                indicatorWeight: 2.2,
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  fontFamily: 'Cairo',
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  fontFamily: 'Cairo',
                ),
                tabs: const [
                  Tab(
                    height: 34,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.groups_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('المجموعات'),
                      ],
                    ),
                  ),
                  Tab(
                    height: 34,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_month_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('الجدول'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildGroupsTab(theme, isDark),
                _buildWeeklyScheduleTab(theme, isDark),
              ],
            ),
    );
  }

  // =========================================================================
  // SMART SEARCH & FILTER ENGINE FOR GROUPS (محرك البحث الذكي والفلترة)
  // =========================================================================
  String _normalizeArabic(String text) {
    var s = text.trim().toLowerCase();
    // Remove Arabic Tashkeel / Diacritics
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // Normalize Alef variations
    s = s.replaceAll(RegExp(r'[إأآا]'), 'ا');
    // Normalize Taa Marbuta & Haa
    s = s.replaceAll('ة', 'ه');
    // Normalize Yaa & Alef Maksura
    s = s.replaceAll('ى', 'ي');
    // Normalize Arabic & Persian digits to Western digits
    s = s.replaceAll('٠', '0').replaceAll('١', '1').replaceAll('٢', '2')
         .replaceAll('٣', '3').replaceAll('٤', '4').replaceAll('٥', '5')
         .replaceAll('٦', '6').replaceAll('٧', '7').replaceAll('٨', '8').replaceAll('٩', '9');
    return s;
  }

  List<GroupModel> _getFilteredGroups(Map<String, List<ScheduleConflict>> allConflicts) {
    final normQuery = _normalizeArabic(_searchQuery);
    final queryTokens = normQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    _matchedReasons.clear();

    return groups.where((group) {
      // 1. Grade filter
      if (_selectedGradeFilter != null && _selectedGradeFilter!.isNotEmpty) {
        if (group.grade.trim() != _selectedGradeFilter!.trim()) {
          return false;
        }
      }

      // 2. Day filter
      if (_selectedDayFilter != null && _selectedDayFilter!.isNotEmpty) {
        final d = _normalizeArabic(_selectedDayFilter!);
        final groupDays = _normalizeArabic('${group.days} ${group.schedule}');
        if (!groupDays.contains(d)) {
          return false;
        }
      }

      // 3. Status filter
      if (_selectedStatusFilter != null) {
        if (_selectedStatusFilter == 'active' && !group.isActive) return false;
        if (_selectedStatusFilter == 'inactive' && group.isActive) return false;
        if (_selectedStatusFilter == 'conflict') {
          final conflicts = allConflicts[group.id];
          if (conflicts == null || conflicts.isEmpty) return false;
        }
      }

      // 4. Smart search query tokens (ALL tokens must match)
      if (queryTokens.isEmpty) return true;

      final binding = groupBindings[group.id];
      final curriculumName = binding?['curriculum_name'] as String? ?? '';
      final track = binding?['track'] as String? ?? '';

      final normName = _normalizeArabic(group.name);
      final normStage = _normalizeArabic(group.stage);
      final normGrade = _normalizeArabic(group.grade);
      final normSubject = _normalizeArabic(group.subject);
      final normSchedule = _normalizeArabic(group.schedule);
      final normDays = _normalizeArabic(group.days);
      final normTime = _normalizeArabic('${group.startTime} ${group.endTime}');
      final normRoom = _normalizeArabic(group.room);
      final normLocation = _normalizeArabic(group.locationType);
      final normNotes = _normalizeArabic(group.notes);
      final normCurriculum = _normalizeArabic(curriculumName);
      final normTrack = _normalizeArabic(track);
      final normBilling = group.billingType == 'per_session' ? 'حصه بالحصه per session' : 'شهري بالشهر monthly';
      final priceStr = group.monthlyPrice.toString();

      final students = groupStudentsMap[group.id] ?? [];

      String? matchedStudentName;

      for (final token in queryTokens) {
        bool tokenMatches = false;

        // Check group core metadata
        if (normName.contains(token) ||
            normStage.contains(token) ||
            normGrade.contains(token) ||
            normSubject.contains(token) ||
            normSchedule.contains(token) ||
            normDays.contains(token) ||
            normTime.contains(token) ||
            normRoom.contains(token) ||
            normLocation.contains(token) ||
            normNotes.contains(token) ||
            normCurriculum.contains(token) ||
            normTrack.contains(token) ||
            normBilling.contains(token) ||
            priceStr.contains(token)) {
          tokenMatches = true;
        }

        // Check enrolled students
        if (!tokenMatches) {
          for (final s in students) {
            final sNameNorm = _normalizeArabic(s.fullName);
            final sPhone = s.studentPhone.replaceAll(RegExp(r'\s+'), '');
            final pPhone = s.parentPhone.replaceAll(RegExp(r'\s+'), '');
            if (sNameNorm.contains(token) || sPhone.contains(token) || pPhone.contains(token)) {
              tokenMatches = true;
              matchedStudentName = s.fullName;
              break;
            }
          }
        }

        if (!tokenMatches) {
          return false;
        }
      }

      if (matchedStudentName != null && !normName.contains(normQuery)) {
        _matchedReasons[group.id] = matchedStudentName;
      }

      return true;
    }).toList();
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedGradeFilter = null;
      _selectedDayFilter = null;
      _selectedStatusFilter = null;
    });
  }

  Widget _buildSmartSearchBarSection({
    required ThemeData theme,
    required bool isDark,
    required int totalCount,
    required int filteredCount,
    required bool hasConflicts,
  }) {
    final availableGrades = groups
        .map((g) => g.grade.trim())
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()..sort();

    final isAnyFilterActive = _searchQuery.trim().isNotEmpty ||
        _selectedGradeFilter != null ||
        _selectedDayFilter != null ||
        _selectedStatusFilter != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Search Box
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _searchQuery.trim().isNotEmpty
                    ? theme.colorScheme.primary.withValues(alpha: 0.8)
                    : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                width: _searchQuery.trim().isNotEmpty ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'بحث ذكي (اسم المجموعة، الصف، المادة، اليوم، القاعة، أو طالب)...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: _searchQuery.trim().isNotEmpty
                      ? theme.colorScheme.primary
                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  size: 20,
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchQuery.trim().isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: isDark ? Colors.white70 : Colors.black54,
                        tooltip: 'مسح نص البحث',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      ),
                  ],
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 2. Interactive Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // "الكل" Chip
                ChoiceChip(
                  label: const Text('الكل 📋', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  selected: !isAnyFilterActive,
                  onSelected: (_) {
                    _clearAllFilters();
                  },
                  selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                  side: BorderSide(
                    color: !isAnyFilterActive ? theme.colorScheme.primary : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                ),
                const SizedBox(width: 6),

                // Status Filter Chips
                ChoiceChip(
                  label: const Text('نشطة فقط 🟢', style: TextStyle(fontSize: 11.5)),
                  selected: _selectedStatusFilter == 'active',
                  onSelected: (val) {
                    setState(() {
                      _selectedStatusFilter = val ? 'active' : null;
                    });
                  },
                  selectedColor: Colors.green.withValues(alpha: 0.2),
                  side: BorderSide(
                    color: _selectedStatusFilter == 'active' ? Colors.green : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                ),
                const SizedBox(width: 6),

                ChoiceChip(
                  label: const Text('متوقفة ⏸️', style: TextStyle(fontSize: 11.5)),
                  selected: _selectedStatusFilter == 'inactive',
                  onSelected: (val) {
                    setState(() {
                      _selectedStatusFilter = val ? 'inactive' : null;
                    });
                  },
                  selectedColor: Colors.orange.withValues(alpha: 0.2),
                  side: BorderSide(
                    color: _selectedStatusFilter == 'inactive' ? Colors.orange : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                ),
                const SizedBox(width: 6),

                if (hasConflicts) ...[
                  ChoiceChip(
                    label: const Text('بها تعارض ⚠️', style: TextStyle(fontSize: 11.5)),
                    selected: _selectedStatusFilter == 'conflict',
                    onSelected: (val) {
                      setState(() {
                        _selectedStatusFilter = val ? 'conflict' : null;
                      });
                    },
                    selectedColor: Colors.red.withValues(alpha: 0.2),
                    side: BorderSide(
                      color: _selectedStatusFilter == 'conflict' ? Colors.red : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Grade Chips
                for (final g in availableGrades) ...[
                  ChoiceChip(
                    label: Text(g, style: const TextStyle(fontSize: 11.5)),
                    selected: _selectedGradeFilter == g,
                    onSelected: (val) {
                      setState(() {
                        _selectedGradeFilter = val ? g : null;
                      });
                    },
                    selectedColor: const Color(0xFF0284C7).withValues(alpha: 0.2),
                    side: BorderSide(
                      color: _selectedGradeFilter == g ? const Color(0xFF0284C7) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Days Chips
                for (final day in weekDays) ...[
                  ChoiceChip(
                    label: Text(day, style: const TextStyle(fontSize: 11.5)),
                    selected: _selectedDayFilter == day,
                    onSelected: (val) {
                      setState(() {
                        _selectedDayFilter = val ? day : null;
                      });
                    },
                    selectedColor: Colors.purple.withValues(alpha: 0.2),
                    side: BorderSide(
                      color: _selectedDayFilter == day ? Colors.purple : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),

          // 3. Active filter summary banner
          if (isAnyFilterActive) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.filter_list_rounded, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'عرض $filteredCount من أصل $totalCount مجموعة',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _clearAllFilters,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear_all_rounded, size: 14, color: Colors.red.shade400),
                        const SizedBox(width: 2),
                        Text(
                          'إلغاء التصفية',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoResultsEmptyState(ThemeData theme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد مجموعات مطابقة للبحث أو الفلترة 🔍',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'جرّب البحث بكلمات أخرى أو اختر صفاً أو يوماً مختلفاً',
              style: TextStyle(
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إلغاء البحث والفلترة', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _clearAllFilters,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictAlertBanner(Map<String, List<ScheduleConflict>> allConflicts) {
    return InkWell(
      onTap: () {
        _tabController.animateTo(1);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF991B1B), Color(0xFFDC2626)],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFDC2626).withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ تنبيه: تم رصد تعارض في مواعيد ${allConflicts.length} مجموعة دراسية!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'اضغط للانتقال إلى جدول الحصص الأسبوعي لفحص وحل التعارض',
                    style: TextStyle(
                      color: Color(0xFFFEE2E2),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
          ],
        ),
      ),
    );
  }

  // --- 1. Tab: Groups Cards ---
  Widget _buildGroupsTab(ThemeData theme, bool isDark) {
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.groups_outlined, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'لا توجد مجموعات بعد',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'أضف أول مجموعة دراسية للبدء بتنظيم الطلاب',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final allConflicts = ScheduleConflictService.detectAllConflicts(
      groups: groups,
      exceptionalSessions: exceptionalSessions,
    );
    final hasConflictAlert = allConflicts.isNotEmpty;

    final filteredGroups = _getFilteredGroups(allConflicts);
    final isFiltered = _searchQuery.trim().isNotEmpty ||
        _selectedGradeFilter != null ||
        _selectedDayFilter != null ||
        _selectedStatusFilter != null;

    return Column(
      children: [
        _buildSmartSearchBarSection(
          theme: theme,
          isDark: isDark,
          totalCount: groups.length,
          filteredCount: filteredGroups.length,
          hasConflicts: hasConflictAlert,
        ),
        Expanded(
          child: filteredGroups.isEmpty
              ? _buildNoResultsEmptyState(theme, isDark)
              : ListView.builder(
                  key: const PageStorageKey<String>('groups_screen_list_view'),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  itemCount: filteredGroups.length + (hasConflictAlert && !isFiltered ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (hasConflictAlert && !isFiltered && index == 0) {
                      return _buildConflictAlertBanner(allConflicts);
                    }

                    final actualIndex = index - (hasConflictAlert && !isFiltered ? 1 : 0);
                    final group = filteredGroups[actualIndex];
                    final studentCount = groupStudentCounts[group.id] ?? 0;
                    final binding = groupBindings[group.id];
                    final curriculumName =
                        binding?['curriculum_name'] as String? ?? 'لم يُحدد منهج بعد';
                    final track = binding?['track'] as String? ?? 'لغات';

                    final groupConflicts = allConflicts[group.id];
                    final bool hasConflict =
                        groupConflicts != null && groupConflicts.isNotEmpty;

                    return Card(
                      key: ValueKey('group_card_${group.id}'),
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: hasConflict ? 3 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: hasConflict
                            ? const BorderSide(color: Color(0xFFEF4444), width: 1.8)
                            : BorderSide.none,
                      ),
                      child: InkWell(
                        onTap: () => _showGroupStudents(group),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            AppLocale.localizeData(context, group.name),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: group.isActive
                                                ? Colors.green.withValues(alpha: 0.12)
                                                : Colors.orange.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: group.isActive
                                                  ? Colors.green.shade300
                                                  : Colors.orange.shade400,
                                              width: 0.8,
                                            ),
                              ),
                              child: Text(
                                group.isActive ? 'نشطة 🟢' : 'متوقفة ⏸️',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: group.isActive
                                      ? Colors.green.shade800
                                      : Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$studentCount ${AppLocale.tr(context, 'students', ar: 'طالب', en: 'Students')}',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${AppLocale.localizeData(context, group.stage)} • ${AppLocale.localizeData(context, group.grade)}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_matchedReasons[group.id] != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_search_rounded, size: 13, color: Color(0xFF0284C7)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'طالب مسجل: ${_matchedReasons[group.id]}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0284C7),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),

                  // Bound Curriculum Badge (Clickable to change curriculum)
                  InkWell(
                    onTap: () => _showChangeCurriculumDialog(group),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: binding != null
                              ? Colors.blueGrey.withValues(alpha: 0.2)
                              : Colors.amber.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            binding != null
                                ? Icons.link
                                : Icons.add_link_rounded,
                            size: 14,
                            color: binding != null
                                ? Colors.blueAccent
                                : Colors.amber.shade800,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              binding != null
                                  ? '${AppLocale.tr(context, 'curriculum_label', ar: 'المنهج', en: 'Curriculum')}: ${AppLocale.localizeData(context, curriculumName)}'
                                  : 'اضغط لربط المنهج الدراسي 🔗',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: binding != null
                                    ? null
                                    : Colors.amber.shade900,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (binding != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: track == 'لغات'
                                    ? Colors.blue.withValues(alpha: 0.15)
                                    : Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                AppLocale.localizeData(context, track),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: track == 'لغات'
                                      ? Colors.blue.shade700
                                      : Colors.amber.shade900,
                                ),
                              ),
                            ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit,
                            size: 13,
                            color: binding != null
                                ? Colors.grey
                                : Colors.amber.shade800,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          AppLocale.localizeData(context, group.schedule),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (group.billingType == 'per_session'
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFF10B981))
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (group.billingType == 'per_session'
                                    ? const Color(0xFF0284C7)
                                    : const Color(0xFF10B981))
                                .withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          group.billingType == 'per_session'
                              ? 'بالحصة'
                              : 'بالشهر',
                          style: TextStyle(
                            color: group.billingType == 'per_session'
                                ? const Color(0xFF0284C7)
                                : const Color(0xFF10B981),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${group.monthlyPrice.toStringAsFixed(0)} ${group.billingType == 'per_session' ? 'ج.م/حصة' : AppLocale.tr(context, 'egp_per_month', ar: 'ج.م/شهر', en: 'EGP/mo')}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),

                  // Curriculum Growth Rate & Progress Section (معدل نمو المنهج)
                  _buildGroupCurriculumGrowthSection(
                    group,
                    groupProgressMap[group.id],
                    isDark,
                    theme,
                  ),

                  // Schedule Conflict Alert Box inside Card
                  if (hasConflict) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFEF4444),
                              size: 17,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '⚠️ تعارض في المواعيد (${groupConflicts.length}):',
                                  style: const TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                ...groupConflicts.map(
                                  (c) => Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      '• ${c.message}',
                                      style: TextStyle(
                                        color: isDark
                                            ? const Color(0xFFFCA5A5)
                                            : const Color(0xFFB91C1C),
                                        fontSize: 10.5,
                                        height: 1.25,
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
                  ],

                  const SizedBox(height: 6),
                  const Divider(height: 10),

                  // Fast Actions on card (Wrapped to prevent overflow on narrow viewports)
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.people_outline, size: 16),
                        label: Text(
                          AppLocale.tr(
                            context,
                            'students',
                            ar: 'الطلاب',
                            en: 'Students',
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () => _showGroupStudents(group),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          side: BorderSide(color: Colors.indigo.shade200),
                        ),
                        icon: const Icon(
                          Icons.auto_stories_rounded,
                          size: 15,
                          color: Colors.indigo,
                        ),
                        label: const Text(
                          'خطة الشرح 📖',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                        onPressed: () => _showGroupLessonsProgressSheet(group),
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
  ),
],
);
  }

  Widget _buildGroupCurriculumGrowthSection(
    GroupModel group,
    GroupCurriculumProgress? progress,
    bool isDark,
    ThemeData theme,
  ) {
    final hasCurriculum = progress != null && progress.hasCurriculum;
    final percent = progress?.progressPercent ?? 0.0;
    final percentInt = progress?.percentInt ?? 0;
    final completed = progress?.completedLessons ?? 0;
    final total = progress?.totalLessons ?? 0;
    final remaining = progress?.remainingLessons ?? 0;

    final Color progressColor;
    if (percentInt >= 75) {
      progressColor = const Color(0xFF059669);
    } else if (percentInt >= 40) {
      progressColor = const Color(0xFF2563EB);
    } else if (percentInt > 0) {
      progressColor = const Color(0xFFD97706);
    } else {
      progressColor = Colors.grey.shade500;
    }

    return InkWell(
      onTap: () => _showGroupLessonsProgressSheet(group),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1E293B).withValues(alpha: 0.7)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasCurriculum
                ? progressColor.withValues(alpha: 0.25)
                : Colors.grey.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: progressColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.trending_up_rounded,
                    size: 14,
                    color: progressColor,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'معدل نمو المنهج:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (hasCurriculum) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: progressColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$percentInt% إنجاز',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: progressColor,
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    'لم يُسجل منهج',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: hasCurriculum ? percent : 0.0,
                minHeight: 6,
                backgroundColor: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 6),
            if (hasCurriculum) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'تم شرح $completed من أصل $total درس (متبقي $remaining)',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    'خطة الشرح ➔',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (progress.nextLessonTitle != null &&
                  progress.nextLessonTitle!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 11,
                      color: Colors.indigo.shade400,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'الدرس القادم: ${progress.nextLessonTitle}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.indigo.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ] else if (progress.isCompleted) ...[
                const SizedBox(height: 3),
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 12,
                      color: Color(0xFF059669),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'تم الانتهاء من كامل المنهج بنجاح 🎉',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ] else ...[
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 12,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'اضغط هنا لربط منهج المجموعة وتتبع معدل النمو',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }


  // --- 2. Tab: Weekly Schedule Timetable ---
  Widget _buildWeeklyScheduleTab(ThemeData theme, bool isDark) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        // 1. Exceptional Sessions Quick Add Banner
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'الحصص الاستثنائية والتعويضية',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF4F46E5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _showAddExceptionalSessionDialog(),
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text(
                      'جدولة حصة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'جدولة حصص تعويضية (مدرس/طالب) أو استكمال منهج أو مراجعة (فردية أو دوبل)',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),

        // 2. Days Schedule
        ...weekDays.map((day) {
          final dayGroups = groups
              .where((g) => g.schedule.contains(day))
              .toList();
          final dayExceptional = exceptionalSessions
              .where((s) => s.day == day || (s.isRecurring && s.day == day))
              .toList();
          final totalCount = dayGroups.length + dayExceptional.length;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.15),
                            child: Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppLocale.localizeData(context, day),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (dayExceptional.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF59E0B,
                                ).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '⚡ ${dayExceptional.length} استثنائية',
                                style: const TextStyle(
                                  color: Color(0xFFD97706),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            '$totalCount ${AppLocale.tr(context, 'groups', ar: 'حصص / مجموعات', en: 'Sessions')}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  if (dayGroups.isEmpty && dayExceptional.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        AppLocale.tr(
                          context,
                          'no_groups_this_day',
                          ar: 'لا توجد حصص مجدولة في هذا اليوم',
                          en: 'No sessions scheduled for this day',
                        ),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else ...[
                    // --- الحصص الاستثنائية أولاً بتصميم مميز ومتوهج ---
                    ...dayExceptional.map((ex) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [
                                    const Color(0xFF2E200C),
                                    const Color(0xFF1B140B),
                                  ]
                                : [
                                    const Color(0xFFFFFBEB),
                                    const Color(0xFFFEF3C7),
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(
                              0xFFF59E0B,
                            ).withValues(alpha: isDark ? 0.7 : 0.85),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFF59E0B,
                              ).withValues(alpha: isDark ? 0.2 : 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.bolt_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'حصة استثنائية',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ex.scale == 'double'
                                        ? (isDark
                                              ? const Color(0xFF7C2D12)
                                              : const Color(0xFFFFEDD5))
                                        : (isDark
                                              ? const Color(0xFF1E293B)
                                              : const Color(0xFFE2E8F0)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: ex.scale == 'double'
                                          ? const Color(0xFFEA580C)
                                          : Colors.transparent,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    ex.scale == 'double'
                                        ? '🔥 دوبل (2x)'
                                        : 'فردية (1x)',
                                    style: TextStyle(
                                      color: ex.scale == 'double'
                                          ? (isDark
                                                ? const Color(0xFFFDBA74)
                                                : const Color(0xFFC2410C))
                                          : (isDark
                                                ? Colors.white70
                                                : const Color(0xFF475569)),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: 'إلغاء الحصة',
                                  onPressed: () =>
                                      _confirmDeleteExceptionalSession(ex),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              ex.groupName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 13,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  ex.time,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Icon(
                                  Icons.label_outline_rounded,
                                  size: 13,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.grey.shade700,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    ex.reasonLabel,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark
                                          ? Colors.amber.shade200
                                          : const Color(0xFFB45309),
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (ex.isRecurring || ex.date.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    ex.isRecurring
                                        ? Icons.repeat_rounded
                                        : Icons.event_rounded,
                                    size: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    ex.isRecurring
                                        ? 'تتكرر أسبوعياً'
                                        : 'تاريخ الحصة: ${ex.date}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (ex.notes.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'ملاحظة: ${ex.notes}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFF59E0B),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.playlist_add_check_rounded,
                                  size: 15,
                                ),
                                label: const Text(
                                  'تحضير الحصة الآن',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TodayAttendanceScreen(
                                        database: widget.database,
                                        preselectedGroupId: ex.groupId,
                                        initialSessionType: ex.scale,
                                      ),
                                    ),
                                  ).then((_) => _loadGroups());
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    // --- الحصص العادية ---
                    ...dayGroups.map((g) {
                      final stCount = groupStudentCounts[g.id] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TodayAttendanceScreen(
                                  database: widget.database,
                                  preselectedGroupId: g.id,
                                ),
                              ),
                            ).then((_) => _loadGroups());
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E293B)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.grey.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLocale.localizeData(context, g.name),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        '${AppLocale.localizeData(context, g.schedule)} • $stCount ${AppLocale.tr(context, 'students', ar: 'طالب', en: 'Students')}',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: Text(
                                    AppLocale.tr(
                                      context,
                                      'take_attendance_short',
                                      ar: 'تحضير',
                                      en: 'Check-in',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TodayAttendanceScreen(
                                          database: widget.database,
                                          preselectedGroupId: g.id,
                                        ),
                                      ),
                                    ).then((_) => _loadGroups());
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

// =========================================================================
// شاشة / ورقة متابعة خطة دروس المنهج للمجموعة (الحصة السابقة / الحالية / بدون تاريخ)
// =========================================================================
class _GroupLessonsProgressSheetContent extends StatefulWidget {
  const _GroupLessonsProgressSheetContent({
    required this.database,
    required this.group,
    this.curriculumName,
    required this.initialLessons,
    required this.onChanged,
    required this.onChangeCurriculum,
  });

  final DatabaseService database;
  final GroupModel group;
  final String? curriculumName;
  final List<CurriculumLessonModel> initialLessons;
  final VoidCallback onChanged;
  final VoidCallback onChangeCurriculum;

  @override
  State<_GroupLessonsProgressSheetContent> createState() =>
      _GroupLessonsProgressSheetContentState();
}

class _GroupLessonsProgressSheetContentState
    extends State<_GroupLessonsProgressSheetContent> {
  late List<CurriculumLessonModel> lessons;
  Map<int, Map<String, dynamic>> progressMap = {};
  bool isLoading = true;
  String filterStatus = 'all'; // 'all', 'taught', 'remaining'
  String? activeCurriculumName;

  @override
  void initState() {
    super.initState();
    activeCurriculumName = widget.curriculumName;
    lessons = List.from(widget.initialLessons);
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    setState(() => isLoading = true);
    final map = await widget.database.getGroupLessonProgressMap(
      widget.group.id,
    );
    if (mounted) {
      setState(() {
        progressMap = map;
        isLoading = false;
      });
    }
  }

  Future<void> _setLessonStatus(int lessonId, String status) async {
    await widget.database.setGroupLessonProgress(
      groupId: widget.group.id,
      lessonId: lessonId,
      status: status,
    );
    await _loadProgress();
    widget.onChanged();
  }

  Future<void> _markAllNoDate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'تعليم جميع الدروس',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل تريد تعليم جميع دروس هذا المنهج كـ "مشروح مسبقاً (بدون تاريخ)" لمجموعة ${widget.group.name}؟\n\nيُفيد هذا في حال بدأت مع المجموعة بعد قطع شوط من المنهج.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.purple.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، تعليم الكل مسبقاً'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final allIds = lessons.map((l) => l.id).whereType<int>().toList();
    if (allIds.isEmpty) return;
    await widget.database.bulkSetGroupLessonProgress(
      groupId: widget.group.id,
      lessonIds: allIds,
      status: 'no_date',
    );
    await _loadProgress();
    widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تعليم جميع الدروس كمشروح مسبقاً 🟣'),
          backgroundColor: Colors.purple,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _resetAllProgress() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'تصفير خطة المجموعة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'هل أنت متأكد من تصفير حالة جميع الدروس لهذه المجموعة وإرجاعها كـ "لم تُشرح بعد"؟',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تصفير الخطة'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final allIds = lessons.map((l) => l.id).whereType<int>().toList();
    if (allIds.isEmpty) return;
    await widget.database.bulkSetGroupLessonProgress(
      groupId: widget.group.id,
      lessonIds: allIds,
      status: 'uncompleted',
    );
    await _loadProgress();
    widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تصفير خطة الدروس لهذه المجموعة'),
          backgroundColor: Colors.blueGrey,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _setBulkLessonsStatus(List<int> lessonIds, String status) async {
    if (lessonIds.isEmpty) return;
    await widget.database.bulkSetGroupLessonProgress(
      groupId: widget.group.id,
      lessonIds: lessonIds,
      status: status,
    );
    await _loadProgress();
    widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تسجيل هذا الدرس وكافة الدروس السابقة له (${lessonIds.length} درس) كـ "مشروح مسبقاً" ⚡',
          ),
          backgroundColor: const Color(0xFF7C3AED),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showStatusSelectorModal(CurriculumLessonModel lesson) {
    final curStatus =
        progressMap[lesson.id]?['status'] as String? ?? 'uncompleted';
    final lessonIndex = lessons.indexWhere((l) => l.id == lesson.id);
    bool includePrevious = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    lesson.lessonTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'اختر حالة شرح هذا الدرس لمجموعة ${widget.group.name}:',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _buildStatusOption(
                    ctx: modalCtx,
                    label: '🟢 الحصة الحالية (تم الشرح في حصة اليوم)',
                    status: 'current',
                    isSelected: curStatus == 'current',
                    color: const Color(0xFF059669),
                    lessonId: lesson.id!,
                  ),
                  const SizedBox(height: 10),
                  _buildStatusOption(
                    ctx: modalCtx,
                    label: '🔵 الحصة السابقة (تم الشرح في الحصة الماضية)',
                    status: 'previous',
                    isSelected: curStatus == 'previous',
                    color: Colors.blue.shade700,
                    lessonId: lesson.id!,
                  ),
                  const SizedBox(height: 10),
                  // Option: مشروح مسبقاً (مع تشيك بوكس لشمل كافة الدروس السابقة)
                  Container(
                    decoration: BoxDecoration(
                      color: curStatus == 'no_date'
                          ? Colors.purple.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: curStatus == 'no_date'
                            ? Colors.purple.shade700
                            : Colors.grey.shade300,
                        width: curStatus == 'no_date' ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            Navigator.pop(modalCtx);
                            if (includePrevious && lessonIndex > 0) {
                              final previousAndCurrentIds = lessons
                                  .sublist(0, lessonIndex + 1)
                                  .map((l) => l.id)
                                  .whereType<int>()
                                  .toList();
                              _setBulkLessonsStatus(
                                previousAndCurrentIds,
                                'no_date',
                              );
                            } else {
                              _setLessonStatus(lesson.id!, 'no_date');
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    includePrevious && lessonIndex > 0
                                        ? '🟣 مشروح مسبقاً (هذا الدرس وكافة الدروس السابقة)'
                                        : '🟣 مشروح مسبقاً (بدون تاريخ محدد)',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: curStatus == 'no_date'
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      color: curStatus == 'no_date'
                                          ? Colors.purple.shade700
                                          : null,
                                    ),
                                  ),
                                ),
                                if (curStatus == 'no_date')
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.purple.shade700,
                                    size: 22,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (lessonIndex > 0) ...[
                          const Divider(height: 1, indent: 14, endIndent: 14),
                          InkWell(
                            onTap: () {
                              setModalState(() {
                                includePrevious = !includePrevious;
                              });
                            },
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: includePrevious,
                                    activeColor: Colors.purple.shade700,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    onChanged: (val) {
                                      setModalState(() {
                                        includePrevious = val ?? false;
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'تطبيق على كافة الدروس السابقة أيضاً (${lessonIndex} درس سابق)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: includePrevious
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: includePrevious
                                            ? Colors.purple.shade800
                                            : Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildStatusOption(
                    ctx: modalCtx,
                    label: '⚪ لم يُشرح بعد (غير منجز)',
                    status: 'uncompleted',
                    isSelected:
                        curStatus == 'uncompleted' || curStatus == 'untaught',
                    color: Colors.grey.shade700,
                    lessonId: lesson.id!,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusOption({
    required BuildContext ctx,
    required String label,
    required String status,
    required bool isSelected,
    required Color color,
    required int lessonId,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        _setLessonStatus(lessonId, status);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? color : null,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final totalCount = lessons.length;
    final taughtLessons = lessons.where((l) {
      final s = progressMap[l.id]?['status'] as String?;
      return s == 'current' || s == 'previous' || s == 'no_date';
    }).toList();
    final taughtCount = taughtLessons.length;
    final remainingCount = totalCount - taughtCount;
    final double progressPercent = totalCount > 0
        ? (taughtCount / totalCount)
        : 0.0;

    List<CurriculumLessonModel> displayLessons = lessons;
    if (filterStatus == 'taught') {
      displayLessons = taughtLessons;
    } else if (filterStatus == 'remaining') {
      displayLessons = lessons.where((l) {
        final s = progressMap[l.id]?['status'] as String?;
        return s == null || s == 'uncompleted' || s == 'untaught';
      }).toList();
    }

    final unitsMap = <String, List<CurriculumLessonModel>>{};
    for (final l in displayLessons) {
      unitsMap.putIfAbsent(l.unitName, () => []).add(l);
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_stories_rounded,
                    color: Colors.indigo,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'خطة وشرح دروس: ${widget.group.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        activeCurriculumName != null
                            ? 'المنهج: $activeCurriculumName • ${widget.group.grade}'
                            : widget.group.grade,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
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
          ),
          const Divider(height: 1),

          // Body
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : lessons.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'لا توجد دروس مسجلة لهذه المجموعة بعد',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'يمكنك ربط المجموعة بمنهج دراسي رسمي أو إضافة دروس المنهج من قسم المناهج.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: widget.onChangeCurriculum,
                            icon: const Icon(Icons.link_rounded),
                            label: const Text('ربط المنهج الدراسي 🔗'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                    children: [
                      // Statistics Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [
                                    const Color(0xFF1E293B),
                                    const Color(0xFF0F172A),
                                  ]
                                : [Colors.indigo.shade50, Colors.blue.shade50],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.indigo.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'نسبة الإنجاز في المنهج:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '${(progressPercent * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: progressPercent,
                                minHeight: 8,
                                backgroundColor: Colors.grey.shade300,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.indigo,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatItem(
                                  'إجمالي الدروس',
                                  '$totalCount',
                                  Colors.blueGrey,
                                ),
                                _buildStatItem(
                                  'تم شرحها',
                                  '$taughtCount',
                                  const Color(0xFF059669),
                                ),
                                _buildStatItem(
                                  'متبقية',
                                  '$remainingCount',
                                  Colors.amber.shade900,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Bulk Actions Row
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                  horizontal: 8,
                                ),
                                side: BorderSide(color: Colors.purple.shade300),
                              ),
                              icon: const Icon(
                                Icons.playlist_add_check_circle,
                                size: 18,
                                color: Colors.purple,
                              ),
                              label: const Text(
                                'تعليم الكل كمشروح مسبقاً 🟣',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple,
                                ),
                              ),
                              onPressed: _markAllNoDate,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: 'تصفير خطة المجموعة',
                            icon: const Icon(
                              Icons.refresh_rounded,
                              color: Colors.blueGrey,
                            ),
                            onPressed: _resetAllProgress,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: Text(
                                'الكل ($totalCount)',
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: filterStatus == 'all',
                              onSelected: (_) =>
                                  setState(() => filterStatus = 'all'),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text(
                                'تم شرحها ($taughtCount)',
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: filterStatus == 'taught',
                              selectedColor: Colors.green.shade100,
                              onSelected: (_) =>
                                  setState(() => filterStatus = 'taught'),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: Text(
                                'متبقية ($remainingCount)',
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: filterStatus == 'remaining',
                              selectedColor: Colors.amber.shade100,
                              onSelected: (_) =>
                                  setState(() => filterStatus = 'remaining'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Lessons by Unit
                      ...unitsMap.entries.map((entry) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.15),
                            ),
                          ),
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            shape: const RoundedRectangleBorder(
                              side: BorderSide.none,
                            ),
                            collapsedShape: const RoundedRectangleBorder(
                              side: BorderSide.none,
                            ),
                            leading: const Icon(
                              Icons.folder_open_rounded,
                              color: Colors.indigo,
                            ),
                            title: Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                            subtitle: Text(
                              '${entry.value.length} دروس',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            children: entry.value.map((lesson) {
                              final prog = progressMap[lesson.id];
                              final status =
                                  prog?['status'] as String? ?? 'uncompleted';
                              final taughtDate =
                                  prog?['taught_date'] as String?;

                              return InkWell(
                                onTap: () => _showStatusSelectorModal(lesson),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: Colors.grey.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              lesson.lessonTitle,
                                              style: const TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (lesson
                                                .objectives
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                lesson.objectives,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                            if (taughtDate != null &&
                                                taughtDate.isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                'تاريخ الشرح: $taughtDate',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.blueGrey,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildStatusBadge(status),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status) {
      case 'current':
        bg = const Color(0xFF059669).withValues(alpha: 0.15);
        fg = const Color(0xFF059669);
        label = 'الحصة الحالية 🟢';
        icon = Icons.check_circle_rounded;
        break;
      case 'previous':
        bg = Colors.blue.withValues(alpha: 0.15);
        fg = Colors.blue.shade700;
        label = 'الحصة السابقة 🔵';
        icon = Icons.history_rounded;
        break;
      case 'no_date':
        bg = Colors.purple.withValues(alpha: 0.15);
        fg = Colors.purple.shade700;
        label = 'مشروح مسبقاً 🟣';
        icon = Icons.done_all_rounded;
        break;
      default:
        bg = Colors.grey.withValues(alpha: 0.12);
        fg = Colors.grey.shade700;
        label = 'لم يُشرح بعد ⚪';
        icon = Icons.radio_button_unchecked_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.bold,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
