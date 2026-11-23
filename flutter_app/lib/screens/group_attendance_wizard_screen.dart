import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/cloud_sync_service.dart';
import '../core/database/database_service.dart';
import '../core/notification_service.dart';
import '../core/security_service.dart';
import '../core/whatsapp_service.dart';
import '../models/group_model.dart';
import '../models/curriculum_model.dart';
import '../models/exam_model.dart';
import '../models/student_model.dart';
import '../widgets/attendance_lesson_picker_sheet.dart';
import '../widgets/visual_student_report_card.dart';
import 'scanner_screen.dart';
import 'today_attendance_screen.dart';

class GroupAttendanceWizardScreen extends StatefulWidget {
  const GroupAttendanceWizardScreen({
    super.key,
    required this.database,
    required this.group,
    required this.date,
    this.latestLog,
    this.onAttendanceUpdated,
    this.initialSessionType,
  });

  final DatabaseService database;
  final GroupModel group;
  final String date;
  final SessionLogModel? latestLog;
  final VoidCallback? onAttendanceUpdated;
  final String? initialSessionType;

  @override
  State<GroupAttendanceWizardScreen> createState() =>
      _GroupAttendanceWizardScreenState();
}

class _GroupAttendanceWizardScreenState
    extends State<GroupAttendanceWizardScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = true;

  // Session Data & Notebook Controllers
  late TextEditingController _topicController;
  late TextEditingController _contentController;
  late TextEditingController _homeworkController;
  late TextEditingController _nextTopicController;
  late TextEditingController _prevHomeworkController;
  late TextEditingController _prevLessonController;
  late TextEditingController _notesController;

  String _sessionType = 'regular'; // 'regular', 'double', 'makeup'
  bool _isSessionLocked = false;
  Map<String, dynamic>? _teacherCancellation;
  bool get _isSessionCancelledByTeacher => _teacherCancellation != null;

  // Center & Teacher Settings for live preview
  String _centerName = 'سنتر الأستاذ';
  String _teacherName = 'أستاذ المادة';
  String _customTemplate = '';

  // Students & Attendance Data
  List<Map<String, dynamic>> _students = [];
  List<CurriculumLessonModel> _groupLessons = [];
  String? _boundCurriculumName;
  String _searchQuery = '';

  // Step 1: Selected Previous Lessons (Multi-select)
  List<String> _selectedPrevLessons = [];

  // Step 2: Today's Lesson / Exam Mode
  bool _isTodayExamMode = false;
  List<String> _todayExamLessons = [];
  late TextEditingController _todayExamTitleController;
  late TextEditingController _todayExamMaxScoreController;
  String _todayExamGradingMode = 'now'; // 'now' (رصد فوري الآن) or 'scheduled' (جدولة رصد الدرجات لاحقاً)
  final Map<String, double> _todayExamScores = {}; // studentId -> score
  final Map<String, String> _todayExamNotes = {}; // studentId -> note (e.g. 'إجابة نموذجية ⭐')

  // Step 3: Next Lesson / Next Exam Mode
  bool _isNextExamMode = false;
  List<String> _nextExamLessons = [];
  late TextEditingController _nextExamTitleController;

  // Step 4: Selected Student for Live Report Preview & Collapsible State
  String? _selectedPreviewStudentId;
  bool _showReportPreview = false;

  // Step 3: Scheduling & Reminders Data
  bool _scheduleReportLater = false;
  TimeOfDay _scheduledReportTime = const TimeOfDay(hour: 20, minute: 0); // 8:00 PM
  bool _enableUnsentReportAlert = true;
  TimeOfDay _unsentAlertTime = const TimeOfDay(hour: 20, minute: 30); // 8:30 PM
  bool _isReportSent = false;
  final Set<String> _sentAbsenceStudentIds = {};

  final List<String> _quickNotes = [
    'متفوق ومتميز 🏆',
    'يحتاج تركيز واهتمام 💡',
    'لم ينتبه أثناء الشرح ⚠️',
    'تفاعل ممتاز في الحصة 👏',
    'أداء رائع في حل التمارين ⭐',
    'لم يحضر الأدوات المطلوبة 🎒',
  ];

  // Presets / Fixed Homework Templates for Step 2
  final List<({String title, String icon, String text, Color color})>
      _homeworkTemplates = [
    (
      title: 'تطبيق وكتابة كود 💻',
      icon: '💻',
      text: 'كتابة وتطبيق الكود البرمجي العملي الخاص بحصة اليوم وتسليمه على المنصة/الجهاز 💻⚡',
      color: const Color(0xFF0284C7),
    ),
    (
      title: 'مشروع برمجي 🚀',
      icon: '🚀',
      text: 'تطوير مشروع برمجي مصغر وتطبيق المفاهيم والأكواد المشروحة في الحصة 🚀',
      color: const Color(0xFF8B5CF6),
    ),
    (
      title: 'تصحيح أخطاء (Debug) 🐛',
      icon: '🐛',
      text: 'حل تدريب تصحيح الأخطاء البرمجية (Debugging) وإعادة تشغيل الكود بنجاح 🛠️',
      color: const Color(0xFFEF4444),
    ),
    (
      title: 'تحدي الخوارزميات 🧩',
      icon: '🧩',
      text: 'حل تحدي التفكير المنطقي ورسم مخطط التدفق (Flowchart) للمسألة البرمجية 🧩',
      color: const Color(0xFF10B981),
    ),
    (
      title: 'مشروع سكراتش / بلوكات 🐱',
      icon: '🐱',
      text: 'برمجة وتصميم المشروع التفاعلي على منصة Scratch / Blocks وحفظه باسم الطالب 🎨',
      color: const Color(0xFFF59E0B),
    ),
    (
      title: 'كويز تقني وبرمجي 🌐',
      icon: '🌐',
      text: 'أداء الكويز الإلكتروني واختبار المفاهيم التقنية والبرمجية عبر الرابط 🌐',
      color: const Color(0xFF06B6D4),
    ),
    (
      title: 'شيت تدريبات التكنولوجيا 📝',
      icon: '📝',
      text: 'حل تدريبات وتمارين شيت مادة التكنولوجيا والبرمجة صـ ',
      color: const Color(0xFF6366F1),
    ),
    (
      title: 'بحث واستكشاف تقني 💡',
      icon: '💡',
      text: 'إعداد بحث مصغر عن أحدث أدوات التكنولوجيا وتجهيز فكرة تطبيقها 💡',
      color: const Color(0xFFEC4899),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _sessionType = widget.initialSessionType ?? 'regular';

    _topicController = TextEditingController(
      text: widget.latestLog?.lessonTitle ?? '',
    );
    _contentController = TextEditingController(
      text: widget.latestLog?.contentCovered ?? '',
    );
    _homeworkController = TextEditingController(
      text: widget.latestLog?.homework ?? '',
    );
    _nextTopicController = TextEditingController(
      text: widget.latestLog?.nextTopic ?? '',
    );
    _prevHomeworkController = TextEditingController(
      text: widget.latestLog?.previousHomeworkReview ?? '',
    );
    _prevLessonController = TextEditingController(
      text: widget.latestLog?.previousLessonReview ?? '',
    );
    _notesController = TextEditingController(
      text: widget.latestLog?.notes ?? '',
    );

    _todayExamTitleController = TextEditingController(text: 'اختبار تقييمي شامل 📝');
    _todayExamMaxScoreController = TextEditingController(text: '20');
    _nextExamTitleController = TextEditingController(text: 'كويز تقييمي على الجزء المشروح 🎯');

    // Populate initial selected previous lessons from log if available
    final prevRev = widget.latestLog?.previousLessonReview;
    if (prevRev != null && prevRev.isNotEmpty) {
      final parts = prevRev
          .split(RegExp(r'[,،+]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      _selectedPrevLessons = parts;
    }

    if (widget.latestLog?.nextQuiz != null && widget.latestLog!.nextQuiz.isNotEmpty) {
      _isNextExamMode = true;
      _nextExamTitleController.text = widget.latestLog!.nextQuiz;
    }

    _loadData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _topicController.dispose();
    _contentController.dispose();
    _homeworkController.dispose();
    _nextTopicController.dispose();
    _prevHomeworkController.dispose();
    _prevLessonController.dispose();
    _notesController.dispose();
    _todayExamTitleController.dispose();
    _todayExamMaxScoreController.dispose();
    _nextExamTitleController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

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

    final center = await widget.database.getSetting(
      'center_name',
      defaultValue: 'سنتر الأستاذ التعليمي',
    );
    final teacher = await widget.database.getSetting(
      'teacher_name',
      defaultValue: 'أستاذ المادة',
    );

    // Load scheduled report status if any
    final scheduledJson = await widget.database.getSetting(
      'scheduled_report_${widget.group.id}_${widget.date}',
      defaultValue: '',
    );
    if (scheduledJson.isNotEmpty) {
      try {
        final map = jsonDecode(scheduledJson) as Map<String, dynamic>;
        _scheduleReportLater = map['enabled'] == true;
        if (map['time'] != null) {
          final parts = (map['time'] as String).split(':');
          _scheduledReportTime = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
        }
        _enableUnsentReportAlert = map['alert_enabled'] ?? true;
        if (map['alert_time'] != null) {
          final parts = (map['alert_time'] as String).split(':');
          _unsentAlertTime = TimeOfDay(
            hour: int.parse(parts[0]),
            minute: int.parse(parts[1]),
          );
        }
      } catch (_) {}
    }

    final sentStatus = await widget.database.getSetting(
      'report_sent_${widget.group.id}_${widget.date}',
      defaultValue: 'false',
    );
    final customTpl = await widget.database.getSetting(
      'whatsapp_template_session_report',
      defaultValue: '',
    );

    final sentAbsences = <String>{};
    for (final s in data) {
      final sId = s['id'] as String? ?? '';
      if (sId.isNotEmpty) {
        final sent = await widget.database.isStudentReportSentToday(
          studentId: sId,
          date: widget.date,
          category: 'absence',
        );
        if (sent) sentAbsences.add(sId);
      }
    }

    // Check if an exam already exists for this group on this date
    try {
      final existingExams = await widget.database.getExams(groupId: widget.group.id);
      final todayExam = existingExams.where((e) => e.date == widget.date).firstOrNull;
      if (todayExam != null) {
        _isTodayExamMode = true;
        _todayExamTitleController.text = todayExam.title;
        _todayExamMaxScoreController.text = todayExam.maxScore.toStringAsFixed(
            todayExam.maxScore.truncateToDouble() == todayExam.maxScore ? 0 : 1);
        final scores = await widget.database.getExamScoresForExam(todayExam.id);
        _todayExamScores.addAll(scores);
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _sentAbsenceStudentIds.clear();
        _sentAbsenceStudentIds.addAll(sentAbsences);
        _boundCurriculumName = boundCurriculum;
        _students = List<Map<String, dynamic>>.from(
          data.map((m) => Map<String, dynamic>.from(m)),
        );
        _groupLessons = lessons;
        _isSessionLocked = lockVal == 'true';
        _sessionType = savedType;
        _teacherCancellation = cancelInfo;
        _isReportSent = sentStatus == 'true';
        _centerName = center;
        _teacherName = teacher;
        _customTemplate = customTpl;
        if (_students.isNotEmpty && _selectedPreviewStudentId == null) {
          _selectedPreviewStudentId = _students.first['id'] as String?;
        }
        _isLoading = false;
      });
    }
  }

  // Dynamic Step Validation - Checkmark ONLY appears when step data is completed
  bool _isStepCompleted(int step) {
    switch (step) {
      case 0: // المرحلة 1: التحضير للطلبة (كشف الحضور)
        if (_students.isEmpty) return false;
        return _students.every((s) {
          final status = s['attendance_status'] as String?;
          return status != null && status.isNotEmpty;
        });

      case 1: // المرحلة 2: المراجعة على الحصة السابقة والتسميع والواجب
        final hasLesson = _selectedPrevLessons.isNotEmpty ||
            _prevLessonController.text.trim().isNotEmpty;
        final presentStudents = _students.where(
          (s) =>
              s['attendance_status'] == 'present' ||
              s['attendance_status'] == 'late',
        ).toList();
        if (presentStudents.isEmpty) {
          return hasLesson;
        }
        final hasEvaluations = presentStudents.any(
          (s) =>
              (s['recitation_rating'] as String?)?.isNotEmpty == true ||
              (s['homework_status'] as String?)?.isNotEmpty == true,
        );
        return hasLesson && hasEvaluations;

      case 2: // المرحلة 3: شرح درس اليوم أو اختبار الحصة
        return _isTodayExamMode
            ? _todayExamTitleController.text.trim().isNotEmpty
            : _topicController.text.trim().isNotEmpty;

      case 3: // المرحلة 4: تجهيز الدرس القادم والتكليف أو اختبار قادم
        if (_isNextExamMode) {
          return (_nextExamLessons.isNotEmpty || _nextExamTitleController.text.trim().isNotEmpty) &&
              _homeworkController.text.trim().isNotEmpty;
        }
        final hasNextTopic = _nextTopicController.text.trim().isNotEmpty;
        final hasHw = _homeworkController.text.trim().isNotEmpty;
        return hasNextTopic && hasHw;

      case 4: // المرحلة 5: المعاينة والإرسال وجدولة التقرير
        return _isReportSent || _scheduleReportLater || _isSessionLocked;

      default:
        return false;
    }
  }

  Future<void> _saveSessionLogData() async {
    String effectiveTitle;
    String effectiveContent;

    if (_isTodayExamMode) {
      effectiveTitle = _todayExamTitleController.text.trim().isNotEmpty
          ? _todayExamTitleController.text.trim()
          : 'اختبار الحصة 📝';
      effectiveContent = _todayExamLessons.isNotEmpty
          ? 'الدروس المشمولة في الاختبار:\n• ${_todayExamLessons.join('\n• ')}'
          : 'اختبار تقييمي شامل';

      // Save exam to database
      final examId = 'EXAM_${widget.group.id}_${widget.date}';
      final maxScore = double.tryParse(_todayExamMaxScoreController.text.trim()) ?? 20.0;
      await widget.database.saveExam(ExamModel(
        id: examId,
        title: effectiveTitle,
        groupId: widget.group.id,
        date: widget.date,
        maxScore: maxScore,
      ));

      if (_todayExamGradingMode == 'now') {
        for (final entry in _todayExamScores.entries) {
          await widget.database.recordExamScore(ExamScoreModel(
            examId: examId,
            studentId: entry.key,
            score: entry.value,
            note: _todayExamNotes[entry.key] ?? '',
          ));
        }
        try {
          CloudSyncService.instance.syncExams();
        } catch (_) {}
      }
    } else {
      effectiveTitle = _topicController.text.trim().isNotEmpty
          ? _topicController.text.trim()
          : (_nextTopicController.text.trim().isNotEmpty
              ? _nextTopicController.text.trim()
              : (_prevLessonController.text.trim().isNotEmpty
                  ? 'مراجعة: ${_prevLessonController.text.trim()}'
                  : 'حصة دراسية'));
      effectiveContent = _contentController.text.trim();
    }

    String effectiveNextTopic;
    String effectiveNextQuiz;

    if (_isNextExamMode) {
      final examLessonsStr = _nextExamLessons.isNotEmpty ? _nextExamLessons.join('، ') : '';
      effectiveNextQuiz = _nextExamTitleController.text.trim().isNotEmpty
          ? '${_nextExamTitleController.text.trim()}${examLessonsStr.isNotEmpty ? " (على: $examLessonsStr)" : ""}'
          : (examLessonsStr.isNotEmpty ? 'اختبار على: $examLessonsStr' : 'اختبار الحصة القادمة 🎯');
      effectiveNextTopic = _nextTopicController.text.trim().isNotEmpty
          ? _nextTopicController.text.trim()
          : 'اختبار تقييمي شامل 🎯';
    } else {
      effectiveNextTopic = _nextTopicController.text.trim();
      effectiveNextQuiz = '';
    }

    final log = SessionLogModel(
      groupId: widget.group.id,
      date: widget.date,
      lessonTitle: effectiveTitle,
      contentCovered: effectiveContent,
      homework: _homeworkController.text.trim(),
      nextTopic: effectiveNextTopic,
      nextQuiz: effectiveNextQuiz,
      previousHomeworkReview: _prevHomeworkController.text.trim(),
      previousLessonReview: _prevLessonController.text.trim(),
      notes: _notesController.text.trim(),
    );
    if (_isReportSent) return;
    await widget.database.saveSessionLog(log);
    widget.onAttendanceUpdated?.call();
  }

  Future<void> _updateStudentStatus(String studentId, String? status) async {
    if (_isReportSent) {
      _showReportSentImmutableNotice();
      return;
    }
    if (_isSessionLocked) {
      _showLockedNotice();
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      final idx = _students.indexWhere((s) => s['id'] == studentId);
      if (idx != -1) {
        _students[idx]['attendance_status'] = status;
      }
    });

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
    } else {
      await widget.database.setStudentAttendanceStatus(
        studentId: studentId,
        date: widget.date,
        status: status,
        sessionType: _sessionType,
      );
    }

    final stMap = _students.firstWhere((s) => s['id'] == studentId, orElse: () => {});
    await widget.database.processAttendanceSessionBilling(
      group: widget.group,
      studentId: studentId,
      studentName: stMap['full_name'] as String? ?? '',
      date: widget.date,
      status: status,
      sessionScale: _sessionType,
    );
    widget.onAttendanceUpdated?.call();
  }

  Future<void> _resetAllAttendance() async {
    if (_isReportSent) {
      _showReportSentImmutableNotice();
      return;
    }
    if (_isSessionLocked) {
      _showLockedNotice();
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'تصفير كشف الحضور',
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

    HapticFeedback.heavyImpact();
    setState(() {
      for (final s in _students) {
        s['attendance_status'] = null;
      }
    });

    await widget.database.resetGroupAttendanceForDate(
      groupId: widget.group.id,
      date: widget.date,
    );
    widget.onAttendanceUpdated?.call();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تصفير كشف الحضور وإعادة ضبط جميع الطلاب إلى (لم يحدد) 🔄'),
        backgroundColor: Colors.blueGrey,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _markAll(String status) async {
    if (_isReportSent) {
      _showReportSentImmutableNotice();
      return;
    }
    if (_isSessionLocked) {
      _showLockedNotice();
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() {
      for (final s in _students) {
        s['attendance_status'] = status;
      }
    });

    for (final s in _students) {
      final sId = s['id'] as String;
      await widget.database.setStudentAttendanceStatus(
        studentId: sId,
        date: widget.date,
        status: status,
        sessionType: _sessionType,
      );
      await widget.database.processAttendanceSessionBilling(
        group: widget.group,
        studentId: sId,
        studentName: s['full_name'] as String? ?? '',
        date: widget.date,
        status: status,
        sessionScale: _sessionType,
      );
    }
    widget.onAttendanceUpdated?.call();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status == 'present'
              ? 'تم تحضير جميع الطلاب حاضر (${_students.length} طالب) بضغطة واحدة ⚡'
              : 'تم تصفير كشف الحضور.',
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _updateStudentEvaluation({
    required String studentId,
    String? homeworkStatus,
    String? recitationRating,
    String? notes,
  }) async {
    if (_isReportSent) {
      _showReportSentImmutableNotice();
      return;
    }
    if (_isSessionLocked) {
      _showLockedNotice();
      return;
    }

    setState(() {
      final idx = _students.indexWhere((s) => s['id'] == studentId);
      if (idx != -1) {
        if (homeworkStatus != null) {
          _students[idx]['homework_status'] = homeworkStatus;
        }
        if (recitationRating != null) {
          _students[idx]['recitation_rating'] = recitationRating;
        }
        if (notes != null) {
          _students[idx]['notes'] = notes;
        }
      }
    });

    await widget.database.updateStudentAttendanceDetails(
      studentId: studentId,
      date: widget.date,
      homeworkStatus: homeworkStatus,
      recitationRating: recitationRating,
      notes: notes,
    );
    widget.onAttendanceUpdated?.call();
  }

  void _showReportSentImmutableNotice() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: const Row(
          children: [
            Icon(Icons.lock_rounded, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'تم إرسال تقرير الحصة لأولياء الأمور 🔒 تم قفل الحصة نهائياً وممنوع أي تعديل حتى بالبصمة!',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _lockSession() async {
    final authOk = await SecurityService.authenticate(
      context: context,
      database: widget.database,
      reason: 'تأكيد البصمة لاعتماد وقفل كشف الحصة 🔒',
    );
    if (!authOk) return;

    await widget.database.setSetting(
      'attendance_lock_${widget.group.id}_${widget.date}',
      'true',
    );
    setState(() => _isSessionLocked = true);

    // Auto send absence WhatsApp alert to absent students
    // Strict Lock: Lock attendance securely without background WhatsApp spam
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم اعتماد وقفل كشف الحضور رسمياً بنجاح 🔒✓'),
        backgroundColor: Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sendSingleStudentAbsenceAlert(Map<String, dynamic> student) async {
    final parentPhone = (student['parent_phone'] as String? ?? '').trim();
    final studentName = student['full_name'] as String? ?? '';
    final studentId = student['id'] as String? ?? student['student_id'] as String?;
    if (parentPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رقم هاتف ولي الأمر غير مسجل لهذا الطالب'),
          behavior: SnackBarBehavior.floating,
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

    final message = WhatsAppService.absenceMessage(
      centerName: centerName,
      teacherName: teacherName,
      studentName: studentName,
      date: widget.date,
    );

    final result = await WhatsAppService.dispatchMessageDetailed(
      database: widget.database,
      phone: parentPhone,
      message: message,
      studentId: studentId,
      studentName: studentName,
      category: 'absence',
    );

    if (mounted) {
      if (studentId != null && studentId.isNotEmpty) {
        setState(() => _sentAbsenceStudentIds.add(studentId));
      }
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF059669),
          content: Text(
            result.alreadySent
                ? 'تم إرسال إشعار الغياب مسبقاً لولي أمر $studentName بنجاح ✅'
                : 'تم إرسال إشعار الغياب لولي أمر $studentName بنجاح ✅',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
      // إغلاق النافذة الخاصة بتحضير المجموعة بعد تأكيد الإرسال
      Navigator.of(context).pop();
    }
  }

  Future<void> _unlockSession() async {
    if (_isReportSent) {
      _showReportSentImmutableNotice();
      return;
    }
    final authOk = await SecurityService.authenticate(
      context: context,
      database: widget.database,
      reason: 'تأكيد البصمة لفك قفل كشف الحضور والتعديل 🔓',
    );
    if (!authOk) return;

    await widget.database.setSetting(
      'attendance_lock_${widget.group.id}_${widget.date}',
      'false',
    );
    setState(() => _isSessionLocked = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم فك القفل بنجاح، يمكنك التعديل بحرية الآن 🔓'),
        backgroundColor: Colors.blueAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openSendReportFlow() async {
    HapticFeedback.heavyImpact();

    // Verification: check if any student has not been marked
    final unmarked = _students.where((s) {
      final st = s['attendance_status'] as String?;
      return st == null || st.trim().isEmpty || st == 'unmarked';
    }).toList();

    if (unmarked.isNotEmpty) {
      final shouldMarkAbsent = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('طلاب لم يتم رصدهم ⏱️', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
            'يوجد ${unmarked.length} طلاب لم يتم رصد حضورهم أو غيابهم حتى الآن.\n\nهل ترغب في احتسابهم غائبين رسمياً 🚨 لضمان دقة التقارير وسجلات المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('متابعة بدون تغيير'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم، احتسابهم غائبين 🚨', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (shouldMarkAbsent == true) {
        for (final s in unmarked) {
          final sId = s['id'] as String?;
          if (sId != null && sId.isNotEmpty) {
            setState(() {
              final idx = _students.indexWhere((st) => st['id'] == sId);
              if (idx != -1) {
                _students[idx]['attendance_status'] = 'absent';
              }
            });
            await widget.database.setStudentAttendanceStatus(
              studentId: sId,
              date: widget.date,
              status: 'absent',
              sessionType: _sessionType,
            );
          }
        }
      }
    }

    // 2. Prompt Teacher: Send Text Report or Visual Report Card?
    final formatChoice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bCtx) {
        final isDark = Theme.of(bCtx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'اختر صيغة تقرير الحصة للإرسال 📲',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'حدّد الصيغة التي ترغب في إرسالها لولي الأمر عبر واتساب:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 18),
              // Option 1: Visual Report Card
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00F2FE),
                  foregroundColor: const Color(0xFF0B1120),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 1,
                ),
                icon: const Icon(Icons.image_rounded, size: 22),
                label: const Text(
                  '🖼️ كارت تقرير مصور (بطاقة الطالب المصورة الفاخرة)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                ),
                onPressed: () => Navigator.pop(bCtx, 'visual'),
              ),
              const SizedBox(height: 10),
              // Option 2: Written Text Report
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 1,
                ),
                icon: const Icon(Icons.description_rounded, size: 22),
                label: const Text(
                  '📝 تقرير كتابي (رسالة نصية مفصلة عبر واتساب)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                ),
                onPressed: () => Navigator.pop(bCtx, 'text'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(bCtx, null),
                child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        );
      },
    );

    if (formatChoice == null) return;

    final isVisual = (formatChoice == 'visual');
    await widget.database.setSetting('report_card_send_as_visual', isVisual ? 'true' : 'false');

    for (final s in _students) {
      final sId = s['id'] as String?;
      final st = s['attendance_status'] as String?;
      if (sId != null && st != null) {
        await widget.database.processAttendanceSessionBilling(
          group: widget.group,
          studentId: sId,
          studentName: s['full_name'] as String? ?? '',
          date: widget.date,
          status: st,
          sessionScale: _sessionType,
        );
      }
    }
    await _saveSessionLogData();
    await _saveReportScheduleSettings();
    widget.onAttendanceUpdated?.call();

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GroupSessionReportSheet(
        group: widget.group,
        database: widget.database,
        date: widget.date,
      ),
    );

    final sentStatus = await widget.database.getSetting(
      'report_sent_${widget.group.id}_${widget.date}',
      defaultValue: 'false',
    );
    if (sentStatus == 'true') {
      await widget.database.setSetting(
        'attendance_lock_${widget.group.id}_${widget.date}',
        'true',
      );
      await NotificationService.cancelUnsentReportReminder(widget.group.id);
      if (mounted) {
        setState(() {
          _isReportSent = true;
          _isSessionLocked = true;
        });

        // تأكيد نجاح الإرسال والاستلام المعتمد لولي الأمر
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            icon: const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 50),
            title: const Text('تم الإرسال وتأكيد التسليم بنجاح ✅', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            content: Text(
              isVisual
                  ? 'تم إرسال كروت التقارير المصورة بنجاح لجميع أولياء الأمور 🖼️📲\nوتم استلامها واعتماد الحصة وقفلها رسمياً.'
                  : 'تم إرسال التقارير الكتابية المفصلة بنجاح لجميع أولياء الأمور 📝📲\nوتم استلامها واعتماد الحصة وقفلها رسمياً.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            actions: [
              Center(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(c),
                  child: const Text('تم بنجاح ✓', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );

        if (mounted) {
          Navigator.pop(context);
        }
      }
    }
  }

  Future<void> _previewFirstStudentCard() async {
    final list = await widget.database.getGroupStudentsWithAttendance(
      groupId: widget.group.id,
      date: widget.date,
    );
    if (list.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد طلاب مسجلين في المجموعة لمعاينتهم')),
        );
      }
      return;
    }

    // Select the currently chosen student for preview or fallback to the first
    final s = list.firstWhere(
      (st) => st['id'] == _selectedPreviewStudentId,
      orElse: () => list.first,
    );
    final cName = await widget.database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل');
    final tName = await widget.database.getSetting('teacher_name', defaultValue: 'الأستاذ');

    final attStatus = s['attendance_status'] as String?;
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
                : (isAbsent ? 'غائب عن الحصة 🚨' : 'لم يُرصد ⏱️')));

    final effHwStatus = isAbsent
        ? 'لم يحضر للتسليم (غائب) 🚨'
        : (isExcused
            ? 'غياب بعذر ⚪'
            : (s['homework_status'] as String? ?? (isPresent ? 'تم التسليم ✅' : 'لم يسلم ❌')));

    final effRecitation = isAbsent
        ? 'لم يُسمّع (غائب) 🚨'
        : (isExcused ? 'غياب بعذر ⚪' : (s['recitation_rating'] as String?));

    final effRank = isPresent
        ? 'متميز ومنتظم 🌟'
        : (isLate
            ? 'تنبيه تأخير ⏰'
            : (isAbsent ? 'تنبيه غياب ومتابعة ⚠️' : 'متابعة دورية'));

    final effNotes = isAbsent
        ? 'نرجو من ولي الأمر متابعة سبب غياب الطالب والحرص على تعويض ما فاته من المقرر والتكليفات ⚠️'
        : (_notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : (_homeworkController.text.trim().isNotEmpty
                ? 'الواجب: ${_homeworkController.text.trim()}'
                : 'تمنياتنا بدوام التميز والتفوق 🌟'));

    final studentModel = StudentModel(
      id: s['id']?.toString() ?? '',
      fullName: s['full_name']?.toString() ?? 'طالب',
      stage: widget.group.stage.isNotEmpty ? widget.group.stage : (s['stage']?.toString() ?? ''),
      grade: widget.group.grade.isNotEmpty ? widget.group.grade : (s['grade']?.toString() ?? ''),
      studentPhone: s['student_phone']?.toString() ?? '',
      parentPhone: s['parent_phone']?.toString() ?? '',
      groupId: widget.group.id,
      paymentPlan: s['payment_plan']?.toString() ?? widget.group.billingType,
    );

    final realExamScores = await widget.database.getStudentExamScores(studentModel.id);
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
      centerName: cName,
      teacherName: tName,
      rankText: effRank,
      reportTitle: 'معاينة كارت تقرير الحصة الدراسية 📊',
      sessionDate: widget.date,
      attendanceStatusLabel: arabicStatus,
      homeworkStatusLabel: effHwStatus,
      recitationRatingLabel: effRecitation,
      lessonTitle: _topicController.text.trim().isNotEmpty ? _topicController.text.trim() : null,
      previousHomeworkReview: _prevHomeworkController.text.trim().isNotEmpty ? _prevHomeworkController.text.trim() : null,
      homeworkText: _homeworkController.text.trim().isNotEmpty ? _homeworkController.text.trim() : null,
      nextTopic: _nextTopicController.text.trim().isNotEmpty ? _nextTopicController.text.trim() : null,
      subAttendanceNote: isAbsent ? 'غائب عن الحصة' : 'حصة اليوم',
      database: widget.database,
    );
  }

  Future<void> _saveReportScheduleSettings() async {
    final map = {
      'enabled': _scheduleReportLater,
      'time':
          '${_scheduledReportTime.hour.toString().padLeft(2, '0')}:${_scheduledReportTime.minute.toString().padLeft(2, '0')}',
      'alert_enabled': _enableUnsentReportAlert,
      'alert_time':
          '${_unsentAlertTime.hour.toString().padLeft(2, '0')}:${_unsentAlertTime.minute.toString().padLeft(2, '0')}',
    };
    await widget.database.setSetting(
      'scheduled_report_${widget.group.id}_${widget.date}',
      jsonEncode(map),
    );

    if (_enableUnsentReportAlert && !_isReportSent) {
      final now = DateTime.now();
      var reminderDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        _unsentAlertTime.hour,
        _unsentAlertTime.minute,
      );
      if (reminderDateTime.isBefore(now)) {
        reminderDateTime = reminderDateTime.add(const Duration(days: 1));
      }
      await NotificationService.scheduleUnsentReportReminder(
        groupId: widget.group.id,
        groupName: widget.group.name,
        reminderTime: reminderDateTime,
        date: widget.date,
      );

      final sessionDate = DateTime.tryParse(widget.date) ?? DateTime.now();
      if (widget.database.isLastSessionOfMonthForGroup(widget.group, sessionDate)) {
        final monthKey =
            '${sessionDate.year}-${sessionDate.month.toString().padLeft(2, '0')}';
        final hourStr =
            await widget.database.getSetting('monthly_report_hour', defaultValue: '21');
        final minStr =
            await widget.database.getSetting('monthly_report_minute', defaultValue: '0');
        final mHour = int.tryParse(hourStr) ?? 21;
        final mMin = int.tryParse(minStr) ?? 0;
        var monthlyReminderTime = DateTime(
          sessionDate.year,
          sessionDate.month,
          sessionDate.day,
          mHour,
          mMin,
        );
        if (monthlyReminderTime.isBefore(DateTime.now())) {
          monthlyReminderTime = DateTime.now().add(const Duration(minutes: 10));
        }
        await NotificationService.scheduleMonthlyReportReminder(
          groupId: widget.group.id,
          groupName: widget.group.name,
          reminderTime: monthlyReminderTime,
          monthKey: monthKey,
        );
      }
    } else {
      await NotificationService.cancelUnsentReportReminder(widget.group.id);
      await NotificationService.cancelMonthlyReportReminder(widget.group.id);
    }
  }

  void _nextPage() {
    if (_currentStep < 4) {
      HapticFeedback.selectionClick();
      _saveSessionLogData();
      _pageController.animateToPage(
        _currentStep + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishWizard();
    }
  }

  void _prevPage() {
    if (_currentStep > 0) {
      HapticFeedback.selectionClick();
      _pageController.animateToPage(
        _currentStep - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finishWizard() async {
    HapticFeedback.heavyImpact();
    for (final s in _students) {
      final sId = s['id'] as String?;
      final st = s['attendance_status'] as String?;
      if (sId != null && st != null) {
        await widget.database.processAttendanceSessionBilling(
          group: widget.group,
          studentId: sId,
          studentName: s['full_name'] as String? ?? '',
          date: widget.date,
          status: st,
          sessionScale: _sessionType,
        );
      }
    }
    await _saveSessionLogData();
    await _saveReportScheduleSettings();
    widget.onAttendanceUpdated?.call();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم حفظ واعتماد كافة بيانات الحصة والجدولة بنجاح! ✓'),
        backgroundColor: Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _finishWizardWithSchedule() async {
    HapticFeedback.heavyImpact();
    // Explicitly activate schedule report
    _scheduleReportLater = true;
    for (final s in _students) {
      final sId = s['id'] as String?;
      final st = s['attendance_status'] as String?;
      if (sId != null && st != null) {
        await widget.database.processAttendanceSessionBilling(
          group: widget.group,
          studentId: sId,
          studentName: s['full_name'] as String? ?? '',
          date: widget.date,
          status: st,
          sessionScale: _sessionType,
        );
      }
    }
    await _saveSessionLogData();
    await _saveReportScheduleSettings();
    widget.onAttendanceUpdated?.call();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم حفظ بيانات الحصة وتأكيد جدولة التقرير في تمام الساعة ${_scheduledReportTime.format(context)} بنجاح! ⏱️✓',
        ),
        backgroundColor: const Color(0xFF6366F1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context);
  }

  // Dialog to bind the group to a curriculum if not bound
  Future<void> _showBindCurriculumDialog() async {
    final curricula = await widget.database.getDetailedCurriculaList();
    if (!mounted) return;

    if (curricula.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.amber, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'لا توجد مناهج مسجلة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Text(
            'لم يتم إدخال مناهج دراسية في التطبيق بعد.\nيمكنك كتابة اسم الدرس والواجب يدوياً في الخانات بكل سهولة، أو إضافة منهج من شاشة المناهج الدراسية.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('سأكتب الدرس يدوياً ✓'),
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'ربط المجموعة بمنهج دراسي 🔗📚',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(bCtx),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'اختر المنهج الدراسي المناسب لمجموعة "${widget.group.name}" لتمكين الاختيار التلقائي للدروس:',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: curricula.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final item = curricula[i];
                  final cName = (item['name'] as String? ?? 'منهج عام').trim();
                  final totalLessons = item['total_lessons'] ?? 0;
                  final grade = item['grade'] as String? ?? '';
                  final isCurrent = _boundCurriculumName == cName;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                      child: const Icon(Icons.menu_book_rounded, color: Color(0xFF00F2FE), size: 20),
                    ),
                    title: Text(
                      cName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'الدروس: $totalLessons • الصف: $grade',
                      style: const TextStyle(fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981))
                        : const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                    onTap: () async {
                      Navigator.pop(bCtx);
                      await widget.database.bindGroupToCurriculum(
                        groupId: widget.group.id,
                        groupName: widget.group.name,
                        grade: widget.group.grade,
                        curriculumName: cName,
                      );
                      final newLessons = await widget.database.getCurriculumLessons(
                        curriculumName: cName,
                        grade: widget.group.grade,
                      );
                      setState(() {
                        _boundCurriculumName = cName;
                        _groupLessons = newLessons;
                      });
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم ربط المجموعة بنجاح بمنهج "$cName" 📚✓'),
                          backgroundColor: const Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0F1D) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تحضير: ${widget.group.name}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'التاريخ: ${widget.date} • ${widget.group.schedule}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (_isReportSent)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDC2626)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 14, color: Color(0xFFDC2626)),
                  SizedBox(width: 4),
                  Text(
                    'مغلق نهائياً 🔒',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
            )
          else if (_isSessionLocked)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade700),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 14, color: Colors.amber),
                  SizedBox(width: 4),
                  Text(
                    'معتمد ومقفل',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            tooltip: 'مسح الباركود',
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF00F2FE)),
            onPressed: () {
              if (_isReportSent) {
                _showReportSentImmutableNotice();
                return;
              }
              if (_isSessionLocked) {
                _showLockedNotice();
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScannerScreen(database: widget.database),
                ),
              ).then((_) => _loadData());
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'خيارات إضافية',
            icon: const Icon(Icons.more_vert_rounded),
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt_rounded, color: Color(0xFFEF4444), size: 18),
                    SizedBox(width: 8),
                    Text('تصفير الكشف', style: TextStyle(color: Color(0xFFEF4444))),
                  ],
                ),
              ),
            ],
            onSelected: (val) {
              if (val == 'reset') _resetAllAttendance();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: _buildStepperProgressHeader(isDark),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : PageView(
              controller: _pageController,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (idx) {
                setState(() => _currentStep = idx);
                _saveSessionLogData();
              },
              children: [
                _buildStep0Attendance(isDark),
                _buildStep1ReviewAndRecitation(isDark),
                _buildStep2TodayLessonExplanation(isDark),
                _buildStep3NextLessonPrep(isDark),
                _buildStep4LivePreviewAndSchedule(isDark),
              ],
            ),
      bottomNavigationBar: _buildBottomNavigationDock(isDark),
    );
  }

  // --- Step Indicator & Progress Header (5 Steps) ---
  Widget _buildStepperProgressHeader(bool isDark) {
    final steps = [
      (title: 'كشف الحضور', icon: Icons.fact_check_rounded),
      (title: 'المراجعة والتسميع', icon: Icons.rate_review_rounded),
      (title: _isTodayExamMode ? 'اختبار الحصة' : 'شرح درس اليوم', icon: _isTodayExamMode ? Icons.quiz_rounded : Icons.menu_book_rounded),
      (title: _isNextExamMode ? 'اختبار قادم' : 'تجهيز الدرس القادم', icon: _isNextExamMode ? Icons.assignment_late_rounded : Icons.upcoming_rounded),
      (title: 'المعاينة والإرسال', icon: Icons.send_rounded),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: List.generate(steps.length, (idx) {
              final isCurrent = _currentStep == idx;
              // Checkmark ONLY appears when step data is completed!
              final isCompleted = _isStepCompleted(idx);
              final color = isCurrent
                  ? const Color(0xFF00F2FE)
                  : (isCompleted
                      ? const Color(0xFF10B981)
                      : (isDark ? Colors.grey.shade700 : Colors.grey.shade400));

              return Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _saveSessionLogData();
                    _pageController.animateToPage(
                      idx,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCompleted
                                    ? const Color(0xFF10B981)
                                    : (isCurrent
                                        ? const Color(0xFF00F2FE)
                                        : Colors.transparent),
                                border: Border.all(
                                  color: color,
                                  width: isCurrent ? 2 : 1.5,
                                ),
                              ),
                              child: Center(
                                child: isCompleted
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 15,
                                        color: Colors.white,
                                      )
                                    : Text(
                                        '${idx + 1}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: isCurrent
                                              ? Colors.black
                                              : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            steps[idx].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isCurrent
                                  ? FontWeight.w900
                                  : (isCompleted ? FontWeight.bold : FontWeight.normal),
                              color: isCurrent
                                  ? (isDark ? const Color(0xFF00F2FE) : const Color(0xFF0284C7))
                                  : (isCompleted
                                      ? const Color(0xFF10B981)
                                      : (isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 5,
              backgroundColor: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00F2FE)),
              minHeight: 3.5,
            ),
          ),
        ],
      ),
    );
  }

  // --- Bottom Persistent Navigation Dock ---
  Widget _buildBottomNavigationDock(bool isDark) {
    // 1. If report is already sent: locked permanently
    if (_isReportSent) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_rounded, color: Color(0xFF10B981), size: 20),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'تم إرسال التقرير واعتماد الحصة نهائياً 🔒 (ممنوع التعديل)',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 2. Final Step (Step 4: إنهاء التحضير والمعاينة والإرسال)
    if (_currentStep == 4) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'حفظ وإرسال تقرير 🚀',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                      ),
                      onPressed: _openSendReportFlow,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'حفظ وجدولة تقرير ⏱️',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                      ),
                      onPressed: _finishWizardWithSchedule,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF374151) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  onPressed: _prevPage,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 0.8,
                          ),
                        ),
                        child: Center(
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 17,
                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'السابق (الرجوع لتجهيز الدرس القادم)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Steps 0, 1, 2, 3: Standard wizard navigation
    // RTL Arabic Navigation: Child 0 is on the RIGHT (السابق), Child 1 is on the LEFT (التالي)
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF374151) : const Color(0xFFCBD5E1),
                      width: 1.2,
                    ),
                    backgroundColor: isDark
                        ? const Color(0xFF1E293B).withValues(alpha: 0.6)
                        : const Color(0xFFF8FAFC),
                  ),
                  onPressed: _prevPage,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 0.8,
                          ),
                        ),
                        child: Center(
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'السابق',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF00F2FE),
                      Color(0xFF0284C7),
                    ],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _nextPage,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'التالي (${_getStepTitle(_currentStep + 1)})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: Color(0xFF04101E),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFF04101E).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF04101E).withValues(alpha: 0.25),
                                width: 0.8,
                              ),
                            ),
                            child: const Center(
                              child: Directionality(
                                textDirection: TextDirection.ltr,
                                child: Icon(
                                  Icons.chevron_left_rounded,
                                  size: 20,
                                  color: Color(0xFF04101E),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStepTitle(int step) {
    switch (step) {
      case 0:
        return 'كشف الحضور';
      case 1:
        return 'المراجعة والتسميع';
      case 2:
        return _isTodayExamMode ? 'اختبار الحصة' : 'شرح درس اليوم';
      case 3:
        return _isNextExamMode ? 'اختبار قادم' : 'تجهيز الدرس القادم';
      case 4:
        return 'المعاينة والإرسال';
      default:
        return '';
    }
  }

  // =========================================================================
  // STEP 0: 👥 المرحلة الأولى: التحضير للطلبة (كشف الحضور)
  // =========================================================================
  Widget _buildStep0Attendance(bool isDark) {
    final presentCount = _students.where((s) => s['attendance_status'] == 'present').length;
    final lateCount = _students.where((s) => s['attendance_status'] == 'late').length;
    final excusedCount = _students.where((s) => s['attendance_status'] == 'excused').length;
    final absentCount = _students.where((s) => s['attendance_status'] == 'absent').length;
    final unmarkedCount = _students.where((s) => s['attendance_status'] == null || (s['attendance_status'] as String).isEmpty).length;

    final filteredStudents = _searchQuery.trim().isEmpty
        ? _students
        : _students.where((s) {
            final name = (s['full_name'] as String? ?? '').toLowerCase();
            final code = (s['student_code'] as String? ?? '').toLowerCase();
            final q = _searchQuery.trim().toLowerCase();
            return name.contains(q) || code.contains(q);
          }).toList();

    return Column(
      children: [
        // Cancellation Warning if any (Teacher or Student)
        if (_isSessionCancelledByTeacher)
          Builder(
            builder: (ctx) {
              final isTeacher = _teacherCancellation?['cancelled_by'] == 'teacher';
              final color = isTeacher ? Colors.red : Colors.purple;
              final reasonText = _teacherCancellation?['reason'] ?? '';
              final prefix = isTeacher
                  ? 'تنبيه: تم إلغاء هذه الحصة من جهة المعلم 🚫'
                  : 'تنبيه: تم إلغاء هذه الحصة باعتذار من الطلاب ⚠️';
              return Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.shade400),
                ),
                child: Row(
                  children: [
                    Icon(
                      isTeacher ? Icons.cancel_outlined : Icons.person_off_rounded,
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$prefix ${reasonText.isNotEmpty ? "($reasonText)" : ""}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

        // Report Sent & Final Lock Banner (Immutable, no changes allowed even by fingerprint)
        if (_isReportSent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDC2626)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_rounded, color: Color(0xFFDC2626), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم إرسال تقرير الحصة لأولياء الأمور 🔒 الحصة مقفلة نهائياً ومحمية من أي تعديل (ولا حتى بالبصمة)',
                    style: TextStyle(
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Session Scale & Type Picker Strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildSessionTypeCard(
                  type: 'regular',
                  title: 'حصة عادية (1x)',
                  icon: Icons.school_outlined,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildSessionTypeCard(
                  type: 'double',
                  title: 'حصة دوبل (2x)',
                  icon: Icons.bolt_rounded,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildSessionTypeCard(
                  type: 'makeup',
                  title: 'تعويضية 📅',
                  icon: Icons.event_repeat_rounded,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),

        // Quick Actions & Live Stats Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB),
              ),
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.flash_on_rounded, size: 20),
                  label: const Text(
                    'تحضير الكل حاضر ⚡',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                  onPressed: () => _markAll('present'),
                ),
              ),
              const SizedBox(height: 8),

              // Statistics Strip - wrapped with SingleChildScrollView to prevent overflow
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        'الطلاب: ${_students.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'حاضر: $presentCount 🟢',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'متأخر: $lateCount 🟡',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'معذور: $excusedCount 🔵',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'غائب: $absentCount 🔴',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'لم يحدد: $unmarkedCount ⚪',
                        style: const TextStyle(
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Search Box
              TextFormField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'بحث عن اسم الطالب أو الكود...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Students Attendance Cards List
        Expanded(
          child: filteredStudents.isEmpty
              ? const Center(child: Text('لا يوجد طلاب مطابقين للبحث.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filteredStudents.length,
                  itemBuilder: (ctx, index) {
                    final student = filteredStudents[index];
                    return _buildStudentAttendanceCard(student, isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStudentAttendanceCard(Map<String, dynamic> student, bool isDark) {
    final sId = student['id'] as String;
    final sName = student['full_name'] as String? ?? 'بدون اسم';
    final sCode = student['student_code'] as String? ?? '';
    final status = student['attendance_status'] as String?;
    final isStudentActive = (student['is_active'] == null) || ((student['is_active'] as num).toInt() != 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141E33) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'present'
              ? const Color(0xFF10B981).withValues(alpha: 0.6)
              : (status == 'absent'
                  ? Colors.redAccent.withValues(alpha: 0.6)
                  : (isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0))),
          width: (status == 'present' || status == 'absent') ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                child: Text(
                  sName.isNotEmpty ? sName[0] : 'ط',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF00F2FE),
                  ),
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
                            sName,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isStudentActive)
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber.shade700, width: 0.6),
                            ),
                            child: const Text(
                              'متوقف مؤقتاً ⏸️',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (sCode.isNotEmpty)
                      Text(
                        'كود: $sCode',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
              ),
              if (status == 'present')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'حاضر ✓',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 5 Touch Friendly Attendance Buttons
          Row(
            children: [
              Expanded(
                child: _buildAttendanceOptionButton(
                  label: 'حاضر 🟢',
                  isSelected: status == 'present',
                  activeColor: const Color(0xFF10B981),
                  onTap: () => _updateStudentStatus(sId, 'present'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildAttendanceOptionButton(
                  label: 'متأخر 🟡',
                  isSelected: status == 'late',
                  activeColor: Colors.amber.shade700,
                  onTap: () => _updateStudentStatus(sId, 'late'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildAttendanceOptionButton(
                  label: 'معذور 🔵',
                  isSelected: status == 'excused',
                  activeColor: Colors.blue.shade600,
                  onTap: () => _updateStudentStatus(sId, 'excused'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildAttendanceOptionButton(
                  label: 'غائب 🔴',
                  isSelected: status == 'absent',
                  activeColor: Colors.redAccent,
                  onTap: () => _updateStudentStatus(sId, 'absent'),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildAttendanceOptionButton(
                  label: 'لم يحدد ⚪',
                  isSelected: status == null || status.isEmpty,
                  activeColor: Colors.blueGrey,
                  onTap: () => _updateStudentStatus(sId, null),
                ),
              ),
            ],
          ),
          if (status == 'absent') ...[
            const SizedBox(height: 8),
            Builder(
              builder: (ctx) {
                final isAlreadySent = _sentAbsenceStudentIds.contains(sId);
                return SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isAlreadySent
                          ? (isDark ? Colors.grey.shade800 : Colors.grey.shade200)
                          : Colors.red.withValues(alpha: 0.1),
                      foregroundColor: isAlreadySent
                          ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
                          : Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isAlreadySent ? Colors.grey.shade400 : Colors.red.shade300,
                          width: 0.8,
                        ),
                      ),
                    ),
                    icon: Icon(
                      isAlreadySent ? Icons.check_circle_rounded : Icons.send_rounded,
                      size: 14,
                      color: isAlreadySent ? Colors.grey : const Color(0xFF25D366),
                    ),
                    label: Text(
                      isAlreadySent
                          ? 'تم إرسال إشعار الغياب مسبقاً اليوم 🔒 (مغلق)'
                          : 'إرسال إشعار الغياب لولي الأمر عبر واتساب 📲',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isAlreadySent ? Colors.grey : null,
                      ),
                    ),
                    onPressed: isAlreadySent ? null : () => _sendSingleStudentAbsenceAlert(student),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttendanceOptionButton({
    required String label,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : activeColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : activeColor.withValues(alpha: 0.35),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                color: isSelected ? Colors.white : activeColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionTypeCard({
    required String type,
    required String title,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _sessionType == type;
    return InkWell(
      onTap: () async {
        if (_isReportSent) {
          _showReportSentImmutableNotice();
          return;
        }
        if (_isSessionLocked) {
          _showLockedNotice();
          return;
        }
        HapticFeedback.selectionClick();
        setState(() => _sessionType = type);
        await widget.database.setSetting(
          'session_type_${widget.group.id}_${widget.date}',
          type,
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00F2FE).withValues(alpha: isDark ? 0.2 : 0.12)
              : (isDark ? const Color(0xFF141E33) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00F2FE)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? const Color(0xFF00F2FE) : Colors.grey,
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                  color: isSelected
                      ? (isDark ? Colors.white : const Color(0xFF0284C7))
                      : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // STEP 1: 📖 المرحلة الثانية: المراجعة على الحصة السابقة والتسميع والواجب
  // =========================================================================
  Widget _buildStep1ReviewAndRecitation(bool isDark) {
    final presentStudents = _students
        .where((s) =>
            s['attendance_status'] == 'present' ||
            s['attendance_status'] == 'late')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      children: [
        // 1. Curriculum Multi-select Lesson Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141E33) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.rate_review_rounded, color: Color(0xFF00F2FE), size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'الدروس المسَمّعة اليوم 📚',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_groupLessons.isNotEmpty)
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                            foregroundColor: isDark ? const Color(0xFF00F2FE) : const Color(0xFF0284C7),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                          label: const Text(
                            'اختر من المنهج',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _showMultiLessonPickerForReview,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // If group is not bound to curriculum, show helpful prompt
              if (_groupLessons.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: isDark ? 0.15 : 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.shade400.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'المجموعة غير مرتبطة بمنهج دراسي للاختيار التلقائي',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'اربط المجموعة بمنهج لاختيار دروس التسميع بنقرة واحدة، أو اكتب الدرس يدوياً أدناه.',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                            side: BorderSide(color: Colors.amber.shade600),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          icon: const Icon(Icons.link_rounded, size: 16),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '🔗 ربط المجموعة بمنهج دراسي للاختيار',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          onPressed: _showBindCurriculumDialog,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const Text(
                  'حدد الدرس أو أكثر من درس تم مراجعته وسماعه اليوم لتضمينه في التقرير:',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
                const SizedBox(height: 8),
              ],

              // Selected Lessons Chips Wrap
              if (_selectedPrevLessons.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedPrevLessons.map((lessonTitle) {
                    return Chip(
                      avatar: const Icon(Icons.bookmark_added_rounded, size: 14, color: Color(0xFF00F2FE)),
                      label: Text(
                        lessonTitle,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                      onDeleted: () {
                        setState(() {
                          _selectedPrevLessons.remove(lessonTitle);
                          _prevLessonController.text = _selectedPrevLessons.join('، ');
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
              ],

              // Custom/Free-text field for reviewed lessons
              TextFormField(
                controller: _prevLessonController,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: 'اكتب أو اختر الدروس التي تم تسميعها...',
                  prefixIcon: const Icon(Icons.menu_book_rounded, color: Color(0xFF00F2FE)),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
                onChanged: (val) {
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),

              // Previous Homework Review Note
              const Text(
                'ملاحظات تصحيح الواجب السابق:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _prevHomeworkController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'مثال: تم تصحيح حل صفحة 22 وتمت مناقشة أسئلة التفكير العليا...',
                  prefixIcon: const Icon(Icons.assignment_turned_in_rounded, color: Colors.amber),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Quick Batch Homework Bar
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'الكل حل الواجب بالكامل ✅',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  for (final s in presentStudents) {
                    _updateStudentEvaluation(
                      studentId: s['id'] as String,
                      homeworkStatus: 'done',
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6366F1),
                  side: const BorderSide(color: Color(0xFF6366F1)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.star_rounded, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'الكل تسميع ممتاز 🌟',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  for (final s in presentStudents) {
                    _updateStudentEvaluation(
                      studentId: s['id'] as String,
                      recitationRating: 'ممتاز 🌟',
                    );
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Student Recitation & Homework Cards
        if (presentStudents.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey),
                  const SizedBox(height: 10),
                  const Text(
                    'لا يوجد طلاب حاضرون حتى الآن!',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'يرجى رصد الحضور أولاً في الخطوة الأولى.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _prevPage,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('الرجوع لكشف الحضور'),
                  ),
                ],
              ),
            ),
          )
        else
          ...presentStudents.map(
            (student) => _buildStudentEvaluationCard(student, isDark),
          ),
      ],
    );
  }

  Future<void> _showMultiLessonPickerForReview() async {
    if (_groupLessons.isEmpty) {
      _showBindCurriculumDialog();
      return;
    }
    final progressMap = await widget.database.getGroupLessonProgressMap(widget.group.id);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AttendanceLessonPickerSheet(
        groupLessons: _groupLessons,
        group: widget.group,
        date: widget.date,
        initialProgressMap: progressMap,
        initialTopic: _prevLessonController.text,
        database: widget.database,
        isPreviousLessonMode: true,
        onConfirmed: (selectedLessons) {
          if (selectedLessons.isEmpty) return;
          setState(() {
            _selectedPrevLessons = selectedLessons
                .map((l) => l.lessonTitle.isNotEmpty ? l.lessonTitle : l.title)
                .toList();
            _prevLessonController.text = _selectedPrevLessons.join('، ');
          });
        },
      ),
    );
  }

  Widget _buildStudentEvaluationCard(Map<String, dynamic> student, bool isDark) {
    final sId = student['id'] as String;
    final sName = student['full_name'] as String? ?? 'طالب';
    final hwStatus = student['homework_status'] as String? ?? 'done';
    final recitation = student['recitation_rating'] as String? ?? 'ممتاز 🌟';
    final currentNote = student['notes'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141E33) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                child: Text(
                  sName.isNotEmpty ? sName[0] : 'ط',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sName,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 1. Homework Status (أداء الواجب السابق)
          const Text(
            'أداء واجب الحصة السابقة: 📖',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSmallSelectionChip(
                  label: 'كامل ✅',
                  isSelected: hwStatus == 'done',
                  activeColor: const Color(0xFF10B981),
                  onTap: () => _updateStudentEvaluation(studentId: sId, homeworkStatus: 'done'),
                ),
                const SizedBox(width: 12),
                _buildSmallSelectionChip(
                  label: 'ناقص ⚠️',
                  isSelected: hwStatus == 'incomplete',
                  activeColor: Colors.amber.shade700,
                  onTap: () => _updateStudentEvaluation(studentId: sId, homeworkStatus: 'incomplete'),
                ),
                const SizedBox(width: 12),
                _buildSmallSelectionChip(
                  label: 'لم يحل ❌',
                  isSelected: hwStatus == 'not_done',
                  activeColor: Colors.redAccent,
                  onTap: () => _updateStudentEvaluation(studentId: sId, homeworkStatus: 'not_done'),
                ),
                const SizedBox(width: 12),
                _buildSmallSelectionChip(
                  label: 'معذور ⚪',
                  isSelected: hwStatus == 'excused',
                  activeColor: Colors.blue.shade600,
                  onTap: () => _updateStudentEvaluation(studentId: sId, homeworkStatus: 'excused'),
                ),
                const SizedBox(width: 12),
                _buildSmallSelectionChip(
                  label: 'لا يوجد 🚫',
                  isSelected: hwStatus == 'none',
                  activeColor: Colors.grey.shade600,
                  onTap: () => _updateStudentEvaluation(studentId: sId, homeworkStatus: 'none'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Recitation Rating (التقييم والتسميع)
          const Text(
            'تقييم التسميع والمشاركة: ⭐',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ['ممتاز 🌟', 'جيد جداً 👍', 'جيد 👌', 'مقبول ⚠️', 'لم يحفظ ❌', 'لا يوجد ⚪'].map((rating) {
              final isSel = recitation == rating;
              return InkWell(
                onTap: () => _updateStudentEvaluation(studentId: sId, recitationRating: rating),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSel
                        ? const Color(0xFF6366F1)
                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSel ? const Color(0xFF6366F1) : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      width: isSel ? 1.5 : 1.0,
                    ),
                  ),
                  child: Text(
                    rating,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSel ? FontWeight.w900 : FontWeight.bold,
                      color: isSel ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.black87),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // 3. Quick Note Chip Selection
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickNotes.map((note) {
                final isSel = currentNote == note;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ActionChip(
                    label: Text(
                      note,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    backgroundColor: isSel ? const Color(0xFF00F2FE).withValues(alpha: 0.2) : null,
                    side: isSel ? const BorderSide(color: Color(0xFF00F2FE)) : null,
                    onPressed: () => _updateStudentEvaluation(studentId: sId, notes: note),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallSelectionChip({
    required String label,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : activeColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : activeColor.withValues(alpha: 0.35),
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                color: isSelected ? Colors.white : activeColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // STEP 2: 📚 المرحلة الثالثة: شرح درس اليوم أو اختبار الحصة
  // =========================================================================
  Widget _buildStep2TodayLessonExplanation(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      children: [
        // Mode Switcher for Today's Session: شرح درس جديد vs اختبار / كويز الحصة
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _isTodayExamMode = false);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: !_isTodayExamMode
                          ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: !_isTodayExamMode
                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '📖 شرح درس جديد',
                        style: TextStyle(
                          fontWeight: !_isTodayExamMode ? FontWeight.w900 : FontWeight.bold,
                          fontSize: 12.5,
                          color: !_isTodayExamMode
                              ? (isDark ? const Color(0xFF00F2FE) : const Color(0xFF0284C7))
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _isTodayExamMode = true);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _isTodayExamMode
                          ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _isTodayExamMode
                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '🎯 اختبار / كويز الحصة',
                        style: TextStyle(
                          fontWeight: _isTodayExamMode ? FontWeight.w900 : FontWeight.bold,
                          fontSize: 12.5,
                          color: _isTodayExamMode
                              ? const Color(0xFFEF4444)
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Show Exam Mode Content if active, otherwise Standard Lesson Explanation
        if (_isTodayExamMode)
          ..._buildTodayExamModeContent(isDark)
        else ...[
          // Standard Lesson Explanation: Intro Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [const Color(0xFFE0F2FE), Colors.white],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFBAE6FD),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.menu_book_rounded, color: Color(0xFF0284C7), size: 26),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المرحلة 3: شرح درس اليوم والتكليفات الإضافية 📚',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'اختر موضوع درس اليوم من المنهج (متاح شرح جزئي للدروس السابقة)، وحدد التكليفات الإضافية.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Today's Lesson Topic Card with Curriculum Selection
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141E33) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_groupLessons.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.menu_book_rounded, color: Color(0xFF00F2FE), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'المنهج: ${_boundCurriculumName ?? "مربوط"} (${_groupLessons.length} درس)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _showBindCurriculumDialog,
                        child: const Text('تغيير 🔄', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00F2FE).withValues(alpha: isDark ? 0.2 : 0.15),
                        foregroundColor: isDark ? const Color(0xFF00F2FE) : const Color(0xFF0284C7),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: const Color(0xFF00F2FE).withValues(alpha: 0.5),
                          ),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.library_books_rounded, size: 20),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _topicController.text.isNotEmpty
                              ? 'تغيير درس اليوم من المنهج 📚'
                              : 'اختيار درس اليوم من المنهج (${_groupLessons.length} درس) 📚',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                        ),
                      ),
                      onPressed: _showTodayLessonPicker,
                    ),
                  ),
                ] else ...[
                  // Unbound Group Alert Banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: isDark ? 0.15 : 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amber.shade400.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'المجموعة غير مرتبطة بمنهج دراسي للاختيار التلقائي',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                  color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'اربط المجموعة بمنهج لاختيار الدروس بضغطة زر، أو اكتب اسم الدرس يدوياً أدناه.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                              side: BorderSide(color: Colors.amber.shade600),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                            ),
                            icon: const Icon(Icons.link_rounded, size: 18),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '🔗 ربط المجموعة بمنهج دراسي للاختيار',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                            ),
                            onPressed: _showBindCurriculumDialog,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // Manual Input / Editing Field
                Row(
                  children: [
                    const Text(
                      'موضوع درس اليوم المشروح: *',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                    const Spacer(),
                    if (_topicController.text.isNotEmpty)
                      InkWell(
                        onTap: () => setState(() => _topicController.clear()),
                        child: const Text('مسح ✕', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _topicController,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'اختر من المنهج أعلاه أو اكتب اسم الدرس (أو جزء منه للشرح الجزئي)...',
                    prefixIcon: const Icon(Icons.bookmark_added_rounded, color: Color(0xFF00F2FE)),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Objectives & Explanation Content Covered
          const Text(
            'أهداف وعناصر الشرح المغطاة في الحصة:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _contentController,
            maxLines: 3,
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'شرح الأفكار الرئيسية، القوانين، حل تدريبات عملية، وتطبيق الأمثلة...',
              filled: true,
              fillColor: isDark ? const Color(0xFF141E33) : Colors.white,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Additional Assignments for Today's Lesson
          Row(
            children: const [
              Icon(Icons.assignment_turned_in_rounded, size: 18, color: Color(0xFF00F2FE)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'التكليفات الإضافية لدرس اليوم 📝⚡:',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'اضغط للإضافة للواجب',
                style: TextStyle(fontSize: 10.5, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 4 Main Additional Assignments requested: حل أسئلة الكتاب، حل أسئلة المذكرة، حل كويز أونلاين، حفظ الدرس
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildAssignmentTemplateChip(
                title: 'حل أسئلة الكتاب 📚',
                icon: '📚',
                text: 'حل أسئلة وتدريبات الكتاب المدرسي على درس اليوم',
                color: const Color(0xFF0284C7),
                isDark: isDark,
              ),
              _buildAssignmentTemplateChip(
                title: 'حل أسئلة المذكرة 📝',
                icon: '📝',
                text: 'حل أسئلة وتطبيقات المذكرة وشيت التدريبات لدرس اليوم',
                color: const Color(0xFF8B5CF6),
                isDark: isDark,
              ),
              _buildAssignmentTemplateChip(
                title: 'حل كويز أونلاين 🌐',
                icon: '🌐',
                text: 'أداء الكويز الإلكتروني أونلاين عبر الرابط لدرس اليوم',
                color: const Color(0xFF06B6D4),
                isDark: isDark,
              ),
              _buildAssignmentTemplateChip(
                title: 'حفظ الدرس 🧠',
                icon: '🧠',
                text: 'مذاكرة وحفظ المفاهيم والنقاط الرئيسية المشروحة اليوم جيداً',
                color: const Color(0xFF10B981),
                isDark: isDark,
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  // --- Today Exam Mode Content Builder (التاب 3 في وضع الامتحان) ---
  List<Widget> _buildTodayExamModeContent(bool isDark) {
    final presentStudents = _students
        .where((s) =>
            s['attendance_status'] == 'present' ||
            s['attendance_status'] == 'late')
        .toList();

    return [
      // Notice Banner
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.assignment_turned_in_rounded, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'تم تفعيل نمط الاختبار للحصة الحالية • تم إلغاء حقول الشرح العادية لتوفير المساحة والتركيز على الاختبار ورصد درجات الطلاب 🎯',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.redAccent),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // Exam Scope & Title Card
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141E33) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.quiz_rounded, color: Colors.redAccent, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'الدروس المشمولة في الاختبار:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                if (_groupLessons.isNotEmpty)
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: isDark ? 0.2 : 0.1),
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    ),
                    icon: const Icon(Icons.menu_book_rounded, size: 15),
                    label: const Text('اختيار من المنهج 📚', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _showTodayExamLessonsPicker,
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Selected Exam Lessons Chips
            if (_todayExamLessons.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _todayExamLessons.map((lTitle) {
                  return Chip(
                    avatar: const Icon(Icons.check_circle_rounded, size: 14, color: Colors.redAccent),
                    label: Text(lTitle, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                    onDeleted: () {
                      setState(() => _todayExamLessons.remove(lTitle));
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ] else ...[
              Text(
                _groupLessons.isNotEmpty
                    ? 'اضغط على "اختيار من المنهج" لتحديد الدروس التي يغطيها الاختبار، أو اكتب عنوان الاختبار أدناه.'
                    : 'اكتب عنوان الاختبار والدرجة الكلية أدناه:',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 10),
            ],

            // Exam Title & Max Score Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('عنوان / موضوع الاختبار: *', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _todayExamTitleController,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: 'مثال: اختبار شامل على الوحدة الأولى 📝',
                          prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.all(10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (val) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الدرجة الكلية:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _todayExamMaxScoreController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFEF4444)),
                        decoration: InputDecoration(
                          hintText: '20',
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.all(10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (val) => setState(() {}),
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

      // Grading Mode Switcher Card (رصد الدرجات حالا vs جدولة الرصد لاحقاً)
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141E33) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _todayExamGradingMode == 'now'
                ? const Color(0xFF10B981)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⏱️ طريقة رصد درجات الطلاب:',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _todayExamGradingMode = 'now');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _todayExamGradingMode == 'now'
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _todayExamGradingMode == 'now'
                              ? const Color(0xFF10B981)
                              : Colors.grey.shade400,
                          width: _todayExamGradingMode == 'now' ? 1.8 : 1.0,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '⚡ رصد الدرجات الآن في الحصة',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: _todayExamGradingMode == 'now' ? FontWeight.w900 : FontWeight.bold,
                            color: _todayExamGradingMode == 'now' ? const Color(0xFF10B981) : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _todayExamGradingMode = 'scheduled');
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _todayExamGradingMode == 'scheduled'
                            ? const Color(0xFF6366F1).withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _todayExamGradingMode == 'scheduled'
                              ? const Color(0xFF6366F1)
                              : Colors.grey.shade400,
                          width: _todayExamGradingMode == 'scheduled' ? 1.8 : 1.0,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '📅 جدولة رصد الدرجات لاحقاً',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: _todayExamGradingMode == 'scheduled' ? FontWeight.w900 : FontWeight.bold,
                            color: _todayExamGradingMode == 'scheduled' ? const Color(0xFF6366F1) : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (_todayExamGradingMode == 'scheduled') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: Color(0xFF6366F1), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'سيتم إرسال تقرير اليوم لولي الأمر موضحاً: أدى الطالب الاختبار وجارٍ تصحيح أوراق الإجابة وسيتم إشعاركم بالدرجة فور الانتهاء ⏳ مع تذكير ذكي لتذكيرك بالرصد.',
                        style: TextStyle(fontSize: 11.5, height: 1.4, color: Color(0xFF6366F1), fontWeight: FontWeight.bold),
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

      // Rapid Score Input Cards (When grading mode == 'now')
      if (_todayExamGradingMode == 'now') ...[
        Row(
          children: [
            const Icon(Icons.grade_rounded, size: 18, color: Color(0xFF10B981)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'رصد درجات طلاب الحصة (${presentStudents.length} طالب حاضر) 📝:',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...presentStudents.map((s) => _buildStudentExamScoreCard(s, isDark)),
      ],
    ];
  }

  // --- Student Exam Score Card Builder ---
  Widget _buildStudentExamScoreCard(Map<String, dynamic> student, bool isDark) {
    final sId = student['id'] as String? ?? '';
    final sName = student['full_name'] as String? ?? 'طالب';
    final sCode = student['student_code'] as String? ?? '';
    final maxScore = double.tryParse(_todayExamMaxScoreController.text.trim()) ?? 20.0;
    final currentScore = _todayExamScores[sId];
    final currentNote = _todayExamNotes[sId] ?? '';

    int percent = 0;
    String gradeLabel = '';
    Color badgeColor = Colors.grey;

    if (currentScore != null && maxScore > 0) {
      percent = ((currentScore / maxScore) * 100).round();
      if (percent >= 85) {
        gradeLabel = 'ممتاز 🌟';
        badgeColor = const Color(0xFF10B981);
      } else if (percent >= 75) {
        gradeLabel = 'جيد جداً 👍';
        badgeColor = const Color(0xFF0284C7);
      } else if (percent >= 65) {
        gradeLabel = 'جيد 👌';
        badgeColor = Colors.amber.shade700;
      } else if (percent >= 50) {
        gradeLabel = 'مقبول ⚠️';
        badgeColor = Colors.orange.shade800;
      } else {
        gradeLabel = 'يحتاج دعم 🚨';
        badgeColor = Colors.redAccent;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141E33) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: currentScore != null
              ? badgeColor.withValues(alpha: 0.5)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
          width: currentScore != null ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                    if (sCode.isNotEmpty)
                      Text('كود: $sCode', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              // Score Input Box
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 58,
                    height: 36,
                    child: TextFormField(
                      initialValue: currentScore != null
                          ? currentScore.toStringAsFixed(currentScore.truncateToDouble() == currentScore ? 0 : 1)
                          : '',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                      decoration: InputDecoration(
                        hintText: '0',
                        contentPadding: EdgeInsets.zero,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
                        ),
                      ),
                      onChanged: (val) {
                        final parsed = double.tryParse(val.trim());
                        setState(() {
                          if (parsed != null) {
                            _todayExamScores[sId] = parsed;
                          } else {
                            _todayExamScores.remove(sId);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('/ ${maxScore.toStringAsFixed(maxScore.truncateToDouble() == maxScore ? 0 : 1)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  if (currentScore != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: badgeColor, width: 0.8),
                      ),
                      child: Text(
                        '$percent% • $gradeLabel',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Quick Feedback Chips for Exam
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              'إجابة نموذجية ⭐',
              'أخطاء حسابية 🔢',
              'أخطاء قوانين 📐',
              'لم يكمل الوقت ⏳',
              'غياب عن الامتحان ❌',
            ].map((chipText) {
              final isSel = currentNote == chipText;
              return InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (isSel) {
                      _todayExamNotes.remove(sId);
                    } else {
                      _todayExamNotes[sId] = chipText;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSel
                        ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel ? const Color(0xFF6366F1) : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      width: isSel ? 1.4 : 0.8,
                    ),
                  ),
                  child: Text(
                    chipText,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      color: isSel ? const Color(0xFF6366F1) : (isDark ? Colors.grey.shade300 : Colors.black87),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _showTodayLessonPicker() async {
    if (_groupLessons.isEmpty) {
      _showBindCurriculumDialog();
      return;
    }
    final progressMap = await widget.database.getGroupLessonProgressMap(widget.group.id);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AttendanceLessonPickerSheet(
        groupLessons: _groupLessons,
        group: widget.group,
        date: widget.date,
        initialProgressMap: progressMap,
        initialTopic: _topicController.text,
        database: widget.database,
        isPreviousLessonMode: false,
        singleSelect: true,
        onConfirmed: (selectedLessons) async {
          if (selectedLessons.isEmpty) return;
          final l = selectedLessons.first;
          final title = l.lessonTitle.isNotEmpty ? l.lessonTitle : l.title;
          setState(() {
            _topicController.text = title;
            if (l.objectives.isNotEmpty) {
              _contentController.text = l.objectives;
            }
          });
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
      ),
    );
  }

  Future<void> _showTodayExamLessonsPicker() async {
    if (_groupLessons.isEmpty) {
      _showBindCurriculumDialog();
      return;
    }
    final progressMap = await widget.database.getGroupLessonProgressMap(widget.group.id);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AttendanceLessonPickerSheet(
        groupLessons: _groupLessons,
        group: widget.group,
        date: widget.date,
        initialProgressMap: progressMap,
        initialTopic: _todayExamLessons.isNotEmpty ? _todayExamLessons.first : '',
        database: widget.database,
        isPreviousLessonMode: true,
        singleSelect: false,
        onConfirmed: (selectedLessons) {
          if (selectedLessons.isEmpty) return;
          setState(() {
            _todayExamLessons = selectedLessons
                .map((l) => l.lessonTitle.isNotEmpty ? l.lessonTitle : l.title)
                .toList();
            if (_todayExamTitleController.text.isEmpty ||
                _todayExamTitleController.text == 'اختبار تقييمي شامل 📝') {
              _todayExamTitleController.text = 'اختبار على: ${_todayExamLessons.join(' و ')}';
            }
          });
        },
      ),
    );
  }

  // =========================================================================
  // STEP 3: 🚀 المرحلة الرابعة: تجهيز الدرس القادم أو تجهيز اختبار قادم
  // =========================================================================
  Widget _buildStep3NextLessonPrep(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      children: [
        // Mode Switcher for Next Session: شرح درس قادم vs الحصة القادمة اختبار / كويز
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _isNextExamMode = false);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: !_isNextExamMode
                          ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: !_isNextExamMode
                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '📖 شرح درس قادم',
                        style: TextStyle(
                          fontWeight: !_isNextExamMode ? FontWeight.w900 : FontWeight.bold,
                          fontSize: 12.5,
                          color: !_isNextExamMode
                              ? (isDark ? const Color(0xFF818CF8) : const Color(0xFF4338CA))
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _isNextExamMode = true);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _isNextExamMode
                          ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _isNextExamMode
                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '🎯 الحصة القادمة اختبار / كويز',
                        style: TextStyle(
                          fontWeight: _isNextExamMode ? FontWeight.w900 : FontWeight.bold,
                          fontSize: 12.5,
                          color: _isNextExamMode
                              ? const Color(0xFF7C3AED)
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Show Next Exam Mode Content if active, otherwise Standard Next Lesson Prep
        if (_isNextExamMode)
          ..._buildNextExamModeContent(isDark)
        else ...[
          // Standard Next Lesson Intro Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [const Color(0xFFEFF6FF), Colors.white],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFBFDBFE),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF818CF8).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.upcoming_rounded, color: Color(0xFF818CF8), size: 26),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المرحلة 4: تجهيز الدرس القادم والتكليفات 🚀',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'اختر الدرس الذي سيتم شرحه الحصة القادمة من المنهج، وحدد التكليفات ونماذج التحضير أو الاستعداد لاختبار.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Next Lesson Topic Card with Curriculum Integration
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141E33) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_groupLessons.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.menu_book_rounded, color: Color(0xFF00F2FE), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'المنهج: ${_boundCurriculumName ?? "مربوط"} (${_groupLessons.length} درس)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _showBindCurriculumDialog,
                        child: const Text('تغيير 🔄', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF818CF8).withValues(alpha: isDark ? 0.2 : 0.15),
                        foregroundColor: isDark ? const Color(0xFF818CF8) : const Color(0xFF4338CA),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: const Color(0xFF818CF8).withValues(alpha: 0.5),
                          ),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.library_books_rounded, size: 20),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _nextTopicController.text.isNotEmpty
                              ? 'تغيير الدرس القادم من المنهج 📚'
                              : 'اختيار الدرس القادم من المنهج (${_groupLessons.length} درس) 📚',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                        ),
                      ),
                      onPressed: _showNextLessonPicker,
                    ),
                  ),
                ] else ...[
                  // Unbound Group Alert Banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: isDark ? 0.15 : 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amber.shade400.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'المجموعة غير مرتبطة بمنهج دراسي للاختيار التلقائي',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                  color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'اربط المجموعة بمنهج لاختيار الدروس القادمة بنقرة زر، أو اكتب الدرس يدوياً أدناه.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                              side: BorderSide(color: Colors.amber.shade600),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                            ),
                            icon: const Icon(Icons.link_rounded, size: 18),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '🔗 ربط المجموعة بمنهج دراسي للاختيار',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                            ),
                            onPressed: _showBindCurriculumDialog,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // Manual Input / Editing Field
                Row(
                  children: [
                    const Text(
                      'موضوع الدرس القادم (يدوي / مخصص): *',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                    const Spacer(),
                    if (_nextTopicController.text.isNotEmpty)
                      InkWell(
                        onTap: () => setState(() => _nextTopicController.clear()),
                        child: const Text('مسح ✕', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nextTopicController,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'اختر من المنهج أعلاه أو اكتب اسم الدرس القادم...',
                    prefixIcon: const Icon(Icons.bookmark_add_rounded, color: Color(0xFF818CF8)),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Next Lesson Assignment Templates (تحضير الدرس القادم + الاستعداد لاختبار)
          Row(
            children: const [
              Icon(Icons.dashboard_customize_rounded, size: 18, color: Colors.amber),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'نماذج التكليفات الإضافية للدرس القادم ⚡:',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'اضغط للإضافة للواجب',
                style: TextStyle(fontSize: 10.5, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Primary Templates for Next Lesson: تحضير الدرس القادم & الاستعداد لاختبار
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildAssignmentTemplateChip(
                title: 'تحضير الدرس القادم 📖',
                icon: '📖',
                text: 'تحضير وقراءة الدرس القادم واستخراج النقاط الأساسية والمصطلحات',
                color: const Color(0xFF0284C7),
                isDark: isDark,
              ),
              _buildAssignmentTemplateChip(
                title: 'الاستعداد لاختبار 🎯',
                icon: '🎯',
                text: 'الاستعداد التام لاختبار تقييمي شامل في بداية الحصة القادمة',
                color: const Color(0xFFEF4444),
                isDark: isDark,
              ),
              ..._homeworkTemplates.map((tpl) {
                return _buildAssignmentTemplateChip(
                  title: tpl.title,
                  icon: tpl.icon,
                  text: tpl.text,
                  color: tpl.color,
                  isDark: isDark,
                );
              }),
            ],
          ),
          const SizedBox(height: 16),

          // Homework Field
          const Text(
            'الواجب والتكليف المنزلي المطلوب للحصة القادمة: * 📝',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _homeworkController,
            maxLines: 4,
            style: const TextStyle(fontSize: 14, height: 1.4),
            decoration: InputDecoration(
              hintText: 'اختر من النماذج أعلاه أو اكتب نص الواجب المكلف به الطالب بالتفصيل...',
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 50),
                child: Icon(Icons.assignment_rounded, color: Colors.amber),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF141E33) : Colors.white,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
              ),
            ),
            onChanged: (val) => setState(() {}),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  // --- Next Exam Mode Content Builder (التاب 4 في وضع تجهيز اختبار قادم) ---
  List<Widget> _buildNextExamModeContent(bool isDark) {
    return [
      // Notice Banner
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF7C3AED).withValues(alpha: isDark ? 0.18 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.assignment_late_rounded, color: Color(0xFF7C3AED), size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'تجهيز اختبار للحصة القادمة 🎯 سيتم إدراج تنبيه رسمي عريض في تقرير ولي الأمر للاستعداد والمذاكرة التامة.',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF7C3AED)),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // Next Exam Scope & Title Card
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141E33) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.school_rounded, color: Color(0xFF7C3AED), size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'الدروس التي سيشملها اختبار الحصة القادمة:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                if (_groupLessons.isNotEmpty)
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED).withValues(alpha: isDark ? 0.2 : 0.1),
                      foregroundColor: const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    ),
                    icon: const Icon(Icons.menu_book_rounded, size: 15),
                    label: const Text('اختيار من المنهج 📚', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: _showNextExamLessonsPicker,
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Next Exam Selected Lessons Chips
            if (_nextExamLessons.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _nextExamLessons.map((lTitle) {
                  return Chip(
                    avatar: const Icon(Icons.checklist_rtl_rounded, size: 14, color: Color(0xFF7C3AED)),
                    label: Text(lTitle, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    deleteIcon: const Icon(Icons.close_rounded, size: 16),
                    onDeleted: () {
                      setState(() => _nextExamLessons.remove(lTitle));
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ] else ...[
              Text(
                _groupLessons.isNotEmpty
                    ? 'اضغط على "اختيار من المنهج" لتحديد الدروس التي سيشملها الاختبار القادم، أو اكتب موضوع الاختبار أدناه.'
                    : 'اكتب موضوع الاختبار القادم أدناه:',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 10),
            ],

            const Text('موضوع / عنوان الاختبار القادم: *', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            TextFormField(
              controller: _nextExamTitleController,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'مثال: كويز تقييمي على الجزء المشروح 🎯',
                prefixIcon: const Icon(Icons.quiz_rounded, color: Color(0xFF7C3AED)),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (val) => setState(() {}),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // Next Exam Preparation Action Chips (بنقرة زر تضيف للتكليفات والواجب)
      Row(
        children: const [
          Icon(Icons.bolt_rounded, size: 18, color: Color(0xFF7C3AED)),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'نماذج التكليفات للاستعداد للاختبار ⚡:',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'اضغط للإضافة للواجب',
            style: TextStyle(fontSize: 10.5, color: Colors.grey),
          ),
        ],
      ),
      const SizedBox(height: 8),

      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _buildAssignmentTemplateChip(
            title: 'الاستعداد لاختبار 🎯',
            icon: '🎯',
            text: 'الاستعداد التام لاختبار شامل ومذاكرة الدروس المحددة بدقة 🎯',
            color: const Color(0xFFEF4444),
            isDark: isDark,
          ),
          _buildAssignmentTemplateChip(
            title: 'مراجعة القوانين 📌',
            icon: '📌',
            text: 'مراجعة وحفظ كافة القوانين والتعريفات الهامة للدروس المقررة 📌',
            color: const Color(0xFFF59E0B),
            isDark: isDark,
          ),
          _buildAssignmentTemplateChip(
            title: 'حل نماذج امتحانات 📑',
            icon: '📑',
            text: 'حل نماذج امتحانات وتدريبات سابقة استعداداً للاختبار القادم 📑',
            color: const Color(0xFF06B6D4),
            isDark: isDark,
          ),
          _buildAssignmentTemplateChip(
            title: 'إحضار الأدوات ✍️',
            icon: '✍️',
            text: 'إحضار الآلة الحاسبة والأدوات الهندسية وكشكول المادة كاملة للاختبار 📐',
            color: const Color(0xFF10B981),
            isDark: isDark,
          ),
        ],
      ),
      const SizedBox(height: 14),

      // Homework / Requirements Field
      const Text(
        'الواجب والتكليفات المطلوبة للاستعداد للاختبار: * 📝',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
      ),
      const SizedBox(height: 6),
      TextFormField(
        controller: _homeworkController,
        maxLines: 4,
        style: const TextStyle(fontSize: 14, height: 1.4),
        decoration: InputDecoration(
          hintText: 'اكتب نص التكليف ومصادر المذاكرة المطلوبة للاختبار بالتفصيل...',
          prefixIcon: const Padding(
            padding: EdgeInsets.only(bottom: 50),
            child: Icon(Icons.assignment_late_rounded, color: Color(0xFF7C3AED)),
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF141E33) : Colors.white,
          contentPadding: const EdgeInsets.all(14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            ),
          ),
        ),
        onChanged: (val) => setState(() {}),
      ),
      const SizedBox(height: 12),

      // WhatsApp Warning Preview Card
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFDCF8C6).withValues(alpha: isDark ? 0.15 : 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.mark_chat_read_rounded, size: 16, color: Color(0xFF075E54)),
                SizedBox(width: 6),
                Text('كيف سيظهر لولي الأمر في تقرير اليوم؟ 📱', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF075E54))),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '4️⃣ تكليفات الحصة القادمة:\n'
              '• ⚠️ تنبيه هام: الحصة القادمة اختبار تقييمي 🎯\n'
              '• المطلوب الاستعداد لـ: ${_nextExamTitleController.text.trim()}${_nextExamLessons.isNotEmpty ? " (على: ${_nextExamLessons.join(' و ')})" : ""}\n'
              '• المطلوب: ${_homeworkController.text.trim().isNotEmpty ? _homeworkController.text.trim() : "مذاكرة الدروس المحددة وحل التدريبات"}',
              style: const TextStyle(fontSize: 11, height: 1.4, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _showNextExamLessonsPicker() async {
    if (_groupLessons.isEmpty) {
      _showBindCurriculumDialog();
      return;
    }
    final progressMap = await widget.database.getGroupLessonProgressMap(widget.group.id);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AttendanceLessonPickerSheet(
        groupLessons: _groupLessons,
        group: widget.group,
        date: widget.date,
        initialProgressMap: progressMap,
        initialTopic: _nextExamLessons.isNotEmpty ? _nextExamLessons.first : '',
        database: widget.database,
        isPreviousLessonMode: true,
        singleSelect: false,
        onConfirmed: (selectedLessons) {
          if (selectedLessons.isEmpty) return;
          setState(() {
            _nextExamLessons = selectedLessons
                .map((l) => l.lessonTitle.isNotEmpty ? l.lessonTitle : l.title)
                .toList();
            if (_nextExamTitleController.text.isEmpty ||
                _nextExamTitleController.text == 'كويز تقييمي على الجزء المشروح 🎯') {
              _nextExamTitleController.text = 'اختبار شامل على: ${_nextExamLessons.join(' و ')}';
            }
            final alertText = '🎯 الاستعداد لاختبار الحصة القادمة على:\n• ${_nextExamLessons.join('\n• ')}';
            if (!_homeworkController.text.contains('الاستعداد لاختبار')) {
              if (_homeworkController.text.trim().isEmpty) {
                _homeworkController.text = alertText;
              } else {
                _homeworkController.text = '${_homeworkController.text.trim()}\n\n$alertText';
              }
            }
          });
        },
      ),
    );
  }

  Future<void> _showNextLessonPicker() async {
    if (_groupLessons.isEmpty) {
      _showBindCurriculumDialog();
      return;
    }
    final progressMap = await widget.database.getGroupLessonProgressMap(widget.group.id);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AttendanceLessonPickerSheet(
        groupLessons: _groupLessons,
        group: widget.group,
        date: widget.date,
        initialProgressMap: progressMap,
        initialTopic: _nextTopicController.text,
        database: widget.database,
        isPreviousLessonMode: false,
        singleSelect: true,
        onConfirmed: (selectedLessons) {
          if (selectedLessons.isEmpty) return;
          final l = selectedLessons.first;
          final title = l.lessonTitle.isNotEmpty ? l.lessonTitle : l.title;
          setState(() {
            _nextTopicController.text = title;
          });
        },
      ),
    );
  }

  Widget _buildAssignmentTemplateChip({
    required String title,
    required String icon,
    required String text,
    required Color color,
    required bool isDark,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (_homeworkController.text.trim().isEmpty) {
            _homeworkController.text = text;
          } else if (!_homeworkController.text.contains(text)) {
            _homeworkController.text = '${_homeworkController.text.trim()}\n• $text';
          }
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت إضافة: "$title" للتكليفات بنجاح 📝'),
            backgroundColor: color,
            duration: const Duration(milliseconds: 1400),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : color,
              ),
            ),
            const SizedBox(width: 5),
            Icon(Icons.add_circle_outline_rounded, size: 15, color: color),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // STEP 4: 📊 المرحلة الخامسة: إرسال التقرير ومعاينته وجدولة إرساله
  // =========================================================================
  Widget _buildStep4LivePreviewAndSchedule(bool isDark) {
    final presentCount = _students.where((s) => s['attendance_status'] == 'present').length;
    final lateCount = _students.where((s) => s['attendance_status'] == 'late').length;
    final absentCount = _students.where((s) => s['attendance_status'] == 'absent').length;

    // Student for preview
    final previewStudent = _students.firstWhere(
      (s) => s['id'] == _selectedPreviewStudentId,
      orElse: () => _students.isNotEmpty ? _students.first : <String, dynamic>{},
    );

    final previewMessage = _buildPreviewReportText(previewStudent);

    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      children: [
        // 1. Session Quick Summary Cards
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF00F2FE).withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'ملخص الحصة: ${widget.group.name}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _sessionType == 'double'
                          ? 'حصة دوبل (2x)'
                          : (_sessionType == 'makeup' ? 'تعويضية' : 'حصة عادية (1x)'),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00F2FE),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildSummaryMiniStat('إجمالي الطلاب', '${_students.length}', Colors.white)),
                  Expanded(child: _buildSummaryMiniStat('حاضر', '$presentCount', const Color(0xFF10B981))),
                  Expanded(child: _buildSummaryMiniStat('متأخر', '$lateCount', Colors.amber)),
                  Expanded(child: _buildSummaryMiniStat('غائب', '$absentCount', Colors.redAccent)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. LIVE INTERACTIVE REPORT PREVIEW (معاينة التقرير التفاعلية الحية - اختيارية قابلة للفتح والغلق)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141E33) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF25D366).withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF25D366).withValues(alpha: isDark ? 0.15 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.remove_red_eye_rounded, color: Color(0xFF25D366), size: 22),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'معاينة التقرير لولي الأمر 👁️📱',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: _showReportPreview ? Colors.grey : const Color(0xFF25D366),
                      backgroundColor: (_showReportPreview ? Colors.grey : const Color(0xFF25D366)).withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: Icon(
                      _showReportPreview ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _showReportPreview ? 'إغلاق المعاينة ✕' : 'فتح المعاينة 👁️',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: () {
                      setState(() => _showReportPreview = !_showReportPreview);
                    },
                  ),
                  if (_showReportPreview) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'نسخ نص التقرير',
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: previewMessage));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ نص التقرير إلى الحافظة 📋'),
                            backgroundColor: Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
              if (_showReportPreview) ...[
                const SizedBox(height: 10),
                // Student Selector for Preview
                if (_students.isNotEmpty) ...[
                  Row(
                    children: [
                      const Text('معاينة لطالب:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedPreviewStudentId,
                              isExpanded: true,
                              items: _students.map((st) {
                                return DropdownMenuItem<String>(
                                  value: st['id'] as String,
                                  child: Text(
                                    st['full_name'] as String? ?? 'طالب',
                                    style: const TextStyle(fontSize: 12.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() => _selectedPreviewStudentId = val);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // WhatsApp Preview Chat Bubble
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0D1B1E)
                        : const Color(0xFFDCF8C6).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF25D366).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    previewMessage,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      fontFamily: 'monospace',
                      color: isDark ? Colors.grey.shade200 : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 16),

        // 3. WHATSAPP INSTANT DISPATCH BUTTON
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.send_rounded, color: Color(0xFF25D366), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'إرسال تقرير الحصة واتساب الآن 📲',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: Color(0xFF25D366),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'إرسال التقرير فوراً لجميع أولياء الأمور بنقرة واحدة (شاملاً الحضور، الواجب، التسميع، والدرس القادم).',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00F2FE),
                    foregroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 22),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'إرسال كروت التقارير المصورة إلكترونياً 🖼️⚡',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                    ),
                  ),
                  onPressed: _openSendReportFlow,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00F2FE),
                    side: const BorderSide(color: Color(0xFF00F2FE), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.remove_red_eye_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'معاينة كارت التقرير الفاخر للطلاب 👁️✨',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                  ),
                  onPressed: _previewFirstStudentCard,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 4. SCHEDULING & UNSENT REPORT ALARM
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141E33) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Switch: Schedule Report Later
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: Color(0xFF6366F1), size: 22),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'جدولة إرسال التقرير خلال اليوم ⏱️📅',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'حدّد وقتًا مخصصًا لإرسال التقرير لاحقًا بدلاً من إرساله فورًا الآن.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                value: _scheduleReportLater,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  setState(() => _scheduleReportLater = val);
                },
              ),

              if (_scheduleReportLater) ...[
                const SizedBox(height: 10),
                const Text('اختر موعد إرسال التقرير:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    _buildTimePresetChip('الساعة 06:00 م 🌆', const TimeOfDay(hour: 18, minute: 0)),
                    _buildTimePresetChip('الساعة 08:00 م 🌙', const TimeOfDay(hour: 20, minute: 0)),
                    _buildTimePresetChip('الساعة 09:30 م 🌃', const TimeOfDay(hour: 21, minute: 30)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'الوقت المجدول المحدد:',
                        style: TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.access_time_rounded, size: 16),
                      label: Text(_formatTimeOfDay(_scheduledReportTime)),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _scheduledReportTime,
                        );
                        if (picked != null) {
                          setState(() => _scheduledReportTime = picked);
                        }
                      },
                    ),
                  ],
                ),
                const Divider(height: 24),
              ],

              // Switch: Unsent Report Alert & Alarm
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Row(
                  children: [
                    Icon(Icons.notification_important_rounded, color: Colors.amber, size: 22),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تنبيه وإشعار: في تقرير لم يُرسل لولي الأمر 🔔🚨',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'يطلق التطبيق إشعاراً رناناً لتذكيرك إذا انقضى الوقت ولم تكن قد أرسلت التقرير بعد.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                value: _enableUnsentReportAlert,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  setState(() => _enableUnsentReportAlert = val);
                },
              ),

              if (_enableUnsentReportAlert) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'موعد إطلاق التنبيه الذكي:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber.shade700,
                        side: BorderSide(color: Colors.amber.shade400),
                      ),
                      icon: const Icon(Icons.alarm_on_rounded, size: 16),
                      label: Text(_formatTimeOfDay(_unsentAlertTime)),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _unsentAlertTime,
                        );
                        if (picked != null) {
                          setState(() => _unsentAlertTime = picked);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.volume_up_rounded, size: 16),
                  label: const Text('تجربة التنبيه والإشعار الآن 🔔', style: TextStyle(fontSize: 11.5)),
                  onPressed: () async {
                    HapticFeedback.heavyImpact();
                    await NotificationService.showNotification(
                      id: 88888,
                      title: '🚨 تنبيه: تقرير حصة لم يُرسل لولي الأمر!',
                      body: 'تذكير: لم تقم بإرسال تقرير حصة "${widget.group.name}" لأولياء الأمور حتى الآن 📲',
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم إطلاق إشعار وتنبيه التجربة بنجاح! 🔔'),
                        backgroundColor: Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 5. LOCK & BIOMETRIC APPROVAL BANNER
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _isSessionLocked
                ? Colors.amber.shade900.withValues(alpha: 0.12)
                : const Color(0xFF10B981).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isSessionLocked ? Colors.amber.shade700 : const Color(0xFF10B981),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isSessionLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: _isSessionLocked ? Colors.amber.shade800 : const Color(0xFF10B981),
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isReportSent
                          ? 'تم إرسال التقرير واعتماد الحصة نهائياً 🔒'
                          : (_isSessionLocked
                              ? 'كشف الحضور معتمد ومقفل 🔒'
                              : 'كشف الحضور جاهز للاعتماد والقفل 🔓'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: _isReportSent
                            ? const Color(0xFFDC2626)
                            : (_isSessionLocked ? Colors.amber.shade900 : const Color(0xFF10B981)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isReportSent
                          ? 'الحصة مقفلة نهائياً ومحمية من أي تعديل (ولا حتى بالبصمة).'
                          : (_isSessionLocked
                              ? 'الكشف محمي ببصمة الإصبع لمنع أي تعديل عشوائي.'
                              : 'اضغط لاعتماد الحصة رسمياً وقفلها بالبصمة الحيوية.'),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: _isReportSent
                          ? const Color(0xFFDC2626).withValues(alpha: 0.15)
                          : (_isSessionLocked ? Colors.amber.shade100 : const Color(0xFF10B981)),
                      foregroundColor: _isReportSent
                          ? const Color(0xFFDC2626)
                          : (_isSessionLocked ? Colors.amber.shade900 : Colors.white),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: _isReportSent
                        ? _showReportSentImmutableNotice
                        : (_isSessionLocked ? _unlockSession : _lockSession),
                    child: Text(
                      _isReportSent
                          ? 'ممنوع التعديل 🔒'
                          : (_isSessionLocked ? 'فك القفل' : 'اعتماد وقفل 🔒'),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _buildPreviewReportText(Map<String, dynamic> student) {
    final sId = student['id'] as String? ?? '';
    final sName = student['full_name'] as String? ?? 'الطالب';
    final attStatus = student['attendance_status'] as String?;
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
                : (isAbsent ? 'غائب عن الحصة 🚨' : 'لم يُرصد حضوره ⏱️')));

    final rawHw = student['homework_status'] as String?;
    final hwStatus = isAbsent
        ? 'لم يحضر للتسليم (غائب عن الحصة) 🚨'
        : (isExcused
            ? 'غياب بعذر مسبق ⚪'
            : (rawHw == 'done'
                ? 'كامل ومتقن ✅'
                : (rawHw == 'incomplete'
                    ? 'ناقص ⚠️'
                    : (rawHw == 'not_done'
                        ? 'لم يحل ❌'
                        : (rawHw == 'none'
                            ? 'لا يوجد واجب ⚪'
                            : (isPresent ? 'كامل ومتقن ✅' : 'لم يحدد'))))));

    final rawRecitation = student['recitation_rating'] as String?;
    final recitation = isAbsent
        ? 'لم يُسمّع (غائب عن الحصة) 🚨'
        : (isExcused
            ? 'غياب بعذر مسبق ⚪'
            : (rawRecitation ?? (isPresent ? 'متميز 🌟' : 'لم يحدد')));

    // Smart Content Formulation for Today's Lesson vs Exam
    String effectiveLesson;
    String effectiveLessonContent;

    if (_isTodayExamMode) {
      effectiveLesson = _todayExamTitleController.text.trim().isNotEmpty
          ? _todayExamTitleController.text.trim()
          : 'اختبار تقييمي شامل 📝';

      final examLessonsStr = _todayExamLessons.isNotEmpty
          ? 'الدروس المشمولة: ${_todayExamLessons.join(' و ')}'
          : '';

      if (_todayExamGradingMode == 'now') {
        final score = _todayExamScores[sId];
        final maxScore = double.tryParse(_todayExamMaxScoreController.text.trim()) ?? 20.0;
        final note = _todayExamNotes[sId];

        String scoreLine;
        if (score != null) {
          final pct = maxScore > 0 ? ((score / maxScore) * 100).round() : 0;
          final gradeLabel = pct >= 85
              ? 'ممتاز 🌟'
              : (pct >= 75
                  ? 'جيد جداً 👍'
                  : (pct >= 65
                      ? 'جيد 👌'
                      : (pct >= 50 ? 'مقبول ⚠️' : 'يحتاج دعم 🚨')));
          scoreLine = 'الدرجة: $score من $maxScore ($pct% - $gradeLabel)';
        } else {
          scoreLine = 'الدرجة: لم تُرصد بعد ⏱️';
        }

        effectiveLessonContent = '🎯 نتيجة اختبار الحصة اليوم:\n'
            '• $scoreLine\n'
            '${note != null && note.isNotEmpty ? "• تقييم الإجابة: $note\n" : ""}'
            '${examLessonsStr.isNotEmpty ? "• $examLessonsStr" : ""}';
      } else {
        effectiveLessonContent = '🎯 اختبار الحصة اليوم:\n'
            '• حالة الطالب: أدى الطالب الاختبار في الحصة بنجاح 🟢\n'
            '• النتيجة: جارٍ تصحيح أوراق الإجابة ورصد الدرجات وسيتم إشعاركم بها فور الانتهاء ⏳\n'
            '${examLessonsStr.isNotEmpty ? "• $examLessonsStr" : ""}';
      }
    } else {
      effectiveLesson = _nextTopicController.text.trim().isNotEmpty
          ? _nextTopicController.text.trim()
          : (_topicController.text.trim().isNotEmpty
              ? _topicController.text.trim()
              : 'مقرر الحصة اليومي');
      effectiveLessonContent = _contentController.text.trim();
    }

    // Smart Upcoming Exam Alert
    String? effectiveNextQuiz;
    if (_isNextExamMode) {
      final examLessonsStr = _nextExamLessons.isNotEmpty ? _nextExamLessons.join(' و ') : '';
      effectiveNextQuiz = _nextExamTitleController.text.trim().isNotEmpty
          ? '${_nextExamTitleController.text.trim()}${examLessonsStr.isNotEmpty ? " (على: $examLessonsStr)" : ""}'
          : (examLessonsStr.isNotEmpty ? 'اختبار على: $examLessonsStr' : 'اختبار الحصة القادمة 🎯');
    }

    final studentNotes = (student['notes'] as String?)?.trim();
    final effectiveNotes = isAbsent
        ? (studentNotes != null && studentNotes.isNotEmpty
            ? studentNotes
            : 'نرجو من ولي الأمر متابعة سبب غياب الطالب والحرص على تعويض ما فاته من المقرر والتكليفات ⚠️')
        : (studentNotes != null && studentNotes.isNotEmpty
            ? studentNotes
            : _notesController.text.trim());

    return WhatsAppService.sessionFollowUpMessage(
      centerName: _centerName,
      teacherName: _teacherName,
      studentName: sName,
      groupName: widget.group.name,
      date: widget.date,
      lessonTitle: effectiveLesson,
      lessonContent: effectiveLessonContent,
      homework: _homeworkController.text.trim(),
      notes: effectiveNotes,
      attendanceStatus: arabicStatus,
      recitationRating: recitation,
      homeworkStatus: hwStatus,
      nextQuiz: effectiveNextQuiz,
      previousHomeworkReview: _prevHomeworkController.text.trim(),
      previousLessonReview: _prevLessonController.text.trim(),
      customTemplate: _customTemplate.isNotEmpty ? _customTemplate : null,
    );
  }

  Widget _buildSummaryMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ),
      ],
    );
  }

  Widget _buildTimePresetChip(String label, TimeOfDay time) {
    final isSel = _scheduledReportTime.hour == time.hour && _scheduledReportTime.minute == time.minute;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      selected: isSel,
      onSelected: (val) {
        if (val) setState(() => _scheduledReportTime = time);
      },
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'ص' : 'م';
    return '$hour:$minute $period';
  }
}
