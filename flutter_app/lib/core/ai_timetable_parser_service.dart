import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/school_period_model.dart';

class AiTimetableParseResult {
  final bool isSuccess;
  final List<SchoolPeriodModel> periods;
  final Map<String, int> periodsPerDay;
  final List<String> warnings;
  final String? errorMessage;

  const AiTimetableParseResult({
    required this.isSuccess,
    required this.periods,
    required this.periodsPerDay,
    this.warnings = const [],
    this.errorMessage,
  });

  int get totalPeriods => periods.length;
}

class AiTimetableParserService {
  static const List<String> officialDays = [
    'الأحد',
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
  ];

  static const Map<int, ({String start, String end})> defaultSchoolTimings = {
    1: (start: '08:00', end: '08:45'),
    2: (start: '08:50', end: '09:35'),
    3: (start: '09:40', end: '10:25'),
    4: (start: '11:00', end: '11:45'),
    5: (start: '11:50', end: '12:35'),
    6: (start: '12:40', end: '01:25'),
    7: (start: '01:30', end: '02:15'),
    8: (start: '02:20', end: '03:05'),
  };

  /// The magic, battle-tested prompt designed for Gemini to convert school schedule photos into pure JSON
  static const String geminiPromptTemplate = '''
أنت خبير فائق الدقة في قراءة وتحليل جداول الحصص المدرسية من الصور والمستندات.
المطلوب:
1. انظر بعناية إلى صورة الجدول المرفقة واستخرج جميع الحصص المدرسية الخاصة بالمعلم فقط.
2. حوّل البيانات بدقة إلى مصفوفة JSON صالحة حصراً بدون أي شرح أو مقدمات أو كلام إضافي، وبنفس التنسيق التالي تماماً:

[
  {
    "day": "الأحد",
    "period": 1,
    "class": "1/2 ع",
    "subject": "تكنولوجيا المعلومات",
    "room": "معمل 1",
    "notes": ""
  },
  {
    "day": "الأحد",
    "period": 2,
    "class": "2/1 ع",
    "subject": "تكنولوجيا المعلومات",
    "room": "معمل 1",
    "notes": ""
  }
]

قواعد وقوانين صارمة:
- أيام الأسبوع المعتمدة باللغة العربية حصراً: (الأحد، الإثنين، الثلاثاء، الأربعاء، الخميس).
- رقم الحصة ("period"): رقم صحيح من 1 إلى 8.
- اسم الفصل ("class"): اكتبه كما في الجدول تماماً (مثل: "1/1", "1/2 ع", "ثالثة أول", "3/2").
- المادة ("subject"): اكتب اسم المادة المشروحة (مثل: "تكنولوجيا المعلومات ICT", "حاسب آلي", "علوم", "احتياط").
- إذا كانت الحصة احتياطاً، اكتب في "subject": "احتياط" أو في "notes": "حصة احتياط".
- لا تضع أي علامات أو نصوص قبل أو بعد مصفوفة الـ JSON، أخرج فقط الـ JSON النقي.
''';

