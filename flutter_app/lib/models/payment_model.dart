class PaymentModel {
  final int? id;
  final String studentId;
  final double amount;
  final String date;
  final String type; // شهر / حصة / مذكرة
  final String note;

  const PaymentModel({
    this.id,
    required this.studentId,
    required this.amount,
    required this.date,
    required this.type,
    this.note = '',
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'student_id': studentId,
        'amount': amount,
        'date': date,
        'type': type,
        'note': note,
      };

  factory PaymentModel.fromMap(Map<String, dynamic> map) => PaymentModel(
        id: map['id'] as int?,
        studentId: map['student_id'] as String,
        amount: (map['amount'] as num).toDouble(),
        date: map['date'] as String,
        type: map['type'] as String? ?? 'اشتراك شهري',
        note: map['note'] as String? ?? '',
      );
}
