import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import '../../models/attendance_model.dart';
import '../../models/curriculum_model.dart';
import '../../models/exam_model.dart';
import '../../models/exceptional_session_model.dart';
import '../../models/group_model.dart';
import '../../models/payment_model.dart';
import '../../models/school_period_model.dart';
import '../../models/student_model.dart';

enum DataChangeEvent {
  students,
  groups,
  attendance,
  finances,
  curriculum,
  exams,
  settings,
  timetable,
  reports,
  all,
}

class DatabaseService {
  static DatabaseService? shared;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _databaseKeyName = 'teacher_center_database_key_v1';
  static const String _legacyCleanupKey = 'legacy_plaintext_cleanup_v1';
  Database? _database;
  Future<Database>? _databaseOpening;

  DatabaseService() {
    shared = this;
  }

  static final StreamController<DataChangeEvent> _dataChangeController =
      StreamController<DataChangeEvent>.broadcast();
  Stream<DataChangeEvent> get onDataChanged => _dataChangeController.stream;

  void notifyChange(DataChangeEvent event) {
    if (!_dataChangeController.isClosed) {
      _dataChangeController.add(event);
    }
  }

  Future<Database> get database {
    final openedDatabase = _database;
    if (openedDatabase != null) return Future.value(openedDatabase);

    final openingDatabase = _databaseOpening;
    if (openingDatabase != null) return openingDatabase;

    final opening = _openDatabase();
    _databaseOpening = opening;
    return opening.whenComplete(() {
      if (identical(_databaseOpening, opening)) _databaseOpening = null;
    });
  }

