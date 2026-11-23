import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Interactive circular image cropper & avatar editor.
/// Allows zooming in/out, panning in all directions, rotating,
/// micro-adjusting with ultra-high precision nudges, viewing real-time certificate preview,
/// and cropping with 100% pixel-perfect accuracy without any overflow.
class CircularImageCropper {
  /// Opens the circular cropper screen and returns the cropped [File], or null if canceled.
  static Future<File?> cropImage(
    BuildContext context, {
    required String imagePath,
    String title = 'تعديل وقص الصورة',
    double outputSize = 1000.0,
    bool isBottomSeal = false,
  }) async {
    return Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => CircularImageCropperScreen(
          imagePath: imagePath,
          title: title,
          outputSize: outputSize,
          isBottomSeal: isBottomSeal,
        ),
      ),
    );
  }
}

class CircularImageCropperScreen extends StatefulWidget {
  final String imagePath;
  final String title;
  final double outputSize;
  final bool isBottomSeal;

  const CircularImageCropperScreen({
    super.key,
    required this.imagePath,
    this.title = 'تعديل وقص الصورة',
    this.outputSize = 1000.0,
    this.isBottomSeal = false,
  });

  @override
  State<CircularImageCropperScreen> createState() =>
      _CircularImageCropperScreenState();
}

