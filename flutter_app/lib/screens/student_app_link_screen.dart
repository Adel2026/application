import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/database/database_service.dart';
import '../core/whatsapp_service.dart';

/// نموذج بيانات الطالب للعرض في قائمة الربط والتفعيل
class StudentLinkItem {
  final String id;
  final String name;
  final String grade;
  final String groupName;
  final String pin;
  final String phone;
  final bool paid;
  final String quizScore;
  final String quizMax;
  final String hwStatus;

  StudentLinkItem({
    required this.id,
    required this.name,
    required this.grade,
    this.groupName = '',
    required this.pin,
    required this.phone,
    this.paid = true,
    this.quizScore = '20',
    this.quizMax = '20',
    this.hwStatus = 'مكتمل ✓',
  });
}

/// شاشة ربط تطبيق الطالب وولي الأمر والمعاينة الحية (Student App Link & Live Sync Screen)
class StudentAppLinkScreen extends StatefulWidget {
  final DatabaseService? database;

  const StudentAppLinkScreen({
    super.key,
    this.database,
  });

  @override
  State<StudentAppLinkScreen> createState() => _StudentAppLinkScreenState();
}

class _StudentAppLinkScreenState extends State<StudentAppLinkScreen> {
  // بيانات السنتر والمعلم الأساسية
  String centerName = 'سنتر القمة التعليمي';
  String teacherName = 'أستاذ المادة';
  String centerCode = 'QEMMA-2026';

  // خيارات التحكم فيما يظهر للطالب في تطبيقه (Feature Toggles)
  bool showLessons = true;
  bool showHomework = true;
  bool showGrades = true;
  bool showPayments = true;

  // بيانات الحصة الحالية للمعاينة الحية
  String currentLessonTitle = 'التكامل المحدد وتطبيقاته الهندسية';
  String coveredTopics =
      'شرح قواعد التكامل المحدد + حساب المساحات تحت المنحنى + حل 12 مسألة مستويات عليا.';
  String bookletPages = 'ملزمة الشرح ص 42 إلى ص 49';
  String nextHomework =
      'حل تمارين الواجب من ص 50 إلى ص 53 بالملزمة + المسائل المقالية رقم (4، 7، 11).';
  String nextQuiz = 'امتحان شامل 20 دقيقة على التفاضل والتكامل أول الحصة القادمة';

  // البحث والفلترة
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;

