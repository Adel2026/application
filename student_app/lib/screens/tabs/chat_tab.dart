import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/student_auth_service.dart';
import '../../services/student_communication_service.dart';
import '../../services/student_notification_sound_service.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _service = StudentCommunicationService.instance;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isWriting = false;
  bool _showAssetsPanel = false;
  int _activeAssetTabIndex = 0; // 0: Emojis, 1: Stickers

  static const List<String> _quickReplies = [
    'السلام عليكم يا أستاذ ✋',
    'عندي استفسار عن واجب الحصة ❓',
    'أعتذر عن حضور حصة اليوم لظرف طارئ ⚠️',
    'شكراً جزيلاً لحضرتك 🌸',
    'تم الانتهاء من المذاكرة بنجاح 🎯',
  ];

  static const List<String> _baseEmojis = [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
    '🙂', '😉', '😌', '😍', '🥰', '😘', '😋', '😜', '😎', '🤓',
    '🥳', '🤩', '👍', '👏', '🙌', '🤝', '🙏', '✍️', '💪', '🔥',
    '💯', '⭐', '🌟', '✨', '🎉', '🎁', '🏆', '🥇', '📚', '💡',
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🧠', '🎓', '🚀', '✅',
  ];

  static const List<String> _baseStickers = [
    'https://cdn-icons-png.flaticon.com/512/3135/3135715.png', // Certificate/Grad
    'https://cdn-icons-png.flaticon.com/512/190/190411.png',   // Star trophy
    'https://cdn-icons-png.flaticon.com/512/1828/1828884.png', // 100 points
    'https://cdn-icons-png.flaticon.com/512/2583/2583344.png', // Gold Medal
    'https://cdn-icons-png.flaticon.com/512/3208/3208726.png', // Fire rocket
    'https://cdn-icons-png.flaticon.com/512/3135/3135789.png', // Thumbs up
  ];

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      final isNowWriting = _textController.text.trim().isNotEmpty;
      if (isNowWriting != _isWriting) {
        setState(() => _isWriting = isNowWriting);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentId = student?['id'] ?? '';
    final isParent = StudentAuthService.instance.isParent;

    const waHeaderColor = Color(0xFF008069);
    const waBubbleMe = Color(0xFFD9FDD3);
    const waCheckBlue = Color(0xFF53BDEB);

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        backgroundColor: waHeaderColor,
        elevation: 1,
        titleSpacing: 0,
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.school_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'مستر عادل - سنتر الأوائل 🎓',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      const Text('متصل الآن عبر السحابة', style: TextStyle(fontSize: 11, color: Colors.white70)),
                      if (isParent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('حساب ولي أمر 🛡️', style: TextStyle(fontSize: 9.5, color: Colors.amber, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Quick replies row
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: const Color(0xFF111B21),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _quickReplies.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                return ActionChip(
                  label: Text(_quickReplies[i], style: const TextStyle(fontSize: 11, color: Color(0xFFE9EDEF))),
                  backgroundColor: const Color(0xFF202C33),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onPressed: () => _sendMessage(_quickReplies[i]),
                );
              },
            ),
          ),

          // Messages list
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _service.streamMessages(studentId),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'لا توجد رسائل سابقة. ابدأ محادثتك مع المعلم الآن 💬',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender'] == 'student';
                    final text = (msg['text'] ?? '').toString();
                    final isSticker = text.startsWith('http') && (text.endsWith('.png') || text.endsWith('.jpg') || text.endsWith('.webp'));
                    final ts = msg['created_at'];
                    String timeStr = '';
                    if (ts is Timestamp) {
                      final dt = ts.toDate();
                      timeStr = '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                    }

                    return Align(
                      alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                        padding: isSticker
                            ? const EdgeInsets.all(4)
                            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSticker
                              ? Colors.transparent
                              : (isMe ? waBubbleMe : const Color(0xFF202C33)),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: isMe ? const Radius.circular(2) : const Radius.circular(12),
                            bottomRight: isMe ? const Radius.circular(12) : const Radius.circular(2),
                          ),
                          boxShadow: isSticker
                              ? null
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                        ),
                        child: isSticker
                            ? Image.network(text, width: 120, height: 120, fit: BoxFit.contain)
                            : Wrap(
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.end,
                                children: [
                                  Text(
                                    text,
                                    style: TextStyle(
                                      color: isMe ? Colors.black87 : Colors.white,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        timeStr,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isMe ? Colors.black54 : Colors.white60,
                                        ),
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 3),
                                        const Icon(Icons.done_all, size: 14, color: waCheckBlue),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Emoji & Stickers Panel (Toggleable)
          if (_showAssetsPanel) _buildAssetsPanel(),

          // WhatsApp Style Input Bar
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            color: const Color(0xFF111B21),
            child: Row(
              children: [
                // White Capsule Bar
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF202C33),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _showAssetsPanel ? Icons.keyboard_alt_rounded : Icons.emoji_emotions_outlined,
                            color: const Color(0xFF8696A0),
                            size: 24,
                          ),
                          onPressed: () {
                            setState(() => _showAssetsPanel = !_showAssetsPanel);
                          },
                        ),
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: isParent ? 'مراسلة المعلم (حساب ولي الأمر)...' : 'مراسلة المعلم...',
                              hintStyle: const TextStyle(color: Color(0xFF8696A0), fontSize: 14),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                            ),
                          ),
                        ),
                        if (!_isWriting) ...[
                          IconButton(
                            icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF8696A0), size: 22),
                            onPressed: () => _sendMessage('مرفق واجب/سؤال 📎'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFF8696A0), size: 22),
                            onPressed: () => _sendMessage('صورة الواجب 📷'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Green Circle Button (Send or Mic)
                GestureDetector(
                  onTap: () {
                    if (_isWriting) {
                      _sendMessage();
                    } else {
                      _sendMessage('تسجيل صوتي 🎤');
                    }
                  },
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00A884),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isWriting ? Icons.send_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetsPanel() {
    return Container(
      height: 220,
      color: const Color(0xFF1E293B),
      child: Column(
        children: [
          // Header Toggle: إيموجي | ملصقات
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: const Color(0xFF0F172A),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('إيموجي 😊', style: TextStyle(fontSize: 11)),
                  selected: _activeAssetTabIndex == 0,
                  onSelected: (val) => setState(() => _activeAssetTabIndex = 0),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('ملصقات السنتر 🖼️', style: TextStyle(fontSize: 11)),
                  selected: _activeAssetTabIndex == 1,
                  onSelected: (val) => setState(() => _activeAssetTabIndex = 1),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: StreamBuilder<Map<String, dynamic>>(
              stream: _service.streamChatAssets(),
              builder: (context, snapshot) {
                final cloudData = snapshot.data ?? {};
                final customEmojis = (cloudData['custom_emojis'] as List?)?.map((e) => e['value'].toString()).toList() ?? [];
                final customStickers = (cloudData['custom_stickers'] as List?)?.map((e) => e['value'].toString()).toList() ?? [];

                if (_activeAssetTabIndex == 0) {
                  final allEmojis = [...customEmojis, ..._baseEmojis];
                  return GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: allEmojis.length,
                    itemBuilder: (context, i) {
                      return InkWell(
                        onTap: () {
                          _textController.text += allEmojis[i];
                          _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
                        },
                        child: Center(
                          child: Text(allEmojis[i], style: const TextStyle(fontSize: 24)),
                        ),
                      );
                    },
                  );
                } else {
                  final allStickers = [...customStickers, ..._baseStickers];
                  return GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: allStickers.length,
                    itemBuilder: (context, i) {
                      return InkWell(
                        onTap: () => _sendMessage(allStickers[i]),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Image.network(allStickers[i], fit: BoxFit.contain),
                        ),
                      );
                    },
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
