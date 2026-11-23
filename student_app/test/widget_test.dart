import 'package:flutter_test/flutter_test.dart';
import 'package:edu_academy_student/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const EduAcademyStudentApp());
  });
}
