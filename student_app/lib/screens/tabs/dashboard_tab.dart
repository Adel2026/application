import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/student_auth_service.dart';
import '../../services/student_data_service.dart';
import '../../theme/app_theme.dart';
import '../smart_pdf_viewer_screen.dart';
import '../student_rewards_screen.dart';

class DashboardTab extends StatelessWidget {
  final void Function(int tabIndex)? onNavigateTab;

  const DashboardTab({super.key, this.onNavigateTab});

  void _navigate(int index) {
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
    onNavigateTab?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    final groupId = student?['group_id'];

    return StreamBuilder<Map<String, dynamic>>(
      stream: StudentDataService.instance.streamAppVisibilityConfig(),
      builder: (context, configSnap) {
        final config = configSnap.data ?? {};
        final showLessons = config['show_lessons'] != false;
        final showHomework = config['show_homework'] != false;
        final showGrades = config['show_grades'] != false;
        final showPayments = config['show_payments'] != false;

        return RefreshIndicator(
          color: const Color(0xFF00F2FE),
          onRefresh: () async {
            // Real-time streams are automatically fresh
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. Cancellation / Urgent Alert Banner (if any)
              if (groupId != null)
                StreamBuilder<List<Map<String, dynamic>>>(
              stream: StudentDataService.instance.streamGroupCancellations(groupId),
              builder: (context, snapshot) {
                final cancellations = snapshot.data ?? [];
                if (cancellations.isEmpty) return const SizedBox.shrink();
                final latest = cancellations.first;
                final reason = latest['reason'] ?? '';
                final date = latest['date'] ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.danger.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تنبيه عاجل: تم إلغاء حصة $date 🚫',
                              style: const TextStyle(
                                color: AppTheme.danger,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            if (reason.toString().isNotEmpty)
                              Text(
                                'السبب: $reason',
                                style: const TextStyle(
                                  color: Color(0xFFFCA5A5),
                                  fontSize: 11.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // 2. Next Lesson Hero Card (with pulsing cyan live badge & countdown)
          if (showLessons || showHomework) ...[
            _buildNextLessonHero(context, groupId),
            const SizedBox(height: 18),
          ],

          // 2.5 بطاقة التحدي الذهبية (بنك النقاط والمكافآت التفاعلي)
          _buildPointsChallengeCard(context, studentId),
          const SizedBox(height: 18),

          // 3. Quick Actions Header & 4 Big Chic Rounded Cards
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الوصول السريع ⚡',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textLight,
                ),
              ),
              Text(
                'كل ما تحتاجه بضغطة زر',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildQuickActionsGrid(context),
          const SizedBox(height: 18),

          // 4. Continue Studying Hero Banner (Dedicated Smart PDF Reader)
          _buildContinueStudyingHero(context, groupId),
          const SizedBox(height: 18),

          // 5. Fast-Tracking Academic Health Overview (Attendance, Financials, Reports)
          _buildFastTrackingOverview(context, studentId, showPayments: showPayments),
          const SizedBox(height: 20),

          // 6. Recent Activity Feed
          if (showGrades) ...[
            _buildRecentActivitySection(studentId),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
      },
    );
  }

  // =========================================================================
  // 0. Golden Challenge Card (بنك النقاط والمكافآت التفاعلي)
  // =========================================================================
  Widget _buildPointsChallengeCard(BuildContext context, String studentId) {
    return StreamBuilder(
      stream: StudentDataService.instance.streamStudent(studentId),
      builder: (context, studentSnap) {
        final sData = studentSnap.data?.data() ?? {};
        final points = (sData['points_balance'] as num?)?.toInt() ?? 0;

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: StudentDataService.instance.streamRewardsCatalog(),
          builder: (context, rewardsSnap) {
            final rewards = rewardsSnap.data ?? [];
            int nextCost = 50;
            String nextTitle = 'مكافأة التفوق';

            if (rewards.isNotEmpty) {
              final upcoming = rewards.where((r) => ((r['cost_points'] as num).toInt()) > points).toList();
              if (upcoming.isNotEmpty) {
                upcoming.sort((a, b) => ((a['cost_points'] as num).toInt()).compareTo((b['cost_points'] as num).toInt()));
                nextCost = (upcoming.first['cost_points'] as num).toInt();
                nextTitle = upcoming.first['title'] as String;
              } else {
                nextCost = (rewards.last['cost_points'] as num).toInt();
                nextTitle = rewards.last['title'] as String;
              }
            }

            final progress = (points / (nextCost > 0 ? nextCost : 1)).clamp(0.0, 1.0);
            final needed = (nextCost - points) > 0 ? (nextCost - points) : 0;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.5), width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFFD700)]),
                        ),
                        child: const Icon(Icons.stars_rounded, color: Colors.black, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text(
                                  'تحدي النقاط والمكافآت 🏆',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14.5),
                                ),
                                SizedBox(width: 6),
                                Text('• مباشر', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              needed > 0 ? 'متبقي $needed نقطة لفتح ($nextTitle)' : '🎉 رصيدك مؤهل لاستبدال مكافأة الآن!',
                              style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.monetization_on_rounded, color: Color(0xFFFFD700), size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '$points',
                              style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFFFD700)),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Button to rewards store
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StudentRewardsScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.storefront_rounded, color: Color(0xFFFFD700), size: 16),
                          SizedBox(width: 8),
                          Text(
                            'فتح متجر المكافآت ولوحة الشرف 🎁',
                            style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFFFD700), size: 12),
                        ],
                      ),
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

  // =========================================================================
  // 1. Next Lesson Hero Card
  // =========================================================================
  Widget _buildNextLessonHero(BuildContext context, dynamic groupId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: StudentDataService.instance.streamGroupSessions(groupId),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? [];
        final hasSession = sessions.isNotEmpty;
        final latestSession = hasSession ? sessions.first : null;

        final lessonTitle = latestSession?['title'] ?? 'مراجعة المنهج وحل بنك الأسئلة';
        final sessionDate = latestSession?['session_date'] ?? 'الأحد القادم';
        final sessionTime = latestSession?['start_time'] ?? '05:00 م';

        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF172554)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0284C7).withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Live Pulsing Badge + Date/Time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fiber_manual_record, color: Color(0xFF00F2FE), size: 10),
                        SizedBox(width: 5),
                        Text(
                          'حصة قادمة',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00F2FE),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '📅 $sessionDate • $sessionTime',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                lessonTitle,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // Meta Row
              const Row(
                children: [
                  Icon(Icons.person_pin_circle_outlined, size: 14, color: Color(0xFF94A3B8)),
                  SizedBox(width: 4),
                  Text(
                    'أكاديمية المعلم',
                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                  SizedBox(width: 12),
                  Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF94A3B8)),
                  SizedBox(width: 4),
                  Text(
                    'القاعة الرئيسية',
                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Action CTA Button: Full width gradient
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _navigate(4), // Opens LessonsTab
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00F2FE), Color(0xFF0284C7)],
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'تأكيد الحضور والواجب المطلوب',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF050B14),
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_back_rounded, size: 16, color: Color(0xFF050B14)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================================
  // 2. 4 Chic Quick Action Cards (2x2 Grid)
  // =========================================================================
  Widget _buildQuickActionsGrid(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.25,
      children: [
        // Card 1: مذكراتي الذكية (Cyan)
        _buildActionCard(
          title: 'مذكراتي الذكية',
          subtitle: 'PDF فائق السرعة وأدوات مذاكرة',
          badgeText: 'جديد ⚡',
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF00F2FE),
          onTap: () => _navigate(1), // Tab 1: Materials
        ),

        // Card 2: واجباتي ومهامي (Green)
        _buildActionCard(
          title: 'واجباتي ومهامي',
          subtitle: 'حل التمارين والواجبات المنزلية',
          badgeText: 'مطلوب',
          icon: Icons.assignment_rounded,
          color: const Color(0xFF10B981),
          onTap: () => _navigate(4), // Subpage: Lessons
        ),

        // Card 3: لوحة الشرف والدرجات (Amber)
        _buildActionCard(
          title: 'لوحة الشرف',
          subtitle: 'نتائج الاختبارات والشهادات',
          badgeText: 'متفوق 🌟',
          icon: Icons.emoji_events_rounded,
          color: const Color(0xFFF59E0B),
          onTap: () => _navigate(2), // Tab 2: Exams
        ),

        // Card 4: محادثة المعلم (Purple)
        _buildActionCard(
          title: 'محادثة المعلم',
          subtitle: 'اسأل واستفسر صوت وصورة',
          badgeText: 'مباشر ⚡',
          icon: Icons.forum_rounded,
          color: const Color(0xFF8B5CF6),
          onTap: () => _navigate(3), // Tab 3: Chat
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: color.withValues(alpha: 0.28),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top row: Icon + Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(icon, color: color, size: 20),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),

              // Title and Subtitle
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 3. Continue Studying Hero Banner
  // =========================================================================
  Widget _buildContinueStudyingHero(BuildContext context, dynamic groupId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: StudentDataService.instance.streamLessonMaterials(groupId: groupId),
      builder: (context, snapshot) {
        final materials = snapshot.data ?? [];
        final hasMat = materials.isNotEmpty;
        final mat = hasMat ? materials.first : null;
        final title = mat?['title'] ?? 'مذكرة المراجعة الشاملة ليلة الامتحان';
        final fileUrl = (mat?['file_url'] ?? '').toString();
        final materialId = (mat?['id'] ?? 'mat_recent').toString();

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (fileUrl.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SmartPdfViewerScreen(
                      materialId: materialId,
                      title: title,
                      fileUrl: fileUrl,
                    ),
                  ),
                );
              } else {
                _navigate(1); // Go to Materials library
              }
            },
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Mini PDF Cover
                  Container(
                    width: 44,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
                        SizedBox(height: 2),
                        Text(
                          'PDF',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Progress & Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Text(
                              'تابِع المذاكرة الآن 📖',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF00F2FE),
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              '• توقفت عند صفحة 14',
                              style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Progress Bar (65%)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            height: 5,
                            width: double.infinity,
                            color: const Color(0xFF1E293B),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerRight,
                              widthFactor: 0.65,
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF00F2FE), Color(0xFF0284C7)],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Arrow Button
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 13,
                      color: Color(0xFF00F2FE),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================================================================
  // 4. Fast-Tracking Academic Health Overview (Attendance, Financials, Reports)
  // =========================================================================
  Widget _buildFastTrackingOverview(BuildContext context, dynamic studentId, {bool showPayments = true}) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: StudentDataService.instance.streamStudentAttendance(studentId),
      builder: (context, attSnapshot) {
        final attendances = attSnapshot.data ?? [];
        final totalAtt = attendances.length;
        final presentAtt = attendances.where((a) => a['status'] == 'present').length;
        final absentAtt = attendances.where((a) => a['status'] == 'absent').length;
        final attRate = totalAtt == 0 ? 100 : ((presentAtt / totalAtt) * 100).toInt();

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: StudentDataService.instance.streamStudentFinancials(studentId),
          builder: (context, finSnapshot) {
            final financials = finSnapshot.data ?? [];
            double totalReq = 0;
            double totalPaid = 0;
            for (final f in financials) {
              totalReq += (f['required_amount'] as num? ?? 0).toDouble();
              totalPaid += (f['paid_amount'] as num? ?? 0).toDouble();
            }
            final remaining = (totalReq - totalPaid).clamp(0, double.infinity);

            return Row(
              children: [
                // Attendance Quick Pill
                Expanded(
                  child: _buildOverviewPill(
                    icon: Icons.event_available_rounded,
                    color: attRate >= 85 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    title: 'الحضور والالتزام',
                    value: '%$attRate',
                    onTap: () => _showAttendanceDetailsModal(
                      context,
                      attendances,
                      totalAtt,
                      presentAtt,
                      absentAtt,
                      attRate,
                    ),
                  ),
                ),

                // Financials Quick Pill (إذا كان المعلم مفعلاً إظهار المدفوعات)
                if (showPayments) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildOverviewPill(
                      icon: Icons.account_balance_wallet_rounded,
                      color: remaining == 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      title: 'المصروفات',
                      value: remaining == 0 ? 'مسدد ✅' : '${remaining.toStringAsFixed(0)} ج',
                      onTap: () => _navigate(6), // Financials subpage
                    ),
                  ),
                ],
                const SizedBox(width: 8),

                // Reports Quick Pill
                Expanded(
                  child: _buildOverviewPill(
                    icon: Icons.assessment_rounded,
                    color: const Color(0xFF38BDF8),
                    title: 'التقرير الشامل',
                    value: 'معتمد 🛡️',
                    onTap: () => _navigate(5), // Reports subpage
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOverviewPill({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivitySection(dynamic studentId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.bolt_rounded, size: 18, color: Color(0xFF00F2FE)),
            SizedBox(width: 8),
            Text(
              'آخر التحديثات والأنشطة الأكاديمية ⚡',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppTheme.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Stream Latest Exam
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: StudentDataService.instance.streamStudentExams(studentId),
          builder: (context, snap) {
            final exams = snap.data ?? [];
            if (exams.isEmpty) return const SizedBox.shrink();
            final latest = exams.first;
            final title = latest['exam_title'] ?? 'اختبار تقييمي';
            final score = latest['score'] ?? 0;
            final max = latest['max_score'] ?? 50;
            final date = latest['exam_date'] ?? '';

            return _buildActivityCard(
              title: 'آخر اختبار رُصد: $title',
              subtitle: 'الدرجة: $score من $max  |  بتاريخ: $date',
              icon: Icons.assignment_turned_in_rounded,
              color: const Color(0xFFA855F7),
              onTap: () => _navigate(1),
            );
          },
        ),

        // Stream Latest Attendance
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: StudentDataService.instance.streamStudentAttendance(studentId),
          builder: (context, snap) {
            final atts = snap.data ?? [];
            if (atts.isEmpty) return const SizedBox.shrink();
            final latest = atts.first;
            final date = latest['attendance_date'] ?? latest['session_date'] ?? '';
            final status = latest['status'] == 'present' ? 'حاضر ✅' : 'غائب ❌';

            return _buildActivityCard(
              title: 'آخر تسجيل حضور: $date',
              subtitle: 'الحالة: $status',
              icon: Icons.event_available_rounded,
              color: const Color(0xFF10B981),
              onTap: () => _navigate(2),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActivityCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.darkCardBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
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
                const Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // نافذة سجل حضور وغياب الطالب التفصيلي لولي الأمر
  // =========================================================================
  void _showAttendanceDetailsModal(
    BuildContext context,
    List<Map<String, dynamic>> attendances,
    int totalAtt,
    int presentAtt,
    int absentAtt,
    int attRate,
  ) {
    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.75,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
          child: Column(
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

              // ترويسة الشيت
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.event_available_rounded, color: Color(0xFF10B981), size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سجل حضور وغياب الطالب التفصيلي 📅',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textLight,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'بيان بكافة الحصص المنفذة وتاريخ ووقت تسجيل الحضور',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // بطاقات إحصائيات الحضور السريعة
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildAttendanceStatPill(
                        label: 'إجمالي الحصص',
                        value: '$totalAtt حصة',
                        color: const Color(0xFF00F2FE),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildAttendanceStatPill(
                        label: 'الحضور الفعلي',
                        value: '$presentAtt ✅',
                        color: const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildAttendanceStatPill(
                        label: 'عدد الغياب',
                        value: '$absentAtt ❌',
                        color: absentAtt > 0 ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildAttendanceStatPill(
                        label: 'نسبة الالتزام',
                        value: '%$attRate',
                        color: attRate >= 85 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),
              const Text(
                'سجل الحصص بالتواريخ:',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textLight),
              ),
              const SizedBox(height: 8),

              // قائمة سجلات الحضور
              Expanded(
                child: attendances.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد سجلات حضور مسجلة حتى الآن.',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        itemCount: attendances.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final a = attendances[index];
                          final date = (a['attendance_date'] ?? a['session_date'] ?? '').toString();
                          final status = (a['status'] ?? 'present').toString();
                          final isPresent = status == 'present';
                          final isLate = status == 'late';
                          final checkInTime = (a['check_in_at'] ?? '').toString();
                          final source = (a['source'] ?? '').toString();

                          Color statusColor = isPresent
                              ? const Color(0xFF10B981)
                              : (isLate ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
                          String statusText = isPresent
                              ? 'حاضر في الموعد ✅'
                              : (isLate ? 'حاضر متأخر ⏱️' : 'غائب ❌');

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isPresent ? Icons.check_rounded : (isLate ? Icons.access_time_rounded : Icons.close_rounded),
                                    color: statusColor,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'حصة يوم: $date',
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textLight,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        checkInTime.isNotEmpty
                                            ? 'وقت التحضير: $checkInTime  ${source.isNotEmpty ? "• $source" : ""}'
                                            : (isPresent ? 'تم تسجيل الحضور داخل الحصة' : 'لم يسجل حضور الطالب في هذه الحصة'),
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildAttendanceStatPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

