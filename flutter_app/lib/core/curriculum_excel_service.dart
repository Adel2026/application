import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';

import '../models/curriculum_model.dart';
import 'database/database_service.dart';

class CurriculumImportReport {
  final int totalParsed;
  final int totalSaved;
  final List<String> grades;
  final int unitsCount;
  final List<String> errors;

  CurriculumImportReport({
    required this.totalParsed,
    required this.totalSaved,
    required this.grades,
    required this.unitsCount,
    this.errors = const [],
  });
}

class CurriculumExcelService {
  /// Infer educational stage from grade name
  static String inferStage(String grade) {
    if (grade.contains('ابتدائي') || grade.contains('الابتدائي') || grade.toLowerCase().contains('pri')) return 'المرحلة الابتدائية';
    if (grade.contains('إعدادي') || grade.contains('اعدادي') || grade.contains('الإعدادي') || grade.toLowerCase().contains('prep')) return 'المرحلة الإعدادية';
    return 'المرحلة الثانوية';
  }

  /// Automatically detects standard grade, stage, and curriculum name from file name or sheet name
  static Map<String, String> detectGradeAndCurriculum({String? fileName, String? sheetName}) {
    final combined = '${fileName ?? ''} ${sheetName ?? ''}'.toLowerCase();

    String grade = 'الصف الأول الإعدادي (Prep 1)';
    String stage = 'المرحلة الإعدادية';
    String curriculumName = 'منهج الصف الأول الإعدادي (Prep 1)';

    if (combined.contains('prep 3') || combined.contains('prep3') || combined.contains('ثالث إعدادي') || combined.contains('ثالث اعدادي')) {
      grade = 'الصف الثالث الإعدادي (Prep 3)';
      stage = 'المرحلة الإعدادية';
      curriculumName = 'منهج الصف الثالث الإعدادي (Prep 3)';
    } else if (combined.contains('prep 2') || combined.contains('prep2') || combined.contains('ثاني إعدادي') || combined.contains('ثاني اعدادي')) {
      grade = 'الصف الثاني الإعدادي (Prep 2)';
      stage = 'المرحلة الإعدادية';
      curriculumName = 'منهج الصف الثاني الإعدادي (Prep 2)';
    } else if (combined.contains('prep 1') || combined.contains('prep1') || combined.contains('أول إعدادي') || combined.contains('اول اعدادي')) {
      grade = 'الصف الأول الإعدادي (Prep 1)';
      stage = 'المرحلة الإعدادية';
      curriculumName = 'منهج الصف الأول الإعدادي (Prep 1)';
    } else if (combined.contains('prim 4') || combined.contains('prim4') || combined.contains('pri 4') || combined.contains('pri4') || combined.contains('رابع ابتدائي')) {
      grade = 'الصف الرابع الابتدائي (Prim 4)';
      stage = 'المرحلة الابتدائية';
      curriculumName = 'منهج الصف الرابع الابتدائي (Prim 4)';
    } else if (combined.contains('prim 5') || combined.contains('prim5') || combined.contains('pri 5') || combined.contains('pri5') || combined.contains('خامس ابتدائي')) {
      grade = 'الصف الخامس الابتدائي (Prim 5)';
      stage = 'المرحلة الابتدائية';
      curriculumName = 'منهج الصف الخامس الابتدائي (Prim 5)';
    } else if (combined.contains('prim 6') || combined.contains('prim6') || combined.contains('pri 6') || combined.contains('pri6') || combined.contains('سادس ابتدائي')) {
      grade = 'الصف السادس الابتدائي (Prim 6)';
      stage = 'المرحلة الابتدائية';
      curriculumName = 'منهج الصف السادس الابتدائي (Prim 6)';
    } else if (combined.contains('sec 1') || combined.contains('sec1') || combined.contains('أول ثانوي') || combined.contains('اول ثانوي')) {
      grade = 'الصف الأول الثانوي (Sec 1)';
      stage = 'المرحلة الثانوية';
      curriculumName = 'منهج الصف الأول الثانوي (Sec 1)';
    } else if (combined.contains('sec 2') || combined.contains('sec2') || combined.contains('ثاني ثانوي')) {
      grade = 'الصف الثاني الثانوي (Sec 2)';
      stage = 'المرحلة الثانوية';
      curriculumName = 'منهج الصف الثاني الثانوي (Sec 2)';
    } else if (combined.contains('sec 3') || combined.contains('sec3') || combined.contains('ثالث ثانوي')) {
      grade = 'الصف الثالث الثانوي (Sec 3)';
      stage = 'المرحلة الثانوية';
      curriculumName = 'منهج الصف الثالث الثانوي (Sec 3)';
    } else if (fileName != null && fileName.trim().isNotEmpty) {
      final cleanBase = fileName.replaceAll(RegExp(r'\.(xlsx|xls|csv)$', caseSensitive: false), '').trim();
      if (cleanBase.isNotEmpty) {
        curriculumName = cleanBase.startsWith('منهج') ? cleanBase : 'منهج $cleanBase';
        stage = inferStage(cleanBase);
        grade = cleanBase;
      }
    }

    return {
      'grade': grade,
      'stage': stage,
      'curriculumName': curriculumName,
    };
  }

