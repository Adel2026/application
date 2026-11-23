import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../models/student_model.dart';
import '../models/group_model.dart';
import 'curriculum_excel_service.dart';
import 'database/database_service.dart';

class ExcelImportReport {
  final String title;
  final int totalRows;
  final int successCount;
  final int skippedCount;
  final List<String> createdGroups;
  final List<String> notes;
  final List<String> errors;

  const ExcelImportReport({
    required this.title,
    required this.totalRows,
    required this.successCount,
    this.skippedCount = 0,
    this.createdGroups = const [],
    this.notes = const [],
    this.errors = const [],
  });

  bool get isSuccess => errors.isEmpty && successCount > 0;
}

class ExcelImportService {
  // -------------------------------------------------------------
  // 1. STUDENTS IMPORT
  // -------------------------------------------------------------
  static Future<ExcelImportReport> importStudents({
    required Uint8List bytes,
    required DatabaseService database,
    bool autoCreateGroups = true,
  }) async {
    final List<List<String>> rows = _extractTableRows(bytes);
    if (rows.isEmpty) {
      return const ExcelImportReport(
        title: 'استيراد كشف الطلاب',
        totalRows: 0,
        successCount: 0,
        errors: ['الملف المختار فارغ أو لا يمكن قراءته.'],
      );
    }

    final List<StudentModel> studentsToSave = [];
    final List<String> createdGroupNames = [];
    final List<String> errors = [];

    int totalDataRows = 0;
    int skippedRows = 0;

    // Preload existing groups to link by name
    final existingGroups = await database.getGroups();
    final Map<String, GroupModel> groupMap = {};
    for (final g in existingGroups) {
      groupMap[g.name.trim().toLowerCase()] = g;
    }

    int headerRowIndex = -1;
    int nameCol = -1;
    int studentPhoneCol = -1;
    int parentNameCol = -1;
    int parentPhoneCol = -1;
    int gradeOrStageCol = -1;
    int groupCol = -1;
    int planCol = -1;
    int balanceCol = -1;
    int idCol = -1;

    // Scan first 6 rows to locate header row
    for (int r = 0; r < rows.length && r < 6; r++) {
      final row = rows[r];
      for (int c = 0; c < row.length; c++) {
        final val = row[c].trim();
        if (val.isEmpty) continue;

        if (_matchesAny(val, ['اسم الطالب', 'الاسم بالكامل', 'الاسم', 'student name', 'full name', 'طالب'])) {
          nameCol = c;
        } else if (_matchesAny(val, ['هاتف الطالب', 'موبايل الطالب', 'تليفون الطالب', 'رقم الطالب', 'student phone'])) {
          studentPhoneCol = c;
        } else if (_matchesAny(val, ['اسم ولي الأمر', 'اسم ولي الامر', 'ولي الأمر', 'ولي الامر', 'parent name', 'guardian name'])) {
          parentNameCol = c;
        } else if (_matchesAny(val, ['هاتف ولي الامر', 'هاتف ولي الأمر', 'موبايل ولي الامر', 'موبايل ولي الأمر', 'تليفون ولي الامر', 'parent phone', 'guardian phone'])) {
          parentPhoneCol = c;
        } else if (_matchesAny(val, ['المجموعة الدراسية', 'اسم المجموعة', 'المجموعة', 'الفصل', 'group name', 'group', 'batch'])) {
          groupCol = c;
        } else if (_matchesAny(val, ['المرحلة', 'المرحلة الدراسية', 'المرحلة التعليمية', 'الصف الدراسي', 'الصف', 'grade', 'stage', 'level'])) {
          gradeOrStageCol = c;
        } else if (_matchesAny(val, ['نظام الدفع', 'خطة الدفع', 'الاشتراك', 'نوع الاشتراك', 'payment plan', 'plan'])) {
          planCol = c;
        } else if (_matchesAny(val, ['المبلغ المتبقي', 'المتبقي', 'باقي الحساب', 'دين', 'outstanding', 'balance', 'due'])) {
          balanceCol = c;
        } else if (_matchesAny(val, ['كود الطالب', 'الكود', 'معرف الطالب', 'code', 'student id'])) {
          idCol = c;
        }
      }

      if (nameCol != -1) {
        headerRowIndex = r;
        break;
      }
    }

    // Default to standard PC backup positional layout:
    // م, اسم الطالب, هاتف الطالب, اسم ولي الأمر, هاتف ولي الأمر, المجموعة الدراسية, المرحلة
    if (nameCol == -1) {
      nameCol = 1;
      studentPhoneCol = 2;
      parentNameCol = 3;
      parentPhoneCol = 4;
      groupCol = 5;
      gradeOrStageCol = 6;
      headerRowIndex = 0;
    }

    final startRow = headerRowIndex + 1;
    final startCodeNumber = await database.getNextStudentCodeNumber();

    for (int r = startRow; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      String getCol(int idx) {
        if (idx >= 0 && idx < row.length) {
          return row[idx].trim();
        }
        return '';
      }

      final name = getCol(nameCol);
      if (name.isEmpty) {
        continue; // Skip empty rows
      }

      totalDataRows++;

      final studentPhone = _cleanPhone(getCol(studentPhoneCol));
      final parentName = getCol(parentNameCol);
      final parentPhoneRaw = _cleanPhone(getCol(parentPhoneCol));
      final parentPhone = parentPhoneRaw.isNotEmpty ? parentPhoneRaw : studentPhone;

      final gradeOrStage = getCol(gradeOrStageCol);
      final groupName = getCol(groupCol);
      final planRaw = getCol(planCol);
      final balanceRaw = getCol(balanceCol);
      final idRaw = getCol(idCol);

      final String grade;
      final String stage;
      if (gradeOrStage.contains('الصف') || gradeOrStage.contains('Sec') || gradeOrStage.contains('Prep') || gradeOrStage.contains('Pri')) {
        grade = gradeOrStage;
        stage = _inferStage(gradeOrStage);
      } else if (gradeOrStage.contains('ثانوي') || gradeOrStage.contains('إعدادي') || gradeOrStage.contains('ابتدائي')) {
        stage = gradeOrStage;
        grade = _defaultGradeForStage(gradeOrStage);
      } else if (gradeOrStage.isNotEmpty) {
        grade = gradeOrStage;
        stage = _inferStage(gradeOrStage);
      } else {
        grade = 'الصف الأول الثانوي (Sec 1)';
        stage = 'المرحلة الثانوية';
      }

      final paymentPlan = planRaw.isNotEmpty ? planRaw : 'شهري';
      final balance = double.tryParse(balanceRaw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;

      // Group resolution
      String? targetGroupId;
      if (groupName.isNotEmpty && groupName != 'بدون مجموعة') {
        final normName = groupName.trim().toLowerCase();
        if (groupMap.containsKey(normName)) {
          targetGroupId = groupMap[normName]!.id;
        } else if (autoCreateGroups) {
          final newGroupId = 'GRP_${DateTime.now().millisecondsSinceEpoch}_${groupMap.length + 1}';
          final newGroup = GroupModel(
            id: newGroupId,
            name: groupName.trim(),
            stage: stage,
            grade: grade,
            schedule: 'مواعيد محددة لاحقاً',
            monthlyPrice: 0,
          );
          await database.saveGroup(newGroup);
          groupMap[normName] = newGroup;
          createdGroupNames.add(groupName.trim());
          targetGroupId = newGroupId;
        }
      }

      final studentId = idRaw.isNotEmpty
          ? idRaw
          : 'Std-${startCodeNumber + studentsToSave.length}';

      studentsToSave.add(
        StudentModel(
          id: studentId,
          fullName: name,
          stage: stage,
          grade: grade,
          studentPhone: studentPhone,
          parentPhone: parentPhone,
          parentName: parentName.isNotEmpty ? parentName : 'ولي أمر الطالب',
          groupId: targetGroupId,
          paymentPlan: paymentPlan,
          outstandingAmount: balance,
        ),
      );
    }

    if (studentsToSave.isNotEmpty) {
      await database.saveStudentsBatch(studentsToSave);
    }

    return ExcelImportReport(
      title: 'استيراد كشف الطلاب',
      totalRows: totalDataRows,
      successCount: studentsToSave.length,
      skippedCount: skippedRows,
      createdGroups: createdGroupNames,
      notes: [
        if (createdGroupNames.isNotEmpty)
          'تم إنشاء ${createdGroupNames.length} مجموعة جديدة تلقائياً وربط الطلاب بها.',
      ],
      errors: errors,
    );
  }

  // -------------------------------------------------------------
  // 2. GROUPS IMPORT
  // -------------------------------------------------------------
  static Future<ExcelImportReport> importGroups({
    required Uint8List bytes,
    required DatabaseService database,
  }) async {
    final List<List<String>> rows = _extractTableRows(bytes);
    if (rows.isEmpty) {
      return const ExcelImportReport(
        title: 'استيراد المجموعات والفصول',
        totalRows: 0,
        successCount: 0,
        errors: ['الملف المختار فارغ أو لا يمكن قراءته.'],
      );
    }

    final List<GroupModel> groupsToSave = [];
    final List<String> errors = [];
    int totalDataRows = 0;

    // Preload existing groups to allow upserting/updating
    final existingGroups = await database.getGroups();
    final Map<String, GroupModel> existingByName = {};
    for (final g in existingGroups) {
      existingByName[g.name.trim().toLowerCase()] = g;
    }

    int headerRowIndex = -1;
    int nameCol = -1;
    int subjectCol = -1;
    int stageCol = -1;
    int gradeCol = -1;
    int locTypeCol = -1;
    int roomCol = -1;
    int daysCol = -1;
    int startTimeCol = -1;
    int endTimeCol = -1;
    int billingCol = -1;
    int sessionPriceCol = -1;
    int monthlyPriceCol = -1;
    int maxCol = -1;
    int colorCol = -1;
    int notesCol = -1;
    int scheduleCol = -1;

    for (int r = 0; r < rows.length && r < 6; r++) {
      final row = rows[r];
      for (int c = 0; c < row.length; c++) {
        final val = row[c].trim();
        if (val.isEmpty) continue;

        if (_matchesAny(val, ['اسم المجموعة', 'المجموعة', 'اسم الفصل', 'group name'])) {
          nameCol = c;
        } else if (_matchesAny(val, ['المادة', 'المادة الدراسية', 'subject'])) {
          subjectCol = c;
        } else if (_matchesAny(val, ['المرحلة التعليمية', 'المرحلة', 'stage', 'level'])) {
          stageCol = c;
        } else if (_matchesAny(val, ['الصف الدراسي', 'الصف', 'grade', 'year'])) {
          gradeCol = c;
        } else if (_matchesAny(val, ['المكان', 'نوع المكان', 'location type', 'location'])) {
          locTypeCol = c;
        } else if (_matchesAny(val, ['اسم المكان', 'القاعة', 'الغرفة', 'room', 'hall'])) {
          roomCol = c;
        } else if (_matchesAny(val, ['أيام الأسبوع', 'ايام الاسبوع', 'الأيام', 'الايام', 'weekdays', 'days'])) {
          daysCol = c;
        } else if (_matchesAny(val, ['وقت البداية', 'البداية', 'start time', 'start'])) {
          startTimeCol = c;
        } else if (_matchesAny(val, ['وقت النهاية', 'النهاية', 'end time', 'end'])) {
          endTimeCol = c;
        } else if (_matchesAny(val, ['نظام المحاسبة', 'نوع المحاسبة', 'طريقة الدفع', 'billing type', 'billing'])) {
          billingCol = c;
        } else if (_matchesAny(val, ['سعر الحصة', 'سعر الجلسة', 'session price'])) {
          sessionPriceCol = c;
        } else if (_matchesAny(val, ['الاشتراك الشهري', 'سعر الشهري', 'المصروفات', 'monthly price', 'price'])) {
          monthlyPriceCol = c;
        } else if (_matchesAny(val, ['السعة القصوى', 'الحد الأقصى', 'السعة', 'سعة الطلاب', 'max students', 'capacity'])) {
          maxCol = c;
        } else if (_matchesAny(val, ['اللون', 'كود اللون', 'color'])) {
          colorCol = c;
        } else if (_matchesAny(val, ['ملاحظات', 'notes', 'description'])) {
          notesCol = c;
        } else if (_matchesAny(val, ['مواعيد الحصص', 'المواعيد', 'schedule'])) {
          scheduleCol = c;
        }
      }

      if (nameCol != -1) {
        headerRowIndex = r;
        break;
      }
    }

    // Default to positional 15-column layout if header not detected:
    // اسم المجموعة,المادة,المرحلة,الصف الدراسي,المكان,اسم المكان,أيام الأسبوع,وقت البداية,وقت النهاية,نظام المحاسبة,سعر الحصة,الاشتراك الشهري,السعة القصوى,اللون,ملاحظات
    if (nameCol == -1) {
      nameCol = 0;
      subjectCol = 1;
      stageCol = 2;
      gradeCol = 3;
      locTypeCol = 4;
      roomCol = 5;
      daysCol = 6;
      startTimeCol = 7;
      endTimeCol = 8;
      billingCol = 9;
      sessionPriceCol = 10;
      monthlyPriceCol = 11;
      maxCol = 12;
      colorCol = 13;
      notesCol = 14;
      headerRowIndex = 0;
    }

    final startRow = headerRowIndex + 1;

    for (int r = startRow; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      String getCol(int idx) {
        if (idx >= 0 && idx < row.length) {
          return row[idx].trim();
        }
        return '';
      }

      final name = getCol(nameCol);
      if (name.isEmpty) continue;

      totalDataRows++;

      final subjectRaw = getCol(subjectCol);
      final stageRaw = getCol(stageCol);
      final gradeRaw = getCol(gradeCol);
      final locTypeRaw = getCol(locTypeCol);
      final roomRaw = getCol(roomCol);
      final daysRaw = getCol(daysCol);
      final startTimeRaw = getCol(startTimeCol);
      final endTimeRaw = getCol(endTimeCol);
      final billingRaw = getCol(billingCol);
      final sessionPriceRaw = getCol(sessionPriceCol);
      final monthlyPriceRaw = getCol(monthlyPriceCol);
      final maxRaw = getCol(maxCol);
      final colorRaw = getCol(colorCol);
      final notesRaw = getCol(notesCol);
      final scheduleRaw = getCol(scheduleCol);

      final grade = gradeRaw.isNotEmpty ? gradeRaw : 'الصف الأول الثانوي (Sec 1)';
      final stage = _codeToStage(stageRaw.isNotEmpty ? stageRaw : _inferStage(grade));
      final subject = subjectRaw.isNotEmpty ? subjectRaw : 'عام';
      final locationType = _codeToLocation(locTypeRaw);
      final days = _numbersToDays(daysRaw);
      final startTime = startTimeRaw.isNotEmpty ? startTimeRaw : '15:00';
      final endTime = endTimeRaw.isNotEmpty ? endTimeRaw : '16:00';

      final schedule = scheduleRaw.isNotEmpty
          ? scheduleRaw
          : _buildSchedule(days, startTime, endTime);

      final priceSession = double.tryParse(sessionPriceRaw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
      final priceMonthly = double.tryParse(monthlyPriceRaw.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
      final price = priceMonthly > 0 ? priceMonthly : priceSession;

      final maxStudents = int.tryParse(maxRaw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 30;
      final billingType = (billingRaw.contains('session') || billingRaw.contains('حصة'))
          ? 'per_session'
          : 'monthly';

      final colorValue = _parseColorHex(colorRaw);

      final normName = name.trim().toLowerCase();
      final existing = existingByName[normName];
      final groupId = existing?.id ?? 'GRP_${DateTime.now().millisecondsSinceEpoch}_${groupsToSave.length + 1}';

      groupsToSave.add(
        GroupModel(
          id: groupId,
          name: name.trim(),
          stage: stage,
          grade: grade,
          schedule: schedule,
          monthlyPrice: price,
          room: roomRaw,
          maxStudents: maxStudents,
          billingType: billingType,
          colorValue: colorValue,
          notes: notesRaw,
          subject: subject,
          locationType: locationType,
          startTime: startTime,
          endTime: endTime,
          days: days,
        ),
      );
    }

    if (groupsToSave.isNotEmpty) {
      await database.saveGroupsBatch(groupsToSave);
    }

    return ExcelImportReport(
      title: 'استيراد المجموعات والفصول',
      totalRows: totalDataRows,
      successCount: groupsToSave.length,
      errors: errors,
    );
  }

  // -------------------------------------------------------------
  // 3. CURRICULA IMPORT
  // -------------------------------------------------------------
  static Future<ExcelImportReport> importCurriculum({
    required Uint8List bytes,
    required DatabaseService database,
    bool replaceAll = false,
    String? targetGrade,
    String defaultSubject = 'عام',
  }) async {
    final lessons = CurriculumExcelService.parseExcelBytes(
      bytes: bytes,
      defaultSubject: defaultSubject,
      defaultGrade: targetGrade ?? 'الصف الأول الثانوي',
    );

    if (lessons.isEmpty) {
      return const ExcelImportReport(
        title: 'استيراد المناهج والدروس',
        totalRows: 0,
        successCount: 0,
        errors: ['لم يتم العثور على أية دروس أو وحدات صالحة في ملف الإكسل المختار.'],
      );
    }

    await database.saveCurriculumLessonsBatch(
      lessons,
      replaceAll: replaceAll,
      grade: targetGrade,
    );

    final uniqueUnits = lessons.map((l) => l.unitName).toSet().length;

    return ExcelImportReport(
      title: 'استيراد المناهج والدروس',
      totalRows: lessons.length,
      successCount: lessons.length,
      notes: [
        'تم استيراد $uniqueUnits وحدة دراسية بإجمالي ${lessons.length} درس بنجاح.',
      ],
    );
  }

  // -------------------------------------------------------------
  // 4. TEMPLATE GENERATION
  // -------------------------------------------------------------

  /// Creates a ready-to-fill sample Excel template for Students matching PC backup layout:
  /// م,اسم الطالب,هاتف الطالب,اسم ولي الأمر,هاتف ولي الأمر,المجموعة الدراسية,المرحلة
  static Uint8List createStudentsTemplateBytes() {
    final excel = Excel.createExcel();
    final sheet = excel['جهات اتصال الطلاب'];
    excel.setDefaultSheet('جهات اتصال الطلاب');
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final headers = [
      'م',
      'اسم الطالب',
      'هاتف الطالب',
      'اسم ولي الأمر',
      'هاتف ولي الأمر',
      'المجموعة الدراسية',
      'المرحلة',
    ];

    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1E3A8A'),
        fontColorHex: ExcelColor.white,
      );
    }

    final sampleRows = [
      ['1', 'أحمد حسام', '01019140354', 'ولي أمر الطالب', '01225261489', 'Sh-Prep1', 'الصف الأول الإعدادي (Prep 1)'],
      ['2', 'سارة مصطفى', '01234567890', 'مصطفى كمال', '01099887766', 'Sec1-yousef', 'الصف الأول الثانوي (Sec 1)'],
      ['3', 'يوسف خالد', '01511223344', 'خالد حسن', '01288776655', 'Sec2-Math', 'الصف الثاني الثانوي (Sec 2)'],
    ];

    for (int r = 0; r < sampleRows.length; r++) {
      final row = sampleRows[r];
      for (int c = 0; c < row.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        cell.value = TextCellValue(row[c]);
      }
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  /// Creates a ready-to-fill sample Excel template for Groups matching PC backup layout:
  /// اسم المجموعة,المادة,المرحلة,الصف الدراسي,المكان,اسم المكان,أيام الأسبوع,وقت البداية,وقت النهاية,نظام المحاسبة,سعر الحصة,الاشتراك الشهري,السعة القصوى,اللون,ملاحظات
  static Uint8List createGroupsTemplateBytes() {
    final excel = Excel.createExcel();
    final sheet = excel['المجموعات'];
    excel.setDefaultSheet('المجموعات');
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final headers = [
      'اسم المجموعة',
      'المادة',
      'المرحلة',
      'الصف الدراسي',
      'المكان',
      'اسم المكان',
      'أيام الأسبوع',
      'وقت البداية',
      'وقت النهاية',
      'نظام المحاسبة',
      'سعر الحصة',
      'الاشتراك الشهري',
      'السعة القصوى',
      'اللون',
      'ملاحظات',
    ];

    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#047857'),
        fontColorHex: ExcelColor.white,
      );
    }

    final sampleRows = [
      ['Sec1-yousef', 'برمجة', 'secondary', 'الصف الأول الثانوي (Sec 1)', 'home', 'عذبه مسلم', '1, 4', '15:00', '16:00', 'per_session', '200', '200', '1', '#2563eb', ''],
      ['Sh-Prep1', 'تكنولوجيا', 'preparatory', 'الصف الأول الإعدادي (Prep 1)', 'center', 'قاعة النور', '2, 5', '16:30', '18:00', 'monthly', '250', '250', '25', '#10b981', 'مجموعة المتفوقين'],
    ];

    for (int r = 0; r < sampleRows.length; r++) {
      final row = sampleRows[r];
      for (int c = 0; c < row.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        cell.value = TextCellValue(row[c]);
      }
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  /// Creates a ready-to-fill sample Excel template for Curricula
  static Uint8List createCurriculumTemplateBytes() {
    return CurriculumExcelService.createSampleTemplate();
  }

  // -------------------------------------------------------------
  // 5. EXPORT ACTUAL DATA TO EXCEL
  // -------------------------------------------------------------
  /// Exports active students matching PC layout:
  /// م,اسم الطالب,هاتف الطالب,اسم ولي الأمر,هاتف ولي الأمر,المجموعة الدراسية,المرحلة
  static Uint8List exportStudentsToExcelBytes({
    required List<StudentModel> students,
    Map<String, String> groupNames = const {},
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['جهات اتصال الطلاب'];
    excel.setDefaultSheet('جهات اتصال الطلاب');
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final headers = [
      'م',
      'اسم الطالب',
      'هاتف الطالب',
      'اسم ولي الأمر',
      'هاتف ولي الأمر',
      'المجموعة الدراسية',
      'المرحلة',
    ];

    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#0D9488'),
        fontColorHex: ExcelColor.white,
      );
    }

    for (int r = 0; r < students.length; r++) {
      final s = students[r];
      final groupName = (s.groupId != null && groupNames.containsKey(s.groupId))
          ? groupNames[s.groupId]!
          : (s.groupId ?? 'بدون مجموعة');

      final gradeOrStage = s.grade.isNotEmpty ? s.grade : s.stage;
      final parentName = s.parentName.isNotEmpty ? s.parentName : 'ولي أمر الطالب';

      final rowData = [
        (r + 1).toString(),
        s.fullName,
        s.studentPhone,
        parentName,
        s.parentPhone,
        groupName,
        gradeOrStage,
      ];

      for (int c = 0; c < rowData.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        cell.value = TextCellValue(rowData[c]);
      }
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  /// Exports active groups matching PC layout:
  /// اسم المجموعة,المادة,المرحلة,الصف الدراسي,المكان,اسم المكان,أيام الأسبوع,وقت البداية,وقت النهاية,نظام المحاسبة,سعر الحصة,الاشتراك الشهري,السعة القصوى,اللون,ملاحظات
  static Uint8List exportGroupsToExcelBytes({
    required List<GroupModel> groups,
    Map<String, int> studentCounts = const {},
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['المجموعات'];
    excel.setDefaultSheet('المجموعات');
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final headers = [
      'اسم المجموعة',
      'المادة',
      'المرحلة',
      'الصف الدراسي',
      'المكان',
      'اسم المكان',
      'أيام الأسبوع',
      'وقت البداية',
      'وقت النهاية',
      'نظام المحاسبة',
      'سعر الحصة',
      'الاشتراك الشهري',
      'السعة القصوى',
      'اللون',
      'ملاحظات',
    ];

    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#107C41'),
        fontColorHex: ExcelColor.white,
      );
    }

    for (int r = 0; r < groups.length; r++) {
      final g = groups[r];
      final subject = g.subject.isNotEmpty ? g.subject : 'عام';
      final stageCode = _stageToCode(g.stage);
      final locCode = _locationToCode(g.locationType);
      final daysCode = _daysToNumbers(g.days);
      final priceStr = g.monthlyPrice.toInt().toString();
      final colorHex = '#${(g.colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

      final rowData = [
        g.name,
        subject,
        stageCode,
        g.grade,
        locCode,
        g.room,
        daysCode,
        g.startTime,
        g.endTime,
        g.billingType,
        priceStr,
        priceStr,
        g.maxStudents.toString(),
        colorHex,
        g.notes,
      ];

      for (int c = 0; c < rowData.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        cell.value = TextCellValue(rowData[c]);
      }
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? []);
  }

  // -------------------------------------------------------------
  // UNIVERSAL TABLE PARSER (EXCEL & CSV)
  // -------------------------------------------------------------
  static List<List<String>> _extractTableRows(Uint8List bytes) {
    if (bytes.isEmpty) return [];

    // Check if zip archive (Excel .xlsx starts with PK = 0x50, 0x4B)
    if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      try {
        final excel = Excel.decodeBytes(bytes);
        for (final table in excel.tables.keys) {
          final sheet = excel.tables[table];
          if (sheet != null && sheet.rows.isNotEmpty) {
            final List<List<String>> result = [];
            for (final r in sheet.rows) {
              final rowCells = r.map((c) => _cleanText(c?.value)).toList();
              // Check if not completely empty
              if (rowCells.any((element) => element.isNotEmpty)) {
                result.add(rowCells);
              }
            }
            if (result.isNotEmpty) return result;
          }
        }
      } catch (_) {
        // Fall back to CSV if Excel decoding fails
      }
    }

    // CSV fallback
    return _parseCsv(bytes);
  }

  static List<List<String>> _parseCsv(Uint8List bytes) {
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes);
    }

    // Strip BOM if present
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }

    final List<List<String>> rows = [];
    final lines = content.split(RegExp(r'\r\n|\n|\r'));

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final List<String> cells = [];
      final sb = StringBuffer();
      bool inQuotes = false;

      for (int i = 0; i < line.length; i++) {
        final char = line[i];
        if (char == '"') {
          if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            inQuotes = !inQuotes;
          }
        } else if (char == ',' && !inQuotes) {
          cells.add(sb.toString().trim());
          sb.clear();
        } else {
          sb.write(char);
        }
      }
      cells.add(sb.toString().trim());

