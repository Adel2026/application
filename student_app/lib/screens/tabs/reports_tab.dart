import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/student_auth_service.dart';
import '../../services/student_data_service.dart';
import '../../theme/app_theme.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  // التاريخ أو الشهر المحدد للعرض (null يعني آخر تقرير معتمد تلقائياً)
  String? _selectedHistoricalMonth;

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    final groupId = student?['group_id'];

    return Scaffold(
      backgroundColor: const Color(0xFF060911),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: StudentDataService.instance.streamStudentFullReport(
          studentId: studentId,
          groupId: groupId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)));
          }

          final data = snapshot.data ?? {};
          final sData = (data['student'] as Map<String, dynamic>?) ?? student ?? {};
          final studentName = sData['full_name'] ?? 'الطالب';
          final rawCode = (sData['student_code'] ?? sData['id'] ?? studentId).toString().trim();
          final studentCode = rawCode.replaceAll(RegExp(r'\D'), '');
          final grade = (sData['grade'] != null && sData['grade'].toString().isNotEmpty)
              ? sData['grade'].toString()
              : 'المرحلة الدراسية';

          final groupData = (data['group'] as Map<String, dynamic>?) ?? {};
          final groupName = groupData['name'] ?? 'المجموعة الدراسية';

          final allAttendances = (data['attendances'] as List<Map<String, dynamic>>?) ?? [];
          final allExams = (data['exams'] as List<Map<String, dynamic>>?) ?? [];
          final allFins = (data['financials'] as List<Map<String, dynamic>>?) ?? [];

          // تجميع الشهور المتاحة لإنشاء أرشيف التقارير السابقة
          final availableMonths = _extractAvailableMonths(
            attendances: allAttendances,
            exams: allExams,
            financials: allFins,
          );

          // تحديد الشهر المعروض: إما المختار من الأرشيف، أو آخر شهر تلقائياً
          final currentActiveMonth = _selectedHistoricalMonth ??
              (availableMonths.isNotEmpty ? availableMonths.first : _currentMonthKey());

          final isViewingHistorical = _selectedHistoricalMonth != null &&
              availableMonths.isNotEmpty &&
              _selectedHistoricalMonth != availableMonths.first;

          // تصفية السجلات للشهر المعروض
          final filteredAttendances = allAttendances.where((a) {
            final d = (a['attendance_date'] ?? a['session_date'] ?? '').toString();
            return _matchesMonth(d, currentActiveMonth);
          }).toList();

          final filteredExams = allExams.where((e) {
            final d = (e['exam_date'] ?? '').toString();
            return _matchesMonth(d, currentActiveMonth);
          }).toList();

          final filteredFins = allFins.where((f) {
            final d = (f['session_date'] ?? '').toString();
            return _matchesMonth(d, currentActiveMonth);
          }).toList();

          return _buildDistinctReportView(
            studentName: studentName,
            studentCode: studentCode.isNotEmpty ? studentCode : rawCode,
            grade: grade,
            groupName: groupName,
            monthKey: currentActiveMonth,
            isViewingHistorical: isViewingHistorical,
            availableMonths: availableMonths,
            attendances: filteredAttendances,
            exams: filteredExams,
            financials: filteredFins,
          );
        },
      ),
    );
  }

  // =========================================================================
  // بناء التقرير الأكاديمي المعتمد بالستايل الجديد الحصري
  // =========================================================================
  Widget _buildDistinctReportView({
    required String studentName,
    required String studentCode,
    required String grade,
    required String groupName,
    required String monthKey,
    required bool isViewingHistorical,
    required List<String> availableMonths,
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

    // 2. حساب الواجبات والتطبيقات
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

    // 4. الموقف المالي
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

    // 5. التقييم الشامل التراكمي
    final double overallScore = exams.isEmpty
        ? ((attendancePercent * 0.6) + (homeworkPercent * 0.4)).clamp(0, 100)
        : ((attendancePercent * 0.3) + (homeworkPercent * 0.3) + (averageExamPercent * 0.4)).clamp(0, 100);

    String overallRank;
    Color overallColor;
    if (overallScore >= 90) {
      overallRank = 'طالب متميز فائق 🌟 (امتياز)';
      overallColor = const Color(0xFF00F2FE);
    } else if (overallScore >= 80) {
      overallRank = 'طالب مجتهد جداً 🎯 (جيد جداً مرتفع)';
      overallColor = const Color(0xFF10B981);
    } else if (overallScore >= 70) {
      overallRank = 'مستوى جيد 📚 (جيد)';
      overallColor = const Color(0xFFFBBF24);
    } else {
      overallRank = 'يحتاج إلى مزيد من المتابعة ⚠️';
      overallColor = const Color(0xFFF43F5E);
    }

    final formattedMonthLabel = _formatMonthLabel(monthKey);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // أ. شريط تنبيه إذا كان الطالب يستعرض تقريراً سابقاً من الأرشيف
        if (isViewingHistorical)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, color: Color(0xFFF59E0B), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'أنت تستعرض الآن تقريراً سابقاً: $formattedMonthLabel',
                    style: const TextStyle(
                      color: Color(0xFFFDE68A),
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFF00F2FE),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedHistoricalMonth = null);
                  },
                  child: const Text('العودة لآخر تقرير ⚡', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

        // ب. بطاقة التقرير الأكاديمي الحصري (New Distinct Executive Style)
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00F2FE).withValues(alpha: 0.08),
                blurRadius: 28,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. ترويسة التقرير الرسمية مع الختم الأكاديمي
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                        border: Border.all(color: const Color(0xFF00F2FE), width: 1.5),
                      ),
                      child: const Center(
                        child: Icon(Icons.verified_rounded, color: Color(0xFF00F2FE), size: 26),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isViewingHistorical ? 'تقرير أرشيفي سابق' : 'آخر تقرير أكاديمي معتمد',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF00F2FE),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                                ),
                                child: const Text(
                                  'معتمد 🛡️',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'الفترة: $formattedMonthLabel • صادر عن الأكاديمية التعليمية',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(color: Color(0xFF1E293B), height: 1, thickness: 1),

              // 2. بطاقة بيانات الطالب والتقييم العام
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF1E293B),
                            border: Border.all(color: const Color(0xFF334155), width: 1.2),
                          ),
                          child: const Center(
                            child: Text('🎓', style: TextStyle(fontSize: 24)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                studentName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.textLight,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$grade • $groupName',
                                style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00F2FE).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            children: [
                              const Text('كود الطالب', style: TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8))),
                              Text(
                                studentCode,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF00F2FE),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // مؤشر التقييم العام
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: overallColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: overallColor.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.workspace_premium_rounded, color: overallColor, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('التقييم الأكاديمي العام:', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                Text(
                                  overallRank,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: overallColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '%${overallScore.toInt()}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: overallColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(color: Color(0xFF1E293B), height: 1, thickness: 1),

              // 3. شبكة المحاور الأكاديمية الأربعة بالتفصيل
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    // المحور 1: الحضور والانتظام
                    _buildMetricRow(
                      icon: Icons.calendar_today_rounded,
                      iconColor: const Color(0xFF10B981),
                      title: 'الالتزام بالحضور والانتظام',
                      value: '%$attendancePercent',
                      statusBadge: attendancePercent >= 85 ? 'ملتزم تماماً ✅' : 'يحتاج انضباطاً ⚠️',
                      badgeColor: attendancePercent >= 85 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      subtitle: totalSessions == 0
                          ? 'لا توجد حصص مسجلة في هذه الفترة'
                          : 'حضر $presentCount من أصل $totalSessions حصة مقررة ($absentCount غياب)',
                      progress: attendancePercent / 100,
                    ),

                    const SizedBox(height: 14),

                    // المحور 2: إنجاز الواجبات والتطبيقات
                    _buildMetricRow(
                      icon: Icons.edit_note_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      title: 'إنجاز الواجبات والتطبيقات',
                      value: '%$homeworkPercent',
                      statusBadge: homeworkPercent >= 80 ? 'إنجاز ممتاز ✍️' : 'متابعة مطلوبة ⚠️',
                      badgeColor: homeworkPercent >= 80 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      subtitle: totalSessions == 0
                          ? 'لم تسجل واجبات بعد'
                          : 'تم إتقان وتسليم $hwDoneCount واجب من أصل $totalSessions',
                      progress: homeworkPercent / 100,
                    ),

                    const SizedBox(height: 14),

                    // المحور 3: الامتحانات والتقييمات
                    _buildMetricRow(
                      icon: Icons.analytics_rounded,
                      iconColor: const Color(0xFFA855F7),
                      title: 'معدل درجات الامتحانات',
                      value: exams.isEmpty ? '--' : '%${averageExamPercent.toStringAsFixed(1)}',
                      statusBadge: exams.isEmpty ? 'في الانتظار ⏳' : (averageExamPercent >= 80 ? 'تفوق 🌟' : 'يحتاج تركيزاً ⚠️'),
                      badgeColor: exams.isEmpty ? const Color(0xFF64748B) : (averageExamPercent >= 80 ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                      subtitle: exams.isEmpty
                          ? 'لم تجر اختبارات شهرية بعد في هذه الفترة'
                          : '${exams.length} اختبار تم رصده في هذه الفترة',
                      progress: exams.isEmpty ? 0 : (averageExamPercent / 100),
                    ),

                    const SizedBox(height: 14),

                    // المحور 4: الموقف المالي
                    _buildMetricRow(
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: isFinanciallyCleared ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      title: 'الموقف المالي والاشتراك',
                      value: isFinanciallyCleared ? 'خالص ✅' : '${remainingDebt.toStringAsFixed(0)} ج.م',
                      statusBadge: isFinanciallyCleared ? 'مسدد بالكامل 💳' : 'متبقي سداد ⚠️',
                      badgeColor: isFinanciallyCleared ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      subtitle: isFinanciallyCleared
                          ? 'تم سداد كافة المصروفات والاشتراكات المقررة'
                          : 'يرجى مراجعة إدارة السنتر لتسوية المتأخرات',
                      progress: isFinanciallyCleared ? 1.0 : 0.4,
                    ),
                  ],
                ),
              ),

              const Divider(color: Color(0xFF1E293B), height: 1, thickness: 1),

              // 4. توجيه وملاحظات المعلم الأكاديمية
              Container(
                margin: const EdgeInsets.all(18),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.psychology_rounded, color: Color(0xFF00F2FE), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'توصية وتوجيه المعلم الأكاديمي 👨‍🏫',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00F2FE),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            attendancePercent >= 90
                                ? 'الطالب يظهر التزاماً ممتازاً في الحضور والتركيز. نوصي بالاستمرار في هذا الأداء وحل الواجبات والتطبيقات أولاً بأول لضمان الصدارة في الاختبار القادم.'
                                : 'يرجى من ولي الأمر متابعة انتظام الطالب في الحضور وحل الواجبات المقررة لرفع المستوى وتحقيق النتيجة المرجوة.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFCBD5E1),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 5. تذييل التقرير مع كود الاعتماد
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF090D16),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'تاريخ الاعتماد: ${DateTime.now().toString().split(' ')[0]}',
                      style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                    ),
                    const Text(
                      'منصة Edu Academy الذكية 🎓',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00F2FE),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ج. زر الوصول لأرشيف التقارير السابقة
        _buildPreviousReportsArchiveButton(availableMonths),

        const SizedBox(height: 24),
      ],
    );
  }

  // عنصر محور أكاديمي واحد
  Widget _buildMetricRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String statusBadge,
    required Color badgeColor,
    required String subtitle,
    required double progress,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusBadge,
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: badgeColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFF334155),
              valueColor: AlwaysStoppedAnimation<Color>(iconColor),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // زر وبوتوم شيت أرشيف التقارير السابقة
  // =========================================================================
  Widget _buildPreviousReportsArchiveButton(List<String> availableMonths) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.lightImpact();
            _openPreviousReportsSheet(availableMonths);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.inventory_2_rounded, color: Color(0xFF00F2FE), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'أرشيف التقارير السابقة 📂',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textLight,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        availableMonths.length > 1
                            ? 'اضغط هنا للاطلاع على تقارير الشهور السابقة'
                            : 'لا توجد تقارير سابقة مسجلة حتى الآن',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPreviousReportsSheet(List<String> availableMonths) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Icon(Icons.folder_shared_rounded, color: Color(0xFF00F2FE), size: 22),
                SizedBox(width: 10),
                Text(
                  'أرشيف تقارير المتابعة السابقة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textLight,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'اختر الشهر للاطلاع على سجل وأداء الطالب في تلك الفترة:',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 14),
            if (availableMonths.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'لا توجد تقارير في الأرشيف حتى الآن.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: availableMonths.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final mKey = availableMonths[index];
                  final isLatest = index == 0;
                  final isSelected = (_selectedHistoricalMonth ?? availableMonths.first) == mKey;

                  return Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00F2FE).withValues(alpha: 0.12)
                          : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF00F2FE) : const Color(0xFF334155),
                        width: isSelected ? 1.4 : 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      leading: Icon(
                        isLatest ? Icons.auto_awesome_rounded : Icons.description_rounded,
                        color: isLatest ? const Color(0xFF00F2FE) : const Color(0xFF94A3B8),
                        size: 22,
                      ),
                      title: Text(
                        _formatMonthLabel(mKey),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? const Color(0xFF00F2FE) : AppTheme.textLight,
                        ),
                      ),
                      subtitle: Text(
                        isLatest ? 'آخر تقرير صادر (الحالي) ⚡' : 'تقرير أرشيفي محفوظ 📑',
                        style: TextStyle(
                          fontSize: 11,
                          color: isLatest ? const Color(0xFF38BDF8) : AppTheme.textMuted,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00F2FE), size: 20)
                          : const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: AppTheme.textMuted),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(ctx);
                        setState(() {
                          _selectedHistoricalMonth = isLatest ? null : mKey;
                        });
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // دوال مساعدة لاستخراج الشهور والتواريخ
  // =========================================================================
  List<String> _extractAvailableMonths({
    required List<Map<String, dynamic>> attendances,
    required List<Map<String, dynamic>> exams,
    required List<Map<String, dynamic>> financials,
  }) {
    final set = <String>{};
    for (final a in attendances) {
      final d = (a['attendance_date'] ?? a['session_date'] ?? '').toString();
      if (d.length >= 7) set.add(d.substring(0, 7));
    }
    for (final e in exams) {
      final d = (e['exam_date'] ?? '').toString();
      if (d.length >= 7) set.add(d.substring(0, 7));
    }
    for (final f in financials) {
      final d = (f['session_date'] ?? '').toString();
      if (d.length >= 7) set.add(d.substring(0, 7));
    }

    final current = _currentMonthKey();
    set.add(current);

    final list = set.toList();
    list.sort((a, b) => b.compareTo(a)); // الأحدث فالأقدم
    return list;
  }

  String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  bool _matchesMonth(String dateStr, String monthKey) {
    if (dateStr.isEmpty) return false;
    return dateStr.startsWith(monthKey);
  }

  String _formatMonthLabel(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length < 2) return monthKey;
    final year = parts[0];
    final mInt = int.tryParse(parts[1]) ?? 1;

    const monthNames = [
      '',
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];

    final mName = (mInt >= 1 && mInt <= 12) ? monthNames[mInt] : parts[1];
    return 'شهر $mName ($year)';
  }
}
