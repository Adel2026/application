import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Session Exam Modes & Smart Grading Logic Tests', () {
    test('Calculates score percentage and evaluation badge correctly', () {
      String getScoreEvaluation(double score, double maxScore) {
        if (maxScore <= 0) return '';
        final percent = (score / maxScore) * 100;
        if (percent >= 90) return 'ممتاز 🌟';
        if (percent >= 80) return 'جيد جداً ✨';
        if (percent >= 65) return 'جيد 👍';
        if (percent >= 50) return 'مقبول ⚠️';
        return 'يحتاج اهتمام 🚨';
      }

      expect(getScoreEvaluation(19, 20), 'ممتاز 🌟');
      expect(getScoreEvaluation(16, 20), 'جيد جداً ✨');
      expect(getScoreEvaluation(14, 20), 'جيد 👍');
      expect(getScoreEvaluation(11, 20), 'مقبول ⚠️');
      expect(getScoreEvaluation(8, 20), 'يحتاج اهتمام 🚨');
    });

    test('Today Exam Report formatting when graded now', () {
      final isTodayExamMode = true;
      final todayExamGradingMode = 'now';
      final todayExamTitle = 'كويز شامل على الباب الأول';
      final maxScore = 20.0;
      final studentScore = 18.5;
      final note = 'إجابة نموذجية ⭐';

      final buffer = StringBuffer();
      if (isTodayExamMode) {
        buffer.writeln('🎯 *اختبار الحصة اليوم:* $todayExamTitle');
        if (todayExamGradingMode == 'now') {
          final pct = (studentScore / maxScore * 100).toStringAsFixed(0);
          buffer.writeln('📊 *الدرجة:* $studentScore من $maxScore ($pct% • ممتاز 🌟)');
          if (note.isNotEmpty) {
            buffer.writeln('💡 *ملاحظة المصحح:* $note');
          }
        }
      }

      final report = buffer.toString();
      expect(report, contains('🎯 *اختبار الحصة اليوم:* كويز شامل على الباب الأول'));
      expect(report, contains('📊 *الدرجة:* 18.5 من 20.0 (93% • ممتاز 🌟)'));
      expect(report, contains('💡 *ملاحظة المصحح:* إجابة نموذجية ⭐'));
    });

    test('Today Exam Report formatting when grading is scheduled', () {
      final isTodayExamMode = true;
      final todayExamGradingMode = 'later';
      final todayExamTitle = 'اختبار منتصف الشهر';

      final buffer = StringBuffer();
      if (isTodayExamMode) {
        buffer.writeln('🎯 *اختبار الحصة اليوم:* $todayExamTitle');
        if (todayExamGradingMode == 'later') {
          buffer.writeln('⏳ *حالة التصحيح:* جاري التصحيح وسيتم إعلان الدرجة فور الانتهاء.');
        }
      }

      final report = buffer.toString();
      expect(report, contains('🎯 *اختبار الحصة اليوم:* اختبار منتصف الشهر'));
      expect(report, contains('⏳ *حالة التصحيح:* جاري التصحيح'));
    });

    test('Next Exam Alert formatting in report', () {
      final isNextExamMode = true;
      final nextExamTitle = 'اختبار تجريبي على البابين 1 و 2';
      final nextExamLessons = ['الدرس الأول: الحركة الموجية', 'الدرس الثاني: الحركة الاهتزازية'];
      final nextTasks = ['الاستعداد لاختبار 🎯', 'مراجعة القوانين والملخص 📌'];

      final buffer = StringBuffer();
      if (isNextExamMode) {
        buffer.writeln('⚠️ *تنبيه هام - الحصة القادمة اختبار:* $nextExamTitle');
        buffer.writeln('📚 *الدروس المقررة في الاختبار:*');
        for (final l in nextExamLessons) {
          buffer.writeln('  ▫️ $l');
        }
        buffer.writeln('📌 *المطلوب:* ${nextTasks.join("، ")}');
      }

      final report = buffer.toString();
      expect(report, contains('⚠️ *تنبيه هام - الحصة القادمة اختبار:*'));
      expect(report, contains('الحركة الموجية'));
      expect(report, contains('الاستعداد لاختبار 🎯، مراجعة القوانين والملخص 📌'));
    });
  });
}