  /// Parses raw text (JSON, Markdown JSON, or line-by-line Arabic text) into a verified list of SchoolPeriodModel
  static AiTimetableParseResult parse(
    String rawInput, {
    Map<int, ({String start, String end})>? periodTimings,
  }) {
    final text = rawInput.trim();
    if (text.isEmpty) {
      return const AiTimetableParseResult(
        isSuccess: false,
        periods: [],
        periodsPerDay: {},
        errorMessage: 'النص المدخل فارغ. يرجى لصق ناتج Gemini أولاً.',
      );
    }

    final timings = periodTimings ?? defaultSchoolTimings;
    final warnings = <String>[];
    List<SchoolPeriodModel> parsed = [];

    // Attempt 1: Parse JSON (direct or extracted from markdown/text)
    final jsonParsed = _tryParseJson(text, timings, warnings);
    if (jsonParsed != null && jsonParsed.isNotEmpty) {
      parsed = jsonParsed;
    } else {
      // Attempt 2: Fallback line-by-line Arabic parser
      final lineParsed = _tryParseLineByLine(text, timings, warnings);
      if (lineParsed.isNotEmpty) {
        parsed = lineParsed;
      }
    }

    if (parsed.isEmpty) {
      return AiTimetableParseResult(
        isSuccess: false,
        periods: [],
        periodsPerDay: {},
        warnings: warnings,
        errorMessage:
            'تعذر التعرف على حصص صالحة في النص المدخل.\nتأكد من نسخ الـ JSON كاملاً من Gemini أو استخدام البرومبت المعتمد.',
      );
    }

    // Deduplicate and resolve slots (same day + same periodNumber)
    final slotMap = <String, SchoolPeriodModel>{};
    for (final p in parsed) {
      final key = '${p.dayOfWeek}_${p.periodNumber}';
      if (slotMap.containsKey(key)) {
        warnings.add(
            'تنبيه: تم رصد تكرار للحصة ${p.periodNumber} يوم ${p.dayOfWeek} (تم اعتماد آخر مدخل: ${p.className} - ${p.subject}).');
      }
      slotMap[key] = p;
    }

    final sortedPeriods = slotMap.values.toList()
      ..sort((a, b) {
        final dA = _dayIndex(a.dayOfWeek);
        final dB = _dayIndex(b.dayOfWeek);
        if (dA != dB) return dA.compareTo(dB);
        return a.periodNumber.compareTo(b.periodNumber);
      });

    final counts = <String, int>{};
    for (final d in officialDays) {
      counts[d] = 0;
    }
    for (final p in sortedPeriods) {
      counts[p.dayOfWeek] = (counts[p.dayOfWeek] ?? 0) + 1;
    }

    return AiTimetableParseResult(
      isSuccess: true,
      periods: sortedPeriods,
      periodsPerDay: counts,
      warnings: warnings,
    );
  }

