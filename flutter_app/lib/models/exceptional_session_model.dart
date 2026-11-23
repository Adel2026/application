class ExceptionalSessionModel {
  final String id;
  final String groupId;
  final String groupName;
  final String title;
  final String reason; // 'teacher_makeup', 'student_makeup', 'curriculum', 'revision', 'custom'
  final String scale; // 'single', 'double'
  final String date; // YYYY-MM-DD
  final String day; // 'السبت', 'الأحد', ...
  final String time; // e.g. '04:00 PM'
  final bool isRecurring;
  final int recurringWeeks;
  final String notes;
  final String status; // 'active', 'completed', 'cancelled'
  final String createdAt;

  const ExceptionalSessionModel({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.title,
    required this.reason,
    this.scale = 'single',
    required this.date,
    required this.day,
    required this.time,
    this.isRecurring = false,
    this.recurringWeeks = 1,
    this.notes = '',
    this.status = 'active',
    required this.createdAt,
  });

  String get reasonLabel {
    switch (reason) {
      case 'teacher_makeup':
        return 'تعويض (إلغاء المدرس)';
      case 'student_makeup':
        return 'تعويض (غياب الطالب)';
      case 'curriculum':
        return 'استكمال المنهج';
      case 'revision':
        return 'مراجعة ليلة الامتحان';
      default:
        return 'حصة استثنائية';
    }
  }

  String get scaleLabel => scale == 'double' ? 'حصة دوبل (2x)' : 'حصة فردية (1x)';

  Map<String, dynamic> toMap() => {
        'id': id,
        'group_id': groupId,
        'group_name': groupName,
        'title': title,
        'reason': reason,
        'scale': scale,
        'date': date,
        'day': day,
        'time': time,
        'is_recurring': isRecurring ? 1 : 0,
        'recurring_weeks': recurringWeeks,
        'notes': notes,
        'status': status,
        'created_at': createdAt,
      };

  factory ExceptionalSessionModel.fromMap(Map<String, dynamic> map) => ExceptionalSessionModel(
        id: map['id'] as String,
        groupId: map['group_id'] as String,
        groupName: map['group_name'] as String? ?? '',
        title: map['title'] as String? ?? 'حصة استثنائية',
        reason: map['reason'] as String? ?? 'teacher_makeup',
        scale: map['scale'] as String? ?? 'single',
        date: map['date'] as String,
        day: map['day'] as String? ?? '',
        time: map['time'] as String? ?? '',
        isRecurring: (map['is_recurring'] as num?)?.toInt() == 1,
        recurringWeeks: (map['recurring_weeks'] as num?)?.toInt() ?? 1,
        notes: map['notes'] as String? ?? '',
        status: map['status'] as String? ?? 'active',
        createdAt: map['created_at'] as String? ?? DateTime.now().toIso8601String(),
      );
}
