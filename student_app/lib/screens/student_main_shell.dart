import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/student_auth_service.dart';
import '../services/student_communication_service.dart';
import '../services/student_data_service.dart';
import '../services/student_notification_sound_service.dart';
import '../services/student_update_service.dart';
import '../theme/app_theme.dart';
import 'certificate_celebration_dialog.dart';
import 'login_screen.dart';
import 'student_notifications_screen.dart';
import 'student_settings_screen.dart';
import 'tabs/chat_tab.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/exams_tab.dart';
import 'tabs/financials_tab.dart';
import 'tabs/lessons_tab.dart';
import 'tabs/materials_tab.dart';
import 'tabs/reports_tab.dart';

class StudentMainShell extends StatefulWidget {
  const StudentMainShell({super.key});

  @override
  State<StudentMainShell> createState() => _StudentMainShellState();
}

class _StudentMainShellState extends State<StudentMainShell> {
  int _currentIndex = 0;

  late final List<Widget> _tabs;

  final _titles = const [
    'الرئيسية 🏠',
    'مكتبة المذكرات 📚',
    'درجاتي واختباراتي 📊',
    'محادثة المعلم 💬',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = [
      DashboardTab(onNavigateTab: (index) {
        navigateToSection(index);
      }),
      const MaterialsTab(),
      const ExamsTab(),
      const ChatTab(),
    ];

    StudentNotificationSoundService.onNotificationPayloadClicked
        .addListener(_handleSystemNotificationClick);

    StudentAuthService.instance.onSessionRevoked
        .addListener(_handleSessionRevoked);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        StudentUpdateService.instance.checkForUpdate(context);
        _listenForCelebration();
      }
    });
  }

  StreamSubscription? _certSub;
  final Set<String> _celebratedExamIds = {};

  void _listenForCelebration() {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    if (studentId.toString().isEmpty) return;

    _certSub = StudentDataService.instance.streamStudentExams(studentId).listen((exams) async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      const oneDayMs = 24 * 60 * 60 * 1000;

      for (final exam in exams) {
        final examId = '${exam['exam_id'] ?? exam['id']}';
        final isRevoked = exam['certificate_deleted'] == true ||
            exam['certificate_revoked'] == true ||
            exam['has_certificate'] == false ||
            exam['certificate_issued'] == false;
        final hasCert = !isRevoked && (exam['has_certificate'] == true);
        if (!hasCert) {
          _celebratedExamIds.add(examId);
          continue;
        }

        // التحقق من صلاحية ظهور الشهادة عند فتح التطبيق (تظهر لمدة يوم واحد فقط = 24 ساعة)
        final firstSeenKey = 'cert_first_seen_${studentId}_$examId';
        final firstSeen = prefs.getInt(firstSeenKey);

        if (firstSeen == null) {
          // أول مرة يشاهدها: نسجل تاريخ الاستلام ونعرض الاحتفال
          await prefs.setInt(firstSeenKey, now);
          _celebratedExamIds.add(examId);
          if (!mounted) return;
          _showCertificateCelebration(exam, student, studentId);
          break;
        } else if (now - firstSeen < oneDayMs) {
          // لم يمر 24 ساعة بعد: تظهر مرة واحدة في هذه الجلسة الحالية فقط
          if (!_celebratedExamIds.contains(examId)) {
            _celebratedExamIds.add(examId);
            if (!mounted) return;
            _showCertificateCelebration(exam, student, studentId);
            break;
          }
        } else {
          // انتهت فترة الـ 24 ساعة: لا تنبثق كنافذة احتفال عند الفتح، وتبقى في الأرشيف
          _celebratedExamIds.add(examId);
        }
      }
    });
  }

  void _showCertificateCelebration(
    Map<String, dynamic> exam,
    Map<String, dynamic>? student,
    dynamic studentId,
  ) {
    final realStudentName = (exam['student_name'] ?? student?['full_name'] ?? student?['name'] ?? '').toString().trim();
    final effectiveStudentName = realStudentName.isNotEmpty ? realStudentName : 'الطالب المتفوق';
    final realCode = '${exam['student_code'] ?? student?['student_code'] ?? studentId}';
    final realGroup = (exam['group_name'] ?? student?['group_name'] ?? '').toString().trim();

    CertificateCelebrationDialog.show(
      context: context,
      exam: exam,
      studentName: effectiveStudentName,
      code: realCode,
      groupName: realGroup,
    );
  }

  @override
  void dispose() {
    _certSub?.cancel();
    StudentNotificationSoundService.onNotificationPayloadClicked
        .removeListener(_handleSystemNotificationClick);
    StudentAuthService.instance.onSessionRevoked
        .removeListener(_handleSessionRevoked);
    super.dispose();
  }

  void _handleSessionRevoked() {
    final reason = StudentAuthService.instance.onSessionRevoked.value;
    if (reason == null || !mounted) return;
    StudentAuthService.instance.onSessionRevoked.value = null;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(notice: reason),
      ),
      (route) => false,
    );
  }

  void navigateToSection(int index) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    switch (index) {
      case 0: // الرئيسية
        setState(() => _currentIndex = 0);
        break;
      case 1: // مذكراتي (المكتبة الذكية)
        setState(() => _currentIndex = 1);
        break;
      case 2: // درجاتي ولوحة الشرف
        setState(() => _currentIndex = 2);
        break;
      case 3: // تواصل مع المعلم
        setState(() => _currentIndex = 3);
        final student = StudentAuthService.instance.currentStudent;
        final studentId = (student?['id'] ?? '').toString();
        if (studentId.isNotEmpty) {
          StudentCommunicationService.instance.markConversationReadByStudent(studentId);
        }
        break;
      case 4: // الحصص والواجبات
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: const Color(0xFF060911),
              appBar: AppBar(
                title: const Text('الحصص والواجبات 📝', style: TextStyle(fontWeight: FontWeight.w900)),
                backgroundColor: const Color(0xFF0F172A),
                elevation: 0,
              ),
              body: const LessonsTab(),
            ),
          ),
        );
        break;
      case 5: // تقارير المتابعة
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: const Color(0xFF060911),
              appBar: AppBar(
                title: const Text('تقرير المتابعة والتقييم 📑', style: TextStyle(fontWeight: FontWeight.w900)),
                backgroundColor: const Color(0xFF0F172A),
                elevation: 0,
              ),
              body: const ReportsTab(),
            ),
          ),
        );
        break;
      case 6: // الحساب والمصروفات
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: const Color(0xFF060911),
              appBar: AppBar(
                title: const Text('الحساب والمصروفات 🧾', style: TextStyle(fontWeight: FontWeight.w900)),
                backgroundColor: const Color(0xFF0F172A),
                elevation: 0,
              ),
              body: const FinancialsTab(),
            ),
          ),
        );
        break;
      default:
        if (index >= 0 && index < _tabs.length) {
          setState(() => _currentIndex = index);
        }
    }
  }

  void _handleSystemNotificationClick() {
    final payload =
        StudentNotificationSoundService.onNotificationPayloadClicked.value;
    if (payload == null || !mounted) return;
    StudentNotificationSoundService.onNotificationPayloadClicked.value = null;

    if (payload.contains('exam')) {
      navigateToSection(2);
    } else if (payload.contains('session') || payload.contains('lesson')) {
      navigateToSection(4);
    } else if (payload.contains('material') || payload.contains('pdf')) {
      navigateToSection(1);
    } else if (payload.contains('report')) {
      navigateToSection(5);
    } else if (payload.contains('financial')) {
      navigateToSection(6);
    } else if (payload.contains('chat')) {
      navigateToSection(3);
    } else {
      navigateToSection(0);
    }
  }

  void _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('هل ترغب حقاً في تسجيل الخروج من حساب الطالب؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('خروج', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await StudentAuthService.instance.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // =========================================================================
  // قائمة ترس الإعدادات السريعة (البروفايل، الإعدادات، تسجيل الخروج)
  // =========================================================================
  void _openSettingsMenu() {
    HapticFeedback.lightImpact();
    final student = StudentAuthService.instance.currentStudent;
    final name = student?['full_name'] ?? 'طالب الأكاديمية';
    final code = student?['student_code'] ?? student?['id'] ?? '';
    final grade = student?['grade'] ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // Mini Profile Header
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                    border: Border.all(color: const Color(0xFF00F2FE), width: 1.5),
                  ),
                  child: const Center(
                    child: Text('🎓', style: TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'كود: $code ${grade.isNotEmpty ? " • $grade" : ""}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFF1E293B)),
            const SizedBox(height: 8),

            // 1. Profile Option
            _buildSettingsMenuItem(
              icon: Icons.person_rounded,
              iconColor: const Color(0xFF00F2FE),
              title: 'البروفايل (الملف الشخصي)',
              subtitle: 'استعراض بيانات الطالب والمرحلة والهواتف',
              onTap: () {
                Navigator.pop(ctx);
                _showProfileModal();
              },
            ),
            const SizedBox(height: 6),

            // 2. Settings & Privacy Option
            _buildSettingsMenuItem(
              icon: Icons.security_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'الإعدادات والخصوصية',
              subtitle: 'تغيير الرمز السري PIN والمصادقة الثنائية 2FA',
              onTap: () {
                Navigator.pop(ctx);
                _showPrivacySettingsModal();
              },
            ),
            const SizedBox(height: 6),

            // 3. Check for Updates Option
            _buildSettingsMenuItem(
              icon: Icons.system_update_rounded,
              iconColor: const Color(0xFF38BDF8),
              title: 'التحقق من التحديثات',
              subtitle: 'فحص توفر أحدث إصدار وتحديث التطبيق تلقائياً',
              onTap: () {
                Navigator.pop(ctx);
                StudentUpdateService.instance.checkForUpdate(context, showNoUpdateToast: true);
              },
            ),
            const SizedBox(height: 6),

            // 4. Logout Option
            _buildSettingsMenuItem(
              icon: Icons.logout_rounded,
              iconColor: const Color(0xFFEF4444),
              title: 'تسجيل الخروج',
              subtitle: 'الخروج من حساب الطالب',
              isDestructive: true,
              onTap: () {
                Navigator.pop(ctx);
                _handleLogout();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsMenuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDestructive
                  ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                  : const Color(0xFF334155),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: isDestructive ? const Color(0xFFEF4444) : AppTheme.textLight,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  // نافذة البروفايل
  void _showProfileModal() {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF00F2FE), width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(Icons.person_pin_rounded, color: Color(0xFF00F2FE), size: 24),
            SizedBox(width: 10),
            Text('بيانات الطالب والبروفايل', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: StudentDataService.instance.streamStudent(studentId),
          builder: (context, snap) {
            final d = snap.data?.data() ?? student ?? {};
            final name = d['full_name'] ?? 'الطالب';
            final code = d['student_code'] ?? studentId;
            final grade = d['grade'] ?? 'المرحلة الدراسية';
            final phone = d['phone'] ?? d['student_phone'] ?? 'غير مسجل';
            final parentPhone = d['parent_phone'] ?? 'غير مسجل';
            final groupId = d['group_id'] ?? '';

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProfileRow('اسم الطالب:', name),
                  _buildProfileRow('كود الطالب:', code),
                  _buildProfileRow('الصف الدراسي:', grade),
                  if (groupId.toString().isNotEmpty)
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: StudentDataService.instance.streamGroup(groupId),
                      builder: (context, gSnap) {
                        final gName = gSnap.data?.data()?['name'] ?? 'مجموعة $groupId';
                        return _buildProfileRow('المجموعة:', gName);
                      },
                    ),
                  _buildProfileRow('هاتف الطالب:', phone),
                  _buildProfileRow('هاتف ولي الأمر:', parentPhone),
                  _buildProfileRow('الأكاديمية:', 'Edu Academy الذكية'),
                ],
              ),
            );
          },
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F2FE),
              foregroundColor: const Color(0xFF050B14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textLight),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // نافذة الإعدادات والخصوصية (تغيير PIN والمصادقة الثنائية)
  void _showPrivacySettingsModal() {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? localError;
    bool isUpdating2fa = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
          ),
          title: const Row(
            children: [
              Icon(Icons.lock_person_rounded, color: Color(0xFF10B981), size: 24),
              SizedBox(width: 10),
              Text('الإعدادات والخصوصية 🔒', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 2FA Switch
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: StudentDataService.instance.streamStudent(studentId),
                  builder: (context, snap) {
                    final is2Fa = snap.data?.data()?['require_2fa'] != false;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('المصادقة الثنائية (2FA)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                SizedBox(height: 2),
                                Text('تأكيد رقم الهاتف عند الدخول', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                              ],
                            ),
                          ),
                          Switch(
                            value: is2Fa,
                            thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
                              if (states.contains(WidgetState.selected)) {
                                return const Color(0xFF00F2FE);
                              }
                              return Colors.grey;
                            }),
                            activeTrackColor: const Color(0xFF00F2FE).withValues(alpha: 0.3),
                            onChanged: isUpdating2fa
                                ? null
                                : (newVal) async {
                                    setDialogState(() => isUpdating2fa = true);
                                    await StudentAuthService.instance.update2FA(newVal);
                                    setDialogState(() => isUpdating2fa = false);
                                  },
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Change PIN section
                const Text('تغيير الرمز السري (PIN):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE))),
                const SizedBox(height: 8),
                TextField(
                  controller: newPinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'الرمز السري الجديد (4 أرقام فأكثر)',
                    prefixIcon: const Icon(Icons.password_rounded, size: 18),
                    filled: true,
                    fillColor: AppTheme.darkCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmPinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'تأكيد الرمز الجديد',
                    prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    filled: true,
                    fillColor: AppTheme.darkCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),

                if (localError != null) ...[
                  const SizedBox(height: 8),
                  Text(localError!, style: const TextStyle(color: AppTheme.danger, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final p1 = newPinController.text.trim();
                final p2 = confirmPinController.text.trim();
                if (p1.length < 4) {
                  setDialogState(() => localError = 'الرمز يجب أن يتكون من 4 أرقام على الأقل');
                  return;
                }
                if (p1 != p2) {
                  setDialogState(() => localError = 'الرمزان غير متطابقين');
                  return;
                }
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final ok = await StudentAuthService.instance.updatePin(p1);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'تم تحديث الرمز السري بنجاح 🔒' : 'فشل التحديث'),
                    backgroundColor: ok ? AppTheme.success : AppTheme.danger,
                  ),
                );
              },
              child: const Text('حفظ الرمز', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeAppBarTitle(Map<String, dynamic>? student) {
    final fullName = (student?['full_name'] ?? student?['name'] ?? 'طالب الأكاديمية').toString().trim();
    final firstName = fullName.isNotEmpty ? fullName.split(' ').first : 'طالبنا';
    final code = (student?['student_code'] ?? student?['id'] ?? '').toString().trim();
    final grade = (student?['grade'] ?? student?['stage'] ?? '').toString().trim();
    final isParent = StudentAuthService.instance.isParent;

    return Row(
      children: [
        // Avatar with gradient glow and streak flame badge (tap opens quick profile sheet)
        GestureDetector(
          onTap: _openSettingsMenu,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF00F2FE), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  firstName.isNotEmpty ? firstName.characters.first : '🎓',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -3,
              right: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF0F172A), width: 1.5),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🔥', style: TextStyle(fontSize: 8.5)),
                    SizedBox(width: 1),
                    Text(
                      '5د',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF050811),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'مرحباً، $firstName ✨',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                        color: AppTheme.textLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isParent) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        '👨‍👩‍👧 ولي أمر',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                grade.isNotEmpty ? '$grade 🎓' : 'كود الطالب: $code ⚡',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF00F2FE),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStandardAppBarTitle() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00F2FE).withValues(alpha: 0.3),
                blurRadius: 8,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            _titles[_currentIndex],
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppTheme.textLight,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    final groupId = student?['group_id'];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 16,
        title: _currentIndex == 0
            ? _buildHomeAppBarTitle(student)
            : _buildStandardAppBarTitle(),
        actions: [
          // Notifications Bell with Live Unread Counter
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: StudentCommunicationService.instance.streamStudentNotifications(
              studentId: studentId,
              groupId: groupId,
            ),
            builder: (context, snapshot) {
              final notifs = snapshot.data ?? [];
              return FutureBuilder<int>(
                future: StudentCommunicationService.instance.getUnreadNotificationsCount(notifs),
                builder: (context, unreadSnap) {
                  final unreadCount = unreadSnap.data ?? 0;
                  return IconButton(
                    tooltip: 'مركز الإشعارات والتنبيهات',
                    icon: Badge(
                      isLabelVisible: unreadCount > 0,
                      label: Text('$unreadCount'),
                      backgroundColor: const Color(0xFFEF4444),
                      child: const Icon(Icons.notifications_none_rounded),
                    ),
                    onPressed: () async {
                      final targetIndex = await Navigator.push<int>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StudentNotificationsScreen(),
                        ),
                      );
                      if (targetIndex != null) {
                        if (targetIndex == 1) {
                          navigateToSection(2); // exams
                        } else if (targetIndex == 2) {
                          navigateToSection(4); // lessons
                        } else if (targetIndex == 3) {
                          navigateToSection(1); // materials
                        } else if (targetIndex == 4) {
                          navigateToSection(5); // reports
                        } else if (targetIndex == 5) {
                          navigateToSection(6); // financials
                        } else if (targetIndex == 6) {
                          navigateToSection(3); // chat
                        } else {
                          navigateToSection(0);
                        }
                      }
                    },
                  );
                },
              );
            },
          ),

          // Settings Gear Icon (Opens full settings & profile)
          IconButton(
            tooltip: 'الإعدادات والملف الشخصي ⚙️',
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF00F2FE)),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StudentSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.darkCard,
          border: Border(
            top: BorderSide(color: AppTheme.darkCardBorder, width: 1),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          backgroundColor: Colors.transparent,
          indicatorColor: const Color(0xFF00F2FE).withValues(alpha: 0.18),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 66,
          onDestinationSelected: (idx) {
            navigateToSection(idx);
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined, size: 23),
              selectedIcon: Icon(Icons.home_rounded, color: Color(0xFF00F2FE), size: 23),
              label: 'الرئيسية',
            ),
            const NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined, size: 23),
              selectedIcon: Icon(Icons.auto_stories_rounded, color: Color(0xFF00F2FE), size: 23),
              label: 'مذكراتي',
            ),
            const NavigationDestination(
              icon: Icon(Icons.military_tech_outlined, size: 23),
              selectedIcon: Icon(Icons.military_tech_rounded, color: Color(0xFF00F2FE), size: 23),
              label: 'درجاتي',
            ),
            NavigationDestination(
              icon: StreamBuilder<int>(
                stream: StudentCommunicationService.instance
                    .streamUnreadMessagesForStudent(studentId),
                builder: (context, snap) {
                  final unread = snap.data ?? 0;
                  return Badge(
                    isLabelVisible: unread > 0,
                    label: Text('$unread'),
                    backgroundColor: const Color(0xFF00B4D8),
                    child: const Icon(Icons.chat_bubble_outline_rounded, size: 21),
                  );
                },
              ),
              selectedIcon: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF00F2FE), size: 21),
              label: 'تواصل',
            ),
          ],
        ),
      ),
    );
  }
}
