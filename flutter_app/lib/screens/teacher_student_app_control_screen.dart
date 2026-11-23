import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/cloud_sync_service.dart';
import '../core/database/database_service.dart';
import '../core/teacher_update_service.dart';
import '../core/whatsapp_service.dart';
import 'student_app_link_screen.dart';
import 'teacher_materials_hub_screen.dart';

class TeacherStudentAppControlScreen extends StatefulWidget {
  final DatabaseService? database;

  const TeacherStudentAppControlScreen({
    super.key,
    this.database,
  });

  @override
  State<TeacherStudentAppControlScreen> createState() =>
      _TeacherStudentAppControlScreenState();
}

class _TeacherStudentAppControlScreenState
    extends State<TeacherStudentAppControlScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'all'; // all, custom_pin, default_pin, 2fa_on, 2fa_off
  final Set<String> _revealedPins = {};
  bool _isSyncing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// مزامنة الطلاب يدوياً مع السحابة للتأكد من اكتمال كافة البيانات
  Future<void> _syncStudentsNow() async {
    setState(() => _isSyncing = true);
    HapticFeedback.lightImpact();
    try {
      await CloudSyncService.instance.syncStudents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت مزامنة بيانات الطلاب مع السحابة بنجاح ☁️'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء المزامنة: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// حساب الرمز السري الافتراضي للطالب (آخر 4 أرقام من الهاتف أو الكود)
  String _calculateDefaultPin(Map<String, dynamic> data) {
    final pPhone = (data['parent_phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    final sPhone = (data['student_phone'] ?? data['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    if (pPhone.length >= 4) {
      return pPhone.substring(pPhone.length - 4);
    }
    if (sPhone.length >= 4) {
      return sPhone.substring(sPhone.length - 4);
    }
    final sCode = (data['student_code'] ?? data['id'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    if (sCode.isNotEmpty) {
      return sCode;
    }
    return '1234';
  }

  /// تبديل حالة المصادقة الثنائية مع إجبارية رقم الهاتف وإرسال رسالة تأكيد عبر واتساب
  Future<void> _handle2FaToggle(String docId, bool is2FaCurrentlyEnabled, Map<String, dynamic> data) async {
    HapticFeedback.selectionClick();
    if (is2FaCurrentlyEnabled) {
      // Deactivating 2FA
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF0F172A) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('إيقاف المصادقة الثنائية 2FA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Text('هل ترغب في تعطيل التحقق بالهاتف للطالب (${data['full_name'] ?? docId})؟ سيتمكن الطالب من الدخول بالرمز السري فقط دون تأكيد رقم الهاتف.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تعطيل 2FA'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await FirebaseFirestore.instance
            .collection('academies')
            .doc('default')
            .collection('students')
            .doc(docId)
            .set({
          'require_2fa': false,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تعطيل المصادقة الثنائية 🔓'),
              backgroundColor: Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      return;
    }

    // Activating 2FA: Phone number is MANDATORY + Send WhatsApp message
    final sPhone = (data['student_phone'] ?? data['phone'] ?? '').toString().trim();
    final pPhone = (data['parent_phone'] ?? '').toString().trim();
    final initialPhone = sPhone.isNotEmpty ? sPhone : pPhone;

    final phoneController = TextEditingController(text: initialPhone);
    final formKey = GlobalKey<FormState>();
    bool isStudentPhoneType = sPhone.isNotEmpty || pPhone.isEmpty;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
            ),
            title: const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تفعيل المصادقة الثنائية (2FA) 🔒',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'لحماية حساب الطالب (${data['full_name'] ?? docId})، يجب تسجيل رقم هاتف معتمد (إجباري) للتحقق وإرسال رسالة تأكيد عبر واتساب:',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Phone input field (MANDATORY)
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'رقم هاتف التحقق (إجباري) *',
                        hintText: '01xxxxxxxxx',
                        prefixIcon: const Icon(Icons.phone_android_rounded, color: Color(0xFF10B981)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
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
                    const SizedBox(height: 10),

                    // Phone owner type
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => isStudentPhoneType = true),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isStudentPhoneType
                                    ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
                                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isStudentPhoneType ? const Color(0xFF00F2FE) : Colors.transparent,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'هاتف الطالب',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isStudentPhoneType ? FontWeight.bold : FontWeight.normal,
                                    color: isStudentPhoneType ? const Color(0xFF00F2FE) : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => isStudentPhoneType = false),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: !isStudentPhoneType
                                    ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
                                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: !isStudentPhoneType ? const Color(0xFF00F2FE) : Colors.transparent,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'ولي الأمر',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: !isStudentPhoneType ? FontWeight.bold : FontWeight.normal,
                                    color: !isStudentPhoneType ? const Color(0xFF00F2FE) : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

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
                              'سيقوم التطبيق بإرسال رسالة تأكيد رسمية عبر الواتساب إلى هذا الرقم فور التفعيل.',
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('تأكيد وإرسال واتساب 💬', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  if (formKey.currentState?.validate() ?? false) {
                    final cleanPhone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
                    Navigator.pop(ctx);

                    // 1. Save in Firestore
                    final updateData = <String, dynamic>{
                      'require_2fa': true,
                      'two_fa_verified_phone': cleanPhone,
                      'phone': cleanPhone,
                      if (isStudentPhoneType) 'student_phone': cleanPhone else 'parent_phone': cleanPhone,
                      'updated_at': FieldValue.serverTimestamp(),
                    };

                    await FirebaseFirestore.instance
                        .collection('academies')
                        .doc('default')
                        .collection('students')
                        .doc(docId)
                        .set(updateData, SetOptions(merge: true));

                    // 2. Update in SQLite if available
                    if (widget.database != null) {
                      try {
                        final student = await widget.database!.findStudentById(docId);
                        if (student != null) {
                          final updated = student.copyWith(
                            studentPhone: isStudentPhoneType ? cleanPhone : student.studentPhone,
                            parentPhone: !isStudentPhoneType ? cleanPhone : student.parentPhone,
                          );
                          await widget.database!.saveStudent(updated);
                        }
                      } catch (_) {}
                    }

                    // 3. Send WhatsApp Confirmation Message
                    final sName = (data['full_name'] ?? 'الطالب').toString();
                    final sCode = (data['student_code'] ?? docId).toString();
                    final sPin = (data['pin_code'] ?? _calculateDefaultPin(data)).toString();

                    final confirmMsg = '''
🔐 *تأكيد تفعيل المصادقة الثنائية (2FA) - تطبيق Edu Academy*

مرحباً بك،
تم بنجاح تفعيل نظام التحقق برقم الهاتف لحساب الطالب:
👤 *اسم الطالب:* $sName
🆔 *كود الطالب:* $sCode
🔒 *الرمز السري (PIN):* $sPin
📱 *رقم الهاتف المعتمد للدخول:* $cleanPhone

━━━━━━━━━━━━━━━━━━
⚠️ *تنبيه أمان:* تم تأمين الحساب ولن يتمكن أي شخص من فتح التطبيق إلا بإدخال هذا الرقم المعتمد والرمز السري.
نتمنى لكم دوام التفوق والنجاح! 🌟
''';

                    await WhatsAppService.openWhatsApp(
                      phone: cleanPhone,
                      message: confirmMsg,
                      database: widget.database,
                      studentId: docId,
                      studentName: sName,
                      category: 'security',
                    );

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم تفعيل المصادقة الثنائية وجاري إرسال رسالة التأكيد عبر واتساب 💬'),
                          backgroundColor: Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// تعديل كود الطالب ليصبح مكوناً من 5 أرقام مع التحديث في قاعدة البيانات والسحابة
  Future<void> _editStudentCode(String docId, Map<String, dynamic> data) async {
    final currentCode = (data['student_code'] ?? docId).toString().replaceAll(RegExp(r'\D'), '');
    final studentName = (data['full_name'] ?? 'الطالب').toString();

    // Default suggestion is random 5 digits if not already 5 digits
    String suggested = currentCode;
    if (suggested.length != 5) {
      if (widget.database != null) {
        suggested = await widget.database!.generateUniqueRandom5DigitCode();
      } else {
        suggested = '${10000 + Random().nextInt(90000)}';
      }
    }

    final codeCtrl = TextEditingController(text: suggested);
    final formKey = GlobalKey<FormState>();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF00F2FE), width: 1.2),
          ),
          title: const Row(
            children: [
              Icon(Icons.casino_rounded, color: Color(0xFF00F2FE)),
              SizedBox(width: 8),
              Expanded(
                child: Text('كود عشوائي للطالب (5 أرقام) 🎲', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تعديل كود تسجيل الدخول الخاص بالطالب: ($studentName)', style: TextStyle(fontSize: 12.5, color: isDark ? const Color(0xFFCBD5E1) : Colors.black87)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2),
                  decoration: InputDecoration(
                    labelText: 'كود الطالب (5 أرقام عشوائية) *',
                    hintText: 'مثال: 48291',
                    prefixIcon: const Icon(Icons.badge_rounded, color: Color(0xFF00F2FE)),
                    suffixIcon: IconButton(
                      tooltip: 'توليد كود عشوائي جديد 🎲',
                      icon: const Icon(Icons.casino_rounded, color: Color(0xFF00F2FE)),
                      onPressed: () async {
                        final r = widget.database != null
                            ? await widget.database!.generateUniqueRandom5DigitCode()
                            : '${10000 + Random().nextInt(90000)}';
                        codeCtrl.text = r;
                      },
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (val) {
                    final clean = (val ?? '').trim().replaceAll(RegExp(r'\D'), '');
                    if (clean.length != 5) {
                      return 'يجب أن يتكون كود الطالب من 5 أرقام بالضبط (مثال: 48291)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                const Text('🎲 الكود العشوائي غير المسلسل يمنع التخمين ويزيد من خصوصية حساب الطالب.', style: TextStyle(fontSize: 10.5, color: Colors.grey)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00F2FE), foregroundColor: Colors.black87),
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final newCode = codeCtrl.text.trim();
                  Navigator.pop(ctx);

                  try {
                    final rawId = (data['id'] ?? docId).toString();

                    // 1. Update SQLite cascade
                    if (widget.database != null) {
                      await widget.database!.updateStudentIdCascade(rawId, newCode);
                      if (rawId != docId) {
                        await widget.database!.updateStudentIdCascade(docId, newCode);
                      }
                    }

                    // 2. Update Firestore
                    final firestore = FirebaseFirestore.instance;
                    final col = firestore.collection('academies').doc('default').collection('students');

                    final oldDoc = await col.doc(docId).get();
                    Map<String, dynamic> docData = {};
                    if (oldDoc.exists && oldDoc.data() != null) {
                      docData = Map<String, dynamic>.from(oldDoc.data()!);
                    } else {
                      docData = Map<String, dynamic>.from(data);
                    }
                    docData['id'] = newCode;
                    docData['student_code'] = newCode;
                    docData['updated_at'] = FieldValue.serverTimestamp();

                    await col.doc(newCode).set(docData, SetOptions(merge: true));

                    if (docId != newCode) {
                      await col.doc(docId).delete();
                    }
                    if (rawId != newCode && rawId != docId) {
                      await col.doc(rawId).delete();
                    }

                    // 3. مزامنة فورية لتحديث قاعدة البيانات
                    try {
                      await CloudSyncService.instance.syncStudents();
                    } catch (_) {}

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم تعديل كود الطالب إلى ($newCode) وحفظه بنجاح 🔢'),
                          backgroundColor: const Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint('Error saving student code: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء حفظ الكود: $e'),
                          backgroundColor: const Color(0xFFEF4444),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('حفظ الكود 5 أرقام', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// ترقية وتحويل كافة أكواد الطلاب إلى 5 أرقام عشوائية غير مسلسلة
  Future<void> _batchUpgradeAllTo5Digits() async {
    if (widget.database == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.casino_rounded, color: Color(0xFF00F2FE)),
            SizedBox(width: 8),
            Text('توليد أكواد عشوائية (5 أرقام) 🎲', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          'سيتم تعيين أكواد عشوائية فريدة وغير مسلسلة مكونة من 5 أرقام (مثال: 48291, 71053) لجميع الطلاب.\nسيتم تحديث سجلات الحضور والامتحانات والمصروفات ومزامنة السحابة تلقائياً دون أي فقدان للبيانات.\n\nهل ترغب في البدء؟',
          style: TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00F2FE), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('بدء الترقية 🚀'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSyncing = true);
      try {
        final count = await widget.database!.renumberAllStudentsTo5Digits();
        await CloudSyncService.instance.syncStudents();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تمت ترقية $count طالباً إلى أكواد الـ 5 أرقام ومزامنة السحابة بنجاح 🚀'),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ أثناء الترقية: $e'), backgroundColor: const Color(0xFFEF4444)),
          );
        }
      } finally {
        if (mounted) setState(() => _isSyncing = false);
      }
    }
  }

  /// إعادة تعيين الرمز السري للرمز الافتراضي (Reset PIN)
  Future<void> _resetPin(String docId, String studentName, String defaultPin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark
            ? const Color(0xFF0F172A)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Row(
          children: [
            Icon(Icons.restart_alt_rounded, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text('إعادة تعيين الرمز السري', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'هل ترغب في إعادة تعيين الرمز السري للطالب ($studentName)؟\n\n'
          'سيتم إلغاء الرمز المخصص وسيعود الرمز تلقائياً إلى الرمز المبدئي:\n'
          '🔑 [$defaultPin]',
          style: const TextStyle(height: 1.5, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، إعادة التعيين', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedback.mediumImpact();
      try {
        await FirebaseFirestore.instance
            .collection('academies')
            .doc('default')
            .collection('students')
            .doc(docId)
            .update({
          'pin_code': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تمت إعادة تعيين الرمز السري للطالب $studentName بنجاح 🔄'),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ أثناء إعادة التعيين: $e'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    }
  }

  /// تعيين رمز سري جديد ومخصص للطالب
  Future<void> _setCustomPin(String docId, String studentName, String? currentPin) async {
    final pinController = TextEditingController(text: currentPin ?? '');
    String? dialogError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF334155)),
            ),
            title: Row(
              children: [
                const Icon(Icons.key_rounded, color: Color(0xFF00F2FE)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تعيين رمز سري للطالب: $studentName',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'أدخل الرمز السري الجديد المكون من 4 أرقام أو حروف على الأقل:',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                if (dialogError != null) ...[
                  Text(
                    dialogError!,
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: pinController,
                  autofocus: true,
                  keyboardType: TextInputType.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: isDark ? const Color(0xFF00F2FE) : const Color(0xFF0284C7),
                  ),
                  decoration: InputDecoration(
                    hintText: 'مثال: 5544 أو s2026',
                    hintStyle: const TextStyle(letterSpacing: 1, fontSize: 13, color: Colors.grey),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F2FE),
                  foregroundColor: const Color(0xFF050B14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final newPin = pinController.text.trim();
                  if (newPin.length < 4) {
                    setDialogState(() => dialogError = 'يجب أن يتكون الرمز من 4 خانات على الأقل');
                    return;
                  }

                  Navigator.pop(ctx);
                  HapticFeedback.mediumImpact();
                  try {
                    await FirebaseFirestore.instance
                        .collection('academies')
                        .doc('default')
                        .collection('students')
                        .doc(docId)
                        .set({
                      'pin_code': newPin,
                      'updated_at': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم تعيين الرمز السري الجديد ($newPin) بنجاح 🔒'),
                          backgroundColor: const Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء حفظ الرمز: $e'),
                          backgroundColor: const Color(0xFFEF4444),
                        ),
                      );
                    }
                  }
                },
                child: const Text('حفظ الرمز السري', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// فتح نافذة إدارة ونشر تحديثات تطبيق الطالب لجميع الهواتف
  Future<void> _openAppUpdatePublishDialog() async {
    HapticFeedback.lightImpact();

    DocumentSnapshot<Map<String, dynamic>>? configSnap;
    try {
      configSnap = await FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('system_config')
          .doc('student_app_version')
          .get();
    } catch (_) {}

    final data = configSnap?.data() ?? {};
    final currentCode = int.tryParse('${data['latest_version_code'] ?? 1}') ?? 1;
    final currentName = (data['latest_version_name'] ?? '1.0.0').toString();
    final currentUrl = (data['download_url'] ?? '').toString();
    final currentNotes = (data['release_notes'] ?? '• تحديثات شاملة في قسم التقارير والحصص\n• سرعة واستقرار أعلى للتطبيق').toString();
    bool isMandatory = data['is_mandatory'] == true;

    final nameController = TextEditingController(text: currentName);
    final codeController = TextEditingController(text: (currentCode + 1).toString());
    final urlController = TextEditingController(text: currentUrl);
    final notesController = TextEditingController(text: currentNotes);
    bool isSaving = false;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Color(0xFF00F2FE), width: 1.2),
            ),
            title: const Row(
              children: [
                Icon(Icons.rocket_launch_rounded, color: Color(0xFF00F2FE), size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'نشر تحديث جديد لتطبيق الطالب 🚀',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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
                    'بمجرد نشر التحديث، سيظهر إشعار فوري لجميع الطلاب لتحميل وتثبيت التحديث تلقائياً دون فقدان بياناتهم:',
                    style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 16),

                  // رقم الإصدار ورقم البناء
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            labelText: 'رقم الإصدار (Version)',
                            hintText: '1.1.0',
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: codeController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'كود البناء',
                            hintText: '2',
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // رابط تحميل الـ APK المباشر
                  TextField(
                    controller: urlController,
                    decoration: InputDecoration(
                      labelText: 'رابط تحميل ملف APK المباشر 🔗',
                      hintText: 'https://...',
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.link_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ملاحظات التحديث
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'ما الجديد في هذا التحديث (Release Notes)',
                      hintText: 'اكتب التعديلات التي ستظهر للطالب...',
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // مفتاح التحديث الإجباري
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تحديث إجباري (Mandatory) ⚠️',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'يمنع استخدام التطبيق القديم حتى التحديث',
                              style: TextStyle(fontSize: 10.5, color: Colors.grey),
                            ),
                          ],
                        ),
                        Switch(
                          value: isMandatory,
                          activeThumbColor: const Color(0xFF00F2FE),
                          onChanged: (val) {
                            setDialogState(() => isMandatory = val);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F2FE),
                  foregroundColor: const Color(0xFF04101E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: const Text('نشر التحديث للطلاب فوراً 📢', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: isSaving
                    ? null
                    : () async {
                        final vName = nameController.text.trim();
                        final vCode = int.tryParse(codeController.text.trim()) ?? (currentCode + 1);
                        final vUrl = urlController.text.trim();
                        final vNotes = notesController.text.trim();

                        if (vUrl.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('يرجى وضع رابط تحميل ملف الـ APK المباشر'),
                              backgroundColor: Color(0xFFEF4444),
                            ),
                          );
                          return;
                        }

                        setDialogState(() => isSaving = true);
                        try {
                          await FirebaseFirestore.instance
                              .collection('academies')
                              .doc('default')
                              .collection('system_config')
                              .doc('student_app_version')
                              .set({
                            'latest_version_name': vName,
                            'latest_version_code': vCode,
                            'download_url': vUrl,
                            'release_notes': vNotes,
                            'is_mandatory': isMandatory,
                            'published_at': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('تم نشر التحديث (v$vName) بنجاح! سيظهر التنبيه التلقائي لجميع الطلاب فوراً 🚀'),
                                backgroundColor: const Color(0xFF10B981),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('فشل نشر التحديث: $e'),
                                backgroundColor: const Color(0xFFEF4444),
                              ),
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  /// إرسال بيانات الدخول للطالب أو ولي أمره عبر الواتساب
  Future<void> _shareCredentialsViaWhatsApp({
    required String studentName,
    required String studentCode,
    required String pin,
    required String phone,
    required bool is2Fa,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد رقم هاتف مسجل لهذا الطالب لإرسال البيانات إليه'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final message = '''
🎓 *بيانات تسجيل الدخول لتطبيق الطالب - Edu Academy*

مرحباً بك، إليك بيانات الدخول الرسمية الخاصة بالطالب:
👤 *اسم الطالب:* $studentName
🆔 *كود الطالب:* $studentCode
🔒 *الرمز السري (PIN):* $pin
🛡️ *المصادقة الثنائية:* ${is2Fa ? 'مفعلة (يمكنك كتابة رقم الهاتف للتحقق)' : 'معطلة (الدخول بالكود والرمز السري فقط)'}

📲 *لتحميل وتثبيت التطبيق على هاتفك:*
تأكد من فتح تطبيق الطالب وإدخال الكود والرمز السري كما هو موضح أعلاه.
نتمنى لكم دوام التفوق والنجاح! 🌟
''';

    final encoded = Uri.encodeComponent(message);
    final whatsappUri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encoded');
    final webUri = Uri.parse('https://wa.me/$cleanPhone?text=$encoded');

    try {
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر فتح الواتساب: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phonelink_lock_rounded, color: Color(0xFF00F2FE), size: 22),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'بيانات وتأمين تطبيق الطالب',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'ربط ومعاينة تطبيق الطالب 📱',
            icon: const Icon(Icons.phone_android_rounded, color: Color(0xFF10B981)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentAppLinkScreen(database: widget.database),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'توليد أكواد عشوائية (5 أرقام) 🎲',
            icon: const Icon(Icons.casino_rounded, color: Color(0xFF00F2FE)),
            onPressed: _batchUpgradeAllTo5Digits,
          ),
          IconButton(
            tooltip: 'أدوات التحديث السحابي والمذكرات 🚀',
            icon: const Icon(Icons.rocket_launch_rounded, color: Color(0xFF00F2FE)),
            onPressed: () => _showPublishAndMaterialsMenu(context),
          ),
          IconButton(
            tooltip: 'مزامنة مع السحابة فوراً',
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F2FE)),
                  )
                : const Icon(Icons.sync_rounded, color: Color(0xFF00F2FE)),
            onPressed: _isSyncing ? null : _syncStudentsNow,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('academies')
            .doc('default')
            .collection('students')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00F2FE)),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          final allStudents = docs.map((d) {
            final data = d.data();
            data['doc_id'] = d.id;
            return data;
          }).toList();

          // فرز الطلاب تصاعدياً حسب الكود أو الاسم
          allStudents.sort((a, b) {
            final codeA = int.tryParse((a['student_code'] ?? '').toString()) ?? 999999;
            final codeB = int.tryParse((b['student_code'] ?? '').toString()) ?? 999999;
            return codeA.compareTo(codeB);
          });

          // تصفية حسب البحث
          final filteredStudents = allStudents.where((s) {
            final name = (s['full_name'] ?? '').toString().toLowerCase();
            final code = (s['student_code'] ?? s['id'] ?? '').toString().toLowerCase();
            final phone = (s['phone'] ?? s['student_phone'] ?? '').toString();
            final pPhone = (s['parent_phone'] ?? '').toString();
            final q = _searchQuery.toLowerCase().trim();

            final matchesQuery = q.isEmpty ||
                name.contains(q) ||
                code.contains(q) ||
                phone.contains(q) ||
                pPhone.contains(q);

            if (!matchesQuery) return false;

            // فلترة الحالة
            final hasCustomPin = (s['pin_code'] ?? '').toString().trim().isNotEmpty;
            final is2FaOn = s['require_2fa'] != false; // default true

            if (_selectedFilter == 'custom_pin') return hasCustomPin;
            if (_selectedFilter == 'default_pin') return !hasCustomPin;
            if (_selectedFilter == '2fa_on') return is2FaOn;
            if (_selectedFilter == '2fa_off') return !is2FaOn;

            return true;
          }).toList();

          // الإحصائيات
          final totalCount = allStudents.length;
          final customPinCount = allStudents.where((s) => (s['pin_code'] ?? '').toString().trim().isNotEmpty).length;
          final twoFaDisabledCount = allStudents.where((s) => s['require_2fa'] == false).length;

          return Column(
            children: [
              // 1. شريط البحث السريع المدمج مع عداد الطلاب الذكي
              _buildCompactSearchBar(
                totalCount: totalCount,
                filteredCount: filteredStudents.length,
                isDark: isDark,
              ),

              // 2. فلاتر سريعة ومختصرة بنقرة واحدة
              _buildSlimFilterChips(
                totalCount: totalCount,
                customPinCount: customPinCount,
                twoFaDisabledCount: twoFaDisabledCount,
                isDark: isDark,
              ),

              // 3. قائمة الطلاب مباشرة وبكامل وضوحها
              Expanded(
                child: filteredStudents.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded, size: 54, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'لا توجد نتائج مطابقة لبحثك'
                                  : 'لا يوجد طلاب مسجلون في السحابة حتى الآن',
                              style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                            if (allStudents.isEmpty) ...[
                              const SizedBox(height: 14),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F2FE), foregroundColor: Colors.black),
                                onPressed: _syncStudentsNow,
                                icon: const Icon(Icons.cloud_upload_rounded),
                                label: const Text('مزامنة الطلاب من قاعدة البيانات المحلية'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        itemCount: filteredStudents.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final student = filteredStudents[index];
                          return _buildStudentCard(student, isDark);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPublishAndMaterialsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'أدوات التحديث السحابي والمذكرات 🚀',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.phone_android_rounded, color: Color(0xFF10B981)),
                  ),
                  title: const Text('ربط ومعاينة تطبيق الطالب 📱', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('كود السنتر الموحد، مفاتيح التحكم بالظهور، والمحاكي المباشر', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentAppLinkScreen(database: widget.database),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.school_rounded, color: Color(0xFF00F2FE)),
                  ),
                  title: const Text('نشر تحديث لتطبيق الطالب 📱', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('إرسال تحديث سحابي فوري (OTA) لهواتف الطلاب', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openAppUpdatePublishDialog();
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_pin_rounded, color: Color(0xFF38BDF8)),
                  ),
                  title: const Text('نشر تحديث لتطبيق المعلم 👨‍🏫', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('إرسال إشعار تحديث المعلم لكافة الأجهزة', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(ctx);
                    TeacherUpdateService.showPublishTeacherUpdateDialog(context);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFF59E0B)),
                  ),
                  title: const Text('مكتبة مذكرات الحصص وملفات الـ PDF 📚', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('إدارة الملفات والملازم المتاحة للطلاب في التطبيق', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (widget.database != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherMaterialsHubScreen(
                            database: widget.database!,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactSearchBar({
    required int totalCount,
    required int filteredCount,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'بحث باسم الطالب، الكود، أو الهاتف...',
                  hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00F2FE), size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00F2FE), width: 1.4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
              ),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_alt_rounded, size: 16, color: Color(0xFF00F2FE)),
                  const SizedBox(width: 4),
                  Text(
                    _searchQuery.isNotEmpty ? '$filteredCount / $totalCount' : '$totalCount طالب',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: Color(0xFF00F2FE),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlimFilterChips({
    required int totalCount,
    required int customPinCount,
    required int twoFaDisabledCount,
    required bool isDark,
  }) {
    final defaultPinCount = totalCount - customPinCount;
    final filters = [
      {'id': 'all', 'label': 'الكل ($totalCount)'},
      {'id': 'custom_pin', 'label': 'باسورد مخصص ($customPinCount) 🔑'},
      {'id': 'default_pin', 'label': 'افتراضي ($defaultPinCount) 🔄'},
      if (twoFaDisabledCount > 0)
        {'id': '2fa_off', 'label': '2FA معطلة ($twoFaDisabledCount) 🔓'}
      else
        {'id': '2fa_on', 'label': '2FA مؤمن 🔒'},
    ];

    return Container(
      height: 32,
      margin: const EdgeInsets.fromLTRB(0, 2, 0, 6),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final f = filters[index];
          final isSelected = _selectedFilter == f['id'];
          return ChoiceChip(
            label: Text(f['label']!),
            labelStyle: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.black : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            selected: isSelected,
            selectedColor: const Color(0xFF00F2FE),
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            side: BorderSide(
              color: isSelected
                  ? const Color(0xFF00F2FE)
                  : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
            ),
            onSelected: (val) {
              if (val) setState(() => _selectedFilter = f['id']!);
            },
          );
        },
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student, bool isDark) {
    final docId = student['doc_id'] as String;
    final name = (student['full_name'] ?? 'طالب بدون اسم').toString();
    final rawCode = (student['student_code'] ?? student['id'] ?? docId).toString();
    final grade = (student['grade'] ?? '').toString();
    final stage = (student['stage'] ?? '').toString();
    final sPhone = (student['student_phone'] ?? student['phone'] ?? '').toString();
    final pPhone = (student['parent_phone'] ?? '').toString();
    final preferredPhone = pPhone.isNotEmpty ? pPhone : sPhone;

    final storedPin = (student['pin_code'] ?? '').toString().trim();
    final hasCustomPin = storedPin.isNotEmpty;
    final defaultPin = _calculateDefaultPin(student);
    final effectivePin = hasCustomPin ? storedPin : defaultPin;

    final is2FaEnabled = student['require_2fa'] != false;
    final isPinRevealed = _revealedPins.contains(docId);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasCustomPin
              ? const Color(0xFF00F2FE).withValues(alpha: 0.35)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          width: hasCustomPin ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Student Code Badge + Name + 2FA Switch
            Row(
              children: [
                // Glowing Code Badge (Click to Edit 5-Digit Code)
                Tooltip(
                  message: 'تعديل كود الطالب (5 أرقام)',
                  child: InkWell(
                    onTap: () => _editStudentCode(docId, student),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'كود: $rawCode',
                            style: const TextStyle(
                              color: Color(0xFF00F2FE),
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit_rounded, size: 12, color: Color(0xFF00F2FE)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Name & Grade
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (grade.isNotEmpty || stage.isNotEmpty)
                        Text(
                          '$grade ${stage.isNotEmpty ? '• $stage' : ''}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Row 2: PIN Details & Status
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasCustomPin ? Icons.vpn_key_rounded : Icons.lock_clock_rounded,
                    size: 18,
                    color: hasCustomPin ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            text: hasCustomPin ? 'الرمز السري المخصص: ' : 'الرمز السري الافتراضي: ',
                            style: const TextStyle(fontSize: 11.5, color: Colors.grey, fontWeight: FontWeight.bold),
                            children: [
                              TextSpan(
                                text: isPinRevealed ? effectivePin : '••••',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: isPinRevealed ? 2 : 3,
                                  color: hasCustomPin ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B),
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          hasCustomPin
                              ? 'تم تعيينه أو تحديثه بواسطة الطالب/المعلم'
                              : 'آخر 4 أرقام من هاتف ولي الأمر أو الكود',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Eye Toggle Button
                  IconButton(
                    tooltip: isPinRevealed ? 'إخفاء' : 'إظهار الرمز',
                    icon: Icon(
                      isPinRevealed ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 18,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        if (isPinRevealed) {
                          _revealedPins.remove(docId);
                        } else {
                          _revealedPins.add(docId);
                        }
                      });
                    },
                  ),
                  // Copy Button
                  IconButton(
                    tooltip: 'نسخ الرمز',
                    icon: const Icon(Icons.copy_rounded, size: 17, color: Colors.grey),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: effectivePin));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم نسخ الرمز ($effectivePin) للحافظة 📋'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Row 3: 2FA Toggle Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: is2FaEnabled
                    ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.12 : 0.08)
                    : const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: is2FaEnabled
                      ? const Color(0xFF10B981).withValues(alpha: 0.3)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    is2FaEnabled ? Icons.verified_user_rounded : Icons.phonelink_erase_rounded,
                    size: 16,
                    color: is2FaEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          is2FaEnabled ? 'المصادقة الثنائية (2FA): مفعلة' : 'المصادقة الثنائية (2FA): معطلة',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: is2FaEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          is2FaEnabled
                            ? 'يتم التحقق من مطابقة رقم الهاتف إذا كتبه الطالب'
                            : 'يدخل الطالب فوراً بالكود والباسورد بدون التحقق من الهاتف',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: 0.78,
                    child: Switch(
                      value: is2FaEnabled,
                      activeThumbColor: const Color(0xFF10B981),
                      activeTrackColor: const Color(0xFF10B981).withValues(alpha: 0.35),
                      inactiveTrackColor: Colors.grey.shade800,
                      onChanged: (_) => _handle2FaToggle(docId, is2FaEnabled, student),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Row 4: Action Buttons (Reset PIN, Set Custom PIN, WhatsApp)
            Row(
              children: [
                // Set Custom PIN
                Expanded(
                  flex: hasCustomPin ? 3 : 1,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      side: const BorderSide(color: Color(0xFF00F2FE)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF00F2FE)),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'تعيين باسورد',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                      ),
                    ),
                    onPressed: () => _setCustomPin(docId, name, hasCustomPin ? storedPin : null),
                  ),
                ),
                const SizedBox(width: 6),

                // Reset to Default PIN
                if (hasCustomPin) ...[
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.restart_alt_rounded, size: 14, color: Color(0xFFF59E0B)),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'ريسيت',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                        ),
                      ),
                      onPressed: () => _resetPin(docId, name, defaultPin),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // WhatsApp Share
                Expanded(
                  flex: hasCustomPin ? 3 : 1,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.chat_rounded, size: 14),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'إرسال واتساب',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    onPressed: () => _shareCredentialsViaWhatsApp(
                      studentName: name,
                      studentCode: rawCode,
                      pin: effectivePin,
                      phone: preferredPhone,
                      is2Fa: is2FaEnabled,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
