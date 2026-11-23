import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'backup_service.dart';
import 'database/database_service.dart';

class GoogleDriveWebhookFile {
  final String id;
  final String name;
  final String createdTime;
  final String? size;
  final String? webViewLink;

  GoogleDriveWebhookFile({
    required this.id,
    required this.name,
    required this.createdTime,
    this.size,
    this.webViewLink,
  });

  factory GoogleDriveWebhookFile.fromJson(Map<String, dynamic> json) {
    return GoogleDriveWebhookFile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      createdTime: json['createdTime']?.toString() ?? '',
      size: json['size']?.toString(),
      webViewLink: json['webViewLink']?.toString(),
    );
  }
}

class GoogleWebhookService {
  /// Code for Google Apps Script to be deployed as Web App in Google Drive
  static const String defaultScriptCode = r'''/**
 * سكريبت مزامنة والنسخ الاحتياطي لمنظومة الأستاذ مع Google Drive
 * =========================================================
 * خطوات التفعيل في دقيقتين:
 * 1. افتح https://script.google.com واضغط "مشروع جديد (New Project)".
 * 2. امسح أي كود موجود والصق هذا الكود كاملاً مكانه، ثم اضغط حفظ (Ctrl + S).
 * 3. اضغط على الزر الأزرق أعلى اليمين: Deploy (نشر) -> New deployment (نشر جديد).
 * 4. بجوار نوع النشر (Select type) اضغط علامة الترس ⚙ واختر Web app.
 * 5. اضبط الإعدادات كالتالي:
 *    - Description: منظومة الأستاذ - مزامنة Google Drive
 *    - Execute as: Me (حسابك الشخصي)
 *    - Who has access: Anyone (أي شخص يملك الرابط) - هام جداً لكي تستطيع المنظومة الإرسال والاستقبال
 * 6. اضغط Deploy وامنح الأذونات لحسابك (Authorize access).
 * 7. انسخ رابط الـ Web app URL وضعه في إعدادات المنظومة.
 */

const FOLDER_NAME = "نسخ_منظومة_الأستاذ_الاحتياطية";

function getOrCreateBackupFolder() {
  const folders = DriveApp.getFoldersByName(FOLDER_NAME);
  if (folders.hasNext()) {
    return folders.next();
  }
  return DriveApp.createFolder(FOLDER_NAME);
}

function createJsonResponse(data) {
  return ContentService.createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

function doGet(e) {
  try {
    const action = (e && e.parameter && e.parameter.action) || 'ping';
    if (action === 'ping') {
      return createJsonResponse({
        success: true,
        message: 'Google Webhook متصل ويعمل بنجاح!',
        userEmail: Session.getActiveUser().getEmail() || 'حساب Google متصل',
        folder: FOLDER_NAME
      });
    }
    if (action === 'list') {
      return createJsonResponse(listBackups());
    }
    return createJsonResponse({ 
      success: true, 
      message: 'خدمة مزامنة منظومة الأستاذ عبر Google Webhook جاهزة للاستخدام.' 
    });
  } catch (err) {
    return createJsonResponse({ success: false, error: err.toString() });
  }
}

function doPost(e) {
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return createJsonResponse({ success: false, error: 'لم يتم استلام أي بيانات في الطلب.' });
    }
    
    var payload;
    try {
      payload = JSON.parse(e.postData.contents);
    } catch (parseErr) {
      return createJsonResponse({ success: false, error: 'صيغة البيانات المستلمة ليست JSON صالحة.' });
    }

    var action = payload.action || 'backup';

    // فحص الاتصال
    if (action === 'ping' || action === 'test') {
      return createJsonResponse({
        success: true,
        message: 'تم الاتصال بـ Google Webhook بنجاح!',
        userEmail: Session.getActiveUser().getEmail() || 'حساب Google متصل',
        folder: FOLDER_NAME
      });
    }

    // رفع وحفظ نسخة احتياطية في مجلد Drive
    if (action === 'backup') {
      var folder = getOrCreateBackupFolder();
      var now = new Date();
      var dateStr = Utilities.formatDate(now, Session.getScriptTimeZone() || 'GMT+2', 'yyyy-MM-dd_HH-mm');
      var filename = payload.filename || ('tutoring_backup_' + dateStr + '.json');
      var content = typeof payload.data === 'string' ? payload.data : JSON.stringify(payload.data, null, 2);
      
      var file = folder.createFile(filename, content, MimeType.PLAIN_TEXT);
      return createJsonResponse({
        success: true,
        file: {
          id: file.getId(),
          name: file.getName(),
          createdTime: file.getDateCreated().toISOString(),
          size: file.getSize().toString(),
          webViewLink: file.getUrl()
        }
      });
    }

    // جلب قائمة النسخ
    if (action === 'list') {
      return createJsonResponse(listBackups());
    }

    // استرجاع نسخة محددة
    if (action === 'restore') {
      var fileId = payload.fileId;
      if (!fileId) {
        return createJsonResponse({ success: false, error: 'معرف الملف (fileId) غير موجود في الطلب.' });
      }
      var file = DriveApp.getFileById(fileId);
      var content = file.getBlob().getDataAsString();
      var jsonData = JSON.parse(content);
      return createJsonResponse({
        success: true,
        data: jsonData,
        fileName: file.getName()
      });
    }

    // حذف نسخة
    if (action === 'delete') {
      var fileIdToDelete = payload.fileId;
      if (!fileIdToDelete) {
        return createJsonResponse({ success: false, error: 'معرف الملف غير موجود.' });
      }
      var targetFile = DriveApp.getFileById(fileIdToDelete);
      targetFile.setTrashed(true);
      return createJsonResponse({ success: true, message: 'تم حذف النسخة الاحتياطية بنجاح.' });
    }

    return createJsonResponse({ success: false, error: 'إجراء غير مدعوم: ' + action });
  } catch (err) {
    return createJsonResponse({ success: false, error: err.toString() });
  }
}

function listBackups() {
  var folder = getOrCreateBackupFolder();
  var filesIter = folder.getFiles();
  var filesList = [];
  while (filesIter.hasNext()) {
    var f = filesIter.next();
    if (!f.isTrashed() && (f.getName().indexOf('.json') !== -1 || f.getName().indexOf('backup') !== -1)) {
      filesList.push({
        id: f.getId(),
        name: f.getName(),
        createdTime: f.getDateCreated().toISOString(),
        size: f.getSize().toString(),
        webViewLink: f.getUrl()
      });
    }
  }
  filesList.sort(function(a, b) {
    return new Date(b.createdTime).getTime() - new Date(a.createdTime).getTime();
  });
  return { success: true, files: filesList };
}
''';

