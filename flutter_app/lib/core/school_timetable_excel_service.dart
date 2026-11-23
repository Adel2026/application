import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/school_period_model.dart';

class SchoolTimetableExcelService {
  static const List<String> _days = [
    'الأحد',
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
  ];

  static const List<String> _headers = [
    'اليوم',
    'رقم الحصة',
    'بداية الحصة',
    'نهاية الحصة',
    'الفصل',
    'المادة',
    'المكان',
    'ملاحظات',
    'فسحة',
    'إشراف',
    'احتياط',
  ];

  static Uint8List exportPeriods(List<SchoolPeriodModel> periods) {
    final excel = Excel.createExcel();
    final sortedPeriods = [...periods]
      ..sort((a, b) {
        final dayOrder = _dayOrder(a.dayOfWeek) - _dayOrder(b.dayOfWeek);
        return dayOrder != 0 ? dayOrder : a.periodNumber - b.periodNumber;
      });

    for (final day in _days) {
      final sheet = excel[day];
      for (var column = 0; column < _headers.length; column++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
        );
        cell.value = TextCellValue(_headers[column]);
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#0D9488'),
          fontColorHex: ExcelColor.white,
        );
      }

      final dayPeriods = sortedPeriods
          .where((period) => _normalizeDay(period.dayOfWeek) == day)
          .toList();
      for (var row = 0; row < dayPeriods.length; row++) {
        final period = dayPeriods[row];
        final values = [
          day,
          period.periodNumber.toString(),
          period.startTime,
          period.endTime,
          period.className,
          period.subject,
          period.room,
          period.notes,
          period.isRecess ? 'نعم' : 'لا',
          period.supervisionDuty,
          period.isReserve ? 'نعم' : 'لا',
        ];

        for (var column = 0; column < values.length; column++) {
          sheet
              .cell(
                CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: row + 1,
                ),
              )
              .value = TextCellValue(
            values[column],
          );
        }
      }
    }

    excel.setDefaultSheet(_days.first);
    if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
    return Uint8List.fromList(excel.encode() ?? []);
  }

  static List<SchoolPeriodModel> importPeriods(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final periods = <SchoolPeriodModel>[];
    final occupiedSlots = <String>{};
    final idPrefix = DateTime.now().microsecondsSinceEpoch;
    var foundHeader = false;

    for (final entry in excel.tables.entries) {
      final sheetName = entry.key;
      final sheet = entry.value;
      if (sheet.rows.isEmpty) continue;
      final sheetDay = _normalizeDay(sheetName);

      var headerRow = -1;
      final columns = <String, int>{};
      for (
        var rowIndex = 0;
        rowIndex < sheet.rows.length && rowIndex < 10;
        rowIndex++
      ) {
        final candidate = <String, int>{};
        final row = sheet.rows[rowIndex];
        for (var column = 0; column < row.length; column++) {
          final field = _fieldForHeader(_cellToString(row[column]?.value));
          if (field != null) candidate[field] = column;
        }
        if (candidate.containsKey('period') &&
            (candidate.containsKey('day') || sheetDay != null)) {
          headerRow = rowIndex;
          columns.addAll(candidate);
          foundHeader = true;
          break;
        }
      }
      if (headerRow < 0) continue;

      for (
        var rowIndex = headerRow + 1;
        rowIndex < sheet.rows.length;
        rowIndex++
      ) {
        final row = sheet.rows[rowIndex];
        String valueOf(String field) {
          final column = columns[field];
          if (column == null || column >= row.length) return '';
          return _cellToString(row[column]?.value).trim();
        }

        final rawDay = valueOf('day');
        final rawPeriod = valueOf('period');
        if (rawDay.isEmpty && rawPeriod.isEmpty) continue;
        if (rawDay.isEmpty || rawPeriod.isEmpty) {
          throw FormatException(
            'صف ${rowIndex + 1}: اليوم ورقم الحصة مطلوبان.',
          );
        }

        final day = rawDay.isEmpty ? sheetDay : _normalizeDay(rawDay);
        if (day == null) {
          throw FormatException(
            'صف ${rowIndex + 1}: اليوم "$rawDay" غير معروف.',
          );
        }
        if (sheetDay != null && day != sheetDay) {
          throw FormatException(
            'صف ${rowIndex + 1}: اليوم في الشيت لا يطابق اسم الشيت "$sheetName".',
          );
        }

        final periodNumber = _parsePeriodNumber(rawPeriod);
        if (periodNumber == null || periodNumber < 1) {
          throw FormatException(
            'صف ${rowIndex + 1}: رقم الحصة "$rawPeriod" غير صالح.',
          );
        }

        final slotKey = '$day::$periodNumber';
        if (!occupiedSlots.add(slotKey)) {
          throw FormatException(
            'يوجد أكثر من صف للحصة $periodNumber يوم $day.',
          );
        }

        final className = valueOf('class');
        final subject = valueOf('subject');
        final room = valueOf('room');
        final notes = valueOf('notes');
        final supervisionDuty = valueOf('supervision');
        final isRecess = _parseFlag(valueOf('recess'));
        final isReserve = _parseFlag(valueOf('reserve'));
        if (className.isEmpty &&
            subject.isEmpty &&
            room.isEmpty &&
            notes.isEmpty &&
            supervisionDuty.isEmpty &&
            !isRecess &&
            !isReserve) {
          continue;
        }

        periods.add(
          SchoolPeriodModel(
            id: 'school_excel_${idPrefix}_${periods.length}',
            dayOfWeek: day,
            periodNumber: periodNumber,
            className: className,
            subject: subject,
            startTime: valueOf('start').isEmpty ? '08:00' : valueOf('start'),
            endTime: valueOf('end').isEmpty ? '08:45' : valueOf('end'),
            room: room,
            notes: notes,
            isRecess: isRecess,
            supervisionDuty: supervisionDuty,
            isReserve: isReserve,
          ),
        );
      }
    }

    if (!foundHeader) {
      throw const FormatException(
        'لم يتم العثور على أعمدة اليوم ورقم الحصة في ملف Excel.',
      );
    }
    if (periods.isEmpty) {
      throw const FormatException('لم يتم العثور على حصص صالحة في الملف.');
    }
    return periods;
  }

  static String? _fieldForHeader(String header) {
    final value = _normalizeHeader(header);
    if (value.isEmpty) return null;
    if (value.contains('اليوم') ||
        value.contains('dayofweek') ||
        value == 'day') {
      return 'day';
    }
    if (value.contains('رقمالحصة') ||
        value == 'الحصة' ||
        value.contains('period') ||
        value == 'slot') {
      return 'period';
    }
    if (value.contains('بداية') || value.contains('start')) return 'start';
    if (value.contains('نهاية') || value.contains('end')) return 'end';
    if (value.contains('فصل') ||
        value.contains('صف') ||
        value.contains('class') ||
        value.contains('grade')) {
      return 'class';
    }
    if (value.contains('مادة') || value.contains('subject')) return 'subject';
    if (value.contains('مكان') ||
        value.contains('قاعة') ||
        value.contains('room')) {
      return 'room';
    }
    if (value.contains('ملاحظ') || value.contains('notes')) return 'notes';
    if (value.contains('فسحة') ||
        value.contains('استراحة') ||
        value.contains('recess')) {
      return 'recess';
    }
    if (value.contains('إشراف') ||
        value.contains('اشراف') ||
        value.contains('supervision')) {
      return 'supervision';
    }
    if (value.contains('احتياط') || value.contains('reserve')) return 'reserve';
    return null;
  }

  static String _normalizeHeader(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll(RegExp(r'[\s_\-:/()]'), '');

  static String? _normalizeDay(String value) {
    final day = value
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
    if (day.contains('احد') || day.contains('sunday') || day == 'sun') {
      return 'الأحد';
    }
    if (day.contains('اثنين') || day.contains('monday') || day == 'mon') {
      return 'الإثنين';
    }
    if (day.contains('ثلاثاء') || day.contains('tuesday') || day == 'tue') {
      return 'الثلاثاء';
    }
    if (day.contains('اربعاء') || day.contains('wednesday') || day == 'wed') {
      return 'الأربعاء';
    }
    if (day.contains('خميس') || day.contains('thursday') || day == 'thu') {
      return 'الخميس';
    }
    if (day.contains('جمعه') || day.contains('friday') || day == 'fri') {
      return 'الجمعة';
    }
    if (day.contains('سبت') || day.contains('saturday') || day == 'sat') {
      return 'السبت';
    }
    return null;
  }

  static int? _parsePeriodNumber(String value) {
    final direct = int.tryParse(value);
    if (direct != null) return direct;
    final match = RegExp(r'\d+').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  static bool _parseFlag(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'نعم' ||
        normalized == 'yes' ||
        normalized == 'true' ||
        normalized == '1' ||
        normalized == 'x';
  }

  static String _cellToString(dynamic value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text ?? '';
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    return value.toString();
  }

  static int _dayOrder(String day) {
    const days = [
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
    ];
    final index = days.indexOf(day);
    return index < 0 ? days.length : index;
  }
}
