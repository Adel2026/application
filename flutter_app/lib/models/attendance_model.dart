class AttendanceModel {
  const AttendanceModel({
    required this.id,
    required this.studentId,
    required this.attendanceDate,
    required this.checkInAt,
    required this.status,
    this.source = 'qr',
    this.recitationRating,
    this.recitationScore,
    this.homeworkStatus,
    this.notes,
    this.sessionType = 'regular',
  });

  final int? id;
  final String studentId;
  final String attendanceDate;
  final DateTime checkInAt;
  final String status;
  final String source;
  final String? recitationRating;
  final double? recitationScore;
  final String? homeworkStatus;
  final String? notes;
  final String sessionType;

  Map<String, Object?> toMap() => {
        'id': id,
        'student_id': studentId,
        'attendance_date': attendanceDate,
        'check_in_at': checkInAt.toIso8601String(),
        'status': status,
        'source': source,
        if (recitationRating != null) 'recitation_rating': recitationRating,
        if (recitationScore != null) 'recitation_score': recitationScore,
        if (homeworkStatus != null) 'homework_status': homeworkStatus,
        if (notes != null) 'notes': notes,
        'session_type': sessionType,
      };

  factory AttendanceModel.fromMap(Map<String, Object?> map) => AttendanceModel(
        id: map['id'] as int?,
        studentId: map['student_id']! as String,
        attendanceDate: map['attendance_date']! as String,
        checkInAt: DateTime.parse(map['check_in_at']! as String),
        status: map['status']! as String,
        source: map['source'] as String? ?? 'qr',
        recitationRating: map['recitation_rating'] as String?,
        recitationScore: (map['recitation_score'] as num?)?.toDouble(),
        homeworkStatus: map['homework_status'] as String?,
        notes: map['notes'] as String?,
        sessionType: map['session_type'] as String? ?? 'regular',
      );
}
