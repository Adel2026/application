import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/student_auth_service.dart';
import '../services/student_data_service.dart';

class StudentRewardsScreen extends StatefulWidget {
  const StudentRewardsScreen({super.key});

  @override
  State<StudentRewardsScreen> createState() => _StudentRewardsScreenState();
}

class _StudentRewardsScreenState extends State<StudentRewardsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showVoucherDialog(String voucherCode, String rewardTitle) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFFFD700), width: 1.5),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFFD700)]),
              ),
              child: const Icon(Icons.card_giftcard_rounded, color: Colors.black, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'مبروك! تم استخراج قسيمتك 🎁',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              rewardTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  const Text('كود القسيمة للاستلام من المعلم:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Text(
                    voucherCode,
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'أظهر هذا الكود للمعلم في السنتر لاعتماد الجائزة فوراً! 🌟',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
          ],
        ),
        actions: [
          Center(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تم وحفظ القسيمة', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    final studentName = student?['name'] ?? student?['full_name'] ?? 'الطالب';
    final groupId = student?['group_id'];
    final isParent = StudentAuthService.instance.isParent;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('متجر المكافآت ولوحة الشرف 🏆', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFD700),
          labelColor: const Color(0xFFFFD700),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.storefront_rounded), text: 'متجر الجوائز'),
            Tab(icon: Icon(Icons.leaderboard_rounded), text: 'لوحة الشرف (Top 10)'),
          ],
        ),
      ),
      body: StreamBuilder(
        stream: StudentDataService.instance.streamStudent(studentId),
        builder: (context, studentSnap) {
          final sData = studentSnap.data?.data() ?? student ?? {};
          final currentPoints = (sData['points_balance'] as num?)?.toInt() ?? 0;

          return TabBarView(
            controller: _tabController,
            children: [
              _buildStoreTab(currentPoints, studentId, studentName, isParent),
              _buildLeaderboardTab(groupId, studentId),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStoreTab(int currentPoints, String studentId, String studentName, bool isParent) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: StudentDataService.instance.streamRewardsCatalog(),
      builder: (context, snapshot) {
        final rewards = snapshot.data ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Points Balance Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4), width: 1.2),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.15), blurRadius: 20, spreadRadius: 1),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFFD700)]),
                    ),
                    child: const Icon(Icons.monetization_on_rounded, color: Colors.black, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('رصيد النقاط المتاحة 🪙', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          '$currentPoints نقطة',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isParent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('وضع المتابعة 👨‍👧', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Row(
              children: [
                Icon(Icons.card_giftcard_rounded, color: Color(0xFF00F2FE), size: 20),
                SizedBox(width: 8),
                Text('المكافآت المتاحة للاستبدال 🎁', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 12),

            if (rewards.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'سيقوم المعلم بإضافة الجوائز قريباً! تابع اجتهادك لتجمع النقاط 🌟',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else
              ...rewards.map((r) {
                final cost = (r['cost_points'] as num).toInt();
                final canAfford = currentPoints >= cost;
                final needed = cost - currentPoints;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: canAfford ? const Color(0xFFFFD700).withValues(alpha: 0.4) : Colors.white10,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: canAfford ? const Color(0xFFFFD700).withValues(alpha: 0.2) : Colors.white12,
                            child: Icon(Icons.card_giftcard_rounded, color: canAfford ? const Color(0xFFFFD700) : Colors.grey),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['title'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text(r['description'] as String, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$cost 🪙',
                              style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (canAfford) ...[
                        if (!isParent)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD700),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.redeem_rounded, size: 18),
                            label: const Text('استبدال الآن 🎁', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final voucher = await StudentDataService.instance.submitRedemptionRequest(
                                studentId: studentId,
                                studentName: studentName,
                                rewardId: r['id'] as String,
                                rewardTitle: r['title'] as String,
                                costPoints: cost,
                              );
                              if (voucher != null && mounted) {
                                _showVoucherDialog(voucher, r['title'] as String);
                              }
                            },
                          )
                        else
                          const Text(
                            '✅ يمكن للطالب استبدال هذه المكافأة من حسابه',
                            style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: (currentPoints / cost).clamp(0.0, 1.0),
                                  backgroundColor: Colors.white10,
                                  valueColor: const AlwaysStoppedAnimation(Color(0xFF00F2FE)),
                                  minHeight: 6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'تحتاج $needed نقطة ⏳',
                              style: const TextStyle(color: Color(0xFF00F2FE), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _buildLeaderboardTab(dynamic groupId, String studentId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: StudentDataService.instance.streamLeaderboard(groupId),
      builder: (context, snapshot) {
        final leaderboard = snapshot.data ?? [];

        if (leaderboard.isEmpty) {
          return const Center(child: Text('جاري تحميل لوحة الشرف...', style: TextStyle(color: Colors.grey)));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: leaderboard.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final s = leaderboard[i];
            final rank = i + 1;
            final isMe = '${s['id']}' == studentId;
            final points = (s['points_balance'] as num?)?.toInt() ?? 0;

            Color rankColor = Colors.grey;
            if (rank == 1) rankColor = const Color(0xFFFFD700);
            if (rank == 2) rankColor = const Color(0xFFC0C0C0);
            if (rank == 3) rankColor = const Color(0xFFCD7F32);

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF00F2FE).withValues(alpha: 0.12) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isMe
                      ? const Color(0xFF00F2FE)
                      : (rank <= 3 ? rankColor.withValues(alpha: 0.5) : Colors.white10),
                  width: isMe || rank <= 3 ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: rankColor.withValues(alpha: 0.2),
                    ),
                    child: Text(
                      '$rank',
                      style: TextStyle(color: rankColor, fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              s['full_name'] ?? s['name'] ?? 'طالب',
                              style: TextStyle(
                                color: isMe ? const Color(0xFF00F2FE) : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00F2FE),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('أنت 🌟', style: TextStyle(color: Colors.black, fontSize: 9.5, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${s['grade'] ?? ''}',
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$points 🪙',
                      style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
