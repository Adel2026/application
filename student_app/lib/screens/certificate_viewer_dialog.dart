import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/certificate_image_generator.dart';
import '../theme/app_theme.dart';

/// 📜 نافذة عرض وتحميل ومشاركة صورة شهادة التقدير الرسمية فائقة الدقة
class CertificateViewerDialog extends StatefulWidget {
  final Map<String, dynamic> exam;
  final String studentName;
  final String studentCode;
  final String groupName;
  final String grade;

  const CertificateViewerDialog({
    super.key,
    required this.exam,
    required this.studentName,
    required this.studentCode,
    required this.groupName,
    required this.grade,
  });

  static Future<void> show({
    required BuildContext context,
    required Map<String, dynamic> exam,
    required String studentName,
    required String studentCode,
    required String groupName,
    required String grade,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CertificateViewerDialog(
        exam: exam,
        studentName: studentName,
        studentCode: studentCode,
        groupName: groupName,
        grade: grade,
      ),
    );
  }

  @override
  State<CertificateViewerDialog> createState() => _CertificateViewerDialogState();
}

class _CertificateViewerDialogState extends State<CertificateViewerDialog> {
  Uint8List? _imageBytes;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCertificateImage();
  }

  Future<void> _loadCertificateImage() async {
    final base64Str = widget.exam['certificate_image_base64'];
    if (base64Str != null && base64Str.toString().isNotEmpty) {
      try {
        final decoded = base64Decode(base64Str.toString());
        if (mounted) {
          setState(() {
            _imageBytes = decoded;
            _isLoading = false;
          });
        }
        return;
      } catch (e) {
        debugPrint('Error decoding certificate base64: $e');
      }
    }

    // إذا لم تكن الصورة محفوظة في الفايربيز بعد، نولدها لحظياً بنفس البيانات الحقيقية
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

      final bytes = await CertificateImageGenerator.generateCertificatePng(
        studentName: widget.studentName,
        grade: widget.grade,
        groupName: widget.groupName,
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
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error generating local certificate image: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<File?> _saveToTempFile() async {
    if (_imageBytes == null) return null;
    final tempDir = await getTemporaryDirectory();
    final cleanName = widget.studentName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '_').trim();
    final fileName = 'Certificate_${cleanName}_${widget.exam['id'] ?? 'exam'}.png';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(_imageBytes!);
    return file;
  }

  Future<void> _shareCertificate() async {
    if (_imageBytes == null) return;
    setState(() => _isSaving = true);
    try {
      final file = await _saveToTempFile();
      if (file != null) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'شهادة تقدير وتفوق للطالب/ـة ${widget.studentName} في ${widget.exam['exam_title'] ?? 'الاختبار'} 🎓🌟',
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sharing certificate: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _downloadCertificate() async {
    if (_imageBytes == null) return;
    setState(() => _isSaving = true);
    try {
      Directory? targetDir;
      if (Platform.isAndroid) {
        // محاولة الحفظ في مجلد التحميلات Download
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          targetDir = downloadDir;
        }
      }
      targetDir ??= await getApplicationDocumentsDirectory();

      final cleanName = widget.studentName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '_').trim();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${targetDir.path}/شهادة_تقدير_${cleanName}_$timestamp.png');
      await file.writeAsBytes(_imageBytes!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تم حفظ صورة الشهادة بنجاح في مجلد التحميلات 📥\n(${file.path.split('/').last})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving certificate: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('تعذر حفظ الشهادة: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final certTitle = widget.exam['certificate_title'] ?? 'شهادة تقدير وتفوق 🎓';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFD4AF37), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
              blurRadius: 28,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ترويسة النافذة
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD700), size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      certTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFFD700),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // معاينة صورة الشهادة الرأسية مع إمكانية التكبير
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.68,
                ),
                padding: const EdgeInsets.all(12),
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF00F2FE)),
                            SizedBox(height: 14),
                            Text('جارٍ استخراج صورة الشهادة الرسمية...', style: TextStyle(color: Color(0xFF94A3B8))),
                          ],
                        ),
                      )
                    : _imageBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: InteractiveViewer(
                              minScale: 0.8,
                              maxScale: 3.5,
                              child: Image.memory(
                                _imageBytes!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          )
                        : const Center(
                            child: Text(
                              'تعذر تحميل صورة الشهادة',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
              ),
            ),

            // أزرار الحفظ والمشاركة
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF1E293B))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.download_rounded, size: 20),
                      label: const Text('حفظ الصورة 📥', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      onPressed: _isLoading || _isSaving ? null : _downloadCertificate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF00F2FE)),
                        foregroundColor: const Color(0xFF00F2FE),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('مشاركة 📲', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      onPressed: _isLoading || _isSaving ? null : _shareCertificate,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
