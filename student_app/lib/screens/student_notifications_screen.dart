import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/student_auth_service.dart';
import '../services/student_communication_service.dart';
import '../theme/app_theme.dart';

class StudentNotificationsScreen extends StatefulWidget {
  const StudentNotificationsScreen({super.key});

  @override
  State<StudentNotificationsScreen> createState() =>
      _StudentNotificationsScreenState();
}

class _StudentNotificationsScreenState
    extends State<StudentNotificationsScreen> {
  final _service = StudentCommunicationService.instance;
  String _selectedFilter = 'all'; // all, exam, session, report, financial, urgent, general
  Set<String> _readIds = {};
  bool _isLoadingReadIds = true;

  @override
  void initState() {
    super.initState();
    _loadReadState();
  }

  Future<void> _loadReadState() async {
    final ids = await _service.getReadNotificationIds();
    if (mounted) {
      setState(() {
        _readIds = ids;
        _isLoadingReadIds = false;
      });
    }
  }

  Future<void> _handleNotificationAction(Map<String, dynamic> notif, int targetTabIndex) async {
    final id = (notif['id'] ?? '${notif['title']}_${notif['created_at']}').toString();
    await _service.markNotificationAsRead(id);
    if (mounted) {
      setState(() {
        _readIds.add(id);
      });
    }

    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);

    if (mounted) {
      Navigator.pop(context, targetTabIndex);
    }
  }

  Future<void> _markAllAsRead(List<Map<String, dynamic>> list) async {
    if (list.isEmpty) return;
    await _service.markNotificationsAsSeen(list);
    final ids = await _service.getReadNotificationIds();
    if (mounted) {
      setState(() {
        _readIds = ids;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديد جميع الإشعارات كمقروءة بنجاح ✅'),
          backgroundColor: AppTheme.success,
          duration: Duration(seconds: 2),
        ),
      );
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
        title: const Text('مركز الإشعارات والتنبيهات 📢'),
        centerTitle: true,
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _service.streamStudentNotifications(
              studentId: studentId,
              groupId: groupId,
            ),
            builder: (context, snap) {
              final all = snap.data ?? [];
              final unread = all.where((n) {
                final id = (n['id'] ?? '${n['title']}_${n['created_at']}').toString();
                return !_readIds.contains(id);
              }).length;

              if (unread == 0) return const SizedBox.shrink();

              return TextButton.icon(
                onPressed: () => _markAllAsRead(all),
                icon: const Icon(Icons.done_all_rounded, size: 16, color: Color(0xFF00F2FE)),
                label: const Text(
                  'قراءة الكل',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00F2FE),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoadingReadIds
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)))
          : Column(
              children: [
                // 1. Sleek Filter Chips Bar
                _buildFilterBar(),

                // 2. Compact Notifications List
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _service.streamStudentNotifications(
                      studentId: studentId,
                      groupId: groupId,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)));
                      }

                      final rawList = snapshot.data ?? [];
                      final list = _selectedFilter == 'all'
                          ? rawList
                          : rawList.where((n) {
                              final type = (n['type'] ?? 'general').toString().toLowerCase();
                              if (_selectedFilter == 'session') {
                                return type == 'session' || type == 'lesson';
                              }
                              return type == _selectedFilter;
                            }).toList();

                      if (list.isEmpty) {
                        return _buildEmptyState();
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        itemCount: list.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final notif = list[index];
                          final id = (notif['id'] ?? '${notif['title']}_${notif['created_at']}').toString();
                          final isRead = _readIds.contains(id);
                          return _buildCompactNotificationCard(notif, isRead);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterBar() {
    final filters = [
      {'id': 'all', 'label': 'الكل 🌐', 'color': const Color(0xFF00F2FE)},
      {'id': 'exam', 'label': 'الامتحانات 📊', 'color': const Color(0xFFA855F7)},
      {'id': 'session', 'label': 'الحصص 📝', 'color': const Color(0xFF10B981)},
      {'id': 'report', 'label': 'التقارير 📑', 'color': const Color(0xFF38BDF8)},
      {'id': 'financial', 'label': 'المصروفات 🧾', 'color': const Color(0xFFF59E0B)},
      {'id': 'urgent', 'label': 'عاجل ⚠️', 'color': const Color(0xFFF43F5E)},
      {'id': 'general', 'label': 'إعلانات 📢', 'color': const Color(0xFF94A3B8)},
    ];

    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, idx) {
          final item = filters[idx];
          final id = item['id'] as String;
          final label = item['label'] as String;
          final color = item['color'] as Color;
          final isSelected = _selectedFilter == id;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedFilter = id);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.18)
                    : AppTheme.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? color : AppTheme.darkCardBorder,
                  width: isSelected ? 1.4 : 1.0,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? color : AppTheme.textMuted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompactNotificationCard(Map<String, dynamic> notif, bool isRead) {
    final title = (notif['title'] ?? '').toString();
    final body = (notif['body'] ?? '').toString();
    final rawType = (notif['type'] ?? 'general').toString().toLowerCase();
    final ts = notif['created_at'];

    String timeStr = '';
    if (ts is Timestamp) {
      final dt = ts.toDate();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) {
        timeStr = 'منذ ${diff.inMinutes <= 1 ? "دقيقة" : "${diff.inMinutes} د"}';
      } else if (diff.inHours < 24) {
        timeStr = 'منذ ${diff.inHours <= 1 ? "ساعة" : "${diff.inHours} س"}';
      } else {
        timeStr = '${dt.month}/${dt.day}';
      }
    }

    Color neonColor;
    Color neonBg;
    IconData icon;
    String badgeLabel;
    int targetTab;
    String actionLabel;

    switch (rawType) {
      case 'exam':
        neonColor = const Color(0xFFA855F7);
        neonBg = const Color(0xFFA855F7).withValues(alpha: 0.14);
        icon = Icons.assignment_turned_in_rounded;
        badgeLabel = 'اختبار';
        targetTab = 1;
        actionLabel = 'عرض الدرجات 👈';
        break;
      case 'session':
      case 'lesson':
        neonColor = const Color(0xFF10B981);
        neonBg = const Color(0xFF10B981).withValues(alpha: 0.14);
        icon = Icons.menu_book_rounded;
        badgeLabel = 'حصة وواجب';
        targetTab = 2;
        actionLabel = 'عرض الحصة 👈';
        break;
      case 'material':
      case 'pdf':
        neonColor = const Color(0xFFEF4444);
        neonBg = const Color(0xFFEF4444).withValues(alpha: 0.14);
        icon = Icons.picture_as_pdf_rounded;
        badgeLabel = 'مذكرة PDF';
        targetTab = 3;
        actionLabel = 'فتح المذكرة 👈';
        break;
      case 'report':
        neonColor = const Color(0xFF38BDF8);
        neonBg = const Color(0xFF38BDF8).withValues(alpha: 0.14);
        icon = Icons.assessment_rounded;
        badgeLabel = 'تقرير متابعة';
        targetTab = 4;
        actionLabel = 'فتح التقرير 👈';
        break;
      case 'financial':
        neonColor = const Color(0xFFF59E0B);
        neonBg = const Color(0xFFF59E0B).withValues(alpha: 0.14);
        icon = Icons.account_balance_wallet_rounded;
        badgeLabel = 'مصروفات';
        targetTab = 5;
        actionLabel = 'كشف الحساب 👈';
        break;
      case 'chat':
        neonColor = const Color(0xFF00F2FE);
        neonBg = const Color(0xFF00F2FE).withValues(alpha: 0.14);
        icon = Icons.chat_bubble_rounded;
        badgeLabel = 'محادثة';
        targetTab = 6;
        actionLabel = 'فتح المحادثة 👈';
        break;
      case 'urgent':
        neonColor = const Color(0xFFF43F5E);
        neonBg = const Color(0xFFF43F5E).withValues(alpha: 0.16);
        icon = Icons.warning_amber_rounded;
        badgeLabel = 'عاجل';
        targetTab = 0;
        actionLabel = 'عرض التفاصيل 👈';
        break;
      default:
        neonColor = const Color(0xFF00F2FE);
        neonBg = const Color(0xFF00F2FE).withValues(alpha: 0.14);
        icon = Icons.campaign_rounded;
        badgeLabel = 'إعلان';
        targetTab = 0;
        actionLabel = 'عرض الإعلان 👈';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleNotificationAction(notif, targetTab),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isRead
                ? AppTheme.darkCard.withValues(alpha: 0.6)
                : AppTheme.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isRead
                  ? const Color(0xFF10B981).withValues(alpha: 0.3)
                  : neonColor.withValues(alpha: 0.55),
              width: isRead ? 1.0 : 1.4,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: Mini Icon + Category Tag + Read Status + Timestamp
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: neonBg,
                      border: Border.all(color: neonColor, width: 1),
                    ),
                    child: Icon(icon, color: neonColor, size: 15),
                  ),
                  const SizedBox(width: 8),

                  // Category Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: neonColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: neonColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Read Status Indicator
                  if (isRead)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF10B981)),
                        SizedBox(width: 2),
                        Text(
                          'تمت القراءة',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'جديد 🔔',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ),

                  const Spacer(),
                  if (timeStr.isNotEmpty)
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),

              // Title
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: isRead ? const Color(0xFFCBD5E1) : AppTheme.textLight,
                  height: 1.25,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              if (body.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isRead ? const Color(0xFF94A3B8) : const Color(0xFFCBD5E1),
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),

              // Bottom Action Pill (Compact and active)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: neonColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: neonColor.withValues(alpha: 0.4), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          actionLabel,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: neonColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_back_rounded, size: 12, color: neonColor),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.darkCardBorder),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 28,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'لا توجد تنبيهات مطابقة حالياً',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.textLight,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'أي إعلانات أو مواعيد أو اختبارات جديدة ستصلك هنا مباشرة',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
