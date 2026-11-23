import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/student_auth_service.dart';
import '../theme/app_theme.dart';

/// 📖 قارئ مذكرات الـ PDF فائق السرعة والخفيف كلياً
class SmartPdfViewerScreen extends StatefulWidget {
  final String materialId;
  final String title;
  final String fileUrl;
  final String? groupName;
  final String? description;

  const SmartPdfViewerScreen({
    super.key,
    required this.materialId,
    required this.title,
    required this.fileUrl,
    this.groupName,
    this.description,
  });

  @override
  State<SmartPdfViewerScreen> createState() => _SmartPdfViewerScreenState();
}

class _SmartPdfViewerScreenState extends State<SmartPdfViewerScreen> {
  static const _securityChannel = MethodChannel('com.eduacademy/security');

  late final PdfViewerController _pdfController;
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();

  bool _isLoadingFile = true;
  double _downloadProgress = 0.0;
  String? _localFilePath;
  String? _errorMessage;

  int _currentPage = 1;
  int _totalPages = 0;
  bool _isSearchActive = false;
  final TextEditingController _searchController = TextEditingController();
  PdfTextSearchResult? _searchResult;

  int? _savedLastPage;
  bool _hasRestoredPage = false;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _ensureCleanWindow();
    _preparePdfFile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pdfController.dispose();
    super.dispose();
  }

  Future<void> _ensureCleanWindow() async {
    try {
      await _securityChannel.invokeMethod('disableSecureWindow');
    } catch (_) {}
  }

  Future<void> _preparePdfFile() async {
    if (!mounted) return;
    setState(() {
      _isLoadingFile = true;
      _errorMessage = null;
      _downloadProgress = 0.0;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _savedLastPage = prefs.getInt('pdf_progress_${widget.materialId}');

      final appDir = await getApplicationDocumentsDirectory();
      final sanitizedId = widget.materialId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final localFile = File('${appDir.path}/pdf_cache_$sanitizedId.pdf');

      if (await localFile.exists() && await localFile.length() > 1000) {
        if (mounted) {
          setState(() {
            _localFilePath = localFile.path;
            _isLoadingFile = false;
          });
        }
        return;
      }

      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(widget.fileUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('فشل الاتصال بالسيرفر (كود: ${response.statusCode})');
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;
      final fileSink = localFile.openWrite();

      await for (final chunk in response) {
        fileSink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && mounted) {
          setState(() {
            _downloadProgress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          });
        }
      }

      await fileSink.flush();
      await fileSink.close();

      if (mounted) {
        setState(() {
          _localFilePath = localFile.path;
          _isLoadingFile = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFile = false;
          _errorMessage = 'تعذر تحميل ملف المذكرة: $e';
        });
      }
    }
  }

  Future<void> _saveReadingProgress(int page) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pdf_progress_${widget.materialId}', page);
    } catch (_) {}
  }

  /// ⚡ فتح المذكرة مباشرة بالقارئ الخارجي فائق السرعة
  Future<void> _openInNativeViewer() async {
    HapticFeedback.lightImpact();
    try {
      if (_localFilePath != null && await File(_localFilePath!).exists()) {
        final uri = Uri.file(_localFilePath!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return;
        }
      }
      final webUri = Uri.parse(widget.fileUrl);
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر فتح القارئ الخارجي: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _jumpToPageDialog() {
    if (_totalPages <= 1) return;
    int target = _currentPage;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'انتقال إلى صفحة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textLight,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'صفحة $target من $_totalPages',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00F2FE),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF00F2FE),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: const Color(0xFF00F2FE),
                      overlayColor: const Color(0xFF00F2FE).withValues(alpha: 0.2),
                      valueIndicatorColor: const Color(0xFF0F172A),
                    ),
                    child: Slider(
                      value: target.toDouble(),
                      min: 1.0,
                      max: _totalPages.toDouble(),
                      divisions: _totalPages > 1 ? _totalPages - 1 : 1,
                      label: '$target',
                      onChanged: (val) {
                        setModalState(() {
                          target = val.round();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00F2FE),
                        foregroundColor: const Color(0xFF080C14),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _pdfController.jumpToPage(target);
                      },
                      child: const Text(
                        'انتقل الآن 📖',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
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

  @override
  Widget build(BuildContext context) {
    final student = StudentAuthService.instance.currentStudent;
    final studentName = student?['full_name'] ?? student?['name'] ?? 'طالب الأكاديمية';
    final studentCode = student?['student_code'] ?? student?['code'] ?? '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B132B),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          elevation: 2,
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textLight, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: AppTheme.textLight,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (_totalPages > 0)
                GestureDetector(
                  onTap: _jumpToPageDialog,
                  child: Row(
                    children: [
                      Text(
                        'صفحة $_currentPage من $_totalPages • اضغط للانتقال',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: Color(0xFF00F2FE),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.touch_app_rounded, size: 12, color: Color(0xFF00F2FE)),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            // زر الفتح بالقارئ الخارجي السريع
            IconButton(
              tooltip: 'فتح بالقارئ الخارجي فائق السرعة ⚡',
              icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF00F2FE)),
              onPressed: _openInNativeViewer,
            ),
            // زر التكبير
            IconButton(
              tooltip: 'تكبير (+)',
              icon: const Icon(Icons.zoom_in_rounded, color: Colors.white70),
              onPressed: () {
                _pdfController.zoomLevel = (_pdfController.zoomLevel + 0.35).clamp(1.0, 3.5);
              },
            ),
            // زر التصغير
            IconButton(
              tooltip: 'تصغير (-)',
              icon: const Icon(Icons.zoom_out_rounded, color: Colors.white70),
              onPressed: () {
                _pdfController.zoomLevel = (_pdfController.zoomLevel - 0.35).clamp(1.0, 3.5);
              },
            ),
            // زر البحث
            IconButton(
              tooltip: 'بحث داخل المذكرة',
              icon: Icon(
                _isSearchActive ? Icons.search_off_rounded : Icons.search_rounded,
                color: _isSearchActive ? const Color(0xFF00F2FE) : Colors.white70,
              ),
              onPressed: () {
                setState(() {
                  _isSearchActive = !_isSearchActive;
                  if (!_isSearchActive) {
                    _searchResult?.clear();
                    _searchController.clear();
                  }
                });
              },
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomStatusBar(studentName, studentCode),
        body: Stack(
          children: [
            if (_isLoadingFile)
              _buildLoadingState()
            else if (_errorMessage != null)
              _buildErrorState()
            else
              _buildCleanPdfViewer(),

            // شريط البحث المنسدل عند التفعيل
            if (_isSearchActive)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildSearchBar(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCleanPdfViewer() {
    return SfPdfViewer.file(
      File(_localFilePath!),
      key: _pdfViewerKey,
      controller: _pdfController,
      canShowScrollHead: true,
      canShowScrollStatus: true,
      enableDoubleTapZooming: true,
      enableTextSelection: true,
      pageSpacing: 4,
      onDocumentLoaded: (PdfDocumentLoadedDetails details) {
        if (!mounted) return;
        setState(() {
          _totalPages = details.document.pages.count;
        });

        // استعادة آخر صفحة
        if (!_hasRestoredPage && _savedLastPage != null && _savedLastPage! > 1) {
          _hasRestoredPage = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_savedLastPage! <= _totalPages) {
              _pdfController.jumpToPage(_savedLastPage!);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'مرحباً بك! تم استئناف المذاكرة من صفحة $_savedLastPage 📖',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: const Color(0xFF00F2FE),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          });
        }
      },
      onPageChanged: (PdfPageChangedDetails details) {
        if (!mounted) return;
        setState(() {
          _currentPage = details.newPageNumber;
        });
        _saveReadingProgress(details.newPageNumber);
      },
    );
  }

  Widget _buildBottomStatusBar(String studentName, String studentCode) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFF0F172A),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: Color(0xFF00F2FE), size: 14),
              const SizedBox(width: 6),
              Text(
                '$studentName ($studentCode)',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Row(
            children: [
              InkWell(
                onTap: _openInNativeViewer,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.launch_rounded, size: 12, color: Color(0xFF00F2FE)),
                      SizedBox(width: 4),
                      Text(
                        'فتح خارجي',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          color: Color(0xFF00F2FE),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (_totalPages > 0)
                GestureDetector(
                  onTap: _jumpToPageDialog,
                  child: Text(
                    '$_currentPage / $_totalPages 📄',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: Color(0xFF00F2FE),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    final percent = (_downloadProgress * 100).toInt();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.picture_as_pdf_rounded, size: 48, color: Color(0xFF00F2FE)),
            ),
            const SizedBox(height: 20),
            Text(
              'جارٍ تحضير المذكرة... $percent%',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                color: AppTheme.textLight,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                backgroundColor: Colors.white12,
                color: const Color(0xFF00F2FE),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00F2FE),
                side: const BorderSide(color: Color(0xFF00F2FE)),
              ),
              icon: const Icon(Icons.open_in_browser_rounded, size: 16),
              label: const Text('فتح مباشرة في المتصفح / القارئ الخارجي ⚡', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
              onPressed: _openInNativeViewer,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 52, color: AppTheme.danger),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'حدث خطأ أثناء فتح الملف',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                color: AppTheme.danger,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F2FE),
                    foregroundColor: const Color(0xFF080C14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة 🔄', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  onPressed: _preparePdfFile,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('فتح خارجي ⚡', style: TextStyle(fontFamily: 'Cairo')),
                  onPressed: _openInNativeViewer,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
              decoration: InputDecoration(
                hintText: 'ابحث عن كلمة أو موضوع...',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00F2FE)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          _searchResult?.clear();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  _searchResult = _pdfController.searchText(val);
                  setState(() {});
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.arrow_upward_rounded, color: Color(0xFF00F2FE)),
            tooltip: 'السابق',
            onPressed: () => _searchResult?.previousInstance(),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward_rounded, color: Color(0xFF00F2FE)),
            tooltip: 'التالي',
            onPressed: () => _searchResult?.nextInstance(),
          ),
        ],
      ),
    );
  }
}
