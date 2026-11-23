import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/student_auth_service.dart';
import '../../services/student_data_service.dart';
import '../../services/student_notification_sound_service.dart';
import '../../services/student_update_service.dart';
import '../../theme/app_theme.dart';
import '../login_screen.dart';
import '../student_notifications_screen.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _isUpdating2fa = false;

  void _handleChangePinDialog() {
    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? localError;
    bool obscureCurrent = true;
    bool obscureNew = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF334155)),
          ),
          title: const Row(
            children: [
              Icon(Icons.lock_reset_rounded, color: Color(0xFF00F2FE)),
              SizedBox(width: 10),
              Text(
                'تغيير الرمز السري 🔒',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'سيتم حفظ الرمز السري الجديد فوراً ومزامنته مع لوحة تحكم المعلم.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 14),

                // Current PIN
                TextField(
                  controller: currentPinController,
                  obscureText: obscureCurrent,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'الرمز السري الحالي',
                    prefixIcon: const Icon(Icons.password_rounded, color: AppTheme.textMuted),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureCurrent ? Icons.visibility_off : Icons.visibility,
                        color: AppTheme.textMuted,
                      ),
                      onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                // New PIN
                TextField(
                  controller: newPinController,
                  obscureText: obscureNew,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'الرمز السري الجديد (4 أرقام فأكثر)',
                    prefixIcon: const Icon(Icons.vpn_key_rounded, color: Color(0xFF00F2FE)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureNew ? Icons.visibility_off : Icons.visibility,
                        color: AppTheme.textMuted,
                      ),
                      onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                // Confirm PIN
                TextField(
                  controller: confirmPinController,
                  obscureText: obscureNew,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'تأكيد الرمز السري الجديد',
                    prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00F2FE)),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                if (localError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    localError!,
                    style: const TextStyle(color: AppTheme.danger, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
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
                backgroundColor: const Color(0xFF00F2FE),
                foregroundColor: const Color(0xFF050B14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final currentSaved = StudentAuthService.instance.currentStudent?['pin_code']?.toString().trim() ?? '';
                final enteredCurrent = currentPinController.text.trim();
                final p1 = newPinController.text.trim();
                final p2 = confirmPinController.text.trim();

                if (currentSaved.isNotEmpty && enteredCurrent != currentSaved) {
                  setDialogState(() => localError = 'الرمز السري الحالي غير صحيح');
                  return;
                }
                if (p1.length < 4) {
                  setDialogState(() => localError = 'الرمز الجديد يجب أن يتكون من 4 أرقام على الأقل');
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
                    content: Text(ok ? 'تم تحديث الرمز السري وحفظه في المنظومة 🔒' : 'فشل تحديث الرمز السري'),
                    backgroundColor: ok ? AppTheme.success : AppTheme.danger,
                  ),
                );
              },
              child: const Text('حفظ الرمز الجديد', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _handleStudent2FaToggle(BuildContext context, bool newVal, Map<String, dynamic> liveData) async {
    if (!newVal) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('تعطيل المصادقة الثنائية ⚠️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: const Text(
            'هل أنت متأكد من رغبتك في تعطيل المصادقة الثنائية؟ سيتمكن أي شخص يملك كودك والرمز السري من الدخول.',
            style: TextStyle(fontSize: 12.5),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تعطيل'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      setState(() => _isUpdating2fa = true);
      final ok = await StudentAuthService.instance.update2FA(false);
      if (mounted) setState(() => _isUpdating2fa = false);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'تم تعطيل المصادقة الثنائية' : 'فشل تعديل الإعداد'),
            backgroundColor: ok ? AppTheme.warning : AppTheme.danger,
          ),
        );
      }
      return;
    }

    // Enabling 2FA: Mandatory Phone Number & WhatsApp Confirmation
    final student = StudentAuthService.instance.currentStudent ?? liveData;
    final currentPhone = (liveData['two_fa_verified_phone'] ??
            liveData['phone'] ??
            liveData['student_phone'] ??
            liveData['parent_phone'] ??
            student['student_phone'] ??
            student['parent_phone'] ??
            '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');

    final phoneController = TextEditingController(text: currentPhone);
    final formKey = GlobalKey<FormState>();

    final confirmedPhone = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF00F2FE), width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: Color(0xFF00F2FE)),
            SizedBox(width: 8),
            Expanded(
              child: Text('تفعيل المصادقة الثنائية (2FA) 🛡️',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'لحماية حسابك الدراسي، إدخال رقم هاتفك إجباري للتحقق وسيتم إرسال رسالة تأكيد عبر الواتساب فور التفعيل:',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1),
                  decoration: InputDecoration(
                    labelText: 'رقم هاتفك المعتمد للدخول *',
                    hintText: '010XXXXXXXX',
                    prefixIcon: const Icon(Icons.phone_android_rounded, color: Color(0xFF00F2FE)),
                    filled: true,
                    fillColor: AppTheme.darkBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (val) {
                    final clean = (val ?? '').replaceAll(RegExp(r'\D'), '');
                    if (clean.length < 10) {
                      return 'يجب إدخال رقم هاتف صحيح مكون من 10 أرقام على الأقل';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'سيتم إرسال رسالة تأكيد رسمية إلى هذا الرقم عبر تطبيق الواتساب للتحقق من هويتك.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF25D366), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('إلغاء')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00F2FE), foregroundColor: Colors.black87),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('تأكيد وإرسال واتساب 💬', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, phoneController.text.trim().replaceAll(RegExp(r'\D'), ''));
              }
            },
          ),
        ],
      ),
    );

    if (confirmedPhone == null || confirmedPhone.isEmpty) return;

    setState(() => _isUpdating2fa = true);
    final ok = await StudentAuthService.instance.update2FA(true, verifiedPhone: confirmedPhone);
    if (mounted) setState(() => _isUpdating2fa = false);

    if (ok) {
      final sName = (student['full_name'] ?? 'الطالب').toString();
      final sCode = (student['student_code'] ?? student['id'] ?? '').toString();
      final message = '''
🔐 *تأكيد تفعيل المصادقة الثنائية (2FA) - تطبيق الطالب Edu Academy*

مرحباً بك $sName،
تم بنجاح تفعيل نظام التحقق برقم هاتفك للدخول إلى حسابك الدراسي:
🆔 *كود الطالب:* $sCode
📱 *الهاتف المعتمد:* $confirmedPhone

تم قفل الحساب برقم هاتفك لحماية مذكراتك ودروسك ودرجاتك من أي دخول غير مصرح به. ✨
''';
      final encoded = Uri.encodeComponent(message);
      final waUri = Uri.parse('whatsapp://send?phone=$confirmedPhone&text=$encoded');
      final webUri = Uri.parse('https://wa.me/$confirmedPhone?text=$encoded');
      try {
        if (await canLaunchUrl(waUri)) {
          await launchUrl(waUri, mode: LaunchMode.externalApplication);
        } else {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تفعيل المصادقة الثنائية وجاري فتح واتساب لتأكيد الرقم 🛡️'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تفعيل المصادقة الثنائية'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';

    return Scaffold(
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: StudentDataService.instance.streamStudent(studentId),
        builder: (context, snapshot) {
          final liveData = snapshot.data?.data() ?? {};
          final name = liveData['full_name'] ?? student?['full_name'] ?? 'طالب الأكاديمية';
          final sCode = liveData['student_code'] ?? student?['student_code'] ?? studentId;
          final grade = liveData['grade'] ?? student?['grade'] ?? 'المرحلة الدراسية';
          final phone = liveData['phone'] ?? liveData['student_phone'] ?? student?['phone'] ?? 'غير مسجل';
          final parentPhone = liveData['parent_phone'] ?? student?['parent_phone'] ?? 'غير مسجل';
          final groupId = liveData['group_id'] ?? student?['group_id'] ?? '';
          final is2FaEnabled = liveData['require_2fa'] != false;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            children: [
              // 1. Profile Avatar & Name Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF334155)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                        border: Border.all(color: const Color(0xFF00F2FE), width: 2),
                      ),
                      child: const Center(
                        child: Text('🎓', style: TextStyle(fontSize: 28)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'كود: $sCode',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF00F2FE),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'نشط 🟢',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. Academic Profile Details
              _buildSectionTitle('بيانات الطالب الأكاديمية 📋'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.darkCardBorder),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(Icons.school_rounded, 'الصف الدراسي', grade),
                    const Divider(height: 1, color: AppTheme.darkCardBorder),
                    if (groupId.toString().isNotEmpty) ...[
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: StudentDataService.instance.streamGroup(groupId),
                        builder: (context, groupSnap) {
                          final gName = groupSnap.data?.data()?['name'] ?? 'مجموعة $groupId';
                          return _buildInfoRow(Icons.groups_rounded, 'المجموعة الدراسية', gName);
                        },
                      ),
                      const Divider(height: 1, color: AppTheme.darkCardBorder),
                    ],
                    _buildInfoRow(Icons.phone_android_rounded, 'هاتف الطالب', phone.toString()),
                    const Divider(height: 1, color: AppTheme.darkCardBorder),
                    _buildInfoRow(Icons.phone_rounded, 'هاتف ولي الأمر', parentPhone.toString()),
                    const Divider(height: 1, color: AppTheme.darkCardBorder),
                    _buildInfoRow(Icons.business_rounded, 'الأكاديمية', 'Edu Academy - منصة المعلم'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. Privacy & Security Settings (الخصوصية والأمان)
              _buildSectionTitle('الخصوصية والأمان وحماية الحساب 🔒'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    // Change PIN Row
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _handleChangePinDialog,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.password_rounded, color: Color(0xFF00F2FE), size: 22),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'تغيير الرمز السري (PIN)',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.textLight,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'تحديث كلمة المرور المستخدمة لتسجيل دخول الطالب',
                                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: AppTheme.textMuted),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: AppTheme.darkCardBorder),

                    // 2FA Toggle Switch
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.security_rounded, color: Color(0xFF10B981), size: 22),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'المصادقة الثنائية (2FA)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textLight,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'تأكيد رقم الهاتف عند الدخول لزيادة حماية حساب الطالب',
                                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: is2FaEnabled,
                            thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
                              if (states.contains(WidgetState.selected)) {
                                return const Color(0xFF00F2FE);
                              }
                              return Colors.grey;
                            }),
                            activeTrackColor: const Color(0xFF00F2FE).withValues(alpha: 0.3),
                            onChanged: _isUpdating2fa
                                ? null
                                : (newVal) => _handleStudent2FaToggle(context, newVal, liveData),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 4. Notifications & Alerts Settings
              _buildSectionTitle('إعدادات الإشعارات والتنبيهات 📢'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    // Test notification chime
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          HapticFeedback.mediumImpact();
                          StudentNotificationSoundService.instance.playInAppFeedback(isMessage: false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🔔 تم تشغيل نغمة الإشعار المخصصة (Gentle Chime)'),
                              backgroundColor: Color(0xFF00F2FE),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.volume_up_rounded, color: Color(0xFF38BDF8), size: 22),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'تجربة صوت الإشعارات 🔔',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textLight),
                                    ),
                                    SizedBox(height: 2),
                                    Text('اضغط هنا لسماع نغمة تنبيهات الحصص والدرجات', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                  ],
                                ),
                              ),
                              Icon(Icons.play_circle_fill_rounded, size: 24, color: Color(0xFF38BDF8)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: AppTheme.darkCardBorder),

                    // Open Notification Center Button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StudentNotificationsScreen(),
                            ),
                          );
                        },
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.notifications_active_rounded, color: Color(0xFF00F2FE), size: 22),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'فتح مركز الإشعارات والتنبيهات 📢',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textLight),
                                    ),
                                    SizedBox(height: 2),
                                    Text('استعراض كافة الإعلانات والواجبات ورصد الدرجات', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: AppTheme.textMuted),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 5. App Theme & Appearance Section
              _buildSectionTitle('مظهر التطبيق والتصميم 🎨'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    // Theme 1: Active
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.dark_mode_rounded, color: Color(0xFF00F2FE), size: 22),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'الوضع الليلي الملكي الفاخر (Obsidian & Cyan)',
                                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppTheme.textLight),
                                ),
                                SizedBox(height: 2),
                                Text('النمط المعتمد عالي التباين والمريح للعين', style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('مفعل ✅', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF10B981))),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppTheme.darkCardBorder),

                    // Theme 2: Bento Grid Style
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.grid_view_rounded, color: Color(0xFF8B5CF6), size: 22),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'تصميم بينتو الزجاجي (Bento Frost Grid)',
                                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppTheme.textLight),
                                ),
                                SizedBox(height: 2),
                                Text('تصور واجهات زجاجية نيونية بديلة', style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('تصور متاح ✨', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF8B5CF6))),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 6. System Updates & App Info
              _buildSectionTitle('تحديثات النظام والإصدار 🔄'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.darkCardBorder),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(Icons.info_outline_rounded, 'إصدار التطبيق', 'v1.0.29+3011'),
                    const Divider(height: 1, color: AppTheme.darkCardBorder),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          StudentUpdateService.instance.checkForUpdate(context, showNoUpdateToast: true);
                        },
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.system_update_rounded, color: Color(0xFF00F2FE), size: 22),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'فحص التحديثات السحابية الآن',
                                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF00F2FE)),
                                ),
                              ),
                              Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF00F2FE)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 4. Read-Only Notice
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'التطبيق في وضع الاطلاع الأكاديمي المباشر لولي الأمر والطالب، ولا يسمح بتعديل الدرجات أو السجلات الدراسية.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 5. Logout Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger.withValues(alpha: 0.15),
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _handleLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text(
                    'تسجيل الخروج من الحساب',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: AppTheme.textLight,
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textMuted),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }
}
