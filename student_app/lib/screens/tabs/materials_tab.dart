import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/student_auth_service.dart';
import '../../services/student_data_service.dart';
import '../../theme/app_theme.dart';
import '../smart_pdf_viewer_screen.dart';

/// 📚 قسم مكتبة المذكرات والملخصات الذكية (مستقل تماماً عن قسم الحصص)
class MaterialsTab extends StatefulWidget {
  const MaterialsTab({super.key});

  @override
  State<MaterialsTab> createState() => _MaterialsTabState();
}

class _MaterialsTabState extends State<MaterialsTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final Set<String> _cachedMaterialIds = {};
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _checkCachedFiles();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {
          _searchQuery = val.trim();
        });
      }
    });
  }

  Future<void> _checkCachedFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final files = appDir.listSync();
      final cachedIds = <String>{};
      for (final f in files) {
        if (f is File && f.path.contains('pdf_cache_')) {
          final fileName = f.path.split(Platform.pathSeparator).last;
          final id = fileName.replaceFirst('pdf_cache_', '').replaceFirst('.pdf', '');
          cachedIds.add(id);
        }
      }
      if (mounted) {
        setState(() {
          _cachedMaterialIds.clear();
          _cachedMaterialIds.addAll(cachedIds);
        });
      }
    } catch (_) {}
  }

  void _openPdfViewer(Map<String, dynamic> material) {
    HapticFeedback.mediumImpact();
    final docId = material['doc_id'] ?? material['id'] ?? '';
    final title = material['title'] ?? 'مذكرة دراسية';
    final fileUrl = material['file_url'] ?? '';

    if (fileUrl.toString().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ رابط المذكرة غير متاح حالياً، يرجى مراجعة المعلم',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SmartPdfViewerScreen(
          materialId: docId,
          title: title,
          fileUrl: fileUrl,
          groupName: material['group_name'],
          description: material['description'],
        ),
      ),
    ).then((_) {
      _checkCachedFiles();
    });
  }

  Future<void> _openExternal(String fileUrl) async {
    if (fileUrl.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    try {
      final uri = Uri.parse(fileUrl.trim());
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر الفتح خارجياً: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final groupId = student?['group_id'];

    return RefreshIndicator(
      color: const Color(0xFF00F2FE),
      onRefresh: () async {
        await _checkCachedFiles();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Header Banner
          _buildHeaderBanner(),
          const SizedBox(height: 14),

          // 2. Search Field
          _buildSearchBox(),
          const SizedBox(height: 14),

          // 3. Materials Stream from Firebase
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: StudentDataService.instance.streamLessonMaterials(groupId: groupId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: Color(0xFF00F2FE)),
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'خطأ في تحميل المذكرات: ${snapshot.error}',
                      style: const TextStyle(fontFamily: 'Cairo', color: AppTheme.danger),
                    ),
                  ),
                );
              }

              final materials = snapshot.data ?? [];
              final filtered = materials.where((m) {
                if (_searchQuery.isEmpty) return true;
                final title = (m['title'] ?? '').toString().toLowerCase();
                final desc = (m['description'] ?? '').toString().toLowerCase();
                final session = (m['session_title'] ?? '').toString().toLowerCase();
                final q = _searchQuery.toLowerCase();
                return title.contains(q) || desc.contains(q) || session.contains(q);
              }).toList();

              if (filtered.isEmpty) {
                return _buildEmptyState();
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final mat = filtered[idx];
                  return _buildMaterialCard(mat);
                },
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00F2FE).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
              border: Border.all(color: const Color(0xFF00F2FE), width: 1.5),
            ),
            child: const Center(
              child: Text(
                '📚',
                style: TextStyle(fontSize: 26),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مكتبة المذكرات والملخصات الذكية',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textLight,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'مذكرات PDF ومراجعات مؤمنة بعلامة مائية مع ميزة المذاكرة بدون إنترنت 🔒',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.darkCardBorder),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: 'ابحث في المذكرات أو الملخصات أو المراجعات...',
          hintStyle: const TextStyle(fontFamily: 'Cairo', color: AppTheme.textMuted, fontSize: 12.5),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00F2FE), size: 22),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 20),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildMaterialCard(Map<String, dynamic> material) {
    final docId = material['doc_id'] ?? material['id'] ?? '';
    final sanitizedId = docId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final isCached = _cachedMaterialIds.contains(sanitizedId);

    final title = material['title'] ?? 'مذكرة دراسية';
    final groupName = material['group_name'] ?? 'عام لجميع الطلاب';
    final sessionTitle = material['session_title'] ?? '';
    final fileSize = material['file_size'] ?? 'PDF';
    final description = material['description'] ?? '';

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCached
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : AppTheme.darkCardBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openPdfViewer(material),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // PDF Badge icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                      ),
                      child: const Center(
                        child: Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFEF4444), size: 28),
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
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00F2FE).withValues(alpha: 0.1),
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
                              if (sessionTitle.toString().isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFA855F7).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    sessionTitle,
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFA855F7),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (description.toString().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: AppTheme.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF1E293B), height: 1),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isCached ? Icons.offline_pin_rounded : Icons.cloud_done_rounded,
                          size: 16,
                          color: isCached ? const Color(0xFF10B981) : const Color(0xFF00F2FE),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isCached ? 'محفوظ للمذاكرة أوفلاين' : 'حجم الملف: $fileSize',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isCached ? const Color(0xFF10B981) : AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00F2FE),
                            side: const BorderSide(color: Color(0xFF00F2FE)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 14),
                          label: const Text(
                            'خارجي ⚡',
                            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                          onPressed: () => _openExternal(material['file_url'] ?? ''),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00F2FE),
                            foregroundColor: const Color(0xFF080C14),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.menu_book_rounded, size: 15),
                          label: const Text(
                            'قراءة 📖',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: () => _openPdfViewer(material),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF00F2FE).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.picture_as_pdf_rounded, size: 52, color: Color(0xFF00F2FE)),
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد مذكرات أو ملخصات منشورة حالياً',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppTheme.textLight,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'المذكرات والمراجعات التي ينشرها المعلم ستظهر هنا فورياً لتتمكن من فتحها ومذاكرتها بأمان.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: AppTheme.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
