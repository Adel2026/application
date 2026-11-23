import 'package:flutter/material.dart';
import 'academy_communication_service.dart';
import 'database/database_service.dart';
import 'whatsapp_service.dart';

enum ReportDispatchChannel {
  appOnly,
  whatsappOnly,
  both,
}

class ReportDispatchHelper {
  /// عرض نافذة اختيار وجهة إرسال التقرير (تطبيق الطالب، واتساب، أو الاثنين)
  static Future<ReportDispatchChannel?> showChannelPicker({
    required BuildContext context,
    required String studentName,
    String reportTitle = 'تقرير متابعة الطالب',
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<ReportDispatchChannel>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // مقبض السحب
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // العنوان
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Color(0xFF00F2FE), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reportTitle,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اختر وجهة الإرسال للطالب: $studentName',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // الخيار 1: الاثنين معاً (الموصى به)
                _buildChannelTile(
                  ctx: ctx,
                  channel: ReportDispatchChannel.both,
                  title: 'الاثنين معاً (تطبيق الطالب + واتساب) 🚀',
                  subtitle: 'إشعار فوري داخل تطبيق الطالب وفتح رسالة واتساب لولي الأمر',
                  icon: Icons.rocket_launch_rounded,
                  color: const Color(0xFFF59E0B),
                  isDark: isDark,
                  isRecommended: true,
                ),
                const SizedBox(height: 10),

                // الخيار 2: تطبيق الطالب فقط
                _buildChannelTile(
                  ctx: ctx,
                  channel: ReportDispatchChannel.appOnly,
                  title: 'تطبيق الطالب فقط 📱',
                  subtitle: 'إرسال إشعار رسمي وتوثيق التقرير في محادثة الطالب بالتطبيق',
                  icon: Icons.stay_current_portrait_rounded,
                  color: const Color(0xFF00F2FE),
                  isDark: isDark,
                ),
                const SizedBox(height: 10),

                // الخيار 3: واتساب فقط
                _buildChannelTile(
                  ctx: ctx,
                  channel: ReportDispatchChannel.whatsappOnly,
                  title: 'واتساب فقط 💬',
                  subtitle: 'فتح محادثة ولي الأمر على واتساب وإرسال التقرير نصياً',
                  icon: Icons.chat_bubble_rounded,
                  color: const Color(0xFF25D366),
                  isDark: isDark,
                ),
                const SizedBox(height: 14),

                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildChannelTile({
    required BuildContext ctx,
    required ReportDispatchChannel channel,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    bool isRecommended = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(ctx, channel),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRecommended ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              width: isRecommended ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                        ),
                        if (isRecommended) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'موصى به',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  /// إرسال التقرير حسب القناة المختارة مع المعالجة التلقائية الكاملة
  static Future<ReportDispatchChannel?> dispatchReport({
    required BuildContext context,
    required String studentId,
    required String studentName,
    required String studentCode,
    required String parentPhone,
    required String reportTitle,
    required String reportMessage,
    String notifType = 'general',
    DatabaseService? database,
  }) async {
    final channel = await showChannelPicker(
      context: context,
      studentName: studentName,
      reportTitle: reportTitle,
    );

    if (channel == null) return null;

    final commService = AcademyCommunicationService.instance;

    // 1. الإرسال إلى تطبيق الطالب
    if (channel == ReportDispatchChannel.appOnly || channel == ReportDispatchChannel.both) {
      try {
        // إرسال إشعار رسمي
        await commService.sendNotification(
          title: '📋 $reportTitle',
          body: reportMessage.length > 250
              ? '${reportMessage.substring(0, 247)}...'
              : reportMessage,
          type: notifType,
          targetType: 'student',
          targetId: studentId,
          targetName: studentName,
        );

        // إرسال التقرير داخل محادثة الطالب ليبقى محفوظاً في سجله
        await commService.sendMessageFromTeacher(
          studentId: studentId,
          studentName: studentName,
          studentCode: studentCode,
          text: reportMessage,
        );
      } catch (e) {
        debugPrint('Error sending report to student app: $e');
      }
    }

    // 2. الإرسال إلى واتساب
    if (channel == ReportDispatchChannel.whatsappOnly || channel == ReportDispatchChannel.both) {
      if (parentPhone.trim().isNotEmpty) {
        WhatsAppService.openWhatsApp(
          phone: parentPhone,
          message: reportMessage,
        );
      }
    }

    // 3. تسجيل في قاعدة البيانات إن وُجدت
    if (database != null) {
      try {
        await database.logWhatsAppMessage(
          studentId: studentId,
          studentName: studentName,
          phone: parentPhone,
          recipientType: 'parent',
          category: notifType,
          message: reportMessage,
          status: 'sent',
        );
      } catch (e) {
        debugPrint('Error logging message: $e');
      }
    }

    // إشعار نجاح
    if (context.mounted) {
      String successMsg;
      switch (channel) {
        case ReportDispatchChannel.appOnly:
          successMsg = 'تم إرسال التقرير إلى تطبيق الطالب بنجاح 📱';
          break;
        case ReportDispatchChannel.whatsappOnly:
          successMsg = 'جاري فتح محادثة الواتساب لإرسال التقرير 💬';
          break;
        case ReportDispatchChannel.both:
          successMsg = 'تم إرسال التقرير لتطبيق الطالب وجاري فتح الواتساب 🚀';
          break;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return channel;
  }
}
