import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_center/models/curriculum_model.dart';

void main() {
  group('GroupCurriculumProgress tests', () {
    test('calculates percentage, remaining lessons and completion status correctly', () {
      const progress = GroupCurriculumProgress(
        groupId: 'g1',
        groupName: 'Group Alpha',
        stage: 'ابتدائي',
        grade: 'الصف الرابع الابتدائي',
        curriculumName: 'منهج ICT - الصف الرابع',
        totalLessons: 20,
        completedLessons: 9,
        progressPercent: 0.45,
        currentLessonTitle: 'Lesson 9',
        nextLessonTitle: 'Lesson 10',
      );

      expect(progress.percentInt, 45);
      expect(progress.remainingLessons, 11);
      expect(progress.hasCurriculum, isTrue);
      expect(progress.isCompleted, isFalse);
    });

    test('handles 100% completion properly', () {
      const progress = GroupCurriculumProgress(
        groupId: 'g2',
        groupName: 'Group Beta',
        stage: 'إعدادي',
        grade: 'الصف الأول الإعدادي',
        curriculumName: 'منهج العلوم',
        totalLessons: 15,
        completedLessons: 15,
        progressPercent: 1.0,
      );

      expect(progress.percentInt, 100);
      expect(progress.remainingLessons, 0);
      expect(progress.isCompleted, isTrue);
    });

    test('handles empty / unbound curriculum properly', () {
      const progress = GroupCurriculumProgress(
        groupId: 'g3',
        groupName: 'Group Gamma',
        stage: 'ثانوي',
        grade: 'الصف الأول الثانوي',
        curriculumName: null,
        totalLessons: 0,
        completedLessons: 0,
        progressPercent: 0.0,
      );

      expect(progress.percentInt, 0);
      expect(progress.remainingLessons, 0);
      expect(progress.hasCurriculum, isFalse);
      expect(progress.isCompleted, isFalse);
    });
  });
}
