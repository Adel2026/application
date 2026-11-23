import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/student_auth_service.dart';
import '../services/student_data_service.dart';
import '../theme/app_theme.dart';

enum ReportPeriod {
  thisMonth('هذا الشهر (نوفمبر) 📅'),
  lastMonth('الشهر الماضي (أكتوبر) ⏪'),
  allTime('التقرير التراكمي الشامل 🌟');

  final String label;
  const ReportPeriod(this.label);
}

enum ReportThemeColor {
  cyan(
    'سماوي نيون ⚡',
    Color(0xFF00F2FE),
    Color(0xFF0284C7),
    Color(0xFF0B132B),
    Color(0xFF060B19),
  ),
  gold(
    'ذهبي ملكي 👑',
    Color(0xFFFBBF24),
    Color(0xFFD97706),
    Color(0xFF1C1917),
    Color(0xFF0C0A09),
  ),
  emerald(
    'زمردي أخضر 🌿',
    Color(0xFF34D399),
    Color(0xFF059669),
    Color(0xFF062817),
    Color(0xFF03140B),
  ),
  purple(
    'بنفسجي فاخر 💜',
    Color(0xFFA855F7),
    Color(0xFF7C3AED),
    Color(0xFF1E1035),
    Color(0xFF0F071D),
  );

  final String label;
  final Color primary;
  final Color secondary;
  final Color cardBg;
  final Color darkBg;

  const ReportThemeColor(
    this.label,
    this.primary,
    this.secondary,
    this.cardBg,
    this.darkBg,
  );
}

class StudentReportScreen extends StatefulWidget {
  const StudentReportScreen({super.key});

  @override
  State<StudentReportScreen> createState() => _StudentReportScreenState();
}

class _StudentReportScreenState extends State<StudentReportScreen> {
  final GlobalKey _reportCardKey = GlobalKey();
  ReportPeriod _selectedPeriod = ReportPeriod.thisMonth;
  ReportThemeColor _selectedTheme = ReportThemeColor.cyan;
  bool _isExporting = false;

  /// فحص هل التاريخ ينتمي للفترة المحددة
  bool _isDateInPeriod(String dateStr, ReportPeriod period) {
    if (dateStr.isEmpty) return true;
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return true;

    final now = DateTime.now();
    switch (period) {
      case ReportPeriod.thisMonth:
        return dt.year == now.year && dt.month == now.month;
      case ReportPeriod.lastMonth:
        final lastMonth = now.month == 1 ? 12 : now.month - 1;
        final lastYear = now.month == 1 ? now.year - 1 : now.year;
        return dt.year == lastYear && dt.month == lastMonth;
      case ReportPeriod.allTime:
        return true;
    }
  }

