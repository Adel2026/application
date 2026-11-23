import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'database/database_service.dart';
import 'security_service.dart';

class BackupService {
  /// Checkpoints the SQLite WAL and creates a clean .db copy with timestamp
  static Future<File> createLocalBackup(DatabaseService database) async {
    final db = await database.database;
    // Checkpoint WAL so all in-memory or WAL data is committed into main .db
    await db.rawQuery('PRAGMA wal_checkpoint(FULL);');

    final dbPath = await database.getDatabaseFilePath();
    final dbFile = File(dbPath);

    final appDocDir = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(path.join(appDocDir.path, 'backups'));
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }

    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final backupFileName = 'EduAcademy_Backup_$timestamp.db';
    final targetPath = path.join(backupsDir.path, backupFileName);
    final backupFile = await dbFile.copy(targetPath);

    // Also attempt saving a copy to the public Downloads folder for easy direct phone access
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final publicTarget = path.join(downloadDir.path, backupFileName);
        await dbFile.copy(publicTarget);
      }
    } catch (_) {}

    return backupFile;
  }

  /// Exports the backup file directly to Google Drive or other apps via the Android native share sheet
  /// Zero Google API configuration or OAuth required!
  static Future<void> shareToGoogleDriveOrCloud({
    required BuildContext context,
    required DatabaseService database,
  }) async {
    final file = await createLocalBackup(database);
    final fileName = path.basename(file.path);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            name: fileName,
            mimeType: 'application/x-sqlite3',
          ),
        ],
        subject: 'نسخة احتياطية لتطبيق سنتر أستاذي - $fileName',
        text:
            'نسخة احتياطية لقاعدة بيانات سنتر أستاذي.\nيمكنك حفظها مباشرة في Google Drive أو إرسالها إلى واتساب أو البريد الإلكتروني.',
      ),
    );
  }

  /// Restores database from a user-selected .db backup file
  static Future<bool> restoreBackupWithPicker({
    required BuildContext context,
    required DatabaseService database,
  }) async {
    // 1. Authenticate with PIN or Biometric first
    final authenticated = await SecurityService.authenticate(
      context: context,
      database: database,
      reason:
          'يرجى تأكيد الهوية لاستعادة النسخة الاحتياطية واستبدال البيانات الحالية',
    );
    if (!authenticated) return false;

    // 2. Pick backup file
    final files = await FilePicker.pickFiles(
      type: FileType.any,
    );
    if (files.isEmpty || files.first.path == null) {
      return false;
    }

    final sourcePath = files.first.path!;
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return false;

    if (!await database.isDatabaseBackupValid(sourcePath)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            content: Text('الملف المحدد ليس نسخة قاعدة بيانات صالحة للتطبيق.'),
          ),
        );
      }
      return false;
    }

    if (!context.mounted) return false;

    // 3. Confirm overwrite
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              SizedBox(width: 10),
              Text('تأكيد استعادة النسخة الاحتياطية',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الملف المختار: ${path.basename(sourcePath)}',
                style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
              const SizedBox(height: 10),
              const Text(
                'تنبيه: سيتم استبدال جميع البيانات الحالية بالبيانات الموجودة في هذا الملف. هل أنت متأكد من الاستمرار؟',
                style: TextStyle(
                    color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استعادة الآن'),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return false;

    final success = await database.restoreDatabase(sourcePath);
    if (success) {
      await database.preloadSettings();
      database.notifyChange(DataChangeEvent.all);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'تمت استعادة النسخة الاحتياطية وجميع البيانات بنجاح ✅')),
              ],
            ),
          ),
        );
      }
    }
    return success;
  }

  /// Performs a complete factory reset: completely wipes all database tables and resets settings
  static Future<bool> performFactoryReset({
    required BuildContext context,
    required DatabaseService database,
  }) async {
    // 1. Authenticate with PIN or Biometrics first
    final authenticated = await SecurityService.authenticate(
      context: context,
      database: database,
      reason: 'يرجى تأكيد الهوية قبل تنفيذ إعادة ضبط المصنع ومسح البيانات',
    );
    if (!authenticated) return false;

    if (!context.mounted) return false;

    // 2. High-Severity Warning Dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.delete_forever_rounded,
                  color: Color(0xFFEF4444), size: 28),
              SizedBox(width: 10),
              Text(
                'إعادة ضبط المصنع (حذف شامل)',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⚠️ تحذير شديد ونهائي:',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                'سيتم حذف وتصفير جميع البيانات بالكامل، بما في ذلك:\n'
                '• قائمة الطلاب وأولياء الأمور وبياناتهم\n'
                '• المجموعات والحصص وسجلات الحضور والغياب\n'
                '• المدفوعات والاشتراكات والمصروفات المالية\n'
                '• الامتحانات ودرجات الطلاب والمناهج\n'
                '• إعدادات وبوابات الواتساب وتخصيصات التطبيق\n\n'
                'سيعود التطبيق لحالته الأولى كأنه مثبت للتو. لا يمكن التراجع عن هذا الإجراء بعد تنفيذه!',
                style: TextStyle(
                    color: Color(0xFFE2E8F0), fontSize: 12.5, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع وإلغاء',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد الحذف وتصفير التطبيق',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return false;

    // 3. Execute Complete Factory Reset
    final db = await database.database;
    await db.transaction((txn) async {
      await txn.delete('attendance');
      await txn.delete('payments');
      await txn.delete('expenses');
      await txn.delete('exam_scores');
      await txn.delete('exams');
      await txn.delete('session_logs');
      await txn.delete('daily_todos');
      await txn.delete('exceptional_sessions');
      await txn.delete('session_cancellations');
      await txn.delete('group_curriculum_bindings');
      await txn.delete('students');
      await txn.delete('groups');
      await txn.delete('curriculum_lessons');
      await txn.delete('settings');
    });

    // Preload fresh default settings & notify UI
    await database.preloadSettings();
    database.notifyChange(DataChangeEvent.all);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'تمت إعادة ضبط المصنع وتصفير جميع بيانات التطبيق بنجاح ✅')),
            ],
          ),
        ),
      );
    }

    return true;
  }

  // --------------------------------------------------------------------------
  // PC APP FULL JSON SYNC (Identical to C:\Work\MY APP\my-app exportBackupJSON)
  // --------------------------------------------------------------------------

  /// Exports full JSON package compatible with the PC Electron/React app
  static Future<File> exportPCBackupJSON(DatabaseService database) async {
    final students = await database.getStudents();
    final groups = await database.getGroups();
    final attendance = await database.getAllAttendance();
    final payments = await database.getAllPayments();
    final expenses = await database.getExpenses();
    final exams = await database.getExams();

    final payload = {
      'version': '2.1',
      'appName': 'منظومة الأستاذ',
      'exportedAt': DateTime.now().toIso8601String(),
      'students': students
          .map((s) => {
                'id': s.id,
                'name': s.fullName,
                'phone': s.studentPhone,
                'parentName': s.parentName,
                'parentPhone': s.parentPhone,
                'gradeLevel': s.stage,
                'academicYear': s.grade,
                'groupId': s.groupId ?? '',
                'billingType':
                    s.paymentPlan == 'حصة' ? 'per_session' : 'per_month',
                'feeAmount': s.outstandingAmount,
                'active': true,
              })
          .toList(),
      'groups': groups
          .map((g) => {
                'id': g.id,
                'name': g.name,
                'subject': g.subject,
                'gradeLevel': g.stage,
                'academicYear': g.grade,
                'dayOfWeek': g.days,
                'time': g.schedule,
                'room': g.room,
                'maxCapacity': g.maxStudents,
                'locationName': g.locationType,
                'billingType': g.billingType,
                'sessionFee': g.monthlyPrice,
                'monthlyFee': g.monthlyPrice,
                'color':
                    '#${(g.colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
                'notes': g.notes,
              })
          .toList(),
      'attendance': attendance
          .map((a) => {
                'id': a.id.toString(),
                'date': a.attendanceDate,
                'studentId': a.studentId,
                'status': a.status,
                'homeworkStatus': a.homeworkStatus ?? 'done',
                'sessionType': a.sessionType,
                'notes': a.notes ?? '',
              })
          .toList(),
      'payments': payments
          .map((p) => {
                'id': p.id.toString(),
                'studentId': p.studentId,
                'amount': p.amount,
                'date': p.date,
                'category': p.type,
                'notes': p.note,
              })
          .toList(),
      'expenses': expenses
          .map((e) => {
                'id': e['id'] ?? '',
                'title': e['title'] ?? '',
                'amount': e['amount'] ?? 0.0,
                'category': e['category'] ?? '',
                'date': e['date'] ?? '',
                'notes': e['notes'] ?? '',
              })
          .toList(),
      'exams': exams
          .map((ex) => {
                'id': ex.id,
                'title': ex.title,
                'groupId': ex.groupId,
                'date': ex.date,
                'maxScore': ex.maxScore,
              })
          .toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(payload);
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);
    final fileName = 'حزمة_مزامنة_المنظومة_$dateStr.elostaz.json';

    final appDocDir = await getApplicationDocumentsDirectory();
    final file = File(path.join(appDocDir.path, fileName));
    await file.writeAsString(jsonString);

    try {
      final downloadDir =
          Directory('/storage/emulated/0/Download/EduAcademy_Backups');
      if (!await downloadDir.exists())
        await downloadDir.create(recursive: true);
      await file.copy(path.join(downloadDir.path, fileName));
    } catch (_) {}

    return file;
  }

  /// Shares PC JSON Sync package to WhatsApp, Drive, or PC
  static Future<void> sharePCBackupJSON({
    required BuildContext context,
    required DatabaseService database,
  }) async {
    final file = await exportPCBackupJSON(database);
    final fileName = path.basename(file.path);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            name: fileName,
            mimeType: 'application/json',
          ),
        ],
        subject: 'حزمة مزامنة منظومة الأستاذ (نسخة الكمبيوتر) - $fileName',
        text:
            'حزمة مزامنة شاملة متوافقة بالكامل مع نسخة الكمبيوتر (my-app).\nيمكنك استيرادها مباشرة في تطبيق الكمبيوتر أو الهاتف.',
      ),
    );
  }

  /// Imports PC full JSON package into mobile SQLite database
  static Future<int> importPCBackupJSON(
      String jsonString, DatabaseService database) async {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('صيغة ملف النسخ الاحتياطي غير صالحة');
    }

    final data = decoded;
    final db = await database.database;

    final rawStudents = (data['students'] as List?) ?? [];
    final rawGroups = (data['groups'] as List?) ?? [];
    final rawAttendance = (data['attendance'] as List?) ?? [];
    final rawPayments = (data['payments'] as List?) ?? [];
    final rawExpenses = (data['expenses'] as List?) ?? [];
    final rawExams = (data['exams'] as List?) ?? [];

    int importedCount = 0;

    await db.transaction((txn) async {
      // 1. Groups
      for (final g in rawGroups) {
        if (g is! Map) continue;
        final map = Map<String, dynamic>.from(g);
        final id = map['id']?.toString() ??
            'GRP_${DateTime.now().millisecondsSinceEpoch}_$importedCount';
        final name = map['name']?.toString() ?? 'مجموعة';
        final subject = map['subject']?.toString() ?? 'عام';
        final stage = map['gradeLevel']?.toString() ?? 'المرحلة الثانوية';
        final grade =
            map['academicYear']?.toString() ?? 'الصف الأول الثانوي (Sec 1)';
        final schedule = map['time']?.toString() ?? 'مواعيد محددة';
        final price = (map['monthlyFee'] as num?)?.toDouble() ??
            (map['sessionFee'] as num?)?.toDouble() ??
            0.0;
        final room = map['room']?.toString() ?? '';
        final maxStudents = (map['maxCapacity'] as num?)?.toInt() ?? 30;
        final billingType = map['billingType']?.toString() == 'per_session'
            ? 'per_session'
            : 'monthly';
        final colorHex = map['color']?.toString() ?? '#2563eb';
        final notes = map['notes']?.toString() ?? '';
        final days = map['dayOfWeek']?.toString() ?? '';

        await txn.insert(
            'groups',
            {
              'id': id,
              'name': name,
              'subject': subject,
              'stage': stage,
              'grade': grade,
              'schedule': schedule,
              'monthly_price': price,
              'room': room,
              'max_students': maxStudents,
              'billing_type': billingType,
              'color_value': _parseColorHex(colorHex),
              'notes': notes,
              'days': days,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        importedCount++;
      }

      // 2. Students
      for (final s in rawStudents) {
        if (s is! Map) continue;
        final map = Map<String, dynamic>.from(s);
        final id = map['id']?.toString() ??
            'Std_${DateTime.now().millisecondsSinceEpoch}_$importedCount';
        final name = map['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final phone = map['phone']?.toString() ?? '';
        final parentName = map['parentName']?.toString() ?? 'ولي أمر الطالب';
        final parentPhone = map['parentPhone']?.toString() ?? phone;
        final stage = map['gradeLevel']?.toString() ?? 'المرحلة الثانوية';
        final grade = map['academicYear']?.toString() ?? 'الصف الأول الثانوي';
        final groupId = map['groupId']?.toString();
        final plan =
            map['billingType']?.toString() == 'per_session' ? 'حصة' : 'شهري';
        final fee = (map['feeAmount'] as num?)?.toDouble() ?? 0.0;

        await txn.insert(
            'students',
            {
              'id': id,
              'full_name': name,
              'stage': stage,
              'grade': grade,
              'student_phone': phone,
              'parent_phone': parentPhone,
              'parent_name': parentName,
              'group_id':
                  (groupId != null && groupId.isNotEmpty) ? groupId : null,
              'payment_plan': plan,
              'outstanding_amount': fee,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        importedCount++;
      }

      // 3. Attendance
      for (final a in rawAttendance) {
        if (a is! Map) continue;
        final map = Map<String, dynamic>.from(a);
        final studentId = map['studentId']?.toString();
        final date = map['date']?.toString();
        if (studentId == null || date == null) continue;
        final status = map['status']?.toString() ?? 'present';
        final hw = map['homeworkStatus']?.toString() ?? 'done';
        final sessionType = map['sessionType']?.toString() ?? 'regular';
        final notes = map['notes']?.toString();

        await txn.insert(
            'attendance',
            {
              'student_id': studentId,
              'attendance_date': date,
              'check_in_at': '$date 15:00:00',
              'status': status,
              'source': 'pc_sync',
              'homework_status': hw,
              'session_type': sessionType,
              'notes': notes,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        importedCount++;
      }

      // 4. Payments
      for (final p in rawPayments) {
        if (p is! Map) continue;
        final map = Map<String, dynamic>.from(p);
        final studentId = map['studentId']?.toString();
        final amount = (map['amount'] as num?)?.toDouble() ?? 0.0;
        final date = map['date']?.toString() ??
            DateTime.now().toIso8601String().substring(0, 10);
        if (studentId == null || amount <= 0) continue;
        final type = map['category']?.toString() ?? 'شهري';
        final note = map['notes']?.toString();

        await txn.insert(
            'payments',
            {
              'student_id': studentId,
              'amount': amount,
              'date': date,
              'type': type,
              'note': note,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        importedCount++;
      }

      // 5. Expenses
      for (final e in rawExpenses) {
        if (e is! Map) continue;
        final map = Map<String, dynamic>.from(e);
        final title = map['title']?.toString() ?? 'مصروف';
        final amount = (map['amount'] as num?)?.toDouble() ?? 0.0;
        final date = map['date']?.toString() ??
            DateTime.now().toIso8601String().substring(0, 10);
        final category = map['category']?.toString() ?? 'عام';
        final id = map['id']?.toString() ??
            'EXP_${DateTime.now().millisecondsSinceEpoch}_$importedCount';
        final notes = map['notes']?.toString();

        await txn.insert(
            'expenses',
            {
              'id': id,
              'title': title,
              'amount': amount,
              'category': category,
              'date': date,
              'notes': notes,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        importedCount++;
      }

      // 6. Exams
      for (final ex in rawExams) {
        if (ex is! Map) continue;
        final map = Map<String, dynamic>.from(ex);
        final id = map['id']?.toString() ??
            'EX_${DateTime.now().millisecondsSinceEpoch}_$importedCount';
        final title = map['title']?.toString() ?? 'اختبار';
        final groupId = map['groupId']?.toString();
        final date = map['date']?.toString() ??
            DateTime.now().toIso8601String().substring(0, 10);
        final maxScore = (map['maxScore'] as num?)?.toDouble() ?? 100.0;

        await txn.insert(
            'exams',
            {
              'id': id,
              'title': title,
              'group_id': groupId,
              'date': date,
              'max_score': maxScore,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        importedCount++;
      }
    });

    database.notifyChange(DataChangeEvent.all);
    return importedCount;
  }

  /// Restores PC JSON backup with file picker dialog
  static Future<bool> restorePCBackupWithPicker({
    required BuildContext context,
    required DatabaseService database,
  }) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty || files.first.path == null) return false;

    final filePath = files.first.path!;
    final file = File(filePath);
    if (!await file.exists()) return false;

    try {
      final jsonString = await file.readAsString();
      final count = await importPCBackupJSON(jsonString, database);
      await database.preloadSettings();
      database.notifyChange(DataChangeEvent.all);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'تم استيراد $count سجلاً من حزمة الكمبيوتر بنجاح ✅')),
              ],
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            content: Text('فشل استيراد حزمة الكمبيوتر: $e'),
          ),
        );
      }
      return false;
    }
  }

  static int _parseColorHex(String hex) {
    if (hex.isEmpty) return 0xFF2563EB;
    var clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) clean = 'FF$clean';
    return int.tryParse(clean, radix: 16) ?? 0xFF2563EB;
  }
}
