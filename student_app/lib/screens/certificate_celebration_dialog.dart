import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/certificate_image_generator.dart';
import 'certificate_viewer_dialog.dart';

/// احتفال فاخر تفاعلي بمناسبة الحصول على شهادة تقدير 🎓✨
class CertificateCelebrationDialog extends StatefulWidget {
  final Map<String, dynamic> exam;
  final String studentName;
  final String code;
  final String groupName;

  const CertificateCelebrationDialog({
    super.key,
    required this.exam,
    required this.studentName,
    required this.code,
    required this.groupName,
  });

  static Future<void> show({
    required BuildContext context,
    required Map<String, dynamic> exam,
    required String studentName,
    required String code,
    required String groupName,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق الاحتفال',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 550),
      pageBuilder: (ctx, anim1, anim2) {
        return CertificateCelebrationDialog(
          exam: exam,
          studentName: studentName,
          code: code,
          groupName: groupName,
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curved,
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
    );
  }

  @override
  State<CertificateCelebrationDialog> createState() => _CertificateCelebrationDialogState();
}

class _CertificateCelebrationDialogState extends State<CertificateCelebrationDialog>
    with TickerProviderStateMixin {
  late final AnimationController _confettiController;
  late final AnimationController _glowController;
  late final AnimationController _badgeBounceController;

  final List<_ConfettiParticle> _particles = [];
  final Random _rnd = Random();

  Uint8List? _imageBytes;
  bool _isLoadingImage = true;

  @override
  void initState() {
    super.initState();

    // 1. متحكم إطلاق الزينة والكونفيتي
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..addListener(() {
        setState(() {
          for (final p in _particles) {
            p.update();
          }
        });
      });

    // 2. متحكم التوهج النبضي للتاج والأوسمة
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // 3. قفزة الشعار والوسام في البداية
    _badgeBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    // توليد 70 جزيء كونفيتي بأشكال وألوان مبهجة
    for (int i = 0; i < 70; i++) {
      _particles.add(_ConfettiParticle(rnd: _rnd));
    }
    _confettiController.repeat();

    // تحميل صورة الشهادة الأصلية طبقاً لقواعد واختيار المعلم
    _loadCertificateImage();
  }

  Future<void> _loadCertificateImage() async {
    // الأولوية الأولى: صورة الشهادة الأصلية المرسلة من برنامج المعلم
    final base64Str = widget.exam['certificate_image_base64'];
    if (base64Str != null && base64Str.toString().trim().isNotEmpty) {
      try {
        final decoded = base64Decode(base64Str.toString().trim());
        if (mounted) {
          setState(() {
            _imageBytes = decoded;
            _isLoadingImage = false;
          });
        }
        return;
      } catch (e) {
        debugPrint('Error decoding teacher certificate image base64: $e');
      }
    }

    // الأولوية البديلة: التوليد وفق قواعد وبيانات المعلم في حالة تأخر الرفع السحابي
    try {
      final examTitle = widget.exam['exam_title'] ?? 'اختبار تقييمي';
      final score = (widget.exam['score'] as num? ?? 0).toDouble();
      final max = (widget.exam['max_score'] as num? ?? 100).toDouble();
      final pct = (widget.exam['percentage'] as num? ?? (max > 0 ? (score / max) * 100 : 0)).toDouble();
      final rank = (widget.exam['rank'] as num? ?? 0).toInt();
      final certTitle = widget.exam['certificate_title'] ?? 'شهادة تقدير وتفوق 🎓';
      final teacherName = widget.exam['teacher_name'] ?? 'معلم المادة';
      final centerName = widget.exam['center_name'] ?? 'أكاديمية التفوق التعليمية';
      final examDate = widget.exam['exam_date'] ?? widget.exam['date'] ?? '';

      final realStudentName = (widget.exam['student_name'] ?? widget.studentName).toString().trim();
      final displayName = realStudentName.isNotEmpty && realStudentName != 'الطالب' && realStudentName != 'الطالب المتميز'
          ? realStudentName
          : (widget.studentName.isNotEmpty ? widget.studentName : 'الطالب المتفوق');
      final realGroupName = (widget.exam['group_name'] ?? widget.groupName).toString().trim();
      final displayGroupName = realGroupName.isNotEmpty && realGroupName != 'المجموعة الأكاديمية' ? realGroupName : widget.groupName;
      final realGrade = (widget.exam['grade'] ?? '').toString();

      final bytes = await CertificateImageGenerator.generateCertificatePng(
        studentName: displayName,
        grade: realGrade,
        groupName: displayGroupName,
        examTitle: examTitle,
        score: score,
        maxScore: max,
        percentage: pct,
        rank: rank,
        certTitle: certTitle,
        teacherName: teacherName,
        centerName: centerName,
        examDate: examDate,
      );

      if (mounted) {
        setState(() {
          _imageBytes = bytes;
          _isLoadingImage = false;
        });
      }
    } catch (e) {
      debugPrint('Error generating certificate image fallback: $e');
      if (mounted) {
        setState(() => _isLoadingImage = false);
      }
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _glowController.dispose();
    _badgeBounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final score = (widget.exam['score'] as num? ?? 0).toDouble();
    final max = (widget.exam['max_score'] as num? ?? 100).toDouble();
    final pct = (widget.exam['percentage'] as num? ?? (max > 0 ? (score / max) * 100 : 0)).toDouble();
    final rank = (widget.exam['rank'] as num? ?? 0).toInt();

    final isFirst = rank == 1;
    final isTop3 = rank > 0 && rank <= 3;

    // استخراج بيانات الطالب الحقيقية دون أي بيانات عشوائية
    final realStudentName = (widget.exam['student_name'] ?? widget.studentName).toString().trim();
    final displayName = realStudentName.isNotEmpty && realStudentName != 'الطالب' && realStudentName != 'الطالب المتميز'
        ? realStudentName
        : (widget.studentName.isNotEmpty ? widget.studentName : 'الطالب المتفوق');
    final realGroupName = (widget.exam['group_name'] ?? widget.groupName).toString().trim();
    final displayGroupName = realGroupName.isNotEmpty && realGroupName != 'المجموعة الأكاديمية' ? realGroupName : widget.groupName;
    final realGrade = (widget.exam['grade'] ?? '').toString();
    final realCode = '${widget.exam['student_code'] ?? widget.code}';

    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final dialogHeight = (screenHeight * 0.96).clamp(580.0, 940.0);

    String formatNum(double val) {
      if (val == val.roundToDouble()) {
        return val.toInt().toString();
      }
      return val.toStringAsFixed(1);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // خلفية الزينة المتساقطة المبهجة
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ConfettiPainter(particles: _particles),
              ),
            ),
          ),

          // محتوى نافذة التكريم الفاخرة المحدثة
          SafeArea(
            child: Center(
              child: Container(
                height: dialogHeight,
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 480),
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0F1D),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.85),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.28),
                      blurRadius: 36,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // 1. كلمة CONGRATULATIONS الملكية الفاخرة بدون عبارة مبروك
                    AnimatedBuilder(
                      animation: _glowController,
                      builder: (context, child) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // تاج وزخارف ملكية علوية
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.auto_awesome, color: Color(0xFFF59E0B), size: 14),
                                const SizedBox(width: 8),
                                Container(
                                  height: 1.5,
                                  width: 32,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        const Color(0xFFF59E0B).withValues(alpha: 0.85),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text('👑', style: TextStyle(fontSize: 18)),
                                const SizedBox(width: 8),
                                Container(
                                  height: 1.5,
                                  width: 32,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFFF59E0B).withValues(alpha: 0.85),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.auto_awesome, color: Color(0xFFF59E0B), size: 14),
                              ],
                            ),
                            const SizedBox(height: 2),
                            ShaderMask(
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  colors: const [
                                    Color(0xFFFFDF00),
                                    Color(0xFFFFF7C2),
                                    Color(0xFFFFA500),
                                    Color(0xFFFFDF00),
                                  ],
                                  stops: [0.0, (_glowController.value * 0.6 + 0.2).clamp(0.0, 1.0), 0.8, 1.0],
                                ).createShader(bounds);
                              },
                              child: const Text(
                                'CONGRATULATIONS',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3.8,
                                  fontFamily: 'serif',
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: Color(0xFFF59E0B),
                                      blurRadius: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    // 2. مستطيل البيانات الملكي الموسع بسطرين متناسقين
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // السطر الأول: الاسم في سطر كامل بارز مع الكود والمرحلة
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // الاسم وبجانبه رمز الشرف
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        displayName,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          fontFamily: 'Cairo',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // الكود والمرحلة
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'كود: $realCode • ${displayGroupName.isNotEmpty ? displayGroupName : (realGrade.isNotEmpty ? realGrade : "المجموعة")}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF94A3B8),
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Container(height: 1, color: const Color(0xFF1E293B)),
                          const SizedBox(height: 7),

                          // السطر الثاني: المركز في ناحية، والدرجة الفعلية/الكلية والنسبة في الناحية الأخرى
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // شارة المركز والوسام الذهبي (في ناحية)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      rank == 1
                                          ? 'المركز الأول'
                                          : (rank == 2
                                              ? 'المركز الثاني'
                                              : (rank == 3
                                                  ? 'المركز الثالث'
                                                  : (rank > 0 ? 'المركز $rank' : 'مرتبة الشرف'))),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFFF59E0B),
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Icon(
                                      isFirst
                                          ? Icons.emoji_events_rounded
                                          : (isTop3 ? Icons.stars_rounded : Icons.military_tech_rounded),
                                      size: 15,
                                      color: const Color(0xFFF59E0B),
                                    ),
                                  ],
                                ),
                              ),
                              // شارة الدرجة الفعلية والكلية والنسبة بعدها بمسافة صغيرة (في الناحية الأخرى)
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF090E1B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF1E293B)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // الدرجة الفعلية
                                      Text(
                                        formatNum(score),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF10B981),
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const Text(
                                        ' / ',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF64748B),
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      // الدرجة الكلية
                                      Text(
                                        formatNum(max),
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF94A3B8),
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // النسبة المئوية بعدها بمسافة صغيرة
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: const Color(0xFF00F2FE).withValues(alpha: 0.35),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          '%${pct % 1 == 0 ? pct.toInt() : pct.toStringAsFixed(1)}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF00F2FE),
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 3. عرض صورة الشهادة بكامل الطول المتبقي للشاشة (Expanded)
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1120),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.85),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: _buildCertificateContent(
                            displayName: displayName,
                            realCode: realCode,
                            displayGroupName: displayGroupName,
                            realGrade: realGrade,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 4. زر إغلاق في أقصى أسفل الشاشة
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: const Color(0xFF0F172A),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF0F172A)),
                        label: const Text(
                          'إغلاق',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, fontFamily: 'Cairo'),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertificateContent({
    required String displayName,
    required String realCode,
    required String displayGroupName,
    required String realGrade,
  }) {
    if (_isLoadingImage) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFF59E0B)),
            SizedBox(height: 12),
            Text(
              'جاري تحميل صورة الشهادة الرسمية...',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_imageBytes != null) {
      return GestureDetector(
        onTap: () {
          CertificateViewerDialog.show(
            context: context,
            exam: widget.exam,
            studentName: displayName,
            studentCode: realCode,
            groupName: displayGroupName,
            grade: realGrade,
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 1.0,
              maxScale: 3.5,
              clipBehavior: Clip.hardEdge,
              child: Center(
                child: Image.memory(
                  _imageBytes!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  width: double.infinity,
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app_rounded, size: 14, color: Color(0xFFFFD700)),
                    SizedBox(width: 4),
                    Text(
                      'اضغط للمشاركة أو التحميل بدقة عالية 📜🔍',
                      style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const Center(
      child: Text(
        'لم يتم العثور على صورة الشهادة',
        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
      ),
    );
  }
}

class _ConfettiParticle {
  late double x;
  late double y;
  late double vx;
  late double vy;
  late double size;
  late Color color;
  late double rotation;
  late double rotationSpeed;
  final Random rnd;

  _ConfettiParticle({required this.rnd}) {
    reset(initial: true);
  }

  void reset({bool initial = false}) {
    x = rnd.nextDouble() * 400;
    y = initial ? rnd.nextDouble() * 800 : -20;
    vx = (rnd.nextDouble() - 0.5) * 3;
    vy = rnd.nextDouble() * 3 + 2;
    size = rnd.nextDouble() * 8 + 4;
    rotation = rnd.nextDouble() * 2 * pi;
    rotationSpeed = (rnd.nextDouble() - 0.5) * 0.15;

    const colors = [
      Color(0xFFFFDF00), // Gold
      Color(0xFF00F2FE), // Cyan
      Color(0xFF10B981), // Emerald
      Color(0xFFEC4899), // Pink
      Color(0xFF8B5CF6), // Purple
      Color(0xFFF97316), // Orange
      Colors.white,
    ];
    color = colors[rnd.nextInt(colors.length)];
  }

  void update() {
    x += vx;
    y += vy;
    rotation += rotationSpeed;
    if (y > 900) {
      reset();
    }
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;

  _ConfettiPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
