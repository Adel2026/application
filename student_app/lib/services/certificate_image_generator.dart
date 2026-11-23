import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 🏆 مولد صورة شهادة التقدير الرسمية فائقة الدقة بنمط رأسي (Portrait)
/// مصممة خصيصاً لتناسب شاشات الهواتف المحمولة وتملأ الشاشة بدقة 850×1200
class CertificateImageGenerator {
  /// توليد صورة الشهادة الرأسية بصيغة PNG كـ Uint8List
  static Future<Uint8List> generateCertificatePng({
    required String studentName,
    required String grade,
    required String groupName,
    required String examTitle,
    required double score,
    required double maxScore,
    required double percentage,
    required int rank,
    required String certTitle,
    required String teacherName,
    required String centerName,
    required String examDate,
  }) async {
    // الأبعاد الرأسية (Portrait A4/Mobile proportion)
    const double width = 850;
    const double height = 1200;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

    // 1. خلفية ملكية كحلية متدرجة فخمة
    final bgPaint = Paint()
      ..shader = ui.Gradient.radial(
        const Offset(width / 2, height * 0.35),
        height * 0.75,
        const [
          Color(0xFF131D38),
          Color(0xFF0A0F20),
          Color(0xFF03050A),
        ],
        const [0.0, 0.6, 1.0],
      );
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), bgPaint);

    // أشعة ضوئية ناعمة من المركز لإعطاء عمق ثلاثي الأبعاد
    final beamPaint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.025)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 24; i++) {
      final angle = (i * pi) / 24;
      canvas.drawLine(
        Offset(width / 2 - cos(angle) * 900, height * 0.35 - sin(angle) * 900),
        Offset(width / 2 + cos(angle) * 900, height * 0.35 + sin(angle) * 900),
        beamPaint,
      );
    }

    // 2. إطار ذهبي ملكي مزدوج
    final outerBorderPaint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5;

    final innerBorderPaint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(24, 24, width - 48, height - 48), const Radius.circular(22)),
      outerBorderPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(36, 36, width - 72, height - 72), const Radius.circular(16)),
      innerBorderPaint,
    );

    // زوايا مزخرفة ذهبية بالأركان الأربعة
    _drawCornerFlourish(canvas, 44, 44, 0);
    _drawCornerFlourish(canvas, width - 44, 44, 1);
    _drawCornerFlourish(canvas, 44, height - 44, 2);
    _drawCornerFlourish(canvas, width - 44, height - 44, 3);

    // دالة مساعدة لكتابة النصوص
    void drawText({
      required String text,
      required double fontSize,
      required FontWeight fontWeight,
      required Color color,
      required double y,
      bool isCenter = true,
      double? xOffset,
      double letterSpacing = 0.0,
      double maxWidth = width - 100,
    }) {
      final textSpan = TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          letterSpacing: letterSpacing,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: isCenter ? TextAlign.center : TextAlign.right,
        textDirection: TextDirection.rtl,
      );
      textPainter.layout(minWidth: 0, maxWidth: maxWidth);
      final x = isCenter ? (width - textPainter.width) / 2 : (xOffset ?? (width - textPainter.width - 60));
      textPainter.paint(canvas, Offset(x, y));
    }

    // 3. ترويسة اسم الأكاديمية / المركز التعليمي
    final cName = centerName.trim().isNotEmpty ? centerName.trim() : 'أكاديمية التفوق التعليمية';
    drawText(
      text: cName,
      fontSize: 22,
      fontWeight: FontWeight.bold,
      color: const Color(0xFFF59E0B),
      y: 65,
    );

    // 4. عنوان الشهادة الرئيسي المتوهج
    drawText(
      text: certTitle,
      fontSize: 34,
      fontWeight: FontWeight.w900,
      color: const Color(0xFFFFD700),
      letterSpacing: 1.1,
      y: 110,
    );

    // عنوان إنجليزي فخم
    drawText(
      text: 'CERTIFICATE OF EXCELLENCE & HONOR',
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: const Color(0xFFCBD5E1).withValues(alpha: 0.8),
      letterSpacing: 3.0,
      y: 160,
    );

    // فاصل زخرفي ذهبي
    _drawDivider(canvas, width / 2, 195);

    // 5. نص الإهداء والتقدير
    drawText(
      text: 'تتشرف إدارة الأكاديمية بمنح هذه الشهادة بكل فخر واعتزاز إلى الطالب/ـة:',
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: const Color(0xFFCBD5E1),
      y: 225,
    );

    // 6. صندوق اسم الطالب المتفوق
    final nameBoxRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(width / 2, 305), width: width * 0.84, height: 74),
      const Radius.circular(16),
    );
    final nameBoxFill = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;
    final nameBoxBorder = Paint()
      ..color = const Color(0xFFD4AF37)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawRRect(nameBoxRect, nameBoxFill);
    canvas.drawRRect(nameBoxRect, nameBoxBorder);

    // اسم الطالب الفعلي
    drawText(
      text: studentName.trim().isNotEmpty ? studentName.trim() : 'الطالب المتفوق',
      fontSize: 31,
      fontWeight: FontWeight.w900,
      color: Colors.white,
      y: 284,
    );

    // 7. المرحلة والصف والمجموعة
    final groupText = [
      if (grade.trim().isNotEmpty) grade.trim(),
      if (groupName.trim().isNotEmpty) 'مجموعة: ${groupName.trim()}',
    ].join(' • ');

    if (groupText.isNotEmpty) {
      drawText(
        text: groupText,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF38BDF8),
        y: 365,
      );
    }

    // 8. تفاصيل الاختبار
    drawText(
      text: 'تقديراً لحصوله على المركز المتقدم والدرجات العليا في:',
      fontSize: 15.5,
      fontWeight: FontWeight.w500,
      color: const Color(0xFFE2E8F0),
      y: 410,
    );

    drawText(
      text: '« ${examTitle.trim()} »',
      fontSize: 26,
      fontWeight: FontWeight.w800,
      color: const Color(0xFFF59E0B),
      y: 445,
    );

    // 9. لوحة النتائج الرقمية والترتيب (بطاقة أفقية مقسمة لـ 3 أعمدة)
    final statsBoxRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(width / 2, 570), width: width * 0.86, height: 110),
      const Radius.circular(18),
    );
    final statsBoxFill = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.96)
      ..style = PaintingStyle.fill;
    final statsBoxBorder = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    canvas.drawRRect(statsBoxRect, statsBoxFill);
    canvas.drawRRect(statsBoxRect, statsBoxBorder);

    // تقسيم بطاقة النتائج إلى 3 أقسام
    final colW = (width * 0.86) / 3;
    final startX = (width - width * 0.86) / 2;

    // فاصل بين الأعمدة
    final divPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(startX + colW, 525), Offset(startX + colW, 615), divPaint);
    canvas.drawLine(Offset(startX + colW * 2, 525), Offset(startX + colW * 2, 615), divPaint);

    // عمود 1 (اليمين): الدرجة
    drawText(
      text: 'الدرجة المحققة',
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF94A3B8),
      y: 530,
      isCenter: false,
      xOffset: startX + colW * 2 + (colW - 80) / 2,
    );
    drawText(
      text: '${score.toStringAsFixed(1)} / ${maxScore.toStringAsFixed(1)}',
      fontSize: 22,
      fontWeight: FontWeight.w900,
      color: const Color(0xFF10B981),
      y: 565,
      isCenter: false,
      xOffset: startX + colW * 2 + 15,
    );

    // عمود 2 (الوسط): النسبة المئوية
    drawText(
      text: 'النسبة المئوية',
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF94A3B8),
      y: 530,
      isCenter: false,
      xOffset: startX + colW + (colW - 80) / 2,
    );
    drawText(
      text: '%${percentage.toStringAsFixed(1)}',
      fontSize: 23,
      fontWeight: FontWeight.w900,
      color: const Color(0xFF00F2FE),
      y: 565,
      isCenter: false,
      xOffset: startX + colW + (colW - 75) / 2,
    );

    // عمود 3 (اليسار): الترتيب
    final rankStr = rank > 0 ? 'المركز $rank 🏆' : 'مرتبة الشرف 🌟';
    drawText(
      text: 'الترتيب والتفوق',
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF94A3B8),
      y: 530,
      isCenter: false,
      xOffset: startX + (colW - 80) / 2,
    );
    drawText(
      text: rankStr,
      fontSize: 20,
      fontWeight: FontWeight.w900,
      color: const Color(0xFFFFD700),
      y: 567,
      isCenter: false,
      xOffset: startX + 15,
    );

    // 10. نص تشجيعي وبلاغي مأثور
    drawText(
      text: '«نبراسٌ يُضيء دروب العلم، ومثالٌ يُحتذى به في الجد والاجتهاد والمثابرة»',
      fontSize: 15.5,
      fontWeight: FontWeight.w600,
      color: const Color(0xFFD4AF37),
      y: 685,
    );
    drawText(
      text: 'مع أطيب التمنيات بدوام التقدم والريادة الأكاديمية المستمرة.',
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF94A3B8),
      y: 720,
    );

    // 11. الختم الذهبي المعتمد في منتصف الجزء السفلي
    _drawGoldenSeal(canvas, width / 2, 885);

    // 12. بيانات التوثيق والاعتماد والتاريخ
    // التاريخ (يمين)
    drawText(
      text: 'تاريخ الاعتماد:',
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF94A3B8),
      y: 1030,
      isCenter: false,
      xOffset: width - 260,
    );
    drawText(
      text: examDate.isNotEmpty ? examDate : '2026',
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      y: 1060,
      isCenter: false,
      xOffset: width - 260,
    );

    // توقيع المعلم (يسار)
    final tName = teacherName.trim().isNotEmpty ? teacherName.trim() : 'أستاذ المادة';
    drawText(
      text: 'اعتماد معلم المادة:',
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF94A3B8),
      y: 1030,
      isCenter: false,
      xOffset: 80,
    );
    drawText(
      text: tName,
      fontSize: 22,
      fontWeight: FontWeight.w900,
      color: const Color(0xFFFFD700),
      y: 1058,
      isCenter: false,
      xOffset: 80,
    );

    // خط توقيع أنيق تحت اسم المعلم
    final sigPaint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.6)
      ..strokeWidth = 1.4;
    canvas.drawLine(const Offset(80, 1090), const Offset(260, 1090), sigPaint);

    // علامة توثيق أسفل الشهادة
    drawText(
      text: 'وثيقة رسمية معتمدة صادرة من نظام Edu Academy',
      fontSize: 11,
      fontWeight: FontWeight.normal,
      color: const Color(0xFF64748B),
      y: 1145,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// توليد الشهادة كصيغة Base64 جاهزة للتخزين في Firestore والإرسال اللحظي
  static Future<String> generateCertificateBase64({
    required String studentName,
    required String grade,
    required String groupName,
    required String examTitle,
    required double score,
    required double maxScore,
    required double percentage,
    required int rank,
    required String certTitle,
    required String teacherName,
    required String centerName,
    required String examDate,
  }) async {
    final pngBytes = await generateCertificatePng(
      studentName: studentName,
      grade: grade,
      groupName: groupName,
      examTitle: examTitle,
      score: score,
      maxScore: maxScore,
      percentage: percentage,
      rank: rank,
      certTitle: certTitle,
      teacherName: teacherName,
      centerName: centerName,
      examDate: examDate,
    );
    return base64Encode(pngBytes);
  }

  // رسم زوايا ذهبية فخمة
  static void _drawCornerFlourish(Canvas canvas, double x, double y, int cornerIndex) {
    final paint = Paint()
      ..color = const Color(0xFFD4AF37)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final double signX = (cornerIndex == 0 || cornerIndex == 2) ? 1 : -1;
    final double signY = (cornerIndex == 0 || cornerIndex == 1) ? 1 : -1;

    final path = Path();
    path.moveTo(x, y + signY * 36);
    path.lineTo(x, y);
    path.lineTo(x + signX * 36, y);

    canvas.drawPath(path, paint);

    final dotPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x + signX * 12, y + signY * 12), 3.0, dotPaint);
  }

  // رسم فاصل ذهبي متدرج
  static void _drawDivider(Canvas canvas, double centerX, double y) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(centerX - 160, y),
        Offset(centerX + 160, y),
        [
          Colors.transparent,
          const Color(0xFFD4AF37),
          const Color(0xFFFFD700),
          const Color(0xFFD4AF37),
          Colors.transparent,
        ],
        [0.0, 0.25, 0.5, 0.75, 1.0],
      )
      ..strokeWidth = 1.8;

    canvas.drawLine(Offset(centerX - 160, y), Offset(centerX + 160, y), paint);

    final starPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, y), 4.5, starPaint);
  }

  // رسم الختم الذهبي الملكي المعتمد
  static void _drawGoldenSeal(Canvas canvas, double cx, double cy) {
    const sealRadius = 56.0;

    // أشرطة الختم السفلية (Ribbons)
    final ribbonPaint = Paint()
      ..color = const Color(0xFFB45309)
      ..style = PaintingStyle.fill;
    final ribbonBorder = Paint()
      ..color = const Color(0xFFD4AF37)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final leftRibbon = Path()
      ..moveTo(cx - 20, cy + 28)
      ..lineTo(cx - 36, cy + 78)
      ..lineTo(cx - 20, cy + 68)
      ..lineTo(cx - 4, cy + 78)
      ..lineTo(cx - 8, cy + 28)
      ..close();
    canvas.drawPath(leftRibbon, ribbonPaint);
    canvas.drawPath(leftRibbon, ribbonBorder);

    final rightRibbon = Path()
      ..moveTo(cx + 8, cy + 28)
      ..lineTo(cx + 4, cy + 78)
      ..lineTo(cx + 20, cy + 68)
      ..lineTo(cx + 36, cy + 78)
      ..lineTo(cx + 20, cy + 28)
      ..close();
    canvas.drawPath(rightRibbon, ribbonPaint);
    canvas.drawPath(rightRibbon, ribbonBorder);

    // دائرة الختم الخارجية المشرشرة
    final jaggedPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx, cy),
        sealRadius,
        const [Color(0xFFFFD700), Color(0xFFD4AF37), Color(0xFF854D0E)],
        const [0.0, 0.65, 1.0],
      );

    const int teeth = 28;
    final sealPath = Path();
    for (int i = 0; i < teeth * 2; i++) {
      final r = (i % 2 == 0) ? sealRadius : (sealRadius - 5);
      final angle = (i * pi) / teeth;
      final x = cx + cos(angle) * r;
      final y = cy + sin(angle) * r;
      if (i == 0) {
        sealPath.moveTo(x, y);
      } else {
        sealPath.lineTo(x, y);
      }
    }
    sealPath.close();
    canvas.drawPath(sealPath, jaggedPaint);

    // حلقة داخلية
    final ringPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), sealRadius - 10, ringPaint);

    final ringBorder = Paint()
      ..color = const Color(0xFFFFD700)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), sealRadius - 10, ringBorder);

    // نص الختم
    final textSpan = const TextSpan(
      text: '★ معتمد ★\nOFFICIAL',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: Color(0xFFFFD700),
        height: 1.2,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(cx - textPainter.width / 2, cy - textPainter.height / 2));
  }
}
