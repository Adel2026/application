import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/student_main_shell.dart';
import 'services/student_auth_service.dart';
import 'services/student_notification_sound_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // قفل اتجاه الشاشة عمودياً فقط لمنع التدوير التلقائي
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // تهيئة الفايربيز مع تفعيل التخزين المؤقت المحلي الدائم (0ms Latency)
  try {
    await Firebase.initializeApp();
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // تهيئة مصادقة وجلسة الطالب
  await StudentAuthService.instance.initialize();

  // تهيئة الإشعارات والأصوات وتصريح أندرويد
  try {
    await StudentNotificationSoundService.instance.initialize();
  } catch (e) {
    debugPrint('Notification service init error: $e');
  }

  runApp(const EduAcademyStudentApp());
}

class EduAcademyStudentApp extends StatelessWidget {
  const EduAcademyStudentApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = StudentAuthService.instance.isAuthenticated;

    return MaterialApp(
      title: 'Edu Academy - بوابة الطالب',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.darkTheme,
      home: isLoggedIn ? const StudentMainShell() : const LoginScreen(),
    );
  }
}
