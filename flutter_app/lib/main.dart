import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/cloud_sync_service.dart';
import 'core/database/database_service.dart';
import 'core/daily_report_service.dart';
import 'core/notification_service.dart';
import 'core/theme_controller.dart';
import 'screens/home_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // قفل اتجاه الشاشة عمودياً فقط لمنع التدوير التلقائي
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize Firebase Cloud Backend with offline persistence
  try {
    await Firebase.initializeApp();
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // Initialize Database service & in-memory cache
  final database = DatabaseService();
  CloudSyncService.instance.initialize(database);
  final themeController = ThemeController(database);
  final appNavKey = GlobalKey<NavigatorState>();
  NotificationService.navigatorKey = appNavKey;
  NotificationService.databaseService = database;

  runApp(
    EduAcademyApp(
      database: database,
      themeController: themeController,
      navigatorKey: appNavKey,
    ),
  );
}

class _StartupSplashScreen extends StatelessWidget {
  const _StartupSplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF8FAFC),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_rounded, size: 48, color: Color(0xFF2563EB)),
            SizedBox(height: 14),
            Text(
              'سنتر أستاذي التعليمي',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w700,
                fontFamily: 'Cairo',
              ),
            ),
            SizedBox(height: 20),
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

class DatabaseRecoveryApp extends StatelessWidget {
  const DatabaseRecoveryApp({
    super.key,
    required this.database,
    required this.themeController,
    required this.navigatorKey,
    required this.error,
  });

  final DatabaseService database;
  final ThemeController themeController;
  final GlobalKey<NavigatorState> navigatorKey;
  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Cairo',
        fontFamilyFallback: const ['Cairo', 'Segoe UI', 'sans-serif'],
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB45309)),
      ),
      home: _DatabaseRecoveryScreen(
        database: database,
        themeController: themeController,
        navigatorKey: navigatorKey,
        error: error,
      ),
    );
  }
}

class _DatabaseRecoveryScreen extends StatefulWidget {
  const _DatabaseRecoveryScreen({
    required this.database,
    required this.themeController,
    required this.navigatorKey,
    required this.error,
  });

  final DatabaseService database;
  final ThemeController themeController;
  final GlobalKey<NavigatorState> navigatorKey;
  final String error;

  @override
  State<_DatabaseRecoveryScreen> createState() =>
      _DatabaseRecoveryScreenState();
}

class _DatabaseRecoveryScreenState extends State<_DatabaseRecoveryScreen> {
  bool _isRestoring = false;
  String? _status;

