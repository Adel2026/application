import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'database/database_service.dart';

class SecurityService {
  static final LocalAuthentication _localAuth = LocalAuthentication();

  /// Authenticate with Biometrics / Fingerprint specifically for early attendance bypass
  static Future<bool> authenticateWithBiometrics({
    required BuildContext context,
    required DatabaseService database,
    required String reason,
  }) async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      if (canCheck || isSupported) {
        final didAuth = await _localAuth.authenticate(
          localizedReason: reason,
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
            useErrorDialogs: true,
          ),
        );
        return didAuth;
      }
    } catch (e) {
      debugPrint('Biometric auth error: $e');
    }

    if (!context.mounted) return false;
    // Fallback to PIN dialog if device doesn't have biometric hardware enrolled
    return await showPinVerificationDialog(context: context, database: database);
  }

  /// Authenticate using Biometrics if available, otherwise fallback to PIN dialog
  static Future<bool> authenticate({
    required BuildContext context,
    required DatabaseService database,
    String reason = 'يرجى تأكيد الهوية للمتابعة وحماية البيانات',
    bool fallbackToPinDialog = true,
  }) async {
    final pinEnabledStr = await database.getSetting('security_require_auth', defaultValue: 'true');
    if (pinEnabledStr == 'false') {
      return true;
    }

    // Try Biometrics first if enabled
    final biometricsEnabled = await database.getSetting('security_biometrics_enabled', defaultValue: 'true');
    bool biometricsAttempted = false;

    if (biometricsEnabled == 'true') {
      try {
        final canCheck = await _localAuth.canCheckBiometrics;
        final isSupported = await _localAuth.isDeviceSupported();

        if (canCheck || isSupported) {
          biometricsAttempted = true;
          final didAuth = await _localAuth.authenticate(
            localizedReason: reason,
            options: const AuthenticationOptions(
              stickyAuth: true,
              biometricOnly: false,
              useErrorDialogs: true,
            ),
          );
          if (didAuth) return true;
          // If biometric dialog was shown and user dismissed/cancelled, do not force another dialog
          return false;
        }
      } catch (e) {
        debugPrint('Biometric auth error: $e');
      }
    }

    if (!context.mounted) return false;

    // Fallback to PIN Dialog only if biometrics was not available/attempted
    if (!biometricsAttempted && fallbackToPinDialog) {
      return await showPinVerificationDialog(context: context, database: database);
    }

    return false;
  }

  /// Show PIN verification dialog
  static Future<bool> showPinVerificationDialog({
    required BuildContext context,
    required DatabaseService database,
  }) async {
    final expectedPin = await database.getSetting('security_pin', defaultValue: '1234');
    final pinController = TextEditingController();
    bool isPinWrong = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            final theme = Theme.of(ctx);
            final isDark = theme.brightness == Brightness.dark;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_rounded, color: Colors.red, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text('تأكيد رمز الأمان (PIN)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'هذا الإجراء محمي لتجنب التعديل أو الحذف الخاطئ للبيانات.\nيرجى كتابة رمز الأمان (الافتراضي 1234):',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      autofocus: true,
                      maxLength: 8,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '••••',
                        errorText: isPinWrong ? 'رمز الأمان غير صحيح، حاول مرة أخرى' : null,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                        ),
                      ),
                      onSubmitted: (val) {
                        if (val.trim() == expectedPin) {
                          Navigator.pop(dialogCtx, true);
                        } else {
                          setState(() => isPinWrong = true);
                        }
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx, false),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      if (pinController.text.trim() == expectedPin) {
                        Navigator.pop(dialogCtx, true);
                      } else {
                        setState(() => isPinWrong = true);
                      }
                    },
                    child: const Text('تأكيد'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    return result ?? false;
  }

  /// Check if hardware supports biometrics
  static Future<bool> isBiometricsSupported() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Dialog to set or change security PIN
  static Future<bool> showChangePinDialog({
    required BuildContext context,
    required DatabaseService database,
  }) async {
    final currentPin = await database.getSetting('security_pin', defaultValue: '1234');
    final oldPinCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    final confirmPinCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        String? errorMessage;
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                title: const Row(
                  children: [
                    Icon(Icons.password_rounded, color: Color(0xFF10B981), size: 24),
                    SizedBox(width: 10),
                    Text('تعيين / تغيير رمز الأمان (PIN)', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: oldPinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'رمز الأمان الحالي (الافتراضي 1234)',
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newPinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'رمز الأمان الجديد (4 إلى 8 أرقام)',
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPinCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'تأكيد رمز الأمان الجديد',
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx, false),
                    child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                    onPressed: () async {
                      final oldP = oldPinCtrl.text.trim();
                      final newP = newPinCtrl.text.trim();
                      final confP = confirmPinCtrl.text.trim();

                      if (oldP != currentPin) {
                        setState(() => errorMessage = 'رمز الأمان الحالي غير صحيح');
                        return;
                      }
                      if (newP.length < 4) {
                        setState(() => errorMessage = 'يجب أن يتكون الرمز الجديد من 4 أرقام على الأقل');
                        return;
                      }
                      if (newP != confP) {
                        setState(() => errorMessage = 'الرمز الجديد وتأكيده غير متطابقين');
                        return;
                      }

                      await database.setSetting('security_pin', newP);
                      database.notifyChange(DataChangeEvent.settings);
                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx, true);
                      }
                    },
                    child: const Text('حفظ الرمز الجديد'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    return result ?? false;
  }
}
