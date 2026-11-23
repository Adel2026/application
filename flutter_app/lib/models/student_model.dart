import 'dart:convert';

/// جهة اتصال ولي الأمر وصلة القرابة (والد، والدة، أخ، عم، إلخ)
class GuardianContact {
  final String name;
  final String phone;
  final String relationship; // والد، والدة، أخ، عم، خال، ولي أمر، أخرى
  final bool isPrimary;

  const GuardianContact({
    required this.name,
    required this.phone,
    this.relationship = 'والد',
    this.isPrimary = false,
  });

  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    'phone': phone.trim(),
    'relationship': relationship.trim(),
    'is_primary': isPrimary,
  };

  factory GuardianContact.fromMap(Map<String, dynamic> map) => GuardianContact(
    name: (map['name'] ?? '').toString().trim(),
    phone: (map['phone'] ?? '').toString().trim(),
    relationship: (map['relationship'] ?? map['relation'] ?? 'ولي أمر').toString().trim(),
    isPrimary: map['is_primary'] == true,
  );

  GuardianContact copyWith({
    String? name,
    String? phone,
    String? relationship,
    bool? isPrimary,
  }) {
    return GuardianContact(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      relationship: relationship ?? this.relationship,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }
}

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
    this.guardiansJson,
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
  final String? guardiansJson;

  /// قائمة جميع أولياء الأمور المسجلين للطالب مع صلة القرابة لكل منهم
  List<GuardianContact> get guardians {
    if (guardiansJson != null && guardiansJson!.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(guardiansJson!);
        if (decoded is List) {
          final list = decoded
              .map((e) => GuardianContact.fromMap(Map<String, dynamic>.from(e as Map)))
              .where((g) => g.phone.isNotEmpty || g.name.isNotEmpty)
              .toList();
          if (list.isNotEmpty) return list;
        }
      } catch (_) {}
    }
    if (parentPhone.trim().isNotEmpty || parentName.trim().isNotEmpty) {
      return [
        GuardianContact(
          name: parentName.trim().isNotEmpty ? parentName.trim() : 'ولي الأمر',
          phone: parentPhone.trim(),
          relationship: 'والد',
          isPrimary: true,
        ),
      ];
    }
    return [];
  }

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
    String? guardiansJson,
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
      guardiansJson: guardiansJson ?? this.guardiansJson,
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
        'guardians_json': guardiansJson,
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
        guardiansJson: map['guardians_json'] as String?,
      );
}
