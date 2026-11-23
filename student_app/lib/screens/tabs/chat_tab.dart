import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/student_auth_service.dart';
import '../../services/student_communication_service.dart';
import '../../services/student_notification_sound_service.dart';
import '../../theme/app_theme.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _service = StudentCommunicationService.instance;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showEmojiPicker = false;
  String _selectedEmojiCategory = '😃 وجوه';

  static const List<String> _quickReplies = [
    'السلام عليكم يا أستاذ ✋',
    'عندي استفسار عن واجب الحصة ❓',
    'أعتذر عن حضور حصة اليوم لظرف طارئ ⚠️',
    'شكراً جزيلاً لحضرتك 🌸',
    'تم الانتهاء من المذاكرة بنجاح 🎯',
  ];

  static const List<String> _quickEmojis = [
    '👍', '❤️', '🔥', '🎉', '👏', '⭐', '😂', '🧠', '📚', '💯', '🤝', '💡', '❓', '🌸', '🚀', '✍️', '🙏', '✨', '💪', '✅'
  ];

  static const Map<String, List<String>> _categorizedEmojis = {
    '😃 وجوه': [
      '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
      '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😋', '😛', '😜',
      '🤪', '😎', '🤓', '🧐', '🥳', '🤩', '😏', '😒', '😞', '😔',
      '😟', '😕', '🙁', '😣', '😖', '😫', '😩', '🥺', '😢', '😭',
      '😤', '😠', '😡', '🤬', '🤯', '😳', '🥵', '🥶', '😱', '😨',
      '😰', '😥', '😓', '🤔', '🤭', '🤫', '🤥', '😶', '😐', '😑',
    ],
    '👍 تفاعلات': [
      '👍', '👎', '👏', '🙌', '👐', '🤲', '🤝', '🙏', '✍️', '💪',
      '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👆', '👇', '☝️',
      '✋', '🤚', '🖐️', '🖖', '👋', '👊', '✊', '🤛', '🤜', '👌',
    ],
    '📚 دراسة': [
      '📚', '📖', '📕', '📗', '📘', '📙', '📓', '📒', '📃', '📜',
      '📝', '✏️', '✒️', '🖋️', '🖊️', '🖍️', '📐', '📏', '📎', '📌',
      '📍', '🔬', '🔭', '🧪', '🧫', '🧬', '💡', '🧠', '🎓', '🏫',
      '🎒', '💻', '🖥️', '📊', '📈', '📉', '🏆', '🥇', '🥈', '🥉',
      '🎯', '⏳', '⏰', '⏱️', '🔔', '📣', '📢', '🔍', '🔎', '✨',
    ],
    '🔥 حماس': [
      '🔥', '💯', '⭐', '🌟', '✨', '💥', '⚡', '🚀', '🎉', '🎊',
      '🎈', '🎁', '🏆', '💎', '👑', '🥇', '💪', '🎯', '❤️', '🧡',
      '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💖', '💗', '💓',
    ],
    '💡 أفكار': [
      '💡', '❓', '❔', '❗️', '❕', '⚠️', '🚨', '🛑', '⛔️', '⭕️',
      '❌', '✅', '☑️', '✔️', '➕', '➖', '➗', '✖️', '💬', '💭',
      '🗨️', '📢', '🔔', '🔕', '📌', '📍', '🏷️', '🔒', '🔓', '🔑',
    ],
  };

  @override
  void initState() {
    super.initState();
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    if (studentId.isNotEmpty) {
      _service.markConversationReadByStudent(studentId);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _insertEmoji(String emoji) {
    HapticFeedback.selectionClick();
    final text = _textController.text;
    final selection = _textController.selection;
    if (selection.isValid && selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, emoji);
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + emoji.length),
      );
    } else {
      _textController.text = text + emoji;
      _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
    }
  }

  void _backspace() {
    HapticFeedback.selectionClick();
    final text = _textController.text;
    if (text.isEmpty) return;
    final characters = text.characters;
    if (characters.isNotEmpty) {
      _textController.text = characters.skipLast(1).toString();
      _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
    }
  }

  bool _isOnlyEmojis(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return false;
    final chars = clean.characters;
    if (chars.length > 4) return false;
    final hasAlphaNum = RegExp(r'[a-zA-Z0-9\u0600-\u06FF]').hasMatch(clean);
    return !hasAlphaNum;
  }

  void _sendMessage([String? quickText]) async {
    final text = (quickText ?? _textController.text).trim();
    if (text.isEmpty) return;

    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    final studentName = student?['full_name'] ?? 'طالب';
    final studentCode = student?['student_code'] ?? studentId;

    if (studentId.isEmpty) return;

    if (quickText == null) {
      _textController.clear();
    }

    StudentNotificationSoundService.instance.playInAppFeedback(isMessage: true);

    await _service.sendMessageFromStudent(
      studentId: studentId,
      studentName: studentName,
      studentCode: studentCode,
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

  void _showBackgroundStatusInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF00F2FE), width: 1.2),
        ),
        title: const Row(
          children: [
            Text('🟢', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text(
              'استقبال الرسائل مثل WhatsApp',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تطبيق الطالب مجهز للعمل في الخلفية واستقبال رسائل المعلم وتنبيهات الحصص فوراً بصوت واهتزاز كامل حتى والتطبيق مغلق.',
              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💡 نصائح هامة لهواتف أندرويد:', style: TextStyle(color: Color(0xFF00F2FE), fontWeight: FontWeight.bold, fontSize: 12.5)),
                  SizedBox(height: 6),
                  Text('1. اسمح للإشعارات بالظهور كإشعارات منبثقة (Heads-up).', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('2. عيّن توفير طاقة البطارية للتطبيق على "غير مقيّد" (Unrestricted) حتى لا يوقفه النظام أثناء القفل.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F2FE),
              foregroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('فهمت ذلك 👍', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';

    return Column(
      children: [
        // Teacher Banner Info & Background Messaging Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            border: const Border(bottom: BorderSide(color: AppTheme.darkCardBorder)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                  border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.4)),
                ),
                child: const Center(
                  child: Text('👨‍🏫', style: TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'المعلم الأكاديمي 👨‍🏫',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textLight,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'مراسلة فورية مباشرة لمتابعة الدروس والواجبات',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _showBackgroundStatusInfo,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 3.5, backgroundColor: AppTheme.success),
                      SizedBox(width: 5),
                      Text(
                        'كـ WhatsApp ⚡',
                        style: TextStyle(fontSize: 10.5, color: AppTheme.success, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Messages List
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _service.streamMessages(studentId),
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
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppTheme.darkCard,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.darkCardBorder),
                        ),
                        child: const Icon(
                          Icons.forum_outlined,
                          size: 32,
                          color: Color(0xFF00F2FE),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'ابدأ محادثتك الخاصة مع المعلم الآن',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textLight,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'يمكنك إرسال استفساراتك أو إرسال عذر غياب مباشر للمعلم',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        textAlign: TextAlign.center,
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
                  final isMe = msg['sender'] == 'student';
                  final text = (msg['text'] ?? '').toString();
                  final ts = msg['created_at'];

                  String timeStr = '';
                  if (ts is Timestamp) {
                    final dt = ts.toDate();
                    timeStr = '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                  }

                  final onlyEmojis = _isOnlyEmojis(text);

                  // WhatsApp-like styling for emoji-only messages
                  if (onlyEmojis) {
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Text(
                              text,
                              style: const TextStyle(fontSize: 34),
                            ),
                            if (timeStr.isNotEmpty)
                              Text(
                                timeStr,
                                style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                              ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isMe
                            ? const Color(0xFF00B4D8)
                            : AppTheme.darkCard,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                          bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                        ),
                        border: isMe
                            ? null
                            : Border.all(color: AppTheme.darkCardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Text(
                            text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                          if (timeStr.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              timeStr,
                              style: TextStyle(
                                color: isMe ? Colors.white.withValues(alpha: 0.7) : Colors.grey.shade400,
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

        // Quick replies bar
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _quickReplies.length,
            separatorBuilder: (context, index) => const SizedBox(width: 6),
            itemBuilder: (context, idx) {
              final rep = _quickReplies[idx];
              return ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(rep, style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
                backgroundColor: AppTheme.darkCard,
                side: const BorderSide(color: AppTheme.darkCardBorder),
                onPressed: () => _sendMessage(rep),
              );
            },
          ),
        ),
        const SizedBox(height: 4),

        // Quick Emoji Strip Bar
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _quickEmojis.length,
            separatorBuilder: (context, index) => const SizedBox(width: 4),
            itemBuilder: (context, idx) {
              final em = _quickEmojis[idx];
              return InkWell(
                onTap: () => _insertEmoji(em),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Center(
                    child: Text(em, style: const TextStyle(fontSize: 18)),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),

        // Text input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(
            color: AppTheme.darkCard,
            border: Border(top: BorderSide(color: AppTheme.darkCardBorder)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'لوحة الإيموجي',
                  icon: Icon(
                    _showEmojiPicker ? Icons.keyboard_alt_rounded : Icons.emoji_emotions_outlined,
                    color: const Color(0xFF00F2FE),
                    size: 24,
                  ),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _showEmojiPicker = !_showEmojiPicker);
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    onTap: () {
                      if (_showEmojiPicker) {
                        setState(() => _showEmojiPicker = false);
                      }
                    },
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالتك أو استفسارك للمعلم...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF090D16),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppTheme.darkCardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Color(0xFF00F2FE), width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFF00B4D8),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    onPressed: () => _sendMessage(),
                  ),
                ),
              ],
            ),
          ),
        ),

        // In-App Emoji Picker Grid
        if (_showEmojiPicker) _buildEmojiPicker(),
      ],
    );
  }

  Widget _buildEmojiPicker() {
    final currentList = _categorizedEmojis[_selectedEmojiCategory] ?? [];

    return Container(
      height: 250,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF334155))),
      ),
      child: Column(
        children: [
          // Category selector & backspace
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF090D16),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _categorizedEmojis.keys.map((cat) {
                      final isSelected = cat == _selectedEmojiCategory;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedEmojiCategory = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF00F2FE).withValues(alpha: 0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF00F2FE) : Colors.transparent,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              cat,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? const Color(0xFF00F2FE) : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                IconButton(
                  tooltip: 'مسح',
                  icon: const Icon(Icons.backspace_outlined, color: Colors.amber, size: 20),
                  onPressed: _backspace,
                ),
              ],
            ),
          ),

          // Emoji Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: currentList.length,
              itemBuilder: (context, idx) {
                final em = currentList[idx];
                return InkWell(
                  onTap: () => _insertEmoji(em),
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: Text(
                      em,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
