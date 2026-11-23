import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_center/models/group_model.dart';

void main() {
  test('sorts groups chronologically across AM and PM', () {
    final groups = [
      _group('Evening', '03:30 PM'),
      _group('Morning', '09:15 AM'),
      _group('Noon', '12:00 PM'),
      _group('Midnight', '12:00 AM'),
    ]..sort(GroupModel.compareByStartTime);

    expect(groups.map((group) => group.name), [
      'Midnight',
      'Morning',
      'Noon',
      'Evening',
    ]);
  });

  test('uses the group name to break ties and puts invalid times last', () {
    final groups = [
      _group('Zeta', '10:00 AM'),
      _group('Invalid', 'not set'),
      _group('Alpha', '10:00 AM'),
    ]..sort(GroupModel.compareByStartTime);

    expect(groups.map((group) => group.name), ['Alpha', 'Zeta', 'Invalid']);
  });
}

GroupModel _group(String name, String startTime) => GroupModel(
  id: name,
  name: name,
  stage: '',
  grade: '',
  schedule: '',
  monthlyPrice: 0,
  startTime: startTime,
);
