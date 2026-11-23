import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/database/database_service.dart';
import '../core/report_dispatch_helper.dart';
import '../core/whatsapp_service.dart';
import '../models/attendance_model.dart';
import '../models/curriculum_model.dart';
import '../models/group_model.dart';
import '../models/payment_model.dart';
import '../models/student_model.dart';
import '../widgets/circular_image_cropper_dialog.dart';
import '../widgets/section_top_bar.dart';
import '../widgets/visual_student_report_card.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.database,
    this.onBack,
    this.initialTab = 0,
  });

  final DatabaseService database;
  final VoidCallback? onBack;
  final int initialTab;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription<DataChangeEvent>? _dataSub;

  List<StudentModel> students = [];
  List<GroupModel> groups = [];
  StudentModel? selectedStudent;
  GroupModel? selectedGroup;

  List<AttendanceModel> studentAttendance = [];
  List<PaymentModel> studentPayments = [];
  List<Map<String, dynamic>> studentExamScores = [];
  SessionLogModel? studentLatestSession;
  bool isSessionReportSentToday = false;
  bool isAbsenceReportSentToday = false;
  bool isHolisticReportSentToday = false;

  // Sent Reports Log state
  List<Map<String, dynamic>> _reportLogs = [];
  bool _isLoadingLogs = true;
  String _reportsFilterType = 'all'; // all, sessionFollowup, holisticReport, sent, failed
  String _reportsSearchText = '';
  final Set<int> _selectedReportIds = {};

  // Group Reports state
  List<SessionLogModel> groupSessionLogs = [];

  // Settings & Footers state
  bool _isLoadingSettings = true;
  String _sessionScheduleMode = 'end_of_day'; // after_class, end_of_day
  TimeOfDay _sessionReportTime = const TimeOfDay(hour: 20, minute: 0);
  bool _weeklyReportEnabled = true;
  String _weeklyReportDay = 'الجمعة';
  TimeOfDay _weeklyReportTime = const TimeOfDay(hour: 18, minute: 0);
  bool _monthlyReportEnabled = true;
  TimeOfDay _monthlyReportTime = const TimeOfDay(hour: 21, minute: 0);
  bool _sessionIncludeFinancials = false;
  bool _weeklyIncludeFinancials = false;
  bool _monthlyIncludeFinancials = true;

  final TextEditingController _sessionFooterController = TextEditingController();
  final TextEditingController _weeklyFooterController = TextEditingController();
  final TextEditingController _monthlyFooterController = TextEditingController();

  // Visual Report Card Customization inside Reports Screen
  String _reportCardDefaultMode = 'dark'; // 'dark' or 'light'
  String _reportCardDefaultLayout = 'vertical'; // 'vertical' or 'grid'
  String _reportCardDefaultFont = 'cairo';
  String _reportCardDefaultTheme = 'cyan';
  final _reportCardTitleController = TextEditingController();
  bool _reportCardShowQr = true;
  bool _reportCardShowFinance = true;
  bool _reportCardShowStamp = true;
  bool _reportCardShowAttendance = true;
  bool _reportCardShowExams = true;
  bool _reportCardShowHomework = true;
  bool _reportCardShowRank = false;
  bool _reportCardShowTeacherNote = true;
  String? _reportCardHeaderLogoPath;
  String? _reportCardStampLogoPath;

  // Smart Search for Student Report
  final TextEditingController _studentSearchController = TextEditingController();
  String _studentSearchQuery = '';

  // Smart Search for Group Report
  final TextEditingController _groupSearchController = TextEditingController();
  String _groupSearchQuery = '';

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    _loadInitial();
    _loadReportLogs();
    _loadAutomationSettings();

    // Instant Real-Time Synchronization across sections
    _dataSub = widget.database.onDataChanged.listen((event) {
      if (event == DataChangeEvent.reports ||
          event == DataChangeEvent.attendance ||
          event == DataChangeEvent.students ||
          event == DataChangeEvent.groups ||
          event == DataChangeEvent.exams ||
          event == DataChangeEvent.finances ||
          event == DataChangeEvent.all) {
        if (mounted) {
          _refreshData();
        }
      }
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _tabController.dispose();
    _sessionFooterController.dispose();
    _weeklyFooterController.dispose();
    _monthlyFooterController.dispose();
    _studentSearchController.dispose();
    _groupSearchController.dispose();
    _reportCardTitleController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final results = await Future.wait([
      widget.database.getStudents(),
      widget.database.getGroups(),
    ]);
    final sList = results[0] as List<StudentModel>;
    final gList = results[1] as List<GroupModel>;

    if (mounted) {
      setState(() {
        students = sList;
        groups = gList;
        if (selectedStudent == null && students.isNotEmpty) {
          selectedStudent = students.first;
        } else if (selectedStudent != null) {
          selectedStudent = students.where((s) => s.id == selectedStudent!.id).firstOrNull ??
              (students.isNotEmpty ? students.first : null);
        }

        if (selectedGroup == null && groups.isNotEmpty) {
          selectedGroup = groups.first;
        } else if (selectedGroup != null) {
          selectedGroup = groups.where((g) => g.id == selectedGroup!.id).firstOrNull ??
              (groups.isNotEmpty ? groups.first : null);
        }
        isLoading = false;
      });

      if (selectedStudent != null) {
        _loadStudentDetails(selectedStudent!);
      }
      if (selectedGroup != null) {
        _loadGroupDetails(selectedGroup!);
      }
    }
  }

  Future<void> _refreshData() async {
    await _loadReportLogs();
    if (selectedStudent != null) {
      await _loadStudentDetails(selectedStudent!);
    }
    if (selectedGroup != null) {
      await _loadGroupDetails(selectedGroup!);
    }
  }

  Future<void> _loadStudentDetails(StudentModel student) async {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final results = await Future.wait([
      widget.database.getStudentAttendance(student.id),
      widget.database.getStudentPayments(student.id),
      widget.database.getStudentExamScores(student.id),
      student.groupId != null
          ? widget.database.getLatestSessionLogForGroup(student.groupId!)
          : Future.value(null),
      widget.database.isStudentReportSentToday(
        studentId: student.id,
        date: todayStr,
        category: 'sessionFollowup',
      ),
      widget.database.isStudentReportSentToday(
        studentId: student.id,
        date: todayStr,
        category: 'absence',
      ),
      widget.database.isStudentReportSentToday(
        studentId: student.id,
        date: todayStr,
        category: 'holisticReport',
      ),
    ]);
    if (mounted) {
      setState(() {
        studentAttendance = results[0] as List<AttendanceModel>;
        studentPayments = results[1] as List<PaymentModel>;
        studentExamScores = results[2] as List<Map<String, dynamic>>;
        studentLatestSession = results[3] as SessionLogModel?;
        isSessionReportSentToday = results[4] as bool;
        isAbsenceReportSentToday = results[5] as bool;
        isHolisticReportSentToday = results[6] as bool;
      });
    }
  }

  Future<void> _loadGroupDetails(GroupModel group) async {
    final logs = await widget.database.getSessionLogs(groupId: group.id);
    if (mounted) {
      setState(() {
        groupSessionLogs = logs;
      });
    }
  }

  Future<void> _loadReportLogs() async {
    final logs = await widget.database.getReportLogs(
      limit: 200,
      categories: ['sessionFollowup', 'holisticReport'],
    );
    if (mounted) {
      setState(() {
        _reportLogs = logs;
        _isLoadingLogs = false;
      });
    }
  }

  Future<void> _loadAutomationSettings() async {
    final sMode = await widget.database.getSetting(
      'session_report_auto_schedule',
      defaultValue: 'end_of_day',
    );
    final sTime = await widget.database.getSetting(
      'daily_report_time',
      defaultValue: '20:00',
    );
    final wEnabled = await widget.database.getSetting(
      'weekly_report_enabled',
      defaultValue: 'true',
    );
    final wDay = await widget.database.getSetting(
      'weekly_report_day',
      defaultValue: 'الجمعة',
    );
    final wTime = await widget.database.getSetting(
      'weekly_report_time',
      defaultValue: '18:00',
    );
    final mEnabled = await widget.database.getSetting(
      'monthly_report_enabled',
      defaultValue: 'true',
    );
    final mTime = await widget.database.getSetting(
      'monthly_report_time',
      defaultValue: '21:00',
    );

    final sIncFin = await widget.database.getSetting(
      'session_report_include_financials',
      defaultValue: 'false',
    );
    final wIncFin = await widget.database.getSetting(
      'weekly_report_include_financials',
      defaultValue: 'false',
    );
    final mIncFin = await widget.database.getSetting(
      'monthly_report_include_financials',
      defaultValue: 'true',
    );

    final sFooter = await widget.database.getSetting(
      'footer_session_report',
      defaultValue: 'مع تحيات إدارة السنتر لمتابعة واجبات الحصة أولاً بأول ✨',
    );
    final wFooter = await widget.database.getSetting(
      'footer_weekly_report',
      defaultValue: 'تقرير المتابعة الأسبوعي - يرجى مراجعة التكليفات مع الطالب 🌟',
    );
    final mFooter = await widget.database.getSetting(
      'footer_monthly_report',
      defaultValue: 'التقرير الشهري الشامل - شكراً لتعاونكم معنا في بناء مستقبل أبنائنا 🎓',
    );

    // Visual Report Card Settings
    final rcMode = await widget.database.getSetting('report_card_default_mode', defaultValue: 'dark');
    final rcLayout = await widget.database.getSetting('report_card_default_layout', defaultValue: 'vertical');
    final rcFont = await widget.database.getSetting('report_card_default_font', defaultValue: 'cairo');
    final rcTheme = await widget.database.getSetting('report_card_default_theme', defaultValue: 'cyan');
    final rcTitle = await widget.database.getSetting('report_card_default_title', defaultValue: 'تقرير المتابعة والنمو الأكاديمي الشامل لولي الأمر 📊');
    final rcQr = await widget.database.getSetting('report_card_show_qr', defaultValue: 'true');
    final rcFinance = await widget.database.getSetting('report_card_show_finance', defaultValue: 'true');
    final rcStamp = await widget.database.getSetting('report_card_show_stamp', defaultValue: 'true');
    final rcAttendance = await widget.database.getSetting('report_card_show_attendance', defaultValue: 'true');
    final rcExams = await widget.database.getSetting('report_card_show_exams', defaultValue: 'true');
    final rcHomework = await widget.database.getSetting('report_card_show_homework', defaultValue: 'true');
    final rcRank = await widget.database.getSetting('report_card_show_rank', defaultValue: 'false');
    final rcNote = await widget.database.getSetting('report_card_show_note', defaultValue: 'true');

    var hLogo = await widget.database.getSetting('report_card_header_logo_path', defaultValue: '');
    if (hLogo.isEmpty) {
      hLogo = await widget.database.getSetting('custom_logo_path', defaultValue: '');
    }
    var sLogo = await widget.database.getSetting('report_card_stamp_logo_path', defaultValue: '');
    if (sLogo.isEmpty) {
      sLogo = await widget.database.getSetting('custom_logo_path', defaultValue: '');
    }

    if (mounted) {
      setState(() {
        _sessionScheduleMode = sMode;
        _sessionReportTime = _parseTime(sTime);
        _weeklyReportEnabled = wEnabled == 'true';
        _weeklyReportDay = wDay;
        _weeklyReportTime = _parseTime(wTime);
        _monthlyReportEnabled = mEnabled == 'true';
        _monthlyReportTime = _parseTime(mTime);

        _sessionIncludeFinancials = sIncFin == 'true';
        _weeklyIncludeFinancials = wIncFin == 'true';
        _monthlyIncludeFinancials = mIncFin == 'true';

        _sessionFooterController.text = sFooter;
        _weeklyFooterController.text = wFooter;
        _monthlyFooterController.text = mFooter;

        _reportCardDefaultMode = rcMode;
        _reportCardDefaultLayout = rcLayout;
        _reportCardDefaultFont = rcFont;
        _reportCardDefaultTheme = rcTheme;
        _reportCardTitleController.text = rcTitle;
        _reportCardShowQr = rcQr == 'true';
        _reportCardShowFinance = rcFinance == 'true';
        _reportCardShowStamp = rcStamp == 'true';
        _reportCardShowAttendance = rcAttendance == 'true';
        _reportCardShowExams = rcExams == 'true';
        _reportCardShowHomework = rcHomework == 'true';
        _reportCardShowRank = rcRank == 'true';
        _reportCardShowTeacherNote = rcNote == 'true';
        if (hLogo.isNotEmpty && File(hLogo).existsSync()) {
          _reportCardHeaderLogoPath = hLogo;
        }
        if (sLogo.isNotEmpty && File(sLogo).existsSync()) {
          _reportCardStampLogoPath = sLogo;
        }

        _isLoadingSettings = false;
      });
    }
  }

  TimeOfDay _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      final h = int.parse(parts[0]);
      final m = parts.length > 1 ? int.parse(parts[1]) : 0;
      return TimeOfDay(hour: h, minute: m);
    } catch (_) {
      return const TimeOfDay(hour: 20, minute: 0);
    }
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: SectionTopBar(
        title: 'التقارير والمتابعة الأكاديمية',
        icon: Icons.insights_rounded,
        onBack: widget.onBack,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          indicatorColor: Theme.of(context).colorScheme.primary,
          indicatorWeight: 2.2,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(
              height: 38,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_search_rounded, size: 16),
                  SizedBox(width: 5),
                  Text('تقرير الطالب', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Tab(
              height: 38,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mark_chat_read_rounded, size: 16),
                  SizedBox(width: 5),
                  Text('سجل التقارير المرسلة', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Tab(
              height: 38,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.analytics_outlined, size: 16),
                  SizedBox(width: 5),
                  Text('تقارير المجموعات', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Tab(
              height: 38,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 16),
                  SizedBox(width: 5),
                  Text('إعدادات وضبط التقارير', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStudentReportTab(isDark),
                _buildSentReportsLogTab(isDark),
                _buildGroupReportTab(isDark),
                _buildAutomationSettingsTab(isDark),
              ],
            ),
    );
  }

  // ==========================================================================
  // SMART SEARCH & FILTER HELPERS FOR REPORTS
  // ==========================================================================
  List<StudentModel> _getFilteredStudentsForReport(String query, {String? groupFilter, bool onlyDebts = false}) {
    final q = query.trim().toLowerCase();
    return students.where((s) {
      if (onlyDebts && !s.hasOutstandingPayment) return false;
      if (groupFilter != null && groupFilter.isNotEmpty && s.groupId != groupFilter) return false;
      if (q.isEmpty) return true;
      final groupName = groups.where((g) => g.id == s.groupId).firstOrNull?.name.toLowerCase() ?? '';
      return s.fullName.toLowerCase().contains(q) ||
          s.id.toLowerCase().contains(q) ||
          s.studentPhone.contains(q) ||
          s.parentPhone.contains(q) ||
          s.grade.toLowerCase().contains(q) ||
          s.stage.toLowerCase().contains(q) ||
          s.parentName.toLowerCase().contains(q) ||
          groupName.contains(q);
    }).toList();
  }

  List<GroupModel> _getFilteredGroupsForReport(String query, {String? stageFilter}) {
    final q = query.trim().toLowerCase();
    return groups.where((g) {
      if (stageFilter != null && stageFilter.isNotEmpty && stageFilter != 'الكل' && g.stage != stageFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return g.name.toLowerCase().contains(q) ||
          g.grade.toLowerCase().contains(q) ||
          g.stage.toLowerCase().contains(q) ||
          g.schedule.toLowerCase().contains(q) ||
          g.days.toLowerCase().contains(q) ||
          g.room.toLowerCase().contains(q) ||
          g.subject.toLowerCase().contains(q);
    }).toList();
  }

  Widget _buildModalFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color themePrimary,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? themePrimary.withValues(alpha: 0.18)
              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? themePrimary : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? themePrimary : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildSmartStudentSearchSection(bool isDark, StudentModel student) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final groupName = groups.where((g) => g.id == student.groupId).firstOrNull?.name ?? 'بدون مجموعة';
    final matchingStudents = _studentSearchQuery.isNotEmpty
        ? _getFilteredStudentsForReport(_studentSearchQuery)
        : <StudentModel>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Smart search bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : themePrimary.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.person_search_rounded, color: themePrimary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _studentSearchController,
                  onChanged: (val) {
                    setState(() => _studentSearchQuery = val);
                  },
                  decoration: InputDecoration(
                    hintText: 'بحث ذكي: بالاسم، الكود، الهاتف، المجموعة، الصف...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (_studentSearchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    setState(() {
                      _studentSearchController.clear();
                      _studentSearchQuery = '';
                    });
                  },
                ),
              // Smart dropdown arrow button
              Material(
                color: themePrimary.withValues(alpha: isDark ? 0.2 : 0.08),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _showSmartStudentPicker(isDark),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'اختيار طالب',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: themePrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down_rounded, size: 20, color: themePrimary),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Live matching suggestions list when typing
        if (_studentSearchQuery.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: themePrimary.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: matchingStudents.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text('لا يوجد طالب مطابق للبحث', style: TextStyle(fontSize: 13)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(6),
                    itemCount: matchingStudents.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final s = matchingStudents[idx];
                      final grp = groups.where((g) => g.id == s.groupId).firstOrNull?.name ?? 'بدون مجموعة';
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: themePrimary.withValues(alpha: 0.15),
                          child: Text(
                            s.fullName.isNotEmpty ? s.fullName[0] : '?',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: themePrimary),
                          ),
                        ),
                        title: Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('${s.grade} • $grp', style: const TextStyle(fontSize: 11)),
                        trailing: s.hasOutstandingPayment
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'مدين: ${s.outstandingAmount.toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
                                ),
                              )
                            : const Text('خالص ✅', style: TextStyle(fontSize: 11, color: Colors.green)),
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          setState(() {
                            selectedStudent = s;
                            _studentSearchQuery = '';
                            _studentSearchController.clear();
                          });
                          _loadStudentDetails(s);
                        },
                      );
                    },
                  ),
          ),
        ] else ...[
          // Active Selected Student Profile Card
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: themePrimary,
                  child: Text(
                    student.fullName.isNotEmpty ? student.fullName[0] : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              student.fullName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (student.hasOutstandingPayment)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'متأخرات: ${student.outstandingAmount.toStringAsFixed(0)} ج.م',
                                style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'خالص السداد ✅',
                                style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.school_rounded, size: 14, color: isDark ? Colors.white60 : Colors.black54),
                          const SizedBox(width: 4),
                          Text(
                            student.grade,
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.groups_rounded, size: 14, color: isDark ? Colors.white60 : Colors.black54),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              groupName,
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'تغيير الطالب',
                  icon: Icon(Icons.swap_horiz_rounded, color: themePrimary),
                  onPressed: () => _showSmartStudentPicker(isDark),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _showSmartStudentPicker(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String modalSearch = '';
        String selectedGroupFilter = '';
        bool onlyDebts = false;
        final themePrimary = Theme.of(context).colorScheme.primary;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _getFilteredStudentsForReport(
              modalSearch,
              groupFilter: selectedGroupFilter.isNotEmpty ? selectedGroupFilter : null,
              onlyDebts: onlyDebts,
            );

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: themePrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.person_search_rounded, color: themePrimary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'البحث الذكي واختيار الطالب',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'إجمالي المسجلين: ${students.length} طالب',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white60 : Colors.black54,
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
                  const SizedBox(height: 12),

                  // Search input field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                      child: TextField(
                        autofocus: false,
                        onChanged: (val) {
                          setModalState(() => modalSearch = val);
                        },
                        decoration: InputDecoration(
                          hintText: 'ابحث بالاسم، الكود، الهاتف، المجموعة...',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          prefixIcon: Icon(Icons.search_rounded, color: themePrimary, size: 20),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Quick Filter Pills
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _buildModalFilterChip(
                          label: 'الكل (${students.length})',
                          isSelected: !onlyDebts && selectedGroupFilter.isEmpty,
                          onTap: () {
                            setModalState(() {
                              onlyDebts = false;
                              selectedGroupFilter = '';
                            });
                          },
                          themePrimary: themePrimary,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildModalFilterChip(
                          label: 'متأخرات مالية (${students.where((s) => s.hasOutstandingPayment).length})',
                          isSelected: onlyDebts,
                          onTap: () {
                            setModalState(() {
                              onlyDebts = !onlyDebts;
                            });
                          },
                          themePrimary: Colors.red,
                          isDark: isDark,
                        ),
                        ...groups.map((g) {
                          final isSel = selectedGroupFilter == g.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _buildModalFilterChip(
                              label: g.name,
                              isSelected: isSel,
                              onTap: () {
                                setModalState(() {
                                  selectedGroupFilter = isSel ? '' : g.id;
                                });
                              },
                              themePrimary: themePrimary,
                              isDark: isDark,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const Divider(height: 20),

                  // Students List
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: isDark ? Colors.white24 : Colors.black26),
                                const SizedBox(height: 10),
                                const Text('لا توجد نتائج مطابقة للبحث'),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final s = filtered[index];
                              final isCurrent = selectedStudent?.id == s.id;
                              final grpName = groups.where((g) => g.id == s.groupId).firstOrNull?.name ?? 'بدون مجموعة';

                              return InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    selectedStudent = s;
                                    _studentSearchQuery = '';
                                    _studentSearchController.clear();
                                  });
                                  _loadStudentDetails(s);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? themePrimary.withValues(alpha: isDark ? 0.2 : 0.08)
                                        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isCurrent
                                          ? themePrimary
                                          : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
                                      width: isCurrent ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: isCurrent ? themePrimary : themePrimary.withValues(alpha: 0.15),
                                        child: Text(
                                          s.fullName.isNotEmpty ? s.fullName[0] : '?',
                                          style: TextStyle(
                                            color: isCurrent ? Colors.white : themePrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    s.fullName,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                  ),
                                                ),
                                                if (s.hasOutstandingPayment)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      'مدين: ${s.outstandingAmount.toStringAsFixed(0)} ج.م',
                                                      style: const TextStyle(
                                                        color: Colors.red,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green.withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: const Text(
                                                      'خالص السداد ✅',
                                                      style: TextStyle(
                                                        color: Colors.green,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${s.grade} • $grpName',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark ? Colors.white60 : Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isCurrent)
                                        Icon(Icons.check_circle_rounded, color: themePrimary, size: 22),
                                    ],
                                  ),
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

  // ==========================================================================
  // TAB 1: STUDENT COMPREHENSIVE & GROWTH REPORT
  // ==========================================================================
  Widget _buildStudentReportTab(bool isDark) {
    if (students.isEmpty) {
      return const Center(child: Text('لا يوجد طلاب مسجلين'));
    }

    final student = selectedStudent ?? students.first;
    final presentCount = studentAttendance.where((a) => a.status == 'present').length;
    final totalSessions = studentAttendance.length;
    final attPercent = totalSessions > 0 ? (presentCount / totalSessions * 100).toInt() : 100;

    double totalPaid = 0;
    for (final p in studentPayments) {
      totalPaid += p.amount;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // Smart Search and Selector
        _buildSmartStudentSearchSection(isDark, student),
        const SizedBox(height: 14),

        // Summary Metric Cards
        Row(
          children: [
            Expanded(
              child: _ReportMetricCard(
                title: 'نسبة الحضور',
                value: '$attPercent%',
                subtitle: '$presentCount من $totalSessions حصص',
                color: attPercent >= 80 ? Colors.green : Colors.orange,
                icon: Icons.fact_check_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ReportMetricCard(
                title: 'الموقف المالي',
                value: student.hasOutstandingPayment ? '${student.outstandingAmount} ج.م' : 'مسدد ✅',
                subtitle: 'إجمالي المسدد: ${totalPaid.toStringAsFixed(0)} ج.م',
                color: student.hasOutstandingPayment ? Colors.red : Colors.green,
                icon: Icons.payments_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Exam Scores Section
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.assignment_turned_in_rounded, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('سجل الاختبارات والتقييمات', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 20),
                if (studentExamScores.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: Text('لا توجد اختبارات مسجلة لهذا الطالب بعد')),
                  )
                else
                  ...studentExamScores.map((score) {
                    final sVal = (score['score'] as num).toDouble();
                    final maxVal = (score['max_score'] as num).toDouble();
                    final note = score['note'] as String? ?? '';
                    final isPass = sVal >= (maxVal * 0.7);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(score['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text(
                                  '${score['date']}${note.isNotEmpty ? " • $note" : ""}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPass ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$sVal / $maxVal',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isPass ? Colors.green.shade800 : Colors.red.shade800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Lesson & Homework Progress Section
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.menu_book_rounded, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('آخر الدروس والتكليفات المشروحة', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 20),
                if (studentLatestSession == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Center(child: Text('لم يتم تسجيل حصص أو دروس حديثة للمجموعة')),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• موضوع الدرس: ${studentLatestSession!.lessonTitle}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '• تاريخ الحصة: ${studentLatestSession!.date}',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                      if (studentLatestSession!.homework.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '• الواجب المنزلي: ${studentLatestSession!.homework}',
                          style: const TextStyle(fontSize: 12.5, color: Colors.teal),
                        ),
                      ],
                      if (studentLatestSession!.nextTopic.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '• التحضير القادم: ${studentLatestSession!.nextTopic}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Attendance Log Section
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, color: Colors.teal),
                    SizedBox(width: 8),
                    Text('سجل الحضور والغياب الأخير', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 20),
                if (studentAttendance.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: Text('لا توجد سجلات حضور مسجلة بعد')),
                  )
                else
                  ...studentAttendance.take(5).map((a) {
                    final isPresent = a.status == 'present';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.attendanceDate,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isPresent ? 'حاضر (${a.source})' : 'غائب',
                                style: TextStyle(
                                  color: isPresent ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(isPresent ? Icons.check_circle : Icons.cancel,
                                  size: 17, color: isPresent ? Colors.green : Colors.red),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // WhatsApp Dispatch Actions Card with strict duplicate prevention
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141E33) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF25D366).withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.mark_chat_read_rounded, color: Color(0xFF25D366), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'خيارات إرسال التقارير لولي الأمر عبر واتساب 📲',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'التقارير المرسلة مسبقاً اليوم تظهر مغلقة تلقائياً لمنع تكرار الإرسال وإزعاج ولي الأمر 🛡️',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 12),

              // 1. Session Follow-up Report Button
              _buildReportDispatchAction(
                label: 'إرسال تقرير متابعة الحصة اليومية 📝',
                alreadySentLabel: 'تم إرسال تقرير الحصة لولي الأمر مسبقاً اليوم 🔒 (مغلق)',
                isSent: isSessionReportSentToday,
                buttonColor: const Color(0xFF0284C7),
                icon: Icons.assignment_rounded,
                onPressed: isSessionReportSentToday
                    ? null
                    : () => _handleDispatchSessionReport(student),
              ),
              const SizedBox(height: 8),

              // 2. Absence Report Button
              _buildReportDispatchAction(
                label: 'إرسال إشعار / إنذار الغياب 🚨',
                alreadySentLabel: 'تم إرسال إشعار الغياب لولي الأمر مسبقاً اليوم 🔒 (مغلق)',
                isSent: isAbsenceReportSentToday,
                buttonColor: Colors.redAccent,
                icon: Icons.notification_important_rounded,
                onPressed: isAbsenceReportSentToday
                    ? null
                    : () => _handleDispatchAbsenceReport(student),
              ),
              const SizedBox(height: 8),

              // 3. Holistic Progress Report Button
              _buildReportDispatchAction(
                label: 'إرسال تقرير المتابعة الشامل الدوري 📊',
                alreadySentLabel: 'تم إرسال التقرير الشامل لولي الأمر مسبقاً اليوم 🔒 (مغلق)',
                isSent: isHolisticReportSentToday,
                buttonColor: const Color(0xFF10B981),
                icon: Icons.assessment_rounded,
                onPressed: isHolisticReportSentToday
                    ? null
                    : () => _handleDispatchStudentReport(student, attPercent, presentCount, totalSessions),
              ),
              const SizedBox(height: 10),

              // 4. Visual Luxury Report Card (Scenario 3)
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00F2FE), Color(0xFF0284C7)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _handleOpenVisualReportCard(
                      student,
                      attPercent,
                      presentCount,
                      totalSessions,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome_rounded, color: Color(0xFF090E17), size: 20),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'توليد ومشاركة كارت التقرير المصور الفاخر (Image / PDF) 🖼️✨',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: Color(0xFF090E17),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReportDispatchAction({
    required String label,
    required String alreadySentLabel,
    required bool isSent,
    required Color buttonColor,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isSent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                alreadySentLabel,
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 18),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
      onPressed: onPressed,
    );
  }

  void _showReportAlreadySentDialog({
    required String studentName,
    required String reportTypeName,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: Colors.amber, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text('التقرير مرسل مسبقاً اليوم 🛡️')),
          ],
        ),
        content: Text(
          'نحيطكم علماً بأنه تم إرسال ($reportTypeName) لولي أمر الطالب "$studentName" مسبقاً اليوم.\n\nيقوم النظام بإغلاق الإرسال ومنع التكرار تلقائياً لتفادي إزعاج ولي الأمر.',
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
  }

  Future<void> _handleDispatchSessionReport(StudentModel student) async {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final isSent = await widget.database.isStudentReportSentToday(
      studentId: student.id,
      date: todayStr,
      category: 'sessionFollowup',
    );
    if (isSent) {
      if (!mounted) return;
      _showReportAlreadySentDialog(
        studentName: student.fullName,
        reportTypeName: 'تقرير متابعة الحصة',
      );
      return;
    }

    if (student.parentPhone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم هاتف ولي الأمر غير مسجل لهذا الطالب')),
      );
      return;
    }

    final centerName = await widget.database.getSetting('center_name', defaultValue: 'سنتر الأستاذ التعليمي');
    final teacherName = await widget.database.getSetting('teacher_name', defaultValue: 'أستاذ المادة');
    final customFooter = await widget.database.getSetting(
      'footer_session_report',
      defaultValue: 'مع تحيات إدارة السنتر وأستاذ المادة 🌟',
    );

    final lessonPart = studentLatestSession != null
        ? '📖 موضوع الدرس المشروح: ${studentLatestSession!.lessonTitle}\n'
          '${studentLatestSession!.homework.isNotEmpty ? '📝 الواجب المطلوب: ${studentLatestSession!.homework}\n' : ''}'
          '${studentLatestSession!.nextTopic.isNotEmpty ? '🎯 التحضير القادم: ${studentLatestSession!.nextTopic}\n' : ''}'
        : 'حصة دراسية منتظمة\n';

    final message = '''📋 تقرير متابعة الحصة اليومية 📋
$centerName | المعلم: $teacherName
━━━━━━━━━━━━━━━━━
الطالب: ${student.fullName}
الصف: ${student.grade}
📅 تاريخ الحصة: $todayStr

$lessonPart━━━━━━━━━━━━━━━━━
$customFooter''';

    final channel = await ReportDispatchHelper.dispatchReport(
      context: context,
      studentId: student.id,
      studentName: student.fullName,
      studentCode: student.id,
      parentPhone: student.parentPhone,
      reportTitle: 'تقرير متابعة الحصة اليومية 📋',
      reportMessage: message,
      notifType: 'sessionFollowup',
      database: widget.database,
    );

    if (channel != null && mounted) {
      setState(() => isSessionReportSentToday = true);
    }
  }

  Future<void> _handleDispatchAbsenceReport(StudentModel student) async {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final isSent = await widget.database.isStudentReportSentToday(
      studentId: student.id,
      date: todayStr,
      category: 'absence',
    );
    if (isSent) {
      if (!mounted) return;
      _showReportAlreadySentDialog(
        studentName: student.fullName,
        reportTypeName: 'إشعار الغياب',
      );
      return;
    }

    if (student.parentPhone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم هاتف ولي الأمر غير مسجل لهذا الطالب')),
      );
      return;
    }

    final centerName = await widget.database.getSetting('center_name', defaultValue: 'سنتر الأستاذ التعليمي');
    final teacherName = await widget.database.getSetting('teacher_name', defaultValue: 'أستاذ المادة');

    final message = WhatsAppService.absenceMessage(
      centerName: centerName,
      teacherName: teacherName,
      studentName: student.fullName,
      date: todayStr,
    );

    final channel = await ReportDispatchHelper.dispatchReport(
      context: context,
      studentId: student.id,
      studentName: student.fullName,
      studentCode: student.id,
      parentPhone: student.parentPhone,
      reportTitle: 'إشعار غياب عن الحصة 🚨',
      reportMessage: message,
      notifType: 'absence',
      database: widget.database,
    );

    if (channel != null && mounted) {
      setState(() => isAbsenceReportSentToday = true);
    }
  }

  Future<void> _handleDispatchStudentReport(
    StudentModel student,
    int attPercent,
    int presentCount,
    int totalSessions,
  ) async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Strictly check if a report was already sent previously to prevent duplicate sending
    final prevLog = await widget.database.getPreviousReportLog(
      studentId: student.id,
      category: 'holisticReport',
      date: todayStr,
    );

    if (prevLog != null || isHolisticReportSentToday) {
      if (mounted) {
        _showReportAlreadySentDialog(
          studentName: student.fullName,
          reportTypeName: 'تقرير المتابعة الشامل',
        );
      }
      return;
    }

    _showReportFormatChooserSheet(student, attPercent, presentCount, totalSessions);
  }

  void _showReportFormatChooserSheet(
    StudentModel student,
    int attPercent,
    int presentCount,
    int totalSessions,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF0F172A) : Colors.white;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
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
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.send_rounded, color: Color(0xFF0284C7), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'تحديد طريقة إرسال التقرير 📤',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'اختر الصيغة لولي أمر الطالب (${student.fullName}):',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Option 1: Written Text Report
                  _buildChoiceTile(
                    icon: Icons.description_rounded,
                    iconColor: const Color(0xFF0D9488),
                    title: '1. تقرير كتابي نصي (WhatsApp Text) 📄',
                    subtitle: 'رسالة نصية منسقة ومنظمة بالواتساب تشمل الحضور، الدرجات، الواجبات، والمصروفات.',
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(ctx);
                      _executeSendTextReport(student, attPercent, presentCount, totalSessions);
                    },
                  ),
                  const SizedBox(height: 10),

                  // Option 2: Visual Card Image
                  _buildChoiceTile(
                    icon: Icons.image_rounded,
                    iconColor: const Color(0xFF0284C7),
                    title: '2. كارت مصور فاخر عالي الدقة (HD Visual Card) 🖼️',
                    subtitle: 'كارت وبطاقة متابعة رأسية مخصصة بهوية السنتر، الأختام، شريط التقدم المدمج، ورمز QR.',
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(ctx);
                      _handleOpenVisualReportCard(student, attPercent, presentCount, totalSessions);
                    },
                  ),
                  const SizedBox(height: 10),

                  // Option 3: Both
                  _buildChoiceTile(
                    icon: Icons.auto_awesome_rounded,
                    iconColor: const Color(0xFFD97706),
                    title: '3. كلاهما معاً (الكارت المصور + نص التقرير) ✨',
                    subtitle: 'إرسال الكارت المصور الفاخر مرفقاً معه نص التقرير المفصل كاملاً لولي الأمر.',
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(ctx);
                      _handleOpenVisualReportCard(student, attPercent, presentCount, totalSessions);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChoiceTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _executeSendTextReport(
    StudentModel student,
    int attPercent,
    int presentCount,
    int totalSessions,
  ) async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final examsSummary = studentExamScores.isNotEmpty
        ? studentExamScores.take(3).map((e) => '• ${e['title']}: ${e['score']}/${e['max_score']}').join('\n')
        : 'لا توجد اختبارات مسجلة حالياً';

    final includeFin = await widget.database.getSetting(
      'weekly_report_include_financials',
      defaultValue: 'false',
    );
    final debtPart = includeFin == 'true'
        ? '\n\n3️⃣ الموقف المالي:\n${student.hasOutstandingPayment ? 'متأخرات حالية: ${student.outstandingAmount} ج.م' : 'الاشتراك: مسدد بالكامل ✅'}'
        : '';

    final sessionPart = studentLatestSession != null
        ? '\n\n4️⃣ آخر ما تم دراسته والتكليفات:'
            '${studentLatestSession!.previousHomeworkReview.isNotEmpty ? '\n• مراجعة الواجب: ${studentLatestSession!.previousHomeworkReview}' : ''}'
            '\n• الدرس المشروح: ${studentLatestSession!.lessonTitle} (${studentLatestSession!.date})'
            '${studentLatestSession!.homework.isNotEmpty ? '\n• الواجب المنزلي: ${studentLatestSession!.homework}' : ''}'
            '${studentLatestSession!.nextTopic.isNotEmpty ? '\n• التحضير القادم: ${studentLatestSession!.nextTopic}' : ''}'
        : '';

    final centerName = await widget.database.getSetting('center_name', defaultValue: 'سنتر أستاذي التعليمي');
    final teacherName = await widget.database.getSetting('teacher_name', defaultValue: 'الأستاذ');
    final customFooter = await widget.database.getSetting(
      'footer_weekly_report',
      defaultValue: 'مع تمنياتنا للطالب بدوام التفوق والنجاح المستمر ✨',
    );

    final reportMessage = '''📊 تقرير متابعة الطالب الدوري 📊
$centerName | المعلم: $teacherName
━━━━━━━━━━━━━━━━━
الطالب: ${student.fullName}
الصف: ${student.grade}
📅 التاريخ: $todayStr

1️⃣ نسبة الحضور: $attPercent% ($presentCount من $totalSessions حصص)
2️⃣ نتائج الاختبارات:
$examsSummary$debtPart$sessionPart

$customFooter''';

    final channel = await ReportDispatchHelper.dispatchReport(
      context: context,
      studentId: student.id,
      studentName: student.fullName,
      studentCode: student.id,
      parentPhone: student.parentPhone,
      reportTitle: 'تقرير المتابعة الشامل الدوري 📊',
      reportMessage: reportMessage,
      notifType: 'holisticReport',
      database: widget.database,
    );

    if (channel != null && mounted) {
      setState(() => isHolisticReportSentToday = true);
    }
  }

  Future<void> _handleOpenVisualReportCard(
    StudentModel student,
    int attPercent,
    int presentCount,
    int totalSessions,
  ) async {
    String grpName = 'المجموعة العامة';
    String? grpGrade;
    GroupModel? matchedGroup;
    if (student.groupId != null && student.groupId!.trim().isNotEmpty) {
      matchedGroup = groups.where((g) => g.id.trim() == student.groupId!.trim()).firstOrNull;
    }
    if (matchedGroup == null && selectedGroup != null) {
      matchedGroup = selectedGroup;
    }
    if (matchedGroup == null) {
      for (final g in groups) {
        final gStudents = await widget.database.getStudents(groupId: g.id);
        if (gStudents.any((s) => s.id == student.id)) {
          matchedGroup = g;
          break;
        }
      }
    }
    if (matchedGroup != null) {
      grpName = matchedGroup.name;
      grpGrade = matchedGroup.grade;
      if (student.grade != matchedGroup.grade && matchedGroup.grade.isNotEmpty) {
        try {
          await widget.database.updateStudentsBatchFields(
            [student.id],
            grade: matchedGroup.grade,
            stage: matchedGroup.stage,
          );
        } catch (_) {}
      }
    }
    final centerName = await widget.database.getSetting('center_name', defaultValue: 'سنتر الأستاذ التعليمي للأوائل');
    final teacherName = await widget.database.getSetting('teacher_name', defaultValue: 'أ / محمد مصطفى');

    // Calculate average score percentage
    double avgPercent = 0.0;
    if (studentExamScores.isNotEmpty) {
      double totalObtained = 0;
      double totalPossible = 0;
      for (final e in studentExamScores) {
        final s = (e['score'] ?? 0).toDouble();
        final m = (e['max_score'] ?? 50).toDouble();
        if (m > 0) {
          totalObtained += s;
          totalPossible += m;
        }
      }
      if (totalPossible > 0) {
        avgPercent = (totalObtained / totalPossible) * 100;
      }
    } else {
      avgPercent = 0.0;
    }

    if (!mounted) return;

    VisualReportCardModalSheet.show(
      context,
      student: student,
      groupName: grpName,
      groupGrade: grpGrade,
      attendancePercent: attPercent,
      presentCount: presentCount,
      totalSessions: totalSessions,
      averageScorePercent: avgPercent,
      examScores: studentExamScores,
      centerName: centerName,
      teacherName: teacherName,
      lessonTitle: studentLatestSession?.lessonTitle,
      previousHomeworkReview: studentLatestSession?.previousHomeworkReview,
      homeworkText: studentLatestSession?.homework,
      nextTopic: studentLatestSession?.nextTopic,
      nextQuiz: studentLatestSession?.nextQuiz,
      subAttendanceNote: '$presentCount من $totalSessions حصص',
      database: widget.database,
    );
  }

  // ==========================================================================
  // TAB 2: DEDICATED SENT REPORTS LOG (سجل التقارير المرسلة)
  // ==========================================================================
  Widget _buildSentReportsLogTab(bool isDark) {
    if (_isLoadingLogs) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredReports = _reportLogs.where((log) {
      final status = log['status']?.toString() ?? '';
      final isSent = status == 'sent' || status == 'success' || status == 'sent_manual';
      final category = log['category']?.toString() ?? '';

      if (_reportsFilterType == 'sent' && !isSent) return false;
      if (_reportsFilterType == 'failed' && isSent) return false;
      if (_reportsFilterType == 'sessionFollowup' && category != 'sessionFollowup') return false;
      if (_reportsFilterType == 'holisticReport' && category != 'holisticReport') return false;

      if (_reportsSearchText.trim().isNotEmpty) {
        final query = _reportsSearchText.trim().toLowerCase();
        final name = (log['student_name'] ?? '').toString().toLowerCase();
        final phone = (log['phone'] ?? '').toString().toLowerCase();
        final msg = (log['message'] ?? '').toString().toLowerCase();
        return name.contains(query) || phone.contains(query) || msg.contains(query);
      }
      return true;
    }).toList();

    final nowStr = DateTime.now().toIso8601String().substring(0, 10);
    final todayCount = _reportLogs.where((l) => (l['sent_at'] ?? '').toString().startsWith(nowStr)).length;
    final sessionReportsCount = _reportLogs.where((l) => l['category'] == 'sessionFollowup').length;
    final holisticReportsCount = _reportLogs.where((l) => l['category'] == 'holisticReport').length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
      children: [
        // Top Overview Statistics Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.verified_rounded, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'سجل تقارير أولياء الأمور والطلاب',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildSmallStat(
                      label: 'إجمالي التقارير',
                      value: '${_reportLogs.length}',
                      color: const Color(0xFF38BDF8),
                    ),
                  ),
                  Expanded(
                    child: _buildSmallStat(
                      label: 'تقارير اليوم',
                      value: '$todayCount',
                      color: const Color(0xFF34D399),
                    ),
                  ),
                  Expanded(
                    child: _buildSmallStat(
                      label: 'تقارير الحصص',
                      value: '$sessionReportsCount',
                      color: const Color(0xFFFBBF24),
                    ),
                  ),
                  Expanded(
                    child: _buildSmallStat(
                      label: 'أسبوعي وشامل',
                      value: '$holisticReportsCount',
                      color: const Color(0xFFA78BFA),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Search & Select All Actions Bar
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'بحث في سجل التقارير (الاسم أو الرقم)...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (val) => setState(() => _reportsSearchText = val),
              ),
            ),
            if (filteredReports.isNotEmpty) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: _selectedReportIds.length == filteredReports.length && _selectedReportIds.isNotEmpty
                    ? 'إلغاء تحديد الكل'
                    : 'تحديد الكل (${filteredReports.length})',
                icon: Icon(
                  _selectedReportIds.length == filteredReports.length && _selectedReportIds.isNotEmpty
                      ? Icons.check_box_rounded
                      : Icons.checklist_rounded,
                  color: const Color(0xFF0284C7),
                ),
                onPressed: () {
                  setState(() {
                    if (_selectedReportIds.length == filteredReports.length && _selectedReportIds.isNotEmpty) {
                      _selectedReportIds.clear();
                    } else {
                      for (final l in filteredReports) {
                        final id = (l['id'] as num?)?.toInt();
                        if (id != null) _selectedReportIds.add(id);
                      }
                    }
                  });
                },
              ),
            ],
          ],
        ),

        // Long-Press Selection / Hint Banner
        if (_selectedReportIds.isEmpty) ...[
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
                    'اضغط مطولاً على أي تقرير لتحديده وحذفه، أو اختر أكثر من تقرير معاً',
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

        // Batch Action Banner
        if (_selectedReportIds.isNotEmpty) ...[
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
                    'تم تحديد ${_selectedReportIds.length} تقرير للحذف',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() => _selectedReportIds.clear()),
                  child: const Text('إلغاء التحديد', style: TextStyle(fontSize: 11)),
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
                    final count = _selectedReportIds.length;
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('حذف التقارير المحددة'),
                        content: Text('هل أنت متأكد من حذف ($count) تقرير محدد من السجل؟'),
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
                      await widget.database.deleteWhatsAppLogsByIds(_selectedReportIds.toList());
                      setState(() => _selectedReportIds.clear());
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم حذف ($count) تقرير محدد من السجل 🗑️'),
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

        // Quick Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildReportFilterChip('الكل (${_reportLogs.length})', 'all'),
              const SizedBox(width: 6),
              _buildReportFilterChip('تقارير الحصص 📝', 'sessionFollowup'),
              const SizedBox(width: 6),
              _buildReportFilterChip('تقارير أسبوعية وشاملة 📊', 'holisticReport'),
              const SizedBox(width: 6),
              _buildReportFilterChip('المرسلة بنجاح ✅', 'sent'),
              const SizedBox(width: 6),
              _buildReportFilterChip('المعلقة / الأخطاء ⚠️', 'failed'),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Reports Cards List
        if (filteredReports.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('لا توجد تقارير مطابقة في السجل', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          ...filteredReports.map((log) {
            final status = log['status']?.toString() ?? 'sent';
            final isSuccess = status == 'sent' || status == 'success' || status == 'sent_manual';
            final isManual = status == 'sent_manual';
            final recipient = log['recipient_type'] == 'student' ? 'الطالب' : 'ولي الأمر';
            final category = log['category']?.toString() ?? '';
            final sentAt = log['sent_at']?.toString() ?? log['created_at']?.toString() ?? '';
            final logId = (log['id'] as num?)?.toInt();
            final isSelected = logId != null && _selectedReportIds.contains(logId);

            final categoryTitle = category == 'sessionFollowup' ? 'تقرير حصة 📝' : 'تقرير أسبوعي/شهري 📊';

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () {
                HapticFeedback.heavyImpact();
                if (logId != null) {
                  setState(() {
                    if (_selectedReportIds.contains(logId)) {
                      _selectedReportIds.remove(logId);
                    } else {
                      _selectedReportIds.add(logId);
                    }
                  });
                }
              },
              onTap: _selectedReportIds.isNotEmpty
                  ? () {
                      HapticFeedback.selectionClick();
                      if (logId != null) {
                        setState(() {
                          if (_selectedReportIds.contains(logId)) {
                            _selectedReportIds.remove(logId);
                          } else {
                            _selectedReportIds.add(logId);
                          }
                        });
                      }
                    }
                  : null,
              child: IgnorePointer(
                ignoring: _selectedReportIds.isNotEmpty,
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
                        if (logId != null && _selectedReportIds.isNotEmpty)
                          Checkbox(
                            value: isSelected,
                            activeColor: const Color(0xFFEF4444),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedReportIds.add(logId);
                                } else {
                                  _selectedReportIds.remove(logId);
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
                                    label: const Text('حذف التقرير', style: TextStyle(fontSize: 11)),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text('حذف التقرير'),
                                          content: const Text('هل أنت متأكد من حذف هذا التقرير من السجل؟'),
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
                                        setState(() => _selectedReportIds.remove(logId));
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('تم حذف التقرير من السجل 🗑️'),
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
                                  label: const Text('نسخ التقرير', style: TextStyle(fontSize: 11)),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: log['message']?.toString() ?? ''));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('تم نسخ نص التقرير إلى الحافظة 📋'),
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
  }

  Widget _buildSmallStat({required String label, required String value, required Color color}) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
      ],
    );
  }

  Widget _buildReportFilterChip(String label, String value) {
    final isSelected = _reportsFilterType == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF0284C7).withValues(alpha: 0.25),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? const Color(0xFF0284C7) : null,
      ),
      onSelected: (val) {
        if (val) setState(() => _reportsFilterType = value);
      },
    );
  }

  Widget _buildSmartGroupSearchSection(bool isDark, GroupModel group, List<StudentModel> groupStudents) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final matchingGroups = _groupSearchQuery.isNotEmpty
        ? _getFilteredGroupsForReport(_groupSearchQuery)
        : <GroupModel>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Smart search bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : themePrimary.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.manage_search_rounded, color: themePrimary, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _groupSearchController,
                  onChanged: (val) {
                    setState(() => _groupSearchQuery = val);
                  },
                  decoration: InputDecoration(
                    hintText: 'بحث ذكي: باسم المجموعة، المرحلة، المواعيد، القاعة...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (_groupSearchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    setState(() {
                      _groupSearchController.clear();
                      _groupSearchQuery = '';
                    });
                  },
                ),
              // Smart dropdown arrow button
              Material(
                color: themePrimary.withValues(alpha: isDark ? 0.2 : 0.08),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _showSmartGroupPicker(isDark),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'اختيار مجموعة',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: themePrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down_rounded, size: 20, color: themePrimary),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Live matching suggestions list if typing
        if (_groupSearchQuery.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: themePrimary.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: matchingGroups.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text('لا توجد مجموعة مطابقة للبحث', style: TextStyle(fontSize: 13)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(6),
                    itemCount: matchingGroups.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final g = matchingGroups[idx];
                      final count = students.where((s) => s.groupId == g.id).length;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        leading: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Color(g.colorValue).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Icon(Icons.groups_rounded, color: Color(g.colorValue), size: 18),
                          ),
                        ),
                        title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('${g.grade} • ${g.schedule}', style: const TextStyle(fontSize: 11)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: themePrimary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$count طالب',
                            style: TextStyle(color: themePrimary, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          setState(() {
                            selectedGroup = g;
                            _groupSearchQuery = '';
                            _groupSearchController.clear();
                          });
                          _loadGroupDetails(g);
                        },
                      );
                    },
                  ),
          ),
        ] else ...[
          // Active Selected Group Profile Card
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color(group.colorValue).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(Icons.groups_rounded, color: Color(group.colorValue), size: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: themePrimary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${groupStudents.length} طالب مقيد',
                              style: TextStyle(color: themePrimary, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded, size: 14, color: isDark ? Colors.white60 : Colors.black54),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${group.grade} • ${group.schedule}',
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'تغيير المجموعة',
                  icon: Icon(Icons.swap_horiz_rounded, color: themePrimary),
                  onPressed: () => _showSmartGroupPicker(isDark),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _showSmartGroupPicker(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String modalSearch = '';
        String selectedStageFilter = 'الكل';
        final themePrimary = Theme.of(context).colorScheme.primary;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _getFilteredGroupsForReport(
              modalSearch,
              stageFilter: selectedStageFilter,
            );

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: themePrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.groups_rounded, color: themePrimary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'البحث الذكي واختيار المجموعة',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'إجمالي المجموعات: ${groups.length} مجموعة',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white60 : Colors.black54,
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
                  const SizedBox(height: 12),

                  // Search input field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                      child: TextField(
                        autofocus: false,
                        onChanged: (val) {
                          setModalState(() => modalSearch = val);
                        },
                        decoration: InputDecoration(
                          hintText: 'ابحث باسم المجموعة، المواعيد، المرحلة، القاعة...',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          prefixIcon: Icon(Icons.search_rounded, color: themePrimary, size: 20),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Stage filters
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _buildModalFilterChip(
                          label: 'الكل (${groups.length})',
                          isSelected: selectedStageFilter == 'الكل',
                          onTap: () => setModalState(() => selectedStageFilter = 'الكل'),
                          themePrimary: themePrimary,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildModalFilterChip(
                          label: 'المرحلة الابتدائية',
                          isSelected: selectedStageFilter == 'المرحلة الابتدائية',
                          onTap: () => setModalState(() => selectedStageFilter = 'المرحلة الابتدائية'),
                          themePrimary: themePrimary,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildModalFilterChip(
                          label: 'المرحلة الإعدادية',
                          isSelected: selectedStageFilter == 'المرحلة الإعدادية',
                          onTap: () => setModalState(() => selectedStageFilter = 'المرحلة الإعدادية'),
                          themePrimary: themePrimary,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildModalFilterChip(
                          label: 'المرحلة الثانوية',
                          isSelected: selectedStageFilter == 'المرحلة الثانوية',
                          onTap: () => setModalState(() => selectedStageFilter = 'المرحلة الثانوية'),
                          themePrimary: themePrimary,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 20),

                  // Groups List
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: isDark ? Colors.white24 : Colors.black26),
                                const SizedBox(height: 10),
                                const Text('لا توجد مجموعات مطابقة للبحث'),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final g = filtered[index];
                              final isCurrent = selectedGroup?.id == g.id;
                              final grpStudentsCount = students.where((s) => s.groupId == g.id).length;

                              return InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    selectedGroup = g;
                                    _groupSearchQuery = '';
                                    _groupSearchController.clear();
                                  });
                                  _loadGroupDetails(g);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? themePrimary.withValues(alpha: isDark ? 0.2 : 0.08)
                                        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isCurrent
                                          ? themePrimary
                                          : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
                                      width: isCurrent ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: Color(g.colorValue).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Center(
                                          child: Icon(Icons.groups_rounded, color: Color(g.colorValue), size: 22),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    g.name,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: themePrimary.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '$grpStudentsCount طالب',
                                                    style: TextStyle(
                                                      color: themePrimary,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${g.grade} • ${g.schedule}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark ? Colors.white60 : Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isCurrent)
                                        Icon(Icons.check_circle_rounded, color: themePrimary, size: 22),
                                    ],
                                  ),
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

  // ==========================================================================
  // TAB 3: GROUPS & SESSIONS REPORTS
  // ==========================================================================
  Widget _buildGroupReportTab(bool isDark) {
    if (groups.isEmpty) {
      return const Center(child: Text('لا توجد مجموعات مسجلة'));
    }

    final group = selectedGroup ?? groups.first;
    final groupStudents = students.where((s) => s.groupId == group.id).toList();
    final debtors = groupStudents.where((s) => s.hasOutstandingPayment).length;
    final expectedRevenue = groupStudents.length * group.monthlyPrice;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // Smart Search and Selector
        _buildSmartGroupSearchSection(isDark, group, groupStudents),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _ReportMetricCard(
                title: 'إجمالي الطلاب',
                value: '${groupStudents.length}',
                subtitle: 'مقيد بالمجموعة',
                color: Colors.blue,
                icon: Icons.groups_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ReportMetricCard(
                title: 'الإيراد المتوقع',
                value: '$expectedRevenue ج.م',
                subtitle: 'اشتراك ${group.monthlyPrice} ج.م/طالب',
                color: Colors.teal,
                icon: Icons.monetization_on_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ReportMetricCard(
                title: 'متأخرات اشتراك',
                value: '$debtors طالب',
                subtitle: 'من أصل ${groupStudents.length}',
                color: debtors > 0 ? Colors.red : Colors.green,
                icon: Icons.warning_amber_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ReportMetricCard(
                title: 'المرحلة والصف',
                value: group.grade.replaceAll('الصف ', ''),
                subtitle: group.stage,
                color: Colors.indigo,
                icon: Icons.school_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Session Logs Section for this group
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.history_edu_rounded, color: Color(0xFF0284C7)),
                    const SizedBox(width: 8),
                    Text('سجل حصص ${group.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${groupSessionLogs.length} حصة مسجلة', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                const Divider(height: 20),
                if (groupSessionLogs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Center(child: Text('لا توجد حصص مسجلة لهذه المجموعة بعد')),
                  )
                else
                  ...groupSessionLogs.take(5).map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      s.lessonTitle.isNotEmpty ? s.lessonTitle : 'موضوع الحصة',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  Text(s.date, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                ],
                              ),
                              if (s.homework.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text('الواجب: ${s.homework}', style: const TextStyle(fontSize: 11.5, color: Colors.teal)),
                              ],
                            ],
                          ),
                        ),
                      )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Students in Group
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('قائمة طلاب ${group.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const Divider(height: 16),
                if (groupStudents.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('لا يوجد طلاب في هذه المجموعة')))
                else
                  ...groupStudents.map((s) => ListTile(
                        dense: true,
                        leading: CircleAvatar(child: Text(s.fullName.characters.first)),
                        title: Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(s.studentPhone, style: const TextStyle(fontSize: 11)),
                        trailing: Text(
                          s.hasOutstandingPayment ? 'متأخر ${s.outstandingAmount} ج.م' : 'مسدد ✅',
                          style: TextStyle(
                            color: s.hasOutstandingPayment ? Colors.red : Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                      )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // VISUAL REPORT CARD CUSTOMIZATION & LOGO CONTROLS
  // ==========================================================================
  Future<void> _pickReportLogo({required bool isBottomSeal}) async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty || result.first.path == null) return;
      final pickedFile = File(result.first.path!);
      if (!pickedFile.existsSync()) return;

      if (!mounted) return;
      final croppedFile = await CircularImageCropper.cropImage(
        context,
        imagePath: pickedFile.path,
        title: isBottomSeal
            ? 'قص وتعديل ختم التقرير الرسمي (السفلي)'
            : 'قص وتعديل لوجو المؤسسة للتقرير (العلوي)',
        isBottomSeal: isBottomSeal,
      );

      if (croppedFile != null && mounted) {
        final appDir = await getApplicationDocumentsDirectory();
        final folder = Directory('${appDir.path}/report_logos');
        if (!await folder.exists()) {
          await folder.create(recursive: true);
        }
        final ext = croppedFile.path.contains('.') ? croppedFile.path.split('.').last : 'png';
        final destPath = '${folder.path}/report_${isBottomSeal ? 'stamp' : 'header'}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await croppedFile.copy(destPath);

        setState(() {
          if (isBottomSeal) {
            _reportCardStampLogoPath = destPath;
          } else {
            _reportCardHeaderLogoPath = destPath;
          }
        });

        await widget.database.setSetting(
          isBottomSeal ? 'report_card_stamp_logo_path' : 'report_card_header_logo_path',
          destPath,
        );
        widget.database.notifyChange(DataChangeEvent.settings);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isBottomSeal
                    ? 'تم حفظ ختم التقرير الرسمي بنجاح ⚜️'
                    : 'تم حفظ لوجو المؤسسة للتقرير بنجاح 🖼️',
              ),
              backgroundColor: const Color(0xFF0D9488),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تعديل الشعار: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _resetReportLogo({required bool isBottomSeal}) async {
    setState(() {
      if (isBottomSeal) {
        _reportCardStampLogoPath = null;
      } else {
        _reportCardHeaderLogoPath = null;
      }
    });
    await widget.database.setSetting(
      isBottomSeal ? 'report_card_stamp_logo_path' : 'report_card_header_logo_path',
      '',
    );
    widget.database.notifyChange(DataChangeEvent.settings);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBottomSeal ? 'تمت استعادة ختم التقرير الافتراضي' : 'تمت استعادة لوجو التقرير الافتراضي',
          ),
        ),
      );
    }
  }

  Widget _buildReportCardSwitchRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color activeColor,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: activeColor,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: activeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: activeColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  }

  void _previewReportCardFromSettings() {
    StudentModel previewStudent;
    if (selectedStudent != null) {
      previewStudent = selectedStudent!;
    } else if (students.isNotEmpty) {
      previewStudent = students.first;
    } else {
      previewStudent = const StudentModel(
        id: '9999',
        fullName: 'أحمد محمود مصطفى',
        stage: 'الثانوية',
        grade: 'الصف الثالث الثانوي',
        studentPhone: '01000000000',
        parentPhone: '01000000000',
        groupId: '1',
        paymentPlan: 'monthly',
      );
    }

    _handleOpenVisualReportCard(
      previewStudent,
      studentAttendance.isNotEmpty ? 92 : 96,
      studentAttendance.isNotEmpty ? studentAttendance.where((a) => a.status == 'present').length : 12,
      studentAttendance.isNotEmpty ? studentAttendance.length : 13,
    );
  }

  Widget _buildVisualReportCardSettingsSection(bool isDark) {
    final primaryColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Card(
      elevation: 0,
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: primaryColor.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row with Live Preview Button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.palette_rounded, color: primaryColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تخصيص وضبط مظهر التقرير المصور 🎨',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'تحكم شامل في الألوان، الترتيب الرأسي، الشعارات، وإخفاء وإظهار كل قسم',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Live Preview CTA
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor.withValues(alpha: 0.15),
                  foregroundColor: primaryColor,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: primaryColor.withValues(alpha: 0.4)),
                  ),
                ),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('معاينة حية وتجربة فورية للتقرير 👁️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: _previewReportCardFromSettings,
              ),
            ),
            const Divider(height: 24),

            // 1. Layout Mode (عمودي انسيابي تحت بعض vs شبكي)
            const Text(
              '1. ترتيب وتوزيع عناصر التقرير 📐',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _reportCardDefaultLayout = 'vertical'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                      decoration: BoxDecoration(
                        color: _reportCardDefaultLayout == 'vertical'
                            ? primaryColor.withValues(alpha: 0.15)
                            : (isDark ? Colors.grey.shade900 : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _reportCardDefaultLayout == 'vertical' ? primaryColor : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.view_agenda_rounded, color: _reportCardDefaultLayout == 'vertical' ? primaryColor : Colors.grey, size: 20),
                          const SizedBox(height: 4),
                          Text(
                            'عمودي انسيابي 📱\n(تحت بعض)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: _reportCardDefaultLayout == 'vertical' ? FontWeight.bold : FontWeight.normal,
                              color: _reportCardDefaultLayout == 'vertical' ? primaryColor : null,
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
                    onTap: () => setState(() => _reportCardDefaultLayout = 'grid'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                      decoration: BoxDecoration(
                        color: _reportCardDefaultLayout == 'grid'
                            ? primaryColor.withValues(alpha: 0.15)
                            : (isDark ? Colors.grey.shade900 : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _reportCardDefaultLayout == 'grid' ? primaryColor : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.grid_view_rounded, color: _reportCardDefaultLayout == 'grid' ? primaryColor : Colors.grey, size: 20),
                          const SizedBox(height: 4),
                          Text(
                            'شبكي مدمج 📊\n(بطاقات متجاورة)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: _reportCardDefaultLayout == 'grid' ? FontWeight.bold : FontWeight.normal,
                              color: _reportCardDefaultLayout == 'grid' ? primaryColor : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 2. Light vs Dark Mode
            const Text(
              '2. وضع الإضاءة الافتراضي للتقرير 🌓',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _reportCardDefaultMode = 'dark'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                      decoration: BoxDecoration(
                        color: _reportCardDefaultMode == 'dark'
                            ? const Color(0xFF0F172A)
                            : (isDark ? Colors.grey.shade900 : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _reportCardDefaultMode == 'dark' ? const Color(0xFF38BDF8) : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.dark_mode_rounded, color: Color(0xFF38BDF8), size: 20),
                          SizedBox(height: 4),
                          Text(
                            '🌙 ليلي فاخر\n(كحلي ملكي)',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _reportCardDefaultMode = 'light'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                      decoration: BoxDecoration(
                        color: _reportCardDefaultMode == 'light'
                            ? const Color(0xFFFFFBEB)
                            : (isDark ? Colors.grey.shade900 : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _reportCardDefaultMode == 'light' ? const Color(0xFFD97706) : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.light_mode_rounded, color: Color(0xFFD97706), size: 20),
                          SizedBox(height: 4),
                          Text(
                            '☀️ نهاري عاجي\n(ورقي أنيق)',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 3. Theme Palettes
            const Text(
              '3. نمط الألوان والتدرج اللوني 🎨',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildThemeChip('cyan', 'سماوي كحلي 💎', const Color(0xFF0284C7)),
                _buildThemeChip('gold', 'ذهبي ملكي 👑', const Color(0xFFD97706)),
                _buildThemeChip('emerald', 'زمردي أخضر 🌿', const Color(0xFF059669)),
                _buildThemeChip('purple', 'بنفسجي فاخر 🔮', const Color(0xFF7C3AED)),
              ],
            ),
            const SizedBox(height: 16),

            // 4. Font Selection
            const Text(
              '4. نوع الخط العربي المستخدم 🖋️',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFontChip('cairo', 'كايرو (Cairo)'),
                _buildFontChip('tajawal', 'تجوال (Tajawal)'),
                _buildFontChip('readexPro', 'ريدكس (Readex)'),
                _buildFontChip('amiri', 'أميري (Amiri)'),
              ],
            ),
            const SizedBox(height: 16),

            // 5. Custom Title
            const Text(
              '5. عنوان التقرير الرئيسي في الترويسة 🏷️',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reportCardTitleController,
              decoration: InputDecoration(
                hintText: 'تقرير المتابعة والنمو الأكاديمي الشامل لولي الأمر 📊',
                filled: true,
                fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.title_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 18),

            // 6. Logos & Stamp Settings (Customized like Certificate!)
            const Text(
              '6. إدارة وتعديل الشعارات والأختام (بالقص الدائري الذكي) 🖼️',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildLogoConfigCard(
              title: 'لوجو المؤسسة / السنتر (أعلى التقرير)',
              subtitle: 'يظهر في ترويسة التقرير بجانب بيانات السنتر',
              logoPath: _reportCardHeaderLogoPath,
              isBottomSeal: false,
              isDark: isDark,
            ),
            const SizedBox(height: 10),
            _buildLogoConfigCard(
              title: 'ختم الإدارة وتوقيع المعلم (أسفل التقرير)',
              subtitle: 'يظهر في مربع التوثيق الرسمي وقسم التوقيعات',
              logoPath: _reportCardStampLogoPath,
              isBottomSeal: true,
              isDark: isDark,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'صورة الطالب تظهر تلقائياً بجانب الاسم في التقرير، ويمكن تغييرها وقصها من شاشة التقرير المباشرة أو ملف الطالب بدقة.',
                      style: TextStyle(fontSize: 11, color: Color(0xFFD97706)),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),

            // 7. Granular Switches (إظهار / إخفاء كل عنصر)
            const Text(
              '7. التحكم الدقيق في محتويات وعناصر التقرير ⚙️',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildReportCardSwitchRow(
              title: 'سجل الحضور والغياب والمواظبة 📅',
              subtitle: 'عرض إجمالي الحصص ونسبة الانضباط',
              icon: Icons.calendar_today_rounded,
              value: _reportCardShowAttendance,
              onChanged: (v) => setState(() => _reportCardShowAttendance = v),
              activeColor: Colors.teal,
            ),
            _buildReportCardSwitchRow(
              title: 'سجل الامتحانات والاختبارات الدورية 📝',
              subtitle: 'عرض نتائج الاختبارات والدرجات والتقييم',
              icon: Icons.assignment_turned_in_rounded,
              value: _reportCardShowExams,
              onChanged: (v) => setState(() => _reportCardShowExams = v),
              activeColor: Colors.blue,
            ),
            _buildReportCardSwitchRow(
              title: 'الواجبات والتسميع وملاحظات الحصة 📚',
              subtitle: 'عرض تفاصيل الأداء والواجبات المنزلية',
              icon: Icons.menu_book_rounded,
              value: _reportCardShowHomework,
              onChanged: (v) => setState(() => _reportCardShowHomework = v),
              activeColor: Colors.deepPurple,
            ),
            _buildReportCardSwitchRow(
              title: 'المصروفات والحالة المالية 💰',
              subtitle: 'إظهار حالة السداد والاشتراك لولي الأمر',
              icon: Icons.account_balance_wallet_rounded,
              value: _reportCardShowFinance,
              onChanged: (v) => setState(() => _reportCardShowFinance = v),
              activeColor: Colors.amber.shade800,
            ),
            _buildReportCardSwitchRow(
              title: 'رمز الاستجابة السريع الذكي (QR Code) 🔐',
              subtitle: 'كود التحقق الرقمي لتأكيد صحة التقرير',
              icon: Icons.qr_code_2_rounded,
              value: _reportCardShowQr,
              onChanged: (v) => setState(() => _reportCardShowQr = v),
              activeColor: Colors.indigo,
            ),
            _buildReportCardSwitchRow(
              title: 'ختم التوثيق وتوقيع المعلم المعتمد ⚜️',
              subtitle: 'عرض مربع الاعتماد الرسمي في أسفل التقرير',
              icon: Icons.verified_rounded,
              value: _reportCardShowStamp,
              onChanged: (v) => setState(() => _reportCardShowStamp = v),
              activeColor: const Color(0xFFD97706),
            ),
            _buildReportCardSwitchRow(
              title: 'ملاحظة وتوجيهات المعلم لولي الأمر ✍️',
              subtitle: 'صندوق التوجيه التربوي المخصص للطالب',
              icon: Icons.rate_review_rounded,
              value: _reportCardShowTeacherNote,
              onChanged: (v) => setState(() => _reportCardShowTeacherNote = v),
              activeColor: Colors.green,
            ),
            _buildReportCardSwitchRow(
              title: 'وسام التميز الأكاديمي 🌟',
              subtitle: 'إبراز بطاقة تميز إضافية في التقرير',
              icon: Icons.military_tech_rounded,
              value: _reportCardShowRank,
              onChanged: (v) => setState(() => _reportCardShowRank = v),
              activeColor: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeChip(String value, String label, Color color) {
    final isSelected = _reportCardDefaultTheme == value;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label, style: TextStyle(fontSize: 11.5, color: isSelected ? Colors.white : null, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selectedColor: color,
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      onSelected: (val) {
        if (val) setState(() => _reportCardDefaultTheme = value);
      },
    );
  }

  Widget _buildFontChip(String value, String label) {
    final isSelected = _reportCardDefaultFont == value;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label, style: TextStyle(fontSize: 11.5, color: isSelected ? Colors.white : null, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selectedColor: const Color(0xFF0284C7),
      onSelected: (val) {
        if (val) setState(() => _reportCardDefaultFont = value);
      },
    );
  }

  Widget _buildLogoConfigCard({
    required String title,
    required String subtitle,
    required String? logoPath,
    required bool isBottomSeal,
    required bool isDark,
  }) {
    final hasCustom = logoPath != null && logoPath.isNotEmpty && File(logoPath).existsSync();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? Colors.grey.shade800 : Colors.white,
              border: Border.all(color: isBottomSeal ? const Color(0xFFD97706) : const Color(0xFF0284C7), width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasCustom
                ? Image.file(File(logoPath), fit: BoxFit.cover)
                : Icon(
                    isBottomSeal ? Icons.verified_user_rounded : Icons.school_rounded,
                    color: isBottomSeal ? const Color(0xFFD97706) : const Color(0xFF0284C7),
                    size: 24,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.crop_rotate_rounded, size: 14),
                label: const Text('قص وتغيير', style: TextStyle(fontSize: 11)),
                onPressed: () => _pickReportLogo(isBottomSeal: isBottomSeal),
              ),
              if (hasCustom)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _resetReportLogo(isBottomSeal: isBottomSeal),
                  child: const Text('استعادة الافتراضي', style: TextStyle(fontSize: 10, color: Colors.redAccent)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // TAB 4: AUTOMATION SCHEDULING & CUSTOM FOOTERS
  // ==========================================================================
  Widget _buildAutomationSettingsTab(bool isDark) {
    if (_isLoadingSettings) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
      children: [
        // Intro Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0284C7).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFF0284C7), size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إعدادات وضبط مظهر وجدولة التقارير ⚙️',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'حدد مظهر وبنية التقرير المصور الفاخر ومواعيد إرسال التقارير لولي الأمر وتذييل كل نوع رسالة.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Visual Report Card Customization Section
        _buildVisualReportCardSettingsSection(isDark),
        const SizedBox(height: 14),

        // 1. Session Report Scheduling
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.event_note_rounded, color: Colors.teal),
                    SizedBox(width: 8),
                    Text('تقرير الحصة اليومي المجدول', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 20),
                const Text('موعد إرسال تقرير الحصة لولي الأمر:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'end_of_day',
                      label: Text('في نهاية اليوم 🌙', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: 'after_class',
                      label: Text('مباشرة بعد الحصة ⚡', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {_sessionScheduleMode},
                  onSelectionChanged: (set) {
                    if (set.isNotEmpty) setState(() => _sessionScheduleMode = set.first);
                  },
                ),
                const SizedBox(height: 6),
                if (_sessionScheduleMode == 'end_of_day')
                  ListTile(
                    title: const Text('ساعة الإرسال المسائية', style: TextStyle(fontSize: 13)),
                    trailing: TextButton.icon(
                      icon: const Icon(Icons.access_time_rounded, size: 16),
                      label: Text(_formatTime(_sessionReportTime)),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: _sessionReportTime);
                        if (picked != null) setState(() => _sessionReportTime = picked);
                      },
                    ),
                  ),
                SwitchListTile(
                  title: const Text('تضمين الموقف المالي في تقرير الحصة اليومي', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('يُفضل إيقافه لتركيز تقرير الحصة على المتابعة والواجب فقط', style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                  value: _sessionIncludeFinancials,
                  onChanged: (v) => setState(() => _sessionIncludeFinancials = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 2. Weekly & Monthly Report Automation
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, color: Color(0xFF0284C7)),
                    SizedBox(width: 8),
                    Text('التقارير الدورية (أسبوعية وشهرية)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 20),
                SwitchListTile(
                  title: const Text('تفعيل التقرير الأسبوعي الشامل', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text('يرسل ملخص الحضور والدرجات يوم: $_weeklyReportDay الساعة ${_formatTime(_weeklyReportTime)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  value: _weeklyReportEnabled,
                  onChanged: (v) => setState(() => _weeklyReportEnabled = v),
                ),
                if (_weeklyReportEnabled) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Text('يوم الإرسال: ', style: TextStyle(fontSize: 12)),
                        DropdownButton<String>(
                          value: _weeklyReportDay,
                          items: ['الخميس', 'الجمعة', 'السبت']
                              .map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12))))
                              .toList(),
                          onChanged: (d) => setState(() => _weeklyReportDay = d ?? 'الجمعة'),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.access_time_rounded, size: 16),
                          label: Text(_formatTime(_weeklyReportTime)),
                          onPressed: () async {
                            final picked = await showTimePicker(context: context, initialTime: _weeklyReportTime);
                            if (picked != null) setState(() => _weeklyReportTime = picked);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(),
                SwitchListTile(
                  title: const Text('تفعيل التقرير الشهري للنمو التعليمي والمالي', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text('يرسل تلقائياً في نهاية الشهر الساعة: ${_formatTime(_monthlyReportTime)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  value: _monthlyReportEnabled,
                  onChanged: (v) => setState(() => _monthlyReportEnabled = v),
                ),
                if (_monthlyReportEnabled)
                  ListTile(
                    title: const Text('ساعة إرسال التقرير الشهري', style: TextStyle(fontSize: 13)),
                    trailing: TextButton.icon(
                      icon: const Icon(Icons.access_time_rounded, size: 16),
                      label: Text(_formatTime(_monthlyReportTime)),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: _monthlyReportTime);
                        if (picked != null) setState(() => _monthlyReportTime = picked);
                      },
                    ),
                  ),
                SwitchListTile(
                  title: const Text('تضمين الموقف المالي في التقرير الشهري', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('موصى به لإحاطة ولي الأمر بالمطالبات والاشتراكات الشهرية', style: TextStyle(fontSize: 10.5, color: Colors.grey)),
                  value: _monthlyIncludeFinancials,
                  onChanged: (v) => setState(() => _monthlyIncludeFinancials = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 3. Custom Footers for each report type
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.format_quote_rounded, color: Colors.deepPurple),
                    SizedBox(width: 8),
                    Text('تخصيص تذييل كل نوع تقرير', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 20),
                const Text('تذييل تقرير الحصة اليومي:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _sessionFooterController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('تذييل التقرير الأسبوعي:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _weeklyFooterController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('تذييل التقرير الشهري الشامل:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: _monthlyFooterController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Save Settings Button
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0284C7),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.save_rounded, color: Colors.white),
          label: const Text('حفظ إعدادات وتذييلات التقارير ✨', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          onPressed: _saveAutomationSettings,
        ),
      ],
    );
  }

  Future<void> _saveAutomationSettings() async {
    await widget.database.setSetting('session_report_auto_schedule', _sessionScheduleMode);
    await widget.database.setSetting('daily_report_time', _formatTime(_sessionReportTime));
    await widget.database.setSetting('weekly_report_enabled', _weeklyReportEnabled ? 'true' : 'false');
    await widget.database.setSetting('weekly_report_day', _weeklyReportDay);
    await widget.database.setSetting('weekly_report_time', _formatTime(_weeklyReportTime));
    await widget.database.setSetting('monthly_report_enabled', _monthlyReportEnabled ? 'true' : 'false');
    await widget.database.setSetting('monthly_report_time', _formatTime(_monthlyReportTime));

    await widget.database.setSetting('session_report_include_financials', _sessionIncludeFinancials ? 'true' : 'false');
    await widget.database.setSetting('weekly_report_include_financials', _weeklyIncludeFinancials ? 'true' : 'false');
    await widget.database.setSetting('monthly_report_include_financials', _monthlyIncludeFinancials ? 'true' : 'false');

    await widget.database.setSetting('footer_session_report', _sessionFooterController.text.trim());
    await widget.database.setSetting('footer_weekly_report', _weeklyFooterController.text.trim());
    await widget.database.setSetting('footer_monthly_report', _monthlyFooterController.text.trim());

    // Save visual report card customization
    await widget.database.setSetting('report_card_default_mode', _reportCardDefaultMode);
    await widget.database.setSetting('report_card_default_layout', _reportCardDefaultLayout);
    await widget.database.setSetting('report_card_default_font', _reportCardDefaultFont);
    await widget.database.setSetting('report_card_default_theme', _reportCardDefaultTheme);
    await widget.database.setSetting('report_card_default_title', _reportCardTitleController.text.trim());
    await widget.database.setSetting('report_card_show_qr', _reportCardShowQr ? 'true' : 'false');
    await widget.database.setSetting('report_card_show_finance', _reportCardShowFinance ? 'true' : 'false');
    await widget.database.setSetting('report_card_show_stamp', _reportCardShowStamp ? 'true' : 'false');
    await widget.database.setSetting('report_card_show_attendance', _reportCardShowAttendance ? 'true' : 'false');
    await widget.database.setSetting('report_card_show_exams', _reportCardShowExams ? 'true' : 'false');
    await widget.database.setSetting('report_card_show_homework', _reportCardShowHomework ? 'true' : 'false');
    await widget.database.setSetting('report_card_show_rank', _reportCardShowRank ? 'true' : 'false');
    await widget.database.setSetting('report_card_show_note', _reportCardShowTeacherNote ? 'true' : 'false');
    if (_reportCardHeaderLogoPath != null) {
      await widget.database.setSetting('report_card_header_logo_path', _reportCardHeaderLogoPath!);
    }
    if (_reportCardStampLogoPath != null) {
      await widget.database.setSetting('report_card_stamp_logo_path', _reportCardStampLogoPath!);
    }

    // Trigger instant synchronization across all app sections
    widget.database.notifyChange(DataChangeEvent.settings);
    widget.database.notifyChange(DataChangeEvent.reports);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ كافة إعدادات التقارير وتنسيق المظهر وتطبيق التزامن اللحظي بنجاح ✨'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
