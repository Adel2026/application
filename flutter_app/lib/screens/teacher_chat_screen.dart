import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/academy_communication_service.dart';
import '../core/chat_media_upload_service.dart';
import '../core/database/database_service.dart';

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
  final _imagePicker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();

  bool _isWriting = false;
  bool _showAssetsPanel = false;
  int _activeAssetTabIndex = 0; // 0: Emojis, 1: Stickers

  // Audio recording state
  bool _isRecording = false;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  String? _currentlyPlayingUrl;
  bool _isPlayingAudio = false;
  bool _isUploading = false;
  String _uploadStatus = '';

  static const List<String> _quickReplies = [
    'أهلاً بك يا بطل 🌟',
    'تم تسجيل عذرك المقبول ✅',
    'الواجب مطلوب الحصة القادمة 📝',
    'بالتوفيق والنجاح دائماً 🎯',
    'تم استلام رسالتك وسيتم مراجعتها 👍',
  ];

  static const List<String> _baseEmojis = [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
    '🙂', '😉', '😌', '😍', '🥰', '😘', '😋', '😜', '😎', '🤓',
    '🥳', '🤩', '👍', '👏', '🙌', '🤝', '🙏', '✍️', '💪', '🔥',
    '💯', '⭐', '🌟', '✨', '🎉', '🎁', '🏆', '🥇', '📚', '💡',
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🧠', '🎓', '🚀', '✅',
  ];

  static const List<String> _baseStickers = [
    'https://cdn-icons-png.flaticon.com/512/3135/3135715.png',
    'https://cdn-icons-png.flaticon.com/512/190/190411.png',
    'https://cdn-icons-png.flaticon.com/512/1828/1828884.png',
    'https://cdn-icons-png.flaticon.com/512/2583/2583344.png',
    'https://cdn-icons-png.flaticon.com/512/3208/3208726.png',
    'https://cdn-icons-png.flaticon.com/512/3135/3135789.png',
  ];

  @override
  void initState() {
    super.initState();
    _service.activeChatStudentId = widget.studentId;
    _service.markConversationReadByTeacher(widget.studentId);
    _textController.addListener(() {
      final isNowWriting = _textController.text.trim().isNotEmpty;
      if (isNowWriting != _isWriting) {
        setState(() => _isWriting = isNowWriting);
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlayingAudio = state == PlayerState.playing;
          if (state == PlayerState.completed || state == PlayerState.stopped) {
            _currentlyPlayingUrl = null;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    if (_service.activeChatStudentId == widget.studentId) {
      _service.activeChatStudentId = null;
    }
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _giveBonusPointsInChat() async {
    HapticFeedback.heavyImpact();
    final awarded = await DatabaseService.shared?.awardStudentPoints(
      studentId: widget.studentId,
      delta: 5,
      reason: 'نقاط تشجيع وتفوق من داخل المحادثة 🪙',
    ) ?? false;

    if (awarded) {
      _sendMessage('🎉 تم منحك +5 نقاط تشجيعية لتفاعلك المتميز! 🪙');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم منح ${widget.studentName} +5 نقاط تشجيعية! 🪙'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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

    _scrollToBottom();
  }

  void _scrollToBottom() {
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

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(source: source, imageQuality: 75);
      if (picked == null) return;

      setState(() {
        _isUploading = true;
        _uploadStatus = 'جاري رفع الصورة... 📷';
      });

      final url = await ChatMediaUploadService.uploadMediaFile(File(picked.path));
      if (url != null) {
        await _service.sendMessageFromTeacher(
          studentId: widget.studentId,
          studentName: widget.studentName,
          studentCode: widget.studentCode,
          text: '',
          mediaUrl: url,
          mediaType: 'image',
        );
        _scrollToBottom();
      } else {
        _showError('تعذر رفع الصورة. تحقق من اتصال الإنترنت.');
      }
    } catch (e) {
      _showError('خطأ أثناء اختيار الصورة: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty || files.first.path == null) return;

      final file = File(files.first.path!);
      final fileName = files.first.name;

      setState(() {
        _isUploading = true;
        _uploadStatus = 'جاري رفع الملف (${fileName})... 📎';
      });

      final url = await ChatMediaUploadService.uploadMediaFile(file);
      if (url != null) {
        await _service.sendMessageFromTeacher(
          studentId: widget.studentId,
          studentName: widget.studentName,
          studentCode: widget.studentCode,
          text: fileName,
          mediaUrl: url,
          mediaType: 'file',
          fileName: fileName,
        );
        _scrollToBottom();
      } else {
        _showError('تعذر رفع الملف. تحقق من اتصال الإنترنت.');
      }
    } catch (e) {
      _showError('خطأ أثناء اختيار الملف: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );

        HapticFeedback.heavyImpact();
        setState(() {
          _isRecording = true;
          _recordingDuration = 0;
        });

        _recordingTimer?.cancel();
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (mounted) setState(() => _recordingDuration++);
        });
      } else {
        _showError('يرجى منح إذن الميكروفون للتسجيل الصوتي');
      }
    } catch (e) {
      _showError('تعذر بدء التسجيل الصوتي: $e');
    }
  }

  Future<void> _stopAndSendRecording() async {
    _recordingTimer?.cancel();
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);

      if (path != null && _recordingDuration >= 1) {
        final audioFile = File(path);
        if (await audioFile.exists()) {
          setState(() {
            _isUploading = true;
            _uploadStatus = 'جاري إرسال التسجيل الصوتي... 🎤';
          });

          final url = await ChatMediaUploadService.uploadMediaFile(audioFile);
          if (url != null) {
            await _service.sendMessageFromTeacher(
              studentId: widget.studentId,
              studentName: widget.studentName,
              studentCode: widget.studentCode,
              text: 'تسجيل صوتي (${_recordingDuration} ث)',
              mediaUrl: url,
              mediaType: 'audio',
            );
            _scrollToBottom();
          } else {
            _showError('تعذر رفع التسجيل الصوتي.');
          }
        }
      }
    } catch (e) {
      _showError('خطأ في إرسال الصوت: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    await _audioRecorder.stop();
    setState(() => _isRecording = false);
  }

  Future<void> _toggleAudioPlay(String url) async {
    try {
      if (_currentlyPlayingUrl == url && _isPlayingAudio) {
        await _audioPlayer.pause();
        setState(() => _isPlayingAudio = false);
      } else {
        await _audioPlayer.stop();
        await _audioPlayer.play(UrlSource(url));
        setState(() {
          _currentlyPlayingUrl = url;
          _isPlayingAudio = true;
        });
      }
    } catch (e) {
      _showError('تعذر تشغيل الصوت: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700, behavior: SnackBarBehavior.floating),
    );
  }

  void _showAddAssetDialog(String type) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          type == 'sticker' ? 'إضافة رابط ملصق جديد 🖼️' : 'إضافة إيموجي مخصص 😊',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
        ),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: type == 'sticker' ? 'أدخل رابط صورة الملصق (URL)' : 'أدخل الرمز التعبيري',
            hintStyle: const TextStyle(color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00A884)),
            onPressed: () async {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                await _service.addChatAsset(type: type, value: val);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تمت إضافة العنصر ومزامنته للطلاب بنجاح! 🚀')),
                );
              }
            },
            child: const Text('إضافة وحفظ', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const waHeaderColor = Color(0xFF008069);
    const waBubbleMe = Color(0xFFD9FDD3);
    const waCheckBlue = Color(0xFF53BDEB);

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        backgroundColor: waHeaderColor,
        elevation: 1,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.studentName,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text('كود: ${widget.studentCode}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('طالب / ولي أمر 🛡️', style: TextStyle(fontSize: 9.5, color: Colors.amber, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'منح 5 نقاط تشجيعية 🪙',
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add, size: 14, color: Colors.black),
                  Text('5 🪙', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
                ],
              ),
            ),
            onPressed: _giveBonusPointsInChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: const Color(0xFF111B21),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _quickReplies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                return ActionChip(
                  label: Text(_quickReplies[i], style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  backgroundColor: const Color(0xFF1F2C34),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onPressed: () => _sendMessage(_quickReplies[i]),
                );
              },
            ),
          ),
          if (_isUploading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              color: const Color(0xFF00A884),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_uploadStatus, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _service.streamMessages(widget.studentId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)));
                }

                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 55, color: Colors.white.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        const Text(
                          'لا توجد رسائل سابقة مع هذا الطالب',
                          style: TextStyle(color: Colors.white60, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender'] == 'teacher';
                    final text = (msg['text'] ?? '').toString();
                    final mediaUrl = (msg['media_url'] ?? '').toString();
                    final mediaType = (msg['media_type'] ?? '').toString();
                    final fileName = (msg['file_name'] ?? 'مستند مرفق').toString();
                    final isSticker = mediaType == 'sticker' || (text.startsWith('http') && (text.endsWith('.png') || text.endsWith('.jpg') || text.endsWith('.webp')));
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
                        child: _buildMessageContent(
                          isMe: isMe,
                          text: text,
                          mediaUrl: mediaUrl,
                          mediaType: mediaType,
                          fileName: fileName,
                          isSticker: isSticker,
                          timeStr: timeStr,
                          waCheckBlue: waCheckBlue,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_showAssetsPanel) _buildAssetsPanel(),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            color: const Color(0xFF111B21),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2C34),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: _isRecording
                        ? Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: _cancelRecording,
                              ),
                              const Icon(Icons.mic, color: Colors.redAccent, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'تسجيل صوتي: ${_recordingDuration}s',
                                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              const Text('حرّك للإلغاء', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              const SizedBox(width: 8),
                            ],
                          )
                        : Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  _showAssetsPanel ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
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
                                  style: const TextStyle(color: Colors.white, fontSize: 14.5),
                                  minLines: 1,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    hintText: 'مراسلة الطالب أو ولي الأمر...',
                                    hintStyle: TextStyle(color: Color(0xFF8696A0), fontSize: 14),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                  ),
                                ),
                              ),
                              if (!_isWriting) ...[
                                IconButton(
                                  icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF8696A0), size: 22),
                                  onPressed: _pickAndSendFile,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFF8696A0), size: 22),
                                  onPressed: () => _pickAndSendImage(ImageSource.camera),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.photo_library_rounded, color: Color(0xFF8696A0), size: 22),
                                  onPressed: () => _pickAndSendImage(ImageSource.gallery),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    if (_isWriting) {
                      _sendMessage();
                    } else if (_isRecording) {
                      _stopAndSendRecording();
                    } else {
                      _startRecording();
                    }
                  },
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _isRecording ? Colors.redAccent : const Color(0xFF00A884),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isWriting
                          ? Icons.send_rounded
                          : (_isRecording ? Icons.stop_rounded : Icons.mic_rounded),
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

  Widget _buildMessageContent({
    required bool isMe,
    required String text,
    required String mediaUrl,
    required String mediaType,
    required String fileName,
    required bool isSticker,
    required String timeStr,
    required Color waCheckBlue,
  }) {
    if (isSticker) {
      return Image.network(
        mediaUrl.isNotEmpty ? mediaUrl : text,
        width: 120,
        height: 120,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50, color: Colors.grey),
      );
    }

    if (mediaType == 'image' && mediaUrl.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: GestureDetector(
              onTap: () => launchUrl(Uri.parse(mediaUrl), mode: LaunchMode.externalApplication),
              child: Image.network(
                mediaUrl,
                width: 220,
                height: 200,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: 220,
                    height: 150,
                    color: Colors.black26,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00A884)),
                  );
                },
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 60, color: Colors.grey),
              ),
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(text, style: TextStyle(color: isMe ? Colors.black87 : Colors.white, fontSize: 13.5)),
          ],
          _buildTimeAndStatus(isMe, timeStr, waCheckBlue),
        ],
      );
    }

    if (mediaType == 'audio' && mediaUrl.isNotEmpty) {
      final isPlayingThis = _currentlyPlayingUrl == mediaUrl && _isPlayingAudio;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(isPlayingThis ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 38),
                color: isMe ? const Color(0xFF008069) : const Color(0xFF00A884),
                onPressed: () => _toggleAudioPlay(mediaUrl),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تسجيل صوتي 🎤', style: TextStyle(color: isMe ? Colors.black87 : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(text, style: TextStyle(color: isMe ? Colors.black54 : Colors.white60, fontSize: 10.5)),
                ],
              ),
            ],
          ),
          _buildTimeAndStatus(isMe, timeStr, waCheckBlue),
        ],
      );
    }

    if (mediaType == 'file' && mediaUrl.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => launchUrl(Uri.parse(mediaUrl), mode: LaunchMode.externalApplication),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isMe ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file_rounded, size: 32, color: Colors.amber),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: TextStyle(color: isMe ? Colors.black87 : Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text('انقر لفتح الملف 📥', style: TextStyle(color: Color(0xFF00A884), fontSize: 10.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildTimeAndStatus(isMe, timeStr, waCheckBlue),
        ],
      );
    }

    return Wrap(
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
        _buildTimeAndStatus(isMe, timeStr, waCheckBlue),
      ],
    );
  }

  Widget _buildTimeAndStatus(bool isMe, String timeStr, Color waCheckBlue) {
    return Row(
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
          Icon(Icons.done_all, size: 14, color: waCheckBlue),
        ],
      ],
    );
  }

  Widget _buildAssetsPanel() {
    return Container(
      height: 220,
      color: const Color(0xFF1E293B),
      child: Column(
        children: [
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
                  label: const Text('ملصقات 🖼️', style: TextStyle(fontSize: 11)),
                  selected: _activeAssetTabIndex == 1,
                  onSelected: (val) => setState(() => _activeAssetTabIndex = 1),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF00A884)),
                  label: Text(
                    _activeAssetTabIndex == 0 ? '+ إيموجي' : '+ ملصق',
                    style: const TextStyle(color: Color(0xFF00A884), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _showAddAssetDialog(_activeAssetTabIndex == 0 ? 'emoji' : 'sticker'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<Map<String, dynamic>>(
              stream: _service.streamChatAssets(),
              builder: (context, snapshot) {
                final data = snapshot.data ?? {};
                final customList = (_activeAssetTabIndex == 0
                        ? (data['custom_emojis'] as List<dynamic>?)
                        : (data['custom_stickers'] as List<dynamic>?)) ??
                    [];

                final customValues = customList
                    .map((e) => (e is Map ? e['value'] : e).toString())
                    .where((s) => s.isNotEmpty)
                    .toList();

                final allItems = _activeAssetTabIndex == 0
                    ? [..._baseEmojis, ...customValues]
                    : [..._baseStickers, ...customValues];

                return GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _activeAssetTabIndex == 0 ? 8 : 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: allItems.length,
                  itemBuilder: (context, i) {
                    final item = allItems[i];
                    if (_activeAssetTabIndex == 0) {
                      return InkWell(
                        onTap: () {
                          _textController.text += item;
                          setState(() => _isWriting = true);
                        },
                        child: Center(child: Text(item, style: const TextStyle(fontSize: 22))),
                      );
                    } else {
                      return InkWell(
                        onTap: () {
                          _sendMessage(item);
                          setState(() => _showAssetsPanel = false);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Image.network(
                            item,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 24, color: Colors.grey),
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
