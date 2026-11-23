class ExamModel {
  final String id;
  final String title;
  final String groupId;
  final String date;
  final double maxScore;

  const ExamModel({
    required this.id,
    required this.title,
    required this.groupId,
    required this.date,
    required this.maxScore,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'group_id': groupId,
        'date': date,
        'max_score': maxScore,
      };

  factory ExamModel.fromMap(Map<String, dynamic> map) => ExamModel(
        id: map['id'] as String,
        title: map['title'] as String,
        groupId: map['group_id'] as String? ?? '',
        date: map['date'] as String,
        maxScore: (map['max_score'] as num?)?.toDouble() ?? 100,
      );
}

class ExamScoreModel {
  final int? id;
  final String examId;
  final String studentId;
  final double score;
  final String note;

  const ExamScoreModel({
    this.id,
    required this.examId,
    required this.studentId,
    required this.score,
    this.note = '',
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'exam_id': examId,
        'student_id': studentId,
        'score': score,
        'note': note,
      };

  factory ExamScoreModel.fromMap(Map<String, dynamic> map) => ExamScoreModel(
        id: map['id'] as int?,
        examId: map['exam_id'] as String,
        studentId: map['student_id'] as String,
        score: (map['score'] as num).toDouble(),
        note: map['note'] as String? ?? '',
      );
}
