import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/alarm_service.dart';
import '../core/app_style.dart';
import '../core/database/database_service.dart';
import '../core/whatsapp_service.dart';
import '../models/group_model.dart';
import '../models/payment_model.dart';
import '../models/student_model.dart';
import '../widgets/section_top_bar.dart';
import 'group_attendance_wizard_screen.dart';

class FinancesScreen extends StatefulWidget {
  const FinancesScreen({
    super.key,
    required this.database,
    this.onBack,
    this.initialTabIndex = 0,
  });
  final DatabaseService database;
  final VoidCallback? onBack;
  final int initialTabIndex;

  @override
  State<FinancesScreen> createState() => _FinancesScreenState();
}

class _StudentClaimsGroup {
  final StudentModel? student;
  final String studentId;
  final String studentName;
  final String groupName;
  final String grade;
  final GroupModel? group;
  final double basePrice;
  final List<Map<String, dynamic>> claims;
  final double totalAmount;
  final double totalPaid;
  final double remainingAmount;
  final bool isFullySettled;

  const _StudentClaimsGroup({
    required this.student,
    required this.studentId,
    required this.studentName,
    required this.groupName,
    required this.grade,
    required this.group,
    required this.basePrice,
    required this.claims,
    required this.totalAmount,
    required this.totalPaid,
    required this.remainingAmount,
    required this.isFullySettled,
  });
}

