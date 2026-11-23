import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ContactResult {
  final String phone;
  final String name;

  const ContactResult({
    required this.phone,
    required this.name,
  });

  @override
  String toString() => 'ContactResult(name: $name, phone: $phone)';
}

class ContactPickerService {
  static const MethodChannel _channel = MethodChannel('com.example.teacher_center/contacts');

  /// Opens the device native contact directory to pick a contact number and name.
  /// Returns [ContactResult] with the cleaned phone number and contact name, or `null` if cancelled.
  static Future<ContactResult?> pickContact() async {
    try {
      final res = await _channel.invokeMethod<Map>('pickContact');
      if (res == null) return null;

      final rawPhone = (res['phone'] ?? '').toString();
      final name = (res['name'] ?? '').toString().trim();

      // Normalize digits from Eastern Arabic / Persian to ASCII
      var phone = rawPhone.trim();
      const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
      const persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
      for (int i = 0; i < 10; i++) {
        phone = phone.replaceAll(arabicDigits[i], '$i');
        phone = phone.replaceAll(persianDigits[i], '$i');
      }

      // Remove spaces, hyphens, parentheses
      var clean = phone.replaceAll(RegExp(r'[^\d+]'), '');

      // Normalize Egypt mobile numbers to standard 01XXXXXXXXX format for local entry
      if (clean.startsWith('+20') && clean.length == 13 && clean.startsWith('+201')) {
        clean = '0${clean.substring(3)}';
      } else if (clean.startsWith('0020') && clean.length == 14 && clean.startsWith('00201')) {
        clean = '0${clean.substring(4)}';
      } else if (clean.startsWith('20') && clean.length == 12 && clean.startsWith('201')) {
        clean = '0${clean.substring(2)}';
      } else if (clean.startsWith('+')) {
        clean = clean.substring(1);
      }

      return ContactResult(phone: clean, name: name);
    } catch (e) {
      debugPrint('ContactPickerService: Error opening contact picker: $e');
      return null;
    }
  }
}
