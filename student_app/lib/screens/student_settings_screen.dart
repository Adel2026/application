import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'tabs/settings_tab.dart';

class StudentSettingsScreen extends StatelessWidget {
  const StudentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('الإعدادات والملف الشخصي ⚙️'),
        centerTitle: true,
      ),
      body: const SettingsTab(),
    );
  }
}
