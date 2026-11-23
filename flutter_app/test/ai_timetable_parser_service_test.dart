import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_center/core/ai_timetable_parser_service.dart';

void main() {
  group('AiTimetableParserService Tests', () {
    test('Parses pure JSON array correctly', () {
      const input = '''
[
  {
    "day": "الأحد",
    "period": 1,
    "class": "1/2 ع",
    "subject": "تكنولوجيا المعلومات",
    "room": "معمل 1",
    "notes": "الدرس الأول"
  },
  {
    "day": "الأحد",
    "period": 2,
    "class": "2/1 ع",
    "subject": "تكنولوجيا المعلومات",
    "room": "معمل 1",
    "notes": ""
  },
  {
    "day": "الإثنين",
    "period": 3,
    "class": "3/2 ع",
    "subject": "حاسب آلي احتياط",
    "room": "",
    "notes": "حصة احتياط"
  }
]
''';

      final result = AiTimetableParserService.parse(input);
      expect(result.isSuccess, isTrue);
      expect(result.periods.length, 3);
      expect(result.periodsPerDay['الأحد'], 2);
      expect(result.periodsPerDay['الإثنين'], 1);
      expect(result.periods[0].className, '1/2 ع');
      expect(result.periods[0].periodNumber, 1);
      expect(result.periods[2].isReserve, isTrue);
    });

    test('Parses markdown wrapped JSON code block', () {
      const input = '''
إليك جدول الحصص المستخرج من الصورة:
```json
[
  {
    "day": "الثلاثاء",
    "period": "1",
    "class": "1/1",
    "subject": "ICT"
  },
  {
    "day": "الخميس",
    "period": 4,
    "class": "2/2",
    "subject": "كمبيوتر"
  }
]
```
تمنياتنا بالتوفيق!
''';

      final result = AiTimetableParserService.parse(input);
      expect(result.isSuccess, isTrue);
      expect(result.periods.length, 2);
      expect(result.periodsPerDay['الثلاثاء'], 1);
      expect(result.periodsPerDay['الخميس'], 1);
    });

    test('Parses line-by-line Arabic format fallback', () {
      const input = '''
الأحد:
الحصة 1: فصل 1/1 ع - تكنولوجيا المعلومات - معمل الكمبيوتر
الحصة 2: فصل 1/2 ع - تكنولوجيا المعلومات - معمل الكمبيوتر

الإثنين:
الحصة 3: فصل 2/1 ع - حاسب آلي
''';

      final result = AiTimetableParserService.parse(input);
      expect(result.isSuccess, isTrue);
      expect(result.periods.length, 3);
      expect(result.periods[0].className, 'فصل 1/1 ع');
      expect(result.periods[0].dayOfWeek, 'الأحد');
    });

    test('Parses day-mapped JSON and handles trailing commas and embedded period strings', () {
      const input = '''
{
  "الأحد": [
    {
      "period": "الحصة الأولى",
      "class": "1/3 ع",
      "subject": "رياضيات",
      "room": "فصل 3",
    },
    {
      "period": "الحصة 2",
      "class": "2/2 ع",
      "subject": "علوم",
    },
  ],
  "الخميس": [
    {
      "period": 5,
      "class": "3/1 ع",
      "subject": "لغة عربية",
    }
  ]
}
''';

      final result = AiTimetableParserService.parse(input);
      expect(result.isSuccess, isTrue);
      expect(result.periods.length, 3);
      expect(result.periodsPerDay['الأحد'], 2);
      expect(result.periodsPerDay['الخميس'], 1);
      expect(result.periods[0].periodNumber, 1);
      expect(result.periods[1].periodNumber, 2);
      expect(result.periods[2].periodNumber, 5);
    });

    test('Handles empty and invalid inputs gracefully', () {
      final emptyResult = AiTimetableParserService.parse('');
      expect(emptyResult.isSuccess, isFalse);

      final invalidResult = AiTimetableParserService.parse('هذا نص عادي لا يحتوي على أي جدول أو حصص');
      expect(invalidResult.isSuccess, isFalse);
    });
  });
}
