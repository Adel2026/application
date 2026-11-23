class GroupModel {
  final String id;
  final String name;
  final String stage;
  final String grade;
  final String schedule; // e.g., "السبت والثلاثاء 4:00 م"
  final double monthlyPrice;
  final String room;
  final int maxStudents;
  final String billingType; // 'monthly' or 'per_session'
  final int colorValue;
  final String notes;
  final String subject;
  final String locationType;
  final String startTime;
  final String endTime;
  final String days;
  final bool isActive;

  const GroupModel({
    required this.id,
    required this.name,
    required this.stage,
    required this.grade,
    required this.schedule,
    required this.monthlyPrice,
    this.room = '',
    this.maxStudents = 30,
    this.billingType = 'per_session',
    this.colorValue = 0xFF2563EB,
    this.notes = '',
    this.subject = '',
    this.locationType = 'منزل المعلم أو الطالب',
    this.startTime = '03:00 PM',
    this.endTime = '04:00 PM',
    this.days = '',
    this.isActive = true,
  });

  GroupModel copyWith({
    String? id,
    String? name,
    String? stage,
    String? grade,
    String? schedule,
    double? monthlyPrice,
    String? room,
    int? maxStudents,
    String? billingType,
    int? colorValue,
    String? notes,
    String? subject,
    String? locationType,
    String? startTime,
    String? endTime,
    String? days,
    bool? isActive,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      stage: stage ?? this.stage,
      grade: grade ?? this.grade,
      schedule: schedule ?? this.schedule,
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      room: room ?? this.room,
      maxStudents: maxStudents ?? this.maxStudents,
      billingType: billingType ?? this.billingType,
      colorValue: colorValue ?? this.colorValue,
      notes: notes ?? this.notes,
      subject: subject ?? this.subject,
      locationType: locationType ?? this.locationType,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      days: days ?? this.days,
      isActive: isActive ?? this.isActive,
    );
  }

  static int compareByStartTime(GroupModel first, GroupModel second) {
    final timeOrder = _startTimeInMinutes(
      first.startTime,
    ).compareTo(_startTimeInMinutes(second.startTime));
    return timeOrder != 0 ? timeOrder : first.name.compareTo(second.name);
  }

  static int _startTimeInMinutes(String value) {
    final normalized = value.trim().toUpperCase();
    final isPM = normalized.contains('PM') || normalized.contains('م');
    final isAM = normalized.contains('AM') || normalized.contains('ص');
    if (isAM && isPM) return 24 * 60;

    final timeParts = normalized.replaceAll(RegExp(r'[^0-9:]'), '').split(':');
    if (timeParts.isEmpty || timeParts.length > 2) return 24 * 60;

    var hour = int.tryParse(timeParts[0]);
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) : 0;
    if (hour == null || minute == null || minute < 0 || minute >= 60) {
      return 24 * 60;
    }
    if ((isAM || isPM) && (hour < 1 || hour > 12)) return 24 * 60;
    if (!isAM && !isPM && hour > 23) return 24 * 60;

    if (isPM && hour < 12) hour += 12;
    if (isAM && hour == 12) hour = 0;
    return hour * 60 + minute;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'stage': stage,
    'grade': grade,
    'schedule': schedule,
    'monthly_price': monthlyPrice,
    'room': room,
    'max_students': maxStudents,
    'billing_type': billingType,
    'color_value': colorValue,
    'notes': notes,
    'subject': subject,
    'location_type': locationType,
    'start_time': startTime,
    'end_time': endTime,
    'days': days,
    'is_active': isActive ? 1 : 0,
  };

  factory GroupModel.fromMap(Map<String, dynamic> map) => GroupModel(
    id: map['id'] as String,
    name: map['name'] as String,
    stage: map['stage'] as String? ?? 'عام',
    grade: map['grade'] as String? ?? '',
    schedule: map['schedule'] as String? ?? '',
    monthlyPrice: (map['monthly_price'] as num?)?.toDouble() ?? 0,
    room: map['room'] as String? ?? '',
    maxStudents: (map['max_students'] as num?)?.toInt() ?? 30,
    billingType: map['billing_type'] as String? ?? 'per_session',
    colorValue: (map['color_value'] as num?)?.toInt() ?? 0xFF2563EB,
    notes: map['notes'] as String? ?? '',
    subject: map['subject'] as String? ?? '',
    locationType: map['location_type'] as String? ?? 'منزل المعلم أو الطالب',
    startTime: map['start_time'] as String? ?? '03:00 PM',
    endTime: map['end_time'] as String? ?? '04:00 PM',
    days: map['days'] as String? ?? '',
    isActive: (map['is_active'] as num?)?.toInt() != 0,
  );
}
