class CurriculumLessonModel {
  final int? id;
  final String subject;
  final String stage;
  final String grade;
  final String unitName;
  final String lessonTitle;
  final String objectives;
  final int chapterNumber;
  final bool isCompleted;
  final String? curriculumName;
  final String? lessonDate;
  final String? homeworkNotes;

  const CurriculumLessonModel({
    this.id,
    required this.subject,
    this.stage = 'ثانوي',
    required this.grade,
    required this.unitName,
    required this.lessonTitle,
    this.objectives = '',
    this.chapterNumber = 1,
    this.isCompleted = false,
    this.curriculumName,
    this.lessonDate,
    this.homeworkNotes,
  });

  String get title => lessonTitle;
  String get unitTitle => unitName;
  String get description => objectives;
  String? get date => lessonDate;
  String? get homework => homeworkNotes;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'subject': subject,
        'stage': stage,
        'grade': grade,
        'unit_name': unitName,
        'lesson_title': lessonTitle,
        'objectives': objectives,
        'chapter_number': chapterNumber,
        'is_completed': isCompleted ? 1 : 0,
        if (curriculumName != null) 'curriculum_name': curriculumName,
        if (lessonDate != null) 'lesson_date': lessonDate,
        if (homeworkNotes != null) 'homework_notes': homeworkNotes,
      };

  factory CurriculumLessonModel.fromMap(Map<String, dynamic> map) => CurriculumLessonModel(
        id: map['id'] as int?,
        subject: map['subject'] as String? ?? 'عام',
        stage: map['stage'] as String? ?? 'ثانوي',
        grade: map['grade'] as String? ?? '',
        unitName: map['unit_name'] as String? ?? 'الوحدة الأولى',
        lessonTitle: map['lesson_title'] as String? ?? '',
        objectives: map['objectives'] as String? ?? '',
        chapterNumber: (map['chapter_number'] as num?)?.toInt() ?? 1,
        isCompleted: (map['is_completed'] as num?)?.toInt() == 1,
        curriculumName: map['curriculum_name'] as String?,
        lessonDate: map['lesson_date'] as String?,
        homeworkNotes: map['homework_notes'] as String?,
      );

  CurriculumLessonModel copyWith({
    int? id,
    String? subject,
    String? stage,
    String? grade,
    String? unitName,
    String? lessonTitle,
    String? objectives,
    int? chapterNumber,
    bool? isCompleted,
    String? curriculumName,
    String? lessonDate,
    String? homeworkNotes,
  }) {
    return CurriculumLessonModel(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      stage: stage ?? this.stage,
      grade: grade ?? this.grade,
      unitName: unitName ?? this.unitName,
      lessonTitle: lessonTitle ?? this.lessonTitle,
      objectives: objectives ?? this.objectives,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      isCompleted: isCompleted ?? this.isCompleted,
      curriculumName: curriculumName ?? this.curriculumName,
      lessonDate: lessonDate ?? this.lessonDate,
      homeworkNotes: homeworkNotes ?? this.homeworkNotes,
    );
  }
}

class SessionLogModel {
  final int? id;
  final String groupId;
  final String date;
  final String lessonTitle;
  final String contentCovered;
  final String homework;
  final String nextTopic;
  final String nextQuiz;
  final String nextHomework;
  final String previousHomeworkReview;
  final String previousLessonReview;
  final String notes;
  final String createdAt;
  final String? studentId;
  final String? studentName;
  final String? curriculumName;

  const SessionLogModel({
    this.id,
    required this.groupId,
    required this.date,
    required this.lessonTitle,
    this.contentCovered = '',
    required this.homework,
    this.nextTopic = '',
    this.nextQuiz = '',
    this.nextHomework = '',
    this.previousHomeworkReview = '',
    this.previousLessonReview = '',
    this.notes = '',
    String? createdAt,
    this.studentId,
    this.studentName,
    this.curriculumName,
  }) : createdAt = createdAt ?? date;

  String get sessionDate => date;
  String get teacherNotes => notes;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'group_id': groupId,
        'date': date,
        'lesson_title': lessonTitle,
        'content_covered': contentCovered,
        'homework': homework,
        'next_topic': nextTopic,
        'next_quiz': nextQuiz,
        'next_homework': nextHomework,
        'previous_homework_review': previousHomeworkReview,
        'previous_lesson_review': previousLessonReview,
        'notes': notes,
        'created_at': createdAt,
        if (studentId != null) 'student_id': studentId,
        if (studentName != null) 'student_name': studentName,
        if (curriculumName != null) 'curriculum_name': curriculumName,
      };

  factory SessionLogModel.fromMap(Map<String, dynamic> map) => SessionLogModel(
        id: map['id'] as int?,
        groupId: map['group_id'] as String,
        date: map['date'] as String,
        lessonTitle: map['lesson_title'] as String? ?? '',
        contentCovered: map['content_covered'] as String? ?? map['notes'] as String? ?? '',
        homework: map['homework'] as String? ?? '',
        nextTopic: map['next_topic'] as String? ?? '',
        nextQuiz: map['next_quiz'] as String? ?? '',
        nextHomework: map['next_homework'] as String? ?? '',
        previousHomeworkReview: map['previous_homework_review'] as String? ?? '',
        previousLessonReview: map['previous_lesson_review'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        createdAt: map['created_at'] as String? ?? map['date'] as String? ?? '',
        studentId: map['student_id'] as String?,
        studentName: map['student_name'] as String?,
        curriculumName: map['curriculum_name'] as String?,
      );
}

class GroupCurriculumProgress {
  final String groupId;
  final String groupName;
  final String stage;
  final String grade;
  final String? curriculumName;
  final String track;
  final int totalLessons;
  final int completedLessons;
  final double progressPercent; // 0.0 to 1.0
  final String? currentLessonTitle;
  final String? nextLessonTitle;
  final String? lastTaughtDate;
  final int unitsCount;
  final int studentCount;
  final String schedule;
  final int colorValue;

  const GroupCurriculumProgress({
    required this.groupId,
    required this.groupName,
    required this.stage,
    required this.grade,
    this.curriculumName,
    this.track = 'لغات',
    required this.totalLessons,
    required this.completedLessons,
    required this.progressPercent,
    this.currentLessonTitle,
    this.nextLessonTitle,
    this.lastTaughtDate,
    this.unitsCount = 0,
    this.studentCount = 0,
    this.schedule = '',
    this.colorValue = 0xFF2563EB,
  });

  int get remainingLessons =>
      (totalLessons - completedLessons).clamp(0, totalLessons);
  int get percentInt => (progressPercent * 100).round();
  bool get hasCurriculum =>
      curriculumName != null && curriculumName!.isNotEmpty && totalLessons > 0;
  bool get isCompleted => totalLessons > 0 && completedLessons >= totalLessons;
}

