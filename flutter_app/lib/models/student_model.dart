import 'dart:convert';

class StudentModel {
  const StudentModel({
    required this.id,
    required this.fullName,
    required this.stage,
    required this.grade,
    required this.studentPhone,
    required this.parentPhone,
    required this.groupId,
    required this.paymentPlan,
    this.outstandingAmount = 0,
    this.parentName = '',
    this.isActive = true,
  });

  final String id;
  final String fullName;
  final String stage;
  final String grade;
  final String studentPhone;
  final String parentPhone;
  final String? groupId;
  final String paymentPlan;
  final double outstandingAmount;
  final String parentName;
  final bool isActive;

  bool get hasOutstandingPayment => outstandingAmount > 0;

  String get qrPayload => jsonEncode(<String, String>{
        'type': 'teacher_center_student',
        'studentId': id,
      });

  StudentModel copyWith({
    String? id,
    String? fullName,
    String? stage,
    String? grade,
    String? studentPhone,
    String? parentPhone,
    String? groupId,
    String? paymentPlan,
    double? outstandingAmount,
    String? parentName,
    bool? isActive,
  }) {
    return StudentModel(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      stage: stage ?? this.stage,
      grade: grade ?? this.grade,
      studentPhone: studentPhone ?? this.studentPhone,
      parentPhone: parentPhone ?? this.parentPhone,
      groupId: groupId ?? this.groupId,
      paymentPlan: paymentPlan ?? this.paymentPlan,
      outstandingAmount: outstandingAmount ?? this.outstandingAmount,
      parentName: parentName ?? this.parentName,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'full_name': fullName,
        'stage': stage,
        'grade': grade,
        'student_phone': studentPhone,
        'parent_phone': parentPhone,
        'group_id': groupId,
        'payment_plan': paymentPlan,
        'outstanding_amount': outstandingAmount,
        'parent_name': parentName,
        'is_active': isActive ? 1 : 0,
      };

  factory StudentModel.fromMap(Map<String, Object?> map) => StudentModel(
        id: map['id']! as String,
        fullName: map['full_name']! as String,
        stage: map['stage']! as String,
        grade: map['grade']! as String,
        studentPhone: map['student_phone']! as String,
        parentPhone: map['parent_phone']! as String,
        groupId: map['group_id'] as String?,
        paymentPlan: map['payment_plan']! as String,
        outstandingAmount: (map['outstanding_amount'] as num?)?.toDouble() ?? 0,
        parentName: (map['parent_name'] as String?) ?? '',
        isActive: (map['is_active'] as num?)?.toInt() != 0,
      );
}
