import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentAuthService {
  static final StudentAuthService instance = StudentAuthService._internal();
  StudentAuthService._internal();

  Map<String, dynamic>? currentStudent;
  bool get isAuthenticated => currentStudent != null;

  /// إشعار فوري عند إلغاء الجلسة أو تغيير المعلم للرمز السري لحظياً
  final ValueNotifier<String?> onSessionRevoked = ValueNotifier<String?>(null);
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _studentDocSub;

  static const String _keyIsLoggedIn = 'student_is_logged_in';
  static const String _keyStudentId = 'student_id';
  static const String _keyStudentCode = 'student_code';
  static const String _keyStudentName = 'student_name';
  static const String _keyGroupId = 'student_group_id';
  static const String _keyGrade = 'student_grade';
  static const String _keyStage = 'student_stage';
  static const String _keyPinCode = 'student_pin_code';
  static const String _keyUserRole = 'user_role';

  bool get isParent => currentStudent?['user_role'] == 'parent';

  Future<void> initialize() async {
    // 1. Ensure anonymous Firebase Auth for database rules
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      debugPrint('Auth notice: $e');
    }

    // 2. Load stored session
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_keyIsLoggedIn) ?? false;
    if (isLoggedIn) {
      final sId = prefs.getString(_keyStudentId) ?? '';
      final sCode = prefs.getString(_keyStudentCode) ?? '';
      final sPin = prefs.getString(_keyPinCode) ?? '';

      // التحقق الصارم من وجود رمز سري محفوظ
      if (sId.isEmpty || sPin.isEmpty) {
        await logout();
        return;
      }

      currentStudent = {
        'id': sId,
        'student_code': sCode.isNotEmpty ? sCode : sId,
        'full_name': prefs.getString(_keyStudentName) ?? '',
        'group_id': prefs.getString(_keyGroupId),
        'grade': prefs.getString(_keyGrade) ?? '',
        'stage': prefs.getString(_keyStage) ?? '',
        'pin_code': sPin,
        'user_role': prefs.getString(_keyUserRole) ?? 'student',
      };

      // التحقق الفوري من صحة الرمز السري مع فايربيز وعدم تغييره من المعلم
      try {
        final doc = await FirebaseFirestore.instance
            .collection('academies')
            .doc('default')
            .collection('students')
            .doc(sId)
            .get();

        if (doc.exists && doc.data() != null) {
          final d = doc.data()!;
          final remotePin = (d['pin_code'] ?? d['password'] ?? '').toString().trim();
          if (remotePin.isNotEmpty && remotePin != sPin.trim()) {
            // الرمز تم تغييره من قِبل المعلم! إلغاء فوري للجلسة
            await logout();
            return;
          }

          final sCodeRaw = (d['student_code'] ?? '').toString().trim();
          final code = sCodeRaw.isNotEmpty ? sCodeRaw : (d['id'] ?? doc.id).toString();
          currentStudent!['grade'] = (d['grade'] ?? '').toString();
          currentStudent!['stage'] = (d['stage'] ?? '').toString();
          currentStudent!['student_code'] = code;
          currentStudent!['full_name'] = (d['full_name'] ?? currentStudent!['full_name']).toString();
          currentStudent!['phone'] = (d['phone'] ?? d['student_phone'] ?? '').toString();
          currentStudent!['parent_phone'] = (d['parent_phone'] ?? '').toString();
          currentStudent!['require_2fa'] = d['require_2fa'] != false;

          await prefs.setString(_keyStudentCode, code);
          await prefs.setString(_keyGrade, currentStudent!['grade']);
          await prefs.setString(_keyStage, currentStudent!['stage']);

          // بدء المراقبة اللحظية لتغيير كلمة المرور من طرف المعلم
          startRealtimeSecurityWatcher();
        } else {
          // الحساب غير موجود في قاعدة البيانات
          await logout();
          return;
        }
      } catch (e) {
        debugPrint('Validation check error: $e');
        // في حالة انقطاع النت يتم تشغيل المراقب بمجرد توفر الاتصال
        startRealtimeSecurityWatcher();
      }
    }
  }

  /// مراقبة لحظية صارمة لأي تغيير في بيانات الطالب أو الرمز السري من المعلم
  void startRealtimeSecurityWatcher() {
    _studentDocSub?.cancel();
    if (currentStudent == null) return;
    final studentId = currentStudent!['id'];
    if (studentId == null || '$studentId'.isEmpty) return;

    _studentDocSub = FirebaseFirestore.instance
        .collection('academies')
        .doc('default')
        .collection('students')
        .doc('$studentId')
        .snapshots()
        .listen((docSnap) async {
      if (!docSnap.exists || docSnap.data() == null) {
        await logout();
        onSessionRevoked.value = 'تم إلغاء حساب الطالب أو حذفه من قِبل المعلم.';
        return;
      }

      final data = docSnap.data()!;
      final remotePin = (data['pin_code'] ?? data['password'] ?? '').toString().trim();
      final localPin = currentStudent?['pin_code']?.toString().trim() ?? '';

      // تحديث بيانات البروفايل اللحظية
      if (currentStudent != null) {
        currentStudent!['full_name'] = data['full_name'] ?? currentStudent!['full_name'];
        currentStudent!['require_2fa'] = data['require_2fa'] != false;
        currentStudent!['phone'] = (data['phone'] ?? data['student_phone'] ?? '').toString();
        currentStudent!['parent_phone'] = (data['parent_phone'] ?? '').toString();
        currentStudent!['grade'] = (data['grade'] ?? currentStudent!['grade']).toString();
        currentStudent!['stage'] = (data['stage'] ?? currentStudent!['stage']).toString();
      }

      // التحقق الصارم: إذا قام المعلم بتغيير الرمز السري من لوحة التحكم، يتم قفل التطبيق فوراً
      if (remotePin.isNotEmpty && localPin.isNotEmpty && remotePin != localPin) {
        debugPrint('🔒 [SecurityAlert] Teacher updated student PIN code! Revoking session.');
        await logout();
        onSessionRevoked.value = 'تم تغيير الرمز السري من قِبل المعلم. يرجى إدخال الرمز السري الجديد فوراً 🔒';
      }
    }, onError: (e) {
      debugPrint('Security watcher error: $e');
    });
  }

  /// تسجيل الدخول الآمن بكود الطالب والرمز السري (الخطوة 1) ورقم الهاتف الاختياري (الخطوة 4)
  Future<Map<String, dynamic>> loginSecure({
    required String code,
    required String pin,
    String? phone,
  }) async {
    try {
      final cleanCode = code.trim();
      final cleanPin = pin.trim();

      if (cleanCode.isEmpty) {
        return {'success': false, 'message': 'يرجى إدخال كود الطالب الخاص بك.'};
      }
      if (cleanPin.isEmpty) {
        return {'success': false, 'message': 'يرجى إدخال الرمز السري (PIN).'};
      }

      final cleanLower = cleanCode.toLowerCase();
      final digitsOnly = cleanCode.replaceAll(RegExp(r'\D'), '');

      final firestore = FirebaseFirestore.instance;
      final studentsCol = firestore
          .collection('academies')
          .doc('default')
          .collection('students');

      Map<String, dynamic>? data;
      String? foundDocId;

      // 1. فحص مباشر بالـ Document ID بمختلف الأشكال (101, Std-101, std-101)
      final candidates = [
        cleanCode,
        'Std-$cleanCode',
        'std-$cleanCode',
        cleanLower,
        if (digitsOnly.isNotEmpty) 'Std-$digitsOnly',
      ];

      for (final cand in candidates) {
        if (data != null) break;
        try {
          final docSnap = await studentsCol.doc(cand).get();
          if (docSnap.exists && docSnap.data() != null) {
            data = docSnap.data();
            foundDocId = docSnap.id;
          }
        } catch (_) {}
      }

      // 2. فحص بحقل student_code أو id
      if (data == null) {
        for (final cand in [cleanCode, digitsOnly, ...candidates]) {
          if (cand.isEmpty || data != null) continue;
          try {
            final q1 = await studentsCol.where('student_code', isEqualTo: cand).limit(1).get();
            if (q1.docs.isNotEmpty) {
              data = q1.docs.first.data();
              foundDocId = q1.docs.first.id;
              break;
            }
          } catch (_) {}

          try {
            final q2 = await studentsCol.where('id', isEqualTo: cand).limit(1).get();
            if (q2.docs.isNotEmpty) {
              data = q2.docs.first.data();
              foundDocId = q2.docs.first.id;
              break;
            }
          } catch (_) {}
        }
      }

      // 3. فحص برقم الهاتف
      if (data == null && digitsOnly.length >= 8) {
        try {
          final qPhone = await studentsCol.where('phone', isEqualTo: cleanCode).limit(1).get();
          if (qPhone.docs.isNotEmpty) {
            data = qPhone.docs.first.data();
            foundDocId = qPhone.docs.first.id;
          }
        } catch (_) {}

        if (data == null) {
          try {
            final qParent = await studentsCol.where('parent_phone', isEqualTo: cleanCode).limit(1).get();
            if (qParent.docs.isNotEmpty) {
              data = qParent.docs.first.data();
              foundDocId = qParent.docs.first.id;
            }
          } catch (_) {}
        }
      }

      // 4. فحص شامل في قائمة الطلاب (مرونة كاملة في مطابقة الأرقام أو الأسماء)
      if (data == null) {
        try {
          final allSnap = await studentsCol.limit(250).get();
          for (final doc in allSnap.docs) {
            final d = doc.data();
            final docId = doc.id;
            final docIdDigits = docId.replaceAll(RegExp(r'\D'), '');
            final idVal = (d['id'] ?? '').toString();
            final idDigits = idVal.replaceAll(RegExp(r'\D'), '');
            final sCodeVal = (d['student_code'] ?? '').toString().trim();
            final sCodeDigits = sCodeVal.replaceAll(RegExp(r'\D'), '');
            final sPhone = (d['phone'] ?? d['student_phone'] ?? '').toString();
            final pPhone = (d['parent_phone'] ?? '').toString();

            final bool isMatch = docId.toLowerCase() == cleanLower ||
                idVal.toLowerCase() == cleanLower ||
                (sCodeVal.isNotEmpty && sCodeVal.toLowerCase() == cleanLower) ||
                (digitsOnly.isNotEmpty &&
                    (docIdDigits == digitsOnly || idDigits == digitsOnly || sCodeDigits == digitsOnly)) ||
                (digitsOnly.length >= 8 && (sPhone.contains(digitsOnly) || pPhone.contains(digitsOnly)));

            if (isMatch) {
              data = d;
              foundDocId = doc.id;
              break;
            }
          }
        } catch (_) {}
      }

      if (data == null) {
        return {
          'success': false,
          'message': 'لم يتم العثور على طالب بهذا الكود في المنظومة. تأكد من كودك أو راجع المعلم.',
        };
      }

      // ==========================================
      // [الخطوة 1]: التحقق الصارم من الرمز السري PIN
      // ==========================================
      final storedPin = (data['pin_code'] ?? data['password'] ?? '').toString().trim();
      final pPhoneDigits = (data['parent_phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      final sPhoneDigits = (data['student_phone'] ?? data['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      final rawDocId = (data['id'] ?? foundDocId).toString().replaceAll(RegExp(r'\D'), '');
      final sCodeDigits = (data['student_code'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

      // الرموز المبدئية الافتراضية للطلاب الذين لم يعينوا PIN بعد
      final defaultCandidates = <String>{
        if (pPhoneDigits.length >= 4) pPhoneDigits.substring(pPhoneDigits.length - 4),
        if (sPhoneDigits.length >= 4) sPhoneDigits.substring(sPhoneDigits.length - 4),
        if (rawDocId.isNotEmpty) rawDocId,
        if (sCodeDigits.isNotEmpty) sCodeDigits,
        '1234',
        '123456',
      };

      if (storedPin.isNotEmpty) {
        // تم تعيين رمز سري مسبقاً للطالب: يجب مطابقته بدقة
        if (cleanPin != storedPin) {
          return {
            'success': false,
            'message': 'الرمز السري (PIN) غير صحيح! تأكد من الرمز أو تواصل مع المعلم لاستعادته.',
          };
        }
      } else {
        // لم يتم تعيين PIN بعد (تسجيل الدخول للمرة الأولى)
        // نقبل أي رمز مكون من 4 أرقام فأكثر أو يطابق البدائل الذكية، ويتم اعتماده كـ PIN جديد للطالب
        final isValidInitialPin = defaultCandidates.contains(cleanPin) || cleanPin.length >= 4;
        if (!isValidInitialPin) {
          return {
            'success': false,
            'message': 'الرمز السري المبدئي غير صالح. أدخل 4 أرقام على الأقل (أو آخر 4 أرقام من هاتف ولي الأمر).',
          };
        }

        // حفظ هذا الرمز كـ PIN رسمي للطالب في Firestore
        try {
          if (foundDocId != null) {
            await studentsCol.doc(foundDocId).set({
              'pin_code': cleanPin,
            }, SetOptions(merge: true));
          }
        } catch (e) {
          debugPrint('Notice saving initial pin: $e');
        }
      }

      // ==========================================
      // [الخطوة 4]: التحقق من رقم الهاتف (المصادقة الثنائية 2FA)
      // ==========================================
      final is2FaEnabled = data['require_2fa'] != false;
      if (is2FaEnabled && phone != null && phone.trim().isNotEmpty) {
        final cleanPhone = phone.trim().replaceAll(RegExp(r'\D'), '');
        if (cleanPhone.length >= 4) {
          final sPhone = (data['student_phone'] ?? data['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
          final pPhone = (data['parent_phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
          if (sPhone.isNotEmpty || pPhone.isNotEmpty) {
            final isPhoneMatch = (sPhone.isNotEmpty && sPhone.contains(cleanPhone)) ||
                (pPhone.isNotEmpty && pPhone.contains(cleanPhone));
            if (!isPhoneMatch) {
              return {
                'success': false,
                'message': 'رقم الهاتف المدخل غير مطابق لهاتف الطالب أو ولي الأمر المسجل لدى المعلم.',
              };
            }
          }
        }
      }

      // ==========================================
      // اعتماد الجلسة وحفظها محلياً
      // ==========================================
      final studentId = (data['id'] ?? foundDocId).toString();
      final sCodeRaw = (data['student_code'] ?? '').toString().trim();
      final numFallback = studentId.replaceAll(RegExp(r'\D'), '');
      final studentCode = sCodeRaw.isNotEmpty
          ? sCodeRaw
          : (numFallback.isNotEmpty ? numFallback : studentId);
      final fullName = (data['full_name'] ?? 'طالب أكاديمية إديو').toString();
      final groupId = (data['group_id'] ?? '').toString();
      final grade = (data['grade'] ?? '').toString();
      final stage = (data['stage'] ?? '').toString();

      currentStudent = {
        'id': studentId,
        'student_code': studentCode,
        'full_name': fullName,
        'group_id': groupId,
        'phone': (data['phone'] ?? data['student_phone'] ?? '').toString(),
        'parent_phone': (data['parent_phone'] ?? '').toString(),
        'grade': grade,
        'stage': stage,
        'pin_code': cleanPin,
        'require_2fa': is2FaEnabled,
        'user_role': 'student',
      };

      // حفظ الجلسة محلياً
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsLoggedIn, true);
      await prefs.setString(_keyStudentId, studentId);
      await prefs.setString(_keyStudentCode, studentCode);
      await prefs.setString(_keyStudentName, fullName);
      await prefs.setString(_keyGroupId, groupId);
      await prefs.setString(_keyGrade, grade);
      await prefs.setString(_keyStage, stage);
      await prefs.setString(_keyPinCode, cleanPin);
      await prefs.setString(_keyUserRole, 'student');

      // تشغيل المراقبة الأمنية اللحظية للجلسة
      startRealtimeSecurityWatcher();

      return {'success': true};
    } catch (e) {
      debugPrint('Login error: $e');
      return {'success': false, 'message': 'حدث خطأ غير متوقع أثناء الاتصال. يرجى المحاولة لاحقاً.'};
    }
  }

  /// تسجيل دخول ولي الأمر برقم هاتفه للتعرف التلقائي على أبنائه ومتابعتهم
  Future<Map<String, dynamic>> loginParent({
    required String parentPhone,
    String? studentCode,
  }) async {
    try {
      final cleanPhone = parentPhone.trim().replaceAll(RegExp(r'\D'), '');
      if (cleanPhone.length < 8) {
        return {
          'success': false,
          'message': 'يرجى إدخال رقم هاتف صحيح مكون من 8 أرقام على الأقل.',
        };
      }

      final firestore = FirebaseFirestore.instance;
      final studentsCol = firestore
          .collection('academies')
          .doc('default')
          .collection('students');

      final List<Map<String, dynamic>> matchedChildren = [];

      // 1. استعلام مباشر بحقل parent_phone
      try {
        final q1 = await studentsCol.where('parent_phone', isEqualTo: parentPhone.trim()).get();
        for (final doc in q1.docs) {
          final d = Map<String, dynamic>.from(doc.data());
          d['id'] = doc.id;
          matchedChildren.add(d);
        }
      } catch (_) {}

      // 2. فحص مرن مع استبعاد المسافات والصيغ المختلفة
      if (matchedChildren.isEmpty) {
        try {
          final allSnap = await studentsCol.limit(300).get();
          for (final doc in allSnap.docs) {
            final d = Map<String, dynamic>.from(doc.data());
            final p = (d['parent_phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
            final s = (d['phone'] ?? d['student_phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
            if ((p.isNotEmpty && p.contains(cleanPhone)) || (cleanPhone.length >= 10 && p == cleanPhone) ||
                (s.isNotEmpty && s.contains(cleanPhone))) {
              d['id'] = doc.id;
              matchedChildren.add(d);
            }
          }
        } catch (_) {}
      }

      // إلغاء تكرار الطلاب بنفس الـ ID
      final Map<String, Map<String, dynamic>> uniqueChildren = {};
      for (final c in matchedChildren) {
        final id = c['id'] ?? c['student_code'];
        if (id != null) uniqueChildren['$id'] = c;
      }
      final childrenList = uniqueChildren.values.toList();

      if (childrenList.isEmpty) {
        return {
          'success': false,
          'message': 'لم يتم العثور على أي طالب مسجل برقم هاتف ولي الأمر هذا ($parentPhone).\nتأكد من الرقم المسجل في الأكاديمية أو تواصل مع المعلم.',
        };
      }

      // إذا كان ولي الأمر أدخل كود طالب محدد لتأكيد الهوية
      if (studentCode != null && studentCode.trim().isNotEmpty) {
        final target = studentCode.trim().toLowerCase();
        final found = childrenList.where((c) {
          final code = (c['student_code'] ?? c['id'] ?? '').toString().toLowerCase();
          return code == target || code.contains(target);
        }).firstOrNull;

        if (found != null) {
          return await selectChild(found);
        }
      }

      // إذا كان لدى ولي الأمر ابن واحد فقط مسجل: الدخول المباشر
      if (childrenList.length == 1) {
        return await selectChild(childrenList.first);
      }

      // إذا كان لديه أكثر من ابن (مثلاً 2 أو 3 أبناء): نُرجع القائمة لاختيار الابن
      return {
        'success': true,
        'requires_child_selection': true,
        'children': childrenList,
      };
    } catch (e) {
      debugPrint('Parent login error: $e');
      return {'success': false, 'message': 'حدث خطأ أثناء تسجيل دخول ولي الأمر: $e'};
    }
  }

  /// تفعيل جلسة متابعة لابن محدد عند دخول ولي الأمر
  Future<Map<String, dynamic>> selectChild(Map<String, dynamic> data) async {
    try {
      final studentId = (data['id'] ?? '').toString();
      final sCodeRaw = (data['student_code'] ?? '').toString().trim();
      final studentCode = sCodeRaw.isNotEmpty ? sCodeRaw : studentId;
      final fullName = (data['full_name'] ?? 'طالب الأكاديمية').toString();
      final groupId = (data['group_id'] ?? '').toString();
      final grade = (data['grade'] ?? '').toString();
      final stage = (data['stage'] ?? '').toString();
      final pin = (data['pin_code'] ?? '1234').toString();

      currentStudent = {
        'id': studentId,
        'student_code': studentCode,
        'full_name': fullName,
        'group_id': groupId,
        'phone': (data['phone'] ?? data['student_phone'] ?? '').toString(),
        'parent_phone': (data['parent_phone'] ?? '').toString(),
        'grade': grade,
        'stage': stage,
        'pin_code': pin,
        'user_role': 'parent',
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsLoggedIn, true);
      await prefs.setString(_keyStudentId, studentId);
      await prefs.setString(_keyStudentCode, studentCode);
      await prefs.setString(_keyStudentName, fullName);
      await prefs.setString(_keyGroupId, groupId);
      await prefs.setString(_keyGrade, grade);
      await prefs.setString(_keyStage, stage);
      await prefs.setString(_keyPinCode, pin);
      await prefs.setString(_keyUserRole, 'parent');

      startRealtimeSecurityWatcher();

      return {'success': true, 'requires_child_selection': false};
    } catch (e) {
      return {'success': false, 'message': 'تعذر حفظ بيانات الجلسة: $e'};
    }
  }

  /// تسجيل الدخول بكود الطالب ورقم الهاتف (للتوافق القديم)
  Future<bool> loginWithCode({
    required String code,
    String? pin,
    String? phone,
  }) async {
    final res = await loginSecure(
      code: code,
      pin: pin ?? (phone != null && phone.trim().isNotEmpty ? phone.trim() : '1234'),
      phone: phone,
    );
    return res['success'] == true;
  }

  /// تغيير وتحديث الرمز السري PIN الخاص بالطالب وحفظه في فايربيز وتطبيق المعلم
  Future<bool> updatePin(String newPin) async {
    final cleanPin = newPin.trim();
    if (currentStudent == null || cleanPin.length < 4) return false;
    try {
      final studentId = currentStudent!['id'];
      final studentsCol = FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('students');
      await studentsCol.doc(studentId).set({
        'pin_code': cleanPin,
        'pin_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPinCode, cleanPin);
      currentStudent!['pin_code'] = cleanPin;
      return true;
    } catch (e) {
      debugPrint('Error updating pin: $e');
      return false;
    }
  }

  /// تفعيل أو تعطيل المصادقة الثنائية 2FA من طرف الطالب وحفظه في فايربيز وتطبيق المعلم
  Future<bool> update2FA(bool enabled, {String? verifiedPhone}) async {
    if (currentStudent == null) return false;
    try {
      final studentId = currentStudent!['id'];
      final studentsCol = FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('students');
      final updateData = <String, dynamic>{
        'require_2fa': enabled,
        if (verifiedPhone != null && verifiedPhone.isNotEmpty) ...{
          'two_fa_verified_phone': verifiedPhone,
          'phone': verifiedPhone,
        },
        'security_updated_at': FieldValue.serverTimestamp(),
      };
      await studentsCol.doc(studentId).set(updateData, SetOptions(merge: true));

      currentStudent!['require_2fa'] = enabled;
      if (verifiedPhone != null && verifiedPhone.isNotEmpty) {
        currentStudent!['two_fa_verified_phone'] = verifiedPhone;
        currentStudent!['phone'] = verifiedPhone;
      }
      return true;
    } catch (e) {
      debugPrint('Error updating 2FA: $e');
      return false;
    }
  }

  /// تسجيل الخروج الصارم وإلغاء الجلسة والمراقب
  Future<void> logout() async {
    _studentDocSub?.cancel();
    _studentDocSub = null;
    currentStudent = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
