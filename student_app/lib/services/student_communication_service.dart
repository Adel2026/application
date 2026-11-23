import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentCommunicationService {
  static final StudentCommunicationService instance =
      StudentCommunicationService._internal();
  StudentCommunicationService._internal();

  DocumentReference get _academyRef =>
      FirebaseFirestore.instance.collection('academies').doc('default');

  CollectionReference<Map<String, dynamic>> get _notificationsCol =>
      _academyRef.collection('notifications');

  CollectionReference<Map<String, dynamic>> get _conversationsCol =>
      _academyRef.collection('conversations');

  static const String _keyReadNotifIds = 'read_notifications_ids_set_v2';

  /// الحصول على معرّفات الإشعارات المقروءة للطالب
  Future<Set<String>> getReadNotificationIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyReadNotifIds) ?? [];
    return list.toSet();
  }

  /// تسجيل إشعار معين كمقروء
  Future<void> markNotificationAsRead(String notifId) async {
    if (notifId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_keyReadNotifIds) ?? []).toSet();
    set.add(notifId);
    await prefs.setStringList(_keyReadNotifIds, set.toList());
  }

  /// بث حي للإشعارات الموجهة للطالب أو مجموعته أو جميع الطلاب
  Stream<List<Map<String, dynamic>>> streamStudentNotifications({
    required String studentId,
    String? groupId,
  }) {
    return _notificationsCol
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final targetType = d['target_type'] ?? 'all';
        final targetId = '${d['target_id'] ?? ''}';

        final bool isForMe = targetType == 'all' ||
            (targetType == 'student' && (targetId == studentId || targetId == studentId.replaceAll(RegExp(r'\D'), ''))) ||
            (targetType == 'group' && groupId != null && targetId == groupId);

        if (isForMe) {
          final item = Map<String, dynamic>.from(d);
          item['id'] = item['id'] ?? doc.id;
          list.add(item);
        }
      }
      return list;
    });
  }

  /// حساب عدد الإشعارات غير المقروءة بدقة
  Future<int> getUnreadNotificationsCount(List<Map<String, dynamic>> notifs) async {
    final readIds = await getReadNotificationIds();
    int unread = 0;
    for (final n in notifs) {
      final id = (n['id'] ?? '${n['title']}_${n['created_at']}').toString();
      if (!readIds.contains(id)) {
        unread++;
      }
    }
    return unread;
  }

  /// تسجيل قراءة جميع الإشعارات دفعة واحدة
  Future<void> markNotificationsAsSeen(List<Map<String, dynamic>> notifs) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_keyReadNotifIds) ?? []).toSet();
    for (final n in notifs) {
      final id = (n['id'] ?? '${n['title']}_${n['created_at']}').toString();
      set.add(id);
    }
    await prefs.setStringList(_keyReadNotifIds, set.toList());
  }

  /// بث حي لرسائل المحادثة بين الطالب والمعلم
  Stream<List<Map<String, dynamic>>> streamMessages(String studentId) {
    return _conversationsCol
        .doc(studentId)
        .collection('messages')
        .orderBy('created_at', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// بث حي لعدد الرسائل غير المقروءة الواردة من المعلم للطالب
  Stream<int> streamUnreadMessagesForStudent(String studentId) {
    return _conversationsCol.doc(studentId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return 0;
      return (doc.data()!['unread_student'] as num? ?? 0).toInt();
    });
  }

  /// إرسال رسالة من الطالب إلى المعلم
  Future<void> sendMessageFromStudent({
    required String studentId,
    required String studentName,
    required String studentCode,
    required String text,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    final convRef = _conversationsCol.doc(studentId);
    final msgRef = convRef.collection('messages').doc();

    final batch = FirebaseFirestore.instance.batch();

    // 1. إضافة الرسالة
    batch.set(msgRef, {
      'id': msgRef.id,
      'sender': 'student',
      'sender_name': studentName,
      'text': cleanText,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
    });

    // 2. تحديث رأس المحادثة
    batch.set(convRef, {
      'student_id': studentId,
      'student_name': studentName,
      'student_code': studentCode,
      'last_message': cleanText,
      'last_sender': 'student',
      'last_message_time': FieldValue.serverTimestamp(),
      'unread_teacher': FieldValue.increment(1),
      'unread_student': 0,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// تصفير عداد الرسائل غير المقروءة للطالب عند فتح المحادثة
  Future<void> markConversationReadByStudent(String studentId) async {
    try {
      await _conversationsCol.doc(studentId).update({
        'unread_student': 0,
      });
    } catch (_) {}
  }
}
