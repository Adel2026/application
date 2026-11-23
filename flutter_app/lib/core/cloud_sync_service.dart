import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'database/database_service.dart';

/// ☁️ CloudSyncService
/// يربط تطبيق المعلم بسحابة Firebase (Firestore) لنقل وتحديث بيانات الطلاب،
/// المجموعات، الحضور، الغياب، الدرجات، والمصروفات لحظياً لتطبيق الطالب.
/// يعمل بنظام Offline-First بحيث لا يؤثر إطلاقاً على عمل التطبيق بدون إنترنت.
class CloudSyncService {
  static final CloudSyncService instance = CloudSyncService._internal();
  CloudSyncService._internal();

  DatabaseService? _databaseService;
  StreamSubscription<DataChangeEvent>? _changeSubscription;
  Timer? _debounceTimer;
  final Set<DataChangeEvent> _pendingEvents = {};

  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);
  final ValueNotifier<DateTime?> lastSyncTime = ValueNotifier<DateTime?>(null);
  final ValueNotifier<String?> syncStatus = ValueNotifier<String?>(null);

  bool _isInitialized = false;
  bool _isProcessing = false;
  static const String _defaultAcademyDoc = 'default';

  /// جلب معرّف السنتر الفريد ديناميكياً مع دعم fallback لـ default لضمان اتصال تطبيق الطالب
  Future<String> getAcademyDocId() async {
    try {
      if (_databaseService != null) {
        final cCode = await _databaseService!.getSetting('center_code', defaultValue: '');
        if (cCode.trim().isNotEmpty) return cCode.trim();
      }
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) return uid;
    } catch (_) {}
    return _defaultAcademyDoc;
  }

  DocumentReference get _academyRef =>
      FirebaseFirestore.instance.collection('academies').doc(_defaultAcademyDoc);

  /// تهيئة الخدمة وربطها بمستمع التغييرات في قاعدة البيانات المحلية
  Future<void> initialize(DatabaseService database) async {
    if (_isInitialized) return;
    _databaseService = database;
    _isInitialized = true;

    // التأكد من تسجيل الدخول الآمن لـ Firebase
    _ensureAuth().then((_) {
      // مزامنة أولية شاملة في الخلفية
      syncAll(silent: true);
    }).catchError((e) {
      debugPrint('☁️ [CloudSync] Auth init warning: $e');
    });

    // الاستماع لجميع أحداث تغيير البيانات في التطبيق
    _changeSubscription = database.onDataChanged.listen((event) {
      _onDatabaseChanged(event);
    });

    debugPrint('☁️ [CloudSync] Service initialized successfully.');
  }

  /// تسجيل دخول تلقائي غير مرئي لتوفير مصادقة آمنة لـ Firebase Security Rules
  Future<void> _ensureAuth() async {
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
        debugPrint('☁️ [CloudSync] Anonymous sign-in established: ${auth.currentUser?.uid}');
      }
    } catch (e) {
      debugPrint('☁️ [CloudSync] Firebase Auth notice: $e');
    }
  }

  /// تجميع وتأخير الأحداث (Debounce) لمنع تكرار الرفع ومزامنة البيانات في أقل من نصف ثانية
  void _onDatabaseChanged(DataChangeEvent event) {
    _pendingEvents.add(event);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _processPendingEvents();
    });
  }

  /// مزامنة فورية فور حدوث تغيير دون انتظار مؤقت
  Future<void> syncImmediately([DataChangeEvent? event]) async {
    if (event != null) {
      _pendingEvents.add(event);
    } else {
      _pendingEvents.add(DataChangeEvent.all);
    }
    _debounceTimer?.cancel();
    await _processPendingEvents();
  }

  Future<void> _processPendingEvents() async {
    if (_pendingEvents.isEmpty || _databaseService == null || _isProcessing) return;
    _isProcessing = true;
    final eventsToProcess = Set<DataChangeEvent>.from(_pendingEvents);
    _pendingEvents.clear();

    if (eventsToProcess.contains(DataChangeEvent.all)) {
      try {
        await syncAll();
      } finally {
        _isProcessing = false;
        if (_pendingEvents.isNotEmpty) {
          Timer(const Duration(milliseconds: 250), () => _processPendingEvents());
        }
      }
      return;
    }

    try {
      isSyncing.value = true;
      syncStatus.value = 'جاري المزامنة السحابية...';

      if (eventsToProcess.contains(DataChangeEvent.students)) {
        await syncStudents();
      }
      if (eventsToProcess.contains(DataChangeEvent.groups)) {
        await syncGroups();
      }
      if (eventsToProcess.contains(DataChangeEvent.attendance)) {
        await syncAttendance();
        await syncSessions();
      }
      if (eventsToProcess.contains(DataChangeEvent.exams)) {
        await syncExams();
      }
      if (eventsToProcess.contains(DataChangeEvent.finances)) {
        await syncFinancialClaims();
      }
      if (eventsToProcess.contains(DataChangeEvent.reports)) {
        await syncCertificates();
      }

      await _updateSyncMeta();
      lastSyncTime.value = DateTime.now();
      syncStatus.value = 'تمت المزامنة بنجاح';
    } catch (e) {
      debugPrint('☁️ [CloudSync] Error during incremental sync: $e');
      syncStatus.value = 'تعذر الاتصال بالسحابة (محفوظ محلياً)';
    } finally {
      isSyncing.value = false;
      _isProcessing = false;
      if (_pendingEvents.isNotEmpty) {
        Timer(const Duration(milliseconds: 250), () => _processPendingEvents());
      }
    }
  }

  /// مزامنة كاملة لجميع البيانات (دفعة أولى أو يدوياً)
  Future<void> syncAll({bool silent = false}) async {
    if (_databaseService == null) return;
    try {
      if (!silent) {
        isSyncing.value = true;
        syncStatus.value = 'جاري المزامنة الشاملة...';
      }

      await _ensureAuth();
      await Future.wait([
        syncGroups(),
        syncStudents(),
        syncSessions(),
        syncAttendance(),
        syncExams(),
        syncFinancialClaims(),
        syncCertificates(),
        syncRewardsCatalog(),
      ]);

      await _updateSyncMeta();
      lastSyncTime.value = DateTime.now();
      if (!silent) syncStatus.value = 'تمت المزامنة الشاملة بنجاح';
      debugPrint('☁️ [CloudSync] Full sync completed successfully.');
    } catch (e) {
      debugPrint('☁️ [CloudSync] Full sync error: $e');
      if (!silent) syncStatus.value = 'محفوظ محلياً (غير متصل بالسحابة)';
    } finally {
      if (!silent) isSyncing.value = false;
    }
  }

  /// 1. مزامنة الطلاب
  Future<void> syncStudents() async {
    final db = await _databaseService!.database;
    final rows = await db.query('students');
    final studentsCol = _academyRef.collection('students');
    final activeIds = <String>{};

    const chunkSize = 400;
    for (int i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.skip(i).take(chunkSize);
      final batch = FirebaseFirestore.instance.batch();

      for (final row in chunk) {
        final studentId = '${row['id']}';
        activeIds.add(studentId);
        final cleanNum = studentId.replaceAll(RegExp(r'\D'), '');
        final studentCode = cleanNum.isNotEmpty ? cleanNum : studentId;
        final sPhone = (row['student_phone'] ?? row['phone'] ?? '').toString();
        final pPhone = (row['parent_phone'] ?? '').toString();
        final docRef = studentsCol.doc(studentId);

        // ضمان توفر PIN للطالب وولي الأمر
        final sPin = (row['student_pin'] as String?)?.trim() ?? '';
        final pPin = (row['parent_pin'] as String?)?.trim() ?? '';
        final fallbackPin = pPhone.length >= 4
            ? pPhone.substring(pPhone.length - 4)
            : (sPhone.length >= 4 ? sPhone.substring(sPhone.length - 4) : '1234');

        batch.set(docRef, {
          'id': studentId,
          'student_code': studentCode, // كود دخول الطالب (رقم أو كود كامل)
          'full_name': row['full_name'] ?? '',
          'phone': sPhone,
          'student_phone': sPhone,
          'parent_phone': pPhone,
          'group_id': '${row['group_id'] ?? ''}',
          'stage': row['stage'] ?? '',
          'grade': row['grade'] ?? '',
          'is_active': row['is_active'] ?? 1,
          'outstanding_amount': row['outstanding_amount'] ?? 0.0,
          'parent_name': row['parent_name'] ?? '',
          'guardians_json': row['guardians_json'] ?? '',
          'student_pin': sPin.isNotEmpty ? sPin : fallbackPin,
          'parent_pin': pPin.isNotEmpty ? pPin : fallbackPin,
          'pin_code': sPin.isNotEmpty ? sPin : fallbackPin, // توافق كامل مع تطبيق الطالب
          'points_balance': row['points_balance'] ?? 0,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }

    // حذف وثائق الطلاب القديمة/الملغاة من السحابة لتجنب تكرار الأكواد القديمة
    try {
      final snapshot = await studentsCol.get();
      final toDelete = snapshot.docs.where((d) => !activeIds.contains(d.id)).toList();
      for (int i = 0; i < toDelete.length; i += chunkSize) {
        final delChunk = toDelete.skip(i).take(chunkSize);
        final deleteBatch = FirebaseFirestore.instance.batch();
        for (final doc in delChunk) {
          deleteBatch.delete(doc.reference);
        }
        await deleteBatch.commit();
      }
    } catch (e) {
      debugPrint('☁️ [CloudSync] Error purging old students: $e');
    }

    debugPrint('☁️ [CloudSync] Synced ${rows.length} students.');
  }

  /// 2. مزامنة المجموعات
  Future<void> syncGroups() async {
    final db = await _databaseService!.database;
    final rows = await db.query('groups');
    final batch = FirebaseFirestore.instance.batch();
    final groupsCol = _academyRef.collection('groups');

    for (final row in rows) {
      final groupId = '${row['id']}';
      final docRef = groupsCol.doc(groupId);
      batch.set(docRef, {
        'id': groupId,
        'name': row['name'] ?? '',
        'stage': row['stage'] ?? '',
        'grade': row['grade'] ?? '',
        'schedule': row['schedule'] ?? '',
        'monthly_price': row['monthly_price'] ?? 0.0,
        'is_active': row['is_active'] ?? 1,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
    debugPrint('☁️ [CloudSync] Synced ${rows.length} groups.');
  }

  /// 3. مزامنة الحصص وتفاصيل الدروس
  Future<void> syncSessions() async {
    final db = await _databaseService!.database;
    final rows = await db.query('session_logs', limit: 500, orderBy: 'id DESC');
    final cancellations = await db.query('session_cancellations', limit: 200, orderBy: 'id DESC');

    final sessionsCol = _academyRef.collection('sessions');
    final cancellationsCol = _academyRef.collection('cancellations');
    const chunkSize = 400;

    for (int i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.skip(i).take(chunkSize);
      final batch = FirebaseFirestore.instance.batch();
      for (final row in chunk) {
        final docRef = sessionsCol.doc('${row['id']}');
        final rawTitle = (row['lesson_title'] ?? '').toString().trim();
        final rawContent = (row['content_covered'] ?? '').toString().trim();
        final effTitle = rawTitle.isNotEmpty ? rawTitle : (rawContent.isNotEmpty ? rawContent : 'حصة دراسية');

        batch.set(docRef, {
          'id': row['id'],
          'group_id': '${row['group_id'] ?? ''}',
          'session_date': row['date'] ?? row['session_date'] ?? '',
          'lesson_title': effTitle,
          'content_covered': rawContent,
          'homework_assigned': row['homework'] ?? row['homework_assigned'] ?? '',
          'next_topic': row['next_topic'] ?? '',
          'next_quiz': row['next_quiz'] ?? '',
          'previous_homework_review': row['previous_homework_review'] ?? '',
          'notes': row['notes'] ?? '',
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }

    for (int i = 0; i < cancellations.length; i += chunkSize) {
      final chunk = cancellations.skip(i).take(chunkSize);
      final batch = FirebaseFirestore.instance.batch();
      for (final canc in chunk) {
        final docRef = cancellationsCol.doc('${canc['id']}');
        batch.set(docRef, {
          'id': canc['id'],
          'group_id': '${canc['group_id'] ?? ''}',
          'date': canc['date'] ?? '',
          'cancelled_by': canc['cancelled_by'] ?? '',
          'reason': canc['reason'] ?? '',
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }

    debugPrint('☁️ [CloudSync] Synced ${rows.length} sessions & ${cancellations.length} cancellations.');
  }

  /// 4. مزامنة الحضور والغياب
  Future<void> syncAttendance() async {
    final db = await _databaseService!.database;
    final rows = await db.query('attendance', limit: 1000, orderBy: 'id DESC');
    final attendanceCol = _academyRef.collection('attendance');
    const chunkSize = 400;

    for (int i = 0; i < rows.length; i += chunkSize) {
      final chunk = rows.skip(i).take(chunkSize);
      final batch = FirebaseFirestore.instance.batch();
      for (final row in chunk) {
        final docRef = attendanceCol.doc('${row['id']}');
        final date = row['attendance_date'] ?? row['session_date'] ?? '';
        batch.set(docRef, {
          'id': row['id'],
          'student_id': '${row['student_id']}',
          'attendance_date': date,
          'session_date': date,
          'check_in_at': row['check_in_at'] ?? '',
          'status': row['status'] ?? 'present',
          'source': row['source'] ?? '',
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
    debugPrint('☁️ [CloudSync] Synced ${rows.length} attendance records.');
  }

  /// 5. مزامنة الاختبارات والدرجات وحساب الرتب والشهادات وإرسال الإشعارات اللحظية لتطبيق الطالب
  Future<void> syncExams() async {
    final db = await _databaseService!.database;
    final exams = await db.query('exams', limit: 100);
    final scores = await db.query('exam_scores', limit: 1000, orderBy: 'id DESC');
    final studentsList = await db.query('students');
    final groupsList = await db.query('groups');

    final cName = await _databaseService!.getSetting('center_name', defaultValue: 'أكاديمية التفوق التعليمية');
    final tName = await _databaseService!.getSetting('teacher_name', defaultValue: 'معلم المادة');

    final studentsMap = {for (var s in studentsList) '${s['id']}': s};
    final groupsMap = {for (var g in groupsList) '${g['id']}': g};

    final examsCol = _academyRef.collection('exams');
    final scoresCol = _academyRef.collection('exam_scores');
    final notifsCol = _academyRef.collection('notifications');

    // مزامنة بيانات الاختبارات في حزم آمنة
    WriteBatch currentBatch = FirebaseFirestore.instance.batch();
    int batchCount = 0;

    for (final exam in exams) {
      final docRef = examsCol.doc('${exam['id']}');
      currentBatch.set(docRef, {
        'id': '${exam['id']}',
        'title': exam['title'] ?? '',
        'max_score': exam['max_score'] ?? 100,
        'exam_date': exam['date'] ?? '',
        'date': exam['date'] ?? '',
        'group_id': '${exam['group_id'] ?? ''}',
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batchCount++;
      if (batchCount >= 40) {
        await currentBatch.commit();
        currentBatch = FirebaseFirestore.instance.batch();
        batchCount = 0;
      }
    }

    // تجميع الدرجات لكل امتحان لحساب الترتيب (Rank) ونسبة التفوق
    final Map<String, List<Map<String, dynamic>>> examScoresGrouped = {};
    for (final s in scores) {
      final eId = '${s['exam_id']}';
      examScoresGrouped.putIfAbsent(eId, () => []).add(s);
    }

    for (final score in scores) {
      final sExamId = '${score['exam_id']}';
      final studentIdStr = '${score['student_id']}';
      final docRef = scoresCol.doc('${sExamId}_$studentIdStr');
      final studentScore = (score['score'] as num? ?? 0).toDouble();

      // إيجاد الاختبار لمعرفة الدرجة العظمى
      final matchedExam = exams.firstWhere(
        (e) => '${e['id']}' == sExamId,
        orElse: () => <String, dynamic>{'max_score': 100},
      );
      final maxScore = (matchedExam['max_score'] as num? ?? 100).toDouble();
      final percent = maxScore > 0 ? (studentScore / maxScore) * 100 : 0.0;

      // حساب الترتيب بين الطلاب في نفس الامتحان
      int rank = 0;
      final groupList = examScoresGrouped[sExamId] ?? [];
      if (groupList.isNotEmpty) {
        final sortedScores = groupList
            .map((e) => (e['score'] as num? ?? 0).toDouble())
            .toList()
          ..sort((a, b) => b.compareTo(a));
        rank = sortedScores.indexOf(studentScore) + 1;
      }

      final isRevoked = await _databaseService!.getSetting('cert_revoked_${sExamId}_$studentIdStr', defaultValue: 'false') == 'true' ||
          await _databaseService!.getSetting('cert_revoked_all_$sExamId', defaultValue: 'false') == 'true';

      final bool hasCertificate = !isRevoked && (percent >= 85.0 || (rank > 0 && rank <= 3 && percent >= 60.0));

      String certTitle = 'شهادة تفوق وامتياز 🎓';
      if (rank == 1) {
        certTitle = 'شهادة المركز الأول والصدارة 🏆';
      } else if (rank == 2) {
        certTitle = 'شهادة المركز الثاني مع مرتبة الشرف 🥈';
      } else if (rank == 3) {
        certTitle = 'شهادة المركز الثالث المتميز 🥉';
      }

      final studentData = studentsMap[studentIdStr];
      final groupData = studentData != null ? groupsMap['${studentData['group_id']}'] : null;

      final studentName = (studentData?['full_name'] ?? studentData?['name'] ?? '').toString().trim();
      final finalStudentName = studentName.isNotEmpty ? studentName : 'الطالب المتفوق';
      final studentCode = (studentData?['student_code'] ?? studentData?['code'] ?? studentIdStr.replaceAll(RegExp(r'\D'), '')).toString();
      final groupName = (groupData?['name'] ?? '').toString();
      final grade = (studentData?['grade'] ?? '').toString();
      final stage = (studentData?['stage'] ?? '').toString();
      final examDateStr = (matchedExam['date'] ?? '').toString();
      final examTitleStr = (matchedExam['title'] ?? 'اختبار تقييمي').toString();

      // حفظ نتيجة الاختبار وترحيلها لحظياً لتطبيق الطالب (مع الحفاظ على أي صورة شهادة تم إصدارها سابقاً عبر SetOptions merge)
      final scoreData = <String, dynamic>{
        'id': '${sExamId}_$studentIdStr',
        'exam_id': sExamId,
        'exam_title': examTitleStr,
        'exam_date': examDateStr,
        'student_id': studentIdStr,
        'student_name': finalStudentName,
        'student_code': studentCode,
        'group_name': groupName,
        'grade': grade,
        'stage': stage,
        'teacher_name': tName,
        'center_name': cName,
        'score': studentScore,
        'max_score': maxScore,
        'percentage': percent,
        'rank': rank,
        'has_certificate': hasCertificate,
        'certificate_title': hasCertificate ? certTitle : null,
        'notes': score['note'] ?? '',
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (isRevoked) {
        scoreData['has_certificate'] = false;
        scoreData['certificate_issued'] = false;
        scoreData['certificate_deleted'] = true;
        scoreData['certificate_revoked'] = true;
        scoreData['certificate_image_base64'] = FieldValue.delete();
        scoreData['certificate_title'] = FieldValue.delete();
      }

      currentBatch.set(docRef, scoreData, SetOptions(merge: true));

      batchCount++;

      // إرسال إشعار فوري للطالب برصد الدرجة
      final scoreNotifId = 'score_${sExamId}_$studentIdStr';
      final notifDoc = notifsCol.doc(scoreNotifId);
      currentBatch.set(notifDoc, {
        'id': scoreNotifId,
        'title': '📝 رصد نتيجة اختبار: $examTitleStr',
        'body': 'حصلت على درجة $studentScore من $maxScore (%${percent.toStringAsFixed(1)}) ${rank > 0 ? "• المركز $rank 🎖️" : ""}',
        'target_type': 'student',
        'target_id': studentIdStr,
        'type': 'exam_score',
        'exam_id': sExamId,
        'student_id': studentIdStr,
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batchCount++;

      if (batchCount >= 40) {
        await currentBatch.commit();
        currentBatch = FirebaseFirestore.instance.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await currentBatch.commit();
    }

    debugPrint('☁️ [CloudSync] Synced ${exams.length} exams & ${scores.length} scores with real-time notifications.');
  }

  /// 📜 إصدار ونشر صورة الشهادة الرسمية الأصلية بنفس دقتها وحجمها لتطبيق الطالب مباشرة
  Future<bool> publishCertificateImage({
    required String examId,
    required String studentId,
    required Uint8List imageBytes,
    required String studentName,
    required String examTitle,
    required String certTitle,
  }) async {
    try {
      final base64Image = base64Encode(imageBytes);
      final docId = '${examId}_$studentId';
      final scoreDocRef = _academyRef.collection('exam_scores').doc(docId);
      final cleanCode = studentId.replaceAll(RegExp(r'\D'), '');

      // تحديث نتيجة الاختبار ببيانات وصورة الشهادة المعتمدة الأصلية (مع التأكد من وجود معرّف الطالب واسمه)
      await scoreDocRef.set({
        'id': docId,
        'student_id': studentId,
        'student_code': cleanCode.isNotEmpty ? cleanCode : studentId,
        'student_name': studentName,
        'exam_id': examId,
        'exam_title': examTitle,
        'has_certificate': true,
        'certificate_image_base64': base64Image,
        'certificate_title': certTitle,
        'certificate_issued': true,
        'certificate_deleted': false,
        'certificate_revoked': false,
        'certificate_issued_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // مسح علامة الإلغاء إذا كانت موجودة
      await _databaseService?.setSetting('cert_revoked_${examId}_$studentId', 'false');
      await _databaseService?.setSetting('cert_revoked_all_$examId', 'false');

      // إرسال إشعار فوري ومميز للطالب بصدور شهادته المعتمدة
      final notifId = 'cert_${examId}_$studentId';
      await _academyRef.collection('notifications').doc(notifId).set({
        'id': notifId,
        'title': '🎓 صدرت شهادة تقديرك الرسمية!',
        'body': 'ألف مبروك يا $studentName! أصدر المعلم شهادة تقديرك الرسمية المعتمدة في "$examTitle". تفقد صورتها واحتفل بإنجازك الآن! 🌟',
        'target_type': 'student',
        'target_id': studentId,
        'type': 'certificate',
        'exam_id': examId,
        'student_id': studentId,
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('☁️ [CloudSync] Published official certificate for $studentName in exam $examId successfully.');
      return true;
    } catch (e) {
      debugPrint('☁️ [CloudSync] Error publishing certificate image: $e');
      return false;
    }
  }

  /// 🗑️ حذف وسحب شهادة الطالب من السحابة وتطبيق الطالب فوراً
  Future<bool> revokeCertificate({
    required String examId,
    required String studentId,
  }) async {
    try {
      final docId = '${examId}_$studentId';
      final scoreDocRef = _academyRef.collection('exam_scores').doc(docId);

      // 1. تحديث نتيجة الاختبار وحذف بيانات وصورة الشهادة
      await scoreDocRef.set({
        'has_certificate': false,
        'certificate_issued': false,
        'certificate_deleted': true,
        'certificate_revoked': true,
        'certificate_image_base64': FieldValue.delete(),
        'certificate_title': FieldValue.delete(),
        'certificate_revoked_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. حذف إشعار الشهادة من قائمة الإشعارات
      final notifId = 'cert_${examId}_$studentId';
      await _academyRef.collection('notifications').doc(notifId).delete();

      // 3. حفظ علامة الإلغاء محلياً
      await _databaseService?.setSetting('cert_revoked_${examId}_$studentId', 'true');

      debugPrint('☁️ [CloudSync] Revoked certificate for student $studentId in exam $examId successfully.');
      return true;
    } catch (e) {
      debugPrint('☁️ [CloudSync] Error revoking certificate: $e');
      return false;
    }
  }

  /// 🗑️ حذف وسحب جميع شهادات الاختبار من تطبيق الطالب دفعة واحدة
  Future<bool> revokeAllCertificatesForExam({
    required String examId,
  }) async {
    try {
      final scoresSnap = await _academyRef
          .collection('exam_scores')
          .where('exam_id', isEqualTo: examId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in scoresSnap.docs) {
        batch.set(doc.reference, {
          'has_certificate': false,
          'certificate_issued': false,
          'certificate_deleted': true,
          'certificate_revoked': true,
          'certificate_image_base64': FieldValue.delete(),
          'certificate_title': FieldValue.delete(),
          'certificate_revoked_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        final studentId = doc.data()['student_id'];
        if (studentId != null) {
          final notifRef = _academyRef.collection('notifications').doc('cert_${examId}_$studentId');
          batch.delete(notifRef);
          await _databaseService?.setSetting('cert_revoked_${examId}_$studentId', 'true');
        }
      }

      await _databaseService?.setSetting('cert_revoked_all_$examId', 'true');
      await batch.commit();
      debugPrint('☁️ [CloudSync] Revoked all certificates for exam $examId successfully.');
      return true;
    } catch (e) {
      debugPrint('☁️ [CloudSync] Error revoking all certificates for exam $examId: $e');
      return false;
    }
  }

  /// 🗑️ حذف اختبار بالكامل من السحابة وتطبيق الطالب (بما فيه الدرجات والشهادات والإشعارات)
  Future<void> deleteExamFromCloud(String examId) async {
    try {
      // 1. حذف وثيقة الاختبار
      await _academyRef.collection('exams').doc(examId).delete();

      // 2. جلب وحذف درجات وشهادات الاختبار
      final scoresSnap = await _academyRef
          .collection('exam_scores')
          .where('exam_id', isEqualTo: examId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in scoresSnap.docs) {
        batch.delete(doc.reference);
        final studentId = doc.data()['student_id'];
        if (studentId != null) {
          batch.delete(_academyRef.collection('notifications').doc('score_${examId}_$studentId'));
          batch.delete(_academyRef.collection('notifications').doc('cert_${examId}_$studentId'));
        }
      }
      await batch.commit();
      debugPrint('☁️ [CloudSync] Deleted exam $examId and all related scores/certificates from cloud.');
    } catch (e) {
      debugPrint('☁️ [CloudSync] Error deleting exam from cloud: $e');
    }
  }

  /// 🚀 مزامنة فورية ومباشرة لدرجات امتحان معين فور حفظها لمنع أي تأخير في ترحيل الدرجات
  Future<void> syncExamScoresDirect({
    required String examId,
    required String examTitle,
    required double maxScore,
    required String examDate,
    required Map<String, double> scores,
  }) async {
    try {
      if (_databaseService == null) return;
      final db = await _databaseService!.database;
      final studentsList = await db.query('students');
      final studentsMap = {for (var s in studentsList) '${s['id']}': s};

      final cName = await _databaseService!.getSetting('center_name', defaultValue: 'أكاديمية التفوق التعليمية');
      final tName = await _databaseService!.getSetting('teacher_name', defaultValue: 'معلم المادة');

      final scoresCol = _academyRef.collection('exam_scores');
      final notifsCol = _academyRef.collection('notifications');

      final sortedEntries = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final batch = FirebaseFirestore.instance.batch();

      final examDoc = _academyRef.collection('exams').doc(examId);
      batch.set(examDoc, {
        'id': examId,
        'title': examTitle,
        'max_score': maxScore,
        'exam_date': examDate,
        'date': examDate,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      for (int i = 0; i < sortedEntries.length; i++) {
        final entry = sortedEntries[i];
        final studentId = entry.key;
        final studentScore = entry.value;
        final rank = i + 1;
        final percent = maxScore > 0 ? (studentScore / maxScore) * 100 : 0.0;
        final hasCert = percent >= 85.0 || (rank <= 3 && percent >= 60.0);

        String certTitle = 'شهادة تفوق وامتياز 🎓';
        if (rank == 1) {
          certTitle = 'شهادة المركز الأول والصدارة 🏆';
        } else if (rank == 2) {
          certTitle = 'شهادة المركز الثاني مع مرتبة الشرف 🥈';
        } else if (rank == 3) {
          certTitle = 'شهادة المركز الثالث المتميز 🥉';
        }

        final sData = studentsMap[studentId];
        final studentName = (sData?['full_name'] ?? sData?['name'] ?? '').toString().trim();
        final finalName = studentName.isNotEmpty ? studentName : 'الطالب المتفوق';
        final cleanCode = (sData?['student_code'] ?? studentId.replaceAll(RegExp(r'\D'), '')).toString();
        final grade = (sData?['grade'] ?? '').toString();
        final stage = (sData?['stage'] ?? '').toString();

        final docId = '${examId}_$studentId';
        final docRef = scoresCol.doc(docId);

        final isRevoked = await _databaseService!.getSetting('cert_revoked_${examId}_$studentId', defaultValue: 'false') == 'true' ||
            await _databaseService!.getSetting('cert_revoked_all_$examId', defaultValue: 'false') == 'true';
        final effHasCert = !isRevoked && hasCert;

        final directScoreData = <String, dynamic>{
          'id': docId,
          'exam_id': examId,
          'exam_title': examTitle,
          'exam_date': examDate,
          'student_id': studentId,
          'student_name': finalName,
          'student_code': cleanCode,
          'grade': grade,
          'stage': stage,
          'teacher_name': tName,
          'center_name': cName,
          'score': studentScore,
          'max_score': maxScore,
          'percentage': percent,
          'rank': rank,
          'has_certificate': effHasCert,
          'certificate_title': effHasCert ? certTitle : null,
          'updated_at': FieldValue.serverTimestamp(),
        };

        if (isRevoked) {
          directScoreData['has_certificate'] = false;
          directScoreData['certificate_issued'] = false;
          directScoreData['certificate_deleted'] = true;
          directScoreData['certificate_revoked'] = true;
          directScoreData['certificate_image_base64'] = FieldValue.delete();
          directScoreData['certificate_title'] = FieldValue.delete();
        }

        batch.set(docRef, directScoreData, SetOptions(merge: true));

        final notifId = 'score_${examId}_$studentId';
        batch.set(notifsCol.doc(notifId), {
          'id': notifId,
          'title': '📝 رصد نتيجة اختبار: $examTitle',
          'body': 'حصلت على درجة $studentScore من $maxScore (%${percent.toStringAsFixed(1)}) ${rank > 0 ? "• المركز $rank 🎖️" : ""}',
          'target_type': 'student',
          'target_id': studentId,
          'type': 'exam_score',
          'exam_id': examId,
          'student_id': studentId,
          'created_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
      debugPrint('☁️ [CloudSync] Direct sync for exam $examId committed successfully.');
    } catch (e) {
      debugPrint('☁️ [CloudSync] Direct exam sync error: $e');
    }
  }

  /// 6. مزامنة المطالبات والمصروفات المالية
  Future<void> syncFinancialClaims() async {
    final db = await _databaseService!.database;
    final claims = await db.query('financial_claims', limit: 1000, orderBy: 'id DESC');
    final claimsCol = _academyRef.collection('financial_claims');
    const chunkSize = 400;

    for (int i = 0; i < claims.length; i += chunkSize) {
      final chunk = claims.skip(i).take(chunkSize);
      final batch = FirebaseFirestore.instance.batch();
      for (final claim in chunk) {
        final docRef = claimsCol.doc('${claim['id']}');
        final amount = (claim['amount'] as num? ?? 0).toDouble();
        final paid = (claim['paid_amount'] as num? ?? 0).toDouble();
        final isPaid = (claim['status'] == 'paid' || (paid >= amount && amount > 0)) ? 1 : 0;

        batch.set(docRef, {
          'id': claim['id'],
          'claim_id': claim['claim_id'] ?? '',
          'student_id': '${claim['student_id']}',
          'student_name': claim['student_name'] ?? '',
          'group_id': '${claim['group_id'] ?? ''}',
          'group_name': claim['group_name'] ?? '',
          'session_date': claim['session_date'] ?? '',
          'required_amount': amount,
          'amount': amount,
          'paid_amount': paid,
          'is_paid': isPaid,
          'status': claim['status'] ?? 'active',
          'note': claim['note'] ?? '',
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
    debugPrint('☁️ [CloudSync] Synced ${claims.length} financial claims.');
  }

  /// 7. مزامنة شهادات التقدير الصادرة في مجموعة فرعية certificates داخل مستند السنتر
  Future<void> syncCertificates() async {
    try {
      final db = await _databaseService!.database;
      final certs = await db.query('certificates', limit: 500, orderBy: 'issued_at DESC');
      if (certs.isEmpty) return;

      final certsCol = _academyRef.collection('certificates');
      const chunkSize = 400;

      for (int i = 0; i < certs.length; i += chunkSize) {
        final chunk = certs.skip(i).take(chunkSize);
        final batch = FirebaseFirestore.instance.batch();
        for (final c in chunk) {
          final certId = '${c['id']}';
          final docRef = certsCol.doc(certId);
          batch.set(docRef, {
            'id': certId,
            'student_id': '${c['student_id']}',
            'student_name': c['student_name'] ?? '',
            'exam_title': c['exam_title'] ?? '',
            'badge_title': c['badge_title'] ?? '',
            'score_text': c['score_text'] ?? '',
            'issued_at': c['issued_at'] ?? '',
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await batch.commit();
      }
      debugPrint('☁️ [CloudSync] Synced ${certs.length} certificates successfully.');
    } catch (e) {
      debugPrint('☁️ [CloudSync] Error syncing certificates: $e');
    }
  }

  /// مزامنة كتالوج المكافآت إلى السحابة ليراها تطبيق الطالب
  Future<void> syncRewardsCatalog() async {
    try {
      final db = await _databaseService!.database;
      final rewards = await db.query('rewards_catalog');
      final rewardsCol = _academyRef.collection('rewards');

      final batch = FirebaseFirestore.instance.batch();
      for (final r in rewards) {
        final rId = '${r['id']}';
        batch.set(rewardsCol.doc(rId), {
          'id': rId,
          'title': r['title'] ?? '',
          'description': r['description'] ?? '',
          'cost_points': r['cost_points'] ?? 0,
          'icon_name': r['icon_name'] ?? 'gift',
          'is_active': r['is_active'] ?? 1,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
      debugPrint('☁️ [CloudSync] Synced ${rewards.length} rewards to cloud.');
    } catch (e) {
      debugPrint('☁️ [CloudSync] Error syncing rewards: $e');
    }
  }

  /// تحديث بيانات آخر مزامنة للأكاديمية
  Future<void> _updateSyncMeta() async {
    try {
      await _academyRef.set({
        'name': 'Edu Academy',
        'last_sync': FieldValue.serverTimestamp(),
        'app_version': '1.0.0',
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void dispose() {
    _changeSubscription?.cancel();
    _debounceTimer?.cancel();
  }
}
