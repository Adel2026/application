import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/database/database_service.dart';
import '../core/whatsapp_service.dart';
import '../models/student_model.dart';
import '../widgets/section_top_bar.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, required this.database});
  final DatabaseService database;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  MobileScannerController? controller;
  Key _scannerKey = UniqueKey();
  bool _hasPermission = false;
  bool _isCheckingPermission = true;
  bool _isPermanentlyDenied = false;
  bool isProcessing = false;
  String? lastScannedName;
  String? lastScannedStatus;
  bool isTorchOn = false;
  CameraFacing _currentFacing = CameraFacing.back;
  bool _isInitializingScanner = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAndRequestPermission(requestIfNeeded: true);
  }

  Future<void> _checkAndRequestPermission({bool requestIfNeeded = true}) async {
    if (!mounted) return;
    setState(() => _isCheckingPermission = true);

    var status = await Permission.camera.status;
    if (!status.isGranted && requestIfNeeded) {
      status = await Permission.camera.request();
    }

    if (!mounted) return;

    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
        _isPermanentlyDenied = false;
        _isCheckingPermission = false;
      });
      await _safeInitScannerController(facing: _currentFacing);
    } else {
      setState(() {
        _hasPermission = false;
        _isPermanentlyDenied = status.isPermanentlyDenied;
        _isCheckingPermission = false;
      });
    }
  }

  Future<void> _safeInitScannerController({CameraFacing facing = CameraFacing.back}) async {
    if (!mounted) return;
    setState(() => _isInitializingScanner = true);

    try {
      if (controller != null) {
        try {
          await controller!.stop();
        } catch (_) {}
        try {
          await controller!.dispose();
        } catch (_) {}
        controller = null;
      }

      // Allow Android CameraX native lifecycle to fully release the camera hardware
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;

      final newController = MobileScannerController(
        formats: const [
          BarcodeFormat.qrCode,
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
        ],
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 800,
        autoStart: true,
        facing: facing,
        torchEnabled: false,
      );

      if (mounted) {
        setState(() {
          controller = newController;
          _currentFacing = facing;
          _scannerKey = UniqueKey();
          isTorchOn = false;
          _isInitializingScanner = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializingScanner = false;
        });
      }
    }
  }

  Future<void> _scanFromGallery() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
      );
      if (result.isEmpty || result.first.path == null) return;
      final path = result.first.path!;

      if (controller == null) {
        _showMessage('جاري تهيئة الماسح، حاول مجدداً', isError: true);
        return;
      }

      final barcodeCapture = await controller!.analyzeImage(path);
      if (barcodeCapture != null && barcodeCapture.barcodes.isNotEmpty) {
        await _handleScan(barcodeCapture);
      } else {
        _showMessage('لم يتم العثور على كود باركود أو QR صالح في الصورة المحددة', isError: true);
      }
    } catch (e) {
      _showMessage('تعذر فحص الصورة: $e', isError: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (controller == null || !_hasPermission) return;

    switch (state) {
      case AppLifecycleState.resumed:
        if (!controller!.value.isRunning) {
          try {
            controller!.start();
          } catch (_) {}
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        if (controller!.value.isRunning) {
          try {
            controller!.stop();
          } catch (_) {}
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (isProcessing || capture.barcodes.isEmpty) return;

    String? rawValue;
    for (final barcode in capture.barcodes) {
      final v = barcode.rawValue ?? barcode.displayValue;
      if (v != null && v.trim().isNotEmpty) {
        rawValue = v.trim();
        break;
      }
    }

    if (rawValue == null || rawValue.isEmpty) return;

    setState(() => isProcessing = true);
    final studentId = _extractStudentId(rawValue);
    await _processStudentCheckIn(studentId);
  }

  Future<void> _processStudentCheckIn(String studentIdentifier) async {
    final cleanId = studentIdentifier.trim();
    if (cleanId.isEmpty) {
      if (mounted) setState(() => isProcessing = false);
      return;
    }

    try {
      await HapticFeedback.mediumImpact();
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}

    StudentModel? student;
    var alreadyRecorded = false;
    try {
      student = await widget.database.findStudentById(cleanId);
      if (student != null) {
        final existingAttendance = await widget.database.getTodayAttendance(student.id);
        await widget.database.recordAttendance(studentId: student.id, source: 'qr');
        alreadyRecorded = existingAttendance != null;
        if (student.groupId != null && student.groupId!.isNotEmpty) {
          final grp = await widget.database.getGroupById(student.groupId!);
          if (grp != null && grp.monthlyPrice > 0) {
            final todayStr = DateTime.now().toIso8601String().substring(0, 10);
            await widget.database.processAttendanceSessionBilling(
              group: grp,
              studentId: student.id,
              studentName: student.fullName,
              date: todayStr,
              status: 'present',
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('تعذر تسجيل الحضور: $e', isError: true);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (mounted) setState(() => isProcessing = false);
      return;
    }

    if (!mounted) return;
    if (student == null) {
      _showMessage('تم قراءة الكود ($cleanId) ولكن لم يتم العثور على طالب مطابق', isError: true);
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (mounted) setState(() => isProcessing = false);
      return;
    }

    String whatsappNote = '';
    if (!alreadyRecorded) {
      final sent = await WhatsAppService.autoSendAttendanceAlert(
        database: widget.database,
        studentName: student.fullName,
        parentPhone: student.parentPhone,
        studentId: student.id,
      );
      if (sent) {
        whatsappNote = ' • (تم إرسال إشعار واتساب)';
      }
    }

    final paymentMessage = student.hasOutstandingPayment ? 'عليه متأخرات ${student.outstandingAmount.toStringAsFixed(0)} ج.م' : 'الاشتراك مسدد';
    final attendanceMessage = alreadyRecorded ? 'مسجل مسبقاً' : 'تم تسجيل الحضور بنجاح ✅';

    setState(() {
      lastScannedName = student?.fullName;
      lastScannedStatus = '$attendanceMessage - $paymentMessage$whatsappNote';
    });

    _showMessage('${student.fullName}: $attendanceMessage ($paymentMessage)$whatsappNote', isError: false);

    // Give 1.2 seconds cooldown before accepting next barcode to prevent multiple accidental scans
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => isProcessing = false);
  }

  String _extractStudentId(String rawValue) {
    try {
      final value = jsonDecode(rawValue);
      if (value is Map<String, dynamic>) {
        if (value['studentId'] != null) return value['studentId'].toString().trim();
        if (value['id'] != null) return value['id'].toString().trim();
        if (value['code'] != null) return value['code'].toString().trim();
      }
    } catch (_) {
      // not JSON
    }

    final trimmed = rawValue.trim();

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasQuery) {
      if (uri.queryParameters.containsKey('studentId')) return uri.queryParameters['studentId']!.trim();
      if (uri.queryParameters.containsKey('id')) return uri.queryParameters['id']!.trim();
      if (uri.queryParameters.containsKey('code')) return uri.queryParameters['code']!.trim();
    }

    return trimmed;
  }

  void _showManualEntryDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.keyboard_rounded, color: Color(0xFF25D366)),
              SizedBox(width: 8),
              Text('تسجيل حضور يدوي بالكود / الهاتف', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'اكتب كود الطالب، أو رقم هاتف الطالب أو ولي الأمر لتسجيل الحضور فوراً:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: textController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'كود أو هاتف الطالب',
                  hintText: 'مثال: Std-100 أو 010xxxxxxxx',
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final txt = textController.text.trim();
                Navigator.pop(ctx);
                if (txt.isNotEmpty) {
                  setState(() => isProcessing = true);
                  _processStudentCheckIn(txt);
                }
              },
              child: const Text('تسجيل الحضور'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      controller?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermission) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: const SectionTopBar(
          title: 'ماسح QR للحضور',
          icon: Icons.qr_code_scanner_rounded,
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF10B981)),
              SizedBox(height: 16),
              Text(
                'التحقق من صلاحية الكاميرا...',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: SectionTopBar(
          title: 'ماسح QR للحضور',
          icon: Icons.qr_code_scanner_rounded,
          extraActions: [
            IconButton(
              onPressed: _showManualEntryDialog,
              icon: const Icon(Icons.keyboard_alt_rounded, color: Color(0xFF25D366), size: 22),
              tooltip: 'إدخال كود يدوياً',
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEF4444), width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFFEF4444), size: 52),
                ),
                const SizedBox(height: 20),
                const Text(
                  'إذن الكاميرا مطلوب للمسح',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  _isPermanentlyDenied
                      ? 'تم رفض إذن الكاميرا مسبقاً في إعدادات الهاتف.\nاضغط على الزر أدناه للانتقال المباشر إلى إعدادات التطبيق وتفعيل خيار (الكاميرا).'
                      : 'يحتاج التطبيق إلى إذن الكاميرا لمسح باركود وQR كود بطاقات الطلاب وتسجيل الحضور الفوري.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5, height: 1.5),
                ),
                const SizedBox(height: 28),
                if (_isPermanentlyDenied)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    onPressed: () => openAppSettings(),
                    icon: const Icon(Icons.settings_rounded, size: 20),
                    label: const Text('فتح إعدادات التطبيق وتفعيل الكاميرا', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    onPressed: () => _checkAndRequestPermission(requestIfNeeded: true),
                    icon: const Icon(Icons.camera_alt_rounded, size: 20),
                    label: const Text('منح إذن استخدام الكاميرا الآن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _showManualEntryDialog,
                  icon: const Icon(Icons.keyboard_alt_rounded, size: 20),
                  label: const Text('تسجيل الحضور يدوياً (بالكود أو الهاتف)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: SectionTopBar(
        title: 'ماسح QR للحضور',
        icon: Icons.qr_code_scanner_rounded,
        extraActions: [
          IconButton(
            onPressed: () async {
              if (controller == null) return;
              try {
                await controller!.toggleTorch();
                setState(() => isTorchOn = !isTorchOn);
              } catch (_) {}
            },
            icon: Icon(
              isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: isTorchOn ? Colors.amber : Colors.white,
              size: 20,
            ),
            tooltip: 'فلاش',
          ),
          IconButton(
            onPressed: () async {
              try {
                if (controller != null) {
                  await controller!.switchCamera();
                  if (mounted) {
                    setState(() {
                      _currentFacing = _currentFacing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
                    });
                  }
                }
              } catch (_) {
                final next = _currentFacing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
                await _safeInitScannerController(facing: next);
              }
            },
            icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 20),
            tooltip: 'تبديل الكاميرا',
          ),
          IconButton(
            onPressed: _scanFromGallery,
            icon: const Icon(Icons.photo_library_rounded, color: Color(0xFF38BDF8), size: 21),
            tooltip: 'مسح كود من صورة / الاستوديو',
          ),
          IconButton(
            onPressed: _showManualEntryDialog,
            icon: const Icon(Icons.keyboard_alt_rounded, color: Color(0xFF25D366), size: 22),
            tooltip: 'إدخال كود يدوياً',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera Preview
          if (_isInitializingScanner || controller == null)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF25D366)),
                  SizedBox(height: 14),
                  Text('جاري تشغيل الكاميرا...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            )
          else
            MobileScanner(
              key: _scannerKey,
              controller: controller!,
              onDetect: _handleScan,
              errorBuilder: (context, error, child) {
                final isPermDenied = error.errorCode == MobileScannerErrorCode.permissionDenied;
                return Container(
                  color: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_outlined, color: Colors.amber, size: 54),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'تعذر تشغيل الكاميرا',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isPermDenied
                                ? 'تم رفض إذن الكاميرا. يرجى الضغط أدناه لفتح إعدادات الهاتف ومنح التطبيق إذن الكاميرا.'
                                : 'سبب الحالة: (${error.errorCode.name})\nقد يكون مستشعر الكاميرا مشغولاً بواسطة تطبيق آخر أو يحتاج إعادة تهيئة.\nيمكنك النقر لإعادة المحاولة، أو قراءة الكود من صورة بالاستوديو، أو إدخال الكود يدوياً.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.5),
                          ),
                          const SizedBox(height: 22),
                          if (isPermDenied)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => openAppSettings(),
                              icon: const Icon(Icons.settings_rounded, size: 20),
                              label: const Text('فتح إعدادات الهاتف ومنح الإذن', style: TextStyle(fontWeight: FontWeight.bold)),
                            )
                          else ...[
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => _safeInitScannerController(facing: _currentFacing),
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              label: const Text('إعادة تشغيل الكاميرا', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFE2E8F0),
                                side: const BorderSide(color: Color(0xFF475569)),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                final next = _currentFacing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
                                _safeInitScannerController(facing: next);
                              },
                              icon: const Icon(Icons.flip_camera_android_rounded, size: 19),
                              label: Text(
                                _currentFacing == CameraFacing.back ? 'تجربة الكاميرا الأمامية' : 'تجربة الكاميرا الخلفية',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF38BDF8),
                              side: const BorderSide(color: Color(0xFF38BDF8)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _scanFromGallery,
                            icon: const Icon(Icons.photo_library_rounded, size: 19),
                            label: const Text('مسح كود من صورة في الاستوديو', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF25D366),
                              side: const BorderSide(color: Color(0xFF25D366)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _showManualEntryDialog,
                            icon: const Icon(Icons.keyboard_alt_rounded, size: 19),
                            label: const Text('أدخل كود أو هاتف الطالب يدوياً', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // Scanner Target Frame
          Center(
            child: Container(
              width: 270,
              height: 270,
              decoration: BoxDecoration(
                border: Border.all(
                  color: isProcessing ? const Color(0xFF10B981) : const Color(0xFF25D366),
                  width: 3.5,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: (isProcessing ? const Color(0xFF10B981) : const Color(0xFF25D366)).withValues(alpha: 0.25),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),

          // Processing Indicator
          if (isProcessing)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF10B981)),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'جاري تسجيل الحضور...',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Bar Overlay
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lastScannedName != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF10B981), width: 1.2),
                    ),
                    child: Column(
                      children: [
                        Text(
                          lastScannedName!,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lastScannedStatus ?? '',
                          style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
                Card(
                  color: const Color(0xDD0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0x3338BDF8)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF25D366), size: 24),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'وجّه الكاميرا نحو كود الطالب، أو سجّل يدوياً بالزر ⌨️',
                            style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF38BDF8),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: _showManualEntryDialog,
                          icon: const Icon(Icons.edit_note_rounded, size: 18),
                          label: const Text('يدوي', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
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
}