class _CircularImageCropperScreenState
    extends State<CircularImageCropperScreen> {
  final TransformationController _transformationController =
      TransformationController();

  ui.Image? _image;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  int _quarterTurns = 0;
  double _currentScale = 1.0;
  bool _cropAsCircle = true;
  bool _showGrid = true;
  bool _showNudgePad = true;
  double _nudgeSensitivity = 1.0; // 0.5px, 1px, 2px, 5px precision step
  bool _showExpandedPreview = false;

  // Cached layout dimensions
  double _viewportWidth = 0;
  double _viewportHeight = 0;
  double _childWidth = 0;
  double _childHeight = 0;
  Offset _circleCenter = Offset.zero;
  double _circleRadius = 140;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
    _loadImage();
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    _image?.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if ((scale - _currentScale).abs() > 0.005) {
      setState(() {
        _currentScale = scale;
      });
    }
  }

  Future<void> _loadImage() async {
    try {
      final file = File(widget.imagePath);
      if (!await file.exists()) {
        setState(() {
          _errorMessage = 'الملف غير موجود';
          _isLoading = false;
        });
        return;
      }

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      if (mounted) {
        setState(() {
          _image = frame.image;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'تعذر قراءة الصورة: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _initTransformation({bool fitInside = false}) {
    if (_image == null || _viewportWidth <= 0 || _viewportHeight <= 0) return;

    final diameter = _circleRadius * 2;
    final isRotated = _quarterTurns % 2 == 1;
    final origAspect = _image!.width / _image!.height;
    final effectiveAspect = isRotated ? (1.0 / origAspect) : origAspect;

    if (fitInside) {
      // Contain the entire image inside the circle
      if (!isRotated) {
        if (origAspect >= 1.0) {
          _childWidth = diameter;
          _childHeight = diameter / origAspect;
        } else {
          _childHeight = diameter;
          _childWidth = diameter * origAspect;
        }
      } else {
        if (effectiveAspect >= 1.0) {
          _childHeight = diameter;
          _childWidth = diameter * origAspect;
        } else {
          _childWidth = diameter;
          _childHeight = diameter / origAspect;
        }
      }
    } else {
      // Cover the circle
      if (!isRotated) {
        if (origAspect >= 1.0) {
          _childHeight = diameter;
          _childWidth = diameter * origAspect;
        } else {
          _childWidth = diameter;
          _childHeight = diameter / origAspect;
        }
      } else {
        if (effectiveAspect >= 1.0) {
          _childWidth = diameter;
          _childHeight = diameter / origAspect;
        } else {
          _childHeight = diameter;
          _childWidth = diameter * origAspect;
        }
      }
    }

    final effW = isRotated ? _childHeight : _childWidth;
    final effH = isRotated ? _childWidth : _childHeight;

    // With constrained: false and alignment: Alignment.topLeft,
    // translating by (tx, ty) positions the center of the child exactly at _circleCenter
    final tx = _circleCenter.dx - effW / 2;
    final ty = _circleCenter.dy - effH / 2;

    _transformationController.value = Matrix4.translationValues(tx, ty, 0);
    _currentScale = 1.0;
  }

  void _applyScaleFromSlider(double newScale) {
    if (_image == null || _circleRadius <= 0) return;

    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    if (currentScale <= 0) return;

    final factor = newScale / currentScale;

    // Keep scaling centered strictly at _circleCenter
    final curTx = currentMatrix.storage[12];
    final curTy = currentMatrix.storage[13];

    final newTx = _circleCenter.dx - (_circleCenter.dx - curTx) * factor;
    final newTy = _circleCenter.dy - (_circleCenter.dy - curTy) * factor;

    final newMatrix = Matrix4.identity()
      ..setEntry(0, 0, newScale)
      ..setEntry(1, 1, newScale)
      ..setEntry(0, 3, newTx)
      ..setEntry(1, 3, newTy);

    _transformationController.value = newMatrix;
    setState(() => _currentScale = newScale);
  }

  /// Nudge the image in pixels for millimeter-accurate positioning
  void _nudge(double dx, double dy) {
    HapticFeedback.selectionClick();
    final m = _transformationController.value.clone();
    m.storage[12] += (dx * _nudgeSensitivity);
    m.storage[13] += (dy * _nudgeSensitivity);
    _transformationController.value = m;
    setState(() {});
  }

  void _rotateClockwise() {
    HapticFeedback.mediumImpact();
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _initTransformation();
    });
  }

  void _resetTransform() {
    HapticFeedback.lightImpact();
    setState(() {
      _quarterTurns = 0;
      _initTransformation();
    });
  }

  Future<void> _saveAndCrop() async {
    if (_image == null || _isSaving) return;

    setState(() => _isSaving = true);
    HapticFeedback.heavyImpact();

    try {
      final S = widget.outputSize;
      final R = _circleRadius;
      final C = _circleCenter;
      final M = _transformationController.value;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, S, S),
      );

      canvas.save();

      // If user selected circular cut, clip canvas to circle
      if (_cropAsCircle) {
        canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, S, S)));
      }

      // 1. Center of canvas
      canvas.translate(S / 2, S / 2);
      // 2. Scale viewport radius R to output radius S / 2
      canvas.scale(S / (2 * R));
      // 3. Move circle center to origin
      canvas.translate(-C.dx, -C.dy);
      // 4. Apply InteractiveViewer transformation (aligned at topLeft with constrained: false)
      canvas.transform(M.storage);

      // 5. If rotated, apply rotation around center of displayed box
      final isRotated = _quarterTurns % 2 == 1;
      final displayW = isRotated ? _childHeight : _childWidth;
      final displayH = isRotated ? _childWidth : _childHeight;

      if (_quarterTurns != 0) {
        canvas.translate(displayW / 2, displayH / 2);
        canvas.rotate(_quarterTurns * (pi / 2));
        canvas.translate(-_childWidth / 2, -_childHeight / 2);
      }

      // 6. Scale from image pixel dimensions to display dimensions
      canvas.scale(_childWidth / _image!.width, _childHeight / _image!.height);

      // 7. Draw the image with ultra-high quality
      canvas.drawImage(
        _image!,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );

      canvas.restore();

      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(S.toInt(), S.toInt());
      final byteData =
          await croppedImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('فشل تحويل الصورة الملتقطة');
      }

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final outputFile = File(
        '${tempDir.path}/cropped_avatar_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await outputFile.writeAsBytes(pngBytes);

      if (mounted) {
        Navigator.of(context).pop(outputFile);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء حفظ الصورة: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF00F2FE)),
                    SizedBox(height: 16),
                    Text(
                      'جاري تحميل وضبط الصورة بدقة متناهية...',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              )
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFEF4444),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('إغلاق'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  // 1. Sleek Top Header Bar
                  _buildTopBar(),

                  // 2. Interactive Workspace with Hole Mask
                  Expanded(
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;

                        final diameter =
                            min(w - 30, h - 30).clamp(160.0, 320.0);
                        final radius = diameter / 2;
                        final center = Offset(w / 2, h / 2);

                        // If viewport resized or first layout, initialize transform
                        if ((_viewportWidth - w).abs() > 2 ||
                            (_viewportHeight - h).abs() > 2 ||
                            (_circleRadius - radius).abs() > 2) {
                          _viewportWidth = w;
                          _viewportHeight = h;
                          _circleRadius = radius;
                          _circleCenter = center;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _initTransformation();
                          });
                        }

                        final isRotated = _quarterTurns % 2 == 1;
                        final displayW =
                            isRotated ? _childHeight : _childWidth;
                        final displayH =
                            isRotated ? _childWidth : _childHeight;

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            // Layer A: Interactive Image Viewer
                            // CRITICAL FIX: constrained: false ensures the child has exactly displayW x displayH
                            // matching the exact canvas calculations in _saveAndCrop() with 100.0% pixel accuracy!
                            ClipRect(
                              child: InteractiveViewer(
                                transformationController:
                                    _transformationController,
                                alignment: Alignment.topLeft,
                                constrained: false,
                                minScale: 0.15,
                                maxScale: 8.0,
                                boundaryMargin: const EdgeInsets.all(
                                  double.infinity,
                                ),
                                child: SizedBox(
                                  width: displayW,
                                  height: displayH,
                                  child: RotatedBox(
                                    quarterTurns: _quarterTurns,
                                    child: SizedBox(
                                      width: _childWidth,
                                      height: _childHeight,
                                      child: RawImage(
                                        image: _image,
                                        fit: BoxFit.fill,
                                        filterQuality: FilterQuality.high,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Layer B: Semi-transparent Scrim with Circular Hole & Glowing Border
                            IgnorePointer(
                              child: CustomPaint(
                                size: Size(w, h),
                                painter: _HoleMaskPainter(
                                  circleCenter: _circleCenter,
                                  circleRadius: _circleRadius,
                                  showGrid: _showGrid,
                                ),
                              ),
                            ),

                            // Layer C: Floating Gesture Guide Tooltip
                            Positioned(
                              top: 8,
                              left: 12,
                              right: 12,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xFF00F2FE).withValues(
                                        alpha: 0.4,
                                      ),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.4),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.touch_app_rounded,
                                        color: Color(0xFF00F2FE),
                                        size: 13,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          'حرك وكبّر الصورة داخل الدائرة • المعاينة حية ومطابقة 100% ✨',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Layer D: Live Certificate Preview Badge (Floating in Corner with 60/120fps sync)
                            Positioned(
                              bottom: 10,
                              left: 10,
                              child: _buildLiveCertificatePreviewBadge(),
                            ),

                            // Layer E: Precision Nudge Pad Button (Bottom Right)
                            Positioned(
                              bottom: 10,
                              right: 10,
                              child: _buildNudgePadToggle(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // 3. Bottom Control Dock (Zoom slider, Rotate, Reset, Nudge, Sensitivity)
                  _buildBottomControlDock(),
                ],
              ),
      ),
    );
  }

  // --- Real-time Live Certificate Preview Badge (Synchronous 60/120fps with ListenableBuilder) ---
  Widget _buildLiveCertificatePreviewBadge() {
    final badgeSize = _showExpandedPreview ? 108.0 : 72.0;
    final isSeal = widget.isBottomSeal;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _showExpandedPreview = !_showExpandedPreview);
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSeal ? const Color(0xFF10B981) : const Color(0xFFD4AF37),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.remove_red_eye_rounded,
                  size: 11,
                  color: isSeal ? const Color(0xFF10B981) : const Color(0xFFD4AF37),
                ),
                const SizedBox(width: 3),
                Text(
                  isSeal ? 'معاينة ختم الشهادة' : 'معاينة اللوجو بالشهادة',
                  style: TextStyle(
                    color: isSeal ? const Color(0xFF10B981) : const Color(0xFFD4AF37),
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _showExpandedPreview ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  size: 11,
                  color: Colors.white54,
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Live Canvas inside Certificate Circle with ribbon if seal
            ListenableBuilder(
              listenable: _transformationController,
              builder: (context, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: badgeSize,
                      height: badgeSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: isSeal ? const Color(0xFF10B981) : const Color(0xFFD4AF37),
                          width: 2.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (isSeal ? const Color(0xFF10B981) : const Color(0xFFD4AF37))
                                .withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CustomPaint(
                        size: Size(badgeSize, badgeSize),
                        painter: _LiveCroppedPreviewPainter(
                          image: _image,
                          matrix: _transformationController.value,
                          circleCenter: _circleCenter,
                          circleRadius: _circleRadius,
                          quarterTurns: _quarterTurns,
                          childWidth: _childWidth,
                          childHeight: _childHeight,
                          isCircle: _cropAsCircle,
                        ),
                      ),
                    ),
                    if (isSeal) ...[
                      const SizedBox(height: 1),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 4, height: 7, color: const Color(0xFFDC2626)),
                          const SizedBox(width: 2),
                          Container(width: 4, height: 7, color: const Color(0xFFDC2626)),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- Toggleable Precision Nudge Pad with Sensitivity Selection ---
  Widget _buildNudgePadToggle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_showNudgePad)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF00F2FE).withValues(alpha: 0.6),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sensitivity selector buttons (0.5px, 1px, 2px, 5px)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStepChip('0.5px', 0.5),
                    const SizedBox(width: 3),
                    _buildStepChip('1px', 1.0),
                    const SizedBox(width: 3),
                    _buildStepChip('2px', 2.0),
                    const SizedBox(width: 3),
                    _buildStepChip('5px', 5.0),
                  ],
                ),
                const SizedBox(height: 5),

                // D-Pad for millimeter micro-movement
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  color: Colors.white,
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 26),
                  onPressed: () => _nudge(0, -1),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_left_rounded),
                      color: Colors.white,
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 26),
                      onPressed: () => _nudge(-1, 0),
                    ),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF00F2FE),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00F2FE).withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_right_rounded),
                      color: Colors.white,
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 26),
                      onPressed: () => _nudge(1, 0),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  color: Colors.white,
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 26),
                  onPressed: () => _nudge(0, 1),
                ),
              ],
            ),
          ),
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _showNudgePad = !_showNudgePad);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _showNudgePad
                  ? const Color(0xFF00F2FE)
                  : const Color(0xFF0F172A).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF00F2FE),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.open_with_rounded,
                  size: 13,
                  color: _showNudgePad ? Colors.black : const Color(0xFF00F2FE),
                ),
                const SizedBox(width: 4),
                Text(
                  _showNudgePad ? 'إخفاء الأسهم' : 'تحريك دقيق 🎛️',
                  style: TextStyle(
                    color: _showNudgePad ? Colors.black : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepChip(String label, double val) {
    final isSel = _nudgeSensitivity == val;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _nudgeSensitivity = val);
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF00F2FE) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? Colors.black : Colors.white70,
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // --- Top App Bar ---
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Cancel Button
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text(
              'إلغاء',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            ),
          ),

          // Title
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 1),
                const Text(
                  'قص وضبط صورة دائرية بدقة متناهية 100%',
                  style: TextStyle(fontSize: 9.5, color: Color(0xFF00F2FE)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),

          // Save Button
          InkWell(
            onTap: _isSaving ? null : _saveAndCrop,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00F2FE), Color(0xFF2563EB)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSaving)
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  else
                    const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  const SizedBox(width: 4),
                  Text(
                    _isSaving ? 'حفظ...' : 'حفظ واعتمد ✨',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
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

  // --- Bottom Control Dock ---
  Widget _buildBottomControlDock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: const Border(
          top: BorderSide(color: Color(0xFF1E293B), width: 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Quick Presets (احتواء، ملء، 100%، 130%، 160%)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPresetChip('احتواء كامل 🔲', () {
                  _quarterTurns = 0;
                  _initTransformation(fitInside: true);
                }),
                const SizedBox(width: 5),
                _buildPresetChip('ملء الدائرة ⚪', () {
                  _quarterTurns = 0;
                  _initTransformation(fitInside: false);
                }),
                const SizedBox(width: 5),
                _buildPresetChip('100%', () => _applyScaleFromSlider(1.0)),
                const SizedBox(width: 5),
                _buildPresetChip('130%', () => _applyScaleFromSlider(1.3)),
                const SizedBox(width: 5),
                _buildPresetChip('160%', () => _applyScaleFromSlider(1.6)),
                const SizedBox(width: 5),
                _buildPresetChip('200%', () => _applyScaleFromSlider(2.0)),
              ],
            ),
          ),
          const SizedBox(height: 5),

          // Row 2: Fine Zoom Slider with Micro-step (-) and (+) buttons
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.zoom_out_rounded, size: 20),
                color: Colors.white70,
                tooltip: 'تصغير دقيق (-5%)',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () {
                  final target = (_currentScale - 0.05).clamp(0.15, 6.0);
                  _applyScaleFromSlider(target);
                },
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF00F2FE),
                    inactiveTrackColor: const Color(0xFF1E293B),
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6.5,
                    ),
                    overlayColor:
                        const Color(0xFF00F2FE).withValues(alpha: 0.2),
                    trackHeight: 3.5,
                  ),
                  child: Slider(
                    value: _currentScale.clamp(0.15, 6.0),
                    min: 0.15,
                    max: 6.0,
                    divisions: 117,
                    onChanged: _applyScaleFromSlider,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in_rounded, size: 20),
                color: Colors.white70,
                tooltip: 'تكبير دقيق (+5%)',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () {
                  final target = (_currentScale + 0.05).clamp(0.15, 6.0);
                  _applyScaleFromSlider(target);
                },
              ),
              const SizedBox(width: 5),
              Container(
                width: 48,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${(_currentScale * 100).toInt()}%',
                  style: const TextStyle(
                    color: Color(0xFF00F2FE),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Row 3: Tool buttons wrapped in horizontal scroll so it NEVER overflows on small screens!
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildToolButton(
                  icon: Icons.rotate_90_degrees_cw_rounded,
                  label: 'تدوير 90°',
                  onTap: _rotateClockwise,
                ),
                const SizedBox(width: 6),
                _buildToolButton(
                  icon: _showGrid
                      ? Icons.grid_on_rounded
                      : Icons.grid_off_rounded,
                  label: _showGrid ? 'الشبكة' : 'بدون شبكة',
                  isActive: _showGrid,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showGrid = !_showGrid);
                  },
                ),
                const SizedBox(width: 6),
                _buildToolButton(
                  icon: _cropAsCircle
                      ? Icons.circle_outlined
                      : Icons.crop_square_rounded,
                  label: _cropAsCircle ? 'دائري' : 'مربع',
                  isActive: _cropAsCircle,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _cropAsCircle = !_cropAsCircle);
                  },
                ),
                const SizedBox(width: 6),
                _buildToolButton(
                  icon: Icons.restart_alt_rounded,
                  label: 'إعادة ضبط',
                  onTap: _resetTransform,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? const Color(0xFF00F2FE).withValues(alpha: 0.6)
                : const Color(0xFF334155),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? const Color(0xFF00F2FE) : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: isActive ? const Color(0xFF00F2FE) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for Live Certificate Preview Badge
class _LiveCroppedPreviewPainter extends CustomPainter {
  final ui.Image? image;
  final Matrix4 matrix;
  final Offset circleCenter;
  final double circleRadius;
  final int quarterTurns;
  final double childWidth;
  final double childHeight;
  final bool isCircle;

  _LiveCroppedPreviewPainter({
    required this.image,
    required this.matrix,
    required this.circleCenter,
    required this.circleRadius,
    required this.quarterTurns,
    required this.childWidth,
    required this.childHeight,
    required this.isCircle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null || circleRadius <= 0) return;

    final S = size.width;
    final R = circleRadius;
    final C = circleCenter;

    canvas.save();
    if (isCircle) {
      canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, S, S)));
    }

    // Exact same transformation chain as _saveAndCrop():
    canvas.translate(S / 2, S / 2);
    canvas.scale(S / (2 * R));
    canvas.translate(-C.dx, -C.dy);
    canvas.transform(matrix.storage);

    final isRotated = quarterTurns % 2 == 1;
    final displayW = isRotated ? childHeight : childWidth;
    final displayH = isRotated ? childWidth : childHeight;

    if (quarterTurns != 0) {
      canvas.translate(displayW / 2, displayH / 2);
      canvas.rotate(quarterTurns * (pi / 2));
      canvas.translate(-childWidth / 2, -childHeight / 2);
    }

    canvas.scale(childWidth / image!.width, childHeight / image!.height);
    canvas.drawImage(
      image!,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.high,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiveCroppedPreviewPainter oldDelegate) => true;
}

