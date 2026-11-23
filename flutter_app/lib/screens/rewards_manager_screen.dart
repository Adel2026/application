import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/cloud_sync_service.dart';
import '../core/database/database_service.dart';

class RewardsManagerScreen extends StatefulWidget {
  final DatabaseService database;

  const RewardsManagerScreen({super.key, required this.database});

  @override
  State<RewardsManagerScreen> createState() => _RewardsManagerScreenState();
}

class _RewardsManagerScreenState extends State<RewardsManagerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // 1. Rules
  final TextEditingController _attPointsCtrl = TextEditingController();
  final TextEditingController _hwPointsCtrl = TextEditingController();
  final TextEditingController _quizPointsCtrl = TextEditingController();

  // 2. Rewards Catalog
  List<Map<String, dynamic>> _rewards = [];

  // 3. Leaderboard Students
  List<Map<String, dynamic>> _leaderboard = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _attPointsCtrl.dispose();
    _hwPointsCtrl.dispose();
    _quizPointsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final rules = await widget.database.getPointsRules();
      _attPointsCtrl.text = '${rules['attendance'] ?? 10}';
      _hwPointsCtrl.text = '${rules['homework'] ?? 15}';
      _quizPointsCtrl.text = '${rules['quiz'] ?? 25}';

      final rewards = await widget.database.getAllRewards();
      final leaderboard = await widget.database.getLeaderboardStudents(limit: 50);

      if (mounted) {
        setState(() {
          _rewards = rewards;
          _leaderboard = leaderboard;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading rewards data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveRules() async {
    final att = int.tryParse(_attPointsCtrl.text.trim()) ?? 10;
    final hw = int.tryParse(_hwPointsCtrl.text.trim()) ?? 15;
    final quiz = int.tryParse(_quizPointsCtrl.text.trim()) ?? 25;

    await widget.database.savePointsRules(attendance: att, homework: hw, quiz: quiz);
    HapticFeedback.mediumImpact();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ وتحديث قواعد النقاط بنجاح! 🪙'),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAddOrEditRewardDialog([Map<String, dynamic>? existing]) async {
    final titleCtrl = TextEditingController(text: existing?['title'] ?? '');
    final descCtrl = TextEditingController(text: existing?['description'] ?? '');
    final costCtrl = TextEditingController(text: '${existing?['cost_points'] ?? 50}');
    String iconName = existing?['icon_name'] ?? 'gift';

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.card_giftcard_rounded, color: Color(0xFF00F2FE)),
                const SizedBox(width: 8),
                Text(
                  existing != null ? 'تعديل المكافأة 🎁' : 'إضافة مكافأة جديدة 🎁',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم المكافأة *',
                      hintText: 'مثال: خصم 20% على الاشتراك',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: costCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'التكلفة بالنقاط *',
                      hintText: 'مثال: 50',
                      prefixIcon: const Icon(Icons.monetization_on_rounded, color: Color(0xFFF59E0B)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'وصف المكافأة وشروطها',
                      hintText: 'تفاصيل الحصول على المكافأة...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00F2FE),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  final cost = int.tryParse(costCtrl.text.trim()) ?? 0;
                  if (title.isEmpty || cost <= 0) return;

                  final id = existing?['id'] ?? 'reward_${DateTime.now().millisecondsSinceEpoch}';
                  await widget.database.saveReward(
                    id: id,
                    title: title,
                    description: descCtrl.text.trim(),
                    costPoints: cost,
                    iconName: iconName,
                  );

                  // مزامنة فورية مع السحابة
                  CloudSyncService.instance.syncRewardsCatalog();

                  Navigator.pop(ctx);
                  _loadAllData();
                },
                child: const Text('حفظ المكافأة', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteReward(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المكافأة'),
        content: const Text('هل أنت متأكد من حذف هذه المكافأة من الكتالوج؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.database.deleteReward(id);
      CloudSyncService.instance.syncRewardsCatalog();
      _loadAllData();
    }
  }

  Future<void> _giveBonusPoints(Map<String, dynamic> student, int points) async {
    final sId = student['id'] as String;
    final sName = student['full_name'] as String;

    await widget.database.awardStudentPoints(
      studentId: sId,
      delta: points,
      reason: 'نقاط تشجيعية ومكافأة من المعلم 🌟',
    );
    HapticFeedback.lightImpact();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 تم منح $sName +$points نقطة تشجيعية بنجاح! 🪙'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    _loadAllData();
  }

  Future<void> _redeemDialogForStudent(Map<String, dynamic> student) async {
    final sId = student['id'] as String;
    final sName = student['full_name'] as String;
    final currentPoints = (student['points_balance'] as num?)?.toInt() ?? 0;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.redeem_rounded, color: Color(0xFF00F2FE), size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'صرف مكافأة للطالب: $sName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.monetization_on_rounded, color: Color(0xFFF59E0B), size: 16),
                        const SizedBox(width: 4),
                        Text('$currentPoints نقطة', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFF59E0B))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('اختر المكافأة المراد صرفها وخصم نقاطها من رصيد الطالب:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _rewards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = _rewards[i];
                    final cost = (r['cost_points'] as num).toInt();
                    final canAfford = currentPoints >= cost;

                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: canAfford ? const Color(0xFF00F2FE).withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: canAfford ? const Color(0xFF00F2FE).withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1),
                          child: Icon(Icons.card_giftcard_rounded, color: canAfford ? const Color(0xFF00F2FE) : Colors.grey),
                        ),
                        title: Text(r['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                        subtitle: Text('${r['description']}\nالتكلفة: $cost نقطة', style: const TextStyle(fontSize: 11)),
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: canAfford ? const Color(0xFF10B981) : Colors.grey,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: canAfford
                              ? () async {
                                  Navigator.pop(ctx);
                                  final voucher = await widget.database.redeemRewardForStudent(
                                    studentId: sId,
                                    rewardId: r['id'] as String,
                                  );
                                  if (voucher != null && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('🎉 تم صرف المكافأة للطالب بنجاح! كود القسيمة: $voucher'),
                                        backgroundColor: const Color(0xFF10B981),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    _loadAllData();
                                  }
                                }
                              : null,
                          child: const Text('صرف الآن 🎁', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text('بنك النقاط والمكافآت التفاعلي 🏆', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00F2FE),
          labelColor: const Color(0xFF00F2FE),
          unselectedLabelColor: isDark ? Colors.grey : Colors.grey.shade700,
          tabs: const [
            Tab(icon: Icon(Icons.tune_rounded), text: 'قواعد النقاط'),
            Tab(icon: Icon(Icons.card_giftcard_rounded), text: 'كتالوج المكافآت'),
            Tab(icon: Icon(Icons.leaderboard_rounded), text: 'لوحة الشرف والصرف'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRulesTab(isDark),
                _buildRewardsCatalogTab(isDark),
                _buildLeaderboardTab(isDark),
              ],
            ),
    );
  }

  // --- TAB 1: RULES ---
  Widget _buildRulesTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                    : [const Color(0xFFE0F2FE), const Color(0xFFF0FDF4)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: Color(0xFFF59E0B), size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('نظام التحفيز التلقائي بالنقاط 🪙', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      SizedBox(height: 4),
                      Text(
                        'يقوم البرنامج تلقائياً بإضافة هذه النقاط لرصيد الطالب في السحابة وتطبيق الطالب فور رصد حضوره وواجباته في كشف الحصة اليومي.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildRuleCard(
            title: 'حضور الحصة في الموعد 🟢',
            subtitle: 'تمنح تلقائياً عند تسجيل حضور الطالب في كشف الحصة اليومي',
            controller: _attPointsCtrl,
            icon: Icons.check_circle_rounded,
            iconColor: const Color(0xFF10B981),
            isDark: isDark,
          ),
          const SizedBox(height: 12),

          _buildRuleCard(
            title: 'إتمام الواجب المنزلي كاملاً 📚',
            subtitle: 'تمنح تلقائياً عند تقييم الواجب (تم التسليم/كامل)',
            controller: _hwPointsCtrl,
            icon: Icons.assignment_turned_in_rounded,
            iconColor: const Color(0xFFF59E0B),
            isDark: isDark,
          ),
          const SizedBox(height: 12),

          _buildRuleCard(
            title: 'التفوق في التسميع والكويز 🌟',
            subtitle: 'تمنح تلقائياً عند تقييم التسميع (ممتاز / جيد جداً / 90%+)',
            controller: _quizPointsCtrl,
            icon: Icons.stars_rounded,
            iconColor: const Color(0xFF00F2FE),
            isDark: isDark,
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00F2FE),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.save_rounded),
            label: const Text('حفظ وتطبيق القواعد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            onPressed: _saveRules,
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: iconColor.withValues(alpha: 0.15),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, color: iconColor, fontSize: 16),
              decoration: InputDecoration(
                suffixText: '🪙',
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 2: REWARDS CATALOG ---
  Widget _buildRewardsCatalogTab(bool isDark) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF00F2FE),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة مكافأة', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _showAddOrEditRewardDialog(),
      ),
      body: _rewards.isEmpty
          ? const Center(child: Text('لا توجد مكافآت حالياً. اضغط لإضافة مكافأة جديدة!'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _rewards.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = _rewards[i];
                final cost = (r['cost_points'] as num).toInt();

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.card_giftcard_rounded, color: Color(0xFFF59E0B), size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(r['description'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'تكلفة المكافأة: $cost نقطة 🪙',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, size: 20, color: Color(0xFF00F2FE)),
                        onPressed: () => _showAddOrEditRewardDialog(r),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                        onPressed: () => _deleteReward(r['id'] as String),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  // --- TAB 3: LEADERBOARD & REDEMPTION ---
  Widget _buildLeaderboardTab(bool isDark) {
    return Scaffold(
      body: _leaderboard.isEmpty
          ? const Center(child: Text('لا يوجد طلاب مسجلين حالياً'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _leaderboard.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final s = _leaderboard[i];
                final points = (s['points_balance'] as num?)?.toInt() ?? 0;
                final rank = i + 1;

                Color rankColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;
                if (rank == 1) rankColor = const Color(0xFFFFD700);
                if (rank == 2) rankColor = const Color(0xFFC0C0C0);
                if (rank == 3) rankColor = const Color(0xFFCD7F32);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: rank <= 3 ? rankColor.withValues(alpha: 0.5) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      width: rank <= 3 ? 1.4 : 1,
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
                          color: rankColor.withValues(alpha: 0.18),
                        ),
                        child: Text(
                          '$rank',
                          style: TextStyle(fontWeight: FontWeight.w900, color: rankColor, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s['full_name'] as String,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${s['grade'] ?? ''} • رصيد: $points نقطة 🪙',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '+10 نقاط تشجيعية',
                        icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF10B981), size: 22),
                        onPressed: () => _giveBonusPoints(s, 10),
                      ),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _redeemDialogForStudent(s),
                        child: const Text('صرف مكافأة 🎁', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
