import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class TeacherUpdateService {
  static final TeacherUpdateService instance = TeacherUpdateService._internal();
  TeacherUpdateService._internal();

  bool _isChecking = false;
  bool _dialogShown = false;

  /// فحص توفر تحديث جديد لتطبيق المعلم عبر السحابة
  Future<void> checkForUpdate(BuildContext context, {bool showNoUpdateToast = false}) async {
    if (_isChecking || _dialogShown) return;
    _isChecking = true;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1;

      final doc = await FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('system_config')
          .doc('teacher_app_version')
          .get();

      if (!doc.exists || doc.data() == null) {
        if (showNoUpdateToast && context.mounted) {
          _showToast(context, 'أنت تستخدم أحدث إصدار لتطبيق المعلم (v$currentVersion) ✅');
        }
        return;
      }

      final data = doc.data()!;
      final latestBuild = int.tryParse('${data['latest_version_code'] ?? 0}') ?? 0;
      final latestVersion = (data['latest_version_name'] ?? '').toString();
      final downloadUrl = (data['download_url'] ?? '').toString();
      final releaseNotes = (data['release_notes'] ?? '').toString();
      final isMandatory = data['is_mandatory'] == true;

      int normalizeBuild(int b) => b >= 1000 ? (b % 1000) : b;
      final normCurrent = normalizeBuild(currentBuild);
      final normLatest = normalizeBuild(latestBuild);

      final versionCmp = _compareVersions(latestVersion, currentVersion);
      bool isUpdateAvailable = false;
      if (downloadUrl.isNotEmpty) {
        if (versionCmp > 0) {
          isUpdateAvailable = true;
        } else if (versionCmp == 0) {
          if (normLatest > normCurrent || latestBuild > currentBuild) {
            isUpdateAvailable = true;
          }
        } else {
          if (latestBuild > currentBuild) {
            isUpdateAvailable = true;
          }
        }
      }

      if (isUpdateAvailable && context.mounted) {
        _dialogShown = true;
        await _showUpdateDialog(
          context: context,
          currentVersion: currentVersion,
          latestVersion: latestVersion.isNotEmpty ? latestVersion : 'v$latestBuild',
          downloadUrl: downloadUrl,
          releaseNotes: releaseNotes,
          isMandatory: isMandatory,
        );
        _dialogShown = false;
      } else if (showNoUpdateToast && context.mounted) {
        _showToast(context, 'أنت تستخدم أحدث إصدار لتطبيق المعلم (v$currentVersion) ✅');
      }
    } catch (e) {
      debugPrint('Teacher update check error: $e');
      if (showNoUpdateToast && context.mounted) {
        _showToast(context, 'تعذر التحقق من التحديثات. تحقق من اتصال الإنترنت.');
      }
    } finally {
      _isChecking = false;
    }
  }

  static int _compareVersions(String v1, String v2) {
    if (v1.isEmpty || v2.isEmpty) return 0;
    try {
      final p1 = v1.replaceAll('v', '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final p2 = v2.replaceAll('v', '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
      for (int i = 0; i < 3; i++) {
        final val1 = i < p1.length ? p1[i] : 0;
        final val2 = i < p2.length ? p2[i] : 0;
        if (val1 > val2) return 1;
        if (val1 < val2) return -1;
      }
    } catch (_) {}
    return 0;
  }

  /// نافذة عرض تفاصيل التحديث الجديد لتطبيق المعلم مع التحميل والتثبيت المباشر داخلياً
  Future<void> _showUpdateDialog({
    required BuildContext context,
    required String currentVersion,
    required String latestVersion,
    required String downloadUrl,
    required String releaseNotes,
    required bool isMandatory,
  }) async {
    HapticFeedback.heavyImpact();

    // حالة التحميل الداخلي
    bool isDownloading = false;
    double progress = 0.0;
    String statusText = 'جاري التجهيز...';
    String progressDetail = '';
    String? errorMessage;
    HttpClient? activeClient;

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            Future<void> startInAppDownload() async {
              setDialogState(() {
                isDownloading = true;
                progress = 0.0;
                statusText = 'جاري الاتصال بالسيرفر السحابي...';
                progressDetail = '';
                errorMessage = null;
              });

              try {
                final client = HttpClient();
                activeClient = client;
                client.badCertificateCallback = ((X509Certificate cert, String host, int port) => true);

                Uri currentUri = Uri.parse(downloadUrl);
                HttpClientResponse? response;

                // تتبع الـ Redirects تلقائياً لضمان الوصول للملف المباشر
                for (int i = 0; i < 5; i++) {
                  final request = await client.getUrl(currentUri);
                  request.followRedirects = false;
                  response = await request.close();

                  if (response.isRedirect) {
                    final location = response.headers.value(HttpHeaders.locationHeader);
                    if (location != null) {
                      currentUri = Uri.parse(location);
                      continue;
                    }
                  }
                  break;
                }

                if (response == null || response.statusCode != 200) {
                  throw Exception('فشل الاتصال برابط التحديث (كود ${response?.statusCode})');
                }

                final tempDir = await getTemporaryDirectory();
                final apkFile = File('${tempDir.path}/teacher_app_update.apk');
                if (await apkFile.exists()) {
                  try {
                    await apkFile.delete();
                  } catch (_) {}
                }

                final sink = apkFile.openWrite();
                final totalBytes = response.contentLength;
                int receivedBytes = 0;

                await response.listen(
                  (List<int> chunk) {
                    receivedBytes += chunk.length;
                    sink.add(chunk);
                    if (totalBytes > 0) {
                      progress = receivedBytes / totalBytes;
                    }
                    setDialogState(() {
                      statusText = 'جاري تنزيل تحديث المعلم داخلياً...';
                      progressDetail = totalBytes > 0
                          ? '${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB من أصل ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB (${(progress * 100).toInt()}%)'
                          : '${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB تم تنزيلها...';
                    });
                  },
                  cancelOnError: true,
                ).asFuture();

                await sink.flush();
                await sink.close();
                client.close();

                setDialogState(() {
                  statusText = 'اكتمل التنزيل! جاري فتح التثبيت... 🚀';
                  progress = 1.0;
                });

                // طلب التثبيت التلقائي عبر MethodChannel
                const platform = MethodChannel('com.eduacademy/app_installer');
                await platform.invokeMethod('installApk', {'filePath': apkFile.path});
              } catch (e) {
                debugPrint('Teacher download/install error: $e');
                setDialogState(() {
                  isDownloading = false;
                  errorMessage = 'حدث خطأ أثناء التنزيل: ${e.toString().replaceAll('Exception: ', '')}';
                });
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.25),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon Header
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            isDownloading ? Icons.cloud_download_rounded : Icons.rocket_launch_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Text(
                        isDownloading ? 'جاري تحديث سنتر المعلم ⏳' : 'تحديث جديد متوفر لسنتر المعلم! 🚀',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'الإصدار الحالي: v$currentVersion  ➔  الجديد: v$latestVersion',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Progress Section (إذا كان قيد التنزيل)
                      if (isDownloading) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            children: [
                              Text(
                                statusText,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF38BDF8),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: progress > 0 ? progress : null,
                                  minHeight: 10,
                                  backgroundColor: const Color(0xFF334155),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                                ),
                              ),
                              if (progressDetail.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  progressDetail,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ] else ...[
                        if (releaseNotes.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.stars_rounded, color: Color(0xFFFBBF24), size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'المميزات والإصلاحات في هذا التحديث:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFFBBF24),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  releaseNotes,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFCBD5E1),
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],

                      // Error message if any
                      if (errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(fontSize: 11.5, color: Colors.redAccent),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],

                      if (isMandatory) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'هذا التحديث إلزامي لمواصلة استخدام مميزات سنتر المعلم السحابية.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFFFCA5A5), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Action Buttons
                      if (!isDownloading) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 4,
                            ),
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              startInAppDownload();
                            },
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.downloading_rounded, size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'تحديث وتثبيت تلقائي الآن 🚀',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // زر المتصفح البديل في حال واجه مشاكل في الاتصال
                        if (errorMessage != null) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse(downloadUrl);
                              try {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } catch (_) {
                                await Clipboard.setData(ClipboardData(text: downloadUrl));
                              }
                            },
                            icon: const Icon(Icons.open_in_browser_rounded, size: 16, color: Color(0xFF38BDF8)),
                            label: const Text(
                              'تنزيل عبر المتصفح الخارجي كحل بديل',
                              style: TextStyle(fontSize: 11.5, color: Color(0xFF38BDF8)),
                            ),
                          ),
                        ],

                        if (!isMandatory) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text(
                              'تذكيري لاحقاً ⏳',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            ),
                          ),
                        ],
                      ] else ...[
                        if (!isMandatory)
                          TextButton(
                            onPressed: () {
                              try {
                                activeClient?.close(force: true);
                              } catch (_) {}
                              setDialogState(() {
                                isDownloading = false;
                                errorMessage = 'تم إلغاء التنزيل.';
                              });
                            },
                            child: const Text(
                              'إلغاء التنزيل',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// نافذة لنشر تحديث جديد لتطبيق المعلم أو تطبيق الطالب من لوحة التحكم
  static Future<void> showPublishTeacherUpdateDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final urlController = TextEditingController();
    final notesController = TextEditingController();
    bool isMandatory = false;
    bool isSaving = false;

    // جلب الإصدار الحالي من التطبيق
    try {
      final info = await PackageInfo.fromPlatform();
      nameController.text = info.version;
      final currentCode = int.tryParse(info.buildNumber) ?? 1;
      codeController.text = '${currentCode + 1}';
    } catch (_) {
      nameController.text = '1.2.0';
      codeController.text = '2118';
    }

    notesController.text = '• تحسينات في استقرار المزامنة وسرعة التقارير\n• تحديثات في نظام الإشعارات والتحكم الأمني';

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.cloud_upload_rounded, color: Color(0xFF38BDF8), size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'نشر تحديث لتطبيق المعلم 🚀',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'بمجرد حفظ هذا التحديث، سيتعرف تطبيق المعلم على التحديث فوراً ويطلب تنزيله:',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'اسم الإصدار',
                          labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                          hintText: '1.2.0',
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: codeController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'كود البناء',
                          labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                          hintText: '2118',
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  decoration: InputDecoration(
                    labelText: 'رابط التحميل المباشر للـ APK',
                    labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                    hintText: 'https://github.com/.../teacher-app.apk',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  decoration: InputDecoration(
                    labelText: 'مميزات وملاحظات التحديث',
                    labelStyle: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تحديث إجباري ⚠️', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: const Text('منع استخدام النسخة الحالية حتى التحديث', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  value: isMandatory,
                  activeTrackColor: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                  thumbColor: WidgetStateProperty.resolveWith<Color>((states) => states.contains(WidgetState.selected) ? const Color(0xFF38BDF8) : Colors.grey),
                  onChanged: (val) => setDialogState(() => isMandatory = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('نشر التحديث الآن 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: isSaving
                  ? null
                  : () async {
                      final vName = nameController.text.trim();
                      final vCode = int.tryParse(codeController.text.trim()) ?? 1;
                      final vUrl = urlController.text.trim();
                      final vNotes = notesController.text.trim();

                      if (vUrl.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('يرجى إدخال رابط تحميل مباشر لملف APK الخاص بالمعلم'),
                            backgroundColor: Color(0xFFEF4444),
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      try {
                        await FirebaseFirestore.instance
                            .collection('academies')
                            .doc('default')
                            .collection('system_config')
                            .doc('teacher_app_version')
                            .set({
                          'latest_version_name': vName,
                          'latest_version_code': vCode,
                          'download_url': vUrl,
                          'release_notes': vNotes,
                          'is_mandatory': isMandatory,
                          'published_at': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('تم نشر تحديث تطبيق المعلم (v$vName) بنجاح! 🚀'),
                              backgroundColor: const Color(0xFF10B981),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('فشل نشر التحديث: $e'),
                              backgroundColor: const Color(0xFFEF4444),
                            ),
                          );
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  static void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF38BDF8), width: 1),
        ),
      ),
    );
  }
}
