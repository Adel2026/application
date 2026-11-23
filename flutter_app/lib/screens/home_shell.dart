import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_locale.dart';
import '../core/database/database_service.dart';
import '../core/google_webhook_service.dart';
import '../core/security_service.dart';
import '../core/theme_controller.dart';
import 'alarm_clock_screen.dart';
import 'certificates_screen.dart';
import 'curriculum_screen.dart';
import 'dashboard_screen.dart';
import 'exams_screen.dart';
import 'finances_screen.dart';
import 'groups_screen.dart';
import 'profile_screen.dart';
import 'reports_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import 'students_screen.dart';
import 'timetable_screen.dart';
import 'today_attendance_screen.dart';
import 'whatsapp_hub_screen.dart';
import 'teacher_broadcast_screen.dart';
import 'teacher_messages_hub_screen.dart';
import 'teacher_student_app_control_screen.dart';
import 'teacher_materials_hub_screen.dart';
import 'rewards_manager_screen.dart';
import '../core/academy_communication_service.dart';
import '../core/teacher_update_service.dart';
import '../models/group_model.dart';
import '../models/school_period_model.dart';
import '../services/home_widget_service.dart';

class AppAlertItem {
  final String id;
  final String title;
  final String body;
  final IconData icon;
  final Color iconColor;
  final String badgeText;
  final String targetTab;
  final DateTime timestamp;

