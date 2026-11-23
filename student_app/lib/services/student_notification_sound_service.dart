import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'student_auth_service.dart';

class StudentNotificationSoundService {
  static final StudentNotificationSoundService instance =
      StudentNotificationSoundService._internal();
  StudentNotificationSoundService._internal();

  static final ValueNotifier<String?> onNotificationPayloadClicked =
      ValueNotifier<String?>(null);

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  StreamSubscription? _announcementSub;
  StreamSubscription? _messageSub;
  DateTime _serviceStartTime = DateTime.now();

  static const String _announcementChannelId = 'student_announcements_channel_v2';
  static const String _messagesChannelId = 'student_messages_channel_v2';

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    _serviceStartTime = DateTime.now();

    // 1. Configure Android initialization settings
    const androidSettings = AndroidInitializationSettings('ic_notification');
    const initSettings = InitializationSettings(android: androidSettings);

    try {
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse details) {
          debugPrint('🔔 [NotificationClicked] payload: ${details.payload}');
          if (details.payload != null && details.payload!.isNotEmpty) {
            onNotificationPayloadClicked.value = details.payload;
          }
        },
      );
    } catch (e) {
      debugPrint('🔔 Error initializing local notifications: $e');
    }

    // 2. Register Android Notification Channels
    try {
      final android = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        // طلب تصريح الإشعارات في أندرويد 13+
        await android.requestNotificationsPermission();

        // قناة إشعارات الأكاديمية والتنبيهات
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            _announcementChannelId,
            'إعلانات وتنبيهات الأكاديمية 📢',
            description: 'تنبيهات الحصص والاختبارات والمواعيد الهامة',
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('gentle_chime'),
            enableVibration: true,
            audioAttributesUsage: AudioAttributesUsage.notification,
          ),
        );

        // قناة رسائل المعلم الخاصة
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            _messagesChannelId,
            'رسائل المعلم الخاصة 💬',
            description: 'رسائل وتنبيهات المعلم المباشرة مع الطالب',
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('digital_beep'),
            enableVibration: true,
            audioAttributesUsage: AudioAttributesUsage.notification,
          ),
        );
      }
    } catch (e) {
      debugPrint('🔔 Error registering channels: $e');
    }

    // 3. Start active Firestore listeners for incoming alerts & messages
    startListeningToEvents();

    debugPrint('🔔 [StudentNotificationSoundService] Initialized successfully with custom sounds.');
  }

  /// تشغيل استجابة صوتية واهتزازية داخل التطبيق عند إرسال أو استلام رسالة
  Future<void> playInAppFeedback({bool isMessage = true}) async {
    try {
      await SystemSound.play(SystemSoundType.click);
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// إظهار إشعار نظام أندرويد منبثق (Heads-Up) مع صوت الإعلان المخصص (gentle_chime)
  Future<void> showAnnouncementNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    // منع أي رسائل منبثقة تفيد بتفعيل الإشعارات نهائياً
    if (title.contains('تم تفعيل') || body.contains('تم تفعيل') || title.contains('تفعيل الإشعار')) {
      return;
    }

    playInAppFeedback(isMessage: false);

    const androidDetails = AndroidNotificationDetails(
      _announcementChannelId,
      'إعلانات وتنبيهات الأكاديمية 📢',
      channelDescription: 'تنبيهات الحصص والاختبارات والمواعيد الهامة',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('gentle_chime'),
      playSound: true,
      enableVibration: true,
      icon: 'ic_notification',
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    try {
      await _localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('🔔 Error showing announcement notification: $e');
    }
  }

  /// إظهار إشعار نظام أندرويد منبثق (Heads-Up) لرسائل المعلم مع صوت الرسائل المخصص (digital_beep)
  Future<void> showMessageNotification({
    required String senderName,
    required String text,
    String? payload,
  }) async {
    playInAppFeedback(isMessage: true);

    const androidDetails = AndroidNotificationDetails(
      _messagesChannelId,
      'رسائل المعلم الخاصة 💬',
      channelDescription: 'رسائل وتنبيهات المعلم المباشرة مع الطالب',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('digital_beep'),
      playSound: true,
      enableVibration: true,
      icon: 'ic_notification',
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    try {
      await _localNotifications.show(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1,
        title: 'رسالة جديدة من $senderName 👨‍🏫',
        body: text,
        notificationDetails: notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('🔔 Error showing message notification: $e');
    }
  }

  /// بدء الاستماع السحابي الحي للإعلانات والرسائل الجديدة
  void startListeningToEvents() {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    final groupId = student?['group_id'];

    _announcementSub?.cancel();
    _messageSub?.cancel();
    _serviceStartTime = DateTime.now();

    final firestore = FirebaseFirestore.instance;
    final academyRef = firestore.collection('academies').doc('default');

    bool isInitialAnnouncementSnapshot = true;
    // 1. الاستماع للإعلانات والتنبيهات العامة والخاصة (تجاهل الإشعارات السابقة عند فتح التطبيق)
    _announcementSub = academyRef
        .collection('notifications')
        .snapshots()
        .listen((snap) {
      if (isInitialAnnouncementSnapshot) {
        isInitialAnnouncementSnapshot = false;
        return;
      }

      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data();
          if (d == null) continue;

          final title = (d['title'] ?? '').toString();
          final body = (d['body'] ?? '').toString();

          if (title.contains('تم تفعيل') || body.contains('تم تفعيل') || title.contains('تفعيل الإشعار')) {
            continue;
          }

          final targetType = d['target_type'] ?? 'all';
          final targetId = '${d['target_id'] ?? ''}';

          final bool isForMe = targetType == 'all' ||
              (targetType == 'student' &&
                  (targetId == studentId ||
                      targetId == studentId.replaceAll(RegExp(r'\D'), ''))) ||
              (targetType == 'group' && groupId != null && targetId == groupId);

          if (isForMe) {
            final type = d['type'] ?? 'general';
            showAnnouncementNotification(
              title: title.isNotEmpty ? title : 'تنبيه أكاديمي جديد 📢',
              body: body,
              payload: 'type:$type',
            );
          }
        }
      }
    });

    bool isInitialMessageSnapshot = true;
    // 2. الاستماع للرسائل الواردة من المعلم
    if (studentId.isNotEmpty) {
      _messageSub = academyRef
          .collection('conversations')
          .doc(studentId)
          .collection('messages')
          .snapshots()
          .listen((snap) {
        if (isInitialMessageSnapshot) {
          isInitialMessageSnapshot = false;
          return;
        }

        for (final change in snap.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final d = change.doc.data();
            if (d == null) continue;

            final sender = d['sender'] ?? '';
            final ts = d['created_at'];
            DateTime? createdDate;
            if (ts is Timestamp) {
              createdDate = ts.toDate();
            }

            if (sender == 'teacher' &&
                createdDate != null &&
                createdDate.isAfter(_serviceStartTime.subtract(const Duration(seconds: 10)))) {
              final senderName = d['sender_name'] ?? 'المعلم';
              final text = d['text'] ?? '';
              showMessageNotification(
                senderName: senderName,
                text: text,
                payload: 'type:chat',
              );
            }
          }
        }
      });
    }
  }

  void dispose() {
    _announcementSub?.cancel();
    _messageSub?.cancel();
  }
}
