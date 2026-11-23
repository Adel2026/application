import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/database/database_service.dart';
import '../core/whatsapp_service.dart';
import '../models/group_model.dart';
import '../models/student_model.dart';
import '../widgets/circular_image_cropper_dialog.dart';

/// Available layout styles for the Visual Report Card
enum ReportCardLayout {
  vertical('عمودي انسيابي (تحت بعض) 📱'),
  grid('شبكي مدمج 📊');

  final String label;
  const ReportCardLayout(this.label);
}

/// Available font options for the Visual Report Card
enum ReportCardFont {
  cairo('Cairo', 'كايرو (الافتراضي)'),
  tajawal('Tajawal', 'تجوال (الحديث)'),
  readexPro('Readex Pro', 'ريدكس برو (العصري)'),
  amiri('Amiri', 'الأميري (الكلاسيكي)');

  final String family;
  final String label;
  const ReportCardFont(this.family, this.label);
}

/// Available accent palettes for the Report Card
enum ReportCardTheme {
  cyan(
    'سماوي كحلي ⚡',
    Color(0xFF00F2FE),
    Color(0xFF0284C7),
    Color(0xFF0F172A),
    Color(0xFF090E17),
    Color(0xFFF0F9FF),
    Color(0xFFFFFFFF),
  ),
  gold(
    'ذهبي ملكي 👑',
    Color(0xFFFBBF24),
    Color(0xFFD97706),
    Color(0xFF1C1917),
    Color(0xFF0C0A09),
    Color(0xFFFFFBEB),
    Color(0xFFFFFFFF),
  ),
  emerald(
    'زمردي أخضر 🌿',
    Color(0xFF34D399),
    Color(0xFF059669),
    Color(0xFF062817),
    Color(0xFF03140B),
    Color(0xFFF0FDF4),
    Color(0xFFFFFFFF),
  ),
  purple(
    'بنفسجي فاخر 💜',
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFF1E1035),
    Color(0xFF0F071D),
    Color(0xFFFAF5FF),
    Color(0xFFFFFFFF),
  );

  final String label;
  final Color primary;
  final Color secondary;
  final Color cardBg;
  final Color darkBg;
  final Color cardBgLight;
  final Color lightBg;

  const ReportCardTheme(
    this.label,
    this.primary,
    this.secondary,
    this.cardBg,
    this.darkBg,
    this.cardBgLight,
    this.lightBg,
  );
}

class VisualStudentReportCard extends StatelessWidget {
  final StudentModel student;
  final String groupName;
  final String? groupGrade;
  final int attendancePercent;
  final int presentCount;
  final int totalSessions;
  final double averageScorePercent;
  final List<Map<String, dynamic>> examScores;
  final String? teacherNote;
  final String centerName;
  final String teacherName;
  final String? rankText;
  final String? reportTitle;
  final String? sessionDate;
  final String? attendanceStatusLabel;
  final String? homeworkStatusLabel;
  final String? recitationRatingLabel;
  final String? lessonTitle;
  final String? previousHomeworkReview;
  final String? homeworkText;
  final String? nextTopic;
  final String? nextQuiz;
  final String? subAttendanceNote;
  final ReportCardFont font;
  final ReportCardTheme theme;
  final ReportCardLayout layout;
  final bool isDarkMode;
  final bool showQr;
  final bool showFinance;
  final bool showStamp;
  final bool showAttendance;
  final bool showExams;
  final bool showHomework;
  final bool showRank;
  final bool showTeacherNote;
  final String? headerLogoPath;
  final String? studentPhotoPath;
  final String? stampLogoPath;

  const VisualStudentReportCard({
    super.key,
    required this.student,
    required this.groupName,
    this.groupGrade,
    required this.attendancePercent,
    required this.presentCount,
    required this.totalSessions,
    required this.averageScorePercent,
    required this.examScores,
    this.teacherNote,
    required this.centerName,
    required this.teacherName,
    this.rankText,
    this.reportTitle,
    this.sessionDate,
    this.attendanceStatusLabel,
    this.homeworkStatusLabel,
    this.recitationRatingLabel,
    this.lessonTitle,
    this.previousHomeworkReview,
    this.homeworkText,
    this.nextTopic,
    this.nextQuiz,
    this.subAttendanceNote,
    this.font = ReportCardFont.cairo,
    this.theme = ReportCardTheme.cyan,
    this.layout = ReportCardLayout.vertical,
    this.isDarkMode = true,
    this.showQr = true,
    this.showFinance = true,
    this.showStamp = true,
    this.showAttendance = true,
    this.showExams = true,
    this.showHomework = true,
    this.showRank = true,
    this.showTeacherNote = true,
    this.headerLogoPath,
    this.studentPhotoPath,
    this.stampLogoPath,
  });

  TextStyle _getStyle({
    required double fontSize,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    double height = 1.3,
  }) {
    final effectiveColor = color ?? (isDarkMode ? Colors.white : const Color(0xFF0F172A));

    if (font == ReportCardFont.cairo) {
      return TextStyle(
        fontFamily: 'Cairo',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: effectiveColor,
        height: height,
      );
    }
    try {
      switch (font) {
        case ReportCardFont.cairo:
          break;
        case ReportCardFont.tajawal:
          return GoogleFonts.tajawal(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: effectiveColor,
            height: height,
          );
        case ReportCardFont.readexPro:
          return GoogleFonts.readexPro(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: effectiveColor,
            height: height,
          );
        case ReportCardFont.amiri:
          return GoogleFonts.amiri(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: effectiveColor,
            height: height,
          );
      }
    } catch (_) {}

    return TextStyle(
      fontFamily: 'Cairo',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: effectiveColor,
      height: height,
    );
  }

  Widget _buildHeaderLogo() {
    if (headerLogoPath != null && headerLogoPath!.isNotEmpty && File(headerLogoPath!).existsSync()) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: theme.primary.withValues(alpha: isDarkMode ? 0.3 : 0.2),
              blurRadius: 12,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Image.file(
            File(headerLogoPath!),
            width: 48,
            height: 48,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.secondary, theme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: theme.primary.withValues(alpha: isDarkMode ? 0.3 : 0.2),
            blurRadius: 12,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Text('🎓', style: TextStyle(fontSize: 24)),
    );
  }

