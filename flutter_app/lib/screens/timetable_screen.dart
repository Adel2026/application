import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/ai_timetable_parser_service.dart';
import '../core/alarm_service.dart';
import '../core/database/database_service.dart';
import '../core/notification_service.dart';
import '../core/schedule_conflict_service.dart';
import '../core/school_timetable_excel_service.dart';
import '../models/exceptional_session_model.dart';
import '../models/school_period_model.dart';
import '../models/group_model.dart';
import '../models/student_model.dart';
import 'groups_screen.dart';
import 'today_attendance_screen.dart';
import 'alarm_clock_screen.dart';

class TimetableScreen extends StatefulWidget {
  final DatabaseService database;
  final VoidCallback? onBack;
  final String? initialDomain; // 'school' or 'groups'
  final String? initialDay; // 'الأحد', 'الإثنين', etc.
  final String? highlightTargetKey; // 'period_12' or 'group_5'

  const TimetableScreen({
    super.key,
    required this.database,
    this.onBack,
    this.initialDomain,
    this.initialDay,
    this.highlightTargetKey,
  });

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  // Target session to highlight with neon glow
  String? _highlightTargetKey;
  final GlobalKey _highlightedItemKey = GlobalKey();
  bool _hasAutoScrolled = false;

  // Design Theme: 'cyber' (نيون عصري Bento) vs 'classic' (جدول شبكي كامل)
  String _designTheme = 'cyber';

  // Sub-view for classic mode: 'grid' vs 'daily'
  String _schoolViewMode = 'grid';

  // Selected Day
  String _selectedDay = 'الأحد';

  // Weekdays (الأيام الدراسية)
  static const List<String> _schoolWeekdays = [
    'الأحد',
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
  ];

  // Configurable Period Timings
  final Map<int, ({String start, String end})> _periodTimings = {
    1: (start: '08:00', end: '08:45'),
    2: (start: '08:50', end: '09:35'),
    3: (start: '09:40', end: '10:25'),
    4: (start: '11:00', end: '11:45'),
    5: (start: '11:50', end: '12:35'),
    6: (start: '12:40', end: '01:25'),
    7: (start: '01:30', end: '02:15'),
    8: (start: '02:20', end: '03:05'),
  };

  int _recessAfterPeriod = 3;
  String _recessStartTime = '10:25';
  String _recessEndTime = '10:55';

  // Teacher's Supervision Duties (إشراف الطابور وإشراف البريك)
  String _morningAssemblyDutyDay = 'الأحد';
  String _morningAssemblyStartTime = '07:15';
  String _morningAssemblyEndTime = '07:45';
  String _morningAssemblyLocation = 'فناء المدرسة';
  String _breakDutyDay = 'الثلاثاء';
  String _breakDutyLocation = 'فناء المدرسة';

  List<SchoolPeriodModel> _schoolPeriods = [];

  // Active in-sheet feedback callback for settings modal
  void Function(String)? _activeSettingsFeedbackCallback;
  List<Map<String, dynamic>> _schoolClasses = [];
  List<Map<String, dynamic>> _schoolSubjects = [];
  List<GroupModel> _centerGroups = [];
  List<ExceptionalSessionModel> _exceptionalSessions = [];
  Map<String, bool> _groupLockedStatus = {};
  Map<String, bool> _schoolPeriodLockedStatus = {};
  bool _isLoading = true;

  // Schedule Domain: 'school' (الحصص المدرسية) vs 'groups' (مجموعات الدروس)
  String _currentScheduleDomain = 'school';

  // Selected Day for Groups Timetable (يبدأ باليوم الحالي تلقائياً)
  String _groupsSelectedDay = '';
  static const List<String> _groupsWeekdays = [
    'السبت',
    'الأحد',
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'الكل',
  ];

  // Groups Days Row Expanded in the top rectangle
  bool _isGroupsDaysExpanded = false;

  String _settingsSelectedDay = 'الأحد';

  // Subject colors mapping
  Map<String, int> _subjectColors = {};

  // Next-day automatic alarms (Midnight sync)
  bool _autoNextDayAlarm = true;
  int _autoAlarmMinutesBefore = 5;
  String _lastAutoAlarmDate = '';
  bool _isAutoAlarmSyncInProgress = false;
  DateTime? _nextAutoAlarmRetryAt;
  bool _syncToSystemClockApp = false;
  String _currentAlarmTone = 'school_bell';
  String? _currentlyRingingTone;

  // Auto-delete expired and past alarms (Automatic Lifecycle Management)
  bool _autoDeleteExpiredAlarms = true;

  static const List<int> _paletteColors = [
    0xFF00F2FE, // Cyan Neon
    0xFF10B981, // Emerald Green
    0xFF3B82F6, // Royal Blue
    0xFF8B5CF6, // Purple
    0xFFEC4899, // Pink
    0xFFF59E0B, // Amber Orange
    0xFFEF4444, // Red
    0xFF14B8A6, // Teal
    0xFF6366F1, // Indigo
    0xFFF97316, // Orange
    0xFF06B6D4, // Sky Cyan
    0xFFA855F7, // Violet
  ];

  // Auto Period Alerts & Alarms
  bool _autoPeriodAlerts = true;
  Set<String> _alertActiveDays = {
    'الأحد',
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
  };
  Timer? _periodNotificationTimer;
  StreamSubscription<DataChangeEvent>? _databaseSubscription;
  final Set<String> _sentAlertKeys = {};

  static String _normalizeArabicDay(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
  }

  static bool _isGroupScheduledOnDay(GroupModel group, String targetDay) {
    if (targetDay == 'الكل' || targetDay.trim().isEmpty) return true;

    final normTarget = _normalizeArabicDay(targetDay);
    final normSchedule = _normalizeArabicDay(group.schedule);
    final normDays = _normalizeArabicDay(group.days);

    // Direct normalized match
    if (normSchedule.contains(normTarget) || normDays.contains(normTarget)) {
      return true;
    }

    // Bare day name without 'ال' (e.g. 'اثنين' vs 'الاثنين')
    final bareTarget = normTarget.startsWith('ال')
        ? normTarget.substring(2)
        : normTarget;
    if (bareTarget.length >= 3 &&
        (normSchedule.contains(bareTarget) || normDays.contains(bareTarget))) {
      return true;
    }

    // Numeric weekday indices mapping (1 = Monday, ..., 7 = Sunday)
    int? targetIndex;
    if (normTarget.contains('اثنين'))
      targetIndex = 1;
    else if (normTarget.contains('ثلاثاء'))
      targetIndex = 2;
    else if (normTarget.contains('اربعاء'))
      targetIndex = 3;
    else if (normTarget.contains('خميس'))
      targetIndex = 4;
    else if (normTarget.contains('جمعه'))
      targetIndex = 5;
    else if (normTarget.contains('سبت'))
      targetIndex = 6;
    else if (normTarget.contains('احد'))
      targetIndex = 7;

    if (targetIndex != null) {
      final daysSplit = group.days.split(RegExp(r'[,;\s]+'));
      for (final p in daysSplit) {
        final parsed = int.tryParse(p.trim());
        if (parsed != null &&
            (parsed == targetIndex || (targetIndex == 7 && parsed == 0))) {
          return true;
        }
      }
    }

    return false;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialDomain != null && widget.initialDomain!.isNotEmpty) {
      _currentScheduleDomain = widget.initialDomain!;
    }
    if (widget.initialDay != null && widget.initialDay!.isNotEmpty) {
      _selectedDay = widget.initialDay!;
      _groupsSelectedDay = widget.initialDay!;
    }
    if (widget.highlightTargetKey != null && widget.highlightTargetKey!.isNotEmpty) {
      _highlightTargetKey = widget.highlightTargetKey;
    }

    _detectCurrentDay();
    _loadData();
    _initPeriodNotificationMonitor();

    // Listen to real-time database changes (e.g. when groups are added/updated in GroupsScreen)
    _databaseSubscription = widget.database.onDataChanged.listen((event) {
      if (!mounted) return;
      if (event == DataChangeEvent.groups || event == DataChangeEvent.all) {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _periodNotificationTimer?.cancel();
    _databaseSubscription?.cancel();
    super.dispose();
  }

  void _initPeriodNotificationMonitor() {
    _periodNotificationTimer?.cancel();
    _periodNotificationTimer = Timer.periodic(const Duration(seconds: 40), (_) {
      if (_autoPeriodAlerts) _checkAndTriggerPeriodAlerts();
      if (_autoNextDayAlarm && !_isLoading) {
        unawaited(_checkAndRunMidnightAutoAlarmSync());
      }
      if (_autoDeleteExpiredAlarms && !_isLoading) {
        final now = DateTime.now();
        final todayArabic = _getTodayName(now.weekday);
        unawaited(AlarmService.cleanExpiredAlarms(
          todayPeriods: _schoolPeriods,
          todayGroups: _centerGroups,
          todayArabic: todayArabic,
        ));
      }
    });
  }

  void _checkAndTriggerPeriodAlerts() {
    if (!_autoPeriodAlerts) return;

    final now = DateTime.now();
    String todayArabic = '';
    switch (now.weekday) {
      case DateTime.sunday:
        todayArabic = 'الأحد';
        break;
      case DateTime.monday:
        todayArabic = 'الإثنين';
        break;
      case DateTime.tuesday:
        todayArabic = 'الثلاثاء';
        break;
      case DateTime.wednesday:
        todayArabic = 'الأربعاء';
        break;
      case DateTime.thursday:
        todayArabic = 'الخميس';
        break;
      case DateTime.friday:
        todayArabic = 'الجمعة';
        break;
      case DateTime.saturday:
        todayArabic = 'السبت';
        break;
    }

    // Only alert on days configured by the teacher
    if (!_alertActiveDays.contains(todayArabic)) return;

    final todayPeriods = _schoolPeriods
        .where((p) => p.dayOfWeek == todayArabic)
        .toList();
    final todayGroups =
        _centerGroups
            .where((g) => _isGroupScheduledOnDay(g, todayArabic))
            .toList()
          ..sort(GroupModel.compareByStartTime);
    if (todayPeriods.isEmpty && todayGroups.isEmpty) return;

    final currentMinutes = now.hour * 60 + now.minute;
    final dateKey = '${now.year}_${now.month}_${now.day}';

    for (final period in todayPeriods) {
      if (period.isReserve) continue;

      // Start time
      final periodStartMin = _parseTimeToMinutes(period.startTime);
      if (periodStartMin > 0) {
        // 1. 5 minutes before reminder
        final reminderKey = '${dateKey}_${period.id}_remind';
        if (currentMinutes == periodStartMin - 5 &&
            !_sentAlertKeys.contains(reminderKey)) {
          _sentAlertKeys.add(reminderKey);
          NotificationService.showUpcomingPeriodReminder(
            periodName: 'الحصة ${_convertToArabicWords(period.periodNumber)}',
            className: period.className,
            startTime: period.startTime,
            subject: period.subject,
            payload: 'timetable_alarm|live|${Uri.encodeComponent(period.dayOfWeek)}|now|period_${period.id}',
          );
        }

        // 2. Exact start alert
        final startKey = '${dateKey}_${period.id}_start';
        if (currentMinutes == periodStartMin &&
            !_sentAlertKeys.contains(startKey)) {
          _sentAlertKeys.add(startKey);
          NotificationService.showPeriodStartAlert(
            periodName: 'الحصة ${_convertToArabicWords(period.periodNumber)}',
            className: period.className,
            subject: period.subject,
            room: period.room,
            payload: 'timetable_alarm|live|${Uri.encodeComponent(period.dayOfWeek)}|now|period_${period.id}',
          );
        }
      }

      // End time
      final periodEndMin = _parseTimeToMinutes(period.endTime);
      if (periodEndMin > 0) {
        // 3. Exact end alert
        final endKey = '${dateKey}_${period.id}_end';
        if (currentMinutes == periodEndMin &&
            !_sentAlertKeys.contains(endKey)) {
          _sentAlertKeys.add(endKey);
          NotificationService.showPeriodEndAlert(
            periodName: 'الحصة ${_convertToArabicWords(period.periodNumber)}',
            className: period.className,
            payload: 'timetable_alarm|live|${Uri.encodeComponent(period.dayOfWeek)}|now|period_${period.id}',
          );
        }
      }
    }

    // Tutoring Center Groups Reminders & Alerts
    for (final group in todayGroups) {
      final startMin = _parseTimeToMinutes(group.startTime);
      if (startMin > 0) {
        // 5 minutes before reminder
        final reminderKey = '${dateKey}_group_${group.id}_remind';
        if (currentMinutes == startMin - 5 &&
            !_sentAlertKeys.contains(reminderKey)) {
          _sentAlertKeys.add(reminderKey);
          NotificationService.showUpcomingPeriodReminder(
            periodName: 'مجموعة: ${group.name}',
            className: group.grade,
            startTime: group.startTime,
            subject: group.subject.isNotEmpty ? group.subject : 'درس خصوصي',
            payload: 'timetable_alarm|live|${Uri.encodeComponent(todayArabic)}|now|group_${group.id}',
          );
        }

        // Exact start alert
        final startKey = '${dateKey}_group_${group.id}_start';
        if (currentMinutes == startMin && !_sentAlertKeys.contains(startKey)) {
          _sentAlertKeys.add(startKey);
          NotificationService.showPeriodStartAlert(
            periodName: 'بدء درس: ${group.name}',
            className: group.grade,
            subject: group.subject.isNotEmpty ? group.subject : 'درس خصوصي',
            room: group.room,
            payload: 'timetable_alarm|live|${Uri.encodeComponent(todayArabic)}|now|group_${group.id}',
          );
        }
      }

      // End alert
      final endMin = _parseTimeToMinutes(group.endTime);
      if (endMin > 0) {
        final endKey = '${dateKey}_group_${group.id}_end';
        if (currentMinutes == endMin && !_sentAlertKeys.contains(endKey)) {
          _sentAlertKeys.add(endKey);
          NotificationService.showPeriodEndAlert(
            periodName: 'انتهاء درس: ${group.name}',
            className: group.grade,
            payload: 'timetable_alarm|live|${Uri.encodeComponent(todayArabic)}|now|group_${group.id}',
          );
        }
      }
    }
  }

  void _detectCurrentDay() {
    final now = DateTime.now();
    final today = _getTodayName(now.weekday);
    _selectedDay = today;
    _groupsSelectedDay = today;
  }

  /// Automatically synchronizes the next day's timetable alarms at midnight (12:00 AM) or on daily rollover.
  /// Safely purges previous day auto-alarms while keeping manual alarms 100% untouched.
  Future<int> _checkAndRunMidnightAutoAlarmSync({bool force = false}) async {
    if ((!_autoNextDayAlarm && !force) || _isAutoAlarmSyncInProgress) return 0;

    final now = DateTime.now();
    final todayDateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    if (!force &&
        _nextAutoAlarmRetryAt != null &&
        now.isBefore(_nextAutoAlarmRetryAt!)) {
      return 0;
    }
    if (!force && _lastAutoAlarmDate == todayDateKey) return 0;

    _isAutoAlarmSyncInProgress = true;
    try {
      DateTime targetDate = now.add(const Duration(days: 1));
      String targetArabic = _getTodayName(targetDate.weekday);

      var targetPeriods = _schoolPeriods
          .where((p) => p.dayOfWeek == targetArabic && !p.isReserve)
          .toList();
      var targetGroups =
          _centerGroups
              .where((g) => _isGroupScheduledOnDay(g, targetArabic))
              .toList()
            ..sort(GroupModel.compareByStartTime);

      // If tomorrow has no periods or groups (e.g. weekend Friday/Saturday), find the next active teaching day
      if (targetPeriods.isEmpty && targetGroups.isEmpty) {
        for (int i = 2; i <= 7; i++) {
          final candidateDate = now.add(Duration(days: i));
          final candidateArabic = _getTodayName(candidateDate.weekday);
          final cp = _schoolPeriods
              .where((p) => p.dayOfWeek == candidateArabic && !p.isReserve)
              .toList();
          final cg = _centerGroups
              .where((g) => _isGroupScheduledOnDay(g, candidateArabic))
              .toList();
          if (cp.isNotEmpty || cg.isNotEmpty) {
            targetDate = candidateDate;
            targetArabic = candidateArabic;
            targetPeriods = cp;
            targetGroups = cg..sort(GroupModel.compareByStartTime);
            break;
          }
        }
      }

      var count = 0;
      if (targetPeriods.isNotEmpty || targetGroups.isNotEmpty) {
        count = await AlarmService.syncNextDayAutoAlarms(
          nextDayPeriods: targetPeriods,
          nextDayGroups: targetGroups,
          nextDayName: targetArabic,
          minutesBefore: _autoAlarmMinutesBefore,
          scheduledDate: targetDate,
          useSystemClock: _syncToSystemClockApp,
          soundTone: _currentAlarmTone,
        );

        final expectedCount =
            targetPeriods.length +
            targetGroups
                .where((group) => group.startTime.trim().isNotEmpty)
                .length;
        if (!_autoNextDayAlarm && !force) {
          await AlarmService.dismissAutoAlarms();
          return count;
        }
        if (count < expectedCount) {
          _nextAutoAlarmRetryAt = DateTime.now().add(
            const Duration(minutes: 5),
          );
          return count;
        }
      } else {
        await AlarmService.dismissAutoAlarms();
      }

      _nextAutoAlarmRetryAt = null;
      _lastAutoAlarmDate = todayDateKey;
      await widget.database.setSetting(
        'school_last_auto_alarm_date',
        todayDateKey,
      );
      return count;
    } finally {
      _isAutoAlarmSyncInProgress = false;
    }
  }

  Future<int> _syncManualAlarmsForDate(DateTime date) async {
    final dayName = _getTodayName(date.weekday);
    await AlarmService.dismissDateAlarms(date);

    final periods = _schoolPeriods
        .where((period) => period.dayOfWeek == dayName && !period.isReserve)
        .toList();
    final groups =
        _centerGroups
            .where((group) => _isGroupScheduledOnDay(group, dayName))
            .toList()
          ..sort(GroupModel.compareByStartTime);

    var count = await AlarmService.syncDayPeriodAlarms(
      dayPeriods: periods,
      minutesBefore: _autoAlarmMinutesBefore,
      scheduledDate: date,
      useSystemClock: _syncToSystemClockApp,
      soundTone: _currentAlarmTone,
    );
    count += await AlarmService.syncDayGroupAlarms(
      dayGroups: groups,
      dayName: dayName,
      minutesBefore: _autoAlarmMinutesBefore,
      scheduledDate: date,
      useSystemClock: _syncToSystemClockApp,
      soundTone: _currentAlarmTone,
    );
    return count;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        widget.database.getSetting('school_period_timings_config', defaultValue: ''),
        widget.database.getSetting('timetable_design_theme', defaultValue: 'cyber'),
        widget.database.getSetting('school_timetable_view_mode', defaultValue: 'grid'),
        widget.database.getSetting('school_alarm_selected_days', defaultValue: ''),
        widget.database.getSchoolPeriods(),
        widget.database.getSchoolClasses(),
        widget.database.getSchoolSubjects(),
        widget.database.getGroups(),
        widget.database.getSetting('school_auto_period_alerts', defaultValue: 'true'),
        widget.database.getSetting('timetable_active_domain', defaultValue: 'school'),
        widget.database.getSetting('school_auto_next_day_alarms', defaultValue: 'true'),
        widget.database.getSetting('school_auto_alarm_minutes_before', defaultValue: '5'),
        widget.database.getSetting('school_last_auto_alarm_date', defaultValue: ''),
        widget.database.getSetting('school_subject_colors_map', defaultValue: ''),
        widget.database.getSetting('school_auto_delete_expired_alarms', defaultValue: 'true'),
        widget.database.getSetting('school_sync_system_clock_app', defaultValue: 'false'),
        widget.database.getExceptionalSessions(),
        widget.database.getSetting('alarm_sound_tone', defaultValue: 'school_bell'),
      ]);

      final timingsJson = results[0] as String;
      final savedTheme = results[1] as String;
      final savedSchoolMode = results[2] as String;
      final savedAlertDays = results[3] as String;
      final periods = results[4] as List<SchoolPeriodModel>;
      final classes = results[5] as List<Map<String, dynamic>>;
      final subjects = results[6] as List<Map<String, dynamic>>;
      final groups = results[7] as List<GroupModel>;
      final alertsPref = results[8] as String;
      final activeDomainPref = results[9] as String;
      final autoAlarmPref = results[10] as String;
      final autoMinPref = results[11] as String;
      final lastDatePref = results[12] as String;
      final colorsJson = results[13] as String;
      final autoDeletePref = results[14] as String;
      final syncClockPref = results[15] as String;

      // Parse custom period timings if configured
      if (timingsJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(timingsJson) as Map<String, dynamic>;
          for (int i = 1; i <= 8; i++) {
            if (decoded.containsKey('$i')) {
              final m = decoded['$i'] as Map<String, dynamic>;
              _periodTimings[i] = (
                start: m['start'].toString(),
                end: m['end'].toString(),
              );
            }
          }
          if (decoded.containsKey('recess')) {
            final rm = decoded['recess'] as Map<String, dynamic>;
            _recessStartTime = rm['start'].toString();
            _recessEndTime = rm['end'].toString();
          }
          if (decoded.containsKey('recess_after')) {
            final ra = decoded['recess_after'];
            if (ra is int) _recessAfterPeriod = ra;
          }
          if (decoded.containsKey('supervision')) {
            final sm = decoded['supervision'] as Map<String, dynamic>;
            _morningAssemblyDutyDay =
                (sm['assembly_day'] ?? _morningAssemblyDutyDay).toString();
            _morningAssemblyStartTime =
                (sm['assembly_start'] ?? _morningAssemblyStartTime).toString();
            _morningAssemblyEndTime =
                (sm['assembly_end'] ?? _morningAssemblyEndTime).toString();
            _morningAssemblyLocation =
                (sm['assembly_loc'] ?? _morningAssemblyLocation).toString();
            _breakDutyDay = (sm['break_day'] ?? _breakDutyDay).toString();
            _breakDutyLocation = (sm['break_loc'] ?? _breakDutyLocation)
                .toString();
          }
        } catch (_) {}
      }

