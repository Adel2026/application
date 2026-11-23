import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';

class StudentDataService {
  static final StudentDataService instance = StudentDataService._internal();
  StudentDataService._internal();

  DocumentReference get _academyRef =>
      FirebaseFirestore.instance.collection('academies').doc('default');

  // ذاكرة التخزين المؤقت الداخلي مع مؤقت الصلاحية (In-Memory Stale-While-Revalidate Cache)
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheTtl = Duration(minutes: 5);

  bool _isCacheValid(String key) {
    final time = _cacheTimestamps[key];
    if (time == null) return false;
    return DateTime.now().difference(time) < _cacheTtl;
  }

  void _setCache(String key, dynamic value) {
    _memoryCache[key] = value;
    _cacheTimestamps[key] = DateTime.now();
  }

  dynamic _getCache(String key) => _memoryCache[key];

  List<Map<String, dynamic>>? getCachedAttendance(dynamic studentId) =>
      _getCache('att_$studentId') as List<Map<String, dynamic>>?;

  List<Map<String, dynamic>>? getCachedExams(dynamic studentId) =>
      _getCache('exams_$studentId') as List<Map<String, dynamic>>?;

  bool isDataCached(String key) => _isCacheValid(key);

  void invalidateCache([String? key]) {
    if (key != null) {
      _memoryCache.remove(key);
      _cacheTimestamps.remove(key);
    } else {
      _memoryCache.clear();
      _cacheTimestamps.clear();
    }
  }

  /// بث حي لمعلومات الطالب الحالية
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamStudent(dynamic studentId) {
    return _academyRef.collection('students').doc('$studentId').snapshots();
  }

  /// بث حي لمعلومات مجموعة الطالب
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamGroup(dynamic groupId) {
    return _academyRef.collection('groups').doc('$groupId').snapshots();
  }

