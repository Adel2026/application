import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/academy_communication_service.dart';

class TeacherChatScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String studentCode;

  const TeacherChatScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.studentCode,
  });

  @override
  State<TeacherChatScreen> createState() => _TeacherChatScreenState();
}

class _TeacherChatScreenState extends State<TeacherChatScreen> {
  final _service = AcademyCommunicationService.instance;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  static const List<String> _quickReplies = [
    'أهلاً بك يا بطل 🌟',
    'تم تسجيل عذرك المقبول ✅',
    'الواجب مطلوب الحصة القادمة 📝',
    'بالتوفيق والنجاح دائماً 🎯',
    'تم استلام رسالتك وسيتم مراجعتها 👍',
  ];

  @override
  void initState() {
    super.initState();
    _service.activeChatStudentId = widget.studentId;
    _service.markConversationReadByTeacher(widget.studentId);
  }

  @override
  void dispose() {
    if (_service.activeChatStudentId == widget.studentId) {
      _service.activeChatStudentId = null;
    }
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage([String? quickText]) async {
    final text = (quickText ?? _textController.text).trim();
    if (text.isEmpty) return;

    if (quickText == null) {
      _textController.clear();
    }

    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}

    await _service.sendMessageFromTeacher(
      studentId: widget.studentId,
      studentName: widget.studentName,
      studentCode: widget.studentCode,
      text: text,
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFF00B4D8);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: primaryColor.withValues(alpha: 0.2),
              child: const Icon(Icons.school_rounded, color: Color(0xFF00B4D8), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.studentName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'كود: ${widget.studentCode}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _service.streamMessages(widget.studentId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mark_chat_unread_outlined, size: 54, color: Colors.grey.shade500),
                        const SizedBox(height: 10),
                        Text(
                          'لا توجد رسائل سابقة مع ${widget.studentName}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'اكتب رسالة أو اختر رد سريع لبدء المحادثة',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender'] == 'teacher';
                    final text = msg['text'] ?? '';
                    final ts = msg['created_at'];
                    String timeStr = '';
                    if (ts is Timestamp) {
                      final dt = ts.toDate();
                      timeStr = '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                    }

                    return Align(
                      alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe
                              ? primaryColor
                              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: isMe ? const Radius.circular(4) : const Radius.circular(16),
                            bottomRight: isMe ? const Radius.circular(16) : const Radius.circular(4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                          children: [
                            Text(
                              text,
                              style: TextStyle(
                                color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                fontSize: 14,
                                height: 1.35,
                              ),
                            ),
                            if (timeStr.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                timeStr,
                                style: TextStyle(
                                  color: isMe ? Colors.white.withValues(alpha: 0.7) : Colors.grey,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Quick replies
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _quickReplies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final rep = _quickReplies[idx];
                return ActionChip(
                  label: Text(rep, style: const TextStyle(fontSize: 11)),
                  backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  onPressed: () => _sendMessage(rep),
                );
              },
            ),
          ),
          const SizedBox(height: 6),

          // Input bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالتك للطالب...',
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: primaryColor,
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: () => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
