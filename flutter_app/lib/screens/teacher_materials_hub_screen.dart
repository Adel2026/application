import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/academy_communication_service.dart';
import '../core/database/database_service.dart';
import '../models/group_model.dart';
import '../models/curriculum_model.dart';
import '../widgets/section_top_bar.dart';

/// 📚 شاشة مكتبة المذكرات وملفات الحصص (PDF) للمعلم
/// تتيح رفع مذكرات وملخصات الحصص والواجبات كملفات PDF ونشرها بضغطة واحدة لجميع هواتف الطلاب
class TeacherMaterialsHubScreen extends StatefulWidget {
  final DatabaseService database;
  final String? initialGroupId;

  const TeacherMaterialsHubScreen({
    super.key,
    required this.database,
    this.initialGroupId,
  });

  @override
  State<TeacherMaterialsHubScreen> createState() => _TeacherMaterialsHubScreenState();
}

class _TeacherMaterialsHubScreenState extends State<TeacherMaterialsHubScreen> {
  bool _isLoading = true;
  List<GroupModel> _groups = [];
  String _filterGroupId = 'all';

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    try {
      final groups = await widget.database.getGroups();
      _groups = groups;
      if (widget.initialGroupId != null && _groups.any((g) => g.id == widget.initialGroupId)) {
        _filterGroupId = widget.initialGroupId!;
      }
    } catch (e) {
      debugPrint('Error loading groups in materials hub: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF080C14) : const Color(0xFFF1F5F9),
        appBar: SectionTopBar(
          title: 'مكتبة المذكرات والملفات (PDF) 📚',
          icon: Icons.picture_as_pdf_rounded,
          onBack: () => Navigator.of(context).pop(),
          extraActions: [
            IconButton(
              tooltip: 'تحديث القائمة',
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00F2FE)),
              onPressed: () => setState(() {}),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF00F2FE),
          foregroundColor: const Color(0xFF080C14),
          icon: const Icon(Icons.upload_file_rounded, size: 22),
          label: const Text(
            'رفع مذكرة PDF جديدة',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 13.5),
          ),
          onPressed: () => _showUploadDialog(context),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)))
            : Column(
                children: [
                  // شريط التصفية والإحصائيات
                  _buildFilterHeader(isDark),

                  // قائمة الملفات المرفوعة لحظياً من فايربيز
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('academies')
                          .doc('default')
                          .collection('lesson_materials')
                          .orderBy('created_at', descending: true)
                          .limit(40)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)));
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'خطأ في جلب الملفات: ${snapshot.error}',
                              style: const TextStyle(fontFamily: 'Cairo', color: Colors.red),
                            ),
                          );
                        }

                        final allDocs = snapshot.data?.docs ?? [];
                        final filteredDocs = allDocs.where((doc) {
                          if (_filterGroupId == 'all') return true;
                          final gId = doc.data()['group_id']?.toString() ?? '';
                          return gId == _filterGroupId || gId == 'all';
                        }).toList();

                        if (filteredDocs.isEmpty) {
                          return _buildEmptyState(isDark);
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                          itemCount: filteredDocs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final doc = filteredDocs[index];
                            final data = doc.data();
                            return _buildMaterialCard(doc.id, data, isDark);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFilterHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list_rounded, color: Color(0xFF00F2FE), size: 20),
          const SizedBox(width: 8),
          const Text(
            'تصفية بالمجموعة:',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12.5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterGroupId,
                  isExpanded: true,
                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('جميع المجموعات الدراسية 🌐'),
                    ),
                    ..._groups.map(
                      (g) => DropdownMenuItem(
                        value: g.id,
                        child: Text(g.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _filterGroupId = val);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF00F2FE).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.picture_as_pdf_rounded, size: 54, color: Color(0xFF00F2FE)),
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد مذكرات أو ملفات مرفوعة بعد',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'يمكنك تصدير أي ملخص من Google NotebookLM كملف PDF ورفعه هنا فوراً ليظهر لجميع هواتف الطلاب.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF94A3B8), height: 1.5),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F2FE),
                foregroundColor: const Color(0xFF080C14),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text(
                'رفع أول مذكرة PDF 🚀',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              onPressed: () => _showUploadDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialCard(String docId, Map<String, dynamic> data, bool isDark) {
    final title = data['title'] ?? 'مذكرة دراسية';
    final groupName = data['group_name'] ?? 'عام لجميع الطلاب';
    final sessionTitle = data['session_title'] ?? '';
    final fileUrl = data['file_url'] ?? '';
    final fileSize = data['file_size'] ?? 'PDF';
    final description = data['description'] ?? '';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // شارة PDF حمراء فخمة
                Container(
                  width: 44,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFEF4444), size: 22),
                      Text(
                        'PDF',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFEF4444),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
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
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              groupName,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00F2FE),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            fileSize,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      if (sessionTitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.link_rounded, size: 14, color: Color(0xFFF59E0B)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'مرتبطة بحصة: $sessionTitle',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Color(0xFFF59E0B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // شريط أزرار الإجراءات السريعة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              border: Border(top: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00F2FE),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text(
                    'فتح ومعاينة',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _openFileUrl(fileUrl),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text(
                    'مشاركة الرابط',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    SharePlus.instance.share(
                      ShareParams(
                        text: '📚 مذكرة دراسية: $title\n🔗 رابط التحميل والقراءة المباشر:\n$fileUrl',
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'حذف المذكرة',
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                  onPressed: () => _confirmDelete(docId, title),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFileUrl(String url) async {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح الرابط: $e', style: const TextStyle(fontFamily: 'Cairo'))),
        );
      }
    }
  }

  Future<void> _confirmDelete(String docId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          title: const Text('تأكيد حذف المذكرة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text('هل أنت متأكد من حذف ($title)؟ لن يتمكن الطلاب من فتحها بعد الحذف.', style: const TextStyle(fontFamily: 'Cairo', color: Color(0xFFCBD5E1))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف نهائي', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('academies')
            .doc('default')
            .collection('lesson_materials')
            .doc(docId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حذف المذكرة بنجاح', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ أثناء الحذف: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showUploadDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UploadMaterialBottomSheet(
        database: widget.database,
        groups: _groups,
        initialGroupId: _filterGroupId != 'all' ? _filterGroupId : null,
      ),
    );
  }
}

/// نافذة رفع مذكرة أو ملف PDF جديد مع ربط بالحصة وإرسال إشعار
class _UploadMaterialBottomSheet extends StatefulWidget {
  final DatabaseService database;
  final List<GroupModel> groups;
  final String? initialGroupId;

  const _UploadMaterialBottomSheet({
    required this.database,
    required this.groups,
    this.initialGroupId,
  });

  @override
  State<_UploadMaterialBottomSheet> createState() => _UploadMaterialBottomSheetState();
}

class _UploadMaterialBottomSheetState extends State<_UploadMaterialBottomSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  String? _selectedGroupId;
  List<SessionLogModel> _sessions = [];
  String? _selectedSessionId;

  String? _pickedFilePath;
  String? _pickedFileName;
  int _pickedFileSize = 0;

  bool _isUploading = false;
  double _uploadProgress = 0.0;
  bool _notifyStudents = true;

  @override
  void initState() {
    super.initState();
    if (widget.groups.isNotEmpty) {
      _selectedGroupId = widget.initialGroupId ?? widget.groups.first.id;
      _loadSessionsForGroup();
    }
  }

  Future<void> _loadSessionsForGroup() async {
    if (_selectedGroupId == null) return;
    try {
      final all = await widget.database.getSessionLogs();
      if (mounted) {
        setState(() {
          _sessions = all.where((s) => s.groupId == _selectedGroupId).toList();
          _sessions.sort((a, b) => b.date.compareTo(a.date));
          _selectedSessionId = 'none';
        });
      }
    } catch (e) {
      debugPrint('Error loading sessions for upload dialog: $e');
    }
  }

  Future<void> _pickPdfFile() async {
    HapticFeedback.lightImpact();
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result.isNotEmpty && result.first.path != null) {
        final filePath = result.first.path!;
        final file = File(filePath);
        final fileSize = await file.length();
        final fileName = p.basename(filePath);

        setState(() {
          _pickedFilePath = filePath;
          _pickedFileName = fileName;
          _pickedFileSize = fileSize;
          if (_titleController.text.trim().isEmpty) {
            final nameWithoutExt = fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '').trim();
            _titleController.text = nameWithoutExt;
          }
        });
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _startUploadAndPublish() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال عنوان المذكرة أولاً', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.red),
      );
      return;
    }

    if (_pickedFilePath == null || !File(_pickedFilePath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار ملف الـ PDF أولاً', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.2;
    });

    try {
      // 1. رفع ملف الـ PDF إلى السحابة المباشرة (Catbox Direct CDN)
      String downloadUrl = '';
      final filePath = _pickedFilePath!;

      if (File(filePath).existsSync()) {
        try {
          final uri = Uri.parse('https://catbox.moe/user/api.php');
          final request = http.MultipartRequest('POST', uri);
          request.fields['reqtype'] = 'fileupload';
          request.files.add(await http.MultipartFile.fromPath('fileToUpload', filePath));

          final streamedResponse = await request.send();
          if (streamedResponse.statusCode == 200) {
            final respStr = await streamedResponse.stream.bytesToString();
            if (respStr.trim().startsWith('http')) {
              downloadUrl = respStr.trim();
            }
          }
        } catch (e) {
          debugPrint('Catbox upload error: $e');
        }

        // احتياطي لو كات بوكس تعذر
        if (downloadUrl.isEmpty) {
          try {
            final uri = Uri.parse('https://tmpfiles.org/api/v1/upload');
            final request = http.MultipartRequest('POST', uri);
            request.files.add(await http.MultipartFile.fromPath('file', filePath));
            final streamedResponse = await request.send();
            if (streamedResponse.statusCode == 200) {
              final respStr = await streamedResponse.stream.bytesToString();
              // extract url
              final match = RegExp(r'"url":"(https?:\\?/\\?/[^"]+)"').firstMatch(respStr);
              if (match != null) {
                var url = match.group(1)!.replaceAll(r'\/', '/');
                downloadUrl = url.replaceFirst('tmpfiles.org/', 'tmpfiles.org/dl/');
              }
            }
          } catch (e) {
            debugPrint('Tmpfiles fallback error: $e');
          }
        }
      }

      if (downloadUrl.isEmpty) {
        throw 'تعذر رفع الملف إلى السحابة. تأكد من اتصال الإنترنت وحاول مجدداً.';
      }

      setState(() => _uploadProgress = 0.7);

      // 2. تجميع البيانات وحفظها في Firestore
      final selectedGroup = widget.groups.firstWhere(
        (g) => g.id == _selectedGroupId,
        orElse: () => widget.groups.first,
      );

      final materialId = 'mat_${DateTime.now().millisecondsSinceEpoch}';
      final formattedSize = _formatFileSize(_pickedFileSize);

      String linkedSessionTitle = '';
      if (_selectedSessionId != null && _selectedSessionId != 'none') {
        final sess = _sessions.where((s) => (s.id != null ? '${s.id}' : s.date) == _selectedSessionId).firstOrNull;
        if (sess != null) {
          linkedSessionTitle = sess.lessonTitle.isNotEmpty ? sess.lessonTitle : 'حصة ${sess.date}';

          // تحديث الحصة نفسها برابط المذكرة مباشرة
          final docSessionId = sess.id != null ? '${sess.id}' : sess.date;
          try {
            await FirebaseFirestore.instance
                .collection('academies')
                .doc('default')
                .collection('sessions')
                .doc(docSessionId)
                .set({
              'pdf_url': downloadUrl,
              'pdf_title': title,
              'pdf_size': formattedSize,
              'has_pdf': true,
            }, SetOptions(merge: true));
          } catch (e) {
            debugPrint('Error linking PDF to session: $e');
          }
        }
      }

      final materialData = {
        'id': materialId,
        'title': title,
        'description': _descController.text.trim(),
        'group_id': selectedGroup.id,
        'group_name': selectedGroup.name,
        'grade': selectedGroup.grade,
        'session_id': _selectedSessionId != 'none' ? _selectedSessionId : null,
        'session_title': linkedSessionTitle,
        'file_url': downloadUrl,
        'file_name': _pickedFileName ?? 'document.pdf',
        'file_size': formattedSize,
        'file_type': 'pdf',
        'created_at': FieldValue.serverTimestamp(),
        'downloads_count': 0,
      };

      await FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('lesson_materials')
          .doc(materialId)
          .set(materialData);

      setState(() => _uploadProgress = 1.0);

      // 3. إرسال إشعار فوري لجميع هواتف الطلاب
      if (_notifyStudents) {
        try {
          await AcademyCommunicationService.instance.sendNotification(
            title: '📚 مذكرة دراسية جديدة (PDF): $title',
            body: 'قام المعلم برفع مذكرة وملخص جديد لمجموعة (${selectedGroup.name}). افتح التطبيق للقراءة والتحميل!',
            type: 'material',
            targetType: 'group',
            targetId: selectedGroup.id,
            targetName: selectedGroup.name,
          );
        } catch (e) {
          debugPrint('Error sending notification: $e');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم رفع ونشر المذكرة بنجاح لجميع هواتف الطلاب! 🚀', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء الرفع: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: (media.size.height * 0.88).clamp(500.0, 750.0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20, media.viewInsets.bottom + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // مقبض النافذة
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.upload_file_rounded, color: Color(0xFF00F2FE), size: 24),
                    SizedBox(width: 8),
                    Text(
                      'رفع مذكرة وملخص جديد (PDF)',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. زر اختيار ملف الـ PDF
                    InkWell(
                      onTap: _isUploading ? null : _pickPdfFile,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _pickedFilePath != null
                              ? const Color(0xFF10B981).withValues(alpha: 0.1)
                              : const Color(0xFF00F2FE).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _pickedFilePath != null ? const Color(0xFF10B981) : const Color(0xFF00F2FE),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _pickedFilePath != null ? const Color(0xFF10B981) : const Color(0xFF00F2FE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _pickedFilePath != null ? Icons.check_circle_rounded : Icons.picture_as_pdf_rounded,
                                color: const Color(0xFF080C14),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _pickedFileName ?? 'اضغط لاختيار ملف الـ PDF 📄',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _pickedFilePath != null
                                        ? 'الحجم: ${_formatFileSize(_pickedFileSize)} • جاهز للرفع'
                                        : 'يمكنك اختيار ملف PDF من جهازك أو مذكرات الدروس',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: _pickedFilePath != null ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 2. اختيار المجموعة المستهدفة
                    const Text('المجموعة الدراسية المستهدفة:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedGroupId,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: widget.groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedGroupId = val;
                            _loadSessionsForGroup();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // 3. ربط بحصة معينة (اختياري)
                    const Text('ربط بحصة دراسية معينة (اختياري):', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedSessionId,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'none',
                          child: Text('بدون ربط بحصة محددة (مذكرة عامة للمقرر) 🌐'),
                        ),
                        ..._sessions.map((s) {
                          final title = s.lessonTitle.isNotEmpty ? s.lessonTitle : 'حصة بتاريخ ${s.date}';
                          final sessionId = s.id != null ? '${s.id}' : s.date;
                          return DropdownMenuItem(
                            value: sessionId,
                            child: Text('📅 ${s.date} - $title', overflow: TextOverflow.ellipsis),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedSessionId = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // 4. عنوان المذكرة
                    const Text('عنوان المذكرة أو الملخص:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _titleController,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13.5, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'مثال: ملخص الدرس الأول - الحركة في خط مستقيم',
                        hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF64748B)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 5. الملاحظات أو تكليفات الواجب
                    const Text('ملاحظات أو توجيهات للطلاب (اختياري):', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _descController,
                      maxLines: 2,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'مثال: يرجى حل تمارين صفحة 4 بالمذكرة استعداداً لكويز الحصة القادمة...',
                        hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: Color(0xFF64748B)),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),

                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        '📢 إرسال إشعار فوري لجميع هواتف الطلاب في هذه المجموعة',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      value: _notifyStudents,
                      activeColor: const Color(0xFF00F2FE),
                      checkColor: const Color(0xFF080C14),
                      onChanged: (val) => setState(() => _notifyStudents = val ?? true),
                    ),
                  ],
                ),
              ),
            ),

            if (_isUploading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
                backgroundColor: const Color(0xFF1E293B),
                color: const Color(0xFF00F2FE),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'جاري رفع ملف الـ PDF ونشره لجميع هواتف الطلاب... ☁️',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: Color(0xFF00F2FE)),
                ),
              ),
              const SizedBox(height: 8),
            ],

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F2FE),
                  foregroundColor: const Color(0xFF080C14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 3,
                ),
                icon: _isUploading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF080C14)))
                    : const Icon(Icons.cloud_upload_rounded, size: 22),
                label: Text(
                  _isUploading ? 'جاري النشر...' : '🚀 رفع ونشر المذكرة للطلاب فوراً',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, fontSize: 14),
                ),
                onPressed: _isUploading ? null : _startUploadAndPublish,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
