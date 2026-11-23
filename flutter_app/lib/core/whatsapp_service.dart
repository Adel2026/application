import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'database/database_service.dart';

class WhatsAppDispatchResult {
  final bool success;
  final bool sentViaApi;
  final String? errorMessage;
  final int? statusCode;
  final bool alreadySent;

  const WhatsAppDispatchResult({
    required this.success,
    this.sentViaApi = false,
    this.errorMessage,
    this.statusCode,
    this.alreadySent = false,
  });
}

class WhatsAppService {
  static final Set<String> _sentNoticeKeys = {};

  static String generateNoticeKey({
    required String phone,
    String? studentId,
    required String category,
    String? message,
    String? date,
  }) {
    final cleanPhone = formatPhone(phone);
    final dStr = date ?? DateTime.now().toIso8601String().substring(0, 10);
    if (studentId != null && studentId.isNotEmpty) {
      return '${cleanPhone}_${studentId}_${category}_$dStr';
    }
    final hash = message != null ? message.trim().hashCode.toString() : '';
    return '${cleanPhone}_${category}_${hash}_$dStr';
  }

  static Future<bool> isMessageAlreadySentToday({
    required DatabaseService database,
    required String phone,
    String? studentId,
    required String category,
    String? message,
    String? date,
  }) async {
    final dStr = date ?? DateTime.now().toIso8601String().substring(0, 10);

    // Strict student-ID check against the permanent database ledger
    if (studentId != null && studentId.trim().isNotEmpty) {
      final isSentStrict = await database.isMessageSentStrict(
        studentId: studentId.trim(),
        category: category,
        contextKey: dStr,
      );
      if (isSentStrict) return true;
    }

    final key = generateNoticeKey(
      phone: phone,
      studentId: studentId,
      category: category,
      message: message,
      date: date,
    );
    if (_sentNoticeKeys.contains(key)) return true;

    try {
      final db = await database.database;
      final cleanPhone = formatPhone(phone);
      final rows = await db.rawQuery('''
        SELECT id FROM whatsapp_logs
        WHERE phone = ?
          AND category = ?
          AND sent_at LIKE ?
          AND status IN ('sent_api', 'sent_manual', 'opened_whatsapp', 'sent')
        LIMIT 1
      ''', [cleanPhone, category, '$dStr%']);
      if (rows.isNotEmpty) {
        _sentNoticeKeys.add(key);
        return true;
      }
    } catch (_) {}
    return false;
  }

  static void markNoticeAsSent({
    required String phone,
    String? studentId,
    required String category,
    String? message,
    String? date,
  }) {
    final key = generateNoticeKey(
      phone: phone,
      studentId: studentId,
      category: category,
      message: message,
      date: date,
    );
    _sentNoticeKeys.add(key);
  }

  /// Replace standard dynamic placeholders in message templates
  static String replacePlaceholders(
    String template, {
    String? studentName,
    String? parentName,
    String? parentPhone,
    String? studentPhone,
    String? groupName,
    String? centerName,
    String? teacherName,
    String? amount,
    String? date,
    String? time,
    String? examTitle,
    String? score,
    String? maxScore,
    String? lessonTitle,
    String? lessonContent,
    String? homework,
    String? notes,
    String? attendanceStatus,
    String? recitationRating,
    String? homeworkStatus,
    String? nextQuiz,
    String? previousHomeworkReview,
    String? previousLessonReview,
  }) {
    String text = template;
    if (studentName != null && studentName.isNotEmpty) {
      text = text
          .replaceAll('{student_name}', studentName)
          .replaceAll('{اسم_الطالب}', studentName)
          .replaceAll('{student}', studentName)
          .replaceAll('{طالب}', studentName);
    }
    if (parentName != null && parentName.isNotEmpty) {
      text = text
          .replaceAll('{parent_name}', parentName)
          .replaceAll('{ولي_الامر}', parentName)
          .replaceAll('{ولي_الأمر}', parentName)
          .replaceAll('{parent}', parentName);
    }
    if (parentPhone != null && parentPhone.isNotEmpty) {
      text = text
          .replaceAll('{parent_phone}', parentPhone)
          .replaceAll('{هاتف_ولي_الأمر}', parentPhone)
          .replaceAll('{هاتف_الولي}', parentPhone);
    }
    if (studentPhone != null && studentPhone.isNotEmpty) {
      text = text
          .replaceAll('{student_phone}', studentPhone)
          .replaceAll('{هاتف_الطالب}', studentPhone);
    }
    if (groupName != null && groupName.isNotEmpty) {
      text = text
          .replaceAll('{group_name}', groupName)
          .replaceAll('{المجموعة}', groupName)
          .replaceAll('{group}', groupName);
    }
    if (centerName != null && centerName.isNotEmpty) {
      text = text
          .replaceAll('{center_name}', centerName)
          .replaceAll('{السنتر}', centerName)
          .replaceAll('{المركز}', centerName);
    }
    if (teacherName != null && teacherName.isNotEmpty) {
      text = text
          .replaceAll('{teacher_name}', teacherName)
          .replaceAll('{المعلم}', teacherName)
          .replaceAll('{المدرس}', teacherName);
    }
    if (amount != null && amount.isNotEmpty) {
      text = text
          .replaceAll('{amount}', amount)
          .replaceAll('{المبلغ}', amount);
    }
    if (date != null && date.isNotEmpty) {
      text = text
          .replaceAll('{date}', date)
          .replaceAll('{التاريخ}', date);
    }
    if (time != null && time.isNotEmpty) {
      text = text
          .replaceAll('{time}', time)
          .replaceAll('{الوقت}', time)
          .replaceAll('{الساعة}', time);
    }
    if (examTitle != null && examTitle.isNotEmpty) {
      text = text
          .replaceAll('{exam_title}', examTitle)
          .replaceAll('{عنوان_الامتحان}', examTitle)
          .replaceAll('{الامتحان}', examTitle);
    }
    if (score != null && score.isNotEmpty) {
      text = text
          .replaceAll('{score}', score)
          .replaceAll('{الدرجة}', score);
    }
    if (maxScore != null && maxScore.isNotEmpty) {
      text = text
          .replaceAll('{max_score}', maxScore)
          .replaceAll('{الدرجة_القصوى}', maxScore);
    }
    if (lessonTitle != null && lessonTitle.isNotEmpty) {
      text = text
          .replaceAll('{lesson_title}', lessonTitle)
          .replaceAll('{موضوع_الدرس}', lessonTitle)
          .replaceAll('{الدرس}', lessonTitle);
    }
    if (lessonContent != null && lessonContent.isNotEmpty) {
      text = text
          .replaceAll('{lesson_content}', lessonContent)
          .replaceAll('{عناصر_الشرح}', lessonContent)
          .replaceAll('{المحتوى}', lessonContent);
    }
    if (homework != null && homework.isNotEmpty) {
      text = text
          .replaceAll('{homework}', homework)
          .replaceAll('{الواجب}', homework);
    }
    if (notes != null && notes.isNotEmpty) {
      text = text
          .replaceAll('{notes}', notes)
          .replaceAll('{ملاحظات}', notes);
    }
    if (attendanceStatus != null && attendanceStatus.isNotEmpty) {
      text = text
          .replaceAll('{attendance_status}', attendanceStatus)
          .replaceAll('{حالة_الحضور}', attendanceStatus)
          .replaceAll('{الحضور}', attendanceStatus);
    }
    if (recitationRating != null && recitationRating.isNotEmpty) {
      text = text
          .replaceAll('{recitation_rating}', recitationRating)
          .replaceAll('{تقييم_التسميع}', recitationRating)
          .replaceAll('{التسميع}', recitationRating);
    }
    if (homeworkStatus != null && homeworkStatus.isNotEmpty) {
      text = text
          .replaceAll('{homework_status}', homeworkStatus)
          .replaceAll('{تقييم_الواجب}', homeworkStatus)
          .replaceAll('{حالة_الواجب}', homeworkStatus);
    }
    if (nextQuiz != null && nextQuiz.isNotEmpty) {
      text = text
          .replaceAll('{next_quiz}', nextQuiz)
          .replaceAll('{كويز_الحصة_القادمة}', nextQuiz)
          .replaceAll('{الاستعداد_للحصة_القادمة}', nextQuiz);
    }
    if (previousHomeworkReview != null && previousHomeworkReview.isNotEmpty) {
      text = text
          .replaceAll('{previous_homework_review}', previousHomeworkReview)
          .replaceAll('{ملاحظات_الواجب}', previousHomeworkReview);
    }
    if (previousLessonReview != null && previousLessonReview.isNotEmpty) {
      text = text
          .replaceAll('{previous_lesson_review}', previousLessonReview)
          .replaceAll('{موضوع_المراجعة}', previousLessonReview);
    }
    return text;
  }

