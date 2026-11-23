import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Check comprehensive grade order from Prim 4 to Sec 3', () {
    String normalizeArabicText(String text) {
      return text
          .toLowerCase()
          .replaceAll(RegExp(r'[أإآ]'), 'ا')
          .replaceAll('ة', 'ه')
          .replaceAll('ى', 'ي')
          .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    }

    const gradeOrderMarkers = [
      // 0: رابعة ابتدائي / Prim 4
      [
        'pri 4', 'pri4', 'prim 4', 'prim4', 'p4', 'primary 4', 'grade 4',
        'الرابع الابتدائي', 'الرابع الابتدائى', 'رابع ابتدائي', 'رابعه ابتدائي', 'رابعة ابتدائي', 'الصف الرابع',
      ],
      // 1: خامسة ابتدائي / Prim 5
      [
        'pri 5', 'pri5', 'prim 5', 'prim5', 'p5', 'primary 5', 'grade 5',
        'الخامس الابتدائي', 'الخامس الابتدائى', 'خامس ابتدائي', 'خامسه ابتدائي', 'خامسة ابتدائي', 'الصف الخامس',
      ],
      // 2: سادسة ابتدائي / Prim 6
      [
        'pri 6', 'pri6', 'prim 6', 'prim6', 'p6', 'primary 6', 'grade 6',
        'السادس الابتدائي', 'السادس الابتدائى', 'سادس ابتدائي', 'سادسه ابتدائي', 'سادسة ابتدائي', 'الصف السادس',
      ],
      // 3: أولى إعدادي / Prep 1
      [
        'prep 1', 'prep1', 'middle 1',
        'الأول الإعدادي', 'الاول الاعدادي', 'الاول الاعدادى', 'اول اعدادي', 'اولى اعدادي', 'أولى إعدادي', 'الصف الأول الإعدادي', 'الصف الاول الاعدادي',
      ],
      // 4: تانية إعدادي / Prep 2
      [
        'prep 2', 'prep2', 'middle 2',
        'الثاني الإعدادي', 'الثاني الاعدادي', 'الثاني الاعدادى', 'ثاني اعدادي', 'تاني اعدادي', 'ثانية إعدادي', 'تانية اعدادي', 'الصف الثاني الإعدادي', 'الصف الثاني الاعدادي',
      ],
      // 5: تالتة إعدادي / Prep 3
      [
        'prep 3', 'prep3', 'middle 3',
        'الثالث الإعدادي', 'الثالث الاعدادي', 'الثالث الاعدادى', 'ثالث اعدادي', 'تالت اعدادي', 'ثالثة إعدادي', 'تالتة اعدادي', 'الصف الثالث الإعدادي', 'الصف الثالث الاعدادي',
      ],
      // 6: أولى ثانوي / Sec 1
      [
        'sec 1', 'sec1', 'secondary 1',
        'الأول الثانوي', 'الاول الثانوي', 'اول ثانوي', 'اولى ثانوي', 'أولى ثانوي', 'الصف الأول الثانوي', 'الصف الاول الثانوي',
      ],
      // 7: تانية ثانوي / Sec 2
      [
        'sec 2', 'sec2', 'secondary 2',
        'الثاني الثانوي', 'ثاني ثانوي', 'تاني ثانوي', 'ثانية ثانوي', 'تانية ثانوي', 'الصف الثاني الثانوي',
      ],
      // 8: تالتة ثانوي / Sec 3
      [
        'sec 3', 'sec3', 'secondary 3',
        'الثالث الثانوي', 'ثالث ثانوي', 'تالت ثانوي', 'ثالثة ثانوي', 'تالتة ثانوي', 'الصف الثالث الثانوي',
      ],
    ];

    int gradeOrder(String grade) {
      final normalized = normalizeArabicText(grade);
      for (var index = 0; index < gradeOrderMarkers.length; index++) {
        if (gradeOrderMarkers[index].any(
          (marker) => normalized.contains(normalizeArabicText(marker)),
        )) {
          return index;
        }
      }
      if (normalized.contains('ابتدائ') || normalized.contains('pri')) return 2;
      if (normalized.contains('اعداد') || normalized.contains('prep')) return 5;
      if (normalized.contains('ثانوي') || normalized.contains('sec')) return 8;
      return gradeOrderMarkers.length + 10;
    }

    final testList = [
      'منهج تانية ثانوي',
      'الصف الاول الثانوي',
      'Prep 3',
      'ثانية اعدادي',
      'منهج الصف الاول الاعدادي (بدون همزة)',
      'سادسة ابتدائي',
      'الخامس الابتدائى',
      'منهج الصف الرابع الابتدائي (Prim 4)',
    ];

    testList.sort((a, b) => gradeOrder(a).compareTo(gradeOrder(b)));

    expect(gradeOrder(testList[0]), 0); // رابعة ابتدائي
    expect(gradeOrder(testList[1]), 1); // خامسة ابتدائي
    expect(gradeOrder(testList[2]), 2); // سادسة ابتدائي
    expect(gradeOrder(testList[3]), 3); // اول اعدادي
    expect(gradeOrder(testList[4]), 4); // تاني اعدادي
    expect(gradeOrder(testList[5]), 5); // تالت اعدادي
    expect(gradeOrder(testList[6]), 6); // اولى ثانوي
    expect(gradeOrder(testList[7]), 7); // تانية ثانوي
  });
}
