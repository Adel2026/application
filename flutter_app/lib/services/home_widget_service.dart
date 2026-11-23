import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import '../models/group_model.dart';
import '../core/database/database_service.dart';

class HomeWidgetService {
  static const String androidWidgetName = 'NextSessionWidgetProvider';
  static const String qualifiedAndroidName =
      'com.example.teacher_center.NextSessionWidgetProvider';

  /// Requests the Android OS to pin the Next Session widget directly to the home screen
  static Future<bool> pinWidgetToHomeScreen() async {
    try {
      const channel = MethodChannel('com.example.teacher_center/shortcut');
      final res = await channel.invokeMethod<bool>('pinWidget');
      return res ?? false;
    } catch (e) {
      debugPrint('Error pinning widget: $e');
      return false;
    }
  }

  /// Initializes widget listeners and checks for initial launch from widget
  static Future<void> initialize({
    Function(Uri? uri)? onWidgetClick,
  }) async {
    try {
      HomeWidget.widgetClicked.listen((Uri? uri) {
        if (uri != null && onWidgetClick != null) {
          onWidgetClick(uri);
        }
      });

      final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initialUri != null && onWidgetClick != null) {
        onWidgetClick(initialUri);
      }
    } catch (e) {
      debugPrint('Error initializing HomeWidgetService: $e');
    }
  }

  /// Updates the next session widget with latest database information
  static Future<void> updateNextSessionWidget({
    required DatabaseService database,
  }) async {
    try {
      final groups = await database.getGroups();
      if (groups.isEmpty) {
        await _saveAndRefresh(
          hasSession: false,
          title: 'سنتر أستاذي التعليمي',
          groupName: 'لا توجد مجموعات مسجلة',
          grade: 'ابدأ بإضافة أول مجموعة',
          time: '--:--',
          room: '',
          groupId: '',
        );
        return;
      }

      final now = DateTime.now();
      final dayNames = [
        'الاثنين',
        'الثلاثاء',
        'الأربعاء',
        'الخميس',
        'الجمعة',
        'السبت',
        'الأحد',
      ];
      final currentDay = dayNames[now.weekday - 1];
      final tomorrowDay = dayNames[now.weekday % 7];

      // Groups today
      final todayGroups = groups.where((g) => g.schedule.contains(currentDay)).toList();

      if (todayGroups.isNotEmpty) {
        // Try to sort by time if extractable
        todayGroups.sort((a, b) => _extractMinutes(a.schedule).compareTo(_extractMinutes(b.schedule)));

        // Find next session that hasn't arrived yet; advances to the next session as soon as scheduled time arrives
        final currentMinutes = now.hour * 60 + now.minute;
        GroupModel? foundGroup;
        for (final g in todayGroups) {
          final groupMinutes = _extractMinutes(g.schedule);
          if (groupMinutes > currentMinutes) {
            foundGroup = g;
            break;
          }
        }

        if (foundGroup != null) {
          final targetGroup = foundGroup;
          final timeStr = _extractTimeLabel(targetGroup.schedule);

          await _saveAndRefresh(
            hasSession: true,
            title: 'الحصة القادمة اليوم ⏰',
            groupName: targetGroup.name,
            grade: targetGroup.grade,
            time: timeStr.isNotEmpty ? timeStr : 'اليوم',
            room: targetGroup.room.isNotEmpty
                ? 'قاعة ${targetGroup.room}'
                : '',
            groupId: targetGroup.id,
          );
          return;
        }
      }

      // Check tomorrow groups
      final tomorrowGroups = groups.where((g) => g.schedule.contains(tomorrowDay)).toList();
      if (tomorrowGroups.isNotEmpty) {
        tomorrowGroups.sort((a, b) => _extractMinutes(a.schedule).compareTo(_extractMinutes(b.schedule)));
        final firstTomorrow = tomorrowGroups.first;
        final timeStr = _extractTimeLabel(firstTomorrow.schedule);

        await _saveAndRefresh(
          hasSession: true,
          title: 'حصة الغد القادمة 📅',
          groupName: firstTomorrow.name,
          grade: firstTomorrow.grade,
          time: timeStr.isNotEmpty ? 'غداً $timeStr' : 'غداً',
          room: firstTomorrow.room.isNotEmpty
              ? 'قاعة ${firstTomorrow.room}'
              : '',
          groupId: firstTomorrow.id,
        );
        return;
      }

      // Fallback: no sessions today or tomorrow
      final firstGroup = groups.first;
      await _saveAndRefresh(
        hasSession: false,
        title: 'سنتر أستاذي التعليمي',
        groupName: 'اكتملت حصص اليوم ✅',
        grade: 'لا توجد حصص متبقية اليوم',
        time: '--:--',
        room: '',
        groupId: firstGroup.id,
      );
    } catch (e) {
      dev.log('HomeWidget update error: $e');
    }
  }

  static Future<void> _saveAndRefresh({
    required bool hasSession,
    required String title,
    required String groupName,
    required String grade,
    required String time,
    required String room,
    required String groupId,
  }) async {
    await HomeWidget.saveWidgetData<bool>('widget_has_session', hasSession);
    await HomeWidget.saveWidgetData<String>('widget_title', title);
    await HomeWidget.saveWidgetData<String>('widget_group_name', groupName);
    await HomeWidget.saveWidgetData<String>('widget_grade', grade);
    await HomeWidget.saveWidgetData<String>('widget_time', time);
    await HomeWidget.saveWidgetData<String>('widget_room', room);
    await HomeWidget.saveWidgetData<String>('widget_group_id', groupId);

    await HomeWidget.updateWidget(
      name: androidWidgetName,
      androidName: androidWidgetName,
      qualifiedAndroidName: qualifiedAndroidName,
    );
  }

  static int _extractMinutes(String schedule) {
    try {
      final regExp = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM|am|pm|ص|م)?');
      final match = regExp.firstMatch(schedule);
      if (match != null) {
        int hour = int.parse(match.group(1)!);
        int minute = int.parse(match.group(2)!);
        final marker = match.group(3)?.toUpperCase();
        if (marker == 'PM' || marker == 'م') {
          if (hour < 12) hour += 12;
        } else if (marker == 'AM' || marker == 'ص') {
          if (hour == 12) hour = 0;
        }
        return hour * 60 + minute;
      }
    } catch (_) {}
    return 720; // default 12:00 PM
  }

  static String _extractTimeLabel(String schedule) {
    try {
      final regExp = RegExp(r'(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm|ص|م)?)');
      final match = regExp.firstMatch(schedule);
      if (match != null) {
        return match.group(1)!;
      }
    } catch (_) {}
    return '';
  }
}
