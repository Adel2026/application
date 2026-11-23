class SchoolPeriodModel {
  final String id;
  final String dayOfWeek; // 'الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'
  final int periodNumber; // 1 to 8
  final String className; // e.g. "أولى إعدادي - فصل 1/2" or "1/1 ع"
  final String subject; // e.g. "تكنولوجيا المعلومات ICT"
  final String startTime; // e.g. "08:00"
  final String endTime; // e.g. "08:45"
  final String room; // e.g. "معمل الكمبيوتر"
  final String notes;
  final bool isRecess; // فسحة مدرسية
  final String supervisionDuty; // e.g. "إشراف الفناء" or "إشراف الطابور"
  final bool isReserve; // حصة احتياط

  const SchoolPeriodModel({
    required this.id,
    required this.dayOfWeek,
    required this.periodNumber,
    required this.className,
    required this.subject,
    this.startTime = '08:00',
    this.endTime = '08:45',
    this.room = '',
    this.notes = '',
    this.isRecess = false,
    this.supervisionDuty = '',
    this.isReserve = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'day_of_week': dayOfWeek,
        'period_number': periodNumber,
        'class_name': className,
        'subject': subject,
        'start_time': startTime,
        'end_time': endTime,
        'room': room,
        'notes': notes,
        'is_recess': isRecess ? 1 : 0,
        'supervision_duty': supervisionDuty,
        'is_reserve': isReserve ? 1 : 0,
      };

  factory SchoolPeriodModel.fromMap(Map<String, dynamic> map) => SchoolPeriodModel(
        id: map['id'] as String,
        dayOfWeek: map['day_of_week'] as String,
        periodNumber: map['period_number'] as int? ?? 1,
        className: map['class_name'] as String? ?? '',
        subject: map['subject'] as String? ?? '',
        startTime: map['start_time'] as String? ?? '08:00',
        endTime: map['end_time'] as String? ?? '08:45',
        room: map['room'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        isRecess: (map['is_recess'] as int? ?? 0) == 1,
        supervisionDuty: map['supervision_duty'] as String? ?? '',
        isReserve: (map['is_reserve'] as int? ?? 0) == 1,
      );

  SchoolPeriodModel copyWith({
    String? id,
    String? dayOfWeek,
    int? periodNumber,
    String? className,
    String? subject,
    String? startTime,
    String? endTime,
    String? room,
    String? notes,
    bool? isRecess,
    String? supervisionDuty,
    bool? isReserve,
  }) {
    return SchoolPeriodModel(
      id: id ?? this.id,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      periodNumber: periodNumber ?? this.periodNumber,
      className: className ?? this.className,
      subject: subject ?? this.subject,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      room: room ?? this.room,
      notes: notes ?? this.notes,
      isRecess: isRecess ?? this.isRecess,
      supervisionDuty: supervisionDuty ?? this.supervisionDuty,
      isReserve: isReserve ?? this.isReserve,
    );
  }
}
