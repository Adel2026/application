import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'database/database_service.dart';
import '../models/school_period_model.dart';
import '../models/group_model.dart';
import '../screens/finances_screen.dart';
import '../screens/whatsapp_hub_screen.dart';
import '../screens/curriculum_screen.dart';
import '../screens/timetable_screen.dart';
import '../screens/teacher_chat_screen.dart';
import 'alarm_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;
  static GlobalKey<NavigatorState>? navigatorKey;
  static DatabaseService? databaseService;
  static String? _pendingLaunchPayload;
  static const int dailyReportNotificationId = 99001;
  static const int tomorrowPrepNotificationId = 99002;
  static const int _timetableAlarmIdBase = 400000;

  /// Initialize the notification plugin and channels
  static Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('ic_notification');
    const initSettings = InitializationSettings(android: androidSettings);

    try {
      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse details) {
          debugPrint('Notification clicked with payload: ${details.payload}');
          _handleNotificationPayload(details.payload);
        },
      );
      _isInitialized = true;

      // Register high-priority alarm notification channels for each distinct tone
      try {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (android != null) {
          final channels = [
            const AndroidNotificationChannel(
              'timetable_channel_school_bell_v4',
              'منبه جرس الحصة المدرسي 🔔',
              description: 'صوت جرس الحصة الإلكتروني المباشر لمواعيد الحصص والدروس',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('school_bell'),
              enableVibration: true,
              audioAttributesUsage: AudioAttributesUsage.alarm,
            ),
            const AndroidNotificationChannel(
              'timetable_channel_alarm_clock_v4',
              'منبه الرنين المتصاعد ⏰',
              description: 'صوت منبه رقمي متصاعد لمواعيد الحصص والدروس',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('alarm_clock'),
              enableVibration: true,
              audioAttributesUsage: AudioAttributesUsage.alarm,
            ),
            const AndroidNotificationChannel(
              'timetable_channel_digital_beep_v4',
              'نغمة إلكترونية 🎶',
              description: 'نغمة إلكترونية حديثة لتنبيهات الجدول',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('digital_beep'),
              enableVibration: true,
              audioAttributesUsage: AudioAttributesUsage.alarm,
            ),
            const AndroidNotificationChannel(
              'timetable_channel_gentle_chime_v4',
              'نغمة هادئة 🎵',
              description: 'نغمة هادئة لمواعيد الحصص',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('gentle_chime'),
              enableVibration: true,
              audioAttributesUsage: AudioAttributesUsage.alarm,
            ),
            const AndroidNotificationChannel(
              'teacher_student_messages_channel_v3',
              'رسائل واستفسارات الطلاب 💬',
              description: 'تنبيهات فورية عند وصول رسالة جديدة من أي طالب في السنتر',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('digital_beep'),
              enableVibration: true,
              audioAttributesUsage: AudioAttributesUsage.notification,
            ),
            const AndroidNotificationChannel(
              'timetable_loud_alarms_v2',
              'منبهات الجدول المدرسي الذكية',
              description: 'تنبيهات مجدولة لمواعيد الحصص والدروس بأعلى أولوية وصوت منبه',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
              audioAttributesUsage: AudioAttributesUsage.alarm,
            ),
          ];

          for (final ch in channels) {
            await android.createNotificationChannel(ch);
          }
        }
      } catch (channelErr) {
        debugPrint('Error creating timetable alarm channels: $channelErr');
      }

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        _pendingLaunchPayload = launchDetails?.notificationResponse?.payload;
      }
    } catch (e) {
      debugPrint('Error initializing notification service: $e');
    }
  }

  static void handlePendingNotificationLaunch() {
    final payload = _pendingLaunchPayload;
    _pendingLaunchPayload = null;
    if (payload != null) _handleNotificationPayload(payload);
  }

  static void _handleNotificationPayload(String? value) {
    final payload = value ?? '';
    final navigator = navigatorKey?.currentState;
    if (navigator == null) {
      if (payload.isNotEmpty) _pendingLaunchPayload = payload;
      return;
    }

    if (payload.startsWith('timetable_alarm|')) {
      final parts = payload.split('|');
      // payload: timetable_alarm|$category|$dayName|$scope|$key
      final dayName = parts.length > 2 ? Uri.decodeComponent(parts[2]) : '';
      final key = parts.length > 4
          ? Uri.decodeComponent(parts[4])
          : (parts.length > 3 ? Uri.decodeComponent(parts[3]) : '');
      final isGroup = key.startsWith('group_');
      final domain = isGroup ? 'groups' : 'school';

      navigator.push(
        MaterialPageRoute(
          builder: (_) => TimetableScreen(
            database: databaseService ?? DatabaseService(),
            initialDomain: domain,
            initialDay: dayName.isNotEmpty ? dayName : null,
            highlightTargetKey: key,
          ),
        ),
      );
      return;
    }

    if (payload == 'bell_instant_test') {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => TimetableScreen(
            database: databaseService ?? DatabaseService(),
          ),
        ),
      );
      return;
    }

    if (payload == 'curriculum_prep' || payload == 'navigate_tomorrow_prep') {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => CurriculumScreen(
            database: databaseService ?? DatabaseService(),
          ),
        ),
      );
      return;
    }

    if (payload == 'daily_report_send') {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => WhatsAppHubScreen(
            database: databaseService ?? DatabaseService(),
            initialCategory: ParentServiceCategory.holisticReport,
            promptDailyReportSend: true,
          ),
        ),
      );
      return;
    }

    if (payload.startsWith('unsent_report|')) {
      final parts = payload.split('|');
      final groupId = parts.length > 1 ? parts[1] : null;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => WhatsAppHubScreen(
            database: databaseService ?? DatabaseService(),
            initialCategory: ParentServiceCategory.sessionFollowup,
            initialGroupId: groupId,
          ),
        ),
      );
      return;
    }

    if (payload.startsWith('monthly_report|')) {
      final parts = payload.split('|');
      final groupId = parts.length > 1 ? parts[1] : null;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => WhatsAppHubScreen(
            database: databaseService ?? DatabaseService(),
            initialCategory: ParentServiceCategory.holisticReport,
            initialGroupId: groupId,
            initialReportPeriod: StudentReportPeriod.monthly,
          ),
        ),
      );
      return;
    }
    if (payload == 'navigate_overdue_claims' ||
        payload.contains('overdue') ||
        payload.contains('payment')) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => FinancesScreen(
            database: databaseService ?? DatabaseService(),
            initialTabIndex: 1,
          ),
        ),
      );
      return;
    }

    if (payload.startsWith('chat:')) {
      final parts = payload.split(':');
      final studentId = parts.length > 1 ? parts[1] : '';
      final studentName = parts.length > 2 ? parts[2] : 'طالب';
      final studentCode = parts.length > 3 ? parts[3] : studentId;

      navigator.push(
        MaterialPageRoute(
          builder: (_) => TeacherChatScreen(
            studentId: studentId,
            studentName: studentName,
            studentCode: studentCode,
          ),
        ),
      );
      return;
    }
  }

  static Future<void> scheduleDailyReportNotification({
    required int hour,
    required int minute,
    required bool skipToday,
  }) async {
    await initialize();
    tz_data.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduledDate.isAfter(now) || skipToday) {
      scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      );
    }

    await _plugin.cancel(id: dailyReportNotificationId);
    await _plugin.zonedSchedule(
      id: dailyReportNotificationId,
      title: '📊 تقرير المتابعة اليومي',
      body:
          'حان وقت معاينة تقارير الطلاب الذين سُجل لهم حضور أو غياب في حصة مجدولة اليوم وإرسالها.',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_report_channel',
          'تقارير المتابعة اليومية',
          channelDescription: 'تذكير يومي بمعاينة تقارير الطلاب وإرسالها',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification',
          largeIcon: DrawableResourceAndroidBitmap('ic_notification_large'),
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_report_send',
    );
  }

  static Future<void> cancelDailyReportNotification() async {
    await initialize();
    await _plugin.cancel(id: dailyReportNotificationId);
  }

  // --- إشعارات التحضير لمجموعات الغد (خاص بالمعلم) ---

  static String getTomorrowArabicName([DateTime? fromDate]) {
    final tomorrow = (fromDate ?? DateTime.now()).add(const Duration(days: 1));
    switch (tomorrow.weekday) {
      case DateTime.saturday:
        return 'السبت';
      case DateTime.sunday:
        return 'الأحد';
      case DateTime.monday:
        return 'الإثنين';
      case DateTime.tuesday:
        return 'الثلاثاء';
      case DateTime.wednesday:
        return 'الأربعاء';
      case DateTime.thursday:
        return 'الخميس';
      case DateTime.friday:
        return 'الجمعة';
      default:
        return '';
    }
  }

  static bool isGroupScheduledOnDay(GroupModel g, String dayArabic) {
    final normDay = dayArabic
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا');
    final normDays = g.days
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا');
    final normSchedule = g.schedule
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا');
    return (g.days.isNotEmpty &&
            (g.days.contains(dayArabic) || normDays.contains(normDay))) ||
        (g.schedule.isNotEmpty &&
            (g.schedule.contains(dayArabic) || normSchedule.contains(normDay)));
  }

  static Future<List<GroupModel>> getTomorrowGroups(
    DatabaseService db, [
    DateTime? fromDate,
  ]) async {
    try {
      final allGroups = await db.getGroups();
      final tomorrowArabic = getTomorrowArabicName(fromDate);
      final tomorrowGroups = allGroups
          .where((g) => isGroupScheduledOnDay(g, tomorrowArabic))
          .toList();
      tomorrowGroups.sort(GroupModel.compareByStartTime);
      return tomorrowGroups;
    } catch (_) {
      return [];
    }
  }

  static Future<void> cancelTomorrowGroupsPrepNotification() async {
    await initialize();
    try {
      await _plugin.cancel(id: tomorrowPrepNotificationId);
    } catch (_) {}
  }

  static Future<void> syncTomorrowGroupsPrepNotification([
    DatabaseService? db,
  ]) async {
    await cancelTomorrowGroupsPrepNotification();
  }

  static Future<void> scheduleUnsentReportReminder({
    required String groupId,
    required String groupName,
    required DateTime reminderTime,
    String? date,
  }) async {
    final targetDate = date ?? DateTime.now().toIso8601String().substring(0, 10);
    final db = databaseService ?? DatabaseService();
    try {
      final isAlreadySent = await db.isReportSentForGroupToday(
        groupId: groupId,
        date: targetDate,
      );
      if (isAlreadySent) {
        debugPrint(
            'Report already sent for group $groupId on $targetDate. Skipping reminder scheduling.');
        await cancelUnsentReportReminder(groupId);
        return;
      }
    } catch (e) {
      debugPrint('Error checking if report is sent: $e');
    }

    await initialize();
    tz_data.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    final tzReminderTime = tz.TZDateTime.from(reminderTime, tz.local);
    final notifId = (groupId.hashCode.abs() % 100000) + 700000;
    final payload = 'unsent_report|$groupId|$targetDate';

    await _plugin.cancel(id: notifId);
    await _plugin.zonedSchedule(
      id: notifId,
      title: '🚨 تنبيه تقرير لم يُرسل لولي الأمر!',
      body:
          'تذكير: لم تقم بإرسال تقرير حصة "$groupName" لأولياء الأمور بعد. اضغط هنا للإرسال الآن 📲',
      scheduledDate: tzReminderTime,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'unsent_report_channel',
          'تنبيهات تقارير الحصص غير المرسلة',
          channelDescription:
              'تنبيهات تذكيرية بإرسال تقارير الحصص لأولياء الأمور',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification',
          largeIcon: DrawableResourceAndroidBitmap('ic_notification_large'),
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  static Future<void> cancelUnsentReportReminder(String groupId) async {
    await initialize();
    final notifId = (groupId.hashCode.abs() % 100000) + 700000;
    await _plugin.cancel(id: notifId);
  }

  static Future<void> scheduleMonthlyReportReminder({
    required String groupId,
    required String groupName,
    required DateTime reminderTime,
    required String monthKey,
  }) async {
    final db = databaseService ?? DatabaseService();
    try {
      final isAlreadySent = await db.isMonthlyReportSentForGroup(
        groupId: groupId,
        monthKey: monthKey,
      );
      if (isAlreadySent) {
        debugPrint(
            'Monthly report already sent for group $groupId in $monthKey. Skipping reminder scheduling.');
        await cancelMonthlyReportReminder(groupId);
        return;
      }
    } catch (e) {
      debugPrint('Error checking monthly report sent status: $e');
    }

    await initialize();
    tz_data.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    final tzReminderTime = tz.TZDateTime.from(reminderTime, tz.local);
    final notifId = (groupId.hashCode.abs() % 100000) + 800000;
    final payload = 'monthly_report|$groupId|$monthKey';

    await _plugin.cancel(id: notifId);
    await _plugin.zonedSchedule(
      id: notifId,
      title: '📊 تذكير: موعد إرسال التقرير الشهري والمالي!',
      body:
          'تذكير: انتهت آخر حصص هذا الشهر لمجموعة "$groupName". اضغط هنا لمراجعة وإرسال التقرير الشامل لأولياء الأمور 📲',
      scheduledDate: tzReminderTime,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'monthly_report_channel',
          'تنبيهات التقارير الشهرية والمالية',
          channelDescription:
              'تذكيرات بإرسال التقارير الشهرية والمالية الشاملة لأولياء الأمور بعد آخر حصة في الشهر',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification',
          largeIcon: DrawableResourceAndroidBitmap('ic_notification_large'),
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  static Future<void> cancelMonthlyReportReminder(String groupId) async {
    await initialize();
    final notifId = (groupId.hashCode.abs() % 100000) + 800000;
    await _plugin.cancel(id: notifId);
  }

  static (String channelId, String channelName, AndroidNotificationSound? sound) getAlarmChannelForTone(String tone) {
    switch (tone) {
      case 'school_bell':
        return (
          'timetable_channel_school_bell_v4',
          'منبه جرس الحصة المدرسي 🔔',
          const RawResourceAndroidNotificationSound('school_bell'),
        );
      case 'alarm_clock':
      case 'alarm_climb':
        return (
          'timetable_channel_alarm_clock_v4',
          'منبه الرنين المتصاعد ⏰',
          const RawResourceAndroidNotificationSound('alarm_clock'),
        );
      case 'digital_beep':
        return (
          'timetable_channel_digital_beep_v4',
          'نغمة إلكترونية 🎶',
          const RawResourceAndroidNotificationSound('digital_beep'),
        );
      case 'gentle_melody':
      case 'gentle_chime':
        return (
          'timetable_channel_gentle_chime_v4',
          'نغمة هادئة 🎵',
          const RawResourceAndroidNotificationSound('gentle_chime'),
        );
      default:
        return (
          'timetable_channel_school_bell_v4',
          'منبه جرس الحصة المدرسي 🔔',
          const RawResourceAndroidNotificationSound('school_bell'),
        );
    }
  }

  static Future<bool> scheduleTimetableAlarm({
    required String key,
    required String dayName,
    required String title,
    required String body,
    required int hour,
    required int minute,
    DateTime? scheduledDate,
    int minutesBefore = 0,
    bool isAutomatic = false,
    String? soundTone,
  }) async {
    await initialize();
    tz.TZDateTime? alarmDate;
    DateTimeComponents? matchComponents;
    try {
      tz_data.initializeTimeZones();
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

      var alarmMinutes = hour * 60 + minute - minutesBefore;
      alarmMinutes = ((alarmMinutes % 1440) + 1440) % 1440;
      final alarmHour = alarmMinutes ~/ 60;
      final alarmMinute = alarmMinutes % 60;
      final now = tz.TZDateTime.now(tz.local);

      if (scheduledDate != null) {
        alarmDate = tz.TZDateTime(
          tz.local,
          scheduledDate.year,
          scheduledDate.month,
          scheduledDate.day,
          alarmHour,
          alarmMinute,
        );
        if (!alarmDate.isAfter(now)) return false;
      } else {
        final weekday = _weekdayForArabicName(dayName);
        if (weekday == null) return false;
        var daysUntilAlarm = (weekday - now.weekday + 7) % 7;
        alarmDate = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day + daysUntilAlarm,
          alarmHour,
          alarmMinute,
        );
        if (!alarmDate.isAfter(now)) {
          alarmDate = alarmDate.add(const Duration(days: 7));
        }
        matchComponents = DateTimeComponents.dayOfWeekAndTime;
      }

      String tone = soundTone ?? 'school_bell';
      if (soundTone == null && databaseService != null) {
        try {
          tone = await databaseService!.getSetting('alarm_sound_tone', defaultValue: 'school_bell');
        } catch (_) {}
      }
      final (channelId, channelName, notifSound) = getAlarmChannelForTone(tone);

      final category = isAutomatic ? 'auto' : 'manual';
      final scope = scheduledDate == null
          ? 'weekly'
          : '${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')}';
      final payload =
          'timetable_alarm|$category|${Uri.encodeComponent(dayName)}|$scope|${Uri.encodeComponent(key)}';
      final id = _timetableAlarmId(payload);
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: alarmDate,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription:
                'تنبيهات مجدولة لمواعيد الحصص والدروس بأعلى أولوية وصوت منبه',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'ic_notification',
            playSound: true,
            sound: notifSound,
            enableVibration: true,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: matchComponents,
        payload: payload,
      );
      return true;
    } catch (error) {
      debugPrint('Exact timetable alarm failed ($error), trying inexact fallback...');
      if (alarmDate == null) return false;
      try {
        String tone = soundTone ?? 'school_bell';
        if (soundTone == null && databaseService != null) {
          try {
            tone = await databaseService!.getSetting('alarm_sound_tone', defaultValue: 'school_bell');
          } catch (_) {}
        }
        final (channelId, channelName, notifSound) = getAlarmChannelForTone(tone);

        final category = isAutomatic ? 'auto' : 'manual';
        final scope = scheduledDate == null
            ? 'weekly'
            : '${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')}';
        final payload =
            'timetable_alarm|$category|${Uri.encodeComponent(dayName)}|$scope|${Uri.encodeComponent(key)}';
        final id = _timetableAlarmId(payload);
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: alarmDate,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription:
                  'تنبيهات مجدولة لمواعيد الحصص والدروس بأعلى أولوية وصوت منبه',
              importance: Importance.max,
              priority: Priority.high,
              icon: 'ic_notification',
              playSound: true,
              sound: notifSound,
              enableVibration: true,
              audioAttributesUsage: AudioAttributesUsage.alarm,
              category: AndroidNotificationCategory.alarm,
              fullScreenIntent: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: matchComponents,
          payload: payload,
        );
        return true;
      } catch (fallbackErr) {
        debugPrint('Fallback timetable alarm failed: $fallbackErr');
        return false;
      }
    }
  }

  /// Trigger an immediate bell / alarm notification with audible ringtone
  static Future<void> showInstantSchoolBellNotification({
    String title = 'تجربة جرس الحصة والمنبه 🔔',
    String body = 'جرس الحصة يعمل بصوت مسموع وواضح بنجاح!',
    String? soundTone,
  }) async {
    await initialize();
    String tone = soundTone ?? 'school_bell';
    if (soundTone == null && databaseService != null) {
      try {
        tone = await databaseService!.getSetting('alarm_sound_tone', defaultValue: 'school_bell');
      } catch (_) {}
    }
    final (channelId, channelName, notifSound) = getAlarmChannelForTone(tone);
    try {
      await _plugin.show(
        id: 99991,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: 'تنبيهات مجدولة لمواعيد الحصص والدروس بأعلى أولوية وصوت منبه',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'ic_notification',
            playSound: true,
            sound: notifSound,
            enableVibration: true,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
          ),
        ),
        payload: 'bell_instant_test',
      );
    } catch (e) {
      debugPrint('Error showing instant bell notification: $e');
    }
  }

  static String _normalizeDay(String? d) {
    if (d == null) return '';
    return d
        .trim()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه');
  }

  static Future<int> cancelTimetableAlarms({
    String? dayName,
    DateTime? scheduledDate,
    bool automaticOnly = false,
  }) async {
    await initialize();
    final requests = await _plugin.pendingNotificationRequests();
    final normalizedTargetDay = dayName != null ? _normalizeDay(dayName) : null;
    final dateToken = scheduledDate == null
        ? null
        : '|${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')}|';
    var cancelled = 0;
    for (final request in requests) {
      final payload = request.payload ?? '';
      final isTimetableId = request.id >= _timetableAlarmIdBase &&
          request.id < _timetableAlarmIdBase + 1000000;
      final isTimetablePayload = payload.startsWith('timetable_alarm|');

      if (!isTimetableId && !isTimetablePayload) continue;

      if (automaticOnly && !payload.startsWith('timetable_alarm|auto|')) {
        continue;
      }
      if (normalizedTargetDay != null) {
        final parts = payload.split('|');
        if (parts.length >= 3) {
          final payloadDay = Uri.decodeComponent(parts[2]);
          if (_normalizeDay(payloadDay) != normalizedTargetDay) {
            continue;
          }
        } else if (!payload.contains('|${Uri.encodeComponent(dayName!)}|')) {
          continue;
        }
      }
      if (dateToken != null && !payload.contains(dateToken)) continue;
      await _plugin.cancel(id: request.id);
      cancelled++;
    }
    return cancelled;
  }

  /// Cancel a specific alarm by key (e.g. 'period_12' or 'group_5')
  /// When [dateSpecificOnly] is true, recurring weekly alarms are preserved and never cancelled.
  static Future<bool> cancelAlarmByKey(String key, {bool dateSpecificOnly = false}) async {
    await initialize();
    final requests = await _plugin.pendingNotificationRequests();
    final encodedKey = Uri.encodeComponent(key);
    var found = false;
    for (final request in requests) {
      final payload = request.payload ?? '';
      if (payload.startsWith('timetable_alarm|') &&
          payload.endsWith('|$encodedKey')) {
        if (dateSpecificOnly) {
          final parts = payload.split('|');
          // Format: timetable_alarm|category|dayName|scope|key
          // Never cancel recurring weekly alarms during routine daily expired-periods cleanup!
          if (parts.length >= 4 && parts[3] == 'weekly') {
            continue;
          }
        }
        await _plugin.cancel(id: request.id);
        found = true;
      }
    }
    return found;
  }

  /// Automatically cancel all expired and past timetable alarms and notifications
  static Future<int> cancelExpiredAndPastAlarms() async {
    await initialize();
    final requests = await _plugin.pendingNotificationRequests();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var cancelled = 0;

    for (final request in requests) {
      final payload = request.payload ?? '';
      if (!payload.startsWith('timetable_alarm|')) continue;
      final parts = payload.split('|');
      // Format: timetable_alarm|category|dayName|scope|key
      if (parts.length >= 4) {
        final scope = parts[3];
        // If scope is a specific date: YYYY-MM-DD
        if (scope.contains('-')) {
          try {
            final dateParts = scope.split('-');
            if (dateParts.length == 3) {
              final scheduledDate = DateTime(
                int.parse(dateParts[0]),
                int.parse(dateParts[1]),
                int.parse(dateParts[2]),
              );
              // If scheduled date is before today, it has expired!
              if (scheduledDate.isBefore(today)) {
                await _plugin.cancel(id: request.id);
                cancelled++;
              }
            }
          } catch (_) {}
        }
      }
    }
    return cancelled;
  }

  /// Cancel alarms for today's periods or groups whose time has already passed
  static Future<int> cancelAlarmsForPassedPeriodsToday({
    required List<SchoolPeriodModel> todayPeriods,
    required List<GroupModel> todayGroups,
    required String todayArabic,
  }) async {
    await initialize();
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    final normToday = _normalizeDay(todayArabic);
    var cancelled = 0;

    // 1. Periods whose end time has passed
    for (final period in todayPeriods) {
      if (_normalizeDay(period.dayOfWeek) != normToday) continue;
      final parsed = AlarmService.parseTimeString(period.endTime);
      if (parsed != null) {
        final periodEndMin = parsed.$1 * 60 + parsed.$2;
        // If period has finished (past end time) - cancel only today's single date alarm, NEVER weekly
        if (currentMinutes > periodEndMin) {
          final ok = await cancelAlarmByKey('period_${period.id}', dateSpecificOnly: true);
          if (ok) cancelled++;
        }
      }
    }

    // 2. Groups whose time has passed
    for (final group in todayGroups) {
      if (group.startTime.trim().isEmpty) continue;
      final parsed = AlarmService.parseTimeString(group.startTime);
      if (parsed != null) {
        final groupEndMin = parsed.$1 * 60 + parsed.$2 + 60; // 1 hour after start
        if (currentMinutes > groupEndMin) {
          final ok = await cancelAlarmByKey('group_${group.id}', dateSpecificOnly: true);
          if (ok) cancelled++;
        }
      }
    }

    return cancelled;
  }

  static int? _weekdayForArabicName(String dayName) {
    final norm = _normalizeDay(dayName);
    if (norm.contains('اثنين')) return DateTime.monday;
    if (norm.contains('ثلاثاء')) return DateTime.tuesday;
    if (norm.contains('اربعاء')) return DateTime.wednesday;
    if (norm.contains('خميس')) return DateTime.thursday;
    if (norm.contains('جمعه')) return DateTime.friday;
    if (norm.contains('سبت')) return DateTime.saturday;
    if (norm.contains('احد')) return DateTime.sunday;
    return null;
  }

  static int _timetableAlarmId(String payload) {
    var hash = 17;
    for (final unit in payload.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _timetableAlarmIdBase + hash % 1000000;
  }

  /// Request runtime permission (especially for Android 13+)
  static Future<bool> requestPermissions() async {
    await initialize();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
    }
    return false;
  }

  /// Generic notification helper
  static Future<void> showNotification({
    int? id,
    required String title,
    required String body,
    String channelId = 'center_alerts',
    String channelName = 'تنبيهات السنتر العامة',
    String? payload,
  }) async {
    await initialize();

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'إشعارات وتنبيهات سنتر أستاذي التعليمي',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'ic_notification',
      largeIcon: const DrawableResourceAndroidBitmap('ic_notification_large'),
      color: const Color(0xFF1E3A8A),
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    final details = NotificationDetails(android: androidDetails);
    final notificationId = id ?? Random().nextInt(100000);

    try {
      await _plugin.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  /// Absence alert notification
  static Future<void> showAbsenceAlert({
    required String studentName,
    required String groupName,
  }) async {
    await showNotification(
      title: '🚨 تنبيه غياب طالب',
      body:
          'تم تسجيل غياب الطالب "$studentName" في $groupName. تم تجهيز رسالة التنبيه لولي الأمر.',
      channelId: 'attendance_alerts',
      channelName: 'تنبيهات الحضور والغياب',
    );
  }

  /// Attendance confirmation notification
  static Future<void> showAttendanceConfirmation({
    required String studentName,
    required String time,
  }) async {
    await showNotification(
      title: '✅ تسجيل حضور ناجح',
      body: 'تم تسجيل حضور الطالب "$studentName" بنجاح الساعة $time.',
      channelId: 'attendance_alerts',
      channelName: 'تنبيهات الحضور والغياب',
    );
  }

  /// Session upcoming reminder notification
  static Future<void> showSessionReminder({
    required String groupName,
    required String time,
  }) async {
    await showNotification(
      title: '🔔 تذكير بموعد حصة اليوم',
      body:
          'موعد حصة "$groupName" اليوم الساعة $time. تأكد من جاهزية القاعة والمنهج.',
      channelId: 'session_reminders',
      channelName: 'تذكير مواعيد الحصص',
    );
  }

  /// Payment due alert notification
  static Future<void> showPaymentDueAlert({
    required String studentName,
    required double amount,
    String? payload,
  }) async {
    await showNotification(
      title: '💳 تنبيه مستحقات متأخرة',
      body: 'يوجد مستحقات متأخرة على الطالب "$studentName" بقيمة $amount ج.م.',
      channelId: 'payment_alerts',
      channelName: 'تنبيهات الاشتراكات والمتأخرات',
      payload: payload ?? 'navigate_overdue_claims',
    );
  }

  /// Test notification
  static Future<void> showTestNotification() async {
    await showNotification(
      title: '🔔 إشعار تجريبي ناجح من سنتر أستاذي',
      body: 'نظام الإشعارات وتنبيهات الواتساب يعمل بكفاءة تامة على هاتفك! 🎉',
      channelId: 'center_alerts',
      channelName: 'تنبيهات السنتر العامة',
    );
  }

  /// School Period Start Alert Notification
  static Future<void> showPeriodStartAlert({
    required String periodName,
    required String className,
    String? subject,
    String? room,
    String? payload,
  }) async {
    final subStr = (subject != null && subject.isNotEmpty)
        ? ' • مادة $subject'
        : '';
    final roomStr = (room != null && room.isNotEmpty) ? ' (📍 $room)' : '';
    await showNotification(
      title: '🟢 بدأت الآن: $periodName - فصل $className',
      body: 'حان موعد بدء الحصة$subStr$roomStr. جاهز للبدء مع طلابك! 🔔',
      channelId: 'school_period_alerts',
      channelName: 'تنبيهات الحصص المدرسية',
      payload: payload,
    );
  }

  /// School Period End Alert Notification
  static Future<void> showPeriodEndAlert({
    required String periodName,
    required String className,
    String? nextInfo,
    String? payload,
  }) async {
    final nextStr = (nextInfo != null && nextInfo.isNotEmpty)
        ? '\nالموعد التالي: $nextInfo'
        : '';
    await showNotification(
      title: '🏁 انتهت الحصة: $periodName - فصل $className',
      body: 'دق جرس نهاية الحصة.$nextStr ☕',
      channelId: 'school_period_alerts',
      channelName: 'تنبيهات الحصص المدرسية',
      payload: payload,
    );
  }

  /// Upcoming Period Reminder (e.g. 5 minutes before)
  static Future<void> showUpcomingPeriodReminder({
    required String periodName,
    required String className,
    required String startTime,
    String? subject,
    String? payload,
  }) async {
    final subStr = (subject != null && subject.isNotEmpty) ? ' ($subject)' : '';
    await showNotification(
      title: '⏰ اقتربت الحصة: $periodName - فصل $className',
      body: 'تبدأ الحصة$subStr الساعة $startTime (خلال دقائق قليلة). 📚',
      channelId: 'school_period_alerts',
      channelName: 'تنبيهات الحصص المدرسية',
      payload: payload,
    );
  }

  /// إشعار صوتي فوري عند استلام رسالة جديدة من طالب
  static Future<void> showStudentMessageNotification({
    required String studentId,
    required String studentName,
    required String studentCode,
    required String messageText,
  }) async {
    await initialize();

    const channelId = 'teacher_student_messages_channel_v3';
    const channelName = 'رسائل واستفسارات الطلاب 💬';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'تنبيهات فورية عند وصول رسالة جديدة من أي طالب في السنتر',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'ic_notification',
      largeIcon: const DrawableResourceAndroidBitmap('ic_notification_large'),
      color: const Color(0xFF00B4D8),
      showWhen: true,
      enableVibration: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('digital_beep'),
      audioAttributesUsage: AudioAttributesUsage.notification,
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      try {
        await SystemSound.play(SystemSoundType.click);
        await HapticFeedback.heavyImpact();
      } catch (_) {}

      await _plugin.show(
        id: (studentId.hashCode.abs() % 100000) + 500000,
        title: 'رسالة جديدة من $studentName 🎓',
        body: messageText,
        notificationDetails: details,
        payload: 'chat:$studentId:$studentName:$studentCode',
      );
    } catch (e) {
      debugPrint('Error showing student message notification: $e');
    }
  }
}