  static String formatPhone(String phone) {
    // 1. Normalize Eastern Arabic & Persian digits to ASCII
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    for (int i = 0; i < 10; i++) {
      phone = phone.replaceAll(arabicDigits[i], '$i');
      phone = phone.replaceAll(persianDigits[i], '$i');
    }

    String clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.startsWith('00')) {
      clean = clean.substring(2);
    }
    // Egypt mobile: 010, 011, 012, 015
    if (clean.startsWith('01') && clean.length == 11) {
      clean = '2$clean';
    } else if (clean.startsWith('1') && clean.length == 10) {
      clean = '20$clean';
    }
    // Saudi Arabia mobile: 05xxxxxxxx -> 9665xxxxxxxx
    else if (clean.startsWith('05') && clean.length == 10) {
      clean = '966${clean.substring(1)}';
    }
    // Jordan mobile: 07xxxxxxxx -> 9627xxxxxxxx
    else if (clean.startsWith('07') && clean.length == 10) {
      clean = '962${clean.substring(1)}';
    }
    // UAE mobile: 05xxxxxxxx -> 9715xxxxxxxx
    else if (clean.startsWith('05') && clean.length == 9) {
      clean = '971${clean.substring(1)}';
    }
    // Kuwait mobile: 8 digits
    else if ((clean.startsWith('5') || clean.startsWith('6') || clean.startsWith('9')) && clean.length == 8) {
      clean = '965$clean';
    }
    return clean;
  }

  // --- Manual open via WhatsApp app ---
  static Future<bool> openWhatsApp({
    required String phone,
    required String message,
    DatabaseService? database,
    String? studentId,
    String? studentName,
    String recipientType = 'parent',
    String category = 'custom',
    bool logToHistory = true,
    File? imageFile,
  }) async {
    final cleanPhone = formatPhone(phone);
    if (cleanPhone.length < 7) {
      if (logToHistory && database != null) {
        await database.logWhatsAppMessage(
          studentId: studentId,
          studentName: studentName,
          phone: phone,
          recipientType: recipientType,
          category: category,
          message: message,
          status: 'failed',
          errorMessage: 'رقم الهاتف غير صالح ($phone)',
        );
      }
      return false;
    }

    String effectiveMessage = message;
    final db = database ?? DatabaseService.shared;
    if (db != null) {
      effectiveMessage = await appendFooterIfNeeded(db, message, category: category);
    }

    if (imageFile != null && imageFile.existsSync()) {
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile(
                imageFile.path,
                name: 'Report_${cleanPhone}.png',
                mimeType: 'image/png',
              ),
            ],
            text: effectiveMessage,
          ),
        );
        if (logToHistory && db != null) {
          await db.logWhatsAppMessage(
            studentId: studentId,
            studentName: studentName,
            phone: cleanPhone,
            recipientType: recipientType,
            category: category,
            message: effectiveMessage,
            status: 'sent_manual',
          );
        }
        return true;
      } catch (e) {
        debugPrint('Error sharing image via SharePlus: $e');
      }
    }

    final targetPackage = await db?.getSetting('whatsapp_app_package', defaultValue: 'auto') ?? 'auto';
    final encodedMessage = Uri.encodeComponent(effectiveMessage);

    // If a specific package is selected on Android (com.whatsapp or com.whatsapp.w4b)
    if (Platform.isAndroid && (targetPackage == 'com.whatsapp' || targetPackage == 'com.whatsapp.w4b')) {
      final pkgIntentUri = Uri.parse(
        'intent://send?phone=$cleanPhone&text=$encodedMessage#Intent;package=$targetPackage;scheme=whatsapp;end',
      );
      try {
        if (await canLaunchUrl(pkgIntentUri)) {
          final launched = await launchUrl(pkgIntentUri, mode: LaunchMode.externalApplication);
          if (launched) {
            if (logToHistory && db != null) {
              await db.logWhatsAppMessage(
                studentId: studentId,
                studentName: studentName,
                phone: cleanPhone,
                recipientType: recipientType,
                category: category,
                message: effectiveMessage,
                status: 'sent_manual',
              );
            }
            return true;
          }
        }
      } catch (_) {}
    }

    // 1. Native WhatsApp App URI (Preferred: opens WhatsApp/WhatsApp Business directly without browser)
    final nativeUri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encodedMessage');

    // 2. Official WhatsApp API Deep Link (Android system routes this directly to WhatsApp app)
    final apiDeepLink = Uri.parse('https://api.whatsapp.com/send?phone=$cleanPhone&text=$encodedMessage');

    // 3. Fallback Web URI
    final webUri = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMessage');

    bool launchedSuccess = false;

    // Attempt 1: Direct native scheme with canLaunchUrl check
    try {
      if (await canLaunchUrl(nativeUri)) {
        launchedSuccess = await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    // Attempt 2: Direct native launch without checking canLaunchUrl (some Android OEM skins report false but launch succeeds)
    if (!launchedSuccess) {
      try {
        launchedSuccess = await launchUrl(nativeUri, mode: LaunchMode.externalNonBrowserApplication);
      } catch (_) {}
    }

    // Attempt 3: Official API deep link
    if (!launchedSuccess) {
      try {
        if (await canLaunchUrl(apiDeepLink)) {
          launchedSuccess = await launchUrl(apiDeepLink, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    }

    // Attempt 4: Web wa.me link with external application
    if (!launchedSuccess) {
      try {
        launchedSuccess = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    // Attempt 5: Fallback to platform default browser
    if (!launchedSuccess) {
      try {
        launchedSuccess = await launchUrl(webUri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }

    if (logToHistory && db != null) {
      await db.logWhatsAppMessage(
        studentId: studentId,
        studentName: studentName,
        phone: cleanPhone,
        recipientType: recipientType,
        category: category,
        message: effectiveMessage,
        status: launchedSuccess ? 'sent_manual' : 'failed',
        errorMessage: launchedSuccess ? null : 'تعذر فتح تطبيق واتساب على الجهاز',
      );
    }

    if (launchedSuccess && db != null && studentId != null && studentId.trim().isNotEmpty) {
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      await db.recordSentMessage(
        studentId: studentId.trim(),
        category: category,
        contextKey: todayStr,
        phone: cleanPhone,
        status: 'sent_manual',
      );
    }

    return launchedSuccess;
  }

  static Future<bool> makeCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    return await launchUrl(uri);
  }

  // --- Automated send via HTTP REST API ---
  static Future<Map<String, dynamic>> sendViaApi({
    required String endpointUrl,
    required String apiKey,
    required String instanceId,
    required String phone,
    required String message,
    String provider = 'custom',
    File? imageFile,
  }) async {
    final cleanPhone = formatPhone(phone);
    if (endpointUrl.trim().isEmpty) {
      return {'success': false, 'error': 'رابط الـ API غير محدد'};
    }

    try {
      String? base64Img;
      String? dataUri;
      try {
        if (imageFile != null && imageFile.existsSync()) {
          final bytes = await imageFile.readAsBytes();
          base64Img = base64Encode(bytes);
          dataUri = 'data:image/png;base64,$base64Img';
        }
      } catch (_) {}
      var normalizedUrl = endpointUrl.trim();
      if (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
        normalizedUrl = 'https://$normalizedUrl';
      }

      final trimmedKey = apiKey.trim();
      final trimmedInstance = instanceId.trim();
      final prov = provider.toLowerCase();

      // Auto-correct / normalize provider endpoint URLs
      final isWhatsPro = prov == 'whatspro' || normalizedUrl.contains('whats-pro.net');

      if (isWhatsPro) {
        // Fix incomplete URLs or missing messages/send
        if (normalizedUrl.endsWith('/backend/p') ||
            normalizedUrl.endsWith('/backend/p/') ||
            normalizedUrl.endsWith('/backend/panel') ||
            normalizedUrl.endsWith('/backend/profile') ||
            normalizedUrl.endsWith('/backend') ||
            normalizedUrl.endsWith('/backend/') ||
            normalizedUrl.endsWith('/api/send') ||
            normalizedUrl == 'https://whats-pro.net' ||
            normalizedUrl == 'https://whats-pro.net/') {
          normalizedUrl = 'https://whats-pro.net/backend/public/index.php/api/messages/send';
        } else if (!normalizedUrl.contains('/messages/send')) {
          if (normalizedUrl.endsWith('/api')) {
            normalizedUrl = '$normalizedUrl/messages/send';
          } else if (normalizedUrl.endsWith('/api/')) {
            normalizedUrl = '${normalizedUrl}messages/send';
          } else if (!normalizedUrl.contains('/api/')) {
            normalizedUrl = normalizedUrl.replaceAll(RegExp(r'/+$'), '');
            normalizedUrl = '$normalizedUrl/backend/public/index.php/api/messages/send';
          }
        }
      } else if (prov == 'ultramsg' && trimmedInstance.isNotEmpty) {
        if (normalizedUrl.contains('/instance/')) {
          normalizedUrl = normalizedUrl.replaceAll('/instance/', '/$trimmedInstance/');
        } else if (!normalizedUrl.contains('/messages/chat')) {
          normalizedUrl = normalizedUrl.replaceAll(RegExp(r'/+$'), '');
          if (!normalizedUrl.contains(trimmedInstance)) {
            normalizedUrl = '$normalizedUrl/$trimmedInstance/messages/chat';
          } else {
            normalizedUrl = '$normalizedUrl/messages/chat';
          }
        }
      } else if (prov == 'evolution' && trimmedInstance.isNotEmpty) {
        if (normalizedUrl.endsWith('/instance')) {
          normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 8) + trimmedInstance;
        } else if (!normalizedUrl.contains('/message/sendText')) {
          normalizedUrl = normalizedUrl.replaceAll(RegExp(r'/+$'), '');
          normalizedUrl = '$normalizedUrl/message/sendText/$trimmedInstance';
        }
      }

      var uri = Uri.parse(normalizedUrl);
      if (isWhatsPro) {
        final currentParams = Map<String, String>.from(uri.queryParameters);
        if (trimmedKey.isNotEmpty) {
          currentParams.putIfAbsent('token', () => trimmedKey);
          currentParams.putIfAbsent('access_token', () => trimmedKey);
          currentParams.putIfAbsent('api_key', () => trimmedKey);
        }
        if (trimmedInstance.isNotEmpty) {
          currentParams.putIfAbsent('instance_id', () => trimmedInstance);
          currentParams.putIfAbsent('device_id', () => trimmedInstance);
        }
        uri = uri.replace(queryParameters: currentParams.isNotEmpty ? currentParams : null);
      }

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      // Support self-hosted certificates without handshake exceptions
      client.badCertificateCallback = ((X509Certificate cert, String host, int port) => true);

      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Accept', 'application/json');

      Map<String, dynamic> payload;

      switch (prov) {
        case 'whatspro':
          if (trimmedKey.isNotEmpty) {
            request.headers.set('Authorization', 'Bearer $trimmedKey');
            request.headers.set('token', trimmedKey);
            request.headers.set('Token', trimmedKey);
            request.headers.set('access-token', trimmedKey);
            request.headers.set('apikey', trimmedKey);
          }
          if (trimmedInstance.isNotEmpty) {
            request.headers.set('instance-id', trimmedInstance);
            request.headers.set('device-id', trimmedInstance);
          }
          payload = {
            'send_phone': true,
            'phones': [cleanPhone],
            'send_group': false,
            'group_id': 0,
            'send_client': false,
            'client_ids': <int>[],
            'client_default_phone': true,
            'send_all_clients': false,
            'img': dataUri,
            'image': dataUri,
            'media': dataUri,
            'channel': 'whatsapp',
            'message': message,
            // Additional aliases
            'phone': cleanPhone,
            'receiver': cleanPhone,
            'to': cleanPhone,
            'number': cleanPhone,
            'body': message,
            'text': message,
            if (trimmedKey.isNotEmpty) ...{
              'token': trimmedKey,
              'access_token': trimmedKey,
              'api_key': trimmedKey,
            },
            if (trimmedInstance.isNotEmpty) ...{
              'instance_id': trimmedInstance,
              'instanceId': trimmedInstance,
              'instance': trimmedInstance,
              'device_id': trimmedInstance,
              'deviceId': trimmedInstance,
              'session_id': trimmedInstance,
              'sessionId': trimmedInstance,
              'account_id': trimmedInstance,
            },
          };
          break;

        case 'ultramsg':
          // UltraMsg API
          if (trimmedKey.isNotEmpty) {
            request.headers.set('token', trimmedKey);
          }
          payload = {
            'token': trimmedKey,
            'to': cleanPhone,
            'body': message,
            if (dataUri != null) 'image': dataUri,
            if (dataUri != null) 'caption': message,
          };
          break;

        case 'evolution':
          // Evolution API
          if (trimmedKey.isNotEmpty) {
            request.headers.set('apikey', trimmedKey);
          }
          payload = {
            'number': cleanPhone,
            'text': message,
            if (trimmedInstance.isNotEmpty) 'instance': trimmedInstance,
            if (base64Img != null) ...{
              'media': base64Img,
              'mediatype': 'image',
              'mimetype': 'image/png',
              'fileName': 'report.png',
              'caption': message,
            },
          };
          break;

        case 'wassenger':
          // Wassenger API
          if (trimmedKey.isNotEmpty) {
            request.headers.set('Token', trimmedKey);
          }
          final wassengerPhone = cleanPhone.startsWith('+') ? cleanPhone : '+$cleanPhone';
          payload = {
            'phone': wassengerPhone,
            'message': message,
            if (base64Img != null) 'media': {'data': base64Img, 'format': 'image/png'},
          };
          break;

        case 'custom':
        default:
          // Universal / Custom Webhook payload
          if (trimmedKey.isNotEmpty) {
            if (trimmedKey.toLowerCase().startsWith('bearer ')) {
              request.headers.set('Authorization', trimmedKey);
            } else {
              request.headers.set('Authorization', 'Bearer $trimmedKey');
              request.headers.set('x-api-key', trimmedKey);
              request.headers.set('apikey', trimmedKey);
              request.headers.set('token', trimmedKey);
              request.headers.set('Token', trimmedKey);
              request.headers.set('access-token', trimmedKey);
            }
          }
          if (trimmedInstance.isNotEmpty) {
            request.headers.set('instance-id', trimmedInstance);
            request.headers.set('device-id', trimmedInstance);
          }
          payload = {
            'send_phone': true,
            'phones': [cleanPhone],
            'send_group': false,
            'group_id': 0,
            'send_client': false,
            'client_ids': <int>[],
            'client_default_phone': false,
            'send_all_clients': false,
            'img': dataUri ?? '',
            'image': dataUri ?? '',
            'media': base64Img ?? '',
            'caption': message,
            'phone': cleanPhone,
            'to': cleanPhone,
            'receiver': cleanPhone,
            'chatId': '$cleanPhone@c.us',
            'number': cleanPhone,
            'message': message,
            'body': message,
            'text': message,
            if (trimmedKey.isNotEmpty) ...{
              'token': trimmedKey,
              'access_token': trimmedKey,
              'api_key': trimmedKey,
            },
            if (trimmedInstance.isNotEmpty) ...{
              'instanceId': trimmedInstance,
              'instance_id': trimmedInstance,
              'instance': trimmedInstance,
              'device_id': trimmedInstance,
              'sessionId': trimmedInstance,
              'session_id': trimmedInstance,
            },
          };
          break;
      }

      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      final isHttpSuccess = response.statusCode >= 200 && response.statusCode < 300;
      var isSuccess = isHttpSuccess;
      String? errorMessage;

      if (!isHttpSuccess) {
        String serverDetail = '';
        if (responseBody.isNotEmpty) {
          try {
            final parsed = jsonDecode(responseBody);
            if (parsed is Map) {
              if (parsed['errors'] != null) {
                final errs = parsed['errors'];
                if (errs is Map) {
                  final list = <String>[];
                  errs.forEach((k, v) {
                    if (v is List) {
                      list.add('$k: ${v.join(", ")}');
                    } else {
                      list.add('$k: $v');
                    }
                  });
                  if (list.isNotEmpty) {
                    serverDetail = list.join(' \n ');
                  }
                } else if (errs is List) {
                  serverDetail = errs.join(' \n ');
                } else {
                  serverDetail = errs.toString();
                }
              }
              if (serverDetail.isEmpty) {
                serverDetail = (parsed['message'] ?? parsed['error'] ?? parsed['msg'] ?? '').toString();
              }
            }
          } catch (_) {}
        }

        final lowerDetail = serverDetail.toLowerCase();

        if (lowerDetail == 'invalid_token' || (lowerDetail.contains('token') && lowerDetail.contains('invalid'))) {
          errorMessage = 'رمز التوثيق (Token) غير صحيح أو منتهي الصلاحية في Whats-Pro. انسخ الـ Token الصحيح من حسابك في whats-pro.net.';
        } else if (lowerDetail == 'no_token_provided') {
          errorMessage = 'لم يتم إرسال رمز التوثيق (Token). يرجى لصق الـ Token في خانة رمز التوثيق.';
        } else if (lowerDetail.contains('session') || lowerDetail.contains('connect') || lowerDetail.contains('qr')) {
          errorMessage = 'رقم الواتساب غير متصل في موقع Whats-Pro! ادخل على حسابك في whats-pro.net وامسح رمز QR لربط رقمك أولاً.';
        } else if (lowerDetail.contains('balance') || lowerDetail.contains('credit') || lowerDetail.contains('limit') || lowerDetail.contains('plan') || lowerDetail.contains('subscription')) {
          errorMessage = 'رصيد الرسائل أو باقة حسابك في Whats-Pro منتهية. يرجى شحن الرصيد لتتمكن من الإرسال.';
        } else if (serverDetail.isNotEmpty) {
          errorMessage = 'رد السيرفر (كود ${response.statusCode}): $serverDetail';
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          errorMessage = 'رمز التوثيق (Token/API Key) غير صحيح أو منتهي الصلاحية (كود ${response.statusCode}).';
        } else if (response.statusCode == 404) {
          errorMessage = 'الرابط غير موجود أو السيرفر رفض الطلب (كود 404). تأكد من صحة الرابط والـ Token.';
        } else if (response.statusCode == 400 || response.statusCode == 422) {
          errorMessage = 'طلب غير صالح (كود ${response.statusCode}): راجع رقم الهاتف ($cleanPhone).';
        } else {
          errorMessage = 'كود الخطأ: ${response.statusCode} - $responseBody';
        }
      } else {
        // Inspect body for internal API errors even on 200 OK (e.g. UltraMsg error payload)
        if (responseBody.isNotEmpty) {
          try {
            final parsed = jsonDecode(responseBody);
            if (parsed is Map) {
              if (parsed['success'] == false || parsed['success'] == 'false') {
                isSuccess = false;
                final msg = (parsed['message'] ?? parsed['error'] ?? responseBody).toString();
                final lowerMsg = msg.toLowerCase();
                if (lowerMsg == 'invalid_token' || (lowerMsg.contains('token') && lowerMsg.contains('invalid'))) {
                  errorMessage = 'رمز التوثيق (Token) غير صحيح في Whats-Pro.';
                } else if (lowerMsg.contains('session') || lowerMsg.contains('connect')) {
                  errorMessage = 'رقم الواتساب غير متصل في Whats-Pro. امسح كود QR أولاً من الموقع.';
                } else {
                  errorMessage = 'رفض السيرفر الإرسال: $msg';
                }
              } else if (parsed['sent'] == 'false' || parsed['sent'] == false) {
                isSuccess = false;
                errorMessage = 'رفض السيرفر الإرسال: ${parsed['message'] ?? parsed['error'] ?? responseBody}';
              } else if (parsed['error'] != null && parsed['error'] != false && parsed['error'] != '') {
                isSuccess = false;
                final errStr = parsed['error'].toString();
                if (errStr.toLowerCase().contains('instance not connected') || errStr.toLowerCase().contains('not connected')) {
                  errorMessage = 'النسخة غير متصلة برقم الواتساب. امسح رمز الـ QR من لوحة التحكم أولاً.';
                } else if (errStr.toLowerCase().contains('token') || errStr.toLowerCase().contains('unauthorized')) {
                  errorMessage = 'رمز التوثيق (Token) غير صحيح.';
                } else {
                  errorMessage = 'خطأ من السيرفر: $errStr';
                }
              }
            }
          } catch (_) {
            // Non-JSON 200 OK response is still treated as success
          }
        }
      }

      return {
        'success': isSuccess,
        'statusCode': response.statusCode,
        'response': responseBody,
        'error': isSuccess ? null : errorMessage,
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'تعذر الاتصال بالخادم: $e',
      };
    }
  }

  // --- Footer Helper ---
  static Future<String> appendFooterIfNeeded(
    DatabaseService database,
    String message, {
    String? category,
  }) async {
    try {
      if (message.trim().isEmpty) return '';
      final enableFooter = await database.getSetting('whatsapp_enable_footer', defaultValue: 'true');
      if (enableFooter != 'true') return message;

      String trimmedFooter = '';
      if (category != null && category.isNotEmpty) {
        trimmedFooter = (await database.getCategoryFooter(category)).trim();
      }

      if (trimmedFooter.isEmpty) {
        var footer = await database.getSetting('whatsapp_message_footer', defaultValue: '');
        trimmedFooter = footer.trim();

        // If user enabled footer but hasn't customized it yet, generate a clean default from center profile
        if (trimmedFooter.isEmpty) {
          final cName = await database.getSetting('center_name', defaultValue: '');
          final teacherName = await database.getSetting('teacher_name', defaultValue: '');
          final phone = await database.getSetting('phone', defaultValue: '');
          final name = cName.isNotEmpty ? cName : (teacherName.isNotEmpty ? teacherName : '');
          if (name.isNotEmpty || phone.isNotEmpty) {
            final phonePart = phone.isNotEmpty ? '\n📞 للتواصل والاستفسار: $phone' : '';
            trimmedFooter = '---\n📍 $name$phonePart';
            await database.setSetting('whatsapp_message_footer', trimmedFooter);
          }
        }
      }

      if (trimmedFooter.isEmpty) return message;

      final normMsg = message.replaceAll('\r\n', '\n');
      final normFooter = trimmedFooter.replaceAll('\r\n', '\n');
      if (!normMsg.contains(normFooter)) {
        return '$normMsg\n\n$normFooter';
      }
    } catch (_) {}
    return message;
  }

  // --- Smart Dispatcher: Detailed Result ---
  static Future<WhatsAppDispatchResult> dispatchMessageDetailed({
    required DatabaseService database,
    required String phone,
    required String message,
    bool forceManual = false,
    bool isAutomatic = false,
    String? studentId,
    String? studentName,
    String recipientType = 'parent',
    String category = 'custom',
    bool logResult = true,
    File? imageFile,
  }) async {
    // 0. Append configurable footer if enabled and not already present
    final effectiveMessage = await appendFooterIfNeeded(database, message, category: category);

    // Strict deduplication check: Do not re-send if already sent today for this student
    final alreadySent = await isMessageAlreadySentToday(
      database: database,
      phone: phone,
      studentId: studentId,
      category: category,
      message: effectiveMessage,
    );
    if (alreadySent) {
      return const WhatsAppDispatchResult(
        success: true,
        sentViaApi: false,
        errorMessage: 'تم إرسال هذا الإشعار للطالب مسبقاً بنجاح ✅',
        alreadySent: true,
      );
    }

    if (forceManual) {
      final ok = await openWhatsApp(
        phone: phone,
        message: effectiveMessage,
        database: database,
        studentId: studentId,
        studentName: studentName,
        recipientType: recipientType,
        category: category,
        logToHistory: logResult,
        imageFile: imageFile,
      );
      if (ok) {
        markNoticeAsSent(
          phone: phone,
          studentId: studentId,
          category: category,
          message: effectiveMessage,
        );
      }
      return WhatsAppDispatchResult(
        success: ok,
        sentViaApi: false,
        errorMessage: ok ? null : 'تعذر فتح تطبيق واتساب',
      );
    }

    final mode = await database.getSetting('whatsapp_mode', defaultValue: 'manual');
    if (mode == 'api') {
      final endpoint = await database.getSetting('whatsapp_api_endpoint', defaultValue: '');
      final apiKey = await database.getSetting('whatsapp_api_key', defaultValue: '');
      final instanceId = await database.getSetting('whatsapp_api_instance', defaultValue: '');
      final provider = await database.getSetting('whatsapp_api_provider', defaultValue: 'custom');

      if (endpoint.trim().isEmpty) {
        if (isAutomatic) {
          if (logResult) {
            await database.logWhatsAppMessage(
              studentId: studentId,
              studentName: studentName,
              phone: phone,
              recipientType: recipientType,
              category: category,
              message: effectiveMessage,
              status: 'failed',
              errorMessage: 'رابط الـ API غير محدد في الإعدادات',
            );
          }
          return const WhatsAppDispatchResult(
            success: false,
            sentViaApi: true,
            errorMessage: 'رابط الـ API غير محدد في الإعدادات',
          );
        }
        final ok = await openWhatsApp(
          phone: phone,
          message: effectiveMessage,
          database: database,
          studentId: studentId,
          studentName: studentName,
          recipientType: recipientType,
          category: category,
          logToHistory: logResult,
          imageFile: imageFile,
        );
        if (ok) {
          markNoticeAsSent(
            phone: phone,
            studentId: studentId,
            category: category,
            message: effectiveMessage,
          );
        }
        return WhatsAppDispatchResult(
          success: ok,
          sentViaApi: false,
          errorMessage: 'رابط الـ API فارغ، تم التحويل للتطبيق اليدوي',
        );
      }

      final res = await sendViaApi(
        endpointUrl: endpoint,
        apiKey: apiKey,
        instanceId: instanceId,
        phone: phone,
        message: effectiveMessage,
        provider: provider,
        imageFile: imageFile,
      );

      final isSuccess = res['success'] == true;
      if (logResult) {
        await database.logWhatsAppMessage(
          studentId: studentId,
          studentName: studentName,
          phone: phone,
          recipientType: recipientType,
          category: category,
          message: effectiveMessage,
          status: isSuccess ? 'sent_api' : 'failed',
          errorMessage: isSuccess ? null : (res['error']?.toString() ?? 'فشل الاتصال بخادم الـ API'),
        );
      }

      if (isSuccess) {
        markNoticeAsSent(
          phone: phone,
          studentId: studentId,
          category: category,
          message: effectiveMessage,
        );
        if (studentId != null && studentId.trim().isNotEmpty) {
          final todayStr = DateTime.now().toIso8601String().substring(0, 10);
          await database.recordSentMessage(
            studentId: studentId.trim(),
            category: category,
            contextKey: todayStr,
            phone: phone,
            status: 'sent_api',
          );
        }
        return const WhatsAppDispatchResult(success: true, sentViaApi: true);
      } else {
        return WhatsAppDispatchResult(
          success: false,
          sentViaApi: true,
          errorMessage: res['error']?.toString() ?? 'فشل الاتصال بخادم الـ API',
          statusCode: res['statusCode'] as int?,
        );
      }
    }

    // Manual mode
    if (isAutomatic) {
      if (logResult) {
        await database.logWhatsAppMessage(
          studentId: studentId,
          studentName: studentName,
          phone: phone,
          recipientType: recipientType,
          category: category,
          message: effectiveMessage,
          status: 'skipped',
          errorMessage: 'وضع الإرسال محدد على يدوي (لم يُرسل آلياً)',
        );
      }
      return const WhatsAppDispatchResult(
        success: false,
        sentViaApi: false,
        errorMessage: 'وضع الإرسال محدد على يدوي',
      );
    }

    final ok = await openWhatsApp(
      phone: phone,
      message: effectiveMessage,
      database: database,
      studentId: studentId,
      studentName: studentName,
      recipientType: recipientType,
      category: category,
      logToHistory: logResult,
    );
    if (ok) {
      markNoticeAsSent(
        phone: phone,
        studentId: studentId,
        category: category,
        message: effectiveMessage,
      );
    }
    return WhatsAppDispatchResult(
      success: ok,
      sentViaApi: false,
      errorMessage: ok ? null : 'تعذر فتح تطبيق واتساب',
    );
  }

  // --- Smart Dispatcher: Auto API or Manual Fallback ---
  static Future<bool> dispatchMessage({
    required DatabaseService database,
    required String phone,
    required String message,
    bool forceManual = false,
    bool isAutomatic = false,
    String? studentId,
    String? studentName,
    String recipientType = 'parent',
    String category = 'custom',
    bool logResult = true,
    File? imageFile,
  }) async {
    final result = await dispatchMessageDetailed(
      database: database,
      phone: phone,
      message: message,
      forceManual: forceManual,
      isAutomatic: isAutomatic,
      studentId: studentId,
      studentName: studentName,
      recipientType: recipientType,
      category: category,
      logResult: logResult,
      imageFile: imageFile,
    );
    // If API failed during non-automatic dispatch, fallback to manual for backward compatibility
    if (!result.success && result.sentViaApi && !isAutomatic) {
      return await openWhatsApp(
        phone: phone,
        message: message,
        database: database,
        studentId: studentId,
        studentName: studentName,
        recipientType: recipientType,
        category: category,
        logToHistory: logResult,
        imageFile: imageFile,
      );
    }
    return result.success;
  }

  // --- High-Level Automated Triggers ---

  /// Auto Send Attendance Confirmation Alert
  static Future<bool> autoSendAttendanceAlert({
    required DatabaseService database,
    required String studentName,
    required String parentPhone,
    DateTime? time,
    String? studentId,
  }) async {
    final enabled = await database.getSetting('whatsapp_auto_send_attendance', defaultValue: 'false');
    if (enabled != 'true') return false;
    if (parentPhone.trim().isEmpty) return false;

    final centerName = await database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل');
    final now = time ?? DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final message = attendanceConfirmationMessage(
      centerName: centerName,
      studentName: studentName,
      time: timeStr,
      date: dateStr,
    );

    return await dispatchMessage(
      database: database,
      phone: parentPhone,
      message: message,
      isAutomatic: true,
      studentId: studentId,
      studentName: studentName,
      recipientType: 'parent',
      category: 'attendance',
    );
  }

  /// Auto Send Absence Alert
  static Future<bool> autoSendAbsenceAlert({
    required DatabaseService database,
    required String studentName,
    required String parentPhone,
    DateTime? date,
    String? studentId,
  }) async {
    final enabled = await database.getSetting('whatsapp_auto_send_absence', defaultValue: 'false');
    if (enabled != 'true') return false;
    if (parentPhone.trim().isEmpty) return false;

    final centerName = await database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل');
    final teacherName = await database.getSetting('teacher_name', defaultValue: 'الأستاذ');
    final now = date ?? DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final message = absenceMessage(
      centerName: centerName,
      teacherName: teacherName,
      studentName: studentName,
      date: dateStr,
    );

    return await dispatchMessage(
      database: database,
      phone: parentPhone,
      message: message,
      isAutomatic: true,
      studentId: studentId,
      studentName: studentName,
      recipientType: 'parent',
      category: 'absence',
    );
  }

  /// Auto Send Payment Receipt
  static Future<bool> autoSendPaymentReceipt({
    required DatabaseService database,
    required String studentName,
    required String parentPhone,
    required double amount,
    required String type,
    String? date,
    String? studentId,
  }) async {
    final enabled = await database.getSetting('whatsapp_auto_send_payment', defaultValue: 'false');
    if (enabled != 'true') return false;
    if (parentPhone.trim().isEmpty) return false;

    final centerName = await database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل');
    final now = DateTime.now();
    final dateStr = date ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final message = paymentReceiptMessage(
      centerName: centerName,
      studentName: studentName,
      amount: amount,
      type: type,
      date: dateStr,
    );

    return await dispatchMessage(
      database: database,
      phone: parentPhone,
      message: message,
      isAutomatic: true,
      studentId: studentId,
      studentName: studentName,
      recipientType: 'parent',
      category: 'payment',
    );
  }

  /// Auto Send Exam Grade
  static Future<bool> autoSendExamScore({
    required DatabaseService database,
    required String studentName,
    required String parentPhone,
    required String examTitle,
    required double score,
    required double maxScore,
    String? note,
    String? studentId,
  }) async {
    final enabled = await database.getSetting('whatsapp_auto_send_exam', defaultValue: 'false');
    if (enabled != 'true') return false;
    if (parentPhone.trim().isEmpty) return false;

    final centerName = await database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل');
    final message = examScoreMessage(
      centerName: centerName,
      studentName: studentName,
      examTitle: examTitle,
      score: score,
      maxScore: maxScore,
      note: note,
    );

    return await dispatchMessage(
      database: database,
      phone: parentPhone,
      message: message,
      isAutomatic: true,
      studentId: studentId,
      studentName: studentName,
      recipientType: 'parent',
      category: 'exam',
    );
  }

  /// Safe Batch Sender with Anti-Ban Randomized Delay (Jitter between 2.5s and 4.5s)
  static Future<int> sendBatchMessagesWithDelay({
    required DatabaseService database,
    required List<Map<String, String>> messageQueue, // [{'phone': '...', 'message': '...'}]
    void Function(int sent, int total)? onProgress,
  }) async {
    int successCount = 0;
    final random = Random();

    for (int i = 0; i < messageQueue.length; i++) {
      final item = messageQueue[i];
      final phone = item['phone'] ?? '';
      final msg = item['message'] ?? '';

      if (phone.isNotEmpty && msg.isNotEmpty) {
        final ok = await dispatchMessage(
          database: database,
          phone: phone,
          message: msg,
        );
        if (ok) successCount++;
      }

      onProgress?.call(i + 1, messageQueue.length);

      // Apply Anti-Ban sleep only between messages (not after the last one)
      if (i < messageQueue.length - 1) {
        final delaySetting = await database.getSetting('whatsapp_send_delay_seconds', defaultValue: '5');
        final baseDelaySec = int.tryParse(delaySetting) ?? 5;
        final jitterMs = (baseDelaySec * 1000) + random.nextInt(800);
        await Future.delayed(Duration(milliseconds: jitterMs));
      }
    }
    return successCount;
  }

  // --- Bilingual Safe Helpers ---
  /// Checks if a string contains Latin characters (English letters)
  static bool hasLatin(String? text) {
    if (text == null || text.isEmpty) return false;
    return RegExp(r'[a-zA-Z]').hasMatch(text);
  }

  /// Master Default Template for Session Follow-up Reports
  static const String defaultSessionReportTemplate = '''السلام عليكم ورحمة الله وبركاته 🌸
ولي أمر الطالب المحترم:
{اسم_الطالب}
━━━━━━━━━━━━━━━━━━━━━
تقرير متابعة الحصة الدراسية
📅 التاريخ:
{التاريخ}
👥 المجموعة:
{المجموعة}
🏛️ السنتر:
{السنتر}
👨‍🏫 المعلم:
{المعلم}
📍 حالة الحضور:
{حالة_الحضور}
━━━━━━━━━━━━━━━━━━━━━
1️⃣ تصحيح وتقييم واجب الحصة السابقة:
• حالة أداء الواجب:
{تقييم_الواجب}
• ملاحظات الواجب:
{ملاحظات_الواجب}

2️⃣ مراجعة الدرس السابق والتسميع:
• موضوع المراجعة:
{موضوع_المراجعة}
• تقييم التسميع / الكويز:
{تقييم_التسميع}

3️⃣ ما تم شرحه اليوم في الحصة:
• موضوع الدرس:
{موضوع_الدرس}
• عناصر الشرح:
{عناصر_الشرح}

4️⃣ تكليفات الحصة القادمة:
• 📝 الواجب المطلوب:
{الواجب}
• 🎯 المطلوب الاستعداد لـ:
{كويز_الحصة_القادمة}

💡 ملاحظات المعلم:
{ملاحظات}
━━━━━━━━━━━━━━━━━━━━━
نرجو متابعة الطالب في المذاكرة وإنجاز التكليفات أولاً بأول.
بالتوفيق والتميز الدائم بإذن الله 🌟''';

  // --- Message Templates ---
  static String attendanceConfirmationMessage({
    required String centerName,
    required String studentName,
    required String time,
    required String date,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('السلام عليكم ورحمة الله وبركاته 🌸');
    if (hasLatin(studentName)) {
      buffer.writeln('ولي أمر الطالب المحترم:');
      buffer.writeln(studentName);
    } else {
      buffer.writeln('ولي أمر الطالب المحترم / $studentName');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('تم تسجيل حضور الطالب بنجاح:');
    if (hasLatin(centerName)) {
      buffer.writeln('🏛️ المركز / السنتر:\n$centerName');
    } else {
      buffer.writeln('🏛️ السنتر: $centerName');
    }
    buffer.writeln('📅 اليوم: $date');
    buffer.writeln('⏰ الساعة: $time');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.write('نتمنى له يوماً دراسياً موفقاً ومتميزاً 🌸');
    return buffer.toString();
  }

  static String paymentReceiptMessage({
    required String centerName,
    required String studentName,
    required double amount,
    required String type,
    required String date,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('إيصال سداد إلكتروني 🧾');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    if (hasLatin(centerName)) {
      buffer.writeln('🏛️ المركز / السنتر:\n$centerName');
    } else {
      buffer.writeln('🏛️ السنتر: $centerName');
    }
    if (hasLatin(studentName)) {
      buffer.writeln('👤 الطالب:\n$studentName');
    } else {
      buffer.writeln('👤 استلمنا من الطالب: $studentName');
    }
    buffer.writeln('💰 مبلغ وقدره: $amount ج.م');
    if (hasLatin(type)) {
      buffer.writeln('📋 عن:\n$type');
    } else {
      buffer.writeln('📋 عن: $type');
    }
    buffer.writeln('📅 بتاريخ: $date');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.write('شاكرين لكم حسن تعاونكم والتزامكم معنا دائماً ✨');
    return buffer.toString();
  }

  static String teacherCancellationMessage({
    required String centerName,
    required String teacherName,
    required String groupName,
    required String date,
    String reason = '',
    String? makeupInfo,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('السلام عليكم ورحمة الله وبركاته 🌸');
    if (hasLatin(groupName)) {
      buffer.writeln('أولياء أمور وطلاب مجموعة:');
      buffer.writeln(groupName);
    } else {
      buffer.writeln('أولياء أمور وطلاب مجموعة: $groupName');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('⚠️ إشعار هام: اعتذار عن موعد الحصة');
    if (centerName.isNotEmpty) {
      if (hasLatin(centerName)) {
        buffer.writeln('🏛️ السنتر:\n$centerName');
      } else {
        buffer.writeln('🏛️ السنتر: $centerName');
      }
    }
    if (teacherName.isNotEmpty) {
      if (hasLatin(teacherName)) {
        buffer.writeln('👨‍🏫 المدرس:\n$teacherName');
      } else {
        buffer.writeln('👨‍🏫 المدرس: $teacherName');
      }
    }
    buffer.writeln('📅 تاريخ الحصة: $date');
    if (reason.trim().isNotEmpty) {
      if (hasLatin(reason)) {
        buffer.writeln('📝 سبب الإلغاء:\n$reason');
      } else {
        buffer.writeln('📝 سبب الإلغاء: $reason');
      }
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('نعتذر عن عدم إمكانية إقامة حصة اليوم.');
    if (makeupInfo != null && makeupInfo.trim().isNotEmpty) {
      if (hasLatin(makeupInfo)) {
        buffer.writeln('⏳ الموعد البديل / التعويضي:\n$makeupInfo');
      } else {
        buffer.writeln('⏳ الموعد البديل / التعويضي: $makeupInfo');
      }
    } else {
      buffer.writeln('⏳ سيتم إبلاغكم وتحديد موعد الحصة التعويضية في أقرب وقت بمشيئة الله.');
    }
    buffer.writeln('شاكرين ومقدرين حسن تفهمكم وتعاونكم الدائم 🌟');
    return buffer.toString();
  }

  static String studentCancellationMessage({
    required String centerName,
    required String teacherName,
    required String studentName,
    required String groupName,
    required String date,
    String reason = '',
    String? makeupInfo,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('السلام عليكم ورحمة الله وبركاته 🌸');
    if (hasLatin(studentName)) {
      buffer.writeln('ولي أمر الطالب/ة الكريم:');
      buffer.writeln(studentName);
    } else {
      buffer.writeln('ولي أمر الطالب/ة الكريم / $studentName');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📋 إشعار استلام اعتذار الطالب عن الحصة');
    if (centerName.isNotEmpty) {
      if (hasLatin(centerName)) {
        buffer.writeln('🏛️ السنتر:\n$centerName');
      } else {
        buffer.writeln('🏛️ السنتر: $centerName');
      }
    }
    if (teacherName.isNotEmpty) {
      if (hasLatin(teacherName)) {
        buffer.writeln('👨‍🏫 المدرس:\n$teacherName');
      } else {
        buffer.writeln('👨‍🏫 المدرس: $teacherName');
      }
    }
    if (hasLatin(groupName)) {
      buffer.writeln('👥 المجموعة:\n$groupName');
    } else {
      buffer.writeln('👥 المجموعة: $groupName');
    }
    buffer.writeln('📅 تاريخ الحصة: $date');
    if (reason.trim().isNotEmpty) {
      if (hasLatin(reason)) {
        buffer.writeln('📝 سبب الاعتذار:\n$reason');
      } else {
        buffer.writeln('📝 سبب الاعتذار: $reason');
      }
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('تم تسجيل وتوثيق اعتذار الطالب/ة عن حضور الحصة.');
    if (makeupInfo != null && makeupInfo.trim().isNotEmpty) {
      if (hasLatin(makeupInfo)) {
        buffer.writeln('📅 موعد الحصة التعويضية:\n$makeupInfo');
      } else {
        buffer.writeln('📅 موعد الحصة التعويضية: $makeupInfo');
      }
    } else {
      buffer.writeln('💡 سيتم التنسيق معكم لتحديد موعد حصة تعويضية لشرح المحتوى والتكليفات.');
    }
    buffer.writeln('تمنياتنا للطالب بدوام التوفيق والتفوق دائماً 🌟');
    return buffer.toString();
  }

  static String absenceMessage({
    required String centerName,
    required String teacherName,
    required String studentName,
    required String date,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('السلام عليكم ورحمة الله وبركاته 🌸');
    if (hasLatin(studentName)) {
      buffer.writeln('ولي أمر الطالب المحترم:');
      buffer.writeln(studentName);
    } else {
      buffer.writeln('ولي أمر الطالب المحترم / $studentName');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('نود إبلاغكم بغياب الطالب عن حضور حصة اليوم:');
    buffer.writeln('📅 التاريخ: $date');
    if (hasLatin(centerName)) {
      buffer.writeln('🏛️ السنتر:\n$centerName');
    } else {
      buffer.writeln('🏛️ السنتر: $centerName');
    }
    if (hasLatin(teacherName)) {
      buffer.writeln('👨‍🏫 المعلم:\n$teacherName');
    } else {
      buffer.writeln('👨‍🏫 المعلم: $teacherName');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('نرجو الاطمئنان على الطالب والتواصل معنا لمعرفة الواجبات وموعد التعويض.');
    buffer.write('مع خالص التحيات والتقدير 🌸');
    return buffer.toString();
  }

  static String examScoreMessage({
    required String centerName,
    required String studentName,
    required String examTitle,
    required double score,
    required double maxScore,
    String? note,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('السلام عليكم ورحمة الله وبركاته 🌸');
    if (hasLatin(studentName)) {
      buffer.writeln('ولي أمر الطالب المحترم:');
      buffer.writeln(studentName);
    } else {
      buffer.writeln('ولي أمر الطالب / $studentName');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    if (hasLatin(centerName)) {
      buffer.writeln('🏛️ المركز / السنتر:\n$centerName');
    } else {
      buffer.writeln('🏛️ السنتر: $centerName');
    }
    if (hasLatin(examTitle)) {
      buffer.writeln('📝 نتيجة اختبار:\n$examTitle');
    } else {
      buffer.writeln('📝 نتيجة اختبار "$examTitle":');
    }
    buffer.writeln('🎯 الدرجة: $score من $maxScore');
    if (note != null && note.isNotEmpty) {
      if (hasLatin(note)) {
        buffer.writeln('💡 ملاحظة الأستاذ:\n$note');
      } else {
        buffer.writeln('💡 ملاحظة الأستاذ: $note');
      }
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.write('شاكرين حسن تعاونكم ودعمكم المستمر للمستوى الأكاديمي ✨');
    return buffer.toString();
  }

  static String duePaymentMessage({
    required String centerName,
    required String studentName,
    required double amount,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('السلام عليكم ورحمة الله وبركاته 🌸');
    if (hasLatin(studentName)) {
      buffer.writeln('ولي أمر الطالب الكريم:');
      buffer.writeln(studentName);
    } else {
      buffer.writeln('ولي أمر الطالب الكريم / $studentName');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('نحيطكم علماً بأن هناك مستحقات دراسية متأخرة:');
    if (hasLatin(centerName)) {
      buffer.writeln('🏛️ السنتر:\n$centerName');
    } else {
      buffer.writeln('🏛️ السنتر: $centerName');
    }
    buffer.writeln('💰 المبلغ المستحق: $amount ج.م');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.write('شاكرين ومقدرين حسن تعاونكم والتزامكم معنا دائماً 💐');
    return buffer.toString();
  }

  static String reminderMessage({
    required String centerName,
    required String studentName,
    required String schedule,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('تذكير بموعد الحصة القادمة 🔔');
    if (hasLatin(studentName)) {
      buffer.writeln('👤 الطالب:\n$studentName');
    } else {
      buffer.writeln('👤 الطالب / $studentName');
    }
    if (hasLatin(schedule)) {
      buffer.writeln('⏰ الموعد:\n$schedule');
    } else {
      buffer.writeln('⏰ الموعد: $schedule');
    }
    if (hasLatin(centerName)) {
      buffer.writeln('🏛️ في:\n$centerName');
    } else {
      buffer.writeln('🏛️ في: $centerName');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.write('برجاء الحضور في الموعد ومراجعة التكليفات المطلوبة. بالتوفيق دائماً!');
    return buffer.toString();
  }

  static String sessionFollowUpMessage({
    required String centerName,
    required String teacherName,
    required String studentName,
    required String groupName,
    required String date,
    required String lessonTitle,
    String? lessonContent,
    String? homework,
    String? notes,
    String? attendanceStatus,
    String? recitationRating,
    String? homeworkStatus,
    String? nextQuiz,
    String? previousHomeworkReview,
    String? previousLessonReview,
    String? customTemplate,
  }) {
    // If a custom template is provided, use template replacement
    if (customTemplate != null && customTemplate.trim().isNotEmpty) {
      String msg = replacePlaceholders(
        customTemplate,
        studentName: studentName,
        groupName: groupName,
        centerName: centerName,
        teacherName: teacherName,
        date: date,
        lessonTitle: lessonTitle,
        lessonContent: lessonContent,
        homework: homework,
        notes: notes,
        attendanceStatus: attendanceStatus,
        recitationRating: recitationRating,
        homeworkStatus: homeworkStatus,
        nextQuiz: nextQuiz,
        previousHomeworkReview: previousHomeworkReview,
        previousLessonReview: previousLessonReview,
      );
      // Clean up empty lines and unresolved placeholders
      msg = msg.replaceAll(RegExp(r'\{[^\}]+\}'), '');
      msg = msg.replaceAll(RegExp(r'\n{3,}'), '\n\n');
      return msg.trim();
    }

    final buffer = StringBuffer();
    buffer.writeln('السلام عليكم ورحمة الله وبركاته 🌸');
    if (hasLatin(studentName)) {
      buffer.writeln('ولي أمر الطالب المحترم:');
      buffer.writeln(studentName);
    } else {
      buffer.writeln('ولي أمر الطالب المحترم / $studentName');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('نحيطكم علماً بتقرير المتابعة لحصة اليوم:');
    buffer.writeln('📅 التاريخ: $date');
    if (hasLatin(groupName)) {
      buffer.writeln('👥 المجموعة:\n$groupName');
    } else {
      buffer.writeln('👥 المجموعة: $groupName');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    if (centerName.isNotEmpty) {
      if (hasLatin(centerName)) {
        buffer.writeln('🏛️ السنتر:\n$centerName');
      } else {
        buffer.writeln('🏛️ السنتر: $centerName');
      }
    }
    if (teacherName.isNotEmpty) {
      if (hasLatin(teacherName)) {
        buffer.writeln('👨‍🏫 المدرس:\n$teacherName');
      } else {
        buffer.writeln('👨‍🏫 المدرس: $teacherName');
      }
    }
    if (attendanceStatus != null && attendanceStatus.isNotEmpty) {
      if (hasLatin(attendanceStatus)) {
        buffer.writeln('📍 حالة الحضور:\n$attendanceStatus');
      } else {
        buffer.writeln('📍 حالة الحضور: $attendanceStatus');
      }
    }

    // 1️⃣ تصحيح واجب الحصة السابقة
    final hasHwStatus = homeworkStatus != null && homeworkStatus.trim().isNotEmpty;
    final hasPrevHwReview = previousHomeworkReview != null && previousHomeworkReview.trim().isNotEmpty;
    if (hasHwStatus || hasPrevHwReview) {
      buffer.writeln('\n1️⃣ تصحيح وتقييم واجب الحصة السابقة:');
      if (hasHwStatus) {
        if (hasLatin(homeworkStatus)) {
          buffer.writeln('   • حالة أداء الواجب:\n     $homeworkStatus');
        } else {
          buffer.writeln('   • حالة أداء الواجب: $homeworkStatus');
        }
      }
      if (hasPrevHwReview) {
        if (hasLatin(previousHomeworkReview)) {
          buffer.writeln('   • ملاحظات الواجب:\n     $previousHomeworkReview');
        } else {
          buffer.writeln('   • ملاحظات الواجب: $previousHomeworkReview');
        }
      }
    }

    // 2️⃣ مراجعة الدرس السابق والتسميع
    final hasRecitation = recitationRating != null && recitationRating.trim().isNotEmpty;
    final hasPrevLessonReview = previousLessonReview != null && previousLessonReview.trim().isNotEmpty;
    if (hasRecitation || hasPrevLessonReview) {
      buffer.writeln('\n2️⃣ مراجعة الدرس السابق والتسميع:');
      if (hasPrevLessonReview) {
        if (hasLatin(previousLessonReview)) {
          buffer.writeln('   • موضوع المراجعة:\n     $previousLessonReview');
        } else {
          buffer.writeln('   • موضوع المراجعة: $previousLessonReview');
        }
      }
      if (hasRecitation) {
        if (hasLatin(recitationRating)) {
          buffer.writeln('   • تقييم التسميع / الكويز:\n     $recitationRating');
        } else {
          buffer.writeln('   • تقييم التسميع / الكويز: $recitationRating');
        }
      }
    }

    final isAbsent = attendanceStatus != null &&
        (attendanceStatus.contains('غائب') ||
            attendanceStatus.contains('غياب') ||
            attendanceStatus.contains('اعتذار') ||
            attendanceStatus.contains('إلغاء'));

    // 3️⃣ ما تم شرحه اليوم في الحصة
    buffer.writeln(isAbsent ? '\n3️⃣ ما تم شرحه في الحصة (وفات الطالب لغيابه):' : '\n3️⃣ ما تم شرحه اليوم في الحصة:');
    if (hasLatin(lessonTitle)) {
      buffer.writeln('   • موضوع الدرس:\n     $lessonTitle');
    } else {
      buffer.writeln('   • موضوع الدرس: $lessonTitle');
    }
    if (lessonContent != null && lessonContent.trim().isNotEmpty && lessonContent.trim() != lessonTitle.trim()) {
      if (hasLatin(lessonContent)) {
        buffer.writeln('   • عناصر الشرح:\n     $lessonContent');
      } else {
        buffer.writeln('   • عناصر الشرح: $lessonContent');
      }
    }

    // 4️⃣ تكليفات الحصة القادمة
    final hasHomework = homework != null && homework.trim().isNotEmpty;
    final hasQuiz = nextQuiz != null && nextQuiz.trim().isNotEmpty;
    if (hasHomework || hasQuiz) {
      buffer.writeln(isAbsent ? '\n4️⃣ التكليفات والواجب المطلوب تعويضه ومذاكرته:' : '\n4️⃣ تكليفات الحصة القادمة:');
      if (hasHomework) {
        if (hasLatin(homework)) {
          buffer.writeln('   • 📝 الواجب المطلوب:\n     $homework');
        } else {
          buffer.writeln('   • 📝 الواجب المطلوب: $homework');
        }
      }
      if (hasQuiz) {
        if (hasLatin(nextQuiz)) {
          buffer.writeln('   • 🎯 المطلوب الاستعداد لـ:\n     $nextQuiz');
        } else {
          buffer.writeln('   • 🎯 المطلوب الاستعداد لـ: $nextQuiz');
        }
      }
    }

    // ملاحظات إضافية
    if (notes != null && notes.trim().isNotEmpty) {
      final header = isAbsent ? '\n⚠️ تنبيهات وملاحظات المتابعة لولي الأمر:' : '\n💡 ملاحظات المعلم:';
      if (hasLatin(notes)) {
        buffer.writeln('$header\n   $notes');
      } else {
        buffer.writeln('$header $notes');
      }
    }

    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('نرجو متابعة الطالب في المذاكرة وإنجاز التكليفات أولاً بأول.');
    buffer.write('بالتوفيق والتميز الدائم بإذن الله 🌟');

    return buffer.toString();
  }
}
