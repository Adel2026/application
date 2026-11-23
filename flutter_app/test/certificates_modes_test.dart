import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_center/models/certificate_element_config.dart';
import 'package:teacher_center/screens/certificates_screen.dart';

void main() {
  group('Certificates Screen Modes & Data Tests', () {
    test('CertificateMode enum values check', () {
      expect(CertificateMode.values.length, 3);
      expect(CertificateMode.values, contains(CertificateMode.examRankings));
      expect(CertificateMode.values, contains(CertificateMode.groupStudent));
      expect(CertificateMode.values, contains(CertificateMode.customFree));
    });

    test('CertificateStyle and RankTier values check', () {
      expect(CertificateStyle.values.length, 3);
      expect(CertificateStyle.values, contains(CertificateStyle.royal));
      expect(CertificateStyle.values, contains(CertificateStyle.classic));
      expect(CertificateStyle.values, contains(CertificateStyle.natureWood));

      expect(RankTier.values.length, 4);
    });

    test('CertificateElementType enum includes logo and seal', () {
      expect(CertificateElementType.values, contains(CertificateElementType.logo));
      expect(CertificateElementType.values, contains(CertificateElementType.seal));
      expect(CertificateElementType.seal.displayNameAr, contains('الختم'));
      expect(CertificateElementType.seal.displayNameEn, contains('Wax Seal'));
      expect(CertificateElementType.seal.isTextElement, isFalse);
    });

    test('CertificateStudentData model structure and defaults', () {
      const student = CertificateStudentData(
        name: 'أحمد محمد علي عبد الرحمن مصطفى النجار',
        score: '20 / 20',
        percent: '100%',
        rank: 1,
        rankText: '🥇 المركز الأول (صدارة المجموعة الموحدة)',
        groupName: 'ثانوية عامة - دفعة الأوائل والعلماء المتفوقين',
        parentPhone: '01012345678',
      );

      expect(student.name, contains('أحمد'));
      expect(student.score, '20 / 20');
      expect(student.percent, '100%');
      expect(student.rank, 1);
      expect(student.rankText, contains('المركز الأول'));
      expect(student.groupName, contains('دفعة الأوائل'));
      expect(student.parentPhone, '01012345678');
    });

    test('CertificateStudentData default parentPhone is empty', () {
      const student = CertificateStudentData(
        name: 'سارة إبراهيم',
        score: '19 / 20',
        percent: '95%',
        rank: 2,
        rankText: '🥈 المركز الثاني',
        groupName: 'الصف الثالث الإعدادي',
      );

      expect(student.parentPhone, '');
      expect(student.rank, 2);
    });
  });

  group('CircularImageCropper Constraints and Precision Tests', () {
    testWidgets('InteractiveViewer with constrained: false preserves exact dimensions for circular crop', (tester) async {
      final controller = TransformationController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: InteractiveViewer(
                transformationController: controller,
                alignment: Alignment.topLeft,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Container(
                  key: const ValueKey('unconstrained_crop_canvas'),
                  width: 200,
                  height: 200,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      );

      final renderBox = tester.renderObject<RenderBox>(find.byKey(const ValueKey('unconstrained_crop_canvas')));
      expect(renderBox.size, equals(const Size(200.0, 200.0)));
    });
  });
}
