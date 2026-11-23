import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'database/database_service.dart';

class AppIconService {
  static const MethodChannel _channel = MethodChannel('com.example.teacher_center/shortcut');

  /// Check if the device / launcher supports creating pinned home screen shortcuts.
  static Future<bool> isPinShortcutSupported() async {
    try {
      final supported = await _channel.invokeMethod<bool>('isPinShortcutSupported');
      return supported ?? false;
    } catch (e) {
      debugPrint('Error checking pin shortcut support: $e');
      return false;
    }
  }

  /// Create or update a pinned shortcut on the Android Home Screen with a custom icon.
  /// Also sets the icon internally in the database as `custom_app_icon_path` and `custom_logo_path`.
  static Future<bool> setCustomAppIconAndPin({
    required DatabaseService database,
    required String sourceImagePath,
    String? customAppName,
  }) async {
    try {
      final file = File(sourceImagePath);
      if (!file.existsSync()) {
        throw Exception('ملف الصورة غير موجود');
      }

      // 1. Copy image into persistent app directory
      final appDir = await getApplicationDocumentsDirectory();
      final iconsDir = Directory(p.join(appDir.path, 'app_icons'));
      if (!iconsDir.existsSync()) {
        iconsDir.createSync(recursive: true);
      }

      final ext = p.extension(sourceImagePath).isEmpty ? '.png' : p.extension(sourceImagePath);
      final targetFileName = 'icon_${DateTime.now().millisecondsSinceEpoch}$ext';
      final permanentFile = await file.copy(p.join(iconsDir.path, targetFileName));

      // 2. Persist path in database settings
      await database.setSetting('custom_app_icon_path', permanentFile.path);
      await database.setSetting('custom_logo_path', permanentFile.path);

      // Notify listeners so headers, drawer, and lock screen reflect immediately
      database.notifyChange(DataChangeEvent.settings);

      // 3. Resolve app name
      String name = (customAppName ?? '').trim();
      if (name.isEmpty) {
        name = await database.getSetting('teacher_name', defaultValue: 'سنتر أستاذي');
      }

      // 4. Invoke native Android ShortcutManager
      final bool? success = await _channel.invokeMethod<bool>('createPinnedShortcut', {
        'imagePath': permanentFile.path,
        'appName': name,
      });

      return success ?? true;
    } catch (e) {
      debugPrint('AppIconService.setCustomAppIconAndPin error: $e');
      rethrow;
    }
  }

  /// Get current custom app icon path if set.
  static Future<String?> getCustomAppIconPath(DatabaseService database) async {
    final path = await database.getSetting('custom_app_icon_path', defaultValue: '');
    if (path.isNotEmpty && File(path).existsSync()) {
      return path;
    }
    final logoPath = await database.getSetting('custom_logo_path', defaultValue: '');
    if (logoPath.isNotEmpty && File(logoPath).existsSync()) {
      return logoPath;
    }
    return null;
  }

  /// Reset to standard default app icon and branding.
  static Future<void> resetCustomAppIcon(DatabaseService database) async {
    await database.setSetting('custom_app_icon_path', '');
    await database.setSetting('custom_logo_path', '');
    database.notifyChange(DataChangeEvent.settings);
  }
}