  Future<Database> _openDatabase() async {
    final databasesPath = await getDatabasesPath();
    final plainDbPath = path.join(databasesPath, 'teacher_center.db');
    final secureDbPath = path.join(databasesPath, 'teacher_center_secure.db');

    // Seamless automatic migration: if legacy encrypted DB exists and plain DB does not, export to plaintext!
    final plainFile = File(plainDbPath);
    final secureFile = File(secureDbPath);
    if (!await plainFile.exists() && await secureFile.exists()) {
      try {
        final encryptionKey = await _getDatabaseEncryptionKey(secureDbPath);
        if (encryptionKey.isNotEmpty) {
          final secureDb = await sqlcipher.openDatabase(
            secureDbPath,
            password: encryptionKey,
          );
          final escapedPath = plainDbPath.replaceAll("'", "''");
          await secureDb.rawQuery("ATTACH DATABASE '$escapedPath' AS plaintext KEY '';");
          await secureDb.rawQuery("SELECT sqlcipher_export('plaintext');");
          await secureDb.rawQuery("DETACH DATABASE plaintext;");
          await secureDb.close();

          final backupPath = path.join(databasesPath, 'teacher_center_secure.db.bak');
          await secureFile.rename(backupPath);
          final secureWal = File('$secureDbPath-wal');
          if (await secureWal.exists()) await secureWal.delete();
          final secureShm = File('$secureDbPath-shm');
          if (await secureShm.exists()) await secureShm.delete();
          debugPrint('Successfully migrated encrypted database to unencrypted standard SQLite!');
        }
      } catch (e) {
        debugPrint('Migration from secure to plain SQLite warning: $e');
      }
    }

    _database = await openDatabase(
      plainDbPath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.rawQuery('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA synchronous = NORMAL');
        await db.execute('PRAGMA temp_store = MEMORY');
        try {
          await db.rawQuery('PRAGMA cache_size = -16000');
        } catch (_) {}
        try {
          await db.rawQuery('PRAGMA mmap_size = 30000000');
        } catch (_) {}
      },
      onOpen: (db) async {
        final versionRes = await db.rawQuery('PRAGMA user_version');
        final currentVer = Sqflite.firstIntValue(versionRes) ?? 0;
        if (currentVer < 4) {
          await _runMigrationsAndSchemaChecks(db);
          // 🛡️ Data Protection Guard: NEVER seed or wipe existing timetable data on open!
          await db.execute('PRAGMA user_version = 4');
        }
        await _healAndEnsureAttendanceIntegrity(db);
      },
      onCreate: (db, version) async {
        await _runInitialSchema(db);
        await _runMigrationsAndSchemaChecks(db);
        await _populateMrAdelTimetable(db);
        await db.execute('PRAGMA user_version = 4');
        await _healAndEnsureAttendanceIntegrity(db);
      },
    );
    unawaited(_cleanupLegacyDatabaseCopies(databasesPath));
    return _database!;
  }

  Future<void> _healAndEnsureAttendanceIntegrity(Database db) async {
    try {
      try {
        await db.execute('ALTER TABLE financial_claims ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0.0');
      } catch (_) {}

      // 1. Guaranteed recovery for Mazen Ali (Std-108) on 2026-11-16
      final mazenAtt = await db.query(
        'attendance',
        where: 'student_id = ? AND attendance_date = ?',
        whereArgs: ['Std-108', '2026-11-16'],
      );
      if (mazenAtt.isEmpty) {
        await db.insert('attendance', {
          'student_id': 'Std-108',
          'attendance_date': '2026-11-16',
          'check_in_at': '2026-11-16T16:19:33.300533',
          'status': 'present',
          'source': 'manual',
          'recitation_rating': 'لم يحفظ ❌',
          'homework_status': 'not_done',
          'session_type': 'regular',
        });
        debugPrint('Auto-healed Mazen Ali attendance record for 2026-11-16');
      }

      final mazenClaimId = 'session_fee_grp_1794458367591_Std-108_2026-11-16';
      final mazenPay = await db.query(
        'payments',
        where: 'claim_id = ?',
        whereArgs: [mazenClaimId],
      );
      if (mazenPay.isEmpty) {
        await db.insert('payments', {
          'student_id': 'Std-108',
          'amount': 200.0,
          'date': '2026-11-16',
          'type': 'مطالبة استحقاق حصة',
          'note': 'حصة مجموعة: Sec2-Mazen ali • مطالبة فردية [$mazenClaimId]',
          'claim_id': mazenClaimId,
        });
        debugPrint('Auto-healed Mazen Ali payment claim for 2026-11-16');
      }

      // 2. Generalized recovery from whatsapp_logs for any session followup reports
      final followupLogs = await db.rawQuery('''
        SELECT wl.student_id, wl.sent_at, wl.message, wl.status
        FROM whatsapp_logs wl
        WHERE wl.category = 'sessionFollowup'
          AND wl.student_id IS NOT NULL
          AND wl.student_id != ''
      ''');

      for (final log in followupLogs) {
        final sId = log['student_id'] as String?;
        final sentAt = log['sent_at'] as String?;
        final msg = log['message'] as String? ?? '';
        if (sId == null || sId.isEmpty || sentAt == null) continue;

        String logDate = sentAt.substring(0, 10);
        final dateMatch = RegExp(r'\((\d{4}-\d{2}-\d{2})\)').firstMatch(msg);
        if (dateMatch != null) {
          logDate = dateMatch.group(1)!;
        }

        final existing = await db.query(
          'attendance',
          where: 'student_id = ? AND attendance_date = ?',
          whereArgs: [sId, logDate],
        );

        if (existing.isEmpty) {
          String status = 'present';
          if (msg.contains('حاضر')) {
            status = 'present';
          } else if (msg.contains('متأخر')) {
            status = 'late';
          } else if (msg.contains('غائب') || msg.contains('غياب')) {
            status = 'absent';
          }

          String? recitation;
          final recMatch = RegExp(r'تقييم التسميع / الكويز:\s*([^\n\r]+)').firstMatch(msg);
          if (recMatch != null) recitation = recMatch.group(1)?.trim();

          String? homework;
          final hwMatch = RegExp(r'حالة أداء الواجب:\s*([^\n\r]+)').firstMatch(msg);
          if (hwMatch != null) homework = hwMatch.group(1)?.trim();

          await db.insert('attendance', {
            'student_id': sId,
            'attendance_date': logDate,
            'check_in_at': sentAt,
            'status': status,
            'source': 'manual',
            'recitation_rating': recitation,
            'homework_status': homework,
            'session_type': 'regular',
          });
          debugPrint('Auto-healed attendance for student $sId on $logDate from whatsapp_logs');
        }
      }

      // 3. Ensure Sent Messages Ledger and backfill existing WhatsApp logs
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sent_messages_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id TEXT NOT NULL,
          category TEXT NOT NULL,
          context_key TEXT NOT NULL,
          phone TEXT NOT NULL DEFAULT '',
          sent_at TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'sent',
          UNIQUE(student_id, category, context_key)
        )
      ''');
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ledger_lookup ON sent_messages_ledger(student_id, category, context_key)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ledger_cat_key ON sent_messages_ledger(category, context_key)');
      } catch (_) {}

      // Backfill past sent messages
      try {
        await db.execute('''
          INSERT OR IGNORE INTO sent_messages_ledger (student_id, category, context_key, phone, sent_at, status)
          SELECT 
            student_id,
            CASE 
              WHEN category IN ('sessionFollowup', 'session_report', 'daily_report') THEN 'daily_report'
              WHEN category IN ('absence', 'absenceAlert', 'absence_alert') THEN 'absence'
              WHEN category IN ('certificate', 'cert') THEN 'certificate'
              WHEN category IN ('cancellation') THEN 'cancellation'
              WHEN category IN ('payment', 'financialReceipt', 'payment_receipt') THEN 'payment'
              WHEN category IN ('exam', 'examScore', 'exam_score') THEN 'exam'
              ELSE category 
            END as norm_category,
            substr(sent_at, 1, 10) as norm_context,
            phone,
            sent_at,
            'sent'
          FROM whatsapp_logs
          WHERE student_id IS NOT NULL 
            AND student_id != ''
            AND status IN ('sent', 'sent_manual', 'sent_api', 'opened_whatsapp');
        ''');
      } catch (_) {}
    } catch (e, stack) {
      debugPrint('Error in _healAndEnsureAttendanceIntegrity: $e\n$stack');
    }
  }

  Future<void> _runMigrationsAndSchemaChecks(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS curriculum_lessons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
            subject TEXT NOT NULL,
            stage TEXT NOT NULL,
            grade TEXT NOT NULL,
            unit_name TEXT NOT NULL,
            lesson_title TEXT NOT NULL,
            objectives TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS session_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id TEXT NOT NULL,
            date TEXT NOT NULL,
            lesson_title TEXT NOT NULL,
            content_covered TEXT,
            homework TEXT,
            notes TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY(group_id) REFERENCES groups(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS daily_todos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            is_done INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS exceptional_sessions (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            group_name TEXT NOT NULL,
            title TEXT NOT NULL,
            reason TEXT NOT NULL,
            scale TEXT NOT NULL DEFAULT 'single',
            date TEXT NOT NULL,
            day TEXT NOT NULL,
            time TEXT NOT NULL,
            is_recurring INTEGER NOT NULL DEFAULT 0,
            recurring_weeks INTEGER NOT NULL DEFAULT 1,
            notes TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS session_cancellations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id TEXT NOT NULL,
            date TEXT NOT NULL,
            cancelled_by TEXT NOT NULL,
            student_id TEXT,
            reason TEXT,
            notes TEXT,
            notice_sent INTEGER DEFAULT 0,
            notice_sent_at TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await _addColumnIfMissing(
          db,
          'session_cancellations',
          'notice_sent',
          'notice_sent INTEGER DEFAULT 0',
        );
        await _addColumnIfMissing(
          db,
          'session_cancellations',
          'notice_sent_at',
          'notice_sent_at TEXT',
        );
        await _addColumnIfMissing(
          db,
          'session_logs',
          'content_covered',
          'content_covered TEXT',
        );
        await _addColumnIfMissing(db, 'session_logs', 'next_topic', 'next_topic TEXT');
        await _addColumnIfMissing(db, 'session_logs', 'next_quiz', 'next_quiz TEXT');
        await _addColumnIfMissing(
          db,
          'session_logs',
          'next_homework',
          'next_homework TEXT',
        );
        await _addColumnIfMissing(
          db,
          'session_logs',
          'previous_homework_review',
          'previous_homework_review TEXT',
        );
        await _addColumnIfMissing(
          db,
          'session_logs',
          'previous_lesson_review',
          'previous_lesson_review TEXT',
        );
        await _addColumnIfMissing(
          db,
          'curriculum_lessons',
          'chapter_number',
          'chapter_number INTEGER DEFAULT 1',
        );
        await _addColumnIfMissing(
          db,
          'curriculum_lessons',
          'is_completed',
          'is_completed INTEGER DEFAULT 0',
        );
        await _addColumnIfMissing(
          db,
          'curriculum_lessons',
          'curriculum_name',
          'curriculum_name TEXT',
        );
        await _addColumnIfMissing(
          db,
          'curriculum_lessons',
          'lesson_date',
          'lesson_date TEXT',
        );
        await _addColumnIfMissing(
          db,
          'curriculum_lessons',
          'homework_notes',
          'homework_notes TEXT',
        );
        await _addColumnIfMissing(
          db,
          'attendance',
          'recitation_rating',
          'recitation_rating TEXT',
        );
        await _addColumnIfMissing(
          db,
          'attendance',
          'recitation_score',
          'recitation_score REAL',
        );
        await _addColumnIfMissing(
          db,
          'attendance',
          'homework_status',
          'homework_status TEXT',
        );
        await _addColumnIfMissing(db, 'attendance', 'notes', 'notes TEXT');
        await _addColumnIfMissing(
          db,
          'attendance',
          'session_type',
          "session_type TEXT DEFAULT 'regular'",
        );
        await _addColumnIfMissing(db, 'groups', 'room', "room TEXT DEFAULT ''");
        await _addColumnIfMissing(
          db,
          'groups',
          'max_students',
          'max_students INTEGER DEFAULT 30',
        );
        await _addColumnIfMissing(
          db,
          'groups',
          'billing_type',
          "billing_type TEXT DEFAULT 'per_session'",
        );
        try {
          await db.execute(
            "UPDATE groups SET billing_type = 'per_session' WHERE billing_type IS NULL OR billing_type = '' OR billing_type = 'monthly'",
          );
        } catch (_) {}
        await _addColumnIfMissing(
          db,
          'groups',
          'color_value',
          'color_value INTEGER DEFAULT 4280628203',
        );
        await _addColumnIfMissing(db, 'groups', 'notes', "notes TEXT DEFAULT ''");
        await _addColumnIfMissing(db, 'groups', 'subject', "subject TEXT DEFAULT ''");
        await _addColumnIfMissing(
          db,
          'groups',
          'location_type',
          "location_type TEXT DEFAULT 'منزل المعلم أو الطالب'",
        );
        await _addColumnIfMissing(
          db,
          'groups',
          'start_time',
          "start_time TEXT DEFAULT '03:00 PM'",
        );
        await _addColumnIfMissing(
          db,
          'groups',
          'end_time',
          "end_time TEXT DEFAULT '04:00 PM'",
        );
        await _addColumnIfMissing(db, 'groups', 'days', "days TEXT DEFAULT ''");
        await _addColumnIfMissing(
          db,
          'students',
          'parent_name',
          "parent_name TEXT DEFAULT ''",
        );
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance(attendance_date)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_attendance_student ON attendance(student_id)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_student_group ON students(group_id)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_payments_student ON payments(student_id)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_exam_scores_exam ON exam_scores(exam_id)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_session_logs_group ON session_logs(group_id)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_attendance_composite ON attendance(attendance_date, status)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_attendance_student_date ON attendance(student_id, attendance_date)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(date)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_session_logs_latest ON session_logs(group_id, date DESC, id DESC)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_curriculum_lookup ON curriculum_lessons(stage, grade)',
          );
        } catch (_) {}
        await _addColumnIfMissing(db, 'session_logs', 'student_id', 'student_id TEXT');
        await _addColumnIfMissing(db, 'session_logs', 'student_name', 'student_name TEXT');
        await _addColumnIfMissing(
          db,
          'session_logs',
          'curriculum_name',
          'curriculum_name TEXT',
        );
        await _addColumnIfMissing(db, 'payments', 'claim_id', 'claim_id TEXT');
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_payments_claim_id ON payments(claim_id)',
          );
        } catch (_) {}
        await db.execute('''
          CREATE TABLE IF NOT EXISTS expenses (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            category TEXT NOT NULL,
            amount REAL NOT NULL,
            date TEXT NOT NULL,
            notes TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS group_curriculum_bindings (
            id TEXT PRIMARY KEY,
            group_name TEXT NOT NULL,
            grade_badge TEXT NOT NULL,
            curriculum_name TEXT NOT NULL,
            track TEXT NOT NULL DEFAULT 'لغات',
            units_count INTEGER NOT NULL DEFAULT 1,
            lessons_count INTEGER NOT NULL DEFAULT 1,
            is_locked INTEGER NOT NULL DEFAULT 1,
            color_dot INTEGER NOT NULL DEFAULT 4281878774,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS group_lesson_progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id TEXT NOT NULL,
            lesson_id INTEGER NOT NULL,
            status TEXT NOT NULL,
            taught_date TEXT,
            session_type TEXT,
            notes TEXT,
            updated_at TEXT NOT NULL,
            UNIQUE(group_id, lesson_id)
          )
        ''');
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_group_lesson_progress ON group_lesson_progress(group_id, lesson_id)',
          );
        } catch (_) {}
        await db.execute('''
          CREATE TABLE IF NOT EXISTS exceptional_sessions (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            group_name TEXT NOT NULL,
            title TEXT NOT NULL,
            reason TEXT NOT NULL,
            scale TEXT NOT NULL DEFAULT 'single',
            date TEXT NOT NULL,
            day TEXT NOT NULL,
            time TEXT NOT NULL,
            is_recurring INTEGER NOT NULL DEFAULT 0,
            recurring_weeks INTEGER NOT NULL DEFAULT 1,
            notes TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS session_cancellations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            group_id TEXT NOT NULL,
            date TEXT NOT NULL,
            cancelled_by TEXT NOT NULL,
            student_id TEXT,
            reason TEXT,
            notes TEXT,
            notice_sent INTEGER DEFAULT 0,
            notice_sent_at TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        // School Timetable Table (جدول حصص المدرسة)
        await db.execute('''
          CREATE TABLE IF NOT EXISTS school_timetable (
            id TEXT PRIMARY KEY,
            day_of_week TEXT NOT NULL,
            period_number INTEGER NOT NULL,
            class_name TEXT NOT NULL,
            subject TEXT NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            room TEXT DEFAULT '',
            notes TEXT DEFAULT '',
            is_recess INTEGER NOT NULL DEFAULT 0,
            supervision_duty TEXT DEFAULT '',
            is_reserve INTEGER NOT NULL DEFAULT 0
          )
        ''');

        // Tutoring Timetable Table (جدول مواعيد وسناتر الدروس الخصوصية - منفصل تماماً)
        await db.execute('''
          CREATE TABLE IF NOT EXISTS tutoring_timetable (
            id TEXT PRIMARY KEY,
            day_of_week TEXT NOT NULL,
            period_number INTEGER NOT NULL,
            class_name TEXT NOT NULL,
            subject TEXT NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            room TEXT DEFAULT '',
            notes TEXT DEFAULT '',
            is_recess INTEGER NOT NULL DEFAULT 0,
            supervision_duty TEXT DEFAULT '',
            is_reserve INTEGER NOT NULL DEFAULT 0
          )
        ''');

        // School Classes / Stages Table (قاعدة بيانات المراحل والفصول المدرسية)
        await db.execute('''
          CREATE TABLE IF NOT EXISTS school_classes (
            id TEXT PRIMARY KEY,
            stage TEXT NOT NULL,
            class_name TEXT NOT NULL,
            subject TEXT DEFAULT '',
            room TEXT DEFAULT '',
            sort_order INTEGER DEFAULT 0
          )
        ''');

        // Central Sent Messages Ledger (سجل الإرسال المركزي الصارم لمنع تكرار أو تسريب الرسائل)
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sent_messages_ledger (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id TEXT NOT NULL,
            category TEXT NOT NULL,
            context_key TEXT NOT NULL,
            phone TEXT NOT NULL DEFAULT '',
            sent_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'sent',
            UNIQUE(student_id, category, context_key)
          )
        ''');
        try {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_ledger_lookup ON sent_messages_ledger(student_id, category, context_key)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_ledger_cat_key ON sent_messages_ledger(category, context_key)');
        } catch (_) {}

        // Track migrations table (identical to PC database schema)
        await db.execute('''
          CREATE TABLE IF NOT EXISTS _migrations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )
        ''');

        // WhatsApp sent messages log & history
        await db.execute('''
          CREATE TABLE IF NOT EXISTS whatsapp_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id TEXT,
            student_name TEXT,
            phone TEXT NOT NULL,
            recipient_type TEXT NOT NULL DEFAULT 'parent',
            category TEXT NOT NULL,
            message TEXT NOT NULL,
            status TEXT NOT NULL,
            error_message TEXT,
            sent_at TEXT NOT NULL
          )
        ''');
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_whatsapp_logs_date ON whatsapp_logs(sent_at DESC)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_whatsapp_logs_student ON whatsapp_logs(student_id)',
          );
        } catch (_) {}

        try {
          await db.execute('ALTER TABLE students ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE students ADD COLUMN guardians_json TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE students ADD COLUMN student_pin TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE students ADD COLUMN parent_pin TEXT');
        } catch (_) {}

        // توليد تلقائي للرموز السرية للطلاب الذين لا يملكون PIN حالياً
        try {
          final noPinStudents = await db.query(
            'students',
            columns: ['id', 'student_phone', 'parent_phone', 'student_pin', 'parent_pin'],
            where: 'student_pin IS NULL OR student_pin = "" OR parent_pin IS NULL OR parent_pin = ""',
          );
          final rnd = Random();
          for (final row in noPinStudents) {
            final sId = row['id'] as String;
            var sPin = (row['student_pin'] as String?)?.trim() ?? '';
            var pPin = (row['parent_pin'] as String?)?.trim() ?? '';

            if (sPin.isEmpty) {
              final sPhoneDigits = (row['student_phone'] as String? ?? '').replaceAll(RegExp(r'\D'), '');
              if (sPhoneDigits.length >= 4) {
                sPin = sPhoneDigits.substring(sPhoneDigits.length - 4);
              } else {
                sPin = '${1000 + rnd.nextInt(9000)}';
              }
            }

            if (pPin.isEmpty) {
              final pPhoneDigits = (row['parent_phone'] as String? ?? '').replaceAll(RegExp(r'\D'), '');
              if (pPhoneDigits.length >= 4) {
                pPin = pPhoneDigits.substring(pPhoneDigits.length - 4);
              } else {
                pPin = '${1000 + rnd.nextInt(9000)}';
              }
            }

            await db.update(
              'students',
              {'student_pin': sPin, 'parent_pin': pPin},
              where: 'id = ?',
              whereArgs: [sId],
            );
          }
        } catch (e) {
          debugPrint('Error backfilling PINs: $e');
        }

        // جدول الشهادات الصادرة لمزامنتها ومتابعتها
        await db.execute('''
          CREATE TABLE IF NOT EXISTS certificates (
            id TEXT PRIMARY KEY,
            student_id TEXT NOT NULL,
            student_name TEXT NOT NULL,
            exam_title TEXT NOT NULL,
            badge_title TEXT,
            score_text TEXT,
            issued_at TEXT NOT NULL,
            is_synced INTEGER DEFAULT 0
          )
        ''');
        try {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_cert_student ON certificates(student_id)');
        } catch (_) {}

        // نظام بنك النقاط والمكافآت التفاعلي
        try {
          final columns = await db.rawQuery('PRAGMA table_info(students)');
          final hasPoints = columns.any((c) => c['name'] == 'points_balance');
          if (!hasPoints) {
            await db.execute('ALTER TABLE students ADD COLUMN points_balance INTEGER NOT NULL DEFAULT 0');
          }
        } catch (e) {
          debugPrint('Error adding points_balance to students: $e');
        }

        await db.execute('''
          CREATE TABLE IF NOT EXISTS rewards_catalog (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT DEFAULT '',
            cost_points INTEGER NOT NULL,
            icon_name TEXT DEFAULT 'gift',
            is_active INTEGER NOT NULL DEFAULT 1,
            updated_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS student_points_log (
            id TEXT PRIMARY KEY,
            student_id TEXT NOT NULL,
            points_delta INTEGER NOT NULL,
            reason TEXT NOT NULL,
            voucher_code TEXT,
            status TEXT DEFAULT 'completed',
            created_at TEXT NOT NULL
          )
        ''');
        try {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_points_log_student ON student_points_log(student_id)');
        } catch (_) {}

        try {
          await db.execute('ALTER TABLE groups ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1');
        } catch (_) {}

        await db.execute('''
          CREATE TABLE IF NOT EXISTS financial_claims (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            claim_id TEXT UNIQUE NOT NULL,
            student_id TEXT NOT NULL,
            student_name TEXT NOT NULL,
            group_id TEXT NOT NULL,
            group_name TEXT NOT NULL,
            session_date TEXT NOT NULL,
            amount REAL NOT NULL,
            paid_amount REAL NOT NULL DEFAULT 0.0,
            billing_type TEXT NOT NULL DEFAULT 'per_session',
            session_scale TEXT NOT NULL DEFAULT 'regular',
            status TEXT NOT NULL DEFAULT 'active',
            note TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (student_id) REFERENCES students(id),
            FOREIGN KEY (group_id) REFERENCES groups(id)
          )
        ''');
        try {
          await db.execute('ALTER TABLE financial_claims ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0.0');
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_financial_claims_date ON financial_claims(session_date DESC)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_financial_claims_student ON financial_claims(student_id)',
          );
        } catch (_) {}

        await _removeBuiltInCurriculaOnce(db);
        await _removeLegacySiblingColumns(db);
        await _seedAiPythonCurriculumOnce(db);
      }

      Future<void> _runInitialSchema(Database db) async {
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS students (
              id TEXT PRIMARY KEY,
              full_name TEXT NOT NULL,
              stage TEXT NOT NULL,
              grade TEXT NOT NULL,
              student_phone TEXT NOT NULL,
              parent_phone TEXT NOT NULL,
              group_id TEXT,
              payment_plan TEXT NOT NULL,
              outstanding_amount REAL NOT NULL DEFAULT 0
            )
          ''');
        } catch (e) {
          debugPrint('onCreate students table warning: $e');
        }

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS groups (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              stage TEXT NOT NULL,
              grade TEXT NOT NULL,
              schedule TEXT NOT NULL,
              monthly_price REAL NOT NULL DEFAULT 0
            )
          ''');
        } catch (e) {
          debugPrint('onCreate groups table warning: $e');
        }

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS attendance (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              student_id TEXT NOT NULL,
              attendance_date TEXT NOT NULL,
              check_in_at TEXT NOT NULL,
              status TEXT NOT NULL,
              source TEXT NOT NULL,
              UNIQUE(student_id, attendance_date),
              FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE
            )
          ''');
        } catch (e) {
          debugPrint('onCreate attendance table warning: $e');
        }

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS payments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              student_id TEXT NOT NULL,
              amount REAL NOT NULL,
              date TEXT NOT NULL,
              type TEXT NOT NULL,
              note TEXT,
              claim_id TEXT,
              FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE
            )
          ''');
        } catch (e) {
          debugPrint('onCreate payments table warning: $e');
        }

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS exams (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              group_id TEXT,
              date TEXT NOT NULL,
              max_score REAL NOT NULL DEFAULT 100
            )
          ''');
        } catch (e) {
          debugPrint('onCreate exams table warning: $e');
        }

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS exam_scores (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              exam_id TEXT NOT NULL,
              student_id TEXT NOT NULL,
              score REAL NOT NULL,
              note TEXT,
              UNIQUE(exam_id, student_id),
              FOREIGN KEY(student_id) REFERENCES students(id) ON DELETE CASCADE
            )
          ''');
        } catch (e) {
          debugPrint('onCreate exam_scores table warning: $e');
        }

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        } catch (e) {
          debugPrint('onCreate settings table warning: $e');
        }

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS curriculum_lessons (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              subject TEXT NOT NULL,
              stage TEXT NOT NULL,
              grade TEXT NOT NULL,
              unit_name TEXT NOT NULL,
              lesson_title TEXT NOT NULL,
              objectives TEXT
            )
          ''');
        } catch (e) {
          debugPrint('onCreate curriculum_lessons table warning: $e');
        }

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS session_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              group_id TEXT NOT NULL,
              date TEXT NOT NULL,
              lesson_title TEXT NOT NULL,
              homework TEXT,
              notes TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(group_id) REFERENCES groups(id) ON DELETE CASCADE
            )
          ''');
        } catch (e) {
          debugPrint('onCreate session_logs table warning: $e');
        }

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS daily_todos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              is_done INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
        } catch (e) {
          debugPrint('onCreate daily_todos table warning: $e');
        }

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS exceptional_sessions (
              id TEXT PRIMARY KEY,
              group_id TEXT NOT NULL,
              group_name TEXT NOT NULL,
              title TEXT NOT NULL,
              reason TEXT NOT NULL,
              scale TEXT NOT NULL DEFAULT 'single',
              date TEXT NOT NULL,
              day TEXT NOT NULL,
              time TEXT NOT NULL,
              is_recurring INTEGER NOT NULL DEFAULT 0,
              recurring_weeks INTEGER NOT NULL DEFAULT 1,
              notes TEXT,
              status TEXT NOT NULL DEFAULT 'active',
              created_at TEXT NOT NULL
            )
          ''');
        } catch (e) {
          debugPrint('onCreate exceptional_sessions table warning: $e');
        }

        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS session_cancellations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              group_id TEXT NOT NULL,
              date TEXT NOT NULL,
              cancelled_by TEXT NOT NULL,
              student_id TEXT,
              reason TEXT,
              notes TEXT,
              notice_sent INTEGER DEFAULT 0,
              notice_sent_at TEXT,
              created_at TEXT NOT NULL
            )
          ''');
        } catch (e) {
          debugPrint('onCreate session_cancellations table warning: $e');
        }

        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance(attendance_date)',
          );
        } catch (_) {}
        try {
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_student_group ON students(group_id)',
          );
        } catch (_) {}
      }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((entry) => entry['name'] == column)) return;
    if (columns.isEmpty) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $definition');
  }

  Future<void> _removeBuiltInCurriculaOnce(Database db) async {
    const cleanupKey = 'built_in_curricula_removed_v2';
    final completed = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [cleanupKey],
      limit: 1,
    );
    if (completed.isNotEmpty) return;

    await db.transaction((txn) async {
      await txn.delete(
        'curriculum_lessons',
        where:
            "curriculum_name LIKE 'منهج الصف الأول الإعدادي%' OR curriculum_name LIKE '%ICT%' OR curriculum_name LIKE '%افتراضي%' OR lesson_title IN ('قانون أوم وقانونا كيرشوف', 'التأثير المغناطيسي للتيار الكهربي', 'الدوال الحقيقية ورسم المنحنيات')",
      );
      await txn.insert('settings', {
        'key': cleanupKey,
        'value': 'true',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> _removeLegacySiblingColumns(Database db) async {
    const legacyColumns = [
      ['groups', 'is_shared_session'],
      ['groups', 'billing_mode'],
      ['groups', 'student_schedules'],
      ['students', 'custom_price'],
      ['group_curriculum_bindings', 'student_curricula'],
    ];

    for (final entry in legacyColumns) {
      final table = entry[0];
      final column = entry[1];
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (columns.any((row) => row['name'] == column)) {
        await db.execute('ALTER TABLE $table DROP COLUMN $column');
      }
    }
  }

  Future<void> _seedAiPythonCurriculumOnce(Database db) async {
    const seedKey = 'seeded_ai_python_curriculum_v1';
    final alreadySeeded = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [seedKey],
      limit: 1,
    );
    if (alreadySeeded.isNotEmpty) return;

    try {
      final lessonsToInsert = [
        // الوحدة الأولى: الذكاء الاصطناعي ولغات البرمجة
        {
          'subject': 'الذكاء الاصطناعي ولغات البرمجة',
          'stage': 'المرحلة الثانوية',
          'grade': 'الصف الأول الثانوي (Sec 1)',
          'curriculum_name': 'منهج الذكاء الاصطناعي ولغات البرمجة (Python)',
          'unit_name': 'الوحدة الأولى: الذكاء الاصطناعي ولغات البرمجة',
          'lesson_title': 'الدرس الأول: التفكير الحاسوبي وحل المشكلات',
          'objectives': 'التفكير الحاسوبي، تحليل المشكلات وتجزئتها، وتصميم الخطوات المنطقية والخوارزميات.',
          'chapter_number': 1,
          'is_completed': 0,
        },
        {
          'subject': 'الذكاء الاصطناعي ولغات البرمجة',
          'stage': 'المرحلة الثانوية',
          'grade': 'الصف الأول الثانوي (Sec 1)',
          'curriculum_name': 'منهج الذكاء الاصطناعي ولغات البرمجة (Python)',
          'unit_name': 'الوحدة الأولى: الذكاء الاصطناعي ولغات البرمجة',
          'lesson_title': 'الدرس الثاني: خوارزميات الذكاء الاصطناعي',
          'objectives': 'آلية عمل خوارزميات الذكاء الاصطناعي ومفهوم تدريب النماذج واتخاذ القرارات.',
          'chapter_number': 1,
          'is_completed': 0,
        },
        {
          'subject': 'الذكاء الاصطناعي ولغات البرمجة',
          'stage': 'المرحلة الثانوية',
          'grade': 'الصف الأول الثانوي (Sec 1)',
          'curriculum_name': 'منهج الذكاء الاصطناعي ولغات البرمجة (Python)',
          'unit_name': 'الوحدة الأولى: الذكاء الاصطناعي ولغات البرمجة',
          'lesson_title': 'الدرس الثالث: السلاسل النصية Strings والقوائم Lists في لغة Python',
          'objectives': 'التعامل مع النصوص Strings، عمليات الفهرسة والتقطيع، والقوائم Lists وإدارتها.',
          'chapter_number': 1,
          'is_completed': 0,
        },
        {
          'subject': 'الذكاء الاصطناعي ولغات البرمجة',
          'stage': 'المرحلة الثانوية',
          'grade': 'الصف الأول الثانوي (Sec 1)',
          'curriculum_name': 'منهج الذكاء الاصطناعي ولغات البرمجة (Python)',
          'unit_name': 'الوحدة الأولى: الذكاء الاصطناعي ولغات البرمجة',
          'lesson_title': 'الدرس الرابع: الدوال ذات المعاملات في لغة Python',
          'objectives': 'تعريف واستدعاء الدوال المخصصة Functions وتمرير المعاملات Parameters وإرجاع القيم.',
          'chapter_number': 1,
          'is_completed': 0,
        },
        {
          'subject': 'الذكاء الاصطناعي ولغات البرمجة',
          'stage': 'المرحلة الثانوية',
          'grade': 'الصف الأول الثانوي (Sec 1)',
          'curriculum_name': 'منهج الذكاء الاصطناعي ولغات البرمجة (Python)',
          'unit_name': 'الوحدة الأولى: الذكاء الاصطناعي ولغات البرمجة',
          'lesson_title': 'الدرس الخامس: معالجة أخطاء مدخلات المستخدم في لغة Python',
          'objectives': 'التحقق من صحة المدخلات Input Validation ومعالجة الاستثناءات باستخدام try / except.',
          'chapter_number': 1,
          'is_completed': 0,
        },
        // الوحدة الثانية: الذكاء الاصطناعي والأمن السيبراني
        {
          'subject': 'الذكاء الاصطناعي ولغات البرمجة',
          'stage': 'المرحلة الثانوية',
          'grade': 'الصف الأول الثانوي (Sec 1)',
          'curriculum_name': 'منهج الذكاء الاصطناعي ولغات البرمجة (Python)',
          'unit_name': 'الوحدة الثانية: الذكاء الاصطناعي والأمن السيبراني',
          'lesson_title': 'الدرس الأول: التنبؤ باستخدام نموذج الذكاء الاصطناعي',
          'objectives': 'مفهوم التنبؤ الآلي، تدريب النموذج واستخدامه في توقع النتائج.',
          'chapter_number': 2,
          'is_completed': 0,
        },
        {
          'subject': 'الذكاء الاصطناعي ولغات البرمجة',
          'stage': 'المرحلة الثانوية',
          'grade': 'الصف الأول الثانوي (Sec 1)',
          'curriculum_name': 'منهج الذكاء الاصطناعي ولغات البرمجة (Python)',
          'unit_name': 'الوحدة الثانية: الذكاء الاصطناعي والأمن السيبراني',
          'lesson_title': 'الدرس الثاني: الذكاء الاصطناعي وحقوق الملكية الفكرية',
          'objectives': 'الأخلاقيات الرقمية في استخدام الذكاء الاصطناعي، حقوق التأليف والنشر، والنزاهة الأكاديمية.',
          'chapter_number': 2,
          'is_completed': 0,
        },
        {
          'subject': 'الذكاء الاصطناعي ولغات البرمجة',
          'stage': 'المرحلة الثانوية',
          'grade': 'الصف الأول الثانوي (Sec 1)',
          'curriculum_name': 'منهج الذكاء الاصطناعي ولغات البرمجة (Python)',
          'unit_name': 'الوحدة الثانية: الذكاء الاصطناعي والأمن السيبراني',
          'lesson_title': 'الدرس الثالث: الوعي السيبراني والألعاب الإلكترونية الخطرة',
          'objectives': 'أمن المعلومات الشخصية، ومخاطر الألعاب والتطبيقات الإلكترونية غير الموثوقة وكيفية الحماية منها.',
          'chapter_number': 2,
          'is_completed': 0,
        },
        {
          'subject': 'الذكاء الاصطناعي ولغات البرمجة',
          'stage': 'المرحلة الثانوية',
          'grade': 'الصف الأول الثانوي (Sec 1)',
          'curriculum_name': 'منهج الذكاء الاصطناعي ولغات البرمجة (Python)',
          'unit_name': 'الوحدة الثانية: الذكاء الاصطناعي والأمن السيبراني',
          'lesson_title': 'الدرس الرابع: الذكاء الاصطناعي والتزييف العميق (Deepfake)',
          'objectives': 'تقنيات التزييف العميق Deepfake، كيفية كشف المحتوى المزيف، والمخاطر الأمنية والقانونية.',
          'chapter_number': 2,
          'is_completed': 0,
        },
      ];

      await db.transaction((txn) async {
        for (final l in lessonsToInsert) {
          await txn.insert(
            'curriculum_lessons',
            l,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await txn.insert('settings', {
          'key': seedKey,
          'value': 'true',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
      debugPrint('Successfully seeded AI Python curriculum into database.');
    } catch (e) {
      debugPrint('Error seeding AI Python curriculum: $e');
    }
  }

  Future<void> _cleanupLegacyDatabaseCopies(String databasesPath) async {
    if (await _secureStorage.read(key: _legacyCleanupKey) == 'done') return;

    var cleanupComplete = true;
    // 🛡️ Data Protection Guard: teacher_center.db is the active database and must NEVER be deleted!
    const legacyDatabaseNames = [
      'teacher_center_v2.db',
      'teacher_center_v1.db',
      'edu_academy.db',
      'teacher_center_backup.db',
    ];

    for (final name in legacyDatabaseNames) {
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File(path.join(databasesPath, '$name$suffix'));
        try {
          if (await file.exists()) await file.delete();
        } catch (error) {
          cleanupComplete = false;
          debugPrint('Could not remove legacy database file: $error');
        }
      }
    }

    final backupDirectories = <Directory>[];
    try {
      final documents = await getApplicationDocumentsDirectory();
      backupDirectories.add(Directory(path.join(documents.path, 'backups')));
    } catch (_) {
      cleanupComplete = false;
    }

    final backupNamePattern = RegExp(
      r'^EduAcademy_(Backup|Auto)_.*\.db$',
      caseSensitive: false,
    );
    for (final directory in backupDirectories) {
      try {
        if (!await directory.exists()) continue;
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is! File ||
              !backupNamePattern.hasMatch(path.basename(entity.path))) {
            continue;
          }

          final header = await entity.openRead(0, 16).first;
          if (!String.fromCharCodes(header).startsWith('SQLite format 3')) {
            continue;
          }
          await entity.delete();
        }
      } catch (error) {
        cleanupComplete = false;
        debugPrint('Could not clean legacy backups: $error');
      }
    }

    if (cleanupComplete) {
      await _secureStorage.write(key: _legacyCleanupKey, value: 'done');
    }
  }

  Future<String> _getDatabaseEncryptionKey([String? databasePath]) async {
    final savedKey = await _secureStorage.read(key: _databaseKeyName);
    if (savedKey != null && savedKey.isNotEmpty) return savedKey;

    if (databasePath != null) {
      final databaseFile = File(databasePath);
      if (await databaseFile.exists()) {
        try {
          final header = await databaseFile.openRead(0, 16).first;
          if (!String.fromCharCodes(header).startsWith('SQLite format 3')) {
            return '';
          }
        } catch (_) {
          return '';
        }
      }
    }

    final random = Random.secure();
    final key = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await _secureStorage.write(key: _databaseKeyName, value: key);
    return key;
  }

  // --- Students ---
  Future<StudentModel?> findStudentById(String studentId) async {
    final db = await database;
    final clean = studentId.trim();
    if (clean.isEmpty) return null;

    // 1. Direct match on ID
    var rows = await db.query(
      'students',
      where: 'id = ?',
      whereArgs: [clean],
      limit: 1,
    );
    if (rows.isNotEmpty) return StudentModel.fromMap(rows.first);

    // 2. Case-insensitive ID match
    rows = await db.query(
      'students',
      where: 'LOWER(id) = ?',
      whereArgs: [clean.toLowerCase()],
      limit: 1,
    );
    if (rows.isNotEmpty) return StudentModel.fromMap(rows.first);

    // 3. Match with or without Std- / STU- prefix
    if (clean.toUpperCase().startsWith('STD-') ||
        clean.toUpperCase().startsWith('STU-')) {
      final sub = clean.substring(4);
      rows = await db.query(
        'students',
        where: 'id LIKE ?',
        whereArgs: ['%$sub%'],
        limit: 1,
      );
      if (rows.isNotEmpty) return StudentModel.fromMap(rows.first);
    } else {
      rows = await db.query(
        'students',
        where: 'id = ? OR id = ? OR id LIKE ? OR id LIKE ?',
        whereArgs: ['Std-$clean', 'STU-$clean', '%Std-$clean%', '%STU-$clean%'],
        limit: 1,
      );
      if (rows.isNotEmpty) return StudentModel.fromMap(rows.first);
    }

    // 4. Match by phone or parent phone
    final digits = clean.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8) {
      final lastDigits = digits.length >= 10
          ? digits.substring(digits.length - 10)
          : digits;
      rows = await db.query(
        'students',
        where: 'student_phone LIKE ? OR parent_phone LIKE ?',
        whereArgs: ['%$lastDigits', '%$lastDigits'],
        limit: 1,
      );
      if (rows.isNotEmpty) return StudentModel.fromMap(rows.first);
    }

    // 5. Match by exact or partial full name
    rows = await db.query(
      'students',
      where: 'full_name = ?',
      whereArgs: [clean],
      limit: 1,
    );
    if (rows.isNotEmpty) return StudentModel.fromMap(rows.first);

    rows = await db.query(
      'students',
      where: 'full_name LIKE ?',
      whereArgs: ['%$clean%'],
      limit: 1,
    );
    if (rows.isNotEmpty) return StudentModel.fromMap(rows.first);

    return null;
  }

  Future<List<StudentModel>> getStudents({
    String? groupId,
    String? searchQuery,
  }) async {
    final db = await database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (groupId != null &&
        groupId.isNotEmpty &&
        searchQuery != null &&
        searchQuery.isNotEmpty) {
      whereClause =
          'group_id = ? AND (full_name LIKE ? OR student_phone LIKE ? OR parent_phone LIKE ?)';
      whereArgs = [
        groupId,
        '%$searchQuery%',
        '%$searchQuery%',
        '%$searchQuery%',
      ];
    } else if (groupId != null && groupId.isNotEmpty) {
      whereClause = 'group_id = ?';
      whereArgs = [groupId];
    } else if (searchQuery != null && searchQuery.isNotEmpty) {
      whereClause =
          'full_name LIKE ? OR student_phone LIKE ? OR parent_phone LIKE ?';
      whereArgs = ['%$searchQuery%', '%$searchQuery%', '%$searchQuery%'];
    }

    final rows = await db.query(
      'students',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'full_name COLLATE NOCASE',
    );
    return rows.map(StudentModel.fromMap).toList();
  }

  Future<void> saveStudent(StudentModel student) async {
    final db = await database;
    final map = Map<String, dynamic>.from(student.toMap());

    // ضمان وجود student_pin و parent_pin إذا لم يكونا محددين
    if (map['student_pin'] == null || (map['student_pin'] as String).trim().isEmpty) {
      final sPhoneDigits = student.studentPhone.replaceAll(RegExp(r'\D'), '');
      if (sPhoneDigits.length >= 4) {
        map['student_pin'] = sPhoneDigits.substring(sPhoneDigits.length - 4);
      } else {
        map['student_pin'] = '${1000 + Random().nextInt(9000)}';
      }
    }
    if (map['parent_pin'] == null || (map['parent_pin'] as String).trim().isEmpty) {
      final pPhoneDigits = student.parentPhone.replaceAll(RegExp(r'\D'), '');
      if (pPhoneDigits.length >= 4) {
        map['parent_pin'] = pPhoneDigits.substring(pPhoneDigits.length - 4);
      } else {
        map['parent_pin'] = '${1000 + Random().nextInt(9000)}';
      }
    }

    // UPSERT آمن دون تشغيل ON DELETE CASCADE
    final count = await db.update(
      'students',
      map,
      where: 'id = ?',
      whereArgs: [student.id],
    );
    if (count == 0) {
      await db.insert(
        'students',
        map,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    notifyChange(DataChangeEvent.students);
  }

  /// Generates a unique, non-sequential random 5-digit student code (between 10000 and 99999).
  Future<String> generateUniqueRandom5DigitCode() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT id FROM students');
    final existingIds = rows
        .map((r) => (r['id'] as String?)?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final rnd = Random();
    String code;
    do {
      final numVal = 10000 + rnd.nextInt(90000); // 10000 - 99999
      code = '$numVal';
    } while (existingIds.contains(code));

    return code;
  }

  /// Generates the next student code as a unique non-sequential 5-digit code string.
  Future<String> getNextStudentCode() async {
    return await generateUniqueRandom5DigitCode();
  }

  /// Returns a unique random 5-digit number for students.
  Future<int> getNextStudentCodeNumber() async {
    final code = await generateUniqueRandom5DigitCode();
    return int.tryParse(code) ?? 10001;
  }

  /// Safely updates a single student's ID/Code across all database tables (cascade).
  Future<void> updateStudentIdCascade(String oldId, String newId) async {
    final cleanOld = oldId.trim();
    final cleanNew = newId.trim();
    if (cleanOld.isEmpty || cleanNew.isEmpty || cleanOld == cleanNew) return;
    final db = await database;
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        await txn.rawUpdate('UPDATE students SET id = ? WHERE id = ?', [
          cleanNew,
          cleanOld,
        ]);
        await txn.rawUpdate(
          'UPDATE attendance SET student_id = ? WHERE student_id = ?',
          [cleanNew, cleanOld],
        );
        await txn.rawUpdate(
          'UPDATE payments SET student_id = ? WHERE student_id = ?',
          [cleanNew, cleanOld],
        );
        await txn.rawUpdate(
          'UPDATE financial_claims SET student_id = ? WHERE student_id = ?',
          [cleanNew, cleanOld],
        );
        await txn.rawUpdate(
          'UPDATE exam_scores SET student_id = ? WHERE student_id = ?',
          [cleanNew, cleanOld],
        );
        await txn.rawUpdate(
          'UPDATE session_cancellations SET student_id = ? WHERE student_id = ?',
          [cleanNew, cleanOld],
        );
        await txn.rawUpdate(
          'UPDATE sent_messages_ledger SET student_id = ? WHERE student_id = ?',
          [cleanNew, cleanOld],
        );
        await txn.rawUpdate(
          'UPDATE whatsapp_logs SET student_id = ? WHERE student_id = ?',
          [cleanNew, cleanOld],
        );
        await txn.rawUpdate(
          'UPDATE session_logs SET student_id = ? WHERE student_id = ?',
          [cleanNew, cleanOld],
        );
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
    notifyChange(DataChangeEvent.students);
    notifyChange(DataChangeEvent.attendance);
    notifyChange(DataChangeEvent.finances);
  }

  /// Safely assigns unique non-sequential random 5-digit codes (10000 - 99999) to all students.
  Future<int> renumberAllStudentsTo5Digits() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT id, full_name FROM students ORDER BY full_name COLLATE NOCASE',
    );
    if (rows.isEmpty) return 0;

    int count = 0;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random();
    final usedCodes = <String>{};

    // Pre-generate unique random 5-digit codes (10000 - 99999) for each student
    final newCodes = <String>[];
    for (int i = 0; i < rows.length; i++) {
      String code;
      do {
        code = '${10000 + rnd.nextInt(90000)}';
      } while (usedCodes.contains(code));
      usedCodes.add(code);
      newCodes.add(code);
    }

    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        // Pass 1: rename old IDs to temporary unique strings to avoid any collision
        for (int i = 0; i < rows.length; i++) {
          final oldId = rows[i]['id'] as String;
          final tempId = '__TMP_REN_${i}_$timestamp';
          await txn.rawUpdate('UPDATE students SET id = ? WHERE id = ?', [
            tempId,
            oldId,
          ]);
          await txn.rawUpdate(
            'UPDATE attendance SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE payments SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE financial_claims SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE exam_scores SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE session_cancellations SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE sent_messages_ledger SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE whatsapp_logs SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE session_logs SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
        }

        // Pass 2: assign unique random 5-digit codes
        for (int i = 0; i < rows.length; i++) {
          final tempId = '__TMP_REN_${i}_$timestamp';
          final newId = newCodes[i];
          await txn.rawUpdate('UPDATE students SET id = ? WHERE id = ?', [
            newId,
            tempId,
          ]);
          await txn.rawUpdate(
            'UPDATE attendance SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE payments SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE financial_claims SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE exam_scores SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE session_cancellations SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE sent_messages_ledger SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE whatsapp_logs SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE session_logs SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          count++;
        }
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }

    notifyChange(DataChangeEvent.students);
    notifyChange(DataChangeEvent.attendance);
    notifyChange(DataChangeEvent.finances);
    return count;
  }

  /// Safely renumbers all students alphabetically to start from Std-100.
  /// Updates all related tables (attendance, payments, exam_scores, session_cancellations).
  Future<int> renumberAllStudentsToStd100() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT id, full_name FROM students ORDER BY full_name COLLATE NOCASE',
    );
    if (rows.isEmpty) return 0;

    int count = 0;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        // Pass 1: rename old IDs to temporary unique strings to avoid any collision
        for (int i = 0; i < rows.length; i++) {
          final oldId = rows[i]['id'] as String;
          final tempId = '__TMP_REN_${i}_$timestamp';
          await txn.rawUpdate('UPDATE students SET id = ? WHERE id = ?', [
            tempId,
            oldId,
          ]);
          await txn.rawUpdate(
            'UPDATE attendance SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE payments SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE financial_claims SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE exam_scores SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE session_cancellations SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE sent_messages_ledger SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE whatsapp_logs SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
          await txn.rawUpdate(
            'UPDATE session_logs SET student_id = ? WHERE student_id = ?',
            [tempId, oldId],
          );
        }

        // Pass 2: assign clean sequential Std-100, Std-101, ...
        int code = 100;
        for (int i = 0; i < rows.length; i++) {
          final tempId = '__TMP_REN_${i}_$timestamp';
          final newId = 'Std-$code';
          code++;
          await txn.rawUpdate('UPDATE students SET id = ? WHERE id = ?', [
            newId,
            tempId,
          ]);
          await txn.rawUpdate(
            'UPDATE attendance SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE payments SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE financial_claims SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE exam_scores SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE session_cancellations SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE sent_messages_ledger SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE whatsapp_logs SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          await txn.rawUpdate(
            'UPDATE session_logs SET student_id = ? WHERE student_id = ?',
            [newId, tempId],
          );
          count++;
        }
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }

    notifyChange(DataChangeEvent.students);
    notifyChange(DataChangeEvent.attendance);
    notifyChange(DataChangeEvent.finances);
    return count;
  }

  Future<void> saveStudentsBatch(List<StudentModel> students) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final s in students) {
        final map = Map<String, dynamic>.from(s.toMap());
        if (map['student_pin'] == null || (map['student_pin'] as String).trim().isEmpty) {
          final sPhoneDigits = s.studentPhone.replaceAll(RegExp(r'\D'), '');
          map['student_pin'] = sPhoneDigits.length >= 4
              ? sPhoneDigits.substring(sPhoneDigits.length - 4)
              : '${1000 + Random().nextInt(9000)}';
        }
        if (map['parent_pin'] == null || (map['parent_pin'] as String).trim().isEmpty) {
          final pPhoneDigits = s.parentPhone.replaceAll(RegExp(r'\D'), '');
          map['parent_pin'] = pPhoneDigits.length >= 4
              ? pPhoneDigits.substring(pPhoneDigits.length - 4)
              : '${1000 + Random().nextInt(9000)}';
        }
        final count = await txn.update(
          'students',
          map,
          where: 'id = ?',
          whereArgs: [s.id],
        );
        if (count == 0) {
          await txn.insert(
            'students',
            map,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });
    notifyChange(DataChangeEvent.students);
  }

  Future<void> deleteStudent(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('financial_claims', where: 'student_id = ?', whereArgs: [id]);
      await txn.delete('attendance', where: 'student_id = ?', whereArgs: [id]);
      await txn.delete('payments', where: 'student_id = ?', whereArgs: [id]);
      await txn.delete('exam_scores', where: 'student_id = ?', whereArgs: [id]);
      await txn.delete('session_cancellations', where: 'student_id = ?', whereArgs: [id]);
      await txn.delete('certificates', where: 'student_id = ?', whereArgs: [id]);
      await txn.delete('students', where: 'id = ?', whereArgs: [id]);
    });
    notifyChange(DataChangeEvent.students);
    notifyChange(DataChangeEvent.attendance);
    notifyChange(DataChangeEvent.finances);
  }

  /// Deletes multiple students in a single batch transaction with cascade cleanup.
  Future<int> deleteStudentsBatch(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final db = await database;
    int deleted = 0;
    await db.transaction((txn) async {
      final placeholders = List.filled(ids.length, '?').join(',');
      // Delete from related records first
      await txn.rawDelete(
        'DELETE FROM financial_claims WHERE student_id IN ($placeholders)',
        ids,
      );
      await txn.rawDelete(
        'DELETE FROM attendance WHERE student_id IN ($placeholders)',
        ids,
      );
      await txn.rawDelete(
        'DELETE FROM payments WHERE student_id IN ($placeholders)',
        ids,
      );
      await txn.rawDelete(
        'DELETE FROM exam_scores WHERE student_id IN ($placeholders)',
        ids,
      );
      await txn.rawDelete(
        'DELETE FROM session_cancellations WHERE student_id IN ($placeholders)',
        ids,
      );
      await txn.rawDelete(
        'DELETE FROM certificates WHERE student_id IN ($placeholders)',
        ids,
      );
      deleted = await txn.rawDelete(
        'DELETE FROM students WHERE id IN ($placeholders)',
        ids,
      );
    });
    notifyChange(DataChangeEvent.students);
    notifyChange(DataChangeEvent.attendance);
    notifyChange(DataChangeEvent.finances);
    return deleted;
  }

  /// Reassigns or removes multiple students to/from a group.
  Future<void> updateStudentsGroupBatch(
    List<String> ids,
    String? newGroupId,
  ) async {
    if (ids.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final placeholders = List.filled(ids.length, '?').join(',');
      await txn.rawUpdate(
        'UPDATE students SET group_id = ? WHERE id IN ($placeholders)',
        [newGroupId, ...ids],
      );
    });
    notifyChange(DataChangeEvent.groups);
    notifyChange(DataChangeEvent.students);
  }

  /// Updates specific fields across multiple selected students simultaneously.
  Future<int> updateStudentsBatchFields(
    List<String> ids, {
    String? grade,
    String? stage,
    String? paymentPlan,
    double? outstandingAmount,
  }) async {
    if (ids.isEmpty) return 0;
    final Map<String, Object?> updates = {};
    if (grade != null) updates['grade'] = grade;
    if (stage != null) updates['stage'] = stage;
    if (paymentPlan != null) updates['payment_plan'] = paymentPlan;
    if (outstandingAmount != null)
      updates['outstanding_amount'] = outstandingAmount;
    if (updates.isEmpty) return 0;

    final db = await database;
    int updated = 0;
    await db.transaction((txn) async {
      final setClause = updates.keys.map((k) => '$k = ?').join(', ');
      final setValues = updates.values.toList();
      final placeholders = List.filled(ids.length, '?').join(',');
      updated = await txn.rawUpdate(
        'UPDATE students SET $setClause WHERE id IN ($placeholders)',
        [...setValues, ...ids],
      );
    });
    notifyChange(DataChangeEvent.students);
    notifyChange(DataChangeEvent.finances);
    return updated;
  }

  Future<void> updateGroupStudents(
    String groupId,
    List<String> studentIds,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE students SET group_id = NULL WHERE group_id = ?',
        [groupId],
      );
      if (studentIds.isNotEmpty) {
        final placeholders = List.filled(studentIds.length, '?').join(',');
        await txn.rawUpdate(
          'UPDATE students SET group_id = ? WHERE id IN ($placeholders)',
          [groupId, ...studentIds],
        );
      }
    });
    notifyChange(DataChangeEvent.groups);
    notifyChange(DataChangeEvent.students);
  }

  Future<void> assignStudentToGroup(String studentId, String groupId) async {
    final db = await database;
    await db.update(
      'students',
      {'group_id': groupId},
      where: 'id = ?',
      whereArgs: [studentId],
    );
  }

  Future<void> removeStudentFromGroup(String studentId) async {
    final db = await database;
    await db.update(
      'students',
      {'group_id': null},
      where: 'id = ?',
      whereArgs: [studentId],
    );
  }

  // --- Groups ---
  Future<List<GroupModel>> getGroups() async {
    final db = await database;
    final rows = await db.query('groups', orderBy: 'name ASC');
    return rows.map(GroupModel.fromMap).toList();
  }

  Future<GroupModel?> getGroupById(String id) async {
    final db = await database;
    final rows = await db.query(
      'groups',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GroupModel.fromMap(rows.first);
  }

  Future<void> saveGroup(GroupModel group) async {
    final db = await database;
    await db.insert(
      'groups',
      group.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.groups);
  }

  Future<void> saveGroupsBatch(List<GroupModel> groups) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final g in groups) {
        batch.insert(
          'groups',
          g.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    notifyChange(DataChangeEvent.groups);
  }

  Future<void> deleteGroup(String id) async {
    final db = await database;
    await db.delete('groups', where: 'id = ?', whereArgs: [id]);
    notifyChange(DataChangeEvent.groups);
  }

  // --- School Timetable (جدول حصص المدرسة) ---
  Future<List<SchoolPeriodModel>> getSchoolPeriods({String? dayOfWeek}) async {
    final db = await database;
    final List<Map<String, dynamic>> rows;
    if (dayOfWeek != null && dayOfWeek.isNotEmpty) {
      rows = await db.query(
        'school_timetable',
        where: 'day_of_week = ?',
        whereArgs: [dayOfWeek],
        orderBy: 'period_number ASC',
      );
    } else {
      rows = await db.query('school_timetable', orderBy: 'period_number ASC');
    }
    return rows.map(SchoolPeriodModel.fromMap).toList();
  }

  Future<void> saveSchoolPeriod(SchoolPeriodModel period) async {
    final db = await database;
    await db.insert(
      'school_timetable',
      period.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.timetable);
  }

  Future<void> deleteSchoolPeriod(String id) async {
    final db = await database;
    await db.delete('school_timetable', where: 'id = ?', whereArgs: [id]);
    notifyChange(DataChangeEvent.timetable);
  }

  Future<void> clearSchoolTimetable() async {
    final db = await database;
    await db.delete('school_timetable');
    notifyChange(DataChangeEvent.timetable);
  }

  Future<void> replaceSchoolPeriods(List<SchoolPeriodModel> periods) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('school_timetable');
      final batch = txn.batch();
      for (final period in periods) {
        batch.insert(
          'school_timetable',
          period.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    notifyChange(DataChangeEvent.timetable);
  }

  Future<void> backupSchoolTimetable() async {
    final current = await getSchoolPeriods();
    final jsonList = jsonEncode(current.map((p) => p.toMap()).toList());
    await setSetting('school_timetable_backup', jsonList);
    await setSetting('school_timetable_backup_timestamp', DateTime.now().toIso8601String());
  }

  Future<bool> hasSchoolTimetableBackup() async {
    final backupStr = await getSetting('school_timetable_backup', defaultValue: '');
    return backupStr.trim().isNotEmpty && backupStr.trim() != '[]';
  }

  Future<int> restoreSchoolTimetableBackup() async {
    final backupStr = await getSetting('school_timetable_backup', defaultValue: '');
    if (backupStr.trim().isEmpty) return 0;
    try {
      final List<dynamic> decoded = jsonDecode(backupStr);
      final periods = decoded.map((m) => SchoolPeriodModel.fromMap(m as Map<String, dynamic>)).toList();
      await replaceSchoolPeriods(periods);
      return periods.length;
    } catch (e) {
      debugPrint('Error restoring school timetable backup: $e');
      return 0;
    }
  }

  Future<void> replaceSchoolPeriodsForDay(String dayOfWeek, List<SchoolPeriodModel> dayPeriods) async {
    await backupSchoolTimetable();
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('school_timetable', where: 'day_of_week = ?', whereArgs: [dayOfWeek]);
      final batch = txn.batch();
      for (final period in dayPeriods) {
        batch.insert(
          'school_timetable',
          period.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    notifyChange(DataChangeEvent.timetable);
  }

  Future<int> applyAiSchoolTimetableImport(List<SchoolPeriodModel> newPeriods, {String? targetDayOnly}) async {
    await backupSchoolTimetable();
    if (targetDayOnly != null && targetDayOnly.isNotEmpty && targetDayOnly != 'all') {
      await replaceSchoolPeriodsForDay(targetDayOnly, newPeriods);
    } else {
      await replaceSchoolPeriods(newPeriods);
    }
    return newPeriods.length;
  }

  Future<void> _populateMrAdelTimetable(Database db) async {
    // 🛡️ Data Protection Guard: NEVER overwrite or wipe an existing timetable!
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM school_timetable'),
    ) ?? 0;
    if (count > 0) {
      debugPrint('🛡️ [Data Protection] school_timetable already contains $count records. Preserving user data.');
      return;
    }

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final period in mrAdelInitialPeriods) {
        batch.insert(
          'school_timetable',
          period.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    });
    notifyChange(DataChangeEvent.timetable);
  }

  Future<void> populateAdelSolimanTimetable() async {
    final db = await database;
    await _populateMrAdelTimetable(db);
  }

  // ==========================================
  // 🛡️ DATA INTEGRITY & MIGRATION WARNING SYSTEM
  // ==========================================
  Future<void> recordDataMigrationNotice({
    required String title,
    required String message,
    bool isWarning = false,
  }) async {
    final notice = {
      'title': title,
      'message': message,
      'is_warning': isWarning,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await setSetting('pending_data_migration_notice', jsonEncode(notice));
  }

  Future<Map<String, dynamic>?> checkPendingDataMigrationNotice() async {
    final raw = await getSetting('pending_data_migration_notice', defaultValue: '');
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPendingDataMigrationNotice() async {
    await setSetting('pending_data_migration_notice', '');
  }

  static const List<SchoolPeriodModel> mrAdelInitialPeriods = [
    // --- الأحد (Sunday) ---
    SchoolPeriodModel(
      id: 'adel_sun_2',
      dayOfWeek: 'الأحد',
      periodNumber: 2,
      startTime: '08:25',
      endTime: '09:10',
      className: 'SEC 3',
      subject: 'التربية الدينية',
    ),
    SchoolPeriodModel(
      id: 'adel_sun_3',
      dayOfWeek: 'الأحد',
      periodNumber: 3,
      startTime: '09:10',
      endTime: '09:55',
      className: 'SEC 2',
      subject: 'تخصص',
    ),
    SchoolPeriodModel(
      id: 'adel_sun_4',
      dayOfWeek: 'الأحد',
      periodNumber: 4,
      startTime: '09:55',
      endTime: '10:40',
      className: 'SEC 1A',
      subject: 'programming',
    ),
    SchoolPeriodModel(
      id: 'adel_sun_8',
      dayOfWeek: 'الأحد',
      periodNumber: 8,
      startTime: '01:45',
      endTime: '02:30',
      className: 'SEC 1A',
      subject: 'programming',
    ),

    // --- الإثنين (Monday) ---
    SchoolPeriodModel(
      id: 'adel_mon_2',
      dayOfWeek: 'الإثنين',
      periodNumber: 2,
      startTime: '08:25',
      endTime: '09:10',
      className: 'SEC 2',
      subject: 'تخصص',
    ),
    SchoolPeriodModel(
      id: 'adel_mon_5',
      dayOfWeek: 'الإثنين',
      periodNumber: 5,
      startTime: '11:10',
      endTime: '12:00',
      className: 'Prep 3B',
      subject: 'ICT',
    ),
    SchoolPeriodModel(
      id: 'adel_mon_6',
      dayOfWeek: 'الإثنين',
      periodNumber: 6,
      startTime: '12:00',
      endTime: '12:45',
      className: 'SEC 2',
      subject: 'ثقافه مالية',
    ),
    SchoolPeriodModel(
      id: 'adel_mon_8',
      dayOfWeek: 'الإثنين',
      periodNumber: 8,
      startTime: '01:45',
      endTime: '02:30',
      className: 'SEC 1B',
      subject: 'programming',
    ),

    // --- الثلاثاء (Tuesday) ---
    SchoolPeriodModel(
      id: 'adel_tue_2',
      dayOfWeek: 'الثلاثاء',
      periodNumber: 2,
      startTime: '08:25',
      endTime: '09:10',
      className: 'SEC 1B',
      subject: 'programming',
    ),
    SchoolPeriodModel(
      id: 'adel_tue_3',
      dayOfWeek: 'الثلاثاء',
      periodNumber: 3,
      startTime: '09:10',
      endTime: '09:55',
      className: 'SEC 1A',
      subject: 'التربية الدينية',
    ),
    SchoolPeriodModel(
      id: 'adel_tue_5',
      dayOfWeek: 'الثلاثاء',
      periodNumber: 5,
      startTime: '11:10',
      endTime: '12:00',
      className: 'SEC 2',
      subject: 'تخصص',
      room: 'pc-lab',
    ),
    SchoolPeriodModel(
      id: 'adel_tue_6',
      dayOfWeek: 'الثلاثاء',
      periodNumber: 6,
      startTime: '12:00',
      endTime: '12:45',
      className: 'SEC 2',
      subject: 'تخصص',
      room: 'pc-lab',
    ),
    SchoolPeriodModel(
      id: 'adel_tue_8',
      dayOfWeek: 'الثلاثاء',
      periodNumber: 8,
      startTime: '01:45',
      endTime: '02:30',
      className: 'SEC 1A',
      subject: 'programming',
    ),

    // --- الأربعاء (Wednesday) ---
    SchoolPeriodModel(
      id: 'adel_wed_1',
      dayOfWeek: 'الأربعاء',
      periodNumber: 1,
      startTime: '07:40',
      endTime: '08:25',
      className: 'SEC 1A',
      subject: 'التربية الدينية',
    ),
    SchoolPeriodModel(
      id: 'adel_wed_5',
      dayOfWeek: 'الأربعاء',
      periodNumber: 5,
      startTime: '11:10',
      endTime: '12:00',
      className: 'SEC 2',
      subject: 'ثقافه مالية',
    ),
    SchoolPeriodModel(
      id: 'adel_wed_6',
      dayOfWeek: 'الأربعاء',
      periodNumber: 6,
      startTime: '12:00',
      endTime: '12:45',
      className: 'SEC 2',
      subject: 'تخصص',
    ),
    SchoolPeriodModel(
      id: 'adel_wed_7',
      dayOfWeek: 'الأربعاء',
      periodNumber: 7,
      startTime: '01:00',
      endTime: '01:45',
      className: 'SEC 3',
      subject: 'التربية الدينية',
    ),
    SchoolPeriodModel(
      id: 'adel_wed_8',
      dayOfWeek: 'الأربعاء',
      periodNumber: 8,
      startTime: '01:45',
      endTime: '02:30',
      className: 'SEC 1B',
      subject: 'programming',
    ),

    // --- الخميس (Thursday) ---
    SchoolPeriodModel(
      id: 'adel_thu_2',
      dayOfWeek: 'الخميس',
      periodNumber: 2,
      startTime: '08:25',
      endTime: '09:10',
      className: 'Prep 3A',
      subject: 'ICT',
    ),
    SchoolPeriodModel(
      id: 'adel_thu_3',
      dayOfWeek: 'الخميس',
      periodNumber: 3,
      startTime: '09:10',
      endTime: '09:55',
      className: 'SEC 2',
      subject: 'تخصص',
    ),
    SchoolPeriodModel(
      id: 'adel_thu_5',
      dayOfWeek: 'الخميس',
      periodNumber: 5,
      startTime: '11:10',
      endTime: '12:00',
      className: 'SEC 1B',
      subject: 'programming',
    ),
    SchoolPeriodModel(
      id: 'adel_thu_8',
      dayOfWeek: 'الخميس',
      periodNumber: 8,
      startTime: '01:45',
      endTime: '02:30',
      className: 'SEC 1A',
      subject: 'programming',
    ),
  ];

  // --- Tutoring Timetable (جدول مواعيد وسناتر الدروس الخصوصية - منفصل تماماً) ---
  Future<List<SchoolPeriodModel>> getTutoringPeriods({
    String? dayOfWeek,
  }) async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tutoring_timetable (
        id TEXT PRIMARY KEY,
        day_of_week TEXT NOT NULL,
        period_number INTEGER NOT NULL,
        class_name TEXT NOT NULL,
        subject TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        room TEXT DEFAULT '',
        notes TEXT DEFAULT '',
        is_recess INTEGER NOT NULL DEFAULT 0,
        supervision_duty TEXT DEFAULT '',
        is_reserve INTEGER NOT NULL DEFAULT 0
      )
    ''');
    final List<Map<String, dynamic>> rows;
    if (dayOfWeek != null && dayOfWeek.isNotEmpty) {
      rows = await db.query(
        'tutoring_timetable',
        where: 'day_of_week = ?',
        whereArgs: [dayOfWeek],
        orderBy: 'period_number ASC',
      );
    } else {
      rows = await db.query('tutoring_timetable', orderBy: 'period_number ASC');
    }
    return rows.map(SchoolPeriodModel.fromMap).toList();
  }

  Future<void> saveTutoringPeriod(SchoolPeriodModel period) async {
    final db = await database;
    await getTutoringPeriods(); // ensures table exists
    await db.insert(
      'tutoring_timetable',
      period.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.timetable);
  }

  Future<void> deleteTutoringPeriod(String id) async {
    final db = await database;
    await db.delete('tutoring_timetable', where: 'id = ?', whereArgs: [id]);
    notifyChange(DataChangeEvent.timetable);
  }

  Future<void> clearTutoringTimetable() async {
    final db = await database;
    await db.delete('tutoring_timetable');
    notifyChange(DataChangeEvent.timetable);
  }

  // --- School Classes (قاعدة بيانات الفصول المدرسية - بدون بيانات وهمية) ---
  Future<List<Map<String, dynamic>>> getSchoolClasses() async {
    final db = await database;
    return await db.query(
      'school_classes',
      orderBy: 'sort_order ASC, class_name ASC',
    );
  }

  Future<void> saveSchoolClass(Map<String, dynamic> classData) async {
    final db = await database;
    await db.insert(
      'school_classes',
      classData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.timetable);
  }

  Future<void> deleteSchoolClass(String id) async {
    final db = await database;
    await db.delete('school_classes', where: 'id = ?', whereArgs: [id]);
    notifyChange(DataChangeEvent.timetable);
  }

  // --- School Subjects (قاعدة بيانات المواد المدرسية - بدون بيانات وهمية) ---
  Future<List<Map<String, dynamic>>> getSchoolSubjects() async {
    final db = await database;
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS school_subjects (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          sort_order INTEGER DEFAULT 0
        )
      ''');
      return await db.query(
        'school_subjects',
        orderBy: 'sort_order ASC, name ASC',
      );
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSchoolSubject(Map<String, dynamic> subjectData) async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS school_subjects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER DEFAULT 0
      )
    ''');
    await db.insert(
      'school_subjects',
      subjectData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.timetable);
  }

  Future<void> deleteSchoolSubject(String id) async {
    final db = await database;
    await db.delete('school_subjects', where: 'id = ?', whereArgs: [id]);
    notifyChange(DataChangeEvent.timetable);
  }

  // --- Attendance ---
  Future<AttendanceModel> recordAttendance({
    required String studentId,
    String status = 'present',
    String source = 'qr',
    DateTime? date,
  }) async {
    final db = await database;
    final now = date ?? DateTime.now();
    final dateStr = now.toIso8601String().substring(0, 10);
    final existingRows = await db.query(
      'attendance',
      where: 'student_id = ? AND attendance_date = ?',
      whereArgs: [studentId, dateStr],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      final updated = AttendanceModel(
        id: existingRows.first['id'] as int?,
        studentId: studentId,
        attendanceDate: dateStr,
        checkInAt: now,
        status: status,
        source: source,
      );
      await db.update(
        'attendance',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      notifyChange(DataChangeEvent.attendance);
      return updated;
    }
    final attendance = AttendanceModel(
      id: null,
      studentId: studentId,
      attendanceDate: dateStr,
      checkInAt: now,
      status: status,
      source: source,
    );
    final id = await db.insert('attendance', attendance.toMap());
    notifyChange(DataChangeEvent.attendance);
    return AttendanceModel(
      id: id,
      studentId: studentId,
      attendanceDate: dateStr,
      checkInAt: now,
      status: status,
      source: source,
    );
  }

  Future<AttendanceModel?> getTodayAttendance(String studentId) async {
    final db = await database;
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await db.query(
      'attendance',
      where: 'student_id = ? AND attendance_date = ?',
      whereArgs: [studentId, date],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AttendanceModel.fromMap(rows.first);
  }

  Future<List<AttendanceModel>> getAttendanceForDate(String date) async {
    final db = await database;
    final rows = await db.query(
      'attendance',
      where: 'attendance_date = ?',
      whereArgs: [date],
    );
    return rows.map(AttendanceModel.fromMap).toList();
  }

  Future<List<AttendanceModel>> getStudentAttendance(String studentId) async {
    final db = await database;
    final rows = await db.query(
      'attendance',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'attendance_date DESC',
    );
    return rows.map(AttendanceModel.fromMap).toList();
  }

  Future<List<AttendanceModel>> getAllAttendance() async {
    final db = await database;
    final rows = await db.query('attendance', orderBy: 'attendance_date DESC');
    return rows.map(AttendanceModel.fromMap).toList();
  }

  // --- Group Interactive Attendance ---
  Future<List<Map<String, dynamic>>> getPendingAttendanceSessions({int limit = 10}) async {
    final db = await database;
    try {
      final rows = await db.rawQuery('''
        SELECT a.attendance_date as date, s.group_id as group_id, g.name as group_name, g.grade as grade,
               COUNT(DISTINCT s.id) as total_students,
               SUM(CASE WHEN a.status = 'present' OR a.status = 'late' THEN 1 ELSE 0 END) as present_count,
               MAX(CASE WHEN sl.lesson_title IS NOT NULL AND TRIM(sl.lesson_title) != '' AND TRIM(sl.lesson_title) != 'حصة دراسية اعتيادية' THEN 1 ELSE 0 END) as has_lesson,
               MAX(CASE WHEN sl.lesson_title IS NOT NULL THEN sl.lesson_title ELSE '' END) as lesson_title
        FROM attendance a
        JOIN students s ON a.student_id = s.id
        LEFT JOIN groups g ON s.group_id = g.id
        LEFT JOIN session_logs sl ON sl.group_id = s.group_id AND sl.date = a.attendance_date
        WHERE s.group_id IS NOT NULL AND TRIM(s.group_id) != ''
        GROUP BY a.attendance_date, s.group_id
        ORDER BY a.attendance_date DESC
      ''');

      final List<Map<String, dynamic>> pending = [];
      for (final r in rows) {
        final gId = r['group_id'] as String? ?? '';
        final dStr = r['date'] as String? ?? '';
        if (gId.isEmpty || dStr.isEmpty) continue;

        final isReportSent = (await getSetting('report_sent_${gId}_$dStr', defaultValue: 'false')) == 'true';
        final isLocked = (await getSetting('attendance_lock_${gId}_$dStr', defaultValue: 'false')) == 'true';
        final hasLesson = (r['has_lesson'] as int? ?? 0) == 1;

        // If attendance was recorded, but neither report sent nor locked nor lesson filled:
        if (!isReportSent && (!isLocked || !hasLesson)) {
          pending.add({
            'date': dStr,
            'group_id': gId,
            'group_name': r['group_name'] ?? 'مجموعة',
            'grade': r['grade'] ?? '',
            'total_students': r['total_students'] ?? 0,
            'present_count': r['present_count'] ?? 0,
            'has_lesson': hasLesson,
            'lesson_title': r['lesson_title'] ?? '',
          });
          if (pending.length >= limit) break;
        }
      }
      return pending;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getGroupStudentsWithAttendance({
    required String groupId,
    required String date,
  }) async {
    final db = await database;
    return await db.rawQuery(
      '''
      SELECT s.id, s.full_name, s.student_phone, s.parent_phone, s.grade, s.outstanding_amount,
             a.status AS attendance_status, a.source AS attendance_source, a.check_in_at,
             a.recitation_rating, a.recitation_score, a.homework_status, a.notes AS student_notes,
             a.session_type
      FROM students s
      LEFT JOIN attendance a ON s.id = a.student_id AND a.attendance_date = ?
      WHERE s.group_id = ?
      ORDER BY s.full_name COLLATE NOCASE
    ''',
      [date, groupId],
    );
  }

  Future<void> deleteStudentAttendance({
    required String studentId,
    required String date,
  }) async {
    final db = await database;
    await db.delete(
      'attendance',
      where: 'student_id = ? AND attendance_date = ?',
      whereArgs: [studentId, date],
    );
    notifyChange(DataChangeEvent.attendance);
  }

  Future<void> setStudentAttendanceStatus({
    required String studentId,
    required String date,
    required String? status,
    String? sessionType,
  }) async {
    if (status == null || status.isEmpty || status == 'unmarked') {
      await deleteStudentAttendance(studentId: studentId, date: date);
      return;
    }
    final db = await database;
    final now = DateTime.now();
    final existing = await db.query(
      'attendance',
      where: 'student_id = ? AND attendance_date = ?',
      whereArgs: [studentId, date],
      limit: 1,
    );

    final values = <String, dynamic>{
      'status': status,
      'source': 'manual',
      'check_in_at': now.toIso8601String(),
      if (sessionType != null) 'session_type': sessionType,
    };

    if (existing.isNotEmpty) {
      await db.update(
        'attendance',
        values,
        where: 'student_id = ? AND attendance_date = ?',
        whereArgs: [studentId, date],
      );
    } else {
      values['student_id'] = studentId;
      values['attendance_date'] = date;
      if (sessionType == null) values['session_type'] = 'regular';
      await db.insert('attendance', values);
    }
    notifyChange(DataChangeEvent.attendance);
  }

  Future<void> updateStudentAttendanceDetails({
    required String studentId,
    required String date,
    String? status,
    String? recitationRating,
    double? recitationScore,
    String? homeworkStatus,
    String? notes,
    String? sessionType,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final existing = await db.query(
      'attendance',
      where: 'student_id = ? AND attendance_date = ?',
      whereArgs: [studentId, date],
      limit: 1,
    );

    final values = <String, dynamic>{
      if (status != null) 'status': status,
      if (recitationRating != null) 'recitation_rating': recitationRating,
      if (recitationScore != null) 'recitation_score': recitationScore,
      if (homeworkStatus != null) 'homework_status': homeworkStatus,
      if (notes != null) 'notes': notes,
      if (sessionType != null) 'session_type': sessionType,
      'source': 'manual',
    };

    if (existing.isNotEmpty) {
      await db.update(
        'attendance',
        values,
        where: 'student_id = ? AND attendance_date = ?',
        whereArgs: [studentId, date],
      );
    } else {
      values['student_id'] = studentId;
      values['attendance_date'] = date;
      values['check_in_at'] = now.toIso8601String();
      values['status'] = status ?? 'present';
      if (sessionType == null) values['session_type'] = 'regular';
      await db.insert('attendance', values);
    }
    notifyChange(DataChangeEvent.attendance);
  }

  Future<void> markAllGroupAttendance({
    required String groupId,
    required String date,
    required String status,
    String? sessionType,
  }) async {
    final db = await database;
    final students = await db.query(
      'students',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    final now = DateTime.now().toIso8601String();
    for (final s in students) {
      final sId = s['id'] as String;
      final existing = await db.query(
        'attendance',
        where: 'student_id = ? AND attendance_date = ?',
        whereArgs: [sId, date],
      );
      final values = <String, dynamic>{
        'status': status,
        'source': 'manual',
        if (sessionType != null) 'session_type': sessionType,
      };
      if (existing.isNotEmpty) {
        await db.update(
          'attendance',
          values,
          where: 'student_id = ? AND attendance_date = ?',
          whereArgs: [sId, date],
        );
      } else {
        values['student_id'] = sId;
        values['attendance_date'] = date;
        values['check_in_at'] = now;
        if (sessionType == null) values['session_type'] = 'regular';
        await db.insert('attendance', values);
      }
    }
    notifyChange(DataChangeEvent.attendance);
  }

  Future<void> resetGroupAttendanceForDate({
    required String groupId,
    required String date,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // Find all students in group to reverse any session fees charged
      final students = await txn.query(
        'students',
        columns: ['id', 'outstanding_amount'],
        where: 'group_id = ?',
        whereArgs: [groupId],
      );

      for (final s in students) {
        final sId = s['id'] as String;
        final claimId = 'session_fee_${groupId}_${sId}_$date';
        final payments = await txn.query(
          'payments',
          where: 'claim_id = ? OR note LIKE ?',
          whereArgs: [claimId, '%$claimId%'],
        );
        if (payments.isNotEmpty) {
          final charged = (payments.first['amount'] as num?)?.toDouble() ?? 0.0;
          final curOut = (s['outstanding_amount'] as num?)?.toDouble() ?? 0.0;
          final newOutstanding = (curOut - charged).clamp(0.0, double.infinity).toDouble();
          await txn.update(
            'students',
            {'outstanding_amount': newOutstanding},
            where: 'id = ?',
            whereArgs: [sId],
          );
          await txn.delete(
            'payments',
            where: 'claim_id = ? OR note LIKE ?',
            whereArgs: [claimId, '%$claimId%'],
          );
          await txn.update(
            'financial_claims',
            {'status': 'waived', 'note': 'ملغاة بسبب تصفير كشف الحصة'},
            where: 'claim_id = ?',
            whereArgs: [claimId],
          );
        }
      }

      await txn.delete(
        'attendance',
        where:
            'attendance_date = ? AND student_id IN (SELECT id FROM students WHERE group_id = ?)',
        whereArgs: [date, groupId],
      );

      await txn.delete(
        'session_cancellations',
        where: 'group_id = ? AND date = ?',
        whereArgs: [groupId, date],
      );
    });
    notifyChange(DataChangeEvent.attendance);
    notifyChange(DataChangeEvent.finances);
  }

  // --- Session Cancellations (Teacher & Student) ---
  Future<void> recordSessionCancellation({
    required String groupId,
    required String date,
    required String cancelledBy, // 'teacher' or 'student'
    String? studentId,
    String? reason,
    String? notes,
    bool noticeSent = false,
  }) async {
    final db = await database;
    if (studentId != null) {
      await db.delete(
        'session_cancellations',
        where: 'group_id = ? AND date = ? AND student_id = ?',
        whereArgs: [groupId, date, studentId],
      );
    } else {
      await db.delete(
        'session_cancellations',
        where: 'group_id = ? AND date = ? AND (student_id IS NULL OR student_id = "")',
        whereArgs: [groupId, date],
      );
    }

    await db.insert('session_cancellations', {
      'group_id': groupId,
      'date': date,
      'cancelled_by': cancelledBy,
      'student_id': studentId,
      'reason': reason ?? '',
      'notes': notes ?? '',
      'notice_sent': noticeSent ? 1 : 0,
      'notice_sent_at': noticeSent ? DateTime.now().toIso8601String() : null,
      'created_at': DateTime.now().toIso8601String(),
    });
    notifyChange(DataChangeEvent.attendance);
  }

  Future<void> markSessionCancellationNoticeSent({
    required String groupId,
    required String date,
    String? studentId,
  }) async {
    final db = await database;
    if (studentId != null) {
      await db.update(
        'session_cancellations',
        {
          'notice_sent': 1,
          'notice_sent_at': DateTime.now().toIso8601String(),
        },
        where: 'group_id = ? AND date = ? AND student_id = ?',
        whereArgs: [groupId, date, studentId],
      );
    } else {
      await db.update(
        'session_cancellations',
        {
          'notice_sent': 1,
          'notice_sent_at': DateTime.now().toIso8601String(),
        },
        where: 'group_id = ? AND date = ? AND (student_id IS NULL OR student_id = "")',
        whereArgs: [groupId, date],
      );
    }
    notifyChange(DataChangeEvent.attendance);
  }

  Future<bool> isSessionCancellationNoticeSent({
    required String groupId,
    required String date,
    String? studentId,
  }) async {
    final db = await database;
    try {
      final rows = await db.query(
        'session_cancellations',
        columns: ['notice_sent'],
        where: studentId != null
            ? 'group_id = ? AND date = ? AND student_id = ? AND notice_sent = 1'
            : 'group_id = ? AND date = ? AND (student_id IS NULL OR student_id = "") AND notice_sent = 1',
        whereArgs: studentId != null ? [groupId, date, studentId] : [groupId, date],
        limit: 1,
      );
      if (rows.isNotEmpty) return true;
    } catch (_) {}

    try {
      if (studentId != null) {
        final logRows = await db.rawQuery('''
          SELECT id FROM whatsapp_logs
          WHERE student_id = ?
            AND category = 'cancellation'
            AND sent_at LIKE ?
            AND status IN ('sent_api', 'sent_manual', 'opened_whatsapp', 'sent')
          LIMIT 1
        ''', [studentId, '$date%']);
        if (logRows.isNotEmpty) return true;
      } else {
        final logRows = await db.rawQuery('''
          SELECT wl.id FROM whatsapp_logs wl
          JOIN students s ON s.id = wl.student_id
          WHERE s.group_id = ?
            AND wl.category = 'cancellation'
            AND wl.sent_at LIKE ?
            AND wl.status IN ('sent_api', 'sent_manual', 'opened_whatsapp', 'sent')
          LIMIT 1
        ''', [groupId, '$date%']);
        if (logRows.isNotEmpty) return true;
      }
    } catch (_) {}

    return false;
  }

  Future<Map<String, bool>> getGroupCancellationNoticeSentStatus(String date) async {
    final db = await database;
    final map = <String, bool>{};

    try {
      final scRows = await db.query(
        'session_cancellations',
        columns: ['group_id'],
        where: 'date = ? AND (student_id IS NULL OR student_id = "") AND notice_sent = 1',
        whereArgs: [date],
      );
      for (final r in scRows) {
        final gId = r['group_id'] as String?;
        if (gId != null) map[gId] = true;
      }
    } catch (_) {}

    try {
      final wlRows = await db.rawQuery('''
        SELECT DISTINCT s.group_id
        FROM whatsapp_logs wl
        JOIN students s ON s.id = wl.student_id
        WHERE wl.category = 'cancellation'
          AND wl.sent_at LIKE ?
          AND wl.status IN ('sent_api', 'sent_manual', 'opened_whatsapp', 'sent')
      ''', ['$date%']);
      for (final r in wlRows) {
        final gId = r['group_id'] as String?;
        if (gId != null) map[gId] = true;
      }
    } catch (_) {}

    return map;
  }

  Future<void> deleteSessionCancellation({
    required String groupId,
    required String date,
    String? studentId,
    String? cancelledBy,
  }) async {
    final db = await database;
    if (studentId != null) {
      await db.delete(
        'session_cancellations',
        where: 'group_id = ? AND date = ? AND student_id = ?',
        whereArgs: [groupId, date, studentId],
      );
    } else {
      if (cancelledBy != null) {
        await db.delete(
          'session_cancellations',
          where: 'group_id = ? AND date = ? AND cancelled_by = ? AND (student_id IS NULL OR student_id = "")',
          whereArgs: [groupId, date, cancelledBy],
        );
      } else {
        await db.delete(
          'session_cancellations',
          where: 'group_id = ? AND date = ? AND (student_id IS NULL OR student_id = "")',
          whereArgs: [groupId, date],
        );
      }
    }
    notifyChange(DataChangeEvent.attendance);
  }

  Future<Map<String, dynamic>?> getGroupSessionCancellation({
    required String groupId,
    required String date,
  }) async {
    final db = await database;
    final rows = await db.query(
      'session_cancellations',
      where: 'group_id = ? AND date = ? AND (student_id IS NULL OR student_id = "")',
      whereArgs: [groupId, date],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, dynamic>?> getTeacherSessionCancellation({
    required String groupId,
    required String date,
  }) async {
    final db = await database;
    final rows = await db.query(
      'session_cancellations',
      where: 'group_id = ? AND date = ? AND cancelled_by = ? AND (student_id IS NULL OR student_id = "")',
      whereArgs: [groupId, date, 'teacher'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> getStudentSessionCancellations({
    required String groupId,
    required String date,
  }) async {
    final db = await database;
    return await db.query(
      'session_cancellations',
      where: 'group_id = ? AND date = ? AND cancelled_by = ?',
      whereArgs: [groupId, date, 'student'],
    );
  }

  Future<List<Map<String, dynamic>>> getAllCancellationsForDate(
    String date,
  ) async {
    final db = await database;
    return await db.query(
      'session_cancellations',
      where: 'date = ?',
      whereArgs: [date],
    );
  }

  Future<bool> isTeacherSessionCancelled({
    required String groupId,
    required String date,
  }) async {
    final res = await getTeacherSessionCancellation(
      groupId: groupId,
      date: date,
    );
    return res != null;
  }

  // --- Curriculum & Lesson Logs ---
  Future<void> saveCurriculumLesson(CurriculumLessonModel lesson) async {
    final db = await database;
    await db.insert(
      'curriculum_lessons',
      lesson.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.curriculum);
  }

  Future<void> saveCurriculumLessonsBatch(
    List<CurriculumLessonModel> lessons, {
    bool replaceAll = false,
    String? grade,
    String? curriculumName,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      if (curriculumName != null && curriculumName.isNotEmpty) {
        await txn.delete(
          'curriculum_lessons',
          where: 'curriculum_name = ? OR ((curriculum_name IS NULL OR curriculum_name = "") AND grade = ?)',
          whereArgs: [curriculumName, curriculumName],
        );
      } else if (replaceAll) {
        if (grade != null && grade.isNotEmpty) {
          await txn.delete(
            'curriculum_lessons',
            where: 'grade = ?',
            whereArgs: [grade],
          );
        } else {
          await txn.delete('curriculum_lessons');
        }
      }
      final batch = txn.batch();
      for (final l in lessons) {
        batch.insert(
          'curriculum_lessons',
          l.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    notifyChange(DataChangeEvent.curriculum);
  }

  Future<void> deleteCurriculumUnit({
    required String unitName,
    required String grade,
  }) async {
    final db = await database;
    await db.delete(
      'curriculum_lessons',
      where: 'unit_name = ? AND grade = ?',
      whereArgs: [unitName, grade],
    );
    notifyChange(DataChangeEvent.curriculum);
  }

  Future<List<CurriculumLessonModel>> getCurriculumLessons({
    String? grade,
    String? stage,
    String? curriculumName,
  }) async {
    final db = await database;

    String? where;
    List<dynamic>? args;
    if (curriculumName != null && curriculumName.isNotEmpty) {
      where = 'curriculum_name = ? OR grade = ?';
      args = [curriculumName, curriculumName];
    } else if (grade != null && grade.isNotEmpty) {
      where = 'grade = ? OR curriculum_name = ?';
      args = [grade, grade];
    } else if (stage != null && stage.isNotEmpty) {
      where = 'stage = ?';
      args = [stage];
    }
    try {
      final rows = await db.query(
        'curriculum_lessons',
        where: where,
        whereArgs: args,
        orderBy: 'chapter_number ASC, id ASC',
      );
      return rows.map(CurriculumLessonModel.fromMap).toList();
    } catch (_) {
      final rows = await db.query(
        'curriculum_lessons',
        where: where,
        whereArgs: args,
      );
      return rows.map(CurriculumLessonModel.fromMap).toList();
    }
  }

  Future<void> deleteCurriculumLesson(int id) async {
    final db = await database;
    await db.delete('curriculum_lessons', where: 'id = ?', whereArgs: [id]);
    notifyChange(DataChangeEvent.curriculum);
  }

  Future<void> deleteCurriculum(
    String nameOrGrade, {
    bool deleteBoundGroups = false,
  }) async {
    final db = await database;
    final trimmed = nameOrGrade.trim();
    final clean = trimmed.replaceFirst(RegExp(r'^منهج\s+'), '').trim();
    final withManhaj = 'منهج $clean';

    final parenMatch = RegExp(r'\((.*?)\)').firstMatch(nameOrGrade);
    final insideParen = parenMatch?.group(1)?.trim();

    final tokens = {
      trimmed,
      clean,
      withManhaj,
      if (insideParen != null && insideParen.isNotEmpty) insideParen,
    }.where((s) => s.isNotEmpty).toList();

    await db.transaction((txn) async {
      // 1. Delete all matching lessons safely without affecting other subjects or broad wildcards
      for (final t in tokens) {
        await txn.delete(
          'curriculum_lessons',
          where: 'curriculum_name = ? OR ((curriculum_name IS NULL OR curriculum_name = "") AND grade = ?)',
          whereArgs: [t, t],
        );
      }

      // 2. Find bound groups
      final boundRows = await txn.query('group_curriculum_bindings');
      final matchedBindings = boundRows.where((row) {
        final cName = (row['curriculum_name'] as String? ?? '').trim();
        return tokens.any((t) => cName == t);
      }).toList();

      if (deleteBoundGroups) {
        for (final b in matchedBindings) {
          final gid = b['id'] as String?;
          if (gid != null && gid.isNotEmpty) {
            await txn.delete(
              'attendance',
              where:
                  'student_id IN (SELECT id FROM students WHERE group_id = ?)',
              whereArgs: [gid],
            );
            await txn.delete(
              'payments',
              where:
                  'student_id IN (SELECT id FROM students WHERE group_id = ?)',
              whereArgs: [gid],
            );
            await txn.delete(
              'students',
              where: 'group_id = ?',
              whereArgs: [gid],
            );
            await txn.delete('groups', where: 'id = ?', whereArgs: [gid]);
          }
        }
      }

      // 3. Delete matching bindings
      for (final b in matchedBindings) {
        final gid = b['id'] as String?;
        if (gid != null && gid.isNotEmpty) {
          await txn.delete(
            'group_curriculum_bindings',
            where: 'id = ?',
            whereArgs: [gid],
          );
        }
      }
      for (final t in tokens) {
        await txn.delete(
          'group_curriculum_bindings',
          where: 'curriculum_name = ?',
          whereArgs: [t],
        );
      }
    });
    notifyChange(DataChangeEvent.all);
  }

  Future<void> deleteCurriculaBatch(
    List<String> namesOrGrades, {
    bool deleteBoundGroups = false,
  }) async {
    for (final name in namesOrGrades) {
      await deleteCurriculum(name, deleteBoundGroups: deleteBoundGroups);
    }
  }

  Future<void> renameCurriculum({
    required String oldName,
    required String newName,
  }) async {
    final db = await database;
    final trimmedOld = oldName.trim();
    final trimmedNew = newName.trim();
    if (trimmedOld.isEmpty || trimmedNew.isEmpty || trimmedOld == trimmedNew)
      return;

    final cleanOld = trimmedOld.replaceFirst(RegExp(r'^منهج\s+'), '').trim();
    final withManhajOld = 'منهج $cleanOld';
    final parenMatch = RegExp(r'\((.*?)\)').firstMatch(trimmedOld);
    final insideParen = parenMatch?.group(1)?.trim();

    final oldTokens = {
      trimmedOld,
      cleanOld,
      withManhajOld,
      if (insideParen != null && insideParen.isNotEmpty) insideParen,
    }.where((s) => s.isNotEmpty).toList();

    await db.transaction((txn) async {
      for (final token in oldTokens) {
        await txn.update(
          'curriculum_lessons',
          {'curriculum_name': trimmedNew},
          where: 'curriculum_name = ?',
          whereArgs: [token],
        );
      }
      for (final token in oldTokens) {
        await txn.update(
          'curriculum_lessons',
          {'curriculum_name': trimmedNew},
          where:
              '(curriculum_name IS NULL OR curriculum_name = "") AND grade = ?',
          whereArgs: [token],
        );
      }
      for (final token in oldTokens) {
        await txn.update(
          'group_curriculum_bindings',
          {'curriculum_name': trimmedNew},
          where: 'curriculum_name = ?',
          whereArgs: [token],
        );
      }
    });
    notifyChange(DataChangeEvent.all);
  }

  Future<void> updateCurriculumInfo({
    required String currentName,
    required String newName,
    String? subject,
    String? grade,
    String? stage,
    String? track,
  }) async {
    final db = await database;
    final trimmedOld = currentName.trim();
    final trimmedNew = newName.trim();

    final cleanOld = trimmedOld.replaceFirst(RegExp(r'^منهج\s+'), '').trim();
    final withManhajOld = 'منهج $cleanOld';
    final parenMatch = RegExp(r'\((.*?)\)').firstMatch(trimmedOld);
    final insideParen = parenMatch?.group(1)?.trim();

    final oldTokens = {
      trimmedOld,
      cleanOld,
      withManhajOld,
      if (insideParen != null && insideParen.isNotEmpty) insideParen,
    }.where((s) => s.isNotEmpty).toList();

    await db.transaction((txn) async {
      final lessonUpdates = <String, dynamic>{
        'curriculum_name': trimmedNew.isNotEmpty ? trimmedNew : trimmedOld,
      };
      if (subject != null && subject.trim().isNotEmpty)
        lessonUpdates['subject'] = subject.trim();
      if (grade != null && grade.trim().isNotEmpty)
        lessonUpdates['grade'] = grade.trim();
      if (stage != null && stage.trim().isNotEmpty)
        lessonUpdates['stage'] = stage.trim();

      for (final token in oldTokens) {
        await txn.update(
          'curriculum_lessons',
          lessonUpdates,
          where: 'curriculum_name = ? OR grade = ?',
          whereArgs: [token, token],
        );
      }

      final bindingUpdates = <String, dynamic>{
        'curriculum_name': trimmedNew.isNotEmpty ? trimmedNew : trimmedOld,
      };
      if (grade != null && grade.trim().isNotEmpty)
        bindingUpdates['grade_badge'] = grade.trim();
      if (track != null && track.trim().isNotEmpty)
        bindingUpdates['track'] = track.trim();

      for (final token in oldTokens) {
        await txn.update(
          'group_curriculum_bindings',
          bindingUpdates,
          where: 'curriculum_name = ?',
          whereArgs: [token],
        );
      }
    });
    notifyChange(DataChangeEvent.all);
  }

  Future<void> unbindGroupFromCurriculum(
    String groupId, {
    String? groupName,
  }) async {
    final db = await database;
    if (groupName != null && groupName.isNotEmpty) {
      await db.delete(
        'group_curriculum_bindings',
        where: 'id = ? OR group_name = ?',
        whereArgs: [groupId, groupName],
      );
    } else {
      await db.delete(
        'group_curriculum_bindings',
        where: 'id = ?',
        whereArgs: [groupId],
      );
    }
    notifyChange(DataChangeEvent.all);
  }

  Future<void> toggleLessonCompleted(int id, bool isCompleted) async {
    final db = await database;
    await db.update(
      'curriculum_lessons',
      {'is_completed': isCompleted ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyChange(DataChangeEvent.curriculum);
  }

  Future<List<Map<String, dynamic>>> getDetailedCurriculaList() async {
    final db = await database;
    try {
      final rows = await db.rawQuery('''
        SELECT 
          COALESCE(NULLIF(TRIM(curriculum_name), ''), TRIM(grade), 'منهج عام') as name,
          COALESCE(NULLIF(TRIM(grade), ''), 'عام') as grade,
          COALESCE(NULLIF(TRIM(stage), ''), 'عام') as stage,
          COALESCE(NULLIF(TRIM(subject), ''), 'عام') as subject,
          COUNT(*) as total_lessons,
          COUNT(DISTINCT unit_name) as total_units
        FROM curriculum_lessons
        WHERE (curriculum_name IS NOT NULL AND TRIM(curriculum_name) != '')
           OR (grade IS NOT NULL AND TRIM(grade) != '')
        GROUP BY COALESCE(NULLIF(TRIM(curriculum_name), ''), TRIM(grade))
        ORDER BY name ASC
      ''');

      final result = rows.map((r) => Map<String, dynamic>.from(r)).toList();

      // Also ensure any curricula in group_curriculum_bindings that might have been saved are included
      final bRows = await db.rawQuery('''
        SELECT DISTINCT curriculum_name, grade_badge, track
        FROM group_curriculum_bindings
        WHERE curriculum_name IS NOT NULL AND TRIM(curriculum_name) != ''
      ''');
      for (final b in bRows) {
        final bName = (b['curriculum_name'] as String? ?? '').trim();
        if (bName.isNotEmpty && !result.any((r) => r['name'] == bName)) {
          result.add({
            'name': bName,
            'grade': (b['grade_badge'] as String? ?? 'عام').trim(),
            'stage': 'عام',
            'subject': 'عام',
            'total_lessons': 0,
            'total_units': 0,
          });
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> getAllUniqueCurriculaNames() async {
    final details = await getDetailedCurriculaList();
    return details.map((d) => d['name'] as String).toList();
  }

  Future<void> bindGroupToCurriculum({
    required String groupId,
    required String groupName,
    required String grade,
    required String curriculumName,
    String track = 'لغات',
  }) async {
    final db = await database;
    await db.insert('group_curriculum_bindings', {
      'id': groupId,
      'group_name': groupName,
      'grade_badge': grade,
      'curriculum_name': curriculumName.trim(),
      'track': track,
      'is_locked': 1,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyChange(DataChangeEvent.all);
  }

  Future<void> unbindGroupCurriculum(String groupId) async {
    final db = await database;
    await db.delete(
      'group_curriculum_bindings',
      where: 'id = ?',
      whereArgs: [groupId],
    );
    notifyChange(DataChangeEvent.all);
  }

  // --- Group Curriculum Bindings (المركز الحصري لربط المناهج بالبيانات الحقيقية) ---
  Future<List<Map<String, dynamic>>> getGroupCurriculumBindings() async {
    final db = await database;
    try {
      // Return bindings only for real existing groups in database
      final rows = await db.rawQuery('''
        SELECT b.* FROM group_curriculum_bindings b
        INNER JOIN groups g ON b.id = g.id
      ''');
      return rows;
    } catch (_) {
      return [];
    }
  }

  Future<void> cleanMockGroupBindings() async {
    final db = await database;
    try {
      await db.rawDelete(
        'DELETE FROM group_curriculum_bindings WHERE id NOT IN (SELECT id FROM groups)',
      );
    } catch (_) {}
  }

  Future<void> saveGroupCurriculumBinding(Map<String, dynamic> binding) async {
    final db = await database;
    await db.insert(
      'group_curriculum_bindings',
      binding,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.curriculum);
    notifyChange(DataChangeEvent.groups);
  }

  Future<void> saveAllGroupCurriculumBindings(
    List<Map<String, dynamic>> bindings,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final b in bindings) {
        await txn.insert(
          'group_curriculum_bindings',
          b,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    notifyChange(DataChangeEvent.curriculum);
    notifyChange(DataChangeEvent.groups);
  }

  // --- Group Lesson Progress (متابعة دروس المنهج لكل مجموعة) ---
  Future<void> setGroupLessonProgress({
    required String groupId,
    required int lessonId,
    required String status, // 'current', 'previous', 'no_date', 'uncompleted'
    String? taughtDate,
    String? sessionType,
    String? notes,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    if (status == 'uncompleted') {
      await db.delete(
        'group_lesson_progress',
        where: 'group_id = ? AND lesson_id = ?',
        whereArgs: [groupId, lessonId],
      );
    } else {
      await db.insert('group_lesson_progress', {
        'group_id': groupId,
        'lesson_id': lessonId,
        'status': status,
        'taught_date':
            taughtDate ??
            (status == 'current' || status == 'previous'
                ? now.substring(0, 10)
                : null),
        'session_type': sessionType,
        'notes': notes,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    notifyChange(DataChangeEvent.curriculum);
    notifyChange(DataChangeEvent.groups);
    notifyChange(DataChangeEvent.attendance);
  }

  Future<Map<int, Map<String, dynamic>>> getGroupLessonProgressMap(
    String groupId,
  ) async {
    final db = await database;
    try {
      final rows = await db.query(
        'group_lesson_progress',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
      final map = <int, Map<String, dynamic>>{};
      for (final r in rows) {
        final lessonId = r['lesson_id'] as int;
        map[lessonId] = Map<String, dynamic>.from(r);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> bulkSetGroupLessonProgress({
    required String groupId,
    required List<int> lessonIds,
    required String status,
    String? taughtDate,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final lid in lessonIds) {
      if (status == 'uncompleted') {
        batch.delete(
          'group_lesson_progress',
          where: 'group_id = ? AND lesson_id = ?',
          whereArgs: [groupId, lid],
        );
      } else {
        batch.insert('group_lesson_progress', {
          'group_id': groupId,
          'lesson_id': lid,
          'status': status,
          'taught_date':
              taughtDate ??
              (status == 'current' || status == 'previous'
                  ? now.substring(0, 10)
                  : null),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
    notifyChange(DataChangeEvent.curriculum);
    notifyChange(DataChangeEvent.groups);
    notifyChange(DataChangeEvent.attendance);
  }

  // --- Group Curriculum Growth & Progress ---
  Future<List<GroupCurriculumProgress>> getGroupsCurriculumProgress() async {
    final db = await database;
    try {
      final groups = await getGroups();
      if (groups.isEmpty) return [];

      final allStudents = await getStudents();
      final studentCountMap = <String, int>{};
      for (final s in allStudents) {
        if (s.groupId != null) {
          studentCountMap[s.groupId!] = (studentCountMap[s.groupId!] ?? 0) + 1;
        }
      }

      final rawBindings = await getGroupCurriculumBindings();
      final bindingMap = <String, Map<String, dynamic>>{};
      for (final b in rawBindings) {
        final gId = b['id'] as String? ?? '';
        if (gId.isNotEmpty) {
          bindingMap[gId] = b;
        }
      }

      final allLessons = await getCurriculumLessons();

      final progressRows = await db.query('group_lesson_progress');
      final groupProgressMap = <String, Map<int, Map<String, dynamic>>>{};
      for (final r in progressRows) {
        final gId = r['group_id'] as String? ?? '';
        final lId = r['lesson_id'] as int? ?? 0;
        if (gId.isNotEmpty && lId > 0) {
          groupProgressMap.putIfAbsent(gId, () => {})[lId] =
              Map<String, dynamic>.from(r);
        }
      }

      final List<GroupCurriculumProgress> result = [];

      for (final group in groups) {
        final binding = bindingMap[group.id];
        final boundCurriculum =
            (binding?['curriculum_name'] as String?)?.trim();
        final track = binding?['track'] as String? ?? 'لغات';

        List<CurriculumLessonModel> matchingLessons = [];
        String? effectiveCurriculumName = boundCurriculum;

        if (boundCurriculum != null && boundCurriculum.isNotEmpty) {
          matchingLessons = allLessons.where((l) {
            final cName = (l.curriculumName ?? '').trim();
            final grade = l.grade.trim();
            return cName == boundCurriculum || grade == boundCurriculum;
          }).toList();
        }

        if (matchingLessons.isEmpty && group.grade.isNotEmpty) {
          final gGrade = group.grade.trim();
          matchingLessons = allLessons.where((l) {
            final cName = (l.curriculumName ?? '').trim();
            final grade = l.grade.trim();
            return grade == gGrade ||
                cName == gGrade ||
                cName.contains(gGrade);
          }).toList();
          if (matchingLessons.isNotEmpty &&
              (effectiveCurriculumName == null ||
                  effectiveCurriculumName.isEmpty)) {
            effectiveCurriculumName =
                matchingLessons.first.curriculumName ?? group.grade;
          }
        }

        final progressMap = groupProgressMap[group.id] ?? {};
        final totalLessons = matchingLessons.length;
        int completedLessons = 0;
        String? currentLessonTitle;
        String? nextLessonTitle;
        String? lastTaughtDate;
        final Set<String> units = {};

        for (final lesson in matchingLessons) {
          if (lesson.unitName.isNotEmpty) {
            units.add(lesson.unitName);
          }
          final p = lesson.id != null ? progressMap[lesson.id!] : null;
          final status = p?['status'] as String?;
          final isTaught = (status == 'current' ||
                  status == 'previous' ||
                  status == 'no_date') ||
              (status == null && lesson.isCompleted);

          if (isTaught) {
            completedLessons++;
            if (status == 'current') {
              currentLessonTitle = lesson.lessonTitle;
            }
            final tDate = p?['taught_date'] as String?;
            if (tDate != null &&
                (lastTaughtDate == null ||
                    tDate.compareTo(lastTaughtDate) > 0)) {
              lastTaughtDate = tDate;
            }
          } else {
            nextLessonTitle ??= lesson.lessonTitle;
          }
        }

        if (currentLessonTitle == null && completedLessons > 0) {
          final taught = matchingLessons.where((l) {
            final p = l.id != null ? progressMap[l.id!] : null;
            final s = p?['status'] as String?;
            return s == 'current' ||
                s == 'previous' ||
                s == 'no_date' ||
                (s == null && l.isCompleted);
          }).toList();
          if (taught.isNotEmpty) {
            currentLessonTitle = taught.last.lessonTitle;
          }
        }

        final double percent = totalLessons > 0
            ? (completedLessons / totalLessons).clamp(0.0, 1.0)
            : 0.0;

        result.add(GroupCurriculumProgress(
          groupId: group.id,
          groupName: group.name,
          stage: group.stage,
          grade: group.grade,
          curriculumName: effectiveCurriculumName,
          track: track,
          totalLessons: totalLessons,
          completedLessons: completedLessons,
          progressPercent: percent,
          currentLessonTitle: currentLessonTitle,
          nextLessonTitle: nextLessonTitle,
          lastTaughtDate: lastTaughtDate,
          unitsCount: units.length,
          studentCount: studentCountMap[group.id] ?? 0,
          schedule: group.schedule,
          colorValue: group.colorValue,
        ));
      }

      return result;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, GroupCurriculumProgress>>
      getGroupsCurriculumProgressMap() async {
    final list = await getGroupsCurriculumProgress();
    return {for (final p in list) p.groupId: p};
  }


  Future<void> saveSessionLog(SessionLogModel log) async {
    final db = await database;
    await db.insert(
      'session_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.attendance);
  }

  Future<List<SessionLogModel>> getSessionLogs({
    String? groupId,
    String? date,
  }) async {
    final db = await database;
    String? where;
    List<dynamic>? args;
    if (groupId != null && date != null) {
      where = 'group_id = ? AND date = ?';
      args = [groupId, date];
    } else if (groupId != null) {
      where = 'group_id = ?';
      args = [groupId];
    } else if (date != null) {
      where = 'date = ?';
      args = [date];
    }
    final rows = await db.query(
      'session_logs',
      where: where,
      whereArgs: args,
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(SessionLogModel.fromMap).toList();
  }

  Future<SessionLogModel?> getLatestSessionLogForGroup(String groupId) async {
    final db = await database;
    final rows = await db.query(
      'session_logs',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'date DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SessionLogModel.fromMap(rows.first);
  }

  // --- Payments ---
  Future<Map<String, dynamic>> processAttendanceSessionBilling({
    required GroupModel group,
    required String studentId,
    required String studentName,
    required String date,
    required String? status,
    String sessionScale = 'regular',
  }) async {
    try {
      final db = await database;
      final claimId = 'session_fee_${group.id}_${studentId}_$date';
      final result = await db.transaction<Map<String, dynamic>>((txn) async {
        final studentRows = await txn.query(
          'students',
          where: 'id = ?',
          whereArgs: [studentId],
          limit: 1,
        );
        if (studentRows.isEmpty) return {'applied': false};

        final student = StudentModel.fromMap(studentRows.first);
        final existing = await txn.query(
          'payments',
          where: 'claim_id = ? OR note LIKE ?',
          whereArgs: [claimId, '%$claimId%'],
          limit: 1,
        );

        final isPresent = status == 'present' || status == 'late';

        if (isPresent && existing.isEmpty) {
          final basePrice = group.monthlyPrice;
          if (basePrice <= 0) return {'applied': false};

          final scaleMultiplier = sessionScale == 'double' ? 2.0 : 1.0;
          final sessionPrice = basePrice * scaleMultiplier;

          final newOutstanding = student.outstandingAmount + sessionPrice;
          await txn.update(
            'students',
            {'outstanding_amount': newOutstanding},
            where: 'id = ?',
            whereArgs: [studentId],
          );
          await txn.insert('payments', {
            'student_id': studentId,
            'amount': sessionPrice,
            'date': date,
            'type': 'مطالبة استحقاق حصة',
            'note': 'حصة مجموعة: ${group.name} • مطالبة فردية [$claimId]',
            'claim_id': claimId,
          });

          // Immutable Financial Claims Ledger Record (Never deleted)
          await txn.insert('financial_claims', {
            'claim_id': claimId,
            'student_id': studentId,
            'student_name': studentName.isNotEmpty ? studentName : student.fullName,
            'group_id': group.id,
            'group_name': group.name,
            'session_date': date,
            'amount': sessionPrice,
            'billing_type': group.billingType,
            'session_scale': sessionScale,
            'status': 'active',
            'note': 'حصة مجموعة: ${group.name} • استحقاق حضور معتمد',
            'created_at': DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          return {
            'applied': true,
            'amount': sessionPrice,
            'newOutstanding': newOutstanding,
          };
        }

        final shouldReverse = !isPresent;
        if (shouldReverse && existing.isNotEmpty) {
          final charged = (existing.first['amount'] as num?)?.toDouble() ?? 0.0;
          final newOutstanding = (student.outstandingAmount - charged)
              .clamp(0.0, double.infinity)
              .toDouble();
          await txn.update(
            'students',
            {'outstanding_amount': newOutstanding},
            where: 'id = ?',
            whereArgs: [studentId],
          );
          await txn.delete(
            'payments',
            where: 'claim_id = ? OR note LIKE ?',
            whereArgs: [claimId, '%$claimId%'],
          );

          // Update status in financial_claims without deleting history!
          await txn.update(
            'financial_claims',
            {'status': 'waived', 'note': 'ملغاة أو مستبعدة: ${status ?? "لم يحدد"}'},
            where: 'claim_id = ?',
            whereArgs: [claimId],
          );

          return {
            'applied': true,
            'reverted': true,
            'amount': charged,
            'newOutstanding': newOutstanding,
          };
        }
        return {'applied': false};
      });

      if (result['applied'] == true) {
        notifyChange(DataChangeEvent.finances);
        notifyChange(DataChangeEvent.students);
      }
      return result;
    } catch (e, stack) {
      debugPrint('Error in processAttendanceSessionBilling: $e\n$stack');
    }
    return {'applied': false};
  }

  Future<int> reconcileAttendanceBillingForDate(String date) async {
    try {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT a.student_id, a.status, a.session_type, s.full_name, s.group_id
        FROM attendance a
        INNER JOIN students s ON a.student_id = s.id
        WHERE a.attendance_date = ? AND a.status IN ('present', 'late')
      ''', [date]);

      if (rows.isEmpty) return 0;

      final groupsMap = <String, GroupModel>{};
      int appliedCount = 0;

      for (final r in rows) {
        final sId = r['student_id'] as String;
        final sName = r['full_name'] as String? ?? '';
        final gId = r['group_id'] as String?;
        final status = r['status'] as String;
        final sType = r['session_type'] as String? ?? 'regular';

        if (gId == null || gId.isEmpty) continue;

        GroupModel? grp = groupsMap[gId];
        if (grp == null) {
          grp = await getGroupById(gId);
          if (grp != null) groupsMap[gId] = grp;
        }

        if (grp != null && grp.monthlyPrice > 0) {
          final res = await processAttendanceSessionBilling(
            group: grp,
            studentId: sId,
            studentName: sName,
            date: date,
            status: status,
            sessionScale: sType,
          );
          if (res['applied'] == true) {
            appliedCount++;
          }
        }
      }

      if (appliedCount > 0) {
        notifyChange(DataChangeEvent.finances);
        notifyChange(DataChangeEvent.students);
      }
      return appliedCount;
    } catch (e) {
      debugPrint('Error in reconcileAttendanceBillingForDate: $e');
      return 0;
    }
  }

  /// Comprehensive Historical Claims Reconciler
  /// Reconciles ALL past and present attendance sessions across all dates.
  /// Creates immutable records in `financial_claims` that can never be lost or deleted.
  Future<int> reconcileAllAttendanceBilling() async {
    try {
      final db = await database;
      // 1. Fetch all distinct dates from attendance where students attended
      final dateRows = await db.rawQuery('''
        SELECT DISTINCT attendance_date
        FROM attendance
        WHERE status IN ('present', 'late')
        ORDER BY attendance_date ASC
      ''');

      int totalReconciled = 0;
      for (final row in dateRows) {
        final d = row['attendance_date'] as String?;
        if (d != null && d.isNotEmpty) {
          final count = await reconcileAttendanceBillingForDate(d);
          totalReconciled += count;
        }
      }

      // 2. Ensure every claim payment has a corresponding permanent record in financial_claims
      final claimPayments = await db.query(
        'payments',
        where: "type = 'مطالبة استحقاق حصة' AND claim_id IS NOT NULL",
      );

      for (final p in claimPayments) {
        final cId = p['claim_id'] as String;
        final sId = p['student_id'] as String;
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        final pDate = p['date'] as String;
        final note = p['note'] as String? ?? '';

        final existing = await db.query(
          'financial_claims',
          where: 'claim_id = ?',
          whereArgs: [cId],
          limit: 1,
        );

        if (existing.isEmpty) {
          final sRow = await db.query('students', where: 'id = ?', whereArgs: [sId], limit: 1);
          final sName = sRow.isNotEmpty ? (sRow.first['full_name'] as String? ?? '') : '';
          final gId = sRow.isNotEmpty ? (sRow.first['group_id'] as String? ?? '') : '';

          String gName = '';
          if (gId.isNotEmpty) {
            final gRow = await db.query('groups', where: 'id = ?', whereArgs: [gId], limit: 1);
            if (gRow.isNotEmpty) gName = gRow.first['name'] as String? ?? '';
          }

          await db.insert('financial_claims', {
            'claim_id': cId,
            'student_id': sId,
            'student_name': sName,
            'group_id': gId,
            'group_name': gName,
            'session_date': pDate,
            'amount': amt,
            'billing_type': 'per_session',
            'session_scale': note.contains('2x') || note.contains('دوبل') ? 'double' : 'regular',
            'status': 'active',
            'note': note,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      // 3. Mathematical recalculation of students' outstanding debts and FIFO claim settlements
      // Outstanding = Total Active Claims - Total Payments (Receipts)
      final allStudents = await db.query('students');
      for (final st in allStudents) {
        final stId = st['id'] as String;
        await settleStudentClaims(stId, db);
      }

      if (totalReconciled > 0) {
        notifyChange(DataChangeEvent.finances);
        notifyChange(DataChangeEvent.students);
      }
      return totalReconciled;
    } catch (e, stack) {
      debugPrint('Error in reconcileAllAttendanceBilling: $e\n$stack');
      return 0;
    }
  }

  /// Retrieve all immutable financial claims with optional filtering
  Future<List<Map<String, dynamic>>> getAllFinancialClaims({
    String? groupId,
    String? studentId,
  }) async {
    final db = await database;
    String where = '';
    final whereArgs = <dynamic>[];
    if (groupId != null && groupId.isNotEmpty) {
      where = 'group_id = ?';
      whereArgs.add(groupId);
    }
    if (studentId != null && studentId.isNotEmpty) {
      if (where.isNotEmpty) where += ' AND ';
      where += 'student_id = ?';
      whereArgs.add(studentId);
    }

    return await db.query(
      'financial_claims',
      where: where.isNotEmpty ? where : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'session_date DESC, id DESC',
    );
  }

  /// Toggle student active/inactive status
  Future<void> setStudentActiveStatus(String studentId, bool isActive) async {
    final db = await database;
    await db.update(
      'students',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [studentId],
    );
    notifyChange(DataChangeEvent.students);
  }

  /// Toggle group active/inactive status
  Future<void> setGroupActiveStatus(String groupId, bool isActive) async {
    final db = await database;
    await db.update(
      'groups',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [groupId],
    );
    notifyChange(DataChangeEvent.groups);
  }

  /// Mathematically settles student claims against collections in FIFO order
  /// Synchronizes all attended sessions to financial claims under strict programmatic rules
  Future<void> settleStudentClaims(String studentId, [DatabaseExecutor? dbExecutor]) async {
    final db = dbExecutor ?? await database;
    try {
      // 1. Strict Programmatic Rule: Synchronize all attended sessions in `attendance` into `financial_claims`
      final attRows = await db.query(
        'attendance',
        where: 'student_id = ?',
        whereArgs: [studentId],
      );

      final studentRow = await db.query(
        'students',
        where: 'id = ?',
        whereArgs: [studentId],
        limit: 1,
      );

      if (studentRow.isNotEmpty) {
        final gId = studentRow.first['group_id'] as String?;
        final sName = studentRow.first['full_name'] as String? ?? '';
        GroupModel? grp;
        if (gId != null && gId.isNotEmpty) {
          final groupRow = await db.query('groups', where: 'id = ?', whereArgs: [gId], limit: 1);
          if (groupRow.isNotEmpty) {
            grp = GroupModel.fromMap(groupRow.first);
          }
        }

        if (grp != null && grp.monthlyPrice > 0) {
          for (final att in attRows) {
            final attDate = att['attendance_date'] as String;
            final status = att['status'] as String? ?? '';
            final isAttended = status == 'present' || status == 'late';
            final claimId = 'session_fee_${grp.id}_${studentId}_$attDate';
            final sType = att['session_type'] as String? ?? 'regular';
            final scale = sType == 'double' ? 2.0 : 1.0;
            final sessionPrice = grp.monthlyPrice * scale;

            final existingClaims = await db.query(
              'financial_claims',
              where: 'claim_id = ?',
              whereArgs: [claimId],
              limit: 1,
            );

            if (isAttended) {
              if (existingClaims.isEmpty) {
                await db.insert('financial_claims', {
                  'claim_id': claimId,
                  'student_id': studentId,
                  'student_name': sName,
                  'group_id': grp.id,
                  'group_name': grp.name,
                  'session_date': attDate,
                  'amount': sessionPrice,
                  'billing_type': grp.billingType,
                  'session_scale': sType,
                  'status': 'active',
                  'note': 'حصة مجموعة: ${grp.name} • استحقاق حضور معتمد',
                  'created_at': DateTime.now().toIso8601String(),
                });
                final existingPay = await db.query('payments', where: 'claim_id = ?', whereArgs: [claimId], limit: 1);
                if (existingPay.isEmpty) {
                  await db.insert('payments', {
                    'student_id': studentId,
                    'amount': sessionPrice,
                    'date': attDate,
                    'type': 'مطالبة استحقاق حصة',
                    'note': 'حصة مجموعة: ${grp.name} • مطالبة فردية [$claimId]',
                    'claim_id': claimId,
                  });
                }
              } else if (existingClaims.first['status'] != 'active') {
                await db.update(
                  'financial_claims',
                  {'status': 'active', 'amount': sessionPrice},
                  where: 'claim_id = ?',
                  whereArgs: [claimId],
                );
              }
            } else {
              if (existingClaims.isNotEmpty && existingClaims.first['status'] == 'active') {
                await db.update(
                  'financial_claims',
                  {'status': 'waived', 'note': 'ملغاة بسبب الغياب'},
                  where: 'claim_id = ?',
                  whereArgs: [claimId],
                );
                await db.delete('payments', where: 'claim_id = ?', whereArgs: [claimId]);
              }
            }
          }
        }
      }

      // 2. Strict Programmatic Rule: Sum all active financial claims for this student
      final claimsRes = await db.rawQuery('''
        SELECT SUM(amount) AS total
        FROM financial_claims
        WHERE student_id = ? AND status = 'active'
      ''', [studentId]);
      final totalClaims = (claimsRes.first['total'] as num?)?.toDouble() ?? 0.0;

      // 3. Strict Programmatic Rule: Sum all real collection receipts
      final paidRes = await db.rawQuery('''
        SELECT SUM(amount) AS total
        FROM payments
        WHERE student_id = ? AND (claim_id IS NULL AND type != 'مطالبة استحقاق حصة')
      ''', [studentId]);
      final totalPaid = (paidRes.first['total'] as num?)?.toDouble() ?? 0.0;

      // 4. Strict Programmatic Rule: Accurate Debt = Total Claims - Total Paid (Floor at 0.0)
      final accurateDebt = (totalClaims - totalPaid).clamp(0.0, double.infinity);
      await db.update(
        'students',
        {'outstanding_amount': accurateDebt},
        where: 'id = ?',
        whereArgs: [studentId],
      );

      final studentClaims = await db.query(
        'financial_claims',
        where: "student_id = ? AND status = 'active'",
        whereArgs: [studentId],
        orderBy: 'session_date ASC, id ASC',
      );

      double remainingFunds = totalPaid;
      for (final cl in studentClaims) {
        final clId = cl['id'];
        final clAmt = (cl['amount'] as num?)?.toDouble() ?? 0.0;
        double clPaid = 0.0;

        if (remainingFunds >= clAmt) {
          clPaid = clAmt;
          remainingFunds -= clAmt;
        } else if (remainingFunds > 0) {
          clPaid = remainingFunds;
          remainingFunds = 0.0;
        } else {
          clPaid = 0.0;
        }

        final currentPaid = (cl['paid_amount'] as num?)?.toDouble() ?? 0.0;
        if ((clPaid - currentPaid).abs() > 0.01) {
          await db.update(
            'financial_claims',
            {'paid_amount': clPaid},
            where: 'id = ?',
            whereArgs: [clId],
          );
        }
      }
    } catch (e) {
      debugPrint('Error in settleStudentClaims: $e');
    }
  }

  /// Adds a manual session claim or retroactive lesson fee directly for a student
  Future<void> addManualSessionClaim({
    required String studentId,
    required double amount,
    String? date,
    String? note,
  }) async {
    final db = await database;
    final claimDate = date ?? DateTime.now().toIso8601String().substring(0, 10);
    final claimId = 'manual_claim_${studentId}_${DateTime.now().millisecondsSinceEpoch}';

    final sRows = await db.query('students', where: 'id = ?', whereArgs: [studentId], limit: 1);
    final sName = sRows.isNotEmpty ? (sRows.first['full_name'] as String? ?? '') : '';
    final gId = sRows.isNotEmpty ? (sRows.first['group_id'] as String? ?? '') : '';

    String gName = '';
    if (gId.isNotEmpty) {
      final gRows = await db.query('groups', where: 'id = ?', whereArgs: [gId], limit: 1);
      if (gRows.isNotEmpty) gName = gRows.first['name'] as String? ?? '';
    }

    await db.insert('financial_claims', {
      'claim_id': claimId,
      'student_id': studentId,
      'student_name': sName,
      'group_id': gId,
      'group_name': gName,
      'session_date': claimDate,
      'amount': amount,
      'billing_type': 'per_session',
      'session_scale': 'regular',
      'status': 'active',
      'note': note ?? 'إضافة حصة مستحقة يدوياً',
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('payments', {
      'student_id': studentId,
      'amount': amount,
      'date': claimDate,
      'type': 'مطالبة استحقاق حصة',
      'note': note ?? 'إضافة حصة مستحقة [$claimId]',
      'claim_id': claimId,
    });

    await settleStudentClaims(studentId, db);
    notifyChange(DataChangeEvent.finances);
    notifyChange(DataChangeEvent.students);
  }

  Future<void> recordPayment(PaymentModel payment) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('payments', payment.toMap());
    });
    // Immediately calculate and settle claims for this student in FIFO order
    await settleStudentClaims(payment.studentId);
    notifyChange(DataChangeEvent.finances);
    notifyChange(DataChangeEvent.students);
  }

  /// Applies a discrete charitable discount / dues concession ("تيسير وإعفاء لوجه الله")
  /// Directly reduces the currently active required balance/claims for one or multiple students.
  /// It does NOT show up in reports or external receipts to preserve student dignity.
  Future<int> applyStudentDuesConcession({
    required List<String> studentIds,
    required bool isPercentage,
    required double value,
    String? note,
  }) async {
    final db = await database;
    int affectedCount = 0;

    await db.transaction((txn) async {
      for (final sId in studentIds) {
        // 1. Fetch current student
        final studentRows = await txn.query(
          'students',
          where: 'id = ?',
          whereArgs: [sId],
          limit: 1,
        );
        if (studentRows.isEmpty) continue;
        final student = StudentModel.fromMap(studentRows.first);

        // 2. Query active claims
        final activeClaims = await txn.query(
          'financial_claims',
          where: "student_id = ? AND status = 'active'",
          whereArgs: [sId],
          orderBy: 'session_date ASC, id ASC',
        );

        // Calculate actual current required debt
        double totalUnpaidClaims = 0.0;
        for (final c in activeClaims) {
          final amt = (c['amount'] as num?)?.toDouble() ?? 0.0;
          final paid = (c['paid_amount'] as num?)?.toDouble() ?? 0.0;
          totalUnpaidClaims += (amt - paid).clamp(0.0, double.infinity);
        }

        final currentDebt = totalUnpaidClaims > 0 ? totalUnpaidClaims : student.outstandingAmount;
        if (currentDebt <= 0) continue;

        // Calculate discount amount for this student
        double discountAmt = 0.0;
        if (isPercentage) {
          if (value >= 100.0) {
            discountAmt = currentDebt;
          } else {
            discountAmt = currentDebt * (value / 100.0);
          }
        } else {
          discountAmt = value.clamp(0.0, currentDebt);
        }

        if (discountAmt <= 0) continue;

        // 3. Apply discount to active financial claims
        if (activeClaims.isNotEmpty) {
          double remainingToDeduct = discountAmt;
          for (final claim in activeClaims) {
            if (remainingToDeduct <= 0) break;

            final cId = claim['id'];
            final cAmt = (claim['amount'] as num?)?.toDouble() ?? 0.0;
            final cPaid = (claim['paid_amount'] as num?)?.toDouble() ?? 0.0;
            final cUnpaid = (cAmt - cPaid).clamp(0.0, double.infinity);

            if (cUnpaid <= 0) continue;

            if (remainingToDeduct >= cUnpaid) {
              if (cPaid > 0) {
                await txn.update(
                  'financial_claims',
                  {
                    'amount': cPaid,
                    'note': (claim['note'] != null && claim['note'].toString().isNotEmpty)
                        ? '${claim['note']} (تيسير مستحقات)'
                        : 'تيسير مستحقات',
                  },
                  where: 'id = ?',
                  whereArgs: [cId],
                );
              } else {
                await txn.update(
                  'financial_claims',
                  {
                    'status': 'waived',
                    'note': (claim['note'] != null && claim['note'].toString().isNotEmpty)
                        ? '${claim['note']} (إعفاء مستحقات)'
                        : 'إعفاء مستحقات',
                  },
                  where: 'id = ?',
                  whereArgs: [cId],
                );
              }
              remainingToDeduct -= cUnpaid;
            } else {
              final newAmt = cAmt - remainingToDeduct;
              await txn.update(
                'financial_claims',
                {
                  'amount': newAmt,
                  'note': (claim['note'] != null && claim['note'].toString().isNotEmpty)
                      ? '${claim['note']} (تيسير مستحقات)'
                      : 'تيسير مستحقات',
                },
                where: 'id = ?',
                whereArgs: [cId],
              );
              remainingToDeduct = 0.0;
            }
          }
          await settleStudentClaims(sId, txn);
        } else {
          final newOutstanding = (student.outstandingAmount - discountAmt).clamp(0.0, double.infinity);
          await txn.update(
            'students',
            {'outstanding_amount': newOutstanding},
            where: 'id = ?',
            whereArgs: [sId],
          );
        }
        affectedCount++;
      }
    });

    notifyChange(DataChangeEvent.finances);
    notifyChange(DataChangeEvent.students);
    return affectedCount;
  }

  Future<List<PaymentModel>> getStudentPayments(String studentId) async {
    final db = await database;
    final rows = await db.query(
      'payments',
      where: 'student_id = ? AND claim_id IS NULL AND type != ?',
      whereArgs: [studentId, 'مطالبة استحقاق حصة'],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(PaymentModel.fromMap).toList();
  }

  Future<List<PaymentModel>> getAllPayments() async {
    final db = await database;
    final rows = await db.query(
      'payments',
      where: 'claim_id IS NULL AND type != ?',
      whereArgs: ['مطالبة استحقاق حصة'],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(PaymentModel.fromMap).toList();
  }

  // --- Exams & Scores ---
  Future<List<ExamModel>> getExams({String? groupId}) async {
    final db = await database;
    final rows = groupId != null
        ? await db.query(
            'exams',
            where: 'group_id = ?',
            whereArgs: [groupId],
            orderBy: 'date DESC',
          )
        : await db.query('exams', orderBy: 'date DESC');
    return rows.map(ExamModel.fromMap).toList();
  }

  Future<void> saveExam(ExamModel exam) async {
    final db = await database;
    await db.insert(
      'exams',
      exam.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.exams);
  }

  Future<void> recordExamScore(ExamScoreModel score) async {
    final db = await database;
    await db.insert(
      'exam_scores',
      score.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.exams);
  }

  Future<List<Map<String, dynamic>>> getStudentExamScores(
    String studentId,
  ) async {
    final db = await database;
    return await db.rawQuery(
      '''
      SELECT e.title, e.date, e.max_score, s.score, s.note
      FROM exam_scores s
      JOIN exams e ON s.exam_id = e.id
      WHERE s.student_id = ?
      ORDER BY e.date DESC
    ''',
      [studentId],
    );
  }

  Future<void> deleteExam(String examId) async {
    final db = await database;
    await db.delete('exams', where: 'id = ?', whereArgs: [examId]);
    await db.delete('exam_scores', where: 'exam_id = ?', whereArgs: [examId]);
    notifyChange(DataChangeEvent.exams);
  }

  Future<Map<String, double>> getExamScoresForExam(String examId) async {
    final db = await database;
    final rows = await db.query(
      'exam_scores',
      where: 'exam_id = ?',
      whereArgs: [examId],
    );
    final map = <String, double>{};
    for (final r in rows) {
      map[r['student_id'] as String] = (r['score'] as num).toDouble();
    }
    return map;
  }

  Future<void> recordExamScoresBatch(
    String examId,
    Map<String, double> scores,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final entry in scores.entries) {
        await txn.insert('exam_scores', {
          'exam_id': examId,
          'student_id': entry.key,
          'score': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    notifyChange(DataChangeEvent.exams);
  }

  // --- Expenses & Financial Ledger ---
  Future<void> saveExpense(Map<String, dynamic> expense) async {
    final db = await database;
    await db.insert(
      'expenses',
      expense,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.finances);
  }

  Future<List<Map<String, dynamic>>> getExpenses() async {
    final db = await database;
    return await db.query('expenses', orderBy: 'date DESC');
  }

  Future<void> deleteExpense(String id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    notifyChange(DataChangeEvent.finances);
  }

  Future<Map<String, double>> getFinancialMetrics() async {
    final db = await database;
    final payRes = await db.rawQuery(
      'SELECT SUM(amount) as total FROM payments WHERE claim_id IS NULL AND type != ?',
      ['مطالبة استحقاق حصة'],
    );
    final expRes = await db.rawQuery(
      'SELECT SUM(amount) as total FROM expenses',
    );
    final debtRes = await db.rawQuery(
      'SELECT SUM(outstanding_amount) as total FROM students',
    );

    final totalIncome = (payRes.first['total'] as num?)?.toDouble() ?? 0.0;
    final totalExpenses = (expRes.first['total'] as num?)?.toDouble() ?? 0.0;
    final totalDebt = (debtRes.first['total'] as num?)?.toDouble() ?? 0.0;
    final netProfit = totalIncome - totalExpenses;

    return {
      'totalIncome': totalIncome,
      'totalExpenses': totalExpenses,
      'netProfit': netProfit,
      'totalDebt': totalDebt,
    };
  }

  // --- Settings Cache & Preloader ---
  final Map<String, String> _settingsCache = {};

  Future<void> preloadSettings() async {
    try {
      final db = await database;
      final rows = await db.query('settings');
      for (final r in rows) {
        final k = r['key'] as String?;
        final v = r['value'] as String?;
        if (k != null && v != null) {
          _settingsCache[k] = v;
        }
      }
      unawaited(reconcileAllAttendanceBilling());
    } catch (_) {}
  }

  // --- Dashboard & Metrics (Parallelized) ---
  Future<Map<String, dynamic>> getDashboardMetrics() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final results = await Future.wait([
      db.rawQuery('SELECT COUNT(*) FROM students'),
      db.rawQuery(
        'SELECT COUNT(*) FROM attendance WHERE attendance_date = ? AND status = ?',
        [today, 'present'],
      ),
      db.rawQuery(
        'SELECT SUM(amount) as total FROM payments WHERE date = ? AND claim_id IS NULL AND type != ?',
        [today, 'مطالبة استحقاق حصة'],
      ),
      db.rawQuery('SELECT SUM(outstanding_amount) as total FROM students'),
      db.rawQuery('SELECT COUNT(*) FROM groups'),
    ]);

    final totalStudents = Sqflite.firstIntValue(results[0]) ?? 0;
    final todayAttendance = Sqflite.firstIntValue(results[1]) ?? 0;
    final todayRevenue = (results[2].first['total'] as num?)?.toDouble() ?? 0.0;
    final totalDebt = (results[3].first['total'] as num?)?.toDouble() ?? 0.0;
    final totalGroups = Sqflite.firstIntValue(results[4]) ?? 0;

    return {
      'totalStudents': totalStudents,
      'todayAttendance': todayAttendance,
      'todayRevenue': todayRevenue,
      'totalDebt': totalDebt,
      'totalGroups': totalGroups,
    };
  }

  // --- Settings (In-Memory Cached) ---
  Future<String> getSetting(String key, {String defaultValue = ''}) async {
    if (_settingsCache.containsKey(key)) {
      return _settingsCache[key]!;
    }
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) {
      _settingsCache[key] = defaultValue;
      return defaultValue;
    }
    final val = rows.first['value'] as String;
    _settingsCache[key] = val;
    return val;
  }

  Future<void> setSetting(String key, String value) async {
    _settingsCache[key] = value;
    final db = await database;
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyChange(DataChangeEvent.settings);
  }

  // --- Seed Initial Demo Data ---
  Future<void> seedInitialData({bool force = false}) async {
    final db = await database;
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM students'),
        ) ??
        0;
    if (count > 0 && !force) return;

    if (force) {
      await db.delete('session_logs');
      await db.delete('curriculum_lessons');
      await db.delete('exam_scores');
      await db.delete('exams');
      await db.delete('payments');
      await db.delete('attendance');
      await db.delete('students');
      await db.delete('groups');
    }

    // Default settings
    await setSetting('center_name', 'أكاديمية المستقبل التعليمية');
    await setSetting('teacher_name', 'أ. أحمد السيد');
    await setSetting('subject_name', 'الرياضيات والفيزياء');
    await setSetting('contact_phone', '01012345678');
    await setSetting('center_address', 'القاهرة - مصر الجديدة');

    // Groups
    final groups = [
      const GroupModel(
        id: 'grp_sec3_a',
        name: '3 ث - علمي متميز',
        stage: 'الثانوية العامة',
        grade: 'الصف الثالث الثانوي',
        schedule: 'الاثنين والخميس 4:00 م',
        monthlyPrice: 250,
      ),
      const GroupModel(
        id: 'grp_sec2_b',
        name: '2 ث - مجموعة المتفوقين',
        stage: 'الثانوية العامة',
        grade: 'الصف الثاني الثانوي',
        schedule: 'السبت والأربعاء 5:30 م',
        monthlyPrice: 220,
      ),
      const GroupModel(
        id: 'grp_prep3',
        name: '3 ع - مراجعة نهائية',
        stage: 'المرحلة الإعدادية',
        grade: 'الصف الثالث الإعدادي',
        schedule: 'الأحد والثلاثاء 3:30 م',
        monthlyPrice: 180,
      ),
    ];
    for (final g in groups) {
      await saveGroup(g);
    }

    // Students
    final students = [
      const StudentModel(
        id: 'Std-100',
        fullName: 'أحمد محمود إبراهيم',
        stage: 'الثانوية العامة',
        grade: 'الصف الثالث الثانوي',
        studentPhone: '01012345671',
        parentPhone: '01112345671',
        groupId: 'grp_sec3_a',
        paymentPlan: 'شهري',
        outstandingAmount: 0,
      ),
      const StudentModel(
        id: 'Std-101',
        fullName: 'سارة خالد عبد الله',
        stage: 'الثانوية العامة',
        grade: 'الصف الثالث الثانوي',
        studentPhone: '01012345672',
        parentPhone: '01112345672',
        groupId: 'grp_sec3_a',
        paymentPlan: 'شهري',
        outstandingAmount: 250,
      ),
      const StudentModel(
        id: 'Std-102',
        fullName: 'محمد كريم الشريف',
        stage: 'الثانوية العامة',
        grade: 'الصف الثاني الثانوي',
        studentPhone: '01012345673',
        parentPhone: '01112345673',
        groupId: 'grp_sec2_b',
        paymentPlan: 'شهري',
        outstandingAmount: 0,
      ),
      const StudentModel(
        id: 'Std-103',
        fullName: 'مريم هاني فتحي',
        stage: 'المرحلة الإعدادية',
        grade: 'الصف الثالث الإعدادي',
        studentPhone: '01012345674',
        parentPhone: '01112345674',
        groupId: 'grp_prep3',
        paymentPlan: 'شهري',
        outstandingAmount: 180,
      ),
      const StudentModel(
        id: 'Std-104',
        fullName: 'يوسف مصطفى عثمان',
        stage: 'الثانوية العامة',
        grade: 'الصف الثالث الثانوي',
        studentPhone: '01012345675',
        parentPhone: '01112345675',
        groupId: 'grp_sec3_a',
        paymentPlan: 'شهري',
        outstandingAmount: 0,
      ),
    ];
    for (final s in students) {
      await saveStudent(s);
    }

    // Attendance
    final today = DateTime.now();
    final todayStr = today.toIso8601String().substring(0, 10);
    await recordAttendance(
      studentId: 'Std-100',
      status: 'present',
      source: 'qr',
      date: today,
    );
    await recordAttendance(
      studentId: 'Std-102',
      status: 'present',
      source: 'manual',
      date: today,
    );

    // Payments
    await recordPayment(
      PaymentModel(
        studentId: 'Std-100',
        amount: 250,
        date: todayStr,
        type: 'اشتراك شهر نوفمبر',
      ),
    );
    await recordPayment(
      PaymentModel(
        studentId: 'Std-102',
        amount: 220,
        date: todayStr,
        type: 'اشتراك شهر نوفمبر',
      ),
    );

    // Exams
    final exam1 = ExamModel(
      id: 'EXAM-01',
      title: 'اختبار التفاضل والتكامل',
      groupId: 'grp_sec3_a',
      date: todayStr,
      maxScore: 50,
    );
    await saveExam(exam1);
    await recordExamScore(
      const ExamScoreModel(
        examId: 'EXAM-01',
        studentId: 'STU-1001',
        score: 48,
        note: 'ممتاز جداً',
      ),
    );
    await recordExamScore(
      const ExamScoreModel(
        examId: 'EXAM-01',
        studentId: 'STU-1002',
        score: 39,
        note: 'جيد',
      ),
    );
    await recordExamScore(
      const ExamScoreModel(
        examId: 'EXAM-01',
        studentId: 'STU-1005',
        score: 45,
        note: 'متميز',
      ),
    );

  }

  // --- Database File Management & Backup / Restore ---
  Future<String> getDatabaseFilePath() async {
    final databasesPath = await getDatabasesPath();
    return path.join(databasesPath, 'teacher_center.db');
  }

  Future<File?> exportDatabase(String targetPath) async {
    final dbPath = await getDatabaseFilePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) return null;
    return await dbFile.copy(targetPath);
  }

  Future<Uint8List?> getDatabaseBytes() async {
    final dbPath = await getDatabaseFilePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) return null;
    return await dbFile.readAsBytes();
  }

  Future<bool> isDatabaseBackupValid(String sourcePath) async {
    // 1. Try opening as standard unencrypted SQLite database
    try {
      final backup = await openDatabase(
        sourcePath,
        readOnly: true,
        singleInstance: false,
      );
      try {
        final result = await backup.rawQuery('PRAGMA integrity_check');
        if (result.isNotEmpty && result.first.values.first == 'ok') {
          return true;
        }
      } finally {
        await backup.close();
      }
    } catch (_) {}

    // 2. Fallback: check if it is a legacy encrypted backup
    try {
      final key = await _getDatabaseEncryptionKey();
      if (key.isNotEmpty) {
        final backup = await sqlcipher.openDatabase(
          sourcePath,
          password: key,
          readOnly: true,
          singleInstance: false,
        );
        try {
          final result = await backup.rawQuery('PRAGMA integrity_check');
          return result.isNotEmpty && result.first.values.first == 'ok';
        } finally {
          await backup.close();
        }
      }
    } catch (_) {}

    return false;
  }

  Future<bool> restoreDatabaseFromBytes(Uint8List bytes) async {
    try {
      final dbPath = await getDatabaseFilePath();
      final stagedPath =
          '$dbPath.restore-${DateTime.now().microsecondsSinceEpoch}';
      await File(stagedPath).writeAsBytes(bytes, flush: true);
      return await _restoreDatabaseFromFile(stagedPath);
    } catch (e) {
      debugPrint('Restore database from bytes error: $e');
      return false;
    }
  }

  Future<bool> restoreDatabase(String sourcePath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) return false;
      final dbPath = await getDatabaseFilePath();
      final stagedPath =
          '$dbPath.restore-${DateTime.now().microsecondsSinceEpoch}';
      await sourceFile.copy(stagedPath);
      return await _restoreDatabaseFromFile(stagedPath);
    } catch (e) {
      debugPrint('Restore database error: $e');
      return false;
    }
  }

  Future<bool> _restoreDatabaseFromFile(String stagedPath) async {
    final databasePath = await getDatabaseFilePath();
    if (!await isDatabaseBackupValid(stagedPath)) return false;

    // Check if staged file is plain SQLite or encrypted
    bool isPlain = false;
    try {
      final testDb = await openDatabase(
        stagedPath,
        readOnly: true,
        singleInstance: false,
      );
      final result = await testDb.rawQuery('PRAGMA integrity_check');
      isPlain = result.isNotEmpty && result.first.values.first == 'ok';
      await testDb.close();
    } catch (_) {}

    String finalPath = stagedPath;
    if (!isPlain) {
      // Decrypt legacy backup to plain SQLite
      try {
        final key = await _getDatabaseEncryptionKey();
        final encDb = await sqlcipher.openDatabase(stagedPath, password: key);
        final decryptedStaged = '$stagedPath.plain';
        final escapedPath = decryptedStaged.replaceAll("'", "''");
        await encDb.rawQuery("ATTACH DATABASE '$escapedPath' AS plaintext KEY '';");
        await encDb.rawQuery("SELECT sqlcipher_export('plaintext');");
        await encDb.rawQuery("DETACH DATABASE plaintext;");
        await encDb.close();
        finalPath = decryptedStaged;
      } catch (e) {
        debugPrint('Failed to decrypt legacy backup: $e');
        return false;
      }
    }

    if (_database != null && _database!.isOpen) {
      await _database!.rawQuery('PRAGMA wal_checkpoint(FULL)');
      await _database!.close();
      _database = null;
    }

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final original = File(databasePath);
    final backupPath = '$databasePath.restore-backup-$timestamp';
    final hadOriginal = await original.exists();
    if (hadOriginal) await original.rename(backupPath);

    try {
      await File(finalPath).rename(databasePath);
      final restored = await database;
      return restored.isOpen;
    } catch (_) {
      final failedRestore = File(databasePath);
      if (await failedRestore.exists()) {
        await failedRestore.rename('$databasePath.failed-restore-$timestamp');
      }
      if (hadOriginal && await File(backupPath).exists()) {
        await File(backupPath).rename(databasePath);
      }
      rethrow;
    }
  }

  /// Automatically restores the latest valid auto-backup from Downloads/EduAcademy_Backups
  /// if the current database is freshly installed or empty (0 groups and 0 students).
  Future<bool> autoRestoreIfEmpty() async {
    try {
      final db = await database;
      final groupCountRes = await db.rawQuery('SELECT COUNT(*) as c FROM groups');
      final groupCount = Sqflite.firstIntValue(groupCountRes) ?? 0;
      final studentCountRes = await db.rawQuery('SELECT COUNT(*) as c FROM students');
      final studentCount = Sqflite.firstIntValue(studentCountRes) ?? 0;

      // If database already has data, do not overwrite anything
      if (groupCount > 0 || studentCount > 0) {
        return false;
      }

      final downloadDir = Directory('/storage/emulated/0/Download/EduAcademy_Backups');
      if (!await downloadDir.exists()) return false;

      final entities = await downloadDir.list().toList();
      final backupFiles = entities
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList();

      if (backupFiles.isEmpty) return false;

      // Sort by file size descending so the largest (filled) database backup is preferred
      backupFiles.sort((a, b) {
        try {
          return b.lengthSync().compareTo(a.lengthSync());
        } catch (_) {
          return 0;
        }
      });

      for (final bf in backupFiles) {
        final len = await bf.length();
        if (len < 50000) continue; // Skip small skeleton databases
        if (await isDatabaseBackupValid(bf.path)) {
          debugPrint('autoRestoreIfEmpty: Restoring valid backup ($len bytes) from: ${bf.path}');
          final success = await restoreDatabase(bf.path);
          if (success) {
            await preloadSettings();
            notifyChange(DataChangeEvent.all);
            debugPrint('autoRestoreIfEmpty: Successfully restored database!');
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('autoRestoreIfEmpty error: $e');
    }
    return false;
  }

  // --------------------------------------------------------------------------
  // AUTOMATIC DAILY BACKUP (Identical to PC App ensureDailyBackup)
  // --------------------------------------------------------------------------
  Future<void> ensureDailyBackup() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final db = await database;

      // Check if already backed up today
      final lastBackupRes = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['last_daily_backup_date'],
        limit: 1,
      );
      if (lastBackupRes.isNotEmpty && lastBackupRes.first['value'] == today) {
        return;
      }

      // Checkpoint WAL so everything is committed into main .db
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');
      } catch (_) {}

      final dbPath = await getDatabaseFilePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return;

      // 1. Internal App Documents Backup
      final appDocDir = await getApplicationDocumentsDirectory();
      final backupsDir = Directory(path.join(appDocDir.path, 'backups'));
      if (!await backupsDir.exists()) {
        await backupsDir.create(recursive: true);
      }

      var backupFileName = 'EduAcademy_Auto_$today.db';
      var backupAlreadyExists = await File(
        path.join(backupsDir.path, backupFileName),
      ).exists();
      final downloadDir = Directory(
        '/storage/emulated/0/Download/EduAcademy_Backups',
      );
      try {
        backupAlreadyExists |= await File(
          path.join(downloadDir.path, backupFileName),
        ).exists();
      } catch (_) {}
      if (backupAlreadyExists) {
        backupFileName =
            'EduAcademy_Auto_${today}_${DateTime.now().millisecondsSinceEpoch}.db';
      }

      await dbFile.copy(path.join(backupsDir.path, backupFileName));

      // 2. Public Downloads Backup (Survives app uninstalls & modifications)
      try {
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        await dbFile.copy(path.join(downloadDir.path, backupFileName));
      } catch (_) {}

      // Prune old backups keeping last 30
      await _pruneBackups(backupsDir, 30);

      await setSetting('last_daily_backup_date', today);
      await setSetting(
        'last_backup_timestamp',
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('ensureDailyBackup error: $e');
    }
  }

  static Future<void> _pruneBackups(Directory dir, int maxBackups) async {
    try {
      if (!await dir.exists()) return;
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.db'))
          .cast<File>()
          .toList();
      if (files.length <= maxBackups) return;

      files.sort((a, b) => a.path.compareTo(b.path));
      final deleteCount = files.length - maxBackups;
      for (int i = 0; i < deleteCount; i++) {
        try {
          await files[i].delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> wipeAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('session_logs');
      await txn.delete('curriculum_lessons');
      await txn.delete('group_curriculum_bindings');
      await txn.delete('expenses');
      await txn.delete('exam_scores');
      await txn.delete('exams');
      await txn.delete('payments');
      await txn.delete('attendance');
      await txn.delete('students');
      await txn.delete('groups');
    });
  }

  // --- Security PIN & Biometrics Settings ---
  Future<String> getSecurityPin() async {
    return await getSetting('security_pin', defaultValue: '1234');
  }

  Future<void> setSecurityPin(String pin) async {
    await setSetting('security_pin', pin.trim());
  }

  Future<bool> isBiometricsEnabled() async {
    final val = await getSetting(
      'security_biometrics_enabled',
      defaultValue: 'true',
    );
    return val == 'true';
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    await setSetting('security_biometrics_enabled', enabled ? 'true' : 'false');
  }

  // --- Daily Todo List Operations ---
  Future<List<Map<String, dynamic>>> getDailyTodos() async {
    final db = await database;
    return await db.query('daily_todos', orderBy: 'is_done ASC, id DESC');
  }

  Future<int> addDailyTodo(String title) async {
    final db = await database;
    return await db.insert('daily_todos', {
      'title': title.trim(),
      'is_done': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> toggleDailyTodo(int id, bool isDone) async {
    final db = await database;
    await db.update(
      'daily_todos',
      {'is_done': isDone ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteDailyTodo(int id) async {
    final db = await database;
    await db.delete('daily_todos', where: 'id = ?', whereArgs: [id]);
  }

  // ==========================================
  // الحصص الاستثنائية (Exceptional / Makeup Sessions)
  // ==========================================
  Future<void> saveExceptionalSession(ExceptionalSessionModel session) async {
    final db = await database;
    // Prevent duplicate entries for the exact same group, date, and time
    final existing = await db.query(
      'exceptional_sessions',
      where: 'group_id = ? AND date = ? AND time = ?',
      whereArgs: [session.groupId, session.date, session.time],
    );
    if (existing.isNotEmpty) {
      await db.update(
        'exceptional_sessions',
        session.toMap(),
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert(
        'exceptional_sessions',
        session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    notifyChange(DataChangeEvent.groups);
    notifyChange(DataChangeEvent.attendance);
  }

  Future<int> cleanDuplicateExceptionalSessions() async {
    final db = await database;
    final count = await db.rawDelete('''
      DELETE FROM exceptional_sessions
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM exceptional_sessions
        GROUP BY group_id, date, time
      )
    ''');
    if (count > 0) {
      notifyChange(DataChangeEvent.groups);
      notifyChange(DataChangeEvent.attendance);
    }
    return count;
  }

  Future<List<ExceptionalSessionModel>> getExceptionalSessions({
    String? groupId,
    String? date,
    String? day,
    String? status,
  }) async {
    final db = await database;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (groupId != null) {
      whereClauses.add('group_id = ?');
      whereArgs.add(groupId);
    }
    if (date != null) {
      if (day != null) {
        whereClauses.add('(date = ? OR (is_recurring = 1 AND day = ?))');
        whereArgs.add(date);
        whereArgs.add(day);
      } else {
        try {
          final parsedDate = DateTime.parse(date);
          const arabicDays = {
            DateTime.saturday: 'السبت',
            DateTime.sunday: 'الأحد',
            DateTime.monday: 'الاثنين',
            DateTime.tuesday: 'الثلاثاء',
            DateTime.wednesday: 'الأربعاء',
            DateTime.thursday: 'الخميس',
            DateTime.friday: 'الجمعة',
          };
          final derivedDay = arabicDays[parsedDate.weekday] ?? '';
          whereClauses.add('(date = ? OR (is_recurring = 1 AND day = ?))');
          whereArgs.add(date);
          whereArgs.add(derivedDay);
        } catch (_) {
          whereClauses.add('date = ?');
          whereArgs.add(date);
        }
      }
    } else if (day != null) {
      whereClauses.add('(day = ? OR is_recurring = 1)');
      whereArgs.add(day);
    }
    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status);
    }

    final whereString = whereClauses.isNotEmpty
        ? whereClauses.join(' AND ')
        : null;
    final results = await db.query(
      'exceptional_sessions',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'date DESC, time ASC',
    );

    return results.map((m) => ExceptionalSessionModel.fromMap(m)).toList();
  }

  Future<void> deleteExceptionalSession(String id) async {
    final db = await database;
    await db.delete('exceptional_sessions', where: 'id = ?', whereArgs: [id]);
    notifyChange(DataChangeEvent.groups);
    notifyChange(DataChangeEvent.attendance);
  }

  // --- WhatsApp Logs & History ---
  Future<int> logWhatsAppMessage({
    String? studentId,
    String? studentName,
    required String phone,
    String recipientType = 'parent',
    required String category,
    required String message,
    required String status,
    String? errorMessage,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      final insertedId = await db.insert('whatsapp_logs', {
        'student_id': studentId,
        'student_name': studentName,
        'phone': phone,
        'recipient_type': recipientType,
        'category': category,
        'message': message,
        'status': status,
        'error_message': errorMessage,
        'sent_at': now,
      });
      notifyChange(DataChangeEvent.reports);
      return insertedId;
    } catch (e) {
      debugPrint('Error logging WhatsApp message: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getWhatsAppLogs({
    int limit = 150,
    String? studentId,
    String? category,
  }) async {
    try {
      final db = await database;
      String? whereClause;
      List<dynamic>? whereArgs;
      if (studentId != null && category != null) {
        whereClause = 'student_id = ? AND category = ?';
        whereArgs = [studentId, category];
      } else if (studentId != null) {
        whereClause = 'student_id = ?';
        whereArgs = [studentId];
      } else if (category != null) {
        whereClause = 'category = ?';
        whereArgs = [category];
      }
      return await db.query(
        'whatsapp_logs',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'id DESC',
        limit: limit,
      );
    } catch (_) {
      return [];
    }
  }

  /// Specialized query for reports logs only (session reports, weekly reports, monthly reports)
  Future<List<Map<String, dynamic>>> getReportLogs({
    int limit = 150,
    String? studentId,
    List<String>? categories,
  }) async {
    try {
      final db = await database;
      String? whereClause;
      List<dynamic>? whereArgs;
      final reportCats = categories ?? ['sessionFollowup', 'holisticReport'];
      final placeholders = List.filled(reportCats.length, '?').join(',');
      if (studentId != null) {
        whereClause = 'student_id = ? AND category IN ($placeholders)';
        whereArgs = [studentId, ...reportCats];
      } else {
        whereClause = 'category IN ($placeholders)';
        whereArgs = reportCats;
      }
      return await db.query(
        'whatsapp_logs',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'id DESC',
        limit: limit,
      );
    } catch (_) {
      return [];
    }
  }

  Future<void> clearWhatsAppLogs() async {
    try {
      final db = await database;
      await db.delete('whatsapp_logs');
      notifyChange(DataChangeEvent.reports);
    } catch (_) {}
  }

  Future<void> deleteWhatsAppLogsByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    try {
      final db = await database;
      final placeholders = List.filled(ids.length, '?').join(',');
      await db.delete(
        'whatsapp_logs',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
      notifyChange(DataChangeEvent.reports);
    } catch (_) {}
  }

  Future<void> deleteWhatsAppLog(int id) async {
    try {
      final db = await database;
      await db.delete(
        'whatsapp_logs',
        where: 'id = ?',
        whereArgs: [id],
      );
      notifyChange(DataChangeEvent.reports);
    } catch (_) {}
  }

  /// Get detailed log entry if a report was previously sent to a student
  Future<Map<String, dynamic>?> getPreviousReportLog({
    required String studentId,
    required String category,
    String? date,
    String? periodStart,
    String? monthKey,
  }) async {
    try {
      final db = await database;
      String where =
          "student_id = ? AND category = ? AND status IN ('sent', 'sent_manual', 'success')";
      final List<dynamic> args = [studentId, category];

      if (date != null) {
        where += " AND sent_at LIKE ?";
        args.add('$date%');
      } else if (periodStart != null) {
        where += " AND sent_at >= ?";
        args.add(periodStart);
      } else if (monthKey != null) {
        where += " AND sent_at LIKE ?";
        args.add('$monthKey%');
      }

      final rows = await db.query(
        'whatsapp_logs',
        where: where,
        whereArgs: args,
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first;
    } catch (_) {}
    return null;
  }

  /// Check if a student already received a monthly report this month
  Future<bool> isMonthlyReportSentForStudent({
    required String studentId,
    required String monthKey,
  }) async {
    try {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT COUNT(*) as count FROM whatsapp_logs
        WHERE student_id = ?
          AND (category = 'monthly_report' OR (category = 'holisticReport' AND message LIKE '%تقرير شهري%'))
          AND status IN ('sent', 'sent_manual', 'success')
          AND sent_at LIKE ?
      ''', [studentId, '$monthKey%']);
      if (rows.isNotEmpty) {
        final count = (rows.first['count'] as int?) ?? 0;
        return count > 0;
      }
    } catch (_) {}
    return false;
  }

  /// Check if a monthly report was sent for any student in the group this month
  Future<bool> isMonthlyReportSentForGroup({
    required String groupId,
    required String monthKey,
  }) async {
    try {
      final flag = await getSetting('monthly_report_sent_${groupId}_$monthKey', defaultValue: 'false');
      if (flag == 'true') return true;
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT COUNT(*) as count FROM whatsapp_logs wl
        INNER JOIN students s ON s.id = wl.student_id
        WHERE s.group_id = ?
          AND (wl.category = 'monthly_report' OR (wl.category = 'holisticReport' AND wl.message LIKE '%تقرير شهري%'))
          AND wl.status IN ('sent', 'sent_manual', 'success')
          AND wl.sent_at LIKE ?
      ''', [groupId, '$monthKey%']);
      if (rows.isNotEmpty) {
        final count = (rows.first['count'] as int?) ?? 0;
        return count > 0;
      }
    } catch (_) {}
    return false;
  }

  /// Check if session on sessionDate is the final scheduled session in this month for group
  bool isLastSessionOfMonthForGroup(GroupModel group, DateTime sessionDate) {
    final year = sessionDate.year;
    final month = sessionDate.month;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    final remainingDays = <DateTime>[];
    for (int day = sessionDate.day + 1; day <= lastDayOfMonth; day++) {
      remainingDays.add(DateTime(year, month, day));
    }

    final groupDays = group.days.isNotEmpty ? group.days : group.schedule;
    const arabicDays = {
      DateTime.saturday: 'السبت',
      DateTime.sunday: 'الأحد',
      DateTime.monday: 'الاثنين',
      DateTime.tuesday: 'الثلاثاء',
      DateTime.wednesday: 'الأربعاء',
      DateTime.thursday: 'الخميس',
      DateTime.friday: 'الجمعة',
    };

    for (final date in remainingDays) {
      final dayName = arabicDays[date.weekday] ?? '';
      if (dayName.isNotEmpty && groupDays.contains(dayName)) {
        return false;
      }
    }
    return true;
  }

  /// Check if a session report was already sent for a group on a specific date
  Future<bool> isReportSentForGroupToday({
    required String groupId,
    required String date,
  }) async {
    try {
      // 1. Check quick setting flag
      final flag = await getSetting('report_sent_${groupId}_$date', defaultValue: 'false');
      if (flag == 'true') return true;

      // 2. Check in whatsapp_logs if students from this group have reports sent on this date
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT COUNT(*) as count FROM whatsapp_logs wl
        INNER JOIN students s ON s.id = wl.student_id
        WHERE s.group_id = ?
          AND wl.category IN ('sessionFollowup', 'session_report', 'holisticReport')
          AND wl.status IN ('sent', 'sent_manual')
          AND wl.sent_at LIKE ?
      ''', [groupId, '$date%']);
      if (rows.isNotEmpty) {
        final count = (rows.first['count'] as int?) ?? 0;
        if (count > 0) return true;
      }
    } catch (_) {}
    return false;
  }

  /// Normalize message category to standard keys across all modules
  static String normalizeMessageCategory(String cat) {
    final lower = cat.trim().toLowerCase();
    if (lower == 'sessionfollowup' ||
        lower == 'session_report' ||
        lower == 'daily_report' ||
        lower == 'session_followup') {
      return 'daily_report';
    }
    if (lower == 'absence' ||
        lower == 'absencealert' ||
        lower == 'absence_alert') {
      return 'absence';
    }
    if (lower == 'certificate' || lower == 'cert') {
      return 'certificate';
    }
    if (lower == 'cancellation') {
      return 'cancellation';
    }
    if (lower == 'payment' ||
        lower == 'financialreceipt' ||
        lower == 'payment_receipt') {
      return 'payment';
    }
    if (lower == 'exam' ||
        lower == 'examscore' ||
        lower == 'exam_score') {
      return 'exam';
    }
    return cat.trim();
  }

  /// Record sent message to the centralized, tamper-proof ledger
  Future<void> recordSentMessage({
    required String studentId,
    required String category,
    required String contextKey,
    String phone = '',
    String status = 'sent',
    String? sentAt,
  }) async {
    if (studentId.trim().isEmpty) return;
    final normCat = normalizeMessageCategory(category);
    final normKey = contextKey.trim();
    final timestamp = sentAt ?? DateTime.now().toIso8601String();
    try {
      final db = await database;
      await db.insert(
        'sent_messages_ledger',
        {
          'student_id': studentId.trim(),
          'category': normCat,
          'context_key': normKey,
          'phone': phone.trim(),
          'sent_at': timestamp,
          'status': status,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Error recording sent message to ledger: $e');
    }
  }

  /// Strictly check if a student was already sent a message of this category and context
  Future<bool> isMessageSentStrict({
    required String studentId,
    required String category,
    required String contextKey,
  }) async {
    if (studentId.trim().isEmpty) return false;
    final normCat = normalizeMessageCategory(category);
    final normKey = contextKey.trim();
    try {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT id FROM sent_messages_ledger
        WHERE student_id = ?
          AND category = ?
          AND context_key = ?
        LIMIT 1
      ''', [studentId.trim(), normCat, normKey]);
      if (rows.isNotEmpty) return true;

      // Fallback backward compatibility with whatsapp_logs
      final legacyRows = await db.rawQuery('''
        SELECT id FROM whatsapp_logs
        WHERE student_id = ?
          AND (
            category = ? 
            OR (? = 'daily_report' AND category IN ('sessionFollowup', 'session_report', 'daily_report'))
            OR (? = 'absence' AND category IN ('absence', 'absenceAlert', 'absence_alert'))
            OR (? = 'certificate' AND category IN ('certificate', 'cert'))
          )
          AND sent_at LIKE ?
          AND status IN ('sent', 'sent_manual', 'sent_api', 'opened_whatsapp')
        LIMIT 1
      ''', [studentId.trim(), category, normCat, normCat, normCat, '$normKey%']);
      if (legacyRows.isNotEmpty) {
        unawaited(recordSentMessage(
          studentId: studentId.trim(),
          category: normCat,
          contextKey: normKey,
        ));
        return true;
      }
    } catch (e) {
      debugPrint('Error in isMessageSentStrict: $e');
    }
    return false;
  }

  /// Fetch all student IDs who have already received a message for a given category & context
  Future<Set<String>> getSentStudentIdsStrict({
    required String category,
    required String contextKey,
    List<String>? studentIds,
  }) async {
    final normCat = normalizeMessageCategory(category);
    final normKey = contextKey.trim();
    final result = <String>{};
    try {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT student_id FROM sent_messages_ledger
        WHERE category = ? AND context_key = ?
      ''', [normCat, normKey]);
      for (final r in rows) {
        final sId = r['student_id'] as String?;
        if (sId != null && sId.trim().isNotEmpty) {
          result.add(sId.trim());
        }
      }

      // Check legacy whatsapp_logs
      final legacyRows = await db.rawQuery('''
        SELECT DISTINCT student_id FROM whatsapp_logs
        WHERE (
          category = ?
          OR (? = 'daily_report' AND category IN ('sessionFollowup', 'session_report', 'daily_report'))
          OR (? = 'absence' AND category IN ('absence', 'absenceAlert', 'absence_alert'))
          OR (? = 'certificate' AND category IN ('certificate', 'cert'))
        )
        AND sent_at LIKE ?
        AND status IN ('sent', 'sent_manual', 'sent_api', 'opened_whatsapp')
        AND student_id IS NOT NULL AND student_id != ''
      ''', [category, normCat, normCat, normCat, '$normKey%']);
      for (final r in legacyRows) {
        final sId = r['student_id'] as String?;
        if (sId != null && sId.trim().isNotEmpty) {
          final cleanId = sId.trim();
          result.add(cleanId);
          unawaited(recordSentMessage(
            studentId: cleanId,
            category: normCat,
            contextKey: normKey,
          ));
        }
      }
    } catch (e) {
      debugPrint('Error in getSentStudentIdsStrict: $e');
    }
    return result;
  }

  /// Check if a specific student received a session report today
  Future<bool> isStudentReportSentToday({
    required String studentId,
    required String date,
    String category = 'daily_report',
  }) async {
    return isMessageSentStrict(
      studentId: studentId,
      category: category,
      contextKey: date,
    );
  }

  /// Check if a student already received a weekly report this week
  Future<bool> isWeeklyReportSentForStudent({
    required String studentId,
    required String weekStartDate,
  }) async {
    try {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT COUNT(*) as count FROM whatsapp_logs
        WHERE student_id = ?
          AND category = 'holisticReport'
          AND status IN ('sent', 'sent_manual')
          AND sent_at >= ?
      ''', [studentId, weekStartDate]);
      if (rows.isNotEmpty) {
        final count = (rows.first['count'] as int?) ?? 0;
        return count > 0;
      }
    } catch (_) {}
    return false;
  }

  /// Get customizable footer for each message category
  Future<String> getCategoryFooter(String category) async {
    try {
      final custom = await getSetting('whatsapp_footer_$category', defaultValue: '');
      if (custom.trim().isNotEmpty) return custom.trim();

      // Category-specific smart default
      final cName = await getSetting('center_name', defaultValue: '');
      final tName = await getSetting('teacher_name', defaultValue: '');
      final phone = await getSetting('phone', defaultValue: '');
      final name = cName.isNotEmpty ? cName : (tName.isNotEmpty ? tName : 'إدارة السنتر');
      final phoneLine = phone.isNotEmpty ? ' • 📞 $phone' : '';

      switch (category) {
        case 'sessionFollowup':
          return '---\n✨ مع تحيات: $name$phoneLine\nمعاً لغرس حب العلم والتميز 🎓';
        case 'holisticReport':
          return '---\n📈 تقرير أسبوعي صادر عن المنظومة التعليمية الذكية\n$name$phoneLine • شكراً لحسن تعاونكم المثمر';
        case 'absenceAlert':
          return '---\n⚠️ حرصاً منا على مصلحة أبنائنا، يرجى التواصل مع الإدارة: $name$phoneLine';
        case 'notebookBehavior':
          return '---\n⭐ معاً لصناعة الانضباط والتفوق • $name$phoneLine';
        case 'financialReceipt':
          return '---\n💳 إيصال إلكتروني صادر عن إدارة $name$phoneLine';
        default:
          final globalFooter = await getSetting('whatsapp_message_footer', defaultValue: '');
          if (globalFooter.trim().isNotEmpty) return globalFooter.trim();
          return '---\n📍 $name$phoneLine';
      }
    } catch (_) {
      return '';
    }
  }

  /// Set customizable footer for a message category
  Future<void> setCategoryFooter(String category, String footer) async {
    await setSetting('whatsapp_footer_$category', footer.trim());
  }

  // --- Certificates Table Helpers ---
  Future<void> saveCertificate({
    required String id,
    required String studentId,
    required String studentName,
    required String examTitle,
    String? badgeTitle,
    String? scoreText,
    String? issuedAt,
  }) async {
    final db = await database;
    await db.insert(
      'certificates',
      {
        'id': id,
        'student_id': studentId,
        'student_name': studentName,
        'exam_title': examTitle,
        'badge_title': badgeTitle ?? '',
        'score_text': scoreText ?? '',
        'issued_at': issuedAt ?? DateTime.now().toIso8601String(),
        'is_synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.reports);
  }

  Future<List<Map<String, dynamic>>> getCertificates({String? studentId}) async {
    final db = await database;
    if (studentId != null && studentId.isNotEmpty) {
      return await db.query(
        'certificates',
        where: 'student_id = ?',
        whereArgs: [studentId],
        orderBy: 'issued_at DESC',
      );
    }
    return await db.query('certificates', orderBy: 'issued_at DESC');
  }

  // ==========================================
  // نظام بنك النقاط والمكافآت التفاعلي
  // ==========================================

  /// جلب قواعد احتساب النقاط من الإعدادات
  Future<Map<String, int>> getPointsRules() async {
    final att = await getSetting('points_rule_attendance', defaultValue: '10');
    final hw = await getSetting('points_rule_homework', defaultValue: '15');
    final qz = await getSetting('points_rule_quiz', defaultValue: '25');

    return {
      'attendance': int.tryParse(att) ?? 10,
      'homework': int.tryParse(hw) ?? 15,
      'quiz': int.tryParse(qz) ?? 25,
    };
  }

  /// حفظ قواعد احتساب النقاط
  Future<void> savePointsRules({
    required int attendance,
    required int homework,
    required int quiz,
  }) async {
    await setSetting('points_rule_attendance', '$attendance');
    await setSetting('points_rule_homework', '$homework');
    await setSetting('points_rule_quiz', '$quiz');
    notifyChange(DataChangeEvent.settings);
  }

  /// جلب جميع المكافآت من الكتالوج (مع إضافة 3 افتراضية إذا كان فارغاً)
  Future<List<Map<String, dynamic>>> getAllRewards() async {
    final db = await database;
    var rows = await db.query('rewards_catalog', orderBy: 'cost_points ASC');
    if (rows.isEmpty) {
      final now = DateTime.now().toIso8601String();
      await db.insert('rewards_catalog', {
        'id': 'reward_badge_cert',
        'title': 'شهادة تفوق إلكترونية ذهبية 📜',
        'description': 'شهادة تقدير رسمية موقعة تظهر في ملفك وإشعار بالواتساب',
        'cost_points': 50,
        'icon_name': 'card_membership',
        'is_active': 1,
        'updated_at': now,
      });
      await db.insert('rewards_catalog', {
        'id': 'reward_discount_50',
        'title': 'خصم 50 ج على اشتراك الشهر القادم 💵',
        'description': 'قسيمة خصم فورية تطبق على أول مطالبة شهرية قادمة',
        'cost_points': 150,
        'icon_name': 'payments',
        'is_active': 1,
        'updated_at': now,
      });
      await db.insert('rewards_catalog', {
        'id': 'reward_free_month',
        'title': 'شهر مجاني كامل ومذكرة الشرح 🎁',
        'description': 'إعفاء كامل من مصاريف الشهر القادم مع مذكرة المراجعة هدية',
        'cost_points': 300,
        'icon_name': 'stars',
        'is_active': 1,
        'updated_at': now,
      });
      rows = await db.query('rewards_catalog', orderBy: 'cost_points ASC');
    }
    return rows;
  }

  /// حفظ أو تحديث مكافأة في الكتالوج
  Future<void> saveReward({
    required String id,
    required String title,
    String description = '',
    required int costPoints,
    String iconName = 'gift',
    int isActive = 1,
  }) async {
    final db = await database;
    await db.insert(
      'rewards_catalog',
      {
        'id': id,
        'title': title,
        'description': description,
        'cost_points': costPoints,
        'icon_name': iconName,
        'is_active': isActive,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyChange(DataChangeEvent.settings);
  }

  /// حذف مكافأة من الكتالوج
  Future<void> deleteReward(String id) async {
    final db = await database;
    await db.delete('rewards_catalog', where: 'id = ?', whereArgs: [id]);
    notifyChange(DataChangeEvent.settings);
  }

  /// إضافة نقاط لطالب مع تسجيل العملية في سجل النقاط ومنع التكرار لنفس اليوم والسبب
  Future<bool> awardStudentPoints({
    required String studentId,
    required int delta,
    required String reason,
    String? uniqueKey,
  }) async {
    if (delta == 0) return false;
    final db = await database;

    // فحص منع التكرار إذا تم تحديد uniqueKey أو كان اليوم ونفس السبب موجودين
    if (uniqueKey != null && uniqueKey.isNotEmpty) {
      final existing = await db.query(
        'student_points_log',
        where: 'id = ?',
        whereArgs: [uniqueKey],
      );
      if (existing.isNotEmpty) return false;
    }

    final logId = uniqueKey ?? 'pt_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.insert('student_points_log', {
        'id': logId,
        'student_id': studentId,
        'points_delta': delta,
        'reason': reason,
        'voucher_code': null,
        'status': 'completed',
        'created_at': now,
      });

      await txn.rawUpdate(
        'UPDATE students SET points_balance = MAX(0, points_balance + ?) WHERE id = ?',
        [delta, studentId],
      );
    });

    notifyChange(DataChangeEvent.students);
    return true;
  }

  /// استبدال مكافأة للطالب وصرف قسيمة
  Future<String?> redeemRewardForStudent({
    required String studentId,
    required String rewardId,
  }) async {
    final db = await database;

    final rewardRes = await db.query('rewards_catalog', where: 'id = ?', whereArgs: [rewardId]);
    if (rewardRes.isEmpty) return null;
    final reward = rewardRes.first;
    final cost = (reward['cost_points'] as num).toInt();
    final rewardTitle = reward['title'] as String;

    final studentRes = await db.query('students', where: 'id = ?', whereArgs: [studentId]);
    if (studentRes.isEmpty) return null;
    final currentPoints = (studentRes.first['points_balance'] as num?)?.toInt() ?? 0;

    if (currentPoints < cost) return null; // رصيد غير كافٍ

    final rnd = Random();
    final voucherCode = 'GIFT-${1000 + rnd.nextInt(9000)}';
    final now = DateTime.now().toIso8601String();
    final logId = 'redeem_${DateTime.now().millisecondsSinceEpoch}_${rnd.nextInt(1000)}';

    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE students SET points_balance = points_balance - ? WHERE id = ?',
        [cost, studentId],
      );

      await txn.insert('student_points_log', {
        'id': logId,
        'student_id': studentId,
        'points_delta': -cost,
        'reason': 'استبدال مكافأة: $rewardTitle',
        'voucher_code': voucherCode,
        'status': 'completed',
        'created_at': now,
      });
    });

    notifyChange(DataChangeEvent.students);
    return voucherCode;
  }

  /// جلب سجل نقاط الطالب
  Future<List<Map<String, dynamic>>> getStudentPointsLog(String studentId) async {
    final db = await database;
    return await db.query(
      'student_points_log',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'created_at DESC',
    );
  }

  /// جلب أوائل الطلاب في النقاط (لوحة الشرف)
  Future<List<Map<String, dynamic>>> getLeaderboardStudents({int limit = 20, String? groupId}) async {
    final db = await database;
    if (groupId != null && groupId.isNotEmpty) {
      return await db.query(
        'students',
        columns: ['id', 'full_name', 'points_balance', 'grade', 'group_id'],
        where: 'group_id = ? AND is_active = 1',
        whereArgs: [groupId],
        orderBy: 'points_balance DESC',
        limit: limit,
      );
    }
    return await db.query(
      'students',
      columns: ['id', 'full_name', 'points_balance', 'grade', 'group_id'],
      where: 'is_active = 1',
      orderBy: 'points_balance DESC',
      limit: limit,
    );
  }
}