  /// بث حي لسجلات الحضور والغياب والتسميع للطالب
  Stream<List<Map<String, dynamic>>> streamStudentAttendance(dynamic studentId) {
    final sId = '$studentId';
    final clean = sId.replaceAll(RegExp(r'\D'), '');
    final ids = {sId, if (clean.isNotEmpty) clean}.toList();
    return _academyRef
        .collection('attendance')
        .where('student_id', whereIn: ids)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((d) => d.data()).toList();
      list.sort((a, b) => (b['attendance_date'] ?? b['session_date'] ?? '').compareTo(a['attendance_date'] ?? a['session_date'] ?? ''));
      _setCache('att_$sId', list);
      return list;
    });
  }

  /// بث حي لدرجات الامتحانات والاختبارات
  Stream<List<Map<String, dynamic>>> streamStudentExams(dynamic studentId, [dynamic studentCode]) {
    if (studentId == null || '$studentId'.trim().isEmpty) return Stream.value([]);
    final sId = '$studentId'.trim();
    final clean = sId.replaceAll(RegExp(r'\D'), '');
    final codeStr = (studentCode ?? '').toString().trim();
    final cleanCode = codeStr.replaceAll(RegExp(r'\D'), '');
    final ids = {
      sId,
      if (clean.isNotEmpty) clean,
      if (codeStr.isNotEmpty) codeStr,
      if (cleanCode.isNotEmpty) cleanCode,
    }.toList();

    return _academyRef
        .collection('exam_scores')
        .where('student_id', whereIn: ids)
        .snapshots()
        .map((scoresSnap) {
      final scores = scoresSnap.docs.map((d) => d.data()).toList();
      // منع تكرار الشهادات والاختبارات: ندمج ونأخذ سجلاً واحداً فريداً لكل اختبار
      final Map<String, Map<String, dynamic>> uniqueByExam = {};
      for (final s in scores) {
        final eId = '${s['exam_id'] ?? s['id'] ?? ''}'.trim();
        if (eId.isEmpty) continue;
        if (!uniqueByExam.containsKey(eId)) {
          uniqueByExam[eId] = Map<String, dynamic>.from(s);
        } else {
          final existing = uniqueByExam[eId]!;

          // تحديد السجل الأحدث بناءً على تاريخ التحديث
          final sTime = '${s['updated_at'] ?? s['created_at'] ?? s['synced_at'] ?? s['date'] ?? ''}';
          final exTime = '${existing['updated_at'] ?? existing['created_at'] ?? existing['synced_at'] ?? existing['date'] ?? ''}';
          final isCandidateNewer = sTime.compareTo(exTime) > 0;

          // دمج بيانات الشهادة حتى لا تضيع سواء كانت في السجل القديم أو الجديد
          final existingImg = existing['certificate_image_base64'];
          final candidateImg = s['certificate_image_base64'];
          final bestImg = (candidateImg != null && candidateImg.toString().isNotEmpty)
              ? candidateImg
              : existingImg;

          final bestCertIssued = s['certificate_issued'] == true || existing['certificate_issued'] == true;
          final bestHasCert = s['has_certificate'] == true || existing['has_certificate'] == true || (bestImg != null && bestImg.toString().isNotEmpty);
          final bestCertTitle = (s['certificate_title'] != null && s['certificate_title'].toString().isNotEmpty)
              ? s['certificate_title']
              : existing['certificate_title'];

          if (isCandidateNewer) {
            uniqueByExam[eId] = Map<String, dynamic>.from(s);
          }

          if (bestImg != null && bestImg.toString().isNotEmpty) {
            uniqueByExam[eId]!['certificate_image_base64'] = bestImg;
          }
          if (bestHasCert) {
            uniqueByExam[eId]!['has_certificate'] = true;
          }
          if (bestCertIssued) {
            uniqueByExam[eId]!['certificate_issued'] = true;
          }
          if (bestCertTitle != null) {
            uniqueByExam[eId]!['certificate_title'] = bestCertTitle;
          }
        }
      }

      final result = <Map<String, dynamic>>[];
      for (final s in uniqueByExam.values) {
        final max = (s['max_score'] as num? ?? 100).toDouble();
        final score = (s['score'] as num? ?? 0).toDouble();
        final pct = (s['percentage'] as num?)?.toDouble() ?? (max > 0 ? (score / max) * 100 : 0.0);
        final rank = (s['rank'] as num? ?? 0).toInt();
        final hasImg = s['certificate_image_base64'] != null && s['certificate_image_base64'].toString().isNotEmpty;
        final hasCert = s['has_certificate'] == true || hasImg || s['certificate_issued'] == true || pct >= 85.0 || (rank > 0 && rank <= 3 && pct >= 60.0);

        String certTitle = s['certificate_title'] ?? 'شهادة تفوق وامتياز 🎓';
        if (rank == 1) {
          certTitle = 'شهادة المركز الأول والصدارة 🏆';
        } else if (rank == 2) {
          certTitle = 'شهادة المركز الثاني مع مرتبة الشرف 🥈';
        } else if (rank == 3) {
          certTitle = 'شهادة المركز الثالث المتميز 🥉';
        }

        result.add({
          ...s,
          'exam_title': s['exam_title'] ?? 'اختبار تقييمي',
          'max_score': max,
          'score': score,
          'percentage': pct,
          'rank': rank,
          'has_certificate': hasCert,
          'certificate_title': certTitle,
          'exam_date': s['exam_date'] ?? s['date'] ?? '',
        });
      }
      result.sort((a, b) => (b['exam_date'] ?? '').compareTo(a['exam_date'] ?? ''));
      _setCache('exams_$sId', result);
      return result;
    });
  }

  /// بث حي للحصص والواجبات المحددة للمجموعة
  Stream<List<Map<String, dynamic>>> streamGroupSessions(dynamic groupId) {
    if (groupId == null || '$groupId'.isEmpty) return Stream.value([]);
    final gId = '$groupId';
    return _academyRef
        .collection('sessions')
        .where('group_id', isEqualTo: gId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((d) => d.data()).toList();
      list.sort((a, b) => (b['session_date'] ?? '').compareTo(a['session_date'] ?? ''));
      return list;
    });
  }

  /// بث حي لإلغاءات الحصص (تنبيهات طارئة)
  Stream<List<Map<String, dynamic>>> streamGroupCancellations(dynamic groupId) {
    if (groupId == null || '$groupId'.isEmpty) return Stream.value([]);
    final gId = '$groupId';
    return _academyRef
        .collection('cancellations')
        .where('group_id', isEqualTo: gId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((d) => d.data()).toList();
    });
  }

  /// بث حي للمطالبات والمصروفات المالية للطالب
  Stream<List<Map<String, dynamic>>> streamStudentFinancials(dynamic studentId) {
    final sId = '$studentId';
    final clean = sId.replaceAll(RegExp(r'\D'), '');
    final ids = {sId, if (clean.isNotEmpty) clean}.toList();
    return _academyRef
        .collection('financial_claims')
        .where('student_id', whereIn: ids)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((d) => d.data()).toList();
      list.sort((a, b) => (b['session_date'] ?? '').compareTo(a['session_date'] ?? ''));
      return list;
    });
  }

  /// بث حي لمكتبة المذكرات والملخصات الرقمية (PDF)
  Stream<List<Map<String, dynamic>>> streamLessonMaterials({dynamic groupId}) {
    return _academyRef
        .collection('lesson_materials')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['doc_id'] = d.id;
        return data;
      }).toList();

      final filtered = list.where((item) {
        final gId = item['group_id']?.toString() ?? 'all';
        if (gId == 'all' || groupId == null || '$groupId'.isEmpty) return true;
        return gId == '$groupId';
      }).toList();

      filtered.sort((a, b) {
        final aTime = a['created_at']?.toString() ?? '';
        final bTime = b['created_at']?.toString() ?? '';
        return bTime.compareTo(aTime);
      });

      return filtered;
    });
  }

  /// 🚀 بث موحد لكامل بيانات تقرير الطالب (يلغي تداخل الـ 5 StreamBuilders ويقضي على الـ Jank تماماً)
  Stream<Map<String, dynamic>> streamStudentFullReport({
    required dynamic studentId,
    dynamic groupId,
    dynamic studentCode,
  }) {
    return Rx.combineLatest5<
        DocumentSnapshot<Map<String, dynamic>>,
        DocumentSnapshot<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        Map<String, dynamic>>(
      streamStudent(studentId),
      streamGroup(groupId),
      streamStudentAttendance(studentId),
      streamStudentExams(studentId, studentCode),
      streamStudentFinancials(studentId),
      (studentSnap, groupSnap, attendances, exams, financials) {
        return {
          'student': studentSnap.data() ?? {},
          'group': groupSnap.data() ?? {},
          'attendances': attendances,
          'exams': exams,
          'financials': financials,
        };
      },
    );
  }

  /// 🚀 بث موحد للحصص والحضور لتبويب الحصص (يلغي تداخل الـ 3 StreamBuilders)
  Stream<Map<String, dynamic>> streamSessionsAndAttendance({
    required dynamic studentId,
    dynamic groupId,
  }) {
    return Rx.combineLatest3<
        DocumentSnapshot<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        Map<String, dynamic>>(
      streamGroup(groupId),
      streamGroupSessions(groupId),
      streamStudentAttendance(studentId),
      (groupSnap, sessions, attendances) {
        return {
          'group': groupSnap.data() ?? {},
          'sessions': sessions,
          'attendances': attendances,
        };
      },
    );
  }

  /// بث حي لإعدادات ظهور الميزات والأقسام في تطبيق الطالب
  Stream<Map<String, dynamic>> streamAppVisibilityConfig() {
    return _academyRef
        .collection('settings')
        .doc('student_app_visibility')
        .snapshots()
        .map((snap) => snap.data() ?? {});
  }
}
