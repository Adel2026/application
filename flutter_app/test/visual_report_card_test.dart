import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_center/models/student_model.dart';
import 'package:teacher_center/widgets/visual_student_report_card.dart';
import 'package:teacher_center/core/database/database_service.dart';
import 'package:teacher_center/core/whatsapp_service.dart';

void main() {
  const testStudent = StudentModel(
    id: 'test_1',
    fullName: 'أحمد محمد علي',
    stage: 'الإعدادية',
    grade: 'الصف الثالث الإعدادي',
    studentPhone: '01012345678',
    parentPhone: '01098765432',
    groupId: 'grp_1',
    paymentPlan: 'monthly',
  );

  testWidgets('VisualStudentReportCard renders in both Dark and Light mode', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                VisualStudentReportCard(
                  student: testStudent,
                  groupName: 'مجموعة الأوائل',
                  attendancePercent: 100,
                  presentCount: 5,
                  totalSessions: 5,
                  averageScorePercent: 95.0,
                  examScores: [
                    {'title': 'كويز 1', 'score': 10, 'max_score': 10, 'date': '2026-11-18'},
                  ],
                  centerName: 'أكاديمية التفوق',
                  teacherName: 'أ / محمد',
                  isDarkMode: true,
                ),
                VisualStudentReportCard(
                  student: testStudent,
                  groupName: 'مجموعة الأوائل',
                  attendancePercent: 100,
                  presentCount: 5,
                  totalSessions: 5,
                  averageScorePercent: 95.0,
                  examScores: [
                    {'title': 'كويز 1', 'score': 10, 'max_score': 10, 'date': '2026-11-18'},
                  ],
                  centerName: 'أكاديمية التفوق',
                  teacherName: 'أ / محمد',
                  isDarkMode: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('أحمد محمد علي'), findsNWidgets(2));
    expect(find.text('أكاديمية التفوق'), findsNWidgets(2));
  });

  testWidgets('VisualReportCardModalSheet pumps and allows Day/Night toggle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  VisualReportCardModalSheet.show(
                    context,
                    student: testStudent,
                    groupName: 'مجموعة الأوائل',
                    attendancePercent: 100,
                    presentCount: 5,
                    totalSessions: 5,
                    averageScorePercent: 95.0,
                    examScores: const [
                      {'title': 'كويز 1', 'score': 10, 'max_score': 10, 'date': '2026-11-18'},
                    ],
                    centerName: 'سنتر الأستاذ',
                    teacherName: 'أ / محمد',
                    database: DatabaseService(),
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(VisualReportCardModalSheet), findsOneWidget);
    expect(find.text('أحمد محمد علي'), findsOneWidget);

    // Day/Night switch chips exist
    expect(find.text('ليلي'), findsOneWidget);
    expect(find.text('نهاري'), findsOneWidget);

    // Tap Day mode
    await tester.tap(find.text('نهاري'));
    await tester.pumpAndSettle();

    // Verify still mounted and rendered
    expect(find.byType(VisualStudentReportCard), findsOneWidget);
  });

  testWidgets('VisualStudentReportCard renders curriculum breakdown details and half-width metrics', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VisualStudentReportCard(
              student: testStudent,
              groupName: 'مجموعة الأوائل',
              attendancePercent: 92,
              presentCount: 12,
              totalSessions: 13,
              averageScorePercent: 95.0,
              examScores: [
                {'title': 'كويز 1', 'score': 10, 'max_score': 10, 'date': '2026-11-18'},
              ],
              centerName: 'أكاديمية التفوق',
              teacherName: 'أ / محمد',
              lessonTitle: 'قوانين نيوتن للحركة والجاذبية',
              previousHomeworkReview: 'حل تدريبات الفصل الثالث ص 45',
              homeworkText: 'حل المسائل من 1 إلى 15 صفحة 62',
              nextTopic: 'الطاقة والشغل الميكانيكي + اختبار قصير',
              subAttendanceNote: '12 من 13 حصة',
              isDarkMode: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('قوانين نيوتن للحركة والجاذبية'), findsOneWidget);
    expect(find.text('حل تدريبات الفصل الثالث ص 45'), findsOneWidget);
    expect(find.text('حل المسائل من 1 إلى 15 صفحة 62'), findsOneWidget);
    expect(find.text('الطاقة والشغل الميكانيكي + اختبار قصير'), findsOneWidget);
    expect(find.text('12 من 13 حصة'), findsOneWidget);
  });

  testWidgets('When student has no exams, card strictly omits exam metrics and exam breakdown', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VisualStudentReportCard(
              student: testStudent,
              groupName: 'مجموعة الأوائل',
              attendancePercent: 100,
              presentCount: 1,
              totalSessions: 1,
              averageScorePercent: 0.0,
              examScores: [],
              centerName: 'أكاديمية التفوق',
              teacherName: 'أ / محمد',
              lessonTitle: 'مقدمة في الكيمياء العضوية',
              nextQuiz: 'كويز الأسبوع القادم على الهيدروكربونات',
              isDarkMode: true,
            ),
          ),
        ),
      ),
    );

    // Lesson and upcoming quiz should be rendered
    expect(find.text('مقدمة في الكيمياء العضوية'), findsOneWidget);
    expect(find.text('كويز الأسبوع القادم على الهيدروكربونات'), findsOneWidget);

    // No exam metric or exam breakdown header should be present
    expect(find.text('متوسط درجات الاختبارات'), findsNothing);
    expect(find.text('سجل الاختبارات والتقييمات الأخيرة'), findsNothing);
  });

  testWidgets('groupGrade overrides stale student.grade and displays active group grade', (tester) async {
    const studentWithStaleGrade = StudentModel(
      id: 'maram_1',
      fullName: 'مرام أحمد',
      stage: 'الابتدائية',
      grade: 'الصف الرابع الابتدائي',
      studentPhone: '01011111111',
      parentPhone: '01022222222',
      groupId: 'sec1_group',
      paymentPlan: 'monthly',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VisualStudentReportCard(
              student: studentWithStaleGrade,
              groupName: 'Sh-mram',
              groupGrade: 'الصف الأول الثانوي',
              attendancePercent: 100,
              presentCount: 1,
              totalSessions: 1,
              averageScorePercent: 0.0,
              examScores: [],
              centerName: 'أكاديمية التفوق',
              teacherName: 'أ / محمد',
            ),
          ),
        ),
      ),
    );

    expect(find.text('مرام أحمد'), findsOneWidget);
    // Grade in header should be the group's grade 'الصف الأول الثانوي'
    expect(find.textContaining('الصف الأول الثانوي'), findsOneWidget);
    expect(find.textContaining('الصف الرابع الابتدائي'), findsNothing);
  });

  testWidgets('Strict Rule: Financial status is forbidden in daily/weekly reports and allowed only in monthly', (tester) async {
    const studentWithDues = StudentModel(
      id: 'test_finance_1',
      fullName: 'أحمد محمد علي',
      stage: 'الإعدادية',
      grade: 'الصف الثالث الإعدادي',
      studentPhone: '01012345678',
      parentPhone: '01098765432',
      groupId: 'grp_1',
      paymentPlan: 'monthly',
      outstandingAmount: 150.0,
    );

    // 1. Daily / Session report: showFinance = true, but must be suppressed by component
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VisualStudentReportCard(
              student: studentWithDues,
              groupName: 'مجموعة الأوائل',
              reportTitle: 'تقرير متابعة الحصة',
              sessionDate: '2026-11-19',
              showFinance: true,
              attendancePercent: 100,
              presentCount: 1,
              totalSessions: 1,
              averageScorePercent: 0.0,
              examScores: [],
              centerName: 'أكاديمية التفوق',
              teacherName: 'أ / محمد',
            ),
          ),
        ),
      ),
    );

    // Financial section must NOT be rendered
    expect(find.text('الموقف المالي والاشتراك'), findsNothing);

    // 2. Monthly report: showFinance = true, must be rendered
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VisualStudentReportCard(
              student: studentWithDues,
              groupName: 'مجموعة الأوائل',
              reportTitle: 'التقرير الشهري الشامل',
              showFinance: true,
              attendancePercent: 100,
              presentCount: 1,
              totalSessions: 1,
              averageScorePercent: 0.0,
              examScores: [],
              centerName: 'أكاديمية التفوق',
              teacherName: 'أ / محمد',
            ),
          ),
        ),
      ),
    );

    expect(find.text('الموقف المالي والاشتراك'), findsOneWidget);
  });

  testWidgets('Absent student accurately renders absence badge and suppresses default praise', (tester) async {
    const absentStudent = StudentModel(
      id: 'absent_1',
      fullName: 'خالد عبد الله',
      stage: 'الثانوية',
      grade: 'الصف الأول الثانوي',
      studentPhone: '01055555555',
      parentPhone: '01066666666',
      groupId: 'sec1_group',
      paymentPlan: 'monthly',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VisualStudentReportCard(
              student: absentStudent,
              groupName: 'Sh-mram',
              groupGrade: 'الصف الأول الثانوي',
              attendancePercent: 0,
              presentCount: 0,
              totalSessions: 1,
              averageScorePercent: 0.0,
              examScores: [],
              centerName: 'أكاديمية التفوق',
              teacherName: 'أ / محمد',
              sessionDate: '2026-11-19',
              attendanceStatusLabel: 'غائب عن الحصة 🚨',
              homeworkStatusLabel: 'لم يحضر للتسليم (غائب) 🚨',
              recitationRatingLabel: 'لم يُسمّع (غائب) 🚨',
              rankText: 'تنبيه غياب ومتابعة ⚠️',
            ),
          ),
        ),
      ),
    );

    // Name and group rendered
    expect(find.text('خالد عبد الله'), findsOneWidget);

    // Absence badge and status rendered
    expect(find.textContaining('تنبيه غياب ومتابعة'), findsOneWidget);
    expect(find.textContaining('غائب عن الحصة'), findsWidgets);
    expect(find.textContaining('لم يحضر للتسليم'), findsWidgets);

    // Praise tags must NOT be found
    expect(find.text('طالب متميز'), findsNothing);
    expect(find.text('ملتزم جداً 🌟'), findsNothing);
    expect(find.text('واجب كامل ممتاز ✅'), findsNothing);
  });

  testWidgets('VisualReportCardModalSheet supports toggling between Image Only and Image + Text', (tester) async {
    const student = StudentModel(
      id: 'std_test_toggle',
      fullName: 'مريم محمود',
      stage: 'الإعدادية',
      grade: 'الصف الأول الإعدادي',
      studentPhone: '01011122233',
      parentPhone: '01099988877',
      groupId: 'grp_1',
      paymentPlan: 'monthly',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  VisualReportCardModalSheet.show(
                    context,
                    student: student,
                    groupName: 'مجموعة النجوم',
                    attendancePercent: 100,
                    presentCount: 5,
                    totalSessions: 5,
                    averageScorePercent: 90.0,
                    examScores: const [],
                    centerName: 'أكاديمية المستقبل',
                    teacherName: 'أ / أحمد',
                    database: DatabaseService(),
                  );
                },
                child: const Text('OpenSheet'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('OpenSheet'));
    await tester.pumpAndSettle();

    // Verify toggle button exists
    expect(find.textContaining('صورة'), findsWidgets);
    final toggleFinder = find.text('صورة + نص 🖼️📝');
    expect(toggleFinder, findsOneWidget);

    // Tap to switch to image only
    await tester.tap(toggleFinder);
    await tester.pumpAndSettle();

    // Verify it toggled to image only
    expect(find.text('صورة فقط 🖼️'), findsOneWidget);
  });

  test('WhatsAppService handles empty message cleanly when sending image only', () async {
    // When message is empty (image only), appendFooterIfNeeded must not append footer
    final emptyResult = await WhatsAppService.appendFooterIfNeeded(
      DatabaseService(),
      '',
    );
    expect(emptyResult, isEmpty);
  });
}

