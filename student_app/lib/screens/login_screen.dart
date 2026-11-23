import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/student_auth_service.dart';
import '../services/student_notification_sound_service.dart';
import '../theme/app_theme.dart';
import 'student_main_shell.dart';

class LoginScreen extends StatefulWidget {
  final String? notice;

  const LoginScreen({super.key, this.notice});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  // Role: 'student' or 'parent'
  String _selectedRole = 'student';

  // Student Controllers
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  final _studentPhoneController = TextEditingController();

  // Parent Controllers
  final _parentPhoneController = TextEditingController();
  final _parentStudentCodeController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePin = true;
  String? _errorMessage;
  String? _securityAlert;

  @override
  void initState() {
    super.initState();
    _securityAlert = widget.notice;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    _studentPhoneController.dispose();
    _parentPhoneController.dispose();
    _parentStudentCodeController.dispose();
    super.dispose();
  }

  // 1. تسجيل دخول الطالب
  Future<void> _handleStudentLogin() async {
    HapticFeedback.lightImpact();
    final code = _codeController.text.trim();
    final pin = _pinController.text.trim();
    final phone = _studentPhoneController.text.trim();

    if (code.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال كود الطالب الخاص بك');
      return;
    }
    if (pin.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال الرمز السري (PIN)');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await StudentAuthService.instance.loginSecure(
      code: code,
      pin: pin,
      phone: phone.isNotEmpty ? phone : null,
    );

    if (!mounted) return;

    if (res['success'] == true) {
      StudentNotificationSoundService.instance.startListeningToEvents();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const StudentMainShell()),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = res['message'] ?? 'فشل تسجيل الدخول. تحقق من البيانات.';
      });
    }
  }

  // 2. تسجيل دخول ولي الأمر
  Future<void> _handleParentLogin() async {
    HapticFeedback.lightImpact();
    final parentPhone = _parentPhoneController.text.trim();
    final verifyCode = _parentStudentCodeController.text.trim();

    if (parentPhone.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال رقم هاتف ولي الأمر المسجل لدى المعلم');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await StudentAuthService.instance.loginParent(
      parentPhone: parentPhone,
      studentCode: verifyCode.isNotEmpty ? verifyCode : null,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (res['success'] == true) {
      if (res['requires_child_selection'] == true) {
        final children = (res['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        _showChildSelectionModal(children);
      } else {
        StudentNotificationSoundService.instance.startListeningToEvents();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const StudentMainShell()),
        );
      }
    } else {
      setState(() {
        _errorMessage = res['message'] ?? 'لم يتم العثور على حساب بهذا الرقم.';
      });
    }
  }

  // نافذة اختيار الابن في حال كان لولي الأمر أكثر من ابن مسجل
  void _showChildSelectionModal(List<Map<String, dynamic>> children) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 4),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // مقبض النافذة
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Row(
                children: [
                  Icon(Icons.family_restroom_rounded, color: Color(0xFFF59E0B), size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'اختر الابن / الابنة للمتابعة 🌟',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'تم العثور على أكثر من طالب مسجل برقم هاتفك',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: children.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final child = children[index];
                    final name = child['full_name'] ?? 'طالب الأكاديمية';
                    final grade = child['grade'] ?? '';
                    final code = child['student_code'] ?? child['id'] ?? '';

                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final nav = Navigator.of(context);
                        Navigator.pop(ctx);
                        setState(() => _isLoading = true);
                        final selectRes = await StudentAuthService.instance.selectChild(child);
                        if (!mounted) return;
                        setState(() => _isLoading = false);

                        if (selectRes['success'] == true) {
                          StudentNotificationSoundService.instance.startListeningToEvents();
                          nav.pushReplacement(
                            MaterialPageRoute(builder: (_) => const StudentMainShell()),
                          );
                        } else {
                          setState(() {
                            _errorMessage = selectRes['message'] ?? 'تعذر تسجيل الدخول';
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF090D16),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.school_rounded, color: Color(0xFF080C14), size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'الصف: $grade  •  كود: $code',
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFF59E0B)),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isStudent = _selectedRole == 'student';

    return Scaffold(
      backgroundColor: const Color(0xFF060911),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF060911), Color(0xFF0F172A), Color(0xFF060911)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo / Icon
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: (isStudent ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B)).withValues(alpha: 0.35),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title & Subtitle
                  const Text(
                    'Edu Academy',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isStudent ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B)).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (isStudent ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B)).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      isStudent ? 'بوابة الطالب الأكاديمية 🎓' : 'بوابة متابعة ولي الأمر 👨‍👩‍👧',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: isStudent ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Security Revocation Alert Banner
                  if (_securityAlert != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'تنبيه أمني لحظي 🔒',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _securityAlert!,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11.5,
                                    color: Color(0xFFFCA5A5),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // محدد الهوية: طالب أو ولي أمر (Role Switcher)
                  Container(
                    height: 48,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Row(
                      children: [
                        // زر طالب
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              if (_selectedRole != 'student') {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _selectedRole = 'student';
                                  _errorMessage = null;
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: isStudent
                                    ? const LinearGradient(colors: [Color(0xFF00F2FE), Color(0xFF0284C7)])
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '🎓 أنا طالب',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                  color: isStudent ? const Color(0xFF080C14) : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // زر ولي أمر
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              if (_selectedRole != 'parent') {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _selectedRole = 'parent';
                                  _errorMessage = null;
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: !isStudent
                                    ? const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)])
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '👨‍👩‍👧 أنا ولي أمر',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                  color: !isStudent ? const Color(0xFF080C14) : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // بطاقة النموذج (Card)
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isStudent ? const Color(0xFF1E293B) : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          isStudent ? 'تسجيل دخول الطالب 🎓' : 'بوابة متابعة الأبناء 👨‍👩‍👧',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textLight,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isStudent
                              ? 'أدخل كود الطالب المسجل لدى المعلم لمتابعة حصصك ومذكراتك'
                              : 'أدخل رقم هاتفك المسجل لمتابعة حضور ودرجات وواجبات أبنائك فورياً',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            color: AppTheme.textMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),

                        // Error message
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      color: AppTheme.danger,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // ==========================================
                        // حقول نموذج الطالب
                        // ==========================================
                        if (isStudent) ...[
                          // كود الطالب
                          TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                            decoration: InputDecoration(
                              labelText: 'كود الطالب (إلزامي)',
                              labelStyle: const TextStyle(fontFamily: 'Cairo', color: AppTheme.textMuted, fontSize: 13),
                              prefixIcon: const Icon(Icons.badge_rounded, color: Color(0xFF00F2FE)),
                              filled: true,
                              fillColor: const Color(0xFF090D16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Color(0xFF00F2FE), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // الرمز السري PIN
                          TextField(
                            controller: _pinController,
                            obscureText: _obscurePin,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Color(0xFF00F2FE),
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 5,
                            ),
                            decoration: InputDecoration(
                              labelText: 'الرمز السري (PIN)',
                              labelStyle: const TextStyle(fontFamily: 'Cairo', color: AppTheme.textMuted, fontSize: 13),
                              prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF00F2FE)),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePin ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppTheme.textMuted, size: 20),
                                onPressed: () => setState(() => _obscurePin = !_obscurePin),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF090D16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Color(0xFF00F2FE), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // رقم هاتف الطالب أو ولي الأمر للتحقق (اختياري)
                          TextField(
                            controller: _studentPhoneController,
                            keyboardType: TextInputType.phone,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              labelText: 'رقم هاتف ولي الأمر (اختياري للتحقق)',
                              labelStyle: const TextStyle(fontFamily: 'Cairo', color: AppTheme.textMuted, fontSize: 12),
                              prefixIcon: const Icon(Icons.phone_iphone_rounded, color: Color(0xFF10B981)),
                              helperText: 'خطوة اختيارية لزيادة أمان الحساب وتوثيقه',
                              helperStyle: const TextStyle(fontFamily: 'Cairo', color: Color(0xFF64748B), fontSize: 10.5),
                              filled: true,
                              fillColor: const Color(0xFF090D16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                              ),
                            ),
                          ),
                        ]
                        // ==========================================
                        // حقول نموذج ولي الأمر
                        // ==========================================
                        else ...[
                          // رقم هاتف ولي الأمر
                          TextField(
                            controller: _parentPhoneController,
                            keyboardType: TextInputType.phone,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                            decoration: InputDecoration(
                              labelText: 'رقم هاتف ولي الأمر (إلزامي)',
                              labelStyle: const TextStyle(fontFamily: 'Cairo', color: AppTheme.textMuted, fontSize: 13),
                              prefixIcon: const Icon(Icons.phone_android_rounded, color: Color(0xFFF59E0B)),
                              helperText: 'أدخل نفس الرقم المسجل به الطالب في السنتر',
                              helperStyle: const TextStyle(fontFamily: 'Cairo', color: Color(0xFF64748B), fontSize: 10.5),
                              filled: true,
                              fillColor: const Color(0xFF090D16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // كود الطالب لتأكيد الهوية (اختياري)
                          TextField(
                            controller: _parentStudentCodeController,
                            keyboardType: TextInputType.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              labelText: 'كود أحد الأبناء (اختياري للتحقق السريع)',
                              labelStyle: const TextStyle(fontFamily: 'Cairo', color: AppTheme.textMuted, fontSize: 12),
                              prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFFF59E0B)),
                              filled: true,
                              fillColor: const Color(0xFF090D16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 22),

                        // زر الدخول الرئيسي
                        Container(
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: isStudent
                                  ? [const Color(0xFF00F2FE), const Color(0xFF0284C7)]
                                  : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (isStudent ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B)).withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : (isStudent ? _handleStudentLogin : _handleParentLogin),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF04101E)),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        isStudent ? '🚀 تسجيل الدخول كطالب' : '👨‍👩‍👧 دخول ولي الأمر للمتابعة',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14.5,
                                          color: Color(0xFF04101E),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 12),
                        // زر المساعدة
                        TextButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF0F172A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  side: const BorderSide(color: Color(0xFF334155)),
                                ),
                                title: const Row(
                                  children: [
                                    Icon(Icons.help_outline_rounded, color: Color(0xFF00F2FE)),
                                    SizedBox(width: 8),
                                    Text('إرشادات تسجيل الدخول', style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '• للطلاب: ادخل بكود الطالب ورمزك السري (PIN) للدخول الفوري.\n'
                                      '• لأولياء الأمور: ادخل برقم الهاتف المسجل لدى الأكاديمية وسيتعرف النظام تلقائياً على أبنائك المسجلين لمتابعة درجاتهم وحضورهم.\n'
                                      '• في حال نسيت بيانات الدخول، يرجى التواصل مع إدارة السنتر.',
                                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13, height: 1.6, color: Color(0xFFCBD5E1)),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('حسناً', style: TextStyle(fontFamily: 'Cairo', color: Color(0xFF00F2FE), fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          },
                          icon: const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF94A3B8)),
                          label: const Text(
                            'تحتاج مساعدة أو نسيت بياناتك؟',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Edu Academy • المنصة التعليمية المتكاملة',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