  Widget _buildStudentAvatar() {
    if (studentPhotoPath != null && studentPhotoPath!.isNotEmpty && File(studentPhotoPath!).existsSync()) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: theme.primary, width: 2),
        ),
        child: ClipOval(
          child: Image.file(
            File(studentPhotoPath!),
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        shape: BoxShape.circle,
        border: Border.all(color: theme.primary, width: 1.5),
      ),
      alignment: Alignment.center,
      child: const Text('👨‍🎓', style: TextStyle(fontSize: 20)),
    );
  }

  Widget _buildOfficialStamp() {
    if (stampLogoPath != null && stampLogoPath!.isNotEmpty && File(stampLogoPath!).existsSync()) {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: theme.primary, width: 1.5),
        ),
        child: ClipOval(
          child: Image.file(
            File(stampLogoPath!),
            width: 42,
            height: 42,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: theme.primary, width: 1.2),
        color: isDarkMode ? Colors.transparent : theme.primary.withValues(alpha: 0.05),
      ),
      alignment: Alignment.center,
      child: const Text('⚜️', style: TextStyle(fontSize: 16)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = sessionDate ?? '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final reportCode = 'REP-${student.id.length > 5 ? student.id.substring(0, 5).toUpperCase() : student.id.toUpperCase()}-${now.month}-$dateStr';

    final effectiveBg = isDarkMode ? theme.darkBg : theme.lightBg;
    final effectiveCardBg = isDarkMode ? theme.cardBg : theme.cardBgLight;
    final effectiveSubtitleColor = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final effectiveBorderColor = isDarkMode
        ? theme.primary.withValues(alpha: 0.35)
        : theme.primary.withValues(alpha: 0.3);

    final isVertical = layout == ReportCardLayout.vertical;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: isVertical ? 400 : 780,
        constraints: isVertical ? const BoxConstraints(maxWidth: 420) : null,
        decoration: BoxDecoration(
          color: effectiveBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: effectiveBorderColor, width: 1.5),
          boxShadow: isDarkMode
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: theme.primary.withValues(alpha: 0.15),
                    blurRadius: 25,
                    offset: const Offset(0, -2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: theme.primary.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isVertical ? 16 : 28,
          vertical: isVertical ? 20 : 26,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header & Academy Branding
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _buildHeaderLogo(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              centerName.isNotEmpty ? centerName : 'أكاديمية التفوق التعليمية',
                              style: _getStyle(fontSize: isVertical ? 15 : 18, fontWeight: FontWeight.w900),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              reportTitle ?? 'تقرير المتابعة والنمو الأكاديمي الشامل لولي الأمر 📊',
                              style: _getStyle(fontSize: isVertical ? 10 : 11, color: effectiveSubtitleColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: effectiveCardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.primary.withValues(alpha: isDarkMode ? 0.3 : 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'كود التوثيق',
                        style: _getStyle(fontSize: 8.5, color: effectiveSubtitleColor),
                        maxLines: 1,
                      ),
                      Text(
                        reportCode,
                        style: _getStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.primary),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Divider
            Divider(color: theme.primary.withValues(alpha: isDarkMode ? 0.2 : 0.15), height: 1),
            const SizedBox(height: 14),

            // 2. Student Spotlight Card (No mention of "المركز")
            Container(
              padding: EdgeInsets.symmetric(horizontal: isVertical ? 12 : 18, vertical: isVertical ? 10 : 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDarkMode
                      ? [
                          theme.secondary.withValues(alpha: 0.18),
                          theme.cardBg.withValues(alpha: 0.7),
                        ]
                      : [
                          theme.secondary.withValues(alpha: 0.10),
                          theme.cardBgLight.withValues(alpha: 0.9),
                        ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.primary.withValues(alpha: isDarkMode ? 0.25 : 0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        _buildStudentAvatar(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                student.fullName,
                                style: _getStyle(fontSize: isVertical ? 14.5 : 16, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _formattedGradeAndGroup,
                                style: _getStyle(fontSize: isVertical ? 10.5 : 11.5, color: effectiveSubtitleColor),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showRank) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isStudentAbsent
                              ? const [Color(0xFFEF4444), Color(0xFFDC2626)]
                              : (_isStudentLate
                                  ? const [Color(0xFFF59E0B), Color(0xFFD97706)]
                                  : const [Color(0xFF10B981), Color(0xFF059669)]),
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: (_isStudentAbsent
                                    ? const Color(0xFFEF4444)
                                    : (_isStudentLate ? const Color(0xFFF59E0B) : const Color(0xFF10B981)))
                                .withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_isStudentAbsent ? '🚨' : (_isStudentLate ? '⏰' : '⭐'), style: const TextStyle(fontSize: 11)),
                          const SizedBox(width: 4),
                          Text(
                            rankText != null && rankText!.isNotEmpty
                                ? rankText!
                                : (_isStudentAbsent
                                    ? 'تنبيه غياب ومتابعة ⚠️'
                                    : (_isStudentLate ? 'تنبيه تأخير ⏰' : 'طالب متميز')),
                            style: _getStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. Performance Metrics (Vertical Flow vs Grid)
            if (layout == ReportCardLayout.vertical) ...[
              // VERTICAL FLOW (تحت بعض)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showAttendance)
                    _buildVerticalMetricRow(
                      icon: '📅',
                      title: 'نسبة الحضور والمواظبة',
                      value: attendanceStatusLabel ?? '$attendancePercent%',
                      sub: _isStudentAbsent
                          ? 'غياب عن الحصة 🚨'
                          : (_isStudentLate
                              ? 'حاضر متأخر ⏰'
                              : (attendancePercent >= 90
                                  ? 'ملتزم جداً 🌟'
                                  : (attendancePercent >= 75 ? 'انضباط جيد 👍' : 'غياب متكرر ⚠️'))),
                      subColor: _isStudentAbsent
                          ? const Color(0xFFEF4444)
                          : (_isStudentLate ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
                      progress: attendancePercent / 100.0,
                      subNote: subAttendanceNote ??
                          (_isStudentAbsent ? 'غائب عن حصة اليوم' : '$presentCount من $totalSessions حصص'),
                    ),
                  if (showExams && examScores.isNotEmpty)
                    _buildVerticalMetricRow(
                      icon: '🎯',
                      title: 'متوسط درجات الاختبارات',
                      value: '${averageScorePercent.toStringAsFixed(1)}%',
                      sub: averageScorePercent >= 90
                          ? 'امتياز تفوق 🏆'
                          : (averageScorePercent >= 75 ? 'جيد جداً 👍' : (averageScorePercent >= 50 ? 'مستوى جيد 📋' : 'بحاجة لمتابعة ⚠️')),
                      subColor: theme.primary,
                      progress: (averageScorePercent / 100.0).clamp(0.0, 1.0),
                      subNote: 'إجمالي ${examScores.length} اختبارات مسجلة',
                    ),
                  if (showHomework)
                    _buildVerticalMetricRow(
                      icon: '✍️',
                      title: 'الواجب والتسميع الشفوي',
                      value: homeworkStatusLabel ?? (_isStudentAbsent ? 'لم يحضر للتسليم 🚨' : '100%'),
                      sub: recitationRatingLabel != null
                          ? 'تسميع: $recitationRatingLabel'
                          : (_isStudentAbsent ? 'تعذر التقييم لغياب الطالب 🚨' : 'واجب كامل ممتاز ✅'),
                      subColor: _isStudentAbsent ? const Color(0xFFEF4444) : const Color(0xFF8B5CF6),
                      progress: _isStudentAbsent ? 0.0 : 1.0,
                      subNote: _isStudentAbsent ? 'لم يحضر الطالب الحصة' : 'الحصة الحالية والسابقة',
                    ),
                  if (_canShowFinance)
                    _buildVerticalMetricRow(
                      icon: '💳',
                      title: 'الموقف المالي والاشتراك',
                      value: student.hasOutstandingPayment ? '${student.outstandingAmount} ج.م' : 'خالص بالكامل ✨',
                      sub: student.hasOutstandingPayment ? 'مطلوب سداد الاشتراك' : 'مسدد بالكامل لشهر المتابعة',
                      subColor: student.hasOutstandingPayment ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                      progress: student.hasOutstandingPayment ? 0.35 : 1.0,
                      subNote: student.hasOutstandingPayment ? 'متأخرات ⚠️' : 'الاشتراك مسدد ✅',
                    ),
                ],
              ),
            ] else ...[
              // GRID FLOW (شبكي)
              Row(
                children: [
                  if (showAttendance)
                    Expanded(
                      child: _buildKpiBox(
                        icon: '📅',
                        value: attendanceStatusLabel ?? '$attendancePercent%',
                        label: attendanceStatusLabel != null ? 'حالة الحضور' : 'نسبة الحضور',
                        sub: _isStudentAbsent
                            ? 'غياب عن الحصة 🚨'
                            : (_isStudentLate
                                ? 'حاضر متأخر ⏰'
                                : (attendanceStatusLabel != null
                                    ? 'التزام عام $attendancePercent%'
                                    : '$presentCount من $totalSessions حصص')),
                        subColor: _isStudentAbsent
                            ? const Color(0xFFEF4444)
                            : (_isStudentLate ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
                      ),
                    ),
                  if (showExams && examScores.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildKpiBox(
                        icon: '🎯',
                        value: '${averageScorePercent.toStringAsFixed(1)}%',
                        label: 'متوسط الاختبارات',
                        sub: averageScorePercent >= 90 ? 'مستوى امتياز 🌟' : 'مستوى جيد جداً 👍',
                        subColor: theme.primary,
                      ),
                    ),
                  ],
                  if (showHomework) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildKpiBox(
                        icon: '✍️',
                        value: homeworkStatusLabel ?? (_isStudentAbsent ? 'لم يحضر 🚨' : '100%'),
                        label: 'الواجب والتسميع',
                        sub: recitationRatingLabel != null
                            ? 'تسميع: $recitationRatingLabel'
                            : (_isStudentAbsent ? 'لم يُسمّع (غائب) 🚨' : 'التزام تام بالتكليفات ✅'),
                        subColor: _isStudentAbsent ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      ),
                    ),
                  ],
                  if (_canShowFinance) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildKpiBox(
                        icon: '💳',
                        value: student.hasOutstandingPayment ? '${student.outstandingAmount} ج' : 'خالص',
                        label: 'الموقف المالي',
                        sub: student.hasOutstandingPayment ? 'مطلوب سداد' : 'مسدد بالكامل ✨',
                        subColor: student.hasOutstandingPayment ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 16),

            // 4. Exams & Assessments
            if (showExams && examScores.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.assessment_rounded, color: theme.primary, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'سجل الاختبارات والتقييمات الأخيرة',
                      style: _getStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: theme.primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (layout == ReportCardLayout.vertical) ...[
                // Vertical exam cards (تحت بعض)
                ...examScores.take(3).map((item) => _buildVerticalExamCard(item, dateStr, effectiveCardBg, effectiveSubtitleColor)),
              ] else ...[
                // Grid table
                Container(
                  decoration: BoxDecoration(
                    color: effectiveCardBg.withValues(alpha: isDarkMode ? 0.6 : 0.9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.primary.withValues(alpha: isDarkMode ? 0.2 : 0.15)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      children: [
                        Container(
                          color: isDarkMode
                              ? const Color(0xFF1E293B).withValues(alpha: 0.8)
                              : theme.primary.withValues(alpha: 0.08),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Text('الاختبار / التقييم', style: _getStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDarkMode ? theme.primary : theme.secondary))),
                              Expanded(flex: 2, child: Text('التاريخ', style: _getStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDarkMode ? theme.primary : theme.secondary))),
                              Expanded(flex: 2, child: Text('الدرجة المحققة', style: _getStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDarkMode ? theme.primary : theme.secondary))),
                              Expanded(flex: 2, child: Text('النسبة', style: _getStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDarkMode ? theme.primary : theme.secondary))),
                              Expanded(flex: 2, child: Text('التقدير', style: _getStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDarkMode ? theme.primary : theme.secondary))),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: isDarkMode ? const Color(0x2238BDF8) : theme.primary.withValues(alpha: 0.12)),
                        if (examScores.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              'لا توجد اختبارات مسجلة للطالب في هذه الفترة',
                              style: _getStyle(fontSize: 11.5, color: effectiveSubtitleColor),
                            ),
                          )
                        else
                          ...examScores.take(3).map((item) {
                            final title = item['title'] ?? 'اختبار دوري';
                            final score = (item['score'] ?? 0).toDouble();
                            final max = (item['max_score'] ?? 50).toDouble();
                            final pct = max > 0 ? (score / max * 100).round() : 0;
                            final date = item['date'] ?? dateStr;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: isDarkMode ? const Color(0x1538BDF8) : theme.primary.withValues(alpha: 0.08),
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(flex: 3, child: Text(title, style: _getStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                                  Expanded(flex: 2, child: Text(date, style: _getStyle(fontSize: 10.5, color: effectiveSubtitleColor))),
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: theme.primary.withValues(alpha: isDarkMode ? 0.15 : 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '$score / $max',
                                        style: _getStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.primary),
                                      ),
                                    ),
                                  ),
                                  Expanded(flex: 2, child: Text('$pct%', style: _getStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      pct >= 90 ? 'ممتاز 🌟' : (pct >= 75 ? 'جيد جداً 👍' : 'مقبول'),
                                      style: _getStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: pct >= 90 ? const Color(0xFF10B981) : (pct >= 75 ? theme.primary : const Color(0xFFF59E0B)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],

            // Lesson & Curriculum Breakdown (نفس بيانات التقرير الكتابي)
            if (_hasLessonDetails) ...[
              _buildLessonBreakdownBox(effectiveCardBg, effectiveSubtitleColor),
              const SizedBox(height: 14),
            ],

            // 5. Teacher's Evaluation & Note Box
            if (showTeacherNote) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDarkMode
                        ? [
                            const Color(0xFF1E293B).withValues(alpha: 0.6),
                            theme.cardBg.withValues(alpha: 0.8),
                          ]
                        : [
                            theme.cardBgLight,
                            Colors.white,
                          ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.primary.withValues(alpha: isDarkMode ? 0.35 : 0.25),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3.5,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('💡', style: TextStyle(fontSize: 13)),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  'ملاحظة وتوجيه أستاذ المادة لولي الأمر:',
                                  style: _getStyle(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFF59E0B)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            teacherNote != null && teacherNote!.trim().isNotEmpty
                                ? teacherNote!
                                : 'طالب متميز وملتزم داخل قاعة الحصة. نوصي باستمرار نفس وتيرة المذاكرة المنتظمة للحفاظ على التفوق المستمر في المراجعات القادمة 🌟',
                            style: _getStyle(
                              fontSize: 11,
                              color: isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // 6. Footer: Verification QR & Signatures
            Divider(color: theme.primary.withValues(alpha: isDarkMode ? 0.2 : 0.15), height: 1),
            const SizedBox(height: 14),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // QR Verification Block
                Expanded(
                  child: showQr
                      ? Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: QrImageView(
                                data: 'https://eduacademy.app/verify/$reportCode',
                                version: QrVersions.auto,
                                size: 38,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'توثيق رسمي معتمد 🛡️',
                                    style: _getStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.primary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'امسح الرمز للتحقق الفوري',
                                    style: _getStyle(fontSize: 8.5, color: effectiveSubtitleColor),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'تاريخ: $dateStr م',
                                    style: _getStyle(fontSize: 8, color: effectiveSubtitleColor),
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تقرير رسمي معتمد 🛡️',
                              style: _getStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: theme.primary),
                              maxLines: 1,
                            ),
                            Text(
                              'صدر بتاريخ: $dateStr م',
                              style: _getStyle(fontSize: 8.5, color: effectiveSubtitleColor),
                              maxLines: 1,
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 10),

                // Signatures & Stamp
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showStamp) ...[
                      Column(
                        children: [
                          _buildOfficialStamp(),
                          const SizedBox(height: 2),
                          Text(
                            'ختم الإدارة',
                            style: _getStyle(fontSize: 8, color: effectiveSubtitleColor),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                    ],
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text('✍️', style: TextStyle(fontSize: 14)),
                        Container(
                          width: 60,
                          height: 1,
                          color: theme.primary.withValues(alpha: 0.3),
                          margin: const EdgeInsets.symmetric(vertical: 2),
                        ),
                        Text(
                          teacherName.isNotEmpty ? teacherName : 'أستاذ المادة',
                          style: _getStyle(fontSize: 9.5, fontWeight: FontWeight.bold),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalMetricRow({
    required String icon,
    required String title,
    required String value,
    required String sub,
    required Color subColor,
    double? progress,
    String? subNote,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF1E293B).withValues(alpha: 0.6)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkMode
              ? theme.primary.withValues(alpha: 0.18)
              : const Color(0xFFCBD5E1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Title & Icon on right + SubNote on left
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: _getStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
              if (subNote != null && subNote.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  subNote,
                  style: _getStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),

          // Row 2: Half-Width Progress Bar (~45-50% width) + Prominent Bold Rating Badge right next to it!
          Row(
            children: [
              if (progress != null) ...[
                Expanded(
                  flex: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                      color: subColor,
                      minHeight: 7,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: progress != null ? 6 : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: subColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: subColor.withValues(alpha: 0.3)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      '$value • $sub',
                      style: _getStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: subColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _hasLessonDetails =>
      (lessonTitle != null && lessonTitle!.trim().isNotEmpty) ||
      (previousHomeworkReview != null && previousHomeworkReview!.trim().isNotEmpty) ||
      (homeworkText != null && homeworkText!.trim().isNotEmpty) ||
      (nextTopic != null && nextTopic!.trim().isNotEmpty) ||
      (nextQuiz != null && nextQuiz!.trim().isNotEmpty);

  /// Strictly enforces that financial status is ONLY permitted in monthly reports.
  /// It is completely suppressed in daily session reports, weekly reports, or whenever sessionDate/lessonTitle is present.
  bool get _canShowFinance {
    if (!showFinance) return false;
    final title = (reportTitle ?? '').toLowerCase();
    if (sessionDate != null && sessionDate!.trim().isNotEmpty) return false;
    if (lessonTitle != null && lessonTitle!.trim().isNotEmpty) return false;
    if (title.contains('حصة') || title.contains('حصه') || title.contains('يومي') || title.contains('اسبوعي') || title.contains('أسبوعي')) {
      return false;
    }
    final isMonthly = title.contains('شهري') || title.contains('شهر') || title.contains('شامل');
    return isMonthly;
  }

  bool get _isStudentAbsent {
    if (attendanceStatusLabel != null) {
      final lbl = attendanceStatusLabel!;
      if (lbl.contains('غائب') ||
          lbl.contains('غياب') ||
          lbl.contains('اعتذار') ||
          lbl.contains('إلغاء')) {
        return true;
      }
    }
    return attendancePercent == 0 && (sessionDate != null && sessionDate!.isNotEmpty);
  }

  bool get _isStudentLate {
    if (attendanceStatusLabel != null) {
      return attendanceStatusLabel!.contains('متأخر');
    }
    return attendancePercent == 85;
  }

  String get _formattedGradeAndGroup {
    final gGrade = (groupGrade != null && groupGrade!.trim().isNotEmpty)
        ? groupGrade!.trim()
        : student.grade.trim();
    final gName = groupName.trim().isNotEmpty ? groupName.trim() : 'المجموعة العامة';
    if (gGrade.isEmpty) {
      return gName;
    }
    if (gName.startsWith(gGrade) || gName.contains(gGrade)) {
      return gName;
    }
    return '$gGrade • $gName';
  }

  Widget _buildLessonBreakdownBox(Color effectiveCardBg, Color effectiveSubtitleColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: effectiveCardBg.withValues(alpha: isDarkMode ? 0.6 : 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.primary.withValues(alpha: isDarkMode ? 0.2 : 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book_rounded, color: theme.primary, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'تفاصيل الحصة والتكليفات المشروحة 📚',
                  style: _getStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (lessonTitle != null && lessonTitle!.trim().isNotEmpty)
            _buildBreakdownRow('📖 الدرس المشروح:', lessonTitle!, effectiveSubtitleColor),
          if (previousHomeworkReview != null && previousHomeworkReview!.trim().isNotEmpty)
            _buildBreakdownRow('🔍 مراجعة الواجب:', previousHomeworkReview!, effectiveSubtitleColor),
          if (homeworkText != null && homeworkText!.trim().isNotEmpty)
            _buildBreakdownRow('📝 الواجب المنزلي:', homeworkText!, effectiveSubtitleColor),
          if (nextTopic != null && nextTopic!.trim().isNotEmpty)
            _buildBreakdownRow('🎯 التحضير القادم:', nextTopic!, effectiveSubtitleColor),
          if (nextQuiz != null && nextQuiz!.trim().isNotEmpty)
            _buildBreakdownRow('⏰ كويز الحصة القادمة:', nextQuiz!, const Color(0xFFF59E0B)),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String label, String value, Color subtitleColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _getStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: subtitleColor)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: _getStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalExamCard(
    Map<String, dynamic> item,
    String dateStr,
    Color effectiveCardBg,
    Color effectiveSubtitleColor,
  ) {
    final title = item['title'] ?? 'اختبار دوري';
    final score = (item['score'] ?? 0).toDouble();
    final max = (item['max_score'] ?? 50).toDouble();
    final pct = max > 0 ? (score / max * 100).round() : 0;
    final date = item['date'] ?? dateStr;
    final isTop = pct >= 90;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDarkMode
            ? effectiveCardBg.withValues(alpha: 0.7)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDarkMode ? theme.primary.withValues(alpha: 0.15) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _getStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(date, style: _getStyle(fontSize: 9.5, color: effectiveSubtitleColor)),
              ],
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.primary.withValues(alpha: isDarkMode ? 0.15 : 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$score / $max',
                  style: _getStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: theme.primary),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isTop ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$pct% ${isTop ? "ممتاز 🌟" : (pct >= 75 ? "جيد جداً 👍" : "مقبول")}',
                  style: _getStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isTop ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiBox({
    required String icon,
    required String value,
    required String label,
    required String sub,
    required Color subColor,
  }) {
    final effectiveSubtitleColor = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF1E293B).withValues(alpha: 0.5)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode
              ? theme.primary.withValues(alpha: 0.15)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 2),
          Text(value, style: _getStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          Text(label, style: _getStyle(fontSize: 9.5, color: effectiveSubtitleColor)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: subColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              sub,
              style: _getStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: subColor),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal Sheet for configuring font, layout, previewing, and exporting the Visual Report Card
class VisualReportCardModalSheet extends StatefulWidget {
  final StudentModel student;
  final String groupName;
  final String? groupGrade;
  final int attendancePercent;
  final int presentCount;
  final int totalSessions;
  final double averageScorePercent;
  final List<Map<String, dynamic>> examScores;
  final String? teacherNote;
  final String centerName;
  final String teacherName;
  final String? rankText;
  final String? reportTitle;
  final String? sessionDate;
  final String? attendanceStatusLabel;
  final String? homeworkStatusLabel;
  final String? recitationRatingLabel;
  final String? lessonTitle;
  final String? previousHomeworkReview;
  final String? homeworkText;
  final String? nextTopic;
  final String? nextQuiz;
  final String? subAttendanceNote;
  final DatabaseService database;

  const VisualReportCardModalSheet({
    super.key,
    required this.student,
    required this.groupName,
    this.groupGrade,
    required this.attendancePercent,
    required this.presentCount,
    required this.totalSessions,
    required this.averageScorePercent,
    required this.examScores,
    this.teacherNote,
    required this.centerName,
    required this.teacherName,
    this.rankText,
    this.reportTitle,
    this.sessionDate,
    this.attendanceStatusLabel,
    this.homeworkStatusLabel,
    this.recitationRatingLabel,
    this.lessonTitle,
    this.previousHomeworkReview,
    this.homeworkText,
    this.nextTopic,
    this.nextQuiz,
    this.subAttendanceNote,
    required this.database,
  });

  static Future<void> show(
    BuildContext context, {
    required StudentModel student,
    required String groupName,
    String? groupGrade,
    required int attendancePercent,
    required int presentCount,
    required int totalSessions,
    required double averageScorePercent,
    required List<Map<String, dynamic>> examScores,
    String? teacherNote,
    required String centerName,
    required String teacherName,
    String? rankText,
    String? reportTitle,
    String? sessionDate,
    String? attendanceStatusLabel,
    String? homeworkStatusLabel,
    String? recitationRatingLabel,
    String? lessonTitle,
    String? previousHomeworkReview,
    String? homeworkText,
    String? nextTopic,
    String? nextQuiz,
    String? subAttendanceNote,
    required DatabaseService database,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VisualReportCardModalSheet(
        student: student,
        groupName: groupName,
        groupGrade: groupGrade,
        attendancePercent: attendancePercent,
        presentCount: presentCount,
        totalSessions: totalSessions,
        averageScorePercent: averageScorePercent,
        examScores: examScores,
        teacherNote: teacherNote,
        centerName: centerName,
        teacherName: teacherName,
        rankText: rankText,
        reportTitle: reportTitle,
        sessionDate: sessionDate,
        attendanceStatusLabel: attendanceStatusLabel,
        homeworkStatusLabel: homeworkStatusLabel,
        recitationRatingLabel: recitationRatingLabel,
        lessonTitle: lessonTitle,
        previousHomeworkReview: previousHomeworkReview,
        homeworkText: homeworkText,
        nextTopic: nextTopic,
        nextQuiz: nextQuiz,
        subAttendanceNote: subAttendanceNote,
        database: database,
      ),
    );
  }

  @override
  State<VisualReportCardModalSheet> createState() => _VisualReportCardModalSheetState();
}

class _VisualReportCardModalSheetState extends State<VisualReportCardModalSheet> {
  final GlobalKey _cardRepaintKey = GlobalKey();
  ReportCardFont _selectedFont = ReportCardFont.cairo;
  ReportCardTheme _selectedTheme = ReportCardTheme.cyan;
  ReportCardLayout _selectedLayout = ReportCardLayout.vertical;
  bool _isDarkMode = true;
  bool _showQr = true;
  bool _showFinance = true;
  bool _showStamp = true;
  bool _showAttendance = true;
  bool _showExams = true;
  bool _showHomework = true;
  bool _showRank = false;
  bool _showTeacherNote = true;
  String? _customReportTitle;
  String? _customGroupName;
  String? _customGrade;
  List<GroupModel> _allAvailableGroups = [];
  String? _headerLogoPath;
  String? _studentPhotoPath;
  String? _stampLogoPath;
  bool _isExporting = false;
  bool _includeTextMessage = true;

  String get _effectiveGroupName => (_customGroupName != null && _customGroupName!.trim().isNotEmpty)
      ? _customGroupName!
      : (widget.groupName.isNotEmpty ? widget.groupName : 'المجموعة العامة');

  String get _effectiveGrade => (_customGrade != null && _customGrade!.trim().isNotEmpty)
      ? _customGrade!
      : (widget.groupGrade != null && widget.groupGrade!.trim().isNotEmpty)
          ? widget.groupGrade!
          : widget.student.grade;

  bool get _isDailyOrWeekly =>
      (widget.sessionDate != null && widget.sessionDate!.trim().isNotEmpty) ||
      (widget.lessonTitle != null && widget.lessonTitle!.trim().isNotEmpty) ||
      ((_customReportTitle ?? widget.reportTitle ?? '').toLowerCase().contains('حصة') ||
       (_customReportTitle ?? widget.reportTitle ?? '').toLowerCase().contains('حصه') ||
       (_customReportTitle ?? widget.reportTitle ?? '').toLowerCase().contains('يومي') ||
       (_customReportTitle ?? widget.reportTitle ?? '').toLowerCase().contains('أسبوعي') ||
       (_customReportTitle ?? widget.reportTitle ?? '').toLowerCase().contains('اسبوعي'));

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
  }

  Future<void> _loadUserPreferences() async {
    try {
      final mode = await widget.database.getSetting('report_card_default_mode', defaultValue: 'dark');
      final fontStr = await widget.database.getSetting('report_card_default_font', defaultValue: 'cairo');
      final themeStr = await widget.database.getSetting('report_card_default_theme', defaultValue: 'cyan');
      final layoutStr = await widget.database.getSetting('report_card_default_layout', defaultValue: 'vertical');
      final showQrStr = await widget.database.getSetting('report_card_show_qr', defaultValue: 'true');
      final showFinanceStr = await widget.database.getSetting('report_card_show_finance', defaultValue: 'true');
      final showStampStr = await widget.database.getSetting('report_card_show_stamp', defaultValue: 'true');
      final showAttendanceStr = await widget.database.getSetting('report_card_show_attendance', defaultValue: 'true');
      final showExamsStr = await widget.database.getSetting('report_card_show_exams', defaultValue: 'true');
      final showHomeworkStr = await widget.database.getSetting('report_card_show_homework', defaultValue: 'true');
      final showRankStr = await widget.database.getSetting('report_card_show_rank', defaultValue: 'false');
      final showNoteStr = await widget.database.getSetting('report_card_show_note', defaultValue: 'true');
      final savedTitle = await widget.database.getSetting('report_card_default_title', defaultValue: '');
      final incTextStr = await widget.database.getSetting('report_card_include_text_message', defaultValue: 'true');

      // Load available groups for instant picking and resolution
      _allAvailableGroups = await widget.database.getGroups();

      // Resolve student's authentic group and grade from database
      String? resolvedGroupName;
      String? resolvedGrade;
      GroupModel? matchedGroup;
      if (widget.student.groupId != null && widget.student.groupId!.trim().isNotEmpty) {
        matchedGroup = _allAvailableGroups.where((x) => x.id.trim() == widget.student.groupId!.trim()).firstOrNull;
      }
      if (matchedGroup == null && widget.groupName.isNotEmpty) {
        matchedGroup = _allAvailableGroups.where((x) => x.name.trim() == widget.groupName.trim()).firstOrNull;
      }
      if (matchedGroup == null) {
        for (final g in _allAvailableGroups) {
          final stList = await widget.database.getStudents(groupId: g.id);
          if (stList.any((s) => s.id == widget.student.id)) {
            matchedGroup = g;
            break;
          }
        }
      }

      if (matchedGroup != null) {
        resolvedGroupName = matchedGroup.name;
        if (matchedGroup.grade.isNotEmpty) {
          resolvedGrade = matchedGroup.grade;
          // Synchronize database if student's record has mismatched grade:
          if (widget.student.grade != matchedGroup.grade) {
            try {
              await widget.database.updateStudentsBatchFields(
                [widget.student.id],
                grade: matchedGroup.grade,
                stage: matchedGroup.stage,
              );
            } catch (_) {}
          }
        }
      }

      // Strict rule: Financial status is forbidden in daily and weekly reports.
      // Permissible ONLY in monthly comprehensive reports.
      final titleLower = (savedTitle.isNotEmpty ? savedTitle : (widget.reportTitle ?? '')).toLowerCase();
      final isDailyOrWeekly = (widget.sessionDate != null && widget.sessionDate!.trim().isNotEmpty) ||
          (widget.lessonTitle != null && widget.lessonTitle!.trim().isNotEmpty) ||
          titleLower.contains('حصة') || titleLower.contains('حصه') || titleLower.contains('يومي') || titleLower.contains('أسبوعي') || titleLower.contains('اسبوعي');

      final showFinanceEffective = isDailyOrWeekly ? false : (showFinanceStr == 'true');

      // Load logo & photo paths (with fallbacks to certificate logos)
      var hLogo = await widget.database.getSetting('report_card_header_logo_path', defaultValue: '');
      if (hLogo.isEmpty) {
        hLogo = await widget.database.getSetting('custom_logo_path', defaultValue: '');
      }
      if (hLogo.isEmpty) {
        hLogo = await widget.database.getSetting('cert_custom_top_image_path', defaultValue: '');
      }
      var sLogo = await widget.database.getSetting('report_card_stamp_logo_path', defaultValue: '');
      if (sLogo.isEmpty) {
        sLogo = await widget.database.getSetting('custom_logo_path', defaultValue: '');
      }
      if (sLogo.isEmpty) {
        sLogo = await widget.database.getSetting('cert_custom_top_image_path', defaultValue: '');
      }
      final stdPhoto = await widget.database.getSetting('student_photo_${widget.student.id}', defaultValue: '');

      if (!mounted) return;
      setState(() {
        _isDarkMode = mode != 'light';
        _selectedFont = ReportCardFont.values.firstWhere(
          (f) => f.name.toLowerCase() == fontStr.toLowerCase(),
          orElse: () => ReportCardFont.cairo,
        );
        _selectedTheme = ReportCardTheme.values.firstWhere(
          (t) => t.name.toLowerCase() == themeStr.toLowerCase(),
          orElse: () => ReportCardTheme.cyan,
        );
        _selectedLayout = layoutStr == 'grid' ? ReportCardLayout.grid : ReportCardLayout.vertical;
        _showQr = showQrStr == 'true';
        _showFinance = showFinanceEffective;
        _showStamp = showStampStr == 'true';
        _showAttendance = showAttendanceStr == 'true';
        _showExams = showExamsStr == 'true';
        _showHomework = showHomeworkStr == 'true';
        _showRank = showRankStr == 'true';
        _showTeacherNote = showNoteStr == 'true';
        _includeTextMessage = incTextStr == 'true';
        if (savedTitle.isNotEmpty) {
          _customReportTitle = savedTitle;
        }
        if (resolvedGroupName != null && resolvedGroupName.isNotEmpty) {
          _customGroupName = resolvedGroupName;
        }
        if (resolvedGrade != null && resolvedGrade.isNotEmpty) {
          _customGrade = resolvedGrade;
        }
        if (hLogo.isNotEmpty && File(hLogo).existsSync()) {
          _headerLogoPath = hLogo;
        }
        if (sLogo.isNotEmpty && File(sLogo).existsSync()) {
          _stampLogoPath = sLogo;
        }
        if (stdPhoto.isNotEmpty && File(stdPhoto).existsSync()) {
          _studentPhotoPath = stdPhoto;
        }
      });
    } catch (_) {}
  }

  void _editGroupNameDialog() {
    final ctrl = TextEditingController(text: _effectiveGroupName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.groups_rounded, color: Color(0xFF00F2FE), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'تعديل وتحديد اسم المجموعة في التقرير 👥',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'اسم المجموعة المعروض',
                    labelStyle: const TextStyle(color: Color(0xFF00F2FE)),
                    hintText: 'اكتب اسم المجموعة أو اختر من القائمة أدناه',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF00F2FE)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_allAvailableGroups.isNotEmpty) ...[
                  const Text(
                    'أو اختر مباشرة من مجموعات السنتر المسجلة:',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _allAvailableGroups.map((g) {
                      final isSelected = ctrl.text.trim() == g.name.trim();
                      return ActionChip(
                        label: Text(g.name),
                        backgroundColor: isSelected ? const Color(0xFF00F2FE).withValues(alpha: 0.25) : const Color(0xFF1E293B),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF00F2FE) : const Color(0xFF334155),
                        ),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFF00F2FE) : Colors.white70,
                        ),
                        onPressed: () {
                          ctrl.text = g.name;
                          setState(() {
                            _customGroupName = g.name;
                          });
                          Navigator.pop(ctx);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                ],
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_rounded, color: Colors.black),
                  label: const Text('تأكيد وحفظ اسم المجموعة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F2FE),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    final newName = ctrl.text.trim();
                    if (newName.isNotEmpty) {
                      setState(() {
                        _customGroupName = newName;
                      });
                    }
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickLogo({required bool isBottomSeal}) async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty || result.first.path == null) return;

      final pickedFile = File(result.first.path!);
      if (!pickedFile.existsSync()) return;

      if (!mounted) return;
      final croppedFile = await CircularImageCropper.cropImage(
        context,
        imagePath: pickedFile.path,
        title: isBottomSeal ? 'قص وتعديل ختم التقرير الرسمي (السفلي)' : 'قص وتعديل لوجو المؤسسة (العلوي)',
        isBottomSeal: isBottomSeal,
      );
      if (croppedFile == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final logosDir = Directory('${appDir.path}/report_logos');
      if (!logosDir.existsSync()) logosDir.createSync(recursive: true);

      final ext = croppedFile.path.contains('.') ? croppedFile.path.split('.').last : 'png';
      final savedPath = '${logosDir.path}/report_${isBottomSeal ? "stamp" : "header"}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final savedLogo = await croppedFile.copy(savedPath);

      final key = isBottomSeal ? 'report_card_stamp_logo_path' : 'report_card_header_logo_path';
      await widget.database.setSetting(key, savedLogo.path);

      if (!mounted) return;
      setState(() {
        if (isBottomSeal) {
          _stampLogoPath = savedLogo.path;
        } else {
          _headerLogoPath = savedLogo.path;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isBottomSeal ? 'تم تعيين ختم الإدارة المعتمد بنجاح! ⚜️✨' : 'تم تعيين لوجو المؤسسة بنجاح! 🏫✨'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('Error picking logo: $e');
    }
  }

  Future<void> _pickStudentPhoto() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty || result.first.path == null) return;

      final pickedFile = File(result.first.path!);
      if (!pickedFile.existsSync()) return;

      if (!mounted) return;
      final croppedFile = await CircularImageCropper.cropImage(
        context,
        imagePath: pickedFile.path,
        title: 'قص وتعديل صورة الطالب المعتمدة',
        isBottomSeal: false,
      );
      if (croppedFile == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final stdDir = Directory('${appDir.path}/student_photos');
      if (!stdDir.existsSync()) stdDir.createSync(recursive: true);

      final ext = croppedFile.path.contains('.') ? croppedFile.path.split('.').last : 'png';
      final savedPath = '${stdDir.path}/std_${widget.student.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final savedImg = await croppedFile.copy(savedPath);

      await widget.database.setSetting('student_photo_${widget.student.id}', savedImg.path);

      if (!mounted) return;
      setState(() {
        _studentPhotoPath = savedImg.path;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم اعتماد صورة الطالب بنجاح! 👨‍🎓✨'),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('Error picking student photo: $e');
    }
  }

  Future<File?> _captureCardImage() async {
    try {
      final boundary = _cardRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final cleanName = widget.student.fullName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '_');
      final file = File('${tempDir.path}/ReportCard_$cleanName.png');
      await file.writeAsBytes(pngBytes);
      return file;
    } catch (e) {
      debugPrint('Error capturing report card: $e');
      return null;
    }
  }

  Future<void> _shareReportCard({bool directWhatsApp = false}) async {
    if (_isExporting) return;
    HapticFeedback.mediumImpact();
    setState(() => _isExporting = true);

    try {
      final file = await _captureCardImage();
      if (file == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر التقاط صورة كارت التقرير، يرجى المحاولة ثانية')),
          );
        }
        return;
      }

      final message = _includeTextMessage
          ? ('تقرير المتابعة والنمو الأكاديمي الشامل للطالب: *${widget.student.fullName}* 📊🎓\n'
             'من إدارة: *${widget.centerName}* | المعلم: *${widget.teacherName}*\n\n'
             'مرفق كارت التقرير المعتمد موضحاً به نسبة الحضور (${widget.attendancePercent}%) والدرجات والملاحظات التربوية. نتمنى له دوام التفوق والنجاح! 🌟')
          : '';

      if (directWhatsApp && widget.student.parentPhone.isNotEmpty) {
        try {
          Clipboard.setData(ClipboardData(text: widget.student.parentPhone));
        } catch (_) {}
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              name: 'Report_${widget.student.fullName}.png',
              mimeType: 'image/png',
            ),
          ],
          text: message,
        ),
      );

      // Log in database
      await widget.database.logWhatsAppMessage(
        studentId: widget.student.id,
        studentName: widget.student.fullName,
        phone: widget.student.parentPhone,
        recipientType: 'parent',
        category: 'visualReportCard',
        message: message,
        status: 'sent',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم توليد ومشاركة كارت التقرير المصور بنجاح 🖼️✓'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sharing report card: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء المشاركة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _sendElectronicApi() async {
    if (_isExporting) return;
    HapticFeedback.mediumImpact();
    setState(() => _isExporting = true);

    try {
      final file = await _captureCardImage();
      if (file == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر التقاط صورة كارت التقرير، يرجى المحاولة ثانية')),
          );
        }
        return;
      }

      final pPhone = widget.student.parentPhone.trim();
      final sPhone = widget.student.studentPhone.trim();
      final phone = pPhone.isNotEmpty ? pPhone : sPhone;

      if (phone.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('عذراً، لا يوجد رقم هاتف مسجل للطالب ${widget.student.fullName}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final message = _includeTextMessage
          ? ('تقرير المتابعة والنمو الأكاديمي الشامل للطالب: *${widget.student.fullName}* 📊🎓\n'
             'من إدارة: *${widget.centerName}* | المعلم: *${widget.teacherName}*\n\n'
             'مرفق كارت التقرير المعتمد موضحاً به نسبة الحضور (${widget.attendancePercent}%) والدرجات والملاحظات التربوية. نتمنى له دوام التفوق والنجاح! 🌟')
          : '';

      final ok = await WhatsAppService.dispatchMessage(
        database: widget.database,
        phone: phone,
        message: message,
        studentId: widget.student.id,
        studentName: widget.student.fullName,
        recipientType: 'parent',
        category: 'visualReportCard',
        imageFile: file,
        forceManual: false,
      );

      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم الإرسال الإلكتروني السحابي لكارت التقرير بنجاح دون أي تدخل يدوي! 🚀✨'),
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تنبيه: تعذر الإرسال السحابي المباشر. يرجى التأكد من إعدادات WhatsApp API أو استخدام خيار واتساب.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الإرسال: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final totalHeight = MediaQuery.of(context).size.height * 0.92;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: const Color(0xFF0F172A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          height: totalHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.4), width: 1.5),
          ),
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 12),
          child: Column(
            children: [
              // Top Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Modal Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.palette_rounded, color: Color(0xFF00F2FE), size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'كارت تقرير الطالب المصور الرقمي 📊✨',
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'تحكم في الصور، الخط، الوضع النهاري/الليلي، والتخطيط العمودي قبل الإرسال',
                          style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Controls Bar 1: Mode + Layout + Quick Image Change Buttons
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Day/Night Switch
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => setState(() => _isDarkMode = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _isDarkMode ? const Color(0xFF0F172A) : Colors.transparent,
                                borderRadius: BorderRadius.circular(18),
                                border: _isDarkMode ? Border.all(color: const Color(0xFF00F2FE), width: 1) : null,
                              ),
                              child: const Row(
                                children: [
                                  Text('🌙', style: TextStyle(fontSize: 11)),
                                  SizedBox(width: 4),
                                  Text('ليلي', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => setState(() => _isDarkMode = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: !_isDarkMode ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(18),
                                border: !_isDarkMode ? Border.all(color: const Color(0xFFF59E0B), width: 1) : null,
                              ),
                              child: Row(
                                children: [
                                  const Text('☀️', style: TextStyle(fontSize: 11)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'نهاري',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: !_isDarkMode ? const Color(0xFF0F172A) : Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Layout Switch (Vertical vs Grid)
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => setState(() => _selectedLayout = ReportCardLayout.vertical),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _selectedLayout == ReportCardLayout.vertical ? const Color(0xFF00F2FE).withValues(alpha: 0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(18),
                                border: _selectedLayout == ReportCardLayout.vertical ? Border.all(color: const Color(0xFF00F2FE), width: 1) : null,
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.view_agenda_rounded, size: 12, color: Color(0xFF00F2FE)),
                                  SizedBox(width: 4),
                                  Text('عمودي (تحت بعض)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => setState(() => _selectedLayout = ReportCardLayout.grid),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _selectedLayout == ReportCardLayout.grid ? const Color(0xFF00F2FE).withValues(alpha: 0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(18),
                                border: _selectedLayout == ReportCardLayout.grid ? Border.all(color: const Color(0xFF00F2FE), width: 1) : null,
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.grid_view_rounded, size: 12, color: Colors.white70),
                                  SizedBox(width: 4),
                                  Text('شبكي', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white70)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Dispatch mode: Image only vs Image + text
                    InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        setState(() => _includeTextMessage = !_includeTextMessage);
                        try {
                          await widget.database.setSetting('report_card_include_text_message', _includeTextMessage.toString());
                        } catch (_) {}
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _includeTextMessage
                              ? const Color(0xFF00F2FE).withValues(alpha: 0.18)
                              : const Color(0xFFF59E0B).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _includeTextMessage ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _includeTextMessage ? Icons.chat_rounded : Icons.image_rounded,
                              size: 13,
                              color: _includeTextMessage ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _includeTextMessage ? 'صورة + نص 🖼️📝' : 'صورة فقط 🖼️',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: _includeTextMessage ? const Color(0xFF00F2FE) : const Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Quick image buttons (Logo, Student Photo, Stamp)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF38BDF8), width: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      icon: const Icon(Icons.school_rounded, size: 14),
                      label: const Text('لوجو المؤسسة', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                      onPressed: () => _pickLogo(isBottomSeal: false),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF34D399),
                        side: const BorderSide(color: Color(0xFF34D399), width: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      icon: const Icon(Icons.account_circle_rounded, size: 14),
                      label: const Text('صورة الطالب', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                      onPressed: _pickStudentPhoto,
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFBBF24),
                        side: const BorderSide(color: Color(0xFFFBBF24), width: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      icon: const Icon(Icons.verified_rounded, size: 14),
                      label: const Text('ختم الإدارة', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                      onPressed: () => _pickLogo(isBottomSeal: true),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFA78BFA),
                        side: const BorderSide(color: Color(0xFFA78BFA), width: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      icon: const Icon(Icons.groups_rounded, size: 14),
                      label: Text(
                        'المجموعة: $_effectiveGroupName',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: _editGroupNameDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Controls Bar 2: Font & Theme Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text('الخط: ', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                    ...ReportCardFont.values.map((f) {
                      final isSel = _selectedFont == f;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(f.label, style: TextStyle(fontSize: 10.5, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                          selected: isSel,
                          selectedColor: const Color(0xFF00F2FE),
                          backgroundColor: const Color(0xFF1E293B),
                          labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white70),
                          onSelected: (val) {
                            if (val) setState(() => _selectedFont = f);
                          },
                        ),
                      );
                    }),
                    const SizedBox(width: 10),
                    const Text('النمط: ', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                    ...ReportCardTheme.values.map((t) {
                      final isSel = _selectedTheme == t;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(t.label, style: TextStyle(fontSize: 10.5, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                          selected: isSel,
                          selectedColor: t.primary,
                          backgroundColor: const Color(0xFF1E293B),
                          labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white70),
                          onSelected: (val) {
                            if (val) setState(() => _selectedTheme = t);
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Live Preview (Fitted & Pinch-to-zoom)
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _isDarkMode ? const Color(0xFF070C16) : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 3.5,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(8),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topCenter,
                            child: RepaintBoundary(
                              key: _cardRepaintKey,
                              child: VisualStudentReportCard(
                                student: widget.student,
                                groupName: _effectiveGroupName,
                                groupGrade: _effectiveGrade,
                                attendancePercent: widget.attendancePercent,
                                presentCount: widget.presentCount,
                                totalSessions: widget.totalSessions,
                                averageScorePercent: widget.averageScorePercent,
                                examScores: widget.examScores,
                                teacherNote: widget.teacherNote,
                                centerName: widget.centerName,
                                teacherName: widget.teacherName,
                                rankText: widget.rankText,
                                reportTitle: _customReportTitle ?? widget.reportTitle,
                                sessionDate: widget.sessionDate,
                                attendanceStatusLabel: widget.attendanceStatusLabel,
                                homeworkStatusLabel: widget.homeworkStatusLabel,
                                recitationRatingLabel: widget.recitationRatingLabel,
                                lessonTitle: widget.lessonTitle,
                                previousHomeworkReview: widget.previousHomeworkReview,
                                homeworkText: widget.homeworkText,
                                nextTopic: widget.nextTopic,
                                nextQuiz: widget.nextQuiz,
                                subAttendanceNote: widget.subAttendanceNote,
                                font: _selectedFont,
                                theme: _selectedTheme,
                                layout: _selectedLayout,
                                isDarkMode: _isDarkMode,
                                showQr: _showQr,
                                showFinance: !_isDailyOrWeekly && _showFinance,
                                showStamp: _showStamp,
                                showAttendance: _showAttendance,
                                showExams: _showExams,
                                showHomework: _showHomework,
                                showRank: _showRank,
                                showTeacherNote: _showTeacherNote,
                                headerLogoPath: _headerLogoPath,
                                studentPhotoPath: _studentPhotoPath,
                                stampLogoPath: _stampLogoPath,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Action Buttons: Electronic Silent API & Manual WhatsApp
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00F2FE),
                        foregroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 3,
                      ),
                      icon: _isExporting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Color(0xFF0F172A), strokeWidth: 2))
                          : const Icon(Icons.bolt_rounded, size: 21),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'إرسال إلكتروني صامت (API ⚡)',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                      ),
                      onPressed: _isExporting ? null : _sendElectronicApi,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 17),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'واتساب 📲',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      onPressed: _isExporting ? null : () => _shareReportCard(directWhatsApp: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: const Color(0xFF00F2FE),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 20),
                    tooltip: 'مشاركة كصورة عالية الدقة',
                    onPressed: _isExporting ? null : () => _shareReportCard(directWhatsApp: false),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VisualReportCardHelper {
  static Future<void> showPreview(
    BuildContext context, {
    required StudentModel student,
    required String groupName,
    String? groupGrade,
    required int attendancePercent,
    required int presentCount,
    required int totalSessions,
    required double averageScorePercent,
    required List<Map<String, dynamic>> examScores,
    String? teacherNote,
    required String centerName,
    required String teacherName,
    String? rankText,
    String? reportTitle,
    String? sessionDate,
    String? attendanceStatusLabel,
    String? homeworkStatusLabel,
    String? recitationRatingLabel,
    String? lessonTitle,
    String? previousHomeworkReview,
    String? homeworkText,
    String? nextTopic,
    String? nextQuiz,
    String? subAttendanceNote,
    required DatabaseService database,
  }) {
    return VisualReportCardModalSheet.show(
      context,
      student: student,
      groupName: groupName,
      groupGrade: groupGrade,
      attendancePercent: attendancePercent,
      presentCount: presentCount,
      totalSessions: totalSessions,
      averageScorePercent: averageScorePercent,
      examScores: examScores,
      teacherNote: teacherNote,
      centerName: centerName,
      teacherName: teacherName,
      rankText: rankText,
      reportTitle: reportTitle,
      sessionDate: sessionDate,
      attendanceStatusLabel: attendanceStatusLabel,
      homeworkStatusLabel: homeworkStatusLabel,
      recitationRatingLabel: recitationRatingLabel,
      lessonTitle: lessonTitle,
      previousHomeworkReview: previousHomeworkReview,
      homeworkText: homeworkText,
      nextTopic: nextTopic,
      nextQuiz: nextQuiz,
      subAttendanceNote: subAttendanceNote,
      database: database,
    );
  }
}
