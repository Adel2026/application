import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../services/student_auth_service.dart';
import '../theme/app_theme.dart';

/// أدوات المذاكرة التفاعلية داخل شاشة الـ PDF
enum StudyTool {
  pan, // تصفح وتكبير سريع
  pen, // قلم كتابة وتخطيط
  highlighter, // هايلايتر تظليل شفاف
  eraser, // ممحاة ذكية بلمس الخط
}

/// تمثيل الخط المرسوم مع صندوق الإحاطة لحسابات التصادم السريعة (0ms Collision)
class DrawnStroke {
  final Color color;
  final double strokeWidth;
  final bool isHighlighter;
  final List<Offset> points;
  late final Rect bounds;

  DrawnStroke({
    required this.color,
    required this.strokeWidth,
    required this.isHighlighter,
    required this.points,
  }) {
    _calculateBounds();
  }

  void _calculateBounds() {
    if (points.isEmpty) {
      bounds = Rect.zero;
      return;
    }
    double minX = points.first.dx;
    double maxX = points.first.dx;
    double minY = points.first.dy;
    double maxY = points.first.dy;

    for (int i = 1; i < points.length; i++) {
      final p = points[i];
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Map<String, dynamic> toJson() => {
    'c': color.toARGB32(),
    'w': strokeWidth,
    'h': isHighlighter,
    'pts': points.map((p) => [p.dx, p.dy]).toList(),
  };

  factory DrawnStroke.fromJson(Map<String, dynamic> json) {
    final ptsList = json['pts'] as List? ?? [];
    final points = ptsList.map((pt) {
      final list = pt as List;
      return Offset((list[0] as num).toDouble(), (list[1] as num).toDouble());
    }).toList();

    return DrawnStroke(
      color: Color(json['c'] as int),
      strokeWidth: (json['w'] as num).toDouble(),
      isHighlighter: json['h'] as bool? ?? false,
      points: points,
    );
  }
}

/// 📖 قارئ مذكرات الـ PDF فائق السرعة والمزود بأدوات المذاكرة الذكية
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

  // --- 🎨 نظام المذاكرة والتخطيط الذكي ---
  bool _isStudySuiteEnabled = true;
  StudyTool _activeTool = StudyTool.pan;
  bool _isToolbarCollapsed = false;

  Color _penColor = const Color(0xFF0284C7); // أزرق دراسي
  Color _highlighterColor = const Color(0xFFFFEA00); // أصفر فسفوري

  // تخزين الخطوط لكل صفحة
  final Map<int, List<DrawnStroke>> _pageStrokes = {};
  DrawnStroke? _currentActiveStroke;
  Offset? _eraserCurrentPoint;

  // ألوان القلم المتاحة
  final List<Color> _penColors = [
    const Color(0xFF0284C7), // أزرق
    const Color(0xFFEF4444), // أحمر تركيز
    const Color(0xFF10B981), // أخضر تصحيح
    const Color(0xFF8B5CF6), // بنفسجي مميز
    const Color(0xFF0F172A), // أسود حبر
  ];

  // ألوان الهايلايتر المتاحة
  final List<Color> _highlighterColors = [
    const Color(0xFFFFEA00), // أصفر نيون
    const Color(0xFF00E676), // أخضر فسفوري
    const Color(0xFFFF6D00), // برتقالي ناري
    const Color(0xFF00F2FE), // سماوي مشع
  ];

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _ensureCleanWindow();
    _loadSavedNotes();
    _preparePdfFile();
  }

  @override
  void dispose() {
    _saveNotesToDisk();
    _searchController.dispose();
    _pdfController.dispose();
    super.dispose();
  }

  Future<void> _ensureCleanWindow() async {
    try {
      await _securityChannel.invokeMethod('disableSecureWindow');
    } catch (_) {}
  }

  // --- حفظ واسترجاع التخطيطات من الذاكرة المحلية ---
  Future<void> _loadSavedNotes() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sanitizedId = widget.materialId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final notesFile = File('${appDir.path}/pdf_notes_$sanitizedId.json');

      if (await notesFile.exists()) {
        final content = await notesFile.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);

