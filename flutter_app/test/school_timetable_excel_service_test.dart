import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_center/core/school_timetable_excel_service.dart';
import 'package:teacher_center/models/school_period_model.dart';

void main() {
  test(
    'exports and imports school timetable periods without losing fields',
    () {
      const period = SchoolPeriodModel(
        id: 'period-1',
        dayOfWeek: 'الثلاثاء',
        periodNumber: 4,
        className: 'الصف الثاني',
        subject: 'العلوم',
        startTime: '10:00',
        endTime: '10:45',
        room: 'معمل العلوم',
        notes: 'إحضار الأدوات',
        isRecess: false,
        supervisionDuty: 'إشراف المعمل',
        isReserve: true,
      );

      final bytes = SchoolTimetableExcelService.exportPeriods([period]);
      final workbook = Excel.decodeBytes(bytes);
      final imported = SchoolTimetableExcelService.importPeriods(bytes);

      expect(
        workbook.tables.keys,
        containsAll([
          'الأحد',
          'الإثنين',
          'الثلاثاء',
          'الأربعاء',
          'الخميس',
          'الجمعة',
          'السبت',
        ]),
      );
      expect(workbook.tables['الثلاثاء']!.rows, hasLength(2));
      expect(workbook.tables['الأحد']!.rows, hasLength(1));
      expect(imported, hasLength(1));
      expect(imported.single.dayOfWeek, period.dayOfWeek);
      expect(imported.single.periodNumber, period.periodNumber);
      expect(imported.single.className, period.className);
      expect(imported.single.subject, period.subject);
      expect(imported.single.startTime, period.startTime);
      expect(imported.single.endTime, period.endTime);
      expect(imported.single.room, period.room);
      expect(imported.single.notes, period.notes);
      expect(imported.single.supervisionDuty, period.supervisionDuty);
      expect(imported.single.isRecess, period.isRecess);
      expect(imported.single.isReserve, period.isReserve);
    },
  );

  test('imports the previous single-sheet workbook format', () {
    final excel = Excel.createExcel();
    final sheet = excel['الجدول المدرسي'];
    const headers = ['اليوم', 'رقم الحصة', 'المادة'];
    const values = ['الإثنين', '2', 'اللغة العربية'];

    for (var column = 0; column < headers.length; column++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
          .value = TextCellValue(
        headers[column],
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 1))
          .value = TextCellValue(
        values[column],
      );
    }

    final imported = SchoolTimetableExcelService.importPeriods(
      Uint8List.fromList(excel.encode()!),
    );

    expect(imported, hasLength(1));
    expect(imported.single.dayOfWeek, 'الإثنين');
    expect(imported.single.periodNumber, 2);
    expect(imported.single.subject, 'اللغة العربية');
  });
}
