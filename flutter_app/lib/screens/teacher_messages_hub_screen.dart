import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/academy_communication_service.dart';
import '../core/database/database_service.dart';
import 'teacher_chat_screen.dart';

class TeacherMessagesHubScreen extends StatefulWidget {
  final DatabaseService database;

  const TeacherMessagesHubScreen({super.key, required this.database});

  @override
  State<TeacherMessagesHubScreen> createState() => _TeacherMessagesHubScreenState();
}

class _TeacherMessagesHubScreenState extends State<TeacherMessagesHubScreen> {
  final _service = AcademyCommunicationService.instance;
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      final db = await widget.database.database;
      final rows = await db.query('students', columns: ['id', 'full_name', 'grade']);
      if (mounted) {
        setState(() => _students = rows);
      }
    } catch (_) {}
  }

  void _openNewChatDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final filtered = _students.where((s) {
              final name = (s['full_name'] ?? '').toString().toLowerCase();
              final id = (s['id'] ?? '').toString().toLowerCase();
              return name.contains(query.toLowerCase()) || id.contains(query.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.chat_rounded, color: Color(0xFF00B4D8)),
                      const SizedBox(width: 10),
                      const Text(
                        'بدء محادثة جديدة مع طالب',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو الكود...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => setModalState(() => query = val),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final s = filtered[idx];
                        final id = '${s['id']}';
                        final name = '${s['full_name']}';
                        final code = id.replaceAll(RegExp(r'\D'), '');

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF00B4D8).withValues(alpha: 0.2),
                            child: const Icon(Icons.person_outline_rounded, color: Color(0xFF00B4D8)),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('كود: ${code.isNotEmpty ? code : id}'),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TeacherChatScreen(
                                  studentId: id,
                                  studentName: name,
                                  studentCode: code.isNotEmpty ? code : id,
                                ),
                              ),
                            );
                          },
                        );
                      },
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مراسلات الطلاب 💬'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF00B4D8),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_comment_rounded),
        label: const Text('محادثة جديدة', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _openNewChatDialog,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _service.streamConversations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final conversations = snapshot.data ?? [];
          if (conversations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.forum_outlined, size: 64, color: Colors.grey.shade500),
                  const SizedBox(height: 12),
                  const Text(
                    'لا توجد محادثات نشطة حالياً',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'عندما يرسل طالب رسالة أو تبدأ محادثة جديدة، ستظهر هنا فوراً',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(14).copyWith(bottom: 80),
            itemCount: conversations.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final conv = conversations[index];
              final studentId = conv['student_id'] ?? '';
              final studentName = conv['student_name'] ?? 'طالب';
              final studentCode = conv['student_code'] ?? studentId;
              final lastMsg = conv['last_message'] ?? '';
              final unread = (conv['unread_teacher'] as num? ?? 0).toInt();
              final lastSender = conv['last_sender'] ?? '';
              final ts = conv['last_message_time'];
              String timeStr = '';
              if (ts is Timestamp) {
                final dt = ts.toDate();
                timeStr = '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
              }

              return Card(
                elevation: 0,
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: unread > 0
                        ? const Color(0xFF00B4D8)
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    width: unread > 0 ? 1.5 : 1,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF00B4D8).withValues(alpha: 0.15),
                        child: const Icon(Icons.school_rounded, color: Color(0xFF00B4D8), size: 24),
                      ),
                      if (unread > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          studentName,
                          style: TextStyle(
                            fontWeight: unread > 0 ? FontWeight.w900 : FontWeight.bold,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: unread > 0 ? const Color(0xFF00B4D8) : Colors.grey,
                            fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Row(
                    children: [
                      if (lastSender == 'teacher')
                        const Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF00B4D8)),
                      if (lastSender == 'teacher') const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          lastMsg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unread > 0 ? (isDark ? Colors.white : Colors.black87) : Colors.grey,
                            fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeacherChatScreen(
                          studentId: studentId,
                          studentName: studentName,
                          studentCode: studentCode,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