      if (cells.any((c) => c.isNotEmpty)) {
        rows.add(cells);
      }
    }

    return rows;
  }

  // -------------------------------------------------------------
  // HELPERS
  // -------------------------------------------------------------
  static String _cleanText(dynamic value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text?.trim() ?? '';
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) {
      final d = value.value;
      if (d == d.roundToDouble()) {
        return d.toInt().toString();
      }
      return d.toString();
    }
    if (value is DateCellValue) return value.asDateTimeLocal().toIso8601String().substring(0, 10);
    return value.toString().trim();
  }

  static String _cleanPhone(String phone) {
    if (phone.isEmpty) return '';
    var cleaned = phone.trim();
    if (cleaned.endsWith('.0')) {
      cleaned = cleaned.substring(0, cleaned.length - 2);
    }
    cleaned = cleaned.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.length == 10 && (cleaned.startsWith('10') || cleaned.startsWith('11') || cleaned.startsWith('12') || cleaned.startsWith('15'))) {
      cleaned = '0$cleaned';
    }
    return cleaned;
  }

  static bool _matchesAny(String text, List<String> patterns) {
    final normalized = text.toLowerCase().trim();
    for (final p in patterns) {
      if (normalized == p.toLowerCase() || normalized.contains(p.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  static String _inferStage(String grade) {
    final g = grade.trim().toLowerCase();
    if (g.contains('ثانوي') || g.contains('ثانوية') || g.contains('sec')) {
      return 'المرحلة الثانوية';
    } else if (g.contains('إعدادي') || g.contains('اعدادي') || g.contains('prep')) {
      return 'المرحلة الإعدادية';
    } else if (g.contains('ابتدائي') || g.contains('primary') || g.contains('pri')) {
      return 'المرحلة الابتدائية';
    } else if (g.contains('جامع') || g.contains('كلي')) {
      return 'المرحلة الجامعية';
    }
    return 'المرحلة الثانوية';
  }

  static String _defaultGradeForStage(String stage) {
    if (stage.contains('ثانوي')) return 'الصف الأول الثانوي (Sec 1)';
    if (stage.contains('إعدادي') || stage.contains('اعدادي')) return 'الصف الأول الإعدادي (Prep 1)';
    if (stage.contains('ابتدائي')) return 'الصف السادس الابتدائي (Pri 6)';
    return 'الصف الأول الثانوي (Sec 1)';
  }

  static String _stageToCode(String stage) {
    final s = stage.trim().toLowerCase();
    if (s.contains('ثانوي') || s == 'secondary') return 'secondary';
    if (s.contains('إعدادي') || s.contains('اعدادي') || s == 'preparatory') return 'preparatory';
    if (s.contains('ابتدائي') || s == 'primary') return 'primary';
    return stage;
  }

  static String _codeToStage(String code) {
    final c = code.trim().toLowerCase();
    if (c == 'secondary' || c.contains('ثانوي')) return 'المرحلة الثانوية';
    if (c == 'preparatory' || c.contains('إعدادي') || c.contains('اعدادي')) return 'المرحلة الإعدادية';
    if (c == 'primary' || c.contains('ابتدائي')) return 'المرحلة الابتدائية';
    return code;
  }

  static String _locationToCode(String loc) {
    final l = loc.trim().toLowerCase();
    if (l == 'home' || l.contains('منزل')) return 'home';
    if (l == 'center' || l.contains('سنتر') || l.contains('قاعة')) return 'center';
    if (l == 'online' || l.contains('أونلاين') || l.contains('عن بعد')) return 'online';
    return loc;
  }

  static String _codeToLocation(String code) {
    final c = code.trim().toLowerCase();
    if (c == 'home' || c.contains('منزل')) return 'منزل المعلم أو الطالب';
    if (c == 'center' || c.contains('سنتر')) return 'السنتر / القاعة';
    if (c == 'online' || c.contains('أونلاين')) return 'أونلاين (عن بعد)';
    return code.isNotEmpty ? code : 'منزل المعلم أو الطالب';
  }

  static String _daysToNumbers(String days) {
    if (days.isEmpty) return '';
    // If it already contains numbers like "1, 4", preserve them
    if (RegExp(r'\d').hasMatch(days)) {
      return days.trim();
    }

    final Map<String, String> dayToNum = {
      'الاثنين': '1',
      'الثلاثاء': '2',
      'الأربعاء': '3',
      'الخميس': '4',
      'الجمعة': '5',
      'السبت': '6',
      'الأحد': '7',
    };

    final List<String> nums = [];
    for (final entry in dayToNum.entries) {
      if (days.contains(entry.key)) {
        nums.add(entry.value);
      }
    }

    return nums.isNotEmpty ? nums.join(', ') : days;
  }

  static String _numbersToDays(String input) {
    if (input.isEmpty) return '';
    // If it has Arabic text already, return as is
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(input)) {
      return input.trim();
    }

    final Map<String, String> numToDay = {
      '1': 'الاثنين',
      '2': 'الثلاثاء',
      '3': 'الأربعاء',
      '4': 'الخميس',
      '5': 'الجمعة',
      '6': 'السبت',
      '7': 'الأحد',
      '0': 'الأحد',
    };

    final parts = input.split(RegExp(r'[, -]+')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    final List<String> resolved = [];
    for (final p in parts) {
      if (numToDay.containsKey(p)) {
        resolved.add(numToDay[p]!);
      }
    }

    return resolved.isNotEmpty ? resolved.join(', ') : input;
  }

  static String _buildSchedule(String days, String startTime, String endTime) {
    final d = days.isNotEmpty ? days : 'مواعيد محددة';
    final s = startTime.isNotEmpty ? startTime : '';
    final e = endTime.isNotEmpty ? endTime : '';
    if (s.isNotEmpty && e.isNotEmpty) {
      return '$d ($s - $e)';
    } else if (s.isNotEmpty) {
      return '$d ($s)';
    }
    return d;
  }

  static int _parseColorHex(String hex) {
    if (hex.isEmpty) return 0xFF2563EB;
    var clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      clean = 'FF$clean';
    }
    final val = int.tryParse(clean, radix: 16);
    return val ?? 0xFF2563EB;
  }
}