  const AppAlertItem({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.iconColor,
    required this.badgeText,
    required this.targetTab,
    required this.timestamp,
  });
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.database,
    required this.themeController,
  });

  final DatabaseService database;
  final ThemeController themeController;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _bellKey = GlobalKey();
  int selectedIndex = 0;
  String centerName = 'أكاديمية المستقبل';
  String teacherName = 'أ. أحمد السيد';
  String teacherAvatar = '👨‍🏫';
  String? customLogoPath;

  DateTime? _lastBackPressTime;
  List<String> _activeDockItemIds = ['home', 'curriculum', 'whatsapp', 'menu'];
  static const List<Map<String, dynamic>> _allAvailableQuickItems = [
    {
      'id': 'students',
      'title': 'الطلاب',
      'icon': Icons.person_outline_rounded,
      'isDefault': true,
    },
    {
      'id': 'groups',
      'title': 'المجموعات',
      'icon': Icons.groups_outlined,
      'isDefault': true,
    },
    {
      'id': 'timetable',
      'title': 'جدول الحصص',
      'icon': Icons.calendar_month_rounded,
      'isDefault': true,
    },
    {
      'id': 'attendance',
      'title': 'التحضير',
      'icon': Icons.calendar_month_outlined,
      'isDefault': true,
    },
    {
      'id': 'exams',
      'title': 'الامتحانات',
      'icon': Icons.assignment_outlined,
      'isDefault': true,
    },
    {
      'id': 'finances',
      'title': 'المالية',
      'icon': Icons.account_balance_wallet_outlined,
      'isDefault': true,
    },
    {
      'id': 'whatsapp',
      'title': 'واتساب',
      'icon': Icons.chat_bubble_outline_rounded,
      'isDefault': true,
    },
    {
      'id': 'curriculum',
      'title': 'المناهج',
      'icon': Icons.menu_book_rounded,
      'isDefault': true,
    },
    {
      'id': 'reports',
      'title': 'التقارير',
      'icon': Icons.insights_rounded,
      'isDefault': true,
    },
    {
      'id': 'certificates',
      'title': 'الشهادات',
      'icon': Icons.workspace_premium_rounded,
      'isDefault': true,
    },
    {
      'id': 'scanner',
      'title': 'ماسح QR',
      'icon': Icons.qr_code_scanner_rounded,
      'isDefault': true,
    },
    {
      'id': 'alarm',
      'title': 'ساعة المنبه',
      'icon': Icons.alarm_rounded,
      'isDefault': false,
    },
    {
      'id': 'profile',
      'title': 'الملف الشخصي',
      'icon': Icons.badge_outlined,
      'isDefault': false,
    },
    {
      'id': 'settings',
      'title': 'الإعدادات',
      'icon': Icons.tune_rounded,
      'isDefault': true,
    },
  ];

  List<String> _customQuickItemIds = [
    'students',
    'groups',
    'timetable',
    'attendance',
    'exams',
    'finances',
    'whatsapp',
    'curriculum',
    'reports',
    'certificates',
    'scanner',
    'settings',
  ];

  Future<void> _loadQuickMenuConfig() async {
    final raw = await widget.database.getSetting('quick_menu_custom_items', defaultValue: '');
    if (raw.isNotEmpty) {
      try {
        final decoded = List<String>.from(jsonDecode(raw) as List);
        if (decoded.isNotEmpty) {
          if (mounted) setState(() => _customQuickItemIds = decoded);
          return;
        }
      } catch (_) {}
    }
  }

  Future<void> _saveQuickMenuConfig(List<String> ids) async {
    setState(() => _customQuickItemIds = ids);
    await widget.database.setSetting('quick_menu_custom_items', jsonEncode(ids));
  }
  double _dockIconSize = 23.0;
  List<Widget> _screens = [];
  StreamSubscription<DataChangeEvent>? _dataSub;
  Timer? _scheduledBackupTimer;
  Timer? _alertsDebounceTimer;

  List<AppAlertItem> _activeAlerts = [];
  Set<String> _readAlertIds = {};
  Set<String> _dismissedAlertIds = {};
  int get _unreadAlertsCount =>
      _activeAlerts.where((a) => !_readAlertIds.contains(a.id)).length;

  bool _isAppLocked = false;
  bool _isAuthenticatingLock = false;
  DateTime? _pausedTime;

  Future<void> _checkAppLock({bool isResume = false}) async {
    final lockEnabled = await widget.database.getSetting(
      'security_app_lock_enabled',
      defaultValue: 'false',
    );
    if (lockEnabled != 'true') {
      if (_isAppLocked && mounted) {
        setState(() => _isAppLocked = false);
      }
      return;
    }

    if (!mounted) return;
    if (!_isAppLocked) {
      setState(() => _isAppLocked = true);
    }

    if (_isAuthenticatingLock) return;
    _isAuthenticatingLock = true;

    try {
      final authenticated = await SecurityService.authenticate(
        context: context,
        database: widget.database,
        reason: 'التطبيق مقفل لحماية بيانات السنتر والطلاب. يرجى تأكيد الهوية.',
      );

      if (mounted) {
        setState(() {
          _isAppLocked = !authenticated;
        });
      }
    } catch (e) {
      debugPrint('App lock error: $e');
    } finally {
      // Allow Android system dialog to completely dismiss before accepting new lifecycle triggers
      await Future.delayed(const Duration(milliseconds: 600));
      _isAuthenticatingLock = false;
    }
  }

  /// Manually lock the app immediately from the drawer or quick action
  Future<void> _lockAppManually() async {
    try {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {}
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    await widget.database.setSetting('security_app_lock_enabled', 'true');
    if (mounted) {
      setState(() {
        _isAppLocked = true;
      });
    }
  }

  /// Unlock from lock screen using biometrics or fallback
  Future<void> _unlockWithBiometrics() async {
    if (_isAuthenticatingLock) return;
    _isAuthenticatingLock = true;

    try {
      final authenticated = await SecurityService.authenticate(
        context: context,
        database: widget.database,
        reason: 'التطبيق مقفل لحماية بيانات السنتر والطلاب. يرجى تأكيد الهوية.',
      );

      if (mounted && authenticated) {
        setState(() {
          _isAppLocked = false;
        });
      }
    } catch (e) {
      debugPrint('Biometric unlock error: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 600));
      _isAuthenticatingLock = false;
    }
  }

  static const Map<String, ({IconData icon, IconData activeIcon, String title})>
  _dockItemMeta = {
    'home': (
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      title: 'الرئيسية',
    ),
    'curriculum': (
      icon: Icons.menu_book_outlined,
      activeIcon: Icons.menu_book_rounded,
      title: 'المناهج',
    ),
    'whatsapp': (
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      title: 'واتساب',
    ),
    'menu': (
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
      title: 'القائمة',
    ),
    'timetable': (
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month_rounded,
      title: 'جدول الحصص',
    ),
    'exams': (
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment_rounded,
      title: 'الامتحانات',
    ),
    'students': (
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      title: 'الطلاب',
    ),
    'groups': (
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups_rounded,
      title: 'المجموعات',
    ),
    'attendance': (
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check_rounded,
      title: 'التحضير',
    ),
    'finances': (
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet_rounded,
      title: 'الخزينة',
    ),
    'reports': (
      icon: Icons.insights_rounded,
      activeIcon: Icons.insights_rounded,
      title: 'التقارير',
    ),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _rebuildScreens(_activeDockItemIds);
    _loadHeaderInfo();
    _loadUiConfig();
    _loadQuickMenuConfig();
    _loadAlerts();
    _checkAppLock();
    // Start listening for incoming student messages with instant sound notification
    AcademyCommunicationService.instance.startListeningForStudentMessages();
    widget.themeController.addListener(_onThemeOrConfigChanged);
    _dataSub = widget.database.onDataChanged.listen((event) {
      if (mounted) {
        _scheduleLoadAlerts();
        HomeWidgetService.updateNextSessionWidget(database: widget.database);
        if (event == DataChangeEvent.settings || event == DataChangeEvent.all) {
          _loadHeaderInfo();
          _loadUiConfig();
        }
      }
    });

    // Initialize Home Screen Widget integration
    HomeWidgetService.initialize(onWidgetClick: _handleWidgetLaunch);
    HomeWidgetService.updateNextSessionWidget(database: widget.database);

    // Check scheduled Google Drive cloud backup 10 seconds after app startup
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        GoogleWebhookService.checkAndRunScheduledBackup(widget.database);
      }
    });
    // Recurring check every 15 minutes while app is running
    _scheduledBackupTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (mounted) {
        GoogleWebhookService.checkAndRunScheduledBackup(widget.database);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForDataMigrationNotice();
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          TeacherUpdateService.instance.checkForUpdate(context);
        }
      });
    });
  }

  Future<void> _checkForDataMigrationNotice() async {
    if (!mounted) return;
    final notice = await widget.database.checkPendingDataMigrationNotice();
    if (notice != null && mounted) {
      await widget.database.clearPendingDataMigrationNotice();
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                notice['is_warning'] == true
                    ? Icons.warning_amber_rounded
                    : Icons.shield_outlined,
                color: notice['is_warning'] == true
                    ? Colors.amber
                    : const Color(0xFF10B981),
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  notice['title']?.toString() ?? 'تنبيه أمان البيانات',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            notice['message']?.toString() ?? '',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('فهمت ذلك ✓'),
            ),
          ],
        ),
      );
    }
  }

  final Map<String, Widget> _screenCache = {};

  void _rebuildScreens(List<String> ids) {
    _activeDockItemIds = ids;
    _screens = ids
        .map(
          (id) => _screenCache.putIfAbsent(id, () => _getScreenForDockId(id)),
        )
        .toList();
    if (selectedIndex >= _screens.length) {
      selectedIndex = 0;
    }
  }

  Widget _getScreenForDockId(String id) {
    switch (id) {
      case 'home':
        return DashboardScreen(
          database: widget.database,
          onNavigateTab: (target) => _navigateToTab(target),
          onNavConfigChanged: _loadUiConfig,
        );
      case 'curriculum':
        return CurriculumScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      case 'whatsapp':
        return WhatsAppHubScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      case 'menu':
        return const SizedBox.shrink();
      case 'timetable':
        return TimetableScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      case 'exams':
        return ExamsScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      case 'students':
        return StudentsScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      case 'groups':
        return GroupsScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      case 'attendance':
        return TodayAttendanceScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      case 'finances':
        return FinancesScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      case 'reports':
        return ReportsScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      case 'certificates':
        return CertificatesScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      default:
        return DashboardScreen(
          database: widget.database,
          onNavigateTab: (target) => _navigateToTab(target),
          onNavConfigChanged: _loadUiConfig,
        );
    }
  }

  void _onThemeOrConfigChanged() {
    if (mounted) {
      _loadUiConfig();
      _loadHeaderInfo();
    }
  }

  void _handleWidgetLaunch(Uri? uri) {
    if (uri == null || !mounted) return;
    try {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {}
    if (uri.host == 'session' || uri.path.contains('session')) {
      _navigateToTab('attendance');
    } else {
      _navigateToTab('home');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _loadAlerts();
      HomeWidgetService.updateNextSessionWidget(database: widget.database);
      GoogleWebhookService.checkAndRunScheduledBackup(widget.database);

      // If we resumed from our own auth prompt, ignore this lifecycle change
      if (_isAuthenticatingLock) return;

      if (_pausedTime != null) {
        final elapsed = DateTime.now().difference(_pausedTime!);
        _pausedTime = null;
        // Only lock if the app was away in background for more than 5 seconds
        if (elapsed > const Duration(seconds: 5)) {
          widget.database
              .getSetting('security_app_lock_enabled', defaultValue: 'false')
              .then((val) {
                if (val == 'true' && mounted) {
                  _checkAppLock(isResume: true);
                }
              });
        }
      }
    } else if (state == AppLifecycleState.paused) {
      // Only record pause time if not currently in auth prompt
      if (!_isAuthenticatingLock) {
        _pausedTime = DateTime.now();
      }
    }
  }

  @override
  void dispose() {
    _alertsDebounceTimer?.cancel();
    _scheduledBackupTimer?.cancel();
    _dataSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.themeController.removeListener(_onThemeOrConfigChanged);
    super.dispose();
  }

  void _scheduleLoadAlerts() {
    _alertsDebounceTimer?.cancel();
    _alertsDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _loadAlerts();
      }
    });
  }

  Future<void> _loadHeaderInfo() async {
    final settings = await Future.wait<String>([
      widget.database.getSetting(
        'center_name',
        defaultValue: 'أكاديمية المستقبل',
      ),
      widget.database.getSetting('teacher_name', defaultValue: 'أ. أحمد السيد'),
      widget.database.getSetting('teacher_avatar', defaultValue: '👨‍🏫'),
      widget.database.getSetting('teacher_photo_path', defaultValue: ''),
      widget.database.getSetting('custom_logo_path', defaultValue: ''),
    ]);
    final cName = settings[0];
    final tName = settings[1];
    final avatar = settings[2];
    final tPhoto = settings[3];
    final cLogo = tPhoto.isNotEmpty ? tPhoto : settings[4];
    if (mounted) {
      setState(() {
        centerName = cName;
        teacherName = tName;
        teacherAvatar = avatar;
        customLogoPath = cLogo.isNotEmpty ? cLogo : null;
      });
    }
  }

  Future<void> _loadUiConfig() async {
    final settings = await Future.wait<String>([
      widget.database.getSetting('bottom_dock_items', defaultValue: ''),
      widget.database.getSetting('bottom_dock_icon_size', defaultValue: '23'),
    ]);
    final savedDock = settings[0];
    List<String> ids = ['home', 'curriculum', 'whatsapp', 'menu'];
    if (savedDock.isNotEmpty) {
      try {
        final decoded = List<String>.from(jsonDecode(savedDock));
        decoded.remove('profile');
        if (decoded.length >= 2) {
          ids = decoded;
        }
      } catch (_) {}
    }
    final iconSz = double.tryParse(settings[1]) ?? 23.0;
    if (mounted) {
      setState(() {
        _dockIconSize = iconSz;
        _rebuildScreens(ids);
      });
    }
  }

  Future<void> _loadAlerts() async {
    try {
      // 0. Clean any duplicate exceptional sessions in the database
      try {
        await widget.database.cleanDuplicateExceptionalSessions();
      } catch (_) {}

      final savedReadStr = await widget.database.getSetting(
        'read_alert_ids',
        defaultValue: '',
      );
      final savedReadSet = savedReadStr
          .split(',')
          .where((s) => s.isNotEmpty)
          .toSet();

      final savedDismissedStr = await widget.database.getSetting(
        'dismissed_alert_ids',
        defaultValue: '',
      );
      final savedDismissedSet = savedDismissedStr
          .split(',')
          .where((s) => s.isNotEmpty)
          .toSet();

      final rawAlerts = await _generateRealAlerts();
      // Filter out dismissed alerts
      final alerts = rawAlerts
          .where((a) => !savedDismissedSet.contains(a.id))
          .toList();

      if (mounted) {
        setState(() {
          _readAlertIds = savedReadSet;
          _dismissedAlertIds = savedDismissedSet;
          _activeAlerts = alerts;
        });
      }
    } catch (_) {}
  }

  Future<void> _markAlertAsRead(String alertId) async {
    if (_readAlertIds.contains(alertId)) return;
    _readAlertIds.add(alertId);
    setState(() {});
    await widget.database.setSetting('read_alert_ids', _readAlertIds.join(','));
  }

  Future<void> _markAllAlertsAsRead() async {
    for (final a in _activeAlerts) {
      _readAlertIds.add(a.id);
    }
    setState(() {});
    await widget.database.setSetting('read_alert_ids', _readAlertIds.join(','));
  }

  Future<void> _dismissAlert(String alertId) async {
    _dismissedAlertIds.add(alertId);
    _activeAlerts.removeWhere((a) => a.id == alertId);
    setState(() {});
    await widget.database.setSetting(
      'dismissed_alert_ids',
      _dismissedAlertIds.join(','),
    );
  }

  Future<void> _dismissAllAlerts() async {
    for (final a in _activeAlerts) {
      _dismissedAlertIds.add(a.id);
      _readAlertIds.add(a.id);
    }
    _activeAlerts.clear();
    setState(() {});
    await Future.wait([
      widget.database.setSetting(
        'dismissed_alert_ids',
        _dismissedAlertIds.join(','),
      ),
      widget.database.setSetting(
        'read_alert_ids',
        _readAlertIds.join(','),
      ),
    ]);
  }

  Future<List<AppAlertItem>> _generateRealAlerts() async {
    final List<AppAlertItem> alerts = [];
    final now = DateTime.now();
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 1. حصص اليوم المجدولة للمجموعات النشطة ولم يتم رصد حضورها بعد
    try {
      final groups = await widget.database.getGroups();
      final dayNames = {
        DateTime.saturday: 'السبت',
        DateTime.sunday: 'الأحد',
        DateTime.monday: 'الاثنين',
        DateTime.tuesday: 'الثلاثاء',
        DateTime.wednesday: 'الأربعاء',
        DateTime.thursday: 'الخميس',
        DateTime.friday: 'الجمعة',
      };
      final todayArabic = dayNames[now.weekday] ?? '';
      final todayGroups = groups
          .where((g) => g.isActive && g.schedule.contains(todayArabic))
          .toList();

      for (final g in todayGroups) {
        final records = await widget.database.getGroupStudentsWithAttendance(
          groupId: g.id,
          date: dateStr,
        );
        // Do not alert if the group has 0 students enrolled
        if (records.isEmpty) continue;

        final hasAny = records.any((r) => r['attendance_status'] != null);
        if (!hasAny) {
          alerts.add(
            AppAlertItem(
              id: 'unmarked_group_${g.id}_$dateStr',
              title: 'حصة اليوم: ${g.name}',
              body: 'موعد الحصة ${g.schedule} • بانتظار رصد الحضور',
              icon: Icons.alarm_rounded,
              iconColor: const Color(0xFFF59E0B),
              badgeText: 'تحضير',
              targetTab: 'attendance',
              timestamp: now,
            ),
          );
        }
      }
    } catch (_) {}

    // 2. حصص استثنائية مجدولة اليوم (بدون تكرار ومع فحص الحضور)
    try {
      final exSessions = await widget.database.getExceptionalSessions(
        date: dateStr,
        status: 'active',
      );
      final seenGroupEx = <String>{};
      for (final ex in exSessions) {
        // Deduplicate duplicate scheduled sessions for the same group and time
        final dupKey = '${ex.groupId}_${ex.time}';
        if (seenGroupEx.contains(dupKey)) continue;
        seenGroupEx.add(dupKey);

        // Check if attendance is already taken for this group today
        final records = await widget.database.getGroupStudentsWithAttendance(
          groupId: ex.groupId,
          date: dateStr,
        );
        final hasAny = records.any((r) => r['attendance_status'] != null);
        if (hasAny) continue; // Attendance is already taken, no alert needed

        alerts.add(
          AppAlertItem(
            id: 'ex_session_${ex.id}_$dateStr',
            title: 'حصة استثنائية اليوم: ${ex.groupName}',
            body:
                '${ex.reasonLabel} • ${ex.time} (${ex.scale == "double" ? "دوبل 2x" : "فردية"})',
            icon: Icons.bolt_rounded,
            iconColor: const Color(0xFFD97706),
            badgeText: 'استثنائية',
            targetTab: 'attendance',
            timestamp: now,
          ),
        );
      }
    } catch (_) {}

    // 3. طلاب غائبون اليوم بانتظار إرسال تنبيهات واتساب
    try {
      final todayAtt = await widget.database.getAttendanceForDate(dateStr);
      final absentToday = todayAtt.where((a) => a.status == 'absent').toList();
      if (absentToday.isNotEmpty) {
        alerts.add(
          AppAlertItem(
            id: 'absent_alerts_$dateStr',
            title: 'تنبيهات غياب اليوم (${absentToday.length} طالب)',
            body:
                'يوجد طلاب تغيبوا اليوم، يمكنك إرسال تنبيهات واتساب لأولياء الأمور',
            icon: Icons.campaign_rounded,
            iconColor: const Color(0xFFEF4444),
            badgeText: 'واتساب',
            targetTab: 'whatsapp',
            timestamp: now,
          ),
        );
      }
    } catch (_) {}

    // 4. مستحقات واشتراكات متأخرة بالخزينة (للطلاب النشطين فقط)
    try {
      final students = await widget.database.getStudents();
      final overdue = students.where((s) => s.isActive && s.hasOutstandingPayment).toList();
      if (overdue.isNotEmpty) {
        alerts.add(
          AppAlertItem(
            id: 'overdue_fees_${now.month}_${now.year}',
            title: 'مستحقات واشتراكات متأخرة بالخزينة',
            body: 'يوجد ${overdue.length} طالب عليهم مبالغ بانتظار التحصيل',
            icon: Icons.account_balance_wallet_rounded,
            iconColor: const Color(0xFFE11D48),
            badgeText: 'المالية',
            targetTab: 'finances_debts',
            timestamp: now,
          ),
        );
      }
    } catch (_) {}

    // 5. اختبارات تم إنشاؤها ولم ترصد درجاتها بعد
    try {
      final exams = await widget.database.getExams();
      for (final ex in exams.take(2)) {
        final scores = await widget.database.getExamScoresForExam(ex.id);
        if (scores.isEmpty) {
          alerts.add(
            AppAlertItem(
              id: 'exam_unscored_${ex.id}',
              title: 'اختبار بانتظار رصد الدرجات: ${ex.title}',
              body: 'لم يتم رصد درجات الطلاب لهذا الاختبار بعد',
              icon: Icons.quiz_rounded,
              iconColor: const Color(0xFF8B5CF6),
              badgeText: 'امتحانات',
              targetTab: 'exams',
              timestamp: now,
            ),
          );
        }
      }
    } catch (_) {}

    return alerts;
  }

  void _navigateToTab(dynamic target) {
    if (target is int) {
      if (target >= 0 && target < _screens.length) {
        setState(() => selectedIndex = target);
      }
      return;
    }

    if (target is String) {
      final dockId = switch (target) {
        'dashboard' => 'home',
        'syllabus' || 'lessons' => 'curriculum',
        'messages' => 'whatsapp',
        _ => target,
      };
      if (dockId != 'menu') {
        final idx = _activeDockItemIds.indexOf(dockId);
        if (idx != -1) {
          setState(() => selectedIndex = idx);
          return;
        }
      }

      switch (target) {
        case 'dashboard':
        case 'home':
          final screen = _getScreenForId('dashboard');
          Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
          return;
        case 'curriculum':
        case 'syllabus':
        case 'lessons':
          final screen = _getScreenForId('curriculum');
          Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
          return;
        case 'whatsapp':
        case 'messages':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WhatsAppHubScreen(database: widget.database),
            ),
          ).then((_) => _loadHeaderInfo());
          return;
        case 'daily_report_send':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WhatsAppHubScreen(
                database: widget.database,
                initialCategory: ParentServiceCategory.holisticReport,
                promptDailyReportSend: true,
              ),
            ),
          ).then((_) => _loadHeaderInfo());
          return;
        case 'whatsapp_absence':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WhatsAppHubScreen(
                database: widget.database,
                initialCategory: ParentServiceCategory.absenceAlert,
              ),
            ),
          ).then((_) => _loadHeaderInfo());
          return;
        case 'whatsapp_reminder':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WhatsAppHubScreen(
                database: widget.database,
                initialCategory: ParentServiceCategory.sessionReminder,
              ),
            ),
          ).then((_) => _loadHeaderInfo());
          return;
        case 'whatsapp_payment':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WhatsAppHubScreen(
                database: widget.database,
                initialCategory: ParentServiceCategory.financialReceipt,
              ),
            ),
          ).then((_) => _loadHeaderInfo());
          return;
        case 'whatsapp_notebook':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WhatsAppHubScreen(
                database: widget.database,
                initialCategory: ParentServiceCategory.notebookBehavior,
              ),
            ),
          ).then((_) => _loadHeaderInfo());
          return;
        case 'whatsapp_followup':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WhatsAppHubScreen(
                database: widget.database,
                initialCategory: ParentServiceCategory.sessionFollowup,
              ),
            ),
          ).then((_) => _loadHeaderInfo());
          return;
        case 'whatsapp_exams':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WhatsAppHubScreen(
                database: widget.database,
                initialCategory: ParentServiceCategory.examScore,
              ),
            ),
          ).then((_) => _loadHeaderInfo());
          return;
        case 'whatsapp_cancellation':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WhatsAppHubScreen(
                database: widget.database,
                initialCategory: ParentServiceCategory.sessionCancellation,
              ),
            ),
          ).then((_) => _loadHeaderInfo());
          return;
        case 'finances_debts':
        case 'finances_overdue':
        case 'overdue_claims':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  FinancesScreen(database: widget.database, initialTabIndex: 1),
            ),
          ).then((_) => _loadHeaderInfo());
          return;
        case 'settings':
          _openSettingsTab(0);
          return;
        case 'profile':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(database: widget.database),
            ),
          ).then((_) => _loadHeaderInfo());
          return;
        default:
          final screen = _getScreenForId(target);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => screen),
          ).then((_) {
            _loadHeaderInfo();
          });
          return;
      }
    }
  }

  Widget _getScreenForId(String id) {
    switch (id) {
      case 'dashboard':
        return DashboardScreen(
          database: widget.database,
          onNavigateTab: (target) => _navigateToTab(target),
        );
      case 'students':
        return StudentsScreen(database: widget.database);
      case 'groups':
        return GroupsScreen(database: widget.database);
      case 'timetable':
        return TimetableScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      case 'attendance':
        return TodayAttendanceScreen(database: widget.database);
      case 'finances':
        return FinancesScreen(database: widget.database);
      case 'curriculum':
        return CurriculumScreen(database: widget.database);
      case 'exams':
        return ExamsScreen(database: widget.database);
      case 'scanner':
        return ScannerScreen(database: widget.database);
      case 'whatsapp':
        return WhatsAppHubScreen(database: widget.database);
      case 'reports':
        return ReportsScreen(database: widget.database);
      case 'certificates':
        return CertificatesScreen(
          database: widget.database,
          onBack: () => _navigateToTab('home'),
        );
      case 'settings':
        return SettingsScreen(
          database: widget.database,
          themeController: widget.themeController,
        );
      default:
        return DashboardScreen(
          database: widget.database,
          onNavigateTab: (target) => _navigateToTab(target),
        );
    }
  }

  Widget _buildAppLockScreen(bool isDark) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF070E1A)
            : const Color(0xFFF1F5F9),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    centerName.isNotEmpty ? centerName : 'سنتر أستاذي التعليمي',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'التطبيق مقفل لحماية بيانات الطلاب والسنتر',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                        shadowColor: const Color(0x666366F1),
                      ),
                      onPressed: _unlockWithBiometrics,
                      icon: const Icon(Icons.fingerprint_rounded, size: 26),
                      label: const Text(
                        'إلغاء القفل بالبصمة',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6366F1),
                        side: const BorderSide(
                          color: Color(0xFF6366F1),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: const Color(
                          0xFF6366F1,
                        ).withValues(alpha: isDark ? 0.08 : 0.05),
                      ),
                      onPressed: () async {
                        final ok =
                            await SecurityService.showPinVerificationDialog(
                              context: context,
                              database: widget.database,
                            );
                        if (ok && mounted) {
                          setState(() => _isAppLocked = false);
                        }
                      },
                      icon: const Icon(Icons.password_rounded, size: 22),
                      label: const Text(
                        'إدخال رمز المرور (PIN)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    if (_isAppLocked) {
      return _buildAppLockScreen(isDark);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // If drawer is open, close it first
        if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
          _scaffoldKey.currentState?.closeDrawer();
          return;
        }

        // If not on Dashboard tab, navigate to Dashboard first
        if (selectedIndex != 0) {
          setState(() => selectedIndex = 0);
          return;
        }

        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              duration: const Duration(seconds: 2),
              content: const Row(
                children: [
                  Icon(Icons.touch_app_rounded, color: Colors.amber, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'اضغط مرة أخرى للخروج أو العمل بالخلفية',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          return;
        }

        // On confirmed second press within 2s, send app to background
        SystemNavigator.pop();
      },
      child: Scaffold(
        key: _scaffoldKey,
        extendBody: false,
        drawer: _buildAppDrawer(context, isDark, primaryColor),
        appBar: null,
        body: Column(
          children: [
            if (_activeDockItemIds.isNotEmpty &&
                selectedIndex >= 0 &&
                selectedIndex < _activeDockItemIds.length &&
                _activeDockItemIds[selectedIndex] == 'home')
              _buildCompactFixedTopBar(context, isDark, primaryColor),
            Expanded(
              child: IndexedStack(
                index: selectedIndex.clamp(
                  0,
                  _screens.isEmpty ? 0 : _screens.length - 1,
                ),
                children: _screens,
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: RepaintBoundary(
            child: _buildMockupCapsuleDock(isDark, primaryColor),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // FIXED COMPACT TOP HEADER (شريط الهيدر الثابت المدمج)
  // ==========================================================================
  Widget _buildCompactFixedTopBar(
    BuildContext context,
    bool isDark,
    Color primaryColor,
  ) {
    const double topInset = 16.0;
    return Container(
      height: 52 + topInset,
      padding: const EdgeInsets.only(
        top: 4 + topInset,
        bottom: 4,
        left: 14,
        right: 14,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. Drawer Hamburger Button (الثلاث شرط بتوع القائمة - تم نقله هنا)
          InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              _scaffoldKey.currentState?.openDrawer();
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.menu_rounded,
                size: 20,
                color: isDark
                    ? const Color(0xFFCBD5E1)
                    : const Color(0xFF475569),
              ),
            ),
          ),

          // 2. Actions Row: Student Messages + Broadcast + Bell + Profile Pill
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 1. Student Live Messages Hub
                StreamBuilder<int>(
                  stream: AcademyCommunicationService.instance
                      .streamTotalUnreadMessagesForTeacher(),
                  builder: (context, snapshot) {
                    final unreadCount = snapshot.data ?? 0;
                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TeacherMessagesHubScreen(
                              database: widget.database,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFFF1F5F9),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFE2E8F0),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.forum_outlined,
                              size: 18,
                              color: isDark
                                  ? const Color(0xFFCBD5E1)
                                  : const Color(0xFF475569),
                            ),
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1.5,
                                ),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF00B4D8),
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(10)),
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 15,
                                  minHeight: 15,
                                ),
                                child: Center(
                                  child: Text(
                                    '$unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // 2. Student Broadcast Announcements Button
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeacherBroadcastScreen(
                          database: widget.database,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFF1F5F9),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.campaign_outlined,
                      size: 19,
                      color: isDark
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Notification Bell with badge
                InkWell(
                  key: _bellKey,
                  onTap: () =>
                      _showNotificationsDropdown(context, isDark, primaryColor),
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF1F5F9),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.notifications_none_rounded,
                          size: 19,
                          color: isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF475569),
                        ),
                      ),
                      if (_unreadAlertsCount > 0)
                        Positioned(
                          top: -1,
                          right: -1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1.5,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              borderRadius: BorderRadius.all(
                                Radius.circular(10),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x66EF4444),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 15,
                              minHeight: 15,
                            ),
                            child: Center(
                              child: Text(
                                '$_unreadAlertsCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Profile Pill (Avatar + Teacher Name) - Opens Profile Screen
                InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ProfileScreen(database: widget.database),
                      ),
                    ).then((_) => _loadHeaderInfo());
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                teacherName,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                centerName,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF00F2FE),
                                  width: 1.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x3300F2FE),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child:
                                    (customLogoPath != null &&
                                        File(customLogoPath!).existsSync())
                                    ? Image.file(
                                        File(customLogoPath!),
                                        fit: BoxFit.cover,
                                      )
                                    : Image.asset(
                                        'assets/images/app_icon.png',
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: isDark
                                              ? const Color(0xFF1E293B)
                                              : const Color(0xFFE2E8F0),
                                          child: Center(
                                            child: Text(
                                              teacherAvatar.isNotEmpty
                                                  ? teacherAvatar
                                                  : '👨‍🏫',
                                              style: const TextStyle(
                                                fontSize: 17,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF0F172A)
                                        : Colors.white,
                                    width: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  void _showNotificationsDropdown(
    BuildContext context,
    bool isDark,
    Color primary,
  ) {
    final renderBox = _bellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isAr = AppLocale.isArabic(context);

    final double top = position.dy + size.height + 6;
    final double? left = isAr
        ? position.dx.clamp(8.0, screenWidth - 325)
        : null;
    final double? right = isAr
        ? null
        : (screenWidth - (position.dx + size.width)).clamp(
            8.0,
            screenWidth - 325,
          );

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final unreadCount = _unreadAlertsCount;

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(ctx),
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  top: top,
                  left: left,
                  right: right,
                  child: Material(
                    color: Colors.transparent,
                    child: Directionality(
                      textDirection: isAr
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: Container(
                        width: 320,
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.7,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xF80D1627)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? const Color(0x3838BDF8)
                                : const Color(0xFFCBD5E1),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.6 : 0.15,
                              ),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              color: isDark
                                  ? const Color(0x2400F2FE)
                                  : const Color(0xFFF1F5F9),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF00F2FE,
                                      ).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.notifications_active_rounded,
                                      color: Color(0xFF00F2FE),
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'التنبيهات',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (unreadCount > 0) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFEF4444,
                                        ).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0x40EF4444),
                                        ),
                                      ),
                                      child: Text(
                                        '$unreadCount جديد',
                                        style: const TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () async {
                                        await _markAllAlertsAsRead();
                                        setDialogState(() {});
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        child: Text(
                                          'قراءة الكل',
                                          style: TextStyle(
                                            color: themeColorOr(
                                              primary,
                                              isDark,
                                            ),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ] else
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'تمت القراءة ✅',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  if (_activeAlerts.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () async {
                                        await _dismissAllAlerts();
                                        setDialogState(() {});
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF334155)
                                              : const Color(0xFFE2E8F0),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.delete_sweep_rounded,
                                              size: 13,
                                              color: isDark
                                                  ? Colors.grey.shade300
                                                  : Colors.grey.shade700,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              'مسح الكل',
                                              style: TextStyle(
                                                color: isDark
                                                    ? Colors.grey.shade300
                                                    : Colors.grey.shade700,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Alerts Body
                            if (_activeAlerts.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 26,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(
                                          alpha: 0.12,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check_circle_outline_rounded,
                                        color: Colors.green,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'لا توجد تنبيهات معلقة',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'جميع الحصص والمستحقات والاختبارات محدثة بالكامل',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 11,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            else
                              Flexible(
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  itemCount: _activeAlerts.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    thickness: 0.6,
                                    color: isDark
                                        ? const Color(0x1FFFFFFF)
                                        : const Color(0xFFF1F5F9),
                                  ),
                                  itemBuilder: (context, index) {
                                    final alert = _activeAlerts[index];
                                    final isUnread = !_readAlertIds.contains(
                                      alert.id,
                                    );

                                    return _buildSmartNotificationRow(
                                      icon: alert.icon,
                                      iconColor: alert.iconColor,
                                      title: alert.title,
                                      body: alert.body,
                                      badgeText: alert.badgeText,
                                      isDark: isDark,
                                      isUnread: isUnread,
                                      onTap: () async {
                                        await _markAlertAsRead(alert.id);
                                        if (dialogCtx.mounted) {
                                          Navigator.pop(dialogCtx);
                                        }
                                        _navigateToTab(alert.targetTab);
                                      },
                                      onDismiss: () async {
                                        await _dismissAlert(alert.id);
                                        setDialogState(() {});
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color themeColorOr(Color primary, bool isDark) {
    return isDark ? const Color(0xFF38BDF8) : primary;
  }

  Widget _buildSmartNotificationRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
    required String badgeText,
    required bool isDark,
    required bool isUnread,
    required VoidCallback onTap,
    VoidCallback? onDismiss,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isUnread
            ? (isDark ? const Color(0x1400F2FE) : const Color(0xFFF0FDF4))
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isUnread ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: isUnread
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 11.5,
                            color: isUnread
                                ? (isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A))
                                : (isDark
                                      ? Colors.white60
                                      : Colors.grey.shade700),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (isUnread) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            color: iconColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- Concept 1: Floating Glass Capsule (Thumb Island) Menu Hub ---
  void _showBottomMenuHub(
    BuildContext context,
    bool isDark,
    Color primaryColor,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final bottomInset = MediaQuery.of(sheetCtx).padding.bottom;
            final maxHeight = MediaQuery.of(sheetCtx).size.height * 0.85;

            return Directionality(
              textDirection: AppLocale.isArabic(context)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 68),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xF50B1426)
                          : Colors.white.withValues(alpha: 0.98),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: isDark
                            ? const Color(0x4000F2FE)
                            : const Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.65 : 0.15,
                          ),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                        if (isDark)
                          const BoxShadow(
                            color: Color(0x2800F2FE),
                            blurRadius: 22,
                            spreadRadius: 1,
                            offset: Offset(0, -2),
                          ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top handle pill
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFCBD5E1),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Sleek Mini Header
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF00F2FE,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF00F2FE,
                                    ).withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.grid_view_rounded,
                                  color: Color(0xFF00F2FE),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      AppLocale.tr(
                                        context,
                                        'menu_title',
                                        ar: 'القائمة السريعة',
                                        en: 'Quick Menu',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      AppLocale.tr(
                                        context,
                                        'menu_subtitle',
                                        ar: 'كافة أقسام المنصة بحجم موحد متناسق',
                                        en: 'All Management Modules',
                                      ),
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: isDark
                                            ? const Color(0xFF94A3B8)
                                            : const Color(0xFF64748B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Customize quick menu items button
                              InkWell(
                                onTap: () => _showCustomizeQuickMenuSheet(context, sheetCtx, setSheetState, isDark),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3), width: 0.8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_circle_outline_rounded, color: Color(0xFF00F2FE), size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'تخصيص',
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Theme switch
                              InkWell(
                                onTap: () {
                                  widget.themeController.toggleTheme();
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0x2238BDF8)
                                        : const Color(0x100284C7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isDark
                                        ? Icons.light_mode_rounded
                                        : Icons.dark_mode_outlined,
                                    color: Colors.amber,
                                    size: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Settings icon
                              InkWell(
                                onTap: () {
                                  Navigator.pop(sheetCtx);
                                  _openSettingsTab(0);
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0x2238BDF8)
                                        : const Color(0x100284C7),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.settings_outlined,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Dynamic Grid for modules + Add Item Tile
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.02,
                            children: [
                              ..._customQuickItemIds.map((id) {
                                final def = _allAvailableQuickItems.firstWhere(
                                  (it) => it['id'] == id,
                                  orElse: () => {
                                    'id': id,
                                    'title': id,
                                    'icon': Icons.widgets_rounded,
                                  },
                                );
                                return _buildThumbIslandTile(
                                  title: def['title'] as String,
                                  icon: def['icon'] as IconData,
                                  isDark: isDark,
                                  onTap: () => _handleQuickMenuItemTap(sheetCtx, id),
                                );
                              }),
                              _buildAddQuickItemTile(
                                isDark: isDark,
                                onTap: () => _showCustomizeQuickMenuSheet(context, sheetCtx, setSheetState, isDark),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAddQuickItemTile({
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(18),
      splashColor: const Color(0x3300F2FE),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1E293B).withValues(alpha: 0.4)
              : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF00F2FE).withValues(alpha: 0.5),
            width: 1.2,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Color(0xFF00F2FE),
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'إضافة عنصر +',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00F2FE),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleQuickMenuItemTap(BuildContext sheetCtx, String id) {
    switch (id) {
      case 'students':
        _openFeatureFromHub(sheetCtx, 'students', () => StudentsScreen(database: widget.database));
        break;
      case 'groups':
        _openFeatureFromHub(sheetCtx, 'groups', () => GroupsScreen(database: widget.database));
        break;
      case 'timetable':
        _openFeatureFromHub(sheetCtx, 'timetable', () => TimetableScreen(database: widget.database));
        break;
      case 'attendance':
        _openFeatureFromHub(sheetCtx, 'attendance', () => TodayAttendanceScreen(database: widget.database));
        break;
      case 'exams':
        _openFeatureFromHub(sheetCtx, 'exams', () => ExamsScreen(database: widget.database));
        break;
      case 'finances':
        _openFeatureFromHub(sheetCtx, 'finances', () => FinancesScreen(database: widget.database));
        break;
      case 'whatsapp':
        _openFeatureFromHub(sheetCtx, 'whatsapp', () => WhatsAppHubScreen(database: widget.database));
        break;
      case 'curriculum':
        _openFeatureFromHub(sheetCtx, 'curriculum', () => CurriculumScreen(database: widget.database));
        break;
      case 'reports':
        _openFeatureFromHub(sheetCtx, 'reports', () => ReportsScreen(database: widget.database));
        break;
      case 'certificates':
        _openFeatureFromHub(sheetCtx, 'certificates', () => CertificatesScreen(database: widget.database));
        break;
      case 'scanner':
        Navigator.pop(sheetCtx);
        Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen(database: widget.database)));
        break;
      case 'alarm':
        Navigator.pop(sheetCtx);
        Navigator.push(context, MaterialPageRoute(builder: (_) => AlarmClockScreen(database: widget.database)));
        break;
      case 'profile':
        _openFeatureFromHub(sheetCtx, 'profile', () => ProfileScreen(database: widget.database));
        break;
      case 'settings':
        Navigator.pop(sheetCtx);
        _openSettingsTab(0);
        break;
      default:
        Navigator.pop(sheetCtx);
        break;
    }
  }

  void _showCustomizeQuickMenuSheet(
    BuildContext rootCtx,
    BuildContext sheetCtx,
    void Function(void Function()) setSheetState,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: rootCtx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (custCtx) {
        List<String> tempSelected = List<String>.from(_customQuickItemIds);

        return StatefulBuilder(
          builder: (ctx, setCustState) {
            final bottomInset = MediaQuery.of(ctx).padding.bottom;
            final maxHeight = MediaQuery.of(ctx).size.height * 0.8;

            return Directionality(
              textDirection: AppLocale.isArabic(rootCtx)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 16),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark
                            ? const Color(0x4000F2FE)
                            : const Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.tune_rounded,
                                color: Color(0xFF00F2FE),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'تخصيص وإضافة عناصر القائمة السريعة ⚡',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  Text(
                                    'حدد الأقسام والأدوات التي تود إظهارها في القائمة السريعة:',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(custCtx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _allAvailableQuickItems.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (c, idx) {
                              final item = _allAvailableQuickItems[idx];
                              final id = item['id'] as String;
                              final title = item['title'] as String;
                              final icon = item['icon'] as IconData;
                              final isChecked = tempSelected.contains(id);

                              return CheckboxListTile(
                                value: isChecked,
                                activeColor: const Color(0xFF00F2FE),
                                checkColor: Colors.black87,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                secondary: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: isChecked
                                        ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
                                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    icon,
                                    size: 19,
                                    color: isChecked ? const Color(0xFF00F2FE) : Colors.grey,
                                  ),
                                ),
                                title: Text(
                                  title,
                                  style: TextStyle(
                                    fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13.5,
                                  ),
                                ),
                                onChanged: (val) {
                                  setCustState(() {
                                    if (val == true) {
                                      if (!tempSelected.contains(id)) tempSelected.add(id);
                                    } else {
                                      if (tempSelected.length > 1) {
                                        tempSelected.remove(id);
                                      } else {
                                        ScaffoldMessenger.of(rootCtx).showSnackBar(
                                          const SnackBar(
                                            content: Text('يجب الإبقاء على عنصر واحد على الأقل في القائمة السريعة'),
                                            behavior: SnackBarBehavior.floating,
                                            duration: Duration(seconds: 1),
                                          ),
                                        );
                                      }
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                setCustState(() {
                                  tempSelected = _allAvailableQuickItems
                                      .where((it) => it['isDefault'] == true)
                                      .map((it) => it['id'] as String)
                                      .toList();
                                });
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('الافتراضي', style: TextStyle(fontSize: 12)),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF00F2FE),
                                foregroundColor: Colors.black87,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () async {
                                await _saveQuickMenuConfig(tempSelected);
                                setSheetState(() {});
                                if (custCtx.mounted) Navigator.pop(custCtx);
                                if (rootCtx.mounted) {
                                  ScaffoldMessenger.of(rootCtx).showSnackBar(
                                    const SnackBar(
                                      content: Text('تم حفظ وتحديث عناصر القائمة السريعة بنجاح ⚡✓'),
                                      backgroundColor: Color(0xFF10B981),
                                      behavior: SnackBarBehavior.floating,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text(
                                'حفظ التخصيص',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openFeatureFromHub(
    BuildContext sheetCtx,
    String dockId,
    Widget Function() screenBuilder,
  ) {
    Navigator.pop(sheetCtx);
    final idx = _activeDockItemIds.indexOf(dockId);
    if (idx != -1) {
      if (selectedIndex != idx) {
        HapticFeedback.selectionClick();
        setState(() => selectedIndex = idx);
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => screenBuilder()),
      ).then((_) {
        _loadHeaderInfo();
      });
    }
  }

  Widget _buildThumbIslandTile({
    required String title,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(18),
      splashColor: const Color(0x3300F2FE),
      highlightColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0x4016253D) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0x2E38BDF8) : const Color(0xFFE2E8F0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF00F2FE,
                  ).withValues(alpha: isDark ? 0.14 : 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: const Color(0xFF00F2FE), size: 29),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMockupCapsuleDock(bool isDark, Color primaryColor) {
    final bool isRtl = Directionality.of(context) == TextDirection.rtl;
    final int count = _activeDockItemIds.isEmpty
        ? 4
        : _activeDockItemIds.length;
    final int activeIdx = selectedIndex.clamp(0, count - 1);
    final double dockHeight = (52.0 + (_dockIconSize - 22.0) * 0.7).clamp(
      50.0,
      68.0,
    );
    final double haloSize = (_dockIconSize + 14.0).clamp(32.0, 48.0);
    final double pillWidth = (_dockIconSize * 0.95).clamp(18.0, 28.0);

    // Exact fractional alignment calculation for N slots:
    final double targetX;
    if (isRtl) {
      final double fraction = ((count - 1 - activeIdx) + 0.5) / count;
      targetX = (fraction - 0.5) * 2.0;
    } else {
      final double fraction = (activeIdx + 0.5) / count;
      targetX = (fraction - 0.5) * 2.0;
    }

    return Container(
      key: const ValueKey('mockup_capsule_dock'),
      height: dockHeight,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xF2091222)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(dockHeight / 2),
        border: Border.all(
          color: isDark ? const Color(0x3338BDF8) : const Color(0xFFCBD5E1),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          if (isDark)
            const BoxShadow(
              color: Color(0x1800F2FE),
              blurRadius: 14,
              offset: Offset(0, -1),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(dockHeight / 2),
        child: Stack(
          children: [
            // 1. Hardware-accelerated sliding glowing pill indicator (at bottom edge)
            AnimatedAlign(
              alignment: Alignment(targetX, 0.90),
              duration: const Duration(milliseconds: 220),
              curve: Curves.fastEaseInToSlowEaseOut,
              child: Container(
                width: pillWidth,
                height: 2.6,
                decoration: BoxDecoration(
                  color: const Color(0xFF00F2FE),
                  borderRadius: BorderRadius.circular(1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xFF00F2FE),
                      blurRadius: 7,
                      spreadRadius: 0.8,
                    ),
                  ],
                ),
              ),
            ),

            // 2. Hardware-accelerated sliding ambient glow halo behind the active icon
            AnimatedAlign(
              alignment: Alignment(targetX, 0.0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.fastEaseInToSlowEaseOut,
              child: Container(
                width: haloSize,
                height: haloSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x3800F2FE),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),

            // 3. Row of dynamic slots
            Directionality(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(count, (index) {
                  final id = _activeDockItemIds[index];
                  final meta =
                      _dockItemMeta[id] ??
                      (
                        icon: Icons.circle_outlined,
                        activeIcon: Icons.circle,
                        title: id,
                      );
                  final bool isActive = selectedIndex == index;

                  return Expanded(
                    child: _KineticDockIconTab(
                      index: index,
                      icon: meta.icon,
                      activeIcon: meta.activeIcon,
                      isActive: isActive,
                      isDark: isDark,
                      iconSize: _dockIconSize,
                      onTap: () {
                        if (id == 'menu') {
                          HapticFeedback.lightImpact();
                          _showBottomMenuHub(context, isDark, primaryColor);
                          return;
                        }
                        if (selectedIndex != index) {
                          HapticFeedback.selectionClick();
                          setState(() => selectedIndex = index);
                        }
                      },
                      onLongPress: () =>
                          _showBottomMenuHub(context, isDark, primaryColor),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppDrawer(
    BuildContext context,
    bool isDark,
    Color primaryColor,
  ) {
    final activeTabId = (selectedIndex >= 0 && selectedIndex < _activeDockItemIds.length)
        ? _activeDockItemIds[selectedIndex]
        : 'home';

    return Drawer(
      backgroundColor: isDark ? const Color(0xFF0B1329) : const Color(0xFFF8FAFC),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ================================================================
            // 1. EXECUTIVE HEADER WITH MINI-STATS STRIP (Concepts 1 & 4)
            // ================================================================
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryColor,
                    primaryColor.withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(database: widget.database),
                        ),
                      ).then((_) => _loadHeaderInfo());
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
                          ),
                          child: ClipOval(
                            child: (customLogoPath != null && File(customLogoPath!).existsSync())
                                ? Image.file(File(customLogoPath!), fit: BoxFit.cover)
                                : Image.asset(
                                    'assets/images/app_icon.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Text(teacherAvatar, style: const TextStyle(fontSize: 26)),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                centerName.isNotEmpty ? centerName : 'سنتر أستاذي التعليمي',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                teacherName.isNotEmpty ? teacherName : 'المعلم',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 12.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      children: [
                                        Text('تعديل البروفايل', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                        SizedBox(width: 3),
                                        Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 8),
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
                  ),
                  const SizedBox(height: 12),
                  // Mini-Stats Strip from Concept 4
                  FutureBuilder<Map<String, dynamic>>(
                    future: _getDrawerStats(),
                    builder: (context, snapshot) {
                      final stats = snapshot.data ?? {'studentsCount': 0, 'groupsCount': 0, 'attPercent': 100};
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildDrawerMiniStat('الطلاب', '${stats['studentsCount']}', Icons.people_alt_rounded),
                            Container(width: 1, height: 18, color: Colors.white24),
                            _buildDrawerMiniStat('المجموعات', '${stats['groupsCount']}', Icons.groups_rounded),
                            Container(width: 1, height: 18, color: Colors.white24),
                            _buildDrawerMiniStat('نسبة الحضور', '${stats['attPercent']}%', Icons.fact_check_rounded),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // ================================================================
            // 2. SCROLLABLE MENU & LIVE WIDGETS
            // ================================================================
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                children: [
                  // Live Widget: الحصة القادمة اليوم (Concepts 2 & 4)
                  FutureBuilder<Map<String, dynamic>?>(
                    future: _getUpcomingClassToday(),
                    builder: (context, snapshot) {
                      final nextClass = snapshot.data;
                      if (nextClass == null) return const SizedBox.shrink();

                      void openTargetInTimetable() {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TimetableScreen(
                              database: widget.database,
                              initialDomain: nextClass['domain'] as String? ?? 'school',
                              initialDay: nextClass['day'] as String?,
                              highlightTargetKey: nextClass['targetKey'] as String?,
                            ),
                          ),
                        );
                      }

                      final isSchool = nextClass['isSchool'] == true;
                      final isToday = nextClass['isToday'] == true;
                      final accentColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
                      final badgeText = nextClass['badgeText'] as String? ?? 'في الموعد ⏰';
                      final rawBadgeBg = nextClass['badgeBg'] as Color?;
                      final rawBadgeColor = nextClass['badgeColor'] as Color?;

                      // Theme-adaptive, high contrast, eye-friendly badge styling
                      final Color badgeBg;
                      final Color badgeColor;
                      final Color badgeBorder;

                      if (badgeText.contains('دقيقة') || badgeText.contains('الموعد')) {
                        // Upcoming countdown: Warm amber / gold (easy on the eyes, high contrast)
                        badgeBg = isDark
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.22)
                            : const Color(0xFFFEF3C7);
                        badgeColor = isDark
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFFB45309);
                        badgeBorder = isDark
                            ? const Color(0xFFFBBF24).withValues(alpha: 0.45)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.50);
                      } else if (badgeText.contains('الآن')) {
                        // Live / Ongoing: Vivid Red
                        badgeBg = isDark
                            ? const Color(0xFFEF4444).withValues(alpha: 0.22)
                            : const Color(0xFFFEE2E2);
                        badgeColor = isDark
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFFDC2626);
                        badgeBorder = isDark
                            ? const Color(0xFFF87171).withValues(alpha: 0.45)
                            : const Color(0xFFEF4444).withValues(alpha: 0.45);
                      } else if (badgeText.contains('مكتمل')) {
                        // Completed: Emerald Green
                        badgeBg = isDark
                            ? const Color(0xFF10B981).withValues(alpha: 0.22)
                            : const Color(0xFFD1FAE5);
                        badgeColor = isDark
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFF047857);
                        badgeBorder = isDark
                            ? const Color(0xFF34D399).withValues(alpha: 0.45)
                            : const Color(0xFF10B981).withValues(alpha: 0.45);
                      } else {
                        badgeBg = rawBadgeBg ??
                            (isDark
                                ? const Color(0xFF8B5CF6).withValues(alpha: 0.22)
                                : const Color(0xFFEDE9FE));
                        badgeColor = rawBadgeColor ??
                            (isDark
                                ? const Color(0xFFDDD6FE)
                                : const Color(0xFF6D28D9));
                        badgeBorder = badgeColor.withValues(alpha: 0.40);
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF1E1B4B).withValues(alpha: isDark ? 0.95 : 0.08),
                              const Color(0xFF0F172A).withValues(alpha: isDark ? 0.98 : 0.04),
                            ],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: accentColor.withValues(alpha: isDark ? 0.35 : 0.25),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: isDark ? 0.12 : 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: openTargetInTimetable,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: accentColor.withValues(alpha: isDark ? 0.22 : 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.access_time_filled_rounded,
                                          size: 15,
                                          color: accentColor,
                                        ),
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          nextClass['title'] ?? 'حصة اليوم المحددة',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11.5,
                                            color: accentColor,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                        decoration: BoxDecoration(
                                          color: badgeBg,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: badgeBorder, width: 1),
                                        ),
                                        child: Text(
                                          badgeText,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: badgeColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    nextClass['name'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${nextClass['grade'] ?? ''}${nextClass['timeDisplay'] != null ? ' • ${nextClass['timeDisplay']}' : (nextClass['schedule'] != null ? ' • ${nextClass['schedule']}' : '')}${nextClass['room'] != null && nextClass['room'].toString().isNotEmpty ? ' • ${nextClass['room']}' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (nextClass['todayTotalCount'] != null && (nextClass['todayTotalCount'] as int) > 1) ...[
                                    const SizedBox(height: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha: isDark ? 0.15 : 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: accentColor.withValues(alpha: isDark ? 0.30 : 0.20)),
                                      ),
                                      child: Text(
                                        'حصة ${nextClass['todayIndex']} من ${nextClass['todayTotalCount']} اليوم${nextClass['nextUpcomingName'] != null ? ' • التالية: ${nextClass['nextUpcomingName']} (${nextClass['nextUpcomingTime']})' : ''}',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0284C7),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 9),
                                  if (!isSchool && isToday)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: SizedBox(
                                            height: 32,
                                            child: FilledButton.icon(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: const Color(0xFF0284C7),
                                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.calendar_month_rounded,
                                                size: 13,
                                                color: Colors.white,
                                              ),
                                              label: Text(
                                                nextClass['buttonText'] ?? 'عرض في الجدول المحدد ⚡',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              onPressed: openTargetInTimetable,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: SizedBox(
                                            height: 32,
                                            child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: const Color(0xFFA855F7),
                                                side: const BorderSide(color: Color(0xFFA855F7)),
                                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.fact_check_rounded,
                                                size: 13,
                                              ),
                                              label: const Text(
                                                'رصد الحضور 📋',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              onPressed: () {
                                                Navigator.pop(context);
                                                _navigateToTab('attendance');
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    SizedBox(
                                      width: double.infinity,
                                      height: 32,
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFF4F46E5),
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.flash_on_rounded,
                                          size: 14,
                                          color: Color(0xFF00F2FE),
                                        ),
                                        label: Text(
                                          nextClass['buttonText'] ?? 'عرض في الجدول المحدد ⚡',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        onPressed: openTargetInTimetable,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  _buildDrawerSectionTitle('الأقسام الرئيسية', isDark),
                  _buildDrawerTile(
                    icon: Icons.dashboard_rounded,
                    title: 'لوحة التحكم المركزية',
                    subtitle: 'إحصائيات السنتر ونظرة عامة',
                    color: Colors.indigo,
                    isSelected: activeTabId == 'home' || activeTabId == 'dashboard',
                    badge: 'الرئيسية',
                    badgeColor: Colors.indigo,
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToTab('home');
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.people_alt_rounded,
                    title: 'الطلاب والاشتراكات',
                    subtitle: 'إدارة الطلاب ومتابعة الديون',
                    color: Colors.blue,
                    isSelected: activeTabId == 'students',
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToTab('students');
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.groups_rounded,
                    title: 'المجموعات والقاعات',
                    subtitle: 'جداول الحصص والمواعيد',
                    color: Colors.cyan,
                    isSelected: activeTabId == 'groups',
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToTab('groups');
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.calendar_month_rounded,
                    title: 'جدول الحصص والدروس',
                    subtitle: 'الجدول الأسبوعي والمنبهات الذكية',
                    color: const Color(0xFF06B6D4),
                    isSelected: activeTabId == 'timetable',
                    badge: 'مدرسي وسنتر',
                    badgeColor: const Color(0xFF06B6D4),
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToTab('timetable');
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.fact_check_rounded,
                    title: 'كشف حضور الحصة اليومي',
                    subtitle: 'تسجيل الحضور والتسميع المباشر',
                    color: Colors.teal,
                    isSelected: activeTabId == 'attendance',
                    badge: 'تسجيل سريع',
                    badgeColor: Colors.teal,
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToTab('attendance');
                    },
                  ),

                  const Divider(height: 20),
                  _buildDrawerSectionTitle('الأكاديميا والمالية', isDark),

                  _buildDrawerTile(
                    icon: Icons.insights_rounded,
                    title: 'التقارير والمتابعة الأكاديمية',
                    subtitle: 'سجل التقارير الشامل والحصص وجدولتها',
                    color: const Color(0xFF0284C7),
                    isSelected: activeTabId == 'reports',
                    badge: 'سجل شامل 📊',
                    badgeColor: const Color(0xFF0284C7),
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToTab('reports');
                    },
                  ),

                  _buildDrawerTile(
                    icon: Icons.assignment_turned_in_rounded,
                    title: 'الامتحانات ورصد الدرجات',
                    subtitle: 'نتائج الاختبارات وتقييم الطلاب',
                    color: Colors.deepPurple,
                    isSelected: activeTabId == 'exams',
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToTab('exams');
                    },
                  ),

                  _buildDrawerTile(
                    icon: Icons.workspace_premium_rounded,
                    title: 'قسم إعداد وتصميم الشهادات',
                    subtitle: 'شهادات التقدير، الأوائل، والتكريم الخاص',
                    color: const Color(0xFFF59E0B),
                    isSelected: activeTabId == 'certificates',
                    badge: 'استوديو 🎓',
                    badgeColor: const Color(0xFFF59E0B),
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToTab('certificates');
                    },
                  ),

                  _buildDrawerTile(
                    icon: Icons.stars_rounded,
                    title: 'بنك النقاط والمكافآت 🏆',
                    subtitle: 'تحفيز الطلاب، الكتالوج، ولوحة الشرف',
                    color: const Color(0xFF00F2FE),
                    isSelected: false,
                    badge: 'جديد 🪙',
                    badgeColor: const Color(0xFF00F2FE),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RewardsManagerScreen(database: widget.database),
                        ),
                      );
                    },
                  ),

                  // Expandable Curriculum Section
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      childrenPadding: const EdgeInsetsDirectional.only(start: 12, bottom: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.themeController.resolveIcon(Icons.menu_book_rounded),
                          color: Colors.orange,
                          size: 20,
                        ),
                      ),
                      title: const Text('المناهج وتوزيع الدروس', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      subtitle: Text(
                        'توزيع المناهج وخطط المراحل التعليمية',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      ),
                      children: [
                        _buildDrawerSubTile(
                          title: 'كل المناهج والوحدات',
                          subtitle: 'استعراض عام لكافة المراحل',
                          icon: Icons.all_inclusive_rounded,
                          color: Colors.orange,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CurriculumScreen(database: widget.database, initialStage: 'الكل'),
                              ),
                            );
                          },
                        ),
                        _buildDrawerSubTile(
                          title: 'المرحلة الثانوية العامة',
                          subtitle: 'الأول والثاني والثالث الثانوي',
                          icon: Icons.school_rounded,
                          color: Colors.indigo,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CurriculumScreen(database: widget.database, initialStage: 'الثانوية العامة'),
                              ),
                            );
                          },
                        ),
                        _buildDrawerSubTile(
                          title: 'المرحلة الإعدادية',
                          subtitle: 'الأول والثاني والثالث الإعدادي',
                          icon: Icons.menu_book_rounded,
                          color: Colors.teal,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CurriculumScreen(database: widget.database, initialStage: 'المرحلة الإعدادية'),
                              ),
                            );
                          },
                        ),
                        _buildDrawerSubTile(
                          title: 'المرحلة الابتدائية',
                          subtitle: 'صفوف النقل والتأسيس',
                          icon: Icons.child_care_rounded,
                          color: Colors.amber.shade800,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CurriculumScreen(database: widget.database, initialStage: 'المرحلة الابتدائية'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  _buildDrawerTile(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'الخزينة والمصروفات',
                    subtitle: 'المقبوضات والمصروفات وصافي الأرباح',
                    color: const Color(0xFF059669),
                    isSelected: activeTabId == 'finances',
                    badge: 'حسابات 💳',
                    badgeColor: const Color(0xFF059669),
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToTab('finances');
                    },
                  ),
                  _buildDrawerTile(
                    icon: Icons.chat_rounded,
                    title: 'مركز مراسلات الواتساب',
                    subtitle: 'إرسال الإشعارات وتنبيهات أولياء الأمور',
                    color: const Color(0xFF25D366),
                    isSelected: activeTabId == 'whatsapp',
                    badge: 'إشعارات 💬',
                    badgeColor: const Color(0xFF25D366),
                    onTap: () {
                      Navigator.pop(context);
                      _navigateToTab('whatsapp');
                    },
                  ),

                  const Divider(height: 20),
                  _buildDrawerSectionTitle('النظام والتحكم', isDark),

                  _buildDrawerTile(
                    icon: Icons.phonelink_lock_rounded,
                    title: 'بيانات وتأمين تطبيق الطالب',
                    subtitle: 'إدارة كلمات المرور، ريسيت الباسورد، والمصادقة الثنائية 2FA',
                    color: const Color(0xFF00F2FE),
                    badge: 'تطبيق الطالب 📱',
                    badgeColor: const Color(0xFF00F2FE),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherStudentAppControlScreen(
                            database: widget.database,
                          ),
                        ),
                      );
                    },
                  ),

                  _buildDrawerTile(
                    icon: Icons.picture_as_pdf_rounded,
                    title: 'مكتبة المذكرات والملفات (PDF)',
                    subtitle: 'رفع ونشر مذكرات الحصص وملخصات PDF لجميع هواتف الطلاب',
                    color: const Color(0xFF00F2FE),
                    badge: 'PDF & مذكرات 📚',
                    badgeColor: const Color(0xFF00F2FE),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherMaterialsHubScreen(
                            database: widget.database,
                          ),
                        ),
                      );
                    },
                  ),

                  _buildDrawerTile(
                    icon: Icons.system_update_rounded,
                    title: 'التحقق من تحديثات التطبيق (OTA)',
                    subtitle: 'فحص توفر أحدث إصدار لتطبيق المعلم وتحديثه سحابياً',
                    color: const Color(0xFF38BDF8),
                    badge: 'تحديث سحابي 🚀',
                    badgeColor: const Color(0xFF38BDF8),
                    onTap: () {
                      Navigator.pop(context);
                      TeacherUpdateService.instance.checkForUpdate(context, showNoUpdateToast: true);
                    },
                  ),

                  // Expandable Settings Section
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      childrenPadding: const EdgeInsetsDirectional.only(start: 12, bottom: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.themeController.resolveIcon(Icons.settings_rounded),
                          color: Colors.blueGrey,
                          size: 20,
                        ),
                      ),
                      title: const Text('الإعدادات والتحكم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      subtitle: Text(
                        'تخصيص الواجهة والسنتر والنسخ السحابي',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      ),
                      children: [
                        _buildDrawerSubTile(
                          title: 'الشريط السفلي المخصص',
                          subtitle: 'ترتيب وتخصيص أيقونات الشريط الرئيسي',
                          icon: Icons.tune_rounded,
                          color: const Color(0xFF00F2FE),
                          onTap: () => _openSettingsTab(0),
                        ),
                        _buildDrawerSubTile(
                          title: 'ودجات الشاشة الرئيسية',
                          subtitle: 'ترتيب وحجم ومتجر الودجات الذكية',
                          icon: Icons.dashboard_customize_rounded,
                          color: const Color(0xFF818CF8),
                          onTap: () => _openSettingsTab(1),
                        ),
                        _buildDrawerSubTile(
                          title: 'الواتساب والربط البرمجي API',
                          subtitle: 'الربط الآلي، الفترات الزمنية ومنع الحظر',
                          icon: Icons.chat_rounded,
                          color: const Color(0xFF25D366),
                          onTap: () => _openSettingsTab(2),
                        ),
                        _buildDrawerSubTile(
                          title: 'استيراد وتصدير بيانات Excel',
                          subtitle: 'استيراد الطلاب والمجموعات والنماذج',
                          icon: Icons.table_chart_rounded,
                          color: const Color(0xFF10B981),
                          onTap: () => _openSettingsTab(3),
                        ),
                      ],
                    ),
                  ),

                  // Live Widget: شريط حالة المزامنة اللحظية (Concept 2)
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.12 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFF10B981),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'قاعدة البيانات متزامنة لحظياً',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                        Text(
                          'واتساب: متصل ✅',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ================================================================
            // 3. BOTTOM QUICK ACTION FOOTER (Concepts 1 & 3)
            // ================================================================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF334155).withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(
                        isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                        size: 15,
                        color: isDark ? Colors.amber : Colors.indigo,
                      ),
                      label: Text(
                        isDark ? 'الوضع النهاري' : 'الوضع الليلي',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        widget.themeController.toggleTheme();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.lock_rounded, size: 15, color: Colors.teal),
                    label: const Text(
                      'قفل الأمان',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _lockAppManually,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerMiniStat(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white70),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 8.5,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<Map<String, dynamic>> _getDrawerStats() async {
    try {
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final results = await Future.wait([
        widget.database.getStudents(),
        widget.database.getGroups(),
        widget.database.getAttendanceForDate(todayStr),
      ]);
      final studentsList = results[0] as List<dynamic>;
      final groupsList = results[1] as List<dynamic>;
      final attendanceList = results[2] as List<dynamic>;
      final present = attendanceList.where((a) => a.status == 'present' || a.status == 'late').length;
      final attPercent = attendanceList.isNotEmpty ? ((present / attendanceList.length) * 100).toInt() : 100;
      return {
        'studentsCount': studentsList.length,
        'groupsCount': groupsList.length,
        'attPercent': attPercent,
      };
    } catch (_) {
      return {'studentsCount': 0, 'groupsCount': 0, 'attPercent': 100};
    }
  }

  static const Map<int, List<String>> _arabicDayAliases = {
    1: ['الاثنين', 'الإثنين', 'اثنين', 'إثنين', 'تنين', 'اتنين', 'monday', 'mon'],
    2: ['الثلاثاء', 'ثلاثاء', 'الثلاثا', 'ثلاثا', 'التلات', 'تلات', 'tuesday', 'tue'],
    3: ['الأربعاء', 'الاربعاء', 'أربعاء', 'اربعاء', 'الاربعه', 'اربعه', 'الأربعه', 'wednesday', 'wed'],
    4: ['الخميس', 'خميس', 'thursday', 'thu'],
    5: ['الجمعة', 'الجمعه', 'جمعة', 'جمعه', 'friday', 'fri'],
    6: ['السبت', 'سبت', 'saturday', 'sat'],
    7: ['الأحد', 'الاحد', 'أحد', 'احد', 'sunday', 'sun'],
  };

  static String _normalizeArabicDigits(String text) {
    const arDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const enDigits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    var res = text;
    for (int i = 0; i < 10; i++) {
      res = res.replaceAll(arDigits[i], enDigits[i]);
    }
    return res;
  }

  static String _normalizeArabicLetters(String text) {
    return text
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .toLowerCase();
  }

  bool _matchesDayStrict(String? text, int targetWeekday) {
    if (text == null || text.trim().isEmpty) return false;
    final normalized = _normalizeArabicLetters(text);
    final aliases = _arabicDayAliases[targetWeekday] ?? [];

    for (final alias in aliases) {
      final normAlias = _normalizeArabicLetters(alias);
      if (targetWeekday == 7 && normAlias == 'احد') {
        // Prevent false positive on 'واحد' (1) or 'حادي'
        final safeText = normalized.replaceAll('واحد', '').replaceAll('حادي', '');
        if (RegExp(r'(?:^|[^\w\u0621-\u064A])احد(?:$|[^\w\u0621-\u064A])').hasMatch(safeText) ||
            safeText.contains('الاحد')) {
          return true;
        }
      } else {
        if (normalized.contains(normAlias)) return true;
      }
    }
    return false;
  }

  int _parseTimeStrToMinutes(String rawText) {
    if (rawText.trim().isEmpty) return 24 * 60;
    final text = _normalizeArabicDigits(rawText);

    // Pattern 1: Strict with colon: HH:mm with optional AM/PM/ص/م/عصرا/مساء/صباحا/ظهرا
    final regExpWithColon = RegExp(
      r'(\d{1,2}):(\d{2})\s*(ص|م|AM|PM|am|pm|صباحاً|صباحا|مساءً|مساء|عصراً|عصرا|ظهراً|ظهرا|ليلاً|ليلا)?',
      caseSensitive: false,
    );
    final matchColon = regExpWithColon.firstMatch(text);
    if (matchColon != null) {
      int hour = int.tryParse(matchColon.group(1) ?? '') ?? 0;
      int minute = int.tryParse(matchColon.group(2) ?? '0') ?? 0;
      final marker = matchColon.group(3)?.toLowerCase();

      if (marker != null) {
        if (marker.contains('م') || marker.contains('pm') || marker.contains('مساء') || marker.contains('عصر') || marker.contains('ظهر')) {
          if (hour < 12) hour += 12;
        } else if (marker.contains('ص') || marker.contains('am') || marker.contains('صباح')) {
          if (hour == 12) hour = 0;
        }
      } else {
        // In tutoring/school centers, hours 1 to 6 default to PM (13:00 to 18:00) unless marked AM
        if (hour >= 1 && hour <= 6) {
          hour += 12;
        }
      }
      return hour * 60 + minute;
    }

    // Pattern 2: Number followed directly by explicit time indicator (e.g. 5 مساء, 4 عصر, 10 صباح)
    final regExpWithMarker = RegExp(
      r'(?<!\d)(\d{1,2})\s*(ص|م|AM|PM|am|pm|صباحاً|صباحا|مساءً|مساء|عصراً|عصرا|ظهراً|ظهرا|ليلاً|ليلا)',
      caseSensitive: false,
    );
    final matchMarker = regExpWithMarker.firstMatch(text);
    if (matchMarker != null) {
      int hour = int.tryParse(matchMarker.group(1) ?? '') ?? 0;
      final marker = matchMarker.group(2)?.toLowerCase() ?? '';
      if (marker.contains('م') || marker.contains('pm') || marker.contains('مساء') || marker.contains('عصر') || marker.contains('ظهر')) {
        if (hour < 12) hour += 12;
      } else if (marker.contains('ص') || marker.contains('am') || marker.contains('صباح')) {
        if (hour == 12) hour = 0;
      }
      return hour * 60;
    }

    return 24 * 60;
  }

  String _formatMinutesToLabel(int minutes, String rawStartTime, String rawSchedule) {
    final regExp = RegExp(r'(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm|ص|م)?)', caseSensitive: false);
    final matchStart = regExp.firstMatch(rawStartTime);
    if (matchStart != null) return matchStart.group(1)!;

    final matchSched = regExp.firstMatch(rawSchedule);
    if (matchSched != null) return matchSched.group(1)!;

    int h = (minutes ~/ 60) % 24;
    int m = minutes % 60;
    String period = h >= 12 ? 'م' : 'ص';
    int displayHour = h % 12;
    if (displayHour == 0) displayHour = 12;
    String mStr = m.toString().padLeft(2, '0');
    return '$displayHour:$mStr $period';
  }

  Future<Map<String, dynamic>?> _getUpcomingClassToday() async {
    try {
      final groupsList = await widget.database.getGroups();
      List<SchoolPeriodModel> schoolPeriods = [];
      try {
        schoolPeriods = await widget.database.getSchoolPeriods();
      } catch (_) {}

      if (groupsList.isEmpty && schoolPeriods.isEmpty) return null;

      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      final todayDateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      const dayNames = [
        'الاثنين', // 1
        'الثلاثاء', // 2
        'الأربعاء', // 3
        'الخميس', // 4
        'الجمعة', // 5
        'السبت', // 6
        'الأحد', // 7
      ];
      final currentDay = dayNames[now.weekday - 1];
      final tomorrowWeekday = (now.weekday % 7) + 1;
      final tomorrowDay = dayNames[tomorrowWeekday - 1];

      // Check exceptional sessions for today
      List<String> exceptionalGroupIdsToday = [];
      try {
        final exSessions = await widget.database.getExceptionalSessions(
          date: todayDateStr,
          status: 'active',
        );
        exceptionalGroupIdsToday = exSessions.map((e) => e.groupId).toList();
      } catch (_) {}

      // Check which sessions have already had attendance registered today
      final attendedGroupIds = <String>{};
      try {
        final todayLogs = await widget.database.getSessionLogs(date: todayDateStr);
        for (final l in todayLogs) {
          attendedGroupIds.add(l.groupId);
        }
      } catch (_) {}

      int getGroupMinutes(GroupModel g, int weekday) {
        final aliases = _arabicDayAliases[weekday] ?? [];
        final normSchedule = _normalizeArabicDigits(g.schedule);
        for (final alias in aliases) {
          final pattern = RegExp(
            '${RegExp.escape(alias)}[^\\n،,]*?(\\d{1,2}:\\d{2}|\\d{1,2}\\s*(?:ص|م|am|pm|مساء|صباح|عصر))',
            caseSensitive: false,
          );
          final match = pattern.firstMatch(normSchedule);
          if (match != null) {
            final timeStr = match.group(1);
            if (timeStr != null) {
              final parsed = _parseTimeStrToMinutes(timeStr);
              if (parsed != 24 * 60) return parsed;
            }
          }
        }

        final schedM = _parseTimeStrToMinutes(g.schedule);
        final startM = _parseTimeStrToMinutes(g.startTime);

        if (schedM != 24 * 60 && (g.startTime.isEmpty || g.startTime == '03:00 PM')) {
          return schedM;
        }
        if (startM != 24 * 60) return startM;
        if (schedM != 24 * 60) return schedM;
        return 15 * 60;
      }

      // Collect unified sessions for TODAY (School + Groups)
      final List<Map<String, dynamic>> todaySessions = [];

      // 1. School Periods today
      for (final p in schoolPeriods) {
        if (p.isRecess) continue;
        if (!_matchesDayStrict(p.dayOfWeek, now.weekday)) continue;

        int sMin = _parseTimeStrToMinutes(p.startTime);
        int eMin = _parseTimeStrToMinutes(p.endTime);
        if (sMin == 24 * 60) sMin = 8 * 60 + (p.periodNumber - 1) * 50;
        if (eMin <= sMin) eMin = sMin + 45;

        final timeDisplay = (p.startTime.isNotEmpty && p.endTime.isNotEmpty)
            ? '${p.startTime} - ${p.endTime}'
            : _formatMinutesToLabel(sMin, p.startTime, '');

        final roomStr = p.room.isNotEmpty
            ? (p.room.contains('معمل') || p.room.contains('قاعة') ? p.room : 'معمل/فصل ${p.room}')
            : '';

        final periodLabel = p.periodNumber > 0 ? 'الحصة ${p.periodNumber}' : 'حصة مدرسية';
        final classTitle = p.className.startsWith('فصل') ? p.className : 'فصل ${p.className}';
        final nameDisplay = p.subject.isNotEmpty ? '$classTitle • ${p.subject}' : classTitle;

        todaySessions.add({
          'id': p.id,
          'targetKey': 'period_${p.id}',
          'domain': 'school',
          'day': p.dayOfWeek,
          'name': nameDisplay,
          'grade': periodLabel,
          'subject': p.subject,
          'room': roomStr,
          'startTime': p.startTime,
          'endTime': p.endTime,
          'startMinutes': sMin,
          'endMinutes': eMin,
          'timeDisplay': timeDisplay,
          'isReserve': p.isReserve,
          'isSchool': true,
          'alreadyAttended': false,
        });
      }

      // 2. Group sessions today
      for (final g in groupsList) {
        if (!g.isActive) continue;
        final matchesDay = _matchesDayStrict(g.schedule, now.weekday) ||
            _matchesDayStrict(g.days, now.weekday) ||
            exceptionalGroupIdsToday.contains(g.id);
        if (!matchesDay) continue;

        int sMin = getGroupMinutes(g, now.weekday);
        int eMin = _parseTimeStrToMinutes(g.endTime);
        if (eMin <= sMin) eMin = sMin + 60;

        final timeDisplay = _formatMinutesToLabel(sMin, g.startTime, g.schedule);
        final roomStr = g.room.isNotEmpty ? 'قاعة ${g.room}' : '';

        todaySessions.add({
          'id': g.id,
          'targetKey': 'group_${g.id}',
          'domain': 'groups',
          'day': currentDay,
          'name': g.name,
          'grade': '${g.grade} (مجموعة دروس)',
          'subject': '',
          'room': roomStr,
          'startTime': g.startTime,
          'endTime': g.endTime,
          'startMinutes': sMin,
          'endMinutes': eMin,
          'timeDisplay': timeDisplay,
          'isReserve': false,
          'isSchool': false,
          'alreadyAttended': attendedGroupIds.contains(g.id),
        });
      }

      // Sort today's sessions strictly by start time ascending
      todaySessions.sort((a, b) => (a['startMinutes'] as int).compareTo(b['startMinutes'] as int));

      if (todaySessions.isNotEmpty) {
        Map<String, dynamic>? chosenSession;
        String? badgeText;
        Color? badgeBg;
        Color? badgeColor;
        String? title;
        String? buttonText;

        // Priority 1: An ongoing session right now!
        for (final s in todaySessions) {
          final sMin = s['startMinutes'] as int;
          final eMin = s['endMinutes'] as int;
          if (nowMinutes >= sMin && nowMinutes < eMin) {
            chosenSession = s;
            final isSchool = s['isSchool'] == true;
            title = isSchool ? 'الحصة المدرسية الجارية الآن ⚡' : 'درس المجموعة الجاري الآن ⚡';
            badgeText = 'جارية الآن 🔴';
            badgeBg = const Color(0xFFEF4444).withValues(alpha: 0.25);
            badgeColor = const Color(0xFFF87171);
            buttonText = 'عرض في الجدول المحدد ⚡';
            break;
          }
        }

        // Priority 2: Earliest upcoming session today (strictly the earliest!)
        if (chosenSession == null) {
          for (final s in todaySessions) {
            final sMin = s['startMinutes'] as int;
            if (sMin > nowMinutes) {
              chosenSession = s;
              final isSchool = s['isSchool'] == true;
              final minsRemaining = sMin - nowMinutes;
              title = isSchool ? 'الحصة المدرسية القادمة اليوم ⏰' : 'الدرس القادم اليوم ⏰';
              badgeText = (minsRemaining > 0 && minsRemaining <= 60)
                  ? 'بعد $minsRemaining دقيقة ⏳'
                  : 'في الموعد ⏰';
              badgeBg = const Color(0xFFF59E0B).withValues(alpha: 0.20);
              badgeColor = const Color(0xFFD97706);
              buttonText = 'عرض في الجدول المحدد ⚡';
              break;
            }
          }
        }

        // Priority 3: If no upcoming session, find any session today waiting for attendance
        if (chosenSession == null) {
          for (final s in todaySessions) {
            if (s['isSchool'] == false && s['alreadyAttended'] == false) {
              chosenSession = s;
              title = 'حصة اليوم (بانتظار رصد الحضور ⚠️)';
              badgeText = 'رصد الحضور مطلوب ⚠️';
              badgeBg = const Color(0xFFF59E0B).withValues(alpha: 0.25);
              badgeColor = const Color(0xFFF59E0B);
              buttonText = 'رصد حضور الحصة الآن ✍️';
              break;
            }
          }
        }

        // Priority 4: All today sessions have completed
        if (chosenSession == null) {
          final last = todaySessions.last;
          chosenSession = last;
          title = 'اكتملت حصص اليوم المجدولة ✅';
          badgeText = 'مكتمل اليوم ✅';
          badgeBg = const Color(0xFF10B981).withValues(alpha: 0.20);
          badgeColor = const Color(0xFF34D399);
          buttonText = 'عرض الجدول الأسبوعي 📋';
        }

        final currentIndex = todaySessions.indexOf(chosenSession) + 1;
        final nextSessionAfterChosen = todaySessions
            .where((s) => (s['startMinutes'] as int) > (chosenSession!['startMinutes'] as int))
            .firstOrNull;

        return {
          ...chosenSession,
          'title': title,
          'badgeText': badgeText,
          'badgeBg': badgeBg,
          'badgeColor': badgeColor,
          'buttonText': buttonText,
          'isToday': true,
          'todayTotalCount': todaySessions.length,
          'todayIndex': currentIndex,
          'nextUpcomingName': nextSessionAfterChosen?['name'],
          'nextUpcomingTime': nextSessionAfterChosen?['timeDisplay'],
        };
      }

      // Check tomorrow's sessions (School + Groups) when late night or today had 0 sessions
      final List<Map<String, dynamic>> tomorrowSessions = [];

      for (final p in schoolPeriods) {
        if (p.isRecess) continue;
        if (!_matchesDayStrict(p.dayOfWeek, tomorrowWeekday)) continue;
        int sMin = _parseTimeStrToMinutes(p.startTime);
        if (sMin == 24 * 60) sMin = 8 * 60 + (p.periodNumber - 1) * 50;

        final periodLabel = p.periodNumber > 0 ? 'الحصة ${p.periodNumber}' : 'حصة مدرسية';
        final classTitle = p.className.startsWith('فصل') ? p.className : 'فصل ${p.className}';
        final nameDisplay = p.subject.isNotEmpty ? '$classTitle • ${p.subject}' : classTitle;

        tomorrowSessions.add({
          'id': p.id,
          'targetKey': 'period_${p.id}',
          'domain': 'school',
          'day': p.dayOfWeek,
          'name': nameDisplay,
          'grade': periodLabel,
          'room': p.room.isNotEmpty ? (p.room.contains('معمل') ? p.room : 'معمل/فصل ${p.room}') : '',
          'timeDisplay': 'غداً • ${p.startTime}',
          'startMinutes': sMin,
          'isSchool': true,
        });
      }

      for (final g in groupsList) {
        if (!g.isActive) continue;
        if (!_matchesDayStrict(g.schedule, tomorrowWeekday) && !_matchesDayStrict(g.days, tomorrowWeekday)) continue;
        int sMin = getGroupMinutes(g, tomorrowWeekday);
        final timeLabel = _formatMinutesToLabel(sMin, g.startTime, g.schedule);

        tomorrowSessions.add({
          'id': g.id,
          'targetKey': 'group_${g.id}',
          'domain': 'groups',
          'day': tomorrowDay,
          'name': g.name,
          'grade': '${g.grade} (مجموعة دروس)',
          'room': g.room.isNotEmpty ? 'قاعة ${g.room}' : '',
          'timeDisplay': 'غداً • $timeLabel',
          'startMinutes': sMin,
          'isSchool': false,
        });
      }

      if (tomorrowSessions.isNotEmpty) {
        tomorrowSessions.sort((a, b) => (a['startMinutes'] as int).compareTo(b['startMinutes'] as int));
        final t = tomorrowSessions.first;
        return {
          ...t,
          'title': 'حصة الغد الأولى 📅',
          'badgeText': 'غداً 📅',
          'badgeBg': const Color(0xFF3B82F6).withValues(alpha: 0.20),
          'badgeColor': const Color(0xFF60A5FA),
          'buttonText': 'عرض جدول الغد 📅',
          'isToday': false,
        };
      }

      // Fallback
      if (todaySessions.isNotEmpty) {
        final last = todaySessions.last;
        return {
          ...last,
          'title': 'اكتملت حصص اليوم ✅',
          'badgeText': 'مكتمل ✅',
          'badgeBg': const Color(0xFF10B981).withValues(alpha: 0.20),
          'badgeColor': const Color(0xFF34D399),
          'buttonText': 'عرض جدول الحصص 📋',
          'isToday': true,
        };
      }

      if (groupsList.isNotEmpty) {
        final first = groupsList.first;
        return {
          'id': first.id,
          'targetKey': 'group_${first.id}',
          'domain': 'groups',
          'day': currentDay,
          'name': first.name,
          'grade': first.grade,
          'schedule': first.schedule,
          'timeDisplay': first.startTime,
          'room': first.room.isNotEmpty ? 'قاعة ${first.room}' : '',
          'title': 'مجموعات الدروس',
          'badgeText': 'نشطة ✨',
          'badgeBg': const Color(0xFF6366F1).withValues(alpha: 0.20),
          'badgeColor': const Color(0xFF818CF8),
          'buttonText': 'إدارة المجموعات 👥',
          'isToday': false,
        };
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Widget _buildDrawerSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDrawerTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isSelected = false,
    String? badge,
    Color? badgeColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: isDark ? 0.22 : 0.12)
                : (isDark ? Colors.white.withValues(alpha: 0.035) : Colors.black.withValues(alpha: 0.025)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? color.withValues(alpha: 0.6)
                  : (isDark ? const Color(0xFF334155).withValues(alpha: 0.5) : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              if (isSelected)
                Container(
                  width: 3.5,
                  height: 30,
                  margin: const EdgeInsetsDirectional.only(end: 8),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected ? color : color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  widget.themeController.resolveIcon(icon),
                  color: isSelected ? Colors.white : color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isSelected
                                  ? (isDark ? Colors.white : color)
                                  : (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? color).withValues(alpha: isSelected ? 0.9 : 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : (badgeColor ?? color),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSettingsTab(int tabIndex) {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          database: widget.database,
          themeController: widget.themeController,
          initialTab: tabIndex,
          onNavConfigChanged: _loadUiConfig,
        ),
      ),
    ).then((_) {
      _loadHeaderInfo();
      _loadUiConfig();
    });
  }

  Widget _buildDrawerSubTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            widget.themeController.resolveIcon(icon),
            color: color,
            size: 18,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 12,
          color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _KineticDockIconTab extends StatelessWidget {
  final int index;
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final bool isDark;
  final double iconSize;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _KineticDockIconTab({
    required this.index,
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.isDark,
    this.iconSize = 22.0,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(26),
      splashColor: const Color(0x2200F2FE),
      highlightColor: Colors.transparent,
      child: Center(
        child: AnimatedScale(
          scale: isActive ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Icon(
              isActive ? activeIcon : icon,
              size: iconSize,
              color: isActive
                  ? const Color(0xFF00F2FE)
                  : (isDark
                        ? const Color(0xFF8E9BAE)
                        : const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }
}

class _KineticMenuCenterButton extends StatefulWidget {
  final bool isDark;
  final Color primaryColor;
  final VoidCallback onTap;

  const _KineticMenuCenterButton({
    required this.isDark,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  State<_KineticMenuCenterButton> createState() =>
      _KineticMenuCenterButtonState();
}

class _KineticMenuCenterButtonState extends State<_KineticMenuCenterButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTapDown: (_) => setState(() => _scale = 0.88),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: () {
        setState(() => _scale = 1.0);
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      borderRadius: BorderRadius.circular(24),
      splashColor: const Color(0x3300F2FE),
      highlightColor: Colors.transparent,
      child: Center(
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: widget.isDark
                    ? [const Color(0xFF16294D), const Color(0xFF0C1930)]
                    : [const Color(0xFFE2E8F0), const Color(0xFFF1F5F9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: const Color(
                  0xFF00F2FE,
                ).withValues(alpha: widget.isDark ? 0.6 : 0.4),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF00F2FE,
                  ).withValues(alpha: widget.isDark ? 0.25 : 0.12),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.grid_view_rounded,
                size: 21,
                color: Color(0xFF00F2FE),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
