import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'notification_service.dart';

class AcademyCommunicationService {
  static final AcademyCommunicationService instance =
      AcademyCommunicationService._internal();
  AcademyCommunicationService._internal();

  DocumentReference get _academyRef =>
      FirebaseFirestore.instance.collection('academies').doc('default');

  CollectionReference<Map<String, dynamic>> get _notificationsCol =>
      _academyRef.collection('notifications');

  CollectionReference<Map<String, dynamic>> get _conversationsCol =>
      _academyRef.collection('conversations');

  DocumentReference<Map<String, dynamic>> get _chatAssetsDoc =>
      _academyRef.collection('settings').doc('chat_assets');

  /// بث حي للإيموجي والملصقات المخصصة من السحابة
  Stream<Map<String, dynamic>> streamChatAssets() {
    return _chatAssetsDoc.snapshots().map((snap) => snap.data() ?? {});
  }

  /// إضافة إيموجي أو ملصق جديد من قبل المعلم
  Future<void> addChatAsset({
    required String type, // 'emoji' or 'sticker'
    required String value, // emoji character or image URL
    String category = 'عام',
  }) async {
    final field = type == 'sticker' ? 'custom_stickers' : 'custom_emojis';
    await _chatAssetsDoc.set({
      field: FieldValue.arrayUnion([
        {
          'value': value.trim(),
          'category': category.trim(),
          'created_at': DateTime.now().toIso8601String(),
        }
      ]),
    }, SetOptions(merge: true));
  }

  /// حذف إيموجي أو ملصق
  Future<void> removeChatAsset({
    required String type,
    required Map<String, dynamic> item,
  }) async {
    final field = type == 'sticker' ? 'custom_stickers' : 'custom_emojis';
    await _chatAssetsDoc.set({
      field: FieldValue.arrayRemove([item]),
    }, SetOptions(merge: true));
  }

  /// 📢 إرسال إشعار / تنبيه للطلاب
  Future<void> sendNotification({
    required String title,
    required String body,
    String type = 'general', // general, session, exam, financial, urgent
    String targetType = 'all', // all, group, student
    String targetId = 'all',
    String targetName = 'جميع الطلاب',
  }) async {
    final docRef = _notificationsCol.doc();
    await docRef.set({
      'id': docRef.id,
      'title': title.trim(),
      'body': body.trim(),
      'type': type,
      'target_type': targetType,
      'target_id': targetId,
      'target_name': targetName,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': 'المعلم',
    });
  }

  /// حذف إشعار
  Future<void> deleteNotification(String notificationId) async {
    await _notificationsCol.doc(notificationId).delete();
  }

  /// بث حي لجميع الإشعارات الصادرة (للمعلم)
  Stream<List<Map<String, dynamic>>> streamAllNotifications() {
    return _notificationsCol
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// بث حي للمحادثات الحالية بين المعلم والطلاب
  Stream<List<Map<String, dynamic>>> streamConversations() {
    return _conversationsCol
        .orderBy('last_message_time', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// بث حي للرسائل داخل محادثة طالب معين
  Stream<List<Map<String, dynamic>>> streamMessages(String studentId) {
    return _conversationsCol
        .doc(studentId)
        .collection('messages')
        .orderBy('created_at', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// إرسال رسالة من المعلم للطالب
  Future<void> sendMessageFromTeacher({
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
      'sender': 'teacher',
      'sender_name': 'المعلم',
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
      'last_sender': 'teacher',
      'last_message_time': FieldValue.serverTimestamp(),
      'unread_student': FieldValue.increment(1),
      'unread_teacher': 0,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// تصفير عداد الرسائل غير المقروءة للمعلم عند فتح المحادثة
  Future<void> markConversationReadByTeacher(String studentId) async {
    try {
      await _conversationsCol.doc(studentId).update({
        'unread_teacher': 0,
      });
    } catch (_) {}
  }

  /// إجمالي عدد الرسائل غير المقروءة الواردة من الطلاب
  Stream<int> streamTotalUnreadMessagesForTeacher() {
    return _conversationsCol.snapshots().map((snap) {
      int total = 0;
      for (final doc in snap.docs) {
        final count = (doc.data()['unread_teacher'] as num? ?? 0).toInt();
        total += count;
      }
      return total;
    });
  }

  StreamSubscription? _incomingMessagesSubscription;
  DateTime _serviceStartTime = DateTime.now();
  String? activeChatStudentId;

  /// بدء الاستماع السحابي لرسائل الطلاب الواردة وإطلاق إشعار صوتي فوري للمعلم
  void startListeningForStudentMessages() {
    _incomingMessagesSubscription?.cancel();
    _serviceStartTime = DateTime.now();

    _incomingMessagesSubscription = _conversationsCol.snapshots().listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.modified ||
            change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          final lastSender = data['last_sender'];
          final lastMsgTime = data['last_message_time'];
          DateTime? msgDate;
          if (lastMsgTime is Timestamp) {
            msgDate = lastMsgTime.toDate();
          }

          final studentId = data['student_id'] ?? change.doc.id;
          final studentName = data['student_name'] ?? 'طالب';
          final lastMsg = data['last_message'] ?? 'رسالة جديدة';
          final studentCode = data['student_code'] ?? studentId;

          // التحقق من أن الرسالة واردة من طالب
          if (lastSender != 'student') continue;

          // إذا كانت المحادثة موجودة مسبقاً وتم جلبها عند فتح التطبيق، نتأكد من حداثتها
          if (change.type == DocumentChangeType.added) {
            if (msgDate == null ||
                msgDate.isBefore(_serviceStartTime.subtract(const Duration(seconds: 15)))) {
              continue;
            }
          }

          // إذا كان المعلم فاتح شاشة المحادثة مع هذا الطالب حالياً، نكتفي بصوت نقرة هادئ
          if (activeChatStudentId == studentId) {
            SystemSound.play(SystemSoundType.click);
            continue;
          }

          // إطلاق إشعار عالي الأهمية مع نغمة التنبيه الكاملة والاهتزاز
          NotificationService.showStudentMessageNotification(
            studentId: studentId,
            studentName: studentName,
            studentCode: studentCode,
            messageText: lastMsg,
          );
        }
      }
    });
  }
}