  Future<void> _restoreFromBackup() async {
    setState(() {
      _isRestoring = true;
      _status = null;
    });

    var launchMainApp = false;
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (selection.isEmpty) return;

      final sourcePath = selection.first.path;
      if (sourcePath == null) {
        _setStatus('تعذر قراءة مسار ملف النسخة الاحتياطية.');
        return;
      }

      final isValid = await widget.database.isDatabaseBackupValid(sourcePath);
      if (!isValid) {
        _setStatus(
          'النسخة غير صالحة أو مفتاح التشفير لا يطابقها. لم يتم تغيير البيانات.',
        );
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('استعادة النسخة الاحتياطية؟'),
          content: const Text(
            'تم التحقق من النسخة. سيحتفظ التطبيق بالقاعدة الحالية قبل استبدالها.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('استعادة'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final restored = await widget.database.restoreDatabase(sourcePath);
      if (!restored) {
        _setStatus('لم تكتمل الاستعادة. لم يتم حذف النسخة الأصلية.');
        return;
      }

      await Future.wait([
        widget.database.preloadSettings(),
        widget.themeController.loadTheme(),
        NotificationService.initialize(),
      ]);
      NotificationService.requestPermissions();
      if (!mounted) return;

      launchMainApp = true;
      runApp(
        EduAcademyApp(
          database: widget.database,
          themeController: widget.themeController,
          navigatorKey: widget.navigatorKey,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(widget.database.ensureDailyBackup());
      });
    } catch (error) {
      _setStatus('تعذرت الاستعادة: $error');
    } finally {
      if (mounted && !launchMainApp) {
        setState(() => _isRestoring = false);
      }
    }
  }

  void _setStatus(String message) {
    if (mounted) setState(() => _status = message);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.storage_rounded,
                      size: 48,
                      color: Color(0xFFB45309),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'تعذر فتح قاعدة بيانات التطبيق',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'لم يتم حذف بياناتك. يمكنك اختيار نسخة احتياطية؛ لن يستبدل التطبيق القاعدة إلا بعد التحقق منها وموافقتك.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      widget.error,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 12),
                      Text(_status!, textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _isRestoring ? null : _restoreFromBackup,
                      icon: _isRestoring
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.folder_open_rounded),
                      label: Text(
                        _isRestoring
                            ? 'جارٍ التحقق...'
                            : 'اختيار نسخة احتياطية',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EduAcademyApp extends StatefulWidget {
  const EduAcademyApp({
    super.key,
    required this.database,
    required this.themeController,
    required this.navigatorKey,
  });

  final DatabaseService database;
  final ThemeController themeController;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<EduAcademyApp> createState() => _EduAcademyAppState();
}

class _EduAcademyAppState extends State<EduAcademyApp> {
  String? _startupError;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      unawaited(_initializeBackgroundServices());

      // Auto-restore backup if database is freshly installed or empty
      await widget.database.autoRestoreIfEmpty();

      await Future.wait<void>([
        widget.database.preloadSettings(),
        widget.themeController.loadTheme(),
      ]);

      if (!mounted) return;
      setState(() => _isReady = true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(widget.database.ensureDailyBackup());
      });
    } catch (error, stackTrace) {
      debugPrint('App startup initialization failed: $error\n$stackTrace');
      if (mounted) setState(() => _startupError = error.toString());
    }
  }

  Future<void> _initializeBackgroundServices() async {
    try {
      await NotificationService.initialize();
      NotificationService.requestPermissions();
      NotificationService.handlePendingNotificationLaunch();
      await DailyReportService.instance.init(database: widget.database);
      await NotificationService.cancelTomorrowGroupsPrepNotification();
    } catch (error) {
      debugPrint('Background services initialization warning: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = widget.themeController;
    final database = widget.database;
    final navigatorKey = widget.navigatorKey;

    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final currentOption = themeController.currentColor;
        final primaryLight = currentOption.lightColor;
        final primaryDark = currentOption.darkColor;

        final isAr = themeController.isArabic;
        const font = 'Cairo';

        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: isAr ? 'سنتر أستاذي التعليمي' : 'Edu Academy Hub',
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: themeController.themeMode,

          // Safe Text Scaler Guard, Status Bar Tint & Enforce RTL across all pages
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: themeController.isDarkMode
                    ? Brightness.light
                    : Brightness.dark,
                statusBarBrightness: themeController.isDarkMode
                    ? Brightness.dark
                    : Brightness.light,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: themeController.isDarkMode
                    ? Brightness.light
                    : Brightness.dark,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: MediaQuery(
                  data: mediaQuery,
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(fontFamily: 'Cairo'),
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },

          // Light Theme
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryLight,
              brightness: Brightness.light,
              primary: primaryLight,
              surface: Colors.white,
            ),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(themeController.cardRadius),
                side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(themeController.cardRadius),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  themeController.cardRadius.clamp(8.0, 20.0),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  themeController.cardRadius.clamp(8.0, 20.0),
                ),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  themeController.cardRadius.clamp(8.0, 20.0),
                ),
                borderSide: BorderSide(color: primaryLight, width: 2),
              ),
            ),
            iconTheme: IconThemeData(
              fill: themeController.iconStyle == 'rounded' ? 1.0 : 0.0,
              weight: themeController.iconStyle == 'rounded' ? 700.0 : 400.0,
            ),
            fontFamily: font,
            fontFamilyFallback: const ['Cairo', 'Segoe UI', 'sans-serif'],
            textTheme: ThemeData.light().textTheme.apply(
              fontFamily: font,
            ),
          ),

          // Dark Theme
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF071022),
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryDark,
              brightness: Brightness.dark,
              primary: primaryDark,
              surface: const Color(0xFF0E1E38),
            ),
            cardTheme: CardThemeData(
              color: const Color(0xFF0E1E38),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(themeController.cardRadius),
                side: const BorderSide(color: Color(0xFF24426D), width: 1),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: const Color(0xFF0C1C38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(themeController.cardRadius),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF0A172C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  themeController.cardRadius.clamp(8.0, 20.0),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  themeController.cardRadius.clamp(8.0, 20.0),
                ),
                borderSide: const BorderSide(color: Color(0xFF233F6B)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  themeController.cardRadius.clamp(8.0, 20.0),
                ),
                borderSide: BorderSide(color: primaryDark, width: 2),
              ),
            ),
            iconTheme: IconThemeData(
              fill: themeController.iconStyle == 'rounded' ? 1.0 : 0.0,
              weight: themeController.iconStyle == 'rounded' ? 700.0 : 400.0,
            ),
            fontFamily: font,
            fontFamilyFallback: const ['Cairo', 'Segoe UI', 'sans-serif'],
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: font,
            ),
          ),

          home: _startupError != null
              ? _DatabaseRecoveryScreen(
                  database: database,
                  themeController: themeController,
                  navigatorKey: navigatorKey,
                  error: _startupError!,
                )
              : !_isReady
                  ? const _StartupSplashScreen()
                  : HomeShell(database: database, themeController: themeController),
        );
      },
    );
  }
}