  static List<SchoolPeriodModel>? _tryParseJson(
    String rawText,
    Map<int, ({String start, String end})> timings,
    List<String> warnings,
  ) {
    try {
      String jsonStr = rawText;

      // Strip markdown code fences if present (```json ... ``` or ``` ... ```)
      final mdRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false);
      final mdMatch = mdRegex.firstMatch(jsonStr);
      if (mdMatch != null) {
        jsonStr = mdMatch.group(1)?.trim() ?? jsonStr;
      }

      // If text still contains other words before [ or {, extract the json bracket
      final startBracket = jsonStr.indexOf('[');
      final endBracket = jsonStr.lastIndexOf(']');
      final startBrace = jsonStr.indexOf('{');
      final endBrace = jsonStr.lastIndexOf('}');

      if (startBracket != -1 && endBracket != -1 && endBracket > startBracket) {
        // If bracket comes before brace or there's no brace
        if (startBrace == -1 || startBracket < startBrace) {
          jsonStr = jsonStr.substring(startBracket, endBracket + 1);
        } else if (endBrace > startBrace) {
          jsonStr = jsonStr.substring(startBrace, endBrace + 1);
        }
      } else if (startBrace != -1 && endBrace != -1 && endBrace > startBrace) {
        jsonStr = jsonStr.substring(startBrace, endBrace + 1);
      }

      // Remove trailing commas which are invalid in JSON standard but common in LLM output
      jsonStr = jsonStr.replaceAllMapped(RegExp(r',\s*([\]}])'), (m) => m.group(1)!);

      final decoded = jsonDecode(jsonStr);
      List<dynamic> items = [];

      if (decoded is List) {
        items = decoded;
      } else if (decoded is Map) {
        // Check if map keys are day names: e.g. {"الأحد": [...], "الإثنين": [...]}
        bool hasDayKeys = false;
        for (final entry in decoded.entries) {
          final possibleDay = _normalizeDay(entry.key.toString());
          if (possibleDay != null && entry.value is List) {
            hasDayKeys = true;
            for (final item in (entry.value as List)) {
              if (item is Map) {
                final copy = Map<String, dynamic>.from(item);
                copy['day'] ??= possibleDay;
                items.add(copy);
              }
            }
          }
        }

        if (!hasDayKeys) {
          // Check for nested keys like "schedule", "timetable", "periods", "حصص"
          for (final val in decoded.values) {
            if (val is List) {
              items.addAll(val);
            } else if (val is Map) {
              for (final subEntry in val.entries) {
                final possibleDay = _normalizeDay(subEntry.key.toString());
                if (possibleDay != null && subEntry.value is List) {
                  for (final item in (subEntry.value as List)) {
                    if (item is Map) {
                      final copy = Map<String, dynamic>.from(item);
                      copy['day'] ??= possibleDay;
                      items.add(copy);
                    }
                  }
                }
              }
            }
          }
        }
      }

      if (items.isEmpty) return null;

      final results = <SchoolPeriodModel>[];
      final timestamp = DateTime.now().microsecondsSinceEpoch;

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        if (item is! Map) continue;

        final rawDay = item['day'] ?? item['day_of_week'] ?? item['اليوم'] ?? item['يوم'];
        final normalizedDay = _normalizeDay(rawDay?.toString());
        if (normalizedDay == null) {
          warnings.add('تم تجاهل عنصر برقم $i لعدم التعرف على اليوم: "$rawDay"');
          continue;
        }

        final rawPeriod = item['period'] ?? item['period_number'] ?? item['الحصة'] ?? item['رقم_الحصة'];
        final periodNum = _normalizePeriodNumber(rawPeriod);
        if (periodNum == null || periodNum < 1 || periodNum > 8) {
          warnings.add('تم تجاهل عنصر برقم $i يوم $normalizedDay لرقم حصة غير صالح: "$rawPeriod"');
          continue;
        }

        final className = (item['class'] ?? item['class_name'] ?? item['الفصل'] ?? item['الصف'] ?? '').toString().trim();
        final subject = (item['subject'] ?? item['المادة'] ?? 'حصة مدرسية').toString().trim();
        final room = (item['room'] ?? item['location'] ?? item['المكان'] ?? item['المعمل'] ?? '').toString().trim();
        final notes = (item['notes'] ?? item['ملاحظات'] ?? '').toString().trim();

        final isRecess = (item['is_recess'] == true) ||
            subject.contains('فسحة') ||
            className.contains('فسحة');

        final isReserve = (item['is_reserve'] == true) ||
            subject.contains('احتياط') ||
            notes.contains('احتياط');

        // Timing
        final timingTuple = timings[periodNum] ?? (start: '08:00', end: '08:45');
        final startTime = (item['start_time'] ?? item['start'] ?? timingTuple.start).toString().trim();
        final endTime = (item['end_time'] ?? item['end'] ?? timingTuple.end).toString().trim();

        results.add(
          SchoolPeriodModel(
            id: 'ai_${timestamp}_${normalizedDay}_$periodNum',
            dayOfWeek: normalizedDay,
            periodNumber: periodNum,
            className: className.isNotEmpty ? className : (isRecess ? 'الفسحة المدرسية' : 'فصل غير محدد'),
            subject: subject.isNotEmpty ? subject : (isRecess ? 'فسحة' : 'مادة دراسية'),
            startTime: startTime,
            endTime: endTime,
            room: room,
            notes: notes,
            isRecess: isRecess,
            isReserve: isReserve,
          ),
        );
      }

