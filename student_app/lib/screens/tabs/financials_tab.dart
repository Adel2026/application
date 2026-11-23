import 'package:flutter/material.dart';
import '../../services/student_auth_service.dart';
import '../../services/student_data_service.dart';
import '../../theme/app_theme.dart';

class FinancialsTab extends StatelessWidget {
  const FinancialsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';

    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: StudentDataService.instance.streamStudentFinancials(studentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)));
          }

          final claims = snapshot.data ?? [];
          if (claims.isEmpty) {
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
                    child: const Icon(Icons.account_balance_wallet_outlined, size: 34, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'لا توجد مطالبات مالية مسجلة',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textLight),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'حسابك خالص ومحدث بالكامل مع المعلم.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            );
          }

          double totalRequired = 0;
          double totalPaid = 0;
          for (final c in claims) {
            totalRequired += (c['required_amount'] as num? ?? 0).toDouble();
            totalPaid += (c['paid_amount'] as num? ?? 0).toDouble();
          }
          final remaining = (totalRequired - totalPaid).clamp(0, double.infinity);

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            children: [
              // Summary Banner
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: remaining == 0
                        ? [const Color(0xFF064E3B), const Color(0xFF065F46)]
                        : [const Color(0xFF451A03), const Color(0xFF78350F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: remaining == 0 ? AppTheme.success : AppTheme.warning,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      remaining == 0 ? 'الحساب خالص ومسدد بالكامل ✅' : 'إجمالي المتبقي سداده ⚠️',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${remaining.toStringAsFixed(0)} ج.م',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 28,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'تم سداد: ${totalPaid.toStringAsFixed(0)} ج.م',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFFE2E8F0)),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'المطلوب كلياً: ${totalRequired.toStringAsFixed(0)} ج.م',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFFE2E8F0)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'تفاصيل الشهور والاشتراكات',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.textLight),
              ),
              const SizedBox(height: 10),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: claims.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final claim = claims[index];
                  final sessionDate = (claim['session_date'] ?? claim['date'] ?? '').toString();
                  final groupName = (claim['group_name'] ?? '').toString();
                  final title = sessionDate.isNotEmpty 
                      ? 'مطالبة حصة: $sessionDate' 
                      : (groupName.isNotEmpty ? 'اشتراك: $groupName' : 'مطالبة دراسية');
                  final req = (claim['required_amount'] as num? ?? claim['amount'] as num? ?? 0).toDouble();
                  final paid = (claim['paid_amount'] as num? ?? 0).toDouble();
                  final isPaid = (claim['is_paid'] ?? 0) == 1 || (paid >= req && req > 0);
                  final rem = (req - paid).clamp(0, double.infinity);

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.darkCardBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppTheme.textLight,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'المطلوب: ${req.toStringAsFixed(0)} ج.م | المسدد: ${paid.toStringAsFixed(0)} ج.م',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? AppTheme.success.withValues(alpha: 0.15)
                                : AppTheme.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isPaid ? AppTheme.success.withValues(alpha: 0.4) : AppTheme.warning.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            isPaid ? 'خالص ✅' : 'متبقي ${rem.toStringAsFixed(0)} ج.م',
                            style: TextStyle(
                              color: isPaid ? AppTheme.success : AppTheme.warning,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