        data.forEach((pageKey, strokesList) {
          final pageNum = int.tryParse(pageKey);
          if (pageNum != null && strokesList is List) {
            _pageStrokes[pageNum] = strokesList
                .map((s) => DrawnStroke.fromJson(s as Map<String, dynamic>))
                .toList();
          }
        });
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading pdf notes: $e');
    }
  }

  Future<void> _saveNotesToDisk() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sanitizedId = widget.materialId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final notesFile = File('${appDir.path}/pdf_notes_$sanitizedId.json');

      final Map<String, dynamic> exportData = {};
      _pageStrokes.forEach((pageNum, strokes) {
        if (strokes.isNotEmpty) {
          exportData['$pageNum'] = strokes.map((s) => s.toJson()).toList();
        }
      });

      await notesFile.writeAsString(jsonEncode(exportData));
    } catch (e) {
      debugPrint('Error saving pdf notes: $e');
    }
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
          _errorMessage = 'تعذر فتح الملف: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _saveReadingProgress(int pageNumber) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pdf_progress_${widget.materialId}', pageNumber);
    } catch (_) {}
  }

  // --- حسابات مسح الخط عند لمسه (Smart Stroke Eraser Collision) ---
  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lengthSq = dx * dx + dy * dy;
    if (lengthSq == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lengthSq).clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - proj).distance;
  }

  void _handleEraserAt(Offset point) {
    final strokes = _pageStrokes[_currentPage];
    if (strokes == null || strokes.isEmpty) return;

    const double eraserRadius = 32.0;
    bool erasedAny = false;

    for (int i = strokes.length - 1; i >= 0; i--) {
      final stroke = strokes[i];
      // فحص سريع بصندوق الإحاطة (Bounding Box O(1))
      if (!stroke.bounds.inflate(eraserRadius).contains(point)) continue;

      // فحص تصادم دقيق مع نقاط الخط
      bool collided = false;
      if (stroke.points.length <= 2) {
        if ((stroke.points.first - point).distance <= eraserRadius) collided = true;
      } else {
        for (int j = 0; j < stroke.points.length - 1; j++) {
          if (_distanceToSegment(point, stroke.points[j], stroke.points[j + 1]) <= eraserRadius) {
            collided = true;
            break;
          }
        }
      }

      if (collided) {
        strokes.removeAt(i);
        erasedAny = true;
      }
    }

    if (erasedAny) {
      HapticFeedback.selectionClick();
      setState(() {});
    }
  }

  void _undoLastStroke() {
    final strokes = _pageStrokes[_currentPage];
    if (strokes != null && strokes.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        strokes.removeLast();
      });
      _saveNotesToDisk();
    }
  }

  void _clearPageNotes() {
    final strokes = _pageStrokes[_currentPage];
    if (strokes == null || strokes.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'مسح تخطيطات الصفحة؟',
          style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'هل تريد مسح جميع الملاحظات والخطوط والتظليلات من هذه الصفحة فقط؟',
          style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.mediumImpact();
              setState(() {
                _pageStrokes[_currentPage]?.clear();
              });
              _saveNotesToDisk();
            },
            child: const Text('مسح الكل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _jumpToPageDialog() {
    if (_totalPages <= 1) return;
    int target = _currentPage;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
            // زر إظهار/إخفاء أدوات المذاكرة والقلم
            IconButton(
              tooltip: _isStudySuiteEnabled ? 'إخفاء أدوات القلم' : 'إظهار أدوات القلم والتخطيط',
              icon: Icon(
                _isStudySuiteEnabled ? Icons.brush_rounded : Icons.brush_outlined,
                color: _isStudySuiteEnabled ? const Color(0xFF00F2FE) : Colors.white70,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _isStudySuiteEnabled = !_isStudySuiteEnabled;
                  if (!_isStudySuiteEnabled) {
                    _activeTool = StudyTool.pan;
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
            else ...[
              // 1. عارض الـ PDF الأصلي السريع
              _buildCleanPdfViewer(),

              // 2. طبقة الرسم والتظليل والممحاة التفاعلية الفورية (Vector Overlay بتقنية Raw Pointer Events)
              if (_isStudySuiteEnabled)
                _buildDrawingLayer(),

              // 3. شريط أدوات المذاكرة العائم (Floating Studio Toolbar)
              if (_isStudySuiteEnabled)
                _buildFloatingStudyToolbar(),
            ],

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

  /// طبقة الرسم التفاعلية فائقة الحساسية (Raw Pointer Events 0ms Latency)
  Widget _buildDrawingLayer() {
    final isInteractive = _activeTool != StudyTool.pan;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !isInteractive,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            final localPos = event.localPosition;

            if (_activeTool == StudyTool.eraser) {
              setState(() {
                _eraserCurrentPoint = localPos;
              });
              _handleEraserAt(localPos);
            } else if (_activeTool == StudyTool.pen || _activeTool == StudyTool.highlighter) {
              final isHigh = _activeTool == StudyTool.highlighter;
              final color = isHigh ? _highlighterColor : _penColor;
              final width = isHigh ? 24.0 : 3.0;

              // إضافة النقطة مرتين لرسم النقطة أو التحديد الفوري عند اللمس بـ 0ms
              _currentActiveStroke = DrawnStroke(
                color: color,
                strokeWidth: width,
                isHighlighter: isHigh,
                points: [localPos, localPos],
              );
              setState(() {});
            }
          },
          onPointerMove: (event) {
            final localPos = event.localPosition;

            if (_activeTool == StudyTool.eraser) {
              setState(() {
                _eraserCurrentPoint = localPos;
              });
              _handleEraserAt(localPos);
            } else if (_currentActiveStroke != null) {
              setState(() {
                _currentActiveStroke!.points.add(localPos);
              });
            }
          },
          onPointerUp: (event) {
            if (_activeTool == StudyTool.eraser) {
              setState(() {
                _eraserCurrentPoint = null;
              });
              _saveNotesToDisk();
            } else if (_currentActiveStroke != null) {
              _currentActiveStroke!._calculateBounds();
              _pageStrokes.putIfAbsent(_currentPage, () => []);
              _pageStrokes[_currentPage]!.add(_currentActiveStroke!);
              _currentActiveStroke = null;
              setState(() {});
              _saveNotesToDisk();
            }
          },
          onPointerCancel: (_) {
            if (_activeTool == StudyTool.eraser) {
              setState(() {
                _eraserCurrentPoint = null;
              });
            } else if (_currentActiveStroke != null) {
              _currentActiveStroke!._calculateBounds();
              _pageStrokes.putIfAbsent(_currentPage, () => []);
              _pageStrokes[_currentPage]!.add(_currentActiveStroke!);
              _currentActiveStroke = null;
              setState(() {});
            }
          },
          child: CustomPaint(
            painter: _NotesPainter(
              strokes: _pageStrokes[_currentPage] ?? [],
              activeStroke: _currentActiveStroke,
              eraserPoint: _eraserCurrentPoint,
            ),
          ),
        ),
      ),
    );
  }

  /// شريط أدوات المذاكرة العائم (Floating Studio Toolbar)
  Widget _buildFloatingStudyToolbar() {
    if (_isToolbarCollapsed) {
      return Positioned(
        top: 14,
        left: 14,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _isToolbarCollapsed = false);
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF00F2FE), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00F2FE).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              _activeTool == StudyTool.pen
                  ? Icons.edit_rounded
                  : _activeTool == StudyTool.highlighter
                      ? Icons.border_color_rounded
                      : _activeTool == StudyTool.eraser
                          ? Icons.cleaning_services_rounded
                          : Icons.pan_tool_rounded,
              color: const Color(0xFF00F2FE),
              size: 20,
            ),
          ),
        ),
      );
    }

    return Positioned(
      top: 14,
      left: 14,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF334155)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✋ وضع التصفح والتكبير (افتراضي سريع 100%)
            _buildToolItem(
              tool: StudyTool.pan,
              icon: Icons.pan_tool_rounded,
              label: 'تصفح',
              isSelected: _activeTool == StudyTool.pan,
            ),
            const SizedBox(width: 4),

            // ✏️ قلم الكتابة
            _buildToolItem(
              tool: StudyTool.pen,
              icon: Icons.edit_rounded,
              label: 'قلم',
              isSelected: _activeTool == StudyTool.pen,
              badgeColor: _penColor,
            ),
            const SizedBox(width: 4),

            // 🖍️ الهايلايتر الشفاف
            _buildToolItem(
              tool: StudyTool.highlighter,
              icon: Icons.border_color_rounded,
              label: 'تظليل',
              isSelected: _activeTool == StudyTool.highlighter,
              badgeColor: _highlighterColor,
            ),
            const SizedBox(width: 4),

            // 🧼 الممحاة الذكية الموجهة باللمس
            _buildToolItem(
              tool: StudyTool.eraser,
              icon: Icons.cleaning_services_rounded,
              label: 'أستيكة',
              isSelected: _activeTool == StudyTool.eraser,
            ),
            const SizedBox(width: 6),
            Container(width: 1, height: 24, color: const Color(0xFF334155)),
            const SizedBox(width: 6),

            // زر الألوان المنبثق السريع
            if (_activeTool == StudyTool.pen || _activeTool == StudyTool.highlighter) ...[
              GestureDetector(
                onTap: _showColorPickerSheet,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _activeTool == StudyTool.pen ? _penColor : _highlighterColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],

            // ↩️ تراجع عن آخر خط
            IconButton(
              icon: const Icon(Icons.undo_rounded, size: 18, color: Colors.white70),
              tooltip: 'تراجع',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              onPressed: _undoLastStroke,
            ),

            // 🗑️ مسح كل خطوط الصفحة
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, size: 18, color: Color(0xFFEF4444)),
              tooltip: 'مسح تخطيطات الصفحة',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              onPressed: _clearPageNotes,
            ),

            // زر تصغير الشريط
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white38),
              tooltip: 'تصغير الشريط',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              onPressed: () {
                setState(() => _isToolbarCollapsed = true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolItem({
    required StudyTool tool,
    required IconData icon,
    required String label,
    required bool isSelected,
    Color? badgeColor,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _activeTool = tool;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00F2FE).withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF00F2FE) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF00F2FE) : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isSelected ? const Color(0xFF00F2FE) : Colors.white70,
              ),
            ),
            if (badgeColor != null) ...[
              const SizedBox(width: 4),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showColorPickerSheet() {
    final isPen = _activeTool == StudyTool.pen;
    final colors = isPen ? _penColors : _highlighterColors;
    final currentColor = isPen ? _penColor : _highlighterColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPen ? 'اختر لون القلم ✏️' : 'اختر لون التظليل 🖍️',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: colors.map((c) {
                  final isSelected = c.toARGB32() == currentColor.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (isPen) {
                          _penColor = c;
                        } else {
                          _highlighterColor = c;
                        }
                      });
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? const Color(0xFF00F2FE) : Colors.white30,
                          width: isSelected ? 3.5 : 1.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: c.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
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
                fontWeight: FontWeight.w900,
                color: AppTheme.textLight,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'يتم حفظ المذكرة داخل التطبيق لتتمكن من مذاكرتها في أي وقت بدون إنترنت ⚡',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                minHeight: 8,
                backgroundColor: const Color(0xFF1E293B),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00F2FE)),
              ),
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
            const Icon(Icons.error_outline_rounded, size: 54, color: AppTheme.danger),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'حدث خطأ أثناء تحميل الملف',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                color: AppTheme.danger,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
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
      canShowScrollHead: false,
      canShowScrollStatus: true,
      enableDoubleTapZooming: true,
      enableTextSelection: _activeTool == StudyTool.pan,
      pageSpacing: 8,
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