      return results;
    } catch (e) {
      debugPrint('AiTimetableParser JSON attempt failed: $e');
      return null;
    }
  }

  static List<SchoolPeriodModel> _tryParseLineByLine(
    String rawText,
    Map<int, ({String start, String end})> timings,
    List<String> warnings,
  ) {
    final results = <SchoolPeriodModel>[];
    final lines = rawText.split('\n');
    String? currentDay;
    final timestamp = DateTime.now().microsecondsSinceEpoch;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Check if line indicates a day header (e.g., "الأحد:" or "يوم الإثنين")
      final detectedDay = _normalizeDay(line);
      if (detectedDay != null && (line.length <= 15 || line.contains(':') || line.contains('-'))) {
        currentDay = detectedDay;
        continue;
      }

      if (currentDay == null) {
        // Try to see if line has day inside it
        for (final d in officialDays) {
          if (line.contains(d)) {
            currentDay = d;
            break;
          }
        }
      }

      if (currentDay == null) continue;

      // Match period pattern like: "الحصة 1: 1/2 ع - كمبيوتر" or "1 - 1/2 ع - تكنولوجيا"
      final periodMatch = RegExp(r'(?:الحصة|حصة)?\s*([1-8١-٨]|الأولى|الثانية|الثالثة|الرابعة|الخامسة|السادسة|السابعة|الثامنة)[\s:ـ|–\-]+(.*)').firstMatch(line);
      if (periodMatch != null) {
        final periodStr = periodMatch.group(1);
        final periodNum = _normalizePeriodNumber(periodStr);
        final rest = periodMatch.group(2)?.trim() ?? '';

        if (periodNum != null) {
          final parts = rest.split(RegExp(r'[-–•|,]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          final className = parts.isNotEmpty ? parts[0] : 'فصل';
          final subject = parts.length > 1 ? parts[1] : 'حصة مدرسية';
          final room = parts.length > 2 ? parts[2] : '';

          final isReserve = subject.contains('احتياط') || rest.contains('احتياط');
          final isRecess = subject.contains('فسحة') || rest.contains('فسحة');

          final timingTuple = timings[periodNum] ?? (start: '08:00', end: '08:45');

          results.add(
            SchoolPeriodModel(
              id: 'ai_line_${timestamp}_${currentDay}_$periodNum',
              dayOfWeek: currentDay,
              periodNumber: periodNum,
              className: className,
              subject: subject,
              startTime: timingTuple.start,
              endTime: timingTuple.end,
              room: room,
              notes: '',
              isRecess: isRecess,
              isReserve: isReserve,
            ),
          );
        }
      }
    }

    return results;
  }

  static String? _normalizeDay(String? input) {
    if (input == null) return null;
    var s = input.trim();
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), ''); // remove tashkeel
    s = s.replaceAll('إ', 'ا').replaceAll('أ', 'ا').replaceAll('آ', 'ا');
    s = s.replaceAll('ة', 'ه').replaceAll('ى', 'ي');
    s = s.toLowerCase();

    if (s.contains('احد') || s.contains('sun')) return 'الأحد';
    if (s.contains('اثنين') || s.contains('mon')) return 'الإثنين';
    if (s.contains('ثلاث') || s.contains('tue')) return 'الثلاثاء';
    if (s.contains('اربع') || s.contains('wed')) return 'الأربعاء';
    if (s.contains('خميس') || s.contains('thu')) return 'الخميس';
    if (s.contains('جمع') || s.contains('fri')) return 'الجمعة';
    if (s.contains('سبت') || s.contains('sat')) return 'السبت';

    return null;
  }

  static int? _normalizePeriodNumber(dynamic input) {
    if (input == null) return null;
    if (input is num) return input.toInt();
    final s = input.toString().trim();

    // Arabic and English digit mapping
    const digitsMap = {
      '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8,
      '١': 1, '٢': 2, '٣': 3, '٤': 4, '٥': 5, '٦': 6, '٧': 7, '٨': 8,
    };
    if (digitsMap.containsKey(s)) return digitsMap[s];

    // Word mapping
    if (s.contains('اولي') || s.contains('أولى') || s.contains('اولى')) return 1;
    if (s.contains('ثاني') || s.contains('تانية')) return 2;
    if (s.contains('ثالث') || s.contains('تالتة')) return 3;
    if (s.contains('رابع')) return 4;
    if (s.contains('خامس')) return 5;
    if (s.contains('سادس')) return 6;
    if (s.contains('سابع')) return 7;
    if (s.contains('ثامن')) return 8;

    // Check if there is any single digit 1-8 inside the string (e.g. "الحصة 1" or "حصة 4")
    final match = RegExp(r'[1-8١-٨]').firstMatch(s);
    if (match != null) {
      final digitChar = match.group(0);
      if (digitChar != null && digitsMap.containsKey(digitChar)) {
        return digitsMap[digitChar];
      }
    }

    return int.tryParse(s);
  }

  static int _dayIndex(String day) {
    switch (day) {
      case 'الأحد':
        return 0;
      case 'الإثنين':
        return 1;
      case 'الثلاثاء':
        return 2;
      case 'الأربعاء':
        return 3;
      case 'الخميس':
        return 4;
      case 'الجمعة':
        return 5;
      case 'السبت':
        return 6;
      default:
        return 99;
    }
  }
}