  static bool _isCsvBytes(Uint8List bytes, String? fileName) {
    if (fileName != null && fileName.toLowerCase().endsWith('.csv')) return true;
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      // PK zip header (XLSX)
      return false;
    }
    return true;
  }

  /// Parse Excel or CSV bytes into a list of CurriculumLessonModel matching PC files
  static List<CurriculumLessonModel> parseExcelBytes({
    required Uint8List bytes,
    String? fileName,
    String? curriculumName,
    String? targetGrade,
    String? targetStage,
    String defaultSubject = 'ICT & تكنولوجيا المعلومات',
    String? defaultGrade,
  }) {
    if (_isCsvBytes(bytes, fileName)) {
      try {
        final csvLessons = _parseCsvBytes(
          bytes: bytes,
          fileName: fileName,
          curriculumName: curriculumName,
          targetGrade: targetGrade,
          targetStage: targetStage,
          defaultSubject: defaultSubject,
          defaultGrade: defaultGrade,
        );
        if (csvLessons.isNotEmpty) return csvLessons;
      } catch (_) {}
    }

    Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (_) {
      // Fallback: try parsing as CSV in case decodeBytes failed
      return _parseCsvBytes(
        bytes: bytes,
        fileName: fileName,
        curriculumName: curriculumName,
        targetGrade: targetGrade,
        targetStage: targetStage,
        defaultSubject: defaultSubject,
        defaultGrade: defaultGrade,
      );
    }

    final List<CurriculumLessonModel> result = [];

    final detected = detectGradeAndCurriculum(fileName: fileName);
    final fallbackGrade = targetGrade ?? defaultGrade ?? detected['grade']!;
    final fallbackStage = targetStage ?? detected['stage']!;
    final fallbackName = curriculumName ?? detected['curriculumName']!;

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null || sheet.rows.isEmpty) continue;

      // Also check sheet name if table is specific like Prep2
      final sheetDetected = detectGradeAndCurriculum(fileName: fileName, sheetName: table);
      final activeDefaultGrade = targetGrade ?? defaultGrade ?? (sheetDetected['grade'] != 'الصف الأول الإعدادي (Prep 1)' ? sheetDetected['grade']! : fallbackGrade);
      final activeDefaultName = curriculumName ?? (sheetDetected['curriculumName'] != 'منهج الصف الأول الإعدادي (Prep 1)' ? sheetDetected['curriculumName']! : fallbackName);

      int headerRowIndex = -1;
      int subjectCol = -1;
      int gradeCol = -1;
      int unitCol = -1;
      int lessonCol = -1;
      int descCol = -1;
      int completedCol = -1;
      int dateCol = -1;
      int notesCol = -1;
      int numCol = -1;

      // Scan first 5 rows to find header matching PC export or standard forms
      for (int r = 0; r < sheet.rows.length && r < 5; r++) {
        final row = sheet.rows[r];
        for (int c = 0; c < row.length; c++) {
          final val = _cellToString(row[c]?.value).trim().toLowerCase();
          if (val.isEmpty) continue;

          if (val.contains('ملاحظات') || val.contains('واجب') || val.contains('notes') || val.contains('homework')) {
            notesCol = c;
          } else if (val.contains('وصف') || val.contains('عناصر') || val.contains('هدف') || val.contains('objectives') || val.contains('description') || val.contains('desc')) {
            descCol = c;
          } else if (val.contains('مكتمل') || val.contains('completed') || val.contains('إنجاز')) {
            completedCol = c;
          } else if (val.contains('تاريخ') || val.contains('date')) {
            dateCol = c;
          } else if (val.contains('وحدة') || val.contains('unit') || val.contains('باب') || val.contains('chapter')) {
            unitCol = c;
          } else if (val.contains('عنوان') || val.contains('title') || val.contains('درس') || val.contains('lesson') || val.contains('topic')) {
            lessonCol = c;
          } else if (val.contains('مادة') || val.contains('subject')) {
            subjectCol = c;
          } else if (val.contains('صف') || val.contains('grade') || val.contains('مرحلة')) {
            gradeCol = c;
          } else if (val.contains('ترتيب') || val.contains('رقم') || val.contains('order')) {
            numCol = c;
          }
        }

        // If at least unit or lesson column is found, consider this the header row
        if (lessonCol != -1 || unitCol != -1) {
          headerRowIndex = r;
          break;
        }
      }

      // Positional fallbacks matching PC layout if headers aren't detected by text
      final startRow = headerRowIndex >= 0 ? headerRowIndex + 1 : 0;
      if (unitCol == -1 && lessonCol == -1) {
        unitCol = 0;
        lessonCol = 1;
        descCol = 2;
        completedCol = 3;
        dateCol = 4;
        notesCol = 5;
      } else if (unitCol == -1) {
        unitCol = lessonCol == 0 ? 1 : 0;
      } else if (lessonCol == -1) {
        lessonCol = unitCol == 0 ? 1 : 0;
      }

      String currentUnit = 'Unit 1';

      for (int r = startRow; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        if (row.isEmpty) continue;

        String getCol(int colIdx) {
          if (colIdx >= 0 && colIdx < row.length) {
            return _cellToString(row[colIdx]?.value).trim();
          }
          return '';
        }

        final subject = subjectCol != -1 ? getCol(subjectCol) : defaultSubject;
        final grade = gradeCol != -1 ? getCol(gradeCol) : activeDefaultGrade;
        final unitRaw = unitCol != -1 ? getCol(unitCol) : '';
        final lessonRaw = lessonCol != -1 ? getCol(lessonCol) : '';
        final descRaw = descCol != -1 ? getCol(descCol) : '';
        final completedRaw = completedCol != -1 ? getCol(completedCol).toLowerCase() : '';
        final dateRaw = dateCol != -1 ? getCol(dateCol) : '';
        final notesRaw = notesCol != -1 ? getCol(notesCol) : '';
        final numRaw = numCol != -1 ? getCol(numCol) : '';

        if (unitRaw.isNotEmpty) {
          currentUnit = unitRaw;
        }

        // Skip rows that don't have a lesson title
        if (lessonRaw.isEmpty) {
          continue;
        }

        final isDone = completedRaw == 'yes' ||
            completedRaw == 'y' ||
            completedRaw == 'نعم' ||
            completedRaw == 'true' ||
            completedRaw == '1';

        final chapterNum = int.tryParse(numRaw) ?? (result.length + 1);
        final finalGrade = grade.isNotEmpty ? grade : activeDefaultGrade;
        final finalSubject = subject.isNotEmpty ? subject : defaultSubject;
        final finalCurName = curriculumName ?? (activeDefaultName.isNotEmpty ? activeDefaultName : 'منهج $finalGrade');
        final finalStage = targetStage ?? (grade.isNotEmpty ? inferStage(grade) : fallbackStage);

        result.add(
          CurriculumLessonModel(
            subject: finalSubject,
            stage: finalStage,
            grade: finalGrade,
            curriculumName: finalCurName,
            unitName: currentUnit,
            lessonTitle: lessonRaw,
            objectives: descRaw,
            chapterNumber: chapterNum,
            isCompleted: isDone,
            lessonDate: dateRaw.isNotEmpty ? dateRaw : null,
            homeworkNotes: notesRaw.isNotEmpty ? notesRaw : null,
          ),
        );
      }
    }

    return result;
  }

  static List<CurriculumLessonModel> _parseCsvBytes({
    required Uint8List bytes,
    String? fileName,
    String? curriculumName,
    String? targetGrade,
    String? targetStage,
    String defaultSubject = 'ICT & تكنولوجيا المعلومات',
    String? defaultGrade,
  }) {
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = String.fromCharCodes(bytes);
    }

    final lines = content.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return [];

    final detected = detectGradeAndCurriculum(fileName: fileName);
    final fallbackGrade = targetGrade ?? defaultGrade ?? detected['grade']!;
    final fallbackStage = targetStage ?? detected['stage']!;
    final fallbackName = curriculumName ?? detected['curriculumName']!;

    final List<CurriculumLessonModel> result = [];
    String currentUnit = 'Unit 1: The Role of Technology in Our Lives';

    int unitCol = 0;
    int lessonCol = 1;
    int descCol = 2;
    int completedCol = 3;
    int dateCol = 4;
    int notesCol = 5;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final parts = _parseCsvLine(line);
      if (parts.isEmpty) continue;

      // Check if header line
      final firstPart = parts[0].toLowerCase();
      if (firstPart.contains('unit name') || firstPart.contains('اسم الوحدة') || (parts.length > 1 && parts[1].toLowerCase().contains('lesson title'))) {
        for (int c = 0; c < parts.length; c++) {
          final p = parts[c].trim().toLowerCase();
          if (p.contains('ملاحظات') || p.contains('notes') || p.contains('homework')) {
            notesCol = c;
          } else if (p.contains('وصف') || p.contains('description') || p.contains('desc')) {
            descCol = c;
          } else if (p.contains('completed') || p.contains('مكتمل')) {
            completedCol = c;
          } else if (p.contains('date') || p.contains('تاريخ')) {
            dateCol = c;
          } else if (p.contains('unit') || p.contains('وحدة')) {
            unitCol = c;
          } else if (p.contains('lesson') || p.contains('عنوان') || p.contains('درس')) {
            lessonCol = c;
          }
        }
        continue;
      }

      String getCol(int col) => (col >= 0 && col < parts.length) ? parts[col].trim() : '';

      final unitRaw = getCol(unitCol);
      final lessonRaw = getCol(lessonCol);
      final descRaw = getCol(descCol);
      final completedRaw = getCol(completedCol).toLowerCase();
      final dateRaw = getCol(dateCol);
      final notesRaw = getCol(notesCol);

      if (unitRaw.isNotEmpty) {
        currentUnit = unitRaw;
      }

      if (lessonRaw.isEmpty || lessonRaw.toLowerCase() == 'lesson title' || lessonRaw == 'عنوان الدرس') {
        continue;
      }

      final isDone = completedRaw == 'yes' ||
          completedRaw == 'y' ||
          completedRaw == 'نعم' ||
          completedRaw == 'true' ||
          completedRaw == '1';

      result.add(
        CurriculumLessonModel(
          subject: defaultSubject,
          stage: fallbackStage,
          grade: fallbackGrade,
          curriculumName: fallbackName,
          unitName: currentUnit,
          lessonTitle: lessonRaw,
          objectives: descRaw,
          chapterNumber: result.length + 1,
          isCompleted: isDone,
          lessonDate: dateRaw.isNotEmpty ? dateRaw : null,
          homeworkNotes: notesRaw.isNotEmpty ? notesRaw : null,
        ),
      );
    }

    return result;
  }

  static List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    final StringBuffer current = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current.toString().trim());
        current.clear();
      } else {
        current.write(char);
      }
    }
    result.add(current.toString().trim());
    return result;
  }

  /// Import curriculum lessons from Excel bytes and save to database
  static Future<CurriculumImportReport> importCurriculum({
    required Uint8List bytes,
    required DatabaseService database,
    String? fileName,
    String? curriculumName,
    String? grade,
    String? stage,
    String defaultSubject = 'ICT & تكنولوجيا المعلومات',
    String? defaultGrade,
    bool replaceAll = false,
  }) async {
    final parsedLessons = parseExcelBytes(
      bytes: bytes,
      fileName: fileName,
      curriculumName: curriculumName,
      targetGrade: grade,
      targetStage: stage,
      defaultSubject: defaultSubject,
      defaultGrade: defaultGrade,
    );

    if (parsedLessons.isEmpty) {
      return CurriculumImportReport(
        totalParsed: 0,
        totalSaved: 0,
        grades: [],
        unitsCount: 0,
        errors: ['لم يتم العثور على أي دروس صالحة داخل الملف.'],
      );
    }

    await database.saveCurriculumLessonsBatch(parsedLessons, replaceAll: replaceAll);

    final uniqueGrades = parsedLessons.map((l) => l.grade).toSet().toList()..sort();
    final uniqueUnits = parsedLessons.map((l) => '${l.grade}::${l.unitName}').toSet().length;

    return CurriculumImportReport(
      totalParsed: parsedLessons.length,
      totalSaved: parsedLessons.length,
      grades: uniqueGrades,
      unitsCount: uniqueUnits,
    );
  }

  /// Generate a ready-to-fill blank Excel template matching the PC application exactly
  static Uint8List createBlankCurriculumTemplateBytes({
    bool isEnglish = true,
  }) {
    final excel = Excel.createExcel();
    final sheetName = isEnglish ? 'Curriculum' : 'المنهج الدراسي';
    final Sheet sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Exact headers from PC version
    final headerTitles = isEnglish
        ? [
            'Unit Name',
            'Lesson Title',
            'Lesson Description (Optional)',
            'Completed? (Yes/No)',
            'Date (Optional)',
            'Teacher Notes / Homework',
          ]
        : [
            'اسم الوحدة',
            'عنوان الدرس',
            'وصف الدرس (اختياري)',
            'مكتمل؟ (نعم/لا)',
            'التاريخ (اختياري)',
            'ملاحظات المعلم / الواجب',
          ];

    for (int col = 0; col < headerTitles.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headerTitles[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#0D9488'), // Teal 600
        fontColorHex: ExcelColor.white,
      );
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  /// Export curriculum lessons to CSV bytes with UTF-8 BOM for 100% Excel PC compatibility
  static Uint8List exportCurriculumCsv(List<CurriculumLessonModel> lessons, {bool isEnglish = true}) {
    final buffer = StringBuffer();
    // Headers matching PC format exactly
    if (isEnglish) {
      buffer.writeln('Unit Name,Lesson Title,Lesson Description (Optional),Completed? (Yes/No),Date (Optional),Teacher Notes / Homework');
    } else {
      buffer.writeln('اسم الوحدة,عنوان الدرس,وصف الدرس (اختياري),مكتمل؟ (نعم/لا),التاريخ (اختياري),ملاحظات المعلم / الواجب');
    }

    for (final l in lessons) {
      final unit = _escapeCsv(l.unitName);
      final title = _escapeCsv(l.lessonTitle);
      final desc = _escapeCsv(l.objectives);
      final comp = l.isCompleted ? (isEnglish ? 'Yes' : 'نعم') : (isEnglish ? 'No' : 'لا');
      final date = _escapeCsv(l.lessonDate ?? '');
      final notes = _escapeCsv(l.homeworkNotes ?? '');
      buffer.writeln('$unit,$title,$desc,$comp,$date,$notes');
    }

    final utf8Bytes = utf8.encode(buffer.toString());
    // Add UTF-8 BOM so Microsoft Excel opens Arabic without encoding glitches
    final bom = [0xEF, 0xBB, 0xBF];
    return Uint8List.fromList([...bom, ...utf8Bytes]);
  }

  static String _escapeCsv(String val) {
    if (val.contains(',') || val.contains('"') || val.contains('\n') || val.contains('\r')) {
      return '"${val.replaceAll('"', '""')}"';
    }
    return val;
  }

  /// Alias for backward compatibility
  static Uint8List createSampleTemplate({
    String subject = 'ICT & تكنولوجيا المعلومات',
    String grade = 'الصف الأول الإعدادي (Prep 1)',
    bool isEnglish = true,
  }) {
    return createBlankCurriculumTemplateBytes(isEnglish: isEnglish);
  }

  /// Export existing curriculum lessons to Excel bytes with 100% PC compatibility
  static Uint8List exportCurriculum(List<CurriculumLessonModel> lessons, {bool isEnglish = true}) {
    final excel = Excel.createExcel();
    final sheetName = isEnglish ? 'Curriculum' : 'المنهج الدراسي';
    final Sheet sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final headerTitles = isEnglish
        ? [
            'Unit Name',
            'Lesson Title',
            'Lesson Description (Optional)',
            'Completed? (Yes/No)',
            'Date (Optional)',
            'Teacher Notes / Homework',
          ]
        : [
            'اسم الوحدة',
            'عنوان الدرس',
            'وصف الدرس (اختياري)',
            'مكتمل؟ (نعم/لا)',
            'التاريخ (اختياري)',
            'ملاحظات المعلم / الواجب',
          ];

    for (int col = 0; col < headerTitles.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headerTitles[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#0D9488'),
        fontColorHex: ExcelColor.white,
      );
    }

    for (int r = 0; r < lessons.length; r++) {
      final l = lessons[r];
      final rowData = [
        l.unitName,
        l.lessonTitle,
        l.objectives,
        l.isCompleted ? (isEnglish ? 'Yes' : 'نعم') : (isEnglish ? 'No' : 'لا'),
        l.lessonDate ?? '',
        l.homeworkNotes ?? '',
      ];
      for (int c = 0; c < rowData.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        cell.value = TextCellValue(rowData[c]);
      }
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  static String _cellToString(dynamic value) {
    if (value == null) return '';
    if (value is TextCellValue) {
      final t = value.value.text;
      if (t != null && t.isNotEmpty) return t;
      final spanStr = value.value.toString();
      if (spanStr.isNotEmpty && spanStr != 'null') return spanStr;
      return value.toString();
    }
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is DateCellValue) return value.asDateTimeLocal().toIso8601String().substring(0, 10);
    return value.toString();
  }
}