/// راسم الخطوط والتظليلات والممحاة الفوري (Ultra-Fast 60fps Painter)
class _NotesPainter extends CustomPainter {
  final List<DrawnStroke> strokes;
  final DrawnStroke? activeStroke;
  final Offset? eraserPoint;

  _NotesPainter({
    required this.strokes,
    this.activeStroke,
    this.eraserPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. رسم الخطوط المحفوظة
    for (final stroke in strokes) {
      _paintSingleStroke(canvas, stroke);
    }

    // 2. رسم الخط الجاري رسمه لحظياً
    if (activeStroke != null) {
      _paintSingleStroke(canvas, activeStroke!);
    }

    // 3. رسم دائرة الممحاة الذكية أثناء المسح
    if (eraserPoint != null) {
      final eraserPaint = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      final eraserBorder = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(eraserPoint!, 32.0, eraserPaint);
      canvas.drawCircle(eraserPoint!, 32.0, eraserBorder);
    }
  }

  void _paintSingleStroke(Canvas canvas, DrawnStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.isHighlighter
          ? stroke.color.withValues(alpha: 0.38)
          : stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = stroke.isHighlighter ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = stroke.isHighlighter ? StrokeJoin.miter : StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (stroke.points.length == 1) {
      canvas.drawCircle(stroke.points.first, stroke.strokeWidth / 2, paint..style = PaintingStyle.fill);
      return;
    }

    final path = Path()..moveTo(stroke.points[0].dx, stroke.points[0].dy);
    if (stroke.points.length == 2) {
      path.lineTo(stroke.points[1].dx, stroke.points[1].dy);
    } else {
      for (int i = 1; i < stroke.points.length - 1; i++) {
        final p0 = stroke.points[i];
        final p1 = stroke.points[i + 1];
        final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
        path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
      }
      path.lineTo(stroke.points.last.dx, stroke.points.last.dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _NotesPainter oldDelegate) => true;
}
