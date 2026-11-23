import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

class StudentUpdateService {
  static final StudentUpdateService instance = StudentUpdateService._internal();
  StudentUpdateService._internal();

  bool _isChecking = false;
  bool _dialogShown = false;
  bool _hasPromptedThisSession = false;

  /// مقارنة إصدارين بنظام Semantic Versioning (مثل 1.0.12 مقابل 1.0.11)
  static int compareVersions(String v1, String v2) {
    try {
      final p1 = v1.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final p2 = v2.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final len = p1.length > p2.length ? p1.length : p2.length;
      for (int i = 0; i < len; i++) {
        final a = i < p1.length ? p1[i] : 0;
        final b = i < p2.length ? p2[i] : 0;
        if (a != b) return a.compareTo(b);
      }
    } catch (_) {}
    return 0;
  }

  /// فحص توفر تحديث جديد لتطبيق الطالب ومطابقته مع سحابة المعلم
  Future<void> checkForUpdate(BuildContext context, {bool showNoUpdateToast = false}) async {
    if (_isChecking || _dialogShown) return;
    if (!showNoUpdateToast && _hasPromptedThisSession) return;
    _isChecking = true;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1;

      final doc = await FirebaseFirestore.instance
          .collection('academies')
          .doc('default')
          .collection('system_config')
          .doc('student_app_version')
          .get();

      if (!doc.exists || doc.data() == null) {
        if (showNoUpdateToast && context.mounted) {
          _showToast(context, 'أنت تستخدم أحدث إصدار بالفعل (v$currentVersion) ✅');
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

      final versionCmp = compareVersions(latestVersion, currentVersion);

      // التحقق الدقيق لمنع تكرار طلب التحديث في حلقة لا نهائية:
      // 1. إذا كان رقم الإصدار أحدث (مثال 1.0.12 > 1.0.11)
      // 2. أو إذا كان رقم الإصدار متطابقاً ولكن كود البناء أحدث (مثال 15 > 12)
      bool isUpdateAvailable = false;
      if (downloadUrl.isNotEmpty) {
        if (versionCmp > 0) {
          isUpdateAvailable = true;
        } else if (versionCmp == 0) {
          if (normLatest > normCurrent) {
            isUpdateAvailable = true;
          }
        }
      }

      if (isUpdateAvailable && context.mounted) {
        _dialogShown = true;
        _hasPromptedThisSession = true;
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
        _showToast(context, 'أنت تستخدم أحدث إصدار بالفعل (v$currentVersion) ✅');
      }
    } catch (e) {
      debugPrint('Update check error: $e');
      if (showNoUpdateToast && context.mounted) {
        _showToast(context, 'تعذر التحقق من التحديثات. تحقق من اتصال الإنترنت.');
      }
    } finally {
      _isChecking = false;
    }
  }

  /// نافذة عرض التحديث العصري الفخم مع التحميل والتثبيت المباشر داخل التطبيق
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
                final apkFile = File('${tempDir.path}/student_app_update.apk');
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
                      statusText = 'جاري تنزيل التحديث داخلياً...';
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
                final installResult = await platform.invokeMethod('installApk', {'filePath': apkFile.path});
                if (installResult == false) {
                  setDialogState(() {
                    statusText = 'يرجى تفعيل خيار تثبيت التطبيق من الإعدادات ثم إعادة المحاولة ⚙️';
                    isDownloading = false;
                  });
                }
              } catch (e) {
                debugPrint('Download/Install error: $e');
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
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFF00F2FE).withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon Header with Glow
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00F2FE), Color(0xFF10B981)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00F2FE).withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          isDownloading ? Icons.cloud_download_rounded : Icons.rocket_launch_rounded,
                          color: const Color(0xFF060911),
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Text(
                      isDownloading ? 'جاري تحديث التطبيق ⏳' : 'تحديث جديد متوفر للتطبيق! 🚀',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textLight,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),

                    // Version Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'الإصدار الحالي: v$currentVersion  ➔  الجديد: v$latestVersion',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00F2FE),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Progress Section (إذا كان قيد التنزيل)
                    if (isDownloading) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
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
                                color: Color(0xFF00F2FE),
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
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00F2FE)),
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
                      // Release Notes Box
                      if (releaseNotes.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.auto_awesome_rounded, color: Color(0xFFFBBF24), size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'ما الجديد في هذا التحديث:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFBBF24),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                releaseNotes,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFCBD5E1),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ],

                    // Error Box if any
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

                    // Action Buttons
                    if (!isDownloading) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00F2FE),
                            foregroundColor: const Color(0xFF04101E),
                            padding: const EdgeInsets.symmetric(vertical: 13),
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
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
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
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.textMuted,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(ctx);
                          },
                          child: const Text('تذكيري لاحقاً ⏳', style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ] else ...[
                      // إلغاء التحميل
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
            );
          },
        ),
      ),
    );
  }

  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFF00F2FE), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
