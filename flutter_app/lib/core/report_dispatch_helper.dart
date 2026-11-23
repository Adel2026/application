import 'package:flutter/material.dart';
import '../models/student_model.dart';
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
  /// تخصيص ديباجة التقرير لصلة قرابة ولي الأمر (والد، والدة، أخ، إلخ)
  static String personalizeReportForGuardian(String message, GuardianContact guardian, String studentName) {
    final rel = guardian.relationship.trim();
    if (rel.isEmpty || rel == 'ولي أمر') return message;

    String salutation = '';
    if (rel == 'والد') {
      salutation = 'السيد الفاضل (والد الطالب: $studentName)';
    } else if (rel == 'والدة') {
      salutation = 'السيدة الفاضلة (والدة الطالب: $studentName)';
    } else if (rel.contains('أخ')) {
      salutation = 'الأخ الفاضل (أخو الطالب: $studentName)';
    } else if (rel.contains('أخت')) {
      salutation = 'الأخت الفاضلة (أخت الطالب: $studentName)';
    } else {
      salutation = 'السيد الفاضل ($rel الطالب: $studentName)';
    }

    if (guardian.name.isNotEmpty) {
      salutation = '$salutation / ${guardian.name}';
    }

    if (message.contains('ولي أمر الطالب المحترم')) {
      return message.replaceFirst('ولي أمر الطالب المحترم', salutation);
    }

    if (message.contains('السلام عليكم ورحمة الله وبركاته 🌸')) {
      return message.replaceFirst(
        'السلام عليكم ورحمة الله وبركاته 🌸',
        'السلام عليكم ورحمة الله وبركاته 🌸\n$salutation',
      );
    }

    if (message.contains('السلام عليكم ورحمة الله وبركاته')) {
      return message.replaceFirst(
        'السلام عليكم ورحمة الله وبركاته',
        'السلام عليكم ورحمة الله وبركاته\n$salutation',
      );
    }

    return '$salutation\n$message';
  }

  /// نافذة اختيار ولي الأمر عند وجود أكثر من ولي أمر للطالب
  static Future<List<GuardianContact>?> showGuardianPickerSheet({
    required BuildContext context,
    required List<GuardianContact> guardians,
    required String studentName,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = Set<int>.from(List.generate(guardians.length, (i) => i));

    return showModalBottomSheet<List<GuardianContact>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.family_restroom_rounded, color: Color(0xFF25D366), size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('إرسال التقرير لأولياء الأمور 📲', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              Text('اختر من ترغب بإرسال التقرير إليه للطالب: $studentName', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(guardians.length, (i) {
                      final g = guardians[i];
                      final isChecked = selected.contains(i);
                      final relLabel = g.relationship.isNotEmpty ? g.relationship : 'ولي أمر';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isChecked ? const Color(0xFF25D366).withValues(alpha: 0.12) : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isChecked ? const Color(0xFF25D366) : Colors.transparent),
                        ),
                        child: CheckboxListTile(
                          activeColor: const Color(0xFF25D366),
                          value: isChecked,
                          onChanged: (val) {
                            setModalState(() {
                              if (val == true) {
                                selected.add(i);
                              } else {
                                if (selected.length > 1) selected.remove(i);
                              }
                            });
                          },
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  relLabel,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF25D366)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  g.name.isNotEmpty ? g.name : relLabel,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (g.isPrimary)
                                const Text('⭐ رئيسي', style: TextStyle(fontSize: 10, color: Colors.amber)),
                            ],
                          ),
                          subtitle: Text(g.phone, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                      );
                    }),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text('متابعة وإرسال للمحددين (${selected.length}) 🚀', style: const TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          final list = selected.map((i) => guardians[i]).toList();
                          Navigator.pop(ctx, list);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

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
    List<GuardianContact>? guardians,
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

    // 2. الإرسال إلى واتساب لأولياء الأمور
    if (channel == ReportDispatchChannel.whatsappOnly || channel == ReportDispatchChannel.both) {
      final targetGuardians = (guardians != null && guardians.isNotEmpty)
          ? guardians
          : [GuardianContact(name: '', phone: parentPhone, relationship: 'ولي أمر', isPrimary: true)];

      List<GuardianContact> selectedGuardians = targetGuardians;
      if (targetGuardians.length > 1 && context.mounted) {
        final chosen = await showGuardianPickerSheet(
          context: context,
          guardians: targetGuardians,
          studentName: studentName,
        );
        if (chosen != null && chosen.isNotEmpty) {
          selectedGuardians = chosen;
        }
      }

      for (final g in selectedGuardians) {
        if (g.phone.trim().isNotEmpty) {
          final personalized = personalizeReportForGuardian(reportMessage, g, studentName);
          WhatsAppService.openWhatsApp(
            phone: g.phone,
            message: personalized,
          );

          if (database != null) {
            try {
              await database.logWhatsAppMessage(
                studentId: studentId,
                studentName: studentName,
                phone: g.phone,
                recipientType: 'parent',
                category: notifType,
                message: personalized,
                status: 'sent',
              );
            } catch (e) {
              debugPrint('Error logging message: $e');
            }
          }
        }
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