class _FinancesScreenState extends State<FinancesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool isLoading = true;

  List<PaymentModel> payments = [];
  List<Map<String, dynamic>> expenses = [];
  List<StudentModel> students = [];
  List<GroupModel> groups = [];
  List<Map<String, dynamic>> financialClaims = [];
  Map<String, double> metrics = {};
  String? filterGroupId;
  String _claimsFilter = 'all';
  StreamSubscription<DataChangeEvent>? _dataSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadFinances();
    _dataSub = widget.database.onDataChanged.listen((event) {
      if (event == DataChangeEvent.finances ||
          event == DataChangeEvent.students ||
          event == DataChangeEvent.groups ||
          event == DataChangeEvent.all) {
        if (mounted) _loadFinances();
      }
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFinances() async {
    await widget.database.reconcileAllAttendanceBilling();

    if (payments.isEmpty && expenses.isEmpty && financialClaims.isEmpty) {
      setState(() => isLoading = true);
    }
    final results = await Future.wait([
      widget.database.getAllPayments(),
      widget.database.getExpenses(),
      widget.database.getStudents(),
      widget.database.getGroups(),
      widget.database.getFinancialMetrics(),
      widget.database.getAllFinancialClaims(groupId: filterGroupId),
    ]);

    if (mounted) {
      setState(() {
        payments = results[0] as List<PaymentModel>;
        expenses = results[1] as List<Map<String, dynamic>>;
        students = results[2] as List<StudentModel>;
        groups = results[3] as List<GroupModel>;
        metrics = results[4] as Map<String, double>;
        financialClaims = results[5] as List<Map<String, dynamic>>;
        isLoading = false;
      });
    }
  }

  String _debtSearchQuery = '';
  String _smartFilter = 'all'; // 'all', 'top_debt', 'multi_sessions', 'single_session', 'today'
  String _claimsSearchQuery = '';
  final Set<String> _expandedClaimStudentIds = {};

  static String _normalizeArabic(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[إأآا]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String get _currentArabicDay {
    const days = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    return days[DateTime.now().weekday - 1];
  }

  List<StudentModel> get indebtedStudents {
    final query = _normalizeArabic(_debtSearchQuery);
    final currentDay = _currentArabicDay;

    var list = students.where((s) {
      if (!s.hasOutstandingPayment) return false;
      if (filterGroupId != null && s.groupId != filterGroupId) return false;

      if (query.isNotEmpty) {
        final normName = _normalizeArabic(s.fullName);
        final normId = s.id.toLowerCase();
        final normPhone = s.studentPhone.replaceAll(RegExp(r'\D'), '');
        final normParentPhone = s.parentPhone.replaceAll(RegExp(r'\D'), '');
        final group = groups.where((g) => g.id == s.groupId).firstOrNull;
        final normGroup = group != null ? _normalizeArabic(group.name) : '';
        final amtStr = s.outstandingAmount.toStringAsFixed(0);

        final matches = normName.contains(query) ||
            normId.contains(query) ||
            normPhone.contains(query) ||
            normParentPhone.contains(query) ||
            normGroup.contains(query) ||
            amtStr == query;
        if (!matches) return false;
      }

      if (_smartFilter == 'today') {
        final grp = groups.where((g) => g.id == s.groupId).firstOrNull;
        if (grp == null || !AlarmService.isGroupScheduledOnDay(grp, currentDay)) {
          return false;
        }
      } else if (_smartFilter == 'multi_sessions') {
        final grp = groups.where((g) => g.id == s.groupId).firstOrNull;
        final price = grp?.monthlyPrice ?? 100.0;
        if (s.outstandingAmount <= price) return false;
      } else if (_smartFilter == 'single_session') {
        final grp = groups.where((g) => g.id == s.groupId).firstOrNull;
        final price = grp?.monthlyPrice ?? 100.0;
        if (s.outstandingAmount > price) return false;
      }

      return true;
    }).toList();

    if (_smartFilter == 'top_debt') {
      list.sort((a, b) => b.outstandingAmount.compareTo(a.outstandingAmount));
    }

    return list;
  }

  void _showAddPaymentDialog({StudentModel? preselectedStudent}) {
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('برجاء إضافة طلاب أولاً لتسجيل سندات القبض'),
        ),
      );
      return;
    }

    String selectedStudentId = preselectedStudent?.id ?? students.first.id;
    final amountCtrl = TextEditingController(
      text:
          preselectedStudent != null && preselectedStudent.outstandingAmount > 0
          ? preselectedStudent.outstandingAmount.toStringAsFixed(0)
          : '200',
    );
    final noteCtrl = TextEditingController();
    String paymentType = 'اشتراك شهري';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final currentStudent = students
                .where((s) => s.id == selectedStudentId)
                .firstOrNull;
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 20,
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'تسجيل سند قبض / تحصيل جديد',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedStudentId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'اختر الطالب',
                            prefixIcon: Icon(Icons.person),
                          ),
                          items: students
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text(
                                    '${s.fullName} (${s.grade})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setModalState(() {
                                selectedStudentId = v;
                                final st = students
                                    .where((s) => s.id == v)
                                    .firstOrNull;
                                if (st != null && st.outstandingAmount > 0) {
                                  amountCtrl.text = st.outstandingAmount
                                      .toStringAsFixed(0);
                                }
                              });
                            }
                          },
                        ),
                        if (currentStudent != null &&
                            currentStudent.hasOutstandingPayment) ...[
                          const SizedBox(height: 6),
                          Text(
                            'المتأخرات على الطالب: ${currentStudent.outstandingAmount.toStringAsFixed(0)} ج.م',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: amountCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'المبلغ المحصل (ج.م)',
                                  prefixIcon: Container(
                                    width: 44,
                                    alignment: Alignment.center,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'ج.م',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: paymentType,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'نوع التحصيل',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'اشتراك شهري',
                                    child: Text(
                                      'اشتراك شهري',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'حصة فردية',
                                    child: Text(
                                      'حصة فردية',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'مذكرة / كتب',
                                    child: Text(
                                      'مذكرة / كتب',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'رسوم امتحان',
                                    child: Text(
                                      'رسوم امتحان',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setModalState(() => paymentType = v);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: noteCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات السند (اختياري)',
                            prefixIcon: Icon(Icons.notes),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.all(15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.check_circle),
                          label: const Text(
                            'تأكيد التحصيل وإصدار السند',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () async {
                            final amount =
                                double.tryParse(amountCtrl.text.trim()) ?? 0;
                            if (amount > 0 && currentStudent != null) {
                              final payment = PaymentModel(
                                studentId: selectedStudentId,
                                amount: amount,
                                date: DateTime.now().toIso8601String().substring(
                                  0,
                                  10,
                                ),
                                type: paymentType,
                                note: noteCtrl.text.trim(),
                              );
                              await widget.database.recordPayment(payment);

                              final sent =
                                  await WhatsAppService.autoSendPaymentReceipt(
                                    database: widget.database,
                                    studentName: currentStudent.fullName,
                                    parentPhone: currentStudent.parentPhone,
                                    amount: amount,
                                    type: paymentType,
                                    date: payment.date,
                                  );

                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              _loadFinances();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: sent
                                      ? Colors.green
                                      : Colors.blueGrey,
                                  content: Text(
                                    sent
                                        ? 'تم تسجيل سند القبض وإرسال الإيصال بنجاح ✅'
                                        : 'تم تسجيل سند القبض. لم يتم تأكيد إرسال الإيصال عبر واتساب.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddExpenseDialog() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String category = 'إيجار القاعة';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: 20,
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'إضافة مصروف / نفقة جديدة',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: titleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'بند المصروف',
                            prefixIcon: Icon(Icons.title),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: amountCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'المبلغ (ج.م)',
                                  prefixIcon: Icon(Icons.money_off),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: category,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'التصنيف',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'إيجار القاعة',
                                    child: Text(
                                      'إيجار القاعة',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'طباعة وتصوير',
                                    child: Text(
                                      'طباعة وتصوير',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'كهرباء ومرافق',
                                    child: Text(
                                      'كهرباء ومرافق',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'أدوات مكتبية',
                                    child: Text(
                                      'أدوات مكتبية',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'مكافآت وضيافة',
                                    child: Text(
                                      'مكافآت وضيافة',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'أخرى',
                                    child: Text(
                                      'أخرى',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setModalState(() => category = v);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات إضافية',
                            prefixIcon: Icon(Icons.notes),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            padding: const EdgeInsets.all(15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.save),
                          label: const Text(
                            'تسجيل المصروف',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () async {
                            final amount =
                                double.tryParse(amountCtrl.text.trim()) ?? 0;
                            final title = titleCtrl.text.trim();
                            if (amount > 0 && title.isNotEmpty) {
                              await widget.database.saveExpense({
                                'id':
                                    'EXP-${DateTime.now().millisecondsSinceEpoch}',
                                'title': title,
                                'category': category,
                                'amount': amount,
                                'date': DateTime.now().toIso8601String().substring(
                                  0,
                                  10,
                                ),
                                'notes': notesCtrl.text.trim(),
                              });
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              _loadFinances();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Colors.red,
                                  content: Text('تم تسجيل المصروف بنجاح 💸'),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddSessionClaimDialog(StudentModel student) {
    final group = groups.where((g) => g.id == student.groupId).firstOrNull;
    final defaultPrice = group?.monthlyPrice ?? 100.0;
    final amountCtrl = TextEditingController(
      text: defaultPrice > 0 ? defaultPrice.toStringAsFixed(0) : '100',
    );
    final noteCtrl = TextEditingController(text: 'حصة مستحقة إضافية');

    DateTime selectedClaimDate = DateTime.now();
    bool alsoOpenAttendance = false;

    // Helper to determine if a date is a session day according to group's schedule
    bool isGroupDay(DateTime date) {
      if (group == null) return true;
      const days = [
        'الاثنين', // 1
        'الثلاثاء', // 2
        'الأربعاء', // 3
        'الخميس', // 4
        'الجمعة', // 5
        'السبت', // 6
        'الأحد', // 7
      ];
      final dayName = days[(date.weekday - 1) % 7];
      if (group.days.isNotEmpty && group.days.contains(dayName)) return true;
      if (group.schedule.isNotEmpty && group.schedule.contains(dayName)) return true;
      if (group.days.isEmpty && group.schedule.isEmpty) return true;
      return false;
    }

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_task_rounded, color: Color(0xFF10B981), size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إضافة حصة مستحقة للحساب',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        student.fullName,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      'المجموعة: ${group?.name ?? "عام"} • السعر المعتاد: ${defaultPrice.toStringAsFixed(0)} ج.م/حصة\nالمواعيد: ${group?.schedule.isNotEmpty == true ? group!.schedule : "غير محدد"}',
                      style: const TextStyle(fontSize: 11.5, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Session Date Selector with Calendar Icon & Schedule Days Filtering
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedClaimDate,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 1),
                        helpText: 'اختر تاريخ الحصة المستحقة',
                        cancelText: 'إلغاء',
                        confirmText: 'تحديد التاريخ',
                        selectableDayPredicate: (date) {
                          // Allow choosing any date, but days matching group schedule are highlighted,
                          // while non-matching days can still be selected if needed or filtered.
                          // Returning isGroupDay(date) activates only the exact group days, dimming others!
                          return isGroupDay(date);
                        },
                      );
                      if (picked != null) {
                        setDlgState(() {
                          selectedClaimDate = picked;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, color: Colors.teal, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'تاريخ الحصة المستحقة:',
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  selectedClaimDate.toIso8601String().substring(0, 10),
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'تغيير 📅',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'قيمة الحصة المستحقة (ج.م)',
                      prefixIcon: const Icon(Icons.attach_money_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'بيان الحصة (اختياري)',
                      prefixIcon: const Icon(Icons.note_alt_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Option to open attendance wizard directly for this session
                  if (group != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
                      ),
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        title: const Text(
                          'تحضير الحصة كالمعتاد الآن ✍️',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'فتح دفتر التحضير والدروس والتسميع لهذا التاريخ',
                          style: TextStyle(fontSize: 10.5, color: Colors.grey),
                        ),
                        value: alsoOpenAttendance,
                        onChanged: (val) {
                          setDlgState(() {
                            alsoOpenAttendance = val ?? false;
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('إضافة وتراكم الحساب'),
                onPressed: () async {
                  final amt = double.tryParse(amountCtrl.text) ?? defaultPrice;
                  if (amt <= 0) return;
                  final chosenDateStr = selectedClaimDate.toIso8601String().substring(0, 10);
                  Navigator.pop(dlgCtx);

                  await widget.database.addManualSessionClaim(
                    studentId: student.id,
                    amount: amt,
                    date: chosenDateStr,
                    note: noteCtrl.text.trim().isNotEmpty
                        ? noteCtrl.text.trim()
                        : 'حصة مستحقة ($chosenDateStr)',
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تمت إضافة حصة (${amt.toStringAsFixed(0)} ج.م) بتاريخ $chosenDateStr لحساب ${student.fullName} بنجاح ✅',
                        ),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );

                    if (alsoOpenAttendance && group != null) {
                      final sessionLogs = await widget.database.getSessionLogs(
                        groupId: group.id,
                        date: chosenDateStr,
                      );
                      final sessionLog = sessionLogs.isNotEmpty
                          ? sessionLogs.first
                          : await widget.database.getLatestSessionLogForGroup(group.id);

                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupAttendanceWizardScreen(
                            database: widget.database,
                            group: group,
                            date: chosenDateStr,
                            latestLog: sessionLog,
                            onAttendanceUpdated: _loadFinances,
                          ),
                        ),
                      );
                      _loadFinances();
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _quickPaySession(StudentModel student) async {
    final group = groups.where((g) => g.id == student.groupId).firstOrNull;
    final defaultPrice = (group?.monthlyPrice ?? 100.0) > 0 ? (group?.monthlyPrice ?? 100.0) : 100.0;
    final payAmount = student.outstandingAmount < defaultPrice ? student.outstandingAmount : defaultPrice;

    final payment = PaymentModel(
      studentId: student.id,
      amount: payAmount,
      date: DateTime.now().toIso8601String().substring(0, 10),
      type: 'حصة فردية',
      note: 'تسوية سريعة لحصة واحدة',
    );
    await widget.database.recordPayment(payment);

    if (!mounted) return;
    _loadFinances();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        content: Text(
          'تم تحصيل ${payAmount.toStringAsFixed(0)} ج.م (حصة) للطالب ${student.fullName} بنجاح ✅',
        ),
        action: SnackBarAction(
          label: 'إرسال إيصال 💬',
          textColor: Colors.white,
          onPressed: () async {
            final cName = await widget.database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل');
            final msg = WhatsAppService.paymentReceiptMessage(
              centerName: cName,
              studentName: student.fullName,
              amount: payAmount,
              type: 'حصة فردية',
              date: payment.date,
            );
            WhatsAppService.openWhatsApp(
              phone: student.parentPhone,
              message: msg,
              database: widget.database,
              studentId: student.id,
              studentName: student.fullName,
              recipientType: 'parent',
              category: 'payment',
            );
          },
        ),
      ),
    );
  }

  Future<void> _quickSettleAllDebt(StudentModel student) async {
    final payAmount = student.outstandingAmount;
    if (payAmount <= 0) return;

    final payment = PaymentModel(
      studentId: student.id,
      amount: payAmount,
      date: DateTime.now().toIso8601String().substring(0, 10),
      type: 'اشتراك شهري',
      note: 'تسوية وتصفير كامل المستحقات',
    );
    await widget.database.recordPayment(payment);

    if (!mounted) return;
    _loadFinances();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0284C7),
        behavior: SnackBarBehavior.floating,
        content: Text(
          'تم تصفير وتسوية كامل الحساب (${payAmount.toStringAsFixed(0)} ج.م) للطالب ${student.fullName} ✅',
        ),
        action: SnackBarAction(
          label: 'إرسال إيصال 💬',
          textColor: Colors.white,
          onPressed: () async {
            final cName = await widget.database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل');
            final msg = WhatsAppService.paymentReceiptMessage(
              centerName: cName,
              studentName: student.fullName,
              amount: payAmount,
              type: 'تسوية حساب كامل',
              date: payment.date,
            );
            WhatsAppService.openWhatsApp(
              phone: student.parentPhone,
              message: msg,
              database: widget.database,
              studentId: student.id,
              studentName: student.fullName,
              recipientType: 'parent',
              category: 'payment',
            );
          },
        ),
      ),
    );
  }

  Future<void> _sendSmartWhatsAppReminder(StudentModel student) async {
    final cName = await widget.database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل');
    final group = groups.where((g) => g.id == student.groupId).firstOrNull;
    final price = group?.monthlyPrice ?? 0.0;
    final estSessions = price > 0 ? (student.outstandingAmount / price).ceil() : 0;

    final msg = '''السلام عليكم ورحمة الله وبركاته 🌸
ولي أمر الطالب المحترم / ${student.fullName}
تحية طيبة من إدارة *$cName* 📚

نود إحاطتكم علماً ببيان الحساب المالي الحالي:
📌 *المجموعة:* ${group?.name ?? 'عام'}
📌 *المستحق المطلوب:* *${student.outstandingAmount.toStringAsFixed(0)} ج.م* ${estSessions > 0 ? '($estSessions حصص)' : ''}

شاكرين ومقدرين حسن تعاونكم الدائم معنا 🌸''';

    WhatsAppService.openWhatsApp(
      phone: student.parentPhone,
      message: msg,
      database: widget.database,
      studentId: student.id,
      studentName: student.fullName,
      recipientType: 'parent',
      category: 'due_reminder',
    );
  }

  void _showSmartStudentFinancialSheet(StudentModel student) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final group = groups.where((g) => g.id == student.groupId).firstOrNull;
    final basePrice = (group?.monthlyPrice ?? 100.0) > 0 ? (group?.monthlyPrice ?? 100.0) : 100.0;
    final studentClaims = financialClaims
        .where((c) => c['student_id'] == student.id && c['status'] == 'active')
        .toList();
    final studentPayments = payments
        .where((p) => p.studentId == student.id)
        .toList();

    final totalPaidAmt = studentPayments.fold(
      0.0,
      (sum, p) => sum + p.amount,
    );
    final int estSessionsRemaining = basePrice > 0 ? (student.outstandingAmount / basePrice).ceil() : 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Padding(
              padding: EdgeInsets.only(
                top: 16,
                left: 18,
                right: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header with student info and close button
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: student.hasOutstandingPayment
                              ? Colors.red.withValues(alpha: 0.15)
                              : Colors.green.withValues(alpha: 0.15),
                          child: Icon(
                            student.hasOutstandingPayment
                                ? Icons.account_balance_wallet_rounded
                                : Icons.check_circle_rounded,
                            color: student.hasOutstandingPayment ? Colors.red : Colors.green,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                student.fullName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${group?.name ?? "مجموعة عامة"} • ${student.grade}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Key Financial Status Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: student.hasOutstandingPayment
                              ? [
                                  Colors.red.withValues(alpha: isDark ? 0.2 : 0.1),
                                  Colors.orange.withValues(alpha: isDark ? 0.15 : 0.05),
                                ]
                              : [
                                  Colors.green.withValues(alpha: isDark ? 0.2 : 0.1),
                                  Colors.teal.withValues(alpha: isDark ? 0.15 : 0.05),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: student.hasOutstandingPayment
                              ? Colors.red.withValues(alpha: 0.3)
                              : Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                student.hasOutstandingPayment ? 'الحساب: عليه متأخرات ⏳' : 'الحساب: مسدد بالكامل ✅',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: student.hasOutstandingPayment ? Colors.red : Colors.green,
                                ),
                              ),
                              Text(
                                '${basePrice.toStringAsFixed(0)} ج.م / الحصة',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildMiniFinancialStat(
                                label: 'حصص مسجلة',
                                value: '${studentClaims.length} حصص',
                                color: Colors.blue,
                              ),
                              _buildMiniFinancialStat(
                                label: 'إجمالي المحصل',
                                value: '${totalPaidAmt.toStringAsFixed(0)} ج.م',
                                color: Colors.green,
                              ),
                              _buildMiniFinancialStat(
                                label: 'المتبقي المطلوب',
                                value: '${student.outstandingAmount.toStringAsFixed(0)} ج.م',
                                color: student.hasOutstandingPayment ? Colors.red : Colors.green,
                                isBold: true,
                              ),
                            ],
                          ),
                          if (student.hasOutstandingPayment && estSessionsRemaining > 0) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'يعادل تقريباً: $estSessionsRemaining حصص مستحقة مطلوب سدادها',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Smart 1-Tap Quick Action Buttons Grid
                    const Text(
                      'إجراءات مالية ذكية سريعة ⚡',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (student.hasOutstandingPayment) ...[
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.flash_on_rounded, size: 18),
                              label: Text(
                                'تسوية حصة (${(student.outstandingAmount < basePrice ? student.outstandingAmount : basePrice).toStringAsFixed(0)} ج)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                              ),
                              onPressed: () {
                                Navigator.pop(sheetCtx);
                                _quickPaySession(student);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.done_all_rounded, size: 18),
                              label: Text(
                                'تصفير الكل (${student.outstandingAmount.toStringAsFixed(0)} ج)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                              ),
                              onPressed: () {
                                Navigator.pop(sheetCtx);
                                _quickSettleAllDebt(student);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF25D366),
                              side: const BorderSide(color: Color(0xFF25D366)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.chat_rounded, size: 16),
                            label: const Text(
                              'تذكير واتساب ذكي',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              _sendSmartWhatsAppReminder(student);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF10B981),
                              side: const BorderSide(color: Color(0xFF10B981)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.add_task_rounded, size: 16),
                            label: const Text(
                              'إضافة حصة +',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              _showAddSessionClaimDialog(student);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'تيسير وإعفاء لوجه الله',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.volunteer_activism_rounded, color: Color(0xFF10B981), size: 18),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            _showConcessionDialog(preselectedStudent: student);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Recent Financial History for this student
                    const Text(
                      'سجل الحصص والمدفوعات لهذا الطالب:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (studentClaims.isEmpty && studentPayments.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        alignment: Alignment.center,
                        child: Text(
                          'لا توجد حركات مالية سابقة مسجلة لهذا الطالب',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                      )
                    else ...[
                      ...studentClaims.take(5).map((c) {
                        final amt = (c['amount'] as num?)?.toDouble() ?? 0.0;
                        final paid = (c['paid_amount'] as num?)?.toDouble() ?? 0.0;
                        final isPaid = paid >= amt && amt > 0;
                        final date = c['session_date'] as String? ?? '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isPaid ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isPaid ? Icons.check_circle_outline_rounded : Icons.hourglass_top_rounded,
                                size: 16,
                                color: isPaid ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'حصة حضور • $date',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                '${amt.toStringAsFixed(0)} ج.م',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: isPaid ? Colors.green : Colors.red,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isPaid ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isPaid ? 'مسددة' : 'مستحقة',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: isPaid ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      if (studentPayments.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ...studentPayments.take(3).map((p) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: isDark ? 0.1 : 0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.receipt_rounded, size: 16, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'سند قبض (${p.type}) • ${p.date}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  '+ ${p.amount.toStringAsFixed(0)} ج.م',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniFinancialStat({
    required String label,
    required String value,
    required Color color,
    bool isBold = false,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 14 : 12.5,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _showGlobalSmartSearchDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final query = _normalizeArabic(searchQuery);
            final filtered = students.where((s) {
              if (query.isEmpty) return true;
              final normName = _normalizeArabic(s.fullName);
              final normId = s.id.toLowerCase();
              final normPhone = s.studentPhone.replaceAll(RegExp(r'\D'), '');
              final normParentPhone = s.parentPhone.replaceAll(RegExp(r'\D'), '');
              final group = groups.where((g) => g.id == s.groupId).firstOrNull;
              final normGroup = group != null ? _normalizeArabic(group.name) : '';
              final amtStr = s.outstandingAmount.toStringAsFixed(0);

              return normName.contains(query) ||
                  normId.contains(query) ||
                  normPhone.contains(query) ||
                  normParentPhone.contains(query) ||
                  normGroup.contains(query) ||
                  amtStr == query;
            }).toList();

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Dialog(
                backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.82,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.person_search_rounded,
                                color: Theme.of(context).colorScheme.primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'البحث المالي الذكي عن الطلاب',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'ابحث بالاسم، الكود، الهاتف، المجموعة، أو المبلغ المطلوب',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(dlgCtx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Search Input
                        TextField(
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: 'اكتب اسم الطالب، الكود، أو رقم الهاتف...',
                            hintStyle: const TextStyle(fontSize: 13),
                            prefixIcon: const Icon(Icons.search_rounded),
                            isDense: true,
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          onChanged: (val) {
                            setDlgState(() => searchQuery = val);
                          },
                        ),
                        const SizedBox(height: 10),

                        // Search Results Count
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'النتائج (${filtered.length} طالب)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Results List
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'لم يتم العثور على أي طالب مطابق لبحثك',
                                        style: TextStyle(fontSize: 13, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                  itemBuilder: (ctx, idx) {
                                    final s = filtered[idx];
                                    final grp = groups.where((g) => g.id == s.groupId).firstOrNull;
                                    final hasDebt = s.hasOutstandingPayment;

                                    return InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        Navigator.pop(dlgCtx);
                                        _showSmartStudentFinancialSheet(s);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: hasDebt
                                                ? Colors.red.withValues(alpha: 0.25)
                                                : Colors.green.withValues(alpha: 0.2),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor: hasDebt
                                                  ? Colors.red.withValues(alpha: 0.12)
                                                  : Colors.green.withValues(alpha: 0.12),
                                              child: Text(
                                                s.fullName.isNotEmpty ? s.fullName[0] : '?',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: hasDebt ? Colors.red : Colors.green,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    s.fullName,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${grp?.name ?? "عام"} • ${s.grade}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: hasDebt
                                                        ? Colors.red.withValues(alpha: 0.12)
                                                        : Colors.green.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    hasDebt
                                                        ? 'مطلوب: ${s.outstandingAmount.toStringAsFixed(0)} ج.م'
                                                        : 'مسدد بالكامل ✅',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: hasDebt ? Colors.red : Colors.green,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                const Text(
                                                  'عرض الحساب ❯',
                                                  style: TextStyle(fontSize: 10, color: Colors.blue),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showConcessionDialog({StudentModel? preselectedStudent}) {
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد طلاب مسجلين لتطبيق التيسير.')),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isMultiMode = preselectedStudent == null;
    String selectedStudentId = preselectedStudent?.id ??
        (indebtedStudents.isNotEmpty ? indebtedStudents.first.id : students.first.id);

    // Multi-selection set: default to all indebted students
    Set<String> selectedStudentIds = preselectedStudent != null
        ? {preselectedStudent.id}
        : indebtedStudents.map((s) => s.id).toSet();

    String? groupFilter;
    bool isPercentage = true;
    final valueController = TextEditingController(text: '50');
    final noteController = TextEditingController(text: 'لوجه الله تعالى');
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Filtered students for multi mode
            final visibleStudents = students.where((s) {
              if (groupFilter != null && groupFilter!.isNotEmpty && s.groupId != groupFilter) {
                return false;
              }
              return true;
            }).toList();

            // Calculate current required debt
            double currentDebt = 0.0;
            double discountAmount = 0.0;
            double remainingDebt = 0.0;
            int countStudents = 0;

            final parsedVal = double.tryParse(valueController.text.trim()) ?? 0.0;

            if (!isMultiMode) {
              final st = students.where((s) => s.id == selectedStudentId).firstOrNull;
              if (st != null) {
                currentDebt = st.outstandingAmount;
                countStudents = 1;
                if (isPercentage) {
                  discountAmount = parsedVal >= 100.0 ? currentDebt : (currentDebt * (parsedVal / 100.0));
                } else {
                  discountAmount = parsedVal.clamp(0.0, currentDebt);
                }
                remainingDebt = (currentDebt - discountAmount).clamp(0.0, double.infinity);
              }
            } else {
              final chosen = students.where((s) => selectedStudentIds.contains(s.id)).toList();
              countStudents = chosen.length;
              for (final st in chosen) {
                final sDebt = st.outstandingAmount;
                currentDebt += sDebt;
                double sDisc = 0.0;
                if (isPercentage) {
                  sDisc = parsedVal >= 100.0 ? sDebt : (sDebt * (parsedVal / 100.0));
                } else {
                  sDisc = parsedVal.clamp(0.0, sDebt);
                }
                discountAmount += sDisc;
              }
              remainingDebt = (currentDebt - discountAmount).clamp(0.0, double.infinity);
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.88,
                child: Column(
                  children: [
                    // Modal Header (Pinned at top)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.volunteer_activism_rounded,
                              color: Color(0xFF10B981),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'تيسير وإعفاء مستحقات لوجه الله 🤲',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'تخفيض سري ينفذ فوراً على المبالغ المطلوبة حالياً',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Scrollable Body
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Mode Selector: طالب فردي vs مجموعة طلاب
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        setModalState(() => isMultiMode = false);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        decoration: BoxDecoration(
                                          color: !isMultiMode
                                              ? const Color(0xFF10B981)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: !isMultiMode
                                              ? [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.3), blurRadius: 6)]
                                              : null,
                                        ),
                                        alignment: Alignment.center,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'طالب فردي 👤',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: !isMultiMode ? Colors.white : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        setModalState(() => isMultiMode = true);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isMultiMode
                                              ? const Color(0xFF10B981)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: isMultiMode
                                              ? [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.3), blurRadius: 6)]
                                              : null,
                                        ),
                                        alignment: Alignment.center,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'مجموعة طلاب (جماعي) 👥',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: isMultiMode ? Colors.white : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Section 1: Target Selection (Single or Multi)
                            if (!isMultiMode) ...[
                              DropdownButtonFormField<String>(
                                initialValue: selectedStudentId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'اختر الطالب المراد التيسير عليه',
                                  prefixIcon: const Icon(Icons.person, color: Color(0xFF10B981)),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                items: students.map((s) {
                                  final hasDebt = s.outstandingAmount > 0;
                                  return DropdownMenuItem(
                                    value: s.id,
                                    child: Text(
                                      '${s.fullName} (${s.grade}) • ${hasDebt ? "مطلوب: ${s.outstandingAmount.toStringAsFixed(0)} ج.م" : "مسدد"}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: hasDebt ? Colors.red : null,
                                        fontWeight: hasDebt ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setModalState(() => selectedStudentId = v);
                                  }
                                },
                              ),
                            ] else ...[
                              // Multi Selection Header: Group Filter + Select All
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String?>(
                                      initialValue: groupFilter,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: 'تصفية حسب المجموعة',
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      items: [
                                        const DropdownMenuItem(value: null, child: Text('جميع المجموعات (الكل)')),
                                        ...groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis))),
                                      ],
                                      onChanged: (v) {
                                        setModalState(() {
                                          groupFilter = v;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () {
                                      setModalState(() {
                                        final currentVisibleIds = visibleStudents.where((s) => s.outstandingAmount > 0).map((s) => s.id).toSet();
                                        if (selectedStudentIds.containsAll(currentVisibleIds)) {
                                          selectedStudentIds.removeAll(currentVisibleIds);
                                        } else {
                                          selectedStudentIds.addAll(currentVisibleIds);
                                        }
                                      });
                                    },
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        selectedStudentIds.length == visibleStudents.where((s) => s.outstandingAmount > 0).length
                                            ? 'إلغاء التحديد'
                                            : 'تحديد الجميع',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Scrollable checklist
                              Container(
                                height: 130,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                ),
                                child: visibleStudents.isEmpty
                                    ? const Center(child: Text('لا يوجد طلاب في هذه المجموعة'))
                                    : ListView.builder(
                                        itemCount: visibleStudents.length,
                                        itemBuilder: (ctx, idx) {
                                          final s = visibleStudents[idx];
                                          final isSelected = selectedStudentIds.contains(s.id);
                                          return CheckboxListTile(
                                            dense: true,
                                            value: isSelected,
                                            activeColor: const Color(0xFF10B981),
                                            title: Text(
                                              s.fullName,
                                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              '${s.grade} • ${s.outstandingAmount > 0 ? "المطلوب: ${s.outstandingAmount.toStringAsFixed(0)} ج.م" : "مسدد"}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: s.outstandingAmount > 0 ? Colors.red : Colors.green,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            onChanged: (val) {
                                              setModalState(() {
                                                if (val == true) {
                                                  selectedStudentIds.add(s.id);
                                                } else {
                                                  selectedStudentIds.remove(s.id);
                                                }
                                              });
                                            },
                                          );
                                        },
                                      ),
                              ),
                            ],
                            const SizedBox(height: 14),

                            // Section 2: Concession Type (نسبة مئوية % vs مبلغ ثابت ج.م)
                            Text(
                              'نوع وقيمة التيسير / التخفيض:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.grey.shade300 : const Color(0xFF334155)),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () {
                                        setModalState(() {
                                          isPercentage = true;
                                          valueController.text = '50';
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 7),
                                        decoration: BoxDecoration(
                                          color: isPercentage ? const Color(0xFF10B981) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        alignment: Alignment.center,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'نسبة مئوية %',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: isPercentage ? Colors.white : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () {
                                        setModalState(() {
                                          isPercentage = false;
                                          valueController.text = '50';
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 7),
                                        decoration: BoxDecoration(
                                          color: !isPercentage ? const Color(0xFF10B981) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        alignment: Alignment.center,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'مبلغ ثابت (ج.م)',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: !isPercentage ? Colors.white : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Quick Select Chips
                            if (isPercentage)
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _buildQuickValueChip('25%', 25, valueController, setModalState),
                                  _buildQuickValueChip('50%', 50, valueController, setModalState),
                                  _buildQuickValueChip('75%', 75, valueController, setModalState),
                                  _buildQuickValueChip('100% إعفاء كامل 🤲', 100, valueController, setModalState, isFull: true),
                                ],
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _buildQuickValueChip('20 ج.م', 20, valueController, setModalState),
                                  _buildQuickValueChip('50 ج.م', 50, valueController, setModalState),
                                  _buildQuickValueChip('100 ج.م', 100, valueController, setModalState),
                                  _buildQuickValueChip('200 ج.م', 200, valueController, setModalState),
                                ],
                              ),
                            const SizedBox(height: 8),

                            // Custom Value Input Field
                            TextFormField(
                              controller: valueController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: isPercentage ? 'النسبة المئوية المخصومة (%)' : 'المبلغ المخصوم (ج.م)',
                                prefixIcon: Icon(isPercentage ? Icons.percent_rounded : Icons.payments_rounded, color: const Color(0xFF10B981)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                isDense: true,
                              ),
                              onChanged: (_) => setModalState(() {}),
                            ),
                            const SizedBox(height: 12),

                            // Section 3: Live Preview Box (المعاينة الفورية قبل التنفيذ)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.12 : 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          isMultiMode ? 'الطلاب المحددين: $countStudents طالب' : 'طالب واحد محدد',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isPercentage ? 'نسبة: ${parsedVal.toStringAsFixed(0)}%' : 'مبلغ: ${parsedVal.toStringAsFixed(0)} ج.م',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('المطلوب فعلياً الآن:', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                                      Text('${currentDebt.toStringAsFixed(0)} ج.م', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('قيمة التيسير / الإعفاء:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                      Text('− ${discountAmount.toStringAsFixed(0)} ج.م', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF10B981))),
                                    ],
                                  ),
                                  const Divider(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Flexible(
                                        child: Text(
                                          'المتبقي بعد التيسير:',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        remainingDebt <= 0 ? '0 ج.م (إعفاء تام ومسدد ✅)' : '${remainingDebt.toStringAsFixed(0)} ج.م',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                          color: remainingDebt <= 0 ? Colors.green : Colors.amber.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Section 4: Privacy & Dignity Guarantee Banner
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: isDark ? 0.15 : 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.lock_outline_rounded, size: 16, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '🔒 سرية تامة: هذا التيسير سري ولن يظهر كبند إعانة أو صدقة في تقارير أولياء الأمور أو رسائل واتساب حفاظاً على كرامة الطالب.',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blue),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Action Buttons: Confirm & Cancel
                            Row(
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                                    child: const Text('إلغاء'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: (isSubmitting || countStudents == 0 || discountAmount <= 0)
                                        ? null
                                        : () async {
                                            setModalState(() => isSubmitting = true);
                                            final targetIds = !isMultiMode ? [selectedStudentId] : selectedStudentIds.toList();
                                            try {
                                              final affected = await widget.database.applyStudentDuesConcession(
                                                studentIds: targetIds,
                                                isPercentage: isPercentage,
                                                value: parsedVal,
                                                note: noteController.text.trim(),
                                              );
                                              if (!ctx.mounted) return;
                                              Navigator.pop(ctx);
                                              if (!mounted) return;
                                              _loadFinances();
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  backgroundColor: const Color(0xFF10B981),
                                                  content: Text('تم اعتماد وتطبيق التيسير بنجاح لـ $affected طالب وتحديث المستحقات المطلوبة فوراً 🤲'),
                                                ),
                                              );
                                            } catch (e) {
                                              setModalState(() => isSubmitting = false);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  backgroundColor: Colors.red,
                                                  content: Text('حدث خطأ أثناء تطبيق التيسير: $e'),
                                                ),
                                              );
                                            }
                                          },
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          if (isSubmitting)
                                            const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                          else
                                            const Icon(Icons.volunteer_activism_rounded, size: 17),
                                          const SizedBox(width: 6),
                                          Text(
                                            isSubmitting ? 'جارٍ الاعتماد...' : 'اعتماد التيسير لوجه الله 🤲',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickValueChip(
    String label,
    double val,
    TextEditingController controller,
    StateSetter setModalState, {
    bool isFull = false,
  }) {
    final isSelected = controller.text.trim() == val.toStringAsFixed(0);
    return ActionChip(
      label: Text(label),
      backgroundColor: isFull
          ? (isSelected ? const Color(0xFF10B981) : const Color(0xFF10B981).withValues(alpha: 0.15))
          : (isSelected ? const Color(0xFF10B981).withValues(alpha: 0.25) : null),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: isFull && isSelected ? Colors.white : (isSelected ? const Color(0xFF10B981) : null),
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFF10B981) : Colors.grey.withValues(alpha: 0.3),
      ),
      onPressed: () {
        setModalState(() {
          controller.text = val.toStringAsFixed(0);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: SectionTopBar(
        title: 'المالية',
        icon: Icons.account_balance_wallet_rounded,
        onBack: widget.onBack,
        actionLabel: _tabController.index == 2
            ? 'تيسير لله 🤲'
            : (_tabController.index == 3 ? 'تسجيل مصروف' : 'تسجيل حركة'),
        actionIcon: _tabController.index == 2
            ? Icons.volunteer_activism_rounded
            : Icons.add_rounded,
        onAction: () {
          if (_tabController.index == 3) {
            _showAddExpenseDialog();
          } else if (_tabController.index == 2) {
            _showConcessionDialog();
          } else {
            _showAddPaymentDialog();
          }
        },
        extraActions: [
          IconButton(
            icon: const Icon(Icons.person_search_rounded, size: 22),
            tooltip: 'بحث مالي ذكي عن أي طالب',
            onPressed: _showGlobalSmartSearchDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: isDark
              ? const Color(0xFF94A3B8)
              : const Color(0xFF64748B),
          indicatorWeight: 2.2,
          tabs: [
            Tab(
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long, size: 17),
                  const SizedBox(width: 6),
                  Text(
                    'التحصيلات (${payments.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.assignment_turned_in_rounded, size: 17),
                  const SizedBox(width: 6),
                  Text(
                    'سجل المطالبات (${financialClaims.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.money_off, size: 17),
                  const SizedBox(width: 6),
                  Text(
                    'المتأخرات (${indebtedStudents.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_wallet, size: 17),
                  const SizedBox(width: 6),
                  Text(
                    'المصروفات (${expenses.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 6),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: _tabController.index == 3
                  ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                  : [const Color(0xFF10B981), const Color(0xFF059669)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    (_tabController.index == 3
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF10B981))
                        .withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 1.0,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              splashColor: Colors.white24,
              onTap: () {
                HapticFeedback.lightImpact();
                if (_tabController.index == 2) {
                  _showAddExpenseDialog();
                } else {
                  _showAddPaymentDialog();
                }
              },
              child: Center(
                child: Icon(
                  _tabController.index == 2
                      ? Icons.remove_rounded
                      : Icons.add_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Top Global KPI Banner (Hidden on Tab 1 & Tab 2 to maximize viewport)
                if (_tabController.index != 1 && _tabController.index != 2)
                  Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: isDark ? AppStyle.summaryCardGradient : null,
                    color: isDark ? null : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? AppStyle.darkBorderGlow
                          : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.35 : 0.05,
                        ),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                        child: _StatColumn(
                          label: 'إجمالي الإيراد',
                          value:
                              '${(metrics['totalIncome'] ?? 0).toStringAsFixed(0)} ج.م',
                          color: Colors.green,
                          icon: Icons.trending_up,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: Colors.grey.shade400,
                      ),
                      Expanded(
                        child: _StatColumn(
                          label: 'إجمالي المصروف',
                          value:
                              '${(metrics['totalExpenses'] ?? 0).toStringAsFixed(0)} ج.م',
                          color: Colors.red,
                          icon: Icons.trending_down,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: Colors.grey.shade400,
                      ),
                      Expanded(
                        child: _StatColumn(
                          label: 'صافي الربح',
                          value:
                              '${(metrics['netProfit'] ?? 0).toStringAsFixed(0)} ج.م',
                          color: (metrics['netProfit'] ?? 0) >= 0
                              ? Colors.blue
                              : Colors.red,
                          icon: Icons.account_balance,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // TAB 1: PAYMENTS LEDGER
                      _buildPaymentsTab(isDark),
                      // TAB 2: FINANCIAL CLAIMS AUDIT LEDGER (Immutable)
                      _buildClaimsTab(isDark),
                      // TAB 3: DEBTS & UNPAID
                      _buildDebtsTab(isDark),
                      // TAB 4: EXPENSES LEDGER
                      _buildExpensesTab(isDark),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildClaimsTab(bool isDark) {
    final double totalClaimsAmount = financialClaims.where((c) => c['status'] == 'active').fold(
      0.0,
      (sum, c) => sum + ((c['amount'] as num?)?.toDouble() ?? 0.0),
    );
    final double totalCollectedClaims = financialClaims.where((c) => c['status'] == 'active').fold(
      0.0,
      (sum, c) => sum + ((c['paid_amount'] as num?)?.toDouble() ?? 0.0),
    );
    final double netRemainingClaims = (totalClaimsAmount - totalCollectedClaims).clamp(0.0, double.infinity);

    // Group active claims by student_id
    final Map<String, List<Map<String, dynamic>>> claimsByStudent = {};
    for (final c in financialClaims) {
      if (c['status'] != 'active') continue;
      if (filterGroupId != null && c['group_id'] != filterGroupId) continue;
      final sId = c['student_id'] as String? ?? '';
      if (sId.isEmpty) continue;
      claimsByStudent.putIfAbsent(sId, () => []).add(c);
    }

    final List<_StudentClaimsGroup> studentGroups = [];
    for (final entry in claimsByStudent.entries) {
      final sId = entry.key;
      final sClaims = entry.value;
      sClaims.sort((a, b) => (b['session_date'] as String? ?? '').compareTo(a['session_date'] as String? ?? ''));

      final student = students.where((s) => s.id == sId).firstOrNull;
      final studentName = sClaims.first['student_name'] as String? ?? student?.fullName ?? 'طالب';
      final groupName = sClaims.first['group_name'] as String? ?? '';
      final grade = student?.grade ?? '';
      final group = groups.where((g) => g.id == student?.groupId || g.id == sClaims.first['group_id']).firstOrNull;
      final basePrice = (group?.monthlyPrice ?? 100.0) > 0 ? (group?.monthlyPrice ?? 100.0) : 100.0;

      final totalAmt = sClaims.fold(0.0, (sum, c) => sum + ((c['amount'] as num?)?.toDouble() ?? 0.0));
      final totalPaid = sClaims.fold(0.0, (sum, c) => sum + ((c['paid_amount'] as num?)?.toDouble() ?? 0.0));
      final remaining = (totalAmt - totalPaid).clamp(0.0, double.infinity);
      final isFullySettled = remaining <= 0 && totalAmt > 0;

      studentGroups.add(_StudentClaimsGroup(
        student: student,
        studentId: sId,
        studentName: studentName,
        groupName: groupName,
        grade: grade,
        group: group,
        basePrice: basePrice,
        claims: sClaims,
        totalAmount: totalAmt,
        totalPaid: totalPaid,
        remainingAmount: remaining,
        isFullySettled: isFullySettled,
      ));
    }

    // Sort: students with pending claims first (sorted by remaining desc), then settled
    studentGroups.sort((a, b) {
      if (!a.isFullySettled && b.isFullySettled) return -1;
      if (a.isFullySettled && !b.isFullySettled) return 1;
      return b.remainingAmount.compareTo(a.remainingAmount);
    });

    final int settledStudentsCount = studentGroups.where((g) => g.isFullySettled).length;
    final int pendingStudentsCount = studentGroups.where((g) => !g.isFullySettled).length;
    final int partialStudentsCount = studentGroups.where((g) => g.totalPaid > 0 && g.remainingAmount > 0).length;

    // Filter by tab and search query
    final displayGroups = studentGroups.where((g) {
      if (_claimsFilter == 'pending' && g.isFullySettled) return false;
      if (_claimsFilter == 'partial' && !(g.totalPaid > 0 && g.remainingAmount > 0)) return false;
      if (_claimsFilter == 'paid' && !g.isFullySettled) return false;
      if (_claimsSearchQuery.trim().isNotEmpty) {
        final q = _normalizeArabic(_claimsSearchQuery);
        final matchName = _normalizeArabic(g.studentName).contains(q);
        final matchGroup = _normalizeArabic(g.groupName).contains(q);
        final matchId = g.studentId.toLowerCase().contains(q);
        if (!matchName && !matchGroup && !matchId) return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // 3-Column Executive Metrics Summary Grid (Compact)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildExecutiveMetricTile(
                  label: 'إجمالي المطالبات',
                  value: '${totalClaimsAmount.toStringAsFixed(0)} ج.م',
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Container(
                width: 1,
                height: 20,
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
              Expanded(
                child: _buildExecutiveMetricTile(
                  label: 'تم تحصيله ✅',
                  value: '${totalCollectedClaims.toStringAsFixed(0)} ج.م',
                  color: const Color(0xFF10B981),
                ),
              ),
              Container(
                width: 1,
                height: 20,
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
              Expanded(
                child: _buildExecutiveMetricTile(
                  label: 'المتبقي المطلوب ⏳',
                  value: '${netRemainingClaims.toStringAsFixed(0)} ج.م',
                  color: netRemainingClaims > 0 ? const Color(0xFFF43F5E) : const Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ),

        // Search & Filter Toolbar (Compact)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'بحث باسم الطالب أو المجموعة...',
                      hintStyle: const TextStyle(fontSize: 11),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      suffixIcon: _claimsSearchQuery.isNotEmpty
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () => setState(() => _claimsSearchQuery = ''),
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF0284C7)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (val) => setState(() => _claimsSearchQuery = val),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 36,
                child: PopupMenuButton<String?>(
                  tooltip: 'تصفية حسب المجموعة',
                  icon: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: filterGroupId != null
                          ? const Color(0xFF0284C7)
                          : (isDark ? const Color(0xFF1E293B) : Colors.white),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: filterGroupId != null
                            ? const Color(0xFF0284C7)
                            : (isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                    ),
                    child: Icon(
                      Icons.filter_list_rounded,
                      size: 18,
                      color: filterGroupId != null ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                  onSelected: (val) {
                    setState(() => filterGroupId = val);
                    _loadFinances();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: null,
                      child: Text('جميع المجموعات'),
                    ),
                    ...groups.map(
                      (g) => PopupMenuItem(
                        value: g.id,
                        child: Text(g.name),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Filter Pills: Pending, Settled, Partially Paid, All (Compact)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            children: [
              _buildCompactPill(
                label: 'عليهم مستحقات ($pendingStudentsCount) ⏳',
                selected: _claimsFilter == 'pending',
                activeColor: const Color(0xFFD97706),
                isDark: isDark,
                onTap: () => setState(() => _claimsFilter = 'pending'),
              ),
              const SizedBox(width: 6),
              _buildCompactPill(
                label: 'مسددين بالكامل ($settledStudentsCount) ✅',
                selected: _claimsFilter == 'paid',
                activeColor: const Color(0xFF10B981),
                isDark: isDark,
                onTap: () => setState(() => _claimsFilter = 'paid'),
              ),
              const SizedBox(width: 6),
              _buildCompactPill(
                label: 'مسدد جزئياً ($partialStudentsCount) 🌓',
                selected: _claimsFilter == 'partial',
                activeColor: const Color(0xFF0284C7),
                isDark: isDark,
                onTap: () => setState(() => _claimsFilter = 'partial'),
              ),
              const SizedBox(width: 6),
              _buildCompactPill(
                label: 'الكل (${studentGroups.length})',
                selected: _claimsFilter == 'all',
                activeColor: isDark ? const Color(0xFF475569) : const Color(0xFF334155),
                isDark: isDark,
                onTap: () => setState(() => _claimsFilter = 'all'),
              ),
            ],
          ),
        ),

        // Grouped Students Claims List
        Expanded(
          child: displayGroups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.assignment_turned_in_outlined,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _claimsFilter == 'pending'
                            ? 'لا توجد مطالبات معلقة قيد التحصيل ✅'
                            : (_claimsFilter == 'partial'
                                ? 'لا يوجد طلاب مسددين جزئياً حالياً'
                                : (_claimsFilter == 'paid'
                                    ? 'لم يتم تحصيل أي مطالبات بالكامل بعد'
                                    : 'لا توجد مطالبات حصص مسجلة حتى الآن')),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  key: const PageStorageKey<String>('finances_grouped_claims_list_view'),
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 80),
                  itemCount: displayGroups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final g = displayGroups[i];
                    final isExpanded = _expandedClaimStudentIds.contains(g.studentId);
                    final singlePrice = g.basePrice;
                    final singlePayAmt = g.remainingAmount < singlePrice ? g.remainingAmount : singlePrice;
                    final progressRatio = g.totalAmount > 0
                        ? (g.totalPaid / g.totalAmount).clamp(0.0, 1.0)
                        : 1.0;

                    return Container(
                      key: ValueKey('grouped_claim_card_${g.studentId}'),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: g.isFullySettled
                              ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.4 : 0.3)
                              : const Color(0xFFF43F5E).withValues(alpha: isDark ? 0.4 : 0.3),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Card Main Header (Tap to Expand / Collapse)
                          InkWell(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            onTap: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedClaimStudentIds.remove(g.studentId);
                                } else {
                                  _expandedClaimStudentIds.add(g.studentId);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      // Avatar Box
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: g.isFullySettled
                                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                              : const Color(0xFFF43F5E).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: g.isFullySettled
                                                ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                                : const Color(0xFFF43F5E).withValues(alpha: 0.3),
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          g.studentName.isNotEmpty ? g.studentName[0] : '?',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: g.isFullySettled ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),

                                      // Student Title & Group
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              g.studentName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14.5,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${g.groupName} • ${g.grade}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Remaining Amount Badge
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            g.isFullySettled ? '0 ج.م' : '${g.remainingAmount.toStringAsFixed(0)} ج.م',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w900,
                                              color: g.isFullySettled ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: g.isFullySettled
                                                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                                  : const Color(0xFFF43F5E).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              g.isFullySettled
                                                  ? 'مسدد بالكامل ✅'
                                                  : 'متبقي ${((g.remainingAmount / (singlePrice > 0 ? singlePrice : 100)).ceil())} حصص ⏳',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                                color: g.isFullySettled ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(width: 6),
                                      Icon(
                                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                        size: 20,
                                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                      ),
                                    ],
                                  ),

                                  // Micro Financial Progress Bar
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      value: progressRatio,
                                      minHeight: 5,
                                      backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        g.isFullySettled ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'مسدد: ${g.totalPaid.toStringAsFixed(0)} ج.م (${g.claims.where((c) => ((c['paid_amount'] as num?)?.toDouble() ?? 0.0) >= ((c['amount'] as num?)?.toDouble() ?? 0.0) && ((c['amount'] as num?)?.toDouble() ?? 0.0) > 0).length} حصص)',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                        ),
                                      ),
                                      Text(
                                        'إجمالي المطالبات: ${g.claims.length} حصص (${g.totalAmount.toStringAsFixed(0)} ج.م)',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Collapsible Ledger Details Section
                          if (isExpanded) ...[
                            Container(
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                border: Border(
                                  top: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                ),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '📋 بيان الحصص المسجلة (${g.claims.length} حصص):',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0284C7),
                                        ),
                                      ),
                                      Text(
                                        'سعر الحصة: ${singlePrice.toStringAsFixed(0)} ج.م',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Clean Accounting Ledger Rows
                                  Container(
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        // Header row
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF273549) : const Color(0xFFF1F5F9),
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                                          ),
                                          child: const Row(
                                            children: [
                                              Expanded(flex: 3, child: Text('تاريخ الحصة', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                                              Expanded(flex: 2, child: Text('القيمة', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                                              Expanded(flex: 3, child: Text('الحالة', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold))),
                                            ],
                                          ),
                                        ),

                                        // Item rows
                                        ...g.claims.map((c) {
                                          final sessionDate = c['session_date'] as String? ?? '';
                                          final amt = (c['amount'] as num?)?.toDouble() ?? 0.0;
                                          final paidAmt = (c['paid_amount'] as num?)?.toDouble() ?? 0.0;
                                          final isPaid = paidAmt >= amt && amt > 0;
                                          final isDouble = c['session_scale'] == 'double';

                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            decoration: BoxDecoration(
                                              border: Border(
                                                top: BorderSide(
                                                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                                  width: 0.8,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                    sessionDate,
                                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        '${amt.toStringAsFixed(0)} ج',
                                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                      ),
                                                      if (isDouble) ...[
                                                        const SizedBox(width: 4),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: Colors.amber.shade100,
                                                            borderRadius: BorderRadius.circular(3),
                                                          ),
                                                          child: Text(
                                                            '2x',
                                                            style: TextStyle(
                                                              fontSize: 8,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.amber.shade900,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 3,
                                                  child: Align(
                                                    alignment: Alignment.centerRight,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isPaid
                                                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                                            : const Color(0xFFF43F5E).withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(
                                                          color: isPaid
                                                              ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                                              : const Color(0xFFF43F5E).withValues(alpha: 0.3),
                                                          width: 0.8,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        isPaid ? 'مسددة بالكامل ✅' : 'مستحقة ⏳',
                                                        style: TextStyle(
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                          color: isPaid ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),

                                  // Executive Actions Row Inside Card
                                  if (g.student != null) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        if (g.remainingAmount > 0) ...[
                                          Expanded(
                                            flex: 3,
                                            child: FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: const Color(0xFF10B981),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                              onPressed: () => _quickPaySession(g.student!),
                                              child: FittedBox(
                                                child: Text(
                                                  '⚡ تسوية حصة (${singlePayAmt.toStringAsFixed(0)} ج)',
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            flex: 3,
                                            child: FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: const Color(0xFF0284C7),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                              onPressed: () => _quickSettleAllDebt(g.student!),
                                              child: const FittedBox(
                                                child: Text(
                                                  '⚡ تسديد كامل',
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                        ],
                                        Expanded(
                                          flex: 3,
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(0xFF25D366),
                                              side: const BorderSide(color: Color(0xFF25D366)),
                                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                            icon: const Icon(Icons.chat_rounded, size: 14),
                                            label: const FittedBox(
                                              child: Text(
                                                'كشف حساب واتساب',
                                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            onPressed: () => _sendSmartWhatsAppReminder(g.student!),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          tooltip: 'إضافة حصة مستحقة +',
                                          style: IconButton.styleFrom(
                                            backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                            padding: const EdgeInsets.all(7),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          icon: const Icon(Icons.add_task_rounded, size: 16, color: Color(0xFF0284C7)),
                                          onPressed: () => _showAddSessionClaimDialog(g.student!),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildExecutiveMetricTile({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildCompactPill({
    required String label,
    required bool selected,
    required Color activeColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? activeColor
              : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? activeColor
                : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected
                ? Colors.white
                : (isDark ? Colors.white70 : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentsTab(bool isDark) {
    if (payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'لا توجد سندات قبض مسجلة حتى الآن',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('تسجيل أول سند قبض'),
              onPressed: () => _showAddPaymentDialog(),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      key: const PageStorageKey<String>('finances_payments_list_view'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 80),
      itemCount: payments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final p = payments[i];
        final student = students.where((s) => s.id == p.studentId).firstOrNull;

        return Card(
          key: ValueKey('payment_card_${p.id}'),
          elevation: 0,
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green.withValues(alpha: 0.15),
              child: const Icon(Icons.check, color: Colors.green),
            ),
            title: Text(
              student?.fullName ?? 'طالب كود: ${p.studentId}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Text(
              '${p.type} • ${p.date} ${p.note.isNotEmpty ? "\n${p.note}" : ""}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${p.amount.toStringAsFixed(0)} ج.م',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(
                    Icons.share,
                    color: Color(0xFF25D366),
                    size: 20,
                  ),
                  tooltip: 'إرسال إيصال بالواتساب',
                  onPressed: () async {
                    if (student != null) {
                      final cName = await widget.database.getSetting(
                        'center_name',
                        defaultValue: 'أكاديمية المستقبل',
                      );
                      final msg = WhatsAppService.paymentReceiptMessage(
                        centerName: cName,
                        studentName: student.fullName,
                        amount: p.amount,
                        type: p.type,
                        date: p.date,
                      );
                      WhatsAppService.openWhatsApp(
                        phone: student.parentPhone,
                        message: msg,
                        database: widget.database,
                        studentId: student.id,
                        studentName: student.fullName,
                        recipientType: 'parent',
                        category: 'payment',
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDebtsTab(bool isDark) {
    final debtors = indebtedStudents;
    final totalUnpaid = debtors.fold(
      0.0,
      (sum, s) => sum + s.outstandingAmount,
    );

    final allDebtors = students.where((s) => s.hasOutstandingPayment && (filterGroupId == null || s.groupId == filterGroupId)).toList();

    final multiDebtStudents = allDebtors.where((s) {
      final grp = groups.where((g) => g.id == s.groupId).firstOrNull;
      final price = grp?.monthlyPrice ?? 100.0;
      return s.outstandingAmount > price;
    }).toList();

    final singleDebtStudents = allDebtors.where((s) {
      final grp = groups.where((g) => g.id == s.groupId).firstOrNull;
      final price = grp?.monthlyPrice ?? 100.0;
      return s.outstandingAmount <= price;
    }).toList();

    final todayDebtors = allDebtors.where((s) {
      final grp = groups.where((g) => g.id == s.groupId).firstOrNull;
      return grp != null && AlarmService.isGroupScheduledOnDay(grp, _currentArabicDay);
    }).toList();

    return Column(
      children: [
        // 1. Compact Executive Debt Overview Bar (Height ~32px)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: isDark ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.withValues(alpha: isDark ? 0.35 : 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
              const SizedBox(width: 6),
              Text(
                'الديون: ${totalUnpaid.toStringAsFixed(0)} ج.م',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${debtors.length} طالب)',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              if (todayDebtors.isNotEmpty) ...[
                InkWell(
                  onTap: () => setState(() => _smartFilter = _smartFilter == 'today' ? 'all' : 'today'),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _smartFilter == 'today'
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF0284C7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.today_rounded,
                          size: 13,
                          color: _smartFilter == 'today' ? Colors.white : const Color(0xFF0284C7),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'اليوم (${todayDebtors.length})',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: _smartFilter == 'today' ? Colors.white : const Color(0xFF0284C7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              // Charitable Concession Action (Compact)
              InkWell(
                onTap: () => _showConcessionDialog(),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.volunteer_activism_rounded, size: 13, color: Color(0xFF10B981)),
                      SizedBox(width: 3),
                      Text(
                        'إعفاء 🤲',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. Compact Search & Group Filter Bar (Height 36px)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم، الكود، الهاتف، أو المبلغ...',
                      hintStyle: const TextStyle(fontSize: 11),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      suffixIcon: _debtSearchQuery.isNotEmpty
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () => setState(() => _debtSearchQuery = ''),
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFEF4444)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (val) => setState(() => _debtSearchQuery = val),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 36,
                child: PopupMenuButton<String?>(
                  tooltip: 'تصفية حسب المجموعة',
                  icon: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: filterGroupId != null
                          ? const Color(0xFFEF4444)
                          : (isDark ? const Color(0xFF1E293B) : Colors.white),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: filterGroupId != null
                            ? const Color(0xFFEF4444)
                            : (isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                    ),
                    child: Icon(
                      Icons.filter_list_rounded,
                      size: 18,
                      color: filterGroupId != null ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                  onSelected: (val) {
                    setState(() => filterGroupId = val);
                    _loadFinances();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: null,
                      child: Text('جميع المجموعات'),
                    ),
                    ...groups.map(
                      (g) => PopupMenuItem(
                        value: g.id,
                        child: Text(g.name),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 3. Compact Filter Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            children: [
              _buildCompactPill(
                label: 'الكل (${allDebtors.length})',
                selected: _smartFilter == 'all',
                activeColor: isDark ? const Color(0xFF475569) : const Color(0xFF334155),
                isDark: isDark,
                onTap: () => setState(() => _smartFilter = 'all'),
              ),
              const SizedBox(width: 6),
              _buildCompactPill(
                label: 'الأعلى ديناً ⚠️',
                selected: _smartFilter == 'top_debt',
                activeColor: const Color(0xFFDC2626),
                isDark: isDark,
                onTap: () => setState(() => _smartFilter = 'top_debt'),
              ),
              const SizedBox(width: 6),
              _buildCompactPill(
                label: 'أكثر من حصة (${multiDebtStudents.length}) 🔴',
                selected: _smartFilter == 'multi_sessions',
                activeColor: const Color(0xFFEA580C),
                isDark: isDark,
                onTap: () => setState(() => _smartFilter = 'multi_sessions'),
              ),
              const SizedBox(width: 6),
              _buildCompactPill(
                label: 'حصة واحدة (${singleDebtStudents.length}) 🟡',
                selected: _smartFilter == 'single_session',
                activeColor: const Color(0xFFD97706),
                isDark: isDark,
                onTap: () => setState(() => _smartFilter = 'single_session'),
              ),
              if (todayDebtors.isNotEmpty) ...[
                const SizedBox(width: 6),
                _buildCompactPill(
                  label: 'طلاب اليوم (${todayDebtors.length}) 📅',
                  selected: _smartFilter == 'today',
                  activeColor: const Color(0xFF0284C7),
                  isDark: isDark,
                  onTap: () => setState(() => _smartFilter = 'today'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 2),

        Expanded(
          child: debtors.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _debtSearchQuery.isNotEmpty || _smartFilter != 'all'
                            ? Icons.search_off_rounded
                            : Icons.sentiment_very_satisfied,
                        size: 64,
                        color: _debtSearchQuery.isNotEmpty || _smartFilter != 'all'
                            ? Colors.grey.shade400
                            : Colors.green,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _debtSearchQuery.isNotEmpty || _smartFilter != 'all'
                            ? 'لا توجد نتائج مطابقة لبحثك أو فلترك'
                            : 'لا توجد أي متأخرات معلقة! كافة الطلاب مسددين ✅',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _debtSearchQuery.isNotEmpty || _smartFilter != 'all'
                              ? Colors.grey.shade600
                              : Colors.green,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  key: const PageStorageKey<String>('finances_debtors_list_view'),
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 80),
                  itemCount: debtors.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final student = debtors[i];
                    final group = groups
                        .where((g) => g.id == student.groupId)
                        .firstOrNull;
                    final basePrice = (group?.monthlyPrice ?? 100.0) > 0 ? (group?.monthlyPrice ?? 100.0) : 100.0;
                    final singlePayAmt = student.outstandingAmount < basePrice ? student.outstandingAmount : basePrice;

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showSmartStudentFinancialSheet(student),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: isDark ? 0.35 : 0.25),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Top Row: Avatar + Name & Group Info + Outstanding Amount Badge
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Avatar with student initial and money off icon
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      CircleAvatar(
                                        radius: 19,
                                        backgroundColor: Colors.red.withValues(alpha: 0.12),
                                        child: Text(
                                          student.fullName.isNotEmpty ? student.fullName[0] : '?',
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: -2,
                                        right: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.money_off_rounded,
                                            size: 13,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),

                                  // Name & Group/Grade Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                student.fullName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const Icon(
                                              Icons.touch_app_outlined,
                                              size: 14,
                                              color: Colors.grey,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            if (group != null)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                decoration: BoxDecoration(
                                                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.groups_rounded,
                                                      size: 13,
                                                      color: isDark ? Colors.white70 : Colors.black87,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      group.name,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                        color: isDark ? Colors.white70 : Colors.black87,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                              decoration: BoxDecoration(
                                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.school_rounded,
                                                    size: 13,
                                                    color: isDark ? Colors.white70 : Colors.black87,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    student.grade,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: isDark ? Colors.white70 : Colors.black87,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  // Outstanding Amount Badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.red.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'المتأخرات',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.red,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${student.outstandingAmount.toStringAsFixed(0)} ج.م',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // Calculation details badge
                              Builder(
                                builder: (context) {
                                  final studentClaims = financialClaims
                                      .where((c) => c['student_id'] == student.id && c['status'] == 'active')
                                      .toList();
                                  final claimCount = studentClaims.length;

                                  return Container(
                                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.calculate_rounded,
                                          size: 16,
                                          color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            claimCount > 0
                                                ? '$claimCount حصص حضور مسجلة (${basePrice > 0 ? basePrice.toStringAsFixed(0) : "0"} ج/حصة)'
                                                : 'استحقاق مالي مسجل',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white70 : const Color(0xFF334155),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => _showAddSessionClaimDialog(student),
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.add_rounded, size: 13, color: Color(0xFF10B981)),
                                                SizedBox(width: 2),
                                                Text(
                                                  'إضافة حصة +',
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF10B981),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 10),
                              Divider(
                                height: 1,
                                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.08),
                              ),
                              const SizedBox(height: 8),

                              // Bottom Actions Row: 1-Tap Quick Pay Session + 1-Tap Full Settle + Smart WhatsApp + Concession
                              Row(
                                children: [
                                  // Quick Pay 1 Session Button ⚡
                                  Expanded(
                                    flex: 3,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                      onPressed: () => _quickPaySession(student),
                                      child: FittedBox(
                                        child: Text(
                                          '⚡ تسوية حصة (${singlePayAmt.toStringAsFixed(0)} ج)',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),

                                  // Quick Settle Full Amount ⚡
                                  Expanded(
                                    flex: 3,
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF0284C7),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                      onPressed: () => _quickSettleAllDebt(student),
                                      child: const FittedBox(
                                        child: Text(
                                          '⚡ تسديد كامل',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),

                                  // WhatsApp Reminder Button
                                  IconButton(
                                    tooltip: 'تذكير واتساب ذكي',
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.12),
                                      padding: const EdgeInsets.all(7),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.chat_rounded, size: 16, color: Color(0xFF25D366)),
                                    onPressed: () => _sendSmartWhatsAppReminder(student),
                                  ),
                                  const SizedBox(width: 4),

                                  // Charitable Concession Button ("تيسير لله 🤲")
                                  IconButton(
                                    tooltip: 'تيسير وإعفاء لوجه الله 🤲',
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.12),
                                      padding: const EdgeInsets.all(7),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.volunteer_activism_rounded, size: 16, color: Color(0xFF10B981)),
                                    onPressed: () => _showConcessionDialog(preselectedStudent: student),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildExpensesTab(bool isDark) {
    if (expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'لا توجد مصروفات مسجلة حتى الآن',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('تسجيل أول مصروف'),
              onPressed: () => _showAddExpenseDialog(),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      key: const PageStorageKey<String>('finances_expenses_list_view'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 80),
      itemCount: expenses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final exp = expenses[i];
        final amount = (exp['amount'] as num).toDouble();

        return Card(
          key: ValueKey('expense_card_${exp['id']}'),
          elevation: 0,
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.red.withValues(alpha: 0.15),
              child: const Icon(Icons.trending_down, color: Colors.red),
            ),
            title: Text(
              exp['title'] as String,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${exp['category']} • ${exp['date']} ${(exp['notes'] != null && (exp['notes'] as String).isNotEmpty) ? "\n${exp['notes'] as String}" : ""}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${amount.toStringAsFixed(0)} ج.م',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.grey,
                    size: 20,
                  ),
                  onPressed: () async {
                    await widget.database.deleteExpense(exp['id'] as String);
                    _loadFinances();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