/// Custom painter that dims the surrounding area and draws a glowing circular cut-out viewport.
class _HoleMaskPainter extends CustomPainter {
  final Offset circleCenter;
  final double circleRadius;
  final bool showGrid;

  const _HoleMaskPainter({
    required this.circleCenter,
    required this.circleRadius,
    this.showGrid = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final screenRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final circleRect =
        Rect.fromCircle(center: circleCenter, radius: circleRadius);

    // 1. Draw dark studio scrim everywhere EXCEPT inside the circular hole
    final overlayPaint = Paint()
      ..color = const Color(0xD9050A14)
      ..style = PaintingStyle.fill;

    final backgroundPath = Path()..addRect(screenRect);
    final circlePath = Path()..addOval(circleRect);
    final maskPath =
        Path.combine(PathOperation.difference, backgroundPath, circlePath);

    canvas.drawPath(maskPath, overlayPaint);

    // 2. Glowing Neon Border around the Circle
    final glowPaint = Paint()
      ..color = const Color(0xFF00F2FE).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(circleCenter, circleRadius, glowPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF00F2FE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(circleCenter, circleRadius, borderPaint);

    // 3. Subtle Rule-of-Thirds Grid inside the circle
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.save();
      canvas.clipPath(circlePath);

      final d = circleRadius * 2;
      final left = circleCenter.dx - circleRadius;
      final top = circleCenter.dy - circleRadius;

      // Vertical 1/3 and 2/3 lines
      canvas.drawLine(
        Offset(left + d / 3, top),
        Offset(left + d / 3, top + d),
        gridPaint,
      );
      canvas.drawLine(
        Offset(left + 2 * d / 3, top),
        Offset(left + 2 * d / 3, top + d),
        gridPaint,
      );

      // Horizontal 1/3 and 2/3 lines
      canvas.drawLine(
        Offset(left, top + d / 3),
        Offset(left + d, top + d / 3),
        gridPaint,
      );
      canvas.drawLine(
        Offset(left, top + 2 * d / 3),
        Offset(left + d, top + 2 * d / 3),
        gridPaint,
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _HoleMaskPainter oldDelegate) {
    return oldDelegate.circleCenter != circleCenter ||
        oldDelegate.circleRadius != circleRadius ||
        oldDelegate.showGrid != showGrid;
  }
}
