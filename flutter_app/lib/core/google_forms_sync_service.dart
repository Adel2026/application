import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart';

import '../models/student_model.dart';

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class GoogleFormSheetItem {
  final String id;
  final String name;
  final String mimeType;
  final DateTime? modifiedTime;

  GoogleFormSheetItem({
    required this.id,
    required this.name,
    required this.mimeType,
    this.modifiedTime,
  });

  bool get isForm => mimeType.contains('form');
  bool get isSpreadsheet => mimeType.contains('spreadsheet');
}

class GoogleFormsSyncResult {
  final Map<String, double> matchedScores; // studentId -> score
  final List<String> unmatchedRecordNames;
  final int totalRecordsFound;

  GoogleFormsSyncResult({
    required this.matchedScores,
    required this.unmatchedRecordNames,
    required this.totalRecordsFound,
  });
}

class GoogleFormsSyncService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      drive.DriveApi.driveReadonlyScope,
    ],
  );

  /// Check if user is signed in to Google
  static Future<bool> isSignedIn() async {
    try {
      return await _googleSignIn.isSignedIn();
    } catch (_) {
      return false;
    }
  }

  /// Get current user
  static GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  /// Sign in with Google
  static Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } catch (e) {
      debugPrint('GoogleFormsSyncService.signIn error: $e');
      rethrow;
    }
  }

  /// Sign out
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  /// List Google Forms and Spreadsheets from user's Drive
  static Future<List<GoogleFormSheetItem>> listFormsAndSheets() async {
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    account ??= await _googleSignIn.signIn();

    if (account == null) {
      throw Exception('يرجى تسجيل الدخول بحساب Google أولاً للمتابعة');
    }

    final authHeaders = await account.authHeaders;
    final authenticateClient = GoogleAuthClient(authHeaders);
    final driveApi = drive.DriveApi(authenticateClient);

    final response = await driveApi.files.list(
      q: "(mimeType = 'application/vnd.google-apps.spreadsheet' or mimeType = 'application/vnd.google-apps.form') and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name, mimeType, modifiedTime)',
      orderBy: 'modifiedTime desc',
      pageSize: 30,
    );

    final items = <GoogleFormSheetItem>[];
    if (response.files != null) {
      for (final f in response.files!) {
        if (f.id != null && f.name != null) {
          items.add(GoogleFormSheetItem(
            id: f.id!,
            name: f.name!,
            mimeType: f.mimeType ?? 'application/vnd.google-apps.spreadsheet',
            modifiedTime: f.modifiedTime,
          ));
        }
      }
    }
    return items;
  }

  /// Fetch CSV string directly from Drive for a given spreadsheet ID
  static Future<String> fetchCsvFromDrive(String fileId) async {
    GoogleSignInAccount? account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    account ??= await _googleSignIn.signIn();

    if (account == null) {
      throw Exception('يرجى تسجيل الدخول بحساب Google');
    }

    final authHeaders = await account.authHeaders;
    final authenticateClient = GoogleAuthClient(authHeaders);
    final driveApi = drive.DriveApi(authenticateClient);

    final media = await driveApi.files.export(
      fileId,
      'text/csv',
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Fetch CSV string from a public or shared Google Sheets link
  static Future<String> fetchCsvFromLink(String url) async {
    final cleanUrl = url.trim();

    if (cleanUrl.contains('/forms/') || cleanUrl.contains('forms.gle')) {
      throw Exception(
        'هذا رابط نموذج Google Forms وليس جدول النتائج.\n'
        'يرجى فتح النموذج ثم الضغط على تبويب "الردود (Responses)" ثم النقر على أيقونة Google Sheets الخضراء لفتح جدول الردود ونسخ رابطه ولصقه هنا.',
      );
    }

    // Extract spreadsheet ID from url
    final match = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)').firstMatch(cleanUrl);
    String spreadsheetId = '';
    if (match != null && match.groupCount >= 1) {
      spreadsheetId = match.group(1)!;
    } else if (!cleanUrl.contains('/') && cleanUrl.length > 20) {
      spreadsheetId = cleanUrl;
    }

    if (spreadsheetId.isEmpty) {
      throw Exception('رابط جدول البيانات غير صالح. يرجى التأكد من نسخ رابط Google Sheets بشكل صحيح.');
    }

    // Extract gid if present
    final gidMatch = RegExp(r'[?&#]gid=([0-9]+)').firstMatch(cleanUrl);
    final gid = gidMatch != null ? gidMatch.group(1) : null;
    final gidParam = gid != null ? '&gid=$gid' : '';

    final urlsToTry = [
      'https://docs.google.com/spreadsheets/d/$spreadsheetId/gviz/tq?tqx=out:csv$gidParam',
      'https://docs.google.com/spreadsheets/d/$spreadsheetId/export?format=csv$gidParam',
    ];

    http.Response? lastResponse;
    for (final exportUrl in urlsToTry) {
      try {
        final client = http.Client();
        final response = await client.get(
          Uri.parse(exportUrl),
          headers: {
            'Accept': 'text/csv,text/plain,*/*',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        );

        if (response.statusCode == 200) {
          final body = utf8.decode(response.bodyBytes, allowMalformed: true);
          if (!body.trim().startsWith('<!DOCTYPE html') && !body.contains('<html')) {
            return body;
          }
        }
        lastResponse = response;
      } catch (_) {
        // try next endpoint
      }
    }

    if (lastResponse != null &&
        (lastResponse.statusCode == 401 ||
            lastResponse.statusCode == 403 ||
            lastResponse.body.contains('<html'))) {
      throw Exception(
        'الشيت محمي أو خاص. يرجى فتح الشيت في Google Sheets والضغط على "مشاركة (Share)" ثم تغيير إذن الوصول إلى: "أي شخص لديه الرابط يمكنه العرض (Anyone with the link can view)".',
      );
    }

    throw Exception(
      'تعذر قراءة الجدول من الرابط. يرجى التأكد من أن الشيت متاح للعرض لأي شخص لديه الرابط، أو يمكنك تنزيله كملف Excel/CSV واستيراده مباشرة من تبويب "ملف من الجهاز".',
    );
  }

  /// Parse Excel or CSV binary bytes and match against group students
  static GoogleFormsSyncResult parseExcelOrCsvBytes({
    required Uint8List bytes,
    required List<StudentModel> students,
  }) {
    if (bytes.isEmpty) {
      return GoogleFormsSyncResult(
        matchedScores: {},
        unmatchedRecordNames: [],
        totalRecordsFound: 0,
      );
    }

    // Check if zip / Excel .xlsx (magic bytes 0x50, 0x4B)
    if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      try {
        final excel = Excel.decodeBytes(bytes);
        for (final table in excel.tables.keys) {
          final sheet = excel.tables[table];
          if (sheet != null && sheet.rows.isNotEmpty) {
            final List<List<String>> rows = [];
            for (final r in sheet.rows) {
              final rowCells = r.map((c) => c?.value?.toString().trim() ?? '').toList();
              if (rowCells.any((element) => element.isNotEmpty)) {
                rows.add(rowCells);
              }
            }
            if (rows.isNotEmpty) {
              return parseRowsAndMatchScores(rows: rows, students: students);
            }
          }
        }
      } catch (e) {
        debugPrint('Excel decoding error, falling back to CSV: $e');
      }
    }

    // CSV fallback
    String content;
    try {
      content = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      content = latin1.decode(bytes);
    }
    return parseTextAndMatchScores(text: content, students: students);
  }

  /// Parse raw text (CSV, TSV, or tabbed text pasted from clipboard)
  static GoogleFormsSyncResult parseTextAndMatchScores({
    required String text,
    required List<StudentModel> students,
  }) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty) {
      return GoogleFormsSyncResult(
        matchedScores: {},
        unmatchedRecordNames: [],
        totalRecordsFound: 0,
      );
    }

    final firstNonEmpty = lines.firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    String delimiter = ',';
    if (firstNonEmpty.contains('\t')) {
      delimiter = '\t';
    } else if (firstNonEmpty.contains(';') && !firstNonEmpty.contains(',')) {
      delimiter = ';';
    }

    List<String> parseLine(String line) {
      final result = <String>[];
      final buffer = StringBuffer();
      bool inQuotes = false;

      for (int i = 0; i < line.length; i++) {
        final c = line[i];
        if (c == '"') {
          inQuotes = !inQuotes;
        } else if (c == delimiter && !inQuotes) {
          result.add(buffer.toString().trim());
          buffer.clear();
        } else {
          buffer.write(c);
        }
      }
      result.add(buffer.toString().trim());
      return result;
    }

    final List<List<String>> rows = [];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final parsed = parseLine(line);
      if (parsed.any((c) => c.isNotEmpty)) {
        rows.add(parsed);
      }
    }

    return parseRowsAndMatchScores(rows: rows, students: students);
  }

  /// Parse structured rows and match against group students
  static GoogleFormsSyncResult parseRowsAndMatchScores({
    required List<List<String>> rows,
    required List<StudentModel> students,
  }) {
    if (rows.isEmpty) {
      return GoogleFormsSyncResult(
        matchedScores: {},
        unmatchedRecordNames: [],
        totalRecordsFound: 0,
      );
    }

    final headerCols = rows.first.map((h) => h.replaceAll('"', '').trim()).toList();

    int nameColIndex = -1;
    int scoreColIndex = -1;
    int phoneColIndex = -1;
    bool hasHeader = false;

    for (int i = 0; i < headerCols.length; i++) {
      final h = headerCols[i].toLowerCase();
      if (scoreColIndex == -1 &&
          (h.contains('درج') ||
              h.contains('نتيج') ||
              h.contains('score') ||
              h.contains('mark') ||
              h.contains('الدرجة') ||
              h.contains('points'))) {
        scoreColIndex = i;
        hasHeader = true;
      } else if (nameColIndex == -1 &&
          (h.contains('اسم') ||
              h.contains('name') ||
              h.contains('طالب') ||
              h.contains('student') ||
              h.contains('الاسم'))) {
        nameColIndex = i;
        hasHeader = true;
      } else if (phoneColIndex == -1 &&
          (h.contains('هاتف') ||
              h.contains('تليفون') ||
              h.contains('موبايل') ||
              h.contains('phone') ||
              h.contains('واتس'))) {
        phoneColIndex = i;
        hasHeader = true;
      }
    }

    // If no explicit headers were detected, inspect data column types
    if (!hasHeader) {
      for (int c = 0; c < headerCols.length; c++) {
        int scoreCount = 0;
        int textCount = 0;
        final sampleLimit = rows.length < 5 ? rows.length : 5;
        for (int r = 0; r < sampleLimit; r++) {
          if (c < rows[r].length) {
            final val = rows[r][c].trim();
            if (parseScore(val) != null) {
              scoreCount++;
            } else if (val.length > 2 && !RegExp(r'^\d+$').hasMatch(val)) {
              textCount++;
            }
          }
        }
        if (scoreColIndex == -1 && scoreCount >= 1 && textCount == 0) {
          scoreColIndex = c;
        } else if (nameColIndex == -1 && textCount >= 1) {
          nameColIndex = c;
        }
      }
    }

    // Default fallbacks if still not determined
    if (scoreColIndex == -1 && headerCols.length > 1) {
      scoreColIndex = 1;
    }
    if (nameColIndex == -1) {
      nameColIndex = (scoreColIndex == 0 && headerCols.length > 1) ? 1 : 0;
    }

    final Map<String, double> matched = {};
    final List<String> unmatchedNames = [];
    int totalFound = 0;

    final startRow = hasHeader ? 1 : 0;

    for (int i = startRow; i < rows.length; i++) {
      final cols = rows[i].map((c) => c.replaceAll('"', '').trim()).toList();
      if (cols.length <= nameColIndex || cols.length <= scoreColIndex) continue;

      final rawName = cols[nameColIndex];
      final rawScore = cols[scoreColIndex];
      final rawPhone = (phoneColIndex != -1 && phoneColIndex < cols.length) ? cols[phoneColIndex] : '';

      final score = parseScore(rawScore);
      if (score == null || rawName.isEmpty) continue;

      totalFound++;
      final normName = normalizeArabicText(rawName);

      // 1. Exact normalized match
      StudentModel? found = students.where((s) {
        return normalizeArabicText(s.fullName) == normName;
      }).firstOrNull;

      // 2. StartsWith match (for students written as first 3 names)
      if (found == null && normName.split(' ').length >= 2) {
        found = students.where((s) {
          final sNorm = normalizeArabicText(s.fullName);
          return sNorm.startsWith(normName) || normName.startsWith(sNorm);
        }).firstOrNull;
      }

      // 3. Contains all name tokens match
      if (found == null) {
        final tokens = normName.split(' ').where((t) => t.length > 2).toList();
        if (tokens.length >= 2) {
          found = students.where((s) {
            final sNorm = normalizeArabicText(s.fullName);
            return tokens.every((t) => sNorm.contains(t));
          }).firstOrNull;
        }
      }

      // 4. Phone match
      if (found == null && rawPhone.isNotEmpty) {
        final pClean = rawPhone.replaceAll(RegExp(r'[^\d]'), '');
        if (pClean.length >= 8) {
          found = students.where((s) {
            final stPhone = s.studentPhone.replaceAll(RegExp(r'[^\d]'), '');
            final pPhone = s.parentPhone.replaceAll(RegExp(r'[^\d]'), '');
            return (stPhone.isNotEmpty && (stPhone.endsWith(pClean) || pClean.endsWith(stPhone))) ||
                (pPhone.isNotEmpty && (pPhone.endsWith(pClean) || pClean.endsWith(pPhone)));
          }).firstOrNull;
        }
      }

      if (found != null) {
        matched[found.id] = score;
      } else {
        unmatchedNames.add('$rawName ($score)');
      }
    }

    return GoogleFormsSyncResult(
      matchedScores: matched,
      unmatchedRecordNames: unmatchedNames,
      totalRecordsFound: totalFound,
    );
  }

  /// Backward compatible wrapper
  static GoogleFormsSyncResult parseAndMatchScores({
    required String csvContent,
    required List<StudentModel> students,
  }) {
    return parseTextAndMatchScores(text: csvContent, students: students);
  }

  static double? parseScore(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    final slashMatch = RegExp(r'^(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)').firstMatch(s);
    if (slashMatch != null) {
      return double.tryParse(slashMatch.group(1)!);
    }

    final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(s);
    if (numMatch != null) {
      return double.tryParse(numMatch.group(1)!);
    }
    return null;
  }

  static String normalizeArabicText(String text) {
    var s = text.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    s = s.replaceAll('ة', 'ه');
    s = s.replaceAll('ى', 'ي');
    s = s.replaceAll('ؤ', 'و');
    s = s.replaceAll('ئ', 'ي');
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), ''); // remove tashkeel
    s = s.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ''); // remove punctuation
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }
}
