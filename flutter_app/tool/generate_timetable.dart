import 'dart:io';
import '../lib/core/school_timetable_excel_service.dart';
import '../lib/models/school_period_model.dart';

void main() async {
  final periods = [
    // --- الأحد (Sunday) ---
    SchoolPeriodModel(
      id: 'sun_2',
      dayOfWeek: 'الأحد',
      periodNumber: 2,
      startTime: '08:25',
      endTime: '09:10',
      className: 'SEC 3',
      subject: 'التربية الدينية',
    ),
    SchoolPeriodModel(
      id: 'sun_3',
      dayOfWeek: 'الأحد',
      periodNumber: 3,
      startTime: '09:10',
      endTime: '09:55',
      className: 'SEC 2',
      subject: 'تخصص',
    ),
    SchoolPeriodModel(
      id: 'sun_4',
      dayOfWeek: 'الأحد',
      periodNumber: 4,
      startTime: '09:55',
      endTime: '10:40',
      className: 'SEC 1A',
      subject: 'programming',
    ),
    SchoolPeriodModel(
      id: 'sun_8',
      dayOfWeek: 'الأحد',
      periodNumber: 8,
      startTime: '01:45',
      endTime: '02:30',
      className: 'SEC 1A',
      subject: 'programming',
    ),

    // --- الإثنين (Monday) ---
    SchoolPeriodModel(
      id: 'mon_2',
      dayOfWeek: 'الإثنين',
      periodNumber: 2,
      startTime: '08:25',
      endTime: '09:10',
      className: 'SEC 2',
      subject: 'تخصص',
    ),
    SchoolPeriodModel(
      id: 'mon_5',
      dayOfWeek: 'الإثنين',
      periodNumber: 5,
      startTime: '11:10',
      endTime: '12:00',
      className: 'Prep 3B',
      subject: 'ICT',
    ),
    SchoolPeriodModel(
      id: 'mon_6',
      dayOfWeek: 'الإثنين',
      periodNumber: 6,
      startTime: '12:00',
      endTime: '12:45',
      className: 'SEC 2',
      subject: 'ثقافه مالية',
    ),
    SchoolPeriodModel(
      id: 'mon_8',
      dayOfWeek: 'الإثنين',
      periodNumber: 8,
      startTime: '01:45',
      endTime: '02:30',
      className: 'SEC 1B',
      subject: 'programming',
    ),

    // --- الثلاثاء (Tuesday) ---
    SchoolPeriodModel(
      id: 'tue_2',
      dayOfWeek: 'الثلاثاء',
      periodNumber: 2,
      startTime: '08:25',
      endTime: '09:10',
      className: 'SEC 1B',
      subject: 'programming',
    ),
    SchoolPeriodModel(
      id: 'tue_3',
      dayOfWeek: 'الثلاثاء',
      periodNumber: 3,
      startTime: '09:10',
      endTime: '09:55',
      className: 'SEC 1A',
      subject: 'التربية الدينية',
    ),
    SchoolPeriodModel(
      id: 'tue_5',
      dayOfWeek: 'الثلاثاء',
      periodNumber: 5,
      startTime: '11:10',
      endTime: '12:00',
      className: 'SEC 2',
      subject: 'تخصص',
      room: 'pc-lab',
    ),
    SchoolPeriodModel(
      id: 'tue_6',
      dayOfWeek: 'الثلاثاء',
      periodNumber: 6,
      startTime: '12:00',
      endTime: '12:45',
      className: 'SEC 2',
      subject: 'تخصص',
      room: 'pc-lab',
    ),
    SchoolPeriodModel(
      id: 'tue_8',
      dayOfWeek: 'الثلاثاء',
      periodNumber: 8,
      startTime: '01:45',
      endTime: '02:30',
      className: 'SEC 1A',
      subject: 'programming',
    ),

    // --- الأربعاء (Wednesday) ---
    SchoolPeriodModel(
      id: 'wed_1',
      dayOfWeek: 'الأربعاء',
      periodNumber: 1,
      startTime: '07:40',
      endTime: '08:25',
      className: 'SEC 1A',
      subject: 'التربية الدينية',
    ),
    SchoolPeriodModel(
      id: 'wed_5',
      dayOfWeek: 'الأربعاء',
      periodNumber: 5,
      startTime: '11:10',
      endTime: '12:00',
      className: 'SEC 2',
      subject: 'ثقافه مالية',
    ),
    SchoolPeriodModel(
      id: 'wed_6',
      dayOfWeek: 'الأربعاء',
      periodNumber: 6,
      startTime: '12:00',
      endTime: '12:45',
      className: 'SEC 2',
      subject: 'تخصص',
    ),
    SchoolPeriodModel(
      id: 'wed_7',
      dayOfWeek: 'الأربعاء',
      periodNumber: 7,
      startTime: '01:00',
      endTime: '01:45',
      className: 'SEC 3',
      subject: 'التربية الدينية',
    ),
    SchoolPeriodModel(
      id: 'wed_8',
      dayOfWeek: 'الأربعاء',
      periodNumber: 8,
      startTime: '01:45',
      endTime: '02:30',
      className: 'SEC 1B',
      subject: 'programming',
    ),

    // --- الخميس (Thursday) ---
    SchoolPeriodModel(
      id: 'thu_2',
      dayOfWeek: 'الخميس',
      periodNumber: 2,
      startTime: '08:25',
      endTime: '09:10',
      className: 'Prep 3A',
      subject: 'ICT',
    ),
    SchoolPeriodModel(
      id: 'thu_3',
      dayOfWeek: 'الخميس',
      periodNumber: 3,
      startTime: '09:10',
      endTime: '09:55',
      className: 'SEC 2',
      subject: 'تخصص',
    ),
    SchoolPeriodModel(
      id: 'thu_5',
      dayOfWeek: 'الخميس',
      periodNumber: 5,
      startTime: '11:10',
      endTime: '12:00',
      className: 'SEC 1B',
      subject: 'programming',
    ),
    SchoolPeriodModel(
      id: 'thu_8',
      dayOfWeek: 'الخميس',
      periodNumber: 8,
      startTime: '01:45',
      endTime: '02:30',
      className: 'SEC 1A',
      subject: 'programming',
    ),
  ];

  final bytes = SchoolTimetableExcelService.exportPeriods(periods);
  final outFile = File('C:/Work/MY APP/edu_academy/school_timetable.xlsx');
  await outFile.writeAsBytes(bytes);
  print('Successfully generated school_timetable.xlsx with ${periods.length} periods.');

  // Test verify import
  final imported = SchoolTimetableExcelService.importPeriods(bytes);
  print('Verified: Imported ${imported.length} periods cleanly!');
}
