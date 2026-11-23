import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_locale.dart';
import '../core/app_style.dart';
import '../core/attendance_timing_guard.dart';
import '../core/database/database_service.dart';
import '../core/security_service.dart';
import '../core/ui_customization_service.dart';
import '../models/curriculum_model.dart';
import '../models/exam_model.dart';
import '../models/group_model.dart';
import '../core/whatsapp_service.dart';
import '../models/student_model.dart';
import '../widgets/mockup_chart_painters.dart';
import 'certificates_screen.dart';
import 'curriculum_screen.dart';
import 'exams_screen.dart';
import 'finances_screen.dart';
import 'groups_screen.dart';
import 'scanner_screen.dart';
import 'timetable_screen.dart';
import 'today_attendance_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.database,
    required this.onNavigateTab,
    this.onNavConfigChanged,
  });

  final DatabaseService database;
  final Function(dynamic) onNavigateTab;
  final VoidCallback? onNavConfigChanged;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> metrics = {
    'totalStudents': 0,
    'todayAttendance': 0,
    'todayRevenue': 0.0,
    'totalDebt': 0.0,
    'totalGroups': 0,
  };
  String teacherName = 'أ. أحمد السيد';
  String centerName = 'أكاديمية المستقبل';
  String subjectName = 'الرياضيات والفيزياء';
  String teacherAvatar = '👨‍🏫';
  String? centerLogoPath;
  bool isLoading = true;
  bool _hasLoadedData = false;

  // Modular Widgets configuration
  List<DashboardWidgetDef> _widgetDefs = [];
  List<GroupModel> _todayGroups = [];
  Set<String> _todayCancelledGroupIds = {};
  int _completedLessons = 0;
  int _totalLessons = 0;
  List<GroupCurriculumProgress> _groupCurriculumProgress = [];
  List<ExamModel> _recentExams = [];
  List<Map<String, dynamic>> _dailyTodos = [];
  final TextEditingController _notesController = TextEditingController();
  bool _hasSavedNotesFeedback = false;
  StreamSubscription<DataChangeEvent>? _dataSub;

  final List<String> _educationalQuotes = [
    '«المعلم المتميز هو الذي يشعل فضول الطلاب ويقودهم لاكتشاف شغفهم العلمي.»',
    '«التعليم ليس ملء دلو، بل إيقاد شعلة مستمرة في عقول الأجيال.»',
    '«التشجيع كلمة سحرية تبني ثقة الطالب بنفسه وتفجر طاقاته الكامنة.»',
    '«تنوع أساليب التدريس وربطها بالواقع يصنع فارقاً حقيقياً في فهم الطالب.»',
    '«أعظم استثمار في الحياة هو بناء إنسان واعٍ قادر على التفكير والإبداع.»',
  ];

  @override
  void dispose() {
    _dataSub?.cancel();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _dataSub = widget.database.onDataChanged.listen((_) {
      if (mounted) _loadDashboard(silent: true);
    });
  }

  Future<void> _loadDashboard({bool silent = false}) async {
    if (!silent && !_hasLoadedData) {
      setState(() => isLoading = true);
    }

    try {
      final results = await Future.wait([
        widget.database.getDashboardMetrics(),
        widget.database.getSetting(
          'teacher_name',
          defaultValue: 'أ. أحمد السيد',
        ),
        widget.database.getSetting(
          'center_name',
          defaultValue: 'أكاديمية المستقبل',
        ),
        widget.database.getSetting(
          'subject_name',
          defaultValue: 'الرياضيات والفيزياء',
        ),
        widget.database.getSetting('teacher_avatar', defaultValue: '👨‍🏫'),
        widget.database.getSetting('teacher_photo_path', defaultValue: ''),
        widget.database.getSetting('custom_logo_path', defaultValue: ''),
        UiCustomizationService.loadDashboardWidgets(widget.database),
        widget.database.getGroups(),
        widget.database.getCurriculumLessons().catchError(
          (_) => <CurriculumLessonModel>[],
        ),
        widget.database.getExams().catchError((_) => <ExamModel>[]),
        widget.database.getDailyTodos().catchError(
          (_) => <Map<String, dynamic>>[],
        ),
        widget.database.getSetting('teacher_quick_notes', defaultValue: ''),
        widget.database.getFinancialMetrics(),
        widget.database.getGroupsCurriculumProgress().catchError(
          (_) => <GroupCurriculumProgress>[],
        ),
      ]);

      final m = <String, dynamic>{
        ...(results[0] as Map<String, dynamic>),
        ...(results[13] as Map<String, double>),
      };
      final t = results[1] as String;
      final c = results[2] as String;
      final s = results[3] as String;
      final avatar = results[4] as String;
      final teacherPhoto = results[5] as String;
      final customLogo = results[6] as String;
      final logo = teacherPhoto.isNotEmpty ? teacherPhoto : customLogo;

      final widgets = results[7] as List<DashboardWidgetDef>;
      final allGroups = results[8] as List<GroupModel>;
      final todayDayName = _getArabicDayName();
      final todayGroups =
          allGroups.where((g) => g.schedule.contains(todayDayName)).toList()
            ..sort(GroupModel.compareByStartTime);

      final lessons = results[9] as List<CurriculumLessonModel>;
      final completedL = lessons.where((l) => l.isCompleted).length;
      final totalL = lessons.length;

      final exams = results[10] as List<ExamModel>;
      final todos = results[11] as List<Map<String, dynamic>>;
      final notes = results[12] as String;
      final groupCurriculumProgressList =
          results[14] as List<GroupCurriculumProgress>;

      final todayDateStr = DateTime.now().toIso8601String().substring(0, 10);
      final cancels = await widget.database.getAllCancellationsForDate(
        todayDateStr,
      );
      final cancelledIds = cancels
          .where((c) => c['cancelled_by'] == 'teacher')
          .map((c) => c['group_id'] as String)
          .toSet();

      if (_notesController.text.isEmpty && notes.isNotEmpty) {
        _notesController.text = notes;
      }

      if (mounted) {
        setState(() {
          metrics = m;
          teacherName = t;
          centerName = c;
          subjectName = s;
          teacherAvatar = avatar;
          centerLogoPath = logo.isNotEmpty ? logo : null;
          _widgetDefs = widgets;
          _todayGroups = todayGroups;
          _todayCancelledGroupIds = cancelledIds;
          _completedLessons = completedL;
          _totalLessons = totalL;
          _groupCurriculumProgress = groupCurriculumProgressList;
          _recentExams = exams;
          _dailyTodos = todos;
          isLoading = false;
          _hasLoadedData = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _getArabicDayName() {
    final now = DateTime.now();
    const days = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    return days[now.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<Widget> children = [];
    final enabledDefs = _widgetDefs.where((w) => w.isEnabled).toList();

    // Dynamically render enabled widgets honoring user-defined order and size
    int wIdx = 0;
    while (wIdx < enabledDefs.length) {
      final current = enabledDefs[wIdx];
      final currentWidget = _buildWidgetById(current.id, isDark, primary);
      if (currentWidget == null) {
        wIdx++;
        continue;
      }

      // Check if this and next widget are both configured as half-width
      if (current.size == 'half' &&
          wIdx + 1 < enabledDefs.length &&
          enabledDefs[wIdx + 1].size == 'half') {
        final next = enabledDefs[wIdx + 1];
        final nextWidget = _buildWidgetById(next.id, isDark, primary);
        if (nextWidget != null) {
          children.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 150,
                        maxWidth: 360,
                      ),
                      child: currentWidget,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 150,
                        maxWidth: 360,
                      ),
                      child: nextWidget,
                    ),
                  ),
                ),
              ],
            ),
          );
          children.add(const SizedBox(height: 16));
          wIdx += 2;
          continue;
        }
      }

      // Single widget rendering based on size
      if (current.size == 'compact') {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 300, maxWidth: 420),
                child: currentWidget,
              ),
            ),
          ),
        );
      } else if (current.size == 'half') {
        children.add(
          FractionallySizedBox(
            widthFactor: 0.5,
            alignment: AlignmentDirectional.topStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 150, maxWidth: 360),
                child: currentWidget,
              ),
            ),
          ),
        );
      } else {
        children.add(currentWidget);
      }
      children.add(
        SizedBox(
          height: current.id == 'hero_header' || current.id == 'hero_launchpad'
              ? 8
              : 16,
        ),
      );
      wIdx++;
    }

    return RefreshIndicator(
      onRefresh: () => _loadDashboard(silent: true),
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 75),
        children: children.map((w) => RepaintBoundary(child: w)).toList(),
      ),
    );
  }

  Widget? _buildWidgetById(String id, bool isDark, Color primary) {
    switch (id) {
      case 'bento_grid_hub':
      case 'bento_dashboard':
        return _buildBentoGridHub(isDark, primary);
      case 'hero_header':
      case 'hero_launchpad':
        return _buildHeroHeader(isDark, primary);
      case 'kpi_cards':
      case 'unified_six_kpis':
        return _buildKpiCards(isDark);
      case 'active_students_card':
        return _buildActiveStudentsCard(isDark);
      case 'today_classes_attendance':
        return _buildTodayClassesAttendanceCard(isDark);
      case 'monthly_revenue_card':
        return _buildMonthlyRevenueCard(isDark);
      case 'pending_debt_card':
        return _buildPendingDebtCard(isDark);
      case 'net_profit_expenses_card':
        return _buildNetProfitExpensesCard(isDark);
      case 'exams_assessments_card':
      case 'upcoming_exams':
        return _buildUpcomingExamsCard(isDark);
      case 'attendance_callout':
        return _buildAttendanceCallout(isDark);
      case 'today_schedule':
      case 'today_groups_schedule':
        return _buildTodayScheduleCard(isDark, primary);
      case 'financial_overview':
      case 'financial_progress_bar':
        return _buildFinancialOverviewCard(isDark);
      case 'whatsapp_quick_center':
        return _buildWhatsAppQuickCenterCard(isDark);
      case 'recent_receipts_table':
        return _buildRecentReceiptsTableCard(isDark);
      case 'all_groups_schedule_table':
        return _buildAllGroupsScheduleCard(isDark);
      case 'fast_actions_platform':
      case 'quick_actions':
        return _buildLaunchpadGrid(isDark);
      case 'quick_notes_notepad':
        return _buildQuickNotesNotepad(isDark);
      case 'daily_todo_list':
        return _buildDailyTodoList(isDark);
      case 'monthly_performance_comparison':
        return _buildMonthlyPerformanceComparison(isDark);
      case 'attendance_discipline_tracker':
        return _buildAttendanceDisciplineTracker(isDark);
      case 'weekly_classes_calculator':
        return _buildWeeklyClassesCalculator(isDark);
      case 'curriculum_progress':
      case 'curriculum_progress_tracker':
        return _buildCurriculumProgressCard(isDark);
      case 'motivational_quote':
        return _buildMotivationalQuoteCard(isDark);
      case 'system_health':
        return _buildSystemHealthCard(isDark);
      default:
        return null;
    }
  }

  // --------------------------------------------------------------------------
  // WIDGET 1: Hero Header (Now Permanently Fixed in HomeShell Top Bar)
  // --------------------------------------------------------------------------
  Widget _buildHeroHeader(bool isDark, Color primary) {
    return const SizedBox.shrink();
  }

  // --------------------------------------------------------------------------
  // DESIGN 2: Bento Grid Hub (Exact match to uploaded Bento Grid UI mockup)
  // --------------------------------------------------------------------------
  Widget _buildBentoGridHub(bool isDark, Color primary) {
    final int studentCount = (metrics['totalStudents'] as num?)?.toInt() ?? 0;
    final int attendanceCount =
        (metrics['todayAttendance'] as num?)?.toInt() ?? 0;
    final int todayClassCount = _todayGroups.length;
    final double attendanceRate = studentCount > 0
        ? ((attendanceCount / studentCount) * 100).clamp(0, 100)
        : 0.0;
    final isAr = AppLocale.isArabic(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top Bento Card: Overview & Radial Metric (Exact match to Mockup top card)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? const Color(0xFF1E2D42) : const Color(0xFFE2E8F0),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card Header: Dots & Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () =>
                        _showBentoOptionsSheet(context, isDark, primary),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                        size: 20,
                      ),
                    ),
                  ),
                  Text(
                    isAr ? 'منصة إدارة المعلمة' : 'Teacher Management Platform',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF334155),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Metrics Row: Left columns + Right Radial Gauge (RTL layout)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Three Metrics Columns
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildBentoMiniStat(
                          count: '$todayClassCount',
                          label: isAr ? 'حصص\nاليوم' : "Today's\nClasses",
                          isDark: isDark,
                        ),
                        Container(
                          width: 1,
                          height: 34,
                          color: isDark
                              ? const Color(0xFF1E2D42)
                              : const Color(0xFFE2E8F0),
                        ),
                        _buildBentoMiniStat(
                          count: '$studentCount',
                          label: isAr ? 'الطلاب\nالمسجلين' : 'Total\nStudents',
                          isDark: isDark,
                        ),
                        Container(
                          width: 1,
                          height: 34,
                          color: isDark
                              ? const Color(0xFF1E2D42)
                              : const Color(0xFFE2E8F0),
                        ),
                        _buildBentoMiniStat(
                          count: '$attendanceCount',
                          label: isAr ? 'حاضرون\nاليوم' : 'Present\nToday',
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Attendance rate among all registered students.
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 58,
                        height: 58,
                        child: CircularProgressIndicator(
                          value: attendanceRate / 100,
                          strokeWidth: 4.5,
                          backgroundColor: const Color(
                            0xFF00F2FE,
                          ).withValues(alpha: 0.15),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF00F2FE),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${attendanceRate.toInt()}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                              height: 1.0,
                            ),
                          ),
                          const Text(
                            '%',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00F2FE),
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 2. Middle Bento Row: attendance and group shortcuts
        Row(
          children: [
            // Card 2: التحضير السريع مع إطار نيون فيروزي متوهج (Exact Bento Match)
            Expanded(
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TodayAttendanceScreen(database: widget.database),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  height: 145,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: const Color(0xFF00F2FE),
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFF00F2FE,
                        ).withValues(alpha: isDark ? 0.28 : 0.18),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isAr ? 'التحضير' : 'Attendance',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF00F2FE,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.fact_check_rounded,
                              color: Color(0xFF00F2FE),
                              size: 14,
                            ),
                          ),
                        ],
                      ),
                      Center(
                        child: Text(
                          '$attendanceCount',
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                            height: 1.0,
                          ),
                        ),
                      ),
                      Text(
                        isAr ? 'طالب حاضر اليوم' : 'Students present today',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Card 3: المجموعات مع زر "التفاصيل" الفيروزي (Exact Bento Match)
            Expanded(
              child: Container(
                height: 145,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF1E2D42)
                        : const Color(0xFFE2E8F0),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.35 : 0.05,
                      ),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(
                          isAr
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                          color: isDark
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8),
                          size: 18,
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF00F2FE,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.calendar_today_rounded,
                            color: Color(0xFF00F2FE),
                            size: 15,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAr ? 'المجموعات' : 'Groups',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          isAr ? 'التحضير السريع' : 'Quick Attendance',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  GroupsScreen(database: widget.database),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F2FE),
                          foregroundColor: const Color(0xFF0B1426),
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          isAr ? 'التفاصيل' : 'Details',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // 3. Third Bento Card: الحصص والمناهج / الجدول الزمني التفاعلي
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? const Color(0xFF1E2D42) : const Color(0xFFE2E8F0),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () =>
                        _showBentoScheduleOptions(context, isDark, primary),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                        size: 20,
                      ),
                    ),
                  ),
                  Text(
                    isAr ? 'الحصص والمناهج' : 'Classes & Curriculum',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_todayGroups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    isAr
                        ? 'لا توجد حصص مجدولة اليوم'
                        : 'No classes scheduled today',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                )
              else
                ..._todayGroups.take(3).toList().asMap().entries.map((entry) {
                  final group = entry.value;
                  final dotColors = [
                    const Color(0xFF00F2FE),
                    const Color(0xFF38BDF8),
                    const Color(0xFF818CF8),
                  ];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: entry.key == _todayGroups.take(3).length - 1
                          ? 0
                          : 10,
                    ),
                    child: _buildBentoScheduleRow(
                      time: group.startTime,
                      title: group.subject.isEmpty
                          ? group.name
                          : '${group.name} • ${group.subject}',
                      dotColor: dotColors[entry.key],
                      isDark: isDark,
                      onTap: () => _openScheduleAction(context, 0),
                    ),
                  );
                }),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 4. Fourth Bento Card: الغياب والتحضير السريع
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TodayAttendanceScreen(database: widget.database),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF1E2D42)
                    : const Color(0xFFE2E8F0),
                width: 1.1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  isAr
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  color: isDark
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                  size: 18,
                ),
                Row(
                  children: [
                    Text(
                      isAr ? 'الغياب والتحضير' : 'Absence & Attendance',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: Color(0xFF00F2FE),
                        size: 15,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBentoMiniStat({
    required String count,
    required String label,
    required bool isDark,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9.5,
            height: 1.15,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildBentoScheduleRow({
    required String time,
    required String title,
    required Color dotColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0x351E293B)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF475569),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dotColor.withValues(alpha: 0.6),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBentoOptionsSheet(
    BuildContext context,
    bool isDark,
    Color primary,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'خيارات لوحة بينتو الذكية',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFF00F2FE),
                ),
                title: const Text('تحديث بيانات اللوحة فوراً'),
                onTap: () {
                  Navigator.pop(context);
                  _loadDashboard(silent: true);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.tune_rounded,
                  color: Color(0xFF38BDF8),
                ),
                title: const Text('تخصيص الودجات في الإعدادات'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onNavigateTab(1); // Settings
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBentoScheduleOptions(
    BuildContext context,
    bool isDark,
    Color primary,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'إدارة الحصص والمناهج',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.calendar_month_rounded,
                  color: Color(0xFF00F2FE),
                ),
                title: const Text('كشف تحضير الحصص اليوم'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TodayAttendanceScreen(database: widget.database),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.menu_book_rounded,
                  color: Color(0xFF818CF8),
                ),
                title: const Text('استعراض خطة المناهج الكاملة'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CurriculumScreen(database: widget.database),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openScheduleAction(BuildContext context, int index) {
    HapticFeedback.selectionClick();
    if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CurriculumScreen(database: widget.database),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TodayAttendanceScreen(database: widget.database),
        ),
      );
    }
  }

  // --------------------------------------------------------------------------
  // WIDGET 2: Executive KPI Cards (3 Mockup Column Cards)
  // --------------------------------------------------------------------------
  Widget _buildKpiCards(bool isDark) {
    final double totalRevenue =
        (metrics['todayRevenue'] as num?)?.toDouble() ?? 0.0;
    final currencyLabel = AppLocale.tr(context, 'egp', ar: 'ج.م', en: 'EGP');
    final earningsLabel = '${totalRevenue.toInt()} $currencyLabel';
    final int studentCount = (metrics['totalStudents'] as num?)?.toInt() ?? 0;
    final int attendanceCount =
        (metrics['todayAttendance'] as num?)?.toInt() ?? 0;
    final int attendancePct = studentCount > 0
        ? ((attendanceCount / studentCount) * 100).round()
        : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 240;

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Text(
                  AppLocale.tr(
                    context,
                    'overview',
                    ar: 'نظرة عامة',
                    en: 'Overview',
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
              _buildCompactKpiTile(
                isDark: isDark,
                title: AppLocale.tr(
                  context,
                  'today_revenue',
                  ar: 'الأرباح',
                  en: 'Earnings',
                ),
                value: earningsLabel,
                color: const Color(0xFF10B981),
                icon: Icons.trending_up_rounded,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FinancesScreen(database: widget.database),
                    ),
                  ).then((_) => _loadDashboard());
                },
              ),
              const SizedBox(height: 8),
              _buildCompactKpiTile(
                isDark: isDark,
                title: AppLocale.tr(
                  context,
                  'attendance_rate',
                  ar: 'نسبة الحضور',
                  en: 'Attendance',
                ),
                value: '%$attendancePct',
                color: const Color(0xFF00F2FE),
                icon: Icons.fact_check_rounded,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TodayAttendanceScreen(database: widget.database),
                    ),
                  ).then((_) => _loadDashboard());
                },
              ),
              const SizedBox(height: 8),
              _buildCompactKpiTile(
                isDark: isDark,
                title: AppLocale.tr(
                  context,
                  'total_students',
                  ar: 'عدد الطلاب',
                  en: 'Students',
                ),
                value: '$studentCount',
                color: const Color(0xFF38BDF8),
                icon: Icons.groups_rounded,
                onTap: () => widget.onNavigateTab('students'),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header: "نظرة عامة"
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: Text(
                AppLocale.tr(
                  context,
                  'overview',
                  ar: 'نظرة عامة',
                  en: 'Overview',
                ),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),

            // 3 Vertical Cards Row matching reference mockup
            Row(
              children: [
                // Card 1: Revenue / Collections ("الأرباح") with neon green upward trend line
                Expanded(
                  child: _buildMockupStatCard(
                    isDark: isDark,
                    title: AppLocale.tr(
                      context,
                      'today_revenue',
                      ar: 'الأرباح',
                      en: 'Earnings',
                    ),
                    value: earningsLabel,
                    valueColor: const Color(0xFF10B981),
                    graphic: SizedBox(
                      height: 60,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: GreenTrendLinePainter(
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              FinancesScreen(database: widget.database),
                        ),
                      ).then((_) => _loadDashboard());
                    },
                  ),
                ),
                const SizedBox(width: 9),

                // Card 2: Attendance Rate ("نسبة الحضور") with circular progress gauge
                Expanded(
                  child: _buildMockupStatCard(
                    isDark: isDark,
                    title: AppLocale.tr(
                      context,
                      'attendance_rate',
                      ar: 'نسبة الحضور',
                      en: 'Attendance',
                    ),
                    value: '%$attendancePct',
                    valueColor: const Color(0xFF00F2FE),
                    graphic: SizedBox(
                      height: 60,
                      child: Center(
                        child: SizedBox(
                          width: 54,
                          height: 54,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: const Size(54, 54),
                                painter: CyanCircularProgressPainter(
                                  progress: attendancePct / 100.0,
                                  primaryColor: const Color(0xFF00F2FE),
                                  trackColor: isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              Text(
                                '%$attendancePct',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                textDirection: TextDirection.ltr,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              TodayAttendanceScreen(database: widget.database),
                        ),
                      ).then((_) => _loadDashboard());
                    },
                  ),
                ),
                const SizedBox(width: 9),

                // Card 3: Student Count ("عدد الطلاب") with glowing cyan wave
                Expanded(
                  child: _buildMockupStatCard(
                    isDark: isDark,
                    title: AppLocale.tr(
                      context,
                      'total_students',
                      ar: 'عدد الطلاب',
                      en: 'Students',
                    ),
                    value: '$studentCount',
                    valueColor: const Color(0xFF38BDF8),
                    graphic: SizedBox(
                      height: 55,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: CyanWavePainter(
                          color: const Color(0xFF00F2FE),
                        ),
                      ),
                    ),
                    onTap: () => widget.onNavigateTab('students'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompactKpiTile({
    required bool isDark,
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMockupStatCard({
    required bool isDark,
    required String title,
    required String value,
    required Color valueColor,
    required Widget graphic,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 145,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                graphic,
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // WIDGET 3: Attendance Callout
  // --------------------------------------------------------------------------
  Widget _buildAttendanceCallout(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D9488), Color(0xFF115E59)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Icon(
                Icons.assignment_turned_in_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'كشكول الحصة والمتابعة الفورية',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'تسجيل الحضور، درجات التسميع الشفوي، ومتابعة الواجبات',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0D9488),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TodayAttendanceScreen(database: widget.database),
                ),
              ).then((_) => _loadDashboard());
            },
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'فتح الكشكول',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // WIDGET 4: Upcoming Schedule (Mockup Styled Cards)
  // --------------------------------------------------------------------------
  Widget _buildTodayScheduleCard(bool isDark, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header: "الجدول القادم"
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  AppLocale.tr(
                    context,
                    'schedule',
                    ar: 'الجدول القادم',
                    en: 'Upcoming Schedule',
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_todayGroups.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_todayGroups.length} ${AppLocale.tr(context, 'classes', ar: 'حصص', en: 'Classes')}',
                    style: const TextStyle(
                      color: Color(0xFF00F2FE),
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TimetableScreen(database: widget.database),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 14,
                        color: Color(0xFF38BDF8),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'جدول المدرسة 🏫',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
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
        ),

        if (_todayGroups.isNotEmpty)
          Column(
            children: _todayGroups.map((g) {
              final isCancelled = _todayCancelledGroupIds.contains(g.id);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141C2B) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isCancelled
                        ? Colors.red.shade400
                        : (isDark
                              ? const Color(0xFF223147)
                              : const Color(0xFFE2E8F0)),
                    width: isCancelled ? 1.3 : 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.25 : 0.04,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      if (isCancelled) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.lock_rounded, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'تم قفل الحصة لأنها ملغية 🔒 • تم ارسال الاشعار مسبقا لولي الامر',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Color(0xFFDC2626),
                            duration: Duration(seconds: 4),
                          ),
                        );
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            title: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.lock_rounded, color: Colors.red, size: 24),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'الحصة مقفلة 🔒',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'تم قفل الحصة لأنها ملغية 🚫',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Colors.red,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'تم إلغاء حصة اليوم لمجموعة "${g.name}" وتم إرسال إشعار الإلغاء لولي الأمر مسبقاً ✅',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('إغلاق'),
                              ),
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D9488),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.tune_rounded, size: 16),
                                label: const Text('إدارة الحصة الملغاة 📋'),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TodayAttendanceScreen(
                                        database: widget.database,
                                        preselectedGroupId: g.id,
                                      ),
                                    ),
                                  ).then((_) => _loadDashboard());
                                },
                              ),
                            ],
                          ),
                        );
                        return;
                      }

                      final timingCheck =
                          AttendanceTimingGuard.checkGroupAttendanceAllowed(g);
                      if (!timingCheck.isAllowed && !isCancelled) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            title: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.fingerprint_rounded,
                                    color: Colors.amber,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'تأكيد البصمة لفتح التحضير 🔒',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.amber.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.info_outline,
                                        color: Colors.amber,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          AppLocale.localizeData(
                                            context,
                                            timingCheck.message ??
                                                'لا يمكن فتح التحضير إلا قبل موعد المجموعة بـ 5 دقائق فقط.',
                                          ),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'تحضير الحصة غير متاح الآن إلا بتأكيد بصمة إصبع الأستاذ لتخطي القفل الزمني والتحضير مبكراً.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(
                                  AppLocale.tr(
                                    context,
                                    'cancel',
                                    ar: 'إلغاء',
                                    en: 'Cancel',
                                  ),
                                ),
                              ),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D9488),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.fingerprint_rounded,
                                  size: 20,
                                ),
                                label: const Text(
                                  'تأكيد البصمة للفتح 👆',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  final didAuth =
                                      await SecurityService.authenticateWithBiometrics(
                                        context: context,
                                        database: widget.database,
                                        reason:
                                            'يرجى تأكيد البصمة لفتح تحضير مجموعة "${g.name}" قبل موعدها',
                                      );
                                  if (didAuth && context.mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TodayAttendanceScreen(
                                          database: widget.database,
                                          preselectedGroupId: g.id,
                                          initialSessionType: 'early_auth',
                                        ),
                                      ),
                                    ).then((_) => _loadDashboard());
                                  } else if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'فشل أو تم إلغاء التحقق من البصمة. لا يمكن فتح التحضير إلا في الموعد المسموح به ⚠️',
                                        ),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TodayAttendanceScreen(
                            database: widget.database,
                            preselectedGroupId: g.id,
                          ),
                        ),
                      ).then((_) => _loadDashboard());
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          // Indicator
                          Container(
                            width: 4.5,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isCancelled
                                  ? Colors.redAccent
                                  : const Color(0xFF00F2FE),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                  color: isCancelled
                                      ? Colors.red.withValues(alpha: 0.5)
                                      : const Color(0x8000F2FE),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Group Subject & Grade
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        AppLocale.localizeData(context, g.name),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isCancelled)
                                      Container(
                                        margin:
                                            const EdgeInsetsDirectional.only(
                                              start: 6,
                                            ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: Colors.red.shade400,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: const Text(
                                          'ملغية (المعلم) 🚫',
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  AppLocale.localizeData(
                                    context,
                                    g.grade.isNotEmpty ? g.grade : g.stage,
                                  ),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? const Color(0xFF64748B)
                                        : const Color(0xFF94A3B8),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Time & Student Count (constrained to avoid right overflow)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.40,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  AppLocale.localizeData(
                                    context,
                                    g.schedule.isNotEmpty
                                        ? g.schedule
                                        : AppLocale.tr(
                                            context,
                                            'no_schedule',
                                            ar: 'بدون موعد محدد',
                                            en: 'No time scheduled',
                                          ),
                                  ),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${g.maxStudents} ${AppLocale.tr(context, 'students', ar: 'طالب', en: 'Students')}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF64748B),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.people_outline_rounded,
                                      size: 13,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B),
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
                ),
              );
            }).toList(),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141C2B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF223147)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.wb_sunny_outlined,
                  color: Colors.orange,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLocale.tr(
                          context,
                          'no_sessions_today',
                          ar: 'لا توجد حصص مسجلة لهذا اليوم',
                          en: 'No sessions scheduled for today',
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocale.tr(
                          context,
                          'relax_day',
                          ar: 'يوم راحة أو مراجعة ذاتية، يمكنك الاطلاع على كشف كل المجموعات.',
                          en: 'Take a break or review your groups.',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  onPressed: () => widget.onNavigateTab('groups'),
                  child: Text(
                    AppLocale.tr(
                      context,
                      'all_groups',
                      ar: 'كل المجموعات',
                      en: 'All Groups',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // WIDGET 5: Financial Overview Card
  // --------------------------------------------------------------------------
  Widget _buildFinancialOverviewCard(bool isDark) {
    final double revenue = (metrics['todayRevenue'] as num?)?.toDouble() ?? 0.0;
    final double debt = (metrics['totalDebt'] as num?)?.toDouble() ?? 0.0;
    final double total = revenue + debt;
    final double percent = total > 0 ? (revenue / total).clamp(0.0, 1.0) : 0.0;
    final int percentInt = (percent * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isDark ? AppStyle.summaryCardGradient : null,
        color: isDark ? null : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppStyle.darkBorderGlow : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0EA5E9).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x4D38BDF8)),
                      ),
                      child: const Icon(
                        Icons.toll_rounded,
                        color: Color(0xFF38BDF8),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocale.tr(
                              context,
                              'financial_flow_title',
                              ar: 'مؤشر التدفق المالي والتحصيل',
                              en: 'Cash Flow & Collections',
                            ),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppLocale.tr(
                              context,
                              'financial_flow_sub',
                              ar: 'إجمالي التحصيل والسيولة النقدية',
                              en: 'Total Collections & Liquidity',
                            ),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x3310B981),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x6610B981)),
                ),
                child: Text(
                  '$percentInt%',
                  style: const TextStyle(
                    color: Color(0xFF34D399),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Glowing emerald progress bar
          Container(
            height: 10,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E3352) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: percent,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: AppStyle.emeraldProgressGradient,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x9910B981),
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0xFF10B981), blurRadius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${AppLocale.tr(context, 'collected', ar: 'المحصل', en: 'Collected')}: ${revenue.toInt()} ${AppLocale.tr(context, 'egp', ar: 'ج.م', en: 'EGP')}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                width: 1,
                height: 14,
                color: Colors.grey.withValues(alpha: 0.3),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0xFFEF4444), blurRadius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${AppLocale.tr(context, 'overdue', ar: 'المتأخرات', en: 'Overdue')}: ${debt.toInt()} ${AppLocale.tr(context, 'egp', ar: 'ج.م', en: 'EGP')}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: debt > 0 ? const Color(0xFFFB7185) : Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // WIDGET 6: Curriculum Progress Card (معدل نمو المناهج للمجموعات - واضحة ومفسرة)
  // --------------------------------------------------------------------------
  Widget _buildCurriculumProgressCard(bool isDark) {
    final theme = Theme.of(context);
    final isAr = AppLocale.isArabic(context);

    final groupsWithCurriculum =
        _groupCurriculumProgress.where((p) => p.hasCurriculum).toList();
    final totalGroupsCount = _groupCurriculumProgress.length;

    int totalLessonsAll = 0;
    int completedLessonsAll = 0;
    double sumPercents = 0.0;

    for (final p in groupsWithCurriculum) {
      totalLessonsAll += p.totalLessons;
      completedLessonsAll += p.completedLessons;
      sumPercents += p.progressPercent;
    }

    final double avgPercent = groupsWithCurriculum.isNotEmpty
        ? (sumPercents / groupsWithCurriculum.length).clamp(0.0, 1.0)
        : (_totalLessons > 0
            ? (_completedLessons / _totalLessons).clamp(0.0, 1.0)
            : 0.0);
    final int avgPercentInt = (avgPercent * 100).round();
    final int remainingLessonsAll =
        (totalLessonsAll - completedLessonsAll).clamp(0, 99999);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header with Badge & Navigation
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEA580C), Color(0xFFF97316)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr
                          ? 'معدل نمو وإنجاز المناهج للمجموعات'
                          : 'Curriculum Progress by Group',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAr
                          ? 'متابعة حية لنسبة الشرح والتقدم لكل مجموعة دراسية'
                          : 'Live curriculum growth rate for every active group',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CurriculumScreen(database: widget.database),
                    ),
                  ).then((_) => _loadDashboard());
                },
                child: Text(
                  isAr ? 'المناهج ➔' : 'Curriculum ➔',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // 2. Explanatory KPI Metrics Row (واضحة ومفسرة)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155).withValues(alpha: 0.5)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                _buildCurriculumMiniMetric(
                  label: isAr ? 'متوسط الإنجاز' : 'Avg Growth',
                  value: '$avgPercentInt%',
                  color: avgPercentInt >= 70
                      ? const Color(0xFF059669)
                      : (avgPercentInt >= 40
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFEA580C)),
                  icon: Icons.trending_up_rounded,
                  isDark: isDark,
                ),
                Container(
                  height: 32,
                  width: 1,
                  color:
                      isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
                _buildCurriculumMiniMetric(
                  label: isAr ? 'مجموعات بمناهج' : 'Bound Groups',
                  value: '${groupsWithCurriculum.length}/$totalGroupsCount',
                  color: const Color(0xFF6366F1),
                  icon: Icons.hub_rounded,
                  isDark: isDark,
                ),
                Container(
                  height: 32,
                  width: 1,
                  color:
                      isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
                _buildCurriculumMiniMetric(
                  label: isAr ? 'الدروس المشروحة' : 'Lessons Taught',
                  value: '$completedLessonsAll',
                  color: const Color(0xFF059669),
                  icon: Icons.check_circle_outline_rounded,
                  isDark: isDark,
                ),
                Container(
                  height: 32,
                  width: 1,
                  color:
                      isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
                _buildCurriculumMiniMetric(
                  label: isAr ? 'متبقي للشرح' : 'Remaining',
                  value: '$remainingLessonsAll',
                  color: const Color(0xFFD97706),
                  icon: Icons.hourglass_empty_rounded,
                  isDark: isDark,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 3. Group by Group Breakdown Cards (مفسرة ومفصلة)
          if (_groupCurriculumProgress.isEmpty) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 36,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isAr
                          ? 'لا توجد مجموعات مسجلة بعد'
                          : 'No groups registered yet',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAr
                          ? 'أضف مجموعاتك الدراسية واربط مناهجها لتتبع معدل النمو هنا.'
                          : 'Add your classes and link curricula to track growth rate here.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Column(
              children: _groupCurriculumProgress.map((p) {
                return _buildDashboardGroupCurriculumItem(
                  p,
                  isDark,
                  theme,
                  isAr,
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 12),

          // 4. Explanatory Legend / Guide Callout (تفسير واضح ومساعد للمعلم)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0284C7).withValues(alpha: 0.12)
                  : const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF0284C7).withValues(alpha: 0.3)
                    : const Color(0xFFBAE6FD),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 16,
                  color: isDark
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF0284C7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAr
                        ? '💡 كيف يُحسب معدل النمو؟ يُحدث المؤشر آلياً عند تسجيل شرح الدروس في حصص الحضور اليومية أو من خطة شرح المجموعة، لقياس مدى الالتزام بالخطة الزمنية المقررة.'
                        : '💡 How is this calculated? Progress updates automatically from attendance session logs and group lesson plans, ensuring schedule adherence.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFFBAE6FD)
                          : const Color(0xFF0369A1),
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurriculumMiniMetric({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardGroupCurriculumItem(
    GroupCurriculumProgress p,
    bool isDark,
    ThemeData theme,
    bool isAr,
  ) {
    final hasCurriculum = p.hasCurriculum;
    final percentInt = p.percentInt;

    final Color statusColor;
    if (percentInt >= 75) {
      statusColor = const Color(0xFF059669);
    } else if (percentInt >= 40) {
      statusColor = const Color(0xFF2563EB);
    } else if (percentInt > 0) {
      statusColor = const Color(0xFFD97706);
    } else {
      statusColor = Colors.grey.shade500;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.5)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? const Color(0xFF334155).withValues(alpha: 0.5)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: InkWell(
        onTap: () {
          widget.onNavigateTab('groups');
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color(p.colorValue),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.groupName,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
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
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          p.grade,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasCurriculum
                        ? '$percentInt% ${isAr ? 'مكتمل' : 'Done'}'
                        : (isAr ? 'غير مربوط' : 'Unbound'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (p.curriculumName != null && p.curriculumName!.isNotEmpty) ...[
              Text(
                '📚 ${p.curriculumName}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      isDark ? Colors.grey.shade300 : Colors.blueGrey.shade800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: hasCurriculum ? p.progressPercent : 0.0,
                minHeight: 7,
                backgroundColor: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    hasCurriculum
                        ? (isAr
                            ? 'تم شرح ${p.completedLessons} من ${p.totalLessons} درس (متبقي ${p.remainingLessons})'
                            : 'Completed ${p.completedLessons} of ${p.totalLessons} (Remaining ${p.remainingLessons})')
                        : (isAr
                            ? 'اضغط لربط المنهج الدراسي في قسم المجموعات 🔗'
                            : 'Tap to link curriculum in Groups tab 🔗'),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? Colors.grey.shade400
                          : (hasCurriculum
                              ? Colors.grey.shade700
                              : Colors.amber.shade800),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasCurriculum)
                  Text(
                    isAr ? 'عرض الخطة ➔' : 'View Plan ➔',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (p.nextLessonTitle != null && p.nextLessonTitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
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
                      '${isAr ? 'الدرس القادم' : 'Next lesson'}: ${p.nextLessonTitle}',
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
            ] else if (p.isCompleted) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 11,
                    color: Color(0xFF059669),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isAr
                        ? 'تم إنهاء المنهج بالكامل بنجاح 🎉'
                        : 'Curriculum completed successfully 🎉',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF059669),
                      fontWeight: FontWeight.bold,
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


  // --------------------------------------------------------------------------
  // WIDGET 7: Upcoming Exams Card
  // --------------------------------------------------------------------------
  Widget _buildUpcomingExamsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 4,
            spacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.military_tech_rounded,
                      color: Color(0xFF8B5CF6),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLocale.tr(
                      context,
                      'exams',
                      ar: 'الاختبارات',
                      en: 'Exams & Quizzes',
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExamsScreen(database: widget.database),
                    ),
                  ).then((_) => _loadDashboard());
                },
                child: Text(
                  AppLocale.tr(
                    context,
                    'exams_nav',
                    ar: 'كشف الامتحانات ➔',
                    en: 'Exams List ➔',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_recentExams.isNotEmpty)
            Column(
              children: _recentExams.take(2).map((e) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.quiz_outlined,
                        size: 18,
                        color: Color(0xFF8B5CF6),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppLocale.localizeData(context, e.title),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${AppLocale.tr(context, 'max_score', ar: 'الدرجة', en: 'Score')}: ${e.maxScore.toInt()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          else
            Text(
              AppLocale.tr(
                context,
                'no_recent_exams',
                ar: 'لا توجد اختبارات حديثة. اضغط لإضافة أول اختبار ورصد الدرجات.',
                en: 'No recent exams. Tap to add an exam and record scores.',
              ),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // WIDGET: WhatsApp Quick Center Card & Direct Actions
  // --------------------------------------------------------------------------
  Widget _buildWhatsAppQuickCenterCard(bool isDark) {
    final mutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.chat_rounded,
                  color: Color(0xFF25D366),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'مركز إرسال واتساب السريع',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'اختصارات وإرسال فوري دون مغادرة الشاشة',
                      style: TextStyle(fontSize: 11, color: mutedColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'سجل الرسائل المرسلة',
                icon: const Icon(Icons.history_rounded, size: 20),
                onPressed: () => _showSentLogsSheet(isDark),
              ),
              IconButton(
                tooltip: 'فتح مركز واتساب كاملاً',
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                onPressed: () => widget.onNavigateTab('whatsapp'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => _showDirectQuickSendSheet(isDark),
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: const Text(
                    'إرسال سريع لطالب',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF128C4A),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => widget.onNavigateTab('daily_report_send'),
                  icon: const Icon(Icons.summarize_rounded, size: 17),
                  label: const Text(
                    'تقرير اليوم',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الخدمات المباشرة:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: mutedColor,
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => widget.onNavigateTab('whatsapp'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'الكل ⬅',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF128C4A),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildQuickShortcutTile(
                title: 'إنذار غياب',
                icon: Icons.person_off_rounded,
                color: const Color(0xFFEF4444),
                tab: 'whatsapp_absence',
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildQuickShortcutTile(
                title: 'تذكير بالحصة',
                icon: Icons.alarm_rounded,
                color: const Color(0xFF3B82F6),
                tab: 'whatsapp_reminder',
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildQuickShortcutTile(
                title: 'مطالبة مالية',
                icon: Icons.request_quote_rounded,
                color: const Color(0xFF10B981),
                tab: 'whatsapp_payment',
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildQuickShortcutTile(
                title: 'متابعة الحصة',
                icon: Icons.assignment_turned_in_rounded,
                color: const Color(0xFF8B5CF6),
                tab: 'whatsapp_followup',
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildQuickShortcutTile(
                title: 'درجات امتحان',
                icon: Icons.grade_rounded,
                color: const Color(0xFF06B6D4),
                tab: 'whatsapp_exams',
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildQuickShortcutTile(
                title: 'إلغاء حصة',
                icon: Icons.event_busy_rounded,
                color: const Color(0xFFF97316),
                tab: 'whatsapp_cancellation',
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickShortcutTile({
    required String title,
    required IconData icon,
    required Color color,
    required String tab,
    required bool isDark,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onNavigateTab(tab),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: isDark ? 0.35 : 0.22),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 5),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDirectQuickSendSheet(bool isDark) async {
    final students = await widget.database.getStudents();
    if (!mounted) return;

    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد طلاب مسجلون حتى الآن لإرسال رسائل لهم.'),
        ),
      );
      return;
    }

    StudentModel? selectedStudent = students.first;
    String recipientType = 'parent'; // 'parent' or 'student'
    final messageController = TextEditingController();
    bool isSending = false;

    void applyTemplate(String text) {
      if (selectedStudent != null) {
        messageController.text = text.replaceAll('{name}', selectedStudent!.fullName);
      } else {
        messageController.text = text;
      }
    }

    // Default template
    applyTemplate('السلام عليكم ورحمة الله، نود إحاطتكم علماً بمتابعة الطالب {name}.');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final effectivePhone = (recipientType == 'parent')
                ? (selectedStudent?.parentPhone ?? '')
                : (selectedStudent?.studentPhone ?? '');

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
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
                          color: Colors.grey.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.bolt_rounded,
                            color: Color(0xFF25D366),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'إرسال سريع مباشر لطالب',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    const Text(
                      'اختر الطالب:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<StudentModel>(
                          isExpanded: true,
                          value: selectedStudent,
                          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          items: students.map((s) {
                            return DropdownMenuItem<StudentModel>(
                              value: s,
                              child: Text(
                                '${s.fullName} (${s.stage} - ${s.grade})',
                                style: const TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (newStudent) {
                            if (newStudent != null) {
                              setModalState(() {
                                selectedStudent = newStudent;
                                if (messageController.text.contains('{name}')) {
                                  messageController.text = messageController.text
                                      .replaceAll('{name}', newStudent.fullName);
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'جهة الإرسال:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.family_restroom_rounded, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'ولي الأمر (${selectedStudent?.parentPhone.isNotEmpty == true ? selectedStudent!.parentPhone : "لا يوجد"})',
                                  style: const TextStyle(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            selected: recipientType == 'parent',
                            onSelected: (selected) {
                              if (selected) {
                                setModalState(() => recipientType = 'parent');
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person_rounded, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'الطالب (${selectedStudent?.studentPhone.isNotEmpty == true ? selectedStudent!.studentPhone : "لا يوجد"})',
                                  style: const TextStyle(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            selected: recipientType == 'student',
                            onSelected: (selected) {
                              if (selected) {
                                setModalState(() => recipientType = 'student');
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'نماذج رسائل جاهزة:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.person_off_rounded, size: 14, color: Colors.red),
                            label: const Text('إنذار غياب', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              setModalState(() {
                                applyTemplate('السلام عليكم ورحمة الله، نحيطكم علماً بغياب الطالب {name} عن حصة اليوم. يرجى التواصل والمتابعة حرصاً على مستواه الدراسي.');
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            avatar: const Icon(Icons.check_circle_rounded, size: 14, color: Colors.green),
                            label: const Text('إشعار حضور', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              setModalState(() {
                                applyTemplate('السلام عليكم، تم تسجيل حضور الطالب {name} لحصة اليوم بنجاح والتزامه المميز في المجموعة.');
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            avatar: const Icon(Icons.request_quote_rounded, size: 14, color: Colors.teal),
                            label: const Text('مطالبة مالية', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              setModalState(() {
                                applyTemplate('السلام عليكم ورحمة الله، نود تذكير سيادتكم بالمصروفات المستحقة للطالب {name}. شاكرين حسن تعاونكم الدائم.');
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            avatar: const Icon(Icons.alarm_rounded, size: 14, color: Colors.blue),
                            label: const Text('تذكير بموعد', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              setModalState(() {
                                applyTemplate('السلام عليكم، تذكير بموعد الحصة القادمة للطالب {name}. نرجو الحضور في الموعد المحدد.');
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'نص الرسالة:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: messageController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'اكتب نص الرسالة هنا...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: isSending
                            ? null
                            : () async {
                                if (effectivePhone.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'رقم الهاتف غير مسجل لـ ${recipientType == "parent" ? "ولي الأمر" : "الطالب"}!',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }
                                if (messageController.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('يرجى كتابة نص الرسالة أولاً!'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                setModalState(() => isSending = true);

                                try {
                                  final result = await WhatsAppService.dispatchMessageDetailed(
                                    database: widget.database,
                                    phone: effectivePhone.trim(),
                                    message: messageController.text.trim(),
                                    studentId: selectedStudent?.id,
                                    studentName: selectedStudent?.fullName,
                                    recipientType: recipientType,
                                    category: 'quick_direct',
                                    logResult: true,
                                  );

                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }

                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          result.success
                                              ? 'تم فتح واتساب وجارٍ إرسال الرسالة بنجاح'
                                              : (result.errorMessage ?? 'تعذر إرسال الرسالة'),
                                        ),
                                        backgroundColor: result.success
                                            ? const Color(0xFF25D366)
                                            : Colors.red,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() => isSending = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('خطأ أثناء الإرسال: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                        icon: isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          isSending ? 'جارٍ الإرسال...' : 'إرسال الآن عبر واتساب',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
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

  Future<void> _showSentLogsSheet(bool isDark) async {
    final logs = await widget.database.getWhatsAppLogs(limit: 50);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.history_rounded, color: Color(0xFF25D366)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'سجل رسائل واتساب الحديثة',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: logs.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد رسائل مرسلة مسجلة في السجل حتى الآن.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: logs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final log = logs[index];
                            final status = log['status']?.toString() ?? 'sent';
                            final isSuccess = status == 'sent' || status == 'success';
                            final recipient = log['recipient_type'] == 'student'
                                ? 'الطالب'
                                : 'ولي الأمر';

                            return ListTile(
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: isSuccess
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.orange.withValues(alpha: 0.15),
                                child: Icon(
                                  isSuccess
                                      ? Icons.check_circle_rounded
                                      : Icons.schedule_rounded,
                                  color: isSuccess ? Colors.green : Colors.orange,
                                  size: 18,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      log['student_name']?.toString() ??
                                          log['phone']?.toString() ??
                                          'مجهول',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      recipient,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 3),
                                  Text(
                                    log['message']?.toString() ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${log['phone'] ?? ''} • ${log['created_at'] ?? ''}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }


  Widget _buildLaunchpadGrid(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppLocale.tr(context, 'sections', ar: 'الأقسام', en: 'Modules'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              AppLocale.tr(
                context,
                'quick_access',
                ar: 'الوصول السريع',
                en: 'Quick Access',
              ),
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.25,
          children: [
            _LaunchpadCard(
              title: AppLocale.tr(
                context,
                'finances',
                ar: 'المالية',
                en: 'Finances',
              ),
              subtitle: AppLocale.tr(
                context,
                'finances_sub',
                ar: 'إيصالات، دفاتر، سندات',
                en: 'Receipts, ledger & fees',
              ),
              icon: Icons.payments_rounded,
              gradient: const [Color(0xFF059669), Color(0xFF10B981)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FinancesScreen(database: widget.database),
                  ),
                ).then((_) => _loadDashboard());
              },
            ),
            _LaunchpadCard(
              title: AppLocale.tr(
                context,
                'exams',
                ar: 'الاختبارات',
                en: 'Exams',
              ),
              subtitle: AppLocale.tr(
                context,
                'exams_sub',
                ar: 'رصد النتائج وكشوف الأوائل',
                en: 'Results & leaderboards',
              ),
              icon: Icons.military_tech_rounded,
              gradient: const [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExamsScreen(database: widget.database),
                  ),
                ).then((_) => _loadDashboard());
              },
            ),
            _LaunchpadCard(
              title: AppLocale.tr(
                context,
                'certificates',
                ar: 'شهادات التقدير 🎓',
                en: 'Certificates 🎓',
              ),
              subtitle: AppLocale.tr(
                context,
                'certificates_sub_tile',
                ar: 'تصميم وإرسال شهادات الأوائل بالواتساب',
                en: 'Design & send top 10 certificates',
              ),
              icon: Icons.workspace_premium_rounded,
              gradient: const [Color(0xFFD97706), Color(0xFFFBBF24)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CertificatesScreen(database: widget.database),
                  ),
                );
              },
            ),
            _LaunchpadCard(
              title: AppLocale.tr(
                context,
                'curriculum',
                ar: 'المناهج',
                en: 'Curriculum',
              ),
              subtitle: AppLocale.tr(
                context,
                'curriculum_sub_tile',
                ar: 'توزيع الوحدات والدروس',
                en: 'Units & lesson breakdown',
              ),
              icon: Icons.menu_book_rounded,
              gradient: const [Color(0xFFEA580C), Color(0xFFF97316)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CurriculumScreen(database: widget.database),
                  ),
                ).then((_) => _loadDashboard());
              },
            ),
            _LaunchpadCard(
              title: AppLocale.tr(
                context,
                'scanner',
                ar: 'ماسح QR',
                en: 'QR Scanner',
              ),
              subtitle: AppLocale.tr(
                context,
                'scanner_sub',
                ar: 'تحضير ذكي وسريع بالصوت',
                en: 'Voice & instant check-in',
              ),
              icon: Icons.qr_code_scanner_rounded,
              gradient: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScannerScreen(database: widget.database),
                  ),
                ).then((_) => _loadDashboard());
              },
            ),
            _LaunchpadCard(
              title: AppLocale.tr(
                context,
                'students',
                ar: 'الطلاب',
                en: 'Students',
              ),
              subtitle: AppLocale.tr(
                context,
                'students_sub',
                ar: 'سجلات، اشتراكات، ديون',
                en: 'Roster, plans & dues',
              ),
              icon: Icons.badge_rounded,
              gradient: const [Color(0xFF2563EB), Color(0xFF3B82F6)],
              onTap: () => widget.onNavigateTab('students'),
            ),
            _LaunchpadCard(
              title: AppLocale.tr(
                context,
                'groups',
                ar: 'المجموعات',
                en: 'Groups',
              ),
              subtitle: AppLocale.tr(
                context,
                'groups_sub',
                ar: 'الجداول الأسبوعية والسعة',
                en: 'Weekly schedules & capacity',
              ),
              icon: Icons.groups_rounded,
              gradient: const [Color(0xFF475569), Color(0xFF64748B)],
              onTap: () => widget.onNavigateTab('groups'),
            ),
            _LaunchpadCard(
              title: AppLocale.tr(
                context,
                'timetable',
                ar: 'جدول الحصص',
                en: 'Timetable',
              ),
              subtitle: AppLocale.tr(
                context,
                'timetable_sub',
                ar: 'الجدول المدرسي والدروس',
                en: 'School & tutoring schedule',
              ),
              icon: Icons.calendar_month_rounded,
              gradient: const [Color(0xFF06B6D4), Color(0xFF2563EB)],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TimetableScreen(database: widget.database),
                  ),
                ).then((_) => _loadDashboard());
              },
            ),
            _LaunchpadCard(
              title: AppLocale.tr(
                context,
                'whatsapp',
                ar: 'واتساب',
                en: 'WhatsApp',
              ),
              subtitle: AppLocale.tr(
                context,
                'whatsapp_sub',
                ar: '8 قوالب واتساب آلية',
                en: '8 automated templates',
              ),
              icon: Icons.chat_rounded,
              gradient: const [Color(0xFF16A34A), Color(0xFF22C55E)],
              onTap: () => widget.onNavigateTab('whatsapp'),
            ),
            _LaunchpadCard(
              title: AppLocale.tr(
                context,
                'reports',
                ar: 'التقارير',
                en: 'Reports',
              ),
              subtitle: AppLocale.tr(
                context,
                'reports_sub',
                ar: 'رسوم بيانية وتصدير PDF',
                en: 'Analytics & PDF export',
              ),
              icon: Icons.insights_rounded,
              gradient: const [Color(0xFF4F46E5), Color(0xFF6366F1)],
              onTap: () => widget.onNavigateTab('reports'),
            ),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // WIDGET 10: Motivational Quote Card
  // --------------------------------------------------------------------------
  Widget _buildMotivationalQuoteCard(bool isDark) {
    final quoteIndex = (DateTime.now().day) % _educationalQuotes.length;
    final quote = _educationalQuotes[quoteIndex];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lightbulb_rounded,
              color: Colors.amber,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocale.tr(
                    context,
                    'daily_teacher_quote',
                    ar: 'إشراقة ورسالة المعلم اليومية',
                    en: 'Daily Educator Inspiration',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocale.localizeData(context, quote),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // WIDGET 11: System Health Card
  // --------------------------------------------------------------------------
  Widget _buildSystemHealthCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocale.tr(
                    context,
                    'db_protected',
                    ar: 'قاعدة البيانات محمية ومؤمنة محلياً',
                    en: 'Database Secured Locally',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  AppLocale.tr(
                    context,
                    'db_protected_sub',
                    ar: 'يعمل النظام دون الحاجة لإنترنت مع إمكانية النسخ الاحتياطي في أي وقت.',
                    en: 'Offline-first system with instant cloud & local backup support.',
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // NEW WIDGETS FROM CATALOG STORE
  // --------------------------------------------------------------------------

  // 1. بطاقة إجمالي الطلاب النشطين
  Widget _buildActiveStudentsCard(bool isDark) {
    final total = metrics['totalStudents'] ?? 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 240;
        final decoration = BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        );

        if (isCompact) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: decoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: Color(0xFF3B82F6),
                        size: 20,
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '$total ${AppLocale.tr(context, 'students', ar: 'طالب', en: 'Students')}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  AppLocale.tr(
                    context,
                    'active_students_total',
                    ar: 'إجمالي الطلاب النشطين',
                    en: 'Total Active Students',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocale.tr(
                    context,
                    'active_students_sub',
                    ar: 'المسجلين حالياً بالمجموعات',
                    en: 'Currently enrolled',
                  ),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: decoration,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: Color(0xFF3B82F6),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocale.tr(
                        context,
                        'active_students_total',
                        ar: 'إجمالي الطلاب النشطين',
                        en: 'Total Active Students',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocale.tr(
                        context,
                        'active_students_sub',
                        ar: 'المسجلين حالياً بالمجموعات الدراسية',
                        en: 'Currently enrolled in active study groups',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$total ${AppLocale.tr(context, 'students', ar: 'طالب', en: 'Students')}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 2. بطاقة حصص اليوم ومعدل الحضور
  Widget _buildTodayClassesAttendanceCard(bool isDark) {
    final todayCount = _todayGroups.length;
    final present = metrics['todayAttendance'] ?? 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 240;
        final decoration = BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        );

        if (isCompact) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: decoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: Color(0xFFEF4444),
                        size: 20,
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '$todayCount ${AppLocale.tr(context, 'classes', ar: 'حصص', en: 'Classes')}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  AppLocale.tr(
                    context,
                    'today_classes_title',
                    ar: 'حصص اليوم',
                    en: "Today's Classes",
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocale.isArabic(context)
                      ? 'حضور $present طالب'
                      : '$present students checked in',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: decoration,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Color(0xFFEF4444),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocale.tr(
                        context,
                        'today_classes_title',
                        ar: 'حصص اليوم',
                        en: "Today's Classes",
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocale.isArabic(context)
                          ? '$todayCount حصص مجدولة • حضور $present طالب حتى الآن'
                          : '$todayCount classes scheduled • $present students checked in so far',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 3. بطاقة الإيرادات والتحصيلات للشهر
  Widget _buildMonthlyRevenueCard(bool isDark) {
    final rev = (metrics['todayRevenue'] as num?)?.toDouble() ?? 0.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 240;
        final decoration = BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        );

        if (isCompact) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: decoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.trending_up_rounded,
                        color: Color(0xFF059669),
                        size: 20,
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${rev.toStringAsFixed(0)} ${AppLocale.tr(context, 'egp', ar: 'ج.م', en: 'EGP')}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  AppLocale.tr(
                    context,
                    'today_revenue',
                    ar: 'إيرادات اليوم',
                    en: "Today's Revenue",
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocale.tr(
                    context,
                    'today_rev_sub',
                    ar: 'متحصلات الاشتراكات',
                    en: 'Fee collections',
                  ),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: decoration,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: Color(0xFF059669),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocale.tr(
                        context,
                        'today_revenue',
                        ar: 'إيرادات اليوم',
                        en: "Today's Revenue",
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocale.tr(
                        context,
                        'today_rev_sub',
                        ar: 'متحصلات الاشتراكات',
                        en: 'Subscription & fee collections',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${rev.toStringAsFixed(0)} ${AppLocale.tr(context, 'egp', ar: 'ج.م', en: 'EGP')}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 4. بطاقة المتأخرات والمبالغ المعلقة
  Widget _buildPendingDebtCard(bool isDark) {
    final debt = (metrics['totalDebt'] as num?)?.toDouble() ?? 0.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 240;
        final decoration = BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        );

        if (isCompact) {
          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FinancesScreen(
                    database: widget.database,
                    initialTabIndex: 1,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: decoration,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF59E0B,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFF59E0B),
                          size: 20,
                        ),
                      ),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${debt.toStringAsFixed(0)} ${AppLocale.tr(context, 'egp', ar: 'ج.م', en: 'EGP')}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLocale.tr(
                      context,
                      'pending_dues_title',
                      ar: 'المتأخرات والمعلقات',
                      en: 'Pending Dues',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocale.tr(
                      context,
                      'pending_dues_sub',
                      ar: 'المتبقي على الطلاب',
                      en: 'Outstanding balances',
                    ),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }

        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FinancesScreen(
                  database: widget.database,
                  initialTabIndex: 1,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: decoration,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFF59E0B),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocale.tr(
                          context,
                          'pending_dues_title',
                          ar: 'المتأخرات والمبالغ المعلقة',
                          en: 'Pending & Overdue Dues',
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppLocale.tr(
                          context,
                          'pending_dues_sub',
                          ar: 'إجمالي المتبقي على الطلاب قيد المطالبة',
                          en: 'Total outstanding balances awaiting collection',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${debt.toStringAsFixed(0)} ${AppLocale.tr(context, 'egp', ar: 'ج.م', en: 'EGP')}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 5. بطاقة صافي الأرباح والمصروفات
  Widget _buildNetProfitExpensesCard(bool isDark) {
    final netProfit = (metrics['netProfit'] as num?)?.toDouble() ?? 0.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 240;
        final decoration = BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        );

        if (isCompact) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: decoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.payments_rounded,
                        color: Color(0xFF14B8A6),
                        size: 20,
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${netProfit.toStringAsFixed(0)} ${AppLocale.tr(context, 'egp', ar: 'ج.م', en: 'EGP')}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF14B8A6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  AppLocale.tr(
                    context,
                    'net_profit_title',
                    ar: 'صافي التدفق والأرباح',
                    en: 'Net Flow & Profit',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocale.tr(
                    context,
                    'net_profit_sub',
                    ar: 'مؤشر الإيرادات المستقرة',
                    en: 'Stable revenue indicator',
                  ),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: decoration,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.payments_rounded,
                  color: Color(0xFF14B8A6),
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocale.tr(
                        context,
                        'net_profit_title',
                        ar: 'صافي التدفق والأرباح',
                        en: 'Net Operating Flow & Profit',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocale.tr(
                        context,
                        'net_profit_sub',
                        ar: 'مؤشر الإيرادات المستقرة بعد العمليات',
                        en: 'Stable revenue indicator after operating expenses',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${netProfit.toStringAsFixed(0)} ${AppLocale.tr(context, 'egp', ar: 'ج.م', en: 'EGP')}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF14B8A6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 6. أحدث إيصالات القبض والعمليات المالية
  Widget _buildRecentReceiptsTableCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: Color(0xFF475569)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocale.tr(
                    context,
                    'recent_receipts_title',
                    ar: 'أحدث إيصالات القبض والعمليات المالية',
                    en: 'Recent Receipts & Financial Ledger',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FinancesScreen(database: widget.database),
                  ),
                ),
                child: Text(
                  AppLocale.tr(
                    context,
                    'view_all_arrow',
                    ar: 'عرض الكل ➔',
                    en: 'View All ➔',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 6),
          Text(
            AppLocale.tr(
              context,
              'recent_receipts_status',
              ar: 'تم تسجيل كافة العمليات النقدية والاشتراكات بسجلات السنتر بنجاح ✅',
              en: 'All transactions & student subscriptions logged successfully ✅',
            ),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // 7. جدول مواعيد المجموعات
  Widget _buildAllGroupsScheduleCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_view_week_rounded,
                color: Color(0xFFDC2626),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLocale.tr(
                    context,
                    'weekly_groups_schedule',
                    ar: 'جدول مواعيد المجموعات الأسبوعي',
                    en: 'Weekly Groups Schedule',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onPressed: () => widget.onNavigateTab('groups'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppLocale.isArabic(context)
                ? '${metrics['totalGroups'] ?? 0} مجموعات نشطة ومجدولة موزعة على أيام الأسبوع.'
                : '${metrics['totalGroups'] ?? 0} active groups scheduled across weekdays.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // 8. مفكرة الملاحظات السريعة للمعلم
  Widget _buildQuickNotesNotepad(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Color(0xFFF59E0B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocale.tr(
                        context,
                        'quick_notes_title',
                        ar: 'مفكرة الملاحظات والتذكيرات السريعة',
                        en: 'Quick Notes & Reminders',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      AppLocale.tr(
                        context,
                        'quick_notes_sub',
                        ar: 'ملاحظات حرة للمعلم تحفظ تلقائياً',
                        en: 'Educator notes saved automatically',
                      ),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (_hasSavedNotesFeedback)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check,
                        size: 12,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        AppLocale.tr(
                          context,
                          'saved',
                          ar: 'تم الحفظ',
                          en: 'Saved',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(
                      0xFFF59E0B,
                    ).withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(6),
                  ),
                  icon: const Icon(
                    Icons.save_rounded,
                    color: Color(0xFFF59E0B),
                    size: 18,
                  ),
                  tooltip: AppLocale.tr(
                    context,
                    'save_notes',
                    ar: 'حفظ الملاحظات',
                    en: 'Save Notes',
                  ),
                  onPressed: () async {
                    await widget.database.setSetting(
                      'teacher_quick_notes',
                      _notesController.text.trim(),
                    );
                    setState(() => _hasSavedNotesFeedback = true);
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted)
                        setState(() => _hasSavedNotesFeedback = false);
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 4,
            minLines: 2,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              height: 1.4,
            ),
            onChanged: (val) {
              widget.database.setSetting('teacher_quick_notes', val.trim());
            },
            decoration: InputDecoration(
              hintText: AppLocale.tr(
                context,
                'notes_hint',
                ar: 'اكتب هنا ملاحظاتك وتذكيراتك السريعة لليوم، ويتم حفظها مباشرة...',
                en: 'Write your quick reminders and notes here...',
              ),
              hintStyle: TextStyle(
                fontSize: 12,
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFF94A3B8),
              ),
              filled: true,
              fillColor: isDark
                  ? const Color(0xFF0F172A)
                  : const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFF59E0B),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 9. قائمة المهام اليومية التفاعلية
  Widget _buildDailyTodoList(bool isDark) {
    final completedCount = _dailyTodos.where((t) => t['is_done'] == 1).length;
    final totalCount = _dailyTodos.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.check_box_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocale.tr(
                        context,
                        'daily_todo_title',
                        ar: 'قائمة المهام اليومية للأستاذ',
                        en: "Daily Teacher Checklist",
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      AppLocale.tr(
                        context,
                        'daily_todo_sub',
                        ar: 'مهام ومتابعات العمل اليومي',
                        en: 'Daily tasks & follow-ups',
                      ),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (totalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (completedCount == totalCount && totalCount > 0
                                ? const Color(0xFF10B981)
                                : const Color(0xFF3B82F6))
                            .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          (completedCount == totalCount && totalCount > 0
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF3B82F6))
                              .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$completedCount / $totalCount ${AppLocale.tr(context, 'completed_tasks', ar: 'مكتملة', en: 'Done')}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: completedCount == totalCount && totalCount > 0
                          ? const Color(0xFF10B981)
                          : const Color(0xFF3B82F6),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(
                    0xFF10B981,
                  ).withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(6),
                ),
                icon: const Icon(
                  Icons.add_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
                tooltip: AppLocale.tr(
                  context,
                  'add_new_task',
                  ar: 'إضافة مهمة جديدة',
                  en: 'Add New Task',
                ),
                onPressed: () => _showAddTodoDialog(context, isDark),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_dailyTodos.isEmpty)
            InkWell(
              onTap: () => _showAddTodoDialog(context, isDark),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 14,
                ),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.assignment_add,
                      size: 30,
                      color: isDark
                          ? const Color(0xFF475569)
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocale.tr(
                        context,
                        'no_todos_yet',
                        ar: 'لا توجد مهام مضافة بعد، اضغط هنا لإضافة مهمة جديدة',
                        en: 'No tasks added yet. Tap here to add a new task',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._dailyTodos.map((todo) {
              final id = todo['id'] as int;
              final title = todo['title'] as String;
              final isDone = (todo['is_done'] as int) == 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () async {
                    await widget.database.toggleDailyTodo(id, !isDone);
                    final updated = await widget.database.getDailyTodos();
                    if (mounted) setState(() => _dailyTodos = updated);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDone
                          ? (isDark
                                ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                                : const Color(0xFFF1F5F9))
                          : (isDark
                                ? const Color(0xFF0F172A)
                                : const Color(0xFFF8FAFC)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDone
                            ? (isDark
                                  ? const Color(0x33334155)
                                  : const Color(0xFFE2E8F0))
                            : (isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFCBD5E1)),
                      ),
                    ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDone
                                ? const Color(0xFF10B981)
                                : Colors.transparent,
                            border: Border.all(
                              color: isDone
                                  ? const Color(0xFF10B981)
                                  : Colors.grey,
                              width: 1.8,
                            ),
                          ),
                          child: isDone
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            AppLocale.localizeData(context, title),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isDone
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: Colors.grey,
                              color: isDone
                                  ? Colors.grey
                                  : (isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A)),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 30,
                            minHeight: 30,
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: Color(0xFFEF4444),
                          ),
                          tooltip: AppLocale.tr(
                            context,
                            'delete_task',
                            ar: 'حذف المهمة',
                            en: 'Delete Task',
                          ),
                          onPressed: () async {
                            await widget.database.deleteDailyTodo(id);
                            final updated = await widget.database
                                .getDailyTodos();
                            if (mounted) setState(() => _dailyTodos = updated);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showAddTodoDialog(BuildContext context, bool isDark) {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(
              Icons.add_task_rounded,
              color: Color(0xFF10B981),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              AppLocale.tr(
                context,
                'add_todo_modal',
                ar: 'إضافة مهمة يومية جديدة',
                en: 'Add New Daily Task',
              ),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: AppLocale.tr(
              context,
              'todo_input_hint',
              ar: 'اكتب نص المهمة هنا...',
              en: 'Enter task description...',
            ),
            filled: true,
            fillColor: isDark
                ? const Color(0xFF0F172A)
                : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocale.tr(context, 'cancel', ar: 'إلغاء', en: 'Cancel'),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final text = textCtrl.text.trim();
              if (text.isNotEmpty) {
                await widget.database.addDailyTodo(text);
                final updated = await widget.database.getDailyTodos();
                if (mounted) setState(() => _dailyTodos = updated);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: Text(
              AppLocale.tr(
                context,
                'add_task_btn',
                ar: 'إضافة المهمة',
                en: 'Add Task',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 10. مقارنة الأداء المالي
  Widget _buildMonthlyPerformanceComparison(bool isDark) {
    final double todayRev =
        (metrics['todayRevenue'] as num?)?.toDouble() ?? 0.0;
    final double totalDbt = (metrics['totalDebt'] as num?)?.toDouble() ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.show_chart_rounded,
              color: Color(0xFFEF4444),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocale.tr(
                    context,
                    'perf_comp_title',
                    ar: 'مقارنة الأداء والتدفق المالي',
                    en: 'Cash Flow Performance',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppLocale.isArabic(context)
                      ? 'إيراد اليوم: ${todayRev.toStringAsFixed(0)} ج.م • المستحقات المتبقية: ${totalDbt.toStringAsFixed(0)} ج.م'
                      : "Today's Rev: ${todayRev.toStringAsFixed(0)} EGP • Outstanding: ${totalDbt.toStringAsFixed(0)} EGP",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 11. مؤشر انضباط الحضور العام
  Widget _buildAttendanceDisciplineTracker(bool isDark) {
    final int todayAtt = (metrics['todayAttendance'] as num?)?.toInt() ?? 0;
    final int totalSt = (metrics['totalStudents'] as num?)?.toInt() ?? 0;
    final String statusText = totalSt > 0
        ? (AppLocale.isArabic(context)
              ? 'حضور اليوم: $todayAtt من إجمالي $totalSt طالب مسجل'
              : "Today's Attendance: $todayAtt of $totalSt enrolled students")
        : (AppLocale.isArabic(context)
              ? 'سجل حضور وغياب الحصص لمتابعة انضباط الطلاب بدقة.'
              : 'Record class attendance to track student discipline accurately.');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.pie_chart_outline_rounded,
              color: Color(0xFFF97316),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocale.tr(
                    context,
                    'att_discipline_title',
                    ar: 'مؤشر انضباط الحضور والمتابعة',
                    en: 'Attendance Discipline Index',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusText,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 12. حاسبة الحصص الأسبوعية
  Widget _buildWeeklyClassesCalculator(bool isDark) {
    final int todayGroupsCount = _todayGroups.length;
    final int totalGroupsCount = (metrics['totalGroups'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.electric_bolt_rounded,
              color: Color(0xFFF59E0B),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocale.tr(
                    context,
                    'weekly_classes_calc_title',
                    ar: 'جدول ومؤشرات الحصص',
                    en: 'Class Schedule Metrics',
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppLocale.isArabic(context)
                      ? 'مجدول اليوم $todayGroupsCount مجموعة من إجمالي $totalGroupsCount مجموعة دراسية'
                      : 'Scheduled today: $todayGroupsCount of $totalGroupsCount study groups',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Interactive Dashboard Customization BottomSheet
  // --------------------------------------------------------------------------
  // ignore: unused_element
  void _openCustomizeWidgetsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Container(
            height: MediaQuery.of(context).size.height * 0.82,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(
                              0xFF4F46E5,
                            ).withValues(alpha: 0.15),
                            foregroundColor: const Color(0xFF4F46E5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openWidgetCatalogStoreSheet();
                          },
                          icon: const Icon(Icons.storefront_rounded, size: 16),
                          label: Text(
                            AppLocale.tr(
                              context,
                              'store_btn',
                              ar: 'المتجر 🏬',
                              en: 'Store 🏬',
                            ),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: AppLocale.isArabic(context)
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocale.tr(
                                  context,
                                  'customize_widgets_title',
                                  ar: 'تخصيص وترتيب الودجات',
                                  en: 'Customize & Order Widgets',
                                ),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppLocale.tr(
                                  context,
                                  'customize_widgets_sub',
                                  ar: 'اسحب ☰ للترتيب، وفعل ما ترغب بإظهاره',
                                  en: 'Drag ☰ to reorder, toggle to enable',
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      itemCount: _widgetDefs.length,
                      onReorderItem: (oldIndex, newIndex) {
                        setSheetState(() {
                          final item = _widgetDefs.removeAt(oldIndex);
                          _widgetDefs.insert(newIndex, item);
                        });
                        setState(() {});
                        UiCustomizationService.saveDashboardWidgets(
                          widget.database,
                          _widgetDefs,
                        );
                      },
                      itemBuilder: (context, index) {
                        final w = _widgetDefs[index];

                        return Container(
                          key: ValueKey(w.id),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: w.iconColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(w.icon, color: w.iconColor, size: 20),
                            ),
                            title: Text(
                              AppLocale.localizeData(context, w.title),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              AppLocale.localizeData(context, w.subtitle),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch.adaptive(
                                  value: w.isEnabled,
                                  onChanged: (val) {
                                    setSheetState(() => w.isEnabled = val);
                                    setState(() {});
                                    UiCustomizationService.saveDashboardWidgets(
                                      widget.database,
                                      _widgetDefs,
                                    );
                                  },
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.drag_handle_rounded,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              setSheetState(() {
                                _widgetDefs =
                                    UiCustomizationService.getMasterDashboardWidgets();
                              });
                              setState(() {});
                              UiCustomizationService.saveDashboardWidgets(
                                widget.database,
                                _widgetDefs,
                              );
                            },
                            child: Text(
                              AppLocale.tr(
                                context,
                                'restore_defaults',
                                ar: 'استعادة الترتيب الافتراضي',
                                en: 'Restore Defaults',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              AppLocale.tr(
                                context,
                                'done',
                                ar: 'تم',
                                en: 'Done',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
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
          );
        },
      ),
    );
  }

  void _openWidgetCatalogStoreSheet() {
    String selectedCategory = 'all';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final isAr = AppLocale.isArabic(context);
            final categories = [
              {
                'id': 'all',
                'label': AppLocale.tr(
                  context,
                  'cat_all',
                  ar: 'الكل',
                  en: 'All',
                ),
              },
              {
                'id': 'overview',
                'label': AppLocale.tr(
                  context,
                  'cat_overview',
                  ar: 'نظرة عامة',
                  en: 'Overview',
                ),
              },
              {
                'id': 'kpis',
                'label': AppLocale.tr(
                  context,
                  'cat_kpis',
                  ar: 'مؤشرات الأداء',
                  en: 'KPIs',
                ),
              },
              {
                'id': 'schedules',
                'label': AppLocale.tr(
                  context,
                  'cat_schedules',
                  ar: 'الجداول والحصص',
                  en: 'Schedules',
                ),
              },
              {
                'id': 'finances',
                'label': AppLocale.tr(
                  context,
                  'cat_finances',
                  ar: 'الماليات والتحصيل',
                  en: 'Finances',
                ),
              },
              {
                'id': 'tools',
                'label': AppLocale.tr(
                  context,
                  'cat_tools',
                  ar: 'الأدوات والمفكرة',
                  en: 'Tools & Notes',
                ),
              },
            ];

            final filteredList = selectedCategory == 'all'
                ? _widgetDefs
                : _widgetDefs
                      .where((w) => w.category == selectedCategory)
                      .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 25,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.grey.shade200,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: isAr
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocale.tr(
                                  context,
                                  'widget_catalog_title',
                                  ar: 'كتالوج ودجات لوحة التحكم',
                                  en: 'Dashboard Widget Catalog',
                                ),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppLocale.tr(
                                  context,
                                  'widget_catalog_sub',
                                  ar: 'اختر بطاقة لإضافتها مباشرة إلى شاشتك الرئيسية',
                                  en: 'Choose a widget to add to your home screen',
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Color(0xFF6366F1),
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Category filter chips
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      reverse: isAr,
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final cat = categories[idx];
                        final isSel = selectedCategory == cat['id'];
                        return ChoiceChip(
                          label: Text(
                            cat['label']!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSel
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSel
                                  ? Colors.white
                                  : (isDark
                                        ? Colors.grey.shade300
                                        : Colors.grey.shade800),
                            ),
                          ),
                          selected: isSel,
                          selectedColor: const Color(0xFF4F46E5),
                          backgroundColor: isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSel
                                  ? Colors.transparent
                                  : Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          onSelected: (_) {
                            setSheetState(() => selectedCategory = cat['id']!);
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),

                  // List of widget cards
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredList.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final w = filteredList[index];
                        final isAdded = w.isEnabled;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isAdded
                                  ? const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.3)
                                  : (isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFE2E8F0)),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.04,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: isAdded
                                      ? (isDark
                                            ? const Color(0xFF334155)
                                            : Colors.grey.shade200)
                                      : const Color(0xFF4F46E5),
                                  foregroundColor: isAdded
                                      ? (isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade700)
                                      : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () {
                                  final masterIdx = _widgetDefs.indexWhere(
                                    (it) => it.id == w.id,
                                  );
                                  if (masterIdx != -1) {
                                    setSheetState(() {
                                      _widgetDefs[masterIdx].isEnabled =
                                          !isAdded;
                                    });
                                    setState(() {});
                                    UiCustomizationService.saveDashboardWidgets(
                                      widget.database,
                                      _widgetDefs,
                                    );
                                  }
                                },
                                icon: Icon(
                                  isAdded
                                      ? Icons.check_rounded
                                      : Icons.add_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  isAdded
                                      ? AppLocale.tr(
                                          context,
                                          'enabled',
                                          ar: 'مفعلة',
                                          en: 'Enabled',
                                        )
                                      : AppLocale.tr(
                                          context,
                                          'add_plus',
                                          ar: 'إضافة +',
                                          en: 'Add +',
                                        ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: isAr
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: isAr
                                          ? MainAxisAlignment.end
                                          : MainAxisAlignment.start,
                                      children: [
                                        if (isAdded) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFF10B981,
                                              ).withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(
                                                  0xFF10B981,
                                                ).withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Text(
                                              AppLocale.tr(
                                                context,
                                                'added_badge',
                                                ar: 'مضاف',
                                                en: 'Added',
                                              ),
                                              style: const TextStyle(
                                                color: Color(0xFF10B981),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Flexible(
                                          child: Text(
                                            AppLocale.localizeData(
                                              context,
                                              w.title,
                                            ),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            textAlign: isAr
                                                ? TextAlign.right
                                                : TextAlign.left,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      AppLocale.localizeData(
                                        context,
                                        w.subtitle,
                                      ),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? const Color(0xFF94A3B8)
                                            : const Color(0xFF64748B),
                                      ),
                                      textAlign: isAr
                                          ? TextAlign.right
                                          : TextAlign.left,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: w.iconColor.withValues(
                                    alpha: isDark ? 0.2 : 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  w.icon,
                                  color: w.iconColor,
                                  size: 24,
                                ),
                              ),
                            ],
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
      },
    );
  }
}

class _LaunchpadCard extends StatelessWidget {
  const _LaunchpadCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.first.withValues(alpha: 0.28),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(child: Icon(icon, color: Colors.white, size: 20)),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