  /// Validate if URL is a valid Google Apps Script Webhook URL
  static bool isValidUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
    final host = uri.host.toLowerCase();
    return (host == 'script.google.com' || host == 'script.googleusercontent.com') &&
        uri.path.contains('/macros/s/');
  }

  /// Sends a request to Google Apps Script Webhook, correctly handling Google 302 redirects
  static Future<http.Response> _sendGasRequest(Uri url, Map<String, dynamic> body) async {
    final client = http.Client();
    try {
      final request = http.Request('POST', url)
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = jsonEncode(body);

      final streamed = await client.send(request).timeout(const Duration(seconds: 45));

      // Google Apps Script redirects with 302 to script.googleusercontent.com/macros/echo?...
      if (streamed.statusCode == 302 || streamed.statusCode == 301 || streamed.statusCode == 307) {
        final redirectUrl = streamed.headers['location'];
        if (redirectUrl != null && redirectUrl.isNotEmpty) {
          final redirectUri = Uri.parse(redirectUrl);
          final res = await client.get(redirectUri).timeout(const Duration(seconds: 45));
          return res;
        }
      }

      return await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
  }

  /// Test connection to Google Apps Script Webhook
  static Future<Map<String, dynamic>> testConnection(String webhookUrl) async {
    if (!isValidUrl(webhookUrl)) {
      throw const FormatException('يرجى إدخال رابط Google Apps Script Webhook صالح يبدأ بـ https://script.google.com/macros/s/...');
    }

    final uri = Uri.parse(webhookUrl.trim());
    final response = await _sendGasRequest(uri, {'action': 'ping'});

    if (response.statusCode != 200) {
      throw Exception('تعذر الاتصال بـ Google Webhook (كود الاستجابة: ${response.statusCode}). يرجى التأكد من اختيار Who has access: Anyone عند النشر.');
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['success'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'استجاب Google Webhook برسالة غير متوقعة.');
    }

    return {
      'success': true,
      'userEmail': decoded['userEmail']?.toString() ?? 'حساب Google متصل',
      'folder': decoded['folder']?.toString() ?? 'نسخ_منظومة_الأستاذ_الاحتياطية',
      'message': decoded['message']?.toString() ?? 'تم الاتصال بـ Google Webhook بنجاح!',
    };
  }

  /// Upload a full backup snapshot to Google Drive via Webhook
  static Future<GoogleDriveWebhookFile> uploadBackup({
    required String webhookUrl,
    required DatabaseService database,
    String? customFilename,
  }) async {
    if (!isValidUrl(webhookUrl)) {
      throw const FormatException('رابط Google Webhook غير مضبوط أو غير صالح.');
    }

    final backupFile = await BackupService.exportPCBackupJSON(database);
    final jsonContent = await backupFile.readAsString();
    final dynamic jsonData = jsonDecode(jsonContent);

    final now = DateTime.now();
    final stamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
    final filename = customFilename ?? 'tutoring_backup_$stamp.json';

    final uri = Uri.parse(webhookUrl.trim());
    final response = await _sendGasRequest(uri, {
      'action': 'backup',
      'filename': filename,
      'data': jsonData,
    });

    if (response.statusCode != 200) {
      throw Exception('فشل رفع النسخة السحابية إلى Drive (كود: ${response.statusCode}).');
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['success'] != true || decoded['file'] == null) {
      throw Exception(decoded['error']?.toString() ?? 'فشلت عملية حفظ النسخة في Google Drive.');
    }

    // Save timestamp of last successful backup
    await database.setSetting('last_cloud_backup_time', now.toIso8601String());

    return GoogleDriveWebhookFile.fromJson(Map<String, dynamic>.from(decoded['file'] as Map));
  }

  /// List all backups stored in Google Drive folder
  static Future<List<GoogleDriveWebhookFile>> listBackups(String webhookUrl) async {
    if (!isValidUrl(webhookUrl)) {
      throw const FormatException('رابط Google Webhook غير مضبوط.');
    }

    final uri = Uri.parse(webhookUrl.trim());
    final response = await _sendGasRequest(uri, {'action': 'list'});

    if (response.statusCode != 200) {
      throw Exception('تعذر جلب النسخ من Google Drive (كود: ${response.statusCode}).');
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['success'] != true || decoded['files'] is! List) {
      throw Exception(decoded['error']?.toString() ?? 'فشل استرجاع قائمة النسخ من Drive.');
    }

    final filesList = (decoded['files'] as List)
        .map((f) => GoogleDriveWebhookFile.fromJson(Map<String, dynamic>.from(f as Map)))
        .toList();

    return filesList;
  }

  /// Download and restore a specific backup from Google Drive
  static Future<int> restoreBackup({
    required String webhookUrl,
    required String fileId,
    required DatabaseService database,
  }) async {
    if (!isValidUrl(webhookUrl)) {
      throw const FormatException('رابط Google Webhook غير مضبوط.');
    }

    final uri = Uri.parse(webhookUrl.trim());
    final response = await _sendGasRequest(uri, {
      'action': 'restore',
      'fileId': fileId,
    });

    if (response.statusCode != 200) {
      throw Exception('تعذر استرداد النسخة من Google Drive (كود: ${response.statusCode}).');
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['success'] != true || decoded['data'] == null) {
      throw Exception(decoded['error']?.toString() ?? 'فشل قراءة بيانات النسخة الاحتياطية.');
    }

    final jsonString = jsonEncode(decoded['data']);
    final count = await BackupService.importPCBackupJSON(jsonString, database);
    await database.preloadSettings();
    database.notifyChange(DataChangeEvent.all);
    return count;
  }

  /// Delete a backup file from Google Drive
  static Future<bool> deleteBackup({
    required String webhookUrl,
    required String fileId,
  }) async {
    if (!isValidUrl(webhookUrl)) return false;

    final uri = Uri.parse(webhookUrl.trim());
    final response = await _sendGasRequest(uri, {
      'action': 'delete',
      'fileId': fileId,
    });

    if (response.statusCode != 200) return false;
    final dynamic decoded = jsonDecode(response.body);
    return decoded is Map && decoded['success'] == true;
  }

  /// Check and execute scheduled automatic cloud backup
  static bool _isScheduledBackupRunning = false;
  static Future<bool> checkAndRunScheduledBackup(DatabaseService database) async {
    if (_isScheduledBackupRunning) return false;

    try {
      final enabled = await database.getSetting('auto_cloud_backup_enabled');
      if (enabled != 'true') return false;

      final webhookUrl = await database.getSetting('google_webhook_url');
      if (webhookUrl.isEmpty || !isValidUrl(webhookUrl)) return false;

      final savedTime = await database.getSetting('auto_cloud_backup_time', defaultValue: '22:00');
      final scheduledTime = savedTime.trim().isEmpty ? '22:00' : savedTime;
      final lastDate = await database.getSetting('last_auto_cloud_backup_date');

      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Check if already backed up today
      if (lastDate == todayStr) return false;

      // Parse scheduled hour and minute
      final parts = scheduledTime.split(':');
      final targetHour = int.tryParse(parts[0]) ?? 22;
      final targetMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

      final currentMinutes = now.hour * 60 + now.minute;
      final targetMinutes = targetHour * 60 + targetMinute;

      // If current time reached or passed the scheduled time
      if (currentMinutes >= targetMinutes) {
        _isScheduledBackupRunning = true;
        debugPrint('Starting scheduled cloud backup to Google Drive...');

        await uploadBackup(
          webhookUrl: webhookUrl,
          database: database,
          customFilename: 'auto_scheduled_backup_${todayStr}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.json',
        );

        await database.setSetting('last_auto_cloud_backup_date', todayStr);
        debugPrint('Scheduled cloud backup completed successfully ✅ for $todayStr');
        return true;
      }
    } catch (e) {
      debugPrint('Scheduled cloud backup error: $e');
    } finally {
      _isScheduledBackupRunning = false;
    }
    return false;
  }
}