  /// التقاط كارت التقرير كصورة عالية الدقة PNG
  Future<File?> _captureReportCardPng() async {
    try {
      final boundary = _reportCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final student = StudentAuthService.instance.currentStudent;
      final code = student?['student_code'] ?? 'student';
      final file = File('${tempDir.path}/report_card_${code}_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);
      return file;
    } catch (e) {
      debugPrint('Error capturing report card: $e');
      return null;
    }
  }

  /// حفظ التقرير في الموبايل
  Future<void> _saveReportToDevice() async {
    setState(() => _isExporting = true);
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);

    try {
      final file = await _captureReportCardPng();
      if (file != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF00F2FE), width: 1.5),
            ),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF00F2FE)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'تم حفظ كارت التقرير بجودة فائقة جاهز للطباعة والمشاركة 📥',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// مشاركة التقرير المصور عبر الواتساب أو التطبيقات
  Future<void> _shareReportViaWhatsApp() async {
    setState(() => _isExporting = true);
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);

    try {
      final file = await _captureReportCardPng();
      if (file != null) {
        final student = StudentAuthService.instance.currentStudent;
        final name = student?['full_name'] ?? 'الطالب';
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: '📊 تقرير المتابعة الأكاديمي للطالب: $name\nمنصة Edu Academy الذكية 🎓',
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sharing report card: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    final groupId = student?['group_id'];

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: const Text('تقرير المتابعة الشامل 📑'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'مشاركة بالواتساب',
            icon: const Icon(Icons.share_rounded, color: Color(0xFF00F2FE)),
            onPressed: _isExporting ? null : _shareReportViaWhatsApp,
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: StudentDataService.instance.streamStudent(studentId),
        builder: (context, studentSnap) {
          final sData = studentSnap.data?.data() ?? student ?? {};
          final studentName = sData['full_name'] ?? 'الطالب';
          final rawCode = (sData['student_code'] ?? sData['id'] ?? studentId).toString().trim();
          final studentCode = rawCode.replaceAll(RegExp(r'\D'), '');
          final grade = (sData['grade'] != null && sData['grade'].toString().isNotEmpty)
              ? sData['grade'].toString()
              : 'المرحلة الدراسية';

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: StudentDataService.instance.streamGroup(groupId),
            builder: (context, groupSnap) {
              final groupData = groupSnap.data?.data() ?? {};
              final groupName = groupData['name'] ?? 'المجموعة الدراسية';

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: StudentDataService.instance.streamStudentAttendance(studentId),
                builder: (context, attSnap) {
                  final allAttendances = attSnap.data ?? [];
                  final filteredAttendances = allAttendances.where((a) {
                    final d = (a['attendance_date'] ?? a['session_date'] ?? '').toString();
                    return _isDateInPeriod(d, _selectedPeriod);
                  }).toList();

                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: StudentDataService.instance.streamStudentExams(studentId),
                    builder: (context, examSnap) {
                      final allExams = examSnap.data ?? [];
                      final filteredExams = allExams.where((e) {
                        final d = (e['exam_date'] ?? '').toString();
                        return _isDateInPeriod(d, _selectedPeriod);
                      }).toList();

                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream: StudentDataService.instance.streamStudentFinancials(studentId),
                        builder: (context, finSnap) {
                          final allFins = finSnap.data ?? [];
                          final filteredFins = allFins.where((f) {
                            final d = (f['session_date'] ?? '').toString();
                            return _isDateInPeriod(d, _selectedPeriod);
                          }).toList();

                          return _buildMainContent(
                            studentName: studentName,
                            studentCode: studentCode.isNotEmpty ? studentCode : rawCode,
                            grade: grade,
                            groupName: groupName,
                            attendances: filteredAttendances,
                            exams: filteredExams,
                            financials: filteredFins,
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMainContent({
    required String studentName,
    required String studentCode,
    required String grade,
    required String groupName,
    required List<Map<String, dynamic>> attendances,
    required List<Map<String, dynamic>> exams,
    required List<Map<String, dynamic>> financials,
  }) {
    // 1. حساب الحضور والغياب
    final totalSessions = attendances.length;
    final presentCount = attendances.where((a) => a['status'] == 'present').length;
    final lateCount = attendances.where((a) => a['status'] == 'late').length;
    final absentCount = attendances.where((a) => a['status'] == 'absent').length;
    final int attendancePercent = totalSessions == 0
        ? 100
        : (((presentCount + (lateCount * 0.5)) / totalSessions) * 100).toInt().clamp(0, 100);

    // 2. حساب الواجبات
    final hwDoneCount = attendances.where((a) => a['homework_status'] == 'done').length;
    final hwExcusedCount = attendances.where((a) => a['homework_status'] == 'excused').length;
    final int homeworkPercent = totalSessions == 0
        ? 100
        : (((hwDoneCount + (hwExcusedCount * 0.8)) / totalSessions) * 100).toInt().clamp(0, 100);

    // 3. حساب الاختبارات
    double totalEarned = 0;
    double totalMax = 0;
    for (final e in exams) {
      final score = (e['score'] as num? ?? 0).toDouble();
      final max = (e['max_score'] as num? ?? 100).toDouble();
      totalEarned += score;
      totalMax += (max > 0 ? max : 100);
    }
    final double averageExamPercent =
        totalMax == 0 ? 0 : ((totalEarned / totalMax) * 100).clamp(0, 100);

    // 4. التقدير العام ومعدل التميز
    String gradeLetter;
    Color gradeColor;
    if (averageExamPercent >= 95) {
      gradeLetter = 'ممتاز مرتفع 🌟 (A+)';
      gradeColor = const Color(0xFF10B981);
    } else if (averageExamPercent >= 90) {
      gradeLetter = 'ممتاز 🎯 (A)';
      gradeColor = const Color(0xFF00F2FE);
    } else if (averageExamPercent >= 80) {
      gradeLetter = 'جيد جداً 👍 (B+)';
      gradeColor = const Color(0xFF38BDF8);
    } else if (averageExamPercent >= 70) {
      gradeLetter = 'جيد 📚 (B)';
      gradeColor = const Color(0xFFFBBF24);
    } else if (averageExamPercent >= 60) {
      gradeLetter = 'مقبول ⚠️ (C)';
      gradeColor = const Color(0xFFF59E0B);
    } else {
      gradeLetter = 'يحتاج اجتهاداً ومتابعة ⚠️';
      gradeColor = const Color(0xFFF43F5E);
    }

    // 5. الموقف المالي
    double totalClaimAmount = 0;
    double totalPaidAmount = 0;
    for (final f in financials) {
      final claim = (f['amount'] as num? ?? 0).toDouble();
      final paid = (f['paid_amount'] as num? ?? (f['is_paid'] == true ? claim : 0)).toDouble();
      totalClaimAmount += claim;
      totalPaidAmount += paid;
    }
    final remainingDebt = (totalClaimAmount - totalPaidAmount).clamp(0, 999999).toDouble();
    final bool isFinanciallyCleared = remainingDebt <= 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A. فلتر اختيار الفترة الزمنية
          _buildPeriodSelector(),
          const SizedBox(height: 16),

          // B. ثيمات الألوان النيون لكارت التقرير
          _buildThemeSelector(),
          const SizedBox(height: 20),

          // C. كارت التقرير المصور الفخم (قابلة للتحميل والمشاركة)
          RepaintBoundary(
            key: _reportCardKey,
            child: _buildVisualReportCardWidget(
              studentName: studentName,
              studentCode: studentCode,
              grade: grade,
              groupName: groupName,
              attendancePercent: attendancePercent,
              presentCount: presentCount,
              totalSessions: totalSessions,
              absentCount: absentCount,
              homeworkPercent: homeworkPercent,
              hwDoneCount: hwDoneCount,
              averageExamPercent: averageExamPercent,
              gradeLetter: gradeLetter,
              gradeColor: gradeColor,
              exams: exams,
              isFinanciallyCleared: isFinanciallyCleared,
              remainingDebt: remainingDebt,
            ),
          ),
          const SizedBox(height: 20),

          // D. أزرار الحفظ والمشاركة الكبرى
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: const Color(0xFF00F2FE),
                    side: const BorderSide(color: Color(0xFF00F2FE), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  icon: _isExporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F2FE)),
                        )
                      : const Icon(Icons.download_rounded),
                  label: const Text('حفظ كصورة PNG 📥', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _isExporting ? null : _saveReportToDevice,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F2FE),
                    foregroundColor: const Color(0xFF04101E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('مشاركة بالواتساب 📲', style: TextStyle(fontWeight: FontWeight.w900)),
                  onPressed: _isExporting ? null : _shareReportViaWhatsApp,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // E. عدادات الأداء النيون الأربعة (Interactive KPIs)
          _buildKpiGrid(
            attendancePercent: attendancePercent,
            homeworkPercent: homeworkPercent,
            averageExamPercent: averageExamPercent,
            isFinanciallyCleared: isFinanciallyCleared,
            remainingDebt: remainingDebt,
          ),
          const SizedBox(height: 24),

          // F. توصيات المعلم وتوجيهات التفوق
          _buildTeacherRecommendations(
            attendancePercent: attendancePercent,
            averageExamPercent: averageExamPercent,
            homeworkPercent: homeworkPercent,
            studentName: studentName,
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkCardBorder),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: ReportPeriod.values.map((p) {
          final isSelected = _selectedPeriod == p;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedPeriod = p);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF00F2FE).withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: const Color(0xFF00F2FE), width: 1.2)
                      : null,
                ),
                child: Text(
                  p.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    color: isSelected ? const Color(0xFF00F2FE) : AppTheme.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildThemeSelector() {
    return Row(
      children: [
        const Text(
          'ألوان الكارت:',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ReportThemeColor.values.map((t) {
                final isSelected = _selectedTheme == t;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedTheme = t);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? t.primary.withValues(alpha: 0.2) : AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? t.primary : AppTheme.darkCardBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(radius: 5, backgroundColor: t.primary),
                        const SizedBox(width: 6),
                        Text(
                          t.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.normal,
                            color: isSelected ? t.primary : AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  /// ويدجت كارت التقرير المصور الفخم
  Widget _buildVisualReportCardWidget({
    required String studentName,
    required String studentCode,
    required String grade,
    required String groupName,
    required int attendancePercent,
    required int presentCount,
    required int totalSessions,
    required int absentCount,
    required int homeworkPercent,
    required int hwDoneCount,
    required double averageExamPercent,
    required String gradeLetter,
    required Color gradeColor,
    required List<Map<String, dynamic>> exams,
    required bool isFinanciallyCleared,
    required double remainingDebt,
  }) {
    final theme = _selectedTheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.darkBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.primary.withValues(alpha: 0.6), width: 2),
        boxShadow: [
          BoxShadow(
            color: theme.primary.withValues(alpha: 0.25),
            blurRadius: 25,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. رأس الكارت مع الشعار
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.primary.withValues(alpha: 0.25),
                  theme.secondary.withValues(alpha: 0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: theme.primary.withValues(alpha: 0.4), blurRadius: 10),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Edu Academy • المنصة التعليمية الذكية',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'كارت تقرير المتابعة الأكاديمي 🎓',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: theme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.primary, width: 1.2),
                  ),
                  child: Text(
                    _selectedPeriod.label.split(' ')[0],
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: theme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 2. بطاقة هوية الطالب
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.primary.withValues(alpha: 0.2),
                        child: Text(
                          studentName.isNotEmpty ? studentName.substring(0, 1) : 'ط',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.primary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              studentName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$grade • $groupName',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.primary.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          children: [
                            const Text('كود الطالب', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                            Text(
                              studentCode,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: theme.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. المؤشرات الرقمية الأربعة
                Row(
                  children: [
                    _buildReportMetric(
                      title: 'نسبة الحضور',
                      value: '$attendancePercent%',
                      subtitle: '$presentCount من $totalSessions حصة',
                      color: const Color(0xFF10B981),
                      theme: theme,
                    ),
                    const SizedBox(width: 10),
                    _buildReportMetric(
                      title: 'إنجاز الواجبات',
                      value: '$homeworkPercent%',
                      subtitle: '$hwDoneCount واجب تم إتقانه',
                      color: const Color(0xFF00F2FE),
                      theme: theme,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildReportMetric(
                      title: 'معدل الامتحانات',
                      value: '${averageExamPercent.toStringAsFixed(1)}%',
                      subtitle: gradeLetter,
                      color: const Color(0xFFA855F7),
                      theme: theme,
                    ),
                    const SizedBox(width: 10),
                    _buildReportMetric(
                      title: 'الموقف المالي',
                      value: isFinanciallyCleared ? 'خالص السداد ✅' : '$remainingDebt ج.م',
                      subtitle: isFinanciallyCleared ? 'اشتراكات مسددة' : 'متأخرات مستحقة',
                      color: isFinanciallyCleared ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      theme: theme,
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 4. جدول كشف درجات الاختبارات في الفترة
                if (exams.isNotEmpty) ...[
                  Text(
                    'كشف نتائج الاختبارات والتقييمات:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: theme.primary),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      children: exams.take(3).map((e) {
                        final title = e['exam_title'] ?? 'اختبار';
                        final score = e['score'] ?? 0;
                        final max = e['max_score'] ?? 100;
                        final d = e['exam_date'] ?? '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    if (d.toString().isNotEmpty)
                                      Text(d, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$score / $max',
                                  style: TextStyle(fontWeight: FontWeight.w900, color: theme.primary, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // 5. التوقيع والاعتماد الرسمي
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('تاريخ الإصدار', style: TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                        Text(
                          DateTime.now().toIso8601String().substring(0, 10),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.primary.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified_rounded, size: 16, color: theme.primary),
                          const SizedBox(width: 6),
                          const Text(
                            'معتمد من المعلم الأكاديمي 👨‍🏫',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportMetric({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required ReportThemeColor theme,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 9.5, color: Colors.grey.shade400),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiGrid({
    required int attendancePercent,
    required int homeworkPercent,
    required double averageExamPercent,
    required bool isFinanciallyCleared,
    required double remainingDebt,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'مؤشرات الأداء التفاعلية الحية 📊',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildKpiCard(
              title: 'الالتزام بالحضور',
              percentage: attendancePercent,
              color: const Color(0xFF10B981),
              icon: Icons.calendar_today_rounded,
              statusText: attendancePercent >= 85 ? 'ملتزم ممتاز' : 'مطلوب تحسين الحضور',
            ),
            const SizedBox(width: 12),
            _buildKpiCard(
              title: 'معدل الاختبارات',
              percentage: averageExamPercent.toInt(),
              color: const Color(0xFFA855F7),
              icon: Icons.assignment_rounded,
              statusText: averageExamPercent >= 85 ? 'أداء متفوق' : 'مطلوب مراجعة دورية',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildKpiCard(
              title: 'حل الواجبات',
              percentage: homeworkPercent,
              color: const Color(0xFF00F2FE),
              icon: Icons.menu_book_rounded,
              statusText: homeworkPercent >= 85 ? 'حل منتظم' : 'تنبيه واجبات متأخرة',
            ),
            const SizedBox(width: 12),
            _buildKpiCard(
              title: 'الانتظام المالي',
              percentage: isFinanciallyCleared ? 100 : 50,
              color: isFinanciallyCleared ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              icon: Icons.account_balance_wallet_rounded,
              statusText: isFinanciallyCleared ? 'خالص السداد ✅' : 'متبقي: $remainingDebt ج.م',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required int percentage,
    required Color color,
    required IconData icon,
    required String statusText,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 20, color: color),
                Text(
                  '$percentage%',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Text(statusText, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (percentage / 100).clamp(0.0, 1.0),
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherRecommendations({
    required int attendancePercent,
    required double averageExamPercent,
    required int homeworkPercent,
    required String studentName,
  }) {
    String message;
    IconData icon;
    Color accentColor;

    if (averageExamPercent >= 90 && attendancePercent >= 90) {
      message = 'طالب ممتاز ومن الأوائل 🏆! ما شاء الله استمر على هذا الأداء العالي والالتزام الكامل للحفاظ على صدارة الترتيب.';
      icon = Icons.emoji_events_rounded;
      accentColor = const Color(0xFFFBBF24);
    } else if (attendancePercent < 80) {
      message = 'يرجى الحرص على حضور جميع الحصص القادمة دون غياب؛ الغياب يؤثر مباشرة على استيعاب المنهج وحل الواجبات.';
      icon = Icons.warning_rounded;
      accentColor = const Color(0xFFF43F5E);
    } else if (homeworkPercent < 75) {
      message = 'مطلوب الاهتمام بحل كافة واجبات الحصة القادمة بدقة وتسليمها في بداية كل درس لرفع التقييم الأكاديمي 📝.';
      icon = Icons.assignment_late_rounded;
      accentColor = const Color(0xFFF59E0B);
    } else {
      message = 'مستوى أكاديمي جيد مع إمكانية تحسين الدرجات من خلال المراجعة المستمرة وحل التمارين الإضافية بانتظام 👍.';
      icon = Icons.trending_up_rounded;
      accentColor = const Color(0xFF00F2FE);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'توصيات المعلم الأكاديمي 👨‍🏫',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: accentColor),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFCBD5E1), height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
