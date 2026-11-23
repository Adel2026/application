import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ChatMediaUploadService {
  /// رفع ملف وسائط (صورة، مستند، تسجيل صوتي) إلى خادم التخزين السريع واسترجاع رابط مباشر دائم
  static Future<String?> uploadMediaFile(File file) async {
    try {
      if (!await file.exists()) return null;

      // 1. Try Catbox direct upload
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://catbox.moe/user/api.php'),
        );
        request.fields['reqtype'] = 'fileupload';
        request.files.add(await http.MultipartFile.fromPath('fileToUpload', file.path));

        final streamedResponse = await request.send().timeout(const Duration(seconds: 40));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200 && response.body.startsWith('http')) {
          return response.body.trim();
        }
      } catch (_) {}

      // 2. Fallback to tmpfiles.org
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://tmpfiles.org/api/v1/upload'),
        );
        request.files.add(await http.MultipartFile.fromPath('file', file.path));

        final streamedResponse = await request.send().timeout(const Duration(seconds: 40));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] == 'success' && data['data'] != null && data['data']['url'] != null) {
            final rawUrl = data['data']['url'].toString();
            return rawUrl.replaceFirst('tmpfiles.org/', 'tmpfiles.org/dl/');
          }
        }
      } catch (_) {}
    } catch (_) {}
    return null;
  }
}
