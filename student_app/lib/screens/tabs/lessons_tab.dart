import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/student_auth_service.dart';
import '../../services/student_data_service.dart';
import '../../theme/app_theme.dart';
import '../smart_pdf_viewer_screen.dart';

class LessonsTab extends StatefulWidget {
  const LessonsTab({super.key});

  @override
  State<LessonsTab> createState() => _LessonsTabState();
}

class _LessonsTabState extends State<LessonsTab> with SingleTickerProviderStateMixin {
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

  Future<void> _openPdf(BuildContext context, String url, String title) async {
    HapticFeedback.lightImpact();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رابط الملف غير متوفر حالياً', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SmartPdfViewerScreen(
          materialId: 'lesson_${url.hashCode}',
          title: title,
          fileUrl: url,
        ),
      ),
    );
  }

  Future<void> _sharePdf(String url, String title) async {
    HapticFeedback.lightImpact();
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '📚 مذكرة دراسية: $title\n🔗 رابط التحميل والقراءة المباشر:\n$url',
        ),
      );
    } catch (e) {
      debugPrint('Error sharing PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    final groupId = student?['group_id'];

    return Scaffold(
      backgroundColor: const Color(0xFF060911),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          color: const Color(0xFF080C14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: const Color(0xFF080C14),
              unselectedLabelColor: const Color(0xFF94A3B8),
              labelStyle: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
              unselectedLabelStyle: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_month_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('جدول الحصص'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.picture_as_pdf_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('مكتبة المذكرات 📚'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // تبويب 1: جدول الحصص والدروس
          _buildSessionsTab(studentId, groupId),

          // تبويب 2: مكتبة المذكرات وملفات PDF
          _buildMaterialsLibraryTab(groupId),
        ],
      ),
    );
  }

  Widget _buildSessionsTab(String studentId, dynamic groupId) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: StudentDataService.instance.streamSessionsAndAttendance(
        studentId: studentId,
        groupId: groupId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)));
        }

        final data = snapshot.data ?? {};
        final groupData = (data['group'] as Map<String, dynamic>?) ?? {};
        final groupName = groupData['name'] ?? 'مجموعة الطالب الدراسية';
        final rawSessions = (data['sessions'] as List<Map<String, dynamic>>?) ?? [];
        final attendances = (data['attendances'] as List<Map<String, dynamic>>?) ?? [];

        // فهرسة الحضور في خريطة للتصفح الفوري O(1)
        final attByDate = <String, Map<String, dynamic>>{};
        for (final a in attendances) {
          final d = (a['attendance_date'] ?? a['session_date'] ?? '').toString().trim();
          if (d.isNotEmpty && !attByDate.containsKey(d)) {
            attByDate[d] = a;
          }
        }

        final Map<String, Map<String, dynamic>> uniqueMap = {};
        for (final s in rawSessions) {
          final sDate = (s['session_date'] ?? s['date'] ?? '').toString().trim();
          final sTitle = (s['lesson_title'] ?? s['content_covered'] ?? '').toString().trim();
          final key = sDate.isNotEmpty ? '${sDate}_$sTitle' : '${s['id'] ?? UniqueKey()}';

          if (!uniqueMap.containsKey(key)) {
            uniqueMap[key] = Map<String, dynamic>.from(s);
          } else {
            final existing = uniqueMap[key]!;
            final exHw = (existing['homework_assigned'] ?? existing['homework'] ?? '').toString().trim();
            final newHw = (s['homework_assigned'] ?? s['homework'] ?? '').toString().trim();
            if (exHw.isEmpty && newHw.isNotEmpty) existing['homework_assigned'] = newHw;

            final exNotes = (existing['notes'] ?? '').toString().trim();
            final newNotes = (s['notes'] ?? '').toString().trim();
            if (exNotes.isEmpty && newNotes.isNotEmpty) existing['notes'] = newNotes;

            final exPdf = (existing['pdf_url'] ?? '').toString().trim();
            final newPdf = (s['pdf_url'] ?? '').toString().trim();
            if (exPdf.isEmpty && newPdf.isNotEmpty) existing['pdf_url'] = newPdf;
          }
        }

        final sessions = uniqueMap.values.toList();
        sessions.sort((a, b) {
          final dateA = (a['session_date'] ?? a['date'] ?? '').toString();
          final dateB = (b['session_date'] ?? b['date'] ?? '').toString();
          final comp = dateB.compareTo(dateA);
          if (comp != 0) return comp;
          return ('${b['id'] ?? 0}').compareTo('${a['id'] ?? 0}');
        });

        int attendedSessionsCount = 0;
        int absentSessionsCount = 0;

        for (final s in sessions) {
          final sDate = (s['session_date'] ?? s['date'] ?? '').toString().trim();
          final attRecord = attByDate[sDate] ?? _findAttendanceForDate(attendances, sDate);
          if (attRecord != null) {
            if (attRecord['status'] == 'present') {
              attendedSessionsCount++;
            } else if (attRecord['status'] == 'absent') {
              absentSessionsCount++;
            }
          }
        }

        if (sessions.isEmpty) {
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
                  child: const Icon(Icons.menu_book_rounded, size: 34, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 14),
                const Text(
                  'لا توجد حصص مسجلة بعد',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textLight),
                ),
                const SizedBox(height: 6),
                Text(
                  'ستظهر هنا الدروس المشروحة لمجموعة ($groupName) مع حالة حضور الطالب في كل حصة.',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          itemCount: sessions.length + 1,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildHeaderCard(
                groupName: groupName,
                totalSessions: sessions.length,
                attendedCount: attendedSessionsCount,
                absentCount: absentSessionsCount,
              );
            }

            final sessionIndex = index - 1;
            final session = sessions[sessionIndex];
            final sDate = (session['session_date'] ?? session['date'] ?? '').toString();
            final rawTitle = (session['lesson_title'] ?? session['content_covered'] ?? '').toString().trim();
            final lessonNum = sessions.length - sessionIndex;
            final title = rawTitle.isNotEmpty && rawTitle != 'حصة دراسية'
                ? rawTitle
                : 'حصة دراسية #$lessonNum ($groupName)';
            final homework = session['homework_assigned'] ?? session['homework'] ?? '';
            final notes = session['notes'] ?? '';
            final pdfUrl = (session['pdf_url'] ?? '').toString().trim();
            final pdfTitle = (session['pdf_title'] ?? title).toString().trim();
            final pdfSize = (session['pdf_size'] ?? '').toString().trim();

            final attRecord = attByDate[sDate] ?? _findAttendanceForDate(attendances, sDate);

            return _buildSessionCard(
              context: context,
              session: session,
              lessonNumber: lessonNum,
              groupName: groupName,
              date: sDate,
              title: title,
              homework: homework,
              notes: notes,
              pdfUrl: pdfUrl,
              pdfTitle: pdfTitle,
              pdfSize: pdfSize,
              attRecord: attRecord,
            );
          },
        );
      },
    );
  }

  // تبويب مكتبة المذكرات وملفات الـ PDF
  Widget _buildMaterialsLibraryTab(dynamic groupId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('lesson_materials')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)));
        }

        final allDocs = snapshot.data?.docs ?? [];
        final filteredDocs = allDocs.where((doc) {
          final data = doc.data();
          final gId = data['group_id']?.toString() ?? 'all';
          return gId == 'all' || gId == groupId?.toString();
        }).toList();

        if (filteredDocs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, size: 36, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'لا توجد مذكرات دراسية منشورة بعد',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'عندما يقوم المعلم برفع ملخصات الحصص ومذكرات الـ PDF ستظهر هنا فوراً مع إمكانية القراءة والتحميل.',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5, color: Color(0xFF94A3B8)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          itemCount: filteredDocs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = filteredDocs[index].data();
            final title = data['title'] ?? 'مذكرة دراسية';
            final desc = data['description'] ?? '';
            final groupName = data['group_name'] ?? 'عام';
            final sessionTitle = data['session_title'] ?? '';
            final fileUrl = data['file_url'] ?? '';
            final fileSize = data['file_size'] ?? 'PDF';

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF1E293B)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF080C14), size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    groupName,
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    fileSize,
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (sessionTitle.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.link_rounded, size: 14, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'مرتبطة بالحصة: $sessionTitle',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      desc,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00F2FE),
                            foregroundColor: const Color(0xFF080C14),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.visibility_rounded, size: 18),
                          label: const Text(
                            'عرض وقراءة المذكرة',
                            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 12.5),
                          ),
                          onPressed: () => _openPdf(context, fileUrl, title),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          padding: const EdgeInsets.all(10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.share_rounded, color: Colors.white, size: 20),
                        tooltip: 'مشاركة المذكرة',
                        onPressed: () => _sharePdf(fileUrl, title),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeaderCard({
    required String groupName,
    required int totalSessions,
    required int attendedCount,
    required int absentCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.school_rounded, color: Color(0xFF00F2FE), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مقرر وحصص: $groupName',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'يمكنك متابعة مواعيد الحصص ومذكرات الشرح وتكليفات الواجب',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildHeaderMiniPill(
                  label: 'إجمالي الدروس',
                  value: '$totalSessions درس',
                  color: const Color(0xFF00F2FE),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHeaderMiniPill(
                  label: 'حضرها الطالب',
                  value: '$attendedCount ✅',
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHeaderMiniPill(
                  label: 'غياب الطالب',
                  value: '$absentCount ❌',
                  color: absentCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMiniPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.textMuted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard({
    required BuildContext context,
    required Map<String, dynamic> session,
    required int lessonNumber,
    required String groupName,
    required String date,
    required String title,
    required String homework,
    required String notes,
    required String pdfUrl,
    required String pdfTitle,
    required String pdfSize,
    required Map<String, dynamic>? attRecord,
  }) {
    final bool isPresent = attRecord?['status'] == 'present';
    final bool isAbsent = attRecord?['status'] == 'absent';
    final String checkInTime = (attRecord?['check_in_at'] ?? '').toString();

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isPresent) {
      statusColor = const Color(0xFF10B981);
      statusText = checkInTime.isNotEmpty
          ? 'حضر الطالب هذه الحصة ✅ (تم تسجيل الحضور $checkInTime)'
          : 'حضر الطالب هذه الحصة ✅';
      statusIcon = Icons.check_circle_rounded;
    } else if (isAbsent) {
      statusColor = const Color(0xFFEF4444);
      statusText = 'غائب عن هذه الحصة ❌ (تنبيه: مراجعة الشرح والواجب)';
      statusIcon = Icons.cancel_rounded;
    } else {
      statusColor = const Color(0xFF38BDF8);
      statusText = 'حصة مشروحة في المقرر 📖';
      statusIcon = Icons.menu_book_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPresent
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : (isAbsent
                  ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                  : const Color(0xFF334155)),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. رقم وتاريخ الحصة
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'حصة #$lessonNumber  •  $date',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF00F2FE),
                  ),
                ),
              ),
              if (pdfUrl.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.picture_as_pdf_rounded, size: 12, color: Color(0xFF10B981)),
                      SizedBox(width: 4),
                      Text(
                        'مذكرة PDF مرفقة',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // 2. عنوان الدرس
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w900,
              fontSize: 15.5,
              color: AppTheme.textLight,
            ),
          ),

          const SizedBox(height: 10),

          // 3. شارة حضور الطالب
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 4. الواجب إن وجد
          if (homework.toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.edit_note_rounded, color: Color(0xFFF59E0B), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'الواجب والتكليفات المطلوبة:',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          homework,
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppTheme.textLight),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 5. الملاحظات إن وجدت
          if (notes.toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'ملاحظة: $notes',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textMuted),
            ),
          ],

          // 6. زر عرض مذكرة الحصة (PDF)
          if (pdfUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFF00F2FE),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFF00F2FE), width: 1.2),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: Text(
                  pdfSize.isNotEmpty ? 'عرض وتحميل مذكرة الحصة ($pdfSize) 📥' : 'عرض وتحميل مذكرة الحصة (PDF) 📥',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 13),
                ),
                onPressed: () => _openPdf(context, pdfUrl, pdfTitle),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic>? _findAttendanceForDate(List<Map<String, dynamic>> attendances, String date) {
    if (date.isEmpty) return null;
    final cleanTarget = date.trim();
    for (final a in attendances) {
      final aDate = (a['attendance_date'] ?? a['session_date'] ?? '').toString().trim();
      if (aDate == cleanTarget || (aDate.length >= 10 && cleanTarget.length >= 10 && aDate.substring(0, 10) == cleanTarget.substring(0, 10))) {
        return a;
      }
    }
    return null;
  }
}