  // قائمة الطلاب الحقيقية
  List<StudentLinkItem> _students = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// تحميل البيانات والإعدادات وقائمة الطلاب
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    if (widget.database != null) {
      final db = widget.database!;
      final cName = await db.getSetting('center_name', defaultValue: 'سنتر القمة التعليمي');
      final tName = await db.getSetting('teacher_name', defaultValue: 'أستاذ المادة');
      final cCode = await db.getSetting('center_code', defaultValue: 'QEMMA-2026');

      final sLessons = await db.getSetting('student_app_show_lessons', defaultValue: 'true');
      final sHw = await db.getSetting('student_app_show_homework', defaultValue: 'true');
      final sGrades = await db.getSetting('student_app_show_grades', defaultValue: 'true');
      final sPay = await db.getSetting('student_app_show_payments', defaultValue: 'true');

      // جلب أحدث محتوى حصة مدخل
      try {
        final sqldb = await db.database;
        final recentLogs = await sqldb.rawQuery(
          'SELECT * FROM session_logs ORDER BY date DESC, id DESC LIMIT 1',
        );
        if (recentLogs.isNotEmpty) {
          final log = recentLogs.first;
          final title = log['lesson_title']?.toString();
          final content = log['lesson_content']?.toString();
          final hw = log['homework']?.toString();
          final quiz = log['next_quiz']?.toString();

          if (title != null && title.isNotEmpty) currentLessonTitle = title;
          if (content != null && content.isNotEmpty) coveredTopics = content;
          if (hw != null && hw.isNotEmpty) nextHomework = hw;
          if (quiz != null && quiz.isNotEmpty) nextQuiz = quiz;
        }
      } catch (_) {}

      // جلب الطلاب الحقيقيين والمجموعات
      try {
        final groups = await db.getGroups();
        final groupMap = {for (final g in groups) g.id: g.name};

        final rawStudents = await db.getStudents();
        final List<StudentLinkItem> loaded = [];

        for (final s in rawStudents) {
          final pPhone = s.parentPhone.replaceAll(RegExp(r'\D'), '');
          final sPhone = s.studentPhone.replaceAll(RegExp(r'\D'), '');
          final pin = pPhone.length >= 4
              ? pPhone.substring(pPhone.length - 4)
              : (sPhone.length >= 4 ? sPhone.substring(sPhone.length - 4) : '1234');

          final gName = (s.groupId != null && groupMap.containsKey(s.groupId))
              ? groupMap[s.groupId]!
              : (s.groupId ?? '');

          loaded.add(StudentLinkItem(
            id: s.id,
            name: s.fullName,
            grade: s.grade,
            groupName: gName,
            pin: pin,
            phone: s.parentPhone.isNotEmpty ? s.parentPhone : s.studentPhone,
            paid: s.outstandingAmount <= 0,
            quizScore: '19',
            quizMax: '20',
            hwStatus: 'مكتمل ✓',
          ));
        }

        if (mounted) {
          setState(() {
            centerName = cName;
            teacherName = tName;
            centerCode = cCode;
            showLessons = sLessons == 'true';
            showHomework = sHw == 'true';
            showGrades = sGrades == 'true';
            showPayments = sPay == 'true';
            if (loaded.isNotEmpty) _students = loaded;
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint('Error loading students: $e');
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }

    // جلب الإعدادات المحدثة من Firestore لضمان التزامن اللحظي
    _fetchCloudSettings();
  }

  Future<void> _fetchCloudSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('settings')
          .doc('student_app_visibility')
          .get();

      if (doc.exists && mounted) {
        final data = doc.data();
        if (data != null) {
          setState(() {
            if (data.containsKey('show_lessons')) showLessons = data['show_lessons'] == true;
            if (data.containsKey('show_homework')) showHomework = data['show_homework'] == true;
            if (data.containsKey('show_grades')) showGrades = data['show_grades'] == true;
            if (data.containsKey('show_payments')) showPayments = data['show_payments'] == true;
          });
        }
      }
    } catch (_) {}
  }

  /// حفظ إعدادات الرؤية محلياً وسحابياً فور تغيير أي سويتش
  Future<void> _updateVisibilitySetting({
    bool? lessons,
    bool? homework,
    bool? grades,
    bool? payments,
  }) async {
    HapticFeedback.lightImpact();
    setState(() {
      if (lessons != null) showLessons = lessons;
      if (homework != null) showHomework = homework;
      if (grades != null) showGrades = grades;
      if (payments != null) showPayments = payments;
    });

    if (widget.database != null) {
      if (lessons != null) await widget.database!.setSetting('student_app_show_lessons', '$lessons');
      if (homework != null) await widget.database!.setSetting('student_app_show_homework', '$homework');
      if (grades != null) await widget.database!.setSetting('student_app_show_grades', '$grades');
      if (payments != null) await widget.database!.setSetting('student_app_show_payments', '$payments');
    }

    try {
      await FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('settings')
          .doc('student_app_visibility')
          .set({
            'show_lessons': showLessons,
            'show_homework': showHomework,
            'show_grades': showGrades,
            'show_payments': showPayments,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث إعدادات تطبيق الطالب بنجاح ☁️⚡'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error syncing settings to cloud: $e');
    }
  }

  /// نسخ كود السنتر إلى الحافظة
  void _copyCenterCode() {
    Clipboard.setData(ClipboardData(text: centerCode));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'تم نسخ كود السنتر الموحد للمشاركة مع الطلاب ✓',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  /// تعديل كود السنتر الموحد
  void _showEditCenterCodeDialog() {
    final controller = TextEditingController(text: centerCode);
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.edit_rounded, color: Colors.teal),
              SizedBox(width: 8),
              Text('تعديل كود السنتر الموحد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'هذا الكود يكتبه جميع الطلاب عند تسجيل الدخول في تطبيقهم للارتباط بهذا السنتر:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                decoration: InputDecoration(
                  labelText: 'كود السنتر الموحد',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.pin_rounded, color: Colors.teal),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final newCode = controller.text.trim();
                if (newCode.isNotEmpty) {
                  setState(() => centerCode = newCode);
                  if (widget.database != null) {
                    await widget.database!.setSetting('center_code', newCode);
                  }
                  try {
                    await FirebaseFirestore.instance
                        .collection('academies')
                        .doc('default')
                        .set({'center_code': newCode}, SetOptions(merge: true));
                  } catch (_) {}
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('حفظ الكود'),
            ),
          ],
        ),
      ),
    );
  }

  /// عرض نافذة مشاركة بيانات دخول الطالب مع خيار نسخ أو إرسال واتساب مباشر
  void _showSharePinDialog(StudentLinkItem student) {
    final String shareMessage = '''مرحباً بك يا ${student.name} 🎓
بيانات تفعيل ودخول تطبيق الطالب الخاص بـ ($centerName):
━━━━━━━━━━━━━━━━━
🔹 كود السنتر: $centerCode
🔹 كود الطالب: ${student.id}
🔹 الرمز السري (PIN): ${student.pin}
━━━━━━━━━━━━━━━━━
نتمنى لك دوام التفوق والنجاح! 🌟''';

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.share_rounded, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              const Text('بيانات تفعيل الطالب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Text(
                  shareMessage.trim(),
                  style: const TextStyle(fontSize: 12.5, height: 1.5, color: Colors.black87),
                ),
              ),
              const SizedBox(height: 14),
              // زر الإرسال المباشر عبر واتساب
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text(
                  'إرسال فوري لولي الأمر عبر واتساب 📲',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  if (student.phone.trim().isNotEmpty) {
                    WhatsAppService.openWhatsApp(
                      phone: student.phone,
                      message: shareMessage,
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('عذراً، لا يوجد رقم هاتف مسجل لهذا الطالب')),
                    );
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal.shade800,
                side: BorderSide(color: Colors.teal.shade400),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shareMessage.trim()));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ رسالة التفعيل إلى الحافظة بنجاح ✓')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('نسخ الرسالة'),
            ),
          ],
        ),
      ),
    );
  }

  /// عرض المعاينة الحية لما يراه الطالب في تطبيقه (Live Student App Preview)
  void _openStudentLivePreview() {
    StudentLinkItem sampleStudent = _students.isNotEmpty
        ? _students.first
        : StudentLinkItem(
            id: '48210',
            name: 'أحمد محمود حسن',
            grade: 'تالتة ثانوي',
            pin: '4821',
            phone: '',
            paid: true,
            quizScore: '19',
            quizMax: '20',
            hwStatus: 'مكتمل ✓',
          );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // رأس المعاينة بنمط تطبيق الطالب الحديث
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade900, const Color(0xFF0F172A)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      border: const Border(
                        bottom: BorderSide(color: Color(0xFF1E293B)),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.phone_android_rounded, color: Color(0xFF00F2FE), size: 20),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'المعاينة الحية لتطبيق الطالب',
                                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('Live Simulator', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'أهلاً بك يا ${sampleStudent.name.split(' ').first} 👋 (كود: ${sampleStudent.id})',
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),

                  // شريط اختيار الطالب لمعاينة بياناته الحقيقية
                  if (_students.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                      child: Row(
                        children: [
                          const Icon(Icons.swap_horiz_rounded, color: Color(0xFF00F2FE), size: 16),
                          const SizedBox(width: 6),
                          const Text('معاينة كطالب آخر:', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _students.take(12).map((st) {
                                  final isSelected = st.id == sampleStudent.id;
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: ChoiceChip(
                                      label: Text(
                                        st.name.split(' ').take(2).join(' '),
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          color: isSelected ? Colors.black : Colors.white,
                                        ),
                                      ),
                                      selected: isSelected,
                                      selectedColor: const Color(0xFF00F2FE),
                                      backgroundColor: const Color(0xFF0F172A),
                                      visualDensity: VisualDensity.compact,
                                      onSelected: (val) {
                                        if (val) setModalState(() => sampleStudent = st);
                                      },
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // محتوى شاشة الطالب المحاكي
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // بطاقة حالة الاشتراك والمدفوعات
                        if (showPayments)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('مرتبط بـ: $centerName', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    const SizedBox(height: 2),
                                    Text(teacherName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: sampleStudent.paid
                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                        : const Color(0xFFEF4444).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: sampleStudent.paid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    ),
                                  ),
                                  child: Text(
                                    sampleStudent.paid ? 'الاشتراك ساري ✓' : 'مستحق السداد ⚠️',
                                    style: TextStyle(
                                      color: sampleStudent.paid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // ملخص ما تم دراسته بالحصة
                        if (showLessons)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'ما تم دراسته في الحصة 📖',
                                        style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  currentLessonTitle,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  coveredTopics,
                                  style: TextStyle(color: Colors.grey.shade300, fontSize: 12, height: 1.5),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '📖 $bookletPages',
                                  style: const TextStyle(color: Color(0xFF00F2FE), fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),

                        // تكليفات وواجبات الحصة القادمة
                        if (showHomework)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.assignment_rounded, color: Color(0xFFF59E0B), size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'تكليفات الحصة القادمة والواجب 📝',
                                      style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  nextHomework,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, height: 1.5, color: Colors.white),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.notifications_active_rounded, color: Color(0xFFEF4444), size: 15),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        nextQuiz,
                                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                        // درجات الكويز والتقييم
                        if (showGrades)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Column(
                                  children: [
                                    const Text('درجة آخر كويز 🎯', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${sampleStudent.quizScore} / ${sampleStudent.quizMax}',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                                    ),
                                  ],
                                ),
                                Container(width: 1, height: 35, color: const Color(0xFF334155)),
                                Column(
                                  children: [
                                    const Text('تقييم الواجب السابق 📝', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    const SizedBox(height: 4),
                                    Text(
                                      sampleStudent.hwStatus,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                        // إشعار في حال تم إغلاق جميع الأقسام
                        if (!showPayments && !showLessons && !showHomework && !showGrades)
                          Container(
                            padding: const EdgeInsets.all(24),
                            alignment: Alignment.center,
                            child: const Text(
                              'تم إخفاء جميع الأقسام مؤقتاً عبر مفاتيح التحكم 🔒',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
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

  @override
  Widget build(BuildContext context) {
    final filtered = _students.where((s) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      return s.name.toLowerCase().contains(q) ||
          s.id.toLowerCase().contains(q) ||
          s.phone.contains(q);
    }).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: const Text('ربط ومعاينة تطبيق الطالب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          backgroundColor: Colors.teal.shade800,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.teal))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. البطاقة الرئيسية لكود السنتر الموحد والمعاينة الحية
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade900, Colors.teal.shade600],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'الربط السحابي النشط ⚡',
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  centerName,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'المعلم: $teacherName',
                                  style: TextStyle(color: Colors.teal.shade100, fontSize: 11.5),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.link_rounded, color: Colors.white, size: 28),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // صندوق كود السنتر الموحد
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'كود السنتر الموحد لتسجيل الدخول:',
                                    style: TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    centerCode,
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded, color: Colors.white70, size: 18),
                                    tooltip: 'تعديل كود السنتر',
                                    onPressed: _showEditCenterCodeDialog,
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.teal.shade900,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: _copyCenterCode,
                                    icon: const Icon(Icons.copy_rounded, size: 15),
                                    label: const Text('نسخ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // زر المعاينة الحية لشاشة الطالب
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _openStudentLivePreview,
                            icon: const Icon(Icons.phone_android_rounded, size: 18),
                            label: const Text('افتح معاينة حية لشاشة الطالب الآن 📱', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. بطاقة التحكم في البيانات التي تظهر للطالب (Feature Toggles)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.tune_rounded, color: Colors.teal, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'التحكم في البيانات الظاهرة في تطبيق الطالب:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'أي تغيير تقوم به يتم تطبيقه فورياً على هواتف جميع الطلاب عبر السحابة ☁️',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: Colors.teal.shade700,
                          title: const Text('ملخص ما تم دراسته في الحصة والصفحات', style: TextStyle(fontSize: 13)),
                          subtitle: const Text('إظهار عنوان الدرس والموضوعات المشروحة وأرقام الملازم', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          value: showLessons,
                          onChanged: (v) => _updateVisibilitySetting(lessons: v),
                        ),
                        const Divider(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: Colors.teal.shade700,
                          title: const Text('تكليفات وواجبات الحصة القادمة والكويز', style: TextStyle(fontSize: 13)),
                          subtitle: const Text('إظهار مسائل وتدريبات الواجب وموعد وتفاصيل الامتحان القادم', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          value: showHomework,
                          onChanged: (v) => _updateVisibilitySetting(homework: v),
                        ),
                        const Divider(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: Colors.teal.shade700,
                          title: const Text('سجل الحضور وتقييم الواجب ودرجات الكويز', style: TextStyle(fontSize: 13)),
                          subtitle: const Text('إظهار نسبة الحضور ودرجات الاختبارات وتقييم التسميع والواجب', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          value: showGrades,
                          onChanged: (v) => _updateVisibilitySetting(grades: v),
                        ),
                        const Divider(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: Colors.teal.shade700,
                          title: const Text('حالة الاشتراك الشهري وإيصالات الدفع', style: TextStyle(fontSize: 13)),
                          subtitle: const Text('إظهار سريان الاشتراك والمصروفات المستحقة والإيصالات', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          value: showPayments,
                          onChanged: (v) => _updateVisibilitySetting(payments: v),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. قائمة أكواد تفعيل الطلاب (Student PINs & Activation)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'أكواد تفعيل ودخول الطلاب (PINs)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${filtered.length} طالب',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal.shade900),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // خانة البحث عن طالب
                        SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _searchController,
                            onChanged: (val) => setState(() => _searchQuery = val),
                            style: const TextStyle(fontSize: 12.5),
                            decoration: InputDecoration(
                              hintText: 'بحث باسم الطالب أو الكود...',
                              hintStyle: const TextStyle(fontSize: 11.5, color: Colors.grey),
                              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.teal),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 16),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (filtered.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            alignment: Alignment.center,
                            child: const Text('لا يوجد طلاب مطابقين للبحث', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          )
                        else
                          ...filtered.map((st) => Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.shade200, width: 1.2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.02),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // بيانات الطالب: الاسم ثم الكود تحته ثم الصف والمجموعة تحتهما
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // 1. اسم الطالب
                                          Text(
                                            st.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13.5,
                                              color: Color(0xFF0F172A),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 3),

                                          // 2. كود الطالب تحت الاسم مباشرة
                                          Row(
                                            children: [
                                              Icon(Icons.badge_outlined, size: 13, color: Colors.teal.shade800),
                                              const SizedBox(width: 4),
                                              Text(
                                                'كود الطالب: ${st.id}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.teal.shade900,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),

                                          // 3. الصف والمجموعة تحتهما على طول
                                          Row(
                                            children: [
                                              if (st.grade.isNotEmpty) ...[
                                                const Icon(Icons.school_outlined, size: 12, color: Colors.grey),
                                                const SizedBox(width: 3),
                                                Text(
                                                  st.grade,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF475569),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                              if (st.grade.isNotEmpty && st.groupName.isNotEmpty)
                                                const Padding(
                                                  padding: EdgeInsets.symmetric(horizontal: 5),
                                                  child: Text('•', style: TextStyle(color: Colors.grey, fontSize: 11)),
                                                ),
                                              if (st.groupName.isNotEmpty) ...[
                                                const Icon(Icons.groups_outlined, size: 12, color: Colors.grey),
                                                const SizedBox(width: 3),
                                                Flexible(
                                                  child: Text(
                                                    st.groupName,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Color(0xFF475569),
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // الرمز السري وزر المشاركة عبر واتساب
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade50,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.teal.shade200),
                                          ),
                                          child: Text(
                                            'PIN: ${st.pin}',
                                            style: TextStyle(
                                              color: Colors.teal.shade900,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () => _showSharePinDialog(st),
                                          borderRadius: BorderRadius.circular(10),
                                          child: Container(
                                            padding: const EdgeInsets.all(9),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF25D366),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
