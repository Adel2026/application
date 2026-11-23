import 'package:flutter/material.dart';
import '../../services/student_auth_service.dart';
import '../../services/student_data_service.dart';
import '../../theme/app_theme.dart';
import '../certificate_celebration_dialog.dart';
import '../certificate_viewer_dialog.dart';

class ExamsTab extends StatelessWidget {
  const ExamsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    final studentFullName = (student?['full_name'] ?? student?['name'] ?? '').toString().trim();
    final studentCode = '${student?['student_code'] ?? studentId}';
    final studentGroup = (student?['group_name'] ?? '').toString().trim();
    final studentGrade = (student?['grade'] ?? '').toString().trim();

    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: StudentDataService.instance.streamStudentExams(studentId, studentCode),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'تنبيه المزامنة: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)));
          }

          final exams = snapshot.data ?? [];
          if (exams.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.darkCardBorder),
                    ),
                    child: const Icon(Icons.assignment_outlined, size: 34, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'لا توجد درجات اختبارات مسجلة بعد',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textLight),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'ستظهر درجات امتحاناتك هنا فور رصدها من قِبل المعلم.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            itemCount: exams.length,
            separatorBuilder: (context, index) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final exam = exams[index];
              final title = exam['exam_title'] ?? 'اختبار تقييمي';
              final score = (exam['score'] as num? ?? 0).toDouble();
              final max = (exam['max_score'] as num? ?? 50).toDouble();
              final date = exam['exam_date'] ?? '';
              final rank = (exam['rank'] as num? ?? 0).toInt();
              final notes = exam['notes'] ?? '';
              final percentage = (exam['percentage'] as num? ?? (max > 0 ? ((score / max) * 100) : 0)).toDouble();
              final hasCert = exam['has_certificate'] == true ||
                  (exam['certificate_image_base64'] != null && exam['certificate_image_base64'].toString().isNotEmpty) ||
                  exam['certificate_issued'] == true ||
                  percentage >= 85.0 ||
                  (rank > 0 && rank <= 3 && percentage >= 60.0);
              final certTitle = exam['certificate_title'] ?? 'شهادة تقدير وتفوق 🎓';

              Color gradeColor = AppTheme.success;
              if (percentage < 60) {
                gradeColor = AppTheme.danger;
              } else if (percentage < 80) {
                gradeColor = AppTheme.warning;
              }

              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: hasCert
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                        : AppTheme.darkCardBorder,
                    width: hasCert ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: hasCert
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // الرأس: عنوان الاختبار وشارة الشهادة المستحقة إذا وجدت
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15.5,
                                    color: AppTheme.textLight,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.event_note_rounded, size: 13, color: AppTheme.textMuted),
                                    const SizedBox(width: 4),
                                    Text(
                                      date,
                                      style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (rank > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    rank == 1 ? Icons.emoji_events_rounded : Icons.military_tech_rounded,
                                    size: 15,
                                    color: const Color(0xFFF59E0B),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'المركز $rank',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFF59E0B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // لوحة نتيجة الاختبار الاحترافية بدقة عالية وتصميم رقمي فاخر
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF090D16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // درجة الاختبار
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                'الدرجة المحققة',
                                style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: score.toStringAsFixed(score.truncateToDouble() == score ? 0 : 1),
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                        color: gradeColor,
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' / ${max.toStringAsFixed(max.truncateToDouble() == max ? 0 : 1)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Container(width: 1, height: 32, color: const Color(0xFF1E293B)),
                          // النسبة المئوية
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                'النسبة المئوية',
                                style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '%${percentage.toStringAsFixed(1)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF00F2FE),
                                ),
                              ),
                            ],
                          ),
                          Container(width: 1, height: 32, color: const Color(0xFF1E293B)),
                          // التقييم اللفظي
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                'المستوى',
                                style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                percentage >= 90
                                    ? 'ممتاز 🌟'
                                    : (percentage >= 80
                                        ? 'جيد جداً ✨'
                                        : (percentage >= 65 ? 'جيد 👍' : 'يحتاج دعم ⚠️')),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: gradeColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // قسم شهادة التقدير الرسمية إذا كان الطالب مستحقاً
                    if (hasCert) ...[
                      Builder(
                        builder: (ctx) {
                          final realStudentName = (exam['student_name'] ?? studentFullName).toString().trim();
                          final effectiveStudentName = realStudentName.isNotEmpty ? realStudentName : 'الطالب المتفوق';
                          final realGroupName = (exam['group_name'] ?? studentGroup).toString().trim();
                          final realGrade = (exam['grade'] ?? studentGrade).toString().trim();
                          final realCode = '${exam['student_code'] ?? studentCode}';

                          return Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.6), width: 1.2),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD700), size: 22),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              certTitle,
                                              style: const TextStyle(
                                                color: Color(0xFFFFD700),
                                                fontWeight: FontWeight.w900,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                            const Text(
                                              'شهادة تقدير وتفوق معتمدة من معلم المادة 🌟',
                                              style: TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF10B981),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 9),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          icon: const Icon(Icons.image_rounded, size: 16),
                                          label: const Text(
                                            'صورة الشهادة الأصلية 📜',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                          onPressed: () {
                                            CertificateViewerDialog.show(
                                              context: context,
                                              exam: exam,
                                              studentName: effectiveStudentName,
                                              studentCode: realCode,
                                              groupName: realGroupName,
                                              grade: realGrade,
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Color(0xFFF59E0B)),
                                            foregroundColor: const Color(0xFFF59E0B),
                                            padding: const EdgeInsets.symmetric(vertical: 9),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          icon: const Icon(Icons.celebration_rounded, size: 16),
                                          label: const Text(
                                            'الاحتفال ✦',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                          onPressed: () {
                                            CertificateCelebrationDialog.show(
                                              context: context,
                                              exam: exam,
                                              studentName: effectiveStudentName,
                                              code: realCode,
                                              groupName: realGroupName,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],

                    if (notes.toString().isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.darkCardBorder),
                          ),
                          child: Text(
                            'ملاحظة المعلم: $notes',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