      Map<String, int> loadedSubjectColors = {};
      if (colorsJson.isNotEmpty) {
        try {
          final Map<String, dynamic> decoded = jsonDecode(colorsJson);
          loadedSubjectColors = decoded.map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          );
        } catch (_) {}
      }

      Set<String> loadedAlertDays = {
        'الأحد',
        'الإثنين',
        'الثلاثاء',
        'الأربعاء',
        'الخميس',
      };
      if (savedAlertDays.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(savedAlertDays);
          final setDays = decoded.map((e) => e.toString()).toSet();
          if (setDays.isNotEmpty) loadedAlertDays = setDays;
        } catch (_) {}
      }

      final todayDateStr = DateTime.now().toIso8601String().substring(0, 10);
      final Map<String, bool> groupLocks = {};
      await Future.wait(
        groups.map((g) async {
          final lock = await widget.database.getSetting(
            'attendance_lock_${g.id}_$todayDateStr',
            defaultValue: 'false',
          );
          if (lock == 'true') {
            groupLocks[g.id] = true;
          }
        }),
      );

      final Map<String, bool> periodLocks = {};
      await Future.wait(
        periods.map((p) async {
          final pLock = await widget.database.getSetting(
            'school_period_lock_${p.id}_$todayDateStr',
            defaultValue: 'false',
          );
          if (pLock == 'true') {
            periodLocks[p.id] = true;
          }
        }),
      );

      if (mounted) {
        setState(() {
          _schoolPeriods = periods;
          _schoolClasses = classes;
          _schoolSubjects = subjects;
          _centerGroups = groups;
          _groupLockedStatus = groupLocks;
          _schoolPeriodLockedStatus = periodLocks;
          _exceptionalSessions = results.length > 16
              ? (results[16] as List<ExceptionalSessionModel>)
              : [];
          _subjectColors = loadedSubjectColors;
          _currentScheduleDomain = widget.initialDomain ??
              ((activeDomainPref == 'groups') ? 'groups' : 'school');
          _settingsSelectedDay = _selectedDay;
          if (widget.initialDay != null && widget.initialDay!.isNotEmpty) {
            _selectedDay = widget.initialDay!;
            _groupsSelectedDay = widget.initialDay!;
          } else if (_groupsSelectedDay.isEmpty) {
            _groupsSelectedDay = _selectedDay;
          }
          _autoNextDayAlarm = autoAlarmPref == 'true';
          _autoAlarmMinutesBefore = int.tryParse(autoMinPref) ?? 5;
          _lastAutoAlarmDate = lastDatePref;
          _autoPeriodAlerts = alertsPref == 'true';
          _alertActiveDays = loadedAlertDays;
          _autoDeleteExpiredAlarms = autoDeletePref != 'false';
          _syncToSystemClockApp = syncClockPref == 'true';
          _currentAlarmTone = results.length > 17 ? (results[17] as String) : 'school_bell';
          _designTheme = (savedTheme == 'classic') ? 'classic' : 'cyber';
          if (savedSchoolMode == 'daily' || savedSchoolMode == 'grid') {
            _schoolViewMode = savedSchoolMode;
          }
          _isLoading = false;
        });

        if (_highlightTargetKey != null && !_hasAutoScrolled) {
          _hasAutoScrolled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 350), () {
              if (mounted && _highlightedItemKey.currentContext != null) {
                Scrollable.ensureVisible(
                  _highlightedItemKey.currentContext!,
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeInOutCubic,
                  alignment: 0.3,
                );
              }
            });
          });
        }

        if (_autoNextDayAlarm) {
          _checkAndRunMidnightAutoAlarmSync();
        }

        if (_autoDeleteExpiredAlarms) {
          final now = DateTime.now();
          final todayArabic = _getTodayName(now.weekday);
          unawaited(AlarmService.cleanExpiredAlarms(
            todayPeriods: _schoolPeriods,
            todayGroups: _centerGroups,
            todayArabic: todayArabic,
          ));
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _savePeriodTimingsConfig() async {
    final Map<String, dynamic> export = {
      'recess': {'start': _recessStartTime, 'end': _recessEndTime},
      'recess_after': _recessAfterPeriod,
      'supervision': {
        'assembly_day': _morningAssemblyDutyDay,
        'assembly_start': _morningAssemblyStartTime,
        'assembly_end': _morningAssemblyEndTime,
        'assembly_loc': _morningAssemblyLocation,
        'break_day': _breakDutyDay,
        'break_loc': _breakDutyLocation,
      },
    };
    for (final entry in _periodTimings.entries) {
      export['${entry.key}'] = {
        'start': entry.value.start,
        'end': entry.value.end,
      };
    }
    await widget.database.setSetting(
      'school_period_timings_config',
      jsonEncode(export),
    );
  }

  Future<void> _exportSchoolTimetable() async {
    try {
      final bytes = SchoolTimetableExcelService.exportPeriods(_schoolPeriods);
      final fileName = 'الجدول_المدرسي.xlsx';
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              name: fileName,
            ),
          ],
          subject: 'الجدول المدرسي',
          text: 'الجدول المدرسي',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر تصدير الجدول: $error')));
    }
  }

  Future<void> _importSchoolTimetable() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (files.isEmpty) return;

      final file = files.first;
      if (file.path == null) {
        throw const FormatException('تعذر قراءة الملف المختار.');
      }
      final bytes = await File(file.path!).readAsBytes();
      final periods = SchoolTimetableExcelService.importPeriods(bytes);
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('استيراد الجدول المدرسي'),
          content: Text(
            'سيتم استبدال الجدول الحالي (${_schoolPeriods.length} حصة) '
            'بـ ${periods.length} حصة من الملف. هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.file_download_done_rounded),
              label: const Text('استبدال واستيراد'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      await widget.database.replaceSchoolPeriods(periods);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم استيراد ${periods.length} حصة بنجاح.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر استيراد الجدول: $error')));
    }
  }

  SchoolPeriodModel? _getPeriodFor(String day, int periodNum) {
    try {
      return _schoolPeriods.firstWhere(
        (p) => p.dayOfWeek == day && p.periodNumber == periodNum,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isPeriodCurrent(SchoolPeriodModel period) {
    final now = DateTime.now();
    String todayName = _getTodayName(now.weekday);
    if (period.dayOfWeek != todayName) return false;

    try {
      final sMin = _parseTimeToMinutes(period.startTime);
      final eMin = _parseTimeToMinutes(period.endTime);
      final nowMin = now.hour * 60 + now.minute;
      return nowMin >= sMin && nowMin <= eMin;
    } catch (_) {
      return false;
    }
  }

  String _getTodayName(int weekday) {
    switch (weekday) {
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
      case DateTime.saturday:
        return 'السبت';
      default:
        return '';
    }
  }

  int _parseTimeToMinutes(String t) {
    final parsed = AlarmService.parseTimeString(t);
    if (parsed == null) return 0;
    return parsed.$1 * 60 + parsed.$2;
  }

  // --- Schedule Conflict Detection for Groups & Exceptional Sessions (رصد تعارض مواعيد المجموعات والحصص) ---
  Map<String, List<Map<String, dynamic>>> _detectGroupScheduleConflicts() {
    final Map<String, List<Map<String, dynamic>>> conflicts = {};
    final rawConflicts = ScheduleConflictService.detectAllConflicts(
      groups: _centerGroups,
      exceptionalSessions: _exceptionalSessions,
    );

    for (final entry in rawConflicts.entries) {
      final list = entry.value
          .map((c) => {
                'other': c.secondName,
                'name': c.secondName,
                'day': c.day,
                'time': c.secondTime,
                'message': c.message,
              })
          .toList();
      conflicts[entry.key] = list;
    }
    return conflicts;
  }

  // Banner alerting about schedule conflicts
  Widget _buildScheduleConflictAlertBanner(
    Map<String, List<Map<String, dynamic>>> groupConflicts,
    bool isDark,
  ) {
    final totalConflictingGroups = groupConflicts.length;
    String targetDay = '';
    for (final list in groupConflicts.values) {
      if (list.isNotEmpty && list.first['day'] != null) {
        targetDay = list.first['day'] as String;
        break;
      }
    }

    return InkWell(
      onTap: () {
        HapticFeedback.heavyImpact();
        setState(() {
          _currentScheduleDomain = 'groups';
          if (targetDay.isNotEmpty && targetDay != 'الكل') {
            _groupsSelectedDay = targetDay;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              targetDay.isNotEmpty
                  ? 'تم الانتقال لجدول مجموعات يوم $targetDay لفحص وحل التعارض ⚡'
                  : 'تم الانتقال لجدول المجموعات لفحص التعارض ⚡',
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF991B1B), Color(0xFFDC2626)],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF87171), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFDC2626).withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ رصد تعارض في مواعيد $totalConflictingGroups مجموعات دراسية!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    targetDay.isNotEmpty
                        ? 'يوجد تداخل زمني في يوم $targetDay • اضغط للانتقال وحل التعارض فوراً ⚡'
                        : 'اضغط هنا للانتقال لجدول المجموعات وحل التداخل الزمني ⚡',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'حل الآن',
                    style: TextStyle(
                      color: Color(0xFF991B1B),
                      fontWeight: FontWeight.w900,
                      fontSize: 10.5,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(
                    Icons.arrow_back_ios_rounded,
                    size: 10,
                    color: Color(0xFF991B1B),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groupConflicts = _detectGroupScheduleConflicts();

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0B1120)
          : const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Slim Compact App Bar Header
            _buildHeader(isDark),

            // 1.5 Active Ringing Banner (إذا كان جرس الحصة يرن الآن يظهر شريط فوري لإيقافه)
            if (_currentlyRingingTone != null)
              _buildActiveRingingBanner(isDark),

            // 2. Schedule Conflict Glowing Alert Banner
            if (groupConflicts.isNotEmpty)
              _buildScheduleConflictAlertBanner(groupConflicts, isDark),

            // 3. Main Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00F2FE),
                      ),
                    )
                  : _currentScheduleDomain == 'groups'
                  ? _buildDedicatedGroupsTimetableView(isDark, groupConflicts)
                  : _designTheme == 'cyber'
                  ? _buildCyberNeonView(isDark)
                  : _buildClassicView(isDark),
            ),
          ],
        ),
      ),
    );
  }

  // --- Active Ringing Floating Banner ---
  Widget _buildActiveRingingBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_active_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'جرس الحصة يرن الآن 🔔...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFDC2626),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              HapticFeedback.heavyImpact();
              await AlarmService.stopAudio();
              setState(() => _currentlyRingingTone = null);
            },
            icon: const Icon(Icons.stop_circle_rounded, size: 16),
            label: const Text(
              'إيقاف الرنين',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  // --- 1. Compact Header Bar (شريط علوي منسق واحترافي ومتناسق مع الشاشة وبدون أي اوفر فلو) ---
  Widget _buildHeader(bool isDark) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // 1. Back Button
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              if (widget.onBack != null) {
                widget.onBack!();
              } else if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFCBD5E1),
                  width: 0.8,
                ),
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                textDirection: TextDirection.ltr,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. Clean Screen Title (الجدول)
          Expanded(
            child: Text(
              'الجدول',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontFamily: 'Cairo',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),

          // 3. Dedicated Toggle Icon / Button between School Schedule & Groups Schedule
          InkWell(
            onTap: () async {
              HapticFeedback.selectionClick();
              final nextDomain = _currentScheduleDomain == 'school'
                  ? 'groups'
                  : 'school';
              setState(() => _currentScheduleDomain = nextDomain);
              await widget.database.setSetting(
                'timetable_active_domain',
                nextDomain,
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _currentScheduleDomain == 'school'
                      ? [const Color(0xFFA855F7), const Color(0xFF6366F1)]
                      : [const Color(0xFF00F2FE), const Color(0xFF2563EB)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: (_currentScheduleDomain == 'school'
                            ? const Color(0xFFA855F7)
                            : const Color(0xFF00F2FE))
                        .withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _currentScheduleDomain == 'school'
                        ? Icons.groups_rounded
                        : Icons.school_rounded,
                    size: 13,
                    color: _currentScheduleDomain == 'school'
                        ? Colors.white
                        : Colors.black,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _currentScheduleDomain == 'school'
                        ? 'الدروس'
                        : 'المدرسة',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: _currentScheduleDomain == 'school'
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),

          // 4. Manage Groups ＋ (Only when in groups mode)
          if (_currentScheduleDomain == 'groups') ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                color: Color(0xFFA855F7),
                size: 20,
              ),
              tooltip: 'إدارة المجموعات ＋',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupsScreen(database: widget.database),
                  ),
                ).then((_) => _loadData());
              },
            ),
            const SizedBox(width: 2),
          ],

          // 5. In-App Alarm Clock
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            icon: const Icon(
              Icons.alarm_rounded,
              color: Color(0xFF00F2FE),
              size: 20,
            ),
            tooltip: 'شاشة المنبه الذكي ⏰',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AlarmClockScreen(database: widget.database),
                ),
              ).then((_) => _loadData());
            },
          ),
          const SizedBox(width: 2),

          // 6. Settings (with active ring dot if bell is ringing)
          SizedBox(
            width: 30,
            height: 30,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                  icon: const Icon(
                    Icons.tune_rounded,
                    color: Color(0xFFFBBF24),
                    size: 20,
                  ),
                  tooltip: 'إعدادات الجدول وجرس الحصة ⚙️',
                  onPressed: _showUnifiedTimetableSettings,
                ),
                if (_currentlyRingingTone != null)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // --- DESIGN 1: CYBER NEON BENTO (100% Match to media_1794176564339_5caaf347.jpg) ---
  // =========================================================================
  Widget _buildCyberNeonView(bool isDark) {
    final now = DateTime.now();
    final todayName = _getTodayName(now.weekday);

    if (_schoolViewMode == 'grid') {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWeeklyMatrixGrid(isDark),
            const SizedBox(height: 14),
            _buildGridSummaryCard(isDark),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        _schoolViewMode == 'grid' ? 8 : 16,
        10,
        _schoolViewMode == 'grid' ? 8 : 16,
        90,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Horizon Weekdays Slider (with glowing neon active ring & dot underneath)
          _buildCyberDaysSlider(_schoolWeekdays, todayName, isDark),
          const SizedBox(height: 18),

          // 2. Bento Cards List
          _buildCyberSchoolPeriodsList(isDark),
        ],
      ),
    );
  }

  // Days Slider (Image 4: Active day has cyan glowing ring + glowing cyan dot beneath!)
  Widget _buildCyberDaysSlider(
    List<String> daysList,
    String todayName,
    bool isDark,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: daysList.map((day) {
          final isSel = _selectedDay == day;
          final isToday = day == todayName;

          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedDay = day);
              },
              borderRadius: BorderRadius.circular(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSel
                          ? (isDark
                                ? const Color(0xFF0E223D)
                                : const Color(0xFFE0F7FA))
                          : (isDark
                                ? const Color(0xFF141E33)
                                : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSel
                            ? const Color(0xFF00F2FE)
                            : (isDark
                                  ? const Color(0xFF223147)
                                  : const Color(0xFFCBD5E1)),
                        width: isSel ? 1.6 : 1.0,
                      ),
                      boxShadow: isSel
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF00F2FE,
                                ).withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      isToday ? '$day (اليوم)' : day,
                      style: TextStyle(
                        color: isSel
                            ? const Color(0xFF00F2FE)
                            : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Glowing Neon Dot directly beneath active day (Image 4)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: isSel ? 6 : 0,
                    height: isSel ? 6 : 0,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F2FE),
                      shape: BoxShape.circle,
                      boxShadow: isSel
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF00F2FE,
                                ).withValues(alpha: 0.8),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 4. Cyber School Periods List (Image 4: Giant 01/02 Numbers + Bento Cards + Recess)
  Widget _buildCyberSchoolPeriodsList(bool isDark) {
    final dayPeriods =
        _schoolPeriods.where((p) => p.dayOfWeek == _selectedDay).toList()
          ..sort((a, b) => a.periodNumber.compareTo(b.periodNumber));

    return Column(
      children: [
        ...List.generate(8, (index) {
          final pNum = index + 1;

          // Recess Card placed according to user's configured period position
          if (pNum == _recessAfterPeriod) {
            return Column(
              children: [
                _buildCyberPeriodCard(dayPeriods, pNum, isDark),
                const SizedBox(height: 12),
                _buildCyberRecessCard(isDark),
                const SizedBox(height: 12),
              ],
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildCyberPeriodCard(dayPeriods, pNum, isDark),
          );
        }),
      ],
    );
  }

  // Individual Cyber Period Bento Card (Giant 01/02 Number + Neon Border - Image 4)
  Widget _buildCyberPeriodCard(
    List<SchoolPeriodModel> dayPeriods,
    int pNum,
    bool isDark,
  ) {
    final period = dayPeriods.where((p) => p.periodNumber == pNum).firstOrNull;

    if (period == null) {
      // Empty Period Slot (Dashed Border Card: فترة فراغ - للعرض فقط)
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF101B2E).withValues(alpha: 0.3)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0xFF2D3C52) : const Color(0xFFCBD5E1),
            width: 1.2,
          ),
        ),
        child: Center(
          child: Text(
            'فترة فراغ (الحصة ${_convertToArabicWords(pNum)})',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    final isCurrent = _isPeriodCurrent(period);
    final numStr = pNum.toString().padLeft(2, '0');
    final bool isTargetHighlight = _highlightTargetKey != null &&
        (_highlightTargetKey == 'period_${period.id}' ||
            _highlightTargetKey == period.id ||
            _highlightTargetKey == 'period_${period.periodNumber}');

    // Accent Colors
    final Color neonBorder = isTargetHighlight
        ? const Color(0xFF00F2FE)
        : (isCurrent
            ? const Color(0xFF10B981)
            : (pNum % 2 == 1)
                ? const Color(0xFF00F2FE)
                : const Color(0xFF6366F1));

    final Color numberColor = isTargetHighlight
        ? const Color(0xFF00F2FE)
        : (isCurrent
            ? const Color(0xFF10B981)
            : (pNum % 2 == 1)
                ? const Color(0xFF00F2FE).withValues(alpha: 0.7)
                : const Color(0xFF818CF8).withValues(alpha: 0.7));

    final bool isPeriodLocked = _schoolPeriodLockedStatus[period.id] == true;

    return Stack(
      key: isTargetHighlight ? _highlightedItemKey : null,
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            _showPeriodDetails(period);
          },
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
        color: isTargetHighlight
            ? (isDark ? const Color(0xFF0C243B) : const Color(0xFFE0F7FA))
            : (isDark ? const Color(0xFF101B2E) : Colors.white),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: neonBorder,
          width: isTargetHighlight ? 3.0 : (isCurrent ? 2.2 : 1.4),
        ),
        boxShadow: [
          if (isTargetHighlight) ...[
            BoxShadow(
              color: const Color(0xFF00F2FE).withValues(alpha: 0.75),
              blurRadius: 24,
              spreadRadius: 3,
            ),
            BoxShadow(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
              blurRadius: 40,
              spreadRadius: 6,
            ),
          ] else ...[
            BoxShadow(
              color: neonBorder.withValues(alpha: isCurrent ? 0.45 : 0.15),
              blurRadius: isCurrent ? 18 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isTargetHighlight)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00F2FE), Color(0xFF2563EB)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.6),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.stars_rounded, color: Colors.black, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '📍 الحصة المحددة من الإشعار والجدول ⚡',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
          // Left (or Right): Giant 2-Digit Stylized Number: 01, 02 (Image 4)
          Container(
            width: 68,
            alignment: Alignment.center,
            child: Text(
              numStr,
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w900,
                color: numberColor,
                letterSpacing: -1.5,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Middle: Class Title + Subject + Room & Timing Badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title: فصل 1/1 + احتياط
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'فصل ${period.className}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (period.isReserve) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF7C3AED)),
                        ),
                        child: const Text(
                          'احتياط',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFA78BFA),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (period.subject.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    period.subject,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00F2FE),
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                // Badges Row: [معمل 1] & [الآن 08:00 - 08:45] (Image 4)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (period.room.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          period.room,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                      ),

                    // Timing Pill (Glowing emerald when active)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : (isDark
                                  ? const Color(0xFF141E33)
                                  : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCurrent
                              ? const Color(0xFF10B981)
                              : (isDark
                                    ? const Color(0xFF223147)
                                    : const Color(0xFFCBD5E1)),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCurrent) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'الآن ',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                          Text(
                            '${period.startTime} - ${period.endTime}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isCurrent
                                  ? const Color(0xFF10B981)
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  ),
),
),
        if (isPeriodLocked)
          PositionedDirectional(
            end: 18,
            top: 14,
            child: _buildCircularSealStamp(isDark),
          ),
      ],
    );
  }

  // Cyber Recess Card (Image 4: Warm amber glassmorphic card with glowing coffee cup)
  Widget _buildCyberRecessCard(bool isDark) {
    final isBreakDutyDay = _breakDutyDay == _selectedDay;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isBreakDutyDay
            ? const Color(0xFF352310)
            : const Color(0xFF241C12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isBreakDutyDay
              ? const Color(0xFFFBBF24)
              : const Color(0xFFF59E0B),
          width: isBreakDutyDay ? 2.0 : 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFFF59E0B,
            ).withValues(alpha: isBreakDutyDay ? 0.45 : 0.35),
            blurRadius: isBreakDutyDay ? 18 : 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Glowing coffee cup box on the side (Image 4)
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(
                0xFFF59E0B,
              ).withValues(alpha: isBreakDutyDay ? 0.28 : 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
              ),
            ),
            child: const Center(
              child: Text('☕', style: TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 14),

          // Text & Badge (Image 4)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'فسحة مدرسية • $_recessStartTime - $_recessEndTime',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: Color(0xFFF59E0B),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (isBreakDutyDay)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF59E0B,
                          ).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFBBF24)),
                        ),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 13,
                              color: Color(0xFFFBBF24),
                            ),
                            Text(
                              'مكلف بإشراف الفسحة اليوم (${_breakDutyLocation.isNotEmpty ? _breakDutyLocation : "فناء المدرسة"}) ⚡',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFFBBF24),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF59E0B,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(
                              0xFFF59E0B,
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'مكان البريك: بعد الحصة ${_convertToArabicWords(_recessAfterPeriod)}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
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
    );
  }

  Color _getSubjectColor(String subject) {
    if (_subjectColors.containsKey(subject)) {
      return Color(_subjectColors[subject]!);
    }
    return const Color(0xFF00F2FE);
  }

  // --- Authentic Circular Red Ink Seal Stamp for Completed / Locked Sessions ---
  Widget _buildCircularSealStamp(bool isDark) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: -0.16, // authentic tilted ink stamp angle
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFDC2626).withValues(alpha: isDark ? 0.9 : 0.85),
              width: 2.2,
            ),
            color: const Color(0xFFDC2626).withValues(alpha: isDark ? 0.16 : 0.08),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.12),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3.5),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFDC2626).withValues(alpha: 0.55),
                width: 1.0,
              ),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 13,
                  color: Color(0xFFDC2626),
                ),
                SizedBox(height: 1),
                Text(
                  'تم التحضير',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 9.2,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'معتمدة ومغلقة 🔒',
                  style: TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 7.5,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'لعدم التعديل',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 7.0,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // --- DEDICATED GROUPS TIMETABLE TAB (تاب مستقلة لجدول المجموعات ومواعيدها) ---
  // =========================================================================
  Widget _buildDedicatedGroupsTimetableView(
    bool isDark,
    Map<String, List<Map<String, dynamic>>> groupConflicts,
  ) {
    final now = DateTime.now();
    final todayName = _getTodayName(now.weekday);

    if (_groupsSelectedDay.isEmpty) {
      _groupsSelectedDay = todayName;
    }

    // 1. Filter groups by selected day
    final filteredGroups = _groupsSelectedDay == 'الكل'
        ? List<GroupModel>.from(_centerGroups)
        : _centerGroups
              .where((g) => _isGroupScheduledOnDay(g, _groupsSelectedDay))
              .toList();

    // 2. Sort chronologically by start time
    filteredGroups.sort(GroupModel.compareByStartTime);

    // 3. Calculate statistics
    double totalHours = 0;
    final Set<String> activeRooms = {};
    for (final g in filteredGroups) {
      final startMin = _parseTimeToMinutes(g.startTime);
      final endMin = _parseTimeToMinutes(g.endTime);
      final dur = (endMin > startMin) ? (endMin - startMin) : 60;
      totalHours += dur / 60.0;
      if (g.room.isNotEmpty) activeRooms.add(g.room);
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        _schoolViewMode == 'grid' ? 8 : 16,
        10,
        _schoolViewMode == 'grid' ? 8 : 16,
        90,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Integrated Header Rectangle: Right side has Active/Current Day, Left side has "الأيام" button opening horizontal row underneath
          _buildGroupsIntegratedDayRectangle(
            todayName,
            filteredGroups.length,
            totalHours,
            isDark,
          ),
          const SizedBox(height: 14),

          // 2. Metrics & Summary Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E1B4B), const Color(0xFF0F172A)]
                    : [const Color(0xFFF5F3FF), Colors.white],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF3730A3)
                    : const Color(0xFFDDD6FE),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF6366F1,
                  ).withValues(alpha: isDark ? 0.2 : 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Groups count
                _buildGroupsSummaryMetric(
                  icon: Icons.groups_rounded,
                  color: const Color(0xFFA855F7),
                  title: 'المجموعات',
                  value: '${filteredGroups.length}',
                  isDark: isDark,
                ),
                Container(
                  height: 32,
                  width: 1,
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
                // Hours
                _buildGroupsSummaryMetric(
                  icon: Icons.access_time_rounded,
                  color: const Color(0xFF00F2FE),
                  title: 'ساعات التدريس',
                  value: '${totalHours.toStringAsFixed(1)} س',
                  isDark: isDark,
                ),
                Container(
                  height: 32,
                  width: 1,
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
                // Active Rooms
                _buildGroupsSummaryMetric(
                  icon: Icons.meeting_room_outlined,
                  color: const Color(0xFF10B981),
                  title: 'القاعات',
                  value: activeRooms.isEmpty ? '0' : '${activeRooms.length}',
                  isDark: isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Section Title & Manage Groups Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFFA855F7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _groupsSelectedDay == 'الكل'
                            ? 'كافة المجموعات (${filteredGroups.length}):'
                            : '$_groupsSelectedDay (${filteredGroups.length}):',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFA855F7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                label: const Text(
                  'إدارة المجموعات ＋',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupsScreen(database: widget.database),
                    ),
                  ).then((_) => _loadData());
                },
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 4. Empty State
          if (filteredGroups.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF141E33) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF223147)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFA855F7).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.event_busy_rounded,
                      size: 36,
                      color: Color(0xFFA855F7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _groupsSelectedDay == 'الكل'
                        ? 'لا توجد أي مجموعات دراسية مسجلة حالياً'
                        : 'لا توجد مجموعات دروس مجدولة في يوم $_groupsSelectedDay',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'يمكنك إنشاء مجموعة جديدة وتحديد مواعيدها وقاعتها بسهولة',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA855F7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              GroupsScreen(database: widget.database),
                        ),
                      ).then((_) => _loadData());
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      'إضافة مجموعة جديدة ومواعيدها',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            // 5. Groups Timeline Cards List
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredGroups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, index) {
                final group = filteredGroups[index];
                final groupColor = Color(
                  group.colorValue != 0 ? group.colorValue : 0xFF8B5CF6,
                );

                // Check conflict from the comprehensive conflict detector
                final groupConflictsList = groupConflicts[group.id];
                final bool hasConflict =
                    groupConflictsList != null && groupConflictsList.isNotEmpty;

                final startMin = _parseTimeToMinutes(group.startTime);
                final endMin = _parseTimeToMinutes(group.endTime);
                final durationMin = (endMin > startMin)
                    ? (endMin - startMin)
                    : 60;

                final bool isTargetHighlight = _highlightTargetKey != null &&
                    (_highlightTargetKey == 'group_${group.id}' ||
                        _highlightTargetKey == group.id ||
                        _highlightTargetKey == group.name);

                final bool isGroupLocked = _groupLockedStatus[group.id] == true;

                return Stack(
                  key: isTargetHighlight ? _highlightedItemKey : null,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                    color: isTargetHighlight
                        ? (isDark ? const Color(0xFF1E1038) : const Color(0xFFF5EEFD))
                        : (isDark ? const Color(0xFF141E33) : Colors.white),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isTargetHighlight
                          ? const Color(0xFFA855F7)
                          : (hasConflict
                              ? const Color(0xFFFF2E63)
                              : groupColor.withValues(alpha: isDark ? 0.45 : 0.3)),
                      width: isTargetHighlight ? 3.0 : (hasConflict ? 2.2 : 1.2),
                    ),
                    boxShadow: [
                      if (isTargetHighlight) ...[
                        BoxShadow(
                          color: const Color(0xFFA855F7).withValues(alpha: 0.8),
                          blurRadius: 24,
                          spreadRadius: 3,
                        ),
                        BoxShadow(
                          color: const Color(0xFFC084FC).withValues(alpha: 0.45),
                          blurRadius: 40,
                          spreadRadius: 6,
                        ),
                      ] else ...[
                        BoxShadow(
                          color:
                              (hasConflict ? const Color(0xFFFF2E63) : groupColor)
                                  .withValues(
                                    alpha: isDark
                                        ? (hasConflict ? 0.4 : 0.15)
                                        : (hasConflict ? 0.3 : 0.06),
                                  ),
                          blurRadius: hasConflict ? 16 : 10,
                          spreadRadius: hasConflict ? 1.5 : 0,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ],
                  ),
                  child: Column(
                    children: [
                      if (isTargetHighlight)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFA855F7), Color(0xFF38BDF8)],
                            ),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(18),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.stars_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                '📍 المجموعة المحددة من الإشعار والجدول ⚡',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Conflict Warning Banner if overlapping with other group
                      if (hasConflict)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF991B1B), Color(0xFFDC2626)],
                            ),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(18),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '⚠️ تعارض في الموعد مع: ${groupConflictsList.map((c) => "${c['name']} (${c['time']})").toSet().join(' • ')}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => GroupsScreen(
                                        database: widget.database,
                                      ),
                                    ),
                                  ).then((_) => _loadData());
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'تعديل الموعد ⚡',
                                    style: TextStyle(
                                      color: Color(0xFF991B1B),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row: Group Name & Stage/Grade Badge
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: groupColor.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: groupColor.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.groups_rounded,
                                      color: groupColor,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              group.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 15.5,
                                                fontWeight: FontWeight.w900,
                                                color: isDark
                                                    ? Colors.white
                                                    : const Color(0xFF0F172A),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            constraints: const BoxConstraints(
                                              maxWidth: 120,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: groupColor.withValues(
                                                alpha: 0.15,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: groupColor.withValues(
                                                  alpha: 0.3,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              group.stage,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: groupColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${group.grade} ${group.subject.isNotEmpty ? "• ${group.subject}" : ""}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Timing, Venue & Pricing Info Chips
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                // Time
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF1E293B)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.schedule_rounded,
                                        size: 13,
                                        color: Color(0xFF00F2FE),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${group.startTime} - ${group.endTime}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '($durationMin د)',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF00F2FE),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Room / Venue
                                if (group.room.isNotEmpty)
                                  Container(
                                    constraints: BoxConstraints(
                                      maxWidth: MediaQuery.of(context).size.width - 64,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF1E293B)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.meeting_room_outlined,
                                          size: 13,
                                          color: Color(0xFFF59E0B),
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            group.room,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black87,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                // Monthly Price
                                if (group.monthlyPrice > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF1E293B)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.payments_outlined,
                                          size: 13,
                                          color: Color(0xFF10B981),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${group.monthlyPrice.toInt()} ج.م / ${group.billingType == "per_session" ? "حصة" : "شهر"}',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                // Days Chips
                                if (group.schedule.isNotEmpty)
                                  Container(
                                    constraints: BoxConstraints(
                                      maxWidth: MediaQuery.of(context).size.width - 64,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFA855F7,
                                      ).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.calendar_month_outlined,
                                          size: 13,
                                          color: Color(0xFFA855F7),
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            group.schedule,
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFA855F7),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 10),

                            // Action Buttons Row: [تحضير الحصة] & [قائمة الطلاب] & [تعديل]
                            Row(
                              children: [
                                // Attendance & Prep Button
                                Expanded(
                                  flex: 3,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isGroupLocked
                                          ? (isDark ? const Color(0xFF334155) : const Color(0xFF64748B))
                                          : groupColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => TodayAttendanceScreen(
                                            database: widget.database,
                                            preselectedGroupId: group.id,
                                          ),
                                        ),
                                      ).then((_) => _loadData());
                                    },
                                    icon: Icon(
                                      isGroupLocked ? Icons.lock_rounded : Icons.fact_check_rounded,
                                      size: 15,
                                      color: isGroupLocked ? const Color(0xFFFCA5A5) : Colors.white,
                                    ),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        isGroupLocked ? 'معتمدة ومغلقة 🔒' : 'تحضير الحضور',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: isGroupLocked ? const Color(0xFFFEE2E2) : Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // View Students Button
                                Expanded(
                                  flex: 2,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: isDark
                                          ? Colors.white
                                          : const Color(0xFF0F172A),
                                      side: BorderSide(
                                        color: isDark
                                            ? const Color(0xFF334155)
                                            : const Color(0xFFCBD5E1),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () =>
                                        _showGroupStudentsSheet(group),
                                    icon: const Icon(
                                      Icons.people_alt_outlined,
                                      size: 15,
                                    ),
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'الطلاب',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // Edit Group Button
                                IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: isDark
                                        ? const Color(0xFF1E293B)
                                        : const Color(0xFFF1F5F9),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.edit_note_rounded,
                                    size: 18,
                                  ),
                                  tooltip: 'تعديل بيانات المجموعة ومواعيدها',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => GroupsScreen(
                                          database: widget.database,
                                        ),
                                      ),
                                    ).then((_) => _loadData());
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isGroupLocked)
                  PositionedDirectional(
                    end: 18,
                    top: 14,
                    child: _buildCircularSealStamp(isDark),
                  ),
              ],
            );
              },
            ),
        ],
      ),
    );
  }

  // --- Summary Metric Pill Helper ---
  Widget _buildGroupsSummaryMetric({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required bool isDark,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: TextStyle(
            fontSize: 10.5,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // --- Show Group Students Bottom Sheet ---
  void _showGroupStudentsSheet(GroupModel group) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final groupColor = Color(
          group.colorValue != 0 ? group.colorValue : 0xFF8B5CF6,
        );

        return FutureBuilder<List<StudentModel>>(
          future: widget.database.getStudents(groupId: group.id),
          builder: (ctx, snapshot) {
            final students = snapshot.data ?? [];
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.70,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: groupColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.groups_rounded,
                          color: groupColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'طلاب: ${group.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '${students.length} طالب مقيد في هذه المجموعة',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : students.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person_off_rounded,
                                  size: 40,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'لا يوجد طلاب مسجلين في هذه المجموعة بعد',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            itemCount: students.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final s = students[i];
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF141E33)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF223147)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: groupColor.withValues(
                                        alpha: 0.15,
                                      ),
                                      child: Text(
                                        '${i + 1}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: groupColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.fullName,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF0F172A),
                                            ),
                                          ),
                                          if (s.studentPhone.isNotEmpty)
                                            Text(
                                              'هاتف الطالب: ${s.studentPhone}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark
                                                    ? Colors.grey.shade400
                                                    : Colors.grey.shade600,
                                              ),
                                            )
                                          else if (s.parentPhone.isNotEmpty)
                                            Text(
                                              'ولي الأمر: ${s.parentPhone}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark
                                                    ? Colors.grey.shade400
                                                    : Colors.grey.shade600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (s.paymentPlan.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          s.paymentPlan == 'per_session'
                                              ? 'بالحصة'
                                              : 'شهري',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- Integrated Groups Day Rectangle (اليوم الحالي في اليمين، ومقابله زر الأيام، وتفتح أفقي في سطر تحته) ---
  Widget _buildGroupsIntegratedDayRectangle(
    String todayName,
    int groupsCount,
    double totalHours,
    bool isDark,
  ) {
    final isToday = _groupsSelectedDay == todayName;
    final isAll = _groupsSelectedDay == 'الكل';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  isToday ? const Color(0xFF1E1B4B) : const Color(0xFF131B2E),
                  const Color(0xFF0F172A),
                ]
              : [
                  isToday ? const Color(0xFFFAF5FF) : const Color(0xFFF1F5F9),
                  Colors.white,
                ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isToday
              ? const Color(0xFFA855F7).withValues(alpha: 0.5)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1)),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isToday ? const Color(0xFFA855F7) : const Color(0xFF64748B))
                .withValues(alpha: isDark ? 0.25 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Right side has Current Day info, Left side has "الأيام" button
          Row(
            children: [
              // 1. Icon Badge (يمكن الضغط عليه للعودة الفورية لليوم الحالي)
              InkWell(
                onTap: isToday
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        setState(() => _groupsSelectedDay = todayName);
                      },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isToday
                          ? [const Color(0xFFA855F7), const Color(0xFF6366F1)]
                          : [const Color(0xFF0284C7), const Color(0xFF00F2FE)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isToday
                                    ? const Color(0xFFA855F7)
                                    : const Color(0xFF00F2FE))
                                .withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    isToday
                        ? Icons.stars_rounded
                        : (isAll
                              ? Icons.all_inclusive_rounded
                              : Icons.event_note_rounded),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // 2. Day Info (اسم اليوم فقط مثل: الأحد / الخميس / الثلاثاء + علامة النجمة هايبرلينك للعودة لليوم الحالي)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isAll ? 'جميع الأيام' : _groupsSelectedDay,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),

                        // علامة النجمة كـ هايبر لينك للعودة لليوم الحالي
                        if (!isToday)
                          InkWell(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              setState(() => _groupsSelectedDay = todayName);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'تمت العودة لليوم الحالي ($todayName) 🌟',
                                  ),
                                  backgroundColor: const Color(0xFF10B981),
                                  duration: const Duration(seconds: 1),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFBBF24,
                                ).withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFBBF24,
                                  ).withValues(alpha: 0.7),
                                  width: 1,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.stars_rounded,
                                    color: Color(0xFFFBBF24),
                                    size: 14,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'اليوم 🌟',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFBBF24),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF10B981), Color(0xFF059669)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.white,
                                  size: 10,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'اليوم الحالي 🌟',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isAll
                          ? '$groupsCount مجموعات في كافة الأيام'
                          : '$groupsCount مجموعات مجدولة • إجمالي ${totalHours.toStringAsFixed(1)} ساعة',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // 3. Opposite Side (Left in RTL): Small "الأيام" button
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(
                    () => _isGroupsDaysExpanded = !_isGroupsDaysExpanded,
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (isToday
                                ? const Color(0xFFA855F7)
                                : const Color(0xFF00F2FE))
                            .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          (isToday
                                  ? const Color(0xFFA855F7)
                                  : const Color(0xFF00F2FE))
                              .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 15,
                        color: isToday
                            ? const Color(0xFFA855F7)
                            : const Color(0xFF00F2FE),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'الأيام',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: isToday
                              ? const Color(0xFFA855F7)
                              : const Color(0xFF00F2FE),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _isGroupsDaysExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: isToday
                            ? const Color(0xFFA855F7)
                            : const Color(0xFF00F2FE),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Horizontal Row of Days (تفتح أفقي في سطر تحته مش رأسي وبنفس استايل التطبيق)
          if (_isGroupsDaysExpanded) ...[
            const SizedBox(height: 12),
            Container(
              height: 1,
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: _groupsWeekdays.map((day) {
                  final isSelected = _groupsSelectedDay == day;
                  final isDayToday = day == todayName;
                  final count = day == 'الكل'
                      ? _centerGroups.length
                      : _centerGroups
                            .where((g) => _isGroupScheduledOnDay(g, day))
                            .length;

                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _groupsSelectedDay = day;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFA855F7),
                                    Color(0xFF6366F1),
                                  ],
                                )
                              : null,
                          color: isSelected
                              ? null
                              : (isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFA855F7)
                                : (isDayToday
                                      ? const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.8)
                                      : (isDark
                                            ? const Color(0xFF334155)
                                            : const Color(0xFFCBD5E1))),
                            width: isSelected ? 1.8 : (isDayToday ? 1.4 : 1),
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFA855F7,
                                    ).withValues(alpha: 0.35),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              day == 'الكل'
                                  ? Icons.all_inclusive_rounded
                                  : (isDayToday
                                        ? Icons.stars_rounded
                                        : Icons.calendar_today_rounded),
                              size: 13,
                              color: isSelected
                                  ? Colors.white
                                  : (isDayToday
                                        ? const Color(0xFF10B981)
                                        : (isDark
                                              ? Colors.white70
                                              : Colors.black87)),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              day,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark
                                          ? Colors.grey.shade300
                                          : const Color(0xFF0F172A)),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : (isDark
                                          ? const Color(0xFF0F172A)
                                          : Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFFA855F7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // --- DESIGN 2: CLASSIC MATRIX VIEW (Supports Full Weekly Grid & Summary) ---
  // =========================================================================
  Widget _buildClassicView(bool isDark) {
    final now = DateTime.now();
    final todayName = _getTodayName(now.weekday);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        _schoolViewMode == 'grid' ? 8 : 16,
        10,
        _schoolViewMode == 'grid' ? 8 : 16,
        90,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-switcher for Classic: [جدول أسبوعي كامل] vs [جدول يومي]
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF141E33)
                    : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF223147)
                      : const Color(0xFFCBD5E1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSubTabButton(
                    'grid',
                    'جدول أسبوعي كامل',
                    _schoolViewMode,
                    isDark,
                    (m) {
                      setState(() => _schoolViewMode = m);
                      widget.database.setSetting(
                        'school_timetable_view_mode',
                        m,
                      );
                    },
                  ),
                  _buildSubTabButton(
                    'daily',
                    'جدول يومي',
                    _schoolViewMode,
                    isDark,
                    (m) {
                      setState(() => _schoolViewMode = m);
                      widget.database.setSetting(
                        'school_timetable_view_mode',
                        m,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          if (_schoolViewMode == 'grid') ...[
            _buildWeeklyMatrixGrid(isDark),
            const SizedBox(height: 16),
            _buildGridSummaryCard(isDark),
          ] else ...[
            _buildCyberDaysSlider(_schoolWeekdays, todayName, isDark),
            const SizedBox(height: 14),
            _buildCyberSchoolPeriodsList(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildSubTabButton(
    String mode,
    String title,
    String currentMode,
    bool isDark,
    Function(String) onSelect,
  ) {
    final isActive = currentMode == mode;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onSelect(mode);
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF00F2FE) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: isActive
                  ? const Color(0xFF0B1120)
                  : (isDark ? Colors.white60 : Colors.black87),
            ),
          ),
        ),
      ),
    );
  }

  // Weekly Matrix Grid
  Widget _buildWeeklyMatrixGrid(bool isDark) {
    const weekdays = _schoolWeekdays;
    const maxPeriods = 8;
    const titleLabel = 'الحصة';

    const double periodColWidth = 32.0;

    Widget buildTableHeader() {
      return Container(
        color: isDark ? const Color(0xFF15223A) : const Color(0xFFF1F5F9),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            SizedBox(
              width: periodColWidth,
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  titleLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            ...weekdays.map(
              (day) => Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _selectedDay == day
                          ? const Color(0xFF00F2FE)
                          : (isDark ? Colors.white70 : Colors.black87),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildPeriodsRows() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(maxPeriods, (i) {
          final num = i + 1;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGridRow(num, isDark),
              if (num == _recessAfterPeriod)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFFD97706,
                    ).withValues(alpha: isDark ? 0.15 : 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFD97706).withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.coffee_rounded,
                        color: Color(0xFFF59E0B),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'فسحة مدرسية • $_recessStartTime - $_recessEndTime',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFF59E0B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101B2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Matrix Header & Mode Switcher
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131D31) : const Color(0xFFF8FAFC),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(
                  Icons.calendar_view_week_rounded,
                  size: 18,
                  color: Color(0xFF00F2FE),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'جدول الحصص الأسبوعي',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Column(
            children: [
              buildTableHeader(),
              const Divider(height: 1, thickness: 1, color: Color(0x2294A3B8)),
              buildPeriodsRows(),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildGridRow(int periodNum, bool isDark) {
    const double periodColWidth = 32.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0x11FFFFFF) : const Color(0x11000000),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: periodColWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _convertToArabicNumerals(periodNum),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: isDark
                        ? const Color(0xFF00F2FE)
                        : const Color(0xFF0284C7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          ..._schoolWeekdays.map((day) {
            final period = _getPeriodFor(day, periodNum);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: _buildCellChip(period, isDark),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _convertToArabicNumerals(int n) {
    const arabicNums = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨'];
    return (n >= 1 && n <= 8) ? arabicNums[n] : n.toString();
  }

  String _convertToArabicWords(int n) {
    switch (n) {
      case 1:
        return 'الأولى';
      case 2:
        return 'الثانية';
      case 3:
        return 'الثالثة';
      case 4:
        return 'الرابعة';
      case 5:
        return 'الخامسة';
      case 6:
        return 'السادسة';
      case 7:
        return 'السابعة';
      case 8:
        return 'الثامنة';
      default:
        return '$n';
    }
  }

  void _showPeriodDetails(SchoolPeriodModel period) {
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final isLocked = _schoolPeriodLockedStatus[period.id] == true;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(
                period.subject.isNotEmpty ? period.subject : 'تفاصيل الحصة',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (isLocked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded, size: 12, color: Colors.red),
                    SizedBox(width: 4),
                    Text(
                      'معتمدة ومغلقة 🔒',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ],
                ),
              ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الفصل: ${period.className}'),
            const SizedBox(height: 8),
            Text('اليوم: ${period.dayOfWeek}'),
            Text('الحصة: ${_convertToArabicWords(period.periodNumber)} (${period.periodNumber})'),
            Text('الوقت: ${period.startTime} - ${period.endTime}'),
            if (period.room.isNotEmpty) Text('المكان: ${period.room}'),
            if (period.isReserve) ...[
              const SizedBox(height: 8),
              const Text('النوع: حصة احتياط ⚡', style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold)),
            ],
            if (period.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('ملاحظات: ${period.notes}'),
            ],
          ],
        ),
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: isLocked ? const Color(0xFF059669) : const Color(0xFFDC2626),
              side: BorderSide(color: isLocked ? const Color(0xFF059669) : const Color(0xFFDC2626)),
            ),
            icon: Icon(isLocked ? Icons.lock_open_rounded : Icons.lock_rounded, size: 16),
            label: Text(isLocked ? 'إلغاء قفل الحصة 🔓' : 'اعتماد وختم الحصة 🔒'),
            onPressed: () async {
              final key = 'school_period_lock_${period.id}_$todayStr';
              await widget.database.setSetting(key, isLocked ? 'false' : 'true');
              Navigator.pop(dialogContext);
              _loadData();
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildCellChip(SchoolPeriodModel? period, bool isDark) {
    if (period == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131D31) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Text(
            'راحة',
            style: TextStyle(
              fontSize: 10,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    Color bg = const Color(0xFF0284C7);
    Color border = const Color(0xFF38BDF8);

    if (period.isReserve) {
      bg = const Color(0xFF7C3AED);
      border = const Color(0xFFA78BFA);
    } else if (period.subject.isNotEmpty &&
        _subjectColors.containsKey(period.subject)) {
      final customColor = Color(_subjectColors[period.subject]!);
      bg = customColor;
      border = customColor;
    } else {
      final hash = period.className.hashCode.abs() % 4;
      if (hash == 0) {
        bg = const Color(0xFF00F2FE);
        border = const Color(0xFF38BDF8);
      } else if (hash == 1) {
        bg = const Color(0xFF4F46E5);
        border = const Color(0xFF818CF8);
      } else if (hash == 2) {
        bg = const Color(0xFF059669);
        border = const Color(0xFF34D399);
      } else {
        bg = const Color(0xFFD97706);
        border = const Color(0xFFFBBF24);
      }
    }

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _showPeriodDetails(period);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: BoxDecoration(
          color: bg.withValues(alpha: isDark ? 0.35 : 0.85),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: bg.withValues(alpha: isDark ? 0.25 : 0.1),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              period.isReserve ? 'احتياط ⚡' : period.className,
              style: const TextStyle(
                fontSize: 10.5,
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Sleek, Compact Weekly Period Count Banner (إشعار بسيط وخفيف لعدد حصص الأسبوع)
  Widget _buildGridSummaryCard(bool isDark) {
    final totalCount = _schoolPeriods.length;
    final classCounts = <String, int>{};
    int reserveCount = 0;
    for (final p in _schoolPeriods) {
      if (p.isReserve) {
        reserveCount++;
      } else {
        classCounts[p.className] = (classCounts[p.className] ?? 0) + 1;
      }
    }

    final colorsList = [
      const Color(0xFF00F2FE),
      const Color(0xFF7C3AED),
      const Color(0xFF059669),
      const Color(0xFFD97706),
      const Color(0xFFEC4899),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF101B2E).withValues(alpha: 0.9)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.analytics_outlined,
              color: Color(0xFF00F2FE),
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'حصص الأسبوع: $totalCount',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  ...classCounts.entries.toList().asMap().entries.map((entry) {
                    final idx = entry.key;
                    final c = entry.value;
                    final color = colorsList[idx % colorsList.length];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '${c.key}: ${c.value}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    );
                  }),
                  if (reserveCount > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF59E0B,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(
                              0xFFF59E0B,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'احتياط: $reserveCount',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
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

  // =========================================================================
  // --- 6. ADD / EDIT PERIOD MODAL (Class Palette + Time Pickers + 8 Periods) ---
  // =========================================================================
  void _showAddEditPeriodModal({
    SchoolPeriodModel? existing,
    String? initialDay,
    int? initialPeriod,
    String? initialClass,
    String? initialSubject,
    String? initialRoom,
    VoidCallback? onSavedCallback,
  }) {
    String selectedDay = existing?.dayOfWeek ?? initialDay ?? _selectedDay;
    int selectedPeriod = existing?.periodNumber ?? initialPeriod ?? 1;
    final classCtrl = TextEditingController(
      text: existing?.className ?? initialClass ?? '',
    );
    final subjectCtrl = TextEditingController(
      text: existing?.subject ?? initialSubject ?? '',
    );
    final roomCtrl = TextEditingController(
      text: existing?.room ?? initialRoom ?? '',
    );
    bool isReserve = existing?.isReserve ?? false;
    bool isDuty = (existing?.supervisionDuty ?? '').isNotEmpty;

    final initialTiming =
        _periodTimings[selectedPeriod] ?? (start: '08:00', end: '08:45');
    String startTime = existing?.startTime ?? initialTiming.start;
    String endTime = existing?.endTime ?? initialTiming.end;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      existing == null
                          ? 'إضافة حصة للجدول المدرسي'
                          : 'تعديل الحصة المدرسية',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 1. اختيار اليوم
                  const Text(
                    'اختيار اليوم',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _schoolWeekdays.map((day) {
                        final isSel = selectedDay == day;
                        return Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: InkWell(
                            onTap: () => setModalState(() => selectedDay = day),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? const Color(0xFF00F2FE)
                                    : (isDark
                                          ? const Color(0xFF1E293B)
                                          : const Color(0xFFF1F5F9)),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSel
                                      ? const Color(0xFF00F2FE)
                                      : (isDark
                                            ? const Color(0xFF334155)
                                            : const Color(0xFFCBD5E1)),
                                ),
                              ),
                              child: Text(
                                day,
                                style: TextStyle(
                                  color: isSel
                                      ? const Color(0xFF0B1120)
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.black87),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. رقم الحصة (1 إلى 8)
                  const Text(
                    'رقم الحصة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: List.generate(8, (i) {
                      final num = i + 1;
                      final isSel = selectedPeriod == num;
                      return InkWell(
                        onTap: () => setModalState(() {
                          selectedPeriod = num;
                          if (existing == null) {
                            final def =
                                _periodTimings[num] ??
                                (start: '08:00', end: '08:45');
                            startTime = def.start;
                            endTime = def.end;
                          }
                        }),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSel
                                ? const Color(0xFF00F2FE)
                                : (isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSel
                                  ? const Color(0xFF00F2FE)
                                  : (isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFCBD5E1)),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              _convertToArabicNumerals(num),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isSel
                                    ? const Color(0xFF0B1120)
                                    : (isDark
                                          ? Colors.white70
                                          : Colors.black87),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),

                  // 3. توقيت الحصة (من - إلى)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'توقيت الحصة (اضغط لتعديل الوقت)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          final def =
                              _periodTimings[selectedPeriod] ??
                              (start: '08:00', end: '08:45');
                          setModalState(() {
                            startTime = def.start;
                            endTime = def.end;
                          });
                        },
                        child: const Text(
                          'استعادة الافتراضي ↺',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF00F2FE),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await _pickCustomTime(
                              ctx,
                              startTime,
                            );
                            if (picked != null)
                              setModalState(() => startTime = picked);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 16,
                                  color: Color(0xFF00F2FE),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'من (البداية)',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      startTime,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await _pickCustomTime(ctx, endTime);
                            if (picked != null)
                              setModalState(() => endTime = picked);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.alarm_on_rounded,
                                  size: 16,
                                  color: Color(0xFF10B981),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'إلى (النهاية)',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      endTime,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 4. الفصل (فقط الفصل بدون المرحلة)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'الفصل (اختر بضغطة واحدة أو اكتب الاسم)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _showManageClassesDialog();
                        },
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 14,
                              color: Color(0xFF00F2FE),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'إدارة فصولي ⚙️',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF00F2FE),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Quick Class Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ..._schoolClasses.map((sc) {
                          final cName = (sc['class_name'] ?? '').toString();
                          final subj = (sc['subject'] ?? '').toString();
                          final isChosen = classCtrl.text == cName;
                          return Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: InkWell(
                              onTap: () {
                                setModalState(() {
                                  classCtrl.text = cName;
                                  final s = (sc['subject'] ?? '').toString();
                                  final rm = (sc['room'] ?? '').toString();
                                  if (s.isNotEmpty) subjectCtrl.text = s;
                                  if (rm.isNotEmpty) roomCtrl.text = rm;
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: isChosen
                                      ? const Color(0xFF00F2FE)
                                      : (isDark
                                            ? const Color(0xFF1E293B)
                                            : const Color(0xFFF1F5F9)),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isChosen
                                        ? const Color(0xFF00F2FE)
                                        : (isDark
                                              ? const Color(0xFF334155)
                                              : const Color(0xFFCBD5E1)),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      cName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isChosen
                                            ? const Color(0xFF0B1120)
                                            : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                      ),
                                    ),
                                    if (subj.isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      Text(
                                        '($subj)',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: isChosen
                                              ? const Color(
                                                  0xFF0B1120,
                                                ).withValues(alpha: 0.8)
                                              : (isDark
                                                    ? Colors.cyanAccent.shade100
                                                    : const Color(0xFF0284C7)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        InkWell(
                          onTap: () {
                            _showQuickAddClassDialog(
                              onAdded: (newClassName, newSubject) {
                                setModalState(() {
                                  classCtrl.text = newClassName;
                                  if (newSubject.isNotEmpty)
                                    subjectCtrl.text = newSubject;
                                });
                              },
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF00F2FE,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF00F2FE),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_rounded,
                                  size: 14,
                                  color: Color(0xFF00F2FE),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'فصل ومادة ＋',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00F2FE),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextFormField(
                    controller: classCtrl,
                    decoration: InputDecoration(
                      hintText: 'اسم الفصل (مثال: 1/1 أو 2/1)',
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 5. المادة والقاعة
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'المادة الدراسية (اختر بضغطة واحدة أو اكتب)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _showManageSubjectsDialog();
                        },
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 14,
                              color: Color(0xFFA78BFA),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'إدارة موادي ⚙️',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFA78BFA),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Quick Subject Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ..._schoolSubjects.map((sb) {
                          final sName = (sb['name'] ?? '').toString();
                          final isChosen = subjectCtrl.text == sName;
                          return Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: InkWell(
                              onTap: () {
                                setModalState(() => subjectCtrl.text = sName);
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: isChosen
                                      ? const Color(0xFFA78BFA)
                                      : (isDark
                                            ? const Color(0xFF1E293B)
                                            : const Color(0xFFF1F5F9)),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isChosen
                                        ? const Color(0xFFA78BFA)
                                        : (isDark
                                              ? const Color(0xFF334155)
                                              : const Color(0xFFCBD5E1)),
                                  ),
                                ),
                                child: Text(
                                  sName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isChosen
                                        ? Colors.black
                                        : (isDark
                                              ? Colors.white70
                                              : Colors.black87),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        InkWell(
                          onTap: () {
                            _showAddOrEditSubjectDialog(
                              onAdded: (newSubjName) {
                                setModalState(
                                  () => subjectCtrl.text = newSubjName,
                                );
                              },
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFA78BFA,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFA78BFA),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_rounded,
                                  size: 14,
                                  color: Color(0xFFA78BFA),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'مادة جديدة',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFA78BFA),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextFormField(
                    controller: subjectCtrl,
                    decoration: InputDecoration(
                      hintText: 'اسم المادة (مثال: رياضيات / علوم / حاسب)',
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: roomCtrl,
                    decoration: InputDecoration(
                      hintText: 'القاعة أو المعمل (مثال: معمل 1)',
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 6. Switches
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text(
                            'حصة احتياط',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          value: isReserve,
                          activeThumbColor: const Color(0xFF7C3AED),
                          onChanged: (val) =>
                              setModalState(() => isReserve = val),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: const Text(
                            'إشراف الفسحة / الطابور',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          value: isDuty,
                          activeThumbColor: const Color(0xFFF59E0B),
                          onChanged: (val) => setModalState(() => isDuty = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 7. Save & Cancel Buttons
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00F2FE),
                        foregroundColor: const Color(0xFF0B1120),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 4,
                      ),
                      onPressed: () async {
                        final className = classCtrl.text.trim();
                        final subject = subjectCtrl.text.trim();
                        if (className.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('يرجى إدخال اسم الفصل'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        if (!_schoolClasses.any(
                          (c) => c['class_name'] == className,
                        )) {
                          final newClass = {
                            'id':
                                'class_${DateTime.now().millisecondsSinceEpoch}',
                            'stage': '',
                            'class_name': className,
                            'subject': subject,
                            'room': roomCtrl.text.trim(),
                            'sort_order': _schoolClasses.length + 1,
                          };
                          await widget.database.saveSchoolClass(newClass);
                        }

                        if (subject.isNotEmpty &&
                            !_schoolSubjects.any((s) => s['name'] == subject)) {
                          final newSubj = {
                            'id':
                                'subj_${DateTime.now().millisecondsSinceEpoch}',
                            'name': subject,
                            'sort_order': _schoolSubjects.length + 1,
                          };
                          await widget.database.saveSchoolSubject(newSubj);
                        }

                        final newPeriod = SchoolPeriodModel(
                          id:
                              existing?.id ??
                              'period_${DateTime.now().millisecondsSinceEpoch}',
                          dayOfWeek: selectedDay,
                          periodNumber: selectedPeriod,
                          className: className,
                          subject: subject.isNotEmpty ? subject : '',
                          startTime: startTime,
                          endTime: endTime,
                          room: roomCtrl.text.trim(),
                          isReserve: isReserve,
                          supervisionDuty: isDuty ? 'إشراف الفناء' : '',
                        );

                        await widget.database.saveSchoolPeriod(newPeriod);
                        Navigator.pop(ctx);
                        await _loadData();
                        onSavedCallback?.call();

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم حفظ الحصة (${newPeriod.className}) بنجاح ✅',
                              ),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: const Color(0xFF10B981),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'حفظ الحصة',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          'حذف هذه الحصة',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmDeletePeriod(existing);
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'إلغاء',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<String?> _pickCustomTime(BuildContext ctx, String currentTime) async {
    int initialHour = 8;
    int initialMinute = 0;
    final parsed = AlarmService.parseTimeString(currentTime);
    if (parsed != null) {
      initialHour = parsed.$1;
      initialMinute = parsed.$2;
    }

    final TimeOfDay? picked = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
      helpText: 'اختر وقت الحصة',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
    );

    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return null;
  }

  void _confirmDeletePeriod(SchoolPeriodModel period) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'حذف الحصة المدرسية',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'هل تريد بالتأكيد حذف الحصة (${period.className}) من يوم ${period.dayOfWeek}؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await NotificationService.cancelAlarmByKey('period_${period.id}');
              await widget.database.deleteSchoolPeriod(period.id);
              Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // --- 7. ADD / EDIT TUTORING PERIOD MODAL (Group Palette + Timings) ---
  // =========================================================================

  // --- Helpers for Interactive Timetable Settings ---
  String _addMinutesToTimeString(String timeStr, int minutesToAdd) {
    try {
      final parsed = AlarmService.parseTimeString(timeStr);
      if (parsed == null) return timeStr;
      final total = (parsed.$1 * 60 + parsed.$2 + minutesToAdd + 1440) % 1440;
      final newH = total ~/ 60;
      final newM = total % 60;
      return '${newH.toString().padLeft(2, '0')}:${newM.toString().padLeft(2, '0')}';
    } catch (_) {
      return timeStr;
    }
  }

  Future<void> _quickEditPeriodTimes(
    BuildContext ctx,
    SchoolPeriodModel period,
    StateSetter setSheetState,
  ) async {
    final newStart = await _pickCustomTime(ctx, period.startTime);
    if (newStart == null || !mounted) return;
    final newEnd = await _pickCustomTime(ctx, period.endTime);
    if (newEnd == null || !mounted) return;

    HapticFeedback.mediumImpact();
    final updated = period.copyWith(
      startTime: newStart,
      endTime: newEnd,
    );
    await widget.database.saveSchoolPeriod(updated);
    await _loadData();
    setSheetState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تحديث توقيت الحصة بنجاح! ⏱️'),
        backgroundColor: Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _duplicatePeriodToOtherDay(
    BuildContext ctx,
    SchoolPeriodModel period,
    StateSetter setSheetState,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final availableDays =
        _schoolWeekdays.where((d) => d != period.dayOfWeek).toList();

    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (copyCtx) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.copy_all_rounded,
                  color: Color(0xFF818CF8),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'نسخ الحصة (${period.subject.isEmpty ? "احتياط" : period.subject}) إلى يوم آخر:',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(copyCtx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'اختر اليوم الدراسي لنسخ الحصة إليه بنفس الموعد والفصل:',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: availableDays.map((day) {
                return ActionChip(
                  avatar: const Icon(
                    Icons.calendar_today_rounded,
                    size: 14,
                    color: Color(0xFF818CF8),
                  ),
                  label: Text(
                    day,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    Navigator.pop(copyCtx);
                    final newPeriod = SchoolPeriodModel(
                      id: 'period_${DateTime.now().millisecondsSinceEpoch}',
                      dayOfWeek: day,
                      periodNumber: period.periodNumber,
                      className: period.className,
                      subject: period.subject,
                      startTime: period.startTime,
                      endTime: period.endTime,
                      room: period.room,
                      notes: period.notes,
                      isRecess: period.isRecess,
                      supervisionDuty: period.supervisionDuty,
                      isReserve: period.isReserve,
                    );
                    await widget.database.saveSchoolPeriod(newPeriod);
                    await _loadData();
                    setSheetState(() {});
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم نسخ الحصة بنجاح إلى يوم $day 📋✨'),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletePeriodInSettings(
    BuildContext ctx,
    SchoolPeriodModel period,
    StateSetter setSheetState,
  ) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text(
          'تأكيد حذف الحصة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل أنت متأكد من حذف الحصة ${period.periodNumber} (${period.subject.isEmpty ? "احتياط" : period.subject}) ليوم ${period.dayOfWeek}؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedback.mediumImpact();
      await NotificationService.cancelAlarmByKey('period_${period.id}');
      await widget.database.deleteSchoolPeriod(period.id);
      await _loadData();
      setSheetState(() {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الحصة بنجاح.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // =========================================================================
  // --- AI TIMETABLE IMPORT & EDIT MODAL (GEMINI INTEGRATION) ---
  // =========================================================================
  Future<void> _showAiTimetableImportSheet({
    String? initialDay,
    bool returnToSettings = false,
  }) async {
    _showUnifiedTimetableSettings(initialTab: 1);
    if (1 == 2) {
      await _unusedOldAiSheet(
        initialDay: initialDay,
        returnToSettings: returnToSettings,
      );
    }
    return;
  }

  Future<void> _unusedOldAiSheet({
    String? initialDay,
    bool returnToSettings = false,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textController = TextEditingController();
    bool isSingleDayOnly = initialDay != null;
    String selectedDay = initialDay ?? _settingsSelectedDay;
    if (!_schoolWeekdays.contains(selectedDay)) {
      selectedDay = _schoolWeekdays.first;
    }
    AiTimetableParseResult? parseResult;
    bool isProcessing = false;
    bool hasBackup = await widget.database.hasSchoolTimetableBackup();
    bool showPeriodsPreviewList = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          // Re-evaluate parser whenever text or day changes
          void reevaluate() {
            final text = textController.text.trim();
            if (text.isEmpty) {
              parseResult = null;
            } else {
              parseResult = AiTimetableParserService.parse(
                text,
                periodTimings: _periodTimings,
              );
            }
          }

          // Filter periods for target scope
          List<SchoolPeriodModel> activePeriods = [];
          if (parseResult != null && parseResult!.isSuccess) {
            if (isSingleDayOnly) {
              activePeriods = parseResult!.periods
                  .where((p) => p.dayOfWeek == selectedDay)
                  .toList();
            } else {
              activePeriods = parseResult!.periods;
            }
          }

          return Container(
            height: MediaQuery.of(sheetCtx).size.height * 0.94,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                // Top Header Row
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تعديل الجدول المدرسي (الذكاء الاصطناعي)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'استيراد وتحديث الجدول فوراً من صورة عبر Gemini 📸',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? const Color(0xFF818CF8)
                                    : const Color(0xFF4F46E5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          if (returnToSettings) _showUnifiedTimetableSettings();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Content Area
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // === STEP 1: البرومبت والربط مع Gemini ===
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B).withValues(alpha: 0.7)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '1',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'الخطوة الأولى: جهّز البيانات من Gemini',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'صوّر جدولك الورقي بالموبايل، ثم انسخ البرومبت بالزر أدناه وأرسل الصورة والبرومبت لشات Gemini:',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'نسخ برومبت Gemini 📋',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    Clipboard.setData(
                                      const ClipboardData(
                                        text: AiTimetableParserService
                                            .geminiPromptTemplate,
                                      ),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Row(
                                          children: [
                                            Icon(
                                              Icons.check_circle_rounded,
                                              color: Colors.greenAccent,
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'تم نسخ برومبت Gemini بنجاح! الصقه في شات Gemini مع صورة الجدول.',
                                              ),
                                            ),
                                          ],
                                        ),
                                        backgroundColor: Color(0xFF1E1B4B),
                                        duration: Duration(seconds: 4),
                                      ),
                                    );
                                  },
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: isDark
                                        ? const Color(0xFF818CF8)
                                        : const Color(0xFF4F46E5),
                                    side: BorderSide(
                                      color: isDark
                                          ? const Color(0xFF6366F1)
                                          : const Color(0xFF818CF8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.open_in_new_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'فتح Gemini ↗️',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () async {
                                    final uri = Uri.parse(
                                      'https://gemini.google.com/app',
                                    );
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // === STEP 2: تحديد نطاق التحديث + لصق الرد ===
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B).withValues(alpha: 0.7)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00F2FE),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '2',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'الخطوة الثانية: الصق رد Gemini وحدد النطاق',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Scope Switch: Entire Week vs Single Day
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Center(
                                      child: Text(
                                        'كامل الأسبوع 🔄',
                                        style: TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                    selected: !isSingleDayOnly,
                                    onSelected: (sel) {
                                      if (sel) {
                                        setSheetState(() {
                                          isSingleDayOnly = false;
                                          reevaluate();
                                        });
                                      }
                                    },
                                    selectedColor: const Color(0xFF6366F1),
                                    labelStyle: TextStyle(
                                      color: !isSingleDayOnly
                                          ? Colors.white
                                          : (isDark
                                              ? Colors.white70
                                              : Colors.black87),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Center(
                                      child: Text(
                                        'يوم محدد فقط 📅',
                                        style: TextStyle(fontSize: 11.5),
                                      ),
                                    ),
                                    selected: isSingleDayOnly,
                                    onSelected: (sel) {
                                      if (sel) {
                                        setSheetState(() {
                                          isSingleDayOnly = true;
                                          reevaluate();
                                        });
                                      }
                                    },
                                    selectedColor: const Color(0xFF00F2FE),
                                    labelStyle: TextStyle(
                                      color: isSingleDayOnly
                                          ? Colors.black
                                          : (isDark
                                              ? Colors.white70
                                              : Colors.black87),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            if (isSingleDayOnly) ...[
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                                  children: _schoolWeekdays.map((day) {
                                    final isSel = selectedDay == day;
                                    return Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: ChoiceChip(
                                        label: Text(
                                          day,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        selected: isSel,
                                        onSelected: (sel) {
                                          if (sel) {
                                            setSheetState(() {
                                              selectedDay = day;
                                              reevaluate();
                                            });
                                          }
                                        },
                                        selectedColor: const Color(0xFF00F2FE),
                                        labelStyle: TextStyle(
                                          color: isSel
                                              ? Colors.black
                                              : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],

                            const SizedBox(height: 10),

                            // Paste input text box
                            TextField(
                              controller: textController,
                              maxLines: 6,
                              minLines: 3,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'الصق كود الـ JSON أو النص الناتج من Gemini هنا...',
                                hintTextDirection: TextDirection.rtl,
                                hintStyle: TextStyle(
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.grey.shade500,
                                  fontSize: 11.5,
                                ),
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF0B1120)
                                    : Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF6366F1),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              onChanged: (_) {
                                setSheetState(reevaluate);
                              },
                            ),
                            const SizedBox(height: 8),

                            // Quick Buttons: Paste, Analyze & Clear
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.paste_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'لصق من الحافظة 📋',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () async {
                                    final data = await Clipboard.getData(
                                      Clipboard.kTextPlain,
                                    );
                                    if (data?.text != null &&
                                        data!.text!.trim().isNotEmpty) {
                                      textController.text = data.text!;
                                      setSheetState(reevaluate);
                                    }
                                  },
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.search_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'فحص وتحليل الكود 🔍',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    setSheetState(reevaluate);
                                  },
                                ),
                                if (textController.text.isNotEmpty)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.redAccent,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'مسح',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                    onPressed: () {
                                      textController.clear();
                                      setSheetState(reevaluate);
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // === STEP 3: نتيجة الفحص والتحليل ===
                      if (parseResult != null) ...[
                        if (parseResult!.isSuccess)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF10B981),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'تم التعرف على ${parseResult!.totalPeriods} حصة بنجاح!',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12.5,
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: parseResult!.periodsPerDay.entries
                                      .map((e) {
                                    final isTarget = isSingleDayOnly &&
                                        e.key == selectedDay;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isTarget
                                            ? const Color(0xFF00F2FE)
                                            : (isDark
                                                ? const Color(0xFF1E293B)
                                                : Colors.white),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isTarget
                                              ? const Color(0xFF00F2FE)
                                              : Colors.grey.shade400,
                                        ),
                                      ),
                                      child: Text(
                                        '${e.key}: ${e.value} حصص',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: isTarget
                                              ? Colors.black
                                              : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                if (isSingleDayOnly && activePeriods.isEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'تنبيه: لم يتم العثور على حصص خاصة بيوم $selectedDay في البيانات المدخلة.',
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () {
                                    setSheetState(() {
                                      showPeriodsPreviewList =
                                          !showPeriodsPreviewList;
                                    });
                                  },
                                  child: Row(
                                    children: [
                                      Text(
                                        showPeriodsPreviewList
                                            ? 'إخفاء تفاصيل الحصص ▲'
                                            : 'عرض تفاصيل الحصص (${activePeriods.length} حصة) ▼',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF6366F1),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (showPeriodsPreviewList &&
                                    activePeriods.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    constraints:
                                        const BoxConstraints(maxHeight: 180),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF0F172A)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.all(8),
                                      itemCount: activePeriods.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 6),
                                      itemBuilder: (_, idx) {
                                        final p = activePeriods[idx];
                                        return Row(
                                          children: [
                                            Container(
                                              width: 24,
                                              height: 24,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6366F1)
                                                    .withValues(alpha: 0.2),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Text(
                                                '${p.periodNumber}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${p.dayOfWeek} • ${p.subject} • ${p.className}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${p.startTime} - ${p.endTime}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isDark
                                                    ? Colors.white54
                                                    : Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.redAccent,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    parseResult!.errorMessage ??
                                        'تعذر استخراج الحصص من النص المدخل. يرجى التأكد من نسخ الـ JSON بشكل صحيح.',
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 14),
                      ],

                      // Backup / Undo Notification Banner if available
                      if (hasBackup) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.history_rounded,
                                size: 16,
                                color: Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'توجد نسخة احتياطية سابقة محفوظة يمكنك استرجاعها في أي وقت.',
                                  style: TextStyle(fontSize: 10.5),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: sheetCtx,
                                    builder: (c) => AlertDialog(
                                      title: const Text('استرجاع الجدول السابق'),
                                      content: const Text(
                                        'هل تريد استرجاع النسخة السابقة من الجدول المدرسي؟',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('إلغاء'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text('نعم، استرجع'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    final restored = await widget.database
                                        .restoreSchoolTimetableBackup();
                                    if (restored > 0) {
                                      await _loadData();
                                      if (sheetCtx.mounted) {
                                        Navigator.pop(sheetCtx);
                                      }
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'تم استرجاع الجدول السابق بنجاح ↩️',
                                            ),
                                            backgroundColor: Colors.teal,
                                          ),
                                        );
                                      }
                                    }
                                  }
                                },
                                child: const Text(
                                  'تراجع الآن ↩️',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFF59E0B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),

                // Bottom Action Bar ("نفذ")
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF141E33)
                        : const Color(0xFFF8FAFC),
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? const Color(0xFF223147)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: isProcessing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.rocket_launch_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            isProcessing
                                ? 'جارٍ تطبيق الجدول...'
                                : 'نفذ (تحديث الجدول المدرسي) 🚀',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: isProcessing
                              ? null
                              : () async {
                                  final rawInput = textController.text.trim();
                                  if (rawInput.isEmpty) {
                                    HapticFeedback.lightImpact();
                                    await showDialog(
                                      context: sheetCtx,
                                      builder: (c) => AlertDialog(
                                        title: const Row(
                                          children: [
                                            Icon(
                                              Icons.warning_amber_rounded,
                                              color: Colors.amber,
                                              size: 24,
                                            ),
                                            SizedBox(width: 8),
                                            Text('تنبيه'),
                                          ],
                                        ),
                                        content: const Text(
                                          'يرجى لصق كود أو نص الجدول الناتج من Gemini أولاً في المربع المخصص قبل الضغط على تنفيذ.',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                        actions: [
                                          FilledButton(
                                            onPressed: () => Navigator.pop(c),
                                            child: const Text('حسناً'),
                                          ),
                                        ],
                                      ),
                                    );
                                    return;
                                  }

                                  // Force on-the-spot parsing
                                  setSheetState(() => isProcessing = true);
                                  final result = AiTimetableParserService.parse(
                                    rawInput,
                                    periodTimings: _periodTimings,
                                  );
                                  setSheetState(() {
                                    parseResult = result;
                                    isProcessing = false;
                                  });

                                  // Failure alert if no periods parsed
                                  if (!result.isSuccess || result.periods.isEmpty) {
                                    HapticFeedback.heavyImpact();
                                    if (sheetCtx.mounted) {
                                      await showDialog(
                                        context: sheetCtx,
                                        builder: (c) => AlertDialog(
                                          title: const Row(
                                            children: [
                                              Icon(
                                                Icons.cancel_rounded,
                                                color: Colors.redAccent,
                                                size: 24,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'فشل تحديث الجدول ❌',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'تعذر قراءة أو استخراج الحصص من النص المدخل.',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: Colors.redAccent
                                                        .withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                child: Text(
                                                  result.errorMessage ??
                                                      'تنسيق البيانات غير مطابق للـ JSON المطلوب.',
                                                  style: const TextStyle(
                                                    fontSize: 11.5,
                                                    color: Colors.redAccent,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              const Text(
                                                'تأكد من نسخ كود الـ JSON بالكامل من رد Gemini أو استخدام زر نسخ البرومبت أعلاه.',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    Colors.redAccent,
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(c),
                                              child: const Text('حسناً'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  // Scope check
                                  List<SchoolPeriodModel> targetPeriods;
                                  if (isSingleDayOnly) {
                                    targetPeriods = result.periods
                                        .where((p) => p.dayOfWeek == selectedDay)
                                        .toList();
                                    if (targetPeriods.isEmpty) {
                                      final availableDays = result
                                          .periodsPerDay.entries
                                          .where((e) => e.value > 0)
                                          .map((e) => e.key)
                                          .toList();

                                      final switchScope =
                                          await showDialog<bool>(
                                        context: sheetCtx,
                                        builder: (c) => AlertDialog(
                                          title: const Text(
                                            'تنبيه: نطاق التحديث',
                                          ),
                                          content: Text(
                                            'لم يتم العثور على حصص ليوم $selectedDay في البيانات المدخلة.\n\nالأيام المتوفرة في الكود هي: ${availableDays.join("، ")} (إجمالي ${result.totalPeriods} حصة).\n\nهل تريد تحديث الجدول لكامل الأسبوع بدلاً من يوم $selectedDay فقط؟',
                                            style:
                                                const TextStyle(fontSize: 12.5),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const Text(
                                                'إلغاء لاختيار اليوم',
                                              ),
                                            ),
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF6366F1),
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: const Text(
                                                'نعم، حدّث كامل الأسبوع 🔄',
                                              ),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (switchScope == true) {
                                        setSheetState(() {
                                          isSingleDayOnly = false;
                                        });
                                        targetPeriods = result.periods;
                                      } else {
                                        return;
                                      }
                                    }
                                  } else {
                                    targetPeriods = result.periods;
                                  }

                                  // Confirmation Dialog
                                  HapticFeedback.mediumImpact();
                                  final confirm = await showDialog<bool>(
                                    context: sheetCtx,
                                    builder: (c) => AlertDialog(
                                      title: const Row(
                                        children: [
                                          Icon(
                                            Icons.auto_awesome_rounded,
                                            color: Color(0xFF6366F1),
                                          ),
                                          SizedBox(width: 8),
                                          Text('تأكيد تحديث الجدول'),
                                        ],
                                      ),
                                      content: Text(
                                        isSingleDayOnly
                                            ? 'سيتم استبدال جدول يوم $selectedDay فقط بـ ${targetPeriods.length} حصص جديدة.\n\nسيتم حفظ نسخة احتياطية من جدولك الحالي تلقائياً للرجوع في أي وقت.'
                                            : 'سيتم استبدال جدول الحصص بالكامل لجميع الأيام بـ ${targetPeriods.length} حصة جديدة.\n\nسيتم حفظ نسخة احتياطية من جدولك الحالي تلقائياً للرجوع في أي وقت.',
                                        style: const TextStyle(fontSize: 12.5),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('إلغاء'),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF6366F1),
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text('تأكيد وتنفيذ 🚀'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm != true) return;

                                  setSheetState(() => isProcessing = true);

                                  try {
                                    // 1. Backup
                                    await widget.database
                                        .backupSchoolTimetable();

                                    // 2. Apply import
                                    final count = await widget.database
                                        .applyAiSchoolTimetableImport(
                                      targetPeriods,
                                      targetDayOnly: isSingleDayOnly
                                          ? selectedDay
                                          : null,
                                    );

                                    // 3. Reload screen data
                                    await _loadData();

                                    // Close bottom sheet
                                    if (sheetCtx.mounted) {
                                      Navigator.pop(sheetCtx);
                                    }

                                    // Explicit Success Dialog
                                    if (mounted) {
                                      await showDialog(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          title: const Row(
                                            children: [
                                              Icon(
                                                Icons.check_circle_rounded,
                                                color: Color(0xFF10B981),
                                                size: 26,
                                              ),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'تم تحديث الجدول بنجاح! 🚀',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          content: Text(
                                            isSingleDayOnly
                                                ? 'تم بنجاح تحديث جدول يوم $selectedDay وإضافة $count حصة جديدة في الجدول المدرسي.'
                                                : 'تم بنجاح تحديث الجدول المدرسي بالكامل وإضافة $count حصة جديدة لجميع الأيام.',
                                            style:
                                                const TextStyle(fontSize: 13),
                                          ),
                                          actions: [
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF10B981),
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(c),
                                              child: const Text('حسناً 👍'),
                                            ),
                                          ],
                                        ),
                                      );

                                      // Re-open settings if requested AFTER success dialog
                                      if (returnToSettings) {
                                        _showUnifiedTimetableSettings();
                                      }
                                    }
                                  } catch (e) {
                                    setSheetState(() => isProcessing = false);
                                    if (sheetCtx.mounted) {
                                      await showDialog(
                                        context: sheetCtx,
                                        builder: (c) => AlertDialog(
                                          title: const Row(
                                            children: [
                                              Icon(
                                                Icons.error_outline_rounded,
                                                color: Colors.redAccent,
                                              ),
                                              SizedBox(width: 8),
                                              Text('فشل تحديث الجدول ❌'),
                                            ],
                                          ),
                                          content: Text(
                                            'حدث خطأ أثناء تطبيق الجدول:\n$e',
                                          ),
                                          actions: [
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    Colors.redAccent,
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(c),
                                              child: const Text('إغلاق'),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAutoPeriodTimingsGenerator(
    BuildContext ctx,
    StateSetter setSheetState,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String startTime = _periodTimings[1]?.start ?? '08:00';
    int periodDuration = 45;
    int recessAfter = _recessAfterPeriod;
    int recessDuration = 30;
    bool updateExistingDay = true;
    bool updateAllWeek = false;

    try {
      final p1Start = _periodTimings[1]!.start.split(':');
      final p1End = _periodTimings[1]!.end.split(':');
      final startMin = int.parse(p1Start[0]) * 60 + int.parse(p1Start[1]);
      final endMin = int.parse(p1End[0]) * 60 + int.parse(p1End[1]);
      final diff = endMin - startMin;
      if (diff > 15 && diff < 120) periodDuration = diff;
    } catch (_) {}

    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (genCtx) => StatefulBuilder(
        builder: (genCtx, setGenState) {
          final previewTimings = <int, ({String start, String end})>{};
          String currentCursor = startTime;
          String previewRecessStart = '';
          String previewRecessEnd = '';

          for (int i = 1; i <= 8; i++) {
            final pEnd = _addMinutesToTimeString(currentCursor, periodDuration);
            previewTimings[i] = (start: currentCursor, end: pEnd);
            currentCursor = pEnd;

            if (i == recessAfter) {
              previewRecessStart = currentCursor;
              previewRecessEnd =
                  _addMinutesToTimeString(currentCursor, recessDuration);
              currentCursor = previewRecessEnd;
            }
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(genCtx).size.height * 0.88,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00F2FE), Color(0xFF2563EB)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'مولد تسلسل توقيتات الحصص الذكي ⚡',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            'حساب وتحديث مواعيد الحصص والفسحة بضغطة زر واحدة',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(genCtx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // 1. وقت بداية الحصة الأولى
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.start_rounded,
                                  color: Color(0xFF00F2FE),
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'بداية اليوم المدرسي (الحصة 1):',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            InkWell(
                              onTap: () async {
                                final p = await _pickCustomTime(
                                  genCtx,
                                  startTime,
                                );
                                if (p != null) {
                                  setGenState(() => startTime = p);
                                }
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF00F2FE,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF00F2FE),
                                  ),
                                ),
                                child: Text(
                                  startTime,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: Color(0xFF00F2FE),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // 2. مدة الحصة
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'مدة الحصة الدراسية بالدقائق:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [35, 40, 45, 50, 60].map((dur) {
                                final isSel = periodDuration == dur;
                                return ChoiceChip(
                                  label: Text('$dur دقيقة'),
                                  selected: isSel,
                                  onSelected: (val) {
                                    if (val) {
                                      setGenState(() => periodDuration = dur);
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // 3. مكان ومدة الفسحة
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'مكان الفسحة المدرسية:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [2, 3, 4, 5].map((pNum) {
                                final isSel = recessAfter == pNum;
                                return ChoiceChip(
                                  label: Text(
                                    'بعد الحصة ${_convertToArabicWords(pNum)}',
                                  ),
                                  selected: isSel,
                                  onSelected: (val) {
                                    if (val) {
                                      setGenState(() => recessAfter = pNum);
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'مدة الفسحة المدرسية بالدقائق:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [15, 20, 25, 30, 40, 45].map((rDur) {
                                final isSel = recessDuration == rDur;
                                return ChoiceChip(
                                  label: Text('$rDur دقيقة'),
                                  selected: isSel,
                                  onSelected: (val) {
                                    if (val) {
                                      setGenState(() => recessDuration = rDur);
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // 4. خيارات التطبيق
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF6366F1,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                'تحديث حصص يوم $_settingsSelectedDay المسجلة فوراً',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              value: updateExistingDay,
                              onChanged: (val) => setGenState(() {
                                updateExistingDay = val ?? true;
                                if (!updateExistingDay) updateAllWeek = false;
                              }),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text(
                                'تحديث كافة حصص الأسبوع بالكامل (الأحد - الخميس)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              value: updateAllWeek,
                              onChanged: (val) => setGenState(() {
                                updateAllWeek = val ?? false;
                                if (updateAllWeek) updateExistingDay = true;
                              }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Preview List
                      const Text(
                        'معاينة التسلسل الذكي الناتج:',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0B132B)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            ...previewTimings.entries.map((e) {
                              final pNum = e.key;
                              final times = e.value;
                              final isAfterRecess = pNum == recessAfter;
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 3,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'الحصة ${_convertToArabicWords(pNum)}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '${times.start} - ${times.end}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF00F2FE),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isAfterRecess)
                                    Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFF59E0B,
                                        ).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            '☕ الفسحة المدرسية',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFF59E0B),
                                            ),
                                          ),
                                          Text(
                                            '$previewRecessStart - $previewRecessEnd',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFF59E0B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00F2FE),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.flash_on_rounded, size: 20),
                  label: const Text(
                    'تطبيق التسلسل الذكي فوراً ⚡',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                  onPressed: () async {
                    HapticFeedback.heavyImpact();
                    setState(() {
                      for (final e in previewTimings.entries) {
                        _periodTimings[e.key] = e.value;
                      }
                      _recessStartTime = previewRecessStart;
                      _recessEndTime = previewRecessEnd;
                      _recessAfterPeriod = recessAfter;
                    });
                    await _savePeriodTimingsConfig();

                    int updatedCount = 0;
                    if (updateExistingDay) {
                      final targetPeriods = updateAllWeek
                          ? _schoolPeriods
                          : _schoolPeriods
                              .where((p) => p.dayOfWeek == _settingsSelectedDay)
                              .toList();

                      for (final p in targetPeriods) {
                        final newTimes = previewTimings[p.periodNumber];
                        if (newTimes != null) {
                          final updated = p.copyWith(
                            startTime: newTimes.start,
                            endTime: newTimes.end,
                          );
                          await widget.database.saveSchoolPeriod(updated);
                          updatedCount++;
                        }
                      }
                    }

                    await _loadData();
                    setSheetState(() {});
                    if (!mounted || !genCtx.mounted) return;
                    Navigator.pop(genCtx);
                    final msg = updatedCount > 0
                        ? 'تم تطبيق التسلسل وتحديث مواعيد $updatedCount حصة بنجاح! ⚡'
                        : 'تم تطبيق تسلسل التوقيتات بنجاح! ⚡';
                    if (_activeSettingsFeedbackCallback != null) {
                      _activeSettingsFeedbackCallback!(msg);
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          backgroundColor: const Color(0xFF10B981),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // =========================================================================
  // --- UNIFIED TIMETABLE SETTINGS MODAL (7 TABS IN ONE CENTRAL HUB) ---
  // =========================================================================
  void _showUnifiedTimetableSettings({int initialTab = 0}) {
    var selectedTab = initialTab.clamp(0, 6);
    final pageController = PageController(initialPage: selectedTab);
    const tabTitles = [
      'الحصص والتوقيتات ⏰',
      'تعديل وتحديث الجدول (الذكاء الاصطناعي) ✨🤖',
      'الطابور والإشراف والبريك ☀️',
      'المواد والفصول الدراسية 📚',
      'ألوان وثيم الجدول 🎨',
      'جرس الحصة والمنبه الذكي 🔔⏰',
      'الصلاحيات والنظام والأذونات 🛡️',
    ];

    String? sheetSuccessMessage;
    Timer? sheetSuccessTimer;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          void showInSheetFeedback(String msg) {
            HapticFeedback.mediumImpact();
            sheetSuccessTimer?.cancel();
            setSheetState(() {
              sheetSuccessMessage = msg;
            });
            sheetSuccessTimer = Timer(const Duration(seconds: 4), () {
              if (sheetCtx.mounted) {
                setSheetState(() {
                  sheetSuccessMessage = null;
                });
              }
            });
          }

          _activeSettingsFeedbackCallback = showInSheetFeedback;
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Container(
            height: MediaQuery.of(sheetCtx).size.height * 0.96,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                // Header title & close button (الوحيد في أعلى النافذة)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF00F2FE),
                              Color(0xFF2563EB),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.tune_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إعدادات جدول الحصص الشاملة',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              tabTitles[selectedTab],
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: selectedTab == 1
                                    ? const Color(0xFF818CF8)
                                    : const Color(0xFF00F2FE),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Swipable PageView (Fluid Transitions & Natural Gestures)
                Expanded(
                  child: PageView(
                    controller: pageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (index) {
                      HapticFeedback.selectionClick();
                      setSheetState(() => selectedTab = index);
                    },
                    children: [
                      // Tab 0: الحصص والتوقيتات
                      _buildSettingsTimingsTab(
                        sheetCtx,
                        isDark,
                        setSheetState,
                        onNavigateToAiTab: () {
                          pageController.animateToPage(
                            1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.fastEaseInToSlowEaseOut,
                          );
                        },
                      ),

                      // Tab 1: تعديل وتحديث الجدول المدرسي بالذكاء الاصطناعي 🤖✨
                      _SettingsAiTimetableTabWidget(
                        database: widget.database,
                        periodTimings: _periodTimings,
                        schoolWeekdays: _schoolWeekdays,
                        initialDay: _settingsSelectedDay,
                        onTimetableUpdated: () async {
                          await _loadData();
                        },
                        onNotify: showInSheetFeedback,
                      ),

                      // Tab 2: الطابور والبريك
                      _buildSettingsSupervisionTab(
                        sheetCtx,
                        isDark,
                        setSheetState,
                      ),

                      // Tab 3: المواد والفصول
                      _buildSettingsSubjectsClassesTab(
                        sheetCtx,
                        isDark,
                        setSheetState,
                      ),

                      // Tab 4: ألوان وثيم الجدول
                      _buildSettingsColorsThemeTab(
                        sheetCtx,
                        isDark,
                        setSheetState,
                      ),

                      // Tab 5: المنبه الذكي والتنبيهات
                      _buildSettingsAlarmsTab(
                        sheetCtx,
                        isDark,
                        setSheetState,
                      ),

                      // Tab 6: الصلاحيات والنظام والأذونات
                      _buildSettingsPermissionsTab(
                        sheetCtx,
                        isDark,
                        setSheetState,
                      ),
                    ],
                  ),
                ),

                // In-Sheet Live Feedback Banner (يظهر مباشرة على النافذة الحالية بدون الخروج للشاشة السابقة)
                if (sheetSuccessMessage != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF059669), Color(0xFF10B981)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981)
                              .withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sheetSuccessMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            sheetSuccessTimer?.cancel();
                            setSheetState(() => sheetSuccessMessage = null);
                          },
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),

                SafeArea(
                  top: false,
                  child: _buildTimetableSettingsDock(
                    isDark: isDark,
                    selectedIndex: selectedTab,
                    onSelected: (index) {
                      if (selectedTab == index) return;
                      HapticFeedback.selectionClick();
                      setSheetState(() => selectedTab = index);
                      pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.fastEaseInToSlowEaseOut,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      sheetSuccessTimer?.cancel();
      _activeSettingsFeedbackCallback = null;
    });
  }

  Widget _buildTimetableSettingsDock({
    required bool isDark,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
    const colors = [
      Color(0xFF00F2FE),
      Color(0xFF818CF8),
      Color(0xFF38BDF8),
      Color(0xFFA78BFA),
      Color(0xFFEC4899),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
    ];
    final activeColor = colors[selectedIndex.clamp(0, colors.length - 1)];
    const tabs = [
      (label: 'التوقيت', icon: Icons.access_time_rounded),
      (label: 'تعديل الجدول', icon: Icons.auto_awesome_rounded),
      (label: 'الطابور', icon: Icons.wb_sunny_rounded),
      (label: 'المواد', icon: Icons.menu_book_rounded),
      (label: 'الألوان', icon: Icons.palette_rounded),
      (label: 'المنبه', icon: Icons.alarm_rounded),
      (label: 'النظام', icon: Icons.shield_rounded),
    ];
    final totalTabs = tabs.length;
    final targetX = 1.0 - (selectedIndex * (2.0 / (totalTabs - 1)));

    return Container(
      height: 54,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xF2091222) : Colors.white,
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: isDark ? const Color(0x3338BDF8) : const Color(0xFFCBD5E1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          if (isDark)
            BoxShadow(
              color: activeColor.withValues(alpha: 0.14),
              blurRadius: 12,
              offset: const Offset(0, -1),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: Stack(
          children: [
            AnimatedAlign(
              alignment: Alignment(targetX, 0.9),
              duration: const Duration(milliseconds: 200),
              curve: Curves.fastEaseInToSlowEaseOut,
              child: Container(
                width: 28,
                height: 2.8,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: activeColor,
                      blurRadius: 6,
                      spreadRadius: 0.6,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedAlign(
              alignment: Alignment(targetX, 0),
              duration: const Duration(milliseconds: 200),
              curve: Curves.fastEaseInToSlowEaseOut,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.22),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: List.generate(tabs.length, (index) {
                final isSelected = selectedIndex == index;
                final color = isSelected
                    ? colors[index]
                    : (isDark
                          ? const Color(0xFF8E9BAE)
                          : const Color(0xFF64748B));
                return Expanded(
                  child: InkWell(
                    onTap: () => onSelected(index),
                    borderRadius: BorderRadius.circular(27),
                    splashColor: colors[index].withValues(alpha: 0.2),
                    highlightColor: Colors.transparent,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(tabs[index].icon, size: 15, color: color),
                          const SizedBox(height: 1),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Text(
                                tabs[index].label,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 8.8,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // --- Tab 0: الحصص والتوقيتات ---
  Widget _buildSettingsTimingsTab(
    BuildContext ctx,
    bool isDark,
    StateSetter setSheetState, {
    VoidCallback? onNavigateToAiTab,
  }) {
    final periodsOnDay = _schoolPeriods
        .where((p) => p.dayOfWeek == _settingsSelectedDay)
        .toList()
      ..sort((a, b) => a.periodNumber.compareTo(b.periodNumber));
    final basicCount = periodsOnDay.where((p) => !p.isReserve).length;
    final reserveCount = periodsOnDay.where((p) => p.isReserve).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // === SECTION 0: تعديل الجدول المدرسي (بالذكاء الاصطناعي والصور) ===
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      const Color(0xFF1E1B4B),
                      const Color(0xFF0F172A),
                    ]
                  : [
                      const Color(0xFFEEF2FF),
                      const Color(0xFFE0E7FF),
                    ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF6366F1).withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'تعديل الجدول المدرسي',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1E1B4B),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1)
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'جديد 🤖📸',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF818CF8),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'صوّر الجدول الورقي وأرسله لـ Gemini ليتم إدخاله وتعديله بضغطة زر واحدة!',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.flash_on_rounded, size: 16),
                label: const Text(
                  'فتح قسم تعديل وتحديث الجدول الذكي ⚡',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () {
                  if (onNavigateToAiTab != null) {
                    onNavigateToAiTab();
                  } else {
                    _showAiTimetableImportSheet(
                      initialDay: _settingsSelectedDay,
                    );
                  }
                },
              ),
            ],
          ),
        ),

        // 1. SECTION: إدارة الحصص المدرسية + المولد الذكي
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.edit_calendar_rounded,
                  color: Color(0xFF00F2FE),
                  size: 18,
                ),
                SizedBox(width: 6),
                Text(
                  'إدارة الحصص وتوقيتات اليوم:',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Action Buttons Row (Smart Generator + Add Period + Excel)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Smart Timings Generator Button
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00F2FE),
                    foregroundColor: const Color(0xFF0B1120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.flash_on_rounded, size: 16),
                  label: const Text(
                    'مولد التوقيت الذكي ⚡',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                  onPressed: () =>
                      _showAutoPeriodTimingsGenerator(ctx, setSheetState),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'استيراد أو تصدير Excel',
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.table_view_rounded,
                        color: Color(0xFF2DD4BF),
                        size: 20,
                      ),
                      onSelected: (action) {
                        if (action == 'export') {
                          unawaited(_exportSchoolTimetable());
                        } else if (action == 'import') {
                          unawaited(_importSchoolTimetable());
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'export',
                          child: Row(
                            children: [
                              Icon(Icons.file_upload_outlined),
                              SizedBox(width: 10),
                              Text('تصدير إلى Excel'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'import',
                          child: Row(
                            children: [
                              Icon(Icons.file_download_outlined),
                              SizedBox(width: 10),
                              Text('استيراد من Excel'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00F2FE),
                        side: const BorderSide(color: Color(0xFF00F2FE)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text(
                        'إضافة حصة ＋',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () {
                        _showAddEditPeriodModal(
                          initialDay: _settingsSelectedDay,
                          onSavedCallback: () {
                            setSheetState(() {});
                          },
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Days Filter Slider for editing periods
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _schoolWeekdays.map((day) {
              final isSel = _settingsSelectedDay == day;
              final dayPeriodsCount = _schoolPeriods
                  .where((p) => p.dayOfWeek == day)
                  .length;
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _settingsSelectedDay = day);
                    setSheetState(() {});
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSel
                          ? const Color(0xFF00F2FE)
                          : (isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSel
                            ? const Color(0xFF00F2FE)
                            : (isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFCBD5E1)),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          day,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: isSel
                                ? Colors.black
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                        if (dayPeriodsCount > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? Colors.black.withValues(alpha: 0.15)
                                  : const Color(
                                      0xFF00F2FE,
                                    ).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$dayPeriodsCount',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: isSel
                                    ? Colors.black
                                    : const Color(0xFF00F2FE),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),

        // Selected Day Summary Strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 14,
                color: isDark ? Colors.white70 : const Color(0xFF2563EB),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'يوم $_settingsSelectedDay: إجمالي ${periodsOnDay.length} حصص • $basicCount أساسي • $reserveCount احتياط',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // List of periods on selected day for editing
        if (periodsOnDay.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 14,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF223147)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'لا توجد حصص مسجلة في يوم $_settingsSelectedDay. اضغط "إضافة حصة ＋" أو استخدم "مولد التوقيت الذكي ⚡".',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: periodsOnDay.map((p) {
              final sColor = _getSubjectColor(p.subject);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141E33) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: sColor.withValues(alpha: 0.35)),
                  boxShadow: [
                    BoxShadow(
                      color: sColor.withValues(alpha: isDark ? 0.08 : 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: sColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: sColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '${p.periodNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: sColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.isReserve
                                      ? 'حصة احتياط'
                                      : (p.subject.isNotEmpty
                                            ? p.subject
                                            : 'حصة دراسية'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              if (p.className.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    p.className,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Inline quick time editor
                              InkWell(
                                onTap: () => _quickEditPeriodTimes(
                                  ctx,
                                  p,
                                  setSheetState,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.amber.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.access_time_rounded,
                                        size: 11,
                                        color: Colors.amber,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${p.startTime} - ${p.endTime}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // Inline Reserve Toggle
                              InkWell(
                                onTap: () async {
                                  HapticFeedback.selectionClick();
                                  final updated = p.copyWith(
                                    isReserve: !p.isReserve,
                                  );
                                  await widget.database.saveSchoolPeriod(
                                    updated,
                                  );
                                  await _loadData();
                                  setSheetState(() {});
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (p.isReserve
                                                ? const Color(0xFFEF4444)
                                                : const Color(0xFF10B981))
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color:
                                          (p.isReserve
                                                  ? const Color(0xFFEF4444)
                                                  : const Color(0xFF10B981))
                                              .withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    p.isReserve ? 'احتياط 🔴' : 'أساسي 🟢',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: p.isReserve
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                              ),
                              if (p.room.isNotEmpty)
                                Text(
                                  '• ${p.room}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Copy to another day
                    IconButton(
                      icon: const Icon(
                        Icons.copy_all_rounded,
                        size: 18,
                        color: Color(0xFF818CF8),
                      ),
                      tooltip: 'نسخ إلى يوم آخر 📋',
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: () => _duplicatePeriodToOtherDay(
                        ctx,
                        p,
                        setSheetState,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Edit Button
                    IconButton(
                      icon: const Icon(
                        Icons.edit_note_rounded,
                        size: 20,
                        color: Color(0xFF00F2FE),
                      ),
                      tooltip: 'تعديل بيانات الحصة',
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        _showAddEditPeriodModal(
                          existing: p,
                          onSavedCallback: () {
                            setSheetState(() {});
                          },
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    // Delete Button
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                      tooltip: 'حذف الحصة',
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: () => _confirmDeletePeriodInSettings(
                        ctx,
                        p,
                        setSheetState,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 10),
        // 2. SECTION: إعداد توقيتات الحصص والفسحة
        const Row(
          children: [
            Icon(Icons.access_time_rounded, color: Color(0xFFF59E0B), size: 18),
            SizedBox(width: 6),
            Text(
              'توقيتات الحصص اليومية ومكان الفسحة:',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Recess Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.coffee_rounded,
                    color: Color(0xFFF59E0B),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'مكان الفسحة المدرسية (البريك)',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'تظهر الفسحة في الجدول بعد الحصة:',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [1, 2, 3, 4, 5].map((periodNum) {
                    final isSelected = _recessAfterPeriod == periodNum;
                    return Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: InkWell(
                        onTap: () async {
                          setState(() => _recessAfterPeriod = periodNum);
                          setSheetState(() {});
                          await _savePeriodTimingsConfig();
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFF59E0B)
                                : (isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFFF59E0B)
                                  : Colors.grey.shade700,
                            ),
                          ),
                          child: Text(
                            'بعد ${_convertToArabicWords(periodNum)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                              color: isSelected
                                  ? Colors.black87
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'توقيت الفسحة:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  _buildTimePill(
                    _recessStartTime,
                    const Color(0xFFF59E0B),
                    () async {
                      final p = await _pickCustomTime(ctx, _recessStartTime);
                      if (p != null) {
                        setState(() => _recessStartTime = p);
                        setSheetState(() {});
                        await _savePeriodTimingsConfig();
                      }
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('—', style: TextStyle(color: Colors.grey)),
                  ),
                  _buildTimePill(
                    _recessEndTime,
                    const Color(0xFFF59E0B),
                    () async {
                      final p = await _pickCustomTime(ctx, _recessEndTime);
                      if (p != null) {
                        setState(() => _recessEndTime = p);
                        setSheetState(() {});
                        await _savePeriodTimingsConfig();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 8 Periods list
        const Text(
          'توقيتات الحصص الثمانية (اضغط لتعديل البداية أو النهاية):',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        ...List.generate(8, (index) {
          final num = index + 1;
          final color = (num <= _recessAfterPeriod)
              ? const Color(0xFF00F2FE)
              : const Color(0xFF6366F1);
          return _buildTimingRow(
            title: 'الحصة ${_convertToArabicWords(num)}',
            start: _periodTimings[num]!.start,
            end: _periodTimings[num]!.end,
            isDark: isDark,
            color: color,
            onPickStart: () async {
              final p = await _pickCustomTime(ctx, _periodTimings[num]!.start);
              if (p != null) {
                setState(
                  () => _periodTimings[num] = (
                    start: p,
                    end: _periodTimings[num]!.end,
                  ),
                );
                setSheetState(() {});
                await _savePeriodTimingsConfig();
              }
            },
            onPickEnd: () async {
              final p = await _pickCustomTime(ctx, _periodTimings[num]!.end);
              if (p != null) {
                setState(
                  () => _periodTimings[num] = (
                    start: _periodTimings[num]!.start,
                    end: p,
                  ),
                );
                setSheetState(() {});
                await _savePeriodTimingsConfig();
              }
            },
          );
        }),
        const SizedBox(height: 14),
        Center(
          child: TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showConfigureTimingsDialog();
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text(
              'فتح نافذة ضبط التوقيتات التفصيلية الكاملة',
              style: TextStyle(fontSize: 11.5),
            ),
          ),
        ),
        // Dedicated Save Button for Tab 0
        _buildSettingsTabSaveButton(
          label: 'حفظ إعدادات التوقيتات والحصص ✓',
          successMessage: 'تم حفظ إعدادات التوقيتات والحصص بنجاح! ✓',
          onSave: () async {
            await _savePeriodTimingsConfig();
          },
        ),
      ],
    );
  }

  // --- Tab 1: إشراف الطابور والبريك ---
  Widget _buildSettingsSupervisionTab(
    BuildContext ctx,
    bool isDark,
    StateSetter setSheetState,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Morning Assembly
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF818CF8).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF818CF8).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.wb_sunny_rounded,
                    color: Color(0xFF818CF8),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'إشراف طابور الصباح الأسبوعي ☀️',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: Color(0xFF818CF8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'اختر يوم تكليفك بإشراف الطابور:',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ..._schoolWeekdays.map((day) {
                      final isSelected = _morningAssemblyDutyDay == day;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: InkWell(
                          onTap: () async {
                            setState(() => _morningAssemblyDutyDay = day);
                            setSheetState(() {});
                            await _savePeriodTimingsConfig();
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF818CF8)
                                  : (isDark
                                        ? const Color(0xFF1E293B)
                                        : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF818CF8)
                                    : Colors.grey.shade700,
                              ),
                            ),
                            child: Text(
                              day,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: isSelected
                                    ? Colors.black
                                    : (isDark
                                          ? Colors.white70
                                          : Colors.black87),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: InkWell(
                        onTap: () async {
                          setState(() => _morningAssemblyDutyDay = '');
                          setSheetState(() {});
                          await _savePeriodTimingsConfig();
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _morningAssemblyDutyDay.isEmpty
                                ? Colors.grey.shade700
                                : (isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade700),
                          ),
                          child: const Text(
                            'بدون إشراف',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_morningAssemblyDutyDay.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'توقيت الطابور:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    _buildTimePill(
                      _morningAssemblyStartTime,
                      const Color(0xFF818CF8),
                      () async {
                        final p = await _pickCustomTime(
                          ctx,
                          _morningAssemblyStartTime,
                        );
                        if (p != null) {
                          setState(() => _morningAssemblyStartTime = p);
                          setSheetState(() {});
                          await _savePeriodTimingsConfig();
                        }
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('—', style: TextStyle(color: Colors.grey)),
                    ),
                    _buildTimePill(
                      _morningAssemblyEndTime,
                      const Color(0xFF818CF8),
                      () async {
                        final p = await _pickCustomTime(
                          ctx,
                          _morningAssemblyEndTime,
                        );
                        if (p != null) {
                          setState(() => _morningAssemblyEndTime = p);
                          setSheetState(() {});
                          await _savePeriodTimingsConfig();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: _morningAssemblyLocation,
                  decoration: InputDecoration(
                    labelText:
                        'مكان إشراف الطابور (مثال: فناء المدرسة / البوابة)',
                    labelStyle: const TextStyle(fontSize: 12),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF141E33)
                        : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (val) async {
                    _morningAssemblyLocation = val.trim();
                    await _savePeriodTimingsConfig();
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Break Supervision
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: Color(0xFFF59E0B),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'إشراف الفسحة (البريك) الأسبوعي ☕',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'اختر يوم تكليفك بإشراف الفسحة:',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ..._schoolWeekdays.map((day) {
                      final isSelected = _breakDutyDay == day;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: InkWell(
                          onTap: () async {
                            setState(() => _breakDutyDay = day);
                            setSheetState(() {});
                            await _savePeriodTimingsConfig();
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFF59E0B)
                                  : (isDark
                                        ? const Color(0xFF1E293B)
                                        : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFF59E0B)
                                    : Colors.grey.shade700,
                              ),
                            ),
                            child: Text(
                              day,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: isSelected
                                    ? Colors.black
                                    : (isDark
                                          ? Colors.white70
                                          : Colors.black87),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: InkWell(
                        onTap: () async {
                          setState(() => _breakDutyDay = '');
                          setSheetState(() {});
                          await _savePeriodTimingsConfig();
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _breakDutyDay.isEmpty
                                ? Colors.grey.shade700
                                : (isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade700),
                          ),
                          child: const Text(
                            'بدون إشراف',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_breakDutyDay.isNotEmpty) ...[
                const SizedBox(height: 10),
                TextFormField(
                  initialValue: _breakDutyLocation,
                  decoration: InputDecoration(
                    labelText:
                        'مكان إشراف الفسحة (مثال: فناء المدرسة / الأدوار)',
                    labelStyle: const TextStyle(fontSize: 12),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF141E33)
                        : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (val) async {
                    _breakDutyLocation = val.trim();
                    await _savePeriodTimingsConfig();
                  },
                ),
              ],
            ],
          ),
        ),
        // Dedicated Save Button for Tab 1
        _buildSettingsTabSaveButton(
          label: 'حفظ إعدادات الطابور والإشراف والبريك ✓',
          successMessage: 'تم حفظ إعدادات الطابور والإشراف بنجاح! ✓',
          onSave: () async {
            await _savePeriodTimingsConfig();
          },
        ),
      ],
    );
  }

  // --- Tab 2: إدارة المواد والفصول ---
  Widget _buildSettingsSubjectsClassesTab(
    BuildContext ctx,
    bool isDark,
    StateSetter setSheetState,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Subjects Section Header
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  color: Color(0xFFA78BFA),
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  'المواد الدراسية المسجلة',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ],
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00F2FE),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text(
                'إضافة مادة ＋',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              onPressed: () => _showAddSubjectDialog(setSheetState),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_schoolSubjects.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'لم تقم بتسجيل أي مواد بعد. اضغط "إضافة مادة ＋" لإضافة مادتك.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _schoolSubjects.map((s) {
              final sName = s['name']?.toString() ?? '';
              final sId = s['id']?.toString() ?? '';
              final sColor = _getSubjectColor(sName);

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: sColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: sColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        sName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () async {
                        await widget.database.deleteSchoolSubject(sId);
                        final updated = await widget.database
                            .getSchoolSubjects();
                        setState(() => _schoolSubjects = updated);
                        setSheetState(() {});
                      },
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 10),

        // Classes Section Header
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            const Row(
              children: [
                Icon(Icons.class_outlined, color: Color(0xFF38BDF8), size: 18),
                SizedBox(width: 8),
                Text(
                  'فصول المدرسة المسجلة',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ],
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00F2FE),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text(
                'إضافة فصل ＋',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                _showAddOrEditClassDialog(
                  parentSetState: () {
                    setState(() {});
                    setSheetState(() {});
                  },
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_schoolClasses.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'لم تقم بتسجيل أي فصول بعد. اضغط "إضافة فصل ＋" لإضافة فصولك.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _schoolClasses.map((c) {
              final cName = c['class_name']?.toString() ?? '';
              final cSubj = c['subject']?.toString() ?? '';
              final cId = c['id']?.toString() ?? '';

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.school_outlined,
                      size: 14,
                      color: Color(0xFF38BDF8),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'فصل $cName ${cSubj.isNotEmpty ? "($cSubj)" : ""}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        _showAddOrEditClassDialog(
                          existingClass: c,
                          parentSetState: () {
                            setState(() {});
                            setSheetState(() {});
                          },
                        );
                      },
                      child: const Icon(
                        Icons.edit_note_rounded,
                        size: 15,
                        color: Color(0xFF00F2FE),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () async {
                        await widget.database.deleteSchoolClass(cId);
                        final updated = await widget.database
                            .getSchoolClasses();
                        setState(() => _schoolClasses = updated);
                        setSheetState(() {});
                      },
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        // Dedicated Save Button for Tab 2
        _buildSettingsTabSaveButton(
          label: 'حفظ إعدادات المواد والفصول ✓',
          successMessage: 'تم حفظ بيانات المواد الدراسية والفصول بنجاح! ✓',
          onSave: () async {},
        ),
      ],
    );
  }

  // --- Tab 3: ألوان وثيم الجدول ---
  Widget _buildSettingsColorsThemeTab(
    BuildContext ctx,
    bool isDark,
    StateSetter setSheetState,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 🎮 Live Interactive Period Card Preview Playground
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                  : [const Color(0xFFF1F5F9), Colors.white],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  (_designTheme == 'cyber'
                          ? const Color(0xFF00F2FE)
                          : const Color(0xFF2563EB))
                      .withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    (_designTheme == 'cyber'
                            ? const Color(0xFF00F2FE)
                            : const Color(0xFF2563EB))
                        .withValues(alpha: isDark ? 0.2 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(
                        Icons.gamepad_rounded,
                        size: 18,
                        color: Color(0xFF00F2FE),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'معاينة كارت الحصة التفاعلي المباشر 🎮✨',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        'جارية الآن 🟢',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Simulated Live Period Card
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: _designTheme == 'cyber'
                      ? const LinearGradient(
                          colors: [Color(0xFF0D1B2A), Color(0xFF1B263B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: _designTheme == 'cyber'
                      ? null
                      : (isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF8FAFC)),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        (_designTheme == 'cyber'
                                ? const Color(0xFF00F2FE)
                                : const Color(0xFF2563EB))
                            .withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00F2FE), Color(0xFF2563EB)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          '3',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Text(
                                'لغة عربية',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text(
                                '• 1/1 ث',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00F2FE),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '09:40 ص - 10:25 ص • قاعة 2',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'تحضير 📝',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00F2FE),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Theme Selection Card
        const Text(
          'ستايل وشكل الجدول الرئيسي:',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  HapticFeedback.selectionClick();
                  setState(() => _designTheme = 'cyber');
                  setSheetState(() {});
                  await widget.database.setSetting(
                    'timetable_design_theme',
                    'cyber',
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _designTheme == 'cyber'
                        ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
                        : (isDark
                              ? const Color(0xFF141E33)
                              : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _designTheme == 'cyber'
                          ? const Color(0xFF00F2FE)
                          : Colors.grey.shade700,
                      width: _designTheme == 'cyber' ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFF00F2FE),
                        size: 26,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'نيون عصري Bento',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      if (_designTheme == 'cyber') ...[
                        const SizedBox(height: 4),
                        const Text(
                          '✓ الستايل المختار',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF00F2FE),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () async {
                  HapticFeedback.selectionClick();
                  setState(() => _designTheme = 'classic');
                  setSheetState(() {});
                  await widget.database.setSetting(
                    'timetable_design_theme',
                    'classic',
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _designTheme == 'classic'
                        ? const Color(0xFF2563EB).withValues(alpha: 0.15)
                        : (isDark
                              ? const Color(0xFF141E33)
                              : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _designTheme == 'classic'
                          ? const Color(0xFF2563EB)
                          : Colors.grey.shade700,
                      width: _designTheme == 'classic' ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.grid_on_rounded,
                        color: Color(0xFF2563EB),
                        size: 26,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'جدول شبكي كامل',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      if (_designTheme == 'classic') ...[
                        const SizedBox(height: 4),
                        const Text(
                          '✓ الستايل المختار',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 10),

        // Subject Colors Palette Customizer
        const Row(
          children: [
            Icon(Icons.palette_outlined, color: Color(0xFF00F2FE), size: 20),
            SizedBox(width: 8),
            Text(
              'تخصيص ألوان المواد الدراسية:',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'اختر لوناً مميزاً لكل مادة ليظهر فوراً في جدول الحصص اليومي والشبكي:',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 12),

        if (_schoolSubjects.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'قم بإضافة المواد أولاً في تبويب "المواد والفصول" لتتمكن من تخصيص ألوانها.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _schoolSubjects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, index) {
              final subj = _schoolSubjects[index];
              final sName = subj['name']?.toString() ?? '';
              final currentColor = _getSubjectColor(sName);

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF141E33)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: currentColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: currentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: currentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: currentColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            'معاينة اللون',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: currentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: _paletteColors.map((colorVal) {
                          final col = Color(colorVal);
                          final isSel =
                              currentColor.toARGB32() == col.toARGB32();

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: InkWell(
                              onTap: () async {
                                HapticFeedback.selectionClick();
                                setState(
                                  () => _subjectColors[sName] = colorVal,
                                );
                                setSheetState(() {});
                                await widget.database.setSetting(
                                  'school_subject_colors_map',
                                  jsonEncode(_subjectColors),
                                );
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: isSel ? 32 : 26,
                                height: isSel ? 32 : 26,
                                decoration: BoxDecoration(
                                  color: col,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSel
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: isSel ? 2.5 : 0,
                                  ),
                                  boxShadow: isSel
                                      ? [
                                          BoxShadow(
                                            color: col.withValues(alpha: 0.7),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: isSel
                                    ? const Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        // Dedicated Save Button for Tab 3
        _buildSettingsTabSaveButton(
          label: 'حفظ إعدادات ألوان وثيم الجدول ✓',
          successMessage: 'تم حفظ ألوان وثيم الجدول بنجاح! ✓',
          onSave: () async {
            await widget.database.setSetting(
              'school_subject_colors_map',
              jsonEncode(_subjectColors),
            );
          },
        ),
      ],
    );
  }

  Future<void> _saveAlarmSettings(BuildContext sheetContext) async {
    HapticFeedback.heavyImpact();
    try {
      await widget.database.setSetting(
        'school_auto_next_day_alarms',
        _autoNextDayAlarm ? 'true' : 'false',
      );
      await widget.database.setSetting(
        'school_auto_alarm_minutes_before',
        '$_autoAlarmMinutesBefore',
      );
      await widget.database.setSetting(
        'school_auto_period_alerts',
        _autoPeriodAlerts ? 'true' : 'false',
      );
      await widget.database.setSetting(
        'school_alarm_selected_days',
        jsonEncode(_alertActiveDays.toList()),
      );
      await widget.database.setSetting(
        'school_auto_delete_expired_alarms',
        _autoDeleteExpiredAlarms ? 'true' : 'false',
      );

      if (_autoDeleteExpiredAlarms) {
        final now = DateTime.now();
        final todayArabic = _getTodayName(now.weekday);
        unawaited(AlarmService.cleanExpiredAlarms(
          todayPeriods: _schoolPeriods,
          todayGroups: _centerGroups,
          todayArabic: todayArabic,
        ));
      }

      if (!mounted || !sheetContext.mounted) return;
      await showDialog<void>(
        context: sheetContext,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تم الحفظ'),
          content: const Text('تم حفظ إعدادات الإشعارات والمنبهات بنجاح.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted || !sheetContext.mounted) return;
      await showDialog<void>(
        context: sheetContext,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تعذر الحفظ'),
          content: const Text(
            'لم يتم حفظ إعدادات الإشعارات والمنبهات. حاول مرة أخرى.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    }
  }

  // --- Tab 4: جرس الحصة والمنبه الذكي والتنبيهات ---
  Widget _buildSettingsAlarmsTab(
    BuildContext ctx,
    bool isDark,
    StateSetter setSheetState,
  ) {
    final tones = [
      {
        'id': 'school_bell',
        'title': 'جرس الحصة المدرسي 🔔',
        'desc': 'رنين كلاسيكي مزدوج حقيقي وعالي الصوت',
        'icon': Icons.notifications_active_rounded,
        'color': const Color(0xFFFBBF24),
      },
      {
        'id': 'alarm_climb',
        'title': 'رنين متصاعد قوي ⏰',
        'desc': 'صوت منبه إلكتروني متكرر وواضح جداً',
        'icon': Icons.alarm_rounded,
        'color': const Color(0xFF00F2FE),
      },
      {
        'id': 'digital_beep',
        'title': 'نغمة رقمية نشطة 🎶',
        'desc': 'نغمات بييب تصاعدية مرحة وسريعة',
        'icon': Icons.graphic_eq_rounded,
        'color': const Color(0xFF10B981),
      },
      {
        'id': 'gentle_melody',
        'title': 'نغمة هادئة لطيفة 🎵',
        'desc': 'رنين هادئ دافئ غير مزعج داخل الفصل',
        'icon': Icons.music_note_rounded,
        'color': const Color(0xFFA855F7),
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 🔔 Master Interactive School Bell Studio Card (جرس الحصة المدرسي التفاعلي)
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF2E1C05), const Color(0xFF181005)]
                  : [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.45 : 0.65),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.22 : 0.12),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'جرس الحصة المدرسي التفاعلي 🔔',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'رنين حقيقي للحصص والفسحة مع إمكانية التجربة والاستماع فورياً',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Action Buttons Row: [دق الجرس الآن / إيقاف] + [تخصيص كامل ⚙️]
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentlyRingingTone != null
                            ? const Color(0xFFDC2626)
                            : const Color(0xFFF59E0B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      onPressed: () async {
                        HapticFeedback.heavyImpact();
                        if (_currentlyRingingTone != null) {
                          await AlarmService.stopAudio();
                          setState(() => _currentlyRingingTone = null);
                          setSheetState(() {});
                        } else {
                          setState(() => _currentlyRingingTone = _currentAlarmTone);
                          setSheetState(() {});
                          await AlarmService.playAudio(
                            toneId: _currentAlarmTone,
                            durationMs: 8000,
                          );
                          Future.delayed(const Duration(milliseconds: 8200), () {
                            if (mounted) {
                              setState(() => _currentlyRingingTone = null);
                              setSheetState(() {});
                            }
                          });
                        }
                      },
                      icon: Icon(
                        _currentlyRingingTone != null
                            ? Icons.stop_circle_rounded
                            : Icons.notifications_active_rounded,
                        size: 18,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _currentlyRingingTone != null
                              ? 'إيقاف رنين الجرس الآن ⏹️'
                              : 'دق جرس الحصة الآن 🔔',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isDark
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFD97706),
                        ),
                        foregroundColor: isDark
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFFB45309),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showInteractiveSchoolBellSheet();
                      },
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'تخصيص كامل ⚙️',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Divider
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Title for tones
              Row(
                children: [
                  const Icon(
                    Icons.music_note_rounded,
                    size: 16,
                    color: Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'اختر نغمة جرس الحصة الأساسية:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'اضغط للاستماع فورياً 🔊',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Tone Preview Tiles
              ...tones.map((t) {
                final tId = t['id'] as String;
                final tTitle = t['title'] as String;
                final tDesc = t['desc'] as String;
                final tColor = t['color'] as Color;
                final isSelected = _currentAlarmTone == tId;
                final isPlaying = _currentlyRingingTone == tId;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? tColor.withValues(alpha: isDark ? 0.2 : 0.12)
                        : (isDark ? const Color(0xFF141E33) : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? tColor
                          : (isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0)),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Play / Stop Icon Button
                      IconButton(
                        icon: Icon(
                          isPlaying
                              ? Icons.stop_circle_rounded
                              : Icons.play_circle_fill_rounded,
                          color: isPlaying ? const Color(0xFFEF4444) : tColor,
                          size: 26,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: isPlaying ? 'إيقاف الصوت' : 'استماع للتجربة',
                        onPressed: () async {
                          HapticFeedback.selectionClick();
                          if (isPlaying) {
                            await AlarmService.stopAudio();
                            setState(() => _currentlyRingingTone = null);
                            setSheetState(() {});
                          } else {
                            setState(() => _currentlyRingingTone = tId);
                            setSheetState(() {});
                            await AlarmService.playAudio(
                              toneId: tId,
                              durationMs: 8000,
                            );
                            Future.delayed(const Duration(milliseconds: 8200), () {
                              if (mounted && _currentlyRingingTone == tId) {
                                setState(() => _currentlyRingingTone = null);
                                setSheetState(() {});
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tTitle,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? tColor
                                    : (isDark ? Colors.white : const Color(0xFF0F172A)),
                              ),
                            ),
                            Text(
                              tDesc,
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Select Button
                      InkWell(
                        onTap: () async {
                          HapticFeedback.selectionClick();
                          setState(() => _currentAlarmTone = tId);
                          setSheetState(() {});
                          await widget.database.setSetting('alarm_sound_tone', tId);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? tColor
                                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isSelected ? 'مفعل ✓' : 'تفعيل',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              color: isSelected
                                  ? (tColor == const Color(0xFFFBBF24) ? Colors.black : Colors.white)
                                  : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        // 🌟 Dedicated In-App Alarm Clock Screen Hero Banner
        InkWell(
          onTap: () {
            Navigator.pop(ctx);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AlarmClockScreen(database: widget.database),
              ),
            ).then((_) => _loadData());
          },
          borderRadius: BorderRadius.circular(18),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00F2FE), Color(0xFF2563EB)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.alarm_on_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'فتح شاشة منبه الأكاديمية الذكي ⏰',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'شاشة منبه مدمجة شبيهة بمنبه الهاتف تماماً لإدارة وتشغيل وإيقاف كل منبه',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
              ],
            ),
          ),
        ),

        // 0. Auto-Delete Expired Alarms Card (الحذف والإلغاء التلقائي)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Row(
                  children: [
                    Icon(
                      Icons.auto_delete_rounded,
                      color: Color(0xFF10B981),
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'الحذف والإلغاء التلقائي للمنبهات المنتهية ♻️',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'يحذف التطبيق تلقائيًا أي منبه أو تنبيه بمجرد انقضاء موعد الحصة أو انتهاء اليوم الدراسي دون الحاجة لحذفه يدويًا.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                value: _autoDeleteExpiredAlarms,
                onChanged: (val) async {
                  HapticFeedback.selectionClick();
                  setState(() => _autoDeleteExpiredAlarms = val);
                  setSheetState(() {});
                  await widget.database.setSetting(
                    'school_auto_delete_expired_alarms',
                    val ? 'true' : 'false',
                  );
                  if (val) {
                    final now = DateTime.now();
                    final todayArabic = _getTodayName(now.weekday);
                    final cleaned = await AlarmService.cleanExpiredAlarms(
                      todayPeriods: _schoolPeriods,
                      todayGroups: _centerGroups,
                      todayArabic: todayArabic,
                    );
                    if (cleaned > 0 && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'تم تنظيف وإلغاء $cleaned منبهًا وتنبيهًا منتهيًا تلقائيًا ♻️',
                          ),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: const Color(0xFF10B981),
                        ),
                      );
                    }
                  }
                },
              ),
              if (_autoDeleteExpiredAlarms) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        color: Color(0xFF10B981),
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'الحذف التلقائي نشط: يتم مسح المنبهات فور انتهاء الحصص وبداية اليوم الجديد.',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // 1. Next-day Auto Alarm Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF00F2FE).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Row(
                  children: [
                    Icon(
                      Icons.alarm_on_rounded,
                      color: Color(0xFF00F2FE),
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'منبه اليوم التالي التلقائي (الساعة 12 بالليل) ⏰',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'تتم جدولة تنبيهات حصص الغد تلقائيًا عند منتصف الليل، مع إزالة التنبيهات التلقائية السابقة.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                value: _autoNextDayAlarm,
                onChanged: (val) async {
                  HapticFeedback.selectionClick();
                  setState(() => _autoNextDayAlarm = val);
                  setSheetState(() {});
                  await widget.database.setSetting(
                    'school_auto_next_day_alarms',
                    val ? 'true' : 'false',
                  );
                  if (val) {
                    unawaited(_checkAndRunMidnightAutoAlarmSync());
                  } else {
                    await AlarmService.dismissAutoAlarms();
                    _lastAutoAlarmDate = '';
                    _nextAutoAlarmRetryAt = null;
                    await widget.database.setSetting(
                      'school_last_auto_alarm_date',
                      '',
                    );
                  }
                },
              ),
              const SizedBox(height: 8),

              // Preservation Guarantee Note
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.amber.shade400.withValues(alpha: 0.5),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.security_rounded, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'المزامنة الآلية تدير تنبيهات الجدول التلقائية فقط، ولا تمس التنبيهات اليدوية أو المنبهات التي ضبطتها خارج التطبيق.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // System Clock Integration Switch
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: const Color(0xFF00F2FE),
                title: const Row(
                  children: [
                    Icon(
                      Icons.alarm_add_rounded,
                      color: Color(0xFF00F2FE),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'إضافة المنبهات لتطبيق الساعة الرسمي للهاتف ⏰',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'عند التفعيل، يتم أيضاً ضبط منبهات في تطبيق الساعة الخاص بهاتفك لضمان رنين مستمر وشاشة كاملة حتى لو كان الهاتف في أقصى درجات توفير الطاقة.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                value: _syncToSystemClockApp,
                onChanged: (val) async {
                  HapticFeedback.selectionClick();
                  setState(() => _syncToSystemClockApp = val);
                  setSheetState(() {});
                  await widget.database.setSetting(
                    'school_sync_system_clock_app',
                    val ? 'true' : 'false',
                  );
                },
              ),
              const SizedBox(height: 12),

              // Advance warning selection
              const Text(
                'وقت رنين المنبه بالنسبة للحصة:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text(
                      'في نفس موعد الحصة',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: _autoAlarmMinutesBefore == 0,
                    onSelected: (sel) async {
                      if (sel) {
                        setState(() => _autoAlarmMinutesBefore = 0);
                        setSheetState(() {});
                        await widget.database.setSetting(
                          'school_auto_alarm_minutes_before',
                          '0',
                        );
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text(
                      'قبل بـ 5 دقائق ⚡',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: _autoAlarmMinutesBefore == 5,
                    onSelected: (sel) async {
                      if (sel) {
                        setState(() => _autoAlarmMinutesBefore = 5);
                        setSheetState(() {});
                        await widget.database.setSetting(
                          'school_auto_alarm_minutes_before',
                          '5',
                        );
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text(
                      'قبل بـ 10 دقائق',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: _autoAlarmMinutesBefore == 10,
                    onSelected: (sel) async {
                      if (sel) {
                        setState(() => _autoAlarmMinutesBefore = 10);
                        setSheetState(() {});
                        await widget.database.setSetting(
                          'school_auto_alarm_minutes_before',
                          '10',
                        );
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text(
                      'قبل بـ 15 دقيقة',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: _autoAlarmMinutesBefore == 15,
                    onSelected: (sel) async {
                      if (sel) {
                        setState(() => _autoAlarmMinutesBefore = 15);
                        setSheetState(() {});
                        await widget.database.setSetting(
                          'school_auto_alarm_minutes_before',
                          '15',
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // --- 1. Master Weekly Sync Button (Primary Prominent Action) ---
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 3,
                  ),
                  icon: const Icon(Icons.flash_on_rounded, size: 20),
                  label: const Text(
                    '🚀 مزامنة الأسبوع الدراسي بالكامل (الأحد - الخميس)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  onPressed: () async {
                    HapticFeedback.heavyImpact();
                    final count = await _syncWeeklyAlarms();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          count > 0
                              ? 'تمت مزامنة وجدولة $count منبهًا للأسبوع الدراسي بالكامل 🚀'
                              : 'لم توجد حصص مجدولة للأسبوع الدراسي أو تعذرت الجدولة.',
                        ),
                        backgroundColor: const Color(0xFF6366F1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),

              // --- 2. Smart Next Day Sync & Custom Day Sync ---
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00F2FE),
                        foregroundColor: const Color(0xFF0B1120),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.alarm_add_rounded, size: 15),
                      label: const Flexible(
                        child: Text(
                          'مزامنة الغد ⏰',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        final count = await _checkAndRunMidnightAutoAlarmSync(
                          force: true,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              count > 0
                                  ? 'تمت جدولة $count منبهًا تلقائيًا لليوم القادم.'
                                  : 'لا توجد مواعيد لليوم القادم أو تعذرت الجدولة.',
                            ),
                            backgroundColor: const Color(0xFF0D9488),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF00F2FE)),
                        foregroundColor: const Color(0xFF00F2FE),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.event_note_rounded, size: 15),
                      label: const Flexible(
                        child: Text(
                          'مزامنة يوم مخصص 🗓️',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onPressed: () {
                        _showSyncSpecificDayDialog(ctx);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // --- 3. Dismiss & Purge Buttons ---
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        foregroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                      ),
                      icon: const Icon(Icons.cleaning_services_rounded, size: 15),
                      label: const Flexible(
                        child: Text(
                          'تنظيف المنتهية 🧹',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        final now = DateTime.now();
                        final todayArabic = _getTodayName(now.weekday);
                        final count = await AlarmService.cleanExpiredAlarms(
                          todayPeriods: _schoolPeriods,
                          todayGroups: _centerGroups,
                          todayArabic: todayArabic,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              count > 0
                                  ? 'تم تنظيف وحذف $count منبهًا وتنبيهًا منتهيًا بنجاح 🧹'
                                  : 'لا توجد منبهات منتهية حاليًا، كل المواعيد المتبقية سارية.',
                            ),
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        foregroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                      ),
                      icon: const Icon(Icons.delete_forever_rounded, size: 15),
                      label: const Flexible(
                        child: Text(
                          'حذف كافة المنبهات 🗑️',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onPressed: () {
                        _dismissAllAlarms(ctx);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // --- 4. Targeted Dismiss & System Integration ---
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: const BorderSide(color: Color(0xFFA855F7)),
                        foregroundColor: const Color(0xFFA855F7),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                      ),
                      icon: const Icon(Icons.calendar_month_rounded, size: 15),
                      label: const Flexible(
                        child: Text(
                          'إزالة يوم محدد 📅',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onPressed: () {
                        _showDismissDayAlarmsDialog(ctx);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: const BorderSide(color: Color(0xFFFBBF24)),
                        foregroundColor: const Color(0xFFFBBF24),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                      ),
                      icon: const Icon(Icons.volume_up_rounded, size: 15),
                      label: const Flexible(
                        child: Text(
                          'تجربة رنين المنبه 🔔',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onPressed: () async {
                        HapticFeedback.heavyImpact();
                        await AlarmService.testAlarmSound();
                        await NotificationService.showNotification(
                          id: 99999,
                          title: '🔔 تجربة رنين منبه الجدول الفعلي',
                          body: 'صوت ورنين تنبيه الحصة يعمل بكفاءة ودقة عالية 🚀',
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم تشغيل صوت المنبه الفعلي بنجاح! 🔔🎶'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // --- 5. Phone Clock App Button ---
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: Color(0xFF00F2FE)),
                    foregroundColor: const Color(0xFF00F2FE),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.alarm_on_rounded, size: 18),
                  label: const Text(
                    'شاشة المنبه الداخلي الذكي ⏰',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AlarmClockScreen(database: widget.database),
                      ),
                    ).then((_) => _loadData());
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. In-Day Period Audio & Notification Alerts
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Row(
                  children: [
                    Icon(
                      Icons.notifications_active_rounded,
                      color: Color(0xFFFBBF24),
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'إشعارات وتنبيهات الحصص أثناء اليوم 🔔',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'تنبيه صوتي قبل الحصة بـ 5 دقائق، وإشعار عند بدايتها وعند نهايتها.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                value: _autoPeriodAlerts,
                onChanged: (val) async {
                  HapticFeedback.selectionClick();
                  setState(() => _autoPeriodAlerts = val);
                  setSheetState(() {});
                  await widget.database.setSetting(
                    'school_auto_period_alerts',
                    val ? 'true' : 'false',
                  );
                },
              ),
              const SizedBox(height: 10),
              const Text(
                'أيام تفعيل تنبيهات الحصص:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _schoolWeekdays.map((day) {
                  final isSelected = _alertActiveDays.contains(day);
                  return FilterChip(
                    label: Text(
                      day,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (sel) async {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (sel) {
                          _alertActiveDays.add(day);
                        } else {
                          _alertActiveDays.remove(day);
                        }
                      });
                      setSheetState(() {});
                      await widget.database.setSetting(
                        'school_alarm_selected_days',
                        jsonEncode(_alertActiveDays.toList()),
                      );
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFBBF24)),
                  foregroundColor: const Color(0xFFFBBF24),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showInteractiveSchoolBellSheet();
                },
                icon: const Icon(Icons.notifications_active_rounded, size: 16),
                label: const Text(
                  'جرس الحصة والتجربة الفورية 🔔',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showPeriodAlertsAndAlarmsDialog();
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text(
                  'تخصيص منبهات الأيام',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
        // Dedicated Save Button for Tab 4
        _buildSettingsTabSaveButton(
          label: 'حفظ إعدادات المنبه والتنبيهات الذكية ✓',
          successMessage: 'تم حفظ إعدادات المنبه والتنبيهات بنجاح! ✓',
          onSave: () => _saveAlarmSettings(ctx),
        ),
      ],
    );
  }

  // --- Tab 5: الصلاحيات والنظام والأذونات 🛡️ ---
  Widget _buildSettingsPermissionsTab(
    BuildContext ctx,
    bool isDark,
    StateSetter setSheetState,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E1B4B), const Color(0xFF0F172A)]
                  : [const Color(0xFFEFF6FF), Colors.white],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF3730A3) : const Color(0xFFBFDBFE),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.security_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مركز إدارة وصلاحيات النظام 🛡️',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'تحكم كامل في تفعيل أو فحص كافة أذونات الكاميرا، والظهور فوق التطبيقات، والمنبهات.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Permission Card 1: الظهور فوق التطبيقات (System Alert Window / Display over other apps)
        _buildPermissionItemCard(
          title: 'الظهور فوق التطبيقات (Display over apps)',
          desc:
              'ضرورية لعرض شاشة رنين المنبه الذكي وإشعار الحصة فوق أي تطبيق آخر عند بدء وقتها.',
          icon: Icons.layers_rounded,
          iconColor: const Color(0xFFA855F7),
          actionLabel: 'طلب / فحص',
          onTap: () async {
            HapticFeedback.selectionClick();
            final status = await Permission.systemAlertWindow.request();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  status.isGranted
                      ? 'صلاحية الظهور فوق التطبيقات مفعّلة بنجاح! ✓'
                      : 'يرجى تفعيل صلاحية الظهور من شاشة النظام.',
                ),
                backgroundColor: status.isGranted
                    ? const Color(0xFF10B981)
                    : Colors.orange,
                behavior: SnackBarBehavior.floating,
              ),
            );
            setSheetState(() {});
          },
          isDark: isDark,
        ),
        const SizedBox(height: 10),

        // Permission Card 2: الكاميرا لمسح باركود QR كود والبطاقات
        _buildPermissionItemCard(
          title: 'صلاحية الكاميرا (Camera for QR)',
          desc:
              'مطلوبة لمسح كيو ار كود للطلاب والبطاقات الذكية وتسجيل الحضور والانصراف بدقة وسرعة فائقة.',
          icon: Icons.qr_code_scanner_rounded,
          iconColor: const Color(0xFF00F2FE),
          actionLabel: 'طلب / فحص',
          onTap: () async {
            HapticFeedback.selectionClick();
            final status = await Permission.camera.request();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  status.isGranted
                      ? 'صلاحية الكاميرا مفعّلة بنجاح! ✓'
                      : 'تم استدعاء إذن الكاميرا. يرجى منحه من الإعدادات.',
                ),
                backgroundColor: status.isGranted
                    ? const Color(0xFF10B981)
                    : Colors.orange,
                behavior: SnackBarBehavior.floating,
              ),
            );
            setSheetState(() {});
          },
          isDark: isDark,
        ),
        const SizedBox(height: 10),

        // Permission Card 3: التنبيهات والإشعارات (Notifications)
        _buildPermissionItemCard(
          title: 'التنبيهات والإشعارات (Notifications)',
          desc:
              'إرسال تنبيهات الحصص قبل البدء بـ 5 دقائق وتنبيهات الطابور وإشراف الفناء.',
          icon: Icons.notifications_active_rounded,
          iconColor: const Color(0xFFFBBF24),
          actionLabel: 'طلب / فحص',
          onTap: () async {
            HapticFeedback.selectionClick();
            final status = await Permission.notification.request();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  status.isGranted
                      ? 'صلاحية الإشعارات مفعّلة بنجاح! ✓'
                      : 'صلاحية الإشعارات غير مفعلة.',
                ),
                backgroundColor: status.isGranted
                    ? const Color(0xFF10B981)
                    : Colors.orange,
                behavior: SnackBarBehavior.floating,
              ),
            );
            setSheetState(() {});
          },
          isDark: isDark,
        ),
        const SizedBox(height: 10),

        // Permission Card 4: المنبهات الدقيقة (Exact Alarms)
        _buildPermissionItemCard(
          title: 'المنبهات الدقيقة (Exact Alarms)',
          desc:
              'لضمان رنين منبهات الحصص في وقتها بدقة ثانية بدون أي تأخير من توفير طاقة النظام.',
          icon: Icons.alarm_rounded,
          iconColor: const Color(0xFFEC4899),
          actionLabel: 'طلب / فحص',
          onTap: () async {
            HapticFeedback.selectionClick();
            final status = await Permission.scheduleExactAlarm.request();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  status.isGranted
                      ? 'صلاحية المنبهات الدقيقة مفعلة بنجاح! ✓'
                      : 'يرجى السماح بالمنبهات الدقيقة في إعدادات النظام.',
                ),
                backgroundColor: status.isGranted
                    ? const Color(0xFF10B981)
                    : Colors.orange,
                behavior: SnackBarBehavior.floating,
              ),
            );
            setSheetState(() {});
          },
          isDark: isDark,
        ),
        const SizedBox(height: 10),

        // Permission Card 5: تجاهل تحسين استهلاك البطارية
        _buildPermissionItemCard(
          title: 'العمل في الخلفية (تجاهل توفير البطارية)',
          desc:
              'حماية التطبيق من الإغلاق لضمان جدولة منبهات اليوم التالي تلقائياً في منتصف الليل.',
          icon: Icons.battery_charging_full_rounded,
          iconColor: const Color(0xFF10B981),
          actionLabel: 'طلب الاستثناء',
          onTap: () async {
            HapticFeedback.selectionClick();
            final status = await Permission.ignoreBatteryOptimizations
                .request();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  status.isGranted
                      ? 'تم استثناء التطبيق من تحسين البطارية بنجاح! ✓'
                      : 'تم استدعاء شاشة تحسين البطارية.',
                ),
                backgroundColor: status.isGranted
                    ? const Color(0xFF10B981)
                    : Colors.orange,
                behavior: SnackBarBehavior.floating,
              ),
            );
            setSheetState(() {});
          },
          isDark: isDark,
        ),
        const SizedBox(height: 14),

        // Button to Open Android App Settings
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.5),
            ),
          ),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              foregroundColor: const Color(0xFF3B82F6),
            ),
            icon: const Icon(Icons.settings_applications_rounded, size: 20),
            label: const Text(
              'فتح إعدادات التطبيق الكاملة في أندرويد ⚙️',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            onPressed: () async {
              HapticFeedback.mediumImpact();
              await openAppSettings();
            },
          ),
        ),

        // Dedicated Save Button for Tab 5
        _buildSettingsTabSaveButton(
          label: 'حفظ وتطبيق إعدادات الصلاحيات والنظام ✓',
          successMessage: 'تم تطبيق وتأكيد إعدادات الصلاحيات بنجاح! ✓',
          onSave: () async {},
        ),
      ],
    );
  }

  // --- Dedicated Tab Save Button Helper ---
  Widget _buildSettingsTabSaveButton({
    required String label,
    required FutureOr<void> Function() onSave,
    String? successMessage,
  }) {
    return _SettingsTabSaveButtonWidget(
      label: label,
      onSave: onSave,
      successMessage: successMessage,
      onNotify: _activeSettingsFeedbackCallback,
    );
  }

  // --- Permission Card Helper ---
  Widget _buildPermissionItemCard({
    required String title,
    required String desc,
    required IconData icon,
    required Color iconColor,
    required String actionLabel,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141E33) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: iconColor.withValues(alpha: 0.18),
              foregroundColor: iconColor,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onTap,
            child: Text(
              actionLabel,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper to Sync Weekly Timetable Alarms (Sunday - Thursday) ---
  Future<int> _syncWeeklyAlarms() async {
    return await AlarmService.syncWeeklyTimetableAlarms(
      periods: _schoolPeriods.where((p) => !p.isReserve).toList(),
      groups: _centerGroups,
      weekdays: _schoolWeekdays,
      minutesBefore: _autoAlarmMinutesBefore,
      useSystemClock: _syncToSystemClockApp,
    );
  }

  // --- Helper to Sync a Specific Named Weekday ---
  Future<int> _syncDayAlarmsByName(String dayName) async {
    final now = DateTime.now();
    DateTime? targetDate;
    for (int i = 0; i < 7; i++) {
      final d = now.add(Duration(days: i));
      if (_getTodayName(d.weekday) == dayName) {
        targetDate = d;
        break;
      }
    }
    targetDate ??= now;
    return await _syncManualAlarmsForDate(targetDate);
  }

  // --- Helper to Purge and Dismiss ALL Alarms ---
  Future<void> _dismissAllAlarms(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'حذف كافة منبهات الجدول',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من رغبتك في حذف وإلغاء كافة منبهات الجدول المدرسي ومجموعات الدروس بالكامل؟',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, height: 1.4),
            ),
            SizedBox(height: 10),
            Text(
              'سيتم مسح وتصفير كافة المنبهات والتنبيهات المجدولة فورًا داخل التطبيق وبصمت تام 🗑️',
              style: TextStyle(fontSize: 11.5, height: 1.5, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('حذف كافة المنبهات 🗑️'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedback.heavyImpact();
      final count = await AlarmService.dismissAllAlarms();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? 'تم حذف وإلغاء $count منبهًا وتنبيهًا للجدول بنجاح 🗑️'
                : 'تم مسح وإلغاء كافة منبهات الجدول بنجاح.',
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'شاشة المنبه',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AlarmClockScreen(database: widget.database),
                ),
              ).then((_) => _loadData());
            },
          ),
        ),
      );
    }
  }

  // --- Dialog to Sync a Specific Day ---
  void _showSyncSpecificDayDialog(BuildContext ctx) {
    const allDays = [
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
    ];

    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.event_note_rounded,
              color: Color(0xFF00F2FE),
              size: 22,
            ),
            SizedBox(width: 8),
            Text(
              'مزامنة منبهات يوم مخصص',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'اختر اليوم الذي ترغب في جدولة منبهات حصصه ومجموعاته فورًا:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: allDays.map((day) {
                  return ActionChip(
                    avatar: const Icon(
                      Icons.alarm_add_rounded,
                      size: 14,
                      color: Color(0xFF00F2FE),
                    ),
                    label: Text(
                      day,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                    onPressed: () async {
                      Navigator.pop(dCtx);
                      HapticFeedback.mediumImpact();
                      final count = await _syncDayAlarmsByName(day);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            count > 0
                                ? 'تمت جدولة $count منبهًا لحصص ومجموعات يوم $day ⏰'
                                : 'لا توجد حصص أو مجموعات مجدولة ليوم $day.',
                          ),
                          backgroundColor: count > 0
                              ? const Color(0xFF0D9488)
                              : Colors.grey.shade700,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  // --- Dialog to Dismiss Specific Day Alarms ---
  void _showDismissDayAlarmsDialog(BuildContext ctx) {
    const allDays = [
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
    ];

    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.calendar_month_rounded,
              color: Color(0xFFA855F7),
              size: 22,
            ),
            SizedBox(width: 8),
            Text(
              'إزالة تنبيهات يوم محدد',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'اختر اليوم الذي ترغب في إلغاء جميع تنبيهات الجدول المجدولة له داخل التطبيق:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: allDays.map((day) {
                  return ActionChip(
                    label: Text(
                      day,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                    avatar: const Icon(
                      Icons.delete_outline_rounded,
                      size: 14,
                      color: Colors.redAccent,
                    ),
                    onPressed: () async {
                      Navigator.pop(dCtx);
                      HapticFeedback.mediumImpact();
                      final count = await AlarmService.dismissDayAlarms(
                        dayName: day,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            count > 0
                                ? 'تم إلغاء $count تنبيهًا مجدولًا ليوم $day.'
                                : 'لا توجد تنبيهات مجدولة ليوم $day.',
                          ),
                          backgroundColor: const Color(0xFFEF4444),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  // --- Quick Add Subject Dialog ---
  void _showAddSubjectDialog(StateSetter setSheetState) {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text(
          'إضافة مادة دراسية جديدة 📚',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'اسم المادة (مثال: علوم / رياضيات / ICT)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final name = textCtrl.text.trim();
              if (name.isEmpty) return;
              final newSubj = {
                'id': 'subj_${DateTime.now().millisecondsSinceEpoch}',
                'name': name,
                'sort_order': _schoolSubjects.length + 1,
              };
              await widget.database.saveSchoolSubject(newSubj);
              final updated = await widget.database.getSchoolSubjects();
              setState(() => _schoolSubjects = updated);
              setSheetState(() {});
              Navigator.pop(dCtx);
            },
            child: const Text('إضافة وحفظ'),
          ),
        ],
      ),
    );
  }

  // --- Global School Timings, Recess Position & Supervision Duties Dialog ---
  void _showConfigureTimingsDialog({bool returnToSettings = true}) {
    final tempTimings = Map<int, ({String start, String end})>.from(
      _periodTimings,
    );
    String tempRecessStart = _recessStartTime;
    String tempRecessEnd = _recessEndTime;
    int tempRecessAfter = _recessAfterPeriod;

    String tempAssemblyDay = _morningAssemblyDutyDay;
    String tempAssemblyStart = _morningAssemblyStartTime;
    String tempAssemblyEnd = _morningAssemblyEndTime;
    final assemblyLocCtrl = TextEditingController(
      text: _morningAssemblyLocation,
    );

    String tempBreakDay = _breakDutyDay;
    final breakLocCtrl = TextEditingController(text: _breakDutyLocation);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.88,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 18,
                        ),
                        tooltip: 'رجوع للخلف',
                        onPressed: () {
                          Navigator.pop(ctx);
                          if (returnToSettings) _showUnifiedTimetableSettings();
                        },
                      ),
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF59E0B,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.access_time_rounded,
                          color: Color(0xFFF59E0B),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'إعداد الفسحة وإشراف الطابور والبريك ⏱️',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'حدد مكان الفسحة وتوقيتها، ومواعيد إشرافك الأسبوعي بحرية:',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        // --- 1. RECESS POSITION & TIMING ---
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF59E0B,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(
                                0xFFF59E0B,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.coffee_rounded,
                                    color: Color(0xFFF59E0B),
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'مكان الفسحة المدرسية (البريك)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      color: Color(0xFFF59E0B),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'تظهر الفسحة في الجدول بعد الحصة:',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [1, 2, 3, 4, 5].map((periodNum) {
                                    final isSelected =
                                        tempRecessAfter == periodNum;
                                    return Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: InkWell(
                                        onTap: () => setDialogState(
                                          () => tempRecessAfter = periodNum,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 150,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFFF59E0B)
                                                : (isDark
                                                      ? const Color(0xFF1E293B)
                                                      : const Color(
                                                          0xFFF1F5F9,
                                                        )),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFFF59E0B)
                                                  : Colors.grey.shade700,
                                            ),
                                          ),
                                          child: Text(
                                            'بعد ${_convertToArabicWords(periodNum)}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11.5,
                                              color: isSelected
                                                  ? Colors.black87
                                                  : (isDark
                                                        ? Colors.white70
                                                        : Colors.black87),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text(
                                    'توقيت الفسحة:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  _buildTimePill(
                                    tempRecessStart,
                                    const Color(0xFFF59E0B),
                                    () async {
                                      final p = await _pickCustomTime(
                                        ctx,
                                        tempRecessStart,
                                      );
                                      if (p != null)
                                        setDialogState(
                                          () => tempRecessStart = p,
                                        );
                                    },
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Text(
                                      '—',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                  _buildTimePill(
                                    tempRecessEnd,
                                    const Color(0xFFF59E0B),
                                    () async {
                                      final p = await _pickCustomTime(
                                        ctx,
                                        tempRecessEnd,
                                      );
                                      if (p != null)
                                        setDialogState(() => tempRecessEnd = p);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // --- 2. MORNING ASSEMBLY SUPERVISION DUTY ---
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF818CF8,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(
                                0xFF818CF8,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.wb_sunny_rounded,
                                    color: Color(0xFF818CF8),
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'إشراف طابور الصباح الأسبوعي ☀️',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      color: Color(0xFF818CF8),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'اختر يوم تكليفك بإشراف الطابور:',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    ..._schoolWeekdays.map((day) {
                                      final isSelected = tempAssemblyDay == day;
                                      return Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: InkWell(
                                          onTap: () => setDialogState(
                                            () => tempAssemblyDay = day,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? const Color(0xFF818CF8)
                                                  : (isDark
                                                        ? const Color(
                                                            0xFF1E293B,
                                                          )
                                                        : const Color(
                                                            0xFFF1F5F9,
                                                          )),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: isSelected
                                                    ? const Color(0xFF818CF8)
                                                    : Colors.grey.shade700,
                                              ),
                                            ),
                                            child: Text(
                                              day,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color: isSelected
                                                    ? Colors.black
                                                    : (isDark
                                                          ? Colors.white70
                                                          : Colors.black87),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: InkWell(
                                        onTap: () => setDialogState(
                                          () => tempAssemblyDay = '',
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: tempAssemblyDay.isEmpty
                                                ? Colors.grey.shade700
                                                : (isDark
                                                      ? const Color(0xFF1E293B)
                                                      : const Color(
                                                          0xFFF1F5F9,
                                                        )),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          child: const Text(
                                            'بدون إشراف',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (tempAssemblyDay.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    const Text(
                                      'توقيت الطابور:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    _buildTimePill(
                                      tempAssemblyStart,
                                      const Color(0xFF818CF8),
                                      () async {
                                        final p = await _pickCustomTime(
                                          ctx,
                                          tempAssemblyStart,
                                        );
                                        if (p != null)
                                          setDialogState(
                                            () => tempAssemblyStart = p,
                                          );
                                      },
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Text(
                                        '—',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                    _buildTimePill(
                                      tempAssemblyEnd,
                                      const Color(0xFF818CF8),
                                      () async {
                                        final p = await _pickCustomTime(
                                          ctx,
                                          tempAssemblyEnd,
                                        );
                                        if (p != null)
                                          setDialogState(
                                            () => tempAssemblyEnd = p,
                                          );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: assemblyLocCtrl,
                                  decoration: InputDecoration(
                                    labelText:
                                        'مكان الإشراف (مثال: فناء المدرسة / البوابة)',
                                    labelStyle: const TextStyle(fontSize: 12),
                                    filled: true,
                                    fillColor: isDark
                                        ? const Color(0xFF141E33)
                                        : const Color(0xFFF8FAFC),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // --- 3. BREAK SUPERVISION DUTY ---
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF59E0B,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(
                                0xFFF59E0B,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    color: Color(0xFFF59E0B),
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'إشراف الفسحة (البريك) الأسبوعي ☕',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      color: Color(0xFFF59E0B),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'اختر يوم تكليفك بإشراف الفسحة:',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    ..._schoolWeekdays.map((day) {
                                      final isSelected = tempBreakDay == day;
                                      return Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: InkWell(
                                          onTap: () => setDialogState(
                                            () => tempBreakDay = day,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? const Color(0xFFF59E0B)
                                                  : (isDark
                                                        ? const Color(
                                                            0xFF1E293B,
                                                          )
                                                        : const Color(
                                                            0xFFF1F5F9,
                                                          )),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: isSelected
                                                    ? const Color(0xFFF59E0B)
                                                    : Colors.grey.shade700,
                                              ),
                                            ),
                                            child: Text(
                                              day,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color: isSelected
                                                    ? Colors.black
                                                    : (isDark
                                                          ? Colors.white70
                                                          : Colors.black87),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: InkWell(
                                        onTap: () => setDialogState(
                                          () => tempBreakDay = '',
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: tempBreakDay.isEmpty
                                                ? Colors.grey.shade700
                                                : (isDark
                                                      ? const Color(0xFF1E293B)
                                                      : const Color(
                                                          0xFFF1F5F9,
                                                        )),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          child: const Text(
                                            'بدون إشراف',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (tempBreakDay.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: breakLocCtrl,
                                  decoration: InputDecoration(
                                    labelText:
                                        'مكان إشراف الفسحة (مثال: فناء المدرسة / الأدوار)',
                                    labelStyle: const TextStyle(fontSize: 12),
                                    filled: true,
                                    fillColor: isDark
                                        ? const Color(0xFF141E33)
                                        : const Color(0xFFF8FAFC),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // --- 4. PERIODS 1 TO 8 TIMINGS ---
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'توقيتات الحصص (اضغط لتعديل أي حصة):',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        ...List.generate(8, (index) {
                          final num = index + 1;
                          final color = (num <= tempRecessAfter)
                              ? const Color(0xFF00F2FE)
                              : const Color(0xFF6366F1);
                          return _buildTimingRow(
                            title: 'الحصة ${_convertToArabicWords(num)}',
                            start: tempTimings[num]!.start,
                            end: tempTimings[num]!.end,
                            isDark: isDark,
                            color: color,
                            onPickStart: () async {
                              final p = await _pickCustomTime(
                                ctx,
                                tempTimings[num]!.start,
                              );
                              if (p != null)
                                setDialogState(
                                  () => tempTimings[num] = (
                                    start: p,
                                    end: tempTimings[num]!.end,
                                  ),
                                );
                            },
                            onPickEnd: () async {
                              final p = await _pickCustomTime(
                                ctx,
                                tempTimings[num]!.end,
                              );
                              if (p != null)
                                setDialogState(
                                  () => tempTimings[num] = (
                                    start: tempTimings[num]!.start,
                                    end: p,
                                  ),
                                );
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.shade400,
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              if (returnToSettings)
                                _showUnifiedTimetableSettings();
                            },
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'رجوع',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00F2FE),
                              foregroundColor: const Color(0xFF0B1120),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () async {
                              setState(() {
                                _periodTimings.clear();
                                _periodTimings.addAll(tempTimings);
                                _recessStartTime = tempRecessStart;
                                _recessEndTime = tempRecessEnd;
                                _recessAfterPeriod = tempRecessAfter;
                                _morningAssemblyDutyDay = tempAssemblyDay;
                                _morningAssemblyStartTime = tempAssemblyStart;
                                _morningAssemblyEndTime = tempAssemblyEnd;
                                _morningAssemblyLocation = assemblyLocCtrl.text
                                    .trim();
                                _breakDutyDay = tempBreakDay;
                                _breakDutyLocation = breakLocCtrl.text.trim();
                              });
                              await _savePeriodTimingsConfig();
                              Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'تم حفظ وتطبيق مواعيد الفسحة والإشراف بنجاح ⏰✅',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: Color(0xFF10B981),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(
                              Icons.check_circle_outline_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'حفظ التوقيتات',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimingRow({
    required String title,
    required String start,
    required String end,
    required bool isDark,
    required Color color,
    required VoidCallback onPickStart,
    required VoidCallback onPickEnd,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
          ),
          _buildTimePill(start, color, onPickStart),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('—', style: TextStyle(color: Colors.grey)),
          ),
          _buildTimePill(end, color, onPickEnd),
        ],
      ),
    );
  }

  Widget _buildTimePill(String time, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_rounded, size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              time,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Quick Add Class Dialog (Asks for Class & Subject) ---
  void _showQuickAddClassDialog({
    Function(String className, String subject)? onAdded,
  }) {
    final nameCtrl = TextEditingController();
    final subjCtrl = TextEditingController();
    final roomCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.add_circle_outline_rounded, color: Color(0xFF00F2FE)),
            SizedBox(width: 8),
            Text(
              'إضافة فصل ومادة جديدة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسم الفصل (مثال: 1/1 أو 2/3)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.class_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: subjCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المادة (مثال: رياضيات / علوم)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.menu_book_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: roomCtrl,
                decoration: const InputDecoration(
                  labelText: 'المعمل أو القاعة (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F2FE),
              foregroundColor: const Color(0xFF0B1120),
            ),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final subj = subjCtrl.text.trim();
              final room = roomCtrl.text.trim();

              final newClass = {
                'id': 'class_${DateTime.now().millisecondsSinceEpoch}',
                'stage': '',
                'class_name': name,
                'subject': subj,
                'room': room,
                'sort_order': _schoolClasses.length + 1,
              };
              await widget.database.saveSchoolClass(newClass);
              final updated = await widget.database.getSchoolClasses();
              setState(() => _schoolClasses = updated);
              if (onAdded != null) onAdded(name, subj);
              Navigator.pop(ctx);
            },
            child: const Text('إضافة وحفظ'),
          ),
        ],
      ),
    );
  }

  // --- Manage Classes Dialog (Displays Class & Subject, Allows Edit & Delete) ---
  void _showManageClassesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.class_rounded,
                    color: Color(0xFF00F2FE),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'إدارة الفصول والمواد 🏫',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الفصول والمواد المسجلة (يمكنك تعديل أي فصل أو حذفه):',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: _schoolClasses.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                'لا توجد فصول مضافة بعد.\nاضغط على إضافة فصل ومادة جديدة بالأسفل.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _schoolClasses.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 10),
                            itemBuilder: (ctx, idx) {
                              final item = _schoolClasses[idx];
                              final id = item['id'].toString();
                              final cName = item['class_name'].toString();
                              final subj = (item['subject'] ?? '').toString();
                              final room = (item['room'] ?? '').toString();

                              return Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF00F2FE,
                                      ).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFF00F2FE),
                                      ),
                                    ),
                                    child: Text(
                                      cName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                        color: Color(0xFF00F2FE),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          subj.isNotEmpty
                                              ? subj
                                              : 'بدون مادة محددة',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: subj.isNotEmpty
                                                ? (isDark
                                                      ? Colors.white
                                                      : Colors.black87)
                                                : Colors.grey,
                                          ),
                                        ),
                                        if (room.isNotEmpty)
                                          Text(
                                            '📍 $room',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Edit Button
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_note_rounded,
                                      color: Color(0xFF00F2FE),
                                      size: 24,
                                    ),
                                    tooltip: 'تعديل الفصل والمادة',
                                    onPressed: () {
                                      _showAddOrEditClassDialog(
                                        existingClass: item,
                                        parentSetState: () =>
                                            setDialogState(() {}),
                                      );
                                    },
                                  ),
                                  // Delete Button
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    tooltip: 'حذف الفصل',
                                    onPressed: () async {
                                      await widget.database.deleteSchoolClass(
                                        id,
                                      );
                                      final updated = await widget.database
                                          .getSchoolClasses();
                                      setState(() => _schoolClasses = updated);
                                      setDialogState(() {});
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00F2FE),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'إضافة فصل ومادة ＋',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  _showAddOrEditClassDialog(
                    parentSetState: () => setDialogState(() {}),
                  );
                },
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Add or Edit Class & Subject Dialog ---
  void _showAddOrEditClassDialog({
    Map<String, dynamic>? existingClass,
    required VoidCallback parentSetState,
  }) {
    final isEdit = existingClass != null;
    final oldClassName = existingClass?['class_name']?.toString() ?? '';
    final nameCtrl = TextEditingController(
      text: existingClass?['class_name'] ?? '',
    );
    final subjCtrl = TextEditingController(
      text: existingClass?['subject'] ?? '',
    );
    final roomCtrl = TextEditingController(text: existingClass?['room'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Icon(
                  isEdit
                      ? Icons.edit_note_rounded
                      : Icons.add_circle_outline_rounded,
                  color: const Color(0xFF00F2FE),
                ),
                const SizedBox(width: 8),
                Text(
                  isEdit
                      ? 'تعديل بيانات الفصل والمادة'
                      : 'إضافة فصل ومادة جديدة',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'اسم الفصل (مثال: 1/1 أو 2/1)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.class_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Quick Subject Chips for Class
                  if (_schoolSubjects.isNotEmpty) ...[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'اختر المادة من قائمتك أو اكتب:',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ..._schoolSubjects.map((sb) {
                            final sName = (sb['name'] ?? '').toString();
                            final isChosen = subjCtrl.text == sName;
                            return Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: InkWell(
                                onTap: () =>
                                    setDialogState(() => subjCtrl.text = sName),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isChosen
                                        ? const Color(0xFFA78BFA)
                                        : (isDark
                                              ? const Color(0xFF1E293B)
                                              : const Color(0xFFF1F5F9)),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isChosen
                                          ? const Color(0xFFA78BFA)
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                  child: Text(
                                    sName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isChosen
                                          ? Colors.black
                                          : (isDark
                                                ? Colors.white70
                                                : Colors.black87),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  TextFormField(
                    controller: subjCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المادة (مثال: رياضيات / علوم / حاسب)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.menu_book_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: roomCtrl,
                    decoration: const InputDecoration(
                      labelText: 'المعمل أو القاعة الافتراضية (اختياري)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F2FE),
                  foregroundColor: const Color(0xFF0B1120),
                ),
                onPressed: () async {
                  final cName = nameCtrl.text.trim();
                  if (cName.isEmpty) return;
                  final subj = subjCtrl.text.trim();
                  final room = roomCtrl.text.trim();

                  final classData = {
                    'id':
                        existingClass?['id'] ??
                        'class_${DateTime.now().millisecondsSinceEpoch}',
                    'stage': '',
                    'class_name': cName,
                    'subject': subj,
                    'room': room,
                    'sort_order':
                        existingClass?['sort_order'] ??
                        (_schoolClasses.length + 1),
                  };

                  await widget.database.saveSchoolClass(classData);

                  // If this subject is new, also save it in registered subjects
                  if (subj.isNotEmpty &&
                      !_schoolSubjects.any((s) => s['name'] == subj)) {
                    final newSubj = {
                      'id': 'subj_${DateTime.now().millisecondsSinceEpoch}',
                      'name': subj,
                      'sort_order': _schoolSubjects.length + 1,
                    };
                    await widget.database.saveSchoolSubject(newSubj);
                    final updatedSubjs = await widget.database
                        .getSchoolSubjects();
                    setState(() => _schoolSubjects = updatedSubjs);
                  }

                  // If editing, also synchronize existing timetable periods of that class
                  if (isEdit && oldClassName.isNotEmpty) {
                    try {
                      final db = await widget.database.database;
                      if (oldClassName != cName) {
                        await db.update(
                          'school_periods',
                          {'class_name': cName},
                          where: 'class_name = ?',
                          whereArgs: [oldClassName],
                        );
                      }
                      if (subj.isNotEmpty) {
                        await db.update(
                          'school_periods',
                          {'subject': subj},
                          where: 'class_name = ?',
                          whereArgs: [cName],
                        );
                      }
                      final updatedPeriods = await widget.database
                          .getSchoolPeriods();
                      setState(() => _schoolPeriods = updatedPeriods);
                    } catch (_) {}
                  }

                  final updatedClasses = await widget.database
                      .getSchoolClasses();
                  setState(() => _schoolClasses = updatedClasses);
                  parentSetState();
                  Navigator.pop(ctx);
                },
                child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة وحفظ'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Manage Subjects Dialog (قائمة إدارة المواد الدراسية) ---
  void _showManageSubjectsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA78BFA).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: Color(0xFFA78BFA),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'إدارة المواد الدراسية 📚',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المواد المسجلة لديك (تظهر في قائمة الاختيار السريع):',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: _schoolSubjects.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                'لا توجد مواد مضافة بعد.\nاضغط على إضافة مادة جديدة بالأسفل.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _schoolSubjects.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 10),
                            itemBuilder: (ctx, idx) {
                              final item = _schoolSubjects[idx];
                              final id = item['id'].toString();
                              final sName = item['name'].toString();

                              return Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFA78BFA,
                                      ).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFA78BFA),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.book_rounded,
                                          size: 14,
                                          color: Color(0xFFA78BFA),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          sName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                            color: Color(0xFFA78BFA),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  // Edit Button
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_note_rounded,
                                      color: Color(0xFFA78BFA),
                                      size: 24,
                                    ),
                                    tooltip: 'تعديل اسم المادة',
                                    onPressed: () {
                                      _showAddOrEditSubjectDialog(
                                        existingSubject: item,
                                        onAdded: (_) => setDialogState(() {}),
                                      );
                                    },
                                  ),
                                  // Delete Button
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                    tooltip: 'حذف المادة',
                                    onPressed: () async {
                                      await widget.database.deleteSchoolSubject(
                                        id,
                                      );
                                      final updated = await widget.database
                                          .getSchoolSubjects();
                                      setState(() => _schoolSubjects = updated);
                                      setDialogState(() {});
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFA78BFA),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'إضافة مادة جديدة ＋',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  _showAddOrEditSubjectDialog(
                    onAdded: (_) => setDialogState(() {}),
                  );
                },
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Add or Edit Subject Dialog ---
  void _showAddOrEditSubjectDialog({
    Map<String, dynamic>? existingSubject,
    Function(String name)? onAdded,
  }) {
    final isEdit = existingSubject != null;
    final oldName = existingSubject?['name']?.toString() ?? '';
    final nameCtrl = TextEditingController(
      text: existingSubject?['name'] ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(
              isEdit
                  ? Icons.edit_note_rounded
                  : Icons.add_circle_outline_rounded,
              color: const Color(0xFFA78BFA),
            ),
            const SizedBox(width: 8),
            Text(
              isEdit ? 'تعديل اسم المادة' : 'إضافة مادة دراسية جديدة',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: TextFormField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'اسم المادة (مثال: رياضيات / لغة عربية / علوم)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.menu_book_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA78BFA),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final sName = nameCtrl.text.trim();
              if (sName.isEmpty) return;

              final subjData = {
                'id':
                    existingSubject?['id'] ??
                    'subj_${DateTime.now().millisecondsSinceEpoch}',
                'name': sName,
                'sort_order':
                    existingSubject?['sort_order'] ??
                    (_schoolSubjects.length + 1),
              };

              await widget.database.saveSchoolSubject(subjData);

              // If editing, synchronize with periods and classes that use old name
              if (isEdit && oldName.isNotEmpty && oldName != sName) {
                try {
                  final db = await widget.database.database;
                  await db.update(
                    'school_periods',
                    {'subject': sName},
                    where: 'subject = ?',
                    whereArgs: [oldName],
                  );
                  await db.update(
                    'school_classes',
                    {'subject': sName},
                    where: 'subject = ?',
                    whereArgs: [oldName],
                  );
                  final updatedPeriods = await widget.database
                      .getSchoolPeriods();
                  final updatedClasses = await widget.database
                      .getSchoolClasses();
                  setState(() {
                    _schoolPeriods = updatedPeriods;
                    _schoolClasses = updatedClasses;
                  });
                } catch (_) {}
              }

              final updated = await widget.database.getSchoolSubjects();
              setState(() => _schoolSubjects = updated);
              if (onAdded != null) onAdded(sName);
              Navigator.pop(ctx);
            },
            child: Text(isEdit ? 'حفظ التعديل' : 'إضافة وحفظ'),
          ),
        ],
      ),
    );
  }

  // --- Interactive School Bell & Timetable Alarm Sheet 🔔⚡ ---
  void _showInteractiveSchoolBellSheet() {
    HapticFeedback.mediumImpact();
    String selectedTone = _currentAlarmTone;
    int minutesBefore = _autoAlarmMinutesBefore;
    bool useSystemClock = _syncToSystemClockApp;
    String? localPlayingTone;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final now = DateTime.now();
          final todayArabic = _getTodayName(now.weekday);

          // Count today's periods and groups
          final todayPeriods = _schoolPeriods
              .where((p) => p.dayOfWeek == todayArabic && !p.isReserve)
              .toList();
          final todayGroups = _centerGroups
              .where((g) => g.schedule.contains(todayArabic) || g.days.contains(todayArabic))
              .toList();
          final totalTodayItems = todayPeriods.length + todayGroups.length;

          final tonesList = [
            {
              'id': 'school_bell',
              'title': 'جرس الحصة المدرسي 🔔',
              'desc': 'رنين كلاسيكي مزدوج حقيقي وعالي الصوت',
              'icon': Icons.notifications_active_rounded,
              'color': 0xFFFBBF24,
            },
            {
              'id': 'alarm_climb',
              'title': 'رنين متصاعد قوي ⏰',
              'desc': 'صوت منبه إلكتروني متكرر وواضح جداً',
              'icon': Icons.alarm_rounded,
              'color': 0xFF00F2FE,
            },
            {
              'id': 'digital_beep',
              'title': 'نغمة رقمية نشطة 🎶',
              'desc': 'نغمات بييب تصاعدية مرحة وسريعة',
              'icon': Icons.graphic_eq_rounded,
              'color': 0xFF10B981,
            },
            {
              'id': 'gentle_melody',
              'title': 'نغمة هادئة لطيفة 🎵',
              'desc': 'رنين هادئ دافئ غير مزعج داخل الفصل',
              'icon': Icons.music_note_rounded,
              'color': 0xFFA855F7,
            },
          ];

          Future<void> handlePlayTone(String toneId) async {
            HapticFeedback.selectionClick();
            if (localPlayingTone == toneId) {
              await AlarmService.stopAudio();
              setSheetState(() => localPlayingTone = null);
              setState(() => _currentlyRingingTone = null);
            } else {
              setSheetState(() => localPlayingTone = toneId);
              setState(() => _currentlyRingingTone = toneId);
              await AlarmService.playAudio(toneId: toneId, durationMs: 8000);
              Future.delayed(const Duration(milliseconds: 8200), () {
                if (ctx.mounted && localPlayingTone == toneId) {
                  setSheetState(() => localPlayingTone = null);
                  if (mounted) setState(() => _currentlyRingingTone = null);
                }
              });
            }
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),

                  // Header Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Color(0xFFFBBF24),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'جرس الحصص ومنبه الجدول 🔔⚡',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'تحكم تفاعلي فوري في صوت ورنة المنبه ومواعيد التنبيه',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          AlarmService.stopAudio();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 1. Hero Card: دق الجرس المدرسي الآن 🔔
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: localPlayingTone != null
                            ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                            : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: (localPlayingTone != null
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFFF59E0B))
                              .withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                localPlayingTone != null
                                    ? Icons.stop_rounded
                                    : Icons.notifications_active_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    localPlayingTone != null
                                        ? 'الجرس يدق الآن بصوت عالٍ... 🔔'
                                        : 'دق الجرس في الفصل الآن 🔔',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    localPlayingTone != null
                                        ? 'اضغط هنا أو على الزر لإيقاف الرنين'
                                        : 'تجربة حية فورية للرنة المحددة بصوت مسموع وواضح',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: localPlayingTone != null
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFFB45309),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: Icon(
                              localPlayingTone != null
                                  ? Icons.stop_circle_rounded
                                  : Icons.volume_up_rounded,
                              size: 20,
                            ),
                            label: Text(
                              localPlayingTone != null
                                  ? 'إيقاف الجرس فوراً 🛑'
                                  : 'دق جرس الحصة الآن 🔔',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            onPressed: () async {
                              if (localPlayingTone != null) {
                                await AlarmService.stopAudio();
                                setSheetState(() => localPlayingTone = null);
                                setState(() => _currentlyRingingTone = null);
                              } else {
                                await handlePlayTone(selectedTone);
                                await NotificationService.showInstantSchoolBellNotification(
                                  title: 'جرس الحصة يدق الآن 🔔',
                                  body: 'تم تجربة جرس الحصة بنجاح بصوت عالي وواضح!',
                                  soundTone: selectedTone,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Section: اختيار رنة ونغمة الجرس 🎶
                  Row(
                    children: [
                      const Icon(Icons.music_note_rounded, color: Color(0xFF00F2FE), size: 18),
                      const SizedBox(width: 6),
                      const Text(
                        'اختيار نغمة ورنة الجرس 🎶:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        'النغمة الحالية: ${tonesList.firstWhere((t) => t['id'] == selectedTone, orElse: () => tonesList[0])['title']}',
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF00F2FE), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Column(
                    children: tonesList.map((tone) {
                      final toneId = tone['id'] as String;
                      final isSelected = selectedTone == toneId;
                      final isPlaying = localPlayingTone == toneId;
                      final toneColor = Color(tone['color'] as int);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? toneColor.withValues(alpha: 0.12)
                              : (isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? toneColor
                                : (isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0)),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: toneColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(tone['icon'] as IconData, color: toneColor, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tone['title'] as String,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: isSelected ? toneColor : (isDark ? Colors.white : Colors.black87),
                                    ),
                                  ),
                                  Text(
                                    tone['desc'] as String,
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            // Preview button
                            IconButton(
                              tooltip: isPlaying ? 'إيقاف 🛑' : 'تجربة النغمة ▶',
                              icon: Icon(
                                isPlaying ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                                color: isPlaying ? const Color(0xFFEF4444) : toneColor,
                                size: 24,
                              ),
                              onPressed: () => handlePlayTone(toneId),
                            ),
                            const SizedBox(width: 4),
                            // Selection button
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                backgroundColor: isSelected ? toneColor : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                                foregroundColor: isSelected ? (toneColor == const Color(0xFFFBBF24) ? Colors.black : Colors.white) : (isDark ? Colors.white70 : Colors.black87),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () async {
                                HapticFeedback.selectionClick();
                                setSheetState(() => selectedTone = toneId);
                                setState(() => _currentAlarmTone = toneId);
                                await widget.database.setSetting('alarm_sound_tone', toneId);
                                handlePlayTone(toneId);
                              },
                              child: Text(
                                isSelected ? 'مفعلة ✓' : 'اختيار',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // 3. Section: طريقة عمل المنبه ⚙️
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.tune_rounded, color: Color(0xFFA855F7), size: 18),
                            SizedBox(width: 6),
                            Text('طريقة التنبيه والرنين:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),

                        InkWell(
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            setSheetState(() => useSystemClock = false);
                            setState(() => _syncToSystemClockApp = false);
                            await widget.database.setSetting('school_sync_system_clock_app', 'false');
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: !useSystemClock
                                  ? const Color(0xFF00F2FE).withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: !useSystemClock
                                    ? const Color(0xFF00F2FE)
                                    : (isDark ? const Color(0xFF223147) : const Color(0xFFCBD5E1)),
                                width: !useSystemClock ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  !useSystemClock ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                  color: !useSystemClock ? const Color(0xFF00F2FE) : Colors.grey,
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '🔔 جرس ومنبه التطبيق الذكي (مُوصى به)',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'يرن بنغمة الجرس المختارة بصوت مسموع كمنبه حصة حقيقي.',
                                        style: TextStyle(fontSize: 10.5, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            setSheetState(() => useSystemClock = true);
                            setState(() => _syncToSystemClockApp = true);
                            await widget.database.setSetting('school_sync_system_clock_app', 'true');
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: useSystemClock
                                  ? const Color(0xFFFBBF24).withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: useSystemClock
                                    ? const Color(0xFFFBBF24)
                                    : (isDark ? const Color(0xFF223147) : const Color(0xFFCBD5E1)),
                                width: useSystemClock ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  useSystemClock ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                  color: useSystemClock ? const Color(0xFFFBBF24) : Colors.grey,
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '📱 تطبيق المنبه الرسمي وساعة الموبايل',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'يبرمج منبهات حقيقية في تطبيق Clock الرسمي للهاتف.',
                                        style: TextStyle(fontSize: 10.5, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 4. Section: وقت التنبيه المسبق ⏳
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.timer_rounded, color: Color(0xFF10B981), size: 18),
                            SizedBox(width: 6),
                            Text('موعد الرنين قبل بداية الحصة:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [0, 5, 10, 15].map((mins) {
                            final isSel = minutesBefore == mins;
                            return ChoiceChip(
                              label: Text(
                                mins == 0 ? 'في الموعد تماماً ⏰' : 'قبل بـ $mins دقائق',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  color: isSel ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                              selected: isSel,
                              selectedColor: const Color(0xFF10B981),
                              onSelected: (val) async {
                                HapticFeedback.selectionClick();
                                setSheetState(() => minutesBefore = mins);
                                setState(() => _autoAlarmMinutesBefore = mins);
                                await widget.database.setSetting('school_auto_alarm_minutes_before', mins.toString());
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. Action: مزامنة وتفعيل منبهات اليوم الآن 🚀
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.flash_on_rounded, size: 20),
                      label: Text(
                        'مزامنة وتفعيل منبهات اليوم ($todayArabic: $totalTodayItems حصة ومجموعة) ⚡',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      onPressed: () async {
                        HapticFeedback.heavyImpact();
                        AlarmService.stopAudio();

                        // Sync today's periods
                        final pCount = await AlarmService.syncDayPeriodAlarms(
                          dayPeriods: todayPeriods,
                          minutesBefore: minutesBefore,
                          useSystemClock: useSystemClock,
                          soundTone: selectedTone,
                        );

                        // Sync today's groups
                        final gCount = await AlarmService.syncDayGroupAlarms(
                          dayGroups: todayGroups,
                          dayName: todayArabic,
                          minutesBefore: minutesBefore,
                          useSystemClock: useSystemClock,
                          soundTone: selectedTone,
                        );

                        final total = pCount + gCount;
                        Navigator.pop(ctx);

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم تفعيل وبرمجة $total منبه ليوم $todayArabic بنجاح! 🔔 ($pCount حصة مدرسة + $gCount مجموعة دروس)',
                              ),
                              backgroundColor: const Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 6. Navigation Button: شاشة المنبه المتقدمة ⏰
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.alarm_on_rounded, size: 18, color: Color(0xFF00F2FE)),
                          label: const Text(
                            'شاشة المنبه وإدارة كافة الأيام ⏰',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            AlarmService.stopAudio();
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AlarmClockScreen(database: widget.database),
                              ),
                            ).then((_) => _loadData());
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Auto Notifications & Timetable Alarm Dialog ---
  void _showPeriodAlertsAndAlarmsDialog() {
    int minutesBefore = 0; // 0 = at start, 5 = 5 minutes before
    Set<String> selectedDays = Set<String>.from(_alertActiveDays);
    if (selectedDays.isEmpty) {
      selectedDays.add(_selectedDay);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          final selectedPeriods =
              _schoolPeriods
                  .where(
                    (p) => selectedDays.contains(p.dayOfWeek) && !p.isReserve,
                  )
                  .toList()
                ..sort((a, b) {
                  final dayA = _schoolWeekdays.indexOf(a.dayOfWeek);
                  final dayB = _schoolWeekdays.indexOf(b.dayOfWeek);
                  if (dayA != dayB) return dayA.compareTo(dayB);
                  return a.periodNumber.compareTo(b.periodNumber);
                });

          final isAllSelected = selectedDays.length == _schoolWeekdays.length;

          return Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFBBF24,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Color(0xFFFBBF24),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'تنبيهات ومنبهات الحصص الذكية ⏰🔔',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 1. Multi-Day Selection Header & Chips (اختيار يوم محدد أو عدة أيام)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF141E33)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF223147)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'حدد الأيام المراد ضبط المنبه والتنبيه لها:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {
                                setSheetState(() {
                                  if (isAllSelected) {
                                    selectedDays = {_selectedDay};
                                  } else {
                                    selectedDays = Set<String>.from(
                                      _schoolWeekdays,
                                    );
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isAllSelected
                                      ? const Color(
                                          0xFF00F2FE,
                                        ).withValues(alpha: 0.2)
                                      : const Color(0xFF00F2FE),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isAllSelected
                                      ? 'إلغاء تحديد الكل'
                                      : '⚡ تحديد كل الأيام',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: isAllSelected
                                        ? const Color(0xFF00F2FE)
                                        : const Color(0xFF0B1120),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _schoolWeekdays.map((day) {
                            final isSel = selectedDays.contains(day);
                            final countForDay = _schoolPeriods
                                .where(
                                  (p) => p.dayOfWeek == day && !p.isReserve,
                                )
                                .length;

                            return FilterChip(
                              label: Text(
                                '$day ($countForDay)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: isSel
                                      ? const Color(0xFF0B1120)
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.black87),
                                ),
                              ),
                              selected: isSel,
                              selectedColor: const Color(0xFF00F2FE),
                              checkmarkColor: const Color(0xFF0B1120),
                              backgroundColor: isDark
                                  ? const Color(0xFF1E293B)
                                  : Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isSel
                                      ? const Color(0xFF00F2FE)
                                      : (isDark
                                            ? const Color(0xFF334155)
                                            : const Color(0xFFCBD5E1)),
                                ),
                              ),
                              onSelected: (val) {
                                setSheetState(() {
                                  if (val) {
                                    selectedDays.add(day);
                                  } else {
                                    if (selectedDays.length > 1) {
                                      selectedDays.remove(day);
                                    }
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 14,
                              color: Color(0xFF00F2FE),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'تم تحديد: ${selectedDays.length} أيام (${selectedPeriods.length} حصة مجدولة)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00F2FE),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Automatic Notifications Switch
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF141E33)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF223147)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        'تنبيهات الحصص التلقائية (إشعارات)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      subtitle: Text(
                        'يرسل إشعاراً قبل بداية الحصة بـ 5 دقائق، وعند البداية، وعند نهاية الحصة للأيام المحددة أعلاه (${selectedDays.join("، ")}).',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      value: _autoPeriodAlerts,
                      activeThumbColor: const Color(0xFF00F2FE),
                      onChanged: (val) async {
                        setState(() {
                          _autoPeriodAlerts = val;
                          _alertActiveDays = Set<String>.from(selectedDays);
                        });
                        setSheetState(() {});
                        await widget.database.setSetting(
                          'school_auto_period_alerts',
                          val ? 'true' : 'false',
                        );
                        await widget.database.setSetting(
                          'school_alarm_selected_days',
                          jsonEncode(selectedDays.toList()),
                        );
                        if (val) {
                          await NotificationService.requestPermissions();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Set Phone Alarms Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.alarm_rounded,
                              color: Color(0xFFF59E0B),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'ضبط منبه هاتف أوتوماتيكي للحصص ⏰',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                                color: Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'يتم ضبط منبه أسبوعي في تطبيق الساعة لكل حصة في الأيام المحددة، ويستمر بالتكرار أسبوعيًا.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 10),

                        // Alarm Timing Option
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'موعد رنين المنبه:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                ChoiceChip(
                                  label: const Text(
                                    'في موعد الحصة بالضبط',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  selected: minutesBefore == 0,
                                  selectedColor: const Color(0xFFF59E0B),
                                  onSelected: (val) =>
                                      setSheetState(() => minutesBefore = 0),
                                ),
                                ChoiceChip(
                                  label: const Text(
                                    'قبلها بـ 5 دقائق',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  selected: minutesBefore == 5,
                                  selectedColor: const Color(0xFFF59E0B),
                                  onSelected: (val) =>
                                      setSheetState(() => minutesBefore = 5),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Action Button: Set Alarms for Selected Days
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B),
                              foregroundColor: const Color(0xFF0B1120),
                              minimumSize: const Size.fromHeight(46),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.alarm_add_rounded, size: 20),
                            label: Text(
                              selectedDays.length == 1
                                  ? 'ضبط منبهات يوم ${selectedDays.first} (${selectedPeriods.length} حصة) ⚡'
                                  : 'ضبط منبهات ${selectedDays.length} أيام (${selectedPeriods.length} حصة) ⚡',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            onPressed: selectedPeriods.isEmpty
                                ? null
                                : () async {
                                    // Save selected days preference
                                    setState(
                                      () => _alertActiveDays = Set<String>.from(
                                        selectedDays,
                                      ),
                                    );
                                    await widget.database.setSetting(
                                      'school_alarm_selected_days',
                                      jsonEncode(selectedDays.toList()),
                                    );

                                    final count =
                                        await AlarmService.syncDayPeriodAlarms(
                                          dayPeriods: selectedPeriods,
                                          minutesBefore: minutesBefore,
                                          useSystemClock: _syncToSystemClockApp,
                                          soundTone: _currentAlarmTone,
                                        );
                                    Navigator.pop(ctx);
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'تم ضبط $count منبه في تطبيق الساعة للأيام المختارة (${selectedDays.join("، ")}).',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          backgroundColor: const Color(
                                            0xFF10B981,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Open Clock App & Test Notification Row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(
                            Icons.alarm_on_rounded,
                            size: 18,
                            color: Color(0xFF00F2FE),
                          ),
                          label: const Text(
                            'شاشة المنبه الداخلي ⏰',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AlarmClockScreen(database: widget.database),
                              ),
                            ).then((_) => _loadData());
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(
                            Icons.notifications_active_outlined,
                            size: 18,
                            color: Color(0xFF10B981),
                          ),
                          label: const Text(
                            'تجربة تنبيه الحصة',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () async {
                            await NotificationService.showPeriodStartAlert(
                              periodName: 'الحصة الأولى (تجربة)',
                              className: '1/1',
                              subject: 'رياضيات',
                              room: 'معمل 1',
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'تم إرسال إشعار تجريبي بنجاح! تفقد شريط الإشعارات أعلى الشاشة 🔔',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Color(0xFF10B981),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SettingsTabSaveButtonWidget extends StatefulWidget {
  final String label;
  final FutureOr<void> Function() onSave;
  final String? successMessage;
  final void Function(String msg)? onNotify;

  const _SettingsTabSaveButtonWidget({
    required this.label,
    required this.onSave,
    this.successMessage,
    this.onNotify,
  });

  @override
  State<_SettingsTabSaveButtonWidget> createState() =>
      _SettingsTabSaveButtonWidgetState();
}

class _SettingsTabSaveButtonWidgetState
    extends State<_SettingsTabSaveButtonWidget> {
  bool _isSaved = false;
  bool _isSaving = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _handlePress() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    HapticFeedback.heavyImpact();

    try {
      await widget.onSave();
      if (!mounted) return;

      final msg = widget.successMessage ?? 'تم حفظ الإعدادات بنجاح! ✓';
      widget.onNotify?.call(msg);

      setState(() {
        _isSaving = false;
        _isSaved = true;
      });

      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) {
          setState(() => _isSaved = false);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaved = _isSaved;
    return Container(
      margin: const EdgeInsets.only(top: 20, bottom: 8),
      width: double.infinity,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: (isSaved
                      ? const Color(0xFF10B981)
                      : const Color(0xFF00F2FE))
                  .withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: isSaved
                ? const Color(0xFF10B981)
                : const Color(0xFF00F2FE),
            foregroundColor: isSaved
                ? Colors.white
                : const Color(0xFF0B1120),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF0B1120),
                  ),
                )
              : Icon(
                  isSaved
                      ? Icons.check_circle_rounded
                      : Icons.save_rounded,
                  size: 20,
                  color: isSaved ? Colors.white : const Color(0xFF0B1120),
                ),
          label: Text(
            _isSaving
                ? 'جارٍ الحفظ...'
                : (isSaved ? 'تم الحفظ بنجاح! ✓' : widget.label),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isSaved ? Colors.white : const Color(0xFF0B1120),
            ),
          ),
          onPressed: _isSaving ? null : _handlePress,
        ),
      ),
    );
  }
}

// =========================================================================
// --- TAB 1: تعديل وتحديث الجدول المدرسي بالذكاء الاصطناعي (AI 3-STARS) ---
// =========================================================================
class _SettingsAiTimetableTabWidget extends StatefulWidget {
  final DatabaseService database;
  final Map<int, ({String end, String start})> periodTimings;
  final List<String> schoolWeekdays;
  final String initialDay;
  final Future<void> Function() onTimetableUpdated;
  final void Function(String msg)? onNotify;

  const _SettingsAiTimetableTabWidget({
    required this.database,
    required this.periodTimings,
    required this.schoolWeekdays,
    required this.initialDay,
    required this.onTimetableUpdated,
    this.onNotify,
  });

  @override
  State<_SettingsAiTimetableTabWidget> createState() =>
      _SettingsAiTimetableTabWidgetState();
}

class _SettingsAiTimetableTabWidgetState
    extends State<_SettingsAiTimetableTabWidget> {
  final TextEditingController _textController = TextEditingController();
  bool _isSingleDayOnly = false;
  late String _selectedDay;
  AiTimetableParseResult? _parseResult;
  bool _isProcessing = false;
  bool _hasBackup = false;
  bool _showPeriodsPreviewList = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDay;
    if (!widget.schoolWeekdays.contains(_selectedDay)) {
      _selectedDay = widget.schoolWeekdays.first;
    }
    _checkBackup();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _checkBackup() async {
    final has = await widget.database.hasSchoolTimetableBackup();
    if (mounted) setState(() => _hasBackup = has);
  }

  void _reevaluate() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _parseResult = null);
    } else {
      setState(() {
        _parseResult = AiTimetableParserService.parse(
          text,
          periodTimings: widget.periodTimings,
        );
      });
    }
  }

  Future<void> _executeImport() async {
    final rawInput = _textController.text.trim();
    if (rawInput.isEmpty) {
      HapticFeedback.lightImpact();
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
              SizedBox(width: 8),
              Text('تنبيه'),
            ],
          ),
          content: const Text(
            'يرجى لصق كود أو نص الجدول الناتج من Gemini أولاً في المربع المخصص قبل الضغط على تنفيذ.',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);
    final result = AiTimetableParserService.parse(
      rawInput,
      periodTimings: widget.periodTimings,
    );
    setState(() {
      _parseResult = result;
      _isProcessing = false;
    });

    if (!result.isSuccess || result.periods.isEmpty) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 24),
                SizedBox(width: 8),
                Text('فشل تحديث الجدول ❌', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تعذر قراءة أو استخراج الحصص من النص المدخل.',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    result.errorMessage ?? 'تنسيق البيانات غير مطابق للـ JSON المطلوب.',
                    style: const TextStyle(fontSize: 11.5, color: Colors.redAccent),
                  ),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      }
      return;
    }

    List<SchoolPeriodModel> targetPeriods;
    if (_isSingleDayOnly) {
      targetPeriods = result.periods.where((p) => p.dayOfWeek == _selectedDay).toList();
      if (targetPeriods.isEmpty) {
        final switchScope = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('لم يتم العثور على حصص لهذا اليوم'),
            content: Text(
              'النص يحتوي على ${result.periods.length} حصة لأيام أخرى، ولكن لا توجد حصص مسجلة ليوم $_selectedDay.\n\nهل تريد استبدال الجدول لكامل الأسبوع بدلاً من يوم واحد فقط؟',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('نعم، لكامل الأسبوع')),
            ],
          ),
        );
        if (switchScope == true) {
          setState(() => _isSingleDayOnly = false);
          targetPeriods = result.periods;
        } else {
          return;
        }
      }
    } else {
      targetPeriods = result.periods;
    }

    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text('تأكيد تحديث الجدول'),
          ],
        ),
        content: Text(
          _isSingleDayOnly
              ? 'سيتم استبدال جدول يوم $_selectedDay فقط بـ ${targetPeriods.length} حصص جديدة.\n\nسيتم حفظ نسخة احتياطية من جدولك الحالي تلقائياً للرجوع في أي وقت.'
              : 'سيتم استبدال جدول الحصص بالكامل لجميع الأيام بـ ${targetPeriods.length} حصة جديدة.\n\nسيتم حفظ نسخة احتياطية من جدولك الحالي تلقائياً للرجوع في أي وقت.',
          style: const TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('تأكيد وتنفيذ 🚀'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      await widget.database.backupSchoolTimetable();
      final count = await widget.database.applyAiSchoolTimetableImport(
        targetPeriods,
        targetDayOnly: _isSingleDayOnly ? _selectedDay : null,
      );
      await widget.onTimetableUpdated();
      await _checkBackup();

      final successMsg = _isSingleDayOnly
          ? 'تم تحديث جدول يوم $_selectedDay بنجاح ($count حصة)! 🚀'
          : 'تم تحديث الجدول المدرسي بالكامل بنجاح ($count حصة)! 🚀';
      widget.onNotify?.call(successMsg);

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _textController.clear();
          _parseResult = null;
        });

        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 26),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تم تحديث الجدول بنجاح! 🚀',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Text(
              _isSingleDayOnly
                  ? 'تم بنجاح تحديث جدول يوم $_selectedDay وإضافة $count حصة جديدة في الجدول المدرسي.'
                  : 'تم بنجاح تحديث الجدول المدرسي بالكامل وإضافة $count حصة جديدة لجميع الأيام.',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                onPressed: () => Navigator.pop(c),
                child: const Text('حسناً 👍'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('فشل تحديث الجدول ❌'),
              ],
            ),
            content: Text('حدث خطأ أثناء تطبيق الجدول:\n$e'),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(c),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    List<SchoolPeriodModel> activePeriods = [];
    if (_parseResult != null && _parseResult!.isSuccess) {
      if (_isSingleDayOnly) {
        activePeriods = _parseResult!.periods
            .where((p) => p.dayOfWeek == _selectedDay)
            .toList();
      } else {
        activePeriods = _parseResult!.periods;
      }
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // === STEP 1: البرومبت والربط مع Gemini ===
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B).withValues(alpha: 0.7)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'الخطوة الأولى: جهّز البيانات من Gemini',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'صوّر جدولك الورقي بالموبايل، ثم انسخ البرومبت بالزر أدناه وأرسل الصورة والبرومبت لشات Gemini:',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text(
                            'نسخ برومبت Gemini 📋',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Clipboard.setData(
                              const ClipboardData(
                                text: AiTimetableParserService.geminiPromptTemplate,
                              ),
                            );
                            widget.onNotify?.call('تم نسخ برومبت Gemini بنجاح! الصقه في شات Gemini مع صورة الجدول.');
                          },
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? const Color(0xFF818CF8)
                                : const Color(0xFF4F46E5),
                            side: BorderSide(
                              color: isDark
                                  ? const Color(0xFF6366F1)
                                  : const Color(0xFF818CF8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: const Text(
                            'فتح Gemini ↗️',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () async {
                            final uri = Uri.parse('https://gemini.google.com/app');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // === STEP 2: تحديد نطاق التحديث + لصق الرد ===
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B).withValues(alpha: 0.7)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F2FE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '2',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'الخطوة الثانية: الصق رد Gemini وحدد النطاق',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Scope Switch: Entire Week vs Single Day
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(
                              child: Text('كامل الأسبوع 🔄', style: TextStyle(fontSize: 11.5)),
                            ),
                            selected: !_isSingleDayOnly,
                            onSelected: (sel) {
                              if (sel) {
                                setState(() {
                                  _isSingleDayOnly = false;
                                  _reevaluate();
                                });
                              }
                            },
                            selectedColor: const Color(0xFF6366F1),
                            labelStyle: TextStyle(
                              color: !_isSingleDayOnly
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(
                              child: Text('يوم محدد فقط 📅', style: TextStyle(fontSize: 11.5)),
                            ),
                            selected: _isSingleDayOnly,
                            onSelected: (sel) {
                              if (sel) {
                                setState(() {
                                  _isSingleDayOnly = true;
                                  _reevaluate();
                                });
                              }
                            },
                            selectedColor: const Color(0xFF00F2FE),
                            labelStyle: TextStyle(
                              color: _isSingleDayOnly
                                  ? Colors.black
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (_isSingleDayOnly) ...[
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: widget.schoolWeekdays.map((day) {
                            final isSel = _selectedDay == day;
                            return Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: ChoiceChip(
                                label: Text(day, style: const TextStyle(fontSize: 11)),
                                selected: isSel,
                                onSelected: (sel) {
                                  if (sel) {
                                    setState(() {
                                      _selectedDay = day;
                                      _reevaluate();
                                    });
                                  }
                                },
                                selectedColor: const Color(0xFF00F2FE),
                                labelStyle: TextStyle(
                                  color: isSel
                                      ? Colors.black
                                      : (isDark ? Colors.white70 : Colors.black87),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Paste input text box
                    TextField(
                      controller: _textController,
                      maxLines: 5,
                      minLines: 3,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'الصق كود الـ JSON أو النص الناتج من Gemini هنا...',
                        hintTextDirection: TextDirection.rtl,
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.grey.shade500,
                          fontSize: 11.5,
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0B1120) : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF6366F1),
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (_) => _reevaluate(),
                    ),
                    const SizedBox(height: 8),

                    // Quick Buttons: Paste, Analyze & Clear
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.paste_rounded, size: 16),
                          label: const Text('لصق من الحافظة 📋', style: TextStyle(fontSize: 11)),
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            if (data?.text != null && data!.text!.trim().isNotEmpty) {
                              _textController.text = data.text!;
                              _reevaluate();
                            }
                          },
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.search_rounded, size: 16),
                          label: const Text('فحص وتحليل الكود 🔍', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _reevaluate();
                          },
                        ),
                        if (_textController.text.isNotEmpty)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            ),
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            label: const Text('مسح', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              _textController.clear();
                              _reevaluate();
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // === STEP 3: نتيجة الفحص والتحليل ===
              if (_parseResult != null) ...[
                if (_parseResult!.isSuccess)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'تم التعرف على ${_parseResult!.totalPeriods} حصة بنجاح!',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _parseResult!.periodsPerDay.entries.map((e) {
                            final isTarget = _isSingleDayOnly && e.key == _selectedDay;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isTarget
                                    ? const Color(0xFF00F2FE)
                                    : (isDark ? const Color(0xFF1E293B) : Colors.white),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isTarget ? const Color(0xFF00F2FE) : Colors.grey.shade400,
                                ),
                              ),
                              child: Text(
                                '${e.key}: ${e.value} حصص',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: isTarget
                                      ? Colors.black
                                      : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        if (_isSingleDayOnly && activePeriods.isEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'تنبيه: لم يتم العثور على حصص خاصة بيوم $_selectedDay في البيانات المدخلة.',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            setState(() => _showPeriodsPreviewList = !_showPeriodsPreviewList);
                          },
                          child: Row(
                            children: [
                              Text(
                                _showPeriodsPreviewList
                                    ? 'إخفاء تفاصيل الحصص ▲'
                                    : 'عرض تفاصيل الحصص (${activePeriods.length} حصة) ▼',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF6366F1),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_showPeriodsPreviewList && activePeriods.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade700),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.all(8),
                              itemCount: activePeriods.length,
                              separatorBuilder: (_, __) => const Divider(height: 6),
                              itemBuilder: (_, idx) {
                                final p = activePeriods[idx];
                                return Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${p.periodNumber}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${p.dayOfWeek} • ${p.subject} • ${p.className}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${p.startTime} - ${p.endTime}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _parseResult!.errorMessage ??
                                'تعذر استخراج الحصص من النص المدخل. يرجى التأكد من نسخ الـ JSON بشكل صحيح.',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
              ],

              // Backup banner
              if (_hasBackup) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history_rounded, size: 16, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'توجد نسخة احتياطية سابقة محفوظة يمكنك استرجاعها في أي وقت.',
                          style: TextStyle(fontSize: 10.5),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('استرجاع الجدول السابق'),
                              content: const Text('هل تريد استرجاع النسخة السابقة من الجدول المدرسي؟'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('نعم، استرجع')),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            final restored = await widget.database.restoreSchoolTimetableBackup();
                            if (restored > 0) {
                              await widget.onTimetableUpdated();
                              await _checkBackup();
                              widget.onNotify?.call('تم استرجاع الجدول السابق بنجاح ↩️');
                            }
                          }
                        },
                        child: const Text(
                          'تراجع الآن ↩️',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),

        // Bottom Action Bar ("نفذ")
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141E33) : const Color(0xFFF8FAFC),
            border: Border(
              top: BorderSide(
                color: isDark ? const Color(0xFF223147) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.rocket_launch_rounded, size: 18),
                  label: Text(
                    _isProcessing ? 'جارٍ تطبيق الجدول...' : 'نفذ (تحديث الجدول المدرسي) 🚀',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isProcessing ? null : _executeImport,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

